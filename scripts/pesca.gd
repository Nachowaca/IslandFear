class_name Pesca
extends Node
## Mecánica de pesca autocontenida. El que la enganche asigna player/terrain/ui antes de add_child
## y llama usar() al apretar T con la caña en mano. Llamar cancelar() si cambia el objeto en mano.

enum Estado { IDLE, LANZADA, ESPERANDO, PICADA }

const MIN_DIST: float = 3.0
const MAX_DIST: float = 8.0
const CANCEL_DIST: float = 14.0
const SEA_LEVEL: float = 0.35
const BITE_WINDOW: float = 1.6

var player: Castaway
var terrain: IslandTerrain
var ui: InventoryUi

var _estado: Estado = Estado.IDLE
var _float: Node3D
var _line: MeshInstance3D
var _line_mat: StandardMaterial3D
var _splash: CPUParticles3D
var _target: Vector3 = Vector3.ZERO
var _water_y: float = SEA_LEVEL
var _timer: float = 0.0
var _time: float = 0.0
var _ripple_t: float = 0.0
var _sink: float = 0.0
var _flying: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func activa() -> bool:
	return _estado != Estado.IDLE

func usar() -> void:
	match _estado:
		Estado.IDLE:
			_lanzar()
		Estado.LANZADA, Estado.ESPERANDO:
			_msg("Recogés la línea.")
			cancelar()
		Estado.PICADA:
			_capturar()

func cancelar() -> void:
	_estado = Estado.IDLE
	_flying = false
	_timer = 0.0
	if _float != null and is_instance_valid(_float):
		_float.queue_free()
	_float = null
	if _line != null and is_instance_valid(_line):
		_line.queue_free()
	_line = null
	if _splash != null and is_instance_valid(_splash):
		_splash.queue_free()
	_splash = null

func _exit_tree() -> void:
	cancelar()

# ---------------------------------------------------------------- lógica

func _msg(t: String) -> void:
	if ui != null:
		ui.message(t)

func _agua_en(x: float, z: float) -> float:
	## Devuelve la altura de la superficie si hay agua en (x,z), o -1000 si no.
	if terrain == null:
		return -1000.0
	var h: float = terrain.height_at(x, z)
	if Vector2(x, z).distance_to(IslandTerrain.POND_CENTER) < IslandTerrain.POND_RADIUS * 1.6:
		if h < terrain.pond_water_level - 0.3:
			return terrain.pond_water_level
		return -1000.0
	if h < 0.3:
		return SEA_LEVEL
	return -1000.0

func _forward() -> Vector3:
	var f: Vector3 = -player.global_transform.basis.z
	var cam: Camera3D = player.get_camera()
	if cam != null:
		f = -cam.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.01:
		f = Vector3.FORWARD
	return f.normalized()

func _lanzar() -> void:
	if player == null or terrain == null or player.dead or not player.controllable:
		return
	var fwd: Vector3 = _forward()
	var base: Vector3 = player.global_position
	var found: bool = false
	var d: float = MIN_DIST
	while d <= MAX_DIST:
		var p: Vector3 = base + fwd * d
		var wy: float = _agua_en(p.x, p.z)
		if wy > -999.0:
			_target = Vector3(p.x, wy, p.z)
			_water_y = wy
			found = true
			break
		d += 0.5
	if not found:
		_msg("Necesitás agua delante para lanzar.")
		return
	cancelar()
	player.pulse_use()
	_crear_flotador()
	_estado = Estado.LANZADA
	_flying = true
	var start: Vector3 = player.hand_transform().origin
	_float.global_position = start
	var tw: Tween = create_tween()
	tw.tween_method(_arco.bind(start), 0.0, 1.0, 0.6)
	tw.tween_callback(_aterrizar)

func _arco(t: float, start: Vector3) -> void:
	if _float == null or not is_instance_valid(_float):
		return
	var p: Vector3 = start.lerp(_target, t)
	p.y += sin(t * PI) * 1.6
	_float.global_position = p

func _aterrizar() -> void:
	if _float == null or not is_instance_valid(_float):
		return
	_flying = false
	_float.global_position = _target
	_ring(_target)
	AudioManager.play(get_tree(), "drip", _target, -2.0)
	_estado = Estado.ESPERANDO
	_timer = _rng.randf_range(6.0, 18.0)

