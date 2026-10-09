class_name IslandTerrain
extends MeshInstance3D

## Isla grande low-poly con relieve: playa ancha de arena, llanura de pasto, colinas, acantilados en el oeste,
## una laguna y una meseta plana para la cueva (ver island_features.gd).
## Radio 120 m (4 veces el área de la versión anterior). El aspecto lo da terrain_island.gdshader.
@export var radius: float = 160.0:
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
@export var tree_count: int = 250
@export var bush_count: int = 600
@export var rock_count: int = 170

const RES := 300

## Mapa de alturas de la isla (silueta de la referencia islarefe.jpg, generado por tools/make_heightmap.gd)
const HMAP_PATH := "res://assets/terrain/island_height.res"
const HMAP_M_PER_PX: float = 0.714
const MAP_HALF := Vector2(134.0, 196.0)   ## mitad del mapa en metros (x, z)
var _hmap: Image
const SAND := Color(0.88, 0.8, 0.56)
const BEACH_W := 0.17          ## ancho de la playa (fracción del radio)
const CLIFF_DIR := Vector2(-1.0, 0.35)   ## hacia dónde están los acantilados (oeste)
const TERRAIN_SHADER: Shader = preload("res://shaders/terrain_island.gdshader")

## Laguna de agua dulce tierra adentro
const POND_CENTER := Vector2(-30.0, -30.0)
const POND_RADIUS := 9.0
const POND_DEPTH := 3.2

## Meseta de la cueva (el suelo se aplana a la altura natural del centro)
const CAVE_CENTER := Vector2(-45.0, 30.0)
const CAVE_PLATEAU_R := 16.0
const PIT_R := 5.5              ## radio del pozo (la "cueva" es un agujero en el terreno)
const PIT_DEPTH := 8.0          ## profundidad del pozo (m)
const RAMP_HALF_W := 1.8        ## semiancho de la rampa de bajada
const RAMP_LEN := 18.0          ## largo de la rampa más allá del borde

## Dirección (plano XZ) desde el pozo hacia donde baja la rampa: hacia el centro de la isla.
static func cave_dir2() -> Vector2:
	return (-CAVE_CENTER).normalized()

## Metros que se excavan en (x, z): pozo circular de paredes empinadas + rampa en trinchera.
func _pit_carve(_x: float, _z: float) -> float:
	return 0.0   # sin pozo: la cueva es una roca con túnel (ver IslandFeatures._build_cave_rock)

func _cave_bump(_x: float, _z: float) -> float:
	return 0.0

var _noise := FastNoiseLite.new()
var _flora: Node3D
var _path_img: Image
var path_lines: Array[Dictionary] = []   ## caminos importantes: {pts: PackedVector2Array, dest: Vector2}
var _path_half: float = 162.0
const PATH_SIZE: int = 768
var eco: EcoMap                         ## mapa ecológico (biomas, humedad, suelo); lo crea la propia isla
var _noise_ready: bool = false
var _mood: float = 0.0
var _mood_timer: float = 0.0
var _flora_mood: float = 0.0

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
	# ánimo más fino para la flora: vínculo + emociones (enojo/miedo la tensan, confianza la calma)
	var fino: float = Isla.vinculo / 60.0 * 0.6 + (Isla.get_emocion("confianza") - 0.45) * 0.6 - Isla.get_emocion("enojo") * 0.8 - Isla.get_emocion("miedo") * 0.4
	_flora_mood = lerpf(_flora_mood, clampf(fino, -1.0, 1.0), 0.06)
	Wind.set_mood(_flora_mood)

func _setup_noise() -> void:
	_noise.seed = noise_seed
	_noise.frequency = 1.5 / 120.0
	if _hmap == null and ResourceLoader.exists(HMAP_PATH):
		_hmap = ResourceLoader.load(HMAP_PATH) as Image
		_smooth_shore()
	_noise_ready = true
	cave_floor_y = maxf(_base_height(CAVE_CENTER.x, CAVE_CENTER.y), 2.0)   # meseta plana donde se apoya la roca de la cueva
	if river == null:
		pond_wl0 = _pond_ring_level()
		river = IslandRiver.new()
		river.build(self, pond_wl0)

## Redondea las orillas del mapa de alturas (calas y puntas): promedia solo cerca del nivel del mar, sin tocar acantilados ni el interior.
func _smooth_shore() -> void:
	var w: int = _hmap.get_width()
	var hh: int = _hmap.get_height()
	var cur: PackedFloat32Array = _hmap.get_data().to_float32_array()
	for pass_i in 3:
		var nxt: PackedFloat32Array = cur.duplicate()
		for y in range(1, hh - 1):
			for x in range(1, w - 1):
				var k: int = y * w + x
				var v: float = cur[k]
				if v < -1.2 or v > 1.8:
					continue
				var sm: float = 0.0
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						sm += clampf(cur[k + oy * w + ox], -1.2, 1.8)
				nxt[k] = lerpf(v, sm / 9.0, 0.8)
		cur = nxt
	_hmap = Image.create_from_data(w, hh, false, Image.FORMAT_RF, cur.to_byte_array())

var river: IslandRiver
var pond_wl0: float = 2.0

## Nivel del agua del estanque: un poco bajo el borde más bajo del anillo exterior (sin contar el río).
func _pond_ring_level() -> float:
	var lowest: float = 1000.0
	for i in 16:
		var ang: float = TAU * i / 16.0
		var rp: Vector2 = POND_CENTER + Vector2(cos(ang), sin(ang)) * POND_RADIUS * 1.5
		lowest = minf(lowest, _height_base(rp.x, rp.y))
	return lowest - 0.1

func base_height_public(x: float, z: float) -> float:
	return _base_height(x, z)

## Altura del terreno en (x, z) — pública para el jugador, la barca y el resto del juego.
func height_at(x: float, z: float) -> float:
	if not _noise_ready:
		_setup_noise()
	return _height(x, z)

func is_in_pond_area(x: float, z: float, margin: float = 1.0) -> bool:
	if river != null and river.dist_at(x, z) < 2.6 * margin:     # el río también aparta árboles, pasto y objetos
		return true
	return Vector2(x, z).distance_to(POND_CENTER) < POND_RADIUS * 1.6 * margin

func is_in_cave_area(x: float, z: float, margin: float = 1.0) -> bool:
	return Vector2(x, z).distance_to(CAVE_CENTER) < CAVE_PLATEAU_R * 1.2 * margin

func _height(x: float, z: float) -> float:
	var h: float = _height_base(x, z)
	if river != null:
		h = river.carve(x, z, h)
	return h

