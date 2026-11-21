shader_type spatial;
// Minimal shared water surface: translucent, gently rippling, with a bright
// fresnel rim. Optionally clipped to a horizontal-cylinder hull (axis along Z)
// so a flat plane inside the hull never pokes through the lining.
render_mode cull_disabled, depth_draw_opaque, shadows_disabled;

uniform vec4 water_color : source_color = vec4(0.05, 0.22, 0.28, 0.72);
// Seen from below the surface is a brighter, silvery mirror lit from above.
uniform vec4 underside_color : source_color = vec4(0.25, 0.55, 0.62, 0.85);
uniform float wave_height = 0.004;
uniform float wave_speed = 0.6;
uniform float wave_scale = 6.0;
// Hull clip, in the node's local space. radius <= 0 disables the clip.
uniform float clip_radius = 0.0;
uniform float clip_axis_y = 0.0;

varying vec3 local_pos;

float ripple(vec2 p, float t) {
	return sin(p.x * wave_scale + t) * cos(p.y * wave_scale * 0.8 - t * 0.7);
}

void vertex() {
	local_pos = VERTEX;
	VERTEX.y += ripple(VERTEX.xz, TIME * wave_speed) * wave_height;
}

void fragment() {
	if (clip_radius > 0.0) {
		float dy = local_pos.y - clip_axis_y;
		if (local_pos.x * local_pos.x + dy * dy > clip_radius * clip_radius) {
			discard;
		}
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = water_color.rgb + vec3(0.15) * fres;
	ALPHA = clamp(water_color.a + 0.2 * fres, 0.0, 1.0);
	if (!FRONT_FACING) {
		ALBEDO = mix(ALBEDO, underside_color.rgb, 0.6);
		ALPHA = max(ALPHA, underside_color.a);
		EMISSION = underside_color.rgb * 0.25;
	}
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
}
