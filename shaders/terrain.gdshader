shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert_wrap;

group_uniforms textures;
uniform sampler2D tex_flat  : filter_nearest_mipmap, repeat_enable;
uniform sampler2D tex_slope : filter_nearest_mipmap, repeat_enable;
uniform sampler2D tex_cliff : filter_nearest_mipmap, repeat_enable;

group_uniforms settings;
uniform float texture_scale : hint_range(0.01, 4.0) = 0.5;
uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float slope_start : hint_range(0.0, 1.0) = 0.06;
uniform float cliff_start : hint_range(0.0, 1.0) = 0.30;

group_uniforms variation;
uniform float variation_strength : hint_range(0.0, 1.0) = 0.5;
uniform float dirt_patch_amount : hint_range(0.0, 0.5) = 0.1;
uniform vec3 dirt_color : source_color = vec3(0.25, 0.19, 0.10);

group_uniforms paths;
uniform vec3 path_color : source_color = vec3(0.12, 0.07, 0.03);
uniform float path_roughness : hint_range(0.0, 1.0) = 0.92;

group_uniforms riverbank;
uniform vec3 bank_color : source_color = vec3(0.12, 0.09, 0.05);
uniform float bank_roughness : hint_range(0.0, 1.0) = 0.95;

group_uniforms rock;
uniform vec3 rock_dark : source_color = vec3(0.15, 0.14, 0.13);
uniform vec3 rock_light : source_color = vec3(0.58, 0.56, 0.53);
uniform vec3 rock_mid : source_color = vec3(0.32, 0.30, 0.27);

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

// Triplanar noise — samples noise from all 3 planes, blended by normal
float tri_noise(vec3 wpos, vec3 blend, float scale, vec2 offset) {
	float nx = vnoise(wpos.zy * scale + offset);
	float ny = vnoise(wpos.xz * scale + offset);
	float nz = vnoise(wpos.xy * scale + offset);
	return nx * blend.x + ny * blend.y + nz * blend.z;
}

float tri_fbm(vec3 wpos, vec3 blend, float scale, vec2 offset) {
	float v = tri_noise(wpos, blend, scale, offset) * 0.55;
	v += tri_noise(wpos, blend, scale * 2.1, offset + vec2(100.0)) * 0.30;
	v += tri_noise(wpos, blend, scale * 4.3, offset + vec2(250.0)) * 0.15;
	return v;
}

// Valheim-style rock: large patchy blobs of light/dark with vertical flow streaks
vec3 rock_color(vec3 wpos, vec3 wnorm, float steepness) {
	vec3 blend = abs(wnorm);
	blend = pow(blend, vec3(2.0));
	blend /= (blend.x + blend.y + blend.z + 0.0001);

	// === Large-scale patches (light vs dark rock) ===
	// Domain warp for organic blob shapes
	float warp_x = tri_fbm(wpos, blend, 0.018, vec2(430.0, 170.0));
	float warp_z = tri_fbm(wpos, blend, 0.018, vec2(810.0, 560.0));
	vec3 warped = wpos + vec3(warp_x, 0.0, warp_z) * 35.0;

	float patch = tri_fbm(warped, blend, 0.03, vec2(90.0, 260.0));
	float patch_mask = smoothstep(0.35, 0.65, patch);

	// === Medium detail patches ===
	float med_patch = tri_fbm(wpos, blend, 0.08, vec2(333.0, 777.0));
	float med_mask = smoothstep(0.3, 0.7, med_patch);

	// === Vertical flow/weathering streaks ===
	// Sample from XY and ZY planes (vertical surfaces) — elongated in Y
	float flow_xy = vnoise(wpos.xy * vec2(0.15, 0.06) + vec2(111.0, 222.0));
	float flow_zy = vnoise(wpos.zy * vec2(0.15, 0.06) + vec2(444.0, 555.0));
	float flow = flow_xy * blend.z + flow_zy * blend.x + 0.5 * blend.y;
	// Finer flow lines
	float flow_fine_xy = vnoise(wpos.xy * vec2(0.4, 0.12) + vec2(700.0, 300.0));
	float flow_fine_zy = vnoise(wpos.zy * vec2(0.4, 0.12) + vec2(900.0, 100.0));
	float flow_fine = flow_fine_xy * blend.z + flow_fine_zy * blend.x + 0.5 * blend.y;

	float flow_streak = smoothstep(0.3, 0.7, flow) * 0.6 + smoothstep(0.35, 0.65, flow_fine) * 0.4;

	// === Build the rock color ===
	// Base: patchy mix of dark and light
	vec3 col = mix(rock_dark, rock_light, patch_mask);
	// Medium detail breaks up the large patches
	col = mix(col, rock_mid, med_mask * 0.45);
	// Flow streaks darken/lighten vertically
	col = mix(col, rock_dark * 0.8, (1.0 - flow_streak) * 0.35 * steepness);
	col = mix(col, rock_light * 1.1, flow_streak * 0.2);

	// === Surface grain — fine texture detail ===
	float grain = tri_noise(wpos, blend, 1.8, vec2(200.0, 400.0));
	float grain2 = tri_noise(wpos, blend, 5.0, vec2(600.0, 100.0));
	col *= 0.88 + grain * 0.15 + grain2 * 0.08;

	// === Crevice darkening — steepest faces get darker ===
	col *= mix(1.0, 0.75, steepness * steepness * 0.3);

	// === Subtle color temperature shift across the mountain ===
	float region = tri_noise(wpos, blend, 0.012, vec2(900.0, 700.0));
	vec3 warm = col * vec3(1.04, 1.0, 0.94);
	vec3 cool = col * vec3(0.94, 0.96, 1.04);
	col = mix(warm, cool, region);

	return col;
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
varying float v_river_bank;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
	v_path_mask = COLOR.r;
	v_brightness = COLOR.g;
	v_river_bank = COLOR.b;
}

