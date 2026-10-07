shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D height_tex : repeat_disable, filter_linear;
uniform vec2 height_origin = vec2(-40.5, -40.5);
uniform float height_size = 81.0;
uniform float water_y = 0.35;
uniform vec4 deep_color : source_color = vec4(0.02, 0.30, 0.50, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.25, 0.88, 0.85, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 1.0, 1.0, 1.0);
uniform float wave_height = 0.27;
uniform float wave_speed = 0.6;
uniform float wave_scale = 0.25;
uniform float clear_depth = 4.0;
uniform float foam_width = 0.45;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_glow = 0.0;      // 0..1: cuánta luna hay para reflejar
uniform vec3 moon_tint : source_color = vec3(0.85, 0.9, 1.0);
uniform vec3 sky_color : source_color = vec3(0.7, 0.8, 0.9);     // color del cielo actual (lo pone el LookDirector)
uniform vec3 zenith_color : source_color = vec3(0.2, 0.45, 0.8);
uniform float sky_reflect = 0.6;
uniform vec3 sun_dir = vec3(0.0, -1.0, 0.0);
uniform float sun_glow = 0.0;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.9, 0.7);
uniform float noctiluca = 0.0;        // 0..1 bioluminiscencia en los bajos
uniform vec3 player_pos = vec3(0.0);
uniform vec3 manta_pos = vec3(0.0, 100.0, 0.0);
uniform float manta_glow = 0.0;

