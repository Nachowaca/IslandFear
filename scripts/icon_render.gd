class_name IconRender
extends Node

## Íconos de inventario para objetos sin PNG: dibuja el modelo 3D de ItemDB.make_visual en un SubViewport
## (una sola vez por objeto) y entrega esa textura. Lo crea InventoryUi.

static var inst: IconRender
static var _cache: Dictionary = {}

const SIZE: int = 96

func _enter_tree() -> void:
	inst = self

func _exit_tree() -> void:
	if inst == self:
		inst = null
		_cache.clear()

static func get_icon(id: String) -> Texture2D:
	if inst == null or not ItemDB.DEFS.has(id):
		return null
	if _cache.has(id):
		return _cache[id]
	var tex: Texture2D = inst._render(id)
	_cache[id] = tex
	return tex

func _render(id: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root: Node3D = ItemDB.make_visual(id)
	vp.add_child(root)
	var box: AABB = AABB()
	var first: bool = true
	for c: Node in root.get_children():
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var bb: AABB = mi.transform * mi.mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first:
		box = AABB(Vector3(-0.1, 0.0, -0.1), Vector3(0.2, 0.2, 0.2))
	var center: Vector3 = box.get_center()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.8)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_energy = 0.9
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.length() * 0.95, 0.12)
	vp.add_child(cam)
	var dir: Vector3 = Vector3(0.55, 0.7, 0.6).normalized()
	cam.position = center + dir * 3.0
	cam.look_at(center, Vector3.UP)
	_apagar(vp)
	return vp.get_texture()

## Deja que el viewport dibuje unos cuadros y luego lo apaga: el ícono queda fijo sin costo.
func _apagar(vp: SubViewport) -> void:
	for k in 4:
		await get_tree().process_frame
	if is_instance_valid(vp):
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
