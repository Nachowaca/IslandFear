class_name AmbientArt
extends Node3D

## Ambiente cálido de noche: fogatas abandonadas, flores ámbar y luces ámbar en la cueva y los claros.
## Solo las luces reales más cercanas al jugador están encendidas (límite del renderer Mobile);
## el resto es emisión + halo.

var terrain: IslandTerrain

const MAX_REAL_LIGHTS: int = 3
const FIRE_SCALE: float = 0.15
var _fire_scene: PackedScene = load("res://assets/campfire/low_poly_campfire.glb") as PackedScene
const LIGHT_RANGE: float = 38.0

var _rng := RandomNumberGenerator.new()
var _fires: Array[Dictionary] = []      # {pos, flame, light, ph}
var _spots: Array[Dictionary] = []      # luces ámbar fijas: {pos, light, energy}
var _bulb_mat: StandardMaterial3D
var _flame_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _night: float = 0.0
var _time: float = 0.0
var _player: Node3D
var _dn: Node
var _tick: float = 0.0

func _ready() -> void:
	if terrain == null:
		return
	_rng.seed = terrain.noise_seed * 7 + 19
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.albedo_color = Color(0.25, 0.14, 0.03)
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = Color(1.0, 0.62, 0.18)
	_bulb_mat.emission_energy_multiplier = 0.2
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.albedo_color = Color(1.0, 0.55, 0.12, 0.9)
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.albedo_texture = _radial()
	_halo_mat.albedo_color = Color(1.0, 0.6, 0.2, 0.0)
	_halo_mat.no_depth_test = false
	# _build_campfires()   # desactivadas por ahora (fogatas solas del mapa); la función sigue disponible
	_build_flowers_and_spots()
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_dn = get_tree().get_first_node_in_group("daynight")

func _radial() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

func _find_land(near: Vector2, rad: float, tries: int = 40) -> Vector3:
	for i in tries:
		var a: float = _rng.randf() * TAU
		var d: float = rad * sqrt(_rng.randf())
		var x: float = near.x + cos(a) * d
		var z: float = near.y + sin(a) * d
		var y: float = terrain.height_at(x, z)
		if y > 2.0 and y < 9.0 and not terrain.is_in_pond_area(x, z, 1.1) and not terrain.is_in_cave_area(x, z, 1.0):
			return Vector3(x, y, z)
	return Vector3(0, -100, 0)

func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	m.scale = scl
	parent.add_child(m)
	return m

func _build_campfires() -> void:
	var centers: Array[Vector2] = [Vector2(-5, 40), Vector2(30, -5), Vector2(-60, 5), Vector2(10, 70)]
	for c: Vector2 in centers:
		var p: Vector3 = _find_land(c, 22.0)
		if p.y < -50.0:
			continue
		var root := Node3D.new()
		root.position = p
		root.rotation.y = _rng.randf() * TAU
		add_child(root)
		var inst: Node3D = _fire_scene.instantiate() as Node3D
		var dirt: Node = inst.find_child("polySurface7", true, false)
		if dirt != null:
			dirt.get_parent().remove_child(dirt)
			dirt.free()
		inst.scale = Vector3.ONE * FIRE_SCALE
		inst.position = Vector3(0, 0.11, 0)
		root.add_child(inst)
		var flame_nodes: Array[Node3D] = []
		for fm: Node in inst.find_children("*fire*", "MeshInstance3D", true, false):
			flame_nodes.append(fm.get_parent() as Node3D)
		var hm := QuadMesh.new()
		hm.size = Vector2(5.0, 5.0)
		var hal: MeshInstance3D = _mi(root, hm, _halo_mat.duplicate() as Material, Vector3(0, 0.6, 0))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.58, 0.2)
		l.omni_range = 9.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.position = Vector3(0, 0.7, 0)
		l.visible = false
		root.add_child(l)
		_fires.append({"pos": p, "flames": flame_nodes, "light": l, "halo": hal, "ph": _rng.randf() * TAU})

