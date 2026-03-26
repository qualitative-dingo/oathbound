shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.35;
uniform vec4 rim_color : source_color = vec4(0.8, 0.75, 0.6, 1.0);
uniform float ao_strength : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
uniform float specular_value : hint_range(0.0, 1.0) = 0.15;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.0;

uniform int hide_bone_count = 0;
uniform int[32] hide_bones;

varying float v_hide;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	float hide_weight = 0.0;
	for (int i = 0; i < 4; i++) {
		int bone = int(BONE_INDICES[i]);
		float w = BONE_WEIGHTS[i];
		for (int j = 0; j < 32; j++) {
			if (j >= hide_bone_count) break;
			if (bone == hide_bones[j]) {
				hide_weight += w;
				break;
			}
		}
	}
	v_hide = hide_weight;
}

void fragment() {
	if (v_hide > 0.3) {
		discard;
	}

	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb;

	float noise = hash(UV * 64.0) * 2.0 - 1.0;
	ALBEDO += vec3(noise) * grain_strength;

	float height_ao = smoothstep(0.0, 0.3, UV.y);
	float edge_ao = smoothstep(0.0, 0.05, min(UV.x, min(1.0 - UV.x, min(UV.y, 1.0 - UV.y))));
	float ao = mix(1.0 - ao_strength, 1.0, height_ao * edge_ao);
	ALBEDO *= ao;

	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;

	float rim = 1.0 - dot(NORMAL, VIEW);
	rim = pow(max(rim, 0.0), rim_power) * rim_intensity;
	EMISSION = rim_color.rgb * rim;
}
