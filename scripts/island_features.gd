class_name IslandFeatures
extends Node3D

## Puntos de interés de la isla, todo low-poly con colisión:
##  - Cueva misteriosa (refugio de día, trampa de noche)
##  - Restos de un naufragio en la playa
##  - Círculo de piedras antiguas ("corazón" de la isla)
##  - Árbol ancestral
##  - Montículos de piedra y círculos de hongos brillantes
## Los "lugares sagrados" se registran en `sacred_spots` para que la mente de la isla los proteja.

var terrain: IslandTerrain

var sacred_spots: Array[Dictionary] = []     # {name, pos, radius, kind}
var cave_center: Vector3
var cave_dir: Vector3 = Vector3.RIGHT        # hacia dónde mira la entrada
var cave_entrance: Vector3
const CAVE_INNER_R: float = 3.5
const CAVE_RING_R: float = 5.4

var _rng := RandomNumberGenerator.new()
var _mats: Dictionary = {}
var _crystal_mats: Array[StandardMaterial3D] = []
var _cave_light: OmniLight3D
var _ominous: float = 0.0
var _warm: float = 0.0            ## 0 = fría, 1 = cálida (la isla confía en el jugador)

## La isla expresa su vínculo con el jugador a través del brillo de la cueva.
func set_cave_warmth(w: float) -> void:
	_warm = clampf(w, 0.0, 1.0)
var _seal_body: StaticBody3D
var _seal_mesh: MeshInstance3D
var _seal_shape: CollisionShape3D
var _sealed: bool = false
var _heart_mat: StandardMaterial3D
var _heart_light: OmniLight3D
var _shroom_mats: Array[StandardMaterial3D] = []
var _night: float = 0.0
var _time: float = 0.0
var heart_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	_rng.seed = 4242
	_build_cave()
	_build_standing_stones()
	_build_giant_tree()
	_build_shipwreck()
	_build_cairns()
	_build_mushroom_rings()

# ------------------------------------------------------------------ helpers

func _mat(c: Color) -> StandardMaterial3D:
	var key: String = c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		_mats[key] = m
	return _mats[key]

func _sph(r: float, seg: int = 7, rings: int = 4) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m

func _cyl(rt: float, rb: float, h: float, seg: int = 7) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	return c

func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

