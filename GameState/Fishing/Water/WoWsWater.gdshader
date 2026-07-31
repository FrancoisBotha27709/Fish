shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

//==============================================================================
// STYLIZED "WORLD OF WARSHIPS"-LIKE OCEAN SHADER — Godot 4.6
// Small-map / calm-water version, with biomes
//
// Apply to a ShaderMaterial on a HEAVILY SUBDIVIDED PlaneMesh (waves are
// vertex displacement, so a low-poly plane will snap/facet).
//
// The water sits mostly flat with tiny non-repeating ripples. Two things
// change that locally:
//   1. Object interaction: `ripple_data` — filled by WaterManager.gd,
//      driven by BuoyancySystem.gd. Expanding decaying rings from contact
//      points.
//   2. Biomes: `biome_data` / `biome_chop` / `biome_ripple` / `biome_look` /
//      `biome_tint` — filled by WaterBiomeSystem.gd, driven by WaterBiome.gd
//      (Area3D markers). Each biome is an approximate circle in XZ with a
//      soft falloff band; inside it, the ambient chop and ripple physics
//      are locally re-scaled (bigger/longer/faster/wilder), and the color/
//      foam/roughness can shift too (e.g. darker, foamier storm water).
//
// If your map/world uses different units than meters, set `meters_per_unit`
// once instead of retuning every frequency slider.
//==============================================================================

// ---------------- COLOR ----------------
group_uniforms Color;
uniform vec4 color_deep : source_color = vec4(0.008, 0.09, 0.16, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.04, 0.32, 0.38, 1.0);
uniform vec4 color_horizon_tint : source_color = vec4(0.55, 0.78, 0.80, 1.0);
uniform vec4 color_foam : source_color = vec4(0.96, 0.99, 1.0, 1.0);

// ---------------- SCALE ----------------
group_uniforms Scale;
uniform float meters_per_unit : hint_range(0.001, 100.0) = 1.0;

// ---------------- AMBIENT CHOP (tiny, non-periodic, keeps water from looking dead) ----------------
group_uniforms AmbientChop;
uniform float chop_height : hint_range(0.0, 0.3) = 0.025;
uniform float chop_scale : hint_range(0.05, 4.0) = 1.0;
uniform float chop_speed : hint_range(0.0, 2.0) = 0.2;

// ---------------- SURFACE RIPPLE DETAIL (fragment-only normal detail, no displacement) ----------------
group_uniforms SurfaceDetail;
uniform bool use_custom_normal_maps = false;
uniform sampler2D normal_map_1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map_2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float detail_uv_scale_1 : hint_range(0.05, 12.0) = 2.5;
uniform float detail_uv_scale_2 : hint_range(0.05, 12.0) = 6.0;
uniform float detail_speed_1 : hint_range(0.0, 2.0) = 0.06;
uniform float detail_speed_2 : hint_range(0.0, 2.0) = 0.1;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.5;

// ---------------- FOAM ----------------
group_uniforms Foam;
uniform bool use_custom_foam_texture = false;
uniform sampler2D foam_texture : filter_linear_mipmap, repeat_enable;
uniform float foam_uv_scale : hint_range(0.05, 12.0) = 2.0;
uniform float foam_speed : hint_range(0.0, 2.0) = 0.12;
uniform float foam_crest_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float foam_crest_softness : hint_range(0.01, 1.0) = 0.3;
uniform float foam_amount : hint_range(0.0, 2.0) = 1.0;
uniform bool enable_shore_foam = true;
uniform float shore_foam_distance : hint_range(0.0, 12.0) = 0.6;

// ---------------- LIGHTING / REFLECTION ----------------
group_uniforms Lighting;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.12;
uniform float fresnel_power : hint_range(0.1, 10.0) = 4.5;
uniform float fresnel_min_reflect : hint_range(0.0, 1.0) = 0.03;
uniform float sparkle_intensity : hint_range(0.0, 6.0) = 1.2;
uniform float sparkle_scale : hint_range(1.0, 400.0) = 220.0;
uniform float sparkle_speed : hint_range(0.0, 3.0) = 0.6;

