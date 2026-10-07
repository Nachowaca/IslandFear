shader_type spatial;

// Roca con tono propio (tint.rgb), musgo en las caras que miran arriba (tint.a = cantidad) y mugre en la base.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.3);
uniform float local_unit = 1.0;       // 0.01 para los FBX en centímetros

varying vec3 wnrm;
varying vec3 wpos;
varying float ly;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ly = VERTEX.y / local_unit;
}

void fragment() {
	vec3 t = texture(albedo_tex, UV).rgb * vec3(1.9, 1.9, 2.0) * tint.rgb;
	float n1 = vnoise(wpos * 0.9) * 0.6 + vnoise(wpos * 2.7) * 0.4;
	float n2 = vnoise(wpos * 1.7 + 13.0);
	t *= 0.8 + n1 * 0.45;                                     // manchas de tono dentro de la misma roca
	// musgo arriba y un poco en la base húmeda
	float up = wnrm.y;
	float moss = smoothstep(0.3, 0.72, up + (n2 - 0.5) * 0.7) * tint.a;
	moss += (1.0 - smoothstep(0.0, 0.7, ly)) * tint.a * 0.5 * smoothstep(0.35, 0.65, n1);
	vec3 moss_c = mix(vec3(0.16, 0.3, 0.1), vec3(0.28, 0.4, 0.14), n2);
	t = mix(t, moss_c, clamp(moss, 0.0, 0.85));
	// mugre de tierra al pie
	float dirt = (1.0 - smoothstep(0.0, 0.4, ly)) * smoothstep(0.25, 0.65, n2);
	t = mix(t, vec3(0.26, 0.19, 0.12), dirt * 0.7);
	ALBEDO = t;
	ROUGHNESS = 1.0;
}
