shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_prepass_alpha, no_shadow;

uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.4;
uniform vec3 shadow_color : source_color = vec3(0.02, 0.02, 0.05);

void fragment() {
	vec2 centered = (UV - 0.5) * 2.0;
	float dist = length(centered);
	float falloff = 1.0 - smoothstep(0.3, 1.0, dist);
	ALBEDO = shadow_color;
	ALPHA = falloff * shadow_opacity;
}
