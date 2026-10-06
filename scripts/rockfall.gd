class_name Rockfall
extends Node3D

## Caída de roca. Primero un círculo de advertencia en el suelo, después la roca cae.
## Si el jugador sigue dentro del círculo al impactar, recibe daño.

signal finished(hit: bool, aim: Vector3, player_pos: Vector3)

var player: Castaway
var target: Vector3 = Vector3.ZERO     # punto de impacto (sobre el suelo)
var warn_time: float = 1.6
var fall_height: float = 24.0
var damage: float = 18.0
var radius: float = 2.2
var rock_radius: float = 0.8

var _t: float = 0.0
var _phase: int = 0        # 0 advertencia, 1 cae, 2 escombros
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _rock: MeshInstance3D
var _vy: float = 0.0
var _life: float = 0.0

func _ready() -> void:
	global_position = target
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(0.95, 0.25, 0.1, 0.25)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(1.0, 0.3, 0.1)
	_ring_mat.emission_energy_multiplier = 1.5
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.04
	disc.radial_segments = 20
	_ring = MeshInstance3D.new()
	_ring.mesh = disc
	_ring.material_override = _ring_mat
	_ring.position = Vector3(0, 0.12, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	var sm := SphereMesh.new()
	sm.radius = rock_radius
	sm.height = rock_radius * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.36, 0.35, 0.34)
	rm.roughness = 1.0
	_rock = MeshInstance3D.new()
	_rock.mesh = sm
	_rock.material_override = rm
	_rock.visible = false
	_rock.scale = Vector3(1.0, 0.85, 1.1)
	_rock.rotation = Vector3(randf(), randf() * TAU, randf())
	add_child(_rock)
	AudioManager.play(get_tree(), "rumble", target, -8.0)   # retumbar de advertencia

func _process(delta: float) -> void:
	_t += delta
	match _phase:
		0:
			var k: float = clampf(_t / warn_time, 0.0, 1.0)
			var blink: float = 0.5 + 0.5 * sin(_t * (6.0 + 14.0 * k))
			_ring_mat.albedo_color.a = lerpf(0.15, 0.55, k) * (0.6 + 0.4 * blink)
			_ring.scale = Vector3(lerpf(1.1, 0.95, k), 1.0, lerpf(1.1, 0.95, k))
			if player != null and is_instance_valid(player) and k > 0.3:
				player.add_shake(0.08 + 0.12 * k)
			if _t >= warn_time:
				_phase = 1
				_t = 0.0
				_rock.visible = true
				_rock.position = Vector3(0, fall_height, 0)
				_vy = -4.0
		1:
			_vy -= 48.0 * delta
			_rock.position.y += _vy * delta
			_rock.rotation.x += delta * 3.0
			if _rock.position.y <= rock_radius * 0.55:
				_impact()
		2:
			_life += delta
			if _life > 18.0:
				var s: float = clampf(1.0 - (_life - 18.0) / 2.0, 0.0, 1.0)
				_rock.scale = Vector3(1.0, 0.85, 1.1) * s
				if s <= 0.0:
					queue_free()

func _impact() -> void:
	_phase = 2
	_rock.position.y = rock_radius * 0.5
	_ring.visible = false
	var hit: bool = false
	var ppos: Vector3 = Vector3.ZERO
	if player != null and is_instance_valid(player):
		ppos = player.global_position
		var horiz: float = Vector2(ppos.x - target.x, ppos.z - target.z).length()
		if horiz < radius and ppos.y < target.y + 3.0:
			hit = true
			player.take_damage(damage, "una roca")
		var d: float = Vector2(ppos.x - target.x, ppos.z - target.z).length()
		player.add_shake(clampf(0.7 - d * 0.04, 0.1, 0.7))
	_dust()
	AudioManager.play(get_tree(), "boom", target, 2.0)
	finished.emit(hit, target, ppos)

func _dust() -> void:
	var p := CPUParticles3D.new()
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	s.radial_segments = 5
	s.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.5, 0.45)
	s.material = m
	p.mesh = s
	p.one_shot = true
	p.emitting = true
	p.explosiveness = 1.0
	p.amount = 34
	p.lifetime = 1.4
	p.direction = Vector3.UP
	p.spread = 80.0
	p.gravity = Vector3(0, -5.0, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.4
	p.position = Vector3(0, 0.3, 0)
	add_child(p)
