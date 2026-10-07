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

float vn3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1,0,0)), f.x), mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x), mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y), f.z);
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

	// luna con fase, manchas (mares), cráteres y matices
	vec3 m = normalize(moon_dir);
	float md = dot(d, m);
	if (md > 0.0) {
		vec3 t = normalize(cross(m, vec3(0.0, 1.0, 0.0)));
		vec3 b = cross(m, t);
		vec3 off = d - m * md;
		float rad = 0.065;
		vec2 q = vec2(dot(off, t), dot(off, b)) / rad;
		float r2 = dot(q, q);
		if (r2 < 1.0) {
			vec3 nl = vec3(q.x, q.y, sqrt(1.0 - r2));
			float alpha = acos(clamp(2.0 * moon_phase - 1.0, -1.0, 1.0));
			vec3 ld = vec3(sin(alpha), 0.0, cos(alpha));
			float lit = smoothstep(-0.05, 0.1, dot(nl, ld));
			float mares = smoothstep(0.45, 0.7, vn3(nl * 2.6 + 3.0)) * 0.6 + smoothstep(0.5, 0.8, vn3(nl * 5.5)) * 0.25;
			float warm = vn3(nl * 1.7 + 9.0);
			float crat = smoothstep(0.78, 0.88, vn3(nl * 11.0 + 5.0)) * 0.4;
			vec3 base = mix(vec3(0.82, 0.88, 1.0), vec3(1.0, 0.9, 0.72), warm);
			base = mix(base, vec3(0.3, 0.38, 0.6), clamp(mares * 1.5, 0.0, 0.85));
			base *= 1.0 - crat;
			base *= 0.75 + 0.25 * nl.z;
			vec3 moon_col = base * (0.05 + 1.15 * lit);
			col = mix(col, moon_col, smoothstep(1.0, 0.94, r2) * moon_amount);
		}
		col += vec3(0.3, 0.45, 0.8) * (pow(md, 60.0) * 0.28 + pow(md, 600.0) * 0.5 + pow(md, 14.0) * 0.08) * moon_amount * moon_phase;
		col += vec3(0.55, 0.4, 0.8) * pow(md, 200.0) * 0.12 * moon_amount;
	}

	// estrellas (giran con el cielo real)
	if (h > 0.0 && star_amount > 0.001) {
		vec3 p = vec3(dot(d, star_x), dot(d, star_y), dot(d, star_z)) * 140.0;
		vec3 ip = floor(p);
		float r = hash13(ip);
		float star = step(0.9945, r) * smoothstep(0.5, 0.0, length(fract(p) - 0.5));
		float tw = 0.65 + 0.35 * sin(TIME * 2.5 + r * 60.0);
		col += vec3(1.0, 0.82, 0.45) * star * tw * star_amount * clamp(h * 3.0, 0.0, 1.0) * 1.5;
	}
	COLOR = col;
}
