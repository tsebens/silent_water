shader_type spatial;
// Marine snow anchored in world space. Every flake has a fixed base position in
// a box_size cube; wrapping by the sub's world position keeps a full cube of
// flakes around the sub while each flake stays put in the world.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 sub_pos = vec3(0.0);
uniform float box_size = 24.0;
uniform float flake_size = 0.035;
uniform float fall_speed = 0.04;
// Hull volume (sub-local) where no flakes may appear, and the sub's rotation.
uniform mat3 sub_basis_inv = mat3(1.0);
uniform vec3 hull_center = vec3(0.0, 0.98, 0.0);
uniform vec3 hull_half_extents = vec3(2.1, 2.1, 5.1);
// Faint self-illumination so flakes read as a motion cue even outside the
// lights. Lights still make them much brighter.
uniform float self_glow = 0.35;
uniform vec4 flake_color : source_color = vec4(0.75, 0.78, 0.72, 1.0);

varying float edge_fade;

void vertex() {
	vec3 base = VERTEX;
	float jitter = fract(sin(dot(base.xz, vec2(12.9898, 78.233))) * 43758.5453);
	base.y -= TIME * fall_speed * (0.5 + jitter);
	base.x += sin(TIME * 0.1 + jitter * 6.28) * 0.15;
	// Node sits at sub_pos, so node-local = flake world position - sub_pos.
	vec3 local = mod(base - sub_pos, box_size) - box_size * 0.5;
	// Skip flakes inside the hull: move them outside the clip volume.
	vec3 in_sub = sub_basis_inv * local - hull_center;
	if (all(lessThan(abs(in_sub), hull_half_extents))) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
		edge_fade = 0.0;
	} else {
		vec4 view_center = MODELVIEW_MATRIX * vec4(local, 1.0);
		view_center.xy += (UV - 0.5) * flake_size * (0.6 + jitter);
		POSITION = PROJECTION_MATRIX * view_center;
		float edge = max(max(abs(local.x), abs(local.y)), abs(local.z)) / (box_size * 0.5);
		edge_fade = 1.0 - smoothstep(0.75, 1.0, edge);
	}
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = flake_color.rgb;
	EMISSION = flake_color.rgb * self_glow;
	ALPHA = edge_fade * clamp(1.0 - d, 0.0, 1.0) * flake_color.a;
	ROUGHNESS = 1.0;
	// Billboards have no mesh normals; face the camera so lights reach them.
	NORMAL = vec3(0.0, 0.0, 1.0);
	BACKLIGHT = vec3(0.6);
}