func _build_flowers_and_spots() -> void:
	var anchors: Array[Vector3] = []
	var ce: Vector2 = IslandTerrain.CAVE_CENTER + IslandTerrain.cave_dir2() * 13.0
	anchors.append(Vector3(ce.x, terrain.height_at(ce.x, ce.y), ce.y))
	if terrain.eco != null:
		for mc: Vector3 in terrain.eco.mystery_centers:
			anchors.append(Vector3(mc.x, terrain.height_at(mc.x, mc.z), mc.z))
	var bulb := SphereMesh.new()
	bulb.radius = 0.07
	bulb.height = 0.14
	bulb.radial_segments = 6
	bulb.rings = 3
	var stem := CylinderMesh.new()
	stem.top_radius = 0.008
	stem.bottom_radius = 0.012
	stem.height = 0.35
	stem.radial_segments = 4
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.15, 0.3, 0.12)
	for a: Vector3 in anchors:
		var lt := OmniLight3D.new()
		lt.light_color = Color(1.0, 0.6, 0.22)
		lt.omni_range = 11.0
		lt.light_energy = 0.0
		lt.position = a + Vector3(0, 1.6, 0)
		lt.visible = false
		add_child(lt)
		_spots.append({"pos": a, "light": lt, "energy": 1.3})
		var hm := QuadMesh.new()
		hm.size = Vector2(4.0, 4.0)
		var hal := MeshInstance3D.new()
		hal.mesh = hm
		hal.material_override = _halo_mat
		hal.position = a + Vector3(0, 1.4, 0)
		add_child(hal)
		for i in 14:
			var q: Vector3 = _find_land(Vector2(a.x, a.z), 7.0, 6)
			if q.y < -50.0:
				continue
			var f := Node3D.new()
			f.position = q
			add_child(f)
			_mi(f, stem, stem_mat, Vector3(0, 0.17, 0))
			_mi(f, bulb, _bulb_mat, Vector3(0, 0.37, 0))

func _process(delta: float) -> void:
	_time += delta
	var target: float = float(_dn.get("night_amount")) if _dn != null else 0.0
	_night = lerpf(_night, target, minf(delta * 2.0, 1.0))
	_bulb_mat.emission_energy_multiplier = 0.15 + _night * 2.6
	_halo_mat.albedo_color.a = _night * 0.22
	_tick -= delta
	var dists: Array[Dictionary] = []
	if _tick <= 0.0:
		_tick = 0.4
		var pp: Vector3 = _player.global_position if _player != null else Vector3(0, 0, 90)
		for f: Dictionary in _fires:
			dists.append({"d": (f["pos"] as Vector3).distance_to(pp), "node": f["light"], "e": 1.9})
		for s: Dictionary in _spots:
			dists.append({"d": (s["pos"] as Vector3).distance_to(pp), "node": s["light"], "e": float(s["energy"])})
		dists.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
		for i in dists.size():
			var on: bool = i < MAX_REAL_LIGHTS and float(dists[i]["d"]) < LIGHT_RANGE
			var ln: OmniLight3D = dists[i]["node"] as OmniLight3D
			ln.visible = on
			ln.set_meta("base", float(dists[i]["e"]))
	for s: Dictionary in _spots:
		var sl: OmniLight3D = s["light"] as OmniLight3D
		if sl.visible:
			sl.light_energy = float(sl.get_meta("base", 1.0)) * _night * (0.9 + 0.1 * sin(_time * 1.7))
	for f: Dictionary in _fires:
		var ph: float = float(f["ph"])
		var fl: float = 0.8 + 0.2 * sin(_time * 11.0 + ph) + 0.12 * sin(_time * 23.0 + ph * 2.0)
		var lamp_on: float = 0.35 + 0.65 * _night
		var fns: Array = f["flames"]
		for i in fns.size():
			var ph2: float = ph + float(i) * 1.7
			(fns[i] as Node3D).scale = Vector3(1.0 + 0.05 * sin(_time * 9.0 + ph2), 1.0 + 0.1 * sin(_time * 7.0 + ph2 * 1.3) + 0.05 * sin(_time * 19.0 + ph2), 1.0 + 0.05 * cos(_time * 8.0 + ph2))
		(f["halo"] as MeshInstance3D).visible = true
		((f["halo"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.16 * lamp_on * fl
		var l: OmniLight3D = f["light"] as OmniLight3D
		if l.visible:
			l.light_energy = float(l.get_meta("base", 1.9)) * lamp_on * fl
