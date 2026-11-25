shader_type spatial;
// Minimal shared water surface: translucent, gently rippling, with a bright
// fresnel rim. Clipped to the hull's inner surface (the program's superellipse
// envelope less the wall, axis along Z) so a flat plane never pokes through.
render_mode cull_disabled, depth_draw_opaque, shadows_disabled;

uniform vec4 water_color : source_color = vec4(0.05, 0.22, 0.28, 0.72);
// Seen from below the surface is a brighter, silvery mirror lit from above.
uniform vec4 underside_color : source_color = vec4(0.25, 0.55, 0.62, 0.85);
uniform float wave_height = 0.004;
uniform float wave_speed = 0.6;
uniform float wave_scale = 6.0;
// Hull clip, in the node's local space; set from SubLayout by bilge_water.gd.
// hull_half: outer half-width and half-height. Mirrors SubLayout.inside_hull.
uniform vec2 hull_half = vec2(0.0);
uniform float hull_half_length = 0.0;
uniform float wall = 0.0;
uniform float plan_exponent = 2.0;
uniform float profile_exponent = 2.0;
uniform float section_exponent = 2.0;
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
	if (hull_half_length > 0.0) {
		float t = min(abs(local_pos.z) / hull_half_length, 1.0);
		float hw = hull_half.x * pow(1.0 - pow(t, plan_exponent), 1.0 / plan_exponent) - wall;
		float hh = hull_half.y * pow(1.0 - pow(t, profile_exponent), 1.0 / profile_exponent) - wall;
		float dy = local_pos.y - clip_axis_y;
		if (hw <= 0.0 || hh <= 0.0
				|| pow(abs(local_pos.x) / hw, section_exponent) + pow(abs(dy) / hh, section_exponent) > 1.0) {
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
