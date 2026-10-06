class_name IslandTerrain
extends MeshInstance3D

## Isla grande low-poly con relieve: playa ancha de arena, llanura de pasto, colinas, acantilados en el oeste,
## una laguna y una meseta plana para la cueva (ver island_features.gd).
## Radio 120 m (4 veces el área de la versión anterior). El aspecto lo da terrain_island.gdshader.
@export var radius: float = 120.0:
	set(v):
		radius = v
		_build()
@export var hill_height: float = 9.0:
	set(v):
		hill_height = v
		_build()
@export var noise_seed: int = 7:
	set(v):
		noise_seed = v
		_build()
@export var palm_count: int = 150
@export var tree_count: int = 360
@export var bush_count: int = 600
@export var rock_count: int = 170

const RES := 240
const SAND := Color(0.88, 0.8, 0.56)
const BEACH_W := 0.17          ## ancho de la playa (fracción del radio)
const CLIFF_DIR := Vector2(-1.0, 0.35)   ## hacia dónde están los acantilados (oeste)
const TERRAIN_SHADER: Shader = preload("res://shaders/terrain_island.gdshader")

## Laguna de agua dulce tierra adentro
const POND_CENTER := Vector2(-32.0, 28.0)
const POND_RADIUS := 9.0
const POND_DEPTH := 3.2

## Meseta de la cueva (el suelo se aplana a la altura natural del centro)
const CAVE_CENTER := Vector2(48.0, -40.0)
const CAVE_PLATEAU_R := 16.0
const PIT_R := 5.5              ## radio del pozo (la "cueva" es un agujero en el terreno)
const PIT_DEPTH := 8.0          ## profundidad del pozo (m)
const RAMP_HALF_W := 1.8        ## semiancho de la rampa de bajada
const RAMP_LEN := 18.0          ## largo de la rampa más allá del borde

## Dirección (plano XZ) desde el pozo hacia donde baja la rampa: hacia el centro de la isla.
static func cave_dir2() -> Vector2:
	return (-CAVE_CENTER).normalized()

## Metros que se excavan en (x, z): pozo circular de paredes empinadas + rampa en trinchera.
func _pit_carve(x: float, z: float) -> float:
	var pc: Vector2 = Vector2(x, z) - CAVE_CENTER
	var r: float = pc.length()
	if r > PIT_R + RAMP_LEN + 3.0:
		return 0.0
	var c: float = PIT_DEPTH * (1.0 - smoothstep(PIT_R - 2.0, PIT_R, r))
	var d: Vector2 = cave_dir2()
	var along: float = pc.dot(d)
	var across: float = absf(pc.dot(Vector2(-d.y, d.x)))
	if along > 0.0 and along < PIT_R + RAMP_LEN:
		var t0: float = PIT_R * 0.4
		var k: float = clampf((along - t0) / (PIT_R + RAMP_LEN - t0), 0.0, 1.0)
		var side: float = 1.0 - smoothstep(RAMP_HALF_W, RAMP_HALF_W + 1.2, across)
		c = maxf(c, PIT_DEPTH * (1.0 - k) * side)
	return c

var _noise := FastNoiseLite.new()
var _flora: Node3D
var eco: EcoMap                         ## mapa ecológico (biomas, humedad, suelo); lo crea la propia isla
var _noise_ready: bool = false
var _mood: float = 0.0
var _mood_timer: float = 0.0

var pond_water_level: float = 2.0
var cave_floor_y: float = 3.0
var tree_positions: Array[Vector3] = []
var tree_scales: Array[float] = []
var palm_positions: Array[Vector3] = []
var tree_nodes: Array[Node3D] = []     ## árboles y palmeras como nodos (para talarlos de a uno)
var palm_nodes: Array[Node3D] = []

func _ready() -> void:
	_build()

## El pasto se ve más vivo o más seco según cómo está la isla contigo (sin mostrarlo como número).
func _process(delta: float) -> void:
	_mood_timer += delta
	if _mood_timer < 0.5 or material_override == null:
		return
	_mood_timer = 0.0
	var target: float = clampf(Isla.vinculo / 60.0, -1.0, 1.0)
	_mood = lerpf(_mood, target, 0.05)
	(material_override as ShaderMaterial).set_shader_parameter("mood", _mood)