// ---------------- INTERACTION ----------------
group_uniforms Interaction;
uniform vec4 ripple_data[16]; // xy = world contact point (x,z), z = spawn time (sim_time), w = strength
uniform int ripple_count : hint_range(0, 16) = 0;
uniform float sim_time = 0.0; // driven by script every frame, not the built-in TIME
uniform float ripple_lifetime : hint_range(0.5, 30.0) = 6.0;
uniform float ripple_speed : hint_range(0.1, 20.0) = 2.2;
uniform float ripple_wavelength : hint_range(0.05, 5.0) = 0.7;
uniform float ripple_width : hint_range(0.05, 10.0) = 1.2;
uniform float ripple_amplitude : hint_range(0.0, 3.0) = 0.4;

// ---------------- BIOMES ----------------
group_uniforms Biomes;
// Filled by WaterBiomeSystem.gd from Area3D markers tagged "water_biome"
// (WaterBiome.gd). Each biome is treated as a circle in the water's XZ
// plane with a soft-edged falloff band, not an exact collision shape.
uniform vec4 biome_data[8];   // xy = world center (x,z), z = radius (meters), w = edge blend distance (meters)
uniform int biome_count : hint_range(0, 8) = 0;
uniform vec4 biome_chop[8];   // x = wave height mult, y = wave frequency mult (small = longer waves), z = wave speed mult, w = turbulence (extra "wild" chop layer, 0 = off)
uniform vec4 biome_ripple[8]; // x = ripple speed mult, y = ripple wavelength mult, z = ripple amplitude mult, w = unused
uniform vec4 biome_look[8];   // x = color tint strength (0-1), y = foam amount mult, z = roughness add, w = unused
uniform vec4 biome_tint[8];   // rgb = tint color, a = unused

// ---------------- DEPTH (shore / hull foam) ----------------
group_uniforms Depth;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap, repeat_disable;

varying float wave_height_varying;
varying vec3 world_pos_varying;
varying vec4 biome_look_varying;    // x = tint strength, y = foam mult, z = roughness add
varying vec3 biome_tint_varying;

// ---------------- helpers ----------------
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float total = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        total += value_noise(p) * amp;
        p *= 2.02;
        amp *= 0.5;
    }
    return total;
}

