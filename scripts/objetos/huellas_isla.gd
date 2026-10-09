extends Node3D

## Huellas de otros náufragos (5.6): campamentos viejos, mochilas, cartas, herramientas rotas y marcas en troncos.
## Pocas piezas simples, sin luces ni sombras, repartidas por la isla con semilla fija. Con F cerca se lee un texto corto.

const RADIO: float = 2.4

const TEXTOS: Dictionary = {
	"campamento": [
		"Un círculo de piedras ennegrecidas. Alguien encendió fuego acá, hace mucho. Las cenizas ya son tierra.",
		"Un fogón viejo. Las piedras están acomodadas con cuidado, como si el que las puso esperara quedarse.",
	],
	"mochila": [
		"Una mochila casi enterrada. La tela se deshizo con el sol. Adentro no queda nada que sirva.",
		"Una bolsa de lona, vacía. Tiene un nombre cosido, borrado por la sal.",
	],
	"carta": [
		"Un papel doblado bajo una piedra. La tinta se corrió. Se alcanza a leer: «si alguien lee esto, no pelees con ella».",
		"Una hoja húmeda. Solo se entiende una línea: «me escuchó, pero no me dejó irme».",
	],
	"herramienta": [
		"Un hacha rota. El mango se partió, no la hoja. Alguien la usó con rabia.",
		"Un mango roto y una cabeza oxidada. Las astillas son viejas.",
	],
	"marca": [
		"Un tronco con rayas talladas, de a cinco. Contaron los días hasta que dejaron de contar.",
		"Un poste con marcas en fila. La última está a medias.",
	],
}

var terrain: IslandTerrain
var _rng := RandomNumberGenerator.new()
var _mat_piedra: StandardMaterial3D
var _mat_madera: StandardMaterial3D
var _mat_ceniza: StandardMaterial3D
var _mat_tela: StandardMaterial3D
var _mat_papel: StandardMaterial3D
var _mat_metal: StandardMaterial3D
var _puestas: Array[Vector2] = []

func _ready() -> void:
	if terrain == null:
		return
	_rng.seed = terrain.noise_seed * 37 + 5
	_mat_piedra = _mat(Color(0.45, 0.43, 0.4))
	_mat_madera = _mat(Color(0.3, 0.2, 0.12))
	_mat_ceniza = _mat(Color(0.12, 0.11, 0.1))
	_mat_tela = _mat(Color(0.34, 0.36, 0.24))
	_mat_papel = _mat(Color(0.82, 0.78, 0.66))
	_mat_metal = _mat(Color(0.32, 0.22, 0.16))
	var plan: Array = [
		["campamento", 1.0, 3.0], ["campamento", 3.0, 8.0],
		["mochila", 0.9, 2.0], ["mochila", 2.0, 6.0],
		["carta", 3.0, 10.0], ["carta", 1.2, 4.0],
		["herramienta", 2.0, 8.0],
		["marca", 4.0, 12.0], ["marca", 2.0, 6.0],
	]
	for e: Array in plan:
		_colocar(str(e[0]), float(e[1]), float(e[2]))

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

func _colocar(kind: String, h0: float, h1: float) -> void:
	for t in 80:
		var p: Vector3 = terrain.find_spot(_rng, h0, h1)
		if p.y < -90.0:
			continue
		var xz: Vector2 = Vector2(p.x, p.z)
		if terrain.is_in_cave_area(p.x, p.z, 2.0) or xz.distance_to(IslandTerrain.POND_CENTER) < IslandTerrain.POND_RADIUS + 3.0:
			continue
		var libre: bool = true
		for q: Vector2 in _puestas:
			if q.distance_to(xz) < 14.0:
				libre = false
				break
		for tp: Vector3 in terrain.tree_positions:
			if Vector2(tp.x - p.x, tp.z - p.z).length() < 1.8:
				libre = false
				break
		if not libre:
			continue
		_puestas.append(xz)
		var n := Node3D.new()
		n.name = "Huella_" + kind
		n.position = p
		n.rotation.y = _rng.randf() * TAU
		n.set_meta("textos", TEXTOS[kind])
		n.add_to_group("huella")
		add_child(n)
		call("_armar_" + kind, n)
		return

func _pieza(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _caja(v: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = v
	return b

func _cil(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	return c

func _armar_campamento(n: Node3D) -> void:
	_pieza(n, _cil(0.45, 0.03), _mat_ceniza, Vector3(0, 0.02, 0))
	for i in 7:
		var a: float = TAU * float(i) / 7.0
		var s := SphereMesh.new()
		s.radius = 0.13
		s.height = 0.2
		s.radial_segments = 5
		s.rings = 3
		_pieza(n, s, _mat_piedra, Vector3(cos(a) * 0.62, 0.07, sin(a) * 0.62))
	_pieza(n, _cil(0.07, 1.1), _mat_madera, Vector3(1.3, 0.1, 0.4), Vector3(0, 0.6, PI / 2.0))
	_pieza(n, _cil(0.06, 0.9), _mat_madera, Vector3(-1.2, 0.09, -0.5), Vector3(0, -0.4, PI / 2.0))

func _armar_mochila(n: Node3D) -> void:
	_pieza(n, _caja(Vector3(0.5, 0.3, 0.28)), _mat_tela, Vector3(0, 0.1, 0), Vector3(0.1, 0.2, 0.18))
	_pieza(n, _caja(Vector3(0.46, 0.06, 0.3)), _mat_madera, Vector3(0, 0.26, 0.02), Vector3(0.1, 0.2, 0.18))

func _armar_carta(n: Node3D) -> void:
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.22
	s.radial_segments = 5
	s.rings = 3
	_pieza(n, _caja(Vector3(0.32, 0.012, 0.22)), _mat_papel, Vector3(0, 0.02, 0), Vector3(0, 0.3, 0.05))
	_pieza(n, s, _mat_piedra, Vector3(0.24, 0.07, 0.05))

func _armar_herramienta(n: Node3D) -> void:
	_pieza(n, _cil(0.03, 0.85), _mat_madera, Vector3(0, 0.05, 0), Vector3(0, 0.5, PI / 2.0 - 0.1))
	_pieza(n, _caja(Vector3(0.26, 0.1, 0.05)), _mat_metal, Vector3(0.75, 0.05, 0.35), Vector3(0, 0.9, 0.1))
	_pieza(n, _cil(0.03, 0.3), _mat_madera, Vector3(-0.7, 0.04, -0.3), Vector3(0, 0.2, PI / 2.0))

func _armar_marca(n: Node3D) -> void:
	_pieza(n, _cil(0.09, 1.3), _mat_madera, Vector3(0, 0.6, 0), Vector3(0.06, 0, 0.04))
	for i in 5:
		_pieza(n, _caja(Vector3(0.14, 0.012, 0.012)), _mat_papel, Vector3(0, 0.55 + float(i) * 0.09, 0.09))
