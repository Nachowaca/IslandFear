extends Node3D

## Vida del mar: cardúmenes en los bajos, motas en suspensión y una ballena que rodea la isla de día.
## Todo es liviano (un MultiMesh para los peces, una malla low-poly para la ballena).

const WATER_Y: float = 0.35
const SCHOOLS: int = 9
const FISH_PER_SCHOOL: int = 6
const WHALE_R: float = 205.0
const WHALE_SPEED: float = 0.012        ## rad/s: una vuelta cada ~8 min
const DIVE_PERIOD: float = 38.0         ## cada tanto sube a respirar

var terrain: IslandTerrain

var _rng := RandomNumberGenerator.new()
var _fish_mm: MultiMeshInstance3D
var _schools: Array[Dictionary] = []
var _motes: CPUParticles3D
var _player: Node3D
var _whale: Node3D
var _spout: CPUParticles3D
var _whale_ang: float = 0.0
var _whale_t: float = 0.0
var _daynight: Node
var _time: float = 0.0

func _ready() -> void:
	if terrain == null:
		return
	_rng.seed = 4242
	_build_fish()
	_build_motes()
	_build_whale()
	var manta: Node3D = (load("res://scripts/night_manta.gd") as GDScript).new() as Node3D
	manta.name = "Mantaraya"
	add_child(manta)
	_whale_ang = _rng.randf() * TAU
	_whale_t = _rng.randf() * DIVE_PERIOD

func _process(delta: float) -> void:
	_time += delta
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _daynight == null:
		_daynight = get_tree().get_first_node_in_group("daynight")
	_update_fish(delta)
	_update_motes()
	_update_whale(delta)

# ------------------------------------------------------------------ peces

func _shallow_point(ang: float) -> Vector3:
	# recorre hacia afuera desde la costa hasta hallar agua de 1.2-3 m de profundidad
	var r: float = terrain.radius * 0.55
	var dir: Vector2 = Vector2(cos(ang), sin(ang))
	var best: Vector3 = Vector3(0, -999.0, 0)
	while r < terrain.radius * 1.3:
		var h: float = terrain.height_at(dir.x * r, dir.y * r)
		if h < WATER_Y - 1.2:
			best = Vector3(dir.x * r, h, dir.y * r)
			break
		r += 2.0
	return best

func _build_fish() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.8, 0.82)
	mat.roughness = 0.5
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = SCHOOLS * FISH_PER_SCHOOL
	_fish_mm = MultiMeshInstance3D.new()
	_fish_mm.multimesh = mm
	_fish_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fish_mm)
	for i in SCHOOLS:
		var p: Vector3 = _shallow_point(_rng.randf() * TAU)
		if p.y < -900.0:
			continue
		_schools.append({"c": Vector2(p.x, p.z), "floor": p.y, "ang": _rng.randf() * TAU,
			"rad": _rng.randf_range(2.0, 4.5), "spd": _rng.randf_range(0.15, 0.35) * (1.0 if _rng.randf() < 0.5 else -1.0),
			"depth": _rng.randf_range(0.5, 1.1), "off": _rng.randf() * 10.0})

func _update_fish(delta: float) -> void:
	var mm: MultiMesh = _fish_mm.multimesh
	var idx: int = 0
	for sc: Dictionary in _schools:
		sc["ang"] = float(sc["ang"]) + float(sc["spd"]) * delta
		var a: float = sc["ang"]
		var c: Vector2 = sc["c"]
		var rad: float = sc["rad"]
		var depth: float = maxf(float(sc["depth"]), 0.3)
		for k in FISH_PER_SCHOOL:
			var fa: float = a + float(k) * 0.35
			var fr: float = rad + sin(float(k) * 2.1 + _time * 0.5 + float(sc["off"])) * 0.7
			var pos := Vector3(c.x + cos(fa) * fr, WATER_Y - depth - sin(float(k) * 1.3 + _time) * 0.15, c.y + sin(fa) * fr)
			var tangent := Vector3(-sin(fa), 0.0, cos(fa)) * signf(float(sc["spd"]))
			var fb: Basis = Basis.looking_at(tangent, Vector3.UP)
			fb = fb.rotated(Vector3.UP, sin(_time * 7.0 + float(k)) * 0.15)
			fb = fb.scaled_local(Vector3(0.7, 0.7, 1.9))
			mm.set_instance_transform(idx, Transform3D(fb, pos))
			idx += 1
	while idx < mm.instance_count:
		mm.set_instance_transform(idx, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -50, 0)))
		idx += 1

