class_name AmbientFx
extends Node3D

## Partículas de ambiente que siguen al jugador: hojas cayendo y polen/polvo flotando en la luz.

var _leaves: CPUParticles3D
var _pollen: CPUParticles3D
var _player: Node3D

var _pollen_mat: StandardMaterial3D

## 0 = día (polen dorado), 1 = noche (luciérnagas verdosas y más brillantes).
func set_night(n: float) -> void:
	if _pollen_mat == null:
		return
	var c: Color = Color(1.0, 0.9, 0.6).lerp(Color(0.7, 1.0, 0.25), n)
	_pollen_mat.emission = c
	_pollen_mat.albedo_color = Color(c.r, c.g, c.b, 0.8)
	_pollen_mat.emission_energy_multiplier = lerpf(6.5, 7.0, n)
	_leaves.visible = n < 0.6

func _ready() -> void:
	add_to_group("ambient_fx")
	_leaves = _make_leaves()
	add_child(_leaves)
	_pollen = _make_pollen()
	add_child(_pollen)

func _make_leaves() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.055)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	# forma de hoja ovalada (no un rectangulo plano)
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	mat.albedo_texture = gt
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.45
	quad.material = mat
	p.mesh = quad
	p.amount = 80
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(22, 0.5, 22)
	p.position = Vector3(0, 13, 0)
	p.direction = Vector3(1, 0, 0.3)
	p.spread = 40.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0.5, -1.0, 0.2)
	p.damping_min = 0.7
	p.damping_max = 1.0
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	p.color = Color(0.4, 0.62, 0.2)
	p.hue_variation_min = -0.1
	p.hue_variation_max = 0.12
	return p

func _make_pollen() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var s := SphereMesh.new()
	s.radius = 0.02
	s.height = 0.04
	s.radial_segments = 8
	s.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.7, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.6)
	mat.emission_energy_multiplier = 2.5
	s.material = mat
	_pollen_mat = mat
	p.mesh = s
	p.amount = 220
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(20, 4, 20)
	p.position = Vector3(0, 3.5, 0)
	p.direction = Vector3(1, 0.2, 0.3)
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.45
	p.gravity = Vector3(0.12, 0.02, 0.05)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.3
	return p

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		return
	global_position = Vector3(_player.global_position.x, 0.0, _player.global_position.z)