func _crear_flotador() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = self
	_float = Node3D.new()
	_float.name = "Flotador"
	var top: MeshInstance3D = MeshInstance3D.new()
	var sm1: SphereMesh = SphereMesh.new()
	sm1.radius = 0.08
	sm1.height = 0.16
	sm1.radial_segments = 8
	sm1.rings = 4
	top.mesh = sm1
	top.material_override = _mat(Color(0.9, 0.1, 0.1))
	top.position.y = 0.05
	_float.add_child(top)
	var bot: MeshInstance3D = MeshInstance3D.new()
	var sm2: SphereMesh = SphereMesh.new()
	sm2.radius = 0.07
	sm2.height = 0.1
	sm2.radial_segments = 8
	sm2.rings = 3
	bot.mesh = sm2
	bot.material_override = _mat(Color(0.95, 0.95, 0.95))
	bot.position.y = -0.04
	_float.add_child(bot)
	root.add_child(_float)

	_line = MeshInstance3D.new()
	_line.name = "LineaPesca"
	_line.mesh = ImmediateMesh.new()
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = Color(0.9, 0.9, 0.85, 0.8)
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line.material_override = _line_mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_line)

	_splash = CPUParticles3D.new()
	_splash.emitting = false
	_splash.one_shot = true
	_splash.amount = 18
	_splash.lifetime = 0.7
	_splash.explosiveness = 0.95
	_splash.direction = Vector3.UP
	_splash.spread = 35.0
	_splash.initial_velocity_min = 1.5
	_splash.initial_velocity_max = 2.8
	_splash.gravity = Vector3(0, -7.0, 0)
	var pm: SphereMesh = SphereMesh.new()
	pm.radius = 0.04
	pm.height = 0.08
	pm.radial_segments = 4
	pm.rings = 2
	_splash.mesh = pm
	_splash.material_override = _mat(Color(0.85, 0.95, 1.0))
	root.add_child(_splash)

func _mat(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m

func _ring(pos: Vector3) -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	var tm: TorusMesh = TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 16
	tm.ring_segments = 3
	mi.mesh = tm
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 0.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = Vector3(pos.x, _water_y + 0.03, pos.z)
	mi.scale = Vector3(0.1, 0.05, 0.1)
	var tw: Tween = mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(0.7, 0.05, 0.7), 1.4)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.4)
	tw.chain().tween_callback(mi.queue_free)

func _capturar() -> void:
	var pos: Vector3 = _target
	var resto: int = Inventario.agregar("pescado", 1)
	if resto > 0:
		_msg("Se te escapó: el inventario está lleno.")
	else:
		_msg("Sacás un pescado.")
		Isla.registrar_evento("explorar", pos, 0.2)
	if player != null:
		player.play_action("pickup")
	AudioManager.play(get_tree(), "drip", pos, 2.0)
	_ring(pos)
	cancelar()

func _process(delta: float) -> void:
	if _estado == Estado.IDLE:
		return
	if _float == null or not is_instance_valid(_float) or player == null or not is_instance_valid(player):
		cancelar()
		return
	if player.dead or not player.controllable:
		cancelar()
		return
	if player.global_position.distance_to(_target) > CANCEL_DIST:
		_msg("Se te cortó la línea por alejarte.")
		cancelar()
		return
	_time += delta
	if not _flying:
		_animar(delta)
	_actualizar_linea()

func _animar(delta: float) -> void:
	var bob: float = sin(_time * 2.2) * 0.02
	var drift: Vector3 = Vector3.ZERO
	var target_sink: float = 0.0
	match _estado:
		Estado.ESPERANDO:
			drift = Vector3(sin(_time * 0.7), 0.0, cos(_time * 0.9)) * 0.15
			_timer -= delta
			_ripple_t -= delta
			if _ripple_t <= 0.0:
				_ripple_t = 3.5
				_ring(_float.global_position)
			if _timer <= 0.0:
				_estado = Estado.PICADA
				_timer = BITE_WINDOW
				_msg("¡Algo picó! Tirá ahora (T).")
				_splash.global_position = Vector3(_target.x, _water_y, _target.z)
				_splash.restart()
				_splash.emitting = true
				AudioManager.play(get_tree(), "drip", _target, 0.0)
		Estado.PICADA:
			target_sink = 0.18
			bob = sin(_time * 18.0) * 0.03
			_timer -= delta
			if _timer <= 0.0:
				_msg("Se soltó.")
				_estado = Estado.ESPERANDO
				_timer = _rng.randf_range(6.0, 18.0)
	_sink = lerpf(_sink, target_sink, clampf(delta * 8.0, 0.0, 1.0))
	_float.global_position = Vector3(_target.x + drift.x, _water_y + 0.02 + bob - _sink, _target.z + drift.z)

