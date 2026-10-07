class_name LookContacto
extends MultiMeshInstance3D

## Sombras de contacto: una mancha suave y oscura (teal) bajo cada árbol y palmera. Un solo MultiMesh.
## Se reconstruye (barato) solo si cambia la cantidad de árboles (talas).

var terrain: IslandTerrain

var _mat: ShaderMaterial
var _cuenta: int = -1
var _t: float = 0.0

func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/look_contacto.gdshader") as Shader
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	visibility_range_end = 120.0
	visibility_range_end_margin = 15.0
	visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_reconstruir()

func set_fuerza(f: float) -> void:
	_mat.set_shader_parameter("strength", f)

func _process(delta: float) -> void:
	_t += delta
	if _t > 3.0:
		_t = 0.0
		if terrain != null and terrain.tree_positions.size() + terrain.palm_positions.size() != _cuenta:
			_reconstruir()

func _reconstruir() -> void:
	if terrain == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	mm.mesh = q
	var n_t: int = terrain.tree_positions.size()
	var n_p: int = terrain.palm_positions.size()
	mm.instance_count = n_t + n_p
	for i in n_t:
		var p: Vector3 = terrain.tree_positions[i]
		var s: float = (terrain.tree_scales[i] if i < terrain.tree_scales.size() else 1.0) * 4.2
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, 1.0, s)), Vector3(p.x, p.y + 0.07, p.z)))
	for k in n_p:
		var pp: Vector3 = terrain.palm_positions[k]
		mm.set_instance_transform(n_t + k, Transform3D(Basis.from_scale(Vector3(3.2, 1.0, 3.2)), Vector3(pp.x, pp.y + 0.07, pp.z)))
	multimesh = mm
	_cuenta = n_t + n_p
