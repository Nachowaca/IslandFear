shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform vec3 cloth : source_color = vec3(0.86, 0.8, 0.66);
uniform float bulge = 0.3;
uniform float mast_z = -0.85;
uniform float yaw = 0.2;

// UV.x = distancia a lo largo de la botavara (0 en el mástil), UV.y = altura (0 abajo)
// Tela suelta: se hincha y se afloja con las ráfagas, ondula y gira un poco sobre el mástil.
void vertex() {
	float a = UV.x;
	float b = UV.y;
	float belly = clamp(a * b * (1.0 - a - b) * 27.0, 0.0, 1.0);
	float gust = 0.55 + 0.3 * sin(TIME * 0.9 + a * 2.0) + 0.15 * sin(TIME * 2.3 + b * 3.0);
	float d = VERTEX.z - mast_z;
	float swing = yaw + 0.06 * sin(TIME * 0.7) + 0.03 * sin(TIME * 1.9);
	VERTEX.x += d * swing;                                   // gira sobre el mástil
	VERTEX.x += belly * bulge * gust;                        // panza que respira
	// ondas que corren por la tela hacia el borde de salida (más fuertes lejos del mástil)
	float w = sin(TIME * 3.1 - a * 8.0 + b * 4.0) * 0.06 + sin(TIME * 5.3 - a * 13.0) * 0.025;
	VERTEX.x += w * (0.25 + a) * (1.0 - b * 0.5);
}

void fragment() {
	float seam = smoothstep(0.44, 0.5, abs(fract(UV.y * 7.0) - 0.5));   // costuras de paños
	float dirt = 0.85 + 0.15 * smoothstep(0.0, 0.3, UV.y);
	ALBEDO = cloth * (1.0 - 0.2 * seam) * dirt;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.25, 0.22, 0.16);
}
