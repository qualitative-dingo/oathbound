shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.012;
uniform float scroll_speed : hint_range(0.0, 4.0) = 1.5;
uniform float noise_scale : hint_range(0.1, 10.0) = 3.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float fade = smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.5, UV.y);
	fade *= smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x);

	vec2 noise_uv = UV * noise_scale + vec2(0.0, -TIME * scroll_speed);
	float n1 = value_noise(noise_uv);
	float n2 = value_noise(noise_uv * 2.3 + vec2(TIME * 0.7, 0.0));
	vec2 offset = vec2(n1 - 0.5, n2 - 0.5) * distortion_strength * fade;

	vec4 screen_col = texture(screen_texture, SCREEN_UV + offset);
	ALBEDO = screen_col.rgb;
	ALPHA = fade * 0.6;
}
