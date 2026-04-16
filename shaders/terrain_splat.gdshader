shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap;

// ── Splatmap spike shader ──────────────────────────────────────────────────
// Same vertex streams as terrain.gdshader:
//   COLOR.r = path mask
//   COLOR.g = macro slope magnitude (unused here; slope is reconstructed from UV2)
//   COLOR.b = river bank mask
//   COLOR.a = beach mask
//   UV2     = macro gradient (gx, gz) — reconstructs a zone-continuous normal
//
// Weights (grass / grass_detail / dirt / rock / sand) are computed from slope,
// height, and world-space noise — no hard thresholds, no mesh-edge banding.

group_uniforms textures;
uniform sampler2D tex_grass        : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass_detail : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt         : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock         : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_sand         : source_color, filter_linear_mipmap, repeat_enable;

group_uniforms scales;
uniform float grass_scale  : hint_range(0.02, 4.0) = 0.45;
uniform float detail_scale : hint_range(0.02, 4.0) = 0.12;
uniform float dirt_scale   : hint_range(0.02, 4.0) = 0.40;
uniform float rock_scale   : hint_range(0.02, 2.0) = 0.18;
uniform float sand_scale   : hint_range(0.02, 4.0) = 1.20;

group_uniforms tint;
uniform vec3 grass_tint : source_color = vec3(0.82, 0.92, 0.70);
uniform vec3 dirt_tint  : source_color = vec3(0.90, 0.82, 0.68);
uniform vec3 rock_tint  : source_color = vec3(0.90, 0.90, 0.90);
uniform vec3 sand_tint  : source_color = vec3(1.00, 0.96, 0.82);
uniform vec3 path_tint  : source_color = vec3(0.38, 0.28, 0.18);
uniform vec3 bank_tint  : source_color = vec3(0.42, 0.32, 0.22);

group_uniforms blending;
uniform float slope_midpoint : hint_range(0.0, 1.0) = 0.35;
uniform float slope_softness : hint_range(0.01, 0.8) = 0.30;
uniform float rock_altitude  : hint_range(0.0, 80.0) = 18.0;
uniform float rock_altitude_softness : hint_range(1.0, 40.0) = 14.0;
uniform float detail_mix     : hint_range(0.0, 1.0) = 0.55;
uniform float rock_bump_strength : hint_range(0.0, 4.0) = 1.6;

group_uniforms roughness;
uniform float grass_rough : hint_range(0.0, 1.0) = 0.92;
uniform float dirt_rough  : hint_range(0.0, 1.0) = 0.96;
uniform float rock_rough  : hint_range(0.0, 1.0) = 0.78;
uniform float sand_rough  : hint_range(0.0, 1.0) = 0.88;

uniform vec3 origin_shift;

varying vec3 v_world_pos;
varying vec3 v_macro_normal;
varying float v_path;
varying float v_bank;
varying float v_beach;

// ── Noise helpers ──────────────────────────────────────────────────────────
float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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
	float v = vnoise(p) * 0.55;
	v += vnoise(p * 2.1 + vec2(100.0)) * 0.30;
	v += vnoise(p * 4.3 + vec2(310.0)) * 0.15;
	return v;
}

// ── Triplanar sampling with tile-break variation ───────────────────────────
vec3 triplanar(sampler2D tex, vec3 wpos, vec3 blend, float scale) {
	vec2 uv_x = wpos.zy * scale;
	vec2 uv_y = wpos.xz * scale;
	vec2 uv_z = wpos.xy * scale;
	vec3 cx = texture(tex, uv_x).rgb;
	vec3 cy = texture(tex, uv_y).rgb;
	vec3 cz = texture(tex, uv_z).rgb;
	vec3 c = cx * blend.x + cy * blend.y + cz * blend.z;

	// Break visible tiling by mixing in a rotated / re-scaled sample on top faces
	vec2 uv_break = wpos.xz * scale * 0.41 + vec2(17.0, 31.0);
	vec3 c_break = texture(tex, uv_break).rgb;
	float break_n = vnoise(wpos.xz * 0.06 + vec2(41.0, 67.0));
	c = mix(c, c_break, break_n * 0.35 * blend.y);
	return c;
}

// Analytical world-space rock bump so gradients are identical across zones
float rock_bump_at(vec2 xz) {
	float v = (vnoise(xz * 0.15 + vec2(311.0, 719.0)) - 0.5) * 0.25
	        + (vnoise(xz * 0.5  + vec2(853.0, 127.0)) - 0.5) * 0.20
	        + (vnoise(xz * 1.4  + vec2(491.0, 953.0)) - 0.5) * 0.16
	        + (vnoise(xz * 4.0  + vec2(137.0, 641.0)) - 0.5) * 0.12;
	return v;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_shift;
	v_path  = COLOR.r;
	v_bank  = COLOR.b;
	v_beach = COLOR.a;
	vec2 mg = UV2;
	v_macro_normal = normalize(vec3(-mg.x, 1.0, -mg.y));
}