func _height_base(x: float, z: float) -> float:
	var h: float = _base_height(x, z)
	var dp: float = Vector2(x, z).distance_to(POND_CENTER) / (POND_RADIUS * 1.6)
	dp *= 1.0 + _noise.get_noise_2d(x * 2.2 + 300.0, z * 2.2 - 120.0) * 0.32   # orilla irregular
	if dp < 1.0:
		var k: float = 1.0 - smoothstep(0.0, 1.0, dp)
		h -= POND_DEPTH * k
	var dc: float = Vector2(x, z).distance_to(CAVE_CENTER) / CAVE_PLATEAU_R
	if dc < 1.0:
		var kc: float = 1.0 - smoothstep(0.45, 1.0, dc)
		h = lerpf(h, cave_floor_y, kc)
	h += _cave_bump(x, z)
	h -= _pit_carve(x, z)
	return h

## 0..1: cuánto de acantilado hay en esa dirección (sector oeste con borde irregular).
func _cliff_mask(x: float, z: float) -> float:
	if _hmap != null:
		var gx: float = _hmap_h(x + 2.0, z) - _hmap_h(x - 2.0, z)
		var gz: float = _hmap_h(x, z + 2.0) - _hmap_h(x, z - 2.0)
		return smoothstep(0.55, 1.2, Vector2(gx, gz).length() / 4.0 * 1.0)
	var v := Vector2(x, z)
	if v.length() < 1.0:
		return 0.0
	var c: float = v.normalized().dot(CLIFF_DIR.normalized()) + _noise.get_noise_2d(x * 0.5 + 400.0, z * 0.5) * 0.12
	return smoothstep(0.5, 0.88, c)

## Altura bilineal del mapa en metros (x, z mundo). Fuera del mapa: fondo marino.
func _hmap_h(x: float, z: float) -> float:
	var fx: float = x / HMAP_M_PER_PX + float(_hmap.get_width()) * 0.5 - 0.5
	var fy: float = z / HMAP_M_PER_PX + float(_hmap.get_height()) * 0.5 - 0.5
	var ix: int = floori(fx)
	var iy: int = floori(fy)
	var tx: float = fx - float(ix)
	var ty: float = fy - float(iy)
	var w: int = _hmap.get_width()
	var h: int = _hmap.get_height()
	var v: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for k in 4:
		var cx: int = clampi(ix + (k % 2), 0, w - 1)
		var cy: int = clampi(iy + (k >> 1), 0, h - 1)
		v[k] = _hmap.get_pixel(cx, cy).r
	var res: float = lerpf(lerpf(v[0], v[1], tx), lerpf(v[2], v[3], tx), ty)
	var edge: float = maxf(absf(x) - (float(w) * 0.5 * HMAP_M_PER_PX - 10.0), absf(z) - (float(h) * 0.5 * HMAP_M_PER_PX - 10.0))
	return lerpf(res, -4.5, smoothstep(0.0, 10.0, edge))   # más allá del mapa: fondo marino profundo

func _base_height(x: float, z: float) -> float:
	if _hmap != null:
		var hm: float = _hmap_h(x, z)
		if hm > 0.2:
			hm += _noise.get_noise_2d(x * 2.0, z * 2.0) * 0.35 * smoothstep(0.5, 2.0, hm)
		return hm
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
	h += _massif(x, z, inland)
	if m > 0.0:
		# meseta alta con pared casi vertical sobre la playa, y terrazas
		var wall: float = smoothstep(0.0, 0.035, inland)
		var fade: float = 1.0 - smoothstep(0.3, 0.58, inland)
		var terr: float = 8.0 + _noise.get_noise_2d(x * 3.0 - 200.0, z * 3.0 + 90.0) * 3.5 + _noise.get_noise_2d(x * 0.9, z * 0.9 + 33.0) * 2.0
		h += terr * m * wall * fade
	return h

## Macizo central: la isla se eleva hacia adentro con crestas y valles (ruido en cresta), sin tocar la laguna ni la meseta de la cueva.
func _massif(x: float, z: float, inland: float) -> float:
	var d0: float = clampf(1.0 - Vector2(x, z).length() / radius, 0.0, 1.0)
	var rise: float = smoothstep(0.32, 0.78, d0)
	if rise <= 0.0:
		return 0.0
	var keep: float = smoothstep(POND_RADIUS * 1.6, POND_RADIUS * 3.2, Vector2(x, z).distance_to(POND_CENTER))
	keep *= smoothstep(CAVE_PLATEAU_R, CAVE_PLATEAU_R * 2.2, Vector2(x, z).distance_to(CAVE_CENTER))
	# lomas redondeadas: ruido suave con la posición deformada (sin crestas filosas)
	var wx: float = x + _noise.get_noise_2d(x * 0.8 + 11.0, z * 0.8) * 14.0
	var wz: float = z + _noise.get_noise_2d(x * 0.8, z * 0.8 + 77.0) * 14.0
	var n1: float = _noise.get_noise_2d(wx * 0.75 + 130.0, wz * 0.75 - 70.0) * 0.5 + 0.5
	var dome: float = smoothstep(0.3, 0.85, n1)
	var ridge: float = dome * dome * (3.0 - 2.0 * dome)
	var base: float = 2.5 + _noise.get_noise_2d(x * 0.5, z * 0.5 - 300.0) * 1.0 + _noise.get_noise_2d(x * 2.0, z * 2.0) * 0.35
	return rise * keep * (base + ridge * 8.0) * minf(inland * 4.0, 1.0)

## Categoría del suelo pintada en el color del vértice (alfa): 1 normal, 0.6 cueva, 0.3 fondo de laguna.
func _category(h: float, xz: Vector2) -> float:
	var rel: Vector2 = xz - CAVE_CENTER                  # piso de piedra a lo largo de todo el túnel
	var cd: Vector2 = cave_dir2()
	var along: float = rel.dot(cd)
	if along > -5.0 and along < IslandFeatures.CAVE_LEN and absf(rel.dot(Vector2(-cd.y, cd.x))) < 5.0 and h < cave_floor_y + 0.8:
		return 0.5
	return 1.0

## Cuánto es fondo de laguna en un punto (0 a 1), continuo: se pinta por vértice y el shader lo funde.
func _pond_bed(xz: Vector2) -> float:
	var dpv: float = xz.distance_to(POND_CENTER) / (POND_RADIUS * 1.6)
	dpv *= 1.0 + _noise.get_noise_2d(xz.x * 2.2 + 300.0, xz.y * 2.2 - 120.0) * 0.32
	return 1.0 - smoothstep(0.4, 0.88, dpv)

