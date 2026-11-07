shader_type canvas_item;

varying vec2 at;

void vertex() {
	at = VERTEX;
}

float speck(vec2 p) {
	return fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);
}

float blotch(vec2 p) {
	vec2 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(speck(p), speck(p + vec2(1.0, 0.0)), f.x), mix(speck(p + vec2(0.0, 1.0)), speck(p + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float ink = 0.62 + 0.38 * blotch(at / 9.0);
	ink *= smoothstep(0.08, 0.3, speck(at / 1.6) + 0.3 * blotch(at / 3.0));
	COLOR.a *= ink;
}
