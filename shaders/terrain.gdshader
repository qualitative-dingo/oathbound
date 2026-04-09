shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap;

group_uniforms textures;
uniform sampler2D tex_flat  : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_slope : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_cliff : filter_linear_mipmap, repeat_enable;

group_uniforms settings;
uniform float texture_scale : hint_range(0.01, 4.0) = 0.5;
uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float slope_start : hint_range(0.0, 1.0) = 0.06;
uniform float cliff_start : hint_range(0.0, 1.0) = 0.30;
uniform float min_rock_altitude : hint_range(0.0, 50.0) = 15.0;

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
uniform vec3 rock_color_base : source_color = vec3(0.26, 0.27, 0.30);

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

// Triplanar noise — each axis uses DIFFERENT offsets to prevent wrap-around
float tri_noise(vec3 wpos, vec3 blend, float scale, vec2 off) {
	float nx = vnoise(wpos.zy * scale + off);
	float ny = vnoise(wpos.xz * scale + off + vec2(73.0, 149.0));
	float nz = vnoise(wpos.xy * scale + off + vec2(311.0, 57.0));
	return nx * blend.x + ny * blend.y + nz * blend.z;
}

// Cohesive rock — visible patches in albedo, grit in bump map only
vec3 rock_color(vec3 wpos, vec3 wnorm, float steepness) {
	vec3 bl = abs(wnorm);
	bl = pow(bl, vec3(4.0));
	bl /= (bl.x + bl.y + bl.z + 0.0001);

	// Height-based base tone: mossy-dark at base, neutral mid, lighter peaks
	float height_t = smoothstep(10.0, 80.0, wpos.y);
	vec3 low_rock = vec3(0.22, 0.24, 0.20);
	vec3 mid_rock = rock_color_base;
	vec3 peak_rock = vec3(0.35, 0.36, 0.38);
	vec3 col = mix(low_rock, mid_rock, height_t);
	col = mix(col, peak_rock, smoothstep(60.0, 120.0, wpos.y));

	// ── Regional bias — shifts whole mountains lighter or darker ──
	float region = tri_noise(wpos, bl, 0.002, vec2(1337.0, 42.0));
	col += vec3(region - 0.5) * 0.16;

	// ── Layer 1: broad tonal shift — whole mountain faces ──
	float broad = tri_noise(wpos, bl, 0.005, vec2(90.0, 260.0));
	col += vec3(broad - 0.5) * 0.14;

	// ── Layer 2: medium patches (domain-warped) — the main visible pattern ──
	float warp = tri_noise(wpos, bl, 0.008, vec2(430.0, 170.0));
	vec3 warped = wpos + vec3(warp - 0.5) * 22.0;
	float med = tri_noise(warped, bl, 0.02, vec2(444.0, 888.0));
	col += vec3(med - 0.5) * 0.20;

	// ── Layer 3: detail patches ──
	float small_d = tri_noise(wpos, bl, 0.05, vec2(777.0, 333.0));
	col += vec3(small_d - 0.5) * 0.10;

	// ── Low-frequency color grain only (no high-freq aliasing) ──
	float grain_lo = tri_noise(wpos, bl, 0.15, vec2(200.0, 400.0));
	col *= 0.88 + grain_lo * 0.24;

	// ── Crack veins — thin bright fracture lines ──
	float crack_n = tri_noise(wpos, bl, 0.07, vec2(919.0, 137.0));
	float vein = 1.0 - pow(abs(crack_n * 2.0 - 1.0), 0.35);
	float luma = (col.r + col.g + col.b) * 0.333;
	float dark_fac = 1.0 - clamp(luma / 0.3, 0.0, 1.0);
	col += vec3(0.07, 0.07, 0.06) * vein * dark_fac;

	// ── Moss/lichen on upward-facing rock surfaces ──
	float upface = smoothstep(0.4, 0.7, wnorm.y);
	float moss_noise = vnoise(wpos.xz * 0.08 + vec2(600.0, 200.0));
	float moss_detail = vnoise(wpos.xz * 0.3 + vec2(150.0, 830.0));
	float moss = upface * smoothstep(0.3, 0.6, moss_noise) * 0.3;
	moss *= (0.7 + moss_detail * 0.6);
	// Moss fades at high altitude (too cold/exposed)
	moss *= 1.0 - smoothstep(50.0, 90.0, wpos.y);
	col = mix(col, vec3(0.15, 0.22, 0.10), moss);

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
varying vec3 v_macro_normal;
varying float v_river_bank;

// Analytical rock bump — deterministic function of world XZ, so the gradient
// is identical regardless of which zone mesh draws the fragment.
float rock_bump_at(vec2 xz) {
	float base = (vnoise(xz * 0.12 + vec2(311.0, 719.0)) - 0.5) * 0.22
	           + (vnoise(xz * 0.4  + vec2(853.0, 127.0)) - 0.5) * 0.20
	           + (vnoise(xz * 1.2  + vec2(491.0, 953.0)) - 0.5) * 0.18
	           + (vnoise(xz * 3.5  + vec2(137.0, 641.0)) - 0.5) * 0.15
	           + (vnoise(xz * 9.0  + vec2(557.0, 283.0)) - 0.5) * 0.13
	           + (vnoise(xz * 22.0 + vec2(731.0, 419.0)) - 0.5) * 0.08;
	float crack = vnoise(xz * 0.07 + vec2(919.0, 137.0));
	float vein = 1.0 - pow(abs(crack * 2.0 - 1.0), 0.35);
	return base + vein * 0.04;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
	v_path_mask = COLOR.r;
	vec2 mg = UV2;
	v_macro_normal = normalize(vec3(-mg.x, 1.0, -mg.y));
	v_river_bank = COLOR.b;
}

void fragment() {
	vec3 world_pos = v_world_pos;
	float slope = 1.0 - v_macro_normal.y;

	// Noise-driven rock pattern (world-space, independent of mesh normals)
	vec2 warp_a = vec2(
		fbm2(world_pos.xz * 0.012 + vec2(430.0, 170.0)),
		fbm2(world_pos.xz * 0.012 + vec2(810.0, 560.0))
	) * 60.0;
	float rock_pattern = fbm2((world_pos.xz + warp_a) * 0.015 + vec2(90.0, 260.0)) * 0.6
	                   + vnoise(world_pos.xz * 0.05 + vec2(731.0, 419.0)) * 0.3
	                   + vnoise(world_pos.xz * 0.15 + vec2(53.0, 97.0)) * 0.1;
	float noise_rock = smoothstep(0.40, 0.60, rock_pattern);

	// Perturb slope with world-space noise so gate boundaries follow noise, not zone edges
	float gate_perturb = (rock_pattern - 0.5) * 0.45;
	float slope_g = slope + gate_perturb * 0.55;
	float slope_r = slope + gate_perturb * 1.3;
	float definitely_grass = smoothstep(slope_start + 0.12, max(slope_start - 0.06, 0.0), slope_g);
	float definitely_rock  = smoothstep(slope_start + 0.30, slope_start + 0.65, slope_r);

	// In the transition zone, noise determines grass vs rock
	float rock_w = mix(noise_rock, 1.0, definitely_rock);
	rock_w *= (1.0 - definitely_grass);
	float altitude_gate = smoothstep(min_rock_altitude - 5.0, min_rock_altitude + 10.0, world_pos.y);
	altitude_gate = max(altitude_gate, smoothstep(0.5, 0.7, slope));
	altitude_gate = max(altitude_gate, v_river_bank * 0.5);
	rock_w *= altitude_gate;
	float grass_w = 1.0 - rock_w;

	// Derive all visual slope signals from noise-driven rock_w to avoid triangle edges
	float slope_path_fade = grass_w;
	float steep_override = rock_w;
	float blend_power = mix(8.0, 6.0, rock_w);
	vec3 blend = abs(v_macro_normal);
	blend = pow(blend, vec3(blend_power));
	blend /= (blend.x + blend.y + blend.z + 0.0001);

	vec3 col_flat  = triplanar(tex_flat,  world_pos, blend, texture_scale);

	// Valheim-style patchy rock — used for ALL non-grass terrain
	vec3 col_rock = rock_color(world_pos, v_macro_normal, steep_override);

	// Dirt edge where grass meets rock (muddy transition at boundaries)
	vec3 col_slope = triplanar(tex_slope, world_pos, blend, texture_scale);
	float edge_band = grass_w * rock_w * 4.0;
	vec3 edge_dirt = mix(col_slope * 0.6, col_rock, 0.5);

	// Moss in the transition band — patchy green growth where grass meets rock
	float edge_moss_noise = vnoise(world_pos.xz * 0.12 + vec2(350.0, 720.0));
	float edge_moss = edge_band * smoothstep(0.35, 0.65, edge_moss_noise);
	edge_dirt = mix(edge_dirt, vec3(0.14, 0.20, 0.08), edge_moss * 0.5);

	// Subtle grass scatter at the very edge of flat areas
	float scatter = vnoise(world_pos.xz * 0.35 + vec2(610.0, 390.0));
	float scatter_mask = smoothstep(0.62, 0.80, scatter) * grass_w * 0.15;

	vec3 albedo = col_flat * (grass_w + scatter_mask) + col_rock * (rock_w - scatter_mask);
	// Blend in the dirt edge for a natural grass-to-rock transition
	albedo = mix(albedo, edge_dirt, edge_band * 0.6);

	// Keep cliff_w for post-processing gates (skip brightness/tint on rock)
	float cliff_w = rock_w;

	float n_large = fbm2(world_pos.xz * 0.012);
	float n_med   = fbm2(world_pos.xz * 0.04 + vec2(50.0, 80.0));
	float brightness = 0.38 + n_large * 0.18 + n_med * 0.10;
	brightness = mix(1.0, brightness, variation_strength);
	// Only apply brightness variation to non-cliff areas — rock_color handles its own
	float brightness_applied = mix(brightness, 1.0, cliff_w);
	albedo *= brightness_applied;

	vec3 warm_shift = vec3(0.03, 0.015, -0.015) * (n_large - 0.5) * variation_strength * (1.0 - cliff_w);
	albedo += warm_shift;

	vec2 terrain_warp = vec2(
		fbm2(world_pos.xz * 0.012 + vec2(137.0, 241.0)),
		fbm2(world_pos.xz * 0.012 + vec2(359.0, 83.0))
	) * 28.0;

	float mud = fbm2((world_pos.xz + terrain_warp) * 0.02 + vec2(200.0, 300.0));
	float mud_mask = smoothstep(0.3, 0.55, mud) * grass_w * variation_strength;
	albedo = mix(albedo, col_slope * 0.75, mud_mask * 0.8);

	float dirt_noise = fbm2((world_pos.xz + terrain_warp) * 0.018 + vec2(500.0, 700.0));
	float dirt_thresh = 0.5 + (0.5 - dirt_patch_amount) * 0.6;
	float dirt_mask = smoothstep(dirt_thresh - 0.06, dirt_thresh + 0.06, dirt_noise) * grass_w;
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

	float ao_mask = smoothstep(0.3, 0.6, n_med) * grass_w * 0.2;
	albedo *= (1.0 - ao_mask);

	float ground_shadow = grass_w * 0.12 * (1.0 - dirt_mask) * (1.0 - pm);
	albedo *= (1.0 - ground_shadow);
	float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	albedo = mix(albedo, vec3(luma), ground_shadow * 0.3);

	// Biome tint on grass only — rock stays untinted
	float tint_strength = grass_w;
	vec3 final_tint = mix(vec3(1.0), tint_color, clamp(tint_strength, 0.0, 1.0));
	// Micro-variation computed from world-space noise (replaces per-vertex brightness
	// which caused C0-continuous gradient discontinuities at zone boundaries).
	float micro_n = vnoise(world_pos.xz * 0.06 + vec2(9000.0, 9000.0));
	float vb = 0.92 + (micro_n - 0.5) * 0.24;
	vb = mix(vb, max(vb, 0.92), cliff_w);
	ALBEDO = albedo * final_tint * vb;
	float base_rough = mix(0.8, 0.95, mud_mask * 0.5 + ao_mask);
	base_rough = mix(base_rough, 0.65, dirt_mask);
	base_rough = mix(base_rough, bank_roughness, bank_mask * grass_w);
	// Rock roughness with subtle variation so it doesn't look like plastic
	float rock_rough_var = vnoise(world_pos.xz * 0.08 + vec2(777.0, 333.0)) * 0.12;
	base_rough = mix(base_rough, 0.78 + rock_rough_var, cliff_w);
	ROUGHNESS = mix(base_rough, path_roughness, pm);
	METALLIC = cliff_w * 0.03;
	AO = 1.0 - ao_mask * 2.0;
	AO_LIGHT_AFFECT = 0.5;

	// Rock bump — analytical world-space central differences (no zone boundary seams)
	if (rock_w > 0.01) {
		float eps = 0.15;
		float rb_px = rock_bump_at(world_pos.xz + vec2(eps, 0.0));
		float rb_nx = rock_bump_at(world_pos.xz - vec2(eps, 0.0));
		float rb_pz = rock_bump_at(world_pos.xz + vec2(0.0, eps));
		float rb_nz = rock_bump_at(world_pos.xz - vec2(0.0, eps));
		float inv_eps2 = 1.0 / (2.0 * eps);
		float grad_x = (rb_px - rb_nx) * inv_eps2;
		float grad_z = (rb_pz - rb_nz) * inv_eps2;

		float view_dist = length(VERTEX);
		float bump_lod = 1.0 - smoothstep(30.0, 120.0, view_dist);
		float bump_str = 3.0 * rock_w * bump_lod;

		NORMAL = normalize(NORMAL + vec3(grad_x * bump_str, 0.0, grad_z * bump_str));
	}
}
