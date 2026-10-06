class_name DayNight
extends Node

## Ciclo día/noche REAL: usa la hora local del equipo. Si lo jugás de noche, es de noche.
## Amanece ~6:00, mediodía 12:00, atardece ~18:00. F9 avanza 1 hora (solo para probar).

const SKY_SHADER: Shader = preload("res://shaders/sky_daynight.gdshader")

const DAY_TOP := Color(0.2, 0.45, 0.82)
const DAY_HORIZON := Color(0.72, 0.84, 0.93)
const DUSK_TOP := Color(0.28, 0.3, 0.6)
const DUSK_HORIZON := Color(1.0, 0.52, 0.28)
const NIGHT_TOP := Color(0.012, 0.025, 0.09)
const NIGHT_HORIZON := Color(0.05, 0.08, 0.17)

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
var fog_boost: float = 0.0   ## niebla extra que levanta la isla (0 = normal)
var _sun_shadow_on: bool = true
var _moon_shadow_on: bool = false
var _fx: AmbientFx

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
	_moon.directional_shadow_max_distance = 120.0
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

func _current_hour() -> float:
	var t: Dictionary = Time.get_datetime_dict_from_system() # hora local
	var h: float = float(t["hour"]) + float(t["minute"]) / 60.0 + float(t["second"]) / 3600.0
	return fposmod(h + _offset_hours, 24.0)

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
	var unix: float = Time.get_unix_time_from_system() + _offset_hours * 3600.0 # UTC
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
	moon_phase = (1.0 - cos(lam_m - lam_s)) * 0.5 # 0 luna nueva, 1 luna llena
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

	# Sol
	sun.global_transform = Transform3D(_look_basis(-sun_pos), sun_pos * 80.0)
	var warm: float = smoothstep(0.0, 0.5, e)
	sun.light_color = Color(1.0, 0.5, 0.22).lerp(Color(1.0, 0.95, 0.86), warm)
	sun.light_energy = 1.25 * smoothstep(-0.03, 0.22, e)
	sun.visible = sun.light_energy > 0.01
	var want_sun_shadow: bool = e > 0.02
	if want_sun_shadow != _sun_shadow_on:
		_sun_shadow_on = want_sun_shadow
		sun.shadow_enabled = want_sun_shadow

	# Luna (opuesta al sol)
	var moon_pos: Vector3 = moon_dir
	var moon_up: float = clampf(moon_pos.y, 0.0, 1.0)
	_moon.global_transform = Transform3D(_look_basis(-moon_pos), moon_pos * 80.0)
	_moon.light_energy = 1.1 * night * (0.15 + 0.85 * moon_phase * moon_phase) * smoothstep(0.0, 0.25, moon_up)
	_moon.light_specular = 1.6   # reflejo plateado sobre el agua
	# luz de luna real: blanco frío, poco saturado
	_moon.light_color = Color(0.78, 0.85, 1.0).lerp(Color(0.92, 0.95, 1.0), moon_phase * 0.7)
	var moon_visible: float = night * smoothstep(0.0, 0.2, moon_pos.y)
	if _water_mat == null:
		var w: MeshInstance3D = get_tree().get_first_node_in_group("water_surface") as MeshInstance3D
		if w != null:
			_water_mat = w.mesh.material as ShaderMaterial
	if _water_mat != null:
		_water_mat.set_shader_parameter("moon_dir", moon_pos)
		_water_mat.set_shader_parameter("moon_glow", moon_visible * (0.2 + 0.8 * moon_phase))
	# De noche el ojo ve casi sin color: se desatura
	_env.adjustment_saturation = lerpf(1.12, 0.72, night)
	_moon.visible = _moon.light_energy > 0.01
	var want_moon_shadow: bool = _moon.visible and moon_up > 0.12
	if want_moon_shadow != _moon_shadow_on:
		_moon_shadow_on = want_moon_shadow
		_moon.shadow_enabled = want_moon_shadow

	_starlight.light_energy = 0.3 * night * night
	if _lighthouse == null or not is_instance_valid(_lighthouse):
		_lighthouse = get_tree().get_first_node_in_group("lighthouse") as Lighthouse
	if _lighthouse != null:
		_lighthouse.set_night(night)

	# Cielo
	var top: Color = NIGHT_TOP.lerp(DAY_TOP, day).lerp(DUSK_TOP, dusk * 0.5)
	var horizon: Color = NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK_HORIZON, dusk * 0.85)
	_sky_mat.set_shader_parameter("top_color", top)
	_sky_mat.set_shader_parameter("horizon_color", horizon)
	_sky_mat.set_shader_parameter("ground_color", horizon.darkened(0.55))
	_sky_mat.set_shader_parameter("sun_dir", sun_pos)
	_sky_mat.set_shader_parameter("moon_dir", moon_pos)
	_sky_mat.set_shader_parameter("sun_amount", smoothstep(-0.1, 0.05, e))
	_sky_mat.set_shader_parameter("moon_amount", smoothstep(-0.05, 0.1, moon_pos.y))
	_sky_mat.set_shader_parameter("star_amount", night * night)
	_sky_mat.set_shader_parameter("moon_phase", moon_phase)
	_sky_mat.set_shader_parameter("star_x", star_x)
	_sky_mat.set_shader_parameter("star_y", star_y)
	_sky_mat.set_shader_parameter("star_z", star_z)

	# Ambiente, niebla y exposición
	_env.ambient_light_energy = lerpf(0.7, 1.7, night) + dusk * 0.6
	_env.fog_light_color = horizon
	_env.fog_density = lerpf(0.0012, 0.0024, night) + dusk * 0.0006 + fog_boost
	_env.tonemap_exposure = lerpf(0.95, 1.1, night)

	# Reloj
	var t: Dictionary = Time.get_datetime_dict_from_system()
	var hh: int = int(hour)
	var mm: int = int((hour - float(hh)) * 60.0)
	var ss: int = int(t["second"])
	_clock.text = "%02d:%02d:%02d   %02d/%02d/%d\nSol %d°  Luna %d° (%d%% iluminada)" % [
		hh, mm, ss, int(t["day"]), int(t["month"]), int(t["year"]),
		roundi(rad_to_deg(asin(sun_dir.y))), roundi(rad_to_deg(asin(moon_dir.y))), roundi(moon_phase * 100.0)]

	if refresh_slow:
		_apply_slow(day, night)

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
