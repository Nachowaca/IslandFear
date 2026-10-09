class_name DayNight
extends Node

## Ciclo día/noche REAL: usa la hora local del equipo. Si lo jugás de noche, es de noche.
## Amanece ~6:00, mediodía 12:00, atardece ~18:00. F9 avanza 1 hora (solo para probar).

const SKY_SHADER: Shader = preload("res://shaders/sky_daynight.gdshader")

const DAY_TOP := Color(0.2, 0.45, 0.82)
const DAY_HORIZON := Color(0.72, 0.84, 0.93)
const DUSK_TOP := Color(0.28, 0.3, 0.6)
const DUSK_HORIZON := Color(1.0, 0.52, 0.28)
const NIGHT_TOP := Color(0.015, 0.1, 0.17)
const NIGHT_HORIZON := Color(0.05, 0.25, 0.3)

var sun: DirectionalLight3D
var env_node: WorldEnvironment

## Ubicación del jugador en el planeta (define dónde sale el sol y qué estrellas se ven).
## Por defecto: Buenos Aires. Cambialos por tu ciudad.
@export var latitude: float = -34.9011    # Montevideo, Uruguay (negativo = hemisferio sur)
@export var longitude: float = -56.1645    # negativo = oeste
@export var debug_moon_phase: float = -1.0 # -1 = fase real; 0..1 fuerza la fase (solo para probar)

var hour: float = 12.0
var night_amount: float = 0.0   # 0 = día pleno, 1 = noche cerrada (la usa la mente de la isla)
var sun_dir: Vector3 = Vector3.UP
var moon_dir: Vector3 = Vector3.DOWN
var moon_phase: float = 1.0
var star_x: Vector3 = Vector3.RIGHT
var star_y: Vector3 = Vector3.BACK
var star_z: Vector3 = Vector3.UP
var _offset_hours: float = 0.0
var _env: Environment
var _sky_mat: ShaderMaterial
var _moon: DirectionalLight3D
var _starlight: DirectionalLight3D
var _clock: Label
var _f9_was_down: bool = false
var _f10_was_down: bool = false
var _lighthouse: Lighthouse
var _water_mat: ShaderMaterial
var _vis_timer: float = 0.0
var fog_local: float = 0.0   ## niebla extra según el bioma (la pone BiomeAtmosphere)
var fog_clima: float = 0.0    ## niebla extra del clima (la pone Weather; aparte de fog_boost para no pisar la de la isla)
var cloud: float = 0.0       ## 0 = cielo limpio, 1 = cubierto (lo pone Weather): baja el sol, apaga el cielo
var fog_boost: float = 0.0   ## niebla extra que levanta la isla (0 = normal)
var _sun_shadow_on: bool = true
var _moon_shadow_on: bool = false
var _fx: AmbientFx
var look: LookDirector       ## dueño del look: presets, niebla, glow, haces (ver scripts/look/)

func setup(p_sun: DirectionalLight3D, p_env: WorldEnvironment) -> void:
	sun = p_sun
	env_node = p_env

func _ready() -> void:
	_env = env_node.environment
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	_env.sky = sky
	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Color(0.55, 0.66, 1.0)
	_moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_moon.directional_shadow_max_distance = 70.0
	_moon.shadow_normal_bias = 1.5
	sun.get_parent().add_child(_moon)

	# Luz tenue de estrellas / cielo nocturno: evita la oscuridad total cuando la luna no está
	_starlight = DirectionalLight3D.new()
	_starlight.name = "Starlight"
	_starlight.light_color = Color(0.58, 0.65, 0.88)
	_starlight.shadow_enabled = false
	sun.get_parent().add_child(_starlight)
	_starlight.global_transform = Transform3D(_look_basis(Vector3(-0.3, -1.0, -0.2)), Vector3(0, 80, 0))

	var layer := CanvasLayer.new()
	add_child(layer)
	_clock = Label.new()
	_clock.anchor_top = 1.0
	_clock.anchor_bottom = 1.0
	_clock.offset_left = 20.0
	_clock.offset_top = -70.0
	_clock.add_theme_font_size_override("font_size", 18)
	_clock.add_theme_color_override("font_outline_color", Color.BLACK)
	_clock.add_theme_constant_override("outline_size", 5)
	layer.add_child(_clock)
	look = LookDirector.new()
	look.name = "Look"
	look.daynight = self
	look.env = _env
	look.env_node = env_node
	look.sky_mat = _sky_mat
	look.sun = sun
	add_child(look)
	_update(true)