void vertex() {
    // world_vertex_coords is enabled, so VERTEX arrives already in world space.
    vec2 wpos = VERTEX.xz;
    float sc = 1.0 / max(meters_per_unit, 0.001); // frequency correction for non-meter worlds
    vec2 wpos_m = wpos * sc;

    // ---- blend biome multipliers for this vertex ----
    vec4 chop_mult = vec4(1.0, 1.0, 1.0, 0.0);   // height, freq, speed, turbulence
    vec4 ripple_mult = vec4(1.0, 1.0, 1.0, 0.0); // speed, wavelength, amplitude, unused
    vec4 look_mix = vec4(0.0, 1.0, 0.0, 0.0);    // tint strength, foam mult, roughness add
    vec3 tint_mix = vec3(0.0);

    for (int i = 0; i < 8; i++) {
        if (i >= biome_count) {
            break;
        }
        vec2 center = biome_data[i].xy;
        float radius = biome_data[i].z;
        float blend = max(biome_data[i].w, 0.001);
        float dist = length(wpos - center);
        float w = 1.0 - smoothstep(radius, radius + blend, dist);
        if (w <= 0.001) {
            continue;
        }
        chop_mult = mix(chop_mult, biome_chop[i], w);
        ripple_mult = mix(ripple_mult, biome_ripple[i], w);
        look_mix = mix(look_mix, biome_look[i], w);
        tint_mix = mix(tint_mix, biome_tint[i].rgb, w);
    }
    biome_look_varying = look_mix;
    biome_tint_varying = tint_mix;

    vec3 total_disp = vec3(0.0);
    vec2 total_deriv = vec2(0.0);

    // ---- ambient chop: non-periodic, low amplitude by default, re-scaled per biome ----
    float t_chop = TIME * chop_speed * chop_mult.z;
    float e = 0.5; // sampling epsilon, meters
    vec2 chop_freq = vec2(chop_scale * 0.06 * chop_mult.y);
    vec2 uv_c = wpos_m * chop_freq + vec2(t_chop, -t_chop * 0.7);
    float hC = fbm(uv_c) - 0.5;
    float hX = fbm(uv_c + vec2(e * chop_freq.x, 0.0)) - 0.5;
    float hZ = fbm(uv_c + vec2(0.0, e * chop_freq.y)) - 0.5;
    float local_chop_height = chop_height * chop_mult.x;
    total_disp.y += hC * local_chop_height;
    total_deriv += vec2(hC - hX, hC - hZ) * (local_chop_height / e);

    // ---- extra turbulence layer ("wild" seas, e.g. a cold/stormy biome) ----
    if (chop_mult.w > 0.01) {
        vec2 uv_t = wpos_m * chop_freq * 2.6 + vec2(t_chop * 1.7, t_chop * 1.3);
        float hT = fbm(uv_t) - 0.5;
        float hTX = fbm(uv_t + vec2(e * chop_freq.x * 2.6, 0.0)) - 0.5;
        float hTZ = fbm(uv_t + vec2(0.0, e * chop_freq.y * 2.6)) - 0.5;
        float turb_height = local_chop_height * chop_mult.w;
        total_disp.y += hT * turb_height;
        total_deriv += vec2(hT - hTX, hT - hTZ) * (turb_height / e);
    }

    // ---- object-driven ripples: expanding decaying rings, re-scaled per biome ----
    float local_ripple_speed = ripple_speed * ripple_mult.x;
    float local_ripple_wavelength = ripple_wavelength * ripple_mult.y;
    float k = TAU / max(local_ripple_wavelength, 0.001);

    for (int i = 0; i < 16; i++) {
        if (i >= ripple_count) {
            break;
        }
        vec2 rp = ripple_data[i].xy;
        float spawn = ripple_data[i].z;
        float strength = ripple_data[i].w;
        float age = sim_time - spawn;
        if (age < 0.0 || age > ripple_lifetime || strength <= 0.0001) {
            continue;
        }

        vec2 to_point = (wpos - rp) * sc;
        float dist = length(to_point);
        float wavefront = age * local_ripple_speed;
        float band = exp(-pow((dist - wavefront) / max(ripple_width, 0.001), 2.0));
        if (band < 0.001) {
            continue;
        }

        float decay = strength * (1.0 - age / ripple_lifetime);
        float phase = (dist - wavefront) * k;
        float amp = ripple_amplitude * ripple_mult.z * decay * band;

        total_disp.y += sin(phase) * amp;

        vec2 dir_to = dist > 0.0001 ? normalize(to_point) : vec2(0.0);
        float dh = cos(phase) * k * amp;
        total_deriv += dir_to * dh;
    }

    VERTEX += total_disp;
    world_pos_varying = VERTEX;
    wave_height_varying = total_disp.y;

    NORMAL = normalize(vec3(-total_deriv.x, 1.0, -total_deriv.y));
}

