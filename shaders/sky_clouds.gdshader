shader_type sky;

// Sky gradient (driven by day/night cycle)
uniform vec3 sky_top_color : source_color = vec3(0.22, 0.42, 0.78);
uniform vec3 sky_horizon_color : source_color = vec3(0.50, 0.62, 0.78);
uniform vec3 ground_bottom_color : source_color = vec3(0.12, 0.10, 0.08);
uniform vec3 ground_horizon_color : source_color = vec3(0.40, 0.45, 0.38);

// Sun disc
uniform float sun_angle_max : hint_range(0.0, 90.0) = 20.0;
uniform float sun_curve : hint_range(0.0, 1.0) = 0.08;

// Cloud look
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.3;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.12;
uniform vec3 cloud_bright_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow_color : source_color = vec3(0.55, 0.58, 0.68);
uniform float cloud_speed : hint_range(0.0, 0.05) = 0.006;
uniform float cloud_scale : hint_range(0.5, 4.0) = 1.8;

// ─── Noise ───────────────────────────────────────────────────────────────

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// Gradient noise for smoother large-scale shapes
vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}

float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(
		mix(dot(hash22(i), f),
			dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
		mix(dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
			dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
		u.y
	) + 0.5;
}

// FBM with rotation per octave to break grid alignment
float fbm_value(vec2 p, int octaves) {
	float v = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < octaves; i++) {
		v += amp * value_noise(p * freq);
		p = rot * p;
		freq *= 2.0;
		amp *= 0.5;
	}
	return v;
}

float fbm_gradient(vec2 p, int octaves) {
	float v = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < octaves; i++) {
		v += amp * gradient_noise(p * freq);
		p = rot * p;
		freq *= 2.0;
		amp *= 0.5;
	}
	return v;
}

// ─── Cloud shape ─────────────────────────────────────────────────────────

float cloud_shape(vec2 uv, vec2 wind) {
	// Large-scale structure: gradient noise for smooth puffy shapes
	float base = fbm_gradient(uv * 0.8 + wind, 3);

	// Domain warp: shift coordinates by noise for organic edges
	vec2 warp = vec2(
		fbm_value(uv * 1.5 + wind * 0.7 + 7.3, 3),
		fbm_value(uv * 1.5 + wind * 0.7 + 13.1, 3)
	);
	vec2 warped_uv = uv + warp * 0.4;

	// Medium detail on warped coordinates
	float detail = fbm_value(warped_uv * 2.5 + wind * 1.1, 5);

	// Combine: base provides shape blobs, detail adds texture
	float shape = base * 0.6 + detail * 0.4;

	// Coverage threshold — remap so cloud_coverage controls amount
	float threshold = 1.0 - cloud_coverage;
	float density = smoothstep(threshold, threshold + cloud_softness, shape);

	// Fine erosion at edges for wispy look
	float fine = value_noise(warped_uv * 12.0 + wind * 2.0);
	density *= smoothstep(0.15, 0.45, fine + density * 0.5);

	return clamp(density, 0.0, 1.0);
}

// ─── Sky function ────────────────────────────────────────────────────────

void sky() {
	vec3 dir = EYEDIR;

	// Ground/sky split
	float horizon_blend = smoothstep(-0.05, 0.0, dir.y);

	float ground_t = smoothstep(0.0, -0.4, dir.y);
	vec3 ground = mix(ground_horizon_color, ground_bottom_color, ground_t);

	float sky_t = smoothstep(0.0, 0.65, dir.y);
	vec3 sky_col = mix(sky_horizon_color, sky_top_color, sky_t);

	vec3 col = mix(ground, sky_col, horizon_blend);

	// Sun disc
	if (LIGHT0_ENABLED) {
		float sun_size = sun_angle_max / 180.0 * PI;
		float sun_dot = dot(dir, LIGHT0_DIRECTION);
		float sun_dist = acos(clamp(sun_dot, -1.0, 1.0));
		float sun_fade = smoothstep(sun_size, sun_size * sun_curve, sun_dist);
		col = mix(col, LIGHT0_COLOR * LIGHT0_ENERGY * 0.5, sun_fade * horizon_blend);
	}

	// Clouds — only above horizon
	if (dir.y > 0.005) {
		// Project onto curved dome (slight height ramp avoids stretching at horizon)
		float altitude = 0.15;
		vec2 cloud_uv = dir.xz / (dir.y + altitude) * cloud_scale;

		vec2 wind = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.35);
		float density = cloud_shape(cloud_uv, wind);

		// ── Lighting ──

		float sun_height = 0.5;
		float sun_dp = 0.0;
		vec3 sun_col = vec3(1.0, 0.95, 0.88);
		if (LIGHT0_ENABLED) {
			sun_height = clamp(LIGHT0_DIRECTION.y, 0.0, 1.0);
			sun_dp = clamp(dot(normalize(dir), LIGHT0_DIRECTION), -1.0, 1.0);
			sun_col = LIGHT0_COLOR;
		}

		// Self-shadowing: sample density slightly offset toward sun
		vec2 sun_offset = vec2(0.0);
		if (LIGHT0_ENABLED) {
			sun_offset = LIGHT0_DIRECTION.xz * 0.06;
		}
		float shadow_sample = cloud_shape(cloud_uv + sun_offset, wind);
		float self_shadow = 1.0 - shadow_sample * 0.55;

		// Base brightness from sun angle
		float base_lit = mix(0.35, 1.0, sun_height);
		float lit = base_lit * self_shadow;

		// Detail variation across the cloud surface
		float detail_var = value_noise(cloud_uv * 6.0 + wind * 1.5) * 0.2;
		lit += detail_var;
		lit = clamp(lit, 0.0, 1.0);

		vec3 cloud_col = mix(cloud_shadow_color, cloud_bright_color, lit);

		// Silver lining: bright rim when looking toward sun through thin cloud edges
		float silver = pow(clamp(sun_dp, 0.0, 1.0), 3.0);
		float edge = density * (1.0 - density) * 4.0; // peaks at density=0.5 (cloud edges)
		cloud_col += sun_col * silver * edge * 0.8;

		// Forward scattering: clouds glow when between viewer and sun
		float scatter = pow(clamp(sun_dp, 0.0, 1.0), 8.0);
		cloud_col += sun_col * scatter * density * 0.25;

		// Sunrise/sunset tinting on all clouds
		float low_sun = smoothstep(0.3, 0.0, sun_height);
		vec3 warm_tint = sun_col * vec3(1.1, 0.85, 0.65);
		cloud_col = mix(cloud_col, cloud_col * warm_tint, low_sun * 0.6);

		// Night: clouds go dark blue-grey
		float night_factor = smoothstep(0.05, 0.0, sun_height);
		vec3 night_cloud = vec3(0.08, 0.09, 0.14);
		cloud_col = mix(cloud_col, night_cloud, night_factor * 0.85);

		// Fade at horizon for depth
		float horizon_fade = smoothstep(0.01, 0.15, dir.y);
		density *= horizon_fade;

		// Aerial perspective: distant clouds pick up sky/fog color
		float aerial = 1.0 - horizon_fade;
		cloud_col = mix(cloud_col, sky_col, aerial * 0.6);

		col = mix(col, cloud_col, density * 0.92);
	}

	COLOR = col;
}