func _setup_noise() -> void:
	_noise.seed = noise_seed
	_noise.frequency = 1.5 / radius
	_noise_ready = true
	cave_floor_y = maxf(_base_height(CAVE_CENTER.x, CAVE_CENTER.y), PIT_DEPTH + 1.3)   # el pozo queda sobre el nivel del mar: la zona es un montículo

## Altura del terreno en (x, z) — pública para el jugador, la barca y el resto del juego.
func height_at(x: float, z: float) -> float:
	if not _noise_ready:
		_setup_noise()
	return _height(x, z)

func is_in_pond_area(x: float, z: float, margin: float = 1.0) -> bool:
	return Vector2(x, z).distance_to(POND_CENTER) < POND_RADIUS * 1.6 * margin

func is_in_cave_area(x: float, z: float, margin: float = 1.0) -> bool:
	return Vector2(x, z).distance_to(CAVE_CENTER) < CAVE_PLATEAU_R * 1.2 * margin

func _height(x: float, z: float) -> float:
	var h: float = _base_height(x, z)
	var dp: float = Vector2(x, z).distance_to(POND_CENTER) / (POND_RADIUS * 1.6)
	if dp < 1.0:
		var k: float = 1.0 - smoothstep(0.0, 1.0, dp)
		h -= POND_DEPTH * k
	var dc: float = Vector2(x, z).distance_to(CAVE_CENTER) / CAVE_PLATEAU_R
	if dc < 1.0:
		var kc: float = 1.0 - smoothstep(0.45, 1.0, dc)
		h = lerpf(h, cave_floor_y, kc)
	h -= _pit_carve(x, z)
	return h

## 0..1: cuánto de acantilado hay en esa dirección (sector oeste con borde irregular).
func _cliff_mask(x: float, z: float) -> float:
	var v := Vector2(x, z)
	if v.length() < 1.0:
		return 0.0
	var c: float = v.normalized().dot(CLIFF_DIR.normalized()) + _noise.get_noise_2d(x * 0.5 + 400.0, z * 0.5) * 0.12
	return smoothstep(0.5, 0.88, c)

func _base_height(x: float, z: float) -> float:
	var d: float = 1.0 - Vector2(x, z).length() / radius
	d += _noise.get_noise_2d(x, z) * 0.28
	if d < 0.0:
		return maxf(-1.5 + d * 6.0, -4.0)   # fondo marino
	var m: float = _cliff_mask(x, z)
	var bw: float = lerpf(BEACH_W, 0.06, m)   # playa ancha; en los acantilados se acorta
	if d < bw:
		return lerpf(-1.5, 0.9, d / bw)       # playa: sube sobre el agua
	var inland: float = d - bw
	var hills: float = (_noise.get_noise_2d(x * 1.6 + 50.0, z * 1.6) * 0.5 + 0.5) * hill_height
	var h: float = 0.9 + minf(inland * 5.0, 1.0) * (0.3 + hills * minf(inland * 3.0, 1.0))
	if m > 0.0:
		# meseta alta con pared casi vertical sobre la playa, y terrazas
		var wall: float = smoothstep(0.0, 0.035, inland)
		var fade: float = 1.0 - smoothstep(0.3, 0.58, inland)
		var terr: float = 8.0 + _noise.get_noise_2d(x * 3.0 - 200.0, z * 3.0 + 90.0) * 3.5 + _noise.get_noise_2d(x * 0.9, z * 0.9 + 33.0) * 2.0
		h += terr * m * wall * fade
	return h

## Categoría del suelo pintada en el color del vértice (alfa): 1 normal, 0.6 cueva, 0.3 fondo de laguna.
func _category(h: float, xz: Vector2) -> float:
	if xz.distance_to(CAVE_CENTER) < PIT_R + 4.0 and h < cave_floor_y + 0.6:
		return 0.6
	if xz.distance_to(POND_CENTER) < POND_RADIUS * 1.6 and h < pond_water_level + 0.25:
		return 0.3
	return 1.0

