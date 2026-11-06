shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;
// Still water, built to the shipped worlds' recipe: green and clear over the
// bed in the shallows, a deep blue-green mirror further out. Depth comes from
// the land under each point. A bake supersamples, so there's no ripple trick
// to widen highlights: sky reflection gives the water its colour.
uniform sampler2D heights : filter_linear, repeat_disable;
uniform float terrain_size = 520.0;
uniform float level = 0.0;
uniform vec3 shallow_color = vec3(0.07, 0.09, 0.06);
uniform vec3 deep_color = vec3(0.008, 0.022, 0.026);
uniform float deep_at = 1.6;
uniform float clear_at = 0.7;
uniform float clear = 0.7;
uniform float roughness = 0.02;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world.xz / terrain_size + 0.5;
	float depth = level - texture(heights, uv).r;
	if (depth <= 0.0) {
		discard;
	}
	ALBEDO = mix(shallow_color, deep_color, clamp(depth / deep_at, 0.0, 1.0));
	ALPHA = mix(1.0 - clear, 1.0, clamp(depth / clear_at, 0.0, 1.0));
	ROUGHNESS = roughness;
	SPECULAR = 0.5;
}