func _build() -> void:
	if not is_inside_tree():
		return
	_setup_noise()
	# nivel del agua de la laguna: un poco bajo el borde más bajo del anillo exterior
	pond_water_level = pond_wl0
	var half: float = radius * 1.35
	var step: float = half * 2.0 / RES
	# alturas de la grilla (una sola vez)
	var hg: PackedFloat32Array = PackedFloat32Array()
	hg.resize((RES + 1) * (RES + 1))
	for j in RES + 1:
		for i in RES + 1:
			hg[j * (RES + 1) + i] = _height(-half + i * step, -half + j * step)
	_hg = hg
	_hg_half = half
	_hg_step = step
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
				var col: Color = Color(tone, tone, tone, _category(cen.y, Vector2(cen.x, cen.z)))
				var nf: Vector3 = (b - a).cross(c - a).normalized()
				if nf.y < 0.0:
					nf = -nf
				for k in 3:
					var idx: int = tri[k]
					var gi: int = i + (idx & 1)
					var gj: int = j + (idx >> 1)
					var ns: Vector3 = _grid_normal(hg, gi, gj, step)
					# suave en pasto y lomas, facetado solo donde la pendiente es fuerte (acantilados, rocas)
					var kf: float = smoothstep(0.3, 0.55, 1.0 - ns.y)
					var cav: float = col.a
					var va: float = cav if cav < 0.8 else 1.0 - 0.38 * _pond_bed(Vector2(p[idx].x, p[idx].z))
					var ao: float = _terrain_ao(hg, gi, gj)          # oclusión falsa horneada en el vértice: hondonadas más oscuras
					st.set_color(Color(col.r * ao, col.g * ao, col.b * ao, va))
					st.set_normal(ns.lerp(nf, kf).normalized())
					st.add_vertex(p[idx])
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
	_bake_biome_tint(mat, half)
	if not Engine.is_editor_hint():
		_build_terrain_collision()
		_feed_water_shader(half)
		_spawn_life()

