shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

group_uniforms flow;
uniform float flow_speed : hint_range(0.0, 3.0) = 0.8;
uniform float ripple_scale : hint_range(0.5, 8.0) = 3.0;
uniform float ripple_strength : hint_range(0.0, 0.1) = 0.02;

group_uniforms colors;
uniform vec4 water_color : source_color = vec4(0.10, 0.16, 0.13, 0.55);
uniform vec4 foam_color  : source_color = vec4(0.80, 0.85, 0.82, 0.70);
uniform vec4 deep_tint   : source_color = vec4(0.05, 0.10, 0.08, 0.75);
uniform vec4 sky_tint    : source_color = vec4(0.30, 0.38, 0.35, 1.0);

group_uniforms edge;
uniform float foam_width : hint_range(0.0, 0.5) = 0.15;
uniform float depth_foam_width : hint_range(0.01, 0.5) = 0.12;
uniform float water_level = 0.0;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear;

vec2 ghash(vec2 p) {
	vec3 q = vec3(dot(p, vec2(127.1, 311.7)),
	              dot(p, vec2(269.5, 183.3)),
	              dot(p, vec2(419.2, 371.9)));
	return normalize(fract(sin(q.xy) * 43758.5453) * 2.0 - 1.0);
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float d00 = dot(ghash(i), f);
	float d10 = dot(ghash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float d01 = dot(ghash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d11 = dot(ghash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(d00, d10, u.x), mix(d01, d11, u.x), u.y) * 0.5 + 0.5;
}

varying vec2 v_uv;
varying float v_slope;
varying float v_world_y;
varying vec2 v_world_xz;

void vertex() {
	v_uv = UV;
	v_slope = COLOR.r;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_y = wpos.y;
	v_world_xz = wpos.xz;

	// Slope-scaled speed: flat = base, steep = up to 4x
	float speed = flow_speed * (0.5 + v_slope * 3.5);

	// Noise-based ripple on world-space coords — irregular, organic displacement
	vec2 rp = wpos.xz * 0.3 + vec2(TIME * speed * 0.8, TIME * speed * 0.5);
	float ripple = (gnoise(rp) - 0.5) * ripple_strength * 2.0;
	ripple += (gnoise(rp * 2.3 + vec2(71.0, 37.0)) - 0.5) * ripple_strength * 1.2;
	float ripple_fade = 1.0 - smoothstep(0.2, 0.6, v_slope);
	VERTEX.y += ripple * ripple_fade;
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Slope-scaled speed for consistent vertex/fragment animation
	float speed = flow_speed * (0.5 + v_slope * 3.5);

	// Scrolling UV along the flow direction (V axis = along creek)
	float scroll = TIME * speed;
	vec2 flow_uv = vec2(v_uv.x, v_uv.y - scroll);

	// Multi-octave noise for surface detail
	float n1 = gnoise(flow_uv * ripple_scale * 2.0);
	float n2 = gnoise(flow_uv * ripple_scale * 4.5 + vec2(50.0, 30.0));
	float combined = n1 * 0.6 + n2 * 0.4;

	// ── Depth sampling for terrain intersection ──
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 world_depth_vec = INV_PROJECTION_MATRIX * ndc;
	world_depth_vec /= world_depth_vec.w;
	float depth_diff = -world_depth_vec.z - (-VERTEX.z);

	// ── Perturbed depth edge — organic, noisy shoreline (ported from water.gdshader) ──
	float edge_noise = gnoise(world_pos.xz * 1.2) * 0.45
	                 + gnoise(world_pos.xz * 2.7 + vec2(33.0, 77.0)) * 0.30
	                 + gnoise(world_pos.xz * 6.1 + vec2(-19.0, 41.0)) * 0.15;
	float perturbed_depth = depth_diff + (edge_noise - 0.45) * 0.35;

	// Hard cutoff: suppress water where terrain is clearly above
	float hard_mask = smoothstep(-0.02, 0.12, depth_diff);

	// Shore alpha fade using perturbed depth for organic edge
	float shore_alpha = smoothstep(0.0, 0.5, perturbed_depth) * hard_mask;

	// ── UV-based bank foam (mesh edges) ──
	float edge_dist = min(v_uv.x, 1.0 - v_uv.x);
	float uv_foam = 1.0 - smoothstep(0.0, foam_width, edge_dist);
	uv_foam *= 0.5 + gnoise(flow_uv * 6.0 + vec2(TIME * 0.3, 0.0)) * 0.5;
	uv_foam = smoothstep(0.2, 0.7, uv_foam);

	// ── Depth-based terrain foam (any terrain intersection) ──
	float foam_noise = gnoise(world_pos.xz * 1.8 + vec2(TIME * 0.25, TIME * 0.18));
	float foam_noise2 = gnoise(world_pos.xz * 3.5 - vec2(TIME * 0.18, TIME * 0.35));
	float foam_noise3 = gnoise(world_pos.xz * 0.9 + vec2(TIME * 0.08, -TIME * 0.12));
	float foam_perturbed = depth_diff + (foam_noise3 - 0.5) * 0.06;
	float depth_foam = 1.0 - smoothstep(0.02, depth_foam_width, foam_perturbed);
	depth_foam *= step(-0.04, foam_perturbed);
	float depth_foam_detail = depth_foam * (0.3 + foam_noise * 0.35 + foam_noise2 * 0.25);
	depth_foam_detail = smoothstep(0.15, 0.55, depth_foam_detail);

	// Combine UV foam and depth foam
	float total_foam = clamp(max(uv_foam, depth_foam_detail), 0.0, 1.0);

	// Rapids foam on steep downhill sections — whitewater effect
	float rapids_noise = gnoise(flow_uv * 8.0 + vec2(TIME * 1.5, TIME * 0.8));
	float rapids_noise2 = gnoise(flow_uv * 14.0 - vec2(TIME * 0.9, TIME * 1.2));
	float rapids = v_slope * (rapids_noise * 0.6 + rapids_noise2 * 0.4);
	rapids = smoothstep(0.15, 0.5, rapids) * v_slope;
	total_foam = clamp(max(total_foam, rapids), 0.0, 1.0);

	// ── Water color with center darkening ──
	float center = 1.0 - abs(v_uv.x * 2.0 - 1.0);
	vec4 col = mix(water_color, deep_tint, center * 0.4);
	col.rgb += combined * 0.06;

	// Apply foam to color
	vec4 final_col = mix(col, foam_color, total_foam);

	// ── Fresnel for subtle reflection ──
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fresnel = pow(1.0 - max(dot(NORMAL, view_dir), 0.0), 2.5);
	fresnel = clamp(fresnel, 0.0, 0.5);
	final_col.rgb = mix(final_col.rgb, sky_tint.rgb, fresnel * 0.3);
	final_col.a = mix(final_col.a, 0.85, fresnel * 0.4);

	ALBEDO = final_col.rgb;

	// ── Alpha: max of water alpha and foam alpha for stronger shoreline visibility ──
	float foam_shore_fade = smoothstep(0.0, 0.2, perturbed_depth);
	ALPHA = max(final_col.a * shore_alpha, total_foam * foam_shore_fade * 0.85);

	// Soft fade at mesh edges so the boundary is never a hard line
	float edge_fade = smoothstep(0.0, 0.06, min(v_uv.x, 1.0 - v_uv.x));
	ALPHA *= edge_fade;

	// Fade out creek mesh as it approaches water bodies
	float water_fade = smoothstep(water_level - 1.2, water_level - 0.3, v_world_y);
	ALPHA *= water_fade;

	// Boost visibility on steep cascading sections
	ALPHA = mix(ALPHA, max(ALPHA, 0.85), v_slope * 0.6);

	ROUGHNESS = mix(0.1, 0.4, total_foam);
	METALLIC = mix(0.05, 0.0, total_foam);
	SPECULAR = mix(0.4, 0.15, total_foam);

	// ── Surface normal perturbation via noise central differences ──
	float ns = ripple_strength * 3.0;
	float eps = 0.15;
	vec2 np = v_world_xz * 0.4 + vec2(TIME * 0.6, TIME * 0.35);
	float nc = gnoise(np) + gnoise(np * 2.7 + vec2(43.0, 91.0)) * 0.5;
	float ndx = gnoise(np + vec2(eps, 0.0)) + gnoise((np + vec2(eps, 0.0)) * 2.7 + vec2(43.0, 91.0)) * 0.5;
	float ndz = gnoise(np + vec2(0.0, eps)) + gnoise((np + vec2(0.0, eps)) * 2.7 + vec2(43.0, 91.0)) * 0.5;
	float nx = (ndx - nc) / eps * ns;
	float nz = (ndz - nc) / eps * ns;
	NORMAL = normalize(NORMAL + vec3(nx, 0.0, nz));
}
