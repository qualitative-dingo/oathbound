shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap;

uniform sampler2D stone_texture : source_color, filter_nearest;
uniform sampler2D normal_texture : hint_normal, filter_nearest;
uniform vec4 stone_color : source_color = vec4(0.5, 0.48, 0.45, 1.0);
uniform vec4 stone_color_dark : source_color = vec4(0.32, 0.30, 0.28, 1.0);
uniform vec4 moss_color : source_color = vec4(0.18, 0.38, 0.08, 1.0);
uniform float moss_blend_sharpness : hint_range(0.5, 8.0) = 3.0;
uniform float moss_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float moss_noise_scale : hint_range(0.1, 10.0) = 2.5;
uniform float normal_strength : hint_range(0.0, 5.0) = 2.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float ao_strength : hint_range(0.0, 2.0) = 0.6;
uniform float triplanar_scale : hint_range(0.1, 10.0) = 3.0;
uniform float triplanar_sharpness : hint_range(0.1, 8.0) = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Simple hash noise for organic moss breakup
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm_noise(vec2 p) {
	float v = 0.0;
	v += value_noise(p) * 0.5;
	v += value_noise(p * 2.1 + 7.3) * 0.25;
	v += value_noise(p * 4.3 + 13.7) * 0.125;
	return v / 0.875;
}

vec4 triplanar_sample(sampler2D tex, vec3 pos, vec3 normal, float scale) {
	vec3 blend = pow(abs(normal), vec3(triplanar_sharpness));
	blend /= (blend.x + blend.y + blend.z);
	vec4 x = texture(tex, pos.yz * scale);
	vec4 y = texture(tex, pos.xz * scale);
	vec4 z = texture(tex, pos.xy * scale);
	return x * blend.x + y * blend.y + z * blend.z;
}

vec3 triplanar_normal_sample(sampler2D tex, vec3 pos, vec3 normal, float scale) {
	vec3 blend = pow(abs(normal), vec3(triplanar_sharpness));
	blend /= (blend.x + blend.y + blend.z);
	vec3 x = texture(tex, pos.yz * scale).rgb * 2.0 - 1.0;
	vec3 y = texture(tex, pos.xz * scale).rgb * 2.0 - 1.0;
	vec3 z = texture(tex, pos.xy * scale).rgb * 2.0 - 1.0;
	return normalize(x * blend.x + y * blend.y + z * blend.z);
}

void fragment() {
	vec3 wn = normalize(world_normal);
	vec3 wp = world_pos;

	// Triplanar stone texture
	vec4 stone_tex = triplanar_sample(stone_texture, wp, wn, triplanar_scale);

	// Height + noise-based blend between light (tops) and dark (crevices/bottoms)
	float height_blend = smoothstep(-0.4, 0.6, wn.y);
	float color_noise = value_noise(wp.xz * 1.8 + wp.y * 0.7);
	float dark_mix = clamp((1.0 - height_blend) + (1.0 - color_noise) * 0.3, 0.0, 1.0);
	vec3 blended_stone = mix(stone_color.rgb, stone_color_dark.rgb, dark_mix);
	vec3 base_col = stone_tex.rgb * blended_stone;

	// Normal map with triplanar (strong for that crunchy look)
	vec3 norm_sample = triplanar_normal_sample(normal_texture, wp, wn, triplanar_scale);
	NORMAL_MAP = norm_sample * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;

	// Slope-aware moss: blend based on world-space up-facing normal
	float slope = clamp(wn.y, 0.0, 1.0);

	// Noise breakup so moss isn't a clean line
	float moss_noise = fbm_noise(wp.xz * moss_noise_scale);
	float moss_mask = slope - moss_threshold + (moss_noise - 0.5) * 0.35;
	moss_mask = clamp(moss_mask * moss_blend_sharpness, 0.0, 1.0);

	// Moss is slightly textured too — reuse stone tex as detail
	vec3 moss_col = moss_color.rgb * (0.85 + stone_tex.r * 0.3);
	vec3 final_col = mix(base_col, moss_col, moss_mask);

	// Crevice AO: use normal map detail as proxy for depth
	// Darker in valleys (low normal.z / blue channel = recessed areas)
	float ao_raw = norm_sample.z * 0.5 + 0.5;
	float ao = mix(1.0, ao_raw, ao_strength);

	// Additional height-based AO: bottom of rock is darker
	float height_ao = smoothstep(-0.5, 0.3, wn.y) * 0.3 + 0.7;
	ao *= height_ao;

	ALBEDO = final_col * ao;
	ROUGHNESS = mix(roughness, roughness * 0.9, moss_mask);
}
