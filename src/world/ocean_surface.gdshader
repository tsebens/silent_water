shader_type spatial;
// Translucent low-poly water surface. Waves are a vertex displacement in
// render space (mirrors OceanSurface.wave_height); a fragment ripple layer adds
// detail on top. Double-sided: from below it transmits the sky (sun disc or
// bright patch) through a refraction-like distortion; from above it reflects
// the sky over darker water. Never drawn inside the hull volume (discard).
render_mode cull_disabled, shadows_disabled, unshaded, blend_mix, depth_draw_never;

uniform float amplitude = 0.6;
uniform float wavelength = 14.0;
uniform float wave_speed = 0.5;
uniform vec4 top_color : source_color = vec4(0.05, 0.25, 0.35, 1.0);
uniform vec4 under_color : source_color = vec4(0.55, 0.85, 0.9, 1.0);
uniform vec4 sky_color : source_color = vec4(0.3, 0.6, 0.75, 1.0);
uniform vec4 tint : source_color = vec4(0.6, 0.85, 0.9, 1.0);
uniform float alpha = 0.7;
uniform float transmission = 0.6;
uniform float ripple_scale = 1.5;
uniform float ripple_strength = 0.35;
uniform vec3 sun_direction = vec3(0.4, 0.8, 0.45);
uniform float sun_strength = 1.0;
// Hull volume in render space (the interior is still at the origin).
uniform vec3 hull_center = vec3(0.0);
uniform vec3 hull_half_extents = vec3(2.0, 2.0, 5.0);
uniform mat3 hull_basis = mat3(1.0);

varying float h;
varying vec3 rpos;

float wave_height(vec2 pos, float time) {
	float k = 6.28318530718 / max(wavelength, 0.001);
	float t = time * wave_speed * k;
	float a = sin(pos.x * k + t);
	float b = sin(pos.y * k * 0.83 - t * 0.7 + 1.7);
	float c = sin((pos.x + pos.y) * k * 1.9 + t * 1.3);
	return amplitude * (a * 0.5 + b * 0.3 + c * 0.2);
}

// Gradient of a small sum of travelling sines: the ripple layer.
vec2 ripple_slope(vec2 p, float time) {
	float k = ripple_scale;
	vec2 g = vec2(0.0);
	g += cos(dot(p, vec2(0.9, 0.4)) * k + time * 1.3) * vec2(0.9, 0.4);
	g += cos(dot(p, vec2(-0.5, 0.85)) * k * 1.7 - time * 1.1) * vec2(-0.5, 0.85) * 0.7;
	g += cos(dot(p, vec2(0.2, -1.0)) * k * 2.9 + time * 1.9) * vec2(0.2, -1.0) * 0.4;
	return g * ripple_strength * 0.3;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	h = wave_height(w.xz, TIME);
	VERTEX.y += h;
	rpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 local = (rpos - hull_center) * hull_basis; // inverse of an orthonormal basis
	vec3 q = abs(local);
	if (q.x < hull_half_extents.x && q.y < hull_half_extents.y && q.z < hull_half_extents.z) {
		discard;
	}
	vec2 slope = ripple_slope(rpos.xz, TIME);
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz); // surface -> camera
	float shade = 0.85 + 0.15 * (h / max(amplitude, 0.001));
	vec3 sun = normalize(sun_direction);
	if (FRONT_FACING) {
		// From above: reflect the sky over darker water.
		vec3 r = reflect(-view_dir, n);
		float fres = pow(1.0 - clamp(dot(view_dir, n), 0.0, 1.0), 3.0);
		float glint = smoothstep(0.985, 0.998, dot(r, sun)) * sun_strength;
		vec3 c = mix(top_color.rgb * tint.rgb, sky_color.rgb, 0.25 + 0.6 * fres) * shade;
		ALBEDO = c + vec3(glint);
		ALPHA = clamp(alpha + 0.2 * fres, 0.0, 1.0);
	} else {
		// From below: look up through the surface, bent by the ripple normal.
		vec3 bent = normalize(-view_dir + vec3(-n.x, 0.0, -n.z) * 1.5 * transmission);
		vec3 out_dir = vec3(bent.x, abs(bent.y), bent.z);
		float disc = smoothstep(0.97, 0.995, dot(normalize(out_dir), sun)) * sun_strength;
		float patch_glow = pow(max(dot(normalize(out_dir), sun), 0.0), 8.0) * 0.5 * sun_strength;
		vec3 transmitted = sky_color.rgb * (0.6 + patch_glow) + vec3(disc);
		vec3 c = mix(under_color.rgb * tint.rgb, transmitted, clamp(transmission, 0.0, 1.0)) * shade;
		ALBEDO = c;
		ALPHA = clamp(alpha, 0.0, 1.0);
	}
}
