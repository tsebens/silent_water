shader_type spatial;
// Translucent faceted water surface. Gerstner waves displace the mesh in render
// space (mirrors OceanSurface); the analytic normal is flat per facet, with a
// fragment ripple layer blended in. Lit by hand from the preset's sun (the
// surface is unshaded so engine light fades don't touch it). Double-sided:
// from below it transmits the sky through a refraction-like distortion; from
// above a Fresnel term mixes water colour and sky, plus a tight sun glint.
// Never drawn inside the hull volume (discard).
render_mode cull_disabled, shadows_disabled, unshaded, blend_mix, depth_draw_never;

const int MAX_WAVES = 6;
// Gerstner waves, packed by OceanSurface.pack_waves (the table is generated
// in GDScript so both sides use the same numbers):
// wave_a = (dir.x, dir.z, k, omega), wave_b = (amplitude, horizontal amplitude, 0, 0).
uniform vec4 wave_a[MAX_WAVES];
uniform vec4 wave_b[MAX_WAVES];
uniform int wave_count = 0;
uniform float amplitude = 1.2; // sum of wave amplitudes, for shading
uniform vec4 top_color : source_color = vec4(0.05, 0.25, 0.35, 1.0);
uniform vec4 under_color : source_color = vec4(0.55, 0.85, 0.9, 1.0);
uniform vec4 sky_color : source_color = vec4(0.3, 0.6, 0.75, 1.0);
uniform vec4 tint : source_color = vec4(0.6, 0.85, 0.9, 1.0);
uniform float alpha = 0.7;
uniform float transmission = 0.6;
uniform float ripple_scale = 1.5;
uniform float ripple_strength = 0.35;
// Direction towards the sun (or moon), its colour and strength, from the light preset.
uniform vec3 sun_direction = vec3(0.4, 0.8, 0.45);
uniform vec4 sun_color : source_color = vec4(1.0);
uniform float sun_strength = 1.0;
// Hull volume in render space (the interior is still at the origin).
uniform vec3 hull_center = vec3(0.0);
uniform vec3 hull_half_extents = vec3(2.0, 2.0, 5.0);
uniform mat3 hull_basis = mat3(1.0);

varying float h;
varying vec3 rpos;
// Analytic Gerstner normal at the provoking vertex: one per facet.
varying flat vec3 facet_normal;

// Mirrors OceanSurface.wave_height / horizontal_displacement / wave_normal.
void gerstner(vec2 pos, float time, out float height, out vec2 disp, out vec3 normal) {
	height = 0.0;
	disp = vec2(0.0);
	normal = vec3(0.0, 1.0, 0.0);
	for (int i = 0; i < MAX_WAVES; i++) {
		if (i >= wave_count) {
			break;
		}
		vec2 d = wave_a[i].xy;
		float k = wave_a[i].z;
		float th = k * dot(d, pos) - wave_a[i].w * time;
		float a = wave_b[i].x;
		float q = wave_b[i].y;
		float s = sin(th);
		float c = cos(th);
		height += a * s;
		disp += d * (q * c);
		normal.x -= d.x * k * a * c;
		normal.z -= d.y * k * a * c;
		normal.y -= k * q * s;
	}
	normal = normalize(normal);
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
	float height;
	vec2 disp;
	vec3 normal;
	gerstner(w.xz, TIME, height, disp, normal);
	h = height;
	facet_normal = normal;
	VERTEX.xz += disp;
	VERTEX.y += height;
	rpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 local = (rpos - hull_center) * hull_basis; // inverse of an orthonormal basis
	vec3 q = abs(local);
	if (q.x < hull_half_extents.x && q.y < hull_half_extents.y && q.z < hull_half_extents.z) {
		discard;
	}
	// Facet normal plus the small-scale ripple normal.
	vec2 slope = ripple_slope(rpos.xz, TIME);
	vec3 n = normalize(facet_normal + vec3(-slope.x, 0.0, -slope.y));
	vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz); // surface -> camera
	vec3 sun = normalize(sun_direction);
	vec3 sun_c = sun_color.rgb * sun_strength;
	float crest = clamp(0.5 + 0.5 * h / max(amplitude, 0.001), 0.0, 1.0);
	if (FRONT_FACING) {
		// From above: Fresnel between water colour (looking down) and sky (grazing).
		float ndv = clamp(dot(view_dir, n), 0.0, 1.0);
		float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
		vec3 water = top_color.rgb * tint.rgb * (0.55 + 0.9 * max(dot(n, sun), 0.0) * sun_color.rgb * sun_strength * 0.5);
		water *= 0.85 + 0.3 * crest;
		vec3 c = mix(water, sky_color.rgb, clamp(fres, 0.0, 1.0));
		// Tight specular lobe on the facet normal.
		vec3 hv = normalize(sun + view_dir);
		float spec = pow(max(dot(n, hv), 0.0), 220.0) * 2.5;
		ALBEDO = c + sun_c * spec;
		ALPHA = clamp(alpha + 0.2 * fres + spec, 0.0, 1.0);
	} else {
		// From below: look up through the surface, bent by the facet normal.
		vec3 bent = normalize(-view_dir + vec3(-n.x, 0.0, -n.z) * 1.5 * transmission);
		vec3 out_dir = vec3(bent.x, abs(bent.y), bent.z);
		float disc = smoothstep(0.97, 0.995, dot(normalize(out_dir), sun)) * sun_strength;
		float patch_glow = pow(max(dot(normalize(out_dir), sun), 0.0), 8.0) * 0.5 * sun_strength;
		vec3 transmitted = sky_color.rgb * (0.6 + patch_glow) + sun_color.rgb * disc;
		vec3 c = mix(under_color.rgb * tint.rgb, transmitted, clamp(transmission, 0.0, 1.0)) * (0.85 + 0.3 * crest);
		ALBEDO = c;
		ALPHA = clamp(alpha, 0.0, 1.0);
	}
}
