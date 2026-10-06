class_name Main
extends Node3D

## Flujo: 1) la barca llega con la corriente hasta la costa, 2) el náufrago desembarca y se mueve libre.
## Tab / M: alterna la vista aérea (rueda = zoom, clic izq. arrastrar = girar, WASD = mover).

const WATER_Y: float = 0.35

@onready var _island: IslandTerrain = $Island
@onready var _boat: Boat = $Boat
@onready var _castaway: Castaway = $Boat/Castaway
@onready var _water: Node3D = $Water3D

var _overview_cam: Camera3D
var _focus: Vector3 = Vector3(0, 0, 0)
var _distance: float = 230.0
var _yaw: float = 0.6
var _pitch: float = -0.9
var _dragging: bool = false
var _toggle_was_down: bool = false

var _boat_target: Vector3
var _arrived: bool = false
var _time: float = 0.0
var _hint: Label
var _brain: IslandBrain
var _hud: Hud

func _on_player_died() -> void:
	_brain.notify_death()
	Inventario.vaciar()                                # lo que llevabas se pierde con la vida
	var tomb_pos: Vector3 = _castaway.global_position   # su tumba: en tierra firme, lo más cerca de donde cayó
	var toward: Vector3 = Vector3(-tomb_pos.x, 0.0, -tomb_pos.z).normalized()
	for i in 200:
		if _island.height_at(tomb_pos.x, tomb_pos.z) > 1.0:
			break
		tomb_pos += toward * 0.5
	tomb_pos.y = _island.height_at(tomb_pos.x, tomb_pos.z)
	Isla.registrar_tumba(tomb_pos, _castaway.death_cause)
	var res: Dictionary = Isla.cerrar_vida()          # la personalidad de la isla se desplaza según cómo jugó
	_hud.refresh_lives()
	if bool(res["fin"]):
		# séptima muerte: el jugador se convierte en la isla
		var fin: Dictionary = Isla.calcular_final()
		_hud.show_ending(str(fin["titulo"]), str(fin["cuerpo"]))
		await get_tree().create_timer(22.0).timeout
		Isla.nuevo_ciclo(str(fin["tipo"]))
		IslandBrain.olvidar_todo()
	else:
		var n: int = int(res["vidas_restantes"])
		_hud.show_death("La isla ganó esta vez.\nRecuerda cómo lo hizo.\n\n%s" % ("Te queda 1 vida." if n == 1 else "Te quedan %d vidas." % n))
		await get_tree().create_timer(5.0).timeout
	get_tree().reload_current_scene()

func _ready() -> void:
	UiTheme.apply_default_font()
	add_child(HelpUi.new())
	_water.position.y = WATER_Y - 0.0
	_castaway.terrain = _island
	add_child(AmbientFx.new())
	var lighthouse := Lighthouse.new()
	lighthouse.name = "Lighthouse"
	lighthouse.position = Vector3(-20, 0, -105)   # fuera de la isla
	lighthouse.beam_length = 190.0
	lighthouse.water_level = $Water3D.position.y
	add_child(lighthouse)
	# puntos de interés, mente de la isla e interfaz
	var features := IslandFeatures.new()
	features.name = "Features"
	features.terrain = _island
	add_child(features)
	var brain := IslandBrain.new()
	brain.name = "IslandBrain"
	brain.terrain = _island
	brain.features = features
	brain.player = _castaway
	add_child(brain)
	_brain = brain
	var audio := AudioManager.new()
	audio.name = "Audio"
	audio.terrain = _island
	audio.features = features
	audio.player = _castaway
	audio.brain = brain
	add_child(audio)
	_hud = Hud.new()
	_hud.name = "Hud"
	_hud.player = _castaway
	_hud.brain = brain
	add_child(_hud)
	var inv_ui := InventoryUi.new()
	inv_ui.name = "InventoryUi"
	add_child(inv_ui)
	var inter := Interaccion.new()
	inter.name = "Interaccion"
	inter.player = _castaway
	inter.terrain = _island
	inter.features = features
	inter.ui = inv_ui
	add_child(inter)
	_castaway.died.connect(_on_player_died)
	var daynight := DayNight.new()
	daynight.setup($Water3D/Sun as DirectionalLight3D, $Water3D/WorldEnvironment as WorldEnvironment)
	add_child(daynight)
	_overview_cam = Camera3D.new()
	_overview_cam.far = 3000.0
	add_child(_overview_cam)
	_update_overview()
	_boat_target = _find_landing_point()
	_make_hint()
	_hint.text = "La corriente arrastra la barca hacia una isla..."
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Camina desde la barca hacia el centro de la isla hasta encontrar la orilla.
func _find_landing_point() -> Vector3:
	var start: Vector3 = _boat.global_position
	var dir: Vector3 = (Vector3(0, 0, 0) - start)
	dir.y = 0.0
	dir = dir.normalized()
	var p: Vector3 = start
	for i in 400:
		p += dir * 0.5
		if _island.height_at(p.x, p.z) > -0.1:
			break
	return Vector3(p.x, WATER_Y + 0.02, p.z) - dir * 1.8

