shader_type canvas_item;

uniform vec4 bar_color : source_color = vec4(0.2, 1.0, 0.4, 1.0);
uniform float bar_width = 0.02;        // HALF the bar thickness / bar length (3 / 156)
uniform int copies = 40;
uniform float copy_spacing = 0.03;     // radians between echoes
uniform float falloff = 2.0;
uniform float trail_dir = 1.0;         // 1.0 or -1.0, flips which side the trail is on

const int MAX_COPIES = 128;
const float BAR_ANGLE = -1.5707964;    // your bar points up (-Y)

void fragment() {
    vec2 p = (UV - 0.5) * 2.0;         // -1..1, origin at the Trail's center
    float result = 0.0;

    if (length(p) <= 1.0) {
        for (int i = 0; i < MAX_COPIES; i++) {
            if (i >= copies) break;

            float a = BAR_ANGLE - trail_dir * float(i + 1) * copy_spacing;
            vec2 dir = vec2(cos(a), sin(a));

            float along = dot(p, dir);
            float perp = abs(p.x * dir.y - p.y * dir.x);

            float on_bar = step(0.0, along) * step(along, 1.0)
                         * (1.0 - smoothstep(bar_width * 0.6, bar_width, perp));
            float fade = pow(1.0 - float(i) / float(copies), falloff);

            result = max(result, on_bar * fade);
        }
    }

    COLOR = vec4(bar_color.rgb, bar_color.a * result);
}