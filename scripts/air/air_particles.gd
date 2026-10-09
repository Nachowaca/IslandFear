class_name AirParticles
extends Node3D

## Partículas decorativas del aire: semillas voladoras, pétalos y rocío de amanecer.

# --- Parámetros ajustables ---
const SEEDS_AMOUNT: int = 25
const SEEDS_BOX: Vector3 = Vector3(15.0, 3.0, 15.0)  # extents (caja 30x6x30)
const SEEDS_HEIGHT: float = 2.5  # altura sobre el jugador
const SEEDS_LIFETIME: float = 20.0
const SEEDS_WIND: Vector3 = Vector3(0.05, -0.01, 0.02)
const PETALS_AMOUNT: int = 30
const PETALS_BOX: Vector3 = Vector3(12.0, 0.5, 12.0)
const PETALS_HEIGHT: float = 7.0
const PETALS_LIFETIME: float = 14.0
const DEW_AMOUNT: int = 40
const DEW_BOX: Vector3 = Vector3(8.0, 0.5, 8.0)  # caja 16x1x16
const DEW_LIFETIME: float = 3.5
const DEW_GROUND_OFFSET: float = 0.3  # centro de la caja sobre el suelo
const DEW_START: float = 5.0
const DEW_FULL_END: float = 9.0
const DEW_FADE_END: float = 10.0
const NIGHT_LIMIT: float = 0.6

var player: Node3D
var terrain: IslandTerrain

var _seeds: CPUParticles3D
var _petals: CPUParticles3D
var _dew: CPUParticles3D
var _glints: CPUParticles3D
var _noche: float = 0.0
var _dew_k: float = 0.0

func _ready() -> void:
	top_level = true
	_seeds = _make_seeds()
	add_child(_seeds)
	_petals = _make_petals()
	add_child(_petals)
	_dew = _make_dew()
	add_child(_dew)
	_glints = _make_glints()
	add_child(_glints)
	set_hora(12.0, 0.0)

## hora: 0..24, noche: 0 día .. 1 noche.
func set_hora(hora: float, noche: float) -> void:
	_noche = noche
	var day: bool = noche <= NIGHT_LIMIT
	if _seeds:
		_seeds.emitting = day
		_petals.emitting = day
		_glints.emitting = noche < 0.3
	# Rocío: sube de 5 a 6, pleno hasta 9, se desvanece a las 10
	var k: float = 0.0
	if hora >= DEW_START and hora < DEW_FADE_END:
		k = clampf((hora - DEW_START) / 1.0, 0.0, 1.0)
		if hora > DEW_FULL_END:
			k = 1.0 - (hora - DEW_FULL_END) / (DEW_FADE_END - DEW_FULL_END)
	k *= clampf(1.0 - noche, 0.0, 1.0)
	_dew_k = clampf(k, 0.0, 1.0)
	if _dew:
		_dew.emitting = _dew_k > 0.01
		_dew.color = Color(1.0, 1.0, 1.0, _dew_k)

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var p: Vector3 = player.global_position
	global_position = Vector3(p.x, 0.0, p.z)
	var gy: float = p.y - 1.0
	if terrain != null and is_instance_valid(terrain):
		gy = terrain.height_at(p.x, p.z)
	_dew.position = Vector3(0.0, gy + DEW_GROUND_OFFSET, 0.0)
	_seeds.position = Vector3(0.0, p.y + SEEDS_HEIGHT, 0.0)
	_petals.position = Vector3(0.0, p.y + PETALS_HEIGHT, 0.0)
	_glints.position = Vector3(0.0, p.y + 1.6, 0.0)

# Textura de círculo suave (alpha radial)
func _soft_tex(size: int) -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = size
	gt.height = size
	return gt

func _make_mat(unshaded: bool, scissor: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_tex(32)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if scissor:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.4
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func _fade_curve() -> Curve:
	# Aparece y se apaga suavemente (escala 0 -> 1 -> 0)
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.2, 1.0))
	c.add_point(Vector2(0.8, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c

func _make_seeds() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var mat: StandardMaterial3D = _make_mat(true, false)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.92, 0.75)
	mat.emission_energy_multiplier = 0.6
	quad.material = mat
	p.mesh = quad
	p.amount = SEEDS_AMOUNT
	p.lifetime = SEEDS_LIFETIME
	p.preprocess = SEEDS_LIFETIME
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = SEEDS_BOX
	p.direction = Vector3(1, 0.1, 0.3)
	p.spread = 60.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.35
	p.gravity = SEEDS_WIND
	p.tangential_accel_min = -0.05
	p.tangential_accel_max = 0.05
	p.damping_min = 0.05
	p.damping_max = 0.2
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3  # 0.05-0.09 m con el quad de 0.07
	p.scale_amount_curve = _fade_curve()
	p.color = Color(1.0, 0.97, 0.9, 0.7)
	p.hue_variation_min = -0.02
	p.hue_variation_max = 0.04
	return p

func _make_petals() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.06)  # óvalo
	var mat: StandardMaterial3D = _make_mat(false, true)
	mat.roughness = 1.0
	quad.material = mat
	p.mesh = quad
	p.amount = PETALS_AMOUNT
	p.lifetime = PETALS_LIFETIME
	p.preprocess = PETALS_LIFETIME
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = PETALS_BOX
	p.direction = Vector3(1, -0.2, 0.3)
	p.spread = 50.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.gravity = Vector3(0.12, -0.45, 0.05)
	p.damping_min = 0.3
	p.damping_max = 0.8
	p.angle_max = 360.0
	p.angular_velocity_min = -120.0
	p.angular_velocity_max = 120.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	# Colores: rosa, blanco, amarillo
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gr.colors = PackedColorArray([
		Color(1.0, 0.65, 0.78), Color(1.0, 0.97, 0.95), Color(1.0, 0.88, 0.4)])
	p.color_initial_ramp = gr
	return p

func _make_dew() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	var mat: StandardMaterial3D = _make_mat(true, false)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.97, 1.0)
	mat.emission_energy_multiplier = 2.0
	quad.material = mat
	p.mesh = quad
	p.amount = DEW_AMOUNT
	p.lifetime = DEW_LIFETIME
	p.lifetime_randomness = 0.6
	p.preprocess = DEW_LIFETIME
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = DEW_BOX
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.01
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.75
	p.scale_amount_max = 1.25
	# Parpadeo: brilla y se apaga durante su vida corta
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.35, 1.0))
	c.add_point(Vector2(0.55, 0.5))
	c.add_point(Vector2(0.75, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = c
	p.color = Color(1.0, 1.0, 1.0, 0.0)
	p.emitting = false
	return p

## Destellos de sol: chispitas doradas que se encienden y apagan en el aire durante el dia.
func _make_glints() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var mat: StandardMaterial3D = _make_mat(true, false)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.6)
	mat.emission_energy_multiplier = 5.0
	quad.material = mat
	p.mesh = quad
	p.amount = 70
	p.lifetime = 2.4
	p.lifetime_randomness = 0.6
	p.preprocess = 2.4
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14.0, 3.0, 14.0)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.06
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(0.45, 0.25))
	c.add_point(Vector2(0.6, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = c
	p.color = Color(1.0, 0.95, 0.8, 0.9)
	return p
