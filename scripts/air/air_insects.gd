class_name AirInsects
extends Node3D
## Libélulas y nubes de mosquitos decorativas (solo de día).

# --- Ajustes ---
const DRAGONFLY_COUNT: int = 8
const MIDGE_CLOUDS: int = 4
const MIDGE_POINTS: int = 14
const RELOC_FAR: float = 50.0          ## distancia a la que se reubican
const SPAWN_MIN: float = 8.0
const SPAWN_MAX: float = 40.0
const FLY_MIN_H: float = 0.5           ## altura mínima sobre el agua/suelo
const FLY_MAX_H: float = 1.5
const DRAGON_SPEED: float = 3.2        ## velocidad de crucero (m/s)
const DRAGON_BURST: float = 7.0        ## velocidad de arranque
const WING_FLAP_HZ: float = 45.0
const GROUND_MIN: float = 0.2          ## rango de altura de suelo para anclar
const GROUND_MAX: float = 1.5
const WATER_H: float = 0.9             ## por debajo es agua
const DRAGON_COLOR: Color = Color(0.1, 0.85, 0.8)
const MIDGE_COLOR: Color = Color(0.22, 0.19, 0.16, 0.85)
const MIDGE_RADIUS: float = 0.7

var terrain: IslandTerrain
var player: Node3D

var _noche: float = 0.0
var _dragons: Array[Dictionary] = []
var _clouds: Array[CPUParticles3D] = []
var _cloud_goal: Array[Vector3] = []
var _t: float = 0.0
var _reloc_timer: float = 0.0
var _dragon_root: Node3D
var _midge_root: Node3D

func _ready() -> void:
	_dragon_root = Node3D.new()
	_dragon_root.name = "Dragonflies"
	add_child(_dragon_root)
	_midge_root = Node3D.new()
	_midge_root.name = "Midges"
	add_child(_midge_root)
	_build_dragonflies()
	_build_midges()

func set_noche(n: float) -> void:
	_noche = n
	var dia: bool = n <= 0.5
	_dragon_root.visible = dia
	_midge_root.visible = dia
	for c: CPUParticles3D in _clouds:
		c.emitting = dia

# --- Construcción ---
func _build_dragonflies() -> void:
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.025, 0.025, 0.22)
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(0.11, 0.003, 0.045)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = DRAGON_COLOR
	body_mat.emission_enabled = true
	body_mat.emission = DRAGON_COLOR
	body_mat.emission_energy_multiplier = 0.6
	var wing_mat := StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.75, 0.95, 0.95, 0.35)
	wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wing_mat.emission_enabled = true
	wing_mat.emission = DRAGON_COLOR
	wing_mat.emission_energy_multiplier = 0.3
	for i: int in DRAGONFLY_COUNT:
		var root := Node3D.new()
		_dragon_root.add_child(root)
		var body := MeshInstance3D.new()
		body.mesh = body_mesh
		body.material_override = body_mat
		root.add_child(body)
		var wings: Array[Node3D] = []
		for k: int in 4:
			var pivot := Node3D.new()
			var side: float = 1.0 if k % 2 == 0 else -1.0
			pivot.position = Vector3(0.0, 0.015, 0.05 if k < 2 else -0.01)
			root.add_child(pivot)
			var w := MeshInstance3D.new()
			w.mesh = wing_mesh
			w.material_override = wing_mat
			w.position = Vector3(side * 0.055, 0.0, 0.0)
			pivot.add_child(w)
			pivot.set_meta("side", side)
			wings.append(pivot)
		var d: Dictionary = {
			"node": root, "wings": wings,
			"pos": Vector3.ZERO, "vel": Vector3.ZERO,
			"target": Vector3.ZERO, "state_t": 0.0, "hover": false,
			"anchor": Vector3.ZERO, "ready": false,
			"phase": randf() * TAU,
		}
		_dragons.append(d)
	_place_all_dragons()

