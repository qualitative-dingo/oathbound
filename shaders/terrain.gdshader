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

group_uniforms paths;
uniform vec3 path_color : source_color = vec3(0.18, 0.11, 0.05);
uniform float path_roughness : hint_range(0.0, 1.0) = 0.92;

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

float fbm2(vec2 p) {
	float v = vnoise(p) * 0.6;
	v += vnoise(p * 2.1 + vec2(100.0)) * 0.4;
	return v;
}

vec3 triplanar(sampler2D tex, vec3 wpos, vec3 blend, float scale) {
	vec2 uv_x = wpos.zy * scale;
	vec2 uv_y = wpos.xz * scale;
	vec2 uv_z = wpos.xy * scale;

	vec3 col = texture(tex, uv_x).rgb * blend.x
	         + texture(tex, uv_y).rgb * blend.y
	         + texture(tex, uv_z).rgb * blend.z;

	vec3 col2 = texture(tex, wpos.xz * scale * 0.37 + vec2(17.0, 31.0)).rgb;
	float tile_break = vnoise(wpos.xz * 0.08 + vec2(41.0, 67.0));
	col = mix(col, col2, tile_break * 0.4 * blend.y);

	return col;
}

uniform vec3 origin_shift;

varying vec3 v_world_pos;
varying float v_path_mask;

varying float v_brightness;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
	v_path_mask = COLOR.r;
	v_brightness = COLOR.g;
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

	vec3 col_flat  = triplanar(tex_flat,  world_pos, blend, texture_scale);
	vec3 col_slope = triplanar(tex_slope, world_pos, blend, texture_scale);
	vec3 col_cliff = triplanar(tex_cliff, world_pos, blend, texture_scale);

	vec3 albedo = col_flat * flat_w + col_slope * slope_w + col_cliff * cliff_w;

	float n_large = fbm2(world_pos.xz * 0.012);
	float n_med   = fbm2(world_pos.xz * 0.04 + vec2(50.0, 80.0));
	float brightness = 0.38 + n_large * 0.18 + n_med * 0.10;
	brightness = mix(1.0, brightness, variation_strength);
	albedo *= brightness;

	vec3 warm_shift = vec3(0.03, 0.015, -0.015) * (n_large - 0.5) * variation_strength;
	albedo += warm_shift;

	float mud = fbm2(world_pos.xz * 0.02 + vec2(200.0, 300.0));
	float mud_mask = smoothstep(0.3, 0.55, mud) * flat_w * variation_strength;
	albedo = mix(albedo, col_slope * 0.75, mud_mask * 0.8);

	vec2 dirt_warp = vec2(
		fbm2(world_pos.xz * 0.012 + vec2(137.0, 241.0)),
		fbm2(world_pos.xz * 0.012 + vec2(359.0, 83.0))
	) * 28.0;
	float dirt_noise = fbm2((world_pos.xz + dirt_warp) * 0.018 + vec2(500.0, 700.0));
	float dirt_thresh = 0.5 + (0.5 - dirt_patch_amount) * 0.6;
	float dirt_mask = smoothstep(dirt_thresh - 0.06, dirt_thresh + 0.06, dirt_noise) * flat_w;
	albedo = mix(albedo, dirt_color * (0.85 + vnoise(world_pos.xz * 0.3) * 0.15), dirt_mask);

	// Clay paths from vertex color R channel — blend dirt texture with path tint
	float pm = smoothstep(0.2, 0.7, v_path_mask) * flat_w;
	vec3 dirt_detail = col_slope * 0.6 + col_flat * 0.15;
	vec3 path_base = path_color * dirt_detail * 4.0;
	path_base *= (0.85 + vnoise(world_pos.xz * 0.12 + vec2(900.0, 400.0)) * 0.2);
	path_base *= (0.9 + fbm2(world_pos.xz * 0.06 + vec2(150.0, 250.0)) * 0.15);
	albedo = mix(albedo, path_base, pm);

	float ao_mask = smoothstep(0.3, 0.6, n_med) * flat_w * 0.2;
	albedo *= (1.0 - ao_mask);

	float ground_shadow = flat_w * 0.22 * (1.0 - dirt_mask) * (1.0 - pm);
	albedo *= (1.0 - ground_shadow);
	float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	albedo = mix(albedo, vec3(luma), ground_shadow * 0.5);

	ALBEDO = albedo * tint_color * v_brightness;
	float base_rough = mix(0.8, 0.95, mud_mask * 0.5 + ao_mask);
	base_rough = mix(base_rough, 0.65, dirt_mask);
	ROUGHNESS = mix(base_rough, path_roughness, pm);
	AO = 1.0 - ao_mask * 2.0;
	AO_LIGHT_AFFECT = 0.5;
}
