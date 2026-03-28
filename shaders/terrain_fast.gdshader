shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert_wrap;

group_uniforms textures;
uniform sampler2D tex_flat  : filter_nearest_mipmap, repeat_enable;
uniform sampler2D tex_slope : filter_nearest_mipmap, repeat_enable;
uniform sampler2D tex_cliff : filter_nearest_mipmap, repeat_enable;

group_uniforms settings;
uniform float texture_scale : hint_range(0.01, 4.0) = 0.5;
uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float slope_start : hint_range(0.0, 1.0) = 0.08;
uniform float cliff_start : hint_range(0.0, 1.0) = 0.30;

uniform vec3 origin_shift;
uniform vec3 path_color : source_color = vec3(0.18, 0.11, 0.05);
uniform vec3 bank_color : source_color = vec3(0.12, 0.09, 0.05);

varying float v_path_mask;
varying float v_brightness;
varying float v_river_bank;

void vertex() {
	v_path_mask = COLOR.r;
	v_brightness = COLOR.g;
	v_river_bank = COLOR.b;
}

float hash_fast(vec2 p) {
	float h = dot(p, vec2(127.1, 311.7));
	return fract(sin(h) * 43758.5453);
}

float vnoise_fast(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash_fast(i), hash_fast(i + vec2(1.0, 0.0)), f.x),
		mix(hash_fast(i + vec2(0.0, 1.0)), hash_fast(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - abs(world_normal.y);
	float slope_noise = (vnoise_fast(wpos.xz * 0.15 + vec2(53.0, 97.0)) - 0.5) * 0.14
	                   + (vnoise_fast(wpos.xz * 0.07 + vec2(731.0, 419.0)) - 0.5) * 0.10;
	float warp_n = vnoise_fast(wpos.xz * 0.018 + vec2(430.0, 170.0));
	float patch_n = vnoise_fast(wpos.xz * 0.022 + vec2(90.0, 260.0) + vec2(warp_n) * 45.0);
	slope_noise += (patch_n - 0.5) * 0.16;
	// Two-zone: grass → rock — wide transition for organic blending
	float rock_w = smoothstep(slope_start, slope_start + 0.14, slope + slope_noise);

	float pm = smoothstep(0.2, 0.7, v_path_mask);
	float bm = smoothstep(0.1, 0.6, v_river_bank);
	float creek_mask = smoothstep(0.45, 0.85, v_river_bank);

	vec3 grass_col = vec3(0.10, 0.28, 0.07) * tint_color;

	// Cohesive rock — patches in albedo, no high-freq grain
	vec3 bl = abs(world_normal);
	bl = bl * bl * bl * bl;
	bl /= (bl.x + bl.y + bl.z + 0.0001);

	vec3 rock_col = vec3(0.26, 0.27, 0.30);

	// Regional bias — whole mountains lighter or darker
	float reg_x = vnoise_fast(wpos.zy * 0.002 + vec2(1337.0, 42.0));
	float reg_y = vnoise_fast(wpos.xz * 0.002 + vec2(1410.0, 191.0));
	float region = reg_x * bl.x + reg_y * (bl.y + bl.z);
	rock_col += vec3(region - 0.5) * 0.16;

	// Broad tonal shift
	float broad_x = vnoise_fast(wpos.zy * 0.005 + vec2(90.0, 260.0));
	float broad_y = vnoise_fast(wpos.xz * 0.005 + vec2(163.0, 409.0));
	float broad = broad_x * bl.x + broad_y * (bl.y + bl.z);
	rock_col += vec3(broad - 0.5) * 0.14;

	// Medium patches — main pattern
	float med_x = vnoise_fast(wpos.zy * 0.02 + vec2(444.0, 888.0));
	float med_y = vnoise_fast(wpos.xz * 0.02 + vec2(517.0, 1037.0));
	float med = med_x * bl.x + med_y * (bl.y + bl.z);
	rock_col += vec3(med - 0.5) * 0.20;

	// Low-frequency grain only
	float grain_lo = vnoise_fast(wpos.xz * 0.15 + vec2(200.0, 400.0));
	rock_col *= 0.88 + grain_lo * 0.24;

	vec3 ground = mix(grass_col * tint_color, rock_col, rock_w) * v_brightness;
	ground = mix(ground, bank_color, bm * (1.0 - rock_w));
	// Creek flow — scrolling caustic shimmer on wet areas
	if (creek_mask > 0.01) {
		float ft = TIME * 0.6;
		float caustic = vnoise_fast(wpos.xz * 0.8 + vec2(ft * 0.7, ft));
		float shimmer = smoothstep(0.35, 0.65, caustic) * 0.2;
		ground = mix(ground, vec3(0.06, 0.10, 0.08) + shimmer, creek_mask * (1.0 - rock_w) * 0.6);
	}
	ALBEDO = mix(ground, path_color, pm * (1.0 - rock_w));
	float base_rough = mix(mix(0.85, 0.85, rock_w), 0.7, pm * (1.0 - rock_w));
	base_rough = mix(base_rough, 0.18, creek_mask * (1.0 - rock_w));
	ROUGHNESS = base_rough;
	METALLIC = creek_mask * (1.0 - rock_w) * 0.1;
}