## Cuerpo estático con una forma uniforme (esfera / caja / cilindro)
func _solid(shape: Shape3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = rot
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body

func _sphere_shape(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s

func _boulder(pos: Vector3, r: float, mat: Material, squash: float = 0.85) -> void:
	var yaw: float = _rng.randf() * TAU
	_mi(self, _sph(r, 7, 4), mat, pos, Vector3(_rng.randf_range(-0.25, 0.25), yaw, _rng.randf_range(-0.25, 0.25)), Vector3(1.0, squash, 1.0 + _rng.randf_range(-0.12, 0.12)))
	_solid(_sphere_shape(r * 0.92), pos)

func _spot(min_h: float, max_h: float, min_origin: float = 0.0, max_origin: float = 1000.0, away_from: Vector3 = Vector3.ZERO, away_dist: float = 0.0) -> Vector3:
	for i in 80:
		var p: Vector3 = terrain.find_spot(_rng, min_h, max_h)
		if p.y < -90.0:
			continue
		var d: float = Vector2(p.x, p.z).length()
		if d < min_origin or d > max_origin:
			continue
		if away_dist > 0.0 and Vector2(p.x, p.z).distance_to(Vector2(away_from.x, away_from.z)) < away_dist:
			continue
		return p
	return Vector3(0, -100, 0)

# ------------------------------------------------------------------ cueva

func _build_cave() -> void:
	var c2: Vector2 = IslandTerrain.CAVE_CENTER
	var fy: float = terrain.cave_floor_y
	cave_center = Vector3(c2.x, fy, c2.y)
	var to_origin: Vector2 = (-c2).normalized()
	cave_dir = Vector3(to_origin.x, 0.0, to_origin.y)
	cave_entrance = cave_center + cave_dir * CAVE_RING_R
	var a_e: float = atan2(cave_dir.z, cave_dir.x)
	var rock: StandardMaterial3D = _mat(Color(0.4, 0.38, 0.37))
	var dark: StandardMaterial3D = _mat(Color(0.28, 0.27, 0.28))
	var mossy: StandardMaterial3D = _mat(Color(0.3, 0.38, 0.27))

	# anillo de muros (deja un hueco en la entrada)
	var n: int = 12
	for i in range(2, n - 1):
		var a: float = a_e + TAU * float(i) / float(n)
		var r: float = _rng.randf_range(2.0, 2.4)
		var pos: Vector3 = cave_center + Vector3(cos(a) * CAVE_RING_R, 0.9, sin(a) * CAVE_RING_R)
		_boulder(pos, r, rock if i % 2 == 0 else dark)
	# peñascos que enmarcan la entrada (hueco de ~3 m de ancho)
	for s: float in [-1.0, 1.0]:
		var af: float = a_e + 0.62 * s
		_boulder(cave_center + Vector3(cos(af) * CAVE_RING_R, 0.9, sin(af) * CAVE_RING_R), 1.7, dark)
	# capa exterior (montículo), con el corredor de entrada despejado
	for i in 14:
		var a2: float = a_e + TAU * (float(i) + 0.5) / 14.0
		if absf(angle_difference(a2, a_e)) < 0.75:
			continue
		var r2: float = _rng.randf_range(2.4, 3.2)
		var d2: float = _rng.randf_range(7.4, 9.0)
		_boulder(cave_center + Vector3(cos(a2) * d2, 0.9, sin(a2) * d2), r2, mossy if i % 3 == 0 else rock)
	# techo abovedado
	_boulder(cave_center + Vector3(0, 5.7, 0), 2.7, dark, 0.8)
	for i in 8:
		var a3: float = TAU * float(i) / 8.0 + 0.3
		if absf(angle_difference(a3, a_e)) < 0.5:
			continue
		_boulder(cave_center + Vector3(cos(a3) * 4.1, 4.5, sin(a3) * 4.1), 2.3, rock, 0.8)
	for i in 6:
		var a4: float = a_e + TAU * (float(i) + 0.5) / 6.0
		if absf(angle_difference(a4, a_e)) < 1.0:
			continue   # no bajar el techo sobre la entrada
		_boulder(cave_center + Vector3(cos(a4) * 6.0, 3.6, sin(a4) * 6.0), 2.6, mossy if i % 2 == 0 else rock, 0.8)
	# dintel alto sobre la entrada
	_boulder(cave_center + cave_dir * (CAVE_RING_R + 0.2) + Vector3(0, 4.3, 0), 1.5, dark, 0.8)

	# cristales misteriosos al fondo
	var back: Vector3 = -cave_dir
	for i in 6:
		var a5: float = atan2(back.z, back.x) + _rng.randf_range(-1.1, 1.1)
		var rr: float = _rng.randf_range(2.2, 2.9)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.8, 0.85)
		m.emission_enabled = true
		m.emission = Color(0.3, 0.9, 0.9)
		m.emission_energy_multiplier = 1.5
		m.roughness = 0.2
		_crystal_mats.append(m)
		var cr := _cyl(0.0, _rng.randf_range(0.18, 0.3), _rng.randf_range(0.7, 1.4), 5)
		_mi(self, cr, m, cave_center + Vector3(cos(a5) * rr, cr.height * 0.5, sin(a5) * rr), Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3)))
	_cave_light = OmniLight3D.new()
	_cave_light.position = cave_center + Vector3(0, 1.8, 0)
	_cave_light.omni_range = 10.0
	_cave_light.light_energy = 0.8
	_cave_light.light_color = Color(0.4, 0.9, 0.9)
	_cave_light.shadow_enabled = false
	add_child(_cave_light)

	# roca que sella la entrada (la usa la isla de noche)
	_seal_body = StaticBody3D.new()
	_seal_body.position = cave_entrance + Vector3(0, 1.2, 0)
	_seal_shape = CollisionShape3D.new()
	_seal_shape.shape = _sphere_shape(1.6)
	_seal_shape.disabled = true
	_seal_body.add_child(_seal_shape)
	_seal_mesh = _mi(_seal_body, _sph(1.7, 7, 4), dark, Vector3.ZERO, Vector3(0.3, 0.8, 0.1), Vector3(0.01, 0.01, 0.01))
	_seal_mesh.visible = false
	add_child(_seal_body)

	sacred_spots.append({"name": "Cueva", "pos": cave_center, "radius": 6.0, "kind": "refuge"})

func is_inside_cave(p: Vector3) -> bool:
	return Vector2(p.x - cave_center.x, p.z - cave_center.z).length() < CAVE_INNER_R and p.y < cave_center.y + 3.2

func is_cave_sealed() -> bool:
	return _sealed

