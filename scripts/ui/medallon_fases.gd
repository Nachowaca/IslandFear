class_name MedallonFases
extends Control
## Medallón de latón con el cielo de la isla: sol, luna con su fase real y un arco del avance del día. Sin números.

const MARCO: Texture2D = preload("res://assets/generated/ui_medallon_marco.png")
const C_ARCO: Color = Color(0.25, 0.78, 0.72, 0.9)
const C_AGUJA: Color = Color(0.95, 0.8, 0.4)
const RADIO_CIELO: float = 0.70   # relación con el radio total (el hueco del marco)

@export var diametro: float = 96.0:
	set(v):
		diametro = maxf(v, 8.0)
		custom_minimum_size = Vector2(diametro, diametro)
		size = Vector2(diametro, diametro)
		queue_redraw()

var _hora: float = 12.0
var _luz_luna: float = 1.0
var _estrellas: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(diametro, diametro)
	size = Vector2(diametro, diametro)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 26:
		var ang: float = rng.randf() * TAU
		var rr: float = sqrt(rng.randf()) * 0.95
		_estrellas.append(Vector2(cos(ang), sin(ang)) * rr)

func actualizar(hora: float, luz_luna: float) -> void:
	_hora = fposmod(hora, 24.0)
	_luz_luna = clampf(luz_luna, 0.0, 1.0)
	queue_redraw()

func _circulo(c: Vector2, r: float, n: int = 40) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r_tot: float = minf(size.x, size.y) * 0.5
	var r_in: float = r_tot * RADIO_CIELO
	# --- altura del sol (a: 0 amanecer a PI atardecer) ---
	var a_sol: float = (_hora - 6.0) / 12.0 * PI
	var s: float = sin(a_sol)
	var dia: float = smoothstep(-0.2, 0.3, s)
	var calido: float = (1.0 - smoothstep(0.0, 0.55, absf(s + 0.05))) * smoothstep(-0.4, -0.05, s)
	var top: Color = Color(0.02, 0.04, 0.12).lerp(Color(0.25, 0.55, 0.85), dia)
	var bajo: Color = Color(0.05, 0.08, 0.2).lerp(Color(0.6, 0.82, 0.92), dia)
	var tinte_alto: Color = Color(0.95, 0.5, 0.25) if _hora < 12.0 else Color(0.85, 0.3, 0.2)
	bajo = bajo.lerp(tinte_alto, calido * 0.85)
	top = top.lerp(Color(0.45, 0.35, 0.55), calido * 0.4)
	# cielo con degradado vertical
	var pts: PackedVector2Array = _circulo(c, r_in, 48)
	var cols: PackedColorArray = PackedColorArray()
	for p: Vector2 in pts:
		var t: float = clampf((p.y - (c.y - r_in)) / (2.0 * r_in), 0.0, 1.0)
		cols.append(top.lerp(bajo, smoothstep(0.1, 0.75, t)))
	draw_polygon(pts, cols)
	# estrellas
	var noche: float = 1.0 - dia
	if noche > 0.02:
		for e: Vector2 in _estrellas:
			var pe: Vector2 = c + e * r_in
			draw_circle(pe, maxf(r_tot * 0.012, 0.7), Color(1, 1, 0.9, noche * 0.85))
	var horizonte: Vector2 = c + Vector2(0.0, r_in * 0.25)
	var radio_arco: float = r_in * 0.72
	# sol
	if s > -0.15:
		var pos_s: Vector2 = horizonte + Vector2(-cos(a_sol), -sin(a_sol)) * radio_arco
		var col_s: Color = Color(1.0, 0.85, 0.35).lerp(Color(1.0, 0.45, 0.15), calido)
		var rs: float = r_in * 0.15
		draw_circle(pos_s, rs * 2.0, Color(col_s.r, col_s.g, col_s.b, 0.18))
		draw_circle(pos_s, rs * 1.4, Color(col_s.r, col_s.g, col_s.b, 0.25))
		draw_circle(pos_s, rs, col_s)
	# luna con fase
	var mu: float = fposmod(_hora - 19.0, 24.0) / 12.0
	if mu <= 1.0:
		var a_l: float = mu * PI
		var pos_l: Vector2 = horizonte + Vector2(-cos(a_l), -sin(a_l)) * radio_arco
		var rl: float = r_in * 0.17
		var vis: float = clampf(sin(a_l) * 4.0, 0.0, 1.0) * noche
		draw_circle(pos_l, rl * 1.7, Color(0.7, 0.8, 1.0, 0.12 * vis * (0.3 + _luz_luna)))
		draw_circle(pos_l, rl, Color(0.12, 0.14, 0.22, vis))
		var lit: PackedVector2Array = PackedVector2Array()
		var k: float = 1.0 - 2.0 * _luz_luna
		var n: int = 20
		for i: int in n + 1:
			var th: float = PI * 0.5 - PI * float(i) / float(n)
			lit.append(pos_l + Vector2(cos(th), -sin(th)) * rl)
		for i: int in range(1, n):
			var th2: float = -PI * 0.5 + PI * float(i) / float(n)
			lit.append(pos_l + Vector2(k * cos(th2), -sin(th2)) * rl)
		if _luz_luna > 0.03 and lit.size() >= 3:
			draw_colored_polygon(lit, Color(0.93, 0.93, 0.85, vis))
	# mar / horizonte
	var mar: PackedVector2Array = PackedVector2Array()
	var y_h: float = horizonte.y
	for i: int in 25:
		var a2: float = PI * float(i) / 24.0
		var px: float = c.x + cos(a2) * r_in
		var py: float = c.y + sin(a2) * r_in
		if py >= y_h:
			mar.append(Vector2(px, py))
	var dx: float = sqrt(maxf(r_in * r_in - (y_h - c.y) * (y_h - c.y), 0.0))
	mar.insert(0, Vector2(c.x + dx, y_h))
	mar.append(Vector2(c.x - dx, y_h))
	if mar.size() >= 3:
		var col_mar: Color = Color(0.02, 0.06, 0.1).lerp(Color(0.05, 0.3, 0.38), dia).lerp(Color(0.5, 0.25, 0.15), calido * 0.4)
		draw_colored_polygon(mar, col_mar)
	# viñeta de vidrio oscuro
	draw_arc(c, r_in - r_tot * 0.02, 0.0, TAU, 48, Color(0, 0, 0, 0.35), r_tot * 0.06)
	draw_arc(c, r_in * 0.78, PI * 1.1, PI * 1.55, 16, Color(1, 1, 1, 0.12), maxf(r_tot * 0.03, 1.0))
	# marco de latón encima
	draw_texture_rect(MARCO, Rect2(Vector2.ZERO, size), false)
	# arco del avance del día (turquesa) sobre el borde interior + aguja
	var ang0: float = -PI * 0.5
	var ang_h: float = ang0 + _hora / 24.0 * TAU
	var r_marca: float = r_tot * 0.745
	if ang_h > ang0 + 0.01:
		draw_arc(c, r_marca, ang0, ang_h, 48, C_ARCO, maxf(r_tot * 0.04, 1.5))
	var dir: Vector2 = Vector2(cos(ang_h), sin(ang_h))
	draw_line(c + dir * r_tot * 0.62, c + dir * r_tot * 0.9, Color(0.1, 0.06, 0.02), maxf(r_tot * 0.075, 2.5))
	draw_line(c + dir * r_tot * 0.63, c + dir * r_tot * 0.89, C_AGUJA, maxf(r_tot * 0.045, 1.5))
	draw_circle(c + dir * r_tot * 0.9, maxf(r_tot * 0.05, 1.8), C_AGUJA)
