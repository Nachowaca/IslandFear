class_name Weather
extends Node
## Clima caribeño: casi siempre sol, con lluvias tropicales cortas. La lluvia se ANUNCIA (se nubla, baja la luz, sube el viento)
## y nunca empieza de golpe. La isla influye según sus emociones (lluvia, tormenta fuerte o un día cálido y en paz).
## Estados: SOL -> NUBLANDO -> LLOVIZNA/LLUVIA/TORMENTA -> CLAREANDO -> SOL (o PAZ: sol sostenido).
## Duraciones en segundos de juego (una "jornada" de la isla = 300 s). `intensity` 0..1 es cuánta lluvia hay (la usa el sonido);
## `exposed` cuánto te toca a vos. Gancho para después: `wetness` (personaje mojado) ya se calcula, nadie lo usa todavía.

enum S { SOL, NUBLANDO, LLOVIZNA, LLUVIA, TORMENTA, CLAREANDO, PAZ }
const NOMBRES: Array[String] = ["Sol", "Nublando", "Llovizna", "Lluvia", "Tormenta", "Clareando", "Sol en paz"]

## Interruptor general: apagado = cielo limpio siempre y sin ciclo.
@export var enabled: bool = true
@export var sol_min: float = 450.0
@export var sol_max: float = 900.0
@export var paz_min: float = 700.0
@export var paz_max: float = 1100.0
@export var nublando_min: float = 40.0
@export var nublando_max: float = 60.0
@export var lluvia_min: float = 60.0
@export var lluvia_max: float = 150.0
@export var tormenta_min: float = 120.0
@export var tormenta_max: float = 180.0
@export var clareando_time: float = 40.0

var player: Node3D
var features: IslandFeatures
var terrain: IslandTerrain
var brain: IslandBrain

var state: int = S.SOL
var raining: bool = false
var intensity: float = 0.0
var exposed: float = 0.0
var wetness: float = 0.0          ## gancho: 0..1 personaje mojado (sin uso todavía)
var cloud: float = 0.0
var wind: float = 0.0

var _timer: float = 0.0
var _hold: bool = false           ## estado forzado desde el panel: no avanza solo
var _plan: String = "lluvia"
var _rng := RandomNumberGenerator.new()
var _drops: CPUParticles3D
var _drop_mat: StandardMaterial3D
var _shelter: float = 0.0
var _dn: DayNight
var _regrow_t: float = 0.0
var _thunder_t: float = 10.0
var _flash: ColorRect

func _ready() -> void:
	add_to_group("weather")
	_rng.randomize()
	_timer = _rng.randf_range(sol_min * 0.4, sol_max * 0.6)
	_drops = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.55)
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_drop_mat.albedo_color = Color(0.75, 0.85, 1.0, 0.5)
	_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = _drop_mat
	_drops.mesh = q
	_drops.amount = 1100
	_drops.lifetime = 0.9
	_drops.preprocess = 0.9
	_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drops.emission_box_extents = Vector3(18.0, 0.5, 18.0)
	_drops.direction = Vector3(0.12, -1.0, 0.05)
	_drops.spread = 3.0
	_drops.gravity = Vector3(0.0, -22.0, 0.0)
	_drops.initial_velocity_min = 14.0
	_drops.initial_velocity_max = 18.0
	_drops.local_coords = false
	_drops.emitting = false
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drops.visibility_aabb = AABB(Vector3(-30, -25, -30), Vector3(60, 40, 60))
	add_child(_drops)
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(0.85, 0.9, 1.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)

# ------------------------------------------------------------------ control

func nombre() -> String:
	return NOMBRES[state] + (" (fijo)" if _hold else "")

## Fuerza un estado (panel de pruebas). Queda fijo hasta `auto()`.
func forzar(s: int) -> void:
	_cambiar(s)
	_hold = true
	if s == S.NUBLANDO:
		cloud = maxf(cloud, 0.0)

func auto() -> void:
	_hold = false
	_timer = 5.0

func _dur(s: int) -> float:
	match s:
		S.SOL:
			return _rng.randf_range(sol_min, sol_max) * clampf(1.0 - _hostil() / 200.0, 0.6, 1.0)
		S.PAZ:
			return _rng.randf_range(paz_min, paz_max)
		S.NUBLANDO:
			return _rng.randf_range(nublando_min, nublando_max)
		S.LLOVIZNA, S.LLUVIA:
			return _rng.randf_range(lluvia_min, lluvia_max)
		S.TORMENTA:
			return _rng.randf_range(tormenta_min, tormenta_max)
	return clareando_time

