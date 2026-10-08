// Contacto con el jugador: las plantas se doblan al roce, se aplastan y vuelven con retraso (inercia).
// foot_0 = posición actual del jugador; foot_1..3 = dónde estuvo hace ~0.25 / 0.55 / 1.0 s (w = intensidad 0..1).
global uniform vec4 foot_0;
global uniform vec4 foot_1;
global uniform vec4 foot_2;
global uniform vec4 foot_3;

// wp: origen de la planta en el mundo; vwp: posicion mundial del vertice; hk: 0 en la base .. 1 en la punta;
// amount: cuanto reacciona esta planta; reach: alcance (plantas anchas o altas reaccionan desde mas lejos).
// La distancia se mide desde el VERTICE (no desde el origen): una hoja que roza al jugador se dobla aunque la base este lejos.
vec3 foliage_push_v(vec3 wp, vec3 vwp, float hk, float amount, float reach) {
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
		vec2 dv = vwp.xz - f[i].xz;
		float dist = length(dv);
		float r = (0.38 + f[i].w * 0.12) * reach;                 // cerca del cuerpo, no un aura grande
		float k = (1.0 - smoothstep(0.0, r, dist)) * wgt[i] * f[i].w;
		vec2 away = dv / max(dist, 0.001);
		vec2 mv = foot_0.xz - foot_2.xz;                          // hacia donde camina: la planta se arrastra con el cuerpo
		float ml = length(mv);
		vec2 mdir = ml > 0.05 ? mv / ml : away;
		vec2 dir = normalize(away * 0.55 + mdir * 0.8);
		float shake = sin(TIME * 11.0 + wp.x * 4.0 + wp.z * 3.0) * 0.1 * (1.0 - float(i) * 0.2);
		off.xz += (dir + vec2(-dir.y, dir.x) * shake) * k * 1.0;
		off.y -= k * 0.25;
	}
	return off * hk * amount;
}

vec3 foliage_push(vec3 wp, float hk, float amount) {
	return foliage_push_v(wp, wp, hk, amount, 1.0);
}
