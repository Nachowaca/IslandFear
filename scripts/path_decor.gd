extends Node3D

## Caminos importantes: los senderos que llevan a la cueva, al estanque y a los claros misteriosos.
## Les da vida: lajas de piedra (escalones donde hay pendiente), follaje en los bordes según el bioma,
## faroles ámbar con halo que se encienden de noche, luciérnagas y algún árbol que cierra la copa.
## Todo es fijo (no cambia con la relación con la isla). Referencia: docs/ref (sendero nocturno de escalones).

const CELL: float = 32.0
const STEP: float = 1.5

var terrain: IslandTerrain

var _rng := RandomNumberGenerator.new()
var _xf: Dictionary = {}                 # "modelo|cx|cz" -> Array[Transform3D]
var _tint: Dictionary = {}               # modelo -> Color
var _lamps: Array[Transform3D] = []
var _halos: Array[Transform3D] = []
var _fly_spots: Array[Vector3] = []
var _mist_spots: Array[Vector3] = []
var _mists: Array[CPUParticles3D] = []
var _bulb_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _flies: Array[CPUParticles3D] = []
var _fly_timer: float = 0.0
var _player: Node3D
var _daynight: Node
var _time: float = 0.0
var _dests: Array[Vector2] = []

# [modelo, peso, escala mín, escala máx, tinte]
var _table: Array = []

func _ready() -> void:
	if terrain == null or terrain.eco == null or terrain.path_lines.is_empty():
		return
	_rng.seed = terrain.noise_seed * 13 + 5
	_table = _make_table()
	_dests = [IslandTerrain.POND_CENTER, IslandTerrain.CAVE_CENTER + IslandTerrain.cave_dir2() * 12.0]
	for c: Vector3 in terrain.eco.mystery_centers:
		_dests.append(Vector2(c.x, c.z))
	for line: Dictionary in terrain.path_lines:
		_decorate(line["pts"])
	_build_instances()
	_build_lamps()
	_build_flies()
	_build_mist()
	_player = get_tree().get_first_node_in_group("player") as Node3D

func _make_table() -> Array:
	var warm: Color = Color(1.05, 0.98, 0.8)
	var dry: Color = Color(1.25, 1.05, 0.7)
	var grey: Color = Color(0.85, 0.88, 0.9)
	var t: Array = []
	# 0 costa
	t.append([["Pebble_Round_1", 1.5, 0.9, 1.5, grey], ["Pebble_Round_3", 1.0, 0.9, 1.5, grey], ["Grass_Wispy_Short", 1.5, 0.5, 0.9, warm], ["Clover_2", 1.0, 0.8, 1.3, Color.WHITE], ["Plant_1", 0.4, 0.5, 0.8, Color.WHITE]])
	# 1 roquedal
	t.append([["Rock_Medium_1", 1.2, 0.3, 0.6, grey], ["Rock_Medium_2", 1.0, 0.3, 0.6, grey], ["Pebble_Round_2", 2.0, 0.9, 1.6, grey], ["Pebble_Square_2", 1.5, 0.9, 1.6, grey], ["Plant_7", 0.6, 0.5, 0.9, Color.WHITE], ["Fern_1", 0.8, 0.6, 1.0, Color.WHITE]])
	# 2 selva
	t.append([["Fern_1", 3.0, 0.7, 1.2, Color(0.8, 1.0, 0.8)], ["Plant_1_Big", 1.0, 0.5, 0.9, Color.WHITE], ["Plant_7_Big", 1.0, 0.5, 0.9, Color.WHITE], ["UQ:Bush_Small", 1.4, 0.8, 1.3, Color(0.8, 1.0, 0.8)], ["Flower_3_Group", 0.7, 0.8, 1.2, Color.WHITE], ["Clover_1", 1.0, 0.8, 1.2, Color.WHITE]])
	# 3 bosque
	t.append([["Fern_1", 2.0, 0.6, 1.1, Color.WHITE], ["Bush_Common", 1.0, 0.5, 0.9, Color.WHITE], ["Mushroom_Common", 0.5, 0.8, 1.4, Color.WHITE], ["UQ:Flower_2_Clump", 1.0, 0.8, 1.2, Color.WHITE], ["Clover_1", 1.0, 0.8, 1.2, Color.WHITE], ["Flower_4_Group", 0.6, 0.8, 1.2, Color.WHITE]])
	# 4 matorral
	t.append([["Bush_Common_Flowers", 1.2, 0.5, 0.9, warm], ["Grass_Wispy_Tall", 2.0, 0.5, 0.9, warm], ["UQ:Flower_5_Clump", 1.0, 0.8, 1.2, Color.WHITE], ["Plant_7", 0.6, 0.5, 0.9, Color.WHITE]])
	# 5 árido
	t.append([["Rock_Medium_3", 1.0, 0.25, 0.5, dry], ["Pebble_Square_1", 2.0, 0.9, 1.6, dry], ["Pebble_Square_4", 1.5, 0.9, 1.6, dry], ["Grass_Wispy_Short", 1.2, 0.5, 0.9, dry], ["UQ:Bush_Small", 0.8, 0.6, 1.0, dry]])
	for biome: Array in t:
		for e: Array in biome:
			_tint[e[0]] = e[4]
	return t

