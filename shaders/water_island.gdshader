shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D height_tex : repeat_disable, filter_linear;
uniform vec2 height_origin = vec2(-40.5, -40.5);
uniform float height_size = 81.0;
uniform float water_y = 0.35;
uniform vec4 deep_color : source_color = vec4(0.02, 0.30, 0.50, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.25, 0.88, 0.85, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 1.0, 1.0, 1.0);
uniform float wave_height = 0.15;
uniform float wave_speed = 0.4;
uniform float wave_scale = 0.25;
uniform float clear_depth = 4.0;
uniform float foam_width = 0.6;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_glow = 0.0;      // 0..1: cuánta luna hay para reflejar
uniform vec3 moon_tint : source_color = vec3(0.85, 0.9, 1.0);
uniform vec3 sky_color : source_color = vec3(0.7, 0.8, 0.9);     // color del cielo actual (lo pone el LookDirector)
uniform vec3 zenith_color : source_color = vec3(0.2, 0.45, 0.8);
uniform float sky_reflect = 0.6;
uniform vec3 sun_dir = vec3(0.0, -1.0, 0.0);
uniform float sun_glow = 0.0;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.9, 0.7);

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
	VERTEX.y += wave(p, t) * wave_height;
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
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float depth_k = clamp(thickness / clear_depth, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 1.0, depth_k));
	col = mix(col, shallow_color.rgb * 1.2, fres * 0.5);
	col = mix(col, mix(sky_color, zenith_color, 0.35), fres * sky_reflect);       // el agua refleja el cielo del momento

	vec2 fp = world_pos.xz * 1.5;
	float n = vnoise(fp + TIME * 0.2) * 0.6 + vnoise(fp * 2.3 - TIME * 0.15) * 0.4;
	float edge = 1.0 - smoothstep(0.0, foam_width, thickness + (n - 0.5) * 0.35);
	float lapping = 0.5 + 0.5 * sin(TIME * 1.1 + thickness * 5.0);
	float foam = clamp(edge * (0.55 + 0.45 * lapping), 0.0, 1.0);
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
		float glint = pow(nh, 220.0) * (0.4 + 1.6 * sparkle) + pow(nh, 30.0) * 0.18;
		EMISSION += moon_tint * glint * moon_glow * (1.0 - foam);
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
	ALPHA = clamp(mix(0.12, 1.0, smoothstep(0.0, 0.8, depth_k)) + foam * 0.7, 0.0, 1.0);
}
