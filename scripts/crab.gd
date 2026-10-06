class_name Crab
extends Node3D

## Cangrejo de playa: camina de costado, se queda en la arena y huye si te acercás.

var terrain: IslandTerrain
var player: Node3D

const MIN_H: float = 0.5
const MAX_H: float = 1.4

## La isla puede volverlos hostiles por un rato (ver island_brain.gd).
var hostile: bool = false
var hostile_time: float = 0.0
var _bite_cd: float = 0.0

func make_hostile(seconds: float) -> void:
	hostile = true
	hostile_time = seconds

var _dir: Vector3 = Vector3.RIGHT
var _timer: float = 0.0
var _time: float = 0.0
var _claw_l: Node3D
var _claw_r: Node3D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_time = _rng.randf() * 10.0
	_build()
	_pick_dir()

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

func _sphere(r: float, color: Color, pos: Vector3, scl: Vector3, parent: Node3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi

func _build() -> void:
	var red: Color = Color(0.85, 0.25, 0.15)
	_sphere(0.14, red, Vector3(0, 0.1, 0), Vector3(1.4, 0.6, 1.0), self)
	_claw_l = Node3D.new()
	_claw_l.position = Vector3(0.2, 0.1, -0.12)
	add_child(_claw_l)
	_sphere(0.07, red.lightened(0.1), Vector3.ZERO, Vector3(1.0, 0.8, 1.2), _claw_l)
	_claw_r = Node3D.new()
	_claw_r.position = Vector3(-0.2, 0.1, -0.12)
	add_child(_claw_r)
	_sphere(0.07, red.lightened(0.1), Vector3.ZERO, Vector3(1.0, 0.8, 1.2), _claw_r)
	for sx: float in [-1.0, 1.0]:
		_sphere(0.02, Color.BLACK, Vector3(0.07 * sx, 0.2, -0.1), Vector3.ONE, self)
		for i in 3:
			_sphere(0.03, red.darkened(0.2), Vector3(0.2 * sx, 0.05, -0.05 + i * 0.07), Vector3(1.6, 0.5, 0.5), self)

func _pick_dir() -> void:
	var a: float = _rng.randf() * TAU
	_dir = Vector3(cos(a), 0, sin(a))
	_timer = _rng.randf_range(1.0, 3.0)
	if _rng.randf() < 0.4:
		_dir = Vector3.ZERO # se queda quieto

func _process(delta: float) -> void:
	_time += delta
	var speed: float = 0.7
	var move: Vector3 = _dir
	var scared: bool = false
	_bite_cd = maxf(_bite_cd - delta, 0.0)
	if hostile:
		hostile_time -= delta
		if hostile_time <= 0.0:
			hostile = false
	var min_h: float = 0.3 if hostile else MIN_H
	var max_h: float = 3.2 if hostile else MAX_H
	if player != null and is_instance_valid(player):
		var d: Vector3 = global_position - player.global_position
		d.y = 0.0
		if hostile and d.length() < 35.0:
			# la isla los lanza contra el jugador
			move = -d.normalized()
			speed = 3.7
			scared = true
			if d.length() < 1.0 and _bite_cd <= 0.0 and player is Castaway:
				(player as Castaway).take_damage(4.0, "cangrejos")
				_bite_cd = 1.1
		elif d.length() < 4.5:
			move = d.normalized()
			speed = 3.8
			scared = true
	_timer -= delta
	if _timer <= 0.0 and not scared:
		_pick_dir()
	if move != Vector3.ZERO:
		var next: Vector3 = global_position + move * speed * delta
		var h: float = terrain.height_at(next.x, next.z)
		if h >= min_h and h <= max_h:
			global_position = Vector3(next.x, h, next.z)
		elif not scared:
			_dir = -_dir
		# camina de costado: el cuerpo mira perpendicular al movimiento
		var side: Vector3 = move.cross(Vector3.UP)
		rotation.y = lerp_angle(rotation.y, atan2(-side.x, -side.z), 0.15)
	# tenazas
	var wig: float = 0.2 if move == Vector3.ZERO else 0.5
	_claw_l.rotation.x = sin(_time * 6.0) * wig
	_claw_r.rotation.x = sin(_time * 6.0 + 1.5) * wig
