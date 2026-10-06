class_name ThornRoots
extends Node3D

## Raíces espinosas. El suelo se agrieta y tiembla (advertencia), luego brotan espinas.
## Quien esté dentro recibe daño y queda ralentizado un rato.

signal finished(hit: bool, aim: Vector3, player_pos: Vector3)

var player: Castaway
var terrain: IslandTerrain
var center: Vector3 = Vector3.ZERO
var radius: float = 3.0
var warn_time: float = 1.8
var damage: float = 12.0
var slow_time: float = 3.5
var stay_time: float = 5.0

var _t: float = 0.0
var _phase: int = 0       # 0 advertencia, 1 espinas, 2 retirada
var _crack: MeshInstance3D
var _crack_mat: StandardMaterial3D
var _bumps: Array[MeshInstance3D] = []
var _thorns: Array[Node3D] = []

func _ready() -> void:
	global_position = center
	AudioManager.play(get_tree(), "rumble", center, -10.0)
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.albedo_color = Color(0.12, 0.07, 0.08, 0.0)
	_crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_mat.roughness = 1.0
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.03
	disc.radial_segments = 18
	_crack = MeshInstance3D.new()
	_crack.mesh = disc
	_crack.material_override = _crack_mat
	_crack.position = Vector3(0, 0.1, 0)
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.22, 0.12, 0.1)
	bm.roughness = 1.0
	for i in 9:
		var a: float = randf() * TAU
		var r: float = sqrt(randf()) * radius * 0.9
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.12
		cone.height = 0.3
		cone.radial_segments = 4
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = bm
		mi.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		add_child(mi)
		_bumps.append(mi)

func _gy(p: Vector3) -> float:
	return terrain.height_at(p.x, p.z) if terrain != null else center.y

func _process(delta: float) -> void:
	_t += delta
	match _phase:
		0:
			var k: float = clampf(_t / warn_time, 0.0, 1.0)
			_crack_mat.albedo_color.a = k * 0.8
			for b: MeshInstance3D in _bumps:
				b.scale.y = 0.4 + (0.5 + 0.5 * sin(_t * 18.0 + b.position.x * 5.0)) * 1.4 * k
			if player != null and is_instance_valid(player):
				player.add_shake(0.06 + 0.1 * k)
			if _t >= warn_time:
				_erupt()
		1:
			if _t >= stay_time:
				_phase = 2
				_t = 0.0
		2:
			var s: float = clampf(1.0 - _t / 1.0, 0.0, 1.0)
			for th: Node3D in _thorns:
				th.scale.y = maxf(s, 0.001)
			_crack_mat.albedo_color.a = 0.8 * s
			if s <= 0.0:
				queue_free()

func _erupt() -> void:
	_phase = 1
	_t = 0.0
	AudioManager.play(get_tree(), "crack", center, 0.0)
	for b: MeshInstance3D in _bumps:
		b.queue_free()
	_bumps.clear()
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.18, 0.1, 0.08)
	tm.roughness = 1.0
	var tip := StandardMaterial3D.new()
	tip.albedo_color = Color(0.5, 0.1, 0.1)
	var count: int = 14
	for i in count:
		var a: float = TAU * float(i) / float(count) + randf() * 0.4
		var r: float = (radius * 0.95) if i % 2 == 0 else randf() * radius * 0.8
		var h: float = randf_range(1.3, 2.4)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = randf_range(0.14, 0.24)
		cone.height = h
		cone.radial_segments = 5
		var holder := Node3D.new()
		var wp: Vector3 = center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		holder.position = Vector3(cos(a) * r, _gy(wp) - center.y, sin(a) * r)
		holder.rotation = Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = tm if i % 3 != 0 else tip
		mi.position = Vector3(0, h * 0.5, 0)
		holder.add_child(mi)
		holder.scale = Vector3(1, 0.01, 1)
		add_child(holder)
		var tw: Tween = create_tween()
		tw.tween_property(holder, "scale", Vector3(1, 1, 1), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_thorns.append(holder)
	var hit: bool = false
	var ppos: Vector3 = Vector3.ZERO
	if player != null and is_instance_valid(player):
		ppos = player.global_position
		var horiz: float = Vector2(ppos.x - center.x, ppos.z - center.z).length()
		if horiz < radius + 0.4 and ppos.y < center.y + 2.0:
			hit = true
			player.take_damage(damage, "raíces espinosas")
			player.apply_slow(slow_time)
		player.add_shake(0.5)
	finished.emit(hit, center, ppos)
