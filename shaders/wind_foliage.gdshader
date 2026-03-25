shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform vec3 albedo_color : source_color = vec3(0.25, 0.55, 0.15);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform vec3 uv1_scale = vec3(3.0, 3.0, 3.0);
uniform float wind_strength : hint_range(0.0, 2.0) = 0.35;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.2;
uniform float wind_turbulence : hint_range(0.0, 3.0) = 0.6;
global uniform float leaf_wind_multiplier;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	float wm = leaf_wind_multiplier;
	float height_factor = clamp(VERTEX.y * 0.5 + 0.5, 0.0, 1.0);
	height_factor *= height_factor;

	// Per-area tempo variation for organic rustling
	float local_tempo = 0.7 + 0.6 * (sin(world_pos.x * 0.07 + world_pos.z * 0.09 + 31.7)
	                                 * sin(world_pos.z * 0.05 - world_pos.x * 0.06 + 74.3)
	                                 * 0.5 + 0.5);
	float t = TIME * wind_speed * mix(0.6, 1.0, wm) * local_tempo;
	float wave_x = sin(world_pos.x * 0.8 + t) * 0.6
	             + sin(world_pos.x * 1.7 + world_pos.z * 0.9 + t * 1.3) * 0.4;
	float wave_z = cos(world_pos.z * 0.7 + t * 0.9) * 0.5
	             + sin(world_pos.z * 1.5 + world_pos.x * 0.6 + t * 1.1) * 0.3;
	float gust = sin(world_pos.x * 0.3 + world_pos.z * 0.2 + t * 0.4) * 0.5 + 0.5;
	gust = gust * wind_turbulence;

	float sway = wind_strength * wm * height_factor * (1.0 + gust * 0.5) * local_tempo;
	VERTEX.x += wave_x * sway;
	VERTEX.z += wave_z * sway * 0.7;
	VERTEX.y += sin(world_pos.x * 1.2 + world_pos.z * 0.8 + t * 1.5) * sway * 0.15;
}

void fragment() {
	vec3 wp = world_pos;
	vec3 wn = abs(world_normal);
	wn = pow(wn, vec3(1.0));
	wn /= (wn.x + wn.y + wn.z);

	vec2 uv_x = wp.zy * uv1_scale.x;
	vec2 uv_y = wp.xz * uv1_scale.y;
	vec2 uv_z = wp.xy * uv1_scale.z;

	vec4 tex_x = texture(albedo_texture, uv_x);
	vec4 tex_y = texture(albedo_texture, uv_y);
	vec4 tex_z = texture(albedo_texture, uv_z);

	vec3 triplanar = tex_x.rgb * wn.x + tex_y.rgb * wn.y + tex_z.rgb * wn.z;

	ALBEDO = triplanar * albedo_color;
	ROUGHNESS = roughness;
	BACKLIGHT = vec3(0.35);
}
