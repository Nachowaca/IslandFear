class_name Bridge
extends Node3D

## Puente de madera desde la costa hasta el islote del faro. Está ROTO: falta un tramo en el medio
## (con tablones colgando y sogas sueltas). Se construye en coordenadas locales: avanza hacia -Z.
## Uso: crear, asignar propiedades, `position` = inicio y `rotation.y`, añadir al árbol y llamar build().

const PLANK_L := 0.9
const WIDTH := 2.2
const DECK_T := 0.12

var length: float = 40.0
var y_start: float = 1.1
var y_end: float = 1.9
var gap_start: float = 18.0
var gap_len: float = 5.5
var water_y: float = 0.35

var _mats: Array[StandardMaterial3D] = []
var _dark: StandardMaterial3D
var _rope: StandardMaterial3D
var _rng := RandomNumberGenerator.new()

func _deck_y(s: float) -> float:
	return lerpf(y_start, y_end, clampf(s / length, 0.0, 1.0))

func _pitch() -> float:
	return atan2(y_end - y_start, length)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

func _in_gap(s: float, margin: float = 0.0) -> bool:
	return s > gap_start - margin and s < gap_start + gap_len + margin

func build() -> void:
	_rng.seed = 4242
	for c: Color in [Color(0.46, 0.33, 0.2), Color(0.4, 0.29, 0.18), Color(0.52, 0.4, 0.26), Color(0.36, 0.27, 0.18)]:
		_mats.append(_mat(c))
	_dark = _mat(Color(0.25, 0.18, 0.12))
	_rope = _mat(Color(0.62, 0.52, 0.34))
	_build_planks()
	_build_supports()
	_build_rails()
	_build_debris()
	_build_collision()

func _put(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

## Cilindro entre dos puntos locales.
func _between(a: Vector3, b: Vector3, r: float, mat: Material, seg: int = 5) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = a.distance_to(b)
	c.radial_segments = seg
	c.rings = 1
	var mi := _put(c, mat, (a + b) * 0.5)
	mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))

func _build_planks() -> void:
	var plank: BoxMesh = _box(Vector3(WIDTH, DECK_T, PLANK_L - 0.07))
	var n: int = int(length / PLANK_L)
	var pitch: float = _pitch()
	for i in n:
		var s: float = (i + 0.5) * PLANK_L
		if _in_gap(s, -0.01):
			continue
		var m: StandardMaterial3D = _mats[_rng.randi() % _mats.size()]
		var wob: Vector3 = Vector3(_rng.randf_range(-0.01, 0.01), _rng.randf_range(-0.02, 0.02), _rng.randf_range(-0.01, 0.01))
		_put(plank, m, Vector3(0, _deck_y(s) - DECK_T * 0.5, -s), Vector3(pitch, 0, 0) + wob)

func _build_supports() -> void:
	# vigas largas bajo el tablado (una a cada lado), una por tramo
	var sections: Array = [[0.0, gap_start], [gap_start + gap_len, length]]
	for sec: Array in sections:
		var a: float = sec[0]
		var b: float = sec[1]
		for sx: float in [-0.8, 0.8]:
			_between(Vector3(sx, _deck_y(a) - 0.2, -a), Vector3(sx, _deck_y(b) - 0.2, -b), 0.1, _dark, 4)
	# pilotes hundidos en el fondo
	var s: float = 3.0
	while s < length - 1.0:
		for sx: float in [-1.0, 1.0]:
			var top: float = _deck_y(s) - 0.15
			if _in_gap(s, 1.2):
				# pilotes rotos: solo el tocón sobre el agua, algo inclinado
				if absf(s - gap_start) < 1.6 or absf(s - (gap_start + gap_len)) < 1.6:
					var stump_h: float = water_y + 0.5 - (-3.5)
					var st := _put(_cyl(0.17, stump_h), _dark, Vector3(sx * 1.0, -3.5 + stump_h * 0.5, -s), Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15)))
					st.name = "Stump"
				continue
			var h: float = top - (-3.5)
			_put(_cyl(0.17, h), _dark, Vector3(sx, -3.5 + h * 0.5, -s))
		s += 4.4

func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r * 0.9
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	return c

