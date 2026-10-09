class_name LookDestello
extends CanvasLayer

## Destello de lente cuando la cámara mira hacia el sol. Un solo ColorRect con shader aditivo.
## Se apaga si un tronco o roca tapa el sol (rayo de física) y con clima nublado.

var player: Node3D

var _rect: ColorRect
var _mat: ShaderMaterial
var _obj: float = 0.0
var _k: float = 0.0
var _dir: Vector3 = Vector3.UP
var _on: bool = true
var _oclusion: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	layer = 5
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/look_destello.gdshader") as Shader
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)

## dir: hacia el sol; fuerza 0..1 (altura del sol y clima); on: interruptor del look.
func set_sol(dir: Vector3, color: Color, fuerza: float, on: bool) -> void:
	_dir = dir.normalized()
	_obj = fuerza
	_on = on
	_mat.set_shader_parameter("color", Vector3(color.r, color.g, color.b).lerp(Vector3(1.0, 0.9, 0.7), 0.4))

func _process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not _on or _obj <= 0.01:
		_k = lerpf(_k, 0.0, 1.0 - exp(-6.0 * delta))
		_rect.visible = _k > 0.01
		_mat.set_shader_parameter("strength", _k)
		return
	var fwd: Vector3 = -cam.global_transform.basis.z
	var alineado: float = smoothstep(0.55, 0.96, fwd.dot(_dir))
	# ocultacion: un rayo hacia el sol, cada 0.1 s
	_t -= delta
	if _t <= 0.0:
		_t = 0.1
		var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + _dir * 150.0)
		if player is CollisionObject3D:
			q.exclude = [(player as CollisionObject3D).get_rid()]
		_oclusion = 1.0 if not space.intersect_ray(q).is_empty() else 0.0
	var obj: float = alineado * _obj * (1.0 - _oclusion * 0.85)
	_k = lerpf(_k, obj, 1.0 - exp(-5.0 * delta))
	_rect.visible = _k > 0.005
	if not _rect.visible:
		return
	var sp: Vector2 = cam.unproject_position(cam.global_position + _dir * 500.0)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("sun_uv", sp / vs)
	_mat.set_shader_parameter("aspect", vs.x / vs.y)
	_mat.set_shader_parameter("strength", _k)
