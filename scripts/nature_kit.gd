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
	"tree": {"sway": 0.16, "base_y": 2.2, "height_ref": 5.5, "flutter": 0.025, "speed": 1.1, "push": 0.0},
	"bush": {"sway": 0.05, "base_y": 0.1, "height_ref": 1.5, "flutter": 0.02, "speed": 1.5, "push": 0.8},
	"grass": {"sway": 0.07, "base_y": 0.05, "height_ref": 1.5, "flutter": 0.012, "speed": 1.8, "push": 1.0},
}

static var _scenes: Dictionary = {}
static var _mats: Dictionary = {}

static func exists(model: String) -> bool:
	if model.begins_with("UQ:"):
		return ResourceLoader.exists(UQ_DIR + "glTF/" + model.substr(3) + ".gltf")
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
	var src: Node3D = make_uq(model.substr(3), tint) if model.begins_with("UQ:") else make(model, tint)
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
		elif m.resource_name.begins_with("Bark"):
			sm.albedo_color = _bark_tone(tint, false)
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


# ---------------------------------------------------------------- Ultimate Stylized Nature (Quaternius)
const UQ_DIR := "res://assets/ultimate_nature/"
static var _uq_mats: Dictionary = {}
const ROCK_SHADER: Shader = preload("res://shaders/rock_island.gdshader")

## Tonos de gris/marrón de las rocas (alfa = cantidad de musgo, en 3 niveles para compartir materiales).
static func rock_tint(rng: RandomNumberGenerator) -> Color:
	var tones: Array[Color] = [Color(1.0, 1.0, 1.0), Color(1.1, 1.02, 0.88), Color(0.62, 0.65, 0.72), Color(0.85, 0.72, 0.6), Color(1.2, 1.18, 1.1), Color(0.46, 0.47, 0.52)]
	var c: Color = tones[rng.randi() % tones.size()]
	var mossy: Array[float] = [0.08, 0.45, 0.85]
	c.a = mossy[rng.randi() % 3]
	return c

## Tono del tronco según el tinte del árbol (6 variantes fijas, así se comparten materiales).
static func _bark_tone(tint: Color, birch: bool) -> Color:
	var tones: Array[Color] = [Color(1, 1, 1), Color(0.72, 0.66, 0.6), Color(1.25, 1.12, 0.95), Color(0.85, 0.85, 0.95), Color(1.15, 0.85, 0.75), Color(0.55, 0.5, 0.45)]
	var i: int = absi(hash(tint.to_html())) % tones.size()
	if birch:
		return Color(1, 1, 1).lerp(tones[i], 0.4)
	return tones[i]

## Instancia un modelo del pack Ultimate Stylized Nature. Los de `FBX/` (palmeras, rocas…) están en centímetros
## (el nodo ya trae escala 100); los de `glTF/` (abedul, arce, arbustos, flores…) en metros.
## Texturas y viento se asignan acá porque el FBX no las enlaza.
static func make_uq(model: String, tint: Color = Color.WHITE, vis_end: float = 0.0) -> Node3D:
	var ps: PackedScene = _scenes.get("uq:" + model)
	var fbx: bool = ResourceLoader.exists(UQ_DIR + "FBX/" + model + ".fbx")
	if ps == null:
		ps = load(UQ_DIR + ("FBX/" + model + ".fbx" if fbx else "glTF/" + model + ".gltf")) as PackedScene
		_scenes["uq:" + model] = ps
	var n: Node3D = ps.instantiate() as Node3D
	_uq_fix(n, tint, vis_end, fbx, _kind(model))
	return n

static func _uq_fix(n: Node, tint: Color, vis_end: float, fbx: bool, kind: String) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(i)
				var nm: String = m.resource_name if m != null else ""
				if nm == "" and fbx:
					nm = "Grass"               # Grass_Large del FBX viene sin nombre de material
				mi.set_surface_override_material(i, _uq_mat(nm, tint, fbx, kind))
		if vis_end > 0.0:
			mi.visibility_range_end = vis_end
			mi.visibility_range_end_margin = vis_end * 0.1
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in n.get_children():
		_uq_fix(c, tint, vis_end, fbx, kind)

static func _uq_mat(nm: String, tint: Color, fbx: bool, kind: String) -> Material:
	var key: String = "%s|%s|%s|%s" % [nm, tint.to_html(), fbx, kind]
	if _uq_mats.has(key):
		return _uq_mats[key]
	var out: Material
	var g: String = UQ_DIR + "glTF/"
	var u: float = 0.01 if fbx else 1.0                # unidad local -> metros
	if nm.ends_with("_Leaves") or nm == "Grass":
		var sh := ShaderMaterial.new()
		sh.shader = LEAF_SHADER
		if nm == "MapleTree_Leaves":   # la textura original es roja (otoño): usamos la versión en gris teñida de verde
			sh.set_shader_parameter("albedo_tex", load(g + "MapleTree_Leaves_BW.png"))
			sh.set_shader_parameter("tint", Color(0.42, 0.7, 0.26) * tint)
		else:
			sh.set_shader_parameter("albedo_tex", load(g + nm + ".png"))
			sh.set_shader_parameter("tint", Color(0.9, 1.0, 0.8) * tint if nm == "BirchTree_Leaves" else tint)
		var pr: Dictionary = WIND_PARAMS.get(kind if kind != "" else "tree")
		sh.set_shader_parameter("sway", float(pr["sway"]) * (1.8 if nm.begins_with("Palm") else 1.0))
		sh.set_shader_parameter("base_y", float(pr["base_y"]) * (1.0 if nm.begins_with("Palm") else 1.0) * (1.4 if nm.begins_with("Palm") else 1.0) * u)
		sh.set_shader_parameter("height_ref", float(pr["height_ref"]) * 0.6 * u if nm.begins_with("Palm") else float(pr["height_ref"]) * u)
		sh.set_shader_parameter("flutter", pr["flutter"])
		sh.set_shader_parameter("speed", pr["speed"])
		sh.set_shader_parameter("push", pr["push"])
		Wind.register(sh)
		out = sh
	elif nm == "Flowers":
		var sf := StandardMaterial3D.new()
		sf.albedo_texture = load(g + "Flowers.png") as Texture2D
		sf.cull_mode = BaseMaterial3D.CULL_DISABLED
		sf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		sf.roughness = 1.0
		out = sf
	elif nm == "Rock":
		var sr := ShaderMaterial.new()
		sr.shader = ROCK_SHADER
		sr.set_shader_parameter("albedo_tex", load(g + "Rocks.jpg"))
		sr.set_shader_parameter("tint", tint)      # rgb = tono de la roca, a = cantidad de musgo
		sr.set_shader_parameter("local_unit", u)
		out = sr
	elif nm.ends_with("_Trunk") or nm.ends_with("_Bark"):
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = load(g + nm + ".jpg") as Texture2D
		sm.albedo_color = _bark_tone(tint, nm.begins_with("Birch"))
		var nrm: String = g + nm + "_Normal.png"
		if ResourceLoader.exists(nrm):
			sm.normal_enabled = true
			sm.normal_texture = load(nrm) as Texture2D
		sm.roughness = 1.0
		out = sm
	else:
		var sm2 := StandardMaterial3D.new()
		sm2.albedo_color = Color(0.5, 0.5, 0.5)
		out = sm2
	_uq_mats[key] = out
	return out
