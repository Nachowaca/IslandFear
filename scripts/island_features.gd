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
const CAVE_LEN: float = 13.0                  # largo de la cueva desde el centro de la cámara hasta la boca
const CAVE_INNER_R: float = 3.5
const CAVE_RING_R: float = 5.4

var _rng := RandomNumberGenerator.new()
var _mats: Dictionary = {}
var _crystal_mats: Array[StandardMaterial3D] = []
var _cave_light: OmniLight3D
var _cave_orbs: Array[Dictionary] = []   ## luces flotantes del pozo
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
	# La cueva es un POZO excavado en el terreno (ver IslandTerrain._pit_carve) con luces misteriosas adentro.
	var c2: Vector2 = IslandTerrain.CAVE_CENTER
	var floor_y: float = terrain.cave_floor_y
	cave_center = Vector3(c2.x, floor_y, c2.y)
	var d2: Vector2 = IslandTerrain.cave_dir2()
	cave_dir = Vector3(d2.x, 0.0, d2.y)
	var ep: Vector2 = c2 + d2 * (CAVE_LEN - 1.5)                   # donde la isla puede sellar la boca
	cave_entrance = Vector3(ep.x, terrain.height_at(ep.x, ep.y), ep.y)
	var dark: StandardMaterial3D = _mat(Color(0.28, 0.27, 0.28))

	_build_cave_rock(c2, d2)

	# cristales y luces flotantes dentro del pozo
	for i in 7:
		var a5: float = _rng.randf() * TAU
		var rr: float = _rng.randf_range(1.6, 3.6)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.8, 0.85)
		m.emission_enabled = true
		m.emission = Color(0.3, 0.9, 0.9)
		m.emission_energy_multiplier = 1.5
		m.roughness = 0.2
		_crystal_mats.append(m)
		var cr := _cyl(0.0, _rng.randf_range(0.18, 0.3), _rng.randf_range(0.7, 1.4), 5)
		var cp: Vector3 = cave_center + Vector3(cos(a5) * rr, 0.0, sin(a5) * rr)
		cp.y = terrain.height_at(cp.x, cp.z) + cr.height * 0.5 - 0.1
		_mi(self, cr, m, cp, Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3)))
	for i in 9:
		var om := StandardMaterial3D.new()
		om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		om.albedo_color = Color(0.5, 1.0, 1.0)
		om.emission_enabled = true
		om.emission = Color(0.3, 0.9, 0.9)
		om.emission_energy_multiplier = 3.0
		_crystal_mats.append(om)
		var orb := _mi(self, _sph(_rng.randf_range(0.09, 0.18), 8, 4), om, cave_center, Vector3.ZERO)
		var base: Vector3 = cave_center + Vector3(_rng.randf_range(-3.6, 3.6), _rng.randf_range(0.8, 3.8), _rng.randf_range(-3.6, 3.6))
		_cave_orbs.append({"node": orb, "base": base, "ph": _rng.randf() * TAU, "sp": _rng.randf_range(0.4, 1.0), "amp": _rng.randf_range(0.25, 0.7)})
		orb.position = base
	var motes := CPUParticles3D.new()
	var mm := _sph(0.03, 4, 2)
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.albedo_color = Color(0.6, 1.0, 1.0)
	mm.material = mmat
	motes.mesh = mm
	motes.amount = 40
	motes.lifetime = 5.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 3.5
	motes.direction = Vector3.UP
	motes.spread = 25.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.1
	motes.initial_velocity_max = 0.4
	motes.position = cave_center + Vector3(0, 1.5, 0)
	add_child(motes)
	_cave_light = OmniLight3D.new()
	_cave_light.position = cave_center + Vector3(0, 2.0, 0)
	_cave_light.omni_range = 11.0
	_cave_light.light_energy = 0.8
	_cave_light.light_color = Color(0.4, 0.9, 0.9)
	_cave_light.shadow_enabled = false
	add_child(_cave_light)

	# roca que sella la rampa (la usa la isla de noche)
	_seal_body = StaticBody3D.new()
	_seal_body.position = cave_entrance + Vector3(0, 1.2, 0)
	_seal_shape = CollisionShape3D.new()
	_seal_shape.shape = _sphere_shape(2.3)
	_seal_shape.disabled = true
	_seal_body.add_child(_seal_shape)
	_seal_mesh = _mi(_seal_body, _sph(2.4, 7, 4), dark, Vector3.ZERO, Vector3(0.3, 0.8, 0.1), Vector3(0.01, 0.01, 0.01))
	_seal_mesh.visible = false
	add_child(_seal_body)

	sacred_spots.append({"name": "Cueva", "pos": cave_center, "radius": 6.0, "kind": "refuge"})