func _build() -> void:
	if not is_inside_tree():
		return
	_setup_noise()
	# nivel del agua de la laguna: un poco bajo el borde más bajo del anillo exterior
	var lowest: float = 1000.0
	for i in 16:
		var ang: float = TAU * i / 16.0
		var rp: Vector2 = POND_CENTER + Vector2(cos(ang), sin(ang)) * POND_RADIUS * 1.5
		lowest = minf(lowest, _height(rp.x, rp.y))
	pond_water_level = lowest - 0.1
	var half: float = radius * 1.35
	var step: float = half * 2.0 / RES
	# alturas de la grilla (una sola vez)
	var hg: PackedFloat32Array = PackedFloat32Array()
	hg.resize((RES + 1) * (RES + 1))
	for j in RES + 1:
		for i in RES + 1:
			hg[j * (RES + 1) + i] = _height(-half + i * step, -half + j * step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RES:
		for j in RES:
			var x0: float = -half + i * step
			var z0: float = -half + j * step
			var p: Array[Vector3] = [
				Vector3(x0, hg[j * (RES + 1) + i], z0),
				Vector3(x0 + step, hg[j * (RES + 1) + i + 1], z0),
				Vector3(x0, hg[(j + 1) * (RES + 1) + i], z0 + step),
				Vector3(x0 + step, hg[(j + 1) * (RES + 1) + i + 1], z0 + step)]
			# alterna la diagonal para que las facetas no formen un patrón
			var tris: Array = [[0, 1, 2], [1, 3, 2]] if (i + j) % 2 == 0 else [[0, 1, 3], [0, 3, 2]]
			for tri: Array in tris:
				var a: Vector3 = p[tri[0]]
				var b: Vector3 = p[tri[1]]
				var c: Vector3 = p[tri[2]]
				var cen: Vector3 = (a + b + c) / 3.0
				# tinte suave por triángulo (rompe lo plano) y categoría en el alfa
				var jit: float = _noise.get_noise_2d(cen.x * 4.3 + 91.0, cen.z * 4.3 - 40.0)
				var tone: float = 1.0 + jit * 0.13
				st.set_color(Color(tone, tone, tone, _category(cen.y, Vector2(cen.x, cen.z))))
				st.add_vertex(a)
				st.add_vertex(b)
				st.add_vertex(c)
	st.generate_normals()
	mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	for layer: String in ["sand", "grass", "forest", "rock"]:
		mat.set_shader_parameter(layer + "_c", load("res://assets/terrain/%s_c.jpg" % layer))
		mat.set_shader_parameter(layer + "_n", load("res://assets/terrain/%s_n.jpg" % layer))
	mat.set_shader_parameter("water_y", 0.35)
	material_override = mat
	layers = 1 | (1 << 19)         # la capa 20 recibe las huellas (decals)
	_scatter_flora()
	if not Engine.is_editor_hint():
		_build_terrain_collision()
		_feed_water_shader(half)
		_spawn_life()

## Le pasa al agua un mapa de alturas del terreno para la espuma y la transparencia en la orilla.
func _feed_water_shader(half: float) -> void:
	var water: MeshInstance3D = get_tree().get_first_node_in_group("water_surface") as MeshInstance3D
	if water == null:
		return
	var size: int = 320
	var img := Image.create(size, size, false, Image.FORMAT_RF)
	for j in size:
		for i in size:
			var x: float = -half + (float(i) + 0.5) / size * half * 2.0
			var z: float = -half + (float(j) + 0.5) / size * half * 2.0
			img.set_pixel(i, j, Color(_height(x, z), 0, 0, 1))
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var mat: ShaderMaterial = water.mesh.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("height_tex", tex)
	mat.set_shader_parameter("height_origin", Vector2(-half, -half))
	mat.set_shader_parameter("height_size", half * 2.0)
	mat.set_shader_parameter("water_y", water.global_position.y)

## Puebla la isla con recursos, hongos, agua y fauna (ver island_life.gd).
func _spawn_life() -> void:
	var old: Node = get_node_or_null("Life")
	if old:
		old.free()
	var life := IslandLife.new()
	life.name = "Life"
	life.terrain = self
	life.seed_value = noise_seed
	add_child(life)

## Tala un árbol o palmera: lo saca del registro, quita su colisión y lo hace caer. Devuelve su posición.
func fell_tree(tree: Node3D, dir: Vector3) -> Vector3:
	var pos: Vector3 = tree.global_position
	var idx: int = tree_nodes.find(tree)
	if idx >= 0:
		tree_nodes.remove_at(idx)
		if idx < tree_positions.size():
			tree_positions.remove_at(idx)
		if idx < tree_scales.size():
			tree_scales.remove_at(idx)
	var pidx: int = palm_nodes.find(tree)
	if pidx >= 0:
		palm_nodes.remove_at(pidx)
		if pidx < palm_positions.size():
			palm_positions.remove_at(pidx)
	for c: Node in tree.get_children():
		if c is StaticBody3D:
			c.queue_free()
	var axis: Vector3 = Vector3.UP.cross(dir.normalized())
	if axis.length() < 0.01:
		axis = Vector3.RIGHT
	axis = axis.normalized()
	var start: Basis = tree.basis
	var tw: Tween = tree.create_tween()
	tw.tween_method(func(a: float) -> void: tree.basis = Basis(axis, a) * start, 0.0, PI * 0.5, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.4)
	tw.tween_callback(tree.queue_free)
	return pos

## Quita árboles, arbustos y rocas de un círculo (para despejar un lugar especial).
func clear_area(center: Vector2, r: float) -> void:
	if _flora == null:
		return
	for c: Node in _flora.get_children():
		var n3: Node3D = c as Node3D
		if n3 == null:
			continue
		if Vector2(n3.global_position.x, n3.global_position.z).distance_to(center) < r:
			var ti: int = tree_nodes.find(n3)
			if ti >= 0:
				tree_nodes.remove_at(ti)
				tree_positions.remove_at(ti)
				tree_scales.remove_at(ti)
			var pi: int = palm_nodes.find(n3)
			if pi >= 0:
				palm_nodes.remove_at(pi)
				palm_positions.remove_at(pi)
			n3.queue_free()

## Busca un punto con altura entre min_h y max_h (fuera de la laguna y la meseta); y=-100 si falla.
func find_spot(rng: RandomNumberGenerator, min_h: float, max_h: float) -> Vector3:
	return _random_spot(rng, min_h, max_h)

## Colisión exacta del terreno (malla triangular).
func _build_terrain_collision() -> void:
	var old: Node = get_node_or_null("TerrainBody")
	if old:
		old.free()
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)

