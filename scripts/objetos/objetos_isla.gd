extends Node3D

## Coloca los objetos decorativos del catálogo (nivel A: estéticos, sin colisión) con la semilla de la vida.
## Zonas: playa, paseo (junto a los caminos) y orilla del estanque. Un MultiMesh por tipo.

var terrain: IslandTerrain

var _rng := RandomNumberGenerator.new()
var _placed: Array[Vector2] = []
var _xf: Dictionary = {}              # id -> Array[Transform3D]

func _ready() -> void:
	if terrain == null:
		return
	_rng.seed = terrain.noise_seed * 29 + 11
	for zona: String in CatalogoObjetos.ZONAS:
		var lista: Dictionary = CatalogoObjetos.ZONAS[zona]
		for id: String in lista:
			var n: int = lista[id]
			for k in n:
				_colocar(zona, id)
	for id: String in _xf:
		var xs: Array = _xf[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ObjetoBuilder.mesh_for(id)
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i] as Transform3D)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = id
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 140.0
		mmi.visibility_range_end_margin = 14.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
	print("Objetos decorativos: %d tipos, %d piezas" % [_xf.size(), _placed.size()])

func _colocar(zona: String, id: String) -> void:
	for t in 60:
		var p: Vector3 = _spot(zona)
		if p.y < -90.0:
			continue
		var xz: Vector2 = Vector2(p.x, p.z)
		var libre: bool = true
		for q: Vector2 in _placed:
			if q.distance_to(xz) < 2.5:
				libre = false
				break
		if not libre or terrain.is_in_cave_area(p.x, p.z, 1.0):
			continue
		_placed.append(xz)
		var it: Dictionary = CatalogoObjetos.ITEMS[id]
		var tilt: float = it["tilt"]
		var b: Basis = Basis(Vector3.UP, _rng.randf() * TAU)
		b = b * Basis(Vector3.RIGHT, _rng.randf_range(-tilt, tilt)) * Basis(Vector3.BACK, _rng.randf_range(-tilt, tilt))
		var sc: float = it["escala"] * _rng.randf_range(0.9, 1.15)
		b = b.scaled(Vector3.ONE * sc)
		var hundir: float = it["hundir"]
		if not _xf.has(id):
			_xf[id] = []
		(_xf[id] as Array).append(Transform3D(b, Vector3(p.x, p.y - hundir, p.z)))
		return

func _spot(zona: String) -> Vector3:
	match zona:
		"playa":
			return terrain.find_spot(_rng, 0.8, 1.5)
		"paseo":
			if terrain.path_lines.is_empty():
				return Vector3(0, -100, 0)
			var line: Dictionary = terrain.path_lines[_rng.randi() % terrain.path_lines.size()]
			var pts: PackedVector2Array = line["pts"]
			if pts.size() < 3:
				return Vector3(0, -100, 0)
			var i: int = _rng.randi_range(1, pts.size() - 2)
			var dir: Vector2 = (pts[i + 1] - pts[i - 1]).normalized()
			var side: Vector2 = Vector2(-dir.y, dir.x) * (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(1.8, 3.6)
			var q: Vector2 = pts[i] + side
			var h: float = terrain.height_at(q.x, q.y)
			if h < 0.8:
				return Vector3(0, -100, 0)
			return Vector3(q.x, h, q.y)
		"estanque":
			var a: float = _rng.randf() * TAU
			var r: float = _rng.randf_range(IslandTerrain.POND_RADIUS * 0.9, IslandTerrain.POND_RADIUS * 1.9)
			var c: Vector2 = IslandTerrain.POND_CENTER + Vector2(cos(a), sin(a)) * r
			var h2: float = terrain.height_at(c.x, c.y)
			if h2 < terrain.pond_water_level + 0.2 or h2 > terrain.pond_water_level + 2.5:
				return Vector3(0, -100, 0)
			return Vector3(c.x, h2, c.y)
	return Vector3(0, -100, 0)
