shader_type canvas_item;
render_mode blend_add, unshaded;

// Destello de lente: halo suave, estela horizontal y unos reflejos que cruzan la pantalla hacia el centro.
uniform vec2 sun_uv = vec2(0.5, 0.5);
uniform float strength = 0.0;
uniform vec3 color : source_color = vec3(1.0, 0.85, 0.6);
uniform float aspect = 1.78;

float ghost(vec2 uv, vec2 pos, float r, float soft) {
	float d = length((uv - pos) * vec2(aspect, 1.0));
	return smoothstep(r, r - soft, d) * 0.5 + smoothstep(r * 0.55, 0.0, d) * 0.5;
}

void fragment() {
	vec2 uv = UV;
	vec2 d = (uv - sun_uv) * vec2(aspect, 1.0);
	float r = length(d);
	float halo = exp(-r * 5.5) * 0.9 + exp(-r * 18.0) * 1.2;
	float streak = exp(-abs(d.y) * 38.0) * exp(-abs(d.x) * 2.6) * 0.45;
	// reflejos sobre el eje sol -> centro
	vec2 axis = vec2(0.5) - sun_uv;
	float g = 0.0;
	g += ghost(uv, sun_uv + axis * 0.7, 0.045, 0.03) * 0.5;
	g += ghost(uv, sun_uv + axis * 1.15, 0.075, 0.05) * 0.35;
	g += ghost(uv, sun_uv + axis * 1.6, 0.03, 0.02) * 0.6;
	g += ghost(uv, sun_uv + axis * 2.0, 0.11, 0.07) * 0.25;
	// se apaga hacia los bordes de pantalla
	float edge = smoothstep(0.0, 0.18, min(min(sun_uv.x, 1.0 - sun_uv.x), min(sun_uv.y, 1.0 - sun_uv.y)) + 0.12);
	vec3 c = color * (halo + streak) + mix(color, vec3(0.7, 0.9, 1.0), 0.5) * g * 0.6;
	COLOR = vec4(c * strength * edge * 0.55, 1.0);
}
