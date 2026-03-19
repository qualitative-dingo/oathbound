shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform vec4 albedo_color : source_color = vec4(0.25, 0.55, 0.15, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.4;
uniform float wind_strength : hint_range(0.0, 4.0) = 0.5;
uniform float wind_speed : hint_range(0.0, 8.0) = 1.5;
uniform float wind_turbulence : hint_range(0.0, 5.0) = 0.8;
global uniform float leaf_wind_multiplier;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Wind only affects top of grass (UV.y = 0 is top, UV.y = 1 is base)
	float height_factor = 1.0 - UV.y;
	height_factor *= height_factor;

	float wm = leaf_wind_multiplier;
	float t = TIME * wind_speed * mix(0.6, 1.0, wm);

	// Broad rolling waves across the field
	float wave_x = sin(world_pos.x * 0.4 + t * 0.7) * 0.5
	             + sin(world_pos.x * 1.1 + world_pos.z * 0.7 + t) * 0.3;
	float wave_z = cos(world_pos.z * 0.35 + t * 0.6) * 0.4
	             + sin(world_pos.z * 0.9 + world_pos.x * 0.5 + t * 0.8) * 0.25;

	// Small flutter for variation
	float flutter_x = sin(world_pos.x * 3.0 + world_pos.z * 1.5 + t * 3.5) * 0.15;
	float flutter_z = cos(world_pos.z * 2.8 + world_pos.x * 1.3 + t * 3.0) * 0.12;

	// Rolling gust
	float gust = sin(world_pos.x * 0.12 + world_pos.z * 0.08 + t * 0.25) * 0.5 + 0.5;
	gust = gust * gust * wind_turbulence;

	float sway = wind_strength * wm * height_factor * (1.0 + gust * 0.5);

	VERTEX.x += (wave_x + flutter_x * wm) * sway;
	VERTEX.z += (wave_z + flutter_z * wm) * sway * 0.7;
}

void fragment() {
	// Force normals upward so all faces catch sunlight uniformly
	NORMAL = vec3(0.0, 1.0, 0.0);

	vec4 tex = texture(albedo_texture, UV);

	float ground_ao = mix(0.88, 1.0, 1.0 - UV.y);
	ALBEDO = tex.rgb * albedo_color.rgb * ground_ao;
	ROUGHNESS = roughness;
	ALPHA = tex.a * albedo_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
