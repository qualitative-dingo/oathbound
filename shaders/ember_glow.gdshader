shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 color_hot : source_color = vec4(1.0, 0.55, 0.05, 1.0);
uniform vec4 color_cool : source_color = vec4(0.4, 0.08, 0.0, 1.0);
uniform float pulse_speed : hint_range(0.1, 4.0) = 1.2;
uniform float noise_scale : hint_range(1.0, 20.0) = 6.0;
uniform float brightness : hint_range(0.0, 8.0) = 3.0;
uniform float edge_fade : hint_range(0.1, 1.0) = 0.4;

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
	vec2 uv = UV;

	float n1 = value_noise(uv * noise_scale + vec2(TIME * pulse_speed * 0.3, TIME * pulse_speed * 0.2));
	float n2 = value_noise(uv * noise_scale * 1.7 + vec2(-TIME * pulse_speed * 0.4, TIME * pulse_speed * 0.15));
	float combined = (n1 + n2) * 0.5;

	float hotspot = smoothstep(0.35, 0.7, combined);

	vec2 center = uv - vec2(0.5);
	float dist = length(center) * 2.0;
	float circle_mask = 1.0 - smoothstep(1.0 - edge_fade, 1.0, dist);

	vec3 col = mix(color_cool.rgb, color_hot.rgb, hotspot);

	ALBEDO = col * brightness * circle_mask;
	ALPHA = circle_mask * mix(0.4, 1.0, hotspot);
}
