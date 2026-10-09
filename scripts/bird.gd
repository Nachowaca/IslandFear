class_name Bird
extends Node3D

## Pájaro low-poly. GULL: gaviota que vuela en círculos sobre la isla.
## SONGBIRD: pajarito posado en un árbol que huye si el jugador se acerca y luego vuelve.

enum Kind { GULL, SONGBIRD }
enum State { PERCHED, FLEE, RETURN, ORBIT, WANDER, ROAM }

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
var perches: Array[Vector3] = []     ## copas de árboles donde puede posarse (vuela de una a otra)
var perch_trees: Array[Node3D] = []  ## árbol de cada copa (en paralelo a `perches`): si lo talan, el pájaro se va
var perch_tree: Node3D = null
var _vel: Vector3 = Vector3.ZERO
var _roam_pts: Array[Vector3] = []
var _roam_i: int = 0
var _phase: float = 0.0

var _state: State = State.PERCHED
var _time: float = 0.0
var _angle: float = 0.0
var _flee_dir: Vector3 = Vector3.ZERO
var _flee_time: float = 0.0
var _wing_l: Node3D
var _wing_r: Node3D
var _head: Node3D
var _idle_left: float = 6.0
var _wander_to: Vector3 = Vector3.ZERO
var _wander_t: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_angle = _rng.randf() * TAU
	_phase = _rng.randf() * TAU
	_build()
	if kind == Kind.GULL:
		_state = State.ORBIT
	else:
		global_position = perch
		_state = State.PERCHED
		_idle_left = _rng.randf_range(2.0, 14.0)

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
		State.WANDER:
			_do_wander(delta)
		State.ROAM:
			_do_roam(delta)

func _flap(speed: float, amp: float) -> void:
	var a: float = sin(_time * speed) * amp
	_wing_l.rotation.z = a
	_wing_r.rotation.z = -a

func _fold() -> void:
	_wing_l.rotation.z = lerpf(_wing_l.rotation.z, -1.2, 0.2)
	_wing_r.rotation.z = lerpf(_wing_r.rotation.z, 1.2, 0.2)

## Posición en la órbita: radio, velocidad, centro y altura derivan despacio, así que nunca repite el mismo círculo.
func _orbit_pos(ang: float, t: float) -> Vector3:
	var r: float = orbit_radius * (1.0 + 0.22 * sin(t * 0.071 + _phase) + 0.1 * sin(t * 0.137 + _phase * 2.0))
	var c: Vector3 = orbit_center + Vector3(sin(t * 0.047 + _phase) * 35.0, 0.0, cos(t * 0.039 + _phase) * 35.0)
	var h: float = orbit_height + sin(ang * 3.0) * 2.0 + sin(t * 0.17 + _phase) * 7.0
	return c + Vector3(cos(ang) * r, h, sin(ang) * r)

func _do_orbit(delta: float) -> void:
	_angle += orbit_speed * delta * (1.0 + 0.35 * sin(_time * 0.11 + _phase))
	var p: Vector3 = _orbit_pos(_angle, _time)
	var ahead: Vector3 = _orbit_pos(_angle + 0.05, _time)
	global_position = p
	look_at(ahead, Vector3.UP)
	rotation.z += sin(_time * 0.5 + _phase) * 0.2 - 0.25 * signf(orbit_speed)   # inclinación al virar
	# aleteo en ráfagas con planeos de duración irregular
	_flap(5.0 + sin(_time * 0.3 + _phase) * 1.5, 0.35 * maxf(0.0, sin(_time * 0.8 + _phase * 3.0) + 0.3))

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

func _do_perched(delta: float) -> void:
	_fold()
	if perch_tree != null and not _tree_alive(perch_tree):
		perch_tree = null
		scare()   # le talaron el árbol: sale volando
		return
	_idle_left -= delta
	if _idle_left <= 0.0 and not perches.is_empty():
		_idle_left = _rng.randf_range(8.0, 25.0)
		if _rng.randf() < 0.5:
			_start_roam()
			return
		if _pick_perch(6.0, 35.0):
			return
	_head.rotation.y = sin(_time * 1.3 + _angle) * 0.6 * maxf(0.0, sin(_time * 0.4 + _angle * 3.0))
	_head.rotation.x = absf(sin(_time * 3.0 + _angle)) * 0.25 * maxf(0.0, sin(_time * 0.3 + _angle))
	if _player_dist() < 8.0:
		var away: Vector3 = global_position - player.global_position
		away.y = 0.0
		_flee_dir = (away.normalized() + Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))).normalized()
		_flee_time = 0.0
		_state = State.FLEE

## ¿El árbol sigue en pie? (talado = liberado, en cola de borrado o ya caído)
func _tree_alive(t: Node3D) -> bool:
	return is_instance_valid(t) and not t.is_queued_for_deletion() and t.basis.y.normalized().y > 0.9

