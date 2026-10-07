class_name Butterfly
extends Node3D

## Mariposa low-poly: vuela con rumbo suave y errático (aletea en ráfagas, planea, sube y baja),
## y de tanto en tanto se posa en el suelo con las alas abriéndose y cerrándose despacio.

var terrain: IslandTerrain
var home: Vector3 = Vector3.ZERO
var wing_color: Color = Color(0.95, 0.6, 0.15)
var roam_radius: float = 9.0

var _wing_l: Node3D
var _wing_r: Node3D
var _target: Vector3
var _vel: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _rest_left: float = 0.0
var _flap_hz: float = 14.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_time = _rng.randf() * 10.0
	_flap_hz = _rng.randf_range(11.0, 17.0)
	var wing := QuadMesh.new()
	wing.size = Vector2(0.2, 0.15)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = wing_color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	wing.material = mat
	_wing_l = Node3D.new()
	_wing_r = Node3D.new()
	add_child(_wing_l)
	add_child(_wing_r)
	for pair: Array in [[_wing_l, 1.0], [_wing_r, -1.0]]:
		var mi := MeshInstance3D.new()
		mi.mesh = wing
		mi.rotation.x = -PI / 2.0
		mi.position.x = 0.1 * float(pair[1])
		(pair[0] as Node3D).add_child(mi)
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.014
	bm.height = 0.12
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.1, 0.07, 0.05)
	bm.material = bmat
	body.mesh = bm
	body.rotation.x = PI / 2.0
	add_child(body)
	global_position = home + Vector3(0, 1.0, 0)
	_pick_target()

func _pick_target() -> void:
	var a: float = _rng.randf() * TAU
	var r: float = _rng.randf_range(2.0, roam_radius)
	var x: float = home.x + cos(a) * r
	var z: float = home.z + sin(a) * r
	var y: float = terrain.height_at(x, z) + _rng.randf_range(0.6, 2.2)
	_target = Vector3(x, maxf(y, 1.0), z)

func _process(delta: float) -> void:
	_time += delta
	if _rest_left > 0.0:
		_rest_left -= delta
		var slow: float = 0.55 + 0.45 * sin(_time * 2.2)
		_wing_l.rotation.z = lerpf(0.15, 1.1, slow)
		_wing_r.rotation.z = -_wing_l.rotation.z
		return
	var to: Vector3 = _target - global_position
	if to.length() < 0.6:
		if _rng.randf() < 0.3:
			var gy: float = terrain.height_at(global_position.x, global_position.z)
			if gy > 0.8:
				global_position.y = gy + 0.08
				_vel = Vector3.ZERO
				_rest_left = _rng.randf_range(2.0, 6.0)
		_pick_target()
		return
	var desired: Vector3 = to.normalized() * 1.7
	desired += Vector3(sin(_time * 2.3 + _flap_hz), sin(_time * 3.7) * 0.8, cos(_time * 1.9 + _flap_hz)) * 0.9
	_vel = _vel.lerp(desired, minf(delta * 2.0, 1.0))
	global_position += _vel * delta
	var flap_wave: float = sin(_time * _flap_hz)
	global_position.y += flap_wave * 0.35 * delta
	var flat: Vector3 = Vector3(_vel.x, 0.0, _vel.z)
	if flat.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), minf(delta * 4.0, 1.0))
	rotation.z = lerpf(rotation.z, -_vel.x * 0.1, minf(delta * 3.0, 1.0))
	var burst: float = clampf(sin(_time * 1.3 + _flap_hz) * 2.5 + 1.2, 0.0, 1.0)
	var flap: float = flap_wave * lerpf(0.35, 1.0, burst) + 0.3
	_wing_l.rotation.z = flap
	_wing_r.rotation.z = -flap