## La cueva es UNA roca grande (malla procedural) con un túnel y una cámara perforados; el piso es el propio terreno.
func _build_cave_rock(c2: Vector2, d2: Vector2) -> void:
	var nz := FastNoiseLite.new()
	nz.seed = 31
	nz.frequency = 0.22
	var nz2 := FastNoiseLite.new()
	nz2.seed = 77
	nz2.frequency = 0.7
	var side: Vector2 = Vector2(-d2.y, d2.x)
	var seg: int = 32
	var L: float = CAVE_LEN
	var inner: Array = []
	var outer: Array = []
	var n_in: int = 48
	for k in n_in + 1:
		var a: float = lerpf(-4.8, L, float(k) / float(n_in))
		var wi: float
		var hi: float
		if a >= 0.0:
			var t: float = smoothstep(2.5, 6.5, a)
			wi = lerpf(4.4, 2.0, t)
			hi = lerpf(5.0, 3.2, t)
		else:
			var f: float = sqrt(maxf(1.0 - (a / 4.8) * (a / 4.8), 0.0))
			wi = 4.4 * f
			hi = 5.0 * f
		var ring: Array = []
		var cxz: Vector2 = c2 + d2 * a
		var y0: float = terrain.height_at(cxz.x, cxz.y)
		for j in seg + 1:
			var th: float = PI * float(j) / float(seg)
			var q: Vector2 = cxz + side * (wi * cos(th))
			var sn: float = sin(th)
			var yq: float = lerpf(terrain.height_at(q.x, q.y) - 0.05, y0, pow(sn, 0.35))   # el arranque de la pared sigue al piso real (sin escalón)
			var pt: Vector3 = Vector3(q.x, yq + hi * pow(sn, 0.85), q.y)
			var amp: float = 0.55 * sn
			pt += Vector3(nz.get_noise_3d(pt.x, pt.y, pt.z), nz.get_noise_3d(pt.x + 50.0, pt.y, pt.z), nz.get_noise_3d(pt.x, pt.y, pt.z + 50.0)) * amp
			ring.append(pt)
		inner.append(ring)
	var n_out: int = 50
	for k in n_out + 1:
		var a2: float = lerpf(-8.0, L, float(k) / float(n_out))
		var wo: float
		var ho: float
		if a2 >= 0.0:
			var t2: float = smoothstep(0.0, L, a2)
			wo = lerpf(7.0, 4.4, t2)
			ho = lerpf(9.5, 5.2, t2)
		else:
			var f2: float = sqrt(maxf(1.0 - (a2 / 8.0) * (a2 / 8.0), 0.0))
			wo = 7.0 * f2
			ho = 9.5 * f2
		var ring2: Array = []
		var cxz2: Vector2 = c2 + d2 * a2
		var lf: Vector2 = cxz2 + side * wo
		var rt: Vector2 = cxz2 - side * wo
		var yl: float = terrain.height_at(lf.x, lf.y) - 1.0
		var yr: float = terrain.height_at(rt.x, rt.y) - 1.0
		for j in seg + 1:
			var th2: float = PI * float(j) / float(seg)
			var q2: Vector2 = cxz2 + side * (wo * cos(th2))
			var sn2: float = sin(th2)
			var yb: float = lerpf(yl, yr, float(j) / float(seg))
			var pt2: Vector3 = Vector3(q2.x, yb + ho * pow(sn2, 0.8), q2.y)
			var amp2: float = 0.4 + 1.3 * sn2
			pt2 += Vector3(nz.get_noise_3d(pt2.x, pt2.y, pt2.z), nz.get_noise_3d(pt2.x + 50.0, pt2.y, pt2.z), nz.get_noise_3d(pt2.x, pt2.y, pt2.z + 50.0)) * amp2 * 2.0
			pt2 += Vector3(nz2.get_noise_3d(pt2.x, pt2.y, pt2.z), 0.0, nz2.get_noise_3d(pt2.x, pt2.y + 9.0, pt2.z)) * 0.5 * sn2
			ring2.append(pt2)
		outer.append(ring2)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var cd: Dictionary = {"v": verts, "n": norms, "c": cols, "c2": c2}
	for k in n_in:
		for j in seg:
			_cave_quad(cd, inner[k][j], inner[k][j + 1], inner[k + 1][j + 1], inner[k + 1][j], false)
	for k in n_out:
		for j in seg:
			_cave_quad(cd, outer[k][j], outer[k][j + 1], outer[k + 1][j + 1], outer[k + 1][j], true)
	for j in seg:                                             # cara de la boca: une el borde interior con el exterior
		_cave_quad(cd, inner[n_in][j], inner[n_in][j + 1], outer[n_out][j + 1], outer[n_out][j], true)
	verts = cd["v"]
	cols = cd["c"]
	var st := SurfaceTool.new()          # normales suaves: la roca se ve redondeada, no facetada
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vi in verts.size():
		st.set_color(cols[vi])
		st.set_smooth_group(0)
		st.add_vertex(verts[vi])
	st.generate_normals()
	var am: ArrayMesh = st.commit()
	var rm := StandardMaterial3D.new()
	rm.vertex_color_use_as_albedo = true
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rm.roughness = 0.95
	am.surface_set_material(0, rm)
	var body := StaticBody3D.new()
	body.name = "CaveRock"
	var mi := MeshInstance3D.new()
	mi.mesh = am
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shp: ConcavePolygonShape3D = am.create_trimesh_shape() as ConcavePolygonShape3D
	shp.backface_collision = true
	cs.shape = shp
	body.add_child(cs)
	add_child(body)

