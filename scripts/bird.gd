class_name Bird
extends Node3D

## Pájaro low-poly. GULL: gaviota que vuela en círculos sobre la isla.
## SONGBIRD: pajarito posado en un árbol que huye si el jugador se acerca y luego vuelve.

enum Kind { GULL, SONGBIRD }
enum State { PERCHED, FLEE, RETURN, ORBIT }

var kind: Kind = Kind.SONGBIRD
var body_color: Color = Color(0.3, 0.5, 0.8)
var belly_color: Color = Color(0.95, 0.85, 0.4)
var size: float = 1.0
var perch: Vector3 = Vector3.ZERO
var orbit_center: Vector3 = Vector3.ZERO
var orbit_radius: float = 30.0
var orbit_height: float = 18.0
var orbit_speed: float = 0.25
var player: Node3D

var _state: State = State.PERCHED
var _time: float = 0.0
var _angle: float = 0.0
var _flee_dir: Vector3 = Vector3.ZERO
var _flee_time: float = 0.0
var _wing_l: Node3D
var _wing_r: Node3D
var _head: Node3D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_angle = _rng.randf() * TAU
	_build()
	if kind == Kind.GULL:
		_state = State.ORBIT
	else:
		global_position = perch
		_state = State.PERCHED

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _part(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build() -> void:
	var s: float = size
	var body := SphereMesh.new()
	body.radius = 0.12 * s
	body.height = 0.24 * s
	body.radial_segments = 8
	body.rings = 4
	var b: MeshInstance3D = _part(body, body_color, Vector3.ZERO, self)
	b.scale = Vector3(0.8, 0.75, 1.5)
	var belly: MeshInstance3D = _part(body, belly_color, Vector3(0, -0.04 * s, -0.02 * s), self)
	belly.scale = Vector3(0.7, 0.55, 1.3)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.08 * s, -0.17 * s)
	add_child(_head)
	var head := SphereMesh.new()
	head.radius = 0.07 * s
	head.height = 0.14 * s
	head.radial_segments = 8
	head.rings = 4
	_part(head, body_color if kind == Kind.SONGBIRD else Color(0.95, 0.95, 0.95), Vector3.ZERO, _head)
	var beak := PrismMesh.new()
	beak.size = Vector3(0.04 * s, 0.04 * s, 0.1 * s)
	var bk: MeshInstance3D = _part(beak, Color(0.95, 0.65, 0.15), Vector3(0, -0.01 * s, -0.09 * s), _head)
	bk.rotation.x = -PI / 2.0
	var tail := BoxMesh.new()
	tail.size = Vector3(0.1 * s, 0.02 * s, 0.16 * s)
	var tl: MeshInstance3D = _part(tail, body_color.darkened(0.2), Vector3(0, 0.0, 0.2 * s), self)
	tl.rotation.x = 0.2
	var wing := BoxMesh.new()
	wing.size = Vector3(0.38 * s, 0.015 * s, 0.2 * s)
	_wing_l = Node3D.new()
	_wing_l.position = Vector3(0.07 * s, 0.05 * s, 0)
	add_child(_wing_l)
	_part(wing, body_color.darkened(0.1), Vector3(0.19 * s, 0, 0), _wing_l)
	_wing_r = Node3D.new()
	_wing_r.position = Vector3(-0.07 * s, 0.05 * s, 0)
	add_child(_wing_r)
	_part(wing, body_color.darkened(0.1), Vector3(-0.19 * s, 0, 0), _wing_r)

func _process(delta: float) -> void:
	_time += delta
	match _state:
		State.ORBIT:
			_do_orbit(delta)
		State.PERCHED:
			_do_perched(delta)
		State.FLEE:
			_do_flee(delta)
		State.RETURN:
			_do_return(delta)

func _flap(speed: float, amp: float) -> void:
	var a: float = sin(_time * speed) * amp
	_wing_l.rotation.z = a
	_wing_r.rotation.z = -a

func _fold() -> void:
	_wing_l.rotation.z = lerpf(_wing_l.rotation.z, -1.2, 0.2)
	_wing_r.rotation.z = lerpf(_wing_r.rotation.z, 1.2, 0.2)

func _do_orbit(delta: float) -> void:
	_angle += orbit_speed * delta
	var p: Vector3 = orbit_center + Vector3(cos(_angle) * orbit_radius, orbit_height + sin(_angle * 3.0) * 2.0, sin(_angle) * orbit_radius)
	var ahead: Vector3 = orbit_center + Vector3(cos(_angle + 0.05) * orbit_radius, orbit_height + sin((_angle + 0.05) * 3.0) * 2.0, sin(_angle + 0.05) * orbit_radius)
	global_position = p
	look_at(ahead, Vector3.UP)
	rotation.z += sin(_time * 0.5) * 0.15 - 0.25 # leve inclinación al virar
	# aleteo lento con planeos
	_flap(5.0, 0.35 * maxf(0.0, sin(_time * 0.8) + 0.4))

## La isla los espanta (presagio): el pajarito sale volando aunque el jugador esté lejos.
func scare() -> void:
	if kind != Kind.SONGBIRD or _state != State.PERCHED:
		return
	_flee_dir = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
	_flee_time = 0.0
	_state = State.FLEE

func _player_dist() -> float:
	if player == null or not is_instance_valid(player):
		return 1000.0
	return global_position.distance_to(player.global_position)

func _do_perched(_delta: float) -> void:
	_fold()
	_head.rotation.y = sin(_time * 1.3 + _angle) * 0.6 * maxf(0.0, sin(_time * 0.4 + _angle * 3.0))
	_head.rotation.x = absf(sin(_time * 3.0 + _angle)) * 0.25 * maxf(0.0, sin(_time * 0.3 + _angle))
	if _player_dist() < 8.0:
		var away: Vector3 = global_position - player.global_position
		away.y = 0.0
		_flee_dir = (away.normalized() + Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))).normalized()
		_flee_time = 0.0
		_state = State.FLEE

func _do_flee(delta: float) -> void:
	_flee_time += delta
	var vel: Vector3 = _flee_dir * 7.0 + Vector3.UP * 4.0 * maxf(0.0, 1.0 - _flee_time / 1.5)
	global_position += vel * delta
	look_at(global_position + vel, Vector3.UP)
	_flap(30.0, 0.8)
	if _flee_time > 4.0:
		_state = State.RETURN

func _do_return(delta: float) -> void:
	if _player_dist() < 6.0:
		var away: Vector3 = global_position - player.global_position
		away.y = 0.0
		_flee_dir = away.normalized()
		_flee_time = 0.0
		_state = State.FLEE
		return
	var to: Vector3 = perch - global_position
	var dist: float = to.length()
	if dist < 0.25:
		global_position = perch
		_state = State.PERCHED
		return
	var step: Vector3 = to.normalized() * minf(5.0 * delta, dist)
	global_position += step
	look_at(global_position + to, Vector3.UP)
	_flap(30.0, 0.8)
