@tool
class_name IslandTerrain
extends MeshInstance3D

## Isla grande low-poly: playa de arena, llanura de pasto y colinas suaves, con flora.
## Radio 60 m (≈ 4 veces el área de la versión anterior). Incluye una laguna y una meseta plana
## donde se construye la cueva (ver island_features.gd).
@export var radius: float = 60.0:
	set(v):
		radius = v
		_build()
@export var hill_height: float = 6.0:
	set(v):
		hill_height = v
		_build()
@export var noise_seed: int = 7:
	set(v):
		noise_seed = v
		_build()
@export var palm_count: int = 80
@export var tree_count: int = 170
@export var bush_count: int = 280
@export var rock_count: int = 80

const RES := 170
const SAND := Color(0.88, 0.8, 0.56)
const GRASS := Color(0.34, 0.58, 0.22)
const GRASS_DARK := Color(0.24, 0.46, 0.18)
const ROCK := Color(0.5, 0.48, 0.45)
const CAVE_FLOOR := Color(0.3, 0.28, 0.27)

## Laguna de agua dulce tierra adentro
const POND_CENTER := Vector2(-16.0, 14.0)
const POND_RADIUS := 6.0
const POND_DEPTH := 2.8

## Meseta de la cueva (el suelo se aplana a la altura natural del centro)
const CAVE_CENTER := Vector2(24.0, -20.0)
const CAVE_PLATEAU_R := 16.0

var _noise := FastNoiseLite.new()
var _flora: Node3D
var _noise_ready: bool = false

var pond_water_level: float = 2.0
var cave_floor_y: float = 3.0
var tree_positions: Array[Vector3] = []
var tree_scales: Array[float] = []
var palm_positions: Array[Vector3] = []
var tree_nodes: Array[Node3D] = []     ## árboles y palmeras como nodos (para talarlos de a uno)
var palm_nodes: Array[Node3D] = []

func _ready() -> void:
	_build()

func _setup_noise() -> void:
	_noise.seed = noise_seed
	_noise.frequency = 1.5 / radius
	_noise_ready = true
	cave_floor_y = maxf(_base_height(CAVE_CENTER.x, CAVE_CENTER.y), 2.4)

## Altura del terreno en (x, z) — pública para el jugador, la barca y el resto del juego.
func height_at(x: float, z: float) -> float:
	if not _noise_ready:
		_setup_noise()
	return _height(x, z)

func is_in_pond_area(x: float, z: float, margin: float = 1.0) -> bool:
	return Vector2(x, z).distance_to(POND_CENTER) < POND_RADIUS * 1.6 * margin

func is_in_cave_area(x: float, z: float, margin: float = 1.0) -> bool:
	return Vector2(x, z).distance_to(CAVE_CENTER) < CAVE_PLATEAU_R * 0.75 * margin

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
	return h

func _base_height(x: float, z: float) -> float:
	var d: float = 1.0 - Vector2(x, z).length() / radius
	d += _noise.get_noise_2d(x, z) * 0.28
	if d < 0.0:
		return maxf(-1.5 + d * 6.0, -4.0)   # fondo marino
	if d < 0.12:
		return lerpf(-1.5, 0.9, d / 0.12)   # playa: sube sobre el agua
	var inland: float = d - 0.12
	var hills: float = (_noise.get_noise_2d(x * 1.6 + 50.0, z * 1.6) * 0.5 + 0.5) * hill_height
	return 0.9 + minf(inland * 6.0, 1.0) * (0.3 + hills * minf(inland * 3.0, 1.0))