func _process(delta: float) -> void:
	var f9: bool = Input.is_physical_key_pressed(KEY_F9)
	if f9 and not _f9_was_down:
		_offset_hours += 1.0
	_f9_was_down = f9
	# F10: mirar hacia la luna (o hacia el sol si la luna no está sobre el horizonte)
	var f10: bool = Input.is_physical_key_pressed(KEY_F10)
	if f10 and not _f10_was_down:
		var p: Castaway = get_tree().get_first_node_in_group("player") as Castaway
		if p != null:
			p.look_toward(moon_dir if moon_dir.y > 0.0 else sun_dir)
	_f10_was_down = f10
	_vis_timer -= delta
	_update(_vis_timer <= 0.0)
	if _vis_timer <= 0.0:
		_vis_timer = 1.0

func moon_light() -> DirectionalLight3D:
	return _moon

func water_mat() -> ShaderMaterial:
	return _water_mat

## Reloj de la isla: 2 h reales = 24 h de juego (1 h real de día + 1 h real de noche). Fecha fija (equinoccio): días y noches parejos.
const TIME_SCALE: float = 12.0
var _equinox_unix: float = Time.get_unix_time_from_datetime_string("2026-03-20T00:00:00")

## Horas UTC del juego (0..24).
func _game_utc_hours() -> float:
	return fposmod(Time.get_unix_time_from_system() * TIME_SCALE / 3600.0 + _offset_hours, 24.0)

func _current_hour() -> float:
	return fposmod(_game_utc_hours() + longitude / 15.0, 24.0)

## Convierte ascensión recta / declinación a un vector de dirección en el mundo.
## Convención del mundo: +X = Este, -Z = Norte, +Y = arriba.
func _equatorial_to_dir(ra: float, dec: float, gmst_deg: float) -> Vector3:
	var lat: float = deg_to_rad(latitude)
	var ha: float = deg_to_rad(gmst_deg + longitude) - ra
	var sin_alt: float = sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha)
	var alt: float = asin(clampf(sin_alt, -1.0, 1.0))
	var az: float = atan2(sin(ha), cos(ha) * sin(lat) - tan(dec) * cos(lat)) + PI # desde el Norte, hacia el Este
	return Vector3(cos(alt) * sin(az), sin_alt, -cos(alt) * cos(az))

