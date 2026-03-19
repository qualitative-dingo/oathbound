shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_test_disabled;

uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform vec3 color_a : source_color = vec3(0.5, 0.05, 0.05);
uniform vec3 color_b : source_color = vec3(0.95, 0.15, 0.15);
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float aspect_ratio = 13.0; // width / height — controls roundness
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.45;
uniform float border_softness : hint_range(0.001, 0.1) = 0.025;

float rounded_rect_sdf(vec2 p, vec2 half_size, float radius) {
	vec2 d = abs(p) - half_size + vec2(radius);
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}

void fragment() {
	vec2 uv = UV;

	// Remap to centered coordinates scaled by aspect
	vec2 p = (uv - 0.5) * vec2(aspect_ratio, 1.0);
	float half_w = aspect_ratio * 0.5;
	float half_h = 0.5;
	float corner_r = half_h * 0.85;

	// Outer rounded rect (full bar shape)
	float d_outer = rounded_rect_sdf(p, vec2(half_w, half_h), corner_r);

	// Clip outside the bar shape
	float shape_mask = 1.0 - smoothstep(-border_softness, 0.0, d_outer);
	if (shape_mask < 0.01) discard;

	// Dark background with subtle border
	float border_ring = smoothstep(-border_softness * 3.0, -border_softness * 0.5, d_outer);
	vec3 bg_color = vec3(0.06, 0.06, 0.08);
	vec3 border_color = vec3(0.18, 0.18, 0.22);
	vec3 base = mix(bg_color, border_color, border_ring * 0.6);

	// Fill region: left-to-right based on fill_ratio
	float fill_edge = mix(-half_w, half_w, fill_ratio);
	float fill_mask = smoothstep(fill_edge + 0.08, fill_edge - 0.08, p.x);

	// Gradient along the filled portion (left=dark, right=bright)
	float t = clamp((p.x + half_w) / (aspect_ratio), 0.0, 1.0);
	vec3 fill_color = mix(color_a, color_b, t);

	// Brighter core along the center for a glassy/volumetric look
	float center_highlight = 1.0 - abs(p.y) / half_h;
	center_highlight = pow(center_highlight, 2.0) * 0.35;
	fill_color += center_highlight * color_b;

	// Glow rim along the fill edge
	float edge_dist = abs(p.x - fill_edge);
	float edge_glow = exp(-edge_dist * 3.0) * glow_intensity * fill_ratio;
	fill_color += edge_glow * color_b;

	// Outer glow (soft bloom around filled region)
	float outer_glow = smoothstep(0.0, border_softness * 4.0, -d_outer);
	float glow_fill = fill_mask * outer_glow * glow_intensity * 0.3;

	// Damage/use pulse: flash white
	vec3 pulse_color = mix(fill_color, vec3(1.0, 1.0, 1.0), pulse * 0.7);
	vec3 final_fill = mix(fill_color, pulse_color, pulse);

	// Composite: background + filled portion
	vec3 final_color = mix(base, final_fill, fill_mask);
	final_color += glow_fill * color_b;

	float final_alpha = shape_mask * 0.92;

	ALBEDO = final_color;
	ALPHA = final_alpha;
}
