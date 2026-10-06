class_name IslandLife
extends Node3D

## Puebla la isla: recursos (madera, piedra, arcilla), comida (cocos, bayas, raíces, hierbas, hongos
## comestibles y venenosos, conchas), agua dulce con peces, pasto y fauna (gaviotas, pajaritos, cangrejos).
## Todo es low-poly generado por código. Los objetos recolectables son WorldItem (grupo "pickup").

var terrain: IslandTerrain
var seed_value: int = 7

@export var log_count: int = 36
@export var branch_count: int = 90
@export var driftwood_count: int = 28
@export var stone_count: int = 100
@export var clay_count: int = 16
@export var coconut_count: int = 50
@export var berry_bush_count: int = 48
@export var root_count: int = 40
@export var herb_count: int = 30
@export var mushroom_clusters: int = 34
@export var shell_count: int = 50
@export var grass_spots: int = 900
@export var gull_count: int = 9
@export var songbird_count: int = 22
@export var crab_count: int = 22
@export var fish_count: int = 10

var _rng := RandomNumberGenerator.new()
var _materials: Dictionary = {}
var _fish: Array[Dictionary] = []
var _time: float = 0.0
var _critters: Array[Node] = []

func _ready() -> void:
	_rng.seed = seed_value * 31 + 5
	_build_pond()
	_spawn_wood()
	_spawn_stones_and_clay()
	_spawn_food()
	_spawn_mushrooms()
	_spawn_shells()
	_spawn_materials()
	_spawn_grass()
	_spawn_wildlife()
	_spawn_kit_ground()
	_spawn_heart_tree()
	_spawn_stelas()
	call_deferred("_link_player")

func _process(delta: float) -> void:
	_time += delta
	_update_heart(delta)
	for f: Dictionary in _fish:
		var node: Node3D = f["node"]
		f["angle"] = float(f["angle"]) + float(f["speed"]) * delta
		var a: float = f["angle"]
		var r: float = f["radius"]
		var p: Vector3 = terrain.POND_CENTER.x * Vector3.RIGHT + terrain.POND_CENTER.y * Vector3.BACK
		node.position = Vector3(p.x + cos(a) * r, terrain.pond_water_level - float(f["depth"]), p.z + sin(a) * r)
		var tangent: Vector3 = Vector3(-sin(a), 0, cos(a)) * signf(float(f["speed"]))
		node.look_at(node.position + tangent, Vector3.UP)
		node.rotation.z = sin(_time * 8.0 + a) * 0.1

func _link_player() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	for c: Node in _critters:
		if c is Bird:
			(c as Bird).player = player
		elif c is Crab:
			(c as Crab).player = player

# ------------------------------------------------------------------ helpers

