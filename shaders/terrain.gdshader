shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert_wrap;

group_uniforms textures;
uniform sampler2D tex_flat  : filter_nearest_mipmap, repeat_enable;
uniform sampler2D tex_slope : filter_nearest_mipmap, repeat_enable;
uniform sampler2D tex_cliff : filter_nearest_mipmap, repeat_enable;

group_uniforms settings;
uniform float texture_scale : hint_range(0.01, 4.0) = 0.5;
uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float slope_start : hint_range(0.0, 1.0) = 0.25;
uniform float cliff_start : hint_range(0.0, 1.0) = 0.55;

group_uniforms variation;
uniform float variation_strength : hint_range(0.0, 1.0) = 0.5;
uniform float dirt_patch_amount : hint_range(0.0, 0.5) = 0.1;
uniform vec3 dirt_color : source_color = vec3(0.35, 0.28, 0.16);

float hash12(vec2 p) {
	float h = dot(p, vec2(127.1, 311.7));
	return fract(sin(h) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

// 2-octave FBM (was 3 — saves ~33% noise cost)
float fbm2(vec2 p) {
	float v = vnoise(p) * 0.6;
	v += vnoise(p * 2.1 + vec2(100.0)) * 0.4;
	return v;
}

// Triplanar with anti-tiling: second scale only on Y-plane (4 samples, not 6)
vec3 triplanar(sampler2D tex, vec3 wpos, vec3 blend, float scale) {
	vec2 uv_x = wpos.zy * scale;
	vec2 uv_y = wpos.xz * scale;
	vec2 uv_z = wpos.xy * scale;

	vec3 col = texture(tex, uv_x).rgb * blend.x
	         + texture(tex, uv_y).rgb * blend.y
	         + texture(tex, uv_z).rgb * blend.z;

	// Break tiling on flat ground with a second scale (1 extra sample)
	vec3 col2 = texture(tex, wpos.xz * scale * 0.37 + vec2(17.0, 31.0)).rgb;
	float tile_break = vnoise(wpos.xz * 0.08 + vec2(41.0, 67.0));
	col = mix(col, col2, tile_break * 0.4 * blend.y);

	return col;
}

uniform vec3 origin_shift;

varying vec3 v_world_pos;

void vertex() {
	// Scene-space position (small thanks to floating origin) + origin_shift = true world position.
	// Vertex transforms use small scene coords (GPU-friendly), but texturing needs stable world coords.
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
}

void fragment() {
	vec3 world_pos = v_world_pos;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	vec3 blend = abs(world_normal);
	blend = pow(blend, vec3(8.0));
	blend /= (blend.x + blend.y + blend.z + 0.0001);

	float slope = 1.0 - abs(world_normal.y);

	float flat_w  = smoothstep(slope_start + 0.1, slope_start, slope);
	float cliff_w = smoothstep(cliff_start, cliff_start + 0.15, slope);
	float slope_w = max(1.0 - flat_w - cliff_w, 0.0);

	// 9 texture samples total (3 per triplanar call)
	vec3 col_flat  = triplanar(tex_flat,  world_pos, blend, texture_scale);
	vec3 col_slope = triplanar(tex_slope, world_pos, blend, texture_scale);
	vec3 col_cliff = triplanar(tex_cliff, world_pos, blend, texture_scale);

	vec3 albedo = col_flat * flat_w + col_slope * slope_w + col_cliff * cliff_w;

	// Brightness and color variation (2 fbm2 calls = 4 noise evals)
	float n_large = fbm2(world_pos.xz * 0.012);
	float n_med   = fbm2(world_pos.xz * 0.04 + vec2(50.0, 80.0));
	float brightness = 0.6 + n_large * 0.3 + n_med * 0.2;
	brightness = mix(1.0, brightness, variation_strength);
	albedo *= brightness;

	// Hue shift: warm vs cool patches (reuses n_large, no extra noise)
	vec3 warm_shift = vec3(0.03, 0.015, -0.015) * (n_large - 0.5) * variation_strength;
	albedo += warm_shift;

	// Mud patches (1 fbm2 = 2 noise evals, reuses slope triplanar)
	float mud = fbm2(world_pos.xz * 0.02 + vec2(200.0, 300.0));
	float mud_mask = smoothstep(0.3, 0.55, mud) * flat_w * variation_strength;
	albedo = mix(albedo, col_slope * 0.75, mud_mask * 0.8);

	// Bare dirt patches — uses offset noise so they don't overlap mud
	float dirt_noise = fbm2(world_pos.xz * 0.018 + vec2(500.0, 700.0));
	float dirt_thresh = 0.5 + (0.5 - dirt_patch_amount) * 0.6;
	float dirt_mask = smoothstep(dirt_thresh - 0.06, dirt_thresh + 0.06, dirt_noise) * flat_w;
	albedo = mix(albedo, dirt_color * (0.85 + vnoise(world_pos.xz * 0.3) * 0.15), dirt_mask);

	// Ground AO (reuses n_med, no extra noise)
	float ao_mask = smoothstep(0.3, 0.6, n_med) * flat_w * 0.2;
	albedo *= (1.0 - ao_mask);

	// Darken/desaturate flat ground to read as "shadowed under grass"
	float ground_shadow = flat_w * 0.12 * (1.0 - dirt_mask);
	albedo *= (1.0 - ground_shadow);
	float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	albedo = mix(albedo, vec3(luma), ground_shadow * 0.5);

	ALBEDO = albedo * tint_color * COLOR.rgb;
	ROUGHNESS = mix(0.8, 0.95, mud_mask * 0.5 + ao_mask);
	ROUGHNESS = mix(ROUGHNESS, 0.65, dirt_mask);
	AO = 1.0 - ao_mask * 2.0;
	AO_LIGHT_AFFECT = 0.5;
}
