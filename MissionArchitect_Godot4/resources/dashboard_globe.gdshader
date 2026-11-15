shader_type canvas_item;

// Rotating 3D-style Earth for the mission dashboards.  Maps an equirectangular
// texture (real NASA Blue Marble imagery) onto a sphere using per-pixel
// ray/sphere intersection, spins it on the real (sped-up) sidereal rate and
// adds a Lambertian sun term plus a cyan atmosphere rim so it reads as a
// living planet instead of a flat picture.

uniform sampler2D map_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float rot_speed = 0.028;   // radians of longitude per second
uniform vec3 sun_dir = vec3(-0.45, 0.5, 0.66);
uniform float brightness = 1.0;
// UV-space rectangles (x0, y0, x1, y1) where the globe is punched out so art
// overlays (telemetry callouts) baked into the artwork stay on top.
uniform vec4 cutout_a = vec4(0.0);
uniform vec4 cutout_b = vec4(0.0);

bool in_cutout(vec2 uv) {
	if (uv.x > cutout_a.x && uv.x < cutout_a.z && uv.y > cutout_a.y && uv.y < cutout_a.w) {
		return true;
	}
	if (uv.x > cutout_b.x && uv.x < cutout_b.z && uv.y > cutout_b.y && uv.y < cutout_b.w) {
		return true;
	}
	return false;
}

void fragment() {
	// UV 0..1 over the globe's bounding square; q is the unit-disc coordinate.
	vec2 q = (UV - vec2(0.5)) * 2.0;
	float r2 = dot(q, q);
	if (r2 > 1.0) {
		COLOR = vec4(0.0);
	} else {
		float rho = sqrt(r2);
		float z = sqrt(max(1.0 - r2, 0.0));            // front hemisphere depth
		// Longitude: wrap the texture around Y, advancing with TIME.
		float lon = atan(q.x, z) / 6.28318530718 + 0.5 + TIME * rot_speed;
		// Latitude: +1 at the top of the disc = north pole.
		float lat = asin(clamp(-q.y, -1.0, 1.0)) / 3.14159265359;
		vec2 tuv = vec2(fract(lon), 0.5 - lat);
		vec3 base = texture(map_tex, tuv).rgb;

		vec3 n = normalize(vec3(q, z));
		float diff = clamp(dot(n, normalize(sun_dir)), 0.0, 1.0);
		// Soft ambient floor so the night side stays readable on the dark art.
		vec3 col = base * (0.30 + 0.85 * diff) * brightness;

		// Specular glint on the ocean side of the terminator.
		float spec = pow(clamp(dot(reflect(-normalize(sun_dir), n), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 24.0);
		col += vec3(0.35, 0.6, 0.9) * spec * 0.35;

		// Atmosphere: cyan limb glow, stronger toward the lit side.
		float rim = smoothstep(0.68, 1.0, rho);
		float lit_rim = 0.5 + 0.5 * diff;
		col += vec3(0.12, 0.5, 1.0) * rim * lit_rim * 0.55;

		// Anti-aliased outer edge, minus any cutout rectangles.
		float edge = 1.0 - smoothstep(0.985, 1.0, rho);
		if (in_cutout(UV)) {
			edge = 0.0;
		}
		COLOR = vec4(col, edge);
	}
}
