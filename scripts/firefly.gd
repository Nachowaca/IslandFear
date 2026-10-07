class_name Firefly
extends Node3D

## Luciérnaga de la isla: un regalo de noche. Si la isla confía en el náufrago (vínculo alto),
## lo acompaña y le da luz; de día se retira a su escondite. Sin avisos ni indicadores:
## el jugador solo nota que a veces tiene luz y a veces no.

const TRUST_ON: float = 15.0      ## vínculo para que venga (etapa "Tolerante")
const TRUST_OFF: float = 8.0      ## por debajo de esto se va (histéresis para no parpadear)
const NIGHT_ON: float = 0.55
const NIGHT_OFF: float = 0.3
const LIGHT_ENERGY: float = 1.7
const LIGHT_RANGE: float = 6.0
const GUIA_RADIO: float = 3.0        ## distancia al jugador a la que ofrece un objeto
const GUIA_AZUL: Color = Color(0.5, 0.72, 1.0)
const COLOR_CALIDO: Color = Color(1.0, 0.86, 0.5)

var player: Node3D
var terrain: IslandTerrain
var daynight: DayNight

var following: bool = false
var _hideout: Vector3 = Vector3(10, 3, 10)
var _light: OmniLight3D
var _mat: StandardMaterial3D
var _mesh: MeshInstance3D
var _t: float = 0.0
var _seed: float = 0.0
var _energy: float = 0.0
var _prev_player: Vector3 = Vector3.ZERO
var _lead: Vector3 = Vector3.ZERO
var _guia: WorldItem = null
var _guia_t: float = 0.0
var _azul: float = 0.0

func _ready() -> void:
	_seed = randf() * 20.0
	var s := SphereMesh.new()
	s.radius = 0.06
	s.height = 0.12
	s.radial_segments = 8
	s.rings = 4
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.9, 0.5)
	_mat.emission_energy_multiplier = 0.8
	_mat.albedo_color = Color(1.0, 0.92, 0.5)
	s.material = _mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = s
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.86, 0.5)
	_light.omni_range = LIGHT_RANGE
	_light.light_specular = 0.0
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	add_child(_light)
	_pick_hideout()
	global_position = _hideout
	if player != null:
		_prev_player = player.global_position

## Escondite: junto al tronco de un árbol del bosque, siempre el mismo.
func _pick_hideout() -> void:
	if terrain == null or terrain.tree_positions.is_empty():
		return
	var n: int = terrain.tree_positions.size()
	for i in n:
		var q: Vector3 = terrain.tree_positions[(7 + i * 13) % n]
		if q.y > 2.5 and Vector2(q.x, q.z).length() < 70.0:
			_hideout = q + Vector3(0.7, 0.9, 0.2)
			return

func _wants_follow() -> bool:
	if daynight == null:
		return false
	var night: float = daynight.night_amount
	if following:
		return night > NIGHT_OFF and Isla.vinculo >= TRUST_OFF
	return night > NIGHT_ON and Isla.vinculo >= TRUST_ON

## Busca cerca del jugador un recogible "útil" u "ofrenda" (meta guia) para sobrevolarlo con suavidad.
func _buscar_guia(ppos: Vector3) -> WorldItem:
	var best: WorldItem = null
	var best_d: float = GUIA_RADIO
	for n: Node in get_tree().get_nodes_in_group("pickup"):
		var it: WorldItem = n as WorldItem
		if it == null or it.is_queued_for_deletion() or not it.has_meta("guia"):
			continue
		var d: float = it.global_position.distance_to(ppos)
		if d < best_d and d > 1.0:
			best_d = d
			best = it
	return best

func _process(delta: float) -> void:
	if player == null:
		return
	_t += delta
	following = _wants_follow()
	var ppos: Vector3 = player.global_position
	var vel: Vector3 = (ppos - _prev_player) / maxf(delta, 0.0001)
	vel.y = 0.0
	_prev_player = ppos
	_lead = _lead.lerp(vel.limit_length(5.0) * 0.5, 1.0 - exp(-2.0 * delta))
	var target: Vector3
	var speed: float = 3.0
	var tag: float = 0.0
	if following:
		var a: float = _t * 0.7 + _seed
		target = ppos + Vector3(cos(a) * 1.3, 1.7 + sin(_t * 1.3 + _seed) * 0.25, sin(a) * 1.3) + _lead
		_guia_t -= delta
		if _guia_t <= 0.0:
			_guia_t = 0.7
			_guia = _buscar_guia(ppos)
		if _guia != null and (not is_instance_valid(_guia) or _guia.is_queued_for_deletion() or _guia.global_position.distance_to(ppos) < 1.0):
			_guia = null
		if _guia != null:
			var gp: Vector3 = _guia.global_position
			target = gp + Vector3(sin(_t * 0.9) * 0.15, 0.75 + sin(_t * 1.6) * 0.1, cos(_t * 0.8) * 0.15)
		var d: float = global_position.distance_to(ppos)
		speed = 3.0 + clampf(d - 3.0, 0.0, 30.0) * 0.9
		if _guia != null:
			speed = 1.6                        # sutil: se desliza hacia el objeto, sin apuro
		tag = 1.0
	else:
		_guia = null
		target = _hideout + Vector3(sin(_t * 0.6 + _seed) * 0.1, sin(_t * 1.1) * 0.08, 0.0)
		speed = 4.0
	var to: Vector3 = target - global_position
	var step: float = minf(to.length(), speed * delta * maxf(1.0, to.length() * 0.6))
	if to.length() > 0.001:
		global_position += to.normalized() * step
	if terrain != null:
		var g: float = terrain.height_at(global_position.x, global_position.z)
		if g > -50.0:
			global_position.y = maxf(global_position.y, g + 0.6)
	# luz: pareja y cálida con un parpadeo suave; en el escondite apenas un destello
	var flick: float = 0.88 + 0.12 * sin(_t * 9.0 + _seed) * sin(_t * 3.7 + _seed * 2.0)
	var want: float = LIGHT_ENERGY * flick if following else 0.0
	_energy = lerpf(_energy, want, 1.0 - exp(-1.2 * delta))
	var azul_want: float = 1.0 if (_guia != null and str(_guia.get_meta("guia", "")) == "ofrenda") else 0.0
	_azul = lerpf(_azul, azul_want, 1.0 - exp(-2.5 * delta))
	_light.light_color = COLOR_CALIDO.lerp(GUIA_AZUL, _azul)
	_mat.emission = Color(1.0, 0.9, 0.5).lerp(GUIA_AZUL, _azul)
	_light.light_energy = _energy
	_light.visible = _energy > 0.02
	var glow: float = 0.25 + 0.75 * clampf(_energy / LIGHT_ENERGY, 0.0, 1.0)
	_mat.albedo_color = Color(1.0, 0.92, 0.5).lerp(GUIA_AZUL, _azul) * (0.35 + glow * 0.6)   # <1: bajo el umbral de glow (evita bloques)
	_mesh.scale = Vector3.ONE * (0.8 + glow * 0.5 + 0.1 * sin(_t * 7.0 + _seed))
	if tag == 0.0 and global_position.distance_to(_hideout) < 0.4:
		_mesh.scale = Vector3.ONE * (0.55 + 0.1 * sin(_t * 2.0))
