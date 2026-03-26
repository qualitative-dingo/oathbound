shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

group_uniforms FlameShape;
uniform float top_radius : hint_range(0.0, 1.5) = 0.0;
uniform float bottom_radius : hint_range(0.0, 1.5) = 0.5;
uniform float center_radius : hint_range(0.0, 5.0) = 1.5;
uniform float center_position : hint_range(0.0, 1.0) = 0.35;
uniform float cylinder_height : hint_range(0.0, 10.0) = 1.0;
uniform float bottom_curve : hint_range(0.1, 2.0) = 0.4;
uniform float vibrate_amplitude : hint_range(0.0, 0.1) = 0.015;
uniform float vibrate_frequency : hint_range(0.0, 400.0) = 200.0;
group_uniforms;

group_uniforms FlameAppearance;
uniform float speed : hint_range(0.0, 8.0) = 2.0;
uniform float noise_scale : hint_range(0.5, 8.0) = 2.0;
uniform float brightness : hint_range(0.0, 4.0) = 1.5;
uniform float cutoff_base : hint_range(0.0, 1.5) = 0.15;
uniform float band_steps : hint_range(2.0, 8.0) = 4.0;
uniform vec4 color_core : source_color = vec4(1.0, 1.0, 0.95, 1.0);
uniform vec4 color_mid : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform vec4 color_outer : source_color = vec4(1.0, 0.45, 0.05, 1.0);
uniform vec4 color_edge : source_color = vec4(0.6, 0.12, 0.0, 1.0);
group_uniforms;

varying float v_relative_height;

// ── Simplex noise (Ashima Arts, MIT) ────────────────────────────────────────
vec3 mod289_3(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289_4(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x)  { return mod289_4(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
	const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

	vec3 i  = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);
	vec3 g  = step(x0.yzx, x0.xyz);
	vec3 l  = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);
	vec3 x1 = x0 - i1 + C.xxx;
	vec3 x2 = x0 - i2 + C.yyy;
	vec3 x3 = x0 - D.yyy;

	i = mod289_3(i);
	vec4 p = permute(permute(permute(
		i.z + vec4(0.0, i1.z, i2.z, 1.0))
		+ i.y + vec4(0.0, i1.y, i2.y, 1.0))
		+ i.x + vec4(0.0, i1.x, i2.x, 1.0));

	float n_ = 0.142857142857;
	vec3 ns = n_ * D.wyz - D.xzx;
	vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
	vec4 x_ = floor(j * ns.z);
	vec4 y_ = floor(j - 7.0 * x_);
	vec4 x_v = x_ * ns.x + ns.yyyy;
	vec4 y_v = y_ * ns.x + ns.yyyy;
	vec4 h = 1.0 - abs(x_v) - abs(y_v);
	vec4 b0 = vec4(x_v.xy, y_v.xy);
	vec4 b1 = vec4(x_v.zw, y_v.zw);
	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));
	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
	vec3 p0 = vec3(a0.xy, h.x);
	vec3 p1 = vec3(a0.zw, h.y);
	vec3 p2 = vec3(a1.xy, h.z);
	vec3 p3 = vec3(a1.zw, h.w);
	vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
	p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
	vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
	m = m * m;
	return 42.0 * dot(m * m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

// ── Vertex: reshape cylinder into flame silhouette with organic tongues ──────
void vertex() {
	vec3 v_pos = VERTEX;
	float relative_height = (v_pos.y + 1.0) / 2.0;
	v_relative_height = relative_height;

	float scaled_height = relative_height * cylinder_height;
	v_pos.y = scaled_height + sin(TIME * vibrate_frequency) * vibrate_amplitude;

	float radius;
	if (relative_height <= center_position) {
		float t = relative_height / center_position;
		t = pow(t, bottom_curve);
		t = smoothstep(0.0, 1.0, t);
		radius = mix(bottom_radius, center_radius, t);
	} else {
		float t = (relative_height - center_position) / (1.0 - center_position);
		t = smoothstep(0.0, 1.0, t);
		radius = mix(center_radius, top_radius, t);
	}

	// Vertical flame tongues: strong per-angle noise creates distinct tips
	float angle = atan(v_pos.z, v_pos.x);
	float tongue1 = snoise(vec3(angle * 1.5, relative_height * 2.5 - TIME * speed * 1.8, TIME * 0.5));
	float tongue2 = snoise(vec3(angle * 3.0 + 7.0, relative_height * 4.0 - TIME * speed * 2.5, TIME * 0.3));
	float tongue3 = snoise(vec3(angle * 5.0 - 3.0, relative_height * 6.0 - TIME * speed * 1.2, TIME * 0.8));
	float tongue_noise = tongue1 + tongue2 * 0.5 + tongue3 * 0.25;
	float tongue_strength = relative_height * relative_height * 0.5;
	radius *= 1.0 + tongue_noise * tongue_strength;

	// Vertical stretch: tongues extend upward at peaks
	float vert_stretch = max(tongue1, 0.0) * relative_height * 0.15;
	v_pos.y += vert_stretch * cylinder_height;

	// Wind sway that increases with height
	float sway = sin(TIME * 1.3 + relative_height * 2.5) * 0.05 * relative_height;
	float sway_z = sin(TIME * 0.9 + relative_height * 1.8 + 1.5) * 0.035 * relative_height;

	float current_radius = length(vec2(v_pos.x, v_pos.z));
	if (current_radius > 0.0) {
		v_pos.x *= radius / current_radius;
		v_pos.z *= radius / current_radius;
	}
	v_pos.x += sway;
	v_pos.z += sway_z;

	VERTEX = v_pos;
}

// ── Helpers ─────────────────────────────────────────────────────────────────
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float get_noise(vec2 uv, float t) {
	float n = snoise(vec3(uv.x * noise_scale, uv.y * noise_scale * 4.0 + t * speed, 0.0));
	n += snoise(vec3(uv.x * 6.0 + t * speed * 0.7, uv.y * 6.0, 0.0)) * 0.2;
	return n * 0.5 + 0.5;
}

float get_depth(float n, float cutoff, float steps) {
	float d = (n - cutoff) / (1.0 - cutoff);
	d = floor(d * steps) / steps;
	return d;
}

// ── Fragment: toon-banded fire color ────────────────────────────────────────
void fragment() {
	vec2 uv = UV;
	uv.x *= 5.0;
	float t = TIME * 3.0;

	float noise = get_noise(uv, t);

	float cutoff = 1.1 - v_relative_height * 2.5;
	cutoff = max(cutoff, cutoff_base);

	if (noise < cutoff) {
		ALPHA = 0.0;
	} else {
		float d = pow(get_depth(noise, cutoff, band_steps), 0.7);

		vec3 col;
		if (d > 0.75) {
			col = mix(color_mid.rgb, color_core.rgb, (d - 0.75) / 0.25);
		} else if (d > 0.5) {
			col = mix(color_outer.rgb, color_mid.rgb, (d - 0.5) / 0.25);
		} else if (d > 0.25) {
			col = mix(color_edge.rgb, color_outer.rgb, (d - 0.25) / 0.25);
		} else {
			col = color_edge.rgb * (d / 0.25);
		}

		ALBEDO = col * brightness;
		ALPHA = smoothstep(0.0, 0.15, d);
	}
}
