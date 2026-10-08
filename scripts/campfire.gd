class_name Campfire
extends Node3D

## Fogata: llama con partículas, luz parpadeante, humo y leña que se consume.
## Se le puede echar más leña (add_fuel). Cuando se apaga quedan brasas y luego cenizas.

var fuel: float = 60.0                 ## segundos de fuego que quedan
const MAX_FUEL: float = 360.0
const EMBER_TIME: float = 25.0

var _light: OmniLight3D
var _halo: Sprite3D
var _flames: CPUParticles3D
var _smoke: CPUParticles3D
var _embers: MeshInstance3D
var _model: Node3D                     ## fogata con llama animada (encendida)
var _dead: Array[Node3D] = []          ## piedras y leños simples (apagada)
const LOWPOLY_SCENE: PackedScene = preload("res://assets/campfire/low_poly_campfire.glb")
const LOWPOLY_SCALE: float = 0.15
var _flame_nodes: Array[Node3D] = []
var _fk: float = 0.0                   ## nivel de la llama 0..1 (animación de encendido y de apagado)
const FLAME_H: float = 0.8             ## altura de las llamas respecto del modelo (más recogidas)
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
		_dead.append(mi)
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
		_dead.append(mi2)
	_model = LOWPOLY_SCENE.instantiate() as Node3D
	var dirt: Node = _model.find_child("polySurface7", true, false)
	if dirt != null:
		dirt.get_parent().remove_child(dirt)
		dirt.free()
	var stone_mat := StandardMaterial3D.new()          # piedras más claras: el original se ve casi negro sobre el pasto
	stone_mat.albedo_color = Color(0.5, 0.48, 0.45)
	stone_mat.roughness = 1.0
	for rk: Node in _model.find_children("*_rock_*", "MeshInstance3D", true, false):
		(rk as MeshInstance3D).material_override = stone_mat
	for mi3: Node in _model.find_children("*fire*", "MeshInstance3D", true, false):
		_flame_nodes.append(mi3.get_parent() as Node3D)
	_model.scale = Vector3.ONE * LOWPOLY_SCALE
	_model.position = Vector3(0, 0.11, 0)
	add_child(_model)
	_build_rest()

func _build_rest() -> void:
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
	_flames.mesh = _soft_quad(0.3, true)
	_flames.amount = 10
	_flames.lifetime = 0.8
	_flames.direction = Vector3.UP
	_flames.spread = 14.0
	_flames.initial_velocity_min = 0.6
	_flames.initial_velocity_max = 1.3
	_flames.gravity = Vector3(0, 0.6, 0)
	_flames.scale_amount_min = 0.6
	_flames.scale_amount_max = 1.4
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_flames.emission_sphere_radius = 0.2
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.9, 0.3, 0.5), Color(1.0, 0.45, 0.08, 0.4), Color(0.5, 0.1, 0.02, 0.0)])
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
	_smoke.mesh = _soft_quad(0.9, false)
	_smoke.amount = 14
	_smoke.lifetime = 3.5
	_smoke.direction = Vector3.UP
	_smoke.spread = 10.0
	_smoke.initial_velocity_min = 0.7
	_smoke.initial_velocity_max = 1.2
	_smoke.gravity = Vector3(0.15, 0.2, 0.05)
	_smoke.scale_amount_min = 0.9
	_smoke.scale_amount_max = 2.2
	var ssc := Curve.new()
	ssc.add_point(Vector2(0, 0.4))
	ssc.add_point(Vector2(1, 1.6))
	_smoke.scale_amount_curve = ssc
	var gs := Gradient.new()
	gs.colors = PackedColorArray([Color(0.3, 0.27, 0.26, 0.0), Color(0.33, 0.3, 0.3, 0.2), Color(0.3, 0.3, 0.32, 0.0)])
	gs.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	_smoke.color_ramp = gs
	_smoke.position = Vector3(0, 0.9, 0)
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_smoke)
	# luz
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.58, 0.22)
	_light.omni_range = 18.0
	_light.omni_attenuation = 2.2          # caída suave: sin borde duro donde termina la luz
	_light.light_specular = 0.4
	_halo = Sprite3D.new()      # halo cálido de brillo, estilo farol
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1.0, 0.75, 0.35, 0.55), Color(1.0, 0.55, 0.2, 0.28), Color(1.0, 0.45, 0.12, 0.1), Color(1.0, 0.4, 0.08, 0.03), Color(1.0, 0.4, 0.05, 0.0)])
	gr.offsets = PackedFloat32Array([0.0, 0.18, 0.4, 0.7, 1.0])
	gt.gradient = gr
	_halo.texture = gt
	_halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_halo.shaded = false
	_halo.double_sided = true
	_halo.transparent = true
	_halo.pixel_size = 0.02
	_halo.position = Vector3(0, 0.6, 0)
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.material_override = _halo_mat()
	add_child(_halo)
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.3, 0)
	add_child(_light)