void fragment() {
	vec3 world_pos = v_world_pos;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	float slope = 1.0 - abs(world_normal.y);

	// Fix 1: fade vertex-color features on slopes to prevent zigzag mesh artifacts
	float slope_path_fade = smoothstep(0.10, 0.03, slope);

	// Fix 2: procedural color override on slopes — lower threshold catches moderate slopes too
	float steep_override = smoothstep(0.20, 0.45, slope);

	// Soften triplanar blending on steep terrain to reduce projection seam stripes
	float blend_power = mix(8.0, 2.0, steep_override);
	vec3 blend = abs(world_normal);
	blend = pow(blend, vec3(blend_power));
	blend /= (blend.x + blend.y + blend.z + 0.0001);

	// Multi-scale noise to break up the slope contour into organic patches
	float slope_noise = (vnoise(world_pos.xz * 0.15 + vec2(53.0, 97.0)) - 0.5) * 0.08
	                   + (vnoise(world_pos.xz * 0.6 + vec2(200.0, 140.0)) - 0.5) * 0.04;

	// Domain-warped large blobs for organic slope transitions
	vec2 warp = vec2(
		fbm2(world_pos.xz * 0.025 + vec2(430.0, 170.0)),
		fbm2(world_pos.xz * 0.025 + vec2(810.0, 560.0))
	) * 25.0;
	float patch_noise = fbm2((world_pos.xz + warp) * 0.03 + vec2(90.0, 260.0));
	slope_noise += (patch_noise - 0.5) * 0.10;

	float noisy_slope = slope + slope_noise;

	float flat_w  = smoothstep(slope_start + 0.12, slope_start, noisy_slope);
	float cliff_w = smoothstep(cliff_start, cliff_start + 0.18, noisy_slope);
	float slope_w = max(1.0 - flat_w - cliff_w, 0.0);

	vec3 col_flat  = triplanar(tex_flat,  world_pos, blend, texture_scale);
	vec3 col_slope = triplanar(tex_slope, world_pos, blend, texture_scale);

	// Valheim-style patchy rock for steep slopes
	vec3 col_cliff = rock_color(world_pos, world_normal, steep_override);
	// Blend in cliff texture for micro surface detail
	vec3 tex_cliff_col = triplanar(tex_cliff, world_pos, blend, texture_scale);
	col_cliff = mix(col_cliff, col_cliff * tex_cliff_col * 2.2, 0.2);

	// Subtle scatter on gentle slopes only — never on steep terrain
	float scatter = vnoise(world_pos.xz * 0.35 + vec2(610.0, 390.0));
	float scatter_mask = smoothstep(0.62, 0.80, scatter) * slope_w * 0.3 * flat_w;
	float adj_flat_w  = flat_w + scatter_mask;
	float adj_slope_w = max(slope_w - scatter_mask, 0.0);

	vec3 albedo = col_flat * adj_flat_w + col_slope * adj_slope_w + col_cliff * cliff_w;

	float n_large = fbm2(world_pos.xz * 0.012);
	float n_med   = fbm2(world_pos.xz * 0.04 + vec2(50.0, 80.0));
	float brightness = 0.38 + n_large * 0.18 + n_med * 0.10;
	brightness = mix(1.0, brightness, variation_strength);
	albedo *= brightness;

	vec3 warm_shift = vec3(0.03, 0.015, -0.015) * (n_large - 0.5) * variation_strength;
	albedo += warm_shift;

	vec2 terrain_warp = vec2(
		fbm2(world_pos.xz * 0.012 + vec2(137.0, 241.0)),
		fbm2(world_pos.xz * 0.012 + vec2(359.0, 83.0))
	) * 28.0;

	float mud = fbm2((world_pos.xz + terrain_warp) * 0.02 + vec2(200.0, 300.0));
	float mud_mask = smoothstep(0.3, 0.55, mud) * flat_w * variation_strength;
	albedo = mix(albedo, col_slope * 0.75, mud_mask * 0.8);

	float dirt_noise = fbm2((world_pos.xz + terrain_warp) * 0.018 + vec2(500.0, 700.0));
	float dirt_thresh = 0.5 + (0.5 - dirt_patch_amount) * 0.6;
	float dirt_mask = smoothstep(dirt_thresh - 0.06, dirt_thresh + 0.06, dirt_noise) * flat_w;
	albedo = mix(albedo, dirt_color * (0.85 + vnoise(world_pos.xz * 0.3) * 0.15), dirt_mask);

	// Clay paths — use slope_path_fade instead of flat_w to kill zigzags on slopes
	float path_perturb = (vnoise(world_pos.xz * 0.4 + vec2(777.0, 333.0)) - 0.5) * 0.25;
	float pm = smoothstep(0.2, 0.7, v_path_mask + path_perturb) * slope_path_fade;
	vec3 dirt_detail = col_slope * 0.6 + col_flat * 0.15;
	vec3 path_base = path_color * dirt_detail * 4.0;
	path_base *= (0.85 + vnoise(world_pos.xz * 0.12 + vec2(900.0, 400.0)) * 0.2);
	path_base *= (0.9 + fbm2(world_pos.xz * 0.06 + vec2(150.0, 250.0)) * 0.15);
	albedo = mix(albedo, path_base, pm);

	// River bank — use slope_path_fade instead of flat_w to kill zigzags on slopes
	float bank_noise = vnoise(world_pos.xz * 0.15 + vec2(444.0, 222.0));
	float bank_detail = vnoise(world_pos.xz * 0.6 + vec2(111.0, 555.0));
	float bank_mask = smoothstep(0.1, 0.6, v_river_bank + (bank_noise - 0.5) * 0.3);
	vec3 bank_detail_col = col_slope * 0.5 + bank_color * 0.5;
	bank_detail_col *= (0.8 + bank_detail * 0.25);
	albedo = mix(albedo, bank_detail_col, bank_mask * slope_path_fade);

	float ao_mask = smoothstep(0.3, 0.6, n_med) * flat_w * 0.2;
	albedo *= (1.0 - ao_mask);

	float ground_shadow = flat_w * 0.12 * (1.0 - dirt_mask) * (1.0 - pm);
	albedo *= (1.0 - ground_shadow);
	float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	albedo = mix(albedo, vec3(luma), ground_shadow * 0.3);

	// Tint slope textures to match biome — less tinting on steep rock so strata colors show
	albedo *= mix(vec3(1.0), vec3(0.80, 0.82, 0.78), steep_override);

	// Biome tint on flat/slope areas, very subtle on cliffs to preserve strata
	float tint_strength = flat_w + slope_w * 0.50 + cliff_w * 0.15;
	vec3 final_tint = mix(vec3(1.0), tint_color, clamp(tint_strength, 0.0, 1.0));
	ALBEDO = albedo * final_tint * v_brightness;
	float base_rough = mix(0.8, 0.95, mud_mask * 0.5 + ao_mask);
	base_rough = mix(base_rough, 0.65, dirt_mask);
	base_rough = mix(base_rough, bank_roughness, bank_mask * flat_w);
	// Rock has variable roughness — lighter patches smoother, crevices rougher
	float rock_rough_noise = tri_noise(world_pos, blend, 1.2, vec2(444.0, 222.0));
	float rock_rough = 0.72 + rock_rough_noise * 0.22;
	base_rough = mix(base_rough, rock_rough, cliff_w);
	ROUGHNESS = mix(base_rough, path_roughness, pm);
	AO = 1.0 - ao_mask * 2.0;
	AO_LIGHT_AFFECT = 0.5;

	// Procedural bump mapping on rocky surfaces — stronger on cliffs for craggy look
	float rock_strength = slope_w * 0.4 + cliff_w * 0.8;
	if (rock_strength > 0.01) {
		float rn1 = vnoise(world_pos.xz * 2.5 + vec2(311.0, 719.0));
		float rn2 = vnoise(world_pos.xz * 6.0 + vec2(853.0, 127.0));
		float rn3 = vnoise(world_pos.xz * 14.0 + vec2(491.0, 953.0));
		float rock_detail = (rn1 - 0.5) * 0.5 + (rn2 - 0.5) * 0.3 + (rn3 - 0.5) * 0.2;
		NORMAL = normalize(NORMAL + vec3(
			dFdx(rock_detail) * 50.0 * rock_strength,
			0.0,
			dFdy(rock_detail) * 50.0 * rock_strength
		));
	}
}
