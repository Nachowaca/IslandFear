class_name ObjetoBuilder
extends RefCounted

## Arma los objetos estéticos de la isla con formas simples de pocos polígonos y color por vértice
## (un solo material compartido). Cada id produce UNA malla con el origen en el piso, lista para MultiMesh.

static var _cache: Dictionary = {}
static var _mat: StandardMaterial3D

static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.9
	return _mat

static func mesh_for(id: String) -> ArrayMesh:
	if _cache.has(id):
		return _cache[id] as ArrayMesh
	var acc: Dictionary = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
	match id:
		"calavera": _calavera(acc)
		"cruz": _cruz(acc)
		"ojos": _ojos(acc)
		"cofre": _cofre(acc)
		"lata": _lata(acc)
		"botella_verde": _botella(acc, Color(0.2, 0.52, 0.32))
		"botella_ambar": _botella(acc, Color(0.62, 0.35, 0.1))
		"caracola": _caracola(acc)
		"estrella": _estrella(acc)
		"ancla": _ancla(acc)
		"tablones": _tablones(acc)
		"barril": _barril(acc)
		"remo": _remo(acc)
		"cairn": _cairn(acc)
		"fogata_apagada": _fogata(acc)
		"huesos": _huesos(acc)
		"cuerda": _cuerda(acc)
		_: _sph(acc, Vector3(0.3, 0.3, 0.3), Vector3(0, 0.15, 0), Vector3.ZERO, Color(1, 0, 1))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = acc["v"]
	arr[Mesh.ARRAY_NORMAL] = acc["n"]
	arr[Mesh.ARRAY_COLOR] = acc["c"]
	arr[Mesh.ARRAY_INDEX] = acc["i"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, material())
	_cache[id] = am
	return am

# ------------------------------------------------------------------ primitivas

static func _add(acc: Dictionary, m: Mesh, pos: Vector3, rot: Vector3, scl: Vector3, col: Color) -> void:
	var b: Basis = Basis.from_euler(rot) * Basis.from_scale(scl)
	var nb: Basis = b.inverse().transposed()
	var arr: Array = m.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var av: PackedVector3Array = acc["v"]
	var an: PackedVector3Array = acc["n"]
	var ac: PackedColorArray = acc["c"]
	var ai: PackedInt32Array = acc["i"]
	var off: int = av.size()
	for k in vs.size():
		av.append(b * vs[k] + pos)
		an.append((nb * ns[k]).normalized())
		ac.append(col)
	for k in ix.size():
		ai.append(ix[k] + off)
	acc["v"] = av
	acc["n"] = an
	acc["c"] = ac
	acc["i"] = ai

static func _box(acc: Dictionary, size: Vector3, pos: Vector3, rot: Vector3, col: Color) -> void:
	var m := BoxMesh.new()
	m.size = size
	_add(acc, m, pos, rot, Vector3.ONE, col)

static func _cyl(acc: Dictionary, r_top: float, r_bot: float, h: float, pos: Vector3, rot: Vector3, col: Color, seg: int = 7) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	_add(acc, m, pos, rot, Vector3.ONE, col)

static func _sph(acc: Dictionary, diam: Vector3, pos: Vector3, rot: Vector3, col: Color, seg: int = 8, rings: int = 4) -> void:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = seg
	m.rings = rings
	_add(acc, m, pos, rot, diam, col)

static func _torus(acc: Dictionary, inner: float, outer: float, pos: Vector3, rot: Vector3, col: Color) -> void:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 10
	m.ring_segments = 5
	_add(acc, m, pos, rot, Vector3.ONE, col)

# ------------------------------------------------------------------ piezas

static func _calavera(acc: Dictionary) -> void:
	var bone: Color = Color(0.88, 0.85, 0.74)
	var dark: Color = Color(0.08, 0.07, 0.06)
	_sph(acc, Vector3(0.26, 0.24, 0.28), Vector3(0, 0.13, 0), Vector3.ZERO, bone)
	_box(acc, Vector3(0.15, 0.06, 0.13), Vector3(0, 0.03, 0.07), Vector3.ZERO, bone * 0.92)
	_sph(acc, Vector3(0.07, 0.08, 0.05), Vector3(-0.055, 0.14, 0.125), Vector3.ZERO, dark, 6, 3)
	_sph(acc, Vector3(0.07, 0.08, 0.05), Vector3(0.055, 0.14, 0.125), Vector3.ZERO, dark, 6, 3)
	_box(acc, Vector3(0.025, 0.04, 0.03), Vector3(0, 0.08, 0.14), Vector3.ZERO, dark)

