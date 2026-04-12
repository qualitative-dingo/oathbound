shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(0.25, 0.55, 0.15, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.4;
uniform float wind_strength : hint_range(0.0, 4.0) = 0.5;
uniform float wind_speed : hint_range(0.0, 8.0) = 1.5;
uniform float wind_turbulence : hint_range(0.0, 5.0) = 0.8;
uniform int atlas_columns : hint_range(1, 8) = 1;
uniform float density_near : hint_range(0.0, 32.0) = 16.0;
uniform float density_far : hint_range(0.0, 64.0) = 32.0;
uniform float player_push_radius : hint_range(0.0, 4.0) = 1.8;
uniform float player_push_strength : hint_range(0.0, 3.0) = 1.2;
global uniform float leaf_wind_multiplier;
global uniform vec3 player_world_position;

varying vec3 world_pos;
varying flat int tex_index;
varying flat float discard_threshold;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	tex_index = int(INSTANCE_CUSTOM.x * float(atlas_columns) + 0.5);
	tex_index = clamp(tex_index, 0, atlas_columns - 1);

	float instance_rand = fract(INSTANCE_CUSTOM.y * 12345.67 + world_pos.x * 0.123 + world_pos.z * 0.456);
	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float dist_factor = smoothstep(density_near, density_far, cam_dist);
	discard_threshold = mix(1.0, 0.3, dist_factor);

	float scale_factor = mix(1.0, 0.55, dist_factor);
	VERTEX *= scale_factor;

	float height_factor = 1.0 - UV.y;
	height_factor *= height_factor;

	float wm = leaf_wind_multiplier;

	float local_tempo = 0.7 + 0.6 * (sin(world_pos.x * 0.07 + world_pos.z * 0.09 + 31.7)
	                                 * sin(world_pos.z * 0.05 - world_pos.x * 0.06 + 74.3)
	                                 * 0.5 + 0.5);
	float t = TIME * wind_speed * mix(0.6, 1.0, wm) * local_tempo;

	float wave_x = sin(world_pos.x * 0.4 + t * 0.7) * 0.5
	             + sin(world_pos.x * 1.1 + world_pos.z * 0.7 + t) * 0.3;
	float wave_z = cos(world_pos.z * 0.35 + t * 0.6) * 0.4
	             + sin(world_pos.z * 0.9 + world_pos.x * 0.5 + t * 0.8) * 0.25;

	float flutter_x = sin(world_pos.x * 3.0 + world_pos.z * 1.5 + t * 3.5) * 0.15;
	float flutter_z = cos(world_pos.z * 2.8 + world_pos.x * 1.3 + t * 3.0) * 0.12;

	float gust = sin(world_pos.x * 0.12 + world_pos.z * 0.08 + t * 0.25) * 0.5 + 0.5;
	gust = gust * gust * wind_turbulence;

	float sway = wind_strength * wm * height_factor * (1.0 + gust * 0.5) * local_tempo;

	VERTEX.x += (wave_x + flutter_x * wm) * sway;
	VERTEX.z += (wave_z + flutter_z * wm) * sway * 0.7;

	vec2 to_player = world_pos.xz - player_world_position.xz;
	float player_dist = length(to_player);
	float push = 1.0 - smoothstep(0.0, player_push_radius, player_dist);
	push *= push * height_factor * player_push_strength;
	if (player_dist > 0.01) {
		vec2 push_dir = to_player / player_dist;
		VERTEX.x += push_dir.x * push;
		VERTEX.z += push_dir.y * push;
		VERTEX.y -= push * 0.3;
	}
}

void fragment() {
	float instance_rand = fract(world_pos.x * 73.27 + world_pos.z * 97.41);
	if (instance_rand > discard_threshold) {
		discard;
	}

	NORMAL = vec3(0.0, 1.0, 0.0);

	float col_width = 1.0 / float(atlas_columns);
	vec2 atlas_uv = vec2(UV.x * col_width + float(tex_index) * col_width, UV.y);
	vec4 tex = texture(albedo_texture, atlas_uv);

	float ground_ao = mix(0.88, 1.0, 1.0 - UV.y);
	ALBEDO = tex.rgb * albedo_color.rgb * ground_ao;
	ROUGHNESS = roughness;

	float edge_top = smoothstep(0.0, 0.12, UV.y);
	float edge_bot = smoothstep(1.0, 0.88, UV.y);
	ALPHA = tex.a * albedo_color.a * edge_top * edge_bot;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	BACKLIGHT = vec3(0.35);
}
