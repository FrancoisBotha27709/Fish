shader_type canvas_item;
uniform sampler2D current_foam;
uniform sampler2D history_foam;
uniform float delta;

void fragment() {
	float current = texture(current_foam, UV).r;
	float previous = texture(history_foam, UV).r;
	
	previous *= exp(-3.5 * delta);
	previous = max(previous, 0.0);
	
	float foam = max(current, previous);
	COLOR = vec4(vec3(foam), 1.0);
}
