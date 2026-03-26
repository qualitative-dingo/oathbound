shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform float emission_energy : hint_range(0.0, 20.0) = 4.0;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * COLOR.rgb * emission_energy;
	ALPHA = tex.a * COLOR.a;
}
