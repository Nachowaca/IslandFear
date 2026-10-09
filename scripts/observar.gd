class_name Observar
extends Node

## Contemplar la isla: sentarse (V) y mirar con zoom (mantener Z, rueda para ajustar).
## Se crea como hijo de Castaway. No muestra ningún indicador del vínculo con la isla.

signal message(text: String)

const SIT_EVENT_EVERY: float = 12.0
const ZOOM_DEFAULT: float = 28.0
const ZOOM_MIN: float = 12.0
const ZOOM_MAX: float = 45.0
const ZOOM_STEP: float = 3.0
const EYE_IN_SPEED: float = 4.0
const EYE_OUT_SPEED: float = 3.0

var _pl: Castaway
var _zoom_target: float = ZOOM_DEFAULT
var _zooming: bool = false
var _sit_timer: float = 0.0
var _hid: bool = false

func _ready() -> void:
	_pl = get_parent() as Castaway
	if _pl != null:
		_pl.damaged.connect(_on_damaged)

func is_sitting() -> bool:
	return _pl != null and _pl.sitting

func is_zooming() -> bool:
	return _zooming

## Puede sentarse: en el suelo, quieto, con control y fuera del agua.
func can_sit() -> bool:
	if _pl == null or not _pl.controllable or _pl.dead or _pl.menu_lock or _pl.ui_lock:
		return false
	if not _pl.is_on_floor():
		return false
	if Vector2(_pl.velocity.x, _pl.velocity.z).length() > 0.3:
		return false
	if _pl.terrain != null and _pl.terrain.height_at(_pl.global_position.x, _pl.global_position.z) < 0.5:
		return false
	return true

func sit_down() -> void:
	if _pl == null or _pl.sitting or not can_sit():
		return
	_pl.sitting = true
	_sit_timer = 0.0
	message.emit("Te sentás a contemplar la isla.")

func stand_up() -> void:
	if _pl != null:
		_pl.sitting = false

func _on_damaged(_amount: float, _source: String) -> void:
	stand_up()

func _unhandled_input(event: InputEvent) -> void:
	if _pl == null:
		return
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.keycode == KEY_V:
			if _pl.sitting:
				stand_up()
			else:
				sit_down()
	elif event is InputEventMouseButton and _zooming:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			get_viewport().set_input_as_handled()

func _moving_keys() -> bool:
	for code: Key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_X, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE]:
		if Input.is_physical_key_pressed(code) or Input.is_key_pressed(code):
			return true
	return false

func _physics_process(delta: float) -> void:
	if _pl == null:
		return
	var cam: Camera3D = _pl.get_camera()
	var active: bool = cam != null and cam.current

	# --- Sentado
	if _pl.sitting:
		if _pl.dead or not _pl.controllable or not _pl.is_on_floor() or (active and not _pl.menu_lock and not _pl.ui_lock and _moving_keys()):
			stand_up()
		else:
			_sit_timer += delta
			if _sit_timer >= SIT_EVENT_EVERY:
				_sit_timer = 0.0
				Isla.registrar_evento("contemplar", _pl.global_position, 1.0)

	# --- Zoom con Z
	var want: bool = active and _pl.controllable and not _pl.dead and not _pl.ui_lock and not _pl.menu_lock \
		and (Input.is_physical_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_Z))
	if want and not _zooming:
		_zoom_target = clampf(_zoom_target, ZOOM_MIN, ZOOM_MAX)
	_zooming = want
	var speed: float = EYE_IN_SPEED if want else EYE_OUT_SPEED
	_pl.eye_view = move_toward(_pl.eye_view, 1.0 if want else 0.0, speed * delta)
	_pl.zoom_fov = _zoom_target if (want or _pl.eye_view > 0.01) else 0.0
	if not want and _pl.eye_view > 0.01:
		# al soltar, el FOV vuelve al normal mientras la cámara sale de la cabeza
		_pl.zoom_fov = 0.0
	if _pl.eye_view >= 0.85 and not _hid:
		_hid = true
		_pl.set_model_visible(false)
	elif _pl.eye_view < 0.85 and _hid:
		_hid = false
		_pl.set_model_visible(true)
