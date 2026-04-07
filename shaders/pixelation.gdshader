shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.15;
uniform float vignette_softness : hint_range(0.1, 2.0) = 0.7;

void fragment() {
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;

	// Subtle vignette only — no pixelation, no grain, no banding
	vec2 center_dist = SCREEN_UV - 0.5;
	float vignette = smoothstep(vignette_softness, vignette_softness * 0.4, length(center_dist));
	col *= mix(1.0 - vignette_strength, 1.0, vignette);

	COLOR = vec4(col, 1.0);
}
