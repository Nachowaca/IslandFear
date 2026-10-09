class_name TemploCastigo
extends Node

## El templo (zonas sagradas "heart") no se pisa sin respeto.
## - Quedarse 20 s sin hacer nada: la isla avisa y da 6 s para irse. Si seguís, castigo.
## - Hacer fuego en el templo: aviso de 3 s y castigo mayor, sin escape.
## Castigo: la tierra tiembla, llega una tormenta y el personaje asciende como un ángel hacia el bote. Cuesta una vida.

const QUIETO_AVISO: float = 20.0
const VENTANA: float = 6.0
const VENTANA_FUEGO: float = 3.0
const MARGEN: float = 2.0

var player: Castaway
var brain: IslandBrain
var features: IslandFeatures
var boat: Node3D

var _quieto: float = 0.0
var _estado: String = "libre"        ## libre | aviso | castigo
var _t_aviso: float = 0.0
var _fuerte: bool = false
var _spot_pos: Vector3 = Vector3.ZERO
var _spot_r: float = 0.0
var _capa: CanvasLayer
var _oscuro: ColorRect
var _flash: ColorRect
var _lluvia: CPUParticles3D
var _lluvia_snd: AudioStreamPlayer
var _tormenta: float = 0.0

func _ready() -> void:
	add_to_group("templo")
	Isla.evento_registrado.connect(_on_evento)
	Inventario.sembrar_paz()

func _templo_en(pos: Vector3, extra: float) -> Dictionary:
	if features == null:
		return {}
	for sp: Dictionary in features.sacred_spots:
		if str(sp["kind"]) != "heart":
			continue
		var p: Vector3 = sp["pos"]
		if Vector2(pos.x - p.x, pos.z - p.z).length() < float(sp["radius"]) + extra:
			return sp
	return {}

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.dead or not player.controllable:
		return
	if _estado == "castigo":
		return
	var vel: Vector3 = player.velocity
	var rapido: float = Vector2(vel.x, vel.z).length()
	var dentro: Dictionary = _templo_en(player.global_position, 0.0)
	if _estado == "libre":
		if not dentro.is_empty() and rapido < 0.3:
			_quieto += delta
		else:
			_quieto = maxf(_quieto - delta * 2.0, 0.0)
		if _quieto >= QUIETO_AVISO:
			_avisar(dentro, false, VENTANA, "Ya verás lo que es ofender a la isla.")
	elif _estado == "aviso":
		_t_aviso -= delta
		if not _fuerte:
			var aun: Dictionary = _templo_en(player.global_position, MARGEN)
			if aun.is_empty():
				_estado = "libre"                       # se fue a tiempo: la isla queda enojada, nada más
				_quieto = 0.0
				brain._add_offense(12.0, "sacred")
				brain._say("Hacés bien en irte.", "omen")
				return
		if _t_aviso <= 0.0:
			_castigar()

func _avisar(sp: Dictionary, fuerte: bool, ventana: float, texto: String) -> void:
	_estado = "aviso"
	_fuerte = fuerte
	_t_aviso = ventana
	_spot_pos = sp["pos"]
	_spot_r = float(sp["radius"])
	brain._say(texto, "omen")
	player.add_shake(0.5)

func _on_evento(tipo: String, zona: Vector3, _i: float) -> void:
	if tipo != "fuego" or _estado != "libre" or player == null or player.dead:
		return
	var sp: Dictionary = _templo_en(zona, 3.0)
	if sp.is_empty():
		return
	_avisar(sp, true, VENTANA_FUEGO, "No en mi corazón.")

# ------------------------------------------------------------------ castigo

func _castigar() -> void:
	_estado = "castigo"
	player.controllable = false
	player.sitting = false
	player.zoom_fov = 0.0
	var dur: float = 11.0 if _fuerte else 7.0
	IslandBrain.s_rencor = 40.0 if _fuerte else 25.0
	_preparar_tormenta()
	_temblar(dur)
	var tw: Tween = create_tween()
	tw.tween_property(self, "_tormenta", 1.0, 3.0)
	await get_tree().create_timer(dur).timeout
	await _ascender()

func _temblar(dur: float) -> void:
	AudioManager.play(get_tree(), "rumble", player.global_position, 2.0)
	var n: int = int(dur / 0.3)
	for i in n:
		if player == null or not is_instance_valid(player):
			return
		player.add_shake((0.9 if _fuerte else 0.65) * clampf(float(i) / 4.0, 0.3, 1.0))
		if i % 12 == 4:
			_rayo()
		await get_tree().create_timer(0.3).timeout

