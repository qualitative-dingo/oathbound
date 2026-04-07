shader_type spatial;
render_mode blend_mix, cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

uniform sampler2D sprite_texture : filter_linear_mipmap, source_color;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
uniform float normal_strength : hint_range(0.0, 5.0) = 2.5;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float rim_intensity : hint_range(0.0, 2.0) = 0.6;
uniform vec3 rim_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.7;
uniform float specular_val : hint_range(0.0, 1.0) = 0.25;
uniform float ao_edge_strength : hint_range(0.0, 1.0) = 0.5;
uniform float height_curvature : hint_range(0.0, 2.0) = 1.2;

void vertex() {
	// Billboard: always face camera, preserving model scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0]),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1]),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2]),
		MODEL_MATRIX[3]
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 col = texture(sprite_texture, UV);

	if (col.a < alpha_cutoff) {
		discard;
	}

	ALBEDO = col.rgb;
	ALPHA = 1.0;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;

	// --- Pseudo-normal from sprite shape ---
	vec2 px = vec2(1.0) / vec2(textureSize(sprite_texture, 0));

	float a_l = texture(sprite_texture, UV + vec2(-px.x, 0.0)).a;
	float a_r = texture(sprite_texture, UV + vec2( px.x, 0.0)).a;
	float a_u = texture(sprite_texture, UV + vec2(0.0, -px.y)).a;
	float a_d = texture(sprite_texture, UV + vec2(0.0,  px.y)).a;

	float dx = (a_l - a_r) * normal_strength;
	float dy = (a_u - a_d) * normal_strength;

	// Curvature: center of sprite bulges toward camera, edges recede
	vec2 centered = (UV - 0.5) * 2.0;
	float dist_from_center = length(centered);
	float bulge_z = max(1.0 - dist_from_center * height_curvature, 0.1);

	vec3 n = normalize(vec3(dx, -dy, bulge_z));
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// --- Edge-based ambient occlusion ---
	float alpha_neighbors = (a_l + a_r + a_u + a_d) * 0.25;
	float edge_ao = smoothstep(0.0, 0.8, 1.0 - alpha_neighbors);
	float bottom_darken = smoothstep(0.3, 0.9, UV.y) * 0.15;
	AO = 1.0 - (edge_ao * ao_edge_strength + bottom_darken);
	AO_LIGHT_AFFECT = 0.6;

	// --- Rim lighting (Fresnel-like from view angle) ---
	float rim_factor = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), rim_power);
	float edge_mask = smoothstep(0.05, 0.4, min(min(a_l, a_r), min(a_u, a_d)));
	rim_factor *= (1.0 - edge_mask);
	EMISSION = rim_color * rim_factor * rim_intensity;
}