## Posiciones astronómicas reales (algoritmos de baja precisión, error < ~1°).
func _compute_astro() -> void:
	var unix: float = _equinox_unix + _game_utc_hours() * 3600.0 # UTC de juego
	var unix_real: float = Time.get_unix_time_from_system()
	var n: float = unix / 86400.0 + 2440587.5 - 2451545.0       # días desde J2000
	var eps: float = deg_to_rad(23.439 - 0.0000004 * n)
	var gmst: float = fposmod((18.697374558 + 24.06570982441908 * n) * 15.0, 360.0)

	# Sol
	var l_sun: float = fposmod(280.460 + 0.9856474 * n, 360.0)
	var g: float = deg_to_rad(fposmod(357.528 + 0.9856003 * n, 360.0))
	var lam_s: float = deg_to_rad(l_sun + 1.915 * sin(g) + 0.020 * sin(2.0 * g))
	var ra_s: float = atan2(cos(eps) * sin(lam_s), cos(lam_s))
	var dec_s: float = asin(sin(eps) * sin(lam_s))
	sun_dir = _equatorial_to_dir(ra_s, dec_s, gmst)

	# Luna
	var l_moon: float = 218.316 + 13.176396 * n
	var m_moon: float = deg_to_rad(fposmod(134.963 + 13.064993 * n, 360.0))
	var f_moon: float = deg_to_rad(fposmod(93.272 + 13.229350 * n, 360.0))
	var lam_m: float = deg_to_rad(fposmod(l_moon + 6.289 * sin(m_moon), 360.0))
	var beta: float = deg_to_rad(5.128 * sin(f_moon))
	var ra_m: float = atan2(sin(lam_m) * cos(eps) - tan(beta) * sin(eps), cos(lam_m))
	var dec_m: float = asin(sin(beta) * cos(eps) + cos(beta) * sin(eps) * sin(lam_m))
	moon_dir = _equatorial_to_dir(ra_m, dec_m, gmst)
	var sinodico: float = fposmod(unix_real / 86400.0 + 2440587.5 - 2451550.1, 29.530588) / 29.530588
	moon_phase = (1.0 - cos(TAU * sinodico)) * 0.5   # fase real (la fecha del juego está fija)
	# Luna de juego: arco propio. Sale por el este a las 19:00, culmina a las 01:00 y se pone a las 07:00 (siempre hay luna de noche)
	var mu: float = fposmod(hour - 19.0, 24.0) / 12.0
	var ma: float = mu * PI
	moon_dir = Vector3(cos(ma), sin(ma) * 0.8, 0.35).normalized()
	moon_phase = lerpf(0.55, 1.0, moon_phase)     # nunca tan fina que no se vea
	if debug_moon_phase >= 0.0:
		moon_phase = debug_moon_phase

	# Base ecuatorial (para rotar las estrellas con el cielo)
	star_x = _equatorial_to_dir(0.0, 0.0, gmst)
	star_z = _equatorial_to_dir(0.0, PI / 2.0, gmst)
	star_y = star_z.cross(star_x).normalized()

