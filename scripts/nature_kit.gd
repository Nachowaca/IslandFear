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
	"tree": {"sway": 0.16, "base_y": 2.2, "height_ref": 5.5, "flutter": 0.025, "speed": 1.1, "push": 0.0, "near_fade": 3.0},
	"bush": {"sway": 0.05, "base_y": 0.1, "height_ref": 1.5, "flutter": 0.02, "speed": 1.5, "push": 1.0, "reach": 1.1, "tall": 1.8},
	"flower": {"sway": 0.06, "base_y": 0.05, "height_ref": 1.2, "flutter": 0.01, "speed": 1.5, "push": 1.0, "reach": 1.2, "tall": 1.4},
	"grass": {"sway": 0.08, "base_y": 0.05, "height_ref": 1.5, "flutter": 0.012, "speed": 1.6, "push": 1.0, "reach": 1.1, "tall": 1.8},
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

## Colisión para piedras planas / rocas chicas de un MultiMesh: una caja por instancia (un solo cuerpo, muchas formas).
static func add_box_colliders(mmi: MultiMeshInstance3D, min_h: float = 0.08) -> void:
	if Engine.is_editor_hint() or mmi == null or mmi.multimesh == null or mmi.multimesh.mesh == null:
		return
	var bb: AABB = mmi.multimesh.mesh.get_aabb()
	var body := StaticBody3D.new()
	body.name = "Colision"
	for i in mmi.multimesh.instance_count:
		var xf: Transform3D = mmi.multimesh.get_instance_transform(i)
		var sc: Vector3 = xf.basis.get_scale().abs()
		var sz: Vector3 = Vector3(bb.size.x * sc.x, maxf(bb.size.y * sc.y, min_h), bb.size.z * sc.z) * Vector3(0.9, 1.0, 0.9)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = sz
		cs.shape = bx
		var ctr: Vector3 = xf * bb.get_center()
		ctr.y = xf.origin.y + bb.position.y * sc.y + sz.y * 0.5
		cs.transform = Transform3D(xf.basis.orthonormalized(), ctr)
		body.add_child(cs)
	mmi.add_child(body)

## Lo mismo para una piedra suelta (nodo con una malla).
static func add_box_collider(n: Node3D, min_h: float = 0.08) -> void:
	if Engine.is_editor_hint():
		return
	var mi: MeshInstance3D = _first_mesh(n)
	if mi == null:
		return
	var bb: AABB = mi.mesh.get_aabb()
	var sc: Vector3 = mi.transform.basis.get_scale().abs() * n.scale
	var sz: Vector3 = Vector3(bb.size.x * sc.x, maxf(bb.size.y * sc.y, min_h), bb.size.z * sc.z) * Vector3(0.9, 1.0, 0.9)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = sz / n.scale.abs()
	cs.shape = bx
	cs.position = bb.get_center() * mi.transform.basis.get_scale() + mi.transform.origin
	cs.position.y = mi.transform.origin.y + bb.position.y * mi.transform.basis.get_scale().y + bx.size.y * 0.5
	body.add_child(cs)
	n.add_child(body)

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
		var is_foliage: bool = LEAF_TEX.has(m.resource_name) or m.resource_name == "Grass" or m.resource_name == "Leaves" or m.resource_name == "Flowers"
		if is_foliage and kind != "" and sm.albedo_texture != null:
			var sh: ShaderMaterial = ShaderMaterial.new()
			sh.shader = LEAF_SHADER
			sh.set_shader_parameter("albedo_tex", sm.albedo_texture)
			sh.set_shader_parameter("tint", tint if m.resource_name != "Flowers" else Color.WHITE)
			if kind == "bush" and m.resource_name.begins_with("Leaves"):
				sh.set_shader_parameter("tint", tint * Color(0.85, 0.92, 0.75))
				sh.set_shader_parameter("backlight_amt", 0.3)
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
	if model.begins_with("Flower"):
		return "flower"
	if model.begins_with("Grass") or model.begins_with("Fern") or model.begins_with("Plant") or model.begins_with("Clover"):
		return "grass"
	return ""


# ---------------------------------------------------------------- Ultimate Stylized Nature (Quaternius)
const UQ_DIR := "res://assets/ultimate_nature/"
static var _uq_mats: Dictionary = {}
const ROCK_SHADER: Shader = preload("res://shaders/rock_island.gdshader")

## Tonos de gris/marrón de las rocas (alfa = cantidad de musgo, en 3 niveles para compartir materiales).
static func rock_tint(rng: RandomNumberGenerator) -> Color:
	var tones: Array[Color] = [Color(1.0, 1.0, 1.0), Color(1.1, 1.02, 0.88), Color(0.7, 0.68, 0.64), Color(0.85, 0.72, 0.6), Color(1.2, 1.15, 1.05), Color(0.55, 0.52, 0.48)]
	var c: Color = tones[rng.randi() % tones.size()]
	var mossy: Array[float] = [0.08, 0.45, 0.85]
	c.a = mossy[rng.randi() % 3]
	return c