func _build_rails() -> void:
	var post_step: float = 3.0
	var posts: Array[float] = []
	var s: float = 0.0
	while s <= length:
		if not _in_gap(s, 0.2):
			posts.append(s)
		s += post_step
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * (WIDTH * 0.5 + 0.02)
		var prev: Vector3 = Vector3.INF
		var prev_s: float = -100.0
		for ps: float in posts:
			var base: Vector3 = Vector3(x, _deck_y(ps), -ps)
			_put(_cyl(0.07, 1.25), _dark, base + Vector3(0, 0.55, 0))
			var top: Vector3 = base + Vector3(0, 1.0, 0)
			if prev != Vector3.INF and not _in_gap((prev_s + ps) * 0.5, 0.0) and ps - prev_s < post_step + 0.1:
				var mid: Vector3 = (prev + top) * 0.5 + Vector3(0, -0.1, 0)   # la soga cuelga un poco
				_between(prev, mid, 0.025, _rope, 4)
				_between(mid, top, 0.025, _rope, 4)
				_between(prev - Vector3(0, 0.45, 0), top - Vector3(0, 0.55, 0), 0.02, _rope, 4)
			prev = top
			prev_s = ps
			# la soga cortada: cuelga del último poste antes del hueco y del primero después
			if absf(ps - (gap_start - 0.4)) < post_step * 0.6 and ps < gap_start:
				_between(top, top + Vector3(0.0, -0.9, -0.7), 0.025, _rope, 4)
			if absf(ps - (gap_start + gap_len + 0.4)) < post_step * 0.6 and ps > gap_start + gap_len:
				_between(top, top + Vector3(0.0, -1.0, 0.6), 0.025, _rope, 4)

## Tablones que cuelgan al borde del hueco y restos flotando.
func _build_debris() -> void:
	var plank: BoxMesh = _box(Vector3(WIDTH * 0.92, DECK_T, PLANK_L - 0.07))
	var L: float = PLANK_L - 0.07
	var a1: float = -1.15
	_put(plank, _mats[1], Vector3(0.0, _deck_y(gap_start) - DECK_T * 0.5 + sin(a1) * L * 0.5, -gap_start - cos(a1) * L * 0.5), Vector3(a1, 0, 0.05))
	var a2: float = 1.35
	var s2: float = gap_start + gap_len
	_put(plank, _mats[3], Vector3(0.1, _deck_y(s2) - DECK_T * 0.5 - sin(a2) * L * 0.5, -s2 + cos(a2) * L * 0.5), Vector3(a2, 0, -0.08))
	# tablones sueltos flotando en el agua bajo el hueco
	for i in 4:
		var s: float = gap_start + _rng.randf_range(0.5, gap_len - 0.5)
		var f := _put(plank, _mats[_rng.randi() % 4], Vector3(_rng.randf_range(-1.5, 1.5), water_y + 0.02, -s), Vector3(0, _rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.06, 0.06)))
		f.name = "Floating%d" % i
		f.scale = Vector3(0.45 + _rng.randf() * 0.3, 1.0, 1.0)

func _build_collision() -> void:
	var pitch: float = _pitch()
	var sections: Array = [[0.0, gap_start], [gap_start + gap_len, length]]
	var body := StaticBody3D.new()
	body.name = "DeckBody"
	for sec: Array in sections:
		var a: float = sec[0]
		var b: float = sec[1]
		var run: float = b - a
		if run <= 0.1:
			continue
		var mid: float = (a + b) * 0.5
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(WIDTH, DECK_T + 0.1, run / cos(pitch))
		cs.shape = bs
		cs.position = Vector3(0, _deck_y(mid) - DECK_T * 0.5 - 0.05, -mid)
		cs.rotation = Vector3(pitch, 0, 0)
		body.add_child(cs)
	# barandas invisibles para no caerse sin querer (solo en los tramos enteros)
	for sec2: Array in sections:
		var a2: float = sec2[0]
		var b2: float = sec2[1]
		var run2: float = b2 - a2
		if run2 <= 0.1:
			continue
		for sx: float in [-1.0, 1.0]:
			var cr := CollisionShape3D.new()
			var rs := BoxShape3D.new()
			rs.size = Vector3(0.12, 1.1, run2)
			cr.shape = rs
			var m2: float = (a2 + b2) * 0.5
			cr.position = Vector3(sx * (WIDTH * 0.5 + 0.02), _deck_y(m2) + 0.55, -m2)
			cr.rotation = Vector3(pitch, 0, 0)
			body.add_child(cr)
	add_child(body)

## Posición global del hueco (para pistas o para reparar el puente más adelante).
func gap_center_global() -> Vector3:
	return to_global(Vector3(0, _deck_y(gap_start + gap_len * 0.5), -(gap_start + gap_len * 0.5)))
