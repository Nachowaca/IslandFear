class_name RiverWater
extends Node3D

## Superficie del río fino (cinta de agua sobre el cauce que cava IslandRiver). Copia los colores y el cielo del mar para
## que cambie con la hora.

const SHADER: Shader = preload("res://shaders/river_island.gdshader")
const HALF_W: float = 3.2
const ACROSS: int = 9

var terrain: IslandTerrain
var _mat: ShaderMaterial
var _timer: float = 0.0
var _daynight: Node

func _ready() -> void:
	if terrain == null or terrain.river == null or not terrain.river.valid:
		return
	var rv: IslandRiver = terrain.river
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = rv.pts.size()
	var rows: Array = []
	var along: float = 0.0
	for k in n:
		var p: Vector2 = rv.pts[k]
		var a: Vector2 = rv.pts[maxi(k - 1, 0)]
		var b: Vector2 = rv.pts[mini(k + 1, n - 1)]
		var tang: Vector2 = (b - a).normalized()
		var side: Vector2 = Vector2(-tang.y, tang.x)
		if k > 0:
			along += rv.pts[k - 1].distance_to(p)
		var row: Array = []
		for c in ACROSS:
			var u: float = float(c) / float(ACROSS - 1)
			var q: Vector2 = p + side * ((u - 0.5) * 2.0 * HALF_W)
			var wy: float = rv.wl[k]
			var depth: float = wy - terrain.mesh_height_at(q.x, q.y)
			var al: float = smoothstep(-0.05, 0.3, depth)
			row.append({"pos": Vector3(q.x, wy, q.y), "uv": Vector2(u, along / 3.0), "a": al})
		rows.append(row)
	for k in n - 1:
		for c in ACROSS - 1:
			var v00: Dictionary = rows[k][c]
			var v10: Dictionary = rows[k][c + 1]
			var v01: Dictionary = rows[k + 1][c]
			var v11: Dictionary = rows[k + 1][c + 1]
			if float(v00["a"]) + float(v10["a"]) + float(v01["a"]) + float(v11["a"]) < 0.01:
				continue
			for tri: Array in [[v00, v10, v01], [v10, v11, v01]]:
				for v: Dictionary in tri:
					st.set_color(Color(1, 1, 1, float(v["a"])))
					st.set_uv(v["uv"])
					st.set_normal(Vector3.UP)
					st.add_vertex(v["pos"])
	var mi := MeshInstance3D.new()
	mi.name = "RiverSurface"
	mi.mesh = st.commit()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	call_deferred("_sync")

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.4
		_sync()

func _sync() -> void:
	if _mat == null:
		return
	if _daynight == null:
		_daynight = get_tree().get_first_node_in_group("daynight")
	if _daynight == null or not _daynight.has_method("water_mat"):
		return
	var sea: ShaderMaterial = _daynight.call("water_mat") as ShaderMaterial
	if sea == null:
		return
	var deep: Color = sea.get_shader_parameter("deep_color")
	var shallow: Color = sea.get_shader_parameter("shallow_color")
	_mat.set_shader_parameter("deep_color", deep.lerp(Color(0.04, 0.26, 0.22), 0.45))
	_mat.set_shader_parameter("shallow_color", shallow.lerp(Color(0.2, 0.55, 0.42), 0.4))
	for key: String in ["sky_color", "zenith_color", "moon_dir", "moon_glow", "moon_tint", "sun_dir", "sun_glow", "sun_tint"]:
		var v: Variant = sea.get_shader_parameter(key)
		if v != null:
			_mat.set_shader_parameter(key, v)