static func _cruz(acc: Dictionary) -> void:
	var wood: Color = Color(0.34, 0.28, 0.21)
	_cyl(acc, 0.07, 0.1, 1.9, Vector3(0, 0.95, 0), Vector3.ZERO, wood, 6)
	_cyl(acc, 0.06, 0.06, 1.1, Vector3(0, 1.45, 0), Vector3(0, 0, PI * 0.5), wood * 0.9, 6)

static func _ojos(acc: Dictionary) -> void:
	_sph(acc, Vector3(0.9, 0.7, 0.75), Vector3(0, 0.33, 0), Vector3.ZERO, Color(0.55, 0.17, 0.13), 8, 5)
	for sx: float in [-1.0, 1.0]:
		_sph(acc, Vector3(0.2, 0.13, 0.06), Vector3(sx * 0.2, 0.42, 0.31), Vector3(0, sx * 0.5, 0), Color(0.95, 0.93, 0.85), 8, 3)
		_sph(acc, Vector3(0.07, 0.07, 0.05), Vector3(sx * 0.2 - sx * 0.01, 0.42, 0.335), Vector3(0, sx * 0.5, 0), Color(0.05, 0.04, 0.04), 6, 3)

static func _cofre(acc: Dictionary) -> void:
	var wood: Color = Color(0.24, 0.13, 0.07)
	var iron: Color = Color(0.2, 0.2, 0.21)
	_box(acc, Vector3(0.9, 0.42, 0.55), Vector3(0, 0.21, 0), Vector3.ZERO, wood)
	_cyl(acc, 0.275, 0.275, 0.9, Vector3(0, 0.42, 0), Vector3(0, 0, PI * 0.5), wood * 1.15, 8)
	for sx: float in [-0.28, 0.28]:
		_box(acc, Vector3(0.06, 0.44, 0.58), Vector3(sx, 0.22, 0), Vector3.ZERO, iron)
		_cyl(acc, 0.285, 0.285, 0.06, Vector3(sx, 0.42, 0), Vector3(0, 0, PI * 0.5), iron, 8)
	_box(acc, Vector3(0.1, 0.12, 0.04), Vector3(0, 0.4, 0.29), Vector3.ZERO, Color(0.85, 0.65, 0.2))

static func _lata(acc: Dictionary) -> void:
	_cyl(acc, 0.045, 0.045, 0.12, Vector3(0, 0.045, 0), Vector3(0, 0, PI * 0.5), Color(0.72, 0.72, 0.74), 8)
	_cyl(acc, 0.038, 0.038, 0.012, Vector3(0.058, 0.045, 0), Vector3(0, 0, PI * 0.5), Color(0.18, 0.13, 0.09), 8)
	_box(acc, Vector3(0.004, 0.05, 0.035), Vector3(0.06, 0.07, 0.035), Vector3(0.5, 0, 0.3), Color(0.8, 0.8, 0.82))

static func _botella(acc: Dictionary, col: Color) -> void:
	_cyl(acc, 0.04, 0.04, 0.17, Vector3(0, 0.04, 0), Vector3(0, 0, PI * 0.5), col, 7)
	_cyl(acc, 0.016, 0.03, 0.1, Vector3(0.135, 0.04, 0), Vector3(0, 0, -PI * 0.5), col, 7)
	_cyl(acc, 0.015, 0.015, 0.02, Vector3(0.195, 0.04, 0), Vector3(0, 0, PI * 0.5), Color(0.7, 0.6, 0.4), 6)

static func _caracola(acc: Dictionary) -> void:
	_sph(acc, Vector3(0.1, 0.08, 0.1), Vector3(0, 0.04, 0), Vector3.ZERO, Color(0.95, 0.78, 0.7))
	_cyl(acc, 0.0, 0.045, 0.11, Vector3(0, 0.05, 0.08), Vector3(PI * 0.5, 0, 0), Color(0.93, 0.85, 0.78), 6)

static func _estrella(acc: Dictionary) -> void:
	var col: Color = Color(0.9, 0.4, 0.2)
	for k in 5:
		var a: float = float(k) / 5.0 * TAU
		_box(acc, Vector3(0.035, 0.02, 0.11), Vector3(sin(a) * 0.055, 0.01, cos(a) * 0.055), Vector3(0, a, 0), col)
	_sph(acc, Vector3(0.07, 0.03, 0.07), Vector3(0, 0.015, 0), Vector3.ZERO, col * 1.1, 6, 3)

static func _ancla(acc: Dictionary) -> void:
	var rust: Color = Color(0.42, 0.24, 0.13)
	_box(acc, Vector3(0.08, 0.9, 0.08), Vector3(0, 0.45, 0), Vector3.ZERO, rust)
	_torus(acc, 0.05, 0.11, Vector3(0, 0.97, 0), Vector3(PI * 0.5, 0, 0), rust)
	_box(acc, Vector3(0.55, 0.07, 0.07), Vector3(0, 0.78, 0), Vector3.ZERO, rust * 0.9)
	_box(acc, Vector3(0.4, 0.07, 0.07), Vector3(-0.17, 0.1, 0), Vector3(0, 0, 0.55), rust)
	_box(acc, Vector3(0.4, 0.07, 0.07), Vector3(0.17, 0.1, 0), Vector3(0, 0, -0.55), rust)

