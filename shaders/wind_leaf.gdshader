shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
#include "res://shaders/foliage_push.gdshaderinc"

// Follaje del MegaKit con textura (hojas recortadas) que se mece con el viento.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float sway = 0.15;
uniform float base_y = 0.0;
uniform float height_ref = 1.0;
uniform float speed = 1.2;
uniform float flutter = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.4);
uniform float gust_strength = 1.0;
uniform float push = 1.0;          // reacción al roce del jugador (0 = árboles)

void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	float h = clamp((VERTEX.y - base_y) / height_ref, 0.0, 1.0);
	h *= h;
	float phase = dot(wp.xz, normalize(wind_dir)) * 0.18;
	float gust = 0.55 + 0.45 * sin(TIME * 0.35 + phase * 0.5);
	float g = sin(TIME * speed + phase) + 0.5 * sin(TIME * speed * 2.3 + phase * 1.7);
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * g * sway * h * gust * gust_strength;
	off += vec3(sin(TIME * 5.0 + wp.x * 3.0 + VERTEX.x * 6.0), 0.3 * sin(TIME * 4.0 + wp.z * 3.0), cos(TIME * 6.0 + wp.z * 3.0 + VERTEX.z * 6.0)) * flutter * h;
	float hk = clamp((VERTEX.y - base_y) / max(height_ref, 0.01), 0.0, 1.0);
	off += foliage_push(wp, sqrt(hk), push);
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * off);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = t.rgb * tint.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.12, 0.2, 0.06);
}
