shader_type spatial;
// Bad-air view: a soft screen-space blur and an edge vignette. Drawn over
// everything, unlit. No field-of-view change and no lens distortion: the
// screen is only sampled where it is.
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;

uniform float blur : hint_range(0.0, 1.0) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color;
uniform float blur_radius_px = 14.0;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 px = 1.0 / vec2(textureSize(screen_tex, 0));
	float r = blur * blur_radius_px;
	vec3 sum = vec3(0.0);
	float total = 0.0;
	// Two rings of eight taps plus the centre: a cheap disc blur.
	for (int i = 0; i < 17; i++) {
		float ring = i < 8 ? 0.5 : (i < 16 ? 1.0 : 0.0);
		float a = float(i) * 0.785398;
		vec2 o = ring * r * px * vec2(cos(a), sin(a));
		float w = 1.0 - 0.4 * ring;
		sum += textureLod(screen_tex, SCREEN_UV + o, blur * 2.0).rgb * w;
		total += w;
	}
	vec3 col = sum / total;
	// Vignette: closes in from the edges toward the centre.
	float d = length((SCREEN_UV - 0.5) * vec2(1.6, 1.0)) / 0.9;
	float inner = mix(1.2, 0.15, vignette);
	float v = smoothstep(inner, inner + 0.55, d) * clamp(vignette * 1.1, 0.0, 1.0);
	ALBEDO = mix(col, vignette_color.rgb, v);
	ALPHA = 1.0;
}