func _update(refresh_slow: bool) -> void:
	hour = _current_hour()
	_compute_astro()
	add_to_group("daynight")
	var sun_pos: Vector3 = sun_dir
	var e: float = sun_pos.y                       # elevación del sol (-1..1)
	var day: float = smoothstep(-0.16, 0.28, e)    # 0 noche, 1 día pleno
	var dusk: float = clampf(1.0 - absf(e + 0.04) / 0.32, 0.0, 1.0) # amanecer / atardecer
	var night: float = 1.0 - day
	night_amount = night
	var golden: float = (1.0 - smoothstep(0.06, 0.5, e)) * smoothstep(-0.06, 0.1, e)   # hora dorada: sol bajo

	# Sol
	sun.global_transform = Transform3D(_look_basis(-sun_pos), sun_pos * 80.0)
	var want_sun_shadow: bool = e > 0.02
	if want_sun_shadow != _sun_shadow_on:
		_sun_shadow_on = want_sun_shadow
		sun.shadow_enabled = want_sun_shadow

	# Luna (opuesta al sol)
	var moon_pos: Vector3 = moon_dir
	var moon_up: float = clampf(moon_pos.y, 0.0, 1.0)
	_moon.global_transform = Transform3D(_look_basis(-moon_pos), moon_pos * 80.0)
	_moon.light_energy = 1.5 * night * (0.55 + 0.45 * moon_phase * moon_phase) * smoothstep(0.0, 0.25, moon_up)
	_moon.light_specular = 0.5   # reflejo plateado sobre el agua
	# luz de luna real: blanco frío, poco saturado
	var mt: float = float(Time.get_ticks_msec()) * 0.001
	var matiz: float = 0.5 + 0.5 * sin(mt * 0.05) * 0.6 + 0.2 * sin(mt * 0.13 + 1.7)   # el color de la luna deriva despacio
	_moon.light_color = Color(0.3, 0.68, 0.85).lerp(Color(0.5, 0.82, 0.95), moon_phase * 0.7).lerp(Color(0.62, 0.58, 0.95), clampf(matiz, 0.0, 1.0) * 0.45)
	var moon_visible: float = night * smoothstep(0.0, 0.2, moon_pos.y)
	if _water_mat == null:
		var w: MeshInstance3D = get_tree().get_first_node_in_group("water_surface") as MeshInstance3D
		if w != null:
			_water_mat = w.mesh.material as ShaderMaterial
	if _water_mat != null:
		_water_mat.set_shader_parameter("moon_dir", moon_pos)
		_water_mat.set_shader_parameter("moon_glow", moon_visible * (0.2 + 0.8 * moon_phase))
		_water_mat.set_shader_parameter("moon_tint", Color(0.85, 0.9, 1.0).lerp(Color(1.0, 0.86, 0.6), clampf(matiz, 0.0, 1.0)))   # reflejo cálido sobre el agua teal
		_water_mat.set_shader_parameter("deep_color", Color(0.0, 0.36, 0.48).lerp(Color(0.01, 0.17, 0.28), night))
		_water_mat.set_shader_parameter("shallow_color", Color(0.1, 0.8, 0.72).lerp(Color(0.08, 0.42, 0.46), night))
	# De noche el ojo ve casi sin color: se desatura
	_env.adjustment_enabled = true
	if _env.adjustment_color_correction == null:
		_env.adjustment_color_correction = _make_grade_lut()
	_moon.visible = _moon.light_energy > 0.01
	var want_moon_shadow: bool = _moon.visible and moon_up > 0.12
	if want_moon_shadow != _moon_shadow_on:
		_moon_shadow_on = want_moon_shadow
		_moon.shadow_enabled = want_moon_shadow

	_starlight.light_energy = 0.1 * night * night
	if _lighthouse == null or not is_instance_valid(_lighthouse):
		_lighthouse = get_tree().get_first_node_in_group("lighthouse") as Lighthouse
	if _lighthouse != null:
		_lighthouse.set_night(night)

	# Cielo, sol, ambiente, niebla y glow: los decide el LookDirector (presets por hora)
	look.aplicar(day, dusk, golden, e, hour < 12.0)
	_sky_mat.set_shader_parameter("sun_dir", sun_pos)
	_sky_mat.set_shader_parameter("moon_dir", moon_pos)
	_sky_mat.set_shader_parameter("sun_amount", smoothstep(-0.1, 0.05, e) * (1.0 - cloud * 0.92))
	_sky_mat.set_shader_parameter("moon_amount", smoothstep(-0.05, 0.1, moon_pos.y) * (1.0 - cloud * 0.85))
	_sky_mat.set_shader_parameter("star_amount", night * night * (1.0 - cloud))
	_sky_mat.set_shader_parameter("moon_phase", moon_phase)
	_sky_mat.set_shader_parameter("star_x", star_x)
	_sky_mat.set_shader_parameter("star_y", star_y)
	_sky_mat.set_shader_parameter("star_z", star_z)

	# Reloj
	var hh: int = int(hour)
	var mm: int = int((hour - float(hh)) * 60.0)
	_clock.text = "%02d:%02d  (hora de la isla)\nSol %d°  Luna %d° (%d%% iluminada)" % [
		hh, mm,
		roundi(rad_to_deg(asin(sun_dir.y))), roundi(rad_to_deg(asin(moon_dir.y))), roundi(moon_phase * 100.0)]

	if refresh_slow:
		_apply_slow(day, night)

## Gradación de color de autor: sombras teal frías, medios neutros, luces ámbar cálidas.
func _make_grade_lut() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	g.colors = PackedColorArray([Color(0.0, 0.04, 0.07), Color(0.31, 0.37, 0.4), Color(0.74, 0.7, 0.63), Color(1.0, 0.94, 0.82)])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t

func _look_basis(dir: Vector3) -> Basis:
	var up: Vector3 = Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(dir, up)

func _apply_slow(day: float, night: float) -> void:
	# Gaviotas y mariposas solo de día
	for n: Node in get_tree().get_nodes_in_group("day_only"):
		if n is Node3D:
			(n as Node3D).visible = day > 0.3
	# Polen de día -> luciérnagas de noche
	if _fx == null or not is_instance_valid(_fx):
		_fx = get_tree().get_first_node_in_group("ambient_fx") as AmbientFx
	if _fx != null:
		_fx.set_night(night)
