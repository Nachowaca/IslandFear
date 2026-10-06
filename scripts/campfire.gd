class_name Campfire
extends Node3D

## Fogata: llama con partículas, luz parpadeante, humo y leña que se consume.
## Se le puede echar más leña (add_fuel). Cuando se apaga quedan brasas y luego cenizas.

var fuel: float = 60.0                 ## segundos de fuego que quedan
const MAX_FUEL: float = 360.0
const EMBER_TIME: float = 25.0

var _light: OmniLight3D
var _flames: CPUParticles3D
var _smoke: CPUParticles3D
var _embers: MeshInstance3D
var _t: float = 0.0
var _ember_left: float = EMBER_TIME
var _crackle: float = 2.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("campfire")
	_rng.randomize()
	_t = _rng.randf() * 10.0
	_build()

func _mat(c: Color, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
	return m

func _build() -> void:
	# aro de piedras
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		var s := SphereMesh.new()
		s.radius = 0.11
		s.height = 0.2
		s.radial_segments = 5
		s.rings = 3
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = _mat(Color(0.42, 0.42, 0.45))
		mi.position = Vector3(cos(a) * 0.42, 0.06, sin(a) * 0.42)
		add_child(mi)
	# leños cruzados
	for i in 3:
		var c := CylinderMesh.new()
		c.top_radius = 0.05
		c.bottom_radius = 0.06
		c.height = 0.7
		c.radial_segments = 5
		var mi2 := MeshInstance3D.new()
		mi2.mesh = c
		mi2.material_override = _mat(Color(0.28, 0.17, 0.09))
		mi2.position = Vector3(0, 0.1, 0)
		mi2.rotation = Vector3(PI / 2.0 - 0.25, float(i) * 1.05, 0)
		add_child(mi2)
	# brasas (brillan cuando queda poco fuego)
	var e := SphereMesh.new()
	e.radius = 0.28
	e.height = 0.2
	e.radial_segments = 8
	e.rings = 3
	_embers = MeshInstance3D.new()
	_embers.mesh = e
	_embers.material_override = _mat(Color(1.0, 0.35, 0.08), true)
	_embers.position = Vector3(0, 0.1, 0)
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_embers)
	# llama
	_flames = CPUParticles3D.new()
	var q := SphereMesh.new()
	q.radius = 0.09
	q.height = 0.18
	q.radial_segments = 5
	q.rings = 3
	q.material = _mat(Color(1, 1, 1), true)
	_flames.mesh = q
	_flames.amount = 26
	_flames.lifetime = 0.8
	_flames.direction = Vector3.UP
	_flames.spread = 14.0
	_flames.initial_velocity_min = 0.6
	_flames.initial_velocity_max = 1.3
	_flames.gravity = Vector3(0, 0.6, 0)
	_flames.scale_amount_min = 0.5
	_flames.scale_amount_max = 1.2
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_flames.emission_sphere_radius = 0.2
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.9, 0.3, 1.0), Color(1.0, 0.45, 0.08, 0.9), Color(0.5, 0.1, 0.02, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_flames.color_ramp = g
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0.1))
	_flames.scale_amount_curve = sc
	_flames.position = Vector3(0, 0.2, 0)
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flames)
	# humo
	_smoke = CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 5
	sm.rings = 3
	sm.material = _mat(Color(1, 1, 1), true)
	_smoke.mesh = sm
	_smoke.amount = 14
	_smoke.lifetime = 3.5
	_smoke.direction = Vector3.UP
	_smoke.spread = 10.0
	_smoke.initial_velocity_min = 0.7
	_smoke.initial_velocity_max = 1.2
	_smoke.gravity = Vector3(0.15, 0.2, 0.05)
	_smoke.scale_amount_min = 0.8
	_smoke.scale_amount_max = 1.8
	var gs := Gradient.new()
	gs.colors = PackedColorArray([Color(0.35, 0.35, 0.35, 0.0), Color(0.4, 0.4, 0.42, 0.35), Color(0.5, 0.5, 0.52, 0.0)])
	gs.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	_smoke.color_ramp = gs
	_smoke.position = Vector3(0, 0.9, 0)
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_smoke)
	# luz
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.28)
	_light.omni_range = 11.0
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.8, 0)
	add_child(_light)

func add_fuel(seconds: float) -> void:
	fuel = minf(fuel + seconds, MAX_FUEL)
	_ember_left = EMBER_TIME

func is_burning() -> bool:
	return fuel > 0.0

func _process(delta: float) -> void:
	_t += delta
	var burning: bool = fuel > 0.0
	if burning:
		fuel = maxf(fuel - delta, 0.0)
		var k: float = clampf(fuel / 25.0, 0.25, 1.0)              # se achica al final
		_flames.emitting = true
		_flames.scale_amount_min = 0.5 * k
		_flames.scale_amount_max = 1.2 * k
		_smoke.emitting = true
		_light.light_energy = (1.6 + 0.5 * sin(_t * 17.0) + 0.3 * sin(_t * 31.0 + 1.3)) * k
		_light.omni_range = 11.0 * (0.6 + 0.4 * k)
		_embers.visible = true
		(_embers.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.35 + 0.1 * sin(_t * 9.0), 0.08)
		_crackle -= delta
		if _crackle <= 0.0:
			_crackle = _rng.randf_range(1.5, 5.0)
			AudioManager.play(get_tree(), "crack", global_position, -16.0)
	else:
		_flames.emitting = false
		_smoke.emitting = _ember_left > 0.0 and _smoke.emitting
		_ember_left = maxf(_ember_left - delta, 0.0)
		var glow: float = clampf(_ember_left / EMBER_TIME, 0.0, 1.0)
		_light.light_energy = 0.5 * glow * (0.8 + 0.2 * sin(_t * 5.0))
		_embers.visible = glow > 0.02
		(_embers.material_override as StandardMaterial3D).albedo_color = Color(0.9 * glow + 0.1, 0.2 * glow, 0.04)
		if glow <= 0.0:
			_smoke.emitting = false
