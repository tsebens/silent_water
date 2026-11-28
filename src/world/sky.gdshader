shader_type sky;
// Daytime sky: a blue dome fading to a haze at the horizon, and a sun disc with a glow.
// Every colour is a uniform set by SurfaceLighting from the active LightPreset (palette swatches).

uniform vec3 sky_color : source_color = vec3(0.0);
uniform vec3 haze_color : source_color = vec3(0.0);
uniform vec3 sun_color : source_color = vec3(0.0);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
// Angular radius of the disc in radians; 0 draws no disc (and no glow).
uniform float sun_disc_size = 0.0;
uniform float sun_glow = 0.0;
uniform float haze_height = 0.25;

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = max(dir.y, 0.0);
	float haze = 1.0 - smoothstep(0.0, haze_height, up);
	vec3 col = mix(sky_color, haze_color, haze * haze);
	// Below the horizon: the haze, so nothing shows a seam.
	if (dir.y < 0.0) {
		col = haze_color;
	}
	if (sun_disc_size > 0.0) {
		float c = clamp(dot(dir, normalize(sun_direction)), -1.0, 1.0);
		float ang = acos(c);
		float disc = 1.0 - smoothstep(sun_disc_size * 0.9, sun_disc_size, ang);
		float glow = exp(-ang * ang / (sun_disc_size * sun_disc_size * 60.0)) * sun_glow;
		col += sun_color * glow;
		col = mix(col, sun_color * 4.0, disc);
	}
	COLOR = col;
}
