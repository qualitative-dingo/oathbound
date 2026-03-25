shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

group_uniforms waves;
uniform float wave_speed : hint_range(0.0, 2.0)    = 0.08;
uniform float wave_height : hint_range(0.0, 2.0)   = 0.10;
uniform float wave_frequency : hint_range(0.5, 8.0) = 1.2;

group_uniforms colors;
uniform vec4 shallow_color : source_color = vec4(0.08, 0.32, 0.28, 0.50);
uniform vec4 deep_color    : source_color = vec4(0.02, 0.08, 0.14, 0.92);
uniform vec4 foam_color    : source_color = vec4(0.82, 0.88, 0.90, 0.85);

group_uniforms depth;
uniform float depth_distance : hint_range(0.1, 20.0)  = 3.0;
uniform float foam_width : hint_range(0.01, 2.0)      = 1.2;

group_uniforms surface;
uniform float fresnel_power : hint_range(1.0, 8.0)  = 3.5;
uniform float flow_speed : hint_range(0.0, 0.2) = 0.04;
uniform vec4 sky_tint : source_color = vec4(0.35, 0.55, 0.70, 1.0);
uniform float normal_strength : hint_range(0.0, 0.1) = 0.035;

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
	float v = vnoise(p) * 0.5;
	v += vnoise(p * 2.1 + vec2(50.0, 20.0)) * 0.3;
	v += vnoise(p * 4.7 + vec2(-30.0, 80.0)) * 0.2;
	return v;
}

float wave(vec2 pos, float time) {
	float w1 = sin(pos.x * wave_frequency + time * wave_speed * 4.0) * 0.5;
	float w2 = sin(pos.y * wave_frequency * 0.7 + time * wave_speed * 3.2 + 1.5) * 0.35;
	float w3 = sin((pos.x + pos.y) * wave_frequency * 0.5 + time * wave_speed * 2.8) * 0.25;
	float w4 = sin((pos.x * 0.3 - pos.y * 0.7) * wave_frequency * 1.3 + time * wave_speed * 5.0) * 0.15;
	return (w1 + w2 + w3 + w4) * wave_height;
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += wave(world_pos.xz, TIME);
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// ── Scrolling noise layers for surface detail ──
	float t = TIME * flow_speed;
	vec2 uv_a = world_pos.xz * 0.06 + vec2(t, t * 0.7);
	vec2 uv_b = world_pos.xz * 0.045 + vec2(-t * 0.6, t * 0.4);
	vec2 uv_c = world_pos.xz * 0.025 + vec2(t * 0.3, -t * 0.8);
	float noise_a = water_fbm(uv_a);
	float noise_b = water_fbm(uv_b);
	float noise_c = water_fbm(uv_c);
	float combined = (noise_a + noise_b + noise_c) / 3.0;

	// ── Depth sampling ──
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 world_depth = INV_PROJECTION_MATRIX * ndc;
	world_depth /= world_depth.w;
	float depth_diff = -world_depth.z - (-VERTEX.z);

	float depth_factor = clamp(depth_diff / depth_distance, 0.0, 1.0);
	depth_factor = depth_factor * depth_factor;

	// ── Water color with depth ──
	vec4 water_col = mix(shallow_color, deep_color, depth_factor);
	water_col.rgb += combined * 0.04;

	// ── Fresnel for view-angle reflections ──
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fresnel = pow(1.0 - max(dot(NORMAL, view_dir), 0.0), fresnel_power);
	fresnel = clamp(fresnel, 0.0, 0.7);
	water_col.rgb = mix(water_col.rgb, sky_tint.rgb, fresnel * 0.5);
	water_col.a = mix(water_col.a, 0.95, fresnel * 0.6);

	// ── Depth-noise perturbation — breaks up low-poly staircase edges ──
	float edge_noise = vnoise(world_pos.xz * 1.8) * 0.5 + vnoise(world_pos.xz * 4.5) * 0.25;
	float perturbed_depth = depth_diff + (edge_noise - 0.375) * 0.8;

	// ── Shore alpha fade — smoothly hides the mesh/water intersection ──
	float shore_alpha = smoothstep(0.0, 0.6, perturbed_depth);

	// ── Foam along shoreline ──
	float foam_noise = vnoise(world_pos.xz * 1.5 + vec2(TIME * 0.3, TIME * 0.2));
	float foam_noise2 = vnoise(world_pos.xz * 3.0 - vec2(TIME * 0.2, TIME * 0.4));
	float foam_edge = 1.0 - smoothstep(0.05, foam_width, depth_diff);
	foam_edge *= step(0.0, depth_diff);
	float foam_detail = foam_edge * (0.5 + foam_noise * 0.3 + foam_noise2 * 0.2);
	foam_detail = smoothstep(0.15, 0.6, foam_detail);

	// Gentle foam in deeper areas where waves crest
	float deep_foam = smoothstep(foam_width, foam_width * 2.0, depth_diff)
	               * smoothstep(0.55, 0.75, combined) * 0.15;

	float total_foam = clamp(foam_detail + deep_foam, 0.0, 1.0);
	vec4 final_col = mix(water_col, foam_color, total_foam);

	ALBEDO = final_col.rgb;
	float foam_shore_fade = smoothstep(0.0, 0.25, perturbed_depth);
	ALPHA = max(final_col.a * shore_alpha, total_foam * foam_shore_fade * 0.9);
	ROUGHNESS = mix(0.08, 0.35, total_foam);
	METALLIC = mix(0.08, 0.0, total_foam);
	SPECULAR = mix(0.5, 0.1, total_foam);

	// ── Multi-directional surface normals ──
	float ns = normal_strength;
	float rt = TIME;
	float rx = sin(world_pos.x * 0.73 + world_pos.z * 0.17 + rt * 0.31) * ns
	         + sin(world_pos.x * 1.91 + world_pos.z * 0.83 + rt * 0.53) * ns * 0.65
	         + sin(world_pos.x * 4.27 - world_pos.z * 1.53 + rt * 0.79) * ns * 0.35
	         + sin(world_pos.x * 0.37 + world_pos.z * 2.13 + rt * 0.19) * ns * 0.5;
	float rz = sin(world_pos.z * 0.67 - world_pos.x * 0.23 + rt * 0.29) * ns
	         + sin(world_pos.z * 2.13 + world_pos.x * 0.71 + rt * 0.47) * ns * 0.65
	         + sin(world_pos.z * 3.89 + world_pos.x * 1.37 + rt * 0.67) * ns * 0.35
	         + sin(world_pos.z * 0.43 - world_pos.x * 1.87 + rt * 0.23) * ns * 0.5;
	NORMAL = normalize(NORMAL + vec3(rx, 0.0, rz));
}
