class_name Boat
extends Node3D

## Barco de tablas con una vela triangular que se hincha con el viento.
## Tiene colisión (cubierta y bordes) y una plancha de desembarco que baja hasta la orilla.
## Convención: la proa apunta a -Z; el origen está a la altura de la línea de flotación.

const SAIL_SHADER: Shader = preload("res://shaders/sail.gdshader")

const BOW_Z: float = -2.1
const STERN_Z: float = 1.9
const DECK_Y: float = 0.125

var _mats: Dictionary = {}
var _ramp_hinge: Node3D
var _ramp_body: StaticBody3D

func _ready() -> void:
	_build_hull()
	_build_deck()
	_build_rig()
	_build_props()
	_build_collision()

# ------------------------------------------------------------------ helpers

func _mat(c: Color) -> StandardMaterial3D:
	var key: String = c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		_mats[key] = m
	return _mats[key]

func _wood(i: int) -> StandardMaterial3D:
	var tones: Array[Color] = [Color(0.56, 0.39, 0.23), Color(0.47, 0.32, 0.19), Color(0.62, 0.45, 0.27), Color(0.5, 0.35, 0.2)]
	return _mat(tones[i % tones.size()])

func _box(size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi

## Cilindro fino entre dos puntos (cuerdas, mástil, botavara...).
func _line(a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = a.distance_to(b)
	c.radial_segments = 6
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	add_child(mi)
	return mi

## Semiancho del casco a lo largo de la eslora (t = 0 proa, 1 popa).
func _half_width(z: float) -> float:
	var t: float = clampf((z - BOW_Z) / (STERN_Z - BOW_Z), 0.0, 1.0)
	if t < 0.55:
		return 0.85 * sin(0.5 * PI * pow(t / 0.55, 0.8))
	return lerpf(0.85, 0.62, (t - 0.55) / 0.45)

## Altura de la borda (más baja en la proa).
func _hull_top(z: float) -> float:
	var t: float = clampf((z - BOW_Z) / (STERN_Z - BOW_Z), 0.0, 1.0)
	return -0.1 + lerpf(0.34, 0.72, smoothstep(0.0, 0.35, t))

# ------------------------------------------------------------------ casco

func _build_hull() -> void:
	var seg: int = 11
	var z_start: float = BOW_Z + 0.24        # deja la proa abierta para la plancha
	var strake_h: float = 0.18
	for k in 4:
		var y_bottom: float = -0.1 + strake_h * float(k)
		var y_center: float = y_bottom + strake_h * 0.5
		var flare: float = 0.05 * float(k)
		for i in seg:
			var z1: float = lerpf(z_start, STERN_Z, float(i) / float(seg))
			var z2: float = lerpf(z_start, STERN_Z, float(i + 1) / float(seg))
			var zm: float = (z1 + z2) * 0.5
			if y_bottom + strake_h > _hull_top(zm) + 0.03:
				continue
			for s: float in [-1.0, 1.0]:
				var x1: float = (_half_width(z1) + flare) * s
				var x2: float = (_half_width(z2) + flare) * s
				var dx: float = x2 - x1
				var dz: float = z2 - z1
				var seg_len: float = sqrt(dx * dx + dz * dz) + 0.02
				var mi: MeshInstance3D = _box(Vector3(0.05, strake_h - 0.012, seg_len), Vector3((x1 + x2) * 0.5, y_center, zm), _wood(k + i), Vector3(0.0, atan2(dx, dz), 0.0))
				mi.rotation.z = 0.12 * s * -1.0       # las tablas se inclinan hacia afuera
	# espejo de popa y quilla
	_box(Vector3(1.4, 0.64, 0.06), Vector3(0, 0.22, STERN_Z + 0.04), _wood(1))
	_box(Vector3(0.12, 0.1, 3.9), Vector3(0, -0.15, -0.12), _mat(Color(0.28, 0.19, 0.11)))
	# roda (pieza curva de proa)
	_box(Vector3(0.09, 0.55, 0.12), Vector3(0, 0.08, BOW_Z + 0.12), _mat(Color(0.3, 0.2, 0.12)), Vector3(-0.55, 0, 0))

func _build_deck() -> void:
	var i: int = 0
	var z: float = -1.75
	while z <= 1.8:
		var w: float = maxf(2.0 * _half_width(z) - 0.1, 0.3)
		_box(Vector3(w, 0.05, 0.27), Vector3(0, 0.1, z), _wood(i + 2))
		z += 0.285
		i += 1
	# bancos
	for bz: float in [0.55, 1.35]:
		var bw: float = 2.0 * _half_width(bz) * 0.97
		_box(Vector3(bw, 0.05, 0.3), Vector3(0, 0.4, bz), _wood(3))
		_box(Vector3(0.08, 0.28, 0.2), Vector3(-bw * 0.4, 0.25, bz), _wood(1))
		_box(Vector3(0.08, 0.28, 0.2), Vector3(bw * 0.4, 0.25, bz), _wood(1))

# ------------------------------------------------------------------ mástil y vela

func _build_rig() -> void:
	var dark: StandardMaterial3D = _mat(Color(0.3, 0.2, 0.12))
	var rope: StandardMaterial3D = _mat(Color(0.7, 0.62, 0.45))
	var mast_z: float = -0.85
	var base: Vector3 = Vector3(0, DECK_Y, mast_z)
	var top: Vector3 = Vector3(0, 2.85, mast_z)
	_line(base, top, 0.055, dark)
	_box(Vector3(0.28, 0.1, 0.4), Vector3(0, 0.17, mast_z), dark)          # carlinga del mástil
	# botavara
	var boom_a: Vector3 = Vector3(0, 0.95, mast_z)
	var boom_b: Vector3 = Vector3(0, 0.95, 1.05)
	_line(boom_a, boom_b, 0.04, dark)
	# estayes y cuerdas
	_line(top, Vector3(0, 0.2, BOW_Z + 0.15), 0.012, rope)
	_line(top, Vector3(0, 0.45, STERN_Z), 0.012, rope)
	_line(boom_b, Vector3(0, 0.6, STERN_Z - 0.1), 0.012, rope)
	# banderín
	var pennant := PrismMesh.new()
	pennant.size = Vector3(0.28, 0.14, 0.01)
	var pm := MeshInstance3D.new()
	pm.mesh = pennant
	pm.material_override = _mat(Color(0.75, 0.15, 0.12))
	pm.position = Vector3(0, 2.8, mast_z + 0.15)
	pm.rotation = Vector3(0, PI / 2.0, -PI / 2.0)
	add_child(pm)
	# vela triangular con panza
	var sail := MeshInstance3D.new()
	sail.mesh = _make_sail(Vector3(0, 1.0, mast_z), Vector3(0, 2.75, mast_z), Vector3(0, 1.0, 1.0), 9)
	var sm := ShaderMaterial.new()
	sm.shader = SAIL_SHADER
	sail.material_override = sm
	sail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(sail)

func _make_sail(m0: Vector3, m1: Vector3, b: Vector3, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for j in n - i:
			_tri(st, m0, m1, b, n, i, j, i + 1, j, i, j + 1)
			if j < n - i - 1:
				_tri(st, m0, m1, b, n, i + 1, j, i + 1, j + 1, i, j + 1)
	st.generate_normals()
	return st.commit()

func _tri(st: SurfaceTool, m0: Vector3, m1: Vector3, b: Vector3, n: int, i1: int, j1: int, i2: int, j2: int, i3: int, j3: int) -> void:
	for p: Array in [[i1, j1], [i2, j2], [i3, j3]]:
		var a: float = float(p[0]) / float(n)
		var c: float = float(p[1]) / float(n)
		st.set_uv(Vector2(a, c))
		st.add_vertex(m0 + (b - m0) * a + (m1 - m0) * c)

# ------------------------------------------------------------------ detalles

func _build_props() -> void:
	# rollo de cuerda
	var rope_mesh := TorusMesh.new()
	rope_mesh.inner_radius = 0.07
	rope_mesh.outer_radius = 0.17
	rope_mesh.rings = 12
	rope_mesh.ring_segments = 5
	var rm := MeshInstance3D.new()
	rm.mesh = rope_mesh
	rm.material_override = _mat(Color(0.72, 0.64, 0.46))
	rm.position = Vector3(-0.3, 0.2, 0.15)
	add_child(rm)
	# cajón en la popa
	_box(Vector3(0.42, 0.32, 0.4), Vector3(0.3, 0.3, 1.58), _wood(2), Vector3(0, 0.3, 0))
	# remo apoyado sobre los bancos
	_line(Vector3(-0.55, 0.47, 1.9), Vector3(0.45, 0.47, 0.1), 0.025, _mat(Color(0.52, 0.37, 0.2)))
	_box(Vector3(0.14, 0.02, 0.34), Vector3(0.5, 0.47, 0.0), _mat(Color(0.52, 0.37, 0.2)), Vector3(0, 0.5, 0))
	# caña del timón
	_box(Vector3(0.06, 0.06, 0.8), Vector3(0, 0.55, 1.55), _mat(Color(0.3, 0.2, 0.12)), Vector3(0.1, 0, 0))

# ------------------------------------------------------------------ colisión

func _solid(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)

func _build_collision() -> void:
	_solid(Vector3(1.9, 0.12, 3.6), Vector3(0, DECK_Y - 0.06, -0.05))       # cubierta
	_solid(Vector3(0.55, 0.12, 0.5), Vector3(0, DECK_Y - 0.06, -2.0))       # punta de proa
	_solid(Vector3(0.08, 0.7, 3.0), Vector3(0.95, 0.3, 0.4))                # bordas
	_solid(Vector3(0.08, 0.7, 3.0), Vector3(-0.95, 0.3, 0.4))
	_solid(Vector3(1.5, 0.7, 0.08), Vector3(0, 0.3, STERN_Z + 0.04))        # espejo de popa
	_solid(Vector3(0.1, 1.0, 0.1), Vector3(0, 0.6, -0.85))                  # mástil

# ------------------------------------------------------------------ plancha de desembarco

## Baja una plancha desde la proa hasta el suelo. Usar con await.
func deploy_gangway(terrain: IslandTerrain) -> void:
	var s: Vector3 = to_global(Vector3(0, DECK_Y, BOW_Z - 0.25))
	var d: Vector3 = -global_basis.z
	d.y = 0.0
	d = d.normalized()
	var e: Vector3 = s + d * 2.0
	e.y = maxf(terrain.height_at(e.x, e.z), 0.0) + 0.04
	var v: Vector3 = e - s
	var length: float = v.length()
	var final_basis: Basis = Basis.looking_at(v.normalized(), Vector3.UP)
	var raised_dir: Vector3 = (d + Vector3.UP * 1.2).normalized()
	var raised_basis: Basis = Basis.looking_at(raised_dir, Vector3.UP)

	_ramp_hinge = Node3D.new()
	_ramp_hinge.top_level = true
	add_child(_ramp_hinge)
	_ramp_hinge.global_position = s
	_ramp_hinge.global_basis = raised_basis

	_ramp_body = StaticBody3D.new()
	_ramp_body.position = Vector3(0, -0.035, -length * 0.5)
	_ramp_body.collision_layer = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 0.07, length)
	cs.shape = bs
	_ramp_body.add_child(cs)
	var plank := BoxMesh.new()
	plank.size = Vector3(1.0, 0.07, length)
	var pm := MeshInstance3D.new()
	pm.mesh = plank
	pm.material_override = _wood(0)
	_ramp_body.add_child(pm)
	for k in 4:      # listones transversales
		var cleat := BoxMesh.new()
		cleat.size = Vector3(1.0, 0.03, 0.06)
		var cm := MeshInstance3D.new()
		cm.mesh = cleat
		cm.material_override = _wood(1)
		cm.position = Vector3(0, 0.04, -length * 0.5 + length * (0.2 + 0.2 * float(k)))
		_ramp_body.add_child(cm)
	_ramp_hinge.add_child(_ramp_body)

	AudioManager.play(get_tree(), "step_wood", s, 5.0)
	var q0: Quaternion = raised_basis.get_rotation_quaternion()
	var q1: Quaternion = final_basis.get_rotation_quaternion()
	var tw: Tween = create_tween()
	tw.tween_method(func(w: float) -> void: _ramp_hinge.global_basis = Basis(q0.slerp(q1, w)), 0.0, 1.0, 1.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await tw.finished
	_ramp_body.collision_layer = 1
	AudioManager.play(get_tree(), "step_wood", e, 8.0)