float wave(vec2 p, float t) {
	return sin(p.x * 1.0 + t) * 0.5 + sin(p.y * 1.3 - t * 0.8 + p.x * 0.4) * 0.35 + sin((p.x + p.y) * 0.7 + t * 1.2) * 0.25;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

varying vec3 world_pos;

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * wave_scale;
	float t = TIME * wave_speed;
	VERTEX.y += wave(p, t) * wave_height + wave(p * 2.3 + 5.0, t * 1.4) * wave_height * 0.35;
	float e = 0.05;
	float hx = wave(p + vec2(e, 0.0), t) - wave(p - vec2(e, 0.0), t);
	float hz = wave(p + vec2(0.0, e), t) - wave(p - vec2(0.0, e), t);
	NORMAL = normalize(vec3(-hx * wave_height * wave_scale * 5.0, 1.0, -hz * wave_height * wave_scale * 5.0));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 huv = (world_pos.xz - height_origin) / height_size;
	float thickness = 20.0;
	if (huv.x > 0.0 && huv.x < 1.0 && huv.y > 0.0 && huv.y < 1.0) {
		thickness = max(water_y - texture(height_tex, huv).r, 0.0);
	}
	vec2 rip = vec2(vnoise(world_pos.xz * 1.6 + vec2(TIME * 0.5, TIME * 0.2)), vnoise(world_pos.xz * 1.6 + 9.0 - vec2(TIME * 0.3, TIME * 0.45))) - 0.5;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(rip.x * 0.07, 0.0, rip.y * 0.07, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float depth_k = clamp(thickness / clear_depth, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 1.0, depth_k));
	col = mix(col, shallow_color.rgb * 1.05, fres * 0.4);
	col = mix(col, mix(sky_color, zenith_color, 0.35), fres * sky_reflect * 0.5);       // el agua refleja el cielo del momento

	vec2 fp = world_pos.xz * 1.5;
	float n = vnoise(fp + TIME * 0.2) * 0.6 + vnoise(fp * 2.3 - TIME * 0.15) * 0.4;
	// espuma de orilla: la ola avanza y se retira; borde encaje + bandas que se desprenden hacia el mar
	float swash = sin(TIME * 0.8 + n * 2.0);
	float lace = 0.75 + 0.25 * vnoise(world_pos.xz * 2.0 + vec2(TIME * 0.1, -TIME * 0.07));
	float edge = 1.0 - smoothstep(0.0, foam_width, thickness + (n - 0.5) * 0.5 - swash * 0.35);
	float lapping = 0.5 + 0.5 * sin(TIME * 1.1 + thickness * 5.0);
	float tail = smoothstep(0.8, 0.98, sin(thickness * 3.2 - TIME * 1.0 + n * 2.5)) * (1.0 - smoothstep(0.7, 1.8, thickness)) * smoothstep(0.25, 0.8, thickness);
	float foam = clamp(edge * edge * (0.75 + 0.25 * lapping) * (0.6 + 0.4 * lace) + tail * lace * 0.5, 0.0, 1.0);
	float wet_line = smoothstep(0.0, 0.12, thickness) * (1.0 - smoothstep(0.12, 0.5, thickness));
	foam = clamp(foam + wet_line * 0.35 * lace, 0.0, 1.0);
	// fondo sucio: manchas de algas y barro visibles en los bajos, y turbidez cerca de la orilla
	float shallow_k = 1.0 - smoothstep(0.0, 3.2, thickness);
	float dirt = vnoise(world_pos.xz * 0.9) * 0.6 + vnoise(world_pos.xz * 2.7 + 9.0) * 0.4;
	vec3 algae = vec3(0.10, 0.28, 0.16);
	vec3 mud = vec3(0.20, 0.17, 0.10);
	vec3 dirt_col = mix(mud, algae, smoothstep(0.35, 0.7, vnoise(world_pos.xz * 0.45 + 31.0)));
	col = mix(col, dirt_col, smoothstep(0.42, 0.75, dirt) * shallow_k * 0.65);
	col = mix(col, mud * 1.3, shallow_k * 0.18);
	// motas en suspensión que se desplazan despacio
	float motes = smoothstep(0.86, 1.0, vnoise(world_pos.xz * 14.0 + vec2(TIME * 0.05, -TIME * 0.04)));
	col += vec3(0.5, 0.6, 0.5) * motes * shallow_k * 0.18;

	// mar abierto: manchas de espuma sucia y algas flotantes
	float open_k = smoothstep(0.8, 2.5, thickness);
	float warp = vnoise(world_pos.xz * 0.15 + TIME * 0.03) * 6.0;
	float cap = smoothstep(0.88, 1.0, sin(world_pos.x * 0.35 + world_pos.z * 0.2 + warp + TIME * 0.5)) * (0.4 + 0.6 * vnoise(world_pos.xz * 0.2));
	float alg_k = smoothstep(0.62, 0.8, vnoise(world_pos.xz * 0.3 + 55.0 + vec2(TIME * 0.015, 0.0))) * smoothstep(0.0, 1.5, thickness);
	col = mix(col, vec3(0.12, 0.3, 0.14), alg_k * 0.3);
	col = mix(col, vec3(0.1, 0.4, 0.38), vnoise(world_pos.xz * 0.12 + 3.0) * open_k * 0.25);
	foam = clamp(foam + cap * open_k * 0.22, 0.0, 1.0);

	// mini olas: pequeñas crestas que avanzan hacia la orilla
	float lines = sin(thickness * 4.0 - TIME * 1.3 + n * 3.0);
	float crest = smoothstep(0.93, 1.0, lines) * (1.0 - smoothstep(0.5, 1.8, thickness)) * smoothstep(0.1, 0.6, thickness);
	foam = clamp(foam + crest * 0.3, 0.0, 1.0);
	col = mix(col, foam_color.rgb, foam);

	// camino de destellos de la luna sobre el agua
	if (moon_glow > 0.001) {
		vec2 wp = world_pos.xz;
		vec2 nn = vec2(vnoise(wp * 2.2 + TIME * 0.35), vnoise(wp * 2.2 + 17.0 - TIME * 0.3)) - 0.5;
		vec3 nrm = normalize(NORMAL + vec3(nn.x, 0.0, nn.y) * 0.22);
		vec3 L = normalize((VIEW_MATRIX * vec4(normalize(moon_dir), 0.0)).xyz);
		vec3 H = normalize(L + VIEW);
		float nh = max(dot(nrm, H), 0.0);
		float sparkle = smoothstep(0.35, 1.0, vnoise(wp * 3.5 + TIME * 0.9));
		float glint = pow(nh, 420.0) * (0.3 + 1.2 * sparkle) * 0.6 + pow(nh, 60.0) * 0.28 + pow(nh, 14.0) * 0.22 + pow(nh, 4.0) * 0.07;
		EMISSION += moon_tint * glint * moon_glow * (1.0 - foam);
	}

	// luz de la mantaraya: destello cian en el mar
	if (manta_glow > 0.001) {
		vec3 mv = manta_pos - world_pos;
		float md2 = length(mv);
		vec2 mn = vec2(vnoise(world_pos.xz * 2.0 + TIME * 0.3), vnoise(world_pos.xz * 2.0 + 23.0 - TIME * 0.28)) - 0.5;
		vec3 mnr = normalize(NORMAL + vec3(mn.x, 0.0, mn.y) * 0.22);
		vec3 ml = normalize((VIEW_MATRIX * vec4(mv / md2, 0.0)).xyz);
		float mnh = max(dot(mnr, normalize(ml + VIEW)), 0.0);
		float msp = smoothstep(0.35, 1.0, vnoise(world_pos.xz * 3.5 + TIME * 0.8));
		float mgl = pow(mnh, 140.0) * (0.4 + 1.6 * msp) + pow(mnh, 16.0) * 0.14;
		EMISSION += vec3(0.25, 0.9, 1.0) * mgl * manta_glow * (1.0 - foam) * (1.0 / (1.0 + md2 * 0.006)) * 1.6;
	}

	// noctilucas: chispas azules en los bajos, se encienden con las olas y al caminar cerca
	if (noctiluca > 0.001) {
		float band = smoothstep(0.05, 0.3, thickness) * (1.0 - smoothstep(0.8, 3.5, thickness));
		vec2 ng = world_pos.xz * 8.0;
		vec2 ni = floor(ng);
		float nr = hash(ni);
		float ntw = 0.5 + 0.5 * sin(TIME * (0.8 + nr * 2.0) + nr * 50.0);
		float spark = step(0.85, nr) * smoothstep(0.42, 0.0, length(fract(ng) - 0.5)) * ntw;
		float cloud = smoothstep(0.35, 0.75, vnoise(world_pos.xz * 0.7 + vec2(TIME * 0.08, -TIME * 0.05)));
		float near_p = 1.0 - smoothstep(1.5, 8.0, distance(world_pos.xz, player_pos.xz));
		float swash = (crest * 1.2 + edge * lapping * 0.5) * (0.4 + cloud);
		float ng2 = band * (spark * (0.3 + cloud * 1.2) + swash * 0.5) * (0.45 + near_p * 1.6);
		EMISSION += mix(vec3(0.02, 0.25, 1.0), vec3(0.1, 0.7, 1.0), spark) * ng2 * noctiluca * 1.1;
	}

	// destello del sol sobre el agua (mismo método que la luna)
	if (sun_glow > 0.001) {
		vec2 wp2 = world_pos.xz;
		vec2 nn2 = vec2(vnoise(wp2 * 2.0 + TIME * 0.3), vnoise(wp2 * 2.0 + 11.0 - TIME * 0.25)) - 0.5;
		vec3 nrm2 = normalize(NORMAL + vec3(nn2.x, 0.0, nn2.y) * 0.2);
		vec3 L2 = normalize((VIEW_MATRIX * vec4(normalize(sun_dir), 0.0)).xyz);
		vec3 H2 = normalize(L2 + VIEW);
		float nh2 = max(dot(nrm2, H2), 0.0);
		float spark2 = smoothstep(0.3, 1.0, vnoise(wp2 * 3.2 + TIME * 0.8));
		float gl2 = pow(nh2, 180.0) * (0.5 + 1.5 * spark2) + pow(nh2, 26.0) * 0.12;
		EMISSION += sun_tint * gl2 * sun_glow * (1.0 - foam) * 0.8;
	}

	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.8, foam);
	METALLIC = 0.0;
	SPECULAR = 0.8;
	ALPHA = clamp(mix(0.68, 0.96, smoothstep(0.0, 0.8, depth_k)) + foam * 0.7, 0.0, 1.0);
}