func _make_hint() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hint = Label.new()
	_hint.position = Vector2(24, 20)
	_hint.add_theme_font_override("font", UiTheme.BOLD)
	_hint.add_theme_font_size_override("font_size", 26)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 8)
	layer.add_child(_hint)

var _f11_was_down: bool = false

func _process(delta: float) -> void:
	_time += delta
	# F11: pantalla completa / ventana
	var f11: bool = Input.is_physical_key_pressed(KEY_F11)
	if f11 and not _f11_was_down:
		var fs: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_f11_was_down = f11
	_update_boat(delta)
	var toggle_down: bool = Input.is_physical_key_pressed(KEY_M)
	if toggle_down and not _toggle_was_down:
		if _overview_cam.current:
			_castaway.get_camera().make_current()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			_overview_cam.make_current()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_toggle_was_down = toggle_down
	if not _overview_cam.current:
		return
	var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		_focus += Basis(Vector3.UP, _yaw) * Vector3(dir.x, 0, dir.y) * _distance * 0.6 * delta
		_update_overview()

func _update_boat(delta: float) -> void:
	if _arrived:
		return   # varada en la orilla: quieta para que el jugador baje con seguridad
	var to_target: Vector3 = _boat_target - _boat.global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist < 0.25:
		_arrive()
		return
	var speed: float = clampf(dist * 0.3, 0.5, 6.0)  # frena al acercarse
	_boat.global_position += to_target.normalized() * minf(speed * delta, dist)
	_boat.global_position.y = WATER_Y + 0.02 + sin(_time * 1.2) * 0.05
	_boat.rotation.z = sin(_time * 0.9) * 0.025
	_boat.rotation.x = sin(_time * 0.7 + 1.0) * 0.015

func _arrive() -> void:
	_arrived = true
	_boat.rotation.x = 0.0
	_boat.rotation.z = 0.0
	_boat.global_position.y = WATER_Y + 0.02
	_hint.text = "La barca toca la orilla..."
	_castaway.reparent(self, true)
	await get_tree().create_timer(0.8).timeout
	await _boat.deploy_gangway(_island)       # baja la plancha de desembarco
	_castaway.controllable = true
	_hint.text = "Pulsá  H  para ver los controles"
	await get_tree().create_timer(14.0).timeout
	_hint.text = "H  Ayuda"
	_hint.modulate.a = 0.6

func _unhandled_input(event: InputEvent) -> void:
	if not _overview_cam.current:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(15.0, _distance * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(500.0, _distance * 1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		_update_overview()
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		_yaw -= mm.relative.x * 0.005
		_pitch = clampf(_pitch - mm.relative.y * 0.005, -1.5, -0.1)
		_update_overview()

func _update_overview() -> void:
	var rot: Basis = Basis.from_euler(Vector3(_pitch, _yaw, 0))
	_overview_cam.global_position = _focus + rot * Vector3(0, 0, _distance)
	_overview_cam.look_at(_focus, Vector3.UP)
