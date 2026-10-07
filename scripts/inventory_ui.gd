class_name InventoryUi
extends CanvasLayer

## Barra de objetos (10 espacios, teclas 1-9 y 0 o rueda), cartel de la acción disponible,
## avisos, texto de "investigar" y panel de combinar objetos (C). Estilo: UiTheme.

const SLOT: float = 64.0
const GAP: float = 7.0
const BAR_BOTTOM: float = 22.0

var _bar: Control
var _prompt_ctl: Control
var _prompt_parts: Array = []
var _msg: Label
var _info_panel: PanelContainer
var _info: Label
var _craft: Control
var _recipes: Array = []
var _recipe_idx: int = 0
var _msg_t: float = 0.0
var _prog: Control
var _prog_frac: float = -1.0
var _prog_text: String = ""
var _info_t: float = 0.0
var _pulse: float = 0.0

func _ready() -> void:
	layer = 19
	var w: float = float(Inventario.ESPACIOS) * (SLOT + GAP) - GAP
	_bar = Control.new()
	_bar.anchor_left = 0.5
	_bar.anchor_right = 0.5
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_left = -w * 0.5
	_bar.offset_right = w * 0.5
	_bar.offset_top = -SLOT - BAR_BOTTOM
	_bar.offset_bottom = -BAR_BOTTOM
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	Inventario.cambiado.connect(func() -> void: _bar.queue_redraw())

	_prompt_ctl = Control.new()
	_prompt_ctl.anchor_left = 0.5
	_prompt_ctl.anchor_right = 0.5
	_prompt_ctl.anchor_top = 1.0
	_prompt_ctl.anchor_bottom = 1.0
	_prompt_ctl.offset_left = -600.0
	_prompt_ctl.offset_right = 600.0
	_prompt_ctl.offset_top = -SLOT - BAR_BOTTOM - 96.0
	_prompt_ctl.offset_bottom = -SLOT - BAR_BOTTOM - 44.0
	_prompt_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_ctl.draw.connect(_draw_prompt)
	add_child(_prompt_ctl)

	_info_panel = PanelContainer.new()
	_info_panel.anchor_left = 0.5
	_info_panel.anchor_right = 0.5
	_info_panel.anchor_top = 1.0
	_info_panel.anchor_bottom = 1.0
	_info_panel.offset_left = -430.0
	_info_panel.offset_right = 430.0
	_info_panel.offset_top = -SLOT - BAR_BOTTOM - 120.0
	_info_panel.offset_bottom = -SLOT - BAR_BOTTOM - 120.0
	_info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(12, UiTheme.C_TEAL, Color(0.02, 0.06, 0.08, 0.9), 2))
	_info_panel.modulate.a = 0.0
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(800, 0)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_override("font", UiTheme.BODY)
	_info.add_theme_font_size_override("font_size", 26)
	_info.add_theme_color_override("font_color", UiTheme.C_TEXT)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.add_child(_info)
	add_child(_info_panel)

	_msg = Label.new()
	_msg.anchor_left = 0.0
	_msg.anchor_right = 1.0
	_msg.offset_top = 190.0
	_msg.offset_bottom = 250.0
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_override("font", UiTheme.BOLD)
	_msg.add_theme_font_size_override("font_size", 32)
	_msg.add_theme_color_override("font_color", UiTheme.C_TEAL)
	_msg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_msg.add_theme_constant_override("outline_size", 9)
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.modulate.a = 0.0
	add_child(_msg)

	_prog = Control.new()
	_prog.anchor_left = 0.5
	_prog.anchor_right = 0.5
	_prog.anchor_top = 0.5
	_prog.anchor_bottom = 0.5
	_prog.offset_left = -120.0
	_prog.offset_right = 120.0
	_prog.offset_top = 70.0
	_prog.offset_bottom = 290.0
	_prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prog.visible = false
	_prog.draw.connect(_draw_prog)
	add_child(_prog)

	_craft = Control.new()
	_craft.anchor_top = 0.5
	_craft.anchor_bottom = 0.5
	_craft.offset_left = 30.0
	_craft.offset_top = -270.0
	_craft.size = Vector2(600, 540)
	_craft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_craft.visible = false
	_craft.draw.connect(_draw_craft)
	add_child(_craft)

# ------------------------------------------------------------------ API