## Cuerpo estático con un cilindro (troncos) o esfera (rocas) como colisión.
func _add_solid(parent: Node3D, shape: Shape3D, local_pos: Vector3) -> void:
	if Engine.is_editor_hint():
		return
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = local_pos
	body.add_child(cs)
	parent.add_child(body)

func _make_mesh_sphere(r: float, h: float, seg: int, rings: int, mat: Material) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = rings
	m.material = mat
	return m

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

func _scatter_flora() -> void:
	if _flora and is_instance_valid(_flora):
		_flora.free()
	_flora = Node3D.new()
	_flora.name = "Flora"
	add_child(_flora)
	if eco == null or not is_instance_valid(eco):     # el mapa ecológico decide qué crece dónde (bioma)
		eco = EcoMap.new()
		eco.name = "EcoMap"
		eco.terrain = self
		add_child(eco)                                 # su _ready() calcula las capas
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	tree_positions.clear()
	tree_scales.clear()
	palm_positions.clear()
	tree_nodes.clear()
	palm_nodes.clear()
	var vine := CylinderMesh.new()
	vine.top_radius = 0.03
	vine.bottom_radius = 0.02
	vine.height = 2.3
	vine.radial_segments = 4
	vine.material = _mat(Color(0.22, 0.42, 0.16))

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.3
	trunk.height = 2.4
	trunk.radial_segments = 6
	trunk.material = _mat(Color(0.4, 0.27, 0.15))

	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.35
	trunk_shape.height = 3.0
	var trunk_shape_palm := CylinderShape3D.new()
	trunk_shape_palm.radius = 0.25
	trunk_shape_palm.height = 3.0

	# ---- ecología: zonas reales de una costa (playa/duna -> matorral costero -> bosque -> altura),
	# humedad cerca de la laguna y claros por manchas de bosque. En la arena casi no hay árboles
	# (la sal y el viento los matan): solo pocos troncos secos sin hojas.
	var dead_target: int = int(palm_count * 0.22)
	var made: int = 0
	var tries: int = 0
	while made < dead_target and tries < dead_target * 14:
		tries += 1
		var dpos: Vector3 = _random_spot(rng, 1.05, 1.7)
		if dpos.y < -90.0 or _cliff_mask(dpos.x, dpos.z) > 0.2:
			continue
		if forest_value(dpos.x, dpos.z) < 0.05 and rng.randf() < 0.7:
			continue   # se agrupan en las zonas más arboladas
		_add_tree(rng, dpos, "DeadTree_%d" % rng.randi_range(1, 10), rng.randf_range(0.7, 1.1), Color.WHITE, trunk_shape, vine, true)
		made += 1
	# árboles de costa con hojas (mecánica de "palmera"): solo detrás de la playa
	var palm_target: int = int(palm_count * 0.3)
	made = 0
	tries = 0
	while made < palm_target and tries < palm_target * 14:
		tries += 1
		var pos: Vector3 = _random_spot(rng, 1.3, 3.2)
		if pos.y < -90.0 or _cliff_mask(pos.x, pos.z) > 0.25:
			continue
		if rng.randf() > smoothstep(-0.3, 0.2, forest_value(pos.x, pos.z)) + 0.15:
			continue
		var palm := Node3D.new()
		palm.position = pos
		palm.rotation.y = rng.randf() * TAU
		palm.scale = Vector3.ONE * rng.randf_range(1.0, 1.5)
		var coast_visual: Node3D = NatureKit.make_uq("PalmTree_%d" % rng.randi_range(1, 5), Color(rng.randf_range(0.9, 1.1), rng.randf_range(1.0, 1.1), rng.randf_range(0.85, 1.0)), 180.0)
		coast_visual.rotation.x = rng.randf_range(0.04, 0.14)   # el viento del mar los inclina
		palm.add_child(coast_visual)
		_flora.add_child(palm)
		_add_solid(palm, trunk_shape_palm, Vector3(0.1, 1.5, 0))
		palm.set_meta("hojas", 4)
		palm_nodes.append(palm)
		palm_positions.append(pos)
		made += 1
	# bosque: densidad por manchas (claros y arboledas), más denso donde hay humedad, ralo y de coníferas en altura
	made = 0
	tries = 0
	while made < tree_count and tries < tree_count * 6:
		tries += 1
		var pos2: Vector3 = _random_spot(rng, 1.75, 13.0)
		if pos2.y < -90.0:
			continue
		var wet: float = moisture_at(pos2.x, pos2.z)
		var bw: PackedFloat32Array = eco.get_bioma_pesos(pos2)
		var dens: float = bw[2] * 1.0 + bw[3] * 0.75 + bw[4] * 0.2 + bw[5] * 0.05 + bw[1] * 0.08 + bw[0] * 0.05
		var p_tree: float = maxf(dens * (0.65 + 0.7 * smoothstep(-0.3, 0.3, forest_value(pos2.x, pos2.z))), wet * 0.8)
		if pos2.y < 2.6:
			p_tree *= clampf((pos2.y - 1.75) / 0.85, 0.0, 1.0)      # se aclara hacia la costa
		if pos2.y > 7.0:
			p_tree *= 0.45                                            # altura expuesta al viento: poco árbol
		if _cliff_mask(pos2.x, pos2.z) > 0.3 and pos2.y < 3.5:
			p_tree = 0.0                                              # al pie del acantilado solo hay derrumbe
		p_tree *= 1.0 - 0.9 * eco.get_misterio(pos2)          # los claros misteriosos casi no tienen árboles
		if rng.randf() > p_tree:
			continue
		if _too_close(pos2, 2.6):
			continue                                                  # separación mínima entre árboles
		var kit_name: String = "NormalTree_%d" % rng.randi_range(1, 5)
		var sc: float = rng.randf_range(0.9, 1.3)
		var mix: float = rng.randf()
		sc *= 1.0 + 0.25 * bw[2]                                         # la selva tiene árboles más grandes
		var birch_t: float = 0.08 + 0.3 * bw[3]                          # abedules y arces: sobre todo en el bosque
		if mix < birch_t:
			kit_name = "BirchTree_%d" % rng.randi_range(1, 5)
			sc = rng.randf_range(0.95, 1.4)
		elif mix < birch_t * 2.0:
			kit_name = "MapleTree_%d" % rng.randi_range(1, 5)
			sc = rng.randf_range(0.8, 1.2)
		if pos2.y > 7.0 and rng.randf() < 0.9:
			kit_name = "PineTree_%d" % rng.randi_range(1, 5)
			sc = rng.randf_range(1.5, 2.1)
		elif pos2.y > 4.6 and rng.randf() < 0.6:
			kit_name = "PineTree_%d" % rng.randi_range(1, 5)
			sc = rng.randf_range(1.4, 1.9)
		_add_tree(rng, pos2, kit_name, sc, Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.9, 1.05), rng.randf_range(0.8, 0.95)), trunk_shape, vine, false)
		made += 1
	# arbustos: matorral costero denso detrás de la playa, disperso en el bosque, rarísimo en la arena
	made = 0
	tries = 0
	while made < bush_count and tries < bush_count * 5:
		tries += 1
		var pos3: Vector3 = _random_spot(rng, 1.0, 13.0)
		if pos3.y < -90.0:
			continue
		var bw3: PackedFloat32Array = eco.get_bioma_pesos(pos3)
		var p_bush: float = bw3[4] * 0.95 + bw3[5] * 0.5 + bw3[2] * 0.5 + bw3[3] * 0.3 + bw3[1] * 0.08 + bw3[0] * 0.45
		if pos3.y < 1.7:
			p_bush = 0.05
		if rng.randf() > p_bush:
			continue
		var has_flowers: bool = rng.randf() < (0.5 if forest_value(pos3.x, pos3.z) < 0.0 else 0.2)
		var bt: Color = Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.9, 1.1), rng.randf_range(0.8, 1.0))
		var b: Node3D
		if true:
			var opts: Array[String] = ["Bush", "Bush_Large", "Bush_Small"]
			if has_flowers:
				opts = ["Bush_Flowers", "Bush_Large_Flowers", "Bush_Small_Flowers"]
			b = NatureKit.make_uq(opts[rng.randi() % 3], bt, 110.0)
		else:
			b = NatureKit.make("Bush_Common_Flowers" if has_flowers else "Bush_Common", bt, 110.0)
		b.position = pos3 - Vector3(0, 0.1, 0)
		b.rotation.y = rng.randf() * TAU
		b.scale = Vector3.ONE * rng.randf_range(0.55, 1.1)
		_flora.add_child(b)
		made += 1
	# rocas: derrumbe (talud) al pie de los acantilados y afloramientos sueltos
	made = 0
	tries = 0
	while made < rock_count and tries < rock_count * 12:
		tries += 1
		var talus: bool = made < int(rock_count * 0.45)
		var pos4: Vector3 = _random_spot(rng, 0.9, 3.8 if talus else 14.0)
		if pos4.y < -90.0:
			continue
		if talus and _cliff_mask(pos4.x, pos4.z) < 0.25:
			continue
		if not talus and pos4.y < 1.7 and rng.randf() < 0.8:
			continue
		if not talus:
			var bw4: PackedFloat32Array = eco.get_bioma_pesos(pos4)    # los afloramientos se juntan en el roquedal
			if rng.randf() > 0.06 + bw4[1] * 0.9 + bw4[5] * 0.3 + bw4[4] * 0.15 + eco.get_misterio(pos4) * 0.9:
				continue
		var uq_rock: bool = true
		var r: Node3D = NatureKit.make_uq("Rock_%d" % rng.randi_range(1, 5), Color.WHITE, 140.0) if uq_rock else NatureKit.make("Rock_Medium_%d" % rng.randi_range(1, 3), Color.WHITE, 140.0)
		r.position = pos4 - Vector3(0, 0.15, 0)
		r.rotation.y = rng.randf() * TAU
		r.scale = Vector3.ONE * (rng.randf_range(0.3, 0.8) if talus else rng.randf_range(0.25, 0.6))
		if uq_rock:
			r.scale *= 3.0
		_flora.add_child(r)
		var rock_body := StaticBody3D.new()
		var rock_cs := CollisionShape3D.new()
		var rs := SphereShape3D.new()
		rs.radius = (0.5 if uq_rock else 1.1) * r.scale.x
		rock_cs.shape = rs
		rock_body.position = r.position + Vector3(0, 0.5 * r.scale.x, 0)
		rock_body.add_child(rock_cs)
		_flora.add_child(rock_body)
		made += 1

