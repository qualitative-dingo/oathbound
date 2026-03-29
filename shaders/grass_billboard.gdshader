shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap;

uniform bool use_texture_atlas = false;
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform sampler2D albedo_atlas : source_color, filter_nearest_mipmap;
uniform float atlas_columns : hint_range(1.0, 32.0) = 8.0;
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

	float height_factor = 1.0 - UV.y;
	height_factor *= height_factor;
	float wm = leaf_wind_multiplier;

	float t = TIME * wind_speed * mix(0.6, 1.0, wm);
	float gust = sin(world_pos.x * 0.12 + world_pos.z * 0.08 + t * 0.25) * 0.5 + 0.5;
	gust = gust * gust * wind_turbulence;
	float sway = wind_strength * wm * height_factor * (1.0 + gust * 0.35);

	float w1 = sin(world_pos.x * 0.4 + t * 0.7) + sin(world_pos.z * 0.35 + t * 0.6) * 0.6;
	VERTEX.x += w1 * sway * 0.45;
	VERTEX.z += cos(world_pos.z * 0.35 + t * 0.55) * sway * 0.35;

	vec3 pivot = MODEL_MATRIX[3].xyz;
	vec3 sx = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 vl = VERTEX;
	vec3 to_cam = CAMERA_POSITION_WORLD - pivot;
	to_cam.y = 0.0;
	float tc_len = length(to_cam);
	if (tc_len > 1e-5) {
		to_cam /= tc_len;
	} else {
		to_cam = vec3(0.0, 0.0, 1.0);
	}
	vec3 right = cross(vec3(0.0, 1.0, 0.0), to_cam);
	if (dot(right, right) < 1e-8) {
		right = vec3(1.0, 0.0, 0.0);
	} else {
		right = normalize(right);
	}
	vec3 forward = normalize(cross(right, vec3(0.0, 1.0, 0.0)));
	vec3 world_v = pivot + right * (vl.x * sx.x) + vec3(0.0, 1.0, 0.0) * (vl.y * sx.y) + forward * (vl.z * sx.z);

	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_v, 1.0)).xyz;
	world_pos = world_v;
}

void fragment() {
	NORMAL = vec3(0.0, 1.0, 0.0);

	vec4 tex;
	vec3 tint;

	if (use_texture_atlas) {
		float venc = INSTANCE_CUSTOM.x;
		int idx = int(floor(venc * atlas_columns));
		idx = clamp(idx, 0, int(atlas_columns) - 1);
		vec2 atlas_uv = vec2((float(idx) + UV.x) / atlas_columns, UV.y);
		tex = texture(albedo_atlas, atlas_uv);
		tint = INSTANCE_CUSTOM.yzw;
		ALBEDO = tex.rgb * tint;
	} else {
		tex = texture(albedo_texture, UV);
		ALBEDO = tex.rgb * albedo_color.rgb;
	}

	float ground_ao = mix(0.88, 1.0, 1.0 - UV.y);
	ALBEDO *= ground_ao;
	ROUGHNESS = roughness;
	if (use_texture_atlas) {
		ALPHA = tex.a;
	} else {
		ALPHA = tex.a * albedo_color.a;
	}
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	BACKLIGHT = vec3(0.35);
}
