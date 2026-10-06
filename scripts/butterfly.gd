class_name Butterfly
extends Node3D

## Mariposa low-poly: revolotea cerca del suelo alrededor de un punto, aleteando.

var terrain: IslandTerrain
var home: Vector3 = Vector3.ZERO
var wing_color: Color = Color(0.95, 0.6, 0.15)
var roam_radius: float = 7.0

var _wing_l: Node3D
var _wing_r: Node3D
var _target: Vector3
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_time = _rng.randf() * 10.0
	var wing := QuadMesh.new()
	wing.size = Vector2(0.14, 0.11)
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
		mi.position.x = 0.07 * float(pair[1])
		(pair[0] as Node3D).add_child(mi)
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.012
	bm.height = 0.1
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
	var r: float = _rng.randf() * roam_radius
	var x: float = home.x + cos(a) * r
	var z: float = home.z + sin(a) * r
	var y: float = terrain.height_at(x, z) + _rng.randf_range(0.5, 1.8)
	_target = Vector3(x, maxf(y, 1.0), z)

func _process(delta: float) -> void:
	_time += delta
	var to: Vector3 = _target - global_position
	if to.length() < 0.4:
		_pick_target()
		return
	var dir: Vector3 = to.normalized()
	# trayectoria errática
	dir += Vector3(sin(_time * 3.1), sin(_time * 4.3) * 0.6, cos(_time * 2.7)) * 0.45
	global_position += dir.normalized() * 1.3 * delta
	var flat: Vector3 = Vector3(dir.x, 0, dir.z)
	if flat.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), 0.1)
	var flap: float = sin(_time * 24.0) * 0.9
	_wing_l.rotation.z = flap
	_wing_r.rotation.z = -flap