func _material(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		_materials[key] = m
	return _materials[key]

func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

func _cyl(r_top: float, r_bottom: float, h: float, seg: int = 6) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = seg
	return m

func _sph(r: float, seg: int = 6, rings: int = 3) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m

func _prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m

func _item(item_id: String, display_name: String, amount: int, pos: Vector3, yaw: float = 0.0) -> WorldItem:
	var it := WorldItem.new()
	it.name = item_id.capitalize().replace(" ", "")
	it.item_id = item_id
	it.display_name = display_name
	it.amount = amount
	it.position = pos
	it.rotation.y = yaw
	add_child(it)
	return it

func _spot(min_h: float, max_h: float) -> Vector3:
	return terrain.find_spot(_rng, min_h, max_h)

func _valid(p: Vector3) -> bool:
	return p.y > -90.0

# ------------------------------------------------------------------ agua dulce

func _build_pond() -> void:
	var center: Vector2 = terrain.POND_CENTER
	var radius: float = terrain.POND_RADIUS * 1.6
	var water := MeshInstance3D.new()
	var disc := _cyl(radius, radius, 0.04, 20)
	water.mesh = disc
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.5, 0.62, 0.72)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic_specular = 0.9
	water.material_override = m
	water.position = Vector3(center.x, terrain.pond_water_level, center.y)
	water.name = "PondWater"
	add_child(water)
	var it: WorldItem = _item("agua_dulce", "Agua dulce", 1, Vector3(center.x, terrain.pond_water_level, center.y))
	it.hydration = 1.0
	it.interact_radius = radius + 0.8
	# peces
	for i in fish_count:
		var fish := Node3D.new()
		_mesh(fish, _sph(0.1, 6, 3), Color(0.95, 0.55, 0.15), Vector3.ZERO, Vector3.ZERO, Vector3(0.6, 0.6, 1.5))
		_mesh(fish, _prism(Vector3(0.1, 0.12, 0.02)), Color(0.9, 0.4, 0.1), Vector3(0, 0, 0.17), Vector3(0, 0, 0))
		add_child(fish)
		_fish.append({
			"node": fish,
			"angle": _rng.randf() * TAU,
			"radius": _rng.randf_range(0.8, radius * 0.55),
			"speed": _rng.randf_range(0.3, 0.7) * (1.0 if _rng.randf() < 0.5 else -1.0),
			"depth": _rng.randf_range(0.45, 0.9),
		})
	# juncos alrededor de la orilla
	for i in 30:
		var ang: float = _rng.randf() * TAU
		var rr: float = radius * _rng.randf_range(0.95, 1.12)
		var rx: float = center.x + cos(ang) * rr
		var rz: float = center.y + sin(ang) * rr
		var gy: float = terrain.height_at(rx, rz)
		if gy < terrain.pond_water_level - 0.4:
			continue
		var reed := Node3D.new()
		reed.position = Vector3(rx, gy, rz)
		_mesh(reed, _cyl(0.02, 0.025, 1.4, 4), Color(0.4, 0.5, 0.2), Vector3(0, 0.7, 0), Vector3(_rng.randf_range(-0.12, 0.12), 0, _rng.randf_range(-0.12, 0.12)))
		if _rng.randf() < 0.5:
			_mesh(reed, _cyl(0.05, 0.05, 0.22, 5), Color(0.4, 0.25, 0.12), Vector3(0, 1.3, 0))
		add_child(reed)

# ------------------------------------------------------------------ madera

func _spawn_wood() -> void:
	for i in log_count:
		var p: Vector3 = _spot(0.9, 6.0)
		if not _valid(p):
			continue
		var it: WorldItem = _item("madera", "Tronco", 3, p, _rng.randf() * TAU)
		_mesh(it, _cyl(0.16, 0.18, 1.6, 7), Color(0.45, 0.3, 0.17), Vector3(0, 0.17, 0), Vector3(PI / 2.0, 0, 0))
		_mesh(it, _cyl(0.1, 0.1, 0.02, 7), Color(0.75, 0.6, 0.4), Vector3(0, 0.17, -0.8), Vector3(PI / 2.0, 0, 0))
	for i in branch_count:
		var p2: Vector3 = _spot(0.9, 6.5)
		if not _valid(p2):
			continue
		var br: WorldItem = _item("rama", "Rama", 1, p2, _rng.randf() * TAU)
		_mesh(br, _cyl(0.025, 0.04, 0.9, 4), Color(0.4, 0.28, 0.16), Vector3(0, 0.06, 0), Vector3(PI / 2.0, 0, 0.1))
		_mesh(br, _cyl(0.015, 0.025, 0.35, 4), Color(0.4, 0.28, 0.16), Vector3(0.1, 0.09, -0.2), Vector3(PI / 2.0, 0.7, 0))
	for i in driftwood_count:
		var p3: Vector3 = _spot(0.5, 1.0)
		if not _valid(p3):
			continue
		var dw: WorldItem = _item("madera", "Madera de playa", 2, p3, _rng.randf() * TAU)
		_mesh(dw, _cyl(0.08, 0.13, 1.2, 5), Color(0.72, 0.66, 0.56), Vector3(0, 0.1, 0), Vector3(PI / 2.0, 0, 0.15))

# ------------------------------------------------------------------ piedra y tierra

