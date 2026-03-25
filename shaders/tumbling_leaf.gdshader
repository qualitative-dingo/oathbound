shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform vec4 albedo_color : source_color = vec4(0.45, 0.35, 0.15, 1.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.35;
uniform float tumble_speed : hint_range(0.0, 8.0) = 2.5;
global uniform float leaf_wind_multiplier;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// Each leaf gets a unique phase from its world spawn position
	float seed = world_pos.x * 13.37 + world_pos.z * 7.91;
	float phase = fract(seed) * 6.2831;

	float wm = max(leaf_wind_multiplier, 0.2);
	float t = TIME * tumble_speed * wm + phase;

	// Tumble: rotate the quad around its forward axis (rolling along ground)
	float roll = t * 2.3 + sin(t * 0.7) * 0.8;
	float pitch = sin(t * 1.1 + phase) * 0.4;

	float cr = cos(roll); float sr = sin(roll);
	float cp = cos(pitch); float sp = sin(pitch);

	vec3 v = VERTEX;
	// Roll around Z
	vec3 rolled = vec3(v.x * cr - v.y * sr, v.x * sr + v.y * cr, v.z);
	// Pitch around X
	vec3 pitched = vec3(rolled.x, rolled.y * cp - rolled.z * sp, rolled.y * sp + rolled.z * cp);

	VERTEX = pitched;

	// Gentle vertical bob so it doesn't clip into ground
	float bob = abs(sin(t * 1.5)) * 0.15 + 0.08;
	VERTEX.y += bob;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * albedo_color.rgb;
	ROUGHNESS = 0.9;
	ALPHA = tex.a * albedo_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