## Tono del tronco según el tinte del árbol (6 variantes fijas, así se comparten materiales).
static func _bark_tone(tint: Color, birch: bool) -> Color:
	var tones: Array[Color] = [Color(1, 1, 1), Color(0.72, 0.66, 0.6), Color(1.25, 1.12, 0.95), Color(1.0, 0.92, 0.85), Color(1.15, 0.85, 0.75), Color(0.55, 0.5, 0.45)]
	var i: int = absi(hash(tint.to_html())) % tones.size()
	if birch:
		return Color(1, 1, 1).lerp(tones[i], 0.4)
	return tones[i] * Color(0.62, 0.6, 0.55)   # corteza cálida: bajo cielo azul el gris/marrón se vuelve azulado

## Instancia un modelo del pack Ultimate Stylized Nature. Los de `FBX/` (palmeras, rocas…) están en centímetros
## (el nodo ya trae escala 100); los de `glTF/` (abedul, arce, arbustos, flores…) en metros.
## Texturas y viento se asignan acá porque el FBX no las enlaza.
## `shape` solo para rocas: 0 = redondeada, 1 = normal, 2 = de pico fino (alta y afilada).
static func make_uq(model: String, tint: Color = Color.WHITE, vis_end: float = 0.0, shape: int = 1) -> Node3D:
	var ps: PackedScene = _scenes.get("uq:" + model)
	var fbx: bool = ResourceLoader.exists(UQ_DIR + "FBX/" + model + ".fbx")
	if ps == null:
		ps = load(UQ_DIR + ("FBX/" + model + ".fbx" if fbx else "glTF/" + model + ".gltf")) as PackedScene
		_scenes["uq:" + model] = ps
	var n: Node3D = ps.instantiate() as Node3D
	if model.begins_with("Rock_"):
		_soften_rocks(n, model, shape)
	_uq_fix(n, tint, vis_end, fbx, _kind(model))
	return n

static var _soft_meshes: Dictionary = {}

## Da forma a las rocas del pack: redondeadas (normales promediadas, algo achatadas), normales (suavizado leve)
## o de pico fino (alargadas y afiladas hacia arriba, casi facetadas).
static func _soften_rocks(n: Node, model: String, shape: int = 1) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh != null:
			var key: String = model + "|" + str(mi.mesh.get_rid().get_id()) + "|" + str(shape)
			if not _soft_meshes.has(key):
				var am: float = 1.0 if shape == 0 else (0.15 if shape == 2 else 0.7)
				_soft_meshes[key] = _smooth_mesh(mi.mesh, am, shape)
			mi.mesh = _soft_meshes[key]
	for c in n.get_children():
		_soften_rocks(c, model, shape)

static func _smooth_mesh(src: Mesh, amount: float, shape: int = 1) -> Mesh:
	var out := ArrayMesh.new()
	var q: float = maxf(src.get_aabb().size.length() * 0.002, 0.00001)
	for si in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		if shape != 1 and verts.size() > 0:
			var bb: AABB = src.get_aabb()
			var hh: float = maxf(bb.size.y, 0.0001)
			for vi in verts.size():
				var v: Vector3 = verts[vi]
				var t: float = clampf((v.y - bb.position.y) / hh, 0.0, 1.0)
				if shape == 2:
					var pin: float = lerpf(1.0, 0.12, pow(t, 1.4))     # se afina hacia la punta
					v.x = (v.x - bb.get_center().x) * pin * 0.8 + bb.get_center().x
					v.z = (v.z - bb.get_center().z) * pin * 0.8 + bb.get_center().z
					v.y = bb.position.y + (v.y - bb.position.y) * 1.9
				else:
					var sq: float = lerpf(1.0, 0.82, t)               # coronilla redonda y baja
					v.x = (v.x - bb.get_center().x) * 1.12 * sq + bb.get_center().x
					v.z = (v.z - bb.get_center().z) * 1.12 * sq + bb.get_center().z
					v.y = bb.position.y + (v.y - bb.position.y) * 0.78
				verts[vi] = v
			arr[Mesh.ARRAY_VERTEX] = verts
		if nrm.size() == verts.size() and verts.size() > 0:
			var sums: Dictionary = {}
			for i in verts.size():
				var k: Vector3i = Vector3i(roundi(verts[i].x / q), roundi(verts[i].y / q), roundi(verts[i].z / q))
				sums[k] = (sums[k] as Vector3 if sums.has(k) else Vector3.ZERO) + nrm[i]
			var nn: PackedVector3Array = nrm.duplicate()
			for i in verts.size():
				var k2: Vector3i = Vector3i(roundi(verts[i].x / q), roundi(verts[i].y / q), roundi(verts[i].z / q))
				nn[i] = nrm[i].lerp((sums[k2] as Vector3).normalized(), amount).normalized()
			arr[Mesh.ARRAY_NORMAL] = nn
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(si, src.surface_get_material(si))
	return out

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
		if nm.begins_with("Bush"):   # el verde de fábrica de los arbustos es lima plano: lo bajamos y apagamos
			sh.set_shader_parameter("tint", (sh.get_shader_parameter("tint") as Color) * Color(0.85, 0.92, 0.75))
			sh.set_shader_parameter("backlight_amt", 0.3)
		var pr: Dictionary = WIND_PARAMS.get(kind if kind != "" else "tree")
		sh.set_shader_parameter("sway", float(pr["sway"]) * (1.8 if nm.begins_with("Palm") else 1.0))
		sh.set_shader_parameter("base_y", float(pr["base_y"]) * (1.0 if nm.begins_with("Palm") else 1.0) * (1.4 if nm.begins_with("Palm") else 1.0) * u)
		sh.set_shader_parameter("height_ref", float(pr["height_ref"]) * 0.6 * u if nm.begins_with("Palm") else float(pr["height_ref"]) * u)
		sh.set_shader_parameter("flutter", pr["flutter"])
		sh.set_shader_parameter("speed", pr["speed"])
		sh.set_shader_parameter("push", pr["push"])
		sh.set_shader_parameter("reach", pr.get("reach", 1.0))
		sh.set_shader_parameter("tall", pr.get("tall", 1.0))
		sh.set_shader_parameter("near_fade", pr.get("near_fade", 0.0))
		Wind.register(sh)
		out = sh
	elif nm == "Flowers":
		var sf := StandardMaterial3D.new()
		sf.albedo_texture = load(g + "Flowers.png") as Texture2D
		sf.cull_mode = BaseMaterial3D.CULL_DISABLED
		sf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		sf.roughness = 1.0
		out = sf
		if kind == "flower":
			var sh2 := ShaderMaterial.new()
			sh2.shader = LEAF_SHADER
			sh2.set_shader_parameter("albedo_tex", sf.albedo_texture)
			var pf: Dictionary = WIND_PARAMS["flower"]
			for k2: String in pf.keys():
				sh2.set_shader_parameter(k2, pf[k2])
			Wind.register(sh2)
			out = sh2
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