func _spawn_stones_and_clay() -> void:
	for i in stone_count:
		var p: Vector3 = _spot(0.9, 8.0)
		if not _valid(p):
			continue
		var it: WorldItem = _item("piedra", "Piedra", 1, p, _rng.randf() * TAU)
		var g: float = _rng.randf_range(0.45, 0.6)
		_mesh(it, _sph(0.13, 5, 3), Color(g, g, g + 0.03), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(1.0, 0.6, 0.85))
	# arcilla / tierra húmeda alrededor de la laguna
	var center: Vector2 = terrain.POND_CENTER
	for i in clay_count:
		var ang: float = _rng.randf() * TAU
		var rr: float = terrain.POND_RADIUS * _rng.randf_range(1.9, 2.8)
		var x: float = center.x + cos(ang) * rr
		var z: float = center.y + sin(ang) * rr
		var y: float = terrain.height_at(x, z)
		if y < 0.9:
			continue
		var it2: WorldItem = _item("arcilla", "Arcilla", 2, Vector3(x, y, z), _rng.randf() * TAU)
		_mesh(it2, _sph(0.35, 7, 3), Color(0.58, 0.36, 0.24), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(1.0, 0.35, 1.0))
		_mesh(it2, _sph(0.2, 6, 3), Color(0.5, 0.3, 0.2), Vector3(0.25, 0.04, 0.1), Vector3.ZERO, Vector3(1.0, 0.4, 1.0))

# ------------------------------------------------------------------ comida

func _spawn_food() -> void:
	# cocos: caídos cerca de las palmeras
	var spawned: int = 0
	for pp: Vector3 in terrain.palm_positions:
		if spawned >= coconut_count:
			break
		for k in _rng.randi_range(1, 2):
			var off: Vector2 = Vector2(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-1.6, 1.6))
			var x: float = pp.x + off.x
			var z: float = pp.z + off.y
			var y: float = terrain.height_at(x, z)
			if y < 0.7:
				continue
			var it: WorldItem = _item("coco", "Coco", 1, Vector3(x, y, z), _rng.randf() * TAU)
			it.edible = true
			it.nutrition = 0.25
			it.hydration = 0.2
			_mesh(it, _sph(0.14, 7, 4), Color(0.33, 0.21, 0.11), Vector3(0, 0.13, 0))
			_mesh(it, _sph(0.04, 4, 2), Color(0.15, 0.1, 0.05), Vector3(0.05, 0.22, 0.05))
			spawned += 1
	# arbustos de bayas
	for i in berry_bush_count:
		var p: Vector3 = _spot(1.4, 5.0)
		if not _valid(p):
			continue
		var it2: WorldItem = _item("bayas", "Bayas", 3, p, _rng.randf() * TAU)
		it2.edible = true
		it2.nutrition = 0.15
		it2.hydration = 0.05
		_mesh(it2, _sph(0.55, 6, 3), Color(0.2, 0.42, 0.18), Vector3(0, 0.4, 0), Vector3.ZERO, Vector3(1, 0.8, 1))
		for b in 8:
			var a: float = _rng.randf() * TAU
			var rad: float = _rng.randf_range(0.3, 0.52)
			_mesh(it2, _sph(0.06, 5, 3), Color(0.75, 0.1, 0.2), Vector3(cos(a) * rad, _rng.randf_range(0.3, 0.7), sin(a) * rad))
	# raíces comestibles (tubérculos)
	for i in root_count:
		var p2: Vector3 = _spot(1.2, 5.5)
		if not _valid(p2):
			continue
		var it3: WorldItem = _item("raiz", "Raíz comestible", 1, p2, _rng.randf() * TAU)
		it3.edible = true
		it3.nutrition = 0.3
		for l in 5:
			var a2: float = TAU * l / 5.0
			_mesh(it3, _prism(Vector3(0.14, 0.4, 0.02)), Color(0.25, 0.55, 0.22), Vector3(cos(a2) * 0.1, 0.18, sin(a2) * 0.1), Vector3(sin(a2) * 0.4, -a2, -cos(a2) * 0.4))
		_mesh(it3, _cyl(0.0, 0.07, 0.18, 5), Color(0.9, 0.5, 0.15), Vector3(0, 0.05, 0))
	# hierbas medicinales
	for i in herb_count:
		var p3: Vector3 = _spot(1.2, 5.5)
		if not _valid(p3):
			continue
		var it4: WorldItem = _item("hierba", "Hierba medicinal", 1, p3, _rng.randf() * TAU)
		for l in 6:
			var a3: float = TAU * l / 6.0
			_mesh(it4, _prism(Vector3(0.1, 0.32, 0.015)), Color(0.5, 0.75, 0.35), Vector3(cos(a3) * 0.08, 0.15, sin(a3) * 0.08), Vector3(sin(a3) * 0.3, -a3, -cos(a3) * 0.3))
		_mesh(it4, _sph(0.035, 4, 2), Color(0.95, 0.95, 0.85), Vector3(0, 0.34, 0))