## La isla cierra la entrada con una roca.
func seal_cave() -> void:
	if _sealed:
		return
	_sealed = true
	_seal_mesh.visible = true
	_seal_mesh.scale = Vector3(0.05, 0.05, 0.05)
	var tw: Tween = create_tween()
	tw.tween_property(_seal_mesh, "scale", Vector3(1.0, 1.0, 1.0), 1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _seal_shape.disabled = false)
	_dust_burst(_seal_body.global_position, 1.5)

func open_cave() -> void:
	if not _sealed:
		return
	_sealed = false
	_seal_shape.disabled = true
	_dust_burst(_seal_body.global_position, 2.5)
	var tw: Tween = create_tween()
	tw.tween_property(_seal_mesh, "scale", Vector3(0.01, 0.01, 0.01), 1.2)
	tw.tween_callback(func() -> void: _seal_mesh.visible = false)

func _dust_burst(pos: Vector3, power: float) -> void:
	var p := CPUParticles3D.new()
	var s := _sph(0.1, 5, 3)
	s.material = _mat(Color(0.55, 0.5, 0.45))
	p.mesh = s
	p.top_level = true
	p.one_shot = true
	p.emitting = true
	p.explosiveness = 1.0
	p.amount = 28
	p.lifetime = 1.2
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0, -4.0, 0)
	p.initial_velocity_min = 1.5 * power
	p.initial_velocity_max = 3.5 * power
	p.scale_amount_min = 0.7
	p.scale_amount_max = 2.0
	add_child(p)
	p.global_position = pos
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)

## 0 = cueva tranquila (cristales turquesa), 1 = presencia hostil (rojo violeta que late).
func set_cave_ominous(a: float) -> void:
	_ominous = clampf(a, 0.0, 1.0)

# ------------------------------------------------------------------ piedras antiguas

func _build_standing_stones() -> void:
	var p: Vector3 = _spot(2.2, 5.5, 8.0, 38.0, cave_center, 30.0)
	if p.y < -90.0:
		return
	heart_pos = p
	var stone: StandardMaterial3D = _mat(Color(0.5, 0.5, 0.52))
	var count: int = 7
	for i in count:
		var a: float = TAU * float(i) / float(count)
		var sp: Vector3 = p + Vector3(cos(a) * 5.5, 0.0, sin(a) * 5.5)
		var gy: float = terrain.height_at(sp.x, sp.z)
		var h: float = _rng.randf_range(3.4, 4.6)
		var box := BoxMesh.new()
		box.size = Vector3(1.2, h, 0.9)
		var rot: Vector3 = Vector3(_rng.randf_range(-0.07, 0.07), a + PI / 2.0, _rng.randf_range(-0.07, 0.07))
		_mi(self, box, stone, Vector3(sp.x, gy + h * 0.45, sp.z), rot)
		var bs := BoxShape3D.new()
		bs.size = box.size
		_solid(bs, Vector3(sp.x, gy + h * 0.45, sp.z), rot)
	# losa central con anillo rúnico que late
	var slab := _cyl(2.2, 2.4, 0.3, 10)
	_mi(self, slab, _mat(Color(0.4, 0.4, 0.42)), p + Vector3(0, 0.1, 0))
	_heart_mat = StandardMaterial3D.new()
	_heart_mat.albedo_color = Color(0.2, 0.8, 0.8)
	_heart_mat.emission_enabled = true
	_heart_mat.emission = Color(0.2, 0.9, 0.9)
	_heart_mat.emission_energy_multiplier = 1.0
	var ring := TorusMesh.new()
	ring.inner_radius = 1.2
	ring.outer_radius = 1.45
	ring.rings = 16
	ring.ring_segments = 6
	_mi(self, ring, _heart_mat, p + Vector3(0, 0.3, 0))
	_heart_light = OmniLight3D.new()
	_heart_light.position = p + Vector3(0, 1.0, 0)
	_heart_light.omni_range = 9.0
	_heart_light.light_energy = 0.0
	_heart_light.light_color = Color(0.3, 0.9, 0.9)
	_heart_light.shadow_enabled = false
	add_child(_heart_light)
	sacred_spots.append({"name": "Piedras antiguas", "pos": p, "radius": 8.0, "kind": "heart"})

# ------------------------------------------------------------------ árbol ancestral