void fragment() {
	vec3 wpos = v_world_pos;
	vec3 mn   = v_macro_normal;

	// ── Triplanar blend weights (macro normal, smoother for big landforms) ──
	vec3 blend = pow(abs(mn), vec3(5.0));
	blend /= (blend.x + blend.y + blend.z + 0.0001);

	// ── Continuous slope value (0 = flat, 1 = vertical) ────────────────────
	float slope = clamp(1.0 - mn.y, 0.0, 1.0);

	// Noise warp on the slope so rock/grass boundary follows terrain noise,
	// not triangle tessellation. Very cheap.
	float warp_n = fbm2(wpos.xz * 0.025 + vec2(430.0, 170.0));
	float slope_warped = clamp(slope + (warp_n - 0.5) * 0.22, 0.0, 1.0);

	// Altitude gate: rock appears more readily above rock_altitude
	float alt_gate = smoothstep(
		rock_altitude - rock_altitude_softness,
		rock_altitude + rock_altitude_softness,
		wpos.y
	);

	// Combined rock weight: slope OR (high altitude AND some slope)
	float rock_from_slope = smoothstep(
		slope_midpoint - slope_softness,
		slope_midpoint + slope_softness,
		slope_warped
	);
	float rock_w = max(rock_from_slope, alt_gate * smoothstep(0.18, 0.45, slope_warped));

	// Dirt sits in the grass→rock transition band (max ~0.5 at the midpoint)
	float grass_w = 1.0 - rock_w;
	float dirt_w = grass_w * rock_w * 4.0;
	dirt_w = clamp(dirt_w, 0.0, 1.0);

	// ── Sample all four terrain textures ──────────────────────────────────
	vec3 grass_a = triplanar(tex_grass,        wpos, blend, grass_scale)  * grass_tint;
	vec3 grass_b = triplanar(tex_grass_detail, wpos, blend, detail_scale) * grass_tint;
	float grass_noise = fbm2(wpos.xz * 0.05 + vec2(910.0, 430.0));
	vec3 grass_col = mix(grass_a, grass_b, smoothstep(0.35, 0.65, grass_noise) * detail_mix);

	vec3 dirt_col = triplanar(tex_dirt, wpos, blend, dirt_scale) * dirt_tint;
	vec3 rock_col = triplanar(tex_rock, wpos, blend, rock_scale) * rock_tint;
	vec3 sand_col = triplanar(tex_sand, wpos, blend, sand_scale) * sand_tint;

	// Height-based rock shading — darker mossy base, lighter peaks
	float height_t = smoothstep(8.0, 80.0, wpos.y);
	rock_col *= mix(0.78, 1.05, height_t);

	// Subtle moss tint on upward-facing rock below tree line
	float moss_n = vnoise(wpos.xz * 0.09 + vec2(350.0, 720.0));
	float moss_face = smoothstep(0.35, 0.75, mn.y);
	float moss_alt  = 1.0 - smoothstep(45.0, 80.0, wpos.y);
	float moss_mask = moss_face * moss_alt * smoothstep(0.35, 0.7, moss_n);
	rock_col = mix(rock_col, rock_col * vec3(0.55, 0.85, 0.45) + vec3(0.03, 0.06, 0.02), moss_mask * 0.35);

	// ── Combine grass + dirt edge + rock ──────────────────────────────────
	vec3 albedo = mix(grass_col, rock_col, rock_w);
	albedo = mix(albedo, dirt_col, dirt_w * 0.55);

	// ── Path (baked into COLOR.r) ─────────────────────────────────────────
	float path_perturb = (vnoise(wpos.xz * 0.35 + vec2(777.0, 333.0)) - 0.5) * 0.25;
	float pm = smoothstep(0.20, 0.70, v_path + path_perturb) * grass_w;
	vec3 path_col = mix(dirt_col * 0.65, path_tint, 0.4);
	path_col *= (0.9 + vnoise(wpos.xz * 0.12 + vec2(900.0, 400.0)) * 0.2);
	albedo = mix(albedo, path_col, pm);

	// ── River bank ────────────────────────────────────────────────────────
	float bank_n = vnoise(wpos.xz * 0.15 + vec2(444.0, 222.0));
	float bank_mask = smoothstep(0.10, 0.60, v_bank + (bank_n - 0.5) * 0.3) * grass_w;
	vec3 bank_col = mix(dirt_col * 0.55, bank_tint, 0.5);
	albedo = mix(albedo, bank_col, bank_mask * 0.8);

	// ── Beach (ocean coast only; COLOR.a) ─────────────────────────────────
	float beach_warp = vnoise(wpos.xz * 0.06 + vec2(320.0, 610.0));
	float beach_mask = smoothstep(0.10, 0.55, v_beach + (beach_warp - 0.5) * 0.25) * grass_w;
	albedo = mix(albedo, sand_col, beach_mask);

	// ── Global micro-variation (world-space; zero zone-seam risk) ─────────
	float micro = vnoise(wpos.xz * 0.04 + vec2(9000.0, 9000.0));
	albedo *= (0.93 + micro * 0.14);

	ALBEDO = albedo;

	// ── Roughness ─────────────────────────────────────────────────────────
	float rough = mix(grass_rough, rock_rough, rock_w);
	rough = mix(rough, dirt_rough, dirt_w * 0.5);
	rough = mix(rough, sand_rough, beach_mask);
	rough = mix(rough, 0.95, pm);
	ROUGHNESS = rough;

	SPECULAR = 0.35;
	METALLIC = 0.0;
	AO_LIGHT_AFFECT = 0.5;

	// ── Rock normal bump — analytical world-space central differences ─────
	if (rock_w > 0.01) {
		float eps = 0.2;
		float rb_px = rock_bump_at(wpos.xz + vec2(eps, 0.0));
		float rb_nx = rock_bump_at(wpos.xz - vec2(eps, 0.0));
		float rb_pz = rock_bump_at(wpos.xz + vec2(0.0, eps));
		float rb_nz = rock_bump_at(wpos.xz - vec2(0.0, eps));
		float inv_eps2 = 1.0 / (2.0 * eps);
		float gx = (rb_px - rb_nx) * inv_eps2;
		float gz = (rb_pz - rb_nz) * inv_eps2;

		float view_dist = length(VERTEX);
		float lod = 1.0 - smoothstep(40.0, 140.0, view_dist);
		float str = rock_bump_strength * rock_w * lod;
		NORMAL = normalize(NORMAL + vec3(gx * str, 0.0, gz * str));
	}
}