## Mapa de color del pasto por bioma (textura pequeña, se interpola suave entre biomas).
func _bake_biome_tint(mat: ShaderMaterial, half: float) -> void:
	var size: int = 160
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	# [costa, roquedal, selva, bosque, matorral, árido]
	var cols: Array[Color] = [Color(1.1, 1.04, 0.74), Color(0.8, 0.93, 0.82), Color(0.5, 0.9, 0.5), Color(0.72, 0.98, 0.78), Color(1.25, 1.1, 0.6), Color(1.38, 1.1, 0.66)]
	for j in size:
		for i in size:
			var x: float = -half + (float(i) + 0.5) / size * half * 2.0
			var z: float = -half + (float(j) + 0.5) / size * half * 2.0
			var c := Color(1, 1, 1)
			var h: float = _height(x, z)
			if h > 0.5:
				var w: PackedFloat32Array = eco.get_bioma_pesos(Vector3(x, h, z))
				var tot: float = 0.0
				var acc := Vector3.ZERO
				for k in 6:
					tot += w[k]
					acc += Vector3(cols[k].r, cols[k].g, cols[k].b) * w[k]
				if tot > 0.001:
					acc /= tot
					c = Color(acc.x, acc.y, acc.z)
			img.set_pixel(i, j, Color(c.r / 1.5, c.g / 1.5, c.b / 1.5))
	mat.set_shader_parameter("biome_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("biome_origin", Vector2(-half, -half))
	mat.set_shader_parameter("biome_size", half * 2.0)

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
## Árboles talados guardados como molde (fuera del árbol de escena) para que la lluvia tranquila los haga rebrotar.
var felled: Array = []

var _molde_arbol: Node3D = null    ## ultimo arbol talado (molde para replantar con semillas)
var _molde_palma: Node3D = null

func fell_tree(tree: Node3D, dir: Vector3) -> Vector3:
	var pos: Vector3 = tree.global_position
	var es_palma_m: bool = palm_nodes.has(tree)
	if es_palma_m:
		if _molde_palma != null:
			_molde_palma.free()
		_molde_palma = tree.duplicate() as Node3D
	else:
		if _molde_arbol != null:
			_molde_arbol.free()
		_molde_arbol = tree.duplicate() as Node3D
	var idx: int = tree_nodes.find(tree)
	if felled.size() < 80 and (idx >= 0 or palm_nodes.has(tree)):
		felled.append({"node": tree.duplicate(), "palm": palm_nodes.has(tree), "pos": pos})
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

## Hace rebrotar el árbol talado número i: reaparece chico en su lugar y crece despacio. Devuelve su posición (o Vector3.INF si no hay).
func regrow_tree(i: int, seconds: float = 40.0) -> Vector3:
	if i < 0 or i >= felled.size() or _flora == null:
		return Vector3.INF
	var d: Dictionary = felled[i]
	felled.remove_at(i)
	var tree: Node3D = d["node"] as Node3D
	var pos: Vector3 = d["pos"]
	var full: Vector3 = tree.scale
	tree.position = _flora.to_local(pos)
	tree.scale = full * 0.12
	tree.set_meta("golpes", 0)
	if bool(d["palm"]):
		tree.set_meta("hojas", 4)
		palm_nodes.append(tree)
		palm_positions.append(pos)
	else:
		tree_nodes.append(tree)
		tree_positions.append(pos)
		tree_scales.append(full.x)
	_flora.add_child(tree)
	var tw: Tween = tree.create_tween()
	tw.tween_property(tree, "scale", full, seconds).set_trans(Tween.TRANS_SINE)
	return pos

## Replanta un arbol (de semilla): aparece chico en `pos` y crece por etapas. Usa palma cerca de la costa. Devuelve false si no hay molde.
func plant_tree(pos: Vector3, seconds: float = 150.0) -> bool:
	if _flora == null:
		return false
	var palma: bool = pos.y < 4.0
	var molde: Node3D = _molde_palma if palma else _molde_arbol
	if molde == null:
		palma = not palma
		molde = _molde_palma if palma else _molde_arbol
	if molde == null:
		return false
	var tree: Node3D = molde.duplicate() as Node3D
	var full: Vector3 = tree.scale
	tree.position = _flora.to_local(pos)
	tree.scale = full * 0.1
	tree.set_meta("golpes", 0)
	if palma:
		tree.set_meta("hojas", 4)
		palm_nodes.append(tree)
		palm_positions.append(pos)
	else:
		tree_nodes.append(tree)
		tree_positions.append(pos)
		tree_scales.append(full.x)
	_flora.add_child(tree)
	var tw: Tween = tree.create_tween()
	tw.tween_property(tree, "scale", full * 0.35, seconds * 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_property(tree, "scale", full * 0.7, seconds * 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(tree, "scale", full, seconds * 0.35).set_trans(Tween.TRANS_SINE)
	return true

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

const TREE_VIS: float = 110.0   # árboles más lejos se ocultan (rendimiento)

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
	if _path_img == null:
		_build_paths()
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
	trunk_shape_palm.radius = 0.45
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
		if dpos.y < -90.0 or _cliff_mask(dpos.x, dpos.z) > 0.2 or _near_path(dpos.x, dpos.z, 1.0):
			continue
		if forest_value(dpos.x, dpos.z) < 0.05 and rng.randf() < 0.7:
			continue   # se agrupan en las zonas más arboladas
		_add_tree(rng, dpos, "DeadTree_%d" % rng.randi_range(1, 10), rng.randf_range(0.7, 1.1), Color.WHITE, trunk_shape, vine, true)
		made += 1
	# árboles de costa con hojas (mecánica de "palmera"): solo detrás de la playa
	var palm_target: int = int(palm_count * 0.3)
	made = 0
	tries = 0
	while made < palm_target and tries < palm_target * 40:
		tries += 1
		var cpos: Vector3 = _random_spot(rng, 1.3, 3.2)
		if cpos.y < -90.0 or _cliff_mask(cpos.x, cpos.z) > 0.25 or _near_path(cpos.x, cpos.z, 0.8):
			continue
		# palmerales en tramos de costa; el resto de la orilla queda despejada
		if rng.randf() > smoothstep(0.0, 0.3, _stand_value(cpos.x + 500.0, cpos.z - 300.0)) + 0.04:
			continue
		var to_sea: Vector3 = _water_dir(cpos)
		var n_cl: int = rng.randi_range(2, 3)
		for gi in n_cl:
			var pos: Vector3 = cpos
			if gi > 0:
				var ang: float = rng.randf() * TAU
				var rr: float = rng.randf_range(2.8, 4.6)
				pos = Vector3(cpos.x + cos(ang) * rr, 0.0, cpos.z + sin(ang) * rr)
				pos.y = _height(pos.x, pos.z)
				if pos.y < 1.3 or pos.y > 3.4 or _cliff_mask(pos.x, pos.z) > 0.25 or _near_path(pos.x, pos.z, 0.8) or is_in_pond_area(pos.x, pos.z, 1.15) or is_in_cave_area(pos.x, pos.z, 1.0):
					continue
			if _too_close(pos, 3.0):
				continue
			var palm := Node3D.new()
			palm.position = pos
			palm.rotation.y = atan2(to_sea.x, to_sea.z) + rng.randf_range(-0.5, 0.5)   # +Z mira al mar: se inclinan hacia el agua
			palm.scale = Vector3.ONE * rng.randf_range(0.85, 1.25)
			var coast_visual: Node3D = _palm_visual(rng)
			coast_visual.rotation.x = rng.randf_range(0.06, 0.2)
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
		# arboledas y claros marcados: bajo el umbral del ruido no crece casi nada (claro), sobre él hay arboleda densa
		var grove: float = smoothstep(-0.14, 0.1, forest_value(pos2.x, pos2.z))
		var p_tree: float = maxf(dens * (0.04 + 1.1 * grove), wet * 0.8 * (0.35 + 0.65 * grove))
		if pos2.y < 2.6:
			p_tree *= clampf((pos2.y - 1.75) / 0.85, 0.0, 1.0)      # se aclara hacia la costa
		if pos2.y > 7.0:
			p_tree *= 0.45                                            # altura expuesta al viento: poco árbol
		if _cliff_mask(pos2.x, pos2.z) > 0.3 and pos2.y < 3.5:
			p_tree = 0.0                                              # al pie del acantilado solo hay derrumbe
		p_tree *= 1.0 - 0.9 * eco.get_misterio(pos2)          # los claros misteriosos casi no tienen árboles
		if rng.randf() > p_tree:
			continue
		if _near_path(pos2.x, pos2.z, 1.3):
			continue
		# rodales: la especie la decide un ruido de baja frecuencia (manchas de ~50 m), no un dado por árbol
		var stand: float = _stand_value(pos2.x, pos2.z)
		var dom: float = maxf(maxf(bw[2], bw[3]), maxf(bw[4], maxf(bw[0], maxf(bw[1], bw[5]))))
		var edge_b: float = smoothstep(0.4, 0.8, dom)                   # 0 = borde entre biomas, 1 = corazón del bioma
		var jungle: bool = bw[2] > 0.45
		var scrub: bool = (bw[4] + bw[5]) > 0.45
		var gap: float = lerpf(3.4, 2.3, grove) * lerpf(1.25, 1.0, edge_b)
		if jungle:
			gap *= 0.8                                                # selva: muy juntos
		elif scrub:
			gap *= 1.4                                                # matorral: árboles sueltos
		if _too_close(pos2, gap):
			continue                                                  # más juntos en el centro de la arboleda, más aire en los bordes
		var kit_name: String = "NormalTree_%d" % rng.randi_range(1, 5)
		var sc: float = rng.randf_range(0.9, 1.3)
		var stray: bool = rng.randf() < 0.05                           # algún árbol fuera de su rodal, para que no sea una máquina
		if jungle:
			sc = rng.randf_range(1.2, 1.6)                            # selva: grandes y retorcidos
			if (stand > -0.12) != stray:
				kit_name = "TwistedTree_%d" % rng.randi_range(1, 5)
		elif scrub:
			sc = rng.randf_range(0.6, 0.9)                            # matorral: bajos
		elif bw[3] > 0.35:
			if (stand > 0.12) != stray:
				kit_name = "BirchTree_%d" % rng.randi_range(1, 5)
				sc = rng.randf_range(0.95, 1.4)
			elif (stand < -0.12) != stray:
				kit_name = "MapleTree_%d" % rng.randi_range(1, 5)
				sc = rng.randf_range(0.8, 1.2)
		sc *= lerpf(0.72, 1.05, smoothstep(0.0, 0.8, grove)) * lerpf(0.85, 1.0, edge_b)   # más chicos en los bordes
		var mys: float = eco.get_misterio(pos2)
		if rng.randf() < 0.6 * mys:
			kit_name = "TwistedTree_%d" % rng.randi_range(1, 5)      # retorcidos en los bordes de los claros misteriosos
			sc = rng.randf_range(0.9, 1.3)
		if pos2.y > 7.0 and rng.randf() < 0.9:
			kit_name = "PineTree_%d" % rng.randi_range(1, 5)
			sc = rng.randf_range(1.5, 2.1)
		elif pos2.y > 4.6 and rng.randf() < 0.6:
			kit_name = "PineTree_%d" % rng.randi_range(1, 5)
			sc = rng.randf_range(1.4, 1.9)
		_add_tree(rng, pos2, kit_name, sc, Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.9, 1.05), rng.randf_range(0.8, 0.95)), trunk_shape, vine, false)
		made += 1
	_add_edge_markers(rng)
	# sotobosque por bioma, en grupos de 1 a 6 plantas (de a 2, 3 o 6 juntas) de la misma especie casi siempre
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
		var wet3: float = eco.get_humedad(pos3)
		# pesos por especie según el bioma: [arbusto, helecho, hoja ancha, planta 7, flores]
		var sw: Array[float] = [
			bw3[0] * 0.3 + bw3[1] * 0.2 + bw3[2] * 0.3 + bw3[3] * 0.5 + bw3[4] * 1.0 + bw3[5] * 0.6,
			bw3[2] * 1.2 + bw3[3] * 0.8 + bw3[4] * 0.2 + wet3 * 0.6,
			bw3[0] * 0.7 + bw3[2] * 1.0 + bw3[3] * 0.3 + bw3[4] * 0.2,
			bw3[0] * 0.5 + bw3[2] * 0.8 + bw3[3] * 0.2 + bw3[4] * 0.3 + bw3[5] * 0.5,
			bw3[0] * 0.1 + bw3[3] * 0.5 + bw3[4] * 0.6 + bw3[5] * 0.05]
		var tot: float = 0.0
		for w: float in sw:
			tot += w
		if tot <= 0.001:
			continue
		var pick: float = rng.randf() * tot
		var sp: int = 0
		for k in sw.size():
			pick -= sw[k]
			if pick <= 0.0:
				sp = k
				break
		# tamaño del grupo: helechos y flores en manchas grandes, arbustos más sueltos
		var sizes: Array[int] = [1, 2, 2, 3, 3, 6]
		if sp == 1 or sp == 4:
			sizes = [2, 3, 3, 6, 6, 3]
		elif sp == 0:
			sizes = [1, 1, 2, 2, 3, 3]
		var n_group: int = sizes[rng.randi() % sizes.size()]
		var has_flowers: bool = rng.randf() < (0.5 if forest_value(pos3.x, pos3.z) < 0.0 else 0.2)
		var bt: Color = Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.9, 1.1), rng.randf_range(0.8, 1.0))
		for gi in n_group:
			var gp: Vector3 = pos3
			if gi > 0:
				var ga: float = rng.randf() * TAU
				var gr: float = rng.randf_range(0.6, 1.0 + 0.25 * n_group)
				gp = Vector3(pos3.x + cos(ga) * gr, 0.0, pos3.z + sin(ga) * gr)
				gp.y = _height(gp.x, gp.z)
				if gp.y < 1.0 or gp.y > 13.0 or is_in_pond_area(gp.x, gp.z, 1.15) or is_in_cave_area(gp.x, gp.z, 1.0) or is_on_path(gp.x, gp.z, 0.25):
					continue
			var mname: String
			match sp:
				0:
					mname = "Bush_Common_Flowers" if has_flowers else "Bush_Common"
				1:
					mname = "Fern_1"
				2:
					mname = "Plant_1_Big" if rng.randf() < 0.3 else "Plant_1"
				3:
					mname = "Plant_7_Big" if rng.randf() < 0.3 else "Plant_7"
				_:
					mname = "Flower_3_Group" if rng.randf() < 0.5 else "Flower_4_Group"
			if gi > 0 and rng.randf() < 0.2:
				mname = "Fern_1" if sp != 1 else "Plant_1"      # algún vecino distinto
			var b: Node3D
			if sp == 0 and rng.randf() < 0.25:
				var ub: String = "Bush_Small_Flowers" if has_flowers else "Bush_Small"
				b = NatureKit.make_uq(ub, bt * Color(0.7, 0.8, 0.7), 110.0)
			else:
				b = NatureKit.make(mname, bt, 110.0)
			b.position = gp - Vector3(0, 0.1, 0)
			b.rotation.y = rng.randf() * TAU
			var gsc: float = rng.randf_range(0.8, 1.4) * (1.0 if gi == 0 else rng.randf_range(0.7, 1.0))   # el del centro es el más grande
			b.scale = Vector3(rng.randf_range(0.7, 1.3), rng.randf_range(0.75, 1.35), rng.randf_range(0.7, 1.3)) * gsc
			b.rotation.x = rng.randf_range(-0.08, 0.08)
			b.rotation.z = rng.randf_range(-0.08, 0.08)
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
		var ridx: int = rng.randi_range(1, 5)
		var rvar: int = rng.randi_range(0, 2)
		var r: Node3D = NatureKit.make_stone(ridx, rvar, rng.randi_range(0, 2))
		if _near_path(pos4.x, pos4.z, 1.0):
			r.free()
			continue
		r.position = pos4 - Vector3(0, 0.12, 0)
		r.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))
		var rs: float = rng.randf_range(0.3, 0.8) if talus else rng.randf_range(0.25, 0.6)
		r.scale = Vector3(rs * rng.randf_range(0.7, 1.4), rs * rng.randf_range(0.7, 1.35), rs * rng.randf_range(0.7, 1.4))
		r.scale *= 3.0
		_flora.add_child(r)
		_add_rock_body(r, 1000 + ridx * 10 + rvar)
		made += 1
	_add_rock_clusters(rng)

