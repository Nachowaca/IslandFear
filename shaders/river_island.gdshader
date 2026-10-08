shader_type spatial;
render_mode specular_schlick_ggx;

// Río fino: agua verde-turquesa que corre (UV.y = metros a lo largo del río), espuma en los bordes y destellos de sol y luna.
// El borde se desvanece con el alfa del vértice (profundidad sobre el terreno visible).

uniform vec4 deep_color : source_color = vec4(0.03, 0.30, 0.34, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.16, 0.62, 0.55, 1.0);
uniform vec3 sky_color : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 zenith_color : source_color = vec3(0.2, 0.45, 0.8);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_glow = 0.0;
uniform vec3 moon_tint : source_color = vec3(0.85, 0.9, 1.0);
uniform vec3 sun_dir = vec3(0.0, -1.0, 0.0);
uniform float sun_glow = 0.0;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.9, 0.7);
uniform float flow_speed = 0.9;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(UV.y * 2.2 - TIME * 1.6 + UV.x * 3.0) * 0.012;
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;                  // 0 centro .. 1 borde
	float t = TIME * flow_speed;
	vec2 fl = vec2(UV.x * 5.0, UV.y * 0.9 - t);
	float n1 = vnoise(fl * vec2(2.0, 1.2));
	float n2 = vnoise(fl * vec2(4.5, 2.6) + 7.0 + vec2(0.0, -t * 0.6));
	float streak = smoothstep(0.62, 0.9, n1 * 0.6 + n2 * 0.5);
	float depth_k = smoothstep(0.95, 0.15, across);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth_k * 0.8);
	// algas y barro en el lecho, se ven por transparencia
	float silt = vnoise(wpos.xz * 0.9 + 3.0);
	col = mix(col, vec3(0.12, 0.26, 0.14), smoothstep(0.5, 0.85, silt) * 0.45);
	col = mix(col, vec3(0.2, 0.17, 0.1), (1.0 - depth_k) * 0.35);
	// reflejo del cielo con fresnel
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, mix(sky_color, zenith_color, 0.35), fres * 0.4);
	// espuma: rayas que corren y borde claro en las orillas
	float rim = smoothstep(0.62, 0.98, across + (n2 - 0.5) * 0.35);
	float foam = clamp(streak * 0.38 + rim * 0.75 * (0.6 + 0.4 * n1), 0.0, 1.0);
	foam *= 1.0 - smoothstep(0.9, 1.0, across);
	col = mix(col, vec3(0.95, 1.0, 1.0), foam);

	// destellos
	vec2 nn = vec2(vnoise(wpos.xz * 3.0 + vec2(0.0, -t)), vnoise(wpos.xz * 3.0 + 17.0 - vec2(t, 0.0))) - 0.5;
	vec3 nrm = normalize(NORMAL + vec3(nn.x, 0.0, nn.y) * 0.35);
	vec3 Ls = normalize((VIEW_MATRIX * vec4(normalize(sun_dir), 0.0)).xyz);
	float nhs = max(dot(nrm, normalize(Ls + VIEW)), 0.0);
	EMISSION += sun_tint * (pow(nhs, 140.0) * 0.9 + pow(nhs, 24.0) * 0.1) * sun_glow * (1.0 - foam);
	vec3 Lm = normalize((VIEW_MATRIX * vec4(normalize(moon_dir), 0.0)).xyz);
	float nhm = max(dot(nrm, normalize(Lm + VIEW)), 0.0);
	EMISSION += moon_tint * (pow(nhm, 200.0) * 0.6 + pow(nhm, 30.0) * 0.18) * moon_glow * (1.0 - foam);

	ALBEDO = col;
	ROUGHNESS = mix(0.08, 0.7, foam);
	SPECULAR = 0.7;
	float edge_fade = 1.0 - smoothstep(0.72, 1.0, across);
	ALPHA = edge_fade * clamp(COLOR.a * mix(0.62, 0.92, depth_k) + foam * 0.5 * COLOR.a, 0.0, 1.0);
}
