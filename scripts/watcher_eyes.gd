class_name WatcherEyes
extends Node3D

## Un par de ojos que brillan entre los árboles y observan al jugador. Parpadean y se desvanecen
## si el jugador se acerca (o pasado un tiempo).

var player: Node3D
var life: float = 14.0
var eye_color: Color = Color(1.0, 0.75, 0.2)
var flee_distance: float = 7.0
var fixed_facing: bool = false

var _t: float = 0.0
var _eyes: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D
var _fade: float = 0.0
var _blink_at: float = 2.0
var _closing: bool = false

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = eye_color
	_mat.emission_enabled = true
	_mat.emission = eye_color
	_mat.emission_energy_multiplier = 4.0
	var s := SphereMesh.new()
	s.radius = 0.06
	s.height = 0.12
	s.radial_segments = 6
	s.rings = 3
	for sx: float in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = _mat
		mi.position = Vector3(0.16 * sx, 0.0, 0.0)
		mi.scale = Vector3(1.4, 0.8, 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_eyes.append(mi)
	scale = Vector3.ZERO

func _process(delta: float) -> void:
	_t += delta
	if player != null and is_instance_valid(player) and not fixed_facing:
		var to: Vector3 = player.global_position + Vector3(0, 1.4, 0) - global_position
		rotation.y = atan2(-to.x, -to.z) + PI
		if to.length() < flee_distance:
			_closing = true
	if _t > life:
		_closing = true
	# aparecer / desaparecer
	_fade = move_toward(_fade, 0.0 if _closing else 1.0, delta * (3.0 if _closing else 1.2))
	scale = Vector3.ONE * _fade
	if _closing and _fade <= 0.0:
		queue_free()
		return
	# parpadeo
	var open: float = 1.0
	if _t > _blink_at:
		var bt: float = _t - _blink_at
		open = 1.0 - clampf(1.0 - absf(bt - 0.08) / 0.08, 0.0, 1.0)
		if bt > 0.2:
			_blink_at = _t + randf_range(1.5, 4.5)
	for e: MeshInstance3D in _eyes:
		e.scale.y = 0.8 * open + 0.05
