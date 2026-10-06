shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D height_tex : repeat_disable, filter_linear;
uniform vec2 height_origin = vec2(-40.5, -40.5);
uniform float height_size = 81.0;
uniform float water_y = 0.35;
uniform vec4 deep_color : source_color = vec4(0.03, 0.2, 0.38, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.12, 0.62, 0.7, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 1.0, 1.0, 1.0);
uniform float wave_height = 0.15;
uniform float wave_speed = 0.4;
uniform float wave_scale = 0.25;
uniform float clear_depth = 2.5;
uniform float foam_width = 0.6;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_glow = 0.0;      // 0..1: cuánta luna hay para reflejar
uniform vec3 moon_tint : source_color = vec3(0.85, 0.9, 1.0);

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

	vec2 fp = world_pos.xz * 1.5;
	float n = vnoise(fp + TIME * 0.2) * 0.6 + vnoise(fp * 2.3 - TIME * 0.15) * 0.4;
	float edge = 1.0 - smoothstep(0.0, foam_width, thickness + (n - 0.5) * 0.35);
	float lapping = 0.5 + 0.5 * sin(TIME * 1.1 + thickness * 5.0);
	float foam = clamp(edge * (0.55 + 0.45 * lapping), 0.0, 1.0);
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

	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.8, foam);
	METALLIC = 0.0;
	SPECULAR = 0.8;
	ALPHA = clamp(mix(0.25, 1.0, smoothstep(0.0, 0.9, depth_k)) + foam * 0.7, 0.0, 1.0);
}
