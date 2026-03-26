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
	float slope_noise = (vnoise_fast(wpos.xz * 0.12 + vec2(53.0, 97.0)) - 0.5) * 0.08;
	float cliff_w = smoothstep(cliff_start, cliff_start + 0.18, slope + slope_noise);

	float pm = smoothstep(0.2, 0.7, v_path_mask);
	float bm = smoothstep(0.1, 0.6, v_river_bank);

	vec3 grass_col = vec3(0.10, 0.28, 0.07) * tint_color;

	// Simplified patchy rock for distant terrain — triplanar sampling
	vec3 blend_r = abs(world_normal);
	blend_r = blend_r * blend_r;
	blend_r /= (blend_r.x + blend_r.y + blend_r.z + 0.0001);

	// Patchy light/dark blobs
	float n_xz = vnoise_fast(wpos.xz * 0.03 + vec2(90.0, 260.0));
	float n_xy = vnoise_fast(wpos.xy * 0.03 + vec2(90.0, 260.0));
	float n_zy = vnoise_fast(wpos.zy * 0.03 + vec2(90.0, 260.0));
	float patch = n_xz * blend_r.y + n_xy * blend_r.z + n_zy * blend_r.x;
	float patch_mask = smoothstep(0.35, 0.65, patch);

	// Vertical flow streaks on cliffs
	float flow_xy = vnoise_fast(wpos.xy * vec2(0.15, 0.06) + vec2(111.0, 222.0));
	float flow_zy = vnoise_fast(wpos.zy * vec2(0.15, 0.06) + vec2(444.0, 555.0));
	float flow = flow_xy * blend_r.z + flow_zy * blend_r.x + 0.5 * blend_r.y;

	vec3 rock_dark = vec3(0.15, 0.14, 0.13);
	vec3 rock_light = vec3(0.58, 0.56, 0.53);
	vec3 rock_col = mix(rock_dark, rock_light, patch_mask);
	rock_col = mix(rock_col, rock_dark * 0.85, (1.0 - flow) * 0.3 * cliff_w);

	float grain = vnoise_fast(wpos.xz * 1.5 + vec2(200.0, 400.0));
	rock_col *= 0.88 + grain * 0.18;

	vec3 ground = mix(grass_col, rock_col, cliff_w) * v_brightness;
	ground = mix(ground, bank_color, bm);
	ALBEDO = mix(ground, path_color, pm);
	float strata_rough = 0.78 + grain * 0.15;
	ROUGHNESS = mix(mix(mix(0.85, strata_rough, cliff_w), 0.95, bm), 0.7, pm);
}