func _hostil() -> float:
	return brain._effective_hostility() if brain != null else 0.0

func _cambiar(s: int) -> void:
	var antes: int = state
	state = s
	_timer = _dur(s)
	if s == S.NUBLANDO:
		_decir(_plan)
	if antes == S.TORMENTA and s != S.TORMENTA:
		_hacer_charcos()
	if s == S.TORMENTA:
		_thunder_t = _rng.randf_range(4.0, 9.0)

## La isla decide qué viene tras el sol según cómo se siente.
func _siguiente() -> void:
	var enojo: float = Isla.get_emocion("enojo")
	var confianza: float = Isla.get_emocion("confianza")
	var miedo: float = Isla.get_emocion("miedo")
	var h: float = _hostil()
	var p_paz: float = clampf(confianza * 0.6 - h / 120.0, 0.05, 0.45)
	if _rng.randf() < p_paz:
		_cambiar(S.PAZ)
		return
	var p_tormenta: float = clampf(0.05 + enojo * 0.5 + h / 150.0, 0.03, 0.7)
	_plan = "tormenta" if _rng.randf() < p_tormenta else "lluvia"
	if _plan == "lluvia" and miedo > 0.3 and _rng.randf() < 0.3:
		_plan = "llovizna"
	_cambiar(S.NUBLANDO)

func _despues_de_nubes() -> void:
	match _plan:
		"tormenta":
			_cambiar(S.TORMENTA)
		"llovizna":
			_cambiar(S.LLOVIZNA)
		_:
			_cambiar(S.LLUVIA if _rng.randf() < 0.55 else S.LLOVIZNA)

func _decir(tema: String) -> void:
	if brain == null or _rng.randf() > 0.6:
		return
	var tt: String = "tormenta" if tema == "tormenta" else "lluvia"
	var frase: String = brain.voice.ambient(brain._voz(), [tt], true)
	if frase != "":
		brain._say(frase, "omen" if tt == "tormenta" else "whisper")

# ------------------------------------------------------------------ ciclo

func _objetivos() -> Dictionary:
	match state:
		S.NUBLANDO:
			return {"cloud": 0.8, "rain": 0.0, "wind": 0.35}
		S.LLOVIZNA:
			return {"cloud": 0.8, "rain": 0.3, "wind": 0.2}
		S.LLUVIA:
			return {"cloud": 0.95, "rain": 0.65, "wind": 0.3}
		S.TORMENTA:
			return {"cloud": 1.0, "rain": 1.0, "wind": 0.8}
		S.CLAREANDO:
			return {"cloud": 0.25, "rain": 0.0, "wind": 0.1}
	return {"cloud": 0.15, "rain": 0.0, "wind": 0.0}

func _process(delta: float) -> void:
	if _dn == null or not is_instance_valid(_dn):
		_dn = get_tree().get_first_node_in_group("daynight") as DayNight
	var t: Dictionary = _objetivos()
	if not enabled:
		state = S.SOL
		_hold = false
		t = _objetivos()
	elif not _hold:
		_timer -= delta
		if _timer <= 0.0:
			match state:
				S.SOL:
					_siguiente()
				S.PAZ:
					_cambiar(S.SOL)
				S.NUBLANDO:
					_despues_de_nubes()
				S.LLOVIZNA, S.LLUVIA, S.TORMENTA:
					_cambiar(S.CLAREANDO)
				S.CLAREANDO:
					_cambiar(S.SOL)
			t = _objetivos()
	cloud = move_toward(cloud, float(t["cloud"]), delta / 30.0)
	wind = move_toward(wind, float(t["wind"]), delta / 25.0)
	# la lluvia solo arranca cuando el cielo ya está bien cerrado: nunca de golpe
	var rain_t: float = float(t["rain"]) if cloud > 0.6 else 0.0
	intensity = move_toward(intensity, rain_t, delta / 14.0)
	raining = intensity > 0.02
	var in_shelter: bool = player != null and features != null and features.is_inside_cave(player.global_position)
	_shelter = move_toward(_shelter, 1.0 if in_shelter else 0.0, delta * 2.0)
	exposed = intensity * (1.0 - _shelter)
	wetness = move_toward(wetness, 1.0 if exposed > 0.2 else 0.0, delta / (40.0 if exposed > 0.2 else 120.0))

	# cielo, niebla y viento (reusa DayNight / LookDirector / Wind)
	if _dn != null:
		_dn.cloud = cloud
		_dn.fog_clima = cloud * 0.004 + intensity * 0.003 + intensity * intensity * 0.009   # tormenta: poca visibilidad lejana
	Wind.set_clima(wind)

	# lluvia visible
	var cam: Camera3D = get_viewport().get_camera_3d()
	_drops.emitting = exposed > 0.05
	_drop_mat.albedo_color.a = lerpf(0.15, 0.55, clampf(exposed, 0.0, 1.0))
	_drops.direction = Vector3(0.12 + wind * 0.35, -1.0, 0.05)
	# llovizna: gotas chicas y lentas; tormenta: grandes y muy rapidas
	var ik: float = clampf(intensity, 0.0, 1.0)
	_drops.scale_amount_min = lerpf(0.45, 1.1, ik)
	_drops.scale_amount_max = lerpf(0.55, 1.3, ik)
	_drops.initial_velocity_min = lerpf(7.0, 24.0, ik)
	_drops.initial_velocity_max = lerpf(9.0, 30.0, ik)
	_drops.gravity = Vector3(0.0, lerpf(-10.0, -36.0, ik), 0.0)
	if cam != null:
		_drops.global_position = cam.global_position + Vector3(0.0, 13.0, 0.0)

	# lluvia tranquila: la isla se estabiliza y los árboles talados rebrotan
	if (state == S.LLOVIZNA or state == S.LLUVIA) and intensity > 0.2:
		if brain != null:
			brain.offense = maxf(brain.offense - delta * 0.03, 0.0)
		_regrow_t -= delta
		if _regrow_t <= 0.0:
			_regrow_t = 30.0
			regrow_one()

	# tormenta: rayos y truenos
	if state == S.TORMENTA and intensity > 0.5:
		_thunder_t -= delta
		if _thunder_t <= 0.0:
			_thunder_t = _rng.randf_range(9.0, 22.0)
			_rayo()

