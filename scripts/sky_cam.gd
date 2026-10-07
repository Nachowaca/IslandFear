class_name SkyCam
extends Node

## Cámara libre desde el cielo para mirar la isla mientras jugás.
## O: entrar / salir. WASD mueve, Space o E sube, Ctrl o Q baja, Shift acelera, rueda hace zoom.
## Mantené el botón derecho del mouse para mirar. El jugador queda quieto mientras la usás.

var player: Node3D
var player_cam: Camera3D

var _cam: Camera3D
var _label: Label
var _yaw: float = 0.0
var _pitch: float = -0.8
var _speed: float = 18.0
var _looking: bool = false
var _o_was_down: bool = false

func _ready() -> void:
	_cam = Camera3D.new()
	_cam.name = "SkyCamera"
	_cam.far = 4000.0
	_cam.fov = 70.0
	add_child(_cam)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.text = "Cámara del cielo  ·  WASD mover  ·  Space/E subir  ·  Ctrl/Q bajar  ·  Shift rápido  ·  rueda zoom  ·  clic derecho mirar  ·  O volver"
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.offset_left = -380.0
	_label.offset_right = 380.0
	_label.offset_top = 8.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.visible = false
	layer.add_child(_label)

func _process(delta: float) -> void:
	var o_down: bool = Input.is_physical_key_pressed(KEY_O)
	if o_down and not _o_was_down:
		_toggle()
	_o_was_down = o_down
	if not _cam.current:
		return
	var rot: Basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var move: Vector3 = Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move -= rot.z
	if Input.is_physical_key_pressed(KEY_S):
		move += rot.z
	if Input.is_physical_key_pressed(KEY_A):
		move -= rot.x
	if Input.is_physical_key_pressed(KEY_D):
		move += rot.x
	if Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_Q):
		move -= Vector3.UP
	var spd: float = _speed * (3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	_cam.global_position += move * spd * delta
	_cam.global_position.y = maxf(_cam.global_position.y, 3.0)
	_cam.basis = rot

func _toggle() -> void:
	if _cam.current:
		if player_cam != null:
			player_cam.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_label.visible = false
	else:
		var from: Vector3 = Vector3.ZERO
		if player != null:
			from = player.global_position
		if player_cam != null:
			_yaw = player_cam.global_rotation.y
		_pitch = -0.5
		var rot: Basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
		_cam.global_position = from + Vector3(0.0, 4.0, 0.0) + rot.z * 14.0
		_cam.basis = rot
		_cam.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_label.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if _cam == null or not _cam.current:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam.global_position -= _cam.global_basis.z * maxf(_cam.global_position.y * 0.15, 1.5)   # zoom: acerca
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam.global_position += _cam.global_basis.z * maxf(_cam.global_position.y * 0.15, 1.5)   # zoom: aleja
	elif event is InputEventMouseMotion and _looking:
		var mm: InputEventMouseMotion = event
		_yaw -= mm.relative.x * 0.004
		_pitch = clampf(_pitch - mm.relative.y * 0.004, -1.5, 1.2)
