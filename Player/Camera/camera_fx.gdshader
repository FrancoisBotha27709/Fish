shader_type canvas_item;

// ============================ VHS ============================
group_uniforms VHS;
uniform bool vhs_enabled = true;
uniform float vhs_scanline_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float vhs_scanline_count : hint_range(50.0, 1000.0) = 240.0;
uniform float vhs_noise_intensity : hint_range(0.0, 1.0) = 0.05;
uniform float vhs_tracking_distortion : hint_range(0.0, 0.05) = 0.0015;
uniform float vhs_wobble_speed : hint_range(0.0, 10.0) = 1.0;
uniform float vhs_color_bleed : hint_range(0.0, 0.02) = 0.003;
uniform float vhs_vignette : hint_range(0.0, 1.0) = 0.2;

// ================== Chromatic Aberration ======================
group_uniforms ChromaticAberration;
uniform bool ca_enabled = true;
uniform int ca_samples : hint_range(2, 12) = 3;      // "X amount of colours"
uniform float ca_strength : hint_range(0.0, 0.05) = 0.004;
uniform bool ca_radial = true;                       // radial (screen-edge) vs fixed direction

// ======================= Lens Scuffs ==========================
group_uniforms LensScuffs;
uniform bool scuff_enabled = true;
uniform sampler2D scuff_texture : hint_default_black, filter_linear, repeat_enable;
uniform float scuff_opacity : hint_range(0.0, 1.0) = 0.35;
uniform float scuff_scale = 1.0;
uniform vec2 scuff_offset = vec2(0.0, 0.0);
uniform float scuff_smudge : hint_range(0.0, 1.0) = 0.0; // extra blur under scuff mask

// ====================== Color Correction ======================
group_uniforms ColorCorrection;
uniform float cc_exposure : hint_range(-2.0, 2.0) = 0.0;
uniform float cc_contrast : hint_range(0.0, 2.0) = 1.0;
uniform float cc_saturation : hint_range(0.0, 2.0) = 1.0;
uniform float cc_gamma : hint_range(0.1, 3.0) = 1.0;
uniform vec3 cc_color_filter : source_color = vec3(1.0);
uniform vec3 cc_shadows_tint : source_color = vec3(1.0);
uniform vec3 cc_highlights_tint : source_color = vec3(1.0);

// ======================== Lens Distortion ========================
group_uniforms LensDistortion;
uniform bool lens_distortion_enabled = false;
uniform float lens_barrel_amount : hint_range(-1.0, 1.0) = 0.0; // + barrel, - pincushion

// ======================== Cinematic ============================
group_uniforms Cinematic;
uniform bool grain_enabled = true;
uniform float grain_intensity : hint_range(0.0, 1.0) = 0.05;
uniform bool vignette_enabled = true;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.3;
uniform float vignette_softness : hint_range(0.1, 2.0) = 0.8;
uniform bool letterbox_enabled = false;
uniform float letterbox_size : hint_range(0.0, 0.3) = 0.1;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

vec3 sample_screen(vec2 uv) {
	return texture(screen_tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;

	// --- Lens barrel/pincushion distortion ---
	if (lens_distortion_enabled) {
		vec2 c = uv - vec2(0.5);
		float r2 = dot(c, c);
		uv = uv + c * r2 * lens_barrel_amount;
	}

	// --- VHS tracking wobble (horizontal line jitter) ---
	if (vhs_enabled) {
		float wobble = sin(uv.y * 30.0 + t * vhs_wobble_speed) * vhs_tracking_distortion;
		wobble += (hash(vec2(floor(uv.y * 90.0), floor(t * 8.0))) - 0.5) * vhs_tracking_distortion;
		uv.x += wobble;
	}

	// --- Chromatic aberration, sampled across N colour bands ---
	vec3 color = vec3(0.0);
	if (ca_enabled && ca_samples > 1) {
		vec2 dir = ca_radial ? (uv - vec2(0.5)) : vec2(1.0, 0.0);
		float dist = ca_radial ? length(dir) : 1.0;
		vec2 ndir = ca_radial ? normalize(dir + 1e-6) : dir;
		vec3 sum = vec3(0.0);
		for (int i = 0; i < ca_samples; i++) {
			float f = float(i) / float(ca_samples - 1) - 0.5; // -0.5..0.5
			vec2 offset = ndir * f * ca_strength * (ca_radial ? dist : 1.0);
			// hue for this band across the spectrum (red->violet)
			float hue = float(i) / float(max(ca_samples - 1, 1));
			vec3 band = mix(vec3(1.0, 0.15, 0.1), vec3(0.4, 0.2, 1.0), hue);
			if (ca_samples <= 3) {
				// classic RGB split when only 3 samples requested
				band = (i == 0) ? vec3(1.0, 0.0, 0.0) : (i == 1 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
			}
			sum += sample_screen(uv + offset) * band;
		}
		color = sum / (float(ca_samples) * 0.5);
	} else {
		color = sample_screen(uv);
	}

	// --- VHS color bleed + scanlines + noise + vignette ---
	if (vhs_enabled) {
		vec3 bleed_r = sample_screen(uv + vec2(vhs_color_bleed, 0.0));
		vec3 bleed_b = sample_screen(uv - vec2(vhs_color_bleed, 0.0));
		color = vec3(bleed_r.r, color.g, bleed_b.b);

		float scan = sin(uv.y * vhs_scanline_count * PI) * 0.5 + 0.5;
		color *= 1.0 - vhs_scanline_intensity * scan;

		float n = hash(uv * vec2(1024.0, 1024.0) + fract(t) * 100.0);
		color += (n - 0.5) * vhs_noise_intensity;

		float vig = distance(uv, vec2(0.5));
		color *= 1.0 - vig * vhs_vignette;
	}

	// --- Color correction (exposure / contrast / saturation / gamma / tint) ---
	color *= pow(2.0, cc_exposure);
	color = (color - 0.5) * cc_contrast + 0.5;
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, cc_saturation);
	color = mix(color * cc_shadows_tint, color * cc_highlights_tint, clamp(luma, 0.0, 1.0));
	color *= cc_color_filter;
	color = pow(clamp(color, vec3(0.0), vec3(10.0)), vec3(1.0 / max(cc_gamma, 0.001)));

	// --- Lens scuffs / dirt ---
	if (scuff_enabled) {
		vec2 suv = uv * scuff_scale + scuff_offset;
		vec4 scuff = texture(scuff_texture, suv);
		if (scuff_smudge > 0.0) {
			vec3 blur = (sample_screen(uv + vec2(0.002, 0.0)) + sample_screen(uv - vec2(0.002, 0.0))
				+ sample_screen(uv + vec2(0.0, 0.002)) + sample_screen(uv - vec2(0.0, 0.002))) * 0.25;
			color = mix(color, blur, scuff.a * scuff_smudge);
		}
		color = mix(color, color + scuff.rgb, scuff.a * scuff_opacity);
	}

	// --- Cinematic grain / vignette / letterbox ---
	if (grain_enabled) {
		float g = hash(uv * vec2(800.0, 600.0) + t * 60.0) - 0.5;
		color += g * grain_intensity;
	}
	if (vignette_enabled) {
		float d = distance(uv, vec2(0.5)) * 1.414;
		float v = smoothstep(1.0, 1.0 - vignette_softness, 1.0 - d);
		color *= mix(1.0, v, vignette_strength);
	}
	if (letterbox_enabled) {
		if (uv.y < letterbox_size || uv.y > 1.0 - letterbox_size) {
			color = vec3(0.0);
		}
	}

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
