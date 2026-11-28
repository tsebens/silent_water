shader_type spatial;
// Dive-suit helmet frame: an opaque rim that closes in from the screen edges.
// Drawn over everything, unlit. No field-of-view change and no distortion.
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;

uniform float narrowing : hint_range(0.0, 1.0) = 0.0;
uniform vec4 frame_color : source_color;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float d = length((SCREEN_UV - 0.5) * vec2(1.6, 1.0)) / 0.9;
	float inner = mix(1.4, 0.45, narrowing);
	float v = smoothstep(inner, inner + 0.12, d);
	ALBEDO = frame_color.rgb;
	ALPHA = v;
}