func _spawn_mushrooms() -> void:
	if terrain.tree_positions.is_empty():
		return
	for i in mushroom_clusters:
		var idx: int = _rng.randi_range(0, terrain.tree_positions.size() - 1)
		var tp: Vector3 = terrain.tree_positions[idx]
		var poisonous: bool = i % 2 == 1
		var base_a: float = _rng.randf() * TAU
		var base_r: float = _rng.randf_range(1.0, 2.4)
		for k in _rng.randi_range(2, 4):
			var x: float = tp.x + cos(base_a) * base_r + _rng.randf_range(-0.35, 0.35)
			var z: float = tp.z + sin(base_a) * base_r + _rng.randf_range(-0.35, 0.35)
			var y: float = terrain.height_at(x, z)
			if y < 1.0:
				continue
			var it: WorldItem
			var s: float = _rng.randf_range(0.8, 1.4)
			if poisonous:
				it = _item("hongo_venenoso", "Hongo rojo", 1, Vector3(x, y, z), _rng.randf() * TAU)
				it.poisonous = true
				it.edible = true # se puede comer… pero hace daño
				_mesh(it, _cyl(0.025 * s, 0.035 * s, 0.13 * s, 5), Color(0.92, 0.9, 0.8), Vector3(0, 0.065 * s, 0))
				_mesh(it, _sph(0.1 * s, 7, 3), Color(0.8, 0.1, 0.1), Vector3(0, 0.14 * s, 0), Vector3.ZERO, Vector3(1, 0.55, 1))
				for d in 5:
					var da: float = _rng.randf() * TAU
					var dr: float = _rng.randf_range(0.02, 0.07) * s
					_mesh(it, _sph(0.014 * s, 4, 2), Color(0.98, 0.96, 0.9), Vector3(cos(da) * dr, 0.18 * s, sin(da) * dr))
			else:
				it = _item("hongo_comestible", "Hongo pardo", 1, Vector3(x, y, z), _rng.randf() * TAU)
				it.edible = true
				it.nutrition = 0.12
				_mesh(it, _cyl(0.03 * s, 0.04 * s, 0.12 * s, 5), Color(0.9, 0.85, 0.72), Vector3(0, 0.06 * s, 0))
				_mesh(it, _sph(0.09 * s, 7, 3), Color(0.55, 0.38, 0.22), Vector3(0, 0.13 * s, 0), Vector3.ZERO, Vector3(1, 0.5, 1))

## Hojas grandes caídas bajo las palmeras y matas de paja seca (yesca para el fuego).
func _spawn_materials() -> void:
	var made: int = 0
	var palms: Array[Vector3] = terrain.palm_positions
	for pp: Vector3 in palms:
		if made >= 26:
			break
		if _rng.randf() > 0.55:
			continue
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(1.2, 3.0)
		var x: float = pp.x + cos(a) * d
		var z: float = pp.z + sin(a) * d
		var y: float = terrain.height_at(x, z)
		if y < 0.8:
			continue
		var it: WorldItem = _item("hoja_grande", "Hoja grande", 1, Vector3(x, y, z), _rng.randf() * TAU)
		it.add_child(ItemDB.make_visual("hoja_grande"))
		made += 1
	for i in 46:
		var p: Vector3 = _spot(1.0, 4.5)
		if not _valid(p):
			continue
		var s: WorldItem = _item("paja", "Paja seca", _rng.randi_range(1, 2), p, _rng.randf() * TAU)
		s.add_child(ItemDB.make_visual("paja"))

func _spawn_shells() -> void:
	for i in shell_count:
		var p: Vector3 = _spot(0.5, 0.95)
		if not _valid(p):
			continue
		var it: WorldItem = _item("concha", "Concha", 1, p, _rng.randf() * TAU)
		_mesh(it, _sph(0.09, 6, 3), Color(0.95, 0.78, 0.72), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.0, 0.45, 0.85))
		_mesh(it, _cyl(0.0, 0.05, 0.1, 5), Color(0.9, 0.7, 0.65), Vector3(0, 0.05, 0.08), Vector3(PI / 2.0, 0, 0))

