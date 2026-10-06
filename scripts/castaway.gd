class_name Castaway
extends CharacterBody3D

## Náufrago: movimiento en tercera persona + animación procedural low-poly (sin esqueleto).
## Hasta que `controllable` sea true (viaja en la barca) solo se mueve la cámara y respira en reposo.

@export_group("Movimiento")
@export var walk_speed: float = 4.0
@export var run_speed: float = 7.5
@export var acceleration: float = 22.0
@export var deceleration: float = 28.0
@export var air_control: float = 0.5
@export var turn_speed: float = 12.0
@export var jump_velocity: float = 6.5
@export var gravity: float = 20.0
@export var water_slowdown: float = 0.65
@export var min_walk_height: float = -0.1 ## terreno más bajo transitable (el agua está en ~0.35)
@export var wade_floor_y: float = 0.1 ## en aguas poco profundas no se hunde por debajo de esto
@export_group("Cámara")
@export var mouse_sensitivity: float = 0.003
@export var base_fov: float = 70.0
@export var run_fov_boost: float = 8.0
@export_group("Animación")
@export var stride_rate: float = 1.7 ## ciclos de paso por metro recorrido (rad)

signal damaged(amount: float, source: String)
signal died
signal stepped(surface: String, power: float)

@export_group("Salud")
@export var max_health: float = 100.0
@export var regen_delay: float = 8.0       ## segundos sin daño antes de empezar a curarse
@export var regen_rate: float = 1.0        ## puntos por segundo
@export var refuge_regen_rate: float = 4.0 ## curación más rápida dentro del refugio (cueva de día)

var health: float = 100.0
var dead: bool = false
var in_refuge: bool = false
var _since_damage: float = 99.0
var _slow_timer: float = 0.0
var _shake: float = 0.0

var controllable: bool = false

func take_damage(amount: float, source: String = "") -> void:
	if dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_since_damage = 0.0
	_shake = maxf(_shake, 0.4 + amount * 0.015)
	damaged.emit(amount, source)
	if health <= 0.0:
		dead = true
		controllable = false
		died.emit()

func heal(amount: float) -> void:
	if not dead:
		health = minf(health + amount, max_health)

func apply_slow(seconds: float) -> void:
	_slow_timer = maxf(_slow_timer, seconds)

func add_shake(strength: float) -> void:
	_shake = maxf(_shake, strength)
var terrain: IslandTerrain

@onready var _pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _body: Node3D = $Model/Body
@onready var _foot_l: Node3D = $Model/Body/FootL
@onready var _foot_r: Node3D = $Model/Body/FootR
@onready var _torso: Node3D = $Model/Body/Torso
@onready var _robe: Node3D = $Model/Body/Torso/Robe
@onready var _arm_l: Node3D = $Model/Body/Torso/ArmL
@onready var _arm_r: Node3D = $Model/Body/Torso/ArmR
@onready var _head: Node3D = $Model/Body/Torso/Head
@onready var _hair: Node3D = $Model/Body/Torso/Head/HairPivot

var _yaw: float = 0.0
var _pitch: float = -0.05
var _cam_default: Transform3D
var _grounded: bool = true
var _prev_grounded: bool = true
var _prev_vy: float = 0.0
var _phase: float = 0.0
var _time: float = 0.0
var _land_squash: float = 0.0
var _yaw_rate: float = 0.0

var _step_fx: CPUParticles3D
var _last_step: int = 0

func _make_step_fx() -> void:
	_step_fx = CPUParticles3D.new()
	var s := SphereMesh.new()
	s.radius = 0.045
	s.height = 0.09
	s.radial_segments = 5
	s.rings = 3
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	s.material = mat
	_step_fx.mesh = s
	_step_fx.top_level = true
	_step_fx.local_coords = false
	_step_fx.one_shot = true
	_step_fx.emitting = false
	_step_fx.explosiveness = 1.0
	_step_fx.amount = 12
	_step_fx.lifetime = 0.7
	_step_fx.direction = Vector3.UP
	_step_fx.spread = 55.0
	_step_fx.gravity = Vector3(0, -7.0, 0)
	_step_fx.scale_amount_min = 0.6
	_step_fx.scale_amount_max = 1.4
	add_child(_step_fx)

## Polvo de arena, salpicadura de agua o motas de pasto según el suelo.
func _emit_step(power: float) -> void:
	var h: float = 1.5
	if terrain != null:
		h = terrain.height_at(global_position.x, global_position.z)
	stepped.emit("water" if h < 0.38 else ("sand" if h < 1.25 else "grass"), power)
	if h < 0.38:
		_step_fx.color = Color(0.85, 0.95, 1.0)
		_step_fx.amount = 16
		_step_fx.initial_velocity_min = 1.2
		_step_fx.initial_velocity_max = 2.6 + power * 0.15
	elif h < 1.25:
		_step_fx.color = Color(0.9, 0.82, 0.6)
		_step_fx.amount = 10
		_step_fx.initial_velocity_min = 0.4
		_step_fx.initial_velocity_max = 1.1 + power * 0.08
	else:
		_step_fx.color = Color(0.35, 0.55, 0.22)
		_step_fx.amount = 6
		_step_fx.initial_velocity_min = 0.3
		_step_fx.initial_velocity_max = 0.8 + power * 0.05
	_step_fx.global_position = global_position + Vector3(0, 0.08, 0)
	_step_fx.restart()
	_step_fx.emitting = true

