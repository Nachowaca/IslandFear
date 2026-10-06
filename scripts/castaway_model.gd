class_name CastawayModel
extends Node3D

## Cuerpo del náufrago: modelo low-poly de Quaternius (CC0) con sus animaciones.
## Idle / Walk / Run / Jump / RunningJump / Death / SwordSlash vienen en el archivo.
## Agacharse, recoger, comer y beber son retoques de pose por código (castaway_pose.gd).

const MODEL: PackedScene = preload("res://assets/character/quaternius_cc0-male-character-1352.glb")
const MODEL_SCALE: float = 0.372       ## el modelo mide 4.84 unidades -> 1.8 m
const PREFIX: String = "HumanArmature|HumanArmature|Man_"
const LOOPING: Array[String] = ["Idle", "Walk", "Run"]
const WALK_REF: float = 1.6            ## m/s a los que la animación Walk se ve natural
const RUN_REF: float = 4.2
const RUN_FROM: float = 2.8            ## desde esta velocidad se usa Run

var ap: AnimationPlayer
var sk: Skeleton3D
var pose: CastawayPose

var _cur: String = ""
var _air: bool = false
var _action: String = ""
var _action_t: float = 0.0
var _action_len: float = 0.0
var _lock: float = 0.0                 ## tiempo restante de una animación completa (tajo)

func build() -> void:
	var m: Node3D = MODEL.instantiate() as Node3D
	m.rotation.y = PI                  # el modelo mira a +Z, el náufrago a -Z
	m.scale = Vector3.ONE * MODEL_SCALE
	add_child(m)
	ap = m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	sk = m.find_child("Skeleton3D", true, false) as Skeleton3D
	pose = CastawayPose.new()
	pose.name = "Pose"
	sk.add_child(pose)
	for a: String in ap.get_animation_list():
		var short: String = a.trim_prefix(PREFIX)
		ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR if short in LOOPING else Animation.LOOP_NONE
	_play("Idle", 0.0, 1.0)

func _play(short: String, blend: float, speed: float) -> void:
	if _cur != short:
		ap.play(PREFIX + short, blend)
		_cur = short
	ap.speed_scale = speed

## Posición 0..1 dentro del ciclo de caminar/correr (para sincronizar las pisadas); -1 si no camina.
func loco_phase() -> float:
	if _cur != "Walk" and _cur != "Run":
		return -1.0
	return ap.current_animation_position / maxf(ap.current_animation_length, 0.01)

## Acción puntual: "pickup", "eat", "drink" (poses) o "cut" (tajo completo).
func play_action(action: String) -> void:
	match action:
		"pickup":
			_start_pose_action("pickup", 0.7)
		"eat":
			_start_pose_action("eat", 1.0)
		"drink":
			_start_pose_action("drink", 1.1)
		"cut":
			_lock = 0.7
			_cur = ""
			_play("SwordSlash", 0.08, 1.5)

func _start_pose_action(a: String, length: float) -> void:
	_action = a
	_action_t = 0.0
	_action_len = length

func update(dt: float, h_speed: float, air: bool, dead: bool, crouch_target: float) -> void:
	pose.crouch = lerpf(pose.crouch, crouch_target, 1.0 - exp(-9.0 * dt))
	if _action != "":
		_action_t += dt
		var env: float = clampf(minf(_action_t / 0.25, (_action_len - _action_t) / 0.3), 0.0, 1.0)
		pose.act = _action
		pose.act_w = smoothstep(0.0, 1.0, env)
		if _action_t >= _action_len:
			_action = ""
			pose.act = ""
			pose.act_w = 0.0
	if dead:
		_play("Death", 0.15, 1.0)
		return
	if _lock > 0.0:
		_lock -= dt
		return
	if air:
		if not _air:
			_air = true
			_cur = ""
			_play("RunningJump" if h_speed > 3.0 else "Jump", 0.08, 1.7)
		if ap.is_playing() and ap.current_animation_position >= ap.current_animation_length - 0.1:
			ap.pause()
		return
	if _air:
		_air = false
		_cur = ""
	if h_speed < 0.25:
		_play("Idle", 0.25, 1.0)
	elif h_speed < RUN_FROM:
		_play("Walk", 0.2, clampf(h_speed / WALK_REF, 0.6, 2.0))
	else:
		_play("Run", 0.2, clampf(h_speed / RUN_REF, 0.8, 1.9))