## Formato: "E: recoger Bayas    F: investigar" (se separa en teclas y acciones).
func set_prompt(text: String) -> void:
	_prompt_parts.clear()
	if text != "":
		for part: String in text.split("    "):
			var i: int = part.find(": ")
			if i > 0:
				_prompt_parts.append({"key": part.substr(0, i), "txt": part.substr(i + 2)})
	_prompt_ctl.queue_redraw()

func message(text: String) -> void:
	_msg.text = text
	_msg_t = 2.8

func show_info(text: String) -> void:
	_info.text = text
	_info_t = 10.0

func show_recipes(list: Array, idx: int) -> void:
	_recipes = list
	_recipe_idx = idx
	_craft.visible = true
	_craft.queue_redraw()

## Círculo de espera mientras el náufrago fabrica (frac 0..1). frac < 0 lo oculta.
func set_progress(frac: float, text: String = "") -> void:
	_prog_frac = frac
	_prog_text = text
	_prog.visible = frac >= 0.0
	if _prog.visible:
		_prog.queue_redraw()

func _draw_prog() -> void:
	var c: Vector2 = Vector2(120.0, 90.0)
	_prog.draw_circle(c, 58.0, Color(0.02, 0.06, 0.08, 0.78))
	_prog.draw_arc(c, 50.0, 0.0, TAU, 48, Color(UiTheme.C_BRASS, 0.35), 5.0, true)
	_prog.draw_arc(c, 50.0, -PI * 0.5, -PI * 0.5 + TAU * _prog_frac, 48, UiTheme.C_TEAL, 6.0, true)
	for i in 3:                                              # puntitos que giran: la isla y el náufrago "piensan"
		var a: float = _pulse * 3.2 + float(i) * TAU / 3.0
		_prog.draw_circle(c + Vector2(cos(a), sin(a)) * 30.0, 4.5 - float(i) * 0.9, Color(UiTheme.C_TEXT, 0.9))
	UiTheme.text(_prog, UiTheme.BOLD, Vector2(0, 186.0), _prog_text, 22, UiTheme.C_TEXT, 240.0, HORIZONTAL_ALIGNMENT_CENTER, 5)

func hide_recipes() -> void:
	_craft.visible = false

func _process(delta: float) -> void:
	_pulse += delta
	if _msg_t > 0.0:
		_msg_t -= delta
		_msg.modulate.a = clampf(_msg_t / 0.7, 0.0, 1.0)
	if _info_t > 0.0:
		_info_t -= delta
		_info_panel.modulate.a = clampf(_info_t / 1.2, 0.0, 1.0)
	elif _info_panel.modulate.a > 0.0:
		_info_panel.modulate.a = 0.0
	_bar.queue_redraw()
	if _prog.visible:
		_prog.queue_redraw()

# ------------------------------------------------------------------ dibujo

