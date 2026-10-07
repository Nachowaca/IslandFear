shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

// Capa de bruma horizontal con ruido animado. Sigue al jugador en X/Z, pero el ruido es del mundo
// (no "nada" con el jugador). Se desvanece con la distancia y cuando la cámara atraviesa la capa.

uniform vec4 mist_color : source_color = vec4(0.7, 0.8, 0.9, 1.0);
uniform float intensity = 0.0;
uniform float layer_seed = 0.0;
uniform float radius = 75.0;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz * 0.035 + vec2(TIME * 0.018, TIME * 0.011) * (1.0 + layer_seed * 0.4) + vec2(layer_seed * 17.0, layer_seed * 5.0);
	float n = vnoise(p) * 0.6 + vnoise(p * 2.3 + 7.0) * 0.4;
	float d = length(wpos.xz - CAMERA_POSITION_WORLD.xz);
	float edge = 1.0 - smoothstep(radius * 0.4, radius, d);
	float near_f = smoothstep(1.5, 7.0, d);
	float vert = smoothstep(0.2, 2.2, abs(CAMERA_POSITION_WORLD.y - wpos.y));
	ALBEDO = mist_color.rgb;
	ALPHA = smoothstep(0.38, 0.85, n) * edge * near_f * vert * intensity * 0.4;
}