func _pick_biome(pos: Vector3) -> int:
	var w: PackedFloat32Array = terrain.eco.get_bioma_pesos(pos)
	var tot: float = 0.0
	for k in 6:
		tot += w[k]
	if tot <= 0.001:
		return 3
	var r: float = _rng.randf() * tot
	for k in 6:
		r -= w[k]
		if r <= 0.0:
			return k
	return 3

func _pick_plant(biome: int) -> Array:
	var list: Array = _table[biome]
	var tot: float = 0.0
	for e: Array in list:
		tot += float(e[1])
	var r: float = _rng.randf() * tot
	for e: Array in list:
		r -= float(e[1])
		if r <= 0.0:
			return e
	return list[0]

func _ok_ground(x: float, z: float) -> bool:
	var y: float = terrain.height_at(x, z)
	return y > 1.2 and y < 14.0 and not terrain.is_in_pond_area(x, z, 1.15) and not terrain.is_in_cave_area(x, z, 1.0)

func _near_dest(p: Vector2) -> float:
	var best: float = 1.0e9
	for d: Vector2 in _dests:
		best = minf(best, p.distance_to(d))
	return best

func _add(model: String, pos: Vector3, yaw: float, sc: float, squash: float = 1.0) -> void:
	if not NatureKit.exists(model):
		return
	var b: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * squash, sc))
	var key: String = "%s|%d|%d" % [model, floori(pos.x / CELL), floori(pos.z / CELL)]
	if not _xf.has(key):
		_xf[key] = [] as Array[Transform3D]
	(_xf[key] as Array[Transform3D]).append(Transform3D(b, pos))