## Árbol individual (talable): visual, colisión, lianas (solo los vivos) y registro en las listas.
func _add_tree(rng: RandomNumberGenerator, pos: Vector3, kit_name: String, sc: float, tint: Color, shape: Shape3D, vine: Mesh, dead: bool) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * sc
	tree.rotation.y = rng.randf() * TAU
	var visual: Node3D = NatureKit.make_uq(kit_name, tint.lerp(Color.WHITE, 0.5), 160.0) if (kit_name.begins_with("Birch") or kit_name.begins_with("Maple") or kit_name.begins_with("NormalTree") or kit_name.begins_with("PineTree") or dead) else NatureKit.make(kit_name, tint, 160.0)
	tree.add_child(visual)
	_flora.add_child(tree)
	_add_solid(tree, shape, Vector3(0, 1.5, 0))
	var lr := RandomNumberGenerator.new()
	lr.seed = hash(pos)
	var nl: int = 0
	if not dead:
		nl = 0 if lr.randf() > 0.5 else lr.randi_range(1, 2)
	tree.set_meta("lianas", nl)
	if dead:
		tree.set_meta("seco", true)
	for k in nl:
		var v := MeshInstance3D.new()
		v.name = "Liana%d" % k
		v.mesh = vine
		var va: float = lr.randf() * TAU
		v.position = Vector3(cos(va) * 0.95, 2.2, sin(va) * 0.95)
		tree.add_child(v)
	tree_nodes.append(tree)
	tree_positions.append(pos)
	tree_scales.append(tree.scale.x)