func _ready() -> void:
	add_to_group("player")
	_make_step_fx()
	_pivot.top_level = true
	_yaw = global_rotation.y
	_cam_default = _camera.transform
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(60.0)
	_update_pivot(0.0)

## Gira la cámara hacia una dirección del mundo (por ejemplo, la luna).
func look_toward(dir: Vector3) -> void:
	var d: Vector3 = dir.normalized()
	_yaw = atan2(-d.x, -d.z)
	_pitch = clampf(asin(clampf(d.y, -1.0, 1.0)) * 0.9, -1.2, 0.5)

func get_camera() -> Camera3D:
	return _camera

func _unhandled_input(event: InputEvent) -> void:
	if not _camera.current:
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		_yaw -= mm.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - mm.relative.y * mouse_sensitivity, -1.2, 0.5)
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	_time += delta
	_since_damage += delta
	_slow_timer = maxf(_slow_timer - delta, 0.0)
	_shake = move_toward(_shake, 0.0, delta * 0.7)
	if not dead and _since_damage > regen_delay and health < max_health:
		health = minf(health + (refuge_regen_rate if in_refuge else regen_rate) * delta, max_health)
	if controllable and _camera.current:
		_move(delta)
	_animate(delta)
	_update_pivot(delta)

## Teclas leídas directo: W adelante, S o X atrás, A izquierda, D derecha (+ flechas y acciones del Input Map).
func _read_move_input() -> Vector2:
	var v: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _key(KEY_A):
		v.x -= 1.0
	if _key(KEY_D):
		v.x += 1.0
	if _key(KEY_W):
		v.y -= 1.0
	if _key(KEY_S) or _key(KEY_X):
		v.y += 1.0
	return v.limit_length(1.0)

func _key(code: Key) -> bool:
	return Input.is_physical_key_pressed(code) or Input.is_key_pressed(code)

func _move(delta: float) -> void:
	var input: Vector2 = _read_move_input()
	var dir: Vector3 = Vector3.ZERO
	if input != Vector2.ZERO:
		dir = (Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y)).normalized()
	var speed: float = run_speed if _key(KEY_SHIFT) else walk_speed
	if terrain != null and terrain.height_at(global_position.x, global_position.z) < 0.3:
		speed *= water_slowdown # vadeando
	if _slow_timer > 0.0:
		speed *= 0.55 # atrapado por raíces / espinas
	var wish: Vector3 = dir * speed

	# No entrar al mar profundo
	if wish != Vector3.ZERO and terrain != null:
		var ahead: Vector3 = global_position + dir * 0.6
		var h_ahead: float = terrain.height_at(ahead.x, ahead.z)
		var h_here: float = terrain.height_at(global_position.x, global_position.z)
		if h_ahead < min_walk_height and h_ahead < h_here and h_here >= min_walk_height - 0.1:
			wish = Vector3.ZERO

	# Aceleración / frenado suaves
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var rate: float = acceleration if wish != Vector3.ZERO else deceleration
	if not _grounded:
		rate *= air_control
	horizontal = horizontal.move_toward(wish, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# Salto y gravedad
	if _grounded and _key(KEY_SPACE):
		velocity.y = jump_velocity
		_grounded = false
	elif _grounded:
		velocity.y = -1.0
	else:
		velocity.y -= gravity * delta
	_prev_vy = velocity.y
	# Subir escalones bajos (troncos caídos, bordes de roca, la plancha del barco) sin trabarse
	if _grounded and (velocity.x != 0.0 or velocity.z != 0.0):
		var motion: Vector3 = Vector3(velocity.x, 0.0, velocity.z) * delta * 1.5
		if test_move(global_transform, motion):
			var raised: Transform3D = global_transform
			raised.origin.y += 0.42
			if not test_move(raised, motion):
				global_position.y += 0.4
	move_and_slide()
	_grounded = is_on_floor()

	# Vadeo: no se hunde bajo la superficie en la orilla
	if global_position.y < wade_floor_y:
		global_position.y = wade_floor_y
		velocity.y = maxf(velocity.y, 0.0)
		_grounded = true

	# Girar el cuerpo hacia donde camina (el modelo mira hacia -Z)
	var old_yaw: float = rotation.y
	if dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(turn_speed * delta, 0.0, 1.0))
	_yaw_rate = angle_difference(old_yaw, rotation.y) / maxf(delta, 0.0001)

# ---------------------------------------------------------------- animación