## Resamplea el camino cada STEP metros y reparte piedras, follaje, faroles y luciérnagas.
func _decorate(pts: PackedVector2Array) -> void:
	if pts.size() < 3:
		return
	var samples: Array[Vector2] = []
	samples.append(pts[0])
	for i in range(1, pts.size()):
		var a: Vector2 = samples[samples.size() - 1]
		var seg: Vector2 = pts[i] - a
		var l: float = seg.length()
		while l >= STEP:
			a += seg.normalized() * STEP
			samples.append(a)
			seg = pts[i] - a
			l = seg.length()
	var stones: Array[String] = ["RockPath_Round_Small_1", "RockPath_Round_Small_2", "RockPath_Round_Small_3", "RockPath_Square_Small_1", "RockPath_Square_Small_2", "RockPath_Square_Small_3", "RockPath_Round_Thin", "RockPath_Square_Thin", "RockPath_Round_Wide", "RockPath_Square_Wide"]
	for s in stones:
		_tint[s] = Color(1.15, 1.0, 0.88)
	var lamp_acc: float = _rng.randf() * 8.0
	var fly_acc: float = _rng.randf() * 12.0
	var mist_acc: float = _rng.randf() * 10.0
	var tree_acc: float = _rng.randf() * 10.0
	var side_flip: float = 1.0
	for i in range(1, samples.size() - 1):
		var p: Vector2 = samples[i]
		var tan2: Vector2 = (samples[i + 1] - samples[i - 1]).normalized()
		var nrm: Vector2 = Vector2(-tan2.y, tan2.x)
		var yaw: float = atan2(tan2.x, tan2.y)
		var y: float = terrain.height_at(p.x, p.y)
		if y < 1.25 or terrain.is_in_pond_area(p.x, p.y, 1.1) or terrain.is_in_cave_area(p.x, p.y, 1.0):
			continue
		var y2: float = terrain.height_at(samples[i + 1].x, samples[i + 1].y)
		var y0: float = terrain.height_at(samples[i - 1].x, samples[i - 1].y)
		var slope: float = absf(y2 - y0) / (STEP * 2.0)
		var dd: float = _near_dest(p)
		var pos3: Vector3 = Vector3(p.x, y, p.y)
		var biome: int = _pick_biome(pos3)
		# --- piedras: escalones en pendiente, laja suelta cerca de los destinos y en roca/árido
		var stone_p: float = 0.0
		if slope > 0.2:
			stone_p = 0.95
		elif dd < 28.0:
			stone_p = 0.45
		elif biome == 1 or biome == 5:
			stone_p = 0.12
		else:
			stone_p = 0.05
		if _rng.randf() < stone_p:
			var nm: String = stones[_rng.randi() % stones.size()]
			var off: Vector2 = nrm * _rng.randf_range(-0.35, 0.35)
			var sc: float = _rng.randf_range(1.0, 1.5)
			_add(nm, Vector3(p.x + off.x, y - 0.03, p.y + off.y), yaw + _rng.randf_range(-0.2, 0.2), sc)
			if slope > 0.2:                      # escalón real: segunda laja a un costado, a la misma altura
				var nm2: String = stones[_rng.randi() % stones.size()]
				var off2: Vector2 = nrm * _rng.randf_range(-0.9, 0.9) + tan2 * 0.5
				_add(nm2, Vector3(p.x + off2.x, terrain.height_at(p.x + off2.x, p.y + off2.y) - 0.03, p.y + off2.y), yaw + _rng.randf_range(-0.25, 0.25), _rng.randf_range(1.0, 1.4))
		# --- follaje a los costados (más denso cerca de los destinos)
		var dens: float = 2.3 if dd < 30.0 else 1.5
		if biome == 2:
			dens *= 1.3
		elif biome == 5 or biome == 0:
			dens *= 0.6
		for side in 2:
			var sgn: float = -1.0 if side == 0 else 1.0
			var n_plants: int = int(floor(dens)) + (1 if _rng.randf() < dens - floor(dens) else 0)
			for k in n_plants:
				var lat: float = _rng.randf_range(1.2, 3.4) * sgn
				var lon: float = _rng.randf_range(-STEP * 0.5, STEP * 0.5)
				var q: Vector2 = p + nrm * lat + tan2 * lon
				if not _ok_ground(q.x, q.y) or terrain.is_on_path(q.x, q.y, 0.45):
					continue
				var e: Array = _pick_plant(biome)
				var sc2: float = _rng.randf_range(float(e[2]), float(e[3]))
				_add(String(e[0]), Vector3(q.x, terrain.height_at(q.x, q.y) - 0.02, q.y), _rng.randf() * TAU, sc2)
		# --- faroles ámbar: cada ~12 m, cada ~6 m cerca de los destinos
		lamp_acc -= STEP
		if lamp_acc <= 0.0:
			lamp_acc = (6.0 if dd < 30.0 else 12.0) + _rng.randf_range(0.0, 3.0)
			side_flip = -side_flip
			var lq: Vector2 = p + nrm * side_flip * _rng.randf_range(1.5, 2.4)
			if _ok_ground(lq.x, lq.y):
				var ly: float = terrain.height_at(lq.x, lq.y)
				var h: float = _rng.randf_range(0.35, 0.8)
				_lamps.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(1, h / 0.5, 1)), Vector3(lq.x, ly + h * 0.5 - 0.05, lq.y)))
				_halos.append(Transform3D(Basis.IDENTITY, Vector3(lq.x, ly + h, lq.y)))
		# --- puntos para luciérnagas
		fly_acc -= STEP
		if fly_acc <= 0.0:
			fly_acc = 20.0 + _rng.randf_range(0.0, 8.0)
			_fly_spots.append(Vector3(p.x, y + 1.3, p.y))
		# --- bruma baja a ras del suelo
		mist_acc -= STEP
		if mist_acc <= 0.0:
			mist_acc = 14.0 + _rng.randf_range(0.0, 8.0)
			_mist_spots.append(Vector3(p.x, y + 0.25, p.y))
		# --- algún árbol que cierra la copa (selva y bosque)
		tree_acc -= STEP
		if tree_acc <= 0.0:
			tree_acc = 14.0 + _rng.randf_range(0.0, 10.0)
			if biome == 2 or biome == 3:
				var tq: Vector2 = p + nrm * _rng.randf_range(3.6, 6.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
				if _ok_ground(tq.x, tq.y) and not terrain.is_on_path(tq.x, tq.y, 0.2):
					_add_tree(Vector3(tq.x, terrain.height_at(tq.x, tq.y), tq.y))

func _add_tree(pos: Vector3) -> void:
	var nm: String = "CommonTree_%d" % _rng.randi_range(1, 5) if _rng.randf() < 0.6 else "TwistedTree_%d" % _rng.randi_range(1, 5)
	if not NatureKit.exists(nm):
		return
	var t: Node3D = NatureKit.make(nm, Color.WHITE, 160.0)
	t.position = pos
	t.rotation.y = _rng.randf() * TAU
	t.scale = Vector3.ONE * _rng.randf_range(1.0, 1.4)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.35
	sh.height = 4.0
	cs.shape = sh
	cs.position = Vector3(0, 2.0, 0)
	body.add_child(cs)
	t.add_child(body)
	add_child(t)

func _build_instances() -> void:
	var root := Node3D.new()
	root.name = "Follaje"
	add_child(root)
	for key: String in _xf.keys():
		var model: String = key.split("|")[0]
		var arr: Array[Transform3D] = _xf[key]
		var mmi: MultiMeshInstance3D = NatureKit.multi(model, arr, 80.0, _tint.get(model, Color.WHITE), false)
		if mmi != null:
			if model.begins_with("RockPath"):
				_warm_stone(mmi)
			if model.begins_with("RockPath") or model.begins_with("Rock_"):
				NatureKit.add_box_colliders(mmi)
			root.add_child(mmi)

func _radial(edge: float) -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
	g.offsets = PackedFloat32Array([0.0, edge, 1.0])
	gt.gradient = g
	return gt

func _build_lamps() -> void:
	if _lamps.is_empty():
		return
	var root := Node3D.new()
	root.name = "Faroles"
	add_child(root)
	# poste fino + bulbo ámbar
	var stem := CylinderMesh.new()
	stem.top_radius = 0.012
	stem.bottom_radius = 0.02
	stem.height = 0.5
	stem.radial_segments = 5
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.2, 0.14, 0.09)
	stem_mat.roughness = 1.0
	stem.material = stem_mat
	root.add_child(_multi_of(stem, _lamps))
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.albedo_color = Color(1.0, 0.75, 0.35)
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = Color(1.0, 0.62, 0.2)
	_bulb_mat.emission_energy_multiplier = 0.4
	var bulb := SphereMesh.new()
	bulb.radius = 0.07
	bulb.height = 0.14
	bulb.radial_segments = 8
	bulb.rings = 4
	bulb.material = _bulb_mat
	var bulbs: Array[Transform3D] = []
	for h: Transform3D in _halos:
		bulbs.append(h)
	root.add_child(_multi_of(bulb, bulbs))
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.albedo_texture = _radial(0.25)
	_halo_mat.albedo_color = Color(1.0, 0.62, 0.22, 0.0)
	_halo_mat.disable_receive_shadows = true
	_halo_mat.no_depth_test = false
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	quad.material = _halo_mat
	root.add_child(_multi_of(quad, bulbs))

