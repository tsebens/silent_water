shader_type spatial;
// Matte, worn industrial metal for the sub's interior. Tileable and
// procedural: low-contrast panel seams, a few light scratches, and wear along
// edges and the walkway. Triplanar in the mesh's local space, so it needs no
// UVs. No grain or noise filter; every feature is a crisp, deterministic shape.

uniform vec4 base_tone : source_color = vec4(0.24, 0.27, 0.29, 1.0);
// 0 = pristine, 1 = heavily worn.
uniform float wear_amount : hint_range(0.0, 1.0) = 0.35;
// Panel size in metres is panel_size / scale; larger scale = smaller panels.
uniform float scale : hint_range(0.1, 8.0) = 1.0;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.7;
// Height (local Y, metres) below which walkway wear builds up.
uniform float walkway_height = 0.35;

varying vec3 local_pos;
varying vec3 local_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 1 on a seam line, 0 elsewhere, for a grid of the given cell size.
float seam(vec2 p, float cell, float width) {
	vec2 g = abs(fract(p / cell + 0.5) - 0.5) * cell;
	return 1.0 - smoothstep(width * 0.5, width, min(g.x, g.y));
}

// A sparse set of thin diagonal scratches, one candidate per cell.
float scratches(vec2 p) {
	float cell = 0.6;
	vec2 id = floor(p / cell);
	vec2 f = fract(p / cell) - 0.5;
	float h = hash(id);
	if (h < 0.7) {
		return 0.0;
	}
	float a = h * 6.2831;
	vec2 dir = vec2(cos(a), sin(a));
	float across = abs(dot(f, vec2(-dir.y, dir.x)));
	float along = abs(dot(f, dir));
	return (1.0 - smoothstep(0.004, 0.012, across)) * (1.0 - smoothstep(0.25, 0.4, along));
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 n = abs(normalize(local_normal));
	vec2 uv;
	if (n.y >= n.x && n.y >= n.z) {
		uv = local_pos.xz;
	} else if (n.x >= n.z) {
		uv = local_pos.zy;
	} else {
		uv = local_pos.xy;
	}
	uv *= scale;

	float panel = seam(uv, 1.0, 0.012);
	float cell_tone = hash(floor(uv)) - 0.5;
	float scratch = scratches(uv) * wear_amount;
	// Edge wear: seam neighbourhood brightens a little where metal shows through.
	float edge = seam(uv, 1.0, 0.06) * wear_amount;
	float walkway = (1.0 - smoothstep(0.0, walkway_height, local_pos.y)) * wear_amount * 0.5;

	vec3 col = base_tone.rgb * (1.0 + cell_tone * 0.08);
	col *= 1.0 - panel * 0.25;
	col = mix(col, col * 1.7 + 0.03, clamp(scratch + edge * 0.35 + walkway * 0.5, 0.0, 1.0));
	ALBEDO = col;
	METALLIC = metallic_amount;
	ROUGHNESS = clamp(roughness_amount - (scratch + walkway * 0.5) * 0.25, 0.0, 1.0);
}
