class_name FootFx
extends Node3D

## Contacto del jugador con el mundo:
## - alimenta al shader de vegetación con dónde está pisando y dónde estuvo (plantas que se doblan, se aplastan y vuelven con retraso)
## - huellas en la arena (decals que se borran despacio; más marcadas en arena mojada)
## - puñados de hojas y briznas al pisar pasto, y nubes de arena al correr por la playa

const MAX_PRINTS := 56
const PRINT_LIFE := 110.0          ## segundos hasta que una huella se borra del todo
const SAND_MAX_H := 1.7            ## por encima de esto ya no es arena (coincide con el shader)
const DECAL_LAYER := 1 << 19

var player: Castaway
var terrain: IslandTerrain

var _hist: Array[Vector3] = []     ## posiciones recientes (una cada 0.05 s)
var _hist_timer: float = 0.0
var _decals: Array[Decal] = []
var _decal_born: Array[float] = []
var _decal_base: Array[float] = []
var _next_decal: int = 0
var _side: float = 1.0
var _time: float = 0.0
var _leaf_fx: CPUParticles3D
var _sand_fx: CPUParticles3D
var _print_tex: ImageTexture
var _print_tex_l: ImageTexture

func _ready() -> void:
	_print_tex = _make_print_texture()
	var flipped: Image = _print_tex.get_image()
	flipped.flip_x()
	flipped.generate_mipmaps()
	_print_tex_l = ImageTexture.create_from_image(flipped)
	for i in MAX_PRINTS:
		var d := Decal.new()
		d.size = Vector3(0.3, 0.8, 0.52)
		d.texture_albedo = _print_tex
		d.cull_mask = DECAL_LAYER
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.visible = false
		add_child(d)
		_decals.append(d)
		_decal_born.append(-1000.0)
		_decal_base.append(1.0)
	_leaf_fx = _make_burst(Color(0.34, 0.55, 0.2), 0.07, true)
	_sand_fx = _make_burst(Color(0.85, 0.77, 0.55), 0.05, false)
	add_child(_leaf_fx)
	add_child(_sand_fx)
	call_deferred("_link")

func _link() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Castaway
	if player != null:
		player.stepped.connect(_on_step)

func _process(delta: float) -> void:
	_time += delta
	if player == null:
		return
	# historial para la "inercia" de la vegetación
	_hist_timer += delta
	if _hist_timer >= 0.05:
		_hist_timer = 0.0
		_hist.push_front(player.global_position)
		if _hist.size() > 24:
			_hist.resize(24)
	if _hist.is_empty():
		_hist.append(player.global_position)
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var power: float = clampf(0.55 + speed / 6.0, 0.0, 1.0)
	var idx: Array[int] = [0, 5, 11, 20]
	for k in 4:
		var h: Vector3 = _hist[mini(idx[k], _hist.size() - 1)]
		var cur: Vector3 = player.global_position if k == 0 else h
		RenderingServer.global_shader_parameter_set("foot_%d" % k, Vector4(cur.x, cur.y, cur.z, power))
	# desvanecer huellas
	for i in MAX_PRINTS:
		var d: Decal = _decals[i]
		if not d.visible:
			continue
		var age: float = _time - _decal_born[i]
		if age > PRINT_LIFE:
			d.visible = false
			continue
		var a: float = _decal_base[i] * (1.0 - smoothstep(PRINT_LIFE * 0.35, PRINT_LIFE, age))
		d.modulate = Color(1, 1, 1, a)

func _heading() -> Vector3:
	var v: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if v.length() > 0.3:
		return v.normalized()
	return Vector3(0, 0, -1).rotated(Vector3.UP, player.global_rotation.y)