func _multi_of(mesh: Mesh, xf: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _build_flies() -> void:
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.albedo_texture = _radial(0.2)
	fmat.vertex_color_use_as_albedo = true
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	q.material = fmat
	var root := Node3D.new()
	root.name = "Luciernagas"
	add_child(root)
	for sp: Vector3 in _fly_spots:
		var pr := CPUParticles3D.new()
		pr.mesh = q
		pr.amount = 9
		pr.lifetime = 5.0
		pr.preprocess = 3.0
		pr.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		pr.emission_sphere_radius = 3.2
		pr.direction = Vector3.UP
		pr.spread = 180.0
		pr.gravity = Vector3.ZERO
		pr.initial_velocity_min = 0.08
		pr.initial_velocity_max = 0.35
		pr.color = Color(1.0, 0.82, 0.35)
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([Color(1, 0.8, 0.3, 0.0), Color(1, 0.85, 0.4, 1.0), Color(1, 0.8, 0.3, 0.0)])
		ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		pr.color_ramp = ramp
		pr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pr.emitting = false
		pr.position = sp
		root.add_child(pr)
		_flies.append(pr)

## Bruma baja: jirones suaves de niebla a ras del suelo a lo largo de los senderos.
func _build_mist() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = _radial(0.1)
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(4.0, 1.6)
	q.material = mat
	var root := Node3D.new()
	root.name = "Bruma"
	add_child(root)
	for sp: Vector3 in _mist_spots:
		var pr := CPUParticles3D.new()
		pr.mesh = q
		pr.amount = 5
		pr.lifetime = 9.0
		pr.preprocess = 9.0
		pr.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		pr.emission_sphere_radius = 2.6
		pr.direction = Vector3(1, 0, 0)
		pr.spread = 180.0
		pr.gravity = Vector3.ZERO
		pr.initial_velocity_min = 0.03
		pr.initial_velocity_max = 0.15
		pr.color = Color(0.85, 0.9, 0.95)
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0.0)])
		ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		pr.color_ramp = ramp
		pr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pr.emitting = false
		pr.position = sp
		root.add_child(pr)
		_mists.append(pr)