func _color(h: float, slope: float, xz: Vector2 = Vector2(1000, 1000)) -> Color:
	if xz.distance_to(CAVE_CENTER) < 8.5 and absf(h - cave_floor_y) < 0.6:
		return CAVE_FLOOR # suelo rocoso de la cueva
	if xz.distance_to(POND_CENTER) < POND_RADIUS * 1.6 and h < pond_water_level + 0.25:
		return Color(0.55, 0.5, 0.38) # fondo/orilla de la laguna
	if h < 1.2:
		return SAND
	if slope > 0.65:
		return ROCK
	return GRASS if h < 3.2 else GRASS_DARK

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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RES:
		for j in RES:
			var x0: float = -half + i * step
			var z0: float = -half + j * step
			var p: Array[Vector3] = []
			for o: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
				var x: float = x0 + o.x * step
				var z: float = z0 + o.y * step
				p.append(Vector3(x, _height(x, z), z))
			for tri: Array in [[0, 1, 2], [1, 3, 2]]:
				var a: Vector3 = p[tri[0]]
				var b: Vector3 = p[tri[1]]
				var c: Vector3 = p[tri[2]]
				var n: Vector3 = (b - a).cross(c - a).normalized()
				var cen: Vector3 = (a + b + c) / 3.0
				var base_col: Color = _color(cen.y, 1.0 - absf(n.y), Vector2(cen.x, cen.z))
				# variación suave de tono (manchas de tierra, pasto más seco o más vivo) para romper lo plano
				var jit: float = _noise.get_noise_2d(cen.x * 4.3 + 91.0, cen.z * 4.3 - 40.0)
				var jit2: float = _noise.get_noise_2d(cen.x * 0.9 - 300.0, cen.z * 0.9 + 120.0)
				base_col = base_col.lightened(jit * 0.16) if jit > 0.0 else base_col.darkened(-jit * 0.2)
				base_col.r += jit2 * 0.05
				base_col.g -= jit2 * 0.02
				st.set_color(base_col)
				st.add_vertex(a)
				st.add_vertex(b)
				st.add_vertex(c)
	st.generate_normals()
	mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	# grano de detalle (ruido gris) en proyección triplanar: la superficie deja de verse lisa
	var gn := FastNoiseLite.new()
	gn.noise_type = FastNoiseLite.TYPE_CELLULAR
	gn.frequency = 0.02
	gn.fractal_type = FastNoiseLite.FRACTAL_FBM
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.62, 0.62))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = gn
	tex.color_ramp = ramp
	mat.albedo_texture = tex
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.18, 0.18, 0.18)
	material_override = mat
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

	for i in palm_count:
		var pos: Vector3 = _random_spot(rng, 0.9, 2.2)
		if pos.y < -90.0:
			continue
		# árbol costero (mantiene la mecánica de "palmera": cocos, hojas grandes y cuerda); el pack no trae palmeras
		var palm := Node3D.new()
		palm.position = pos
		palm.rotation.y = rng.randf() * TAU
		palm.scale = Vector3.ONE * rng.randf_range(0.5, 0.75)
		var coast_visual: Node3D = NatureKit.make("CommonTree_%d" % rng.randi_range(1, 5), Color(rng.randf_range(0.95, 1.1), rng.randf_range(1.0, 1.12), rng.randf_range(0.8, 0.95)), 160.0)
		coast_visual.rotation.x = rng.randf_range(0.04, 0.14)   # el viento del mar los inclina
		palm.add_child(coast_visual)
		_flora.add_child(palm)
		_add_solid(palm, trunk_shape_palm, Vector3(0.1, 1.5, 0))
		palm.set_meta("hojas", 4)
		palm_nodes.append(palm)
		palm_positions.append(pos)
	for i in tree_count:
		var pos2: Vector3 = _random_spot(rng, 1.8, 7.0)
		if pos2.y < -90.0:
			continue
		var tree := Node3D.new()
		tree.position = pos2
		tree.scale = Vector3.ONE * rng.randf_range(0.62, 1.0)
		tree.rotation.y = rng.randf() * TAU
		var kit_name: String = "CommonTree_%d" % rng.randi_range(1, 5)
		if pos2.y > 4.6 and rng.randf() < 0.6:
			kit_name = "Pine_%d" % rng.randi_range(1, 5)
		var visual: Node3D = NatureKit.make(kit_name, Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.9, 1.05), rng.randf_range(0.8, 0.95)), 160.0)
		tree.add_child(visual)
		_flora.add_child(tree)
		_add_solid(tree, trunk_shape, Vector3(0, 1.5, 0))
		# lianas colgando (generador propio: no altera la generación del resto de la isla)
		var lr := RandomNumberGenerator.new()
		lr.seed = hash(pos2)
		var nl: int = 0 if lr.randf() > 0.5 else lr.randi_range(1, 2)
		tree.set_meta("lianas", nl)
		for k in nl:
			var v := MeshInstance3D.new()
			v.name = "Liana%d" % k
			v.mesh = vine
			var va: float = lr.randf() * TAU
			v.position = Vector3(cos(va) * 0.95, 2.2, sin(va) * 0.95)
			tree.add_child(v)
		tree_nodes.append(tree)
		tree_positions.append(pos2)
		tree_scales.append(tree.scale.x)
	for i in bush_count:
		var pos3: Vector3 = _random_spot(rng, 1.2, 9.0)
		if pos3.y < -90.0:
			continue
		var has_flowers: bool = rng.randf() < 0.4
		var b: Node3D = NatureKit.make("Bush_Common_Flowers" if has_flowers else "Bush_Common", Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.9, 1.1), rng.randf_range(0.8, 1.0)), 110.0)
		b.position = pos3 - Vector3(0, 0.1, 0)
		b.rotation.y = rng.randf() * TAU
		b.scale = Vector3.ONE * rng.randf_range(0.55, 1.1)
		_flora.add_child(b)
	for i in rock_count:
		var pos4: Vector3 = _random_spot(rng, 0.9, 11.0)
		if pos4.y < -90.0:
			continue
		var r: Node3D = NatureKit.make("Rock_Medium_%d" % rng.randi_range(1, 3), Color.WHITE, 140.0)
		r.position = pos4 - Vector3(0, 0.15, 0)
		r.rotation.y = rng.randf() * TAU
		r.scale = Vector3.ONE * rng.randf_range(0.25, 0.6)
		_flora.add_child(r)
		# colisión esférica propia (sin escala no uniforme, que Jolt no soporta)
		var rock_body := StaticBody3D.new()
		var rock_cs := CollisionShape3D.new()
		var rs := SphereShape3D.new()
		rs.radius = 1.1 * r.scale.x
		rock_cs.shape = rs
		rock_body.position = r.position + Vector3(0, 0.5 * r.scale.x, 0)
		rock_body.add_child(rock_cs)
		_flora.add_child(rock_body)

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
