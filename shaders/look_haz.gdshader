shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

// Haz de luz falso (sol bajo entre los árboles, luna). Dos planos cruzados con borde suave:
// sin textura de profundidad, solo geometría + degradé.

uniform vec3 color : source_color = vec3(1.0, 0.85, 0.6);
uniform float intensity = 0.0;
uniform float fade_near = 3.0;
uniform float fade_far = 55.0;

varying float dist;
varying vec3 wpos;

void vertex() {
	dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ax = (UV.x * 2.0 - 1.0);
	float across = exp(-ax * ax * 3.2) * (1.0 - smoothstep(0.45, 0.95, abs(ax)));   // degradé gaussiano: sin borde de tubo
	float streak = 0.55 + 0.45 * sin(wpos.x * 0.9 + wpos.z * 0.7 + ax * 4.0 + TIME * 0.15) * sin(wpos.z * 0.6 - wpos.x * 0.4 + UV.y * 3.0);
	float along = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.5, 1.0, UV.y));
	float facing = smoothstep(0.12, 0.65, abs(dot(normalize(NORMAL), normalize(VIEW))));
	float shimmer = 0.78 + 0.22 * sin(TIME * 0.5 + wpos.x * 0.35 + wpos.z * 0.27 + UV.y * 5.0);
	float dfade = smoothstep(fade_near, fade_near + 5.0, dist) * (1.0 - smoothstep(fade_far * 0.55, fade_far, dist));
	ALBEDO = color;
	ALPHA = across * streak * along * facing * shimmer * dfade * intensity * 0.26;
}
