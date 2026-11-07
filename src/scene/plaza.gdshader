shader_type spatial;
// Paving at two unrelated scales with broad wear, so it doesn't read as a repeat.
uniform sampler2D color_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float metres = 3.2;
uniform float fallen_leaves = 0.0;
uniform float snow = 0.0;

varying vec3 world;
varying float facing_up;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	facing_up = NORMAL.y;
	vec3 t = normalize(cross(vec3(0.0, 0.0, 1.0), NORMAL + vec3(0.001, 0.0, 0.0)));
	TANGENT = t;
	BINORMAL = cross(NORMAL, t);
}

void fragment() {
	// Height shifts the lookup, so the well's sides don't stretch the stones.
	vec2 p = (world.xz + world.y * vec2(0.8, 0.6)) / metres;
	float wear = smoothstep(0.3, 0.7, texture(rough_map, world.xz * 0.031).g);
	vec3 a = texture(color_map, p).rgb;
	vec3 b = texture(color_map, p.yx * 0.73 + vec2(0.37, 0.11)).rgb;
	ALBEDO = mix(a, b, wear * 0.55) * mix(0.82, 1.0, wear);
	NORMAL_MAP = texture(normal_map_tex, p).rgb;
	ROUGHNESS = texture(rough_map, p).g;
	SPECULAR = 0.5;
	if (fallen_leaves > 0.0) {
		float scatter = smoothstep(0.62, 0.72, texture(rough_map, world.xz * 0.21).g) * fallen_leaves;
		ALBEDO = mix(ALBEDO, a * vec3(1.5, 0.72, 0.26), scatter);
	}
	if (snow > 0.0) {
		float cover = step(0.5, facing_up) * smoothstep(0.25, 0.6, wear + (a.g - 0.3) * 0.5) * snow;
		ALBEDO = mix(ALBEDO, vec3(0.8, 0.83, 0.87), cover);
		ROUGHNESS = mix(ROUGHNESS, 0.8, cover);
		NORMAL_MAP = mix(NORMAL_MAP, vec3(0.5, 0.5, 1.0), cover);
	}
}
