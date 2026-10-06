shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform vec3 cloth : source_color = vec3(0.86, 0.8, 0.66);
uniform float bulge = 0.32;

// UV.x = distancia a lo largo de la botavara (0 en el mástil), UV.y = altura (0 abajo)
void vertex() {
	float a = UV.x;
	float b = UV.y;
	float belly = clamp(a * b * (1.0 - a - b) * 27.0, 0.0, 1.0);     // máxima panza en el centro
	float gust = 0.8 + 0.2 * sin(TIME * 1.3 + a * 3.0);
	VERTEX.x += belly * bulge * gust;
	// aleteo del borde de salida
	VERTEX.x += sin(TIME * 7.0 + a * 9.0 + b * 5.0) * 0.025 * a * (1.0 - b);
}

void fragment() {
	float seam = smoothstep(0.44, 0.5, abs(fract(UV.y * 7.0) - 0.5));   // costuras de paños
	float dirt = 0.85 + 0.15 * smoothstep(0.0, 0.3, UV.y);
	ALBEDO = cloth * (1.0 - 0.2 * seam) * dirt;
	ROUGHNESS = 1.0;
}
