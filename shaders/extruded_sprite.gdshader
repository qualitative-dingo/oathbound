shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 modulate_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform float rim_intensity : hint_range(0.0, 2.0) = 0.4;
uniform vec3 rim_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.65;
uniform float specular_val : hint_range(0.0, 1.0) = 0.25;

void vertex() {
	// Y-axis billboard: face camera horizontally, but DON'T tilt vertically.
	// The camera's elevated angle reveals the top of the extrusion = visible depth.
	vec3 world_pos = MODEL_MATRIX[3].xyz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;

	vec3 to_cam = cam_pos - world_pos;
	to_cam.y = 0.0;
	float d = length(to_cam);
	to_cam = d > 0.001 ? to_cam / d : vec3(0.0, 0.0, 1.0);

	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = cross(up, to_cam);

	float sx = length(MODEL_MATRIX[0]);
	float sy = length(MODEL_MATRIX[1]);
	float sz = length(MODEL_MATRIX[2]);

	mat4 bb = mat4(
		vec4(right * sx, 0.0),
		vec4(up * sy, 0.0),
		vec4(to_cam * sz, 0.0),
		MODEL_MATRIX[3]
	);

	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	ALBEDO = COLOR.rgb * modulate_color.rgb;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;

	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), rim_power);
	EMISSION = rim_color * rim * rim_intensity;
}