## Palmera del modelo stylized_palm_tree (una sola malla con textura): se normaliza a ~7 m con la base del tronco en el origen.
const PALM_GLB: String = "res://assets/terrain/stylized_palm_tree_1k_pbr.glb"
const PALM_K: float = 0.48                        ## el modelo mide ~14,5 m: se reduce a ~7 m
const PALM_BASE: Vector3 = Vector3(-1.364, -0.115, -1.210)   ## base del tronco, en el espacio del modelo ya con sus transformaciones
var _palm_mesh: Mesh = null
var _palm_xf: Transform3D = Transform3D.IDENTITY

func _palm_visual(rng: RandomNumberGenerator) -> Node3D:
	if _palm_mesh == null:
		var root: Node3D = (load(PALM_GLB) as PackedScene).instantiate() as Node3D
		var mi: MeshInstance3D = root.find_child("Object_4", true, false) as MeshInstance3D
		var xf: Transform3D = Transform3D.IDENTITY
		var c: Node3D = mi
		while c != null:
			xf = c.transform * xf
			c = c.get_parent() as Node3D
		_palm_mesh = mi.mesh
		_palm_xf = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * PALM_K), -PALM_BASE * PALM_K) * xf
		root.free()
	var holder := Node3D.new()
	var m := MeshInstance3D.new()
	m.mesh = _palm_mesh
	m.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3.ZERO) * _palm_xf
	m.visibility_range_end = 150.0
	m.visibility_range_end_margin = 10.0
	m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	holder.add_child(m)
	holder.scale = Vector3.ONE * rng.randf_range(0.9, 1.1)
	return holder

## Ruido de rodales (manchas de ~55 m, -1..1): decide qué especie domina en cada mancha.
var _stand_noise: FastNoiseLite = null

