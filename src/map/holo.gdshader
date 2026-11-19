shader_type spatial;
// Hologram: translucent, additive, unlit. Clipped to the display volume (an
// elliptic cylinder standing on the projector), with glowing height contour
// lines and brighter edges where surfaces turn away from the viewer.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 holo_color : source_color = vec4(0.3, 0.85, 0.95, 1.0);
uniform float alpha = 0.18;
uniform float edge_boost = 0.5;
// Display volume in render space.
uniform vec3 clip_center = vec3(0.0);
uniform vec3 clip_up = vec3(0.0, 1.0, 0.0);
uniform vec3 clip_axis_x = vec3(1.0, 0.0, 0.0);
uniform float clip_rx = 0.5;
uniform float clip_rz = 0.5;
uniform float clip_height = 0.6;
// Contour lines every this many display metres (0 = none).
uniform float contour_spacing = 0.02;
uniform float contour_strength = 0.35;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 d = world_pos - clip_center;
	float h = dot(d, clip_up);
	vec3 axis_z = normalize(cross(clip_axis_x, clip_up));
	float x = dot(d, clip_axis_x) / clip_rx;
	float z = dot(d, axis_z) / clip_rz;
	if (h < 0.0 || h > clip_height || x * x + z * z > 1.0) {
		discard;
	}
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(1.0 - facing, 2.0) * edge_boost;
	float contour = 0.0;
	if (contour_spacing > 0.0) {
		float f = fract(h / contour_spacing);
		contour = (1.0 - smoothstep(0.0, 0.08, min(f, 1.0 - f))) * contour_strength;
	}
	// Fade toward the top of the volume so the hologram reads as projected.
	float fade = 1.0 - smoothstep(0.75, 1.0, h / clip_height);
	ALBEDO = holo_color.rgb;
	ALPHA = clamp((alpha + edge + contour) * fade, 0.0, 1.0);
}