func _draw_prompt() -> void:
	if _prompt_parts.is_empty():
		return
	var size: int = 24
	var total: float = 28.0
	for p: Dictionary in _prompt_parts:
		total += maxf(UiTheme.BOLD.get_string_size(str(p["key"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0, 30.0) + 10.0
		total += UiTheme.BODY.get_string_size(str(p["txt"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 26.0
	var w: float = _prompt_ctl.size.x
	var x: float = (w - total) * 0.5
	var r := Rect2(x, 4.0, total, 46.0)
	_prompt_ctl.draw_style_box(UiTheme.panel_style(16, Color(UiTheme.C_BRASS, 0.6), Color(0.02, 0.05, 0.07, 0.78), 1), r)
	var cx: float = x + 16.0
	for p: Dictionary in _prompt_parts:
		var kw: float = UiTheme.key_chip(_prompt_ctl, Vector2(cx, 11.0), str(p["key"]), 20)
		cx += kw + 10.0
		UiTheme.text(_prompt_ctl, UiTheme.BODY, Vector2(cx, 36.0), str(p["txt"]), size, UiTheme.C_TEXT, -1.0, HORIZONTAL_ALIGNMENT_LEFT, 3)
		cx += UiTheme.BODY.get_string_size(str(p["txt"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 26.0

func _draw_bar() -> void:
	var sel_e: Variant = Inventario.item_seleccionado()
	if sel_e != null:
		var sid: String = str(sel_e["id"])
		var nm: String = ItemDB.display_name(sid)
		var suf: String = "" if Inventario.descubiertos.has(sid) else "   (sin investigar)"
		UiTheme.text(_bar, UiTheme.BOLD, Vector2(0, -12.0), nm + suf, 24, UiTheme.C_TEXT, _bar.size.x, HORIZONTAL_ALIGNMENT_CENTER, 5)
	for i in Inventario.ESPACIOS:
		var r := Rect2(float(i) * (SLOT + GAP), 0.0, SLOT, SLOT)
		var sel: bool = i == Inventario.seleccionado
		var edge: Color = UiTheme.C_TEAL if sel else Color(UiTheme.C_BRASS, 0.55)
		_bar.draw_style_box(UiTheme.panel_style(10, edge, Color(0.03, 0.07, 0.09, 0.9), 3 if sel else 1), r)
		_bar.draw_texture_rect(UiTheme.WOOD, r.grow(-3.0), true, Color(1, 1, 1, 0.25))
		if sel:
			var glow: float = 0.25 + 0.1 * sin(_pulse * 3.0)
			_bar.draw_rect(r.grow(2.0), Color(UiTheme.C_TEAL, glow), false, 3.0)
		UiTheme.text(_bar, UiTheme.BODY, r.position + Vector2(7, 18), str((i + 1) % 10), 15, Color(0.72, 0.8, 0.82, 0.8), -1.0, HORIZONTAL_ALIGNMENT_LEFT, 3)
		var e: Variant = Inventario.espacios[i]
		if e == null:
			continue
		var id: String = str(e["id"])
		var tex: Texture2D = UiTheme.icon(id)
		if tex != null:
			_bar.draw_texture_rect(tex, Rect2(r.position + Vector2(6, 6), Vector2(SLOT - 12.0, SLOT - 12.0)), false)
		if int(e["n"]) > 1:
			UiTheme.text(_bar, UiTheme.BOLD, r.position + Vector2(0, SLOT - 6.0), str(int(e["n"])), 22, Color(1, 0.96, 0.8), SLOT - 7.0, HORIZONTAL_ALIGNMENT_RIGHT, 6)

func _draw_craft() -> void:
	var rows: int = _recipes.size()
	var h: float = 86.0 + 84.0 * float(rows)
	UiTheme.draw_panel(_craft, Rect2(0, 0, 600, h), UiTheme.C_TEAL)
	UiTheme.text(_craft, UiTheme.TITLE, Vector2(28, 46), "COMBINAR", 30, UiTheme.C_TEAL, -1.0, HORIZONTAL_ALIGNMENT_LEFT, 5)
	UiTheme.text(_craft, UiTheme.BODY, Vector2(0, 46), "Rueda o ↑↓: elegir     E: fabricar     C: cerrar", 17, UiTheme.C_DIM, 572.0, HORIZONTAL_ALIGNMENT_RIGHT, 3)
	for i in rows:
		var rc: Dictionary = _recipes[i]
		var y: float = 66.0 + 84.0 * float(i)
		var sel: bool = i == _recipe_idx
		var ok: bool = bool(rc["ok"])
		var row := Rect2(14, y, 572, 78)
		if sel:
			_craft.draw_style_box(UiTheme.panel_style(10, UiTheme.C_TEAL, Color(0.1, 0.28, 0.3, 0.55), 2), row)
		var tex: Texture2D = UiTheme.icon(str(rc["icon"]))
		if tex != null:
			_craft.draw_texture_rect(tex, Rect2(24, y + 9, 58, 58), false, Color.WHITE if ok else Color(0.55, 0.55, 0.6, 0.7))
		var col: Color = UiTheme.C_GOOD if ok else UiTheme.C_DIM
		UiTheme.text(_craft, UiTheme.BOLD, Vector2(96, y + 28), str(rc["name"]), 24, col, -1.0, HORIZONTAL_ALIGNMENT_LEFT, 4)
		UiTheme.text(_craft, UiTheme.BODY, Vector2(96, y + 52), "Necesita: %s" % str(rc["ing"]), 19, UiTheme.C_TEXT if ok else Color(0.95, 0.6, 0.55), 480.0, HORIZONTAL_ALIGNMENT_LEFT, 3)
		if sel:
			UiTheme.text(_craft, UiTheme.BODY, Vector2(96, y + 72), str(rc["desc"]), 16, UiTheme.C_DIM, 480.0, HORIZONTAL_ALIGNMENT_LEFT, 2)
