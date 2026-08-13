shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

// =====================================================================
// IMPORTANT — this shader fakes real cube geometry by snapping the mesh's
// own vertex heights to a voxel grid. For that to look like small cubes
// (and not a few giant stair-steps) your water mesh needs vertex spacing
// at or finer than `voxel_size`. For a Godot PlaneMesh sized W x D meters:
//     subdivide_width  = int(W / voxel_size)
//     subdivide_depth  = int(D / voxel_size)
// At voxel_size = 0.1 that's 10 vertices per meter in each direction —
// fine for a small pond, expensive for a big open sea (a 100x100m plane
// would be ~1,000,000 verts). If your water is large, raise voxel_size
// (e.g. 0.25–0.5) or only apply this fine a mesh near the camera.
// =====================================================================

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
uniform float chop_height : hint_range(0.0, 0.3) = 0.06;
uniform float chop_scale : hint_range(0.05, 4.0) = 1.0;
uniform float chop_speed : hint_range(0.0, 2.0) = 0.2;

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

// ---------------- LIGHTING ----------------
group_uniforms Lighting;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.4;
uniform float sparkle_intensity : hint_range(0.0, 6.0) = 0.5;
uniform float sparkle_scale : hint_range(1.0, 400.0) = 220.0;
uniform float sparkle_speed : hint_range(0.0, 3.0) = 0.6;
uniform float sparkle_threshold : hint_range(0.8, 0.999) = 0.99; // higher = fewer, sparser glints
uniform float sparkle_flicker_rate : hint_range(0.0, 10.0) = 2.0; // how often glint positions reshuffle per second; 0 = static (old behavior)

// ---------------- VOXELS ----------------
// This is the core of the look. voxel_size is both the horizontal cell
// size and the vertical step height, so each "block" of water is a cube.
group_uniforms Voxels;
uniform float voxel_size : hint_range(0.02, 1.0) = 0.1;
uniform bool flat_voxel_shading = true; // snap color/foam/sparkle patterns to the voxel grid instead of a smooth gradient
uniform int color_bands : hint_range(2, 6) = 3;         // extra flat steps for depth/fresnel tint
uniform float side_face_darken : hint_range(0.0, 1.0) = 0.35; // how much darker a cube's "riser" faces are than its top
uniform float edge_highlight : hint_range(0.0, 1.0) = 0.15;   // thin bright rim along the top edge of each step
uniform int light_bands : hint_range(1, 4) = 2;          // toon diffuse steps on the top faces
uniform float specular_toon_size : hint_range(0.01, 1.0) = 0.12;
uniform bool posterize_sparkle = true;

// ---------------- AUTO WAVES ----------------
// Traveling swells that spawn at random points and expand outward, raising
// the water as the crest passes through — same underlying math as the
// object-driven ripples above, just auto-spawned instead of triggered.
// Different regions spawn on independent random timers so waves show up
// "here and there" rather than everywhere moving in lockstep.
group_uniforms AutoWaves;
uniform bool auto_waves_enabled = true;
uniform float auto_wave_region_size : hint_range(1.0, 30.0) = 6.0; // spacing between potential wave origins
uniform float auto_wave_period : hint_range(1.0, 20.0) = 4.0;      // avg seconds between a region's spawn attempts
uniform float auto_wave_chance : hint_range(0.0, 1.0) = 0.5;       // odds a given attempt actually spawns a wave
uniform float auto_wave_amplitude_steps : hint_range(0.5, 6.0) = 2.0; // crest height, in voxel_size units
uniform float auto_wave_speed : hint_range(0.1, 10.0) = 1.2;       // how fast the crest travels outward, meters/sec
uniform float auto_wave_width : hint_range(0.2, 10.0) = 2.5;       // thickness of the traveling crest, meters
uniform float auto_wave_lifetime : hint_range(0.5, 20.0) = 5.0;    // seconds the wave travels before fully fading
uniform float auto_wave_line_ratio : hint_range(0.0, 1.0) = 0.7;   // fraction of spawns that are elongated line-swells rather than circular point bursts
uniform float auto_wave_length : hint_range(1.0, 30.0) = 6.0;      // base length of a line-swell crest segment

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
uniform vec4 biome_data[8];   // xy = world center (x,z), z = radius (meters), w = edge blend distance (meters)
uniform int biome_count : hint_range(0, 8) = 0;
uniform vec4 biome_chop[8];   // x = wave height mult, y = wave frequency mult, z = wave speed mult, w = turbulence
uniform vec4 biome_ripple[8]; // x = ripple speed mult, y = ripple wavelength mult, z = ripple amplitude mult, w = unused
uniform vec4 biome_look[8];   // x = color tint strength (0-1), y = foam amount mult, z = roughness add, w = unused
uniform vec4 biome_tint[8];   // rgb = tint color, a = unused