func _stand_value(x: float, z: float) -> float:
	if _stand_noise == null:
		_stand_noise = FastNoiseLite.new()
		_stand_noise.seed = noise_seed + 77
		_stand_noise.frequency = 1.0 / 55.0
	return _stand_noise.get_noise_2d(x, z) * 2.0

## Dirección horizontal hacia el agua (hacia donde baja más el terreno).
func _water_dir(p: Vector3) -> Vector3:
	var best: Vector3 = Vector3(0, 0, 1)
	var lo: float = 1e9
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		var h: float = _height(p.x + cos(a) * 5.0, p.z + sin(a) * 5.0)
		if h < lo:
			lo = h
			best = Vector3(cos(a), 0.0, sin(a))
	return best

## Marca el límite entre claro y arboleda con troncos caídos y arbustos.
func _add_edge_markers(rng: RandomNumberGenerator) -> void:
	var logs: int = 0
	var bushes: int = 0
	var tries: int = 0
	var bark: StandardMaterial3D = StandardMaterial3D.new()
	bark.albedo_color = Color(0.36, 0.27, 0.2)
	bark.roughness = 1.0
	while (logs < 14 or bushes < 26) and tries < 900:
		tries += 1
		var q: Vector3 = _random_spot(rng, 2.2, 9.0)
		if q.y < -90.0 or _cliff_mask(q.x, q.z) > 0.3 or _near_path(q.x, q.z, 1.5):
			continue
		var g: float = smoothstep(-0.14, 0.1, forest_value(q.x, q.z))
		if absf(g - 0.5) > 0.22 or rng.randf() > 0.5:
			continue                                                  # solo en la franja de transición
		if _too_close(q, 1.4):
			continue
		if rng.randf() < 0.35 and logs < 14:
			var lg := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			var rad: float = rng.randf_range(0.16, 0.26)
			cm.top_radius = rad * 0.85
			cm.bottom_radius = rad
			cm.height = rng.randf_range(2.4, 4.0)
			cm.radial_segments = 7
			cm.rings = 1
			lg.mesh = cm
			lg.material_override = bark
			lg.position = q + Vector3(0, rad * 0.7, 0)
			lg.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, PI / 2.0)
			lg.visibility_range_end = 90.0
			_flora.add_child(lg)
			logs += 1
		elif bushes < 26:
			var bsh: Node3D = NatureKit.make("Bush_Common", Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.9, 1.1), rng.randf_range(0.8, 1.0)), 110.0)
			bsh.position = q - Vector3(0, 0.1, 0)
			bsh.rotation.y = rng.randf() * TAU
			bsh.scale = Vector3.ONE * rng.randf_range(1.0, 1.5)
			_flora.add_child(bsh)
			bushes += 1

## Forma de una roca: 0 redondeada, 1 normal, 2 de pico fino. `spike` = probabilidad de pico.
func _rock_shape(rng: RandomNumberGenerator, spike: float) -> int:
	var roll: float = rng.randf()
	if roll < spike:
		return 2
	return 0 if roll < spike + (1.0 - spike) * 0.5 else 1

## Grupos de rocas grandes (una peña + satélites): en la costa y en las lomas, como en las referencias.
func _add_rock_clusters(rng: RandomNumberGenerator) -> void:
	var clusters: int = 0
	var tries: int = 0
	while clusters < 16 and tries < 400:
		tries += 1
		var coast: bool = clusters < 9
		var c: Vector3 = _random_spot(rng, 0.7 if coast else 3.0, 2.6 if coast else 14.0)
		if c.y < -90.0:
			continue
		if is_in_pond_area(c.x, c.z, 1.6) or is_in_cave_area(c.x, c.z, 1.6) or is_on_path(c.x, c.z, 0.2):
			continue
		var n: int = rng.randi_range(4, 7)
		for i in n:
			var big: bool = i == 0
			var off: Vector2 = Vector2.ZERO if big else Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.5, 6.0)
			var gx: float = c.x + off.x
			var gz: float = c.z + off.y
			var gy: float = height_at(gx, gz)
			if gy < 0.3:
				continue
			var cidx: int = rng.randi_range(1, 5)
			var cvar: int = rng.randi_range(0, 2)
			var r: Node3D = NatureKit.make_stone(cidx, cvar, rng.randi_range(0, 2))
			r.position = Vector3(gx, gy - 0.25, gz)
			r.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))
			var sc: float = rng.randf_range(1.3, 2.1) if big else rng.randf_range(0.4, 1.0)
			r.scale = Vector3(sc * rng.randf_range(0.9, 1.3), sc * rng.randf_range(0.8, 1.2), sc * rng.randf_range(0.9, 1.3)) * 3.0
			if _near_path(gx, gz, minf(sc * 3.0 * 0.6, 4.0)):
				r.free()
				continue
			_flora.add_child(r)
			_add_rock_body(r, 1000 + cidx * 10 + cvar)
		clusters += 1

## Árbol individual (talable): visual, colisión, lianas (solo los vivos) y registro en las listas.
func _add_tree(rng: RandomNumberGenerator, pos: Vector3, kit_name: String, sc: float, tint: Color, shape: Shape3D, vine: Mesh, dead: bool) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * sc
	tree.rotation.y = rng.randf() * TAU
	var visual: Node3D = NatureKit.make_uq(kit_name, tint.lerp(Color.WHITE, 0.5), TREE_VIS) if (kit_name.begins_with("Birch") or kit_name.begins_with("Maple") or kit_name.begins_with("NormalTree") or kit_name.begins_with("PineTree") or dead) else NatureKit.make(kit_name, tint, TREE_VIS)
	tree.add_child(visual)
	_flora.add_child(tree)
	_add_solid(tree, _trunk_shape_for(kit_name, visual, shape), Vector3(0, 1.5, 0))
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
		v.position = Vector3(cos(va) * 0.4, 2.0, sin(va) * 0.4)   # pegadas al tronco (antes colgaban a 0.95 m, en el aire)
		tree.add_child(v)
	tree_nodes.append(tree)
	tree_positions.append(pos)
	tree_scales.append(tree.scale.x)

var _trunk_r_cache: Dictionary = {}
var _trunk_shape_cache: Dictionary = {}
var _rock_hull_cache: Dictionary = {}