void fragment() {
    vec3 wpos = world_pos_varying;
    float t = TIME;
    float sc = 1.0 / max(meters_per_unit, 0.001);
    vec4 look = biome_look_varying; // x = tint strength, y = foam mult, z = roughness add

    // ---- fine ripple detail normal (tangent-space, fed via NORMAL_MAP) ----
    vec3 detail_n;
    if (use_custom_normal_maps) {
        vec2 uv1 = wpos.xz * sc * detail_uv_scale_1 * 0.1 + vec2(t * detail_speed_1, 0.0);
        vec2 uv2 = wpos.xz * sc * detail_uv_scale_2 * 0.1 - vec2(0.0, t * detail_speed_2);
        vec3 n1 = texture(normal_map_1, uv1).rgb * 2.0 - 1.0;
        vec3 n2 = texture(normal_map_2, uv2).rgb * 2.0 - 1.0;
        detail_n = normalize(vec3(n1.xy + n2.xy, 1.0));
    } else {
        vec2 uv1 = wpos.xz * sc * detail_uv_scale_1 * 0.15 + vec2(t * detail_speed_1, 0.0);
        vec2 uv2 = wpos.xz * sc * detail_uv_scale_2 * 0.15 - vec2(0.0, t * detail_speed_2);
        float e = 0.08;
        float hC = fbm(uv1) + fbm(uv2 * 1.3);
        float hX = fbm(uv1 + vec2(e, 0.0)) + fbm(uv2 * 1.3 + vec2(e, 0.0));
        float hY = fbm(uv1 + vec2(0.0, e)) + fbm(uv2 * 1.3 + vec2(0.0, e));
        detail_n = normalize(vec3((hC - hX) / e, (hC - hY) / e, 1.0));
    }
    NORMAL_MAP = detail_n * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = detail_strength;

    // ---- foam driven by local displacement (ripple crests + shore), not a global swell ----
    float crest_ref = max(ripple_amplitude, 0.001);
    float norm_height = clamp(wave_height_varying / crest_ref, -1.0, 1.0);
    float crest = smoothstep(foam_crest_threshold - foam_crest_softness, foam_crest_threshold + foam_crest_softness, norm_height);

    float foam_pattern;
    if (use_custom_foam_texture) {
        vec2 fuv = wpos.xz * sc * foam_uv_scale * 0.1 + vec2(t * foam_speed, 0.0);
        foam_pattern = texture(foam_texture, fuv).r;
    } else {
        vec2 fuv = wpos.xz * sc * foam_uv_scale * 0.2 + vec2(t * foam_speed, 0.0);
        foam_pattern = fbm(fuv * 3.0);
    }
    float foam_mask = clamp(crest * foam_pattern * foam_amount * look.y, 0.0, 1.0);

    // ---- shore / hull foam using the depth buffer ----
    float shore_mask = 0.0;
    if (enable_shore_foam) {
        float depth_raw = texture(depth_texture, SCREEN_UV).r;
        vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
        vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
        view_pos.xyz /= view_pos.w;
        float scene_depth = -view_pos.z;
        float water_depth = -VERTEX.z; // VERTEX is view-space here (fragment stage)
        float diff = max(scene_depth - water_depth, 0.0);
        shore_mask = 1.0 - smoothstep(0.0, max(shore_foam_distance, 0.001), diff);
        shore_mask *= mix(0.6, 1.0, foam_pattern) * look.y;
    }

    float total_foam = clamp(foam_mask + shore_mask, 0.0, 1.0);

    // ---- base water color, tinted per biome ----
    float fresnel = fresnel_min_reflect + (1.0 - fresnel_min_reflect) * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
    vec3 base_color = mix(color_deep.rgb, color_shallow.rgb, clamp(shore_mask * 1.3, 0.0, 1.0));
    vec3 water_color = mix(base_color, color_horizon_tint.rgb, fresnel * 0.5);
    water_color = mix(water_color, biome_tint_varying, clamp(look.x, 0.0, 1.0));
    vec3 final_color = mix(water_color, color_foam.rgb, total_foam);

    ALBEDO = final_color;
    ROUGHNESS = clamp(mix(roughness_value, 0.85, total_foam) + look.z, 0.0, 1.0);
    METALLIC = mix(0.05, 0.85, fresnel) * (1.0 - total_foam);
    SPECULAR = 0.5;

    // ---- sun-glitter sparkle ----
    vec2 sp_uv = wpos.xz * sc * sparkle_scale * 0.05 + vec2(t * sparkle_speed * 0.3, 0.0);
    float sparkle = pow(hash12(floor(sp_uv)), 28.0);
    float up_facing = clamp(dot(normalize(NORMAL), vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
    EMISSION = vec3(sparkle) * sparkle_intensity * (1.0 - total_foam) * up_facing;
}
