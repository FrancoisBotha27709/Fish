#include "res://GameState/Fishing/Clouds/smog_noise.gdshaderinc"

const int HATCH_STYLE_RELIEF     = 0;   // the original smooth look - no hatching, just returns the lit value
const int HATCH_STYLE_CROSSHATCH = 1;   // one line set in midtones, a crossing second set in the darkest areas
const int HATCH_STYLE_STREAKS    = 2;   // a single hatch direction, thickening/doubling up as it darkens
const int HATCH_STYLE_STIPPLE    = 3;   // dot density increases with shadow, like engraving stipple

// Self-shadow: samples the SAME noise field twice, once offset toward the
// light, and diffs them. Cheap fake shadowing with no real occlusion - just
// reads as light catching the noise's own bumps.
float hatch_relief_from_samples(float n, float n_lit, float sharpness) {
	return clamp(0.5 + (n - n_lit) * sharpness, 0.0, 1.0);
}

// Convenience wrapper for the common case (smooth fbm haze, like the smog).
// Cloud shaders using smog_billow() for puffier shapes should sample it
// themselves and call hatch_relief_from_samples() directly instead.
float hatch_relief(vec2 uv, vec2 light_xz, float offset, float sharpness) {
	float n = smog_fbm(uv);
	float n_lit = smog_fbm(uv + light_xz * offset);
	return hatch_relief_from_samples(n, n_lit, sharpness);
}

// One set of parallel lines at angle_deg, spaced 1/freq apart, `thickness`
// (0..1 of that spacing) wide. Returns 1.0 ON a line, 0.0 in the gaps.
float _hatch_stripe(vec2 uv, float freq, float angle_deg, float thickness) {
	float a = radians(angle_deg);
	vec2 dir = vec2(cos(a), sin(a));
	vec2 perp = vec2(-dir.y, dir.x);
	float coord = dot(uv, perp) * freq;
	float v = abs(fract(coord) - 0.5) * 2.0;         // 0 at a line's center, 1 at a gap's center
	return 1.0 - smoothstep(thickness, thickness + 0.15, v);
}

// Turns `lit` (0 = fully shadowed, 1 = fully lit) into the chosen style.
// Returns a 0..1 "how bright" result to mix your dark/light colors by -
// same contract as `lit` itself, so HATCH_STYLE_RELIEF is a pure pass-through
// and swapping styles never needs to touch the calling code.
float apply_hatch(vec2 uv, float lit, int style, float scale, float strength, float angle_deg) {
	if (style == HATCH_STYLE_RELIEF) {
		return lit;
	}

	float dark = clamp((1.0 - lit) * strength, 0.0, 1.0);
	if (dark < 0.02) {
		return 1.0;   // lit enough that no marks would show - skip the pattern work
	}

	if (style == HATCH_STYLE_STIPPLE) {
		vec2 p = uv * scale;
		vec2 cell = floor(p);
		vec2 f = fract(p) - 0.5;
		vec2 jitter = vec2(smog_hash(cell) - 0.5, smog_hash(cell + 17.3) - 0.5) * 0.5;
		float d = length(f - jitter);
		float radius = mix(0.0, 0.42, dark);          // dots grow as it darkens
		float dot_mask = 1.0 - smoothstep(radius - 0.08, radius, d);
		return mix(1.0, 0.3, dot_mask);
	}

	float thickness = mix(0.08, 0.5, dark);            // lines thicken/merge as it darkens
	float set1 = _hatch_stripe(uv, scale, angle_deg, thickness);
	float shaded = mix(1.0, 0.35, set1);

	if (style == HATCH_STYLE_CROSSHATCH) {
		// classic escalation: a second, crossing set only kicks in once it's
		// dark enough that a single hatch direction isn't reading as "shadow" yet
		float set2 = _hatch_stripe(uv, scale, angle_deg + 90.0, thickness) * step(0.5, dark);
		shaded = mix(shaded, shaded * 0.55, set2);
	} else if (style == HATCH_STYLE_STREAKS) {
		// stays one direction, just adds a tighter second pass instead of crossing
		float set2 = _hatch_stripe(uv, scale * 1.7, angle_deg, thickness * 0.7) * step(0.35, dark);
		shaded = min(shaded, mix(1.0, 0.6, set2));
	}

	return shaded;
}