## Quad con textura radial suave (sin facetas): llama aditiva o humo translúcido.
func _soft_quad(size: float, additive: bool) -> QuadMesh:
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	gt.gradient = g
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.albedo_texture = gt
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	return q

func _halo_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _halo.texture
	m.no_depth_test = false
	return m

func add_fuel(seconds: float) -> void:
	fuel = minf(fuel + seconds, MAX_FUEL)
	_ember_left = EMBER_TIME

func is_burning() -> bool:
	return fuel > 0.0

## Durabilidad del fuego de 0 a 100 (100 = tanque lleno de leña).
func durability() -> float:
	return clampf(fuel / MAX_FUEL * 100.0, 0.0, 100.0)

func _process(delta: float) -> void:
	_t += delta
	var burning: bool = fuel > 0.0
	var target: float = 0.0
	if burning:
		fuel = maxf(fuel - delta, 0.0)
		var dk: float = lerpf(0.4, 1.0, durability() / 100.0)      # más leña, llama más alta
		target = dk * clampf(fuel / 25.0, 0.3, 1.0)               # se achica al final
		_crackle -= delta
		if _crackle <= 0.0:
			_crackle = _rng.randf_range(1.5, 5.0)
			AudioManager.play(get_tree(), "crack", global_position, -16.0)
	# la llama crece al encender o echar leña (rápido) y se apaga despacio (animación de consumirse)
	var rate: float = 0.9 if target > _fk else 0.45
	var was: float = _fk
	_fk = move_toward(_fk, target, rate * delta)
	var dying: bool = not burning and _fk > 0.02
	if dying and was > _fk and not _smoke.emitting:
		_smoke.emitting = true
	_smoke.speed_scale = 1.8 if dying else 1.0
	_flames.emitting = false
	_smoke.emitting = _fk > 0.03 or (_ember_left > 0.0 and not burning and _smoke.emitting)
	if not burning and _fk <= 0.02:
		_ember_left = maxf(_ember_left - delta, 0.0)
	var glow: float = clampf(_ember_left / EMBER_TIME, 0.0, 1.0) if not burning else 0.0
	var fl: float = 1.4 + 0.35 * sin(_t * 17.0) + 0.2 * sin(_t * 31.0 + 1.3)
	if dying:
		fl *= 0.8 + 0.2 * sin(_t * 33.0)                         # titila al morir
	_light.light_energy = maxf(fl * _fk, 0.5 * glow * (0.8 + 0.2 * sin(_t * 5.0)))
	_light.omni_range = 14.0 * (0.6 + 0.4 * _fk)
	_halo.visible = _fk > 0.02
	_halo.scale = Vector3.ONE * maxf(_fk, 0.01) * (1.0 + 0.06 * sin(_t * 13.0))
	_embers.visible = glow > 0.02 or (dying and _fk < 0.5)
	var eg: float = maxf(glow, 1.0 - _fk * 2.0 if dying else 0.0)
	(_embers.material_override as StandardMaterial3D).albedo_color = Color(0.9 * eg + 0.1, 0.2 * eg, 0.04)
	for d: Node3D in _dead:
		d.visible = false
	for i in _flame_nodes.size():
		var fn: Node3D = _flame_nodes[i]
		fn.visible = _fk > 0.03
		var ph: float = float(i) * 1.7
		var wob: float = 1.0 + 0.1 * sin(_t * 7.0 + ph * 1.3) + 0.05 * sin(_t * 19.0 + ph)
		if dying:
			wob *= 0.85 + 0.15 * sin(_t * 30.0 + ph)
		var wd: float = lerpf(0.5, 1.0, _fk)
		fn.scale = Vector3((1.0 + 0.05 * sin(_t * 9.0 + ph)) * wd, wob * _fk * FLAME_H, (1.0 + 0.05 * cos(_t * 8.0 + ph)) * wd)
