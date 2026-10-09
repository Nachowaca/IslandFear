class_name CofreUi
extends CanvasLayer

## Panel del baúl: 30 celdas (6 x 5) arriba y la mochila (10) abajo. Mismo estilo que la barra de objetos.
## Clic izquierdo: pasa toda la pila al otro lado. Clic derecho: pasa una unidad. E o "Cerrar": cierra.

const CELL: float = 66.0
const GAP: float = 8.0
const COLS: int = 6
const PW: float = 860.0
const GRID_TOP: float = 78.0

var abierto: bool = false
var _root: Control
var _cofre: CofrePlaya
var _hover_cofre: int = -1
var _hover_mochila: int = -1
var _hover_cerrar: bool = false
var _pulse: float = 0.0
var _drag_cofre: bool = false      ## arrastrando: de donde sale
var _drag_i: int = -1
var _drag_todo: bool = true
var _mouse: Vector2 = Vector2.ZERO

func _ready() -> void:
	layer = 21
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	_root.draw.connect(_draw_all)
	_root.gui_input.connect(_on_gui)
	add_child(_root)
	Inventario.cambiado.connect(func() -> void:
		if abierto:
			_root.queue_redraw())

func abrir(cofre: CofrePlaya) -> void:
	_cofre = cofre
	abierto = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _cofre != null:
		_cofre.set_abierto(true)
	_root.queue_redraw()

func cerrar() -> void:
	if not abierto:
		return
	abierto = false
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _cofre != null and is_instance_valid(_cofre):
		_cofre.set_abierto(false)

## Con el baúl abierto, las teclas 1-0 guardan lo que hay en esa casilla de la barra (Shift: una sola unidad).
func _input(event: InputEvent) -> void:
	if not abierto or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: Key = (event as InputEventKey).physical_keycode
	var idx: int = -1
	if k >= KEY_1 and k <= KEY_9:
		idx = int(k) - int(KEY_1)
	elif k == KEY_0:
		idx = 9
	if idx >= 0:
		Inventario.mover(false, idx, 1 if (event as InputEventKey).shift_pressed else 99)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if abierto:
		_pulse += delta
		_root.queue_redraw()

# ------------------------------------------------------------------ geometría

func _panel() -> Rect2:
	var h: float = GRID_TOP + 5.0 * (CELL + GAP) + 54.0 + CELL + 50.0
	var sz: Vector2 = _root.size
	return Rect2((sz.x - PW) * 0.5, (sz.y - h) * 0.5, PW, h)

func _rect_cofre(i: int) -> Rect2:
	var pn: Rect2 = _panel()
	var gw: float = float(COLS) * (CELL + GAP) - GAP
	var x: float = pn.position.x + (PW - gw) * 0.5 + float(i % COLS) * (CELL + GAP)
	var y: float = pn.position.y + GRID_TOP + floorf(float(i) / float(COLS)) * (CELL + GAP)
	return Rect2(x, y, CELL, CELL)

func _rect_mochila(j: int) -> Rect2:
	var pn: Rect2 = _panel()
	var gw: float = float(Inventario.ESPACIOS) * (CELL + GAP) - GAP
	var x: float = pn.position.x + (PW - gw) * 0.5 + float(j) * (CELL + GAP)
	var y: float = pn.position.y + GRID_TOP + 5.0 * (CELL + GAP) + 54.0
	return Rect2(x, y, CELL, CELL)

func _rect_cerrar() -> Rect2:
	var pn: Rect2 = _panel()
	return Rect2(pn.end.x - 190.0, pn.position.y + 16.0, 166.0, 40.0)

# ------------------------------------------------------------------ entrada

func _slot_en(pos: Vector2) -> Vector2i:
	# x: 0 = baul, 1 = mochila; y: indice (-1 = ninguna)
	for i in Inventario.COFRE_ESPACIOS:
		if _rect_cofre(i).has_point(pos):
			return Vector2i(0, i)
	for j in Inventario.ESPACIOS:
		if _rect_mochila(j).has_point(pos):
			return Vector2i(1, j)
	return Vector2i(0, -1)