## Colisión del tronco según el modelo: radio = 0.45 del ancho medido entre 0.1 y 0.8 m (se escala con el árbol).
func _trunk_shape_for(kit_name: String, visual: Node3D, _fallback: Shape3D) -> Shape3D:
	if not _trunk_r_cache.has(kit_name):
		var pts: PackedVector3Array = _mesh_points(visual)
		var mn: Vector2 = Vector2(1e9, 1e9)
		var mx: Vector2 = Vector2(-1e9, -1e9)
		var any: bool = false
		for q: Vector3 in pts:
			if q.y > 0.1 and q.y < 0.8:
				mn = mn.min(Vector2(q.x, q.z))
				mx = mx.max(Vector2(q.x, q.z))
				any = true
		var r: float = 0.35
		if any:
			r = clampf(0.45 * 0.5 * ((mx.x - mn.x) + (mx.y - mn.y)), 0.3, 1.1)
		_trunk_r_cache[kit_name] = snappedf(r, 0.05)
	var rr: float = _trunk_r_cache[kit_name]
	if not _trunk_shape_cache.has(rr):
		var cyl := CylinderShape3D.new()
		cyl.radius = rr
		cyl.height = 3.0
		_trunk_shape_cache[rr] = cyl
	return _trunk_shape_cache[rr]

