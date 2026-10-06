shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(1.0, 0.93, 0.75, 1.0);
uniform float intensity = 1.0;
uniform float gain = 1.0;

uniform float beam_length = 110.0;
varying float t_along;

void vertex() {
	// 1 junto a la lámpara (extremo angosto, +Y local), 0 en el extremo lejano
	t_along = clamp(0.5 + VERTEX.y / beam_length, 0.0, 1.0);
}

void fragment() {
	float along = t_along;                               // brillante junto a la lámpara, se desvanece lejos
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6); // borde suave del haz
	ALBEDO = beam_color.rgb * intensity * gain;
	ALPHA = pow(along, 1.3) * edge * 0.4 * intensity * gain;
}
