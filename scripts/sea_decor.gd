extends Node3D

## Decoración del océano (pack coral_water): corales en los bajos de todas las costas,
## cardúmenes que circulan sobre los bajos y dos boyas con vaivén.
## Corales = MultiMesh (casi gratis). Cardúmenes = una malla cada uno, visibles solo cerca del jugador.

const CORAL_SCENE: PackedScene = preload("res://assets/coral_water/lowpoly_coral_pack.glb")
const FISH_SCENE: PackedScene = preload("res://assets/coral_water/fishies.glb")
const BUOY_SCENE: PackedScene = preload("res://assets/coral_water/oceanographic_buoy_ems_icatmar.glb")

const CORAL_PATCHES: int = 26
const CORALS_PER_PATCH: int = 4
const SCHOOLS: int = 7
const FISH_SCALE: float = 0.3
const SHOW_DIST: float = 150.0

var terrain: IslandTerrain
var water_y: float = 0.35
var buoy_spots: Array[Vector3] = []     ## posiciones (x, _, z) de las boyas

var _rng := RandomNumberGenerator.new()
var _schools: Array[Dictionary] = []
var _buoys: Array[Node3D] = []
var _player: Node3D
var _time: float = 0.0
var _vis_timer: float = 0.0

func _ready() -> void:
	if terrain == null:
		return
	_rng.seed = 9137
	_build_corals()
	_build_schools()
	_build_buoys()

## Busca desde tierra hacia afuera el primer punto sumergido en la dirección dada y avanza `extra` metros más.
func _sea_point(ang: float, extra: float) -> Vector3:
	var dir: Vector2 = Vector2(cos(ang), sin(ang))
	var r: float = terrain.radius * 0.5
	while r < terrain.radius * 1.6:
		var h: float = terrain.height_at(dir.x * r, dir.y * r)
		if h < water_y - 0.5:
			var rr: float = r + extra
			return Vector3(dir.x * rr, terrain.height_at(dir.x * rr, dir.y * rr), dir.y * rr)
		r += 1.5
	return Vector3(0, -999.0, 0)

# ------------------------------------------------------------------ corales

func _build_corals() -> void:
	# cada coral del pack: sus mallas centradas en el origen y apoyadas en y = 0
	var parts: Array = []        # [{"meshes": Array[Mesh], "offs": Array[Transform3D], "xf": Array[Transform3D]}]
	var src: Node3D = CORAL_SCENE.instantiate() as Node3D
	var stack: Array = [src]
	var corals: Array[Node3D] = []
	while stack.size() > 0:
		var c: Node = stack.pop_back()
		for ch in c.get_children():
			stack.append(ch)
		if c is Node3D and String(c.name).begins_with("coral_"):
			corals.append(c as Node3D)
	for cn: Node3D in corals:
		var meshes: Array[Mesh] = []
		var offs: Array[Transform3D] = []
		var cstack: Array = [cn]
		var all_aabb: AABB = AABB()
		var first: bool = true
		var items: Array = []
		while cstack.size() > 0:
			var n: Node = cstack.pop_back()
			for ch in n.get_children():
				cstack.append(ch)
			if n is MeshInstance3D:
				var mi: MeshInstance3D = n as MeshInstance3D
				var t: Transform3D = Transform3D.IDENTITY
				var cur: Node = mi
				while cur != null and cur != src:
					t = (cur as Node3D).transform * t
					cur = cur.get_parent()
				var bb: AABB = t * mi.mesh.get_aabb()
				all_aabb = bb if first else all_aabb.merge(bb)
				first = false
				items.append([mi.mesh, t])
		var center: Vector3 = Vector3(all_aabb.get_center().x, all_aabb.position.y, all_aabb.get_center().z)
		for it: Array in items:
			meshes.append(it[0])
			var tt: Transform3D = it[1]
			tt.origin -= center
			offs.append(tt)
		parts.append({"meshes": meshes, "offs": offs, "xf": [] as Array[Transform3D]})
	src.free()
	if parts.is_empty():
		return
	# parches de 2-5 corales sobre los bajos de toda la costa
	for i in CORAL_PATCHES:
		var sp: Vector3 = _sea_point(TAU * (float(i) + _rng.randf_range(0.0, 1.0)) / float(CORAL_PATCHES), _rng.randf_range(0.0, 7.0))
		if sp.y < -900.0:
			continue
		var n_in: int = CORALS_PER_PATCH + _rng.randi_range(-1, 1)
		for k in n_in:
			var q: Vector2 = Vector2(sp.x, sp.z) + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
			var h: float = terrain.height_at(q.x, q.y)
			if h > water_y - 0.35 or h < water_y - 4.0:
				continue
			var idx: int = _rng.randi() % parts.size()
			var sc: float = _rng.randf_range(0.7, 1.5)
			var b: Basis = Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc)
			(parts[idx]["xf"] as Array[Transform3D]).append(Transform3D(b, Vector3(q.x, h - 0.05, q.y)))
	var root := Node3D.new()
	root.name = "Corales"
	add_child(root)
	for pt: Dictionary in parts:
		var xf: Array[Transform3D] = pt["xf"]
		if xf.is_empty():
			continue
		var meshes2: Array[Mesh] = pt["meshes"]
		var offs2: Array[Transform3D] = pt["offs"]
		for m in meshes2.size():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes2[m]
			mm.instance_count = xf.size()
			for j in xf.size():
				mm.set_instance_transform(j, xf[j] * offs2[m])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 160.0
			root.add_child(mmi)