func _animate(delta: float) -> void:
	var h_speed: float = Vector2(velocity.x, velocity.z).length()
	var blend: float = clampf(h_speed / walk_speed, 0.0, 1.0)
	var run_amt: float = clampf((h_speed - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
	_phase += h_speed * delta * stride_rate
	var s: float = sin(_phase)
	var c: float = cos(_phase)
	var air: bool = not _grounded and controllable

	# Pisadas: una por cada medio ciclo de paso
	var step_idx: int = int(floor(_phase / PI))
	if step_idx != _last_step:
		_last_step = step_idx
		if _grounded and controllable and h_speed > 1.0:
			_emit_step(h_speed)

	# Aterrizaje: aplastar al caer
	if _grounded and not _prev_grounded and controllable:
		_land_squash = clampf(-_prev_vy * 0.025, 0.0, 0.3)
		_emit_step(10.0)
	_prev_grounded = _grounded
	_land_squash = lerpf(_land_squash, 0.0, 1.0 - exp(-10.0 * delta))

	# Pies: pasos con levantamiento
	var stride: float = lerpf(0.22, 0.4, run_amt) * blend
	var lift: float = lerpf(0.12, 0.2, run_amt) * blend
	var fl: Vector3 = Vector3(0.14, 0.05 + maxf(0.0, c) * lift, -0.1 - s * stride)
	var fr: Vector3 = Vector3(-0.14, 0.05 + maxf(0.0, -c) * lift, -0.1 + s * stride)
	if air:
		fl = Vector3(0.14, 0.2, -0.2)
		fr = Vector3(-0.14, 0.17, 0.0)
	var k: float = 1.0 - exp(-25.0 * delta)
	_foot_l.position = _foot_l.position.lerp(fl, k)
	_foot_r.position = _foot_r.position.lerp(fr, k)

	# Brazos: balanceo opuesto a las piernas (+ abiertos en el aire)
	var arm_amp: float = lerpf(0.6, 1.2, run_amt) * blend
	var idle_sway: float = sin(_time * 1.5) * 0.04
	var al: Vector3 = Vector3(-s * arm_amp + idle_sway, 0.0, 0.12 + run_amt * 0.1)
	var ar: Vector3 = Vector3(s * arm_amp - idle_sway, 0.0, -0.12 - run_amt * 0.1)
	if air:
		al = Vector3(-0.3, 0.0, 0.9)
		ar = Vector3(-0.3, 0.0, -0.9)
	_arm_l.rotation = _arm_l.rotation.lerp(al, k)
	_arm_r.rotation = _arm_r.rotation.lerp(ar, k)

	# Cuerpo: rebote, estirar/aplastar
	var bounce: float = (1.0 - cos(2.0 * _phase)) * 0.5 * lerpf(0.05, 0.1, run_amt) * blend
	_body.position.y = bounce
	var sy: float = 1.0 - _land_squash
	if air:
		sy += clampf(velocity.y * 0.012, -0.05, 0.1)
	sy += sin(2.0 * _phase) * 0.02 * blend
	var sxz: float = 1.0 / sqrt(maxf(sy, 0.5))
	_body.scale = Vector3(sxz, sy, sxz)

	# Torso: inclinación al avanzar, giro y vaivén de caderas, respiración
	var lean: float = blend * 0.06 + run_amt * 0.16
	var torso_rot: Vector3 = Vector3(-lean, -s * 0.18 * blend, s * 0.05 * blend)
	_torso.rotation = _torso.rotation.lerp(torso_rot, k)
	_torso.scale.y = 1.0 + sin(_time * 1.9) * 0.012 * (1.0 - blend)
	var swish: float = 1.0 + absf(s) * 0.05 * blend
	_robe.scale = Vector3(swish, 1.0, swish)

	# Cabeza: mira al frente compensando la inclinación + cabeceo
	var look_y: float = sin(_time * 0.7) * 0.1 * (1.0 - blend)
	_head.rotation = Vector3(lean * 0.7 + c * 0.03 * blend, look_y, 0.0)

	# Pelo: se arrastra hacia atrás con la velocidad y se mueve al girar
	var hair_x: float = -(0.12 + h_speed / run_speed * 0.9) + sin(_time * 3.0) * 0.04
	if air:
		hair_x += clampf(-velocity.y * 0.03, -0.3, 0.6)
	var hair_z: float = clampf(_yaw_rate * 0.04, -0.6, 0.6)
	var hk: float = 1.0 - exp(-6.0 * delta)
	_hair.rotation.x = lerpf(_hair.rotation.x, hair_x, hk)
	_hair.rotation.z = lerpf(_hair.rotation.z, hair_z, hk)

func _update_pivot(delta: float) -> void:
	_pivot.global_position = global_position + Vector3(0, 1.5, 0)
	_pivot.global_basis = Basis.from_euler(Vector3(_pitch, _yaw, 0))

	# FOV más amplio al correr
	var h_speed: float = Vector2(velocity.x, velocity.z).length()
	var run_amt: float = clampf((h_speed - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
	_camera.fov = lerpf(_camera.fov, base_fov + run_amt * run_fov_boost, 1.0 - exp(-5.0 * delta))

	# La cámara no atraviesa terreno, árboles ni rocas
	_camera.transform = _cam_default
	var from: Vector3 = _pivot.global_position
	var to: Vector3 = _camera.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var hit_pos: Vector3 = hit["position"]
		_camera.global_position = hit_pos + (from - hit_pos).normalized() * 0.3
	if _shake > 0.001:
		_camera.global_position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * 0.12
