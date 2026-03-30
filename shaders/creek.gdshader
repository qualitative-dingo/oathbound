shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

group_uniforms flow;
uniform float flow_speed : hint_range(0.0, 3.0) = 0.8;
uniform float ripple_scale : hint_range(0.5, 8.0) = 3.0;
uniform float ripple_strength : hint_range(0.0, 0.1) = 0.02;

group_uniforms colors;
uniform vec4 water_color : source_color = vec4(0.08, 0.18, 0.32, 0.65);
uniform vec4 foam_color  : source_color = vec4(0.75, 0.82, 0.88, 0.70);
uniform vec4 deep_tint   : source_color = vec4(0.04, 0.10, 0.22, 0.80);

group_uniforms edge;
uniform float foam_width : hint_range(0.0, 0.3) = 0.12;
uniform float edge_fade  : hint_range(0.01, 0.2) = 0.08;

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

varying vec2 v_uv;
varying float v_slope;

void vertex() {
	v_uv = UV;
	v_slope = COLOR.r;

	// Slope-scaled speed: flat = base, steep = up to 4x
	float speed = flow_speed * (0.5 + v_slope * 3.5);

	// Subtle ripple displacement along flow direction
	float ripple = sin(UV.y * ripple_scale * 12.0 + TIME * speed * 4.0) * ripple_strength;
	ripple += sin(UV.y * ripple_scale * 7.3 + UV.x * 3.0 + TIME * speed * 2.8) * ripple_strength * 0.6;
	VERTEX.y += ripple;
}

void fragment() {
	// Slope-scaled speed for consistent vertex/fragment animation
	float speed = flow_speed * (0.5 + v_slope * 3.5);

	// Scrolling UV along the flow direction (V axis = along creek)
	float scroll = TIME * speed;
	vec2 flow_uv = vec2(v_uv.x, v_uv.y + scroll);

	// Multi-octave noise for surface detail
	float n1 = vnoise(flow_uv * ripple_scale * 2.0);
	float n2 = vnoise(flow_uv * ripple_scale * 4.5 + vec2(50.0, 30.0));
	float combined = n1 * 0.6 + n2 * 0.4;

	// Edge foam based on UV.x distance from banks (0 and 1)
	float edge_dist = min(v_uv.x, 1.0 - v_uv.x);
	float foam_mask = 1.0 - smoothstep(0.0, foam_width, edge_dist);
	foam_mask *= 0.5 + vnoise(flow_uv * 6.0 + vec2(TIME * 0.3, 0.0)) * 0.5;
	foam_mask = smoothstep(0.2, 0.7, foam_mask);

	// Depth sampling for terrain intersection
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 world_depth = INV_PROJECTION_MATRIX * ndc;
	world_depth /= world_depth.w;
	float depth_diff = -world_depth.z - (-VERTEX.z);

	// Fade out where creek meets terrain edges
	float shore_fade = smoothstep(0.0, edge_fade, depth_diff);

	// Width-based color darkening (deeper in center)
	float center = 1.0 - abs(v_uv.x * 2.0 - 1.0);
	vec4 col = mix(water_color, deep_tint, center * 0.4);
	col.rgb += combined * 0.06;

	// Apply foam
	col = mix(col, foam_color, foam_mask);

	// Fresnel for subtle reflection
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fresnel = pow(1.0 - max(dot(NORMAL, view_dir), 0.0), 2.5);
	fresnel = clamp(fresnel, 0.0, 0.5);
	col.rgb = mix(col.rgb, vec3(0.25, 0.35, 0.50), fresnel * 0.3);
	col.a = mix(col.a, 0.85, fresnel * 0.4);

	ALBEDO = col.rgb;
	ALPHA = col.a * shore_fade;
	ROUGHNESS = mix(0.1, 0.4, foam_mask);
	METALLIC = 0.05;
	SPECULAR = 0.4;

	// Surface normal perturbation for ripples
	float ns = ripple_strength * 2.0;
	float nx = sin(flow_uv.y * 8.0 + flow_uv.x * 3.0 + TIME * 1.2) * ns
	         + sin(flow_uv.y * 15.0 - flow_uv.x * 5.0 + TIME * 0.8) * ns * 0.5;
	float nz = sin(flow_uv.x * 6.0 + flow_uv.y * 4.0 + TIME * 0.9) * ns
	         + sin(flow_uv.x * 12.0 - flow_uv.y * 8.0 + TIME * 1.4) * ns * 0.5;
	NORMAL = normalize(NORMAL + vec3(nx, 0.0, nz));
}
