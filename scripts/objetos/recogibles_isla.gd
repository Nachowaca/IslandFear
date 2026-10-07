extends Node3D

## Reparte los recogibles (bloque 4.5) con la semilla de la vida, POR ZONA: playa, playa alta, caminos, estanque, cueva, bosque.
## Son WorldItem (grupo "pickup"). Cada uno lleva un destello visible de lejos (son chicos y el pasto los tapa).

var terrain: IslandTerrain

var _rng := RandomNumberGenerator.new()
var _puestos: Array[Vector2] = []
var _glint_mesh: QuadMesh
var _glint_mat: StandardMaterial3D
var _glint_mat_sucio: StandardMaterial3D

# id -> [[zona, cantidad], ...]
const REPARTO: Dictionary = {
	"linterna": [["playa_alta", 1]],
	"bateria": [["paseo", 3], ["bosque", 3], ["cueva", 1], ["playa_alta", 1]],
	"semilla_azul": [["bosque", 3], ["estanque", 2], ["cueva", 1]],
	"botella_vacia": [["playa", 3], ["estanque", 1]],
	"tela_grande": [["playa", 1], ["paseo", 1], ["bosque", 1]],
	"tela_chica": [["playa", 1], ["paseo", 2], ["bosque", 2]],
	"resina": [["bosque", 4], ["paseo", 1]],
	"espina": [["playa_alta", 2], ["bosque", 2]],
	"pala_concha": [["playa", 1]],
	"sal": [["orilla", 4]],
	"caracola": [["playa", 3]],
	"perla": [["orilla", 1], ["estanque", 1]],
	"vidrio_marino": [["playa", 4], ["estanque", 1]],
	"pluma": [["bosque", 3], ["paseo", 2]],
	"cristal_cueva": [["cueva", 4]],
	"flor_luminosa": [["estanque", 3], ["bosque", 2]],
	"moneda_pirata": [["playa", 2], ["cueva", 1]],
	"lata_oxidada": [["paseo", 2], ["playa", 1]],
	"botella_plastico": [["playa", 5]],
	"bolsa_plastico": [["playa", 2], ["bosque", 2]],
	"red_enredada": [["orilla", 2]],
	"bateria_gastada": [["paseo", 1], ["playa", 1]],
}

func _ready() -> void:
	if terrain == null:
		return
	_rng.seed = terrain.noise_seed * 41 + 7
	_glint_mesh = QuadMesh.new()
	_glint_mesh.size = Vector2(0.32, 0.32)
	_glint_mat = _crear_mat(Color(1.0, 0.92, 0.6, 0.85))
	_glint_mat_sucio = _crear_mat(Color(0.6, 0.65, 0.6, 0.6))
	var total: int = 0
	var por_zona: Dictionary = {}
	for id: String in REPARTO:
		for par: Array in REPARTO[id]:
			var zona: String = par[0]
			for k in int(par[1]):
				if _colocar(id, zona):
					total += 1
					por_zona[zona] = int(por_zona.get(zona, 0)) + 1
	print("Recogibles: %d %s" % [total, str(por_zona)])

## Qué ítems guía la luciérnaga: "util" (linterna, baterías, botella, semilla, telas grandes, contaminantes) y "ofrenda" (luz azul).
## No guía comida ni materiales para fabricar (resina, espina, sal, tela chica).
func _guia(id: String) -> String:
	var d: Dictionary = ItemDB.get_def(id)
	if bool(d.get("food", false)):
		return ""
	if bool(d.get("offering", false)):
		return "ofrenda"
	if id in ["linterna", "bateria", "botella_vacia", "semilla_azul", "tela_grande", "pala_concha"] or bool(d.get("contaminante", false)):
		return "util"
	return ""

func _crear_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _glint_tex()
	m.albedo_color = c
	return m

func _glint_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

func _spot(zona: String) -> Vector3:
	match zona:
		"playa":
			return terrain.find_spot(_rng, 0.75, 1.4)
		"orilla":
			return terrain.find_spot(_rng, 0.55, 0.95)
		"playa_alta":
			return terrain.find_spot(_rng, 1.2, 2.8)
		"bosque":
			return terrain.find_spot(_rng, 2.0, 9.0)
		"paseo":
			if terrain.path_lines.is_empty():
				return Vector3(0, -100, 0)
			var line: Dictionary = terrain.path_lines[_rng.randi() % terrain.path_lines.size()]
			var pts: PackedVector2Array = line["pts"]
			if pts.size() < 3:
				return Vector3(0, -100, 0)
			var i: int = _rng.randi_range(1, pts.size() - 2)
			var dir: Vector2 = (pts[i + 1] - pts[i - 1]).normalized()
			var side: Vector2 = Vector2(-dir.y, dir.x) * (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.9, 2.2)
			var q: Vector2 = pts[i] + side
			var h: float = terrain.height_at(q.x, q.y)
			if h < 0.8:
				return Vector3(0, -100, 0)
			return Vector3(q.x, h, q.y)
		"estanque":
			var a: float = _rng.randf() * TAU
			var r: float = _rng.randf_range(IslandTerrain.POND_RADIUS * 1.0, IslandTerrain.POND_RADIUS * 1.8)
			var c: Vector2 = IslandTerrain.POND_CENTER + Vector2(cos(a), sin(a)) * r
			var h2: float = terrain.height_at(c.x, c.y)
			if h2 < terrain.pond_water_level + 0.15 or h2 > terrain.pond_water_level + 2.5:
				return Vector3(0, -100, 0)
			return Vector3(c.x, h2, c.y)
		"cueva":
			var a2: float = _rng.randf() * TAU
			var r2: float = _rng.randf_range(1.0, 3.2)
			var c2: Vector2 = IslandTerrain.CAVE_CENTER + Vector2(cos(a2), sin(a2)) * r2
			return Vector3(c2.x, terrain.height_at(c2.x, c2.y), c2.y)
	return Vector3(0, -100, 0)

func _colocar(id: String, zona: String) -> bool:
	var sep: float = 1.2 if zona == "cueva" else 2.5
	for t in 80:
		var p: Vector3 = _spot(zona)
		if p.y < -90.0:
			continue
		var xz: Vector2 = Vector2(p.x, p.z)
		var libre: bool = true
		for q: Vector2 in _puestos:
			if q.distance_to(xz) < sep:
				libre = false
				break
		if not libre:
			continue
		if zona != "cueva" and terrain.is_in_cave_area(p.x, p.z, 1.0):
			continue
		_puestos.append(xz)
		var it := WorldItem.new()
		it.name = id.capitalize().replace(" ", "")
		it.item_id = id
		it.display_name = ItemDB.display_name(id)
		it.amount = 1
		it.position = p
		it.rotation.y = _rng.randf() * TAU
		add_child(it)
		var vis: Node3D = ItemDB.make_visual(id)
		vis.scale = Vector3.ONE * 1.5
		it.add_child(vis)
		var guia: String = _guia(id)
		if guia != "":
			it.set_meta("guia", guia)
		return true
	return false
