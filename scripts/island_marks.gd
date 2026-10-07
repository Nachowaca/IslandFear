extends Node3D

## Marcas misteriosas en los claros: la isla "estudia" al jugador sin decirlo.
## - Un círculo de suelo pisado en el centro del claro (más marcado cuanto más lo visitaste con calma).
## - Un rastro de huellas que sale del claro hacia el lugar por donde más caminaste.
## Si hiciste daño cerca, el rastro se retira y el círculo se borra. Los cambios solo ocurren cuando no estás mirando (lejos).
## Usa Isla.calor_paso / Isla.calor_dano (se guardan, así que las marcas persisten entre sesiones).

const STEPS: int = 9
const NEAR_R: float = 30.0          ## radio del claro para sumar visitas y daño
const TRAIL_MAX: float = 28.0
const HIDE_DIST: float = 20.0       ## no cambia nada a la vista del jugador

var terrain: IslandTerrain

var _clearings: Array[Dictionary] = []
var _timer: float = 3.0
var _player: Node3D
var _foot_mesh: QuadMesh
var _foot_mat: StandardMaterial3D

func _ready() -> void:
	if terrain == null or terrain.eco == null:
		return
	_foot_mat = StandardMaterial3D.new()
	_foot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_foot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_foot_mat.albedo_texture = _blob(0.5)
	_foot_mat.albedo_color = Color(0.1, 0.07, 0.04, 0.5)
	_foot_mat.disable_receive_shadows = true
	_foot_mesh = QuadMesh.new()
	_foot_mesh.orientation = PlaneMesh.FACE_Y
	_foot_mesh.size = Vector2(0.2, 0.36)
	_foot_mesh.material = _foot_mat
	for c: Vector3 in terrain.eco.mystery_centers:
		_make_clearing(c)

func _blob(edge: float) -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)])
	g.offsets = PackedFloat32Array([0.0, edge, 1.0])
	gt.gradient = g
	return gt

func _make_clearing(c: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(7.5, 7.5)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_texture = _blob(0.55)
	rm.albedo_color = Color(0.16, 0.13, 0.07, 0.0)
	rm.disable_receive_shadows = true
	q.material = rm
	ring.mesh = q
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = Vector3(c.x, terrain.height_at(c.x, c.z) + 0.07, c.z)
	var foot_nodes: Array[MeshInstance3D] = []
	for i in STEPS * 2:
		var mi := MeshInstance3D.new()
		mi.mesh = _foot_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		foot_nodes.append(mi)
	_clearings.append({"center": c, "ring": ring, "ring_mat": rm, "ring_a": 0.0, "ring_goal": 0.0,
		"prints": foot_nodes, "reach": 0.0, "dir": Vector2.ZERO, "len": 0.0, "placed": false})

func _process(delta: float) -> void:
	if _clearings.is_empty():
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_timer -= delta
	if _timer <= 0.0:
		_timer = 4.0
		_evaluate()
	for cl: Dictionary in _clearings:
		var a: float = float(cl["ring_a"])
		var goal: float = float(cl["ring_goal"])
		var ring: MeshInstance3D = cl["ring"]
		var far: bool = _player == null or Vector2(ring.global_position.x - _player.global_position.x, ring.global_position.z - _player.global_position.z).length() > HIDE_DIST
		if far:
			a = lerpf(a, goal, minf(delta * 0.4, 1.0))
		else:
			a = lerpf(a, goal, minf(delta * 0.02, 1.0))     # a la vista, casi no cambia
		cl["ring_a"] = a
		var col: Color = (cl["ring_mat"] as StandardMaterial3D).albedo_color
		col.a = a
		(cl["ring_mat"] as StandardMaterial3D).albedo_color = col

## Mide cuánta calma y cuánto daño hubo cerca de cada claro y ajusta objetivos.
func _evaluate() -> void:
	var mood: float = clampf(Isla.vinculo / 60.0, -1.0, 1.0)
	for cl: Dictionary in _clearings:
		var c: Vector3 = cl["center"]
		var visit: float = 0.0
		var harm: float = 0.0
		var best_v: float = 0.0
		var best: Vector2 = Vector2.ZERO
		for cell: Vector2i in Isla.calor_paso.keys():
			var p := Vector2((float(cell.x) + 0.5) * Isla.CELDA, (float(cell.y) + 0.5) * Isla.CELDA)
			var d: float = p.distance_to(Vector2(c.x, c.z))
			var v: float = float(Isla.calor_paso[cell])
			if d < NEAR_R:
				visit += v
			if d > 7.0 and d < 80.0 and v > best_v:
				best_v = v
				best = p
		for cell2: Vector2i in Isla.calor_dano.keys():
			var p2 := Vector2((float(cell2.x) + 0.5) * Isla.CELDA, (float(cell2.y) + 0.5) * Isla.CELDA)
			if p2.distance_to(Vector2(c.x, c.z)) < NEAR_R:
				harm += float(Isla.calor_dano[cell2])
		var calm: float = clampf(visit / 240.0, 0.0, 1.0) * (1.0 - clampf(harm / 4.0, 0.0, 1.0))
		calm *= clampf(0.55 + mood * 0.5, 0.0, 1.0)
		cl["ring_goal"] = calm * 0.6
		var reach: float = calm if best_v > 6.0 else 0.0
		var to_t: Vector2 = best - Vector2(c.x, c.z)
		cl["dir"] = to_t.normalized()
		cl["len"] = minf(to_t.length() - 3.0, TRAIL_MAX)
		cl["reach"] = reach
		_apply_feet(cl)

func _apply_feet(cl: Dictionary) -> void:
	var c: Vector3 = cl["center"]
	var dir: Vector2 = cl["dir"]
	var reach: float = float(cl["reach"])
	var trail_len: float = float(cl["len"])
	var foot_nodes: Array[MeshInstance3D] = cl["prints"]
	var yaw: float = atan2(dir.x, dir.y)
	var side: Vector2 = Vector2(-dir.y, dir.x)
	for i in STEPS:
		var along: float = 3.0 + (trail_len - 3.0) * float(i) / float(STEPS - 1) if trail_len > 3.0 else 0.0
		var want: bool = trail_len > 6.0 and float(i + 1) / float(STEPS) <= reach + 0.01
		for k in 2:
			var mi: MeshInstance3D = foot_nodes[i * 2 + k]
			var off: float = 0.17 if k == 0 else -0.17
			var stagger: float = 0.0 if k == 0 else 0.45
			var wob: float = sin(float(i) * 1.7 + c.x) * 0.5
			var pos2: Vector2 = Vector2(c.x, c.z) + dir * (along + stagger) + side * (off + wob)
			var y: float = terrain.height_at(pos2.x, pos2.y)
			var ok: bool = want and y > 1.6 and not terrain.is_in_pond_area(pos2.x, pos2.y, 1.0) and not terrain.is_in_cave_area(pos2.x, pos2.y, 1.0)
			# solo cambia cuando el jugador no está cerca para verlo
			var far: bool = _player == null or Vector2(pos2.x - _player.global_position.x, pos2.y - _player.global_position.z).length() > HIDE_DIST
			if not far:
				continue
			mi.visible = ok
			if ok:
				mi.global_position = Vector3(pos2.x, y + 0.06, pos2.y)
				mi.rotation = Vector3(0.0, yaw + sin(float(i * 2 + k)) * 0.15, 0.0)