# ------------------------------------------------------------------ motas en suspensión

func _build_motes() -> void:
	_motes = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.8, 0.9, 0.8, 0.35)
	q.material = m
	_motes.mesh = q
	_motes.amount = 70
	_motes.lifetime = 8.0
	_motes.preprocess = 8.0
	_motes.local_coords = false
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(9.0, 0.8, 9.0)
	_motes.direction = Vector3(0, 1, 0)
	_motes.spread = 180.0
	_motes.initial_velocity_min = 0.02
	_motes.initial_velocity_max = 0.08
	_motes.gravity = Vector3.ZERO
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.emitting = false
	add_child(_motes)

func _update_motes() -> void:
	if _player == null:
		return
	var pp: Vector3 = _player.global_position
	var near_sea: bool = terrain.height_at(pp.x, pp.z) < WATER_Y + 0.8 or pp.y < WATER_Y + 1.5
	_motes.emitting = near_sea
	_motes.global_position = Vector3(pp.x, WATER_Y - 0.9, pp.z)

# ------------------------------------------------------------------ ballena

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m

func _build_whale() -> void:
	_whale = Node3D.new()
	_whale.name = "Ballena"
	add_child(_whale)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 6
	body.mesh = sm
	body.material_override = _mat(Color(0.22, 0.3, 0.38))
	body.scale = Vector3(2.2, 2.0, 7.0)
	_whale.add_child(body)
	var belly := MeshInstance3D.new()
	belly.mesh = sm
	belly.material_override = _mat(Color(0.7, 0.76, 0.8))
	belly.scale = Vector3(1.9, 1.2, 6.2)
	belly.position = Vector3(0, -0.8, 0)
	_whale.add_child(belly)
	var tail := MeshInstance3D.new()
	var tm := PrismMesh.new()
	tm.size = Vector3(4.6, 2.2, 0.35)
	tail.mesh = tm
	tail.material_override = _mat(Color(0.2, 0.27, 0.34))
	tail.position = Vector3(0, 0.3, -8.2)
	tail.rotation = Vector3(PI / 2.0 - 0.15, 0, 0)
	_whale.add_child(tail)
	for s in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		var fm := PrismMesh.new()
		fm.size = Vector3(2.4, 0.3, 1.2)
		fin.mesh = fm
		fin.material_override = _mat(Color(0.2, 0.27, 0.34))
		fin.position = Vector3(2.0 * s, -0.9, 2.5)
		fin.rotation = Vector3(0, 0, 0.5 * s)
		_whale.add_child(fin)
	for mi: Node in _whale.get_children():
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spout = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.95, 1.0, 1.0, 0.5)
	q.material = m
	_spout.mesh = q
	_spout.amount = 24
	_spout.lifetime = 1.8
	_spout.direction = Vector3.UP
	_spout.spread = 12.0
	_spout.initial_velocity_min = 5.0
	_spout.initial_velocity_max = 8.0
	_spout.gravity = Vector3(0, -6.0, 0)
	_spout.scale_amount_min = 0.5
	_spout.scale_amount_max = 1.5
	_spout.local_coords = false
	_spout.emitting = false
	_spout.position = Vector3(0, 2.0, 3.0)
	_whale.add_child(_spout)

func _update_whale(delta: float) -> void:
	var night: float = 0.0
	if _daynight != null:
		night = float(_daynight.get("night_amount"))
	_whale_ang += WHALE_SPEED * delta
	_whale_t += delta
	var phase: float = fposmod(_whale_t, DIVE_PERIOD) / DIVE_PERIOD
	# casi todo el ciclo está sumergida; asoma el lomo un tramo corto
	var up: float = sin(clampf((phase - 0.55) / 0.35, 0.0, 1.0) * PI)
	up *= 1.0 - clampf(night * 1.6, 0.0, 1.0)             # de noche no sale
	var pos := Vector3(cos(_whale_ang) * WHALE_R, WATER_Y - 3.2 + up * 3.2, sin(_whale_ang) * WHALE_R)
	_whale.position = pos
	var tangent := Vector3(-sin(_whale_ang), 0.0, cos(_whale_ang))
	_whale.look_at(pos + tangent, Vector3.UP)
	_whale.rotate_object_local(Vector3.RIGHT, -sin(clampf((phase - 0.55) / 0.35, 0.0, 1.0) * TAU) * 0.08)
	var is_day: bool = night < 0.6          # solo de día; de noche queda oculta (reservado para otra cosa)
	_whale.visible = is_day
	_spout.emitting = is_day and up > 0.85 and phase < 0.78