static func _tablones(acc: Dictionary) -> void:
	var w: Color = Color(0.45, 0.34, 0.24)
	_box(acc, Vector3(1.4, 0.04, 0.16), Vector3(0, 0.03, 0), Vector3(0, 0.0, 0.02), w)
	_box(acc, Vector3(1.1, 0.04, 0.18), Vector3(0.1, 0.04, 0.2), Vector3(0, 0.15, 0.0), w * 0.85)
	_box(acc, Vector3(1.6, 0.04, 0.15), Vector3(-0.1, 0.05, -0.19), Vector3(0, -0.1, 0.04), w * 1.1)
	_box(acc, Vector3(0.14, 0.04, 0.6), Vector3(0.35, 0.09, 0.0), Vector3(0, 0.05, 0), w * 0.7)

static func _barril(acc: Dictionary) -> void:
	var wood: Color = Color(0.4, 0.26, 0.14)
	_cyl(acc, 0.28, 0.28, 0.7, Vector3(0, 0.28, 0), Vector3(0, 0, PI * 0.5), wood, 8)
	for sx: float in [-0.22, 0.22]:
		_cyl(acc, 0.3, 0.3, 0.04, Vector3(sx, 0.28, 0), Vector3(0, 0, PI * 0.5), Color(0.2, 0.2, 0.21), 8)

static func _remo(acc: Dictionary) -> void:
	var w: Color = Color(0.5, 0.38, 0.25)
	_cyl(acc, 0.03, 0.03, 1.6, Vector3(0, 0.8, 0), Vector3.ZERO, w, 6)
	_box(acc, Vector3(0.18, 0.5, 0.03), Vector3(0, 1.45, 0), Vector3.ZERO, w * 1.1)

static func _cairn(acc: Dictionary) -> void:
	_sph(acc, Vector3(0.5, 0.28, 0.45), Vector3(0, 0.13, 0), Vector3.ZERO, Color(0.52, 0.52, 0.54), 7)
	_sph(acc, Vector3(0.38, 0.22, 0.34), Vector3(0.02, 0.35, 0), Vector3(0, 0.6, 0), Color(0.6, 0.6, 0.62), 7)
	_sph(acc, Vector3(0.27, 0.18, 0.24), Vector3(-0.02, 0.52, 0.01), Vector3(0, 1.2, 0), Color(0.5, 0.5, 0.53), 7)
	_sph(acc, Vector3(0.15, 0.12, 0.14), Vector3(0, 0.65, 0), Vector3.ZERO, Color(0.64, 0.64, 0.66), 6)

static func _fogata(acc: Dictionary) -> void:
	_cyl(acc, 0.3, 0.3, 0.01, Vector3(0, 0.005, 0), Vector3.ZERO, Color(0.2, 0.2, 0.21), 9)
	for k in 8:
		var a: float = float(k) / 8.0 * TAU
		_sph(acc, Vector3(0.18, 0.12, 0.16), Vector3(sin(a) * 0.36, 0.06, cos(a) * 0.36), Vector3(0, a, 0), Color(0.36, 0.36, 0.38), 6, 3)
	for k in 4:
		var a2: float = float(k) / 4.0 * TAU + 0.4
		_cyl(acc, 0.03, 0.03, 0.4, Vector3(sin(a2) * 0.05, 0.04, cos(a2) * 0.05), Vector3(PI * 0.5, 0, a2), Color(0.08, 0.07, 0.06), 5)

static func _huesos(acc: Dictionary) -> void:
	var b: Color = Color(0.85, 0.82, 0.7)
	for k in 2:
		var a: float = 0.5 + float(k) * 1.3
		_cyl(acc, 0.02, 0.02, 0.32, Vector3(0, 0.03, 0), Vector3(PI * 0.5, 0, a), b, 5)
		for s: float in [-1.0, 1.0]:
			_sph(acc, Vector3(0.05, 0.05, 0.05), Vector3(sin(a) * s * 0.16, 0.03, cos(a) * s * 0.16), Vector3.ZERO, b, 5, 3)

static func _cuerda(acc: Dictionary) -> void:
	var r: Color = Color(0.72, 0.6, 0.38)
	_torus(acc, 0.13, 0.22, Vector3(0, 0.04, 0), Vector3.ZERO, r)
	_torus(acc, 0.12, 0.2, Vector3(0, 0.1, 0), Vector3.ZERO, r * 0.92)
