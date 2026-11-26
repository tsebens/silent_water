shader_type spatial;
render_mode unshaded, cull_back;
// Navball face. Samples the equirectangular marking mask (assets/textures/navball_mask.png) by the
// object-space direction of each point, so the ball mesh needs no UVs.
//   R upper hemisphere, G lower hemisphere, B markings.
// Drawn from outside. The ball node is held at the inverse of the sub pose, so the face toward the pilot is the
// direction opposite the nose; the shader turns the object frame half a turn about the apex so that face shows the
// nose heading, and the mask runs against heading (tools/navball_texture.py) so headings fall to the right and
// the numerals read unmirrored.
// Object frame (earth-fixed, as the ball node holds it): +Y is the apex, -Z is north (heading 0), +X is east (heading 90).

uniform sampler2D mask : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 upper_color : source_color;
uniform vec4 lower_color : source_color;
uniform vec4 mark_color : source_color;

varying vec3 obj_dir;

void vertex() {
	obj_dir = vec3(-VERTEX.x, VERTEX.y, -VERTEX.z);
}

void fragment() {
	vec3 d = normalize(obj_dir);
	float lon = atan(d.x, -d.z) / TAU;
	float u = fract(-lon);
	// A second longitude with its seam on the far side, for derivatives that stay continuous.
	float u2 = fract(-lon + 0.5) - 0.5;
	float v = 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI;
	vec2 uv = vec2(u, v);
	vec2 dx = vec2(dFdx(u2), dFdx(v));
	vec2 dy = vec2(dFdy(u2), dFdy(v));
	vec3 m = textureGrad(mask, uv, dx, dy).rgb;
	vec3 base = upper_color.rgb * m.r + lower_color.rgb * m.g;
	vec3 col = mix(base, mark_color.rgb, m.b);
	ALBEDO = col;
	EMISSION = mark_color.rgb * m.b;
}
