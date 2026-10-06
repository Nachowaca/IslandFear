class_name Weather
extends Node
## Lluvia ocasional. Cae alrededor de la cámara y se corta bajo techo (el pozo de la cueva protege).
## `intensity` 0..1 es cuánta lluvia hay en el cielo; `exposed` 0..1 cuánto te toca a vos.

@export var clear_min: float = 150.0
@export var clear_max: float = 320.0
@export var rain_min: float = 70.0
@export var rain_max: float = 140.0
## Fuerza lluvia (true) o la corta (false) para probar; null = ciclo normal.
@export var debug_force_rain: bool = false

var player: Node3D
var features: IslandFeatures
var raining: bool = false
var intensity: float = 0.0
var exposed: float = 0.0

var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _drops: CPUParticles3D
var _shelter: float = 0.0

func _ready() -> void:
	add_to_group("weather")
	_rng.randomize()
	_timer = _rng.randf_range(clear_min * 0.4, clear_max * 0.7)
	_drops = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.75, 0.85, 1.0, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	_drops.mesh = q
	_drops.amount = 1100
	_drops.lifetime = 0.9
	_drops.preprocess = 0.9
	_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drops.emission_box_extents = Vector3(18.0, 0.5, 18.0)
	_drops.direction = Vector3(0.12, -1.0, 0.05)
	_drops.spread = 3.0
	_drops.gravity = Vector3(0.0, -22.0, 0.0)
	_drops.initial_velocity_min = 14.0
	_drops.initial_velocity_max = 18.0
	_drops.local_coords = false
	_drops.emitting = false
	_drops.visibility_aabb = AABB(Vector3(-30, -25, -30), Vector3(60, 40, 60))
	add_child(_drops)

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		raining = not raining
		_timer = _rng.randf_range(rain_min, rain_max) if raining else _rng.randf_range(clear_min, clear_max)
	var want: bool = raining or debug_force_rain
	intensity = move_toward(intensity, 1.0 if want else 0.0, delta / 6.0)
	var in_shelter: bool = player != null and features != null and features.is_inside_cave(player.global_position)
	_shelter = move_toward(_shelter, 1.0 if in_shelter else 0.0, delta * 2.0)
	exposed = intensity * (1.0 - _shelter)
	var cam: Camera3D = get_viewport().get_camera_3d()
	_drops.emitting = exposed > 0.05
	if cam != null:
		_drops.global_position = cam.global_position + Vector3(0.0, 13.0, 0.0)