# ------------------------------------------------------------------ pasto

func _spawn_grass() -> void:
	var blade := PrismMesh.new()
	blade.size = Vector3(0.22, 0.55, 0.02)
	blade.material = Wind.make(Color(0.38, 0.65, 0.25), -0.275, 0.55, 0.14, 0.02, 1.7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade
	var transforms: Array[Transform3D] = []
	for i in grass_spots:
		var p: Vector3 = _spot(1.0, 7.0)
		if not _valid(p):
			continue
		var s: float = _rng.randf_range(0.7, 1.5)
		var yaw: float = _rng.randf() * TAU
		for k in 3:
			var b := Basis(Vector3.UP, yaw + k * PI / 3.0).scaled(Vector3(s, s, s))
			var tilt: Basis = Basis(Vector3.RIGHT, _rng.randf_range(-0.2, 0.2))
			transforms.append(Transform3D(b * tilt, p + Vector3(0, 0.25 * s, 0)))
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "Grass"
	add_child(mmi)

## Piedras talladas: pistas de otros náufragos (cambian cada 5 vidas) y las tumbas de tus vidas pasadas.
func _spawn_stelas() -> void:
	var root := Node3D.new()
	root.name = "Stelas"
	add_child(root)
	var block: int = StelaTexts.bloque()
	var rng := RandomNumberGenerator.new()
	rng.seed = block * 7919 + 11
	var msgs: Array = StelaTexts.mensajes(block).duplicate()
	for i in range(msgs.size() - 1, 0, -1):          # barajar con la semilla del bloque
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = msgs[i]
		msgs[i] = msgs[j]
		msgs[j] = tmp
	var placed: Array[Vector3] = []
	var count: int = mini(8, msgs.size())
	for k in count:
		var spot: Vector3 = Vector3(0, -100, 0)
		for attempt in 80:
			var p: Vector3 = terrain.find_spot(rng, 1.3 if k == 0 else 2.0, 2.3 if k == 0 else 7.0)
			if not _valid(p):
				continue
			var ok: bool = true
			for q: Vector3 in placed:
				if Vector2(p.x - q.x, p.z - q.z).length() < 16.0:
					ok = false
					break
			if heart_tree_pos.y > -90.0 and Vector2(p.x - heart_tree_pos.x, p.z - heart_tree_pos.z).length() < 7.0:
				ok = false
			if ok:
				spot = p
				break
		if spot.y < -90.0:
			continue
		placed.append(spot)
		_place_stela(root, str(msgs[k]), false, spot, rng.randi())
	for t in Isla.tumbas:
		var tp: Vector3 = Vector3(float(t["x"]), 0.0, float(t["z"]))
		tp.y = terrain.height_at(tp.x, tp.z)
		_place_stela(root, str(t["texto"]), true, tp, hash(str(t["texto"])))

func _place_stela(root: Node3D, msg: String, tomb: bool, pos: Vector3, sd: int) -> void:
	var s: Stela = Stela.create(msg, tomb, sd)
	var out: Vector2 = Vector2(pos.x, pos.z)
	out = out.normalized() if out.length() > 0.1 else Vector2(0, 1)
	s.position = pos - Vector3(0, 0.08, 0)
	s.rotation.y = atan2(out.x, out.y) + float(absi(sd) % 100) / 100.0 - 0.5
	root.add_child(s)

var _heart_light: OmniLight3D
var _heart_mats: Array[StandardMaterial3D] = []
var heart_tree_pos: Vector3 = Vector3(0, -100, 0)

## Misterio: un árbol retorcido enorme ("árbol corazón") con un círculo de hongos y piedras que brilla de noche.
func _spawn_heart_tree() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 313 + 7
	var c: Vector3 = Vector3(0, -100, 0)
	for k in 60:
		var p: Vector3 = terrain.find_spot(rng, 3.4, 6.0)
		if _valid(p) and Vector2(p.x, p.z).distance_to(Vector2.ZERO) > 8.0 and Vector2(p.x, p.z).distance_to(IslandTerrain.CAVE_CENTER) > 24.0:
			c = p
			break
	if c.y < -90.0 or not NatureKit.exists("TwistedTree_2"):
		return
	heart_tree_pos = c
	var root := Node3D.new()
	root.name = "HeartTree"
	root.position = c
	add_child(root)
	var tree: Node3D = NatureKit.make("TwistedTree_2", Color(0.9, 1.05, 0.9), 260.0)
	tree.scale = Vector3.ONE * 0.55
	tree.rotation.y = rng.randf() * TAU
	root.add_child(tree)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.1
	cyl.height = 4.0
	cs.shape = cyl
	cs.position.y = 2.0
	body.add_child(cs)
	root.add_child(body)
	# círculo de hongos y piedritas alrededor
	var shroom_mat := StandardMaterial3D.new()
	shroom_mat.albedo_color = Color(0.4, 0.9, 0.85)
	shroom_mat.emission_enabled = true
	shroom_mat.emission = Color(0.3, 0.95, 0.85)
	shroom_mat.emission_energy_multiplier = 0.2
	_heart_mats.append(shroom_mat)
	for i in 14:
		var a: float = TAU * float(i) / 14.0 + rng.randf_range(-0.12, 0.12)
		var r: float = rng.randf_range(4.6, 5.4)
		var x: float = c.x + cos(a) * r
		var z: float = c.z + sin(a) * r
		var y: float = terrain.height_at(x, z)
		var model: String = "Mushroom_Laetiporus" if i % 3 == 0 else "Mushroom_Common"
		if not NatureKit.exists(model):
			continue
		var m: Node3D = NatureKit.make(model, Color.WHITE, 90.0)
		m.position = Vector3(x, y - 0.02, z) - c
		m.scale = Vector3.ONE * rng.randf_range(1.2, 1.9)
		m.rotation.y = rng.randf() * TAU
		root.add_child(m)
		# un puntito luminoso sobre cada hongo (brilla de noche)
		var glow := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.07
		sp.height = 0.14
		sp.radial_segments = 6
		sp.rings = 3
		sp.material = shroom_mat
		glow.mesh = sp
		glow.position = m.position + Vector3(0, 0.55 * m.scale.x, 0)
		root.add_child(glow)
	for i in 9:
		var a2: float = rng.randf() * TAU
		var r2: float = rng.randf_range(2.6, 4.2)
		var x2: float = c.x + cos(a2) * r2
		var z2: float = c.z + sin(a2) * r2
		var pb: Node3D = NatureKit.make("Pebble_Round_%d" % rng.randi_range(1, 5), Color.WHITE, 80.0)
		pb.position = Vector3(x2, terrain.height_at(x2, z2), z2) - c
		pb.scale = Vector3.ONE * rng.randf_range(1.0, 2.2)
		root.add_child(pb)
	_heart_light = OmniLight3D.new()
	_heart_light.light_color = Color(0.35, 0.95, 0.85)
	_heart_light.omni_range = 11.0
	_heart_light.light_energy = 0.0
	_heart_light.shadow_enabled = false
	_heart_light.position = Vector3(0, 1.2, 0)
	root.add_child(_heart_light)

func _update_heart(delta: float) -> void:
	if _heart_light == null:
		return
	var dn: Node = get_tree().get_first_node_in_group("daynight")
	var night: float = float(dn.get("night_amount")) if dn != null else 0.0
	var pulse: float = 0.75 + 0.25 * sin(_time * 1.3)
	_heart_light.light_energy = lerpf(_heart_light.light_energy, night * 1.6 * pulse, minf(delta * 2.0, 1.0))
	for m: StandardMaterial3D in _heart_mats:
		m.emission_energy_multiplier = 0.15 + night * 3.0 * pulse

## Cobertura del suelo con el pack de naturaleza (instancias múltiples: miles de plantas baratas).
## [modelo, cantidad, altura mín, altura máx, escala mín, escala máx]
const GROUND_KIT: Array = [
	["Fern_1", 420, 1.6, 8.0, 0.32, 0.6],
	["Grass_Common_Tall", 700, 1.4, 7.0, 0.35, 0.65],
	["Grass_Common_Short", 700, 1.2, 7.0, 0.5, 0.9],
	["Grass_Wispy_Short", 500, 0.9, 3.0, 0.5, 0.9],
	["Flower_3_Group", 130, 1.6, 6.0, 0.22, 0.38],
	["Flower_4_Group", 130, 1.6, 6.0, 0.22, 0.38],
	["Clover_1", 260, 1.5, 6.0, 0.6, 1.0],
	["Plant_1_Big", 70, 2.0, 7.0, 0.28, 0.5],
	["Plant_7_Big", 70, 2.0, 7.0, 0.28, 0.5],
	["Pebble_Round_1", 90, 0.9, 3.0, 0.8, 1.6],
	["Pebble_Square_2", 90, 0.9, 3.5, 0.8, 1.6],
]

func _spawn_kit_ground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + 13
	var root := Node3D.new()
	root.name = "KitGround"
	add_child(root)
	for entry: Array in GROUND_KIT:
		var model: String = entry[0]
		if not NatureKit.exists(model):
			continue
		var xf: Array[Transform3D] = []
		for i in int(entry[1]):
			var p: Vector3 = terrain.find_spot(rng, float(entry[2]), float(entry[3]))
			if not _valid(p):
				continue
			var s: float = rng.randf_range(float(entry[4]), float(entry[5]))
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
			xf.append(Transform3D(b, p - Vector3(0, 0.03, 0)))
		var m: MultiMeshInstance3D = NatureKit.multi(model, xf, 70.0 if xf.size() > 300 else 110.0)
		if m != null:
			root.add_child(m)

# ------------------------------------------------------------------ fauna

func _spawn_wildlife() -> void:
	for i in gull_count:
		var gull := Bird.new()
		gull.kind = Bird.Kind.GULL
		gull.size = 2.4
		gull.body_color = Color(0.9, 0.9, 0.92)
		gull.belly_color = Color.WHITE
		gull.orbit_radius = _rng.randf_range(40.0, 95.0)
		gull.orbit_height = _rng.randf_range(14.0, 30.0)
		gull.orbit_speed = _rng.randf_range(0.12, 0.25) * (1.0 if i % 2 == 0 else -1.0)
		gull.name = "Gull%d" % i
		gull.add_to_group("day_only")
		add_child(gull)
		_critters.append(gull)
	var palettes: Array = [
		[Color(0.25, 0.5, 0.85), Color(0.95, 0.85, 0.4)],
		[Color(0.8, 0.25, 0.2), Color(0.95, 0.9, 0.85)],
		[Color(0.35, 0.65, 0.3), Color(0.9, 0.85, 0.4)],
	]
	for i in songbird_count:
		if terrain.tree_positions.is_empty():
			break
		var idx: int = _rng.randi_range(0, terrain.tree_positions.size() - 1)
		var tp: Vector3 = terrain.tree_positions[idx]
		var ts: float = terrain.tree_scales[idx]
		var bird := Bird.new()
		bird.kind = Bird.Kind.SONGBIRD
		var pal: Array = palettes[i % palettes.size()]
		bird.body_color = pal[0]
		bird.belly_color = pal[1]
		bird.size = 1.0
		bird.perch = tp + Vector3(_rng.randf_range(-0.7, 0.7), 4.9 * ts, _rng.randf_range(-0.7, 0.7))
		bird.name = "Songbird%d" % i
		bird.add_to_group("songbirds")
		add_child(bird)
		_critters.append(bird)
	var wing_colors: Array[Color] = [Color(0.95, 0.6, 0.15), Color(0.95, 0.9, 0.3), Color(0.9, 0.95, 1.0), Color(0.4, 0.6, 0.95)]
	for i in 30:
		var bp: Vector3 = _spot(1.2, 4.5)
		if not _valid(bp):
			continue
		var bf := Butterfly.new()
		bf.terrain = terrain
		bf.home = bp
		bf.wing_color = wing_colors[i % wing_colors.size()]
		bf.name = "Butterfly%d" % i
		bf.add_to_group("day_only")
		add_child(bf)
	for i in crab_count:
		var p: Vector3 = _spot(0.55, 1.3)
		if not _valid(p):
			continue
		var crab := Crab.new()
		crab.terrain = terrain
		crab.position = p
		crab.name = "Crab%d" % i
		crab.add_to_group("crabs")
		add_child(crab)
		_critters.append(crab)