// ---------------- DEPTH (shore / hull foam) ----------------
group_uniforms Depth;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap, repeat_disable;

varying float wave_height_varying;
varying vec3 world_pos_varying;
varying vec2 slope_dir_varying;     // pre-quantization uphill direction, used to pick which flat cardinal side a cube's riser faces
varying vec4 biome_look_varying;
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

float posterize(float x, int bands) {
    float b = max(float(bands), 1.0);
    return floor(clamp(x, 0.0, 1.0) * b) / max(b - 1.0, 1.0);
}

vec2 snap_to_voxel(vec2 p, float size) {
    return (floor(p / size) + 0.5) * size;
}

// Height + analytic slope of the auto-wave system at a meters-space XZ
// position, returned as vec3(height, dHeight/dx, dHeight/dz). Computing the
// slope directly (instead of sampling the field 3x for finite differences)
// is the main cost saving — this function now runs once per vertex, not
// three times. Each spawn is either an elongated "line" swell (a finite
// crest segment rolling in a random direction, like real ocean swell) or a
// circular "point burst" (expanding ring), chosen randomly per spawn via
// auto_wave_line_ratio for visual variety. Only checks the immediate 3x3
// neighborhood of regions — auto_wave_speed/lifetime/region_size defaults
// are chosen so a wave can't travel past that without checking further.
vec3 auto_wave_sample(vec2 wpos_m_sample) {
    if (!auto_waves_enabled) {
        return vec3(0.0);
    }
    float region = max(auto_wave_region_size, 0.001);
    vec2 base_cell = floor(wpos_m_sample / region);
    float height = 0.0;
    vec2 grad = vec2(0.0);

    for (int dx = -1; dx <= 1; dx++) {
        for (int dz = -1; dz <= 1; dz++) {
            vec2 cell = base_cell + vec2(float(dx), float(dz));
            float cell_seed = hash12(cell);
            float period = auto_wave_period * mix(0.7, 1.3, cell_seed);
            float t_offset = cell_seed * 191.3;
            float cycle_index = floor((TIME + t_offset) / period);

            float spawn_roll = hash12(cell + cycle_index * 13.7 + 44.0);
            if (spawn_roll >= auto_wave_chance) {
                continue;
            }

            float spawn_frac = hash12(cell + cycle_index * 7.91);
            float cycle_start = cycle_index * period - t_offset;
            float spawn_time = cycle_start + spawn_frac * period * 0.5;
            float age = TIME - spawn_time;
            if (age < 0.0 || age > auto_wave_lifetime) {
                continue;
            }

            vec2 origin_frac = vec2(hash12(cell + 3.1), hash12(cell + 8.7));
            vec2 origin = (cell + origin_frac) * region;
            vec2 rel = wpos_m_sample - origin;

            float speed = auto_wave_speed * mix(0.7, 1.3, hash12(cell + 2.2));
            float width = max(auto_wave_width * mix(0.6, 1.4, hash12(cell + 9.9)), 0.05);
            float amp = auto_wave_amplitude_steps * voxel_size * mix(0.6, 1.0, hash12(cell + 5.5));
            float decay = 1.0 - age / auto_wave_lifetime;
            float wavefront = age * speed;

            if (hash12(cell + 61.3) < auto_wave_line_ratio) {
                // ---- line swell: a finite crest segment rolling in a random direction ----
                float angle = hash12(cell + 44.4) * TAU;
                vec2 dir = vec2(cos(angle), sin(angle));
                vec2 perp_dir = vec2(-dir.y, dir.x);
                float length_ = max(auto_wave_length * mix(0.5, 1.5, hash12(cell + 17.6)), 0.5);

                float along = dot(rel, dir);
                float perp = dot(rel, perp_dir);
                float local = (along - wavefront) / width;
                float half_len = length_ * 0.5;
                float end_falloff = 1.0 - smoothstep(half_len * 0.6, half_len, abs(perp));

                if (abs(local) < 1.0 && end_falloff > 0.001) {
                    float crest_shape = 0.5 * (1.0 + cos(local * PI));
                    float dcrest = -(PI * 0.5) * sin(local * PI); // d(crest_shape)/d(local)
                    height += amp * crest_shape * end_falloff * decay;
                    grad += amp * dcrest * (1.0 / width) * dir * end_falloff * decay;
                }
            } else {
                // ---- point burst: expanding ring from a single origin ----
                float dist = length(rel);
                float local = (dist - wavefront) / width;
                if (abs(local) < 1.0 && dist > 0.0001) {
                    float crest_shape = 0.5 * (1.0 + cos(local * PI));
                    float dcrest = -(PI * 0.5) * sin(local * PI);
                    height += amp * crest_shape * decay;
                    grad += amp * dcrest * (1.0 / width) * (rel / dist) * decay;
                }
            }
        }
    }
    return vec3(height, grad.x, grad.y);
}

