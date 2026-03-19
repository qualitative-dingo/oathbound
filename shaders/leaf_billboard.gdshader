shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform vec4 albedo_color : source_color = vec4(0.25, 0.55, 0.15, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.4;
uniform float wind_strength : hint_range(0.0, 4.0) = 0.8;
uniform float wind_speed : hint_range(0.0, 8.0) = 1.8;
uniform float wind_turbulence : hint_range(0.0, 5.0) = 1.2;
global uniform float leaf_wind_multiplier;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Normalize wind displacement for MultiMesh scaled unit quads.
	// For regular MeshInstance3D (no node scaling), inst_scale ≈ 1.0 → no change.
	float inst_scale = length(MODEL_MATRIX[0].xyz);
	float inv_scale = 1.0 / max(inst_scale, 0.01);

	float wm = leaf_wind_multiplier;
	float height_factor = clamp(VERTEX.y * inst_scale * 0.3 + 0.7, 0.0, 1.0);

	float t = TIME * wind_speed * mix(0.6, 1.0, wm);

	float wave_x = sin(world_pos.x * 0.5 + t) * 0.6
	             + sin(world_pos.x * 1.3 + world_pos.z * 0.8 + t * 1.3) * 0.4;
	float wave_z = cos(world_pos.z * 0.4 + t * 0.9) * 0.5
	             + sin(world_pos.z * 1.1 + world_pos.x * 0.6 + t * 1.1) * 0.35;

	float flutter_x = sin(world_pos.x * 3.5 + world_pos.z * 2.0 + t * 4.0) * 0.25
	               + sin(world_pos.x * 5.0 + t * 6.5) * 0.12;
	float flutter_z = cos(world_pos.z * 3.2 + world_pos.x * 1.8 + t * 3.7) * 0.2
	               + cos(world_pos.z * 4.8 + t * 5.8) * 0.1;
	float flutter_y = sin(world_pos.x * 4.0 + world_pos.z * 3.0 + t * 5.5) * 0.15;

	float gust = sin(world_pos.x * 0.15 + world_pos.z * 0.1 + t * 0.3) * 0.5 + 0.5;
	gust = gust * gust * wind_turbulence;

	float sway = wind_strength * wm * height_factor * (1.0 + gust * 0.6);

	VERTEX.x += (wave_x + flutter_x * wm) * sway * inv_scale;
	VERTEX.z += (wave_z + flutter_z * wm) * sway * 0.7 * inv_scale;
	VERTEX.y += (sin(world_pos.x * 0.8 + world_pos.z * 0.5 + t * 1.4) * 0.2 + flutter_y * wm) * sway * inv_scale;
}

void fragment() {
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = normalize(mix(n, vec3(0.0, 1.0, 0.0), 0.85));

	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * albedo_color.rgb;
	ROUGHNESS = roughness;
	ALPHA = tex.a * albedo_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