# ------------------------------------------------------------------ cardúmenes

func _build_schools() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.78, 0.9)
	mat.roughness = 0.45
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.5, 0.65)
	mat.emission_energy_multiplier = 0.5
	for i in SCHOOLS:
		var sp: Vector3 = _sea_point(_rng.randf() * TAU, _rng.randf_range(4.0, 14.0))
		if sp.y < -900.0:
			continue
		var fish: Node3D = FISH_SCENE.instantiate() as Node3D
		fish.scale = Vector3.ONE * FISH_SCALE * _rng.randf_range(0.8, 1.2)
		_tint_all(fish, mat)
		add_child(fish)
		fish.visible = false
		_schools.append({"node": fish, "c": Vector2(sp.x, sp.z), "ang": _rng.randf() * TAU,
			"rad": _rng.randf_range(3.0, 8.0), "spd": _rng.randf_range(0.08, 0.2) * (1.0 if _rng.randf() < 0.5 else -1.0),
			"depth": _rng.randf_range(0.9, 1.6), "off": _rng.randf() * 10.0})

func _tint_all(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ch in n.get_children():
		_tint_all(ch, mat)

# ------------------------------------------------------------------ boyas

func _build_buoys() -> void:
	for p: Vector3 in buoy_spots:
		var b: Node3D = BUOY_SCENE.instantiate() as Node3D
		b.position = Vector3(p.x, water_y - 0.15, p.z)
		b.rotation.y = _rng.randf() * TAU
		add_child(b)
		_buoys.append(b)

# ------------------------------------------------------------------ movimiento

func _process(delta: float) -> void:
	_time += delta
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	for sc: Dictionary in _schools:
		var node: Node3D = sc["node"]
		if not node.visible:
			continue
		sc["ang"] = float(sc["ang"]) + float(sc["spd"]) * delta
		var a: float = sc["ang"]
		var c: Vector2 = sc["c"]
		var rad: float = float(sc["rad"]) + sin(_time * 0.2 + float(sc["off"])) * 1.2
		node.position = Vector3(c.x + cos(a) * rad, water_y - float(sc["depth"]) + sin(_time * 0.6 + float(sc["off"])) * 0.2, c.y + sin(a) * rad)
		var tangent: Vector3 = Vector3(-sin(a), 0.0, cos(a)) * signf(float(sc["spd"]))
		node.rotation.y = atan2(tangent.x, tangent.z) + sin(_time * 1.3 + float(sc["off"])) * 0.1
	for i in _buoys.size():
		var b: Node3D = _buoys[i]
		b.position.y = water_y - 0.15 + sin(_time * 0.9 + float(i) * 2.0) * 0.12
		b.rotation.x = sin(_time * 0.7 + float(i)) * 0.06
		b.rotation.z = cos(_time * 0.8 + float(i) * 1.7) * 0.06
	_vis_timer -= delta
	if _vis_timer <= 0.0:
		_vis_timer = 0.6
		for sc: Dictionary in _schools:
			var nd: Node3D = sc["node"]
			if _player == null:
				nd.visible = false
			else:
				var cc: Vector2 = sc["c"]
				var near: bool = Vector2(_player.global_position.x, _player.global_position.z).distance_to(cc) < SHOW_DIST
				if near and not nd.visible:
					nd.position = Vector3(cc.x, water_y - 1.0, cc.y)
				nd.visible = near

