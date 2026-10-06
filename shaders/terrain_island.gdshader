shader_type spatial;
render_mode specular_schlick_ggx;

// Terreno de la isla: 4 capas (arena, pasto, suelo de bosque, roca) mezcladas por altura, pendiente y ruido.
// Mantiene el aspecto facetado low-poly (normales planas) pero con textura y relieve reales.

uniform sampler2D sand_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float water_y = 0.35;
uniform float mood : hint_range(-1.0, 1.0) = 0.0;   // -1 isla hostil (seca, apagada) .. 1 isla confiada (viva)
uniform float normal_strength = 0.9;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 - 8.1) * 0.15;
}

// textura sin repetición visible: dos escalas mezcladas
vec3 tex2(sampler2D t, vec2 uv, float s) {
	return mix(texture(t, uv * s).rgb, texture(t, uv * s * 0.23 + vec2(0.37, 0.19)).rgb, 0.45);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

void fragment() {
	vec3 wn = normalize(wnrm);
	vec2 uv = wpos.xz;
	float h = wpos.y;
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float n_lo = fbm(uv * 0.03);
	float n_mid = fbm(uv * 0.11 + 7.0);

	// pesos de cada capa
	float w_sand = 1.0 - smoothstep(0.95, 1.8 + n_lo * 0.7, h);
	float w_rock = smoothstep(0.26, 0.46, slope + (n_mid - 0.5) * 0.16);
	float w_dirt = smoothstep(0.56, 0.74, n_mid * 0.6 + n_lo * 0.55) * (1.0 - w_sand);
	// categorías pintadas en el vértice: 0.6 suelo de la cueva, 0.3 fondo de laguna
	if (vcol.a < 0.8) {
		if (vcol.a > 0.45) {
			w_rock = 1.0; w_sand = 0.0;
		} else {
			w_sand = 0.65; w_dirt = 0.35; w_rock = 0.0;
		}
	}

	// color
	vec3 c_grass = tex2(grass_c, uv, 0.22);
	vec3 c_dirt = tex2(forest_c, uv, 0.2);
	vec3 c_sand = tex2(sand_c, uv, 0.2);
	// roca triplanar
	vec3 bw = pow(abs(wn), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec2 uvx = wpos.zy * 0.16;
	vec2 uvy = wpos.xz * 0.16;
	vec2 uvz = wpos.xy * 0.16;
	vec3 c_rock = texture(rock_c, uvx).rgb * bw.x + texture(rock_c, uvy).rgb * bw.y + texture(rock_c, uvz).rgb * bw.z;

	// las capas verdes se aclaran/ensucian con el estado de ánimo de la isla
	vec3 grass_tint = mix(vec3(1.08, 0.98, 0.62), vec3(0.95, 1.08, 0.9), mood * 0.5 + 0.5);
	c_grass *= grass_tint;
	c_grass *= 0.8 + n_lo * 0.45;                            // manchas grandes más claras y oscuras
	c_dirt *= 0.85 + n_mid * 0.3;

	vec3 col = c_grass;
	col = mix(col, c_dirt, w_dirt);
	col = mix(col, c_rock, w_rock);
	col = mix(col, c_sand, w_sand * (1.0 - w_rock));
	// arena mojada cerca del agua
	float wet = 1.0 - smoothstep(water_y + 0.05, water_y + 0.75, h);
	col *= mix(1.0, 0.55, wet * w_sand);
	// tinte por vértice (variación por triángulo, estilo low-poly)
	col *= vcol.rgb;

	// relieve: perturba la normal plana con los mapas de normales
	vec3 n_g = tex2(grass_n, uv, 0.22) * 2.0 - 1.0;
	vec3 n_d = tex2(forest_n, uv, 0.2) * 2.0 - 1.0;
	vec3 n_s = tex2(sand_n, uv, 0.2) * 2.0 - 1.0;
	vec3 nrx = texture(rock_n, uvx).rgb * 2.0 - 1.0;
	vec3 nry = texture(rock_n, uvy).rgb * 2.0 - 1.0;
	vec3 nrz = texture(rock_n, uvz).rgb * 2.0 - 1.0;
	vec3 p_rock = vec3(0.0, nrx.y, nrx.x) * bw.x + vec3(nry.x, 0.0, nry.y) * bw.y + vec3(nrz.x, nrz.y, 0.0) * bw.z;
	vec3 p_g = vec3(n_g.x, 0.0, n_g.y);
	vec3 p_d = vec3(n_d.x, 0.0, n_d.y);
	vec3 p_s = vec3(n_s.x, 0.0, n_s.y);
	vec3 p = p_g;
	p = mix(p, p_d, w_dirt);
	p = mix(p, p_rock, w_rock);
	p = mix(p, p_s, w_sand * (1.0 - w_rock));
	vec3 pn = normalize(wn + p * normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(pn, 0.0)).xyz);

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, wet * w_sand);
	SPECULAR = 0.25;
}