## ¿Hay otro árbol o palmera a menos de `min_d` metros?
func _too_close(pos: Vector3, min_d: float) -> bool:
	var d2: float = min_d * min_d
	for q: Vector3 in tree_positions:
		if (q.x - pos.x) * (q.x - pos.x) + (q.z - pos.z) * (q.z - pos.z) < d2:
			return true
	for q2: Vector3 in palm_positions:
		if (q2.x - pos.x) * (q2.x - pos.x) + (q2.z - pos.z) * (q2.z - pos.z) < d2:
			return true
	return false

## Manchas de bosque (-0.5..0.5): arboledas y claros de ~40 m.
func forest_value(x: float, z: float) -> float:
	if not _noise_ready:
		_setup_noise()
	return _noise.get_noise_2d(x * 2.2 + 300.0, z * 2.2 - 120.0)

## Humedad 0..1: alta junto a la laguna, decae con la distancia.
func moisture_at(x: float, z: float) -> float:
	var d: float = Vector2(x, z).distance_to(POND_CENTER)
	return clampf(1.0 - (d - POND_RADIUS * 1.6) / 26.0, 0.0, 1.0)


## Busca un punto con altura entre min_h y max_h; devuelve y=-100 si falla.
func _random_spot(rng: RandomNumberGenerator, min_h: float, max_h: float) -> Vector3:
	for attempt in 40:
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * radius
		var x: float = cos(a) * d
		var z: float = sin(a) * d
		var h: float = _height(x, z)
		if is_in_pond_area(x, z, 1.15) or is_in_cave_area(x, z, 1.0):
			continue
		if h >= min_h and h <= max_h:
			return Vector3(x, h, z)
	return Vector3(0, -100, 0)
