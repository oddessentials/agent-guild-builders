shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D cutout : filter_linear_mipmap, hint_default_white;
uniform float cutout_below = 0.0;

varying float facing_up;

void vertex() {
	facing_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	if (texture(cutout, UV).a < cutout_below) {
		discard;
	}
	ALBEDO = vec3(0.47, 0.49, 0.52);
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	ALPHA = smoothstep(0.25, 0.7, facing_up);
}
