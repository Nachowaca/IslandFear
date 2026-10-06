class_name Wisp
extends Node3D

## Luz errante de la isla. Con `path` repite un recorrido que hizo el jugador (un eco de sus pasos);
## sin `path` flota a lo lejos y se aleja si te acercás. Nunca daña: es solo misterio.

var player: Node3D
var terrain: IslandTerrain
var path: Array[Vector3] = []
var life: float = 28.0
var color: Color = Color(0.65, 0.85, 1.0)
var speed: float = 2.6

var _light: OmniLight3D
var _mesh: MeshInstance3D
var _t: float = 0.0
var _idx: int = 0
var _seed: float = 0.0

func _ready() -> void:
	_seed = randf() * 10.0
	var s := SphereMesh.new()
	s.radius = 0.11
	s.height = 0.22
	s.radial_segments = 8
	s.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	s.material = m
	_mesh = MeshInstance3D.new()
	_mesh.mesh = s
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	add_child(_light)

func _process(delta: float) -> void:
	_t += delta
	var fade: float = clampf(_t / 2.0, 0.0, 1.0) * clampf((life - _t) / 3.0, 0.0, 1.0)
	if _t >= life:
		queue_free()
		return
	if not path.is_empty():
		if _idx >= path.size():
			life = minf(life, _t + 3.0)
		else:
			var tgt: Vector3 = path[_idx] + Vector3(0, 1.4, 0)
			var to: Vector3 = tgt - global_position
			if to.length() < 0.5:
				_idx += 1
			else:
				global_position += to.normalized() * speed * delta
	else:
		if player != null and is_instance_valid(player):
			var away: Vector3 = global_position - player.global_position
			away.y = 0.0
			if away.length() < 9.0:
				global_position += away.normalized() * 3.2 * delta
		global_position.x += sin(_t * 0.7 + _seed) * 0.6 * delta
		global_position.z += cos(_t * 0.5 + _seed) * 0.6 * delta
		if terrain != null:
			var g: float = terrain.height_at(global_position.x, global_position.z)
			global_position.y = lerpf(global_position.y, maxf(g, 0.5) + 1.6, delta * 2.0)
	_mesh.position.y = sin(_t * 2.3 + _seed) * 0.12
	if player != null and is_instance_valid(player) and global_position.distance_to(player.global_position) < 3.0:
		life = minf(life, _t + 1.2)           # se apaga si te acercás demasiado
	_light.light_energy = 1.7 * fade * (0.85 + 0.15 * sin(_t * 9.0 + _seed))
	_mesh.scale = Vector3.ONE * maxf(fade, 0.001)
