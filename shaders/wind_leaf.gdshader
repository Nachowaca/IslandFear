shader_type spatial;
render_mode cull_disabled, specular_disabled, diffuse_lambert_wrap;
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
uniform float reach = 1.0;         // alcance del roce (plantas altas o anchas > 1)
uniform float tall = 1.0;          // cuanto sigue creciendo el balanceo por encima de height_ref (plantas altas)
uniform float near_fade = 0.0;     // follaje que desaparece (con trama) cerca de la cámara; 0 = apagado
uniform float backlight_amt = 1.0;  // brillo por transparencia (plantas del suelo: bajo)
uniform float leaf_dark = 0.85;      // oscurecido general de las hojas
uniform float shade_low = 0.72;      // cuanto se oscurece la parte baja/interior (sombreado propio)
varying float v_hk;
uniform float mood = 0.0;          // ánimo de la isla: -1 tensa/enojada … +1 serena (muy sutil)

void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	float h = clamp((VERTEX.y - base_y) / height_ref, 0.0, tall);
	h *= h;
	float phase = dot(wp.xz, normalize(wind_dir)) * 0.18 + fract(sin(dot(wp.xz, vec2(12.9898, 78.233))) * 43758.5453) * 1.6;
	float gust = 0.55 + 0.45 * sin(TIME * 0.35 + phase * 0.5);
	float tension = max(-mood, 0.0);
	float calm = max(mood, 0.0);
	float sp = speed * (1.0 + tension * 0.45 - calm * 0.15);
	float g = sin(TIME * sp + phase) + 0.5 * sin(TIME * speed * 2.3 + phase * 1.7);
	float expo = 0.7 + 0.7 * smoothstep(1.5, 9.0, wp.y) + 0.3 * (1.0 - smoothstep(0.5, 2.0, wp.y));   // más viento en lomas y en la costa, menos en el bosque bajo
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * g * sway * h * gust * gust_strength * expo * (1.0 + tension * 0.7 - calm * 0.2);
	off += vec3(sin(TIME * 5.0 + wp.x * 3.0 + VERTEX.x * 6.0), 0.3 * sin(TIME * 4.0 + wp.z * 3.0), cos(TIME * 6.0 + wp.z * 3.0 + VERTEX.z * 6.0)) * (flutter + tension * 0.018) * h;
	float hk = clamp((VERTEX.y - base_y) / max(height_ref, 0.01), 0.0, 1.0);
	vec3 vwp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	off += foliage_push_v(wp, vwp, sqrt(hk), push, reach);
	v_hk = hk;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * off);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (near_fade > 0.0) {
		float fd = smoothstep(near_fade * 0.35, near_fade, length(VERTEX));
		float nz = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (fd < nz) {
			discard;
		}
	}
	vec3 c = t.rgb * tint.rgb;
	float tn = max(-mood, 0.0);
	float cm = max(mood, 0.0);
	c = mix(c, vec3(dot(c, vec3(0.3, 0.59, 0.11))), tn * 0.3);   // tensa: se apaga y pierde color
	c *= 1.0 - tn * 0.14 + cm * 0.05;
	c = mix(c, c * vec3(1.06, 1.03, 0.9), cm * 0.5);             // serena: un poco más cálida y viva
	c = mix(vec3(dot(c, vec3(0.3, 0.59, 0.11))), c, 0.88) * leaf_dark * mix(shade_low, 1.0, smoothstep(0.0, 0.85, v_hk));
	ALBEDO = c;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	BACKLIGHT = vec3(0.16, 0.2, 0.05) * backlight_amt;
}
