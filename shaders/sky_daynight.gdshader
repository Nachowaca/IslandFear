shader_type sky;

uniform vec3 top_color : source_color = vec3(0.2, 0.45, 0.82);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.84, 0.93);
uniform vec3 ground_color : source_color = vec3(0.1, 0.25, 0.4);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float sun_amount = 1.0;
uniform float moon_amount = 0.0;
uniform float star_amount = 0.0;
uniform float moon_phase = 1.0;                 // fracción iluminada 0..1
uniform vec3 star_x = vec3(1.0, 0.0, 0.0);      // base ecuatorial en coordenadas del mundo
uniform vec3 star_y = vec3(0.0, 0.0, 1.0);
uniform vec3 star_z = vec3(0.0, 1.0, 0.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.45));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}

	// resplandor y disco del sol
	float sd = dot(d, normalize(sun_dir));
	col += vec3(1.0, 0.85, 0.6) * (smoothstep(0.9994, 0.9998, sd) * 6.0 + pow(max(sd, 0.0), 48.0) * 0.4) * sun_amount;

	// luna con fase real: la parte iluminada mira hacia el sol
	vec3 m = normalize(moon_dir);
	float md = dot(d, m);
	vec3 s_dir = normalize(sun_dir);
	if (md > 0.0) {
		vec3 t = normalize(cross(m, vec3(0.0, 1.0, 0.0)));
		vec3 b = cross(m, t);
		vec3 off = d - m * md;
		float rad = 0.032;
		vec2 q = vec2(dot(off, t), dot(off, b)) / rad;
		float r2 = dot(q, q);
		if (r2 < 1.0) {
			vec3 n = m * sqrt(1.0 - r2) + t * q.x + b * q.y;
			float lit = smoothstep(-0.04, 0.06, dot(n, s_dir));
			vec3 moon_col = vec3(0.93, 0.95, 1.0) * (0.06 + 0.94 * lit);
			col = mix(col, moon_col, smoothstep(1.0, 0.92, r2) * moon_amount);
		}
		col += vec3(0.35, 0.45, 0.75) * (pow(md, 90.0) * 0.3 + pow(md, 900.0) * 0.5 + pow(md, 18.0) * 0.07) * moon_amount * moon_phase;
	}

	// estrellas (giran con el cielo real)
	if (h > 0.0 && star_amount > 0.001) {
		vec3 p = vec3(dot(d, star_x), dot(d, star_y), dot(d, star_z)) * 140.0;
		vec3 ip = floor(p);
		float r = hash13(ip);
		float star = step(0.9965, r) * smoothstep(0.38, 0.0, length(fract(p) - 0.5));
		float tw = 0.65 + 0.35 * sin(TIME * 2.5 + r * 60.0);
		col += vec3(0.9, 0.95, 1.0) * star * tw * star_amount * clamp(h * 3.0, 0.0, 1.0) * 1.5;
	}
	COLOR = col;
}