func _build_midges() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.025, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = MIDGE_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	for i: int in MIDGE_CLOUDS:
		var p := CPUParticles3D.new()
		p.amount = MIDGE_POINTS
		p.lifetime = 4.0
		p.preprocess = 4.0
		p.mesh = mesh
		p.material_override = mat
		p.local_coords = true
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = MIDGE_RADIUS
		p.direction = Vector3.UP
		p.spread = 180.0
		p.gravity = Vector3.ZERO
		p.initial_velocity_min = 0.15
		p.initial_velocity_max = 0.5
		p.orbit_velocity_min = 0.4
		p.orbit_velocity_max = 1.2
		p.linear_accel_min = -0.4
		p.linear_accel_max = 0.4
		p.tangential_accel_min = -0.6
		p.tangential_accel_max = 0.6
		p.damping_min = 0.3
		p.damping_max = 0.8
		p.scale_amount_min = 0.8
		p.scale_amount_max = 1.2
		p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
		_midge_root.add_child(p)
		_clouds.append(p)
		_cloud_goal.append(Vector3.ZERO)
	_place_all_clouds()

# --- Búsqueda de puntos ---
func _center() -> Vector3:
	if player != null and is_instance_valid(player):
		return player.global_position
	return Vector3.ZERO

## Punto con suelo bajo y agua cerca; devuelve (x, y_agua_o_suelo, z) o INF si no halla.
func _find_wet_spot(c: Vector3, rmin: float, rmax: float, tries: int) -> Vector3:
	if terrain == null:
		return Vector3.INF
	for i: int in tries:
		var a: float = randf() * TAU
		var r: float = randf_range(rmin, rmax)
		var x: float = c.x + cos(a) * r
		var z: float = c.z + sin(a) * r
		var h: float = terrain.height_at(x, z)
		if h < GROUND_MIN or h > GROUND_MAX:
			continue
		# agua cerca: alguna muestra a 3-6 m con h < WATER_H
		var wet: bool = false
		for k: int in 6:
			var b: float = float(k) / 6.0 * TAU
			var dd: float = 4.0
			if terrain.height_at(x + cos(b) * dd, z + sin(b) * dd) < WATER_H:
				wet = true
				break
		if wet:
			return Vector3(x, maxf(h, 0.0), z)
	return Vector3.INF

func _place_all_dragons() -> void:
	for d: Dictionary in _dragons:
		_place_dragon(d, true)

func _place_dragon(d: Dictionary, _first: bool) -> void:
	var c: Vector3 = _center()
	var spot: Vector3 = _find_wet_spot(c, SPAWN_MIN, SPAWN_MAX, 25)
	if spot.x == INF:
		d["ready"] = false
		d["anchor"] = Vector3(c.x, -100.0, c.z)
		(d["node"] as Node3D).visible = false
		return
	d["ready"] = true
	(d["node"] as Node3D).visible = true
	d["anchor"] = spot
	var p: Vector3 = spot + Vector3(0.0, randf_range(FLY_MIN_H, FLY_MAX_H), 0.0)
	d["pos"] = p
	d["target"] = p
	d["vel"] = Vector3.ZERO
	(d["node"] as Node3D).global_position = p

func _place_all_clouds() -> void:
	var c: Vector3 = _center()
	for i: int in _clouds.size():
		var spot: Vector3 = _find_wet_spot(c, 6.0, 30.0, 30)
		if spot.x == INF:
			_clouds[i].visible = false
			continue
		_clouds[i].visible = true
		_clouds[i].global_position = spot + Vector3(0.0, 1.2, 0.0)
		_cloud_goal[i] = _clouds[i].global_position

# --- Proceso ---
func _process(delta: float) -> void:
	if _noche > 0.5:
		return
	_t += delta
	_reloc_timer -= delta
	var c: Vector3 = _center()
	var do_reloc: bool = _reloc_timer <= 0.0
	if do_reloc:
		_reloc_timer = 1.0
	for d: Dictionary in _dragons:
		_update_dragon(d, delta, c, do_reloc)
	if do_reloc:
		_update_clouds(c)

func _off_camera(p: Vector3) -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return true
	return cam.is_position_behind(p) or not cam.is_position_in_frustum(p)

