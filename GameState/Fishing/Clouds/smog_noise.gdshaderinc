float smog_hash(vec2 p) {
	p = mod(p, 289.0);
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float smog_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = smog_hash(i);
	float b = smog_hash(i + vec2(1.0, 0.0));
	float c = smog_hash(i + vec2(0.0, 1.0));
	float d = smog_hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Standard fbm - soft, drifting haze. ~0..0.94
float smog_fbm(vec2 p) {
	mat2 m = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));   // rotate each octave so the grid never shows
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * smog_vnoise(p);
		p = m * p * 2.03;
		amp *= 0.5;
	}
	return v;
}

// Billowed fbm - folds each octave at |n*2-1| so it piles up into puffy,
// cauliflower-topped shapes instead of soft haze. This is what reads as
// "clouds" rather than "haze". ~0..1
float smog_billow(vec2 p) {
	mat2 m = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		float n = smog_vnoise(p);
		v += amp * abs(n * 2.0 - 1.0);
		p = m * p * 2.05;
		amp *= 0.55;
	}
	return v;
}