void vertex() {
    // world_vertex_coords is enabled, so VERTEX arrives already in world space.
    vec2 wpos = VERTEX.xz;
    float sc = 1.0 / max(meters_per_unit, 0.001);
    vec2 wpos_m = wpos * sc;

    vec4 chop_mult = vec4(1.0, 1.0, 1.0, 0.0);
    vec4 ripple_mult = vec4(1.0, 1.0, 1.0, 0.0);
    vec4 look_mix = vec4(0.0, 1.0, 0.0, 0.0);
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

    // ---- ambient chop ----
    float t_chop = TIME * chop_speed * chop_mult.z;
    float e = 0.5;
    vec2 chop_freq = vec2(chop_scale * 0.06 * chop_mult.y);
    vec2 uv_c = wpos_m * chop_freq + vec2(t_chop, -t_chop * 0.7);
    float hC = fbm(uv_c) - 0.5;
    float hX = fbm(uv_c + vec2(e * chop_freq.x, 0.0)) - 0.5;
    float hZ = fbm(uv_c + vec2(0.0, e * chop_freq.y)) - 0.5;
    float local_chop_height = chop_height * chop_mult.x;
    total_disp.y += hC * local_chop_height;
    total_deriv += vec2(hC - hX, hC - hZ) * (local_chop_height / e);

    // ---- turbulence layer ----
    if (chop_mult.w > 0.01) {
        vec2 uv_t = wpos_m * chop_freq * 2.6 + vec2(t_chop * 1.7, t_chop * 1.3);
        float hT = fbm(uv_t) - 0.5;
        float hTX = fbm(uv_t + vec2(e * chop_freq.x * 2.6, 0.0)) - 0.5;
        float hTZ = fbm(uv_t + vec2(0.0, e * chop_freq.y * 2.6)) - 0.5;
        float turb_height = local_chop_height * chop_mult.w;
        total_disp.y += hT * turb_height;
        total_deriv += vec2(hT - hTX, hT - hTZ) * (turb_height / e);
    }

    // ---- object-driven ripples ----
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

    // ---- auto waves: random localized swells so the water isn't dead-flat
    // when nothing is touching it. Single analytic sample (height + slope
    // together) instead of three finite-difference samples — cheaper. ----
    if (auto_waves_enabled) {
        vec3 aw = auto_wave_sample(wpos_m);
        total_disp.y += aw.x;
        total_deriv += -aw.yz; // match the (h(x)-h(x+e))/e sign convention used above
    }

    // Store the pre-quantization uphill direction — used in fragment() to
    // decide which flat cardinal direction a cube's "riser" face points.
    slope_dir_varying = total_deriv;

    // ---- snap to the voxel grid: real geometric cube steps ----
    // Horizontal snap keeps each cube's footprint crisp; vertical snap is
    // what actually produces the stacked-block silhouette. Requires the
    // mesh to be subdivided at least this fine (see note at top of file).
    vec2 snapped_xz = snap_to_voxel(wpos, voxel_size);
    VERTEX.x = snapped_xz.x;
    VERTEX.z = snapped_xz.y;
    total_disp.y = round(total_disp.y / voxel_size) * voxel_size;

    VERTEX += vec3(0.0, total_disp.y, 0.0);
    world_pos_varying = VERTEX;
    wave_height_varying = total_disp.y;

    // Kept smooth here only as a cheap fallback normal; fragment() replaces
    // it with a properly flat, quantized cube-face normal.
    NORMAL = normalize(vec3(-total_deriv.x, 1.0, -total_deriv.y));
}

