class_name Lighthouse
extends Node3D

## Faro sobre un montículo de piedra. De noche emite un haz giratorio y lento que ilumina la isla,
## proyecta sombras reales de árboles y objetos, y "rebota" luz cálida donde pega.
## De día se apaga.

@export var rotation_period: float = 30.0   # segundos por vuelta completa (lento)
@export var tower_height: float = 12.0
@export var beam_length: float = 110.0
@export var water_level: float = 0.35
@export var bounce_count: int = 7

const BEAM_SHADER: Shader = preload("res://shaders/lighthouse_beam.gdshader")
const FLARE_SHADER: Shader = preload("res://shaders/lighthouse_flare.gdshader")

var _pivot: Node3D
var _tilt: Node3D
var _spot: SpotLight3D
var _glow: OmniLight3D
var _flare: MeshInstance3D
var _flare_mat: ShaderMaterial
var _lamp_mat: StandardMaterial3D
var _beam_mats: Array[ShaderMaterial] = []
var _bounces: Array[OmniLight3D] = []
var _bounce_targets: Array[Vector3] = []
var _bounce_energy: Array[float] = []
var _intensity: float = 0.0
var _lamp_y: float = 0.0

func _ready() -> void:
	add_to_group("lighthouse")
	_build_mound()
	_build_tower()
	_build_light()
	set_night(0.0)

