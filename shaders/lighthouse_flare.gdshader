shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 flare_color : source_color = vec4(1.0, 0.9, 0.65, 1.0);
uniform float intensity = 1.0;

void vertex() {
	// siempre mira a la cámara (billboard)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[0][0] = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX[1][1] = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX[2][2] = length(MODEL_MATRIX[2].xyz);
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float core = pow(clamp(1.0 - d, 0.0, 1.0), 6.0) * 2.0;
	float halo = pow(clamp(1.0 - d, 0.0, 1.0), 2.2) * 0.35;
	// destello en cruz
	vec2 q = abs(UV - vec2(0.5)) * 2.0;
	float streak = pow(clamp(1.0 - q.x, 0.0, 1.0), 14.0) * pow(clamp(1.0 - q.y * 6.0, 0.0, 1.0), 1.0) * 0.7
		+ pow(clamp(1.0 - q.y, 0.0, 1.0), 14.0) * pow(clamp(1.0 - q.x * 6.0, 0.0, 1.0), 1.0) * 0.3;
	ALBEDO = flare_color.rgb * (core + halo + streak) * intensity;
	ALPHA = clamp((core + halo + streak) * intensity, 0.0, 1.0);
}
