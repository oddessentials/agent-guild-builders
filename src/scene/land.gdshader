shader_type spatial;
// Up to four grounds, blended by a painted map, with broken edges so a painted
// line doesn't read as a line. Textures repeat in metres.
uniform sampler2D weights : filter_linear, repeat_disable;
uniform sampler2D color_0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D color_1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D color_2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D color_3 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_0 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_1 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_3 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_0 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_1 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_2 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_3 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float metres = 3.0;
uniform vec3 grass_tint = vec3(0.72, 0.74, 0.5);
uniform float fallen_leaves = 0.0;
uniform float snow = 0.0;
uniform float grass_recipe = 1.0;
uniform vec4 scale = vec4(1.0);
uniform vec4 glow = vec4(0.0);
uniform vec4 glow_power = vec4(1.0);
uniform float glow_on = 1.0;
uniform float sides = 0.0;

varying vec3 world;
varying vec3 world_normal;
varying float facing_up;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL;
	facing_up = NORMAL.y;
	vec3 t = normalize(cross(vec3(0.0, 0.0, 1.0), NORMAL));
	TANGENT = t;
	BINORMAL = cross(NORMAL, t);
}

// Sampled twice at unrelated scales, so large areas don't show a repeat.
vec3 two_scales(sampler2D tex, vec2 p) {
	return mix(texture(tex, p).rgb, texture(tex, p * 0.37 + vec2(0.31, 0.17)).rgb, 0.35);
}

vec3 projected(sampler2D tex, vec2 p, float s, vec3 side_mix) {
	vec3 top = two_scales(tex, p);
	if (side_mix.y >= 0.999) {
		return top;
	}
	vec3 along_x = two_scales(tex, world.zy / (metres * s));
	vec3 along_z = two_scales(tex, world.xy / (metres * s));
	return top * side_mix.y + along_x * side_mix.x + along_z * side_mix.z;
}

void fragment() {
	vec4 w = texture(weights, UV);
	float wobble = texture(rough_1, world.xz * 0.07).r - 0.5;
	w = max(w + vec4(wobble, -wobble, wobble * 0.5, -wobble * 0.5) * 0.35, vec4(0.0));
	float sum = max(dot(w, vec4(1.0)), 0.001);
	w /= sum;
	vec2 p = world.xz / metres;
	float drift = smoothstep(0.3, 0.7, texture(rough_1, world.xz * 0.013).r);
	if (sides < 0.5 && grass_recipe > 0.5) {
		// The grass recipe of the shipped meadows: olive tint, broad light and dark
		// drifts, and dry patches, so a large field doesn't read as one texture.
		float dry = smoothstep(0.5, 0.7, texture(rough_1, world.xz * 0.0071 + vec2(0.4, 0.1)).r) * 0.45;
		vec3 grass = two_scales(color_0, p * 0.5) * grass_tint;
		grass *= mix(vec3(1.0), vec3(1.1, 0.95, 0.55), dry) * mix(0.62, 0.92, drift);
		ALBEDO = grass * w.r + two_scales(color_1, p) * w.g + two_scales(color_2, p) * w.b + two_scales(color_3, p) * w.a;
		NORMAL_MAP = texture(normal_0, p).rgb * w.r + texture(normal_1, p).rgb * w.g + texture(normal_2, p).rgb * w.b + texture(normal_3, p).rgb * w.a;
		ROUGHNESS = texture(rough_0, p).g * w.r + texture(rough_1, p).g * w.g + texture(rough_2, p).g * w.b + texture(rough_3, p).g * w.a;
	} else {
		vec3 n = abs(normalize(world_normal));
		vec3 side_mix = vec3(1.0, 0.0, 1.0) * n * n * n * n;
		side_mix.y = pow(n.y, 4.0) * 6.0;
		side_mix = sides > 0.5 ? side_mix / (side_mix.x + side_mix.y + side_mix.z) : vec3(0.0, 1.0, 0.0);
		vec3 c0 = projected(color_0, p / scale.x, scale.x, side_mix);
		vec3 c1 = projected(color_1, p / scale.y, scale.y, side_mix);
		vec3 c2 = projected(color_2, p / scale.z, scale.z, side_mix);
		vec3 c3 = projected(color_3, p / scale.w, scale.w, side_mix);
		ALBEDO = c0 * w.r + c1 * w.g + c2 * w.b + c3 * w.a;
		vec3 flat_normal = vec3(0.5, 0.5, 1.0);
		vec3 nm = texture(normal_0, p / scale.x).rgb * w.r + texture(normal_1, p / scale.y).rgb * w.g + texture(normal_2, p / scale.z).rgb * w.b + texture(normal_3, p / scale.w).rgb * w.a;
		NORMAL_MAP = mix(flat_normal, nm, side_mix.y);
		ROUGHNESS = texture(rough_0, p / scale.x).g * w.r + texture(rough_1, p / scale.y).g * w.g + texture(rough_2, p / scale.z).g * w.b + texture(rough_3, p / scale.w).g * w.a;
		EMISSION = (pow(c0, vec3(glow_power.x)) * glow.x * w.r + pow(c1, vec3(glow_power.y)) * glow.y * w.g + pow(c2, vec3(glow_power.z)) * glow.z * w.b + pow(c3, vec3(glow_power.w)) * glow.w * w.a) * glow_on;
	}
	SPECULAR = 0.5;
	if (fallen_leaves > 0.0) {
		float scatter = smoothstep(0.42, 0.62, texture(rough_1, world.xz * 0.09).r) * fallen_leaves * (w.r + w.g);
		ALBEDO = mix(ALBEDO, two_scales(color_1, p * 1.7) * vec3(1.5, 0.72, 0.26), scatter);
	}
	if (snow > 0.0) {
		float cover = smoothstep(0.62, 0.86, facing_up + wobble * 0.12) * snow;
		ALBEDO = mix(ALBEDO, vec3(0.47, 0.49, 0.52) * mix(0.96, 1.0, drift), cover);
		ROUGHNESS = mix(ROUGHNESS, 0.8, cover);
		NORMAL_MAP = mix(NORMAL_MAP, vec3(0.5, 0.5, 1.0), cover);
		EMISSION *= 1.0 - cover;
	}
}