func _mat(c: Color, rough: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _add(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	add_child(mi)
	return mi

func _cyl(rt: float, rb: float, h: float, seg: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

func _build_mound() -> void:
	var rock: StandardMaterial3D = _mat(Color(0.42, 0.41, 0.4))
	var dark: StandardMaterial3D = _mat(Color(0.3, 0.3, 0.31))
	var top_y: float = water_level + 1.7
	_add(_cyl(3.4, 6.2, 6.0, 7), rock, Vector3(0, top_y - 3.0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 11:
		var a: float = TAU * float(i) / 11.0 + rng.randf() * 0.4
		var r: float = rng.randf_range(3.2, 5.6)
		var s := SphereMesh.new()
		var sz: float = rng.randf_range(0.9, 1.9)
		s.radius = sz
		s.height = sz * 1.5
		s.radial_segments = 6
		s.rings = 3
		_add(s, rock if i % 2 == 0 else dark, Vector3(cos(a) * r, water_level + rng.randf_range(-0.3, 0.7), sin(a) * r), Vector3(rng.randf(), rng.randf() * TAU, rng.randf()), Vector3(1.2, 0.8, 1.0))
	for i in 4:
		var a2: float = TAU * float(i) / 4.0 + 0.5
		var s2 := SphereMesh.new()
		s2.radius = 1.4
		s2.height = 1.8
		s2.radial_segments = 6
		s2.rings = 3
		_add(s2, dark, Vector3(cos(a2) * 2.2, top_y + 0.1, sin(a2) * 2.2), Vector3(0.3 * i, a2, 0.2), Vector3(1.0, 0.7, 1.1))

func _build_tower() -> void:
	var base_y: float = water_level + 1.7
	var white: StandardMaterial3D = _mat(Color(0.93, 0.92, 0.88))
	var red: StandardMaterial3D = _mat(Color(0.75, 0.15, 0.12))
	var h: float = tower_height
	_add(_cyl(1.2, 1.8, h, 10), white, Vector3(0, base_y + h * 0.5, 0))
	for k in 3:
		var t: float = (float(k) + 0.5) / 3.0 * 0.62 + 0.08
		var y: float = base_y + h * t
		var rr: float = lerpf(1.8, 1.2, t) + 0.03
		_add(_cyl(rr, rr + 0.04, h * 0.1, 10), red, Vector3(0, y, 0))
	var dark: StandardMaterial3D = _mat(Color(0.12, 0.09, 0.07))
	var door := BoxMesh.new()
	door.size = Vector3(0.6, 1.1, 0.12)
	_add(door, dark, Vector3(0, base_y + 0.6, 1.72))
	var win := BoxMesh.new()
	win.size = Vector3(0.22, 0.4, 0.08)
	for k in 3:
		var wy: float = base_y + h * (0.28 + 0.2 * float(k))
		var wr: float = lerpf(1.8, 1.2, 0.28 + 0.2 * float(k)) - 0.02
		_add(win, dark, Vector3(0, wy, wr))
	var gal_y: float = base_y + h + 0.1
	_add(_cyl(2.0, 2.0, 0.3, 10), dark, Vector3(0, gal_y, 0))
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		_add(_cyl(0.04, 0.04, 0.9, 4), dark, Vector3(cos(a) * 1.95, gal_y + 0.55, sin(a) * 1.95))
	_add(_cyl(1.97, 1.97, 0.06, 12), dark, Vector3(0, gal_y + 1.0, 0))
	_lamp_y = gal_y + 1.1
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(1.0, 0.95, 0.75, 0.55)
	_lamp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.9, 0.6)
	_lamp_mat.emission_energy_multiplier = 0.0
	_lamp_mat.roughness = 0.1
	_add(_cyl(0.95, 0.95, 1.6, 10), _lamp_mat, Vector3(0, _lamp_y + 0.1, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(_cyl(0.03, 1.35, 1.2, 10), red, Vector3(0, _lamp_y + 1.5, 0))
	_add(_cyl(0.05, 0.05, 0.5, 4), dark, Vector3(0, _lamp_y + 2.3, 0))

func _make_cone(top_r: float, bottom_r: float, gain: float) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = top_r
	cone.bottom_radius = bottom_r
	cone.height = beam_length
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var m := ShaderMaterial.new()
	m.shader = BEAM_SHADER
	m.set_shader_parameter("gain", gain)
	_beam_mats.append(m)
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.x = PI / 2.0
	mi.position = Vector3(0, 0, -beam_length * 0.5)
	return mi

func _build_light() -> void:
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, _lamp_y + 0.1, 0)
	_pivot.rotation.y = randf() * TAU
	add_child(_pivot)
	_tilt = Node3D.new()
	_tilt.rotation.x = -0.15     # apunta hacia abajo para que el haz toque la isla
	_pivot.add_child(_tilt)

	# foco principal: sombras reales y suaves de todos los objetos
	_spot = SpotLight3D.new()
	_spot.light_color = Color(1.0, 0.94, 0.8)
	_spot.spot_angle = 11.0
	_spot.spot_angle_attenuation = 0.7
	_spot.spot_range = beam_length + 30.0
	_spot.light_energy = 0.0
	_spot.light_size = 0.08
	_spot.shadow_enabled = true
	_spot.shadow_bias = 0.04
	_spot.shadow_normal_bias = 1.0
	_spot.shadow_blur = 1.8
	_tilt.add_child(_spot)

	# haz visible: núcleo estrecho + envolvente ancha
	_tilt.add_child(_make_cone(0.25, 4.0, 1.0))
	_tilt.add_child(_make_cone(0.4, 11.0, 0.5))

	# resplandor fijo alrededor de la lámpara
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.88, 0.6)
	_glow.omni_range = 18.0
	_glow.light_energy = 0.0
	_glow.shadow_enabled = false
	_pivot.add_child(_glow)

	# destello de lente: crece cuando el haz apunta hacia el jugador
	_flare_mat = ShaderMaterial.new()
	_flare_mat.shader = FLARE_SHADER
	_flare = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_flare.mesh = quad
	_flare.material_override = _flare_mat
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flare.position = _pivot.position
	add_child(_flare)

	# luces de rebote (luz que "salta" del suelo, la arena y los troncos)
	for i in bounce_count:
		var o := OmniLight3D.new()
		o.top_level = true
		o.light_color = Color(1.0, 0.9, 0.7)
		o.omni_range = 9.0
		o.omni_attenuation = 1.6
		o.light_energy = 0.0
		o.shadow_enabled = false
		o.visible = false
		add_child(o)
		_bounces.append(o)
		_bounce_targets.append(Vector3.ZERO)
		_bounce_energy.append(0.0)

func _process(delta: float) -> void:
	if _pivot == null:
		return
	if _intensity > 0.001:
		_pivot.rotation.y -= TAU / rotation_period * delta
	_update_flare()

func _update_flare() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or _intensity <= 0.001:
		_flare.visible = false
		return
	_flare.visible = true
	var lamp: Vector3 = _pivot.global_position
	var to_cam: Vector3 = (cam.global_position - lamp).normalized()
	var fwd: Vector3 = -_tilt.global_basis.z
	var facing: float = pow(maxf(fwd.dot(to_cam), 0.0), 7.0)
	var s: float = lerpf(3.5, 22.0, facing)
	_flare.scale = Vector3(s, s, s)
	_flare_mat.set_shader_parameter("intensity", _intensity * lerpf(0.5, 1.6, facing))

func _physics_process(delta: float) -> void:
	if _pivot == null:
		return
	var on: bool = _intensity > 0.01
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = _pivot.global_position
	var base_basis: Basis = _tilt.global_basis
	# 1 rayo central + anillo dentro del cono
	for i in _bounces.size():
		var yaw_off: float = 0.0
		var pitch_off: float = 0.0
		if i > 0:
			var a: float = TAU * float(i - 1) / float(maxi(_bounces.size() - 1, 1))
			yaw_off = cos(a) * 0.07
			pitch_off = sin(a) * 0.07
		var dir: Vector3 = (base_basis * Basis.from_euler(Vector3(pitch_off, yaw_off, 0.0))) * Vector3(0, 0, -1)
		var target_energy: float = 0.0
		if on:
			var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + dir * (beam_length + 20.0), 1)
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty():
				var p: Vector3 = hit["position"]
				var n: Vector3 = hit["normal"]
				_bounce_targets[i] = p + n * 0.9
				var dist: float = origin.distance_to(p)
				var weight: float = 1.0 if i == 0 else 0.55
				target_energy = 2.6 * _intensity * weight * clampf(1.2 - dist / (beam_length + 20.0), 0.0, 1.0)
				# tinte según la superficie: arena cálida, pasto algo verdoso
				var col: Color = Color(1.0, 0.9, 0.68) if p.y < 1.3 else Color(0.85, 1.0, 0.72)
				_bounces[i].light_color = _bounces[i].light_color.lerp(col, 0.2)
		_bounce_energy[i] = lerpf(_bounce_energy[i], target_energy, clampf(5.0 * delta, 0.0, 1.0))
		var o: OmniLight3D = _bounces[i]
		o.global_position = o.global_position.lerp(_bounce_targets[i], clampf(8.0 * delta, 0.0, 1.0))
		o.light_energy = _bounce_energy[i]
		o.visible = _bounce_energy[i] > 0.02

## n: 0 = día, 1 = noche. Se apaga de día y se enciende al anochecer.
func set_night(n: float) -> void:
	_intensity = smoothstep(0.3, 0.7, n)
	var on: bool = _intensity > 0.01
	if _spot == null:
		return
	_spot.visible = on
	_glow.visible = on
	_spot.light_energy = 110.0 * _intensity
	_glow.light_energy = 2.2 * _intensity
	_lamp_mat.emission_energy_multiplier = 8.0 * _intensity
	for m: ShaderMaterial in _beam_mats:
		m.set_shader_parameter("intensity", _intensity)
