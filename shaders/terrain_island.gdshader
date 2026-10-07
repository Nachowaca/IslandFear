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
uniform sampler2D biome_tex : source_color, filter_linear, repeat_disable;
uniform vec2 biome_origin = vec2(-160.0);
uniform float biome_size = 320.0;
uniform sampler2D path_tex : filter_linear, repeat_disable;
uniform vec2 path_origin = vec2(-160.0);
uniform float path_size = 320.0;

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
	if (vcol.a < 0.55) {
		w_rock = 1.0; w_sand = 0.0;
	} else {
		float pw = smoothstep(0.0, 1.0, clamp((1.0 - vcol.a) / 0.38, 0.0, 1.0));
		w_sand = mix(w_sand, 0.15, pw); w_dirt = mix(w_dirt, 0.85, pw); w_rock = mix(w_rock, 0.0, pw);
	}

	// color
	vec3 c_grass = tex2(grass_c, uv, 0.22);
	vec3 c_dirt = tex2(forest_c, uv, 0.2);
	vec3 c_sand = tex2(sand_c, uv, 0.2);
	// arena caribeña: beige claro con el grano de la textura, sin el tono arcilloso
	float s_g = dot(c_sand, vec3(0.333));
	float rip_n = vnoise(uv * 0.35) * 3.0;
	float ripple = sin(dot(uv, normalize(vec2(0.8, 0.6))) * 2.4 + rip_n * 2.0) * 0.5 + 0.5;
	c_sand = vec3(0.92, 0.91, 0.7) * (0.82 + s_g * 0.45) * (0.95 + ripple * 0.07);
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
	col = mix(col, col * vec3(0.7, 0.66, 0.58), wet * w_sand);
	// suciedad cerca del agua: algas secas, barro y restos
	float dirt_band = (1.0 - smoothstep(water_y + 0.1, water_y + 1.3, h)) * w_sand;
	float dirt_n = smoothstep(0.45, 0.8, fbm(uv * 0.9 + 5.0) * 0.7 + vnoise(uv * 6.0) * 0.3);
	col = mix(col, vec3(0.36, 0.31, 0.22), dirt_band * dirt_n * 0.55);
	// tinte por vértice (variación por triángulo, estilo low-poly)
	col *= vcol.rgb;

	// color más vivo y menos plano (referencias: arena amarilla cálida, pasto saturado con parches, roca clara)
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, mix(1.3, 0.92, w_sand * (1.0 - w_rock)));     // más saturación (menos en la arena)
	// pintado irregular y desprolijo del pasto: doble domain warp + varias escalas, transiciones blandas
		vec2 w1 = vec2(fbm(uv * 0.09 + 3.0), fbm(uv * 0.09 - 9.0)) * 2.0 - 1.0;
		vec2 wp = uv + w1 * 22.0;
		vec2 w2 = vec2(fbm(wp * 0.21 + 17.0), fbm(wp * 0.21 - 4.0)) * 2.0 - 1.0;
		wp += w2 * 7.0;
		float patch_n = fbm(wp * 0.06 + 21.0) * 0.6 + fbm(wp * 0.19) * 0.4;
		float patch_m = fbm(wp * 0.13 - 5.0) * 0.55 + vnoise(wp * 0.45) * 0.45;
		float patch_s = fbm(wp * 0.7 + 11.0);
		float g_only = (1.0 - w_sand) * (1.0 - w_rock) * (1.0 - w_dirt);
		vec3 warm_grass = vec3(1.18, 1.08, 0.66);
		vec3 cool_grass = vec3(0.78, 1.05, 0.90);
		vec3 lush_grass = vec3(0.72, 0.95, 0.66);
		vec3 gtint = mix(cool_grass, warm_grass, smoothstep(0.25, 0.75, patch_n));
		gtint = mix(gtint, lush_grass, smoothstep(0.4, 0.75, patch_m) * 0.6);
		col *= mix(vec3(1.0), gtint, g_only * 0.8);
		// color del pasto según el bioma (selva verde profundo, matorral y zona árida amarillentos, roquedal grisáceo)
		vec3 btint = textureLod(biome_tex, clamp((wpos.xz - biome_origin) / biome_size, 0.0, 1.0), 0.0).rgb * 1.5;
		col *= mix(vec3(1.0), btint, g_only * 0.95 + (1.0 - g_only) * w_dirt * 0.3);
		col *= 1.0 + (patch_s - 0.5) * 0.6 * g_only;                            // moteado desparejo
		// tierra pisada: manchas sueltas y rotas, no círculos
		float bare = smoothstep(0.58, 0.8, fbm(wp * 0.12 + 40.0) * 0.7 + vnoise(wp * 0.9) * 0.3) * g_only;
		col = mix(col, c_dirt * vec3(1.2, 1.05, 0.82), bare * 0.5);
		col = mix(col, col * vec3(1.04, 1.02, 0.95), w_sand * (1.0 - w_rock) * 0.5);   // arena beige clara
	// caminos de tierra: senderos principales (R) y sendas chicas cortadas (G), con borde irregular
	vec3 pt = textureLod(path_tex, clamp((wpos.xz - path_origin) / path_size, 0.0, 1.0), 0.0).rgb;
	float edge_n = fbm(uv * 1.4) * 0.55 + vnoise(uv * 5.0) * 0.45;
	float pm = smoothstep(0.22, 0.5, pt.r + (edge_n - 0.5) * 0.4);
	float pm2 = smoothstep(0.3, 0.55, pt.g + (edge_n - 0.5) * 0.5) * 0.75;
	float path = max(pm, pm2) * (1.0 - w_rock) * smoothstep(0.7, 1.1, h);
	vec3 path_col = c_dirt * vec3(1.3, 1.1, 0.85) * (0.8 + 0.4 * vnoise(uv * 3.0));
	path_col *= 0.9 + 0.2 * step(0.82, vnoise(uv * 17.0));        // guijarros sueltos
	// caminos importantes: tierra más oscura y rojiza, húmeda (referencia: sendero nocturno)
	float imp = smoothstep(0.25, 0.6, pt.b + (edge_n - 0.5) * 0.3) * (1.0 - w_sand);
	path_col = mix(path_col, vec3(0.78, 0.34, 0.17) * (0.8 + 0.5 * vnoise(uv * 4.0)), imp * 0.9);
	col = mix(col, path_col, path * 0.92);
	col = mix(col, col * vec3(1.35, 1.35, 1.42), w_rock * 0.6);             // roca más clara
	col *= 1.0 + clamp((h - 6.0) * 0.02, 0.0, 0.15);                        // las cumbres, algo más claras

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
	vec3 p_s = vec3(n_s.x, 0.0, n_s.y) * 0.6 + vec3(0.12, 0.0, 0.08) * (ripple - 0.5);
	vec3 p = p_g;
	p = mix(p, p_d, max(w_dirt, path));
	p = mix(p, p_rock, w_rock);
	p = mix(p, p_s, w_sand * (1.0 - w_rock));
	vec3 pn = normalize(wn + p * normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(pn, 0.0)).xyz);

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, wet * w_sand);
	SPECULAR = 0.25;
}