func _actualizar_linea() -> void:
	if _line == null or not is_instance_valid(_line):
		return
	var im: ImmediateMesh = _line.mesh as ImmediateMesh
	im.clear_surfaces()
	var a: Vector3 = player.hand_transform().origin
	var b: Vector3 = _float.global_position + Vector3(0, 0.1, 0)
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _line_mat)
	var n: int = 8
	for i: int in range(n + 1):
		var t: float = float(i) / float(n)
		var p: Vector3 = a.lerp(b, t)
		if not _flying:
			p.y -= sin(t * PI) * 0.25
		im.surface_add_vertex(p)
	im.surface_end()

# ---------------------------------------------------------------- visuales

static func _smat(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m

## Caña: eje largo en X, punta hacia -X, empuñadura cerca del origen.
static func make_rod_visual() -> Node3D:
	var root: Node3D = Node3D.new()
	var rod: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.008
	cm.bottom_radius = 0.02
	cm.height = 1.3
	cm.radial_segments = 6
	rod.mesh = cm
	rod.material_override = _smat(Color(0.42, 0.27, 0.13))
	rod.rotation_degrees = Vector3(0, 0, 90)  # top (fino) hacia -X
	rod.position = Vector3(-0.55, 0, 0)
	root.add_child(rod)
	var reel: MeshInstance3D = MeshInstance3D.new()
	var rm: CylinderMesh = CylinderMesh.new()
	rm.top_radius = 0.045
	rm.bottom_radius = 0.045
	rm.height = 0.04
	rm.radial_segments = 8
	reel.mesh = rm
	reel.material_override = _smat(Color(0.55, 0.55, 0.6))
	reel.rotation_degrees = Vector3(90, 0, 0)
	reel.position = Vector3(-0.05, -0.05, 0.0)
	root.add_child(reel)
	var grip: MeshInstance3D = MeshInstance3D.new()
	var gm: CylinderMesh = CylinderMesh.new()
	gm.top_radius = 0.026
	gm.bottom_radius = 0.026
	gm.height = 0.22
	gm.radial_segments = 6
	grip.mesh = gm
	grip.material_override = _smat(Color(0.15, 0.12, 0.1))
	grip.rotation_degrees = Vector3(0, 0, 90)
	grip.position = Vector3(0.0, 0, 0)
	root.add_child(grip)
	return root

## Pez low poly pequeño; mirando hacia +X, cola en -X... (cabeza +X, cola -X).
static func make_fish_visual() -> Node3D:
	var root: Node3D = Node3D.new()
	var body: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	body.mesh = sm
	body.scale = Vector3(0.14, 0.07, 0.04)
	body.material_override = _smat(Color(0.55, 0.65, 0.72))
	root.add_child(body)
	var tail: MeshInstance3D = MeshInstance3D.new()
	var pm: PrismMesh = PrismMesh.new()
	pm.size = Vector3(0.08, 0.1, 0.015)
	tail.mesh = pm
	tail.material_override = _smat(Color(0.45, 0.55, 0.65))
	tail.rotation_degrees = Vector3(0, 0, 90)  # vértice hacia el cuerpo
	tail.position = Vector3(-0.17, 0, 0)
	root.add_child(tail)
	var eye: MeshInstance3D = MeshInstance3D.new()
	var em: SphereMesh = SphereMesh.new()
	em.radius = 0.01
	em.height = 0.02
	em.radial_segments = 4
	em.rings = 2
	eye.mesh = em
	eye.material_override = _smat(Color(0.05, 0.05, 0.05))
	eye.position = Vector3(0.1, 0.02, 0.03)
	root.add_child(eye)
	return root
