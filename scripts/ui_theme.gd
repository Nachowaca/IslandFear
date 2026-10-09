class_name UiTheme
extends RefCounted

## Estilo visual único de la interfaz: mar profundo, madera de naufragio, latón y turquesa.
## Fuentes: Cinzel (títulos) y Alegreya Sans (texto), ambas libres (OFL).

const BODY: Font = preload("res://assets/ui/Alegreya.ttf")
const BOLD: Font = preload("res://assets/ui/AlegreyaBold.ttf")
const TITLE: Font = preload("res://assets/ui/Cinzel.ttf")
const WOOD: Texture2D = preload("res://assets/generated/ui_panel_tile.png")

const C_TEXT := Color(0.94, 0.96, 0.92)
const C_DIM := Color(0.66, 0.74, 0.76)
const C_TEAL := Color(0.47, 0.9, 0.82)
const C_BRASS := Color(0.8, 0.64, 0.34)
const C_BRASS_DK := Color(0.45, 0.34, 0.16)
const C_BAD := Color(0.96, 0.38, 0.32)
const C_GOOD := Color(0.52, 0.92, 0.55)
const C_BG := Color(0.025, 0.06, 0.08, 0.92)

const BASE_SIZE: int = 22

static var _icons: Dictionary = {}

static var _sans: Font

## Tipografía sans del sistema, estilo Helvetica (para textos largos y frases de la isla).
static func sans() -> Font:
	if _sans == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Helvetica Neue", "Helvetica", "Arial", "Liberation Sans", "sans-serif"])
		f.font_weight = 500
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_sans = f
	return _sans

static func apply_default_font() -> void:
	var t: Theme = ThemeDB.get_default_theme()
	if t != null:
		t.default_font = BODY
		t.default_font_size = BASE_SIZE

static func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var path: String = "res://assets/generated/ui_icon_%s.png" % id
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		elif FileAccess.file_exists(path):          # recién generado y sin importar: se lee la imagen directo
			var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null:
				tex = ImageTexture.create_from_image(img)
		if tex == null:
			tex = IconRender.get_icon(id)          # sin PNG: se dibuja el modelo 3D del objeto
		if tex == null:
			return null
		_icons[id] = tex
	return _icons[id]

static func panel_style(radius: int = 10, border: Color = C_BRASS, bg: Color = C_BG, border_w: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.anti_aliasing = true
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	s.content_margin_left = 18.0
	s.content_margin_right = 18.0
	s.content_margin_top = 12.0
	s.content_margin_bottom = 12.0
	return s

static var _madera: Texture2D
static var _perga: Texture2D

static func _tex(path: String, fallback: Texture2D) -> Texture2D:
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path) as Texture2D
		if t != null:
			return t
	if FileAccess.file_exists(path):
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			return ImageTexture.create_from_image(img)
	return fallback

## Madera de barco gastada (textura de naufragio).
static func madera() -> Texture2D:
	if _madera == null:
		_madera = _tex("res://assets/generated/ui_madera_naufragio.png", WOOD)
	return _madera

## Pergamino viejo.
static func pergamino() -> Texture2D:
	if _perga == null:
		_perga = _tex("res://assets/generated/ui_pergamino.png", WOOD)
	return _perga

