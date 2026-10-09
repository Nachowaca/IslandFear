class_name Refugio
extends Node3D

## Refugio simple (tela + madera + hojas): un techito de tela que se mece con el viento y una cama de hojas.
## Mientras alguien duerme, sobre el techo aparecen unas Z grandes y una marca brillante que se ve desde lejos.
## No usa luces: solo materiales y sprites aditivos.

const SHADER_TELA: String = "shader_type spatial;\nrender_mode cull_disabled;\nuniform vec4 col : source_color = vec4(0.78, 0.72, 0.58, 1.0);\nuniform float amp = 0.06;\nvoid vertex() {\n\tfloat borde = clamp(abs(VERTEX.x) / 1.2 + abs(VERTEX.z) / 1.0, 0.0, 1.5);\n\tVERTEX.y += (sin(TIME * 1.7 + VERTEX.x * 2.3 + VERTEX.z * 1.4) * 0.6 + sin(TIME * 3.1 + VERTEX.x * 4.0) * 0.25) * amp * borde;\n}\nvoid fragment() {\n\tALBEDO = col.rgb;\n\tROUGHNESS = 1.0;\n\tBACKLIGHT = col.rgb * 0.35;\n}\n"

var durmiendo: bool = false
var _zzz: Label3D
var _marca: Sprite3D
var _t: float = 0.0
var _mat_marca: StandardMaterial3D

func _ready() -> void:
	add_to_group("refugio")
	_armar()

func cama_pos() -> Vector3:
	return global_position + Vector3(0, 0.12, 0)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

func _pieza(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, sc: Vector3 = Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = sc
	add_child(mi)

func _armar() -> void:
	var madera: StandardMaterial3D = _mat(Color(0.32, 0.21, 0.12))
	# cuatro postes: adelante (z -) altos, atras (z +) bajos
	for sx: float in [-1.0, 1.0]:
		for e: Array in [[-0.85, 1.3], [0.85, 0.75]]:
			var c := CylinderMesh.new()
			c.top_radius = 0.045
			c.bottom_radius = 0.06
			c.height = float(e[1])
			c.radial_segments = 6
			_pieza(c, madera, Vector3(sx * 1.0, float(e[1]) * 0.5, float(e[0])))
	# techo de tela inclinado, con movimiento
	var pl := PlaneMesh.new()
	pl.size = Vector2(2.4, 1.95)
	pl.subdivide_width = 10
	pl.subdivide_depth = 8
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_TELA
	sm.shader = sh
	_pieza(pl, sm, Vector3(0, 1.03, 0), Vector3(0.31, 0, 0))
	# cama de hojas
	var hojas: StandardMaterial3D = _mat(Color(0.2, 0.42, 0.16))
	var hojas2: StandardMaterial3D = _mat(Color(0.3, 0.5, 0.18))
	var base := BoxMesh.new()
	base.size = Vector3(2.0, 0.07, 0.95)
	_pieza(base, _mat(Color(0.26, 0.36, 0.14)), Vector3(0, 0.04, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(global_position.x * 13.0 + global_position.z * 7.0)) + 3
	for i in 9:
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		s.radial_segments = 6
		s.rings = 3
		var px: float = -0.8 + 1.6 * float(i) / 8.0 + rng.randf_range(-0.08, 0.08)
		_pieza(s, hojas if i % 2 == 0 else hojas2, Vector3(px, 0.1 + rng.randf_range(0.0, 0.03), rng.randf_range(-0.22, 0.22)), Vector3(0, rng.randf() * PI, rng.randf_range(-0.2, 0.2)), Vector3(0.62, 0.1, 0.45))
	# Z grandes y marca brillante (solo mientras se duerme)
	_zzz = Label3D.new()
	_zzz.text = "Z z Z"
	_zzz.font_size = 96
	_zzz.outline_size = 14
	_zzz.modulate = Color(1.0, 0.92, 0.6, 0.0)
	_zzz.outline_modulate = Color(0.25, 0.15, 0.4, 0.0)
	_zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_zzz.no_depth_test = true
	_zzz.shaded = false
	_zzz.double_sided = true
	_zzz.fixed_size = false
	_zzz.position = Vector3(0, 2.0, 0)
	_zzz.visible = false
	add_child(_zzz)
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1.0, 0.95, 0.7, 0.9), Color(1.0, 0.85, 0.5, 0.35), Color(1.0, 0.8, 0.4, 0.0)])
	gr.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gt.gradient = gr
	_marca = Sprite3D.new()
	_marca.texture = gt
	_marca.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marca.shaded = false
	_marca.transparent = true
	_marca.double_sided = true
	_marca.no_depth_test = true
	_marca.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat_marca = StandardMaterial3D.new()
	_mat_marca.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_marca.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_marca.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_marca.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat_marca.albedo_texture = gt
	_mat_marca.no_depth_test = true
	_marca.material_override = _mat_marca
	_marca.position = Vector3(0, 0.6, 0)
	_marca.visible = false
	add_child(_marca)

func _process(delta: float) -> void:
	_t += delta
	var vis: bool = durmiendo
	_zzz.visible = vis
	_marca.visible = vis
	if not vis:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var d: float = 6.0
	if cam != null:
		d = cam.global_position.distance_to(global_position)
	var k: float = clampf(d / 6.0, 1.0, 9.0)             # de lejos se agrandan para seguir viendose
	_zzz.pixel_size = 0.006 * k
	_zzz.position = Vector3(0, 2.0 + 0.25 * sin(_t * 1.3), 0)
	var pulso: float = 0.75 + 0.25 * sin(_t * 2.0)
	_zzz.modulate.a = pulso
	_zzz.outline_modulate.a = pulso
	_marca.pixel_size = 0.012 * k
	_mat_marca.albedo_color = Color(1, 1, 1, lerpf(0.15, 0.85, smoothstep(8.0, 30.0, d)) * pulso)
