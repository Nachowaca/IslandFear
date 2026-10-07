shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Sombra de contacto: mancha oscura (teal, nunca negro) suave bajo árboles y rocas.

uniform vec3 shadow_color : source_color = vec3(0.02, 0.07, 0.1);
uniform float strength = 0.5;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = 1.0 - smoothstep(0.1, 1.0, d);
	ALBEDO = shadow_color;
	ALPHA = a * a * strength;
}