func _on_gui(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pos: Vector2 = (event as InputEventMouseMotion).position
		_mouse = pos
		_hover_cofre = -1
		_hover_mochila = -1
		_hover_cerrar = _rect_cerrar().has_point(pos)
		var sl: Vector2i = _slot_en(pos)
		if sl.y >= 0:
			if sl.x == 0:
				_hover_cofre = sl.y
			else:
				_hover_mochila = sl.y
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		var sl2: Vector2i = _slot_en(mb.position)
		if mb.pressed:
			if _rect_cerrar().has_point(mb.position):
				cerrar()
			elif sl2.y >= 0:
				var lista: Array = Inventario.cofre if sl2.x == 0 else Inventario.espacios
				if lista[sl2.y] != null:
					_drag_cofre = sl2.x == 0
					_drag_i = sl2.y
					_drag_todo = mb.button_index == MOUSE_BUTTON_LEFT
		elif _drag_i >= 0:
			# soltar: sobre el otro lado (o con un clic en la misma celda) pasa al otro lado
			var pasa: bool = false
			if sl2.y >= 0:
				var destino_cofre: bool = sl2.x == 0
				pasa = destino_cofre != _drag_cofre or (sl2.y == _drag_i)
			else:
				pasa = false
			if pasa:
				Inventario.mover(_drag_cofre, _drag_i, 99 if _drag_todo else 1)
			_drag_i = -1
	_root.accept_event()

# ------------------------------------------------------------------ dibujo

func _draw_slot(r: Rect2, e: Variant, hover: bool) -> void:
	UiTheme.draw_slot(_root, r, hover, (0.25 + 0.1 * sin(_pulse * 3.0)) if hover else 0.0)
	if e == null:
		return
	var tex: Texture2D = UiTheme.icon(str(e["id"]))
	if tex != null:
		_root.draw_texture_rect(tex, Rect2(r.position + Vector2(6, 6), Vector2(CELL - 12.0, CELL - 12.0)), false)
	if int(e["n"]) > 1:
		UiTheme.text(_root, UiTheme.BOLD, r.position + Vector2(0, CELL - 6.0), str(int(e["n"])), 22, Color(1, 0.96, 0.8), CELL - 7.0, HORIZONTAL_ALIGNMENT_RIGHT, 6)

func _draw_all() -> void:
	_root.draw_rect(Rect2(Vector2.ZERO, _root.size), Color(0, 0, 0, 0.55))
	var pn: Rect2 = _panel()
	UiTheme.draw_panel(_root, pn, UiTheme.C_BRASS, true)
	UiTheme.text(_root, UiTheme.TITLE, pn.position + Vector2(34, 52), "BAÚL DEL NÁUFRAGO", 28, UiTheme.C_BRASS, -1.0, HORIZONTAL_ALIGNMENT_LEFT, 5)
	UiTheme.text(_root, UiTheme.BODY, pn.position + Vector2(400, 40), "Clic o arrastrar: pasar pila   ·   Clic der.: una unidad", 17, UiTheme.C_DIM, -1.0, HORIZONTAL_ALIGNMENT_LEFT, 3)
	UiTheme.text(_root, UiTheme.BODY, pn.position + Vector2(400, 62), "1-0: guardar casilla (Shift: una sola)", 17, UiTheme.C_DIM, -1.0, HORIZONTAL_ALIGNMENT_LEFT, 3)
	var rc: Rect2 = _rect_cerrar()
	_root.draw_style_box(UiTheme.panel_style(10, UiTheme.C_TEAL if _hover_cerrar else Color(UiTheme.C_BRASS, 0.6), Color(0.05, 0.1, 0.12, 0.9), 2), rc)
	UiTheme.text(_root, UiTheme.BOLD, rc.position + Vector2(0, 28), "Cerrar  (E)", 22, UiTheme.C_TEXT, rc.size.x, HORIZONTAL_ALIGNMENT_CENTER, 4)
	for i in Inventario.COFRE_ESPACIOS:
		_draw_slot(_rect_cofre(i), Inventario.cofre[i], i == _hover_cofre)
	UiTheme.text(_root, UiTheme.BOLD, _rect_mochila(0).position + Vector2(0, -10.0), "MOCHILA", 22, UiTheme.C_BRASS, -1.0, HORIZONTAL_ALIGNMENT_LEFT, 4)
	for j in Inventario.ESPACIOS:
		_draw_slot(_rect_mochila(j), Inventario.espacios[j], j == _hover_mochila)
	if _drag_i >= 0:
		var de: Variant = Inventario.cofre[_drag_i] if _drag_cofre else Inventario.espacios[_drag_i]
		if de != null:
			var tx: Texture2D = UiTheme.icon(str(de["id"]))
			if tx != null:
				_root.draw_texture_rect(tx, Rect2(_mouse - Vector2(30, 30), Vector2(60, 60)), false, Color(1, 1, 1, 0.85))
	var sel: Variant = null
	if _hover_cofre >= 0:
		sel = Inventario.cofre[_hover_cofre]
	elif _hover_mochila >= 0:
		sel = Inventario.espacios[_hover_mochila]
	if sel != null:
		UiTheme.text(_root, UiTheme.BOLD, Vector2(pn.position.x, pn.end.y - 20.0), ItemDB.display_name(str(sel["id"])), 24, UiTheme.C_TEXT, pn.size.x, HORIZONTAL_ALIGNMENT_CENTER, 5)
