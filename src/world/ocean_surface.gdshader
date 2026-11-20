shader_type spatial;
// Crisp low-poly water surface. Waves are a vertex displacement in world space
// (mirrors OceanSurface.wave_height). Double-sided: bright ceiling from below.
render_mode cull_disabled, shadows_disabled, unshaded;

uniform float amplitude = 0.6;
uniform float wavelength = 14.0;
uniform float wave_speed = 0.5;
uniform vec4 top_color : source_color = vec4(0.05, 0.25, 0.35, 1.0);
uniform vec4 under_color : source_color = vec4(0.55, 0.85, 0.9, 1.0);

varying float h;

float wave_height(vec2 pos, float time) {
	float k = 6.28318530718 / max(wavelength, 0.001);
	float t = time * wave_speed * k;
	float a = sin(pos.x * k + t);
	float b = sin(pos.y * k * 0.83 - t * 0.7 + 1.7);
	float c = sin((pos.x + pos.y) * k * 1.9 + t * 1.3);
	return amplitude * (a * 0.5 + b * 0.3 + c * 0.2);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	h = wave_height(w.xz, TIME);
	VERTEX.y += h;
}

void fragment() {
	float shade = 0.85 + 0.15 * (h / max(amplitude, 0.001));
	vec3 c = FRONT_FACING ? top_color.rgb : under_color.rgb;
	ALBEDO = c * shade;
}