# ---------------------------------------------------------------- Stylized Stones minipack (rocas de la isla)
const STONES_GLB: String = "res://assets/generated/stylized_stones_minipack.glb"
static var _stone_tpl: Dictionary = {}
static var _stone_mats: Dictionary = {}

## Piedra del minipack: `idx` 1..5 (1 chica y baja ... 5 alta), `variant` 0 = musgo, 1 = sin musgo, 2 = musgo alterno,
## `tone` 0..2 oscurece el material. Devuelve un nodo de 1 m de ancho con la base en y = 0 (se escala desde afuera).
static func make_stone(idx: int, variant: int, tone: int = 0) -> Node3D:
	var key: String = "%d_%d" % [idx, variant]
	if not _stone_tpl.has(key):
		var src: Node3D = (load(STONES_GLB) as PackedScene).instantiate() as Node3D
		var suffix: String = ["", "_001", "_002"][variant]
		var want: String = "Stone_%d_Low%s" % [idx, suffix]
		var found: Node = src.find_child(want, true, false)
		var tpl: Dictionary = {}
		if found != null:
			var mi: MeshInstance3D = null
			for c in found.get_children():
				if c is MeshInstance3D:
					mi = c as MeshInstance3D
			if mi != null:
				var t: Transform3D = Transform3D.IDENTITY
				var cur: Node = mi
				while cur != null and cur != src:
					t = (cur as Node3D).transform * t
					cur = cur.get_parent()
				var bb: AABB = t * mi.mesh.get_aabb()
				var k: float = 1.0 / maxf(maxf(bb.size.x, bb.size.z), 0.0001)
				var base: Vector3 = Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
				var fx: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * k), -k * base) * t
				tpl = {"mesh": mi.mesh, "xf": fx, "mat": mi.mesh.surface_get_material(0)}
		src.free()
		_stone_tpl[key] = tpl
	var out := Node3D.new()
	var tp: Dictionary = _stone_tpl[key]
	if tp.is_empty():
		return out
	var mk: String = "%s_%d" % [key, tone]
	if not _stone_mats.has(mk):
		var m: StandardMaterial3D = (tp["mat"] as StandardMaterial3D).duplicate() as StandardMaterial3D
		var g: float = [1.25, 1.05, 0.88][clampi(tone, 0, 2)]
		m.albedo_color = Color(g * 0.9, g * 0.97, g * 1.05)
		m.emission_enabled = true      # el pack traía emisión al 100 %: la dejamos como un brillo propio muy leve
		m.emission = Color(0.55, 0.5, 0.45)
		m.emission_energy_multiplier = 0.22
		m.roughness = 1.0
		m.metallic = 0.0
		_stone_mats[mk] = m
	var mn := MeshInstance3D.new()
	mn.mesh = tp["mesh"]
	mn.transform = tp["xf"]
	mn.material_override = _stone_mats[mk]
	mn.visibility_range_end = 160.0
	out.add_child(mn)
	return out
