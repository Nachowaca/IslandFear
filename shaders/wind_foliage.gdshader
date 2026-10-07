shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
#include "res://shaders/foliage_push.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.2, 0.5, 0.2, 1.0);
uniform float sway = 0.15;        // metros de balanceo en la punta
uniform float base_y = 0.0;       // y local donde empieza a moverse
uniform float height_ref = 1.0;   // y local de rango completo
uniform float speed = 1.2;
uniform float flutter = 0.0;      // temblor rápido de hojas
uniform vec2 wind_dir = vec2(1.0, 0.4);
uniform float gust_strength = 1.0;
uniform float push = 1.0;
uniform float mood = 0.0;          // ánimo de la isla: -1 tensa … +1 serena

void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	float h = clamp((VERTEX.y - base_y) / height_ref, 0.0, 1.0);
	h *= h;
	float phase = dot(wp.xz, normalize(wind_dir)) * 0.18;
	float gust = 0.55 + 0.45 * sin(TIME * 0.35 + phase * 0.5);   // rachas lentas
	float tension = max(-mood, 0.0);
	float calm = max(mood, 0.0);
	float sp = speed * (1.0 + tension * 0.45 - calm * 0.15);
	float g = sin(TIME * sp + phase) + 0.5 * sin(TIME * speed * 2.3 + phase * 1.7);
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * g * sway * h * gust * gust_strength * (1.0 + tension * 0.7 - calm * 0.2);
	off += vec3(sin(TIME * 6.0 + wp.x * 3.0 + VERTEX.x * 4.0), 0.3 * sin(TIME * 5.0 + wp.z * 3.0), cos(TIME * 7.0 + wp.z * 3.0 + VERTEX.z * 4.0)) * (flutter + tension * 0.018) * h;
	off += foliage_push(wp, sqrt(clamp((VERTEX.y - base_y) / height_ref, 0.0, 1.0)), push);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	vec3 c = albedo.rgb;
	float tn = max(-mood, 0.0);
	float cm = max(mood, 0.0);
	c = mix(c, vec3(dot(c, vec3(0.3, 0.59, 0.11))), tn * 0.3);
	c *= 1.0 - tn * 0.14 + cm * 0.05;
	c = mix(c, c * vec3(1.06, 1.03, 0.9), cm * 0.5);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
