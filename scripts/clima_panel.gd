class_name ClimaPanel
extends CanvasLayer
## Herramienta de pruebas del clima. Botón "Clima" (arriba a la derecha) o tecla K.
## Permite forzar cada estado, avanzar la hora, volver al ciclo automático, apagar el clima y probar charcos y rebrote.

var weather: Weather
var player: Castaway

var _panel: PanelContainer
var _estado: Label
var _k_was_down: bool = false

func _ready() -> void:
	layer = 50
	var abrir := Button.new()
	abrir.text = "Clima (K)"
	abrir.anchor_left = 1.0
	abrir.anchor_right = 1.0
	abrir.offset_left = -110.0
	abrir.offset_right = -12.0
	abrir.offset_top = 78.0
	abrir.offset_bottom = 106.0
	abrir.focus_mode = Control.FOCUS_NONE
	abrir.pressed.connect(_alternar)
	add_child(abrir)

	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -300.0
	_panel.custom_minimum_size.x = 288.0
	_panel.offset_right = -12.0
	_panel.offset_top = 112.0
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	_estado = Label.new()
	box.add_child(_estado)
	for s: int in Weather.S.values():
		_boton(box, Weather.NOMBRES[s], func() -> void: weather.forzar(s))
	_boton(box, "Automático (ciclo normal)", func() -> void: weather.auto())
	var sep := HSeparator.new()
	box.add_child(sep)
	_boton(box, "Hora +1", func() -> void:
		var dn: DayNight = get_tree().get_first_node_in_group("daynight") as DayNight
		if dn != null:
			dn._offset_hours += 1.0)
	_boton(box, "Charcos ya", func() -> void: weather.puddles_now())
	_boton(box, "Rebrotar un árbol talado", func() -> void: weather.regrow_one())
	var chk := CheckButton.new()
	chk.text = "Clima activo"
	chk.button_pressed = weather.enabled
	chk.focus_mode = Control.FOCUS_NONE
	chk.toggled.connect(func(on: bool) -> void: weather.enabled = on)
	box.add_child(chk)

func _boton(box: VBoxContainer, texto: String, fn: Callable) -> void:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	box.add_child(b)

func _alternar() -> void:
	_panel.visible = not _panel.visible
	if player != null:
		player.menu_lock = _panel.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _panel.visible else Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	var k: bool = Input.is_physical_key_pressed(KEY_K)
	if k and not _k_was_down:
		_alternar()
	_k_was_down = k
	if _panel.visible and weather != null:
		_estado.text = "%s\nnubes %d%%  lluvia %d%%\nviento %d%%" % [weather.nombre(), roundi(weather.cloud * 100.0), roundi(weather.intensity * 100.0), roundi(weather.wind * 100.0)]
