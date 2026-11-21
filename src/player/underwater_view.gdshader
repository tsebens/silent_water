shader_type spatial;
// Full-screen underwater treatment: a flat tint and exponential depth fog
// toward the tint colour. Drawn over everything, unlit.
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.04, 0.2, 0.26, 0.28);
uniform float fog_density = 0.25;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float dist = -view.z / view.w;
	float fog = 1.0 - exp(-fog_density * max(dist, 0.0));
	ALBEDO = tint.rgb;
	ALPHA = clamp(tint.a + (1.0 - tint.a) * fog * 0.85, 0.0, 1.0);
}