## Agrega un quad (2 triángulos planos, normales por cara) a la malla de la cueva.
func _cave_quad(cd: Dictionary, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, is_outer: bool) -> void:
	var verts: PackedVector3Array = cd["v"]
	var norms: PackedVector3Array = cd["n"]
	var cols: PackedColorArray = cd["c"]
	var c2: Vector2 = cd["c2"]
	var tris: Array = [[p0, p1, p2], [p0, p2, p3]]
	for tri: Array in tris:
		var t0: Vector3 = tri[0]
		var t1: Vector3 = tri[1]
		var t2v: Vector3 = tri[2]
		var nn: Vector3 = (t1 - t0).cross(t2v - t0)
		if nn.length() < 0.0001:
			continue
		nn = nn.normalized()
		var cen: Vector3 = (t0 + t1 + t2v) / 3.0
		var hv: float = float(absi(hash(Vector3i(roundi(cen.x * 3.0), roundi(cen.y * 3.0), roundi(cen.z * 3.0)))) % 100) / 100.0
		var colr: Color
		if is_outer:
			var out_dir: Vector3 = Vector3(cen.x - c2.x, cen.y - cave_center.y - 2.0, cen.z - c2.y)
			if nn.dot(out_dir) < 0.0:
				nn = -nn
			colr = Color(0.27, 0.27, 0.30) * (0.93 + hv * 0.14)
			var moss: float = smoothstep(0.62, 0.85, nn.y) * smoothstep(cave_center.y + 1.5, cave_center.y + 4.5, cen.y)
			colr = colr.lerp(Color(0.18, 0.30, 0.12), moss * 0.85)
		else:
			colr = Color(0.16, 0.16, 0.19) * (0.93 + hv * 0.14)
		colr = colr.lerp(Color(colr.get_luminance(), colr.get_luminance(), colr.get_luminance()), 0.0)
		colr.a = 1.0
		for pv: Vector3 in [t0, t1, t2v]:
			verts.append(pv)
			norms.append(nn)
			cols.append(colr)

## Roca grande del pack nuevo, con colisión simple; no se puede atravesar pero queda en las paredes.
func _wall_rock(pos: Vector3, sc: float) -> void:
	var r: Node3D = NatureKit.make_uq("Rock_%d" % _rng.randi_range(1, 5), Color(0.8, 0.8, 0.85, 0.3), 220.0)
	r.position = pos
	r.rotation = Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf() * TAU, _rng.randf_range(-0.2, 0.2))
	r.scale = Vector3.ONE * sc
	add_child(r)

func is_inside_cave(p: Vector3) -> bool:
	var rel: Vector2 = Vector2(p.x - cave_center.x, p.z - cave_center.z)
	var d2: Vector2 = Vector2(cave_dir.x, cave_dir.z)
	var along: float = rel.dot(d2)
	var across: float = absf(rel.dot(Vector2(-d2.y, d2.x)))
	if p.y > cave_center.y + 5.0 or along < -4.0 or along > CAVE_LEN - 1.0:
		return false
	return across < (4.2 if along < 3.0 else 2.0)

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
	var holder := Node3D.new()
	holder.position = p
	add_child(holder)
	var big: Node3D = NatureKit.make_uq("MapleTree_2", Color(0.85, 1.0, 0.8), 0.0)   # árbol del pack nuevo, enorme
	big.scale = Vector3.ONE * 2.4
	big.rotation.y = _rng.randf() * TAU
	holder.add_child(big)
	var cs := CylinderShape3D.new()
	cs.radius = 1.2
	cs.height = 9.0
	_solid(cs, p + Vector3(0, 4.5, 0))
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
	for o: Dictionary in _cave_orbs:
		var ph: float = float(o["ph"]) + _time * float(o["sp"])
		(o["node"] as Node3D).position = (o["base"] as Vector3) + Vector3(sin(ph) * float(o["amp"]), sin(ph * 1.7) * float(o["amp"]) * 0.8, cos(ph * 0.8) * float(o["amp"]))
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