func _process(delta: float) -> void:
	_time += delta
	if _bulb_mat == null and _flies.is_empty():
		return
	if _daynight == null:
		_daynight = get_tree().get_first_node_in_group("daynight")
	var night: float = float(_daynight.get("night_amount")) if _daynight != null else 0.0
	var pulse: float = 0.85 + 0.15 * sin(_time * 1.7)
	if _bulb_mat != null:
		_bulb_mat.emission_energy_multiplier = 0.3 + night * 3.5 * pulse
	if _halo_mat != null:
		_halo_mat.albedo_color = Color(1.0, 0.62, 0.22, night * 0.55 * pulse)
	_fly_timer -= delta
	if _fly_timer <= 0.0:
		_fly_timer = 0.7
		if _player == null:
			_player = get_tree().get_first_node_in_group("player") as Node3D
		for pr: CPUParticles3D in _flies:
			var near: bool = _player != null and pr.global_position.distance_to(_player.global_position) < 70.0
			pr.emitting = near and night > 0.45
		for ms: CPUParticles3D in _mists:
			ms.emitting = _player != null and ms.global_position.distance_to(_player.global_position) < 60.0

## Las lajas del pack vienen azuladas: se les da un tono de piedra cálida con musgo.
func _warm_stone(mmi: MultiMeshInstance3D) -> void:
	var mesh: Mesh = mmi.multimesh.mesh
	for i in mesh.get_surface_count():
		var m: Material = mesh.surface_get_material(i)
		if m is BaseMaterial3D:
			var d: BaseMaterial3D = m.duplicate() as BaseMaterial3D
			d.albedo_color = Color(1.55, 1.2, 0.85)
			mesh.surface_set_material(i, d)
