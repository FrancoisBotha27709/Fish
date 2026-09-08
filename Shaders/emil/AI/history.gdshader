shader_type canvas_item;

// Accumulates foam over time: keeps the brightest of this frame's foam
// and last frame's foam, exponentially decayed, so foam lingers and
// fades instead of popping in and out every frame.

uniform sampler2D current_foam;
uniform sampler2D history_foam;
uniform float delta;

// How quickly foam fades once a crest passes. Higher = foam disappears
// almost immediately; lower = foam lingers, e.g. in a boat's wake.
uniform float foam_decay_rate : hint_range(0.1, 10.0) = 3.5;

void fragment() {
	float current = texture(current_foam, UV).r;
	float previous = texture(history_foam, UV).r;

	previous *= exp(-foam_decay_rate * delta);
	previous = max(previous, 0.0);

	float foam = max(current, previous);
	COLOR = vec4(vec3(foam), 1.0);
}
