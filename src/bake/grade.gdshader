shader_type canvas_item;
render_mode blend_disabled;
// The plates' colour transform: linear light in, sRGB out, from a table of
// Blender's AgX "Medium High Contrast" (tools/make_agx_lut.py).
uniform sampler3D lut : filter_linear, repeat_disable;
uniform float lo = -12.5;
uniform float hi = 12.5;

void fragment() {
	vec3 c = max(texture(TEXTURE, UV).rgb, vec3(0.0));
	vec3 t = clamp((log2(max(c, vec3(pow(2.0, lo)))) - lo) / (hi - lo), 0.0, 1.0);
	float size = float(textureSize(lut, 0).x);
	vec3 uvw = (t * (size - 1.0) + 0.5) / size;
	COLOR = vec4(texture(lut, uvw).rgb, 1.0);
}
