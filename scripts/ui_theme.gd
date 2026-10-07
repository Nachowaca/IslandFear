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

## Panel dibujado: fondo oscuro, veta de madera tenue, doble borde y remaches.
static func draw_panel(ci: CanvasItem, r: Rect2, accent: Color = C_BRASS) -> void:
	ci.draw_style_box(panel_style(10, accent, C_BG, 2), r)
	ci.draw_texture_rect(WOOD, r.grow(-4.0), true, Color(1, 1, 1, 0.28))
	ci.draw_rect(r.grow(-6.0), Color(accent.r, accent.g, accent.b, 0.22), false, 1.0)
	for p: Vector2 in [r.position + Vector2(10, 10), Vector2(r.end.x - 10, r.position.y + 10), Vector2(r.position.x + 10, r.end.y - 10), r.end - Vector2(10, 10)]:
		ci.draw_circle(p, 2.6, C_BRASS_DK)
		ci.draw_circle(p + Vector2(-0.6, -0.6), 1.2, accent)

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
