shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert_wrap;

group_uniforms textures;
uniform sampler2D tex_flat  : filter_nearest_mipmap, repeat_enable;
uniform sampler2D tex_slope : filter_nearest_mipmap, repeat_enable;
uniform sampler2D tex_cliff : filter_nearest_mipmap, repeat_enable;

group_uniforms settings;
uniform float texture_scale : hint_range(0.01, 4.0) = 0.5;
uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float slope_start : hint_range(0.0, 1.0) = 0.25;
uniform float cliff_start : hint_range(0.0, 1.0) = 0.55;

uniform vec3 origin_shift;

void fragment() {
	ALBEDO = vec3(0.3, 0.55, 0.2) * tint_color * COLOR.rgb;
	ROUGHNESS = 0.85;
}