void fragment() {
    vec3 wpos = world_pos_varying;
    float t = TIME;
    float sc = 1.0 / max(meters_per_unit, 0.001);
    vec4 look = biome_look_varying;

    // No fine normal-map ripple detail here — it would smear the flat cube
    // faces we're about to build.
    NORMAL_MAP_DEPTH = 0.0;

    // ---- classify this fragment as a cube TOP or a cube SIDE (riser) ----
    // Adjacent step levels are joined by a short, steep ramp in the
    // underlying triangle mesh; we detect that ramp via how fast the
    // (already-stepped) height changes across the screen, and treat it as
    // a flat vertical side face instead of a smooth slope.
    float slope = length(vec2(dFdx(wave_height_varying), dFdy(wave_height_varying)));
    float is_side = smoothstep(voxel_size * 0.12, voxel_size * 0.55, slope);

    vec2 sd = slope_dir_varying;
    vec2 sd_abs = abs(sd);
    vec2 side_dir = sd_abs.x > sd_abs.y ? vec2(sign(sd.x), 0.0) : vec2(0.0, sign(sd.y));
    vec3 flat_top_normal = vec3(0.0, 1.0, 0.0);
    vec3 flat_side_normal = normalize(vec3(-side_dir.x, 0.08, -side_dir.y));
    NORMAL = normalize(mix(flat_top_normal, flat_side_normal, is_side));

    // Thin bright rim right at the edge of a step, like light catching the
    // top lip of a block.
    float rim = smoothstep(voxel_size * 0.03, voxel_size * 0.15, slope) * (1.0 - is_side);

    // ---- pattern coordinates: snapped to the voxel grid so each cube face
    // is ONE flat value, not a smooth gradient across it ----
    vec2 pattern_pos = flat_voxel_shading ? snap_to_voxel(wpos.xz, voxel_size) : wpos.xz;

    // ---- foam ----
    float crest_ref = max(ripple_amplitude, 0.001);
    float norm_height = clamp(wave_height_varying / crest_ref, -1.0, 1.0);
    float crest = smoothstep(foam_crest_threshold - foam_crest_softness, foam_crest_threshold + foam_crest_softness, norm_height);

    float foam_pattern;
    if (use_custom_foam_texture) {
        vec2 fuv = pattern_pos * sc * foam_uv_scale * 0.1 + vec2(t * foam_speed, 0.0);
        foam_pattern = texture(foam_texture, fuv).r;
    } else {
        vec2 fuv = pattern_pos * sc * foam_uv_scale * 0.2 + vec2(t * foam_speed, 0.0);
        foam_pattern = fbm(fuv * 3.0);
    }
    foam_pattern = flat_voxel_shading ? step(0.5, foam_pattern) : foam_pattern;
    float foam_mask = clamp(crest * foam_pattern * foam_amount * look.y, 0.0, 1.0);

    float shore_mask = 0.0;
    if (enable_shore_foam) {
        float depth_raw = texture(depth_texture, SCREEN_UV).r;
        vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
        vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
        view_pos.xyz /= view_pos.w;
        float scene_depth = -view_pos.z;
        float water_depth = -VERTEX.z;
        float diff = max(scene_depth - water_depth, 0.0);
        shore_mask = 1.0 - smoothstep(0.0, max(shore_foam_distance, 0.001), diff);
        shore_mask *= mix(0.6, 1.0, foam_pattern) * look.y;
    }

    float total_foam = step(0.35, clamp(foam_mask + shore_mask, 0.0, 1.0));

    // ---- base color: flat depth/tint bands, no smooth fresnel gradient ----
    float shore_blend = posterize(clamp(shore_mask * 1.3, 0.0, 1.0), color_bands);
    vec3 top_color = mix(color_deep.rgb, color_shallow.rgb, shore_blend);
    top_color = mix(top_color, biome_tint_varying, clamp(look.x, 0.0, 1.0));

    // Side (riser) faces get a flat darker tone, like the shaded side of a
    // Minecraft-style block, instead of any lighting gradient.
    vec3 side_color = top_color * (1.0 - side_face_darken);
    vec3 water_color = mix(top_color, side_color, is_side);
    water_color += vec3(edge_highlight) * rim;

    vec3 final_color = mix(water_color, color_foam.rgb, total_foam);

    ALBEDO = final_color;
    ROUGHNESS = clamp(roughness_value + look.z, 0.0, 1.0);
    METALLIC = 0.0;
    SPECULAR = 0.0;

    vec2 sp_uv = pattern_pos * sc * sparkle_scale * 0.05 + vec2(t * sparkle_speed * 0.3, 0.0);
    vec2 sp_cell = floor(sp_uv);
    if (sparkle_flicker_rate > 0.001) {
        sp_cell += floor(t * sparkle_flicker_rate); // reshuffle which cells glint every so often
    }
    float sparkle_hash = hash12(sp_cell);
    float sparkle = posterize_sparkle ? step(sparkle_threshold, sparkle_hash) : pow(sparkle_hash, 28.0);
    EMISSION = vec3(sparkle) * sparkle_intensity * (1.0 - total_foam) * (1.0 - is_side);
}

void light() {
    // Flat toon diffuse: few bands, so top faces stay mostly one solid
    // tone with at most one clean shadow step — no smooth realistic falloff.
    float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
    float bands = max(float(light_bands), 1.0);
    float banded_ndotl = ceil(NdotL * bands) / bands;
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * banded_ndotl * ATTENUATION;

    vec3 half_vec = normalize(VIEW + LIGHT);
    float NdotH = clamp(dot(NORMAL, half_vec), 0.0, 1.0);
    float spec_cutoff = 1.0 - clamp(specular_toon_size, 0.001, 1.0) * 0.25;
    float spec = step(spec_cutoff, NdotH);
    SPECULAR_LIGHT += spec * LIGHT_COLOR.rgb * ATTENUATION;
}
