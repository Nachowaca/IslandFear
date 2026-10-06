class_name NatureKit
extends RefCounted
## Cargador del pack "Stylized Nature MegaKit" (res://glTF): corrige las hojas (el pack trae una textura
## blanca y otra coloreada "_C"), desactiva el culling de hojas y limita la distancia de dibujado.

const DIR := "res://glTF/"
const LEAF_TEX: Dictionary = {
	"Leaves_NormalTree": "res://Textures/Leaves_NormalTree_C.png",
	"Leaves_TwistedTree": "res://Textures/Leaves_NormalTree_C.png",   # la original es roja (otoño)
	"Leaves_Pine": "res://Textures/Leaf_Pine_C.png",
}

const LEAF_SHADER: Shader = preload("res://shaders/wind_leaf.gdshader")
const WIND_PARAMS: Dictionary = {
	"tree": {"sway": 0.16, "base_y": 2.2, "height_ref": 5.5, "flutter": 0.025, "speed": 1.1},
	"bush": {"sway": 0.05, "base_y": 0.1, "height_ref": 1.5, "flutter": 0.02, "speed": 1.5},
	"grass": {"sway": 0.07, "base_y": 0.05, "height_ref": 1.5, "flutter": 0.012, "speed": 1.8},
}

static var _scenes: Dictionary = {}
static var _mats: Dictionary = {}

static func exists(model: String) -> bool:
	return ResourceLoader.exists(DIR + model + ".gltf")

## Instancia un modelo del pack. `tint` multiplica el color de las hojas; `vis_end` > 0 oculta a esa distancia.
static func make(model: String, tint: Color = Color.WHITE, vis_end: float = 0.0) -> Node3D:
	var ps: PackedScene = _scenes.get(model)
	if ps == null:
		ps = load(DIR + model + ".gltf") as PackedScene
		_scenes[model] = ps
	var n: Node3D = ps.instantiate() as Node3D
	_fix(n, tint, vis_end, _kind(model))
	return n

## Un único MultiMeshInstance3D con muchas copias de un modelo (para pasto, helechos, flores, piedritas…).
static func multi(model: String, xforms: Array[Transform3D], vis_end: float = 90.0, tint: Color = Color.WHITE, shadows: bool = false) -> MultiMeshInstance3D:
	var src: Node3D = make(model, tint)
	var mi: MeshInstance3D = _first_mesh(src)
	if mi == null:
		src.free()
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh: Mesh = mi.mesh.duplicate() as Mesh
	for i in mesh.get_surface_count():
		var ov: Material = mi.get_surface_override_material(i)
		if ov != null:
			mesh.surface_set_material(i, ov)
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	var local: Transform3D = mi.transform
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i] * local)
	var out := MultiMeshInstance3D.new()
	out.multimesh = mm
	out.name = "Kit_" + model
	out.visibility_range_end = vis_end
	out.visibility_range_end_margin = vis_end * 0.1
	out.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	src.free()
	return out

static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n as MeshInstance3D
	for c in n.get_children():
		var r: MeshInstance3D = _first_mesh(c)
		if r != null:
			return r
	return null

static func _fix(n: Node, tint: Color, vis_end: float, kind: String = "") -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(i)
				if m != null:
					mi.set_surface_override_material(i, _fixed(m, tint, kind))
		if vis_end > 0.0:
			mi.visibility_range_end = vis_end
			mi.visibility_range_end_margin = vis_end * 0.1
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in n.get_children():
		_fix(c, tint, vis_end, kind)

static func _fixed(m: Material, tint: Color, kind: String = "") -> Material:
	var key: String = "%s|%s|%s" % [m.resource_name, tint.to_html(), kind]
	if _mats.has(key):
		return _mats[key]
	var out: Material = m
	if m is StandardMaterial3D:
		var sm: StandardMaterial3D = (m as StandardMaterial3D).duplicate() as StandardMaterial3D
		if LEAF_TEX.has(m.resource_name):
			sm.albedo_texture = load(LEAF_TEX[m.resource_name]) as Texture2D
			sm.albedo_color = tint
			sm.vertex_color_use_as_albedo = false
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			sm.roughness = 1.0
		elif m.resource_name.begins_with("Leaves") or m.resource_name == "Grass" or m.resource_name == "Flowers":
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			sm.albedo_color = tint if m.resource_name != "Flowers" else Color.WHITE
		out = sm
		# follaje con viento: mismo aspecto pero con balanceo (solo hojas y pastos, no flores ni corteza)
		var is_foliage: bool = LEAF_TEX.has(m.resource_name) or m.resource_name == "Grass" or m.resource_name == "Leaves"
		if is_foliage and kind != "" and sm.albedo_texture != null:
			var sh: ShaderMaterial = ShaderMaterial.new()
			sh.shader = LEAF_SHADER
			sh.set_shader_parameter("albedo_tex", sm.albedo_texture)
			sh.set_shader_parameter("tint", tint)
			var pr: Dictionary = WIND_PARAMS[kind]
			for k: String in pr.keys():
				sh.set_shader_parameter(k, pr[k])
			Wind.register(sh)
			out = sh
	_mats[key] = out
	return out

## Tipo de planta según el nombre del modelo (decide cuánto se mece).
static func _kind(model: String) -> String:
	if model.contains("Tree") or model.begins_with("Pine"):
		return "tree"
	if model.begins_with("Bush"):
		return "bush"
	if model.begins_with("Grass") or model.begins_with("Fern") or model.begins_with("Plant") or model.begins_with("Clover"):
		return "grass"
	return ""