func _build_giant_tree() -> void:
	var p: Vector3 = _spot(2.0, 5.5, 14.0, 44.0, cave_center, 24.0)
	if p.y < -90.0:
		return
	if heart_pos != Vector3.ZERO and Vector2(p.x - heart_pos.x, p.z - heart_pos.z).length() < 22.0:
		var p2: Vector3 = _spot(2.0, 5.5, 14.0, 44.0, heart_pos, 24.0)
		if p2.y > -90.0:
			p = p2
	var bark: StandardMaterial3D = _mat(Color(0.33, 0.22, 0.14))
	var holder := Node3D.new()
	holder.position = p
	add_child(holder)
	_mi(holder, _cyl(0.9, 1.7, 10.0, 8), bark, Vector3(0, 5.0, 0))
	for i in 7:
		var a: float = TAU * float(i) / 7.0 + _rng.randf() * 0.3
		var root := _cyl(0.0, 0.7, 3.2, 5)
		_mi(holder, root, bark, Vector3(cos(a) * 1.9, 0.5, sin(a) * 1.9), Vector3(sin(a) * 1.1, 0, -cos(a) * 1.1))
	var cs := CylinderShape3D.new()
	cs.radius = 1.7
	cs.height = 9.0
	_solid(cs, p + Vector3(0, 4.5, 0))
	# copa enorme que se mece
	var leaf: ShaderMaterial = Wind.make(Color(0.12, 0.36, 0.15), -3.0, 6.0, 0.35, 0.03, 0.9)
	var offsets: Array[Vector3] = [Vector3(0, 11.0, 0), Vector3(3.2, 10.0, 1.0), Vector3(-3.0, 10.2, -1.2), Vector3(0.6, 10.3, 3.4), Vector3(-0.8, 10.0, -3.3), Vector3(0, 13.0, 0)]
	for o: Vector3 in offsets:
		var sm := _sph(3.4, 8, 5)
		_mi(holder, sm, leaf, o, Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
	sacred_spots.append({"name": "Árbol ancestral", "pos": p, "radius": 7.0, "kind": "heart"})

# ------------------------------------------------------------------ naufragio

func _build_shipwreck() -> void:
	var p: Vector3 = Vector3(0, -100, 0)
	for i in 60:
		var c: Vector3 = terrain.find_spot(_rng, 0.75, 1.1)
		if c.y < -90.0:
			continue
		var d: float = Vector2(c.x, c.z).length()
		if d > 40.0 and c.x < 20.0:
			p = c
			break
	if p.y < -90.0:
		return
	var wood: StandardMaterial3D = _mat(Color(0.38, 0.26, 0.15))
	var weathered: StandardMaterial3D = _mat(Color(0.55, 0.48, 0.4))
	var holder := Node3D.new()
	holder.position = p + Vector3(0, 0.1, 0)
	holder.rotation.y = atan2(-p.x, -p.z) + 0.6
	add_child(holder)
	# quilla y costillas del casco, medio enterrado
	var keel := BoxMesh.new()
	keel.size = Vector3(0.25, 0.3, 6.0)
	_mi(holder, keel, wood, Vector3(0, 0.0, 0), Vector3(0.08, 0, 0))
	for i in 8:
		var z: float = -2.6 + float(i) * 0.75
		var w: float = 1.3 - absf(z) * 0.12
		var plank := BoxMesh.new()
		plank.size = Vector3(0.12, 0.09, 1.9 * (1.0 - absf(z) / 8.0))
		for s: float in [-1.0, 1.0]:
			_mi(holder, plank, wood, Vector3(w * 0.5 * s, 0.55, z), Vector3(0.0, 0.0, 0.0) , Vector3(1, 1, 1)).rotation = Vector3(0, PI / 2.0, 0.9 * s)
	# tablones sueltos de la cubierta y mástil roto
	for i in 5:
		var tb := BoxMesh.new()
		tb.size = Vector3(0.4, 0.08, _rng.randf_range(1.2, 2.2))
		_mi(holder, tb, weathered, Vector3(_rng.randf_range(-2.8, 2.8), 0.1, _rng.randf_range(-3.5, 3.5)), Vector3(0, _rng.randf() * TAU, _rng.randf_range(-0.1, 0.1)))
	_mi(holder, _cyl(0.1, 0.14, 4.2, 6), wood, Vector3(2.0, 0.3, 1.0), Vector3(0.1, 0.3, PI / 2.0 - 0.1))
	# barril y baúl
	_mi(holder, _cyl(0.4, 0.4, 0.8, 8), _mat(Color(0.45, 0.3, 0.16)), Vector3(-1.9, 0.4, -2.2))
	var chest := BoxMesh.new()
	chest.size = Vector3(0.9, 0.55, 0.6)
	_mi(holder, chest, _mat(Color(0.35, 0.22, 0.12)), Vector3(1.6, 0.28, -1.8), Vector3(0, 0.5, 0.08))
	_solid(_sphere_shape(0.9), p + Vector3(0, 0.6, 0))
	for i in 2:
		var it := WorldItem.new()
		it.name = "TablonesNaufragio%d" % i
		it.item_id = "madera"
		it.display_name = "Tablones del naufragio"
		it.amount = 4
		it.position = p + Vector3(_rng.randf_range(-2.0, 2.0), 0.2, _rng.randf_range(-2.0, 2.0))
		add_child(it)
	sacred_spots.append({"name": "Naufragio", "pos": p, "radius": 5.0, "kind": "wreck"})

# ------------------------------------------------------------------ elementos aleatorios

func _build_cairns() -> void:
	for i in 16:
		var p: Vector3 = _spot(1.1, 8.0)
		if p.y < -90.0:
			continue
		var holder := Node3D.new()
		holder.position = p
		add_child(holder)
		var h: float = 0.0
		var r: float = _rng.randf_range(0.5, 0.75)
		for k in _rng.randi_range(3, 5):
			_mi(holder, _sph(r, 6, 3), _mat(Color(0.5, 0.49, 0.48)), Vector3(_rng.randf_range(-0.06, 0.06), h + r * 0.5, _rng.randf_range(-0.06, 0.06)), Vector3(0, _rng.randf() * TAU, 0), Vector3(1, 0.6, 1))
			h += r * 0.9
			r *= 0.8
		_solid(_sphere_shape(0.55), p + Vector3(0, 0.5, 0))

func _build_mushroom_rings() -> void:
	for i in 5:
		var p: Vector3 = _spot(1.6, 6.0, 6.0, 52.0)
		if p.y < -90.0:
			continue
		var count: int = 10
		for k in count:
			var a: float = TAU * float(k) / float(count)
			var x: float = p.x + cos(a) * 1.5
			var z: float = p.z + sin(a) * 1.5
			var y: float = terrain.height_at(x, z)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.35, 0.6, 0.9)
			m.emission_enabled = true
			m.emission = Color(0.3, 0.6, 1.0)
			m.emission_energy_multiplier = 0.2
			_shroom_mats.append(m)
			var s: float = _rng.randf_range(0.8, 1.4)
			_mi(self, _cyl(0.025 * s, 0.035 * s, 0.14 * s, 5), _mat(Color(0.9, 0.9, 0.95)), Vector3(x, y + 0.07 * s, z))
			_mi(self, _sph(0.1 * s, 6, 3), m, Vector3(x, y + 0.15 * s, z), Vector3.ZERO, Vector3(1, 0.55, 1))