func regrow_one() -> void:
	if terrain != null and not terrain.felled.is_empty():
		terrain.regrow_tree(_rng.randi() % terrain.felled.size())

func _rayo() -> void:
	var tw: Tween = create_tween()
	_flash.color.a = 0.0
	tw.tween_property(_flash, "color:a", 0.45, 0.04)
	tw.tween_property(_flash, "color:a", 0.08, 0.08)
	tw.tween_property(_flash, "color:a", 0.3, 0.04)
	tw.tween_property(_flash, "color:a", 0.0, 0.4)
	await get_tree().create_timer(_rng.randf_range(0.4, 1.8)).timeout
	if player != null and is_instance_valid(player):
		var noche: float = _dn.night_amount if _dn != null else 0.0
		AudioManager.play(get_tree(), "boom", player.global_position + Vector3(_rng.randf_range(-30, 30), 6, _rng.randf_range(-30, 30)), lerpf(3.0, -2.0, noche))

# ------------------------------------------------------------------ charcos

## Tras una tormenta fuerte: charcos poco profundos en lugares al azar; se secan solos.
func _hacer_charcos() -> void:
	if terrain == null or player == null:
		return
	var n: int = _rng.randi_range(6, 10)
	var tries: int = 0
	var made: int = 0
	while made < n and tries < 80:
		tries += 1
		var ang: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(6.0, 40.0)
		var x: float = player.global_position.x + cos(ang) * d
		var z: float = player.global_position.z + sin(ang) * d
		var h: float = terrain.height_at(x, z)
		if h < 1.5 or h > 7.0:
			continue
		if features != null and features.is_inside_cave(Vector3(x, h, z)):
			continue
		var hx: float = terrain.height_at(x + 1.2, z)
		var hz: float = terrain.height_at(x, z + 1.2)
		if absf(hx - h) > 0.25 or absf(hz - h) > 0.25:
			continue            # solo en terreno llano
		_puddle(Vector3(x, h + 0.03, z))
		made += 1

func _puddle(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	var r: float = _rng.randf_range(0.5, 1.4)
	cy.top_radius = r
	cy.bottom_radius = r
	cy.height = 0.02
	cy.radial_segments = 14
	cy.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.17, 0.22, 0.0)
	m.roughness = 0.05
	m.metallic = 0.2
	m.metallic_specular = 1.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cy.material = m
	mi.mesh = cy
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1.0, 1.0, _rng.randf_range(0.7, 1.3))
	mi.rotation.y = _rng.randf() * TAU
	get_parent().add_child(mi)
	mi.global_position = pos
	var tw: Tween = mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.6, 8.0)
	tw.tween_interval(_rng.randf_range(120.0, 240.0))
	tw.tween_property(m, "albedo_color:a", 0.0, 40.0)
	tw.tween_callback(mi.queue_free)

func puddles_now() -> void:
	_hacer_charcos()