## Elige otra copa viva a esa distancia y va hacia ella.
func _pick_perch(dmin: float, dmax: float) -> bool:
	for k in 10:
		var i: int = _rng.randi_range(0, perches.size() - 1)
		var tr_i: Node3D = perch_trees[i] if i < perch_trees.size() else null
		if tr_i != null and not _tree_alive(tr_i):
			continue
		var dd: float = perches[i].distance_to(global_position)
		if dd > dmin and dd < dmax:
			_wander_to = perches[i]
			perch_tree = tr_i
			_wander_t = 0.0
			_state = State.WANDER
			return true
	return false

## Vuelo libre: da una vuelta por 3 a 5 puntos al azar a distinta altura y recién después se posa.
func _start_roam() -> void:
	_roam_pts.clear()
	var base: Vector3 = global_position
	var n: int = _rng.randi_range(3, 5)
	var ang: float = _rng.randf() * TAU
	for i in n:
		ang += _rng.randf_range(0.8, 2.2)
		var r: float = _rng.randf_range(12.0, 32.0)
		_roam_pts.append(Vector3(base.x + cos(ang) * r, base.y + _rng.randf_range(3.0, 13.0), base.z + sin(ang) * r))
	_roam_i = 0
	_vel = Vector3(0, 2.5, 0)
	_wander_t = 0.0
	_state = State.ROAM

func _do_roam(delta: float) -> void:
	if player != null and _player_dist() < 4.0:
		scare()
	_wander_t += delta
	var target: Vector3 = _roam_pts[_roam_i]
	var to: Vector3 = target - global_position
	if to.length() < 3.0:
		_roam_i += 1
		if _roam_i >= _roam_pts.size():
			if not _pick_perch(4.0, 60.0):
				_state = State.RETURN
			return
		target = _roam_pts[_roam_i]
		to = target - global_position
	var speed: float = 6.5 + sin(_time * 0.9 + _phase) * 1.5
	var desired: Vector3 = to.normalized() * speed + Vector3.UP * sin(_time * 5.0 + _phase) * 0.8   # bamboleo de aleteo
	var prev_dir: Vector3 = _vel.normalized()
	_vel = _vel.lerp(desired, 1.0 - exp(-1.6 * delta))
	global_position += _vel * delta
	if _vel.length() > 0.5:
		look_at(global_position + _vel, Vector3.UP)
		var turn: float = prev_dir.cross(_vel.normalized()).y
		rotation.z = clampf(turn * 25.0, -0.6, 0.6)   # se inclina al virar
	var burst: float = clampf(sin(_time * 2.4 + _phase) * 2.0 + 0.8, 0.0, 1.0)
	_flap(24.0, lerpf(0.15, 0.85, burst))

func _do_flee(delta: float) -> void:
	_flee_time += delta
	var vel: Vector3 = _flee_dir * 7.0 + Vector3.UP * 4.0 * maxf(0.0, 1.0 - _flee_time / 1.5)
	global_position += vel * delta
	look_at(global_position + vel, Vector3.UP)
	_flap(30.0, 0.8)
	if _flee_time > 4.0:
		_state = State.RETURN

func _do_return(delta: float) -> void:
	if perch_tree != null and not _tree_alive(perch_tree):
		perch_tree = null
	if perch_tree == null and not perches.is_empty() and _pick_perch(4.0, 90.0):
		return   # su árbol ya no está: busca otro
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

## Vuela a otra copa: despega con un salto, aletea en ráfagas con planeos, bambolea y aterriza frenando.
func _do_wander(delta: float) -> void:
	if player != null and _player_dist() < 5.0:
		var away: Vector3 = global_position - player.global_position
		away.y = 0.0
		_flee_dir = away.normalized()
		_flee_time = 0.0
		_state = State.FLEE
		return
	_wander_t += delta
	var to: Vector3 = _wander_to - global_position
	var dist: float = to.length()
	if dist < 0.3:
		global_position = _wander_to
		perch = _wander_to
		_state = State.PERCHED
		_idle_left = _rng.randf_range(6.0, 22.0)
		return
	var dir: Vector3 = to.normalized()
	var speed: float = 5.5 * clampf(dist / 3.0, 0.25, 1.0)
	var lift: float = 2.5 * maxf(0.0, 1.0 - _wander_t / 0.8)
	var arc: float = 0.0
	if dist > 4.0:
		arc = sin(clampf(_wander_t * 0.6, 0.0, PI)) * 0.8
	var vel: Vector3 = dir * speed + Vector3.UP * (lift + arc + sin(_time * 8.0 + _angle) * 0.7)
	global_position += vel * delta
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.05:
		look_at(global_position + flat.normalized() * 2.0 + Vector3.UP * dir.y, Vector3.UP)
	var burst: float = clampf(sin(_time * 3.2 + _angle) * 2.0 + 1.0, 0.0, 1.0)
	if dist < 3.0 or _wander_t < 0.8:
		burst = 1.0
	_flap(26.0, lerpf(0.25, 0.9, burst))
	rotation.z += sin(_time * 8.0 + _angle) * 0.12