## Puntos de todas las mallas de un visual, en coordenadas del visual.
func _mesh_points(v: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var st: Array = [v]
	while st.size() > 0:
		var c: Node = st.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = c as MeshInstance3D
			var xf: Transform3D = mi.transform
			var pp: Node = mi.get_parent()
			while pp != null and pp != v and pp is Node3D:
				xf = (pp as Node3D).transform * xf
				pp = pp.get_parent()
			for si in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				for vv: Vector3 in verts:
					out.append(xf * vv)
		for k in c.get_children():
			st.append(k)
	return out

## Puntos del casco convexo simplificado de cada malla del visual, en coordenadas del visual.
func _hull_points(v: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var st: Array = [v]
	while st.size() > 0:
		var c: Node = st.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = c as MeshInstance3D
			var xf: Transform3D = mi.transform
			var pp: Node = mi.get_parent()
			while pp != null and pp != v and pp is Node3D:
				xf = (pp as Node3D).transform * xf
				pp = pp.get_parent()
			var hs: ConvexPolygonShape3D = mi.mesh.create_convex_shape(true, false)
			if hs != null:
				for q: Vector3 in hs.points:
					out.append(xf * q)
		for k in c.get_children():
			st.append(k)
	return out

## Colisión de roca = casco convexo de su malla real, con la escala de cada roca.
func _add_rock_body(r: Node3D, ridx: int) -> void:
	if Engine.is_editor_hint():
		return
	if not _rock_hull_cache.has(ridx):
		_rock_hull_cache[ridx] = _hull_points(r)
	var base: PackedVector3Array = _rock_hull_cache[ridx]
	var scaled := PackedVector3Array()
	for q: Vector3 in base:
		scaled.append(q * r.scale)
	var sh := ConvexPolygonShape3D.new()
	sh.points = scaled
	var body := StaticBody3D.new()
	body.position = r.position
	body.rotation = r.rotation
	var cs := CollisionShape3D.new()
	cs.shape = sh
	body.add_child(cs)
	_flora.add_child(body)

## ¿Hay camino en (x, z) o a `rad` metros alrededor? Para no poner troncos ni rocas sobre los senderos.
func _near_path(x: float, z: float, rad: float) -> bool:
	if is_on_path(x, z, 0.12):
		return true
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		if is_on_path(x + cos(a) * rad, z + sin(a) * rad, 0.2):
			return true
	return false

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
		var x: float = rng.randf_range(-MAP_HALF.x, MAP_HALF.x)
		var z: float = rng.randf_range(-MAP_HALF.y, MAP_HALF.y)
		var h: float = _height(x, z)
		if is_in_pond_area(x, z, 1.15) or is_in_cave_area(x, z, 1.0) or is_on_path(x, z, 0.25):
			continue
		if h >= min_h and h <= max_h:
			return Vector3(x, h, z)
	return Vector3(0, -100, 0)

# ------------------------------------------------------------------ caminos de tierra

## Valor del camino en (x, z): x = sendero principal, y = sendas chicas (0..1). Sale de un mapa pintado al arrancar.
func path_value(x: float, z: float) -> Vector2:
	if _path_img == null:
		return Vector2.ZERO
	var k: float = float(PATH_SIZE) / (_path_half * 2.0)
	var ix: int = int((x + _path_half) * k)
	var iy: int = int((z + _path_half) * k)
	if ix < 0 or iy < 0 or ix >= PATH_SIZE or iy >= PATH_SIZE:
		return Vector2.ZERO
	var c: Color = _path_img.get_pixel(ix, iy)
	return Vector2(c.r, c.g)

func is_on_path(x: float, z: float, thr: float = 0.25) -> bool:
	var v: Vector2 = path_value(x, z)
	return v.x > thr or v.y * 0.6 > thr

func _path_stamp(img: Image, p: Vector2, width: float, ch: int) -> void:
	var k: float = float(PATH_SIZE) / (_path_half * 2.0)
	var rm: float = width * 0.5 + 0.5
	var rp: int = int(ceil(rm * k))
	var cx: int = int((p.x + _path_half) * k)
	var cy: int = int((p.y + _path_half) * k)
	for dy in range(-rp, rp + 1):
		for dx in range(-rp, rp + 1):
			var ix: int = cx + dx
			var iy: int = cy + dy
			if ix < 0 or iy < 0 or ix >= PATH_SIZE or iy >= PATH_SIZE:
				continue
			var d: float = Vector2(float(dx), float(dy)).length() / k
			var v: float = clampf(1.0 - d / rm, 0.0, 1.0)
			if v <= 0.0:
				continue
			var c: Color = img.get_pixel(ix, iy)
			if ch == 0:
				c.r = maxf(c.r, v)
			elif ch == 2:
				c.b = maxf(c.b, v)
			else:
				c.g = maxf(c.g, v)
			img.set_pixel(ix, iy, c)

## Camina de a hacia b buscando terreno suave (evita agua, acantilados y el estanque) y va dejando huella.
func _path_walk(img: Image, a: Vector2, b: Vector2, rng: RandomNumberGenerator, width: float, ch: int, broken: bool) -> PackedVector2Array:
	var trail: PackedVector2Array = PackedVector2Array([a])
	var pos: Vector2 = a
	var dir: Vector2 = (b - a).normalized()
	var max_steps: int = int(a.distance_to(b) * 0.9) + 40
	var on: bool = true
	var steps: int = 0
	while pos.distance_to(b) > 2.5 and steps < max_steps:
		steps += 1
		var to_b: Vector2 = (b - pos).normalized()
		var base: Vector2 = (to_b * 0.35 + dir * 0.65).normalized()
		var hp: float = _height(pos.x, pos.y)
		var best: Vector2 = base
		var best_cost: float = 1.0e9
		for ang: float in [-0.7, -0.4, -0.2, 0.0, 0.2, 0.4, 0.7]:
			var d: Vector2 = base.rotated(ang)
			var q: Vector2 = pos + d * 2.0
			var h: float = _height(q.x, q.y)
			var cost: float = absf(h - hp) * 3.0 + absf(ang) * 0.6 + rng.randf() * 0.35
			if h < 1.1:
				cost += 6.0
			if _cliff_mask(q.x, q.y) > 0.3:
				cost += 5.0
			if is_in_pond_area(q.x, q.y, 1.0):
				cost += 8.0
			if cost < best_cost:
				best_cost = cost
				best = d
		dir = best
		var prev: Vector2 = pos
		pos += dir * 2.0
		trail.append(pos)
		if broken and rng.randf() < 0.07:
			on = not on
		if on:
			for sub in 5:
				var sp: Vector2 = prev.lerp(pos, float(sub + 1) / 5.0)
				if _height(sp.x, sp.y) > 1.0:
					_path_stamp(img, sp, width, ch)
					if ch == 0:
						_path_stamp(img, sp, width * 0.8, 2)
	return trail

func _build_paths() -> void:
	var half: float = radius * 1.35
	_path_half = half
	path_lines.clear()
	var img := Image.create(PATH_SIZE, PATH_SIZE, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed * 7 + 3
	var nodes: Array[Vector2] = [POND_CENTER, CAVE_CENTER + cave_dir2() * 12.0]
	for c: Vector3 in eco.mystery_centers:
		nodes.append(Vector2(c.x, c.z))
	var beaches: Array[Vector2] = []
	var arrive: Vector2 = Vector2(125.0, 38.0)      # playa de llegada de la barca
	while arrive.x > 0.0 and _height(arrive.x, arrive.y) < 1.1:
		arrive.x -= 1.0
	beaches.append(arrive)
	for i in 40:
		if beaches.size() >= 3:
			break
		var bs: Vector3 = _random_spot(rng, 1.0, 1.5)
		if bs.y < -90.0:
			continue
		var bp := Vector2(bs.x, bs.z)
		var far_ok: bool = true
		for o: Vector2 in beaches:
			if o.distance_to(bp) < 60.0:
				far_ok = false
		if far_ok:
			beaches.append(bp)
	var joined: Array[Vector2] = [nodes[0]]
	var rest: Array[Vector2] = nodes.slice(1)
	while not rest.is_empty():
		var bi: int = 0
		var bj: int = 0
		var bd: float = 1.0e9
		for ii in joined.size():
			for jj in rest.size():
				var dd: float = joined[ii].distance_to(rest[jj])
				if dd < bd:
					bd = dd
					bi = ii
					bj = jj
		var tr1: PackedVector2Array = _path_walk(img, joined[bi], rest[bj], rng, 1.9, 0, false)
		path_lines.append({"pts": tr1, "dest": rest[bj]})
		joined.append(rest[bj])
		rest.remove_at(bj)
	for bp: Vector2 in beaches:
		var near: Vector2 = nodes[0]
		for n: Vector2 in nodes:
			if n.distance_to(bp) < near.distance_to(bp):
				near = n
		var tr2: PackedVector2Array = _path_walk(img, bp, near, rng, 1.9, 0, false)
		path_lines.append({"pts": tr2, "dest": near})
	for i in 2:
		var a: Vector2 = nodes[rng.randi() % nodes.size()]
		var b: Vector2 = nodes[rng.randi() % nodes.size()]
		if a.distance_to(b) > 15.0:
			var tr3: PackedVector2Array = _path_walk(img, a, b, rng, 1.6, 0, false)
			path_lines.append({"pts": tr3, "dest": b})
	for i in 10:
		var st: Vector2 = beaches[rng.randi() % beaches.size()] if not beaches.is_empty() else nodes[0]
		var tg: Vector2 = nodes[rng.randi() % nodes.size()] + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0))
		_path_walk(img, st, tg, rng, 0.6, 1, true)
	_path_img = img
	var mat: ShaderMaterial = material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("path_tex", ImageTexture.create_from_image(img))
		mat.set_shader_parameter("path_origin", Vector2(-half, -half))
		mat.set_shader_parameter("path_size", half * 2.0)

## AO de vértice: compara la altura con el promedio de los vecinos a 2 pasos. Cóncavo (valle, pie de loma) oscurece, convexo aclara apenas.
func _terrain_ao(hg: PackedFloat32Array, gi: int, gj: int) -> float:
	var c: float = hg[gj * (RES + 1) + gi]
	var sum: float = 0.0
	for o: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		sum += hg[clampi(gj + o.y, 0, RES) * (RES + 1) + clampi(gi + o.x, 0, RES)]
	var cav: float = sum * 0.25 - c
	return clampf(1.0 - cav * 0.22, 0.72, 1.04)

## Normal suave de la grilla de alturas en el vértice (gi, gj) por diferencias centrales.
func _grid_normal(hg: PackedFloat32Array, gi: int, gj: int, step: float) -> Vector3:
	var i0: int = maxi(gi - 1, 0)
	var i1: int = mini(gi + 1, RES)
	var j0: int = maxi(gj - 1, 0)
	var j1: int = mini(gj + 1, RES)
	var dx: float = hg[gj * (RES + 1) + i0] - hg[gj * (RES + 1) + i1]
	var dz: float = hg[j0 * (RES + 1) + gi] - hg[j1 * (RES + 1) + gi]
	return Vector3(dx / (float(i1 - i0) * step), 1.0, dz / (float(j1 - j0) * step)).normalized()

var _hg: PackedFloat32Array = PackedFloat32Array()
var _hg_half: float = 0.0
var _hg_step: float = 1.0

## Altura de la malla visible (triangulos de la grilla), no de la funcion exacta: sirve para que el agua encaje con el suelo dibujado.
func mesh_height_at(x: float, z: float) -> float:
	if _hg.is_empty():
		return height_at(x, z)
	var fx: float = (x + _hg_half) / _hg_step
	var fz: float = (z + _hg_half) / _hg_step
	var i: int = clampi(floori(fx), 0, RES - 1)
	var j: int = clampi(floori(fz), 0, RES - 1)
	var u: float = clampf(fx - float(i), 0.0, 1.0)
	var v: float = clampf(fz - float(j), 0.0, 1.0)
	var h00: float = _hg[j * (RES + 1) + i]
	var h10: float = _hg[j * (RES + 1) + i + 1]
	var h01: float = _hg[(j + 1) * (RES + 1) + i]
	var h11: float = _hg[(j + 1) * (RES + 1) + i + 1]
	if (i + j) % 2 == 0:
		# triangulos (0,1,2) y (1,3,2): diagonal de 10 a 01
		if u + v <= 1.0:
			return h00 + (h10 - h00) * u + (h01 - h00) * v
		return h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)
	# triangulos (0,1,3) y (0,3,2): diagonal de 00 a 11
	if u >= v:
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h11 - h01) * u + (h01 - h00) * v
