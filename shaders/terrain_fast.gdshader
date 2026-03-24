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
uniform vec3 path_color : source_color = vec3(0.22, 0.14, 0.07);

varying float v_path_mask;
varying float v_brightness;

void vertex() {
	v_path_mask = COLOR.r;
	v_brightness = COLOR.g;
}

void fragment() {
	float pm = smoothstep(0.2, 0.7, v_path_mask);
	vec3 ground = vec3(0.10, 0.28, 0.07) * tint_color * v_brightness;
	ALBEDO = mix(ground, path_color, pm);
	ROUGHNESS = mix(0.85, 0.7, pm);
}
