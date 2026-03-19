shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

group_uniforms waves;
uniform float wave_speed : hint_range(0.0, 2.0)    = 0.08;
uniform float wave_height : hint_range(0.0, 2.0)   = 0.12;
uniform float wave_frequency : hint_range(0.5, 8.0) = 1.2;

group_uniforms colors;
uniform vec4 shallow_color : source_color = vec4(0.15, 0.45, 0.65, 0.55);
uniform vec4 deep_color    : source_color = vec4(0.04, 0.12, 0.28, 0.88);
uniform vec4 foam_color    : source_color = vec4(0.85, 0.9, 0.95, 0.9);

group_uniforms depth;
uniform float depth_distance : hint_range(0.1, 20.0)  = 4.0;
uniform float foam_width : hint_range(0.01, 2.0)      = 0.7;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear;

float hash(vec2 p) {
	float h = dot(p, vec2(127.1, 311.7));
	return fract(sin(h) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

float water_fbm(vec2 p) {
	float v = vnoise(p) * 0.6;
	v += vnoise(p * 2.3 + vec2(50.0)) * 0.4;
	return v;
}

float wave(vec2 pos, float time) {
	float w1 = sin(pos.x * wave_frequency + time * wave_speed * 4.0) * 0.6;
	float w2 = sin(pos.y * wave_frequency * 0.7 + time * wave_speed * 3.2 + 1.5) * 0.4;
	float w3 = sin((pos.x + pos.y) * wave_frequency * 0.5 + time * wave_speed * 2.8) * 0.3;
	return (w1 + w2 + w3) * wave_height;
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += wave(world_pos.xz, TIME);
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Two scrolling FBM layers at different speeds/directions
	float t = TIME * 0.015;
	vec2 uv_a = world_pos.xz * 0.06 + vec2(t, t * 0.7);
	vec2 uv_b = world_pos.xz * 0.04 + vec2(-t * 0.6, t * 0.4);
	float noise_a = water_fbm(uv_a);
	float noise_b = water_fbm(uv_b);
	float combined = (noise_a + noise_b) * 0.5;

	// Depth-based color
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 world_depth = INV_PROJECTION_MATRIX * ndc;
	world_depth /= world_depth.w;
	float depth_diff = -world_depth.z - (-VERTEX.z);

	float depth_factor = clamp(depth_diff / depth_distance, 0.0, 1.0);
	vec4 water_col = mix(shallow_color, deep_color, depth_factor);

	// Foam along shoreline
	float foam_mask = 1.0 - smoothstep(0.0, foam_width, depth_diff);
	foam_mask *= step(0.0, depth_diff);

	vec4 final_col = mix(water_col, foam_color, foam_mask);

	ALBEDO = final_col.rgb;
	ALPHA = final_col.a;
	ROUGHNESS = 0.15;
	METALLIC = 0.05;
	SPECULAR = 0.4;

	// Multi-directional ripples with irrational frequencies to avoid patterns
	float rt = TIME;
	float rx = sin(world_pos.x * 0.73 + world_pos.z * 0.17 + rt * 0.31) * 0.012
	         + sin(world_pos.x * 1.91 + world_pos.z * 0.83 + rt * 0.53) * 0.008
	         + sin(world_pos.x * 4.27 - world_pos.z * 1.53 + rt * 0.79) * 0.004;
	float rz = sin(world_pos.z * 0.67 - world_pos.x * 0.23 + rt * 0.29) * 0.012
	         + sin(world_pos.z * 2.13 + world_pos.x * 0.71 + rt * 0.47) * 0.008
	         + sin(world_pos.z * 3.89 + world_pos.x * 1.37 + rt * 0.67) * 0.004;
	NORMAL = normalize(NORMAL + vec3(rx, 0.0, rz));
}