## Contorno algo irregular (madera astillada), determinista segun el rectangulo.
static func _jitter_outline(r: Rect2, amp: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var step: float = 22.0
	var seed_v: int = int(r.size.x * 7.0 + r.size.y * 13.0)
	var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for c: int in 4:
		var p0: Vector2 = corners[c]
		var p1: Vector2 = corners[(c + 1) % 4]
		var n: int = maxi(int(p0.distance_to(p1) / step), 1)
		var dir: Vector2 = (p1 - p0) / float(n)
		var nrm: Vector2 = Vector2(-dir.y, dir.x).normalized()
		for i: int in n:
			var h: float = sin(float(seed_v + c * 101 + i * 37) * 12.9898) * 43758.5453
			var j: float = (h - floorf(h)) - 0.5
			var off: Vector2 = nrm * j * amp * (0.0 if i == 0 else 1.0)
			pts.append(p0 + dir * float(i) + off)
	pts.append(pts[0])
	return pts

static func _nail(ci: CanvasItem, p: Vector2, rad: float = 2.6) -> void:
	ci.draw_circle(p + Vector2(0.8, 1.0), rad, Color(0, 0, 0, 0.5))
	ci.draw_circle(p, rad, C_BRASS_DK)
	ci.draw_circle(p + Vector2(-0.6, -0.6), rad * 0.5, Color(0.95, 0.8, 0.5))

## Esquina de refuerzo de laton con dos clavos.
static func _corner(ci: CanvasItem, p: Vector2, sx: float, sy: float, col: Color) -> void:
	var arm: float = 26.0
	var t: float = 7.0
	var dk: Color = Color(col.r * 0.55, col.g * 0.5, col.b * 0.4, 1.0)
	var h := Rect2(p.x if sx > 0.0 else p.x - arm, p.y if sy > 0.0 else p.y - t, arm, t)
	var v := Rect2(p.x if sx > 0.0 else p.x - t, p.y if sy > 0.0 else p.y - arm, t, arm)
	for rr: Rect2 in [h, v]:
		ci.draw_rect(rr, dk)
		ci.draw_rect(rr.grow(-1.0), Color(col.r * 0.8, col.g * 0.78, col.b * 0.7, 1.0))
		ci.draw_line(rr.position + Vector2(1, 1), Vector2(rr.end.x - 1.0, rr.position.y + 1.0), Color(1, 0.9, 0.6, 0.35), 1.0)
	_nail(ci, p + Vector2(sx * 4.0, sy * 4.0), 2.4)
	_nail(ci, p + Vector2(sx * 17.0, sy * 3.5), 1.8)
	_nail(ci, p + Vector2(sx * 3.5, sy * 17.0), 1.8)

## Cuerda trenzada alrededor de un rectangulo.
static func draw_rope(ci: CanvasItem, r: Rect2) -> void:
	var rope := Color(0.72, 0.58, 0.36, 0.95)
	var shade := Color(0.32, 0.22, 0.1, 0.9)
	ci.draw_rect(r, shade, false, 4.0)
	ci.draw_rect(r, rope, false, 2.5)
	var x: float = r.position.x + 4.0
	while x < r.end.x - 4.0:
		ci.draw_line(Vector2(x, r.position.y - 2.0), Vector2(x + 3.0, r.position.y + 2.0), shade, 1.0)
		ci.draw_line(Vector2(x, r.end.y - 2.0), Vector2(x + 3.0, r.end.y + 2.0), shade, 1.0)
		x += 6.0
	var y: float = r.position.y + 4.0
	while y < r.end.y - 4.0:
		ci.draw_line(Vector2(r.position.x - 2.0, y), Vector2(r.position.x + 2.0, y + 3.0), shade, 1.0)
		ci.draw_line(Vector2(r.end.x - 2.0, y), Vector2(r.end.x + 2.0, y + 3.0), shade, 1.0)
		y += 6.0

## Panel dibujado: tablones de naufragio, bordes irregulares, esquinas de laton y clavos.
static func draw_panel(ci: CanvasItem, r: Rect2, accent: Color = C_BRASS, rope: bool = false) -> void:
	var outline: PackedVector2Array = _jitter_outline(r, 3.0)
	ci.draw_style_box(panel_style(6, accent, C_BG, 2), r)
	ci.draw_texture_rect(madera(), r.grow(-3.0), true, Color(0.62, 0.6, 0.58, 0.82))
	ci.draw_rect(r.grow(-3.0), Color(0.02, 0.04, 0.05, 0.42))
	# juntas entre tablones
	var plank: float = 64.0
	var y: float = r.position.y + plank
	var k: int = 0
	while y < r.end.y - 20.0:
		ci.draw_line(Vector2(r.position.x + 4.0, y), Vector2(r.end.x - 4.0, y), Color(0, 0, 0, 0.6), 2.0)
		ci.draw_line(Vector2(r.position.x + 4.0, y + 2.0), Vector2(r.end.x - 4.0, y + 2.0), Color(1, 0.9, 0.7, 0.07), 1.0)
		var jx: float = r.position.x + r.size.x * (0.3 + 0.4 * float((k * 37) % 10) / 10.0)
		ci.draw_line(Vector2(jx, y - plank + 2.0), Vector2(jx, y - 2.0), Color(0, 0, 0, 0.45), 2.0)
		_nail(ci, Vector2(jx - 8.0, y - plank * 0.5), 1.8)
		_nail(ci, Vector2(jx + 8.0, y - plank * 0.5), 1.8)
		y += plank
		k += 1
	ci.draw_polyline(outline, Color(0.03, 0.02, 0.01, 0.9), 4.0, true)
	ci.draw_polyline(outline, Color(accent.r * 0.7, accent.g * 0.7, accent.b * 0.7, 0.9), 1.5, true)
	ci.draw_rect(r.grow(-8.0), Color(accent.r, accent.g, accent.b, 0.2), false, 1.0)
	if rope:
		draw_rope(ci, r.grow(-9.0))
	_corner(ci, r.position + Vector2(2, 2), 1.0, 1.0, C_BRASS)
	_corner(ci, Vector2(r.end.x - 2.0, r.position.y + 2.0), -1.0, 1.0, C_BRASS)
	_corner(ci, Vector2(r.position.x + 2.0, r.end.y - 2.0), 1.0, -1.0, C_BRASS)
	_corner(ci, r.end - Vector2(2, 2), -1.0, -1.0, C_BRASS)

## Casilla de madera con marco de laton (hotbar, baul, mochila).
static func draw_slot(ci: CanvasItem, r: Rect2, selected: bool = false, glow: float = 0.0) -> void:
	var edge: Color = C_TEAL if selected else Color(C_BRASS, 0.8)
	ci.draw_style_box(panel_style(4, edge, Color(0.04, 0.05, 0.05, 0.95), 3 if selected else 2), r)
	ci.draw_texture_rect(madera(), r.grow(-3.0), true, Color(0.7, 0.68, 0.66, 0.9))
	ci.draw_rect(r.grow(-3.0), Color(0.02, 0.03, 0.04, 0.5))
	ci.draw_rect(r.grow(-4.0), Color(0, 0, 0, 0.5), false, 1.0)
	for p: Vector2 in [r.position + Vector2(5, 5), Vector2(r.end.x - 5.0, r.position.y + 5.0), Vector2(r.position.x + 5.0, r.end.y - 5.0), r.end - Vector2(5, 5)]:
		_nail(ci, p, 1.5)
	if glow > 0.0:
		ci.draw_rect(r.grow(2.0), Color(C_TEAL, glow), false, 3.0)

## Fondo de pergamino oscurecido para filas seleccionadas (texto claro sigue legible).
static func draw_parchment(ci: CanvasItem, r: Rect2, tint: Color = Color(0.5, 0.4, 0.28, 0.75)) -> void:
	ci.draw_texture_rect(pergamino(), r, true, tint)
	ci.draw_rect(r, Color(0.05, 0.08, 0.07, 0.35))
	ci.draw_rect(r, Color(C_BRASS, 0.8), false, 1.5)

static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, color: Color = C_TEXT, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT, outline: int = 5) -> void:
	if outline > 0:
		ci.draw_string_outline(font, pos, s, align, width, size, outline, Color(0, 0, 0, 0.85))
	ci.draw_string(font, pos, s, align, width, size, color)

## Etiqueta de tecla: recuadro de latón con la letra, devuelve el ancho usado.
static func key_chip(ci: CanvasItem, pos: Vector2, key: String, size: int = 20) -> float:
	var w: float = maxf(BOLD.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0, 30.0)
	var r := Rect2(pos, Vector2(w, float(size) + 10.0))
	ci.draw_style_box(panel_style(6, C_BRASS, Color(0.16, 0.12, 0.06, 0.95), 2), r)
	ci.draw_string(BOLD, pos + Vector2(0, float(size) + 1.0), key, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(1.0, 0.92, 0.68))
	return w
