class_name LookHaces
extends Node3D

## "Volumétrica" falsa y barata: haces de luz (planos cruzados con shader aditivo) y bruma en capas
## (planos horizontales con ruido) alrededor del jugador. Todo se crea una sola vez; el LookDirector
## solo cambia cuántos se ven. Sin textura de profundidad.

const SHAFT_MAX: int = 14
const LAYER_MAX: int = 3
const RADIO: float = 46.0
const CAPAS_Y: Array[float] = [3.5, 6.0, 9.0]     ## sobre el suelo del jugador (más bajas cortaban el terreno y dejaban "charcos" con borde duro)

var player: Node3D
var terrain: IslandTerrain

var _shafts: Array[MeshInstance3D] = []
var _shaft_mat: ShaderMaterial
var _layers: Array[MeshInstance3D] = []
var _layer_mats: Array[ShaderMaterial] = []
var _rng := RandomNumberGenerator.new()
var _dir: Vector3 = Vector3.UP
var _k_haz: float = 0.0
var _k_haz_obj: float = 0.0
var _k_bruma: float = 0.0
var _k_bruma_obj: float = 0.0
var n_haces: int = 0
var n_capas: int = 0
var activo: bool = true

func _ready() -> void:
	_rng.seed = 424242
	top_level = true
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = load("res://shaders/look_haz.gdshader") as Shader
	var mesh: ArrayMesh = _shaft_mesh()
	for i in SHAFT_MAX:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _shaft_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.set_meta("w", _rng.randf_range(2.6, 5.2))
		mi.set_meta("l", _rng.randf_range(14.0, 26.0))
		add_child(mi)
		mi.global_position = Vector3(0, -500, 0)
		_shafts.append(mi)
	var plane := PlaneMesh.new()
	plane.size = Vector2(190, 190)
	for j in LAYER_MAX:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/look_bruma.gdshader") as Shader
		m.set_shader_parameter("layer_seed", float(j) * 1.7 + 0.3)
		var mi2 := MeshInstance3D.new()
		mi2.mesh = plane
		mi2.material_override = m
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi2.visible = false
		add_child(mi2)
		_layers.append(mi2)
		_layer_mats.append(m)

func _shaft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads: Array = [
		[Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, -0.5), Vector3(0, 0, 0.5), Vector3(0, 1, 0.5), Vector3(0, 1, -0.5), Vector3(1, 0, 0)],
	]
	for q: Array in quads:
		var nrm: Vector3 = q[4]
		var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for idx: Array in [[0, 1, 2], [0, 2, 3]]:
			for k: int in idx:
				st.set_normal(nrm)
				st.set_uv(uvs[k])
				st.add_vertex(q[k])
	return st.commit()

## Luz que produce los haces: dirección HACIA la luz (sol o luna), su color y qué tan fuertes (0..1).
func set_luz(hacia_luz: Vector3, color: Color, fuerza: float) -> void:
	_dir = hacia_luz.normalized()
	_shaft_mat.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	_k_haz_obj = fuerza

func set_bruma(color: Color, fuerza: float) -> void:
	_k_bruma_obj = fuerza
	for m: ShaderMaterial in _layer_mats:
		m.set_shader_parameter("mist_color", color)

func set_cantidades(haces: int, capas: int) -> void:
	n_haces = clampi(haces, 0, SHAFT_MAX)
	n_capas = clampi(capas, 0, LAYER_MAX)

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var k: float = 1.0 - exp(-1.5 * delta)
	_k_haz = lerpf(_k_haz, _k_haz_obj if activo else 0.0, k)
	_k_bruma = lerpf(_k_bruma, _k_bruma_obj if activo else 0.0, k)
	var pp: Vector3 = player.global_position
	# haces
	_shaft_mat.set_shader_parameter("intensity", _k_haz)
	var ver_haces: bool = activo and _k_haz > 0.01 and _dir.y > 0.03
	for i in SHAFT_MAX:
		var mi: MeshInstance3D = _shafts[i]
		var on: bool = ver_haces and i < n_haces
		mi.visible = on
		if not on:
			continue
		var d2: float = Vector2(mi.global_position.x - pp.x, mi.global_position.z - pp.z).length()
		if d2 > RADIO + 6.0:
			_recolocar(mi, pp)
		_orientar(mi)
	# bruma
	for j in LAYER_MAX:
		var on2: bool = activo and _k_bruma > 0.01 and j < n_capas
		_layers[j].visible = on2
		if not on2:
			continue
		_layer_mats[j].set_shader_parameter("intensity", _k_bruma)
		var suelo: float = maxf(terrain.height_at(pp.x, pp.z), 0.0) if terrain != null else 0.0
		_layers[j].global_position = Vector3(pp.x, suelo + CAPAS_Y[j], pp.z)

func _recolocar(mi: MeshInstance3D, pp: Vector3) -> void:
	for t in 8:
		var a: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(10.0, RADIO - 4.0)
		var x: float = pp.x + cos(a) * r
		var z: float = pp.z + sin(a) * r
		var h: float = terrain.height_at(x, z) if terrain != null else 1.5
		if h < 0.9:
			continue
		mi.global_position = Vector3(x, h - 1.0, z)
		return
	mi.global_position = Vector3(pp.x + 9999.0, -500.0, pp.z)     # sin lugar: queda fuera de vista

func _orientar(mi: MeshInstance3D) -> void:
	var y: Vector3 = _dir
	var x: Vector3 = Vector3.UP.cross(y)
	if x.length() < 0.05:
		x = Vector3.RIGHT
	x = x.normalized()
	var z: Vector3 = x.cross(y).normalized()
	var w: float = float(mi.get_meta("w"))
	var l: float = float(mi.get_meta("l"))
	mi.global_transform = Transform3D(Basis(x * w, y * l, z * w), mi.global_position)