func _on_step(_surface: String, power: float) -> void:
	if terrain == null or player == null or player.dead:
		return
	var pos: Vector3 = player.global_position
	var h: float = terrain.height_at(pos.x, pos.z)
	if h < 0.38:
		return                                   # en el agua
	var fwd: Vector3 = _heading()
	var right: Vector3 = fwd.cross(Vector3.UP)
	_side = -_side
	var foot: Vector3 = pos + right * 0.13 * _side + fwd * 0.08
	foot.y = terrain.height_at(foot.x, foot.z)
	if h < SAND_MAX_H:
		_leave_print(foot, fwd, _side, h)
		_puff(_sand_fx, foot, power)
	else:
		_puff(_leaf_fx, foot, power)

func _leave_print(foot: Vector3, fwd: Vector3, side: float, h: float) -> void:
	var i: int = _next_decal
	_next_decal = (_next_decal + 1) % MAX_PRINTS
	var d: Decal = _decals[i]
	d.visible = true
	d.global_position = foot + Vector3(0, 0.15, 0)
	var yaw: float = atan2(-fwd.x, -fwd.z)
	d.global_rotation = Vector3(0, yaw, 0)
	d.texture_albedo = _print_tex if side > 0.0 else _print_tex_l   # pie derecho / izquierdo
	# más marcada y oscura sobre arena húmeda
	var wet: float = 1.0 - smoothstep(0.45, 1.25, h)
	d.modulate = Color(1, 1, 1, 1)
	d.albedo_mix = lerpf(0.4, 0.7, wet)
	_decal_base[i] = lerpf(0.75, 1.0, wet)
	_decal_born[i] = _time

func _puff(fx: CPUParticles3D, at: Vector3, power: float) -> void:
	fx.global_position = at + Vector3(0, 0.08, 0)
	fx.amount = 6 + int(power * 6.0)
	fx.restart()
	fx.emitting = true

func _make_burst(color: Color, size: float, leafy: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size * 1.6, size) if leafy else Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED if leafy else BaseMaterial3D.BILLBOARD_ENABLED
	m.roughness = 1.0
	q.material = m
	p.mesh = q
	p.one_shot = true
	p.emitting = false
	p.amount = 8
	p.lifetime = 0.9 if leafy else 0.6
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0 if leafy else 1.2
	p.gravity = Vector3(0, -3.2 if leafy else -2.0, 0)
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	p.color = color
	if leafy:
		p.hue_variation_min = -0.08
		p.hue_variation_max = 0.1
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Huella de pie: suela ovalada con talón redondo y cinco dedos, texturizada en alfa.
func _make_print_texture() -> ImageTexture:
	var w: int = 48
	var hgt: int = 96
	var img := Image.create(w, hgt, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Color(0.4, 0.31, 0.2, 1.0)
	for y in hgt:
		for x in w:
			var u: float = (float(x) + 0.5) / w * 2.0 - 1.0     # -1..1
			var v: float = (float(y) + 0.5) / hgt * 2.0 - 1.0   # -1 (punta) .. 1 (talón)
			var a: float = 0.0
			# talón
			var heel: float = (u * u) / 0.22 + ((v - 0.62) * (v - 0.62)) / 0.1
			if heel < 1.0:
				a = maxf(a, 1.0 - heel * 0.4)
			# arco y planta (más angosta en el medio)
			var arch_w: float = lerpf(0.34, 0.5, smoothstep(-0.3, -0.7, v))
			var ball: float = (u + 0.05) * (u + 0.05) / (arch_w * arch_w) + ((v + 0.3) * (v + 0.3)) / 0.18
			if ball < 1.0 and v > -0.65 and v < 0.35:
				a = maxf(a, 1.0 - ball * 0.4)
			# dedos
			for t in 5:
				var cx: float = -0.42 + 0.21 * t
				var cy: float = -0.74 - 0.05 * (1.0 - absf(t - 1.0) / 3.0) + 0.04 * t
				var r: float = 0.115 - 0.012 * t
				var dd: float = ((u - cx) * (u - cx) + (v - cy) * (v - cy) * 0.55) / (r * r)
				if dd < 1.0:
					a = maxf(a, 1.0 - dd * 0.35)
			if a > 0.0:
				col.a = clampf(a * 1.4, 0.0, 1.0)
				img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