func _update_dragon(d: Dictionary, delta: float, c: Vector3, do_reloc: bool) -> void:
	var node: Node3D = d["node"] as Node3D
	var pos: Vector3 = d["pos"] as Vector3
	if do_reloc:
		var far: bool = Vector2(pos.x - c.x, pos.z - c.z).length() > RELOC_FAR
		if (far or not (d["ready"] as bool)) and _off_camera(pos):
			_place_dragon(d, false)
			pos = d["pos"] as Vector3
	if not (d["ready"] as bool):
		return
	var vel: Vector3 = d["vel"] as Vector3
	var st: float = (d["state_t"] as float) - delta
	var hover: bool = d["hover"] as bool
	if st <= 0.0:
		# nuevo estado: hover o arranque rápido
		var anchor: Vector3 = d["anchor"] as Vector3
		if hover or randf() < 0.3:
			hover = false
			st = randf_range(0.5, 1.4)
			var ang: float = randf() * TAU
			var dist: float = randf_range(1.5, 5.0)
			var tx: float = anchor.x + cos(ang) * dist
			var tz: float = anchor.z + sin(ang) * dist
			var gy: float = maxf(terrain.height_at(tx, tz), 0.0)
			d["target"] = Vector3(tx, gy + randf_range(FLY_MIN_H, FLY_MAX_H), tz)
			var dir: Vector3 = ((d["target"] as Vector3) - pos).normalized()
			vel = dir * DRAGON_BURST
		else:
			hover = true
			st = randf_range(0.6, 1.8)
		d["hover"] = hover
	d["state_t"] = st
	var tgt: Vector3 = d["target"] as Vector3
	var desired: Vector3 = Vector3.ZERO
	if not hover:
		var to: Vector3 = tgt - pos
		var dist2: float = to.length()
		if dist2 > 0.3:
			var side: Vector3 = to.normalized().cross(Vector3.UP)
			var zig: float = sin(_t * 9.0 + (d["phase"] as float)) * 1.6
			desired = to.normalized() * DRAGON_SPEED + side * zig
		else:
			d["hover"] = true
			d["state_t"] = randf_range(0.5, 1.2)
	else:
		# microtemblor en el aire
		desired = Vector3(sin(_t * 13.0 + (d["phase"] as float)), sin(_t * 9.0), cos(_t * 11.0)) * 0.15
	vel = vel.lerp(desired, clampf(delta * (3.0 if not hover else 6.0), 0.0, 1.0))
	pos += vel * delta
	d["vel"] = vel
	d["pos"] = pos
	node.global_position = pos
	# orientación suave hacia la velocidad
	var flat: Vector3 = Vector3(vel.x, 0.0, vel.z)
	if flat.length() > 0.3:
		var want: float = atan2(flat.x, flat.z)
		node.rotation.y = lerp_angle(node.rotation.y, want, clampf(delta * 8.0, 0.0, 1.0))
	# aleteo
	var flap: float = sin(_t * WING_FLAP_HZ + (d["phase"] as float)) * 0.6
	var wings: Array[Node3D] = []
	wings.assign(d["wings"])
	for k: int in wings.size():
		var w: Node3D = wings[k]
		var s: float = w.get_meta("side") as float
		var off: float = 0.0 if k < 2 else PI * 0.5
		w.rotation.z = s * (flap if k < 2 else -flap * 0.8)
		w.rotation.z += s * off * 0.0

func _update_clouds(c: Vector3) -> void:
	for i: int in _clouds.size():
		var cl: CPUParticles3D = _clouds[i]
		var d: float = Vector2(cl.global_position.x - c.x, cl.global_position.z - c.z).length()
		if (d > RELOC_FAR or not cl.visible) and (not cl.visible or _off_camera(cl.global_position)):
			var spot: Vector3 = _find_wet_spot(c, 6.0, 35.0, 20)
			if spot.x != INF:
				cl.visible = true
				cl.global_position = spot + Vector3(0.0, 1.2, 0.0)
				cl.restart()
			else:
				cl.visible = false