# ------------------------------------------------------------------ animación

func _process(delta: float) -> void:
	_time += delta
	if int(_time * 2.0) != int((_time - delta) * 2.0):
		var dn: Node = get_tree().get_first_node_in_group("daynight")
		if dn != null:
			_night = dn.get("night_amount")
	# cristales de la cueva: turquesa tranquilo -> rojo violeta que late
	var pulse: float = 0.5 + 0.5 * sin(_time * lerpf(1.2, 3.6, _ominous))
	var calm: Color = Color(0.3, 0.9, 0.9).lerp(Color(1.0, 0.72, 0.35), _warm)   # con confianza, la cueva se vuelve cálida (dorada)
	var bad: Color = Color(0.95, 0.15, 0.4)
	var col: Color = calm.lerp(bad, _ominous)
	var energy: float = lerpf(1.2, 4.5, _ominous * (0.4 + 0.6 * pulse)) * lerpf(0.7, 1.4, _night)
	for m: StandardMaterial3D in _crystal_mats:
		m.emission = col
		m.albedo_color = col.darkened(0.4)
		m.emission_energy_multiplier = energy
	if _cave_light != null:
		_cave_light.light_color = col
		_cave_light.light_energy = lerpf(0.5, 3.0, _ominous * (0.5 + 0.5 * pulse)) * lerpf(0.8, 1.3, _night)
	# anillo rúnico de las piedras: late más de noche
	if _heart_mat != null:
		var hp: float = 0.5 + 0.5 * sin(_time * 1.1)
		var hcol: Color = Color(0.2, 0.9, 0.9).lerp(Color(0.9, 0.3, 0.6), _ominous * 0.7)
		_heart_mat.emission = hcol
		_heart_mat.emission_energy_multiplier = lerpf(0.3, 3.0, _night) * (0.6 + 0.4 * hp)
		_heart_light.light_color = hcol
		_heart_light.light_energy = lerpf(0.0, 1.6, _night) * (0.5 + 0.5 * hp)
	for m2: StandardMaterial3D in _shroom_mats:
		m2.emission_energy_multiplier = lerpf(0.15, 2.4, _night)
