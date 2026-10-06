// Contacto con el jugador: las plantas se doblan al roce, se aplastan y vuelven con retraso (inercia).
// foot_0 = posición actual del jugador; foot_1..3 = dónde estuvo hace ~0.25 / 0.55 / 1.0 s (w = intensidad 0..1).
global uniform vec4 foot_0;
global uniform vec4 foot_1;
global uniform vec4 foot_2;
global uniform vec4 foot_3;

// wp: origen de la planta en el mundo; hk: 0 en la base .. 1 en la punta; amount: cuánto reacciona esta planta.
vec3 foliage_push(vec3 wp, float hk, float amount) {
	vec3 off = vec3(0.0);
	if (amount <= 0.001) {
		return off;
	}
	vec4 f[4];
	f[0] = foot_0;
	f[1] = foot_1;
	f[2] = foot_2;
	f[3] = foot_3;
	float wgt[4] = float[4](0.55, 0.25, 0.12, 0.08);
	for (int i = 0; i < 4; i++) {
		if (abs(wp.y - f[i].y) > 1.8) {
			continue;
		}
		vec2 d = wp.xz - f[i].xz;
		float dist = length(d);
		float r = 0.55 + f[i].w * 0.5;
		float k = (1.0 - smoothstep(0.0, r, dist)) * wgt[i] * f[i].w;
		vec2 dir = d / max(dist, 0.001);
		// empuja hacia afuera, aplasta y deja un temblor que se apaga con la distancia
		float shake = sin(TIME * 15.0 + wp.x * 4.0 + wp.z * 3.0) * 0.12 * (1.0 - float(i) * 0.2);
		off.xz += (dir + vec2(-dir.y, dir.x) * shake) * k * 1.9;
		off.y -= k * 0.5;
	}
	return off * hk * amount;
}
