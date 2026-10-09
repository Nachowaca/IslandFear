class_name HelpUi
extends CanvasLayer

## Pantalla de ayuda (tecla H): para qué sirve cada control y cada mecánica.

const SECTIONS: Array[Dictionary] = [
	{"title": "Moverte", "rows": [
		["W A S D", "Caminar. X para retroceder."],
		["Shift", "Correr: llegás antes, pero gastás más hambre y sed."],
		["Espacio", "Saltar."],
		["Ctrl", "Agacharte: vas más lento y en silencio."],
		["Mouse", "Mirar alrededor."],
		["M", "Vista aérea de la isla."]]},
	{"title": "Actuar", "rows": [
		["E", "Recoger lo que tenés delante, beber del estanque o echar leña a una fogata."],
		["F", "Investigar: te cuenta qué es lo que mirás. Puede avisarte de peligros."],
		["R", "Probar o comer el objeto elegido. Cuidado con los hongos."],
		["Q", "Cortar. Con cuchilla: lianas y hojas. Con hacha: talar árboles."],
		["G", "Dejar el objeto elegido (Shift: todos). Una ofrenda en un lugar sagrado calma a la isla."],
		["T", "Usar el objeto en la mano: linterna, antorcha, hacha (talar), cuchilla, caña de pescar."],
		["V", "Sentarte a contemplar la isla. Cualquier movimiento te levanta."],
		["Z", "Mantener para observar con zoom desde los ojos (rueda del mouse: más o menos zoom)."]]},
	{"title": "Fabricar", "rows": [
		["C", "Combinar objetos: cuchilla, cuerda, hacha, lanza, antorcha, caña de pescar y fuego."],
		["1 – 0", "Elegir un objeto de la barra (o usá la rueda del mouse)."]]},
	{"title": "Sobrevivir", "rows": [
		["Hambre y sed", "Bajan solas. Bajo el 10 % se ponen rojas y dejás de curarte. En 0 perdés salud."],
		["Cueva", "De día te protege de la isla. De noche es una trampa."],
		["Fuego", "Da luz de noche. Mantenelo con leña."],
		["Vidas", "Tenés 7. La isla recuerda cómo jugaste."]]},
	{"title": "Sistema", "rows": [
		["H", "Mostrar u ocultar esta ayuda."],
		["I", "Ver la mente de la isla (para pruebas)."],
		["F8", "Silenciar el sonido."],
		["F11", "Pantalla completa."],
		["Esc", "Soltar el mouse."]]},
]

var _root: Control
var _h_was_down: bool = false

func _ready() -> void:
	layer = 40
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.03, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(16, UiTheme.C_BRASS, Color(0.025, 0.06, 0.08, 0.95), 3))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	panel.add_child(outer)
	outer.add_child(_label("AYUDA", UiTheme.TITLE, 42, UiTheme.C_TEAL, HORIZONTAL_ALIGNMENT_CENTER))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 56)
	outer.add_child(cols)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	right.add_theme_constant_override("separation", 12)
	cols.add_child(left)
	cols.add_child(right)
	for i in SECTIONS.size():
		(left if i < 2 else right).add_child(_section(SECTIONS[i]))
	outer.add_child(_label("Pulsá H para cerrar", UiTheme.BODY, 20, UiTheme.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))

func _label(t: String, font: Font, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _section(sec: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.add_child(_label(str(sec["title"]).to_upper(), UiTheme.TITLE, 26, UiTheme.C_BRASS))
	var sep := HSeparator.new()
	box.add_child(sep)
	for row: Array in sec["rows"]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(150, 0)
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var st: StyleBoxFlat = UiTheme.panel_style(7, UiTheme.C_BRASS, Color(0.16, 0.12, 0.06, 0.95), 2)
		st.content_margin_top = 3.0
		st.content_margin_bottom = 3.0
		st.content_margin_left = 8.0
		st.content_margin_right = 8.0
		chip.add_theme_stylebox_override("panel", st)
		chip.add_child(_label(str(row[0]), UiTheme.BOLD, 22, Color(1.0, 0.92, 0.68), HORIZONTAL_ALIGNMENT_CENTER))
		h.add_child(chip)
		var d: Label = _label(str(row[1]), UiTheme.BODY, 23, UiTheme.C_TEXT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(560, 0)
		h.add_child(d)
		box.add_child(h)
	return box

func _process(_delta: float) -> void:
	var down: bool = Input.is_physical_key_pressed(KEY_H)
	if down and not _h_was_down:
		_root.visible = not _root.visible
	_h_was_down = down
