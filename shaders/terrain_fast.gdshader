shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap;

group_uniforms textures;
uniform sampler2D tex_flat  : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_slope : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_cliff : filter_linear_mipmap, repeat_enable;

group_uniforms settings;
uniform float texture_scale : hint_range(0.01, 4.0) = 0.5;
uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float slope_start : hint_range(0.0, 1.0) = 0.08;
uniform float cliff_start : hint_range(0.0, 1.0) = 0.30;

uniform vec3 origin_shift;
uniform vec3 path_color : source_color = vec3(0.18, 0.11, 0.05);
uniform vec3 bank_color : source_color = vec3(0.12, 0.09, 0.05);

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
	vec3 wpos = v_world_pos;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - abs(world_normal.y);

	// Noise-driven rock pattern (world-space, independent of mesh normals)
	float warp_n = vnoise_fast(wpos.xz * 0.012 + vec2(430.0, 170.0));
	float rock_pattern = vnoise_fast(wpos.xz * 0.015 + vec2(90.0, 260.0) + vec2(warp_n) * 60.0) * 0.6
	                   + vnoise_fast(wpos.xz * 0.05 + vec2(731.0, 419.0)) * 0.3
	                   + vnoise_fast(wpos.xz * 0.15 + vec2(53.0, 97.0)) * 0.1;
	float noise_rock = smoothstep(0.40, 0.60, rock_pattern);

	// Perturb slope with world-space noise so gate boundaries follow noise, not triangle edges
	float gate_perturb = (rock_pattern - 0.5) * 0.25;
	float slope_g = slope + gate_perturb * 0.35;
	float slope_r = slope + gate_perturb;
	float definitely_grass = smoothstep(slope_start + 0.05, max(slope_start - 0.03, 0.0), slope_g);
	float definitely_rock  = smoothstep(slope_start + 0.20, slope_start + 0.55, slope_r);

	// In the transition zone, noise determines grass vs rock
	float rock_w = mix(noise_rock, 1.0, definitely_rock);
	rock_w *= (1.0 - definitely_grass);

	float pm = smoothstep(0.2, 0.7, v_path_mask);
	float bm = smoothstep(0.1, 0.6, v_river_bank);

	vec3 grass_col = vec3(0.10, 0.28, 0.07) * tint_color;

	// Cohesive rock — patches in albedo, no high-freq grain
	vec3 bl = abs(world_normal);
	bl = bl * bl * bl * bl;
	bl /= (bl.x + bl.y + bl.z + 0.0001);

	// Height-based base tone: mossy-dark at base, neutral mid, lighter peaks
	float height_t = smoothstep(10.0, 80.0, wpos.y);
	vec3 rock_col = mix(vec3(0.22, 0.24, 0.20), vec3(0.26, 0.27, 0.30), height_t);
	rock_col = mix(rock_col, vec3(0.35, 0.36, 0.38), smoothstep(60.0, 120.0, wpos.y));

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

	// Moss/lichen on upward-facing rock (fades at altitude)
	float upface = smoothstep(0.4, 0.7, world_normal.y) * rock_w;
	float moss_n = vnoise_fast(wpos.xz * 0.08 + vec2(600.0, 200.0));
	float moss = upface * smoothstep(0.3, 0.6, moss_n) * 0.3;
	moss *= 1.0 - smoothstep(50.0, 90.0, wpos.y);
	rock_col = mix(rock_col, vec3(0.15, 0.22, 0.10), moss);

	vec3 ground = mix(grass_col * tint_color, rock_col, rock_w) * v_brightness;
	ground = mix(ground, bank_color, bm * (1.0 - rock_w));
	ALBEDO = mix(ground, path_color, pm * (1.0 - rock_w));
	ROUGHNESS = mix(mix(0.85, 0.85, rock_w), 0.7, pm * (1.0 - rock_w));
}