func _preparar_tormenta() -> void:
	_capa = CanvasLayer.new()
	_capa.layer = 0
	add_child(_capa)
	_oscuro = ColorRect.new()
	_oscuro.color = Color(0.02, 0.03, 0.07, 0.0)
	_oscuro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_oscuro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capa.add_child(_oscuro)
	_flash = ColorRect.new()
	_flash.color = Color(0.85, 0.9, 1.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capa.add_child(_flash)
	_lluvia = CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.015, 0.8, 0.015)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 0.8, 0.95, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = mat
	_lluvia.mesh = bm
	_lluvia.amount = 900
	_lluvia.lifetime = 0.8
	_lluvia.preprocess = 0.8
	_lluvia.direction = Vector3(0.12, -1.0, 0.0)
	_lluvia.spread = 3.0
	_lluvia.initial_velocity_min = 24.0
	_lluvia.initial_velocity_max = 30.0
	_lluvia.gravity = Vector3.ZERO
	_lluvia.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_lluvia.emission_box_extents = Vector3(14.0, 0.5, 14.0)
	_lluvia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lluvia.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	get_parent().add_child(_lluvia)
	_lluvia_snd = AudioStreamPlayer.new()
	_lluvia_snd.stream = SoundBank.rain()
	_lluvia_snd.volume_db = -30.0
	add_child(_lluvia_snd)
	_lluvia_snd.play()
	var dn: Node = get_tree().get_first_node_in_group("daynight")
	if dn != null:
		var tw: Tween = create_tween()
		tw.tween_property(dn, "fog_boost", 0.02, 4.0)
	set_process(true)

func _rayo() -> void:
	if _flash == null:
		return
	AudioManager.play(get_tree(), "boom", player.global_position + Vector3(8, 4, -6), 6.0)
	var tw: Tween = create_tween()
	_flash.color.a = 0.0
	tw.tween_property(_flash, "color:a", 0.75, 0.04)
	tw.tween_property(_flash, "color:a", 0.1, 0.08)
	tw.tween_property(_flash, "color:a", 0.5, 0.04)
	tw.tween_property(_flash, "color:a", 0.0, 0.5)

func _physics_process(_delta: float) -> void:
	if _estado != "castigo":
		return
	if _lluvia != null and player != null:
		_lluvia.global_position = player.global_position + Vector3(0, 13, 0)
	if _oscuro != null:
		_oscuro.color.a = 0.55 * _tormenta
	if _lluvia_snd != null:
		_lluvia_snd.volume_db = lerpf(-30.0, -4.0, _tormenta)

## El personaje se eleva con una luz blanca y vuela hacia el bote. Después, una vida menos.
func _ascender() -> void:
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.95, 0.85)
	luz.omni_range = 9.0
	luz.light_energy = 0.0
	player.add_child(luz)
	var chispas := CPUParticles3D.new()
	var qm := SphereMesh.new()
	qm.radius = 0.03
	qm.height = 0.06
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1.0, 0.95, 0.8)
	qm.material = cm
	chispas.mesh = qm
	chispas.amount = 40
	chispas.lifetime = 1.4
	chispas.direction = Vector3.UP
	chispas.spread = 40.0
	chispas.initial_velocity_min = 0.5
	chispas.initial_velocity_max = 1.5
	chispas.gravity = Vector3(0, 0.4, 0)
	chispas.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	chispas.emission_sphere_radius = 0.5
	chispas.position = Vector3(0, 1.0, 0)
	player.add_child(chispas)
	var inicio: Vector3 = player.global_position
	var destino: Vector3 = boat.global_position + Vector3(0, 2.5, 0) if boat != null else inicio + Vector3(0, 12, 0)
	var medio: Vector3 = inicio.lerp(destino, 0.5) + Vector3(0, 9.0, 0)
	var tw: Tween = create_tween()
	tw.tween_property(luz, "light_energy", 3.0, 2.0)
	var dur: float = 5.5
	var t0: float = 0.0
	AudioManager.play(get_tree(), "pad", player.global_position, 4.0)
	while t0 < dur:
		var dt: float = get_process_delta_time()
		t0 += maxf(dt, 0.016)
		var u: float = clampf(t0 / dur, 0.0, 1.0)
		var e: float = u * u * (3.0 - 2.0 * u)
		var a: Vector3 = inicio.lerp(medio, e)
		var b: Vector3 = medio.lerp(destino, e)
		player.global_position = a.lerp(b, e)
		player.rotation.y += 0.4 * dt
		await get_tree().process_frame
	var fade: Tween = create_tween()
	fade.tween_property(_flash, "color", Color(1, 1, 1, 1), 1.2)
	await fade.finished
	player.death_cause = "ofensa"
	player.dead = true
	player.died.emit()


## Con la semilla de paz en el corazón de la isla: se borra la ofensa y el rencor.
func calmar() -> bool:
	if player == null or _estado == "castigo":
		return false
	if _templo_en(player.global_position, 1.5).is_empty():
		return false
	_estado = "libre"
	_quieto = 0.0
	brain.offense = 0.0
	brain.hostility = 0.0
	IslandBrain.s_rencor = 0.0
	Isla.registrar_evento("ofrenda", player.global_position, 2.0)
	brain._say("Está bien. Te creo.", "whisper")
	AudioManager.play(get_tree(), "pad", player.global_position, 2.0)
	var chispas := CPUParticles3D.new()
	var qm := SphereMesh.new()
	qm.radius = 0.03
	qm.height = 0.06
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1.0, 0.95, 0.8)
	qm.material = cm
	chispas.mesh = qm
	chispas.amount = 30
	chispas.lifetime = 1.6
	chispas.one_shot = true
	chispas.explosiveness = 0.8
	chispas.direction = Vector3.UP
	chispas.spread = 60.0
	chispas.initial_velocity_min = 0.8
	chispas.initial_velocity_max = 2.0
	chispas.gravity = Vector3(0, 0.3, 0)
	chispas.position = Vector3(0, 0.5, 0)
	player.add_child(chispas)
	chispas.emitting = true
	get_tree().create_timer(2.5).timeout.connect(chispas.queue_free)
	return true
