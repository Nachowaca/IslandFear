shader_type spatial;
render_mode cull_disabled;

// Flores que brillan de noche. Se inclinan hacia el jugador (isla serena) o se apartan (isla tensa).
uniform vec4 albedo : source_color = vec4(0.5, 0.3, 0.1, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float energy = 0.3;
uniform float base_off = 0.3;        // altura local del suelo respecto al centro de la malla
uniform float height_ref = 0.35;
uniform vec3 player_pos = vec3(0.0, -1000.0, 0.0);
uniform float lean = 0.25;           // -1 se aparta … +1 se inclina hacia el jugador

void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	vec2 to_p = player_pos.xz - wp.xz;
	float d = length(to_p);
	float near = 1.0 - smoothstep(2.5, 14.0, d);
	float h = clamp((VERTEX.y + base_off) / height_ref, 0.0, 1.0);
	vec3 dir = vec3(to_p.x, 0.0, to_p.y) / max(d, 0.001);
	vec3 off = dir * near * lean * h * h * 0.16;
	off.y -= abs(lean) * near * h * h * 0.03;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.8;
	EMISSION = glow.rgb * energy;
}
