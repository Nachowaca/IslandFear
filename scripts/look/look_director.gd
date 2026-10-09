class_name LookDirector
extends Node

## Dueño del look de autor (luz, color, niebla). Lo crea DayNight y le pasa cada frame cómo está el sol.
## - Mezcla 4 AmbientePreset (noche, amanecer, día, atardecer) y los aplica: cielo, sol, ambiente, niebla
##   (UNA sola: profundidad + altura; BiomeAtmosphere y la isla solo suman con fog_local / fog_boost), glow, exposición.
## - Extras baratos: sombras con color (ambiente tintado), sombras de contacto, haces y bruma en capas,
##   agua que refleja el cielo, DOF opcional.
## - Interruptor maestro (F2), overlay de debug (F3), calidad Baja/Media/Alta (F4).
## Mobile: sin SSAO/SSR/SDFGI/niebla volumétrica; todo con mallas, shaders simples y vertex colors.

enum Calidad { BAJA, MEDIA, ALTA }
const NOMBRES_CALIDAD: Array[String] = ["Baja", "Media", "Alta"]
const CFG_PATH: String = "user://look.cfg"

## Apagado = luz simple: sin haces, bruma, sombras de contacto, glow, DOF ni tinte de sombras. Reversible en caliente.
var look_cinematografico_activo: bool = true
var calidad: int = Calidad.MEDIA
var dof_activo: bool = false          ## ver medición: solo con calidad Alta

var daynight: DayNight
var env: Environment
var env_node: WorldEnvironment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var terrain: IslandTerrain
var player: Node3D

var actual: AmbientePreset = AmbientePreset.new()
var _base: AmbientePreset = AmbientePreset.new()
var _noche: AmbientePreset = AmbientePreset.noche()
var _amanecer: AmbientePreset = AmbientePreset.amanecer()
var _dia: AmbientePreset = AmbientePreset.dia()
var _atardecer: AmbientePreset = AmbientePreset.atardecer()
var _modificador: Dictionary = {}
var _haces: LookHaces
var noche: LookNoche
var eco: EcoMap
var _contacto: LookContacto
var _destello: LookDestello
var _ins: Node3D
var _part: Node3D
var _flut: Node3D
var _cam_attr: CameraAttributesPractical
var _overlay_layer: CanvasLayer
var _overlay: Label
var _overlay_t: float = 0.0
var _keys: Dictionary = {}
var _w_noche: float = 0.0
var _w_dia: float = 0.0
var _w_tw: float = 0.0
var _extras_n: Dictionary = {"luces": 0, "particulas": 0}
var _extras_t: float = 0.0
var _gpu_ms: float = 0.0
var _cpu_ms: float = 0.0
var _medicion: String = ""

## Punto de entrada para que la isla viva altere luz y tono según su estado emocional
## (cielo frío y cerrado si está enojada, cálido si confía). TODAVÍA NO HACE NADA: solo guarda el diccionario.
## Claves previstas: "tinte" (Color), "niebla" (float), "energia_sol" (float), "bloom" (float).
func set_modificador(d: Dictionary) -> void:
	_modificador = d

func _ready() -> void:
	_cargar_cfg()
	_cam_attr = CameraAttributesPractical.new()
	_cam_attr.dof_blur_far_distance = 70.0
	_cam_attr.dof_blur_far_transition = 140.0
	_cam_attr.dof_blur_amount = 0.05
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 30
	add_child(_overlay_layer)
	_overlay = Label.new()
	_overlay.position = Vector2(20, 90)
	_overlay.add_theme_font_size_override("font_size", 17)
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_theme_constant_override("outline_size", 5)
	_overlay.visible = false
	_overlay_layer.add_child(_overlay)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

## Crea las mallas del look que dependen del mundo (una sola vez). Lo llama main cuando la isla ya existe.
func preparar_mundo(p_terrain: IslandTerrain, p_player: Node3D) -> void:
	terrain = p_terrain
	player = p_player
	_haces = LookHaces.new()
	_haces.name = "LookHaces"
	_haces.terrain = terrain
	_haces.player = player
	add_child(_haces)
	_contacto = LookContacto.new()
	_contacto.player = player
	_contacto.name = "LookContacto"
	_contacto.terrain = terrain
	add_child(_contacto)
	noche = LookNoche.new()
	noche.name = "LookNoche"
	noche.terrain = terrain
	noche.eco = eco
	noche.player = player
	add_child(noche)
	_ins = load("res://scripts/air/air_insects.gd").new() as Node3D
	_ins.set("terrain", terrain)
	_ins.set("player", player)
	add_child(_ins)
	_part = load("res://scripts/air/air_particles.gd").new() as Node3D
	_part.set("terrain", terrain)
	_part.set("player", player)
	add_child(_part)
	_flut = load("res://scripts/air/air_flutter.gd").new() as Node3D
	_flut.set("terrain", terrain)
	_flut.set("player", player)
	add_child(_flut)
	_destello = LookDestello.new()
	_destello.name = "LookDestello"
	_destello.player = player
	add_child(_destello)
	_aplicar_calidad()

# ------------------------------------------------------------------ aplicar cada frame

## day: 0 noche..1 día; dusk: cercanía al horizonte; golden: sol bajo; e: elevación del sol; mañana: antes de mediodía.
func aplicar(day: float, dusk: float, golden: float, e: float, manana: bool) -> void:
	_w_noche = 1.0 - day
	_w_dia = day
	_w_tw = clampf(maxf(dusk, golden * 0.75), 0.0, 1.0)
	AmbientePreset.mezclar(_noche, _dia, day, _base)
	AmbientePreset.mezclar(_base, _amanecer if manana else _atardecer, _w_tw, actual)
	var p: AmbientePreset = actual
	var on: bool = look_cinematografico_activo

	# cielo
	var nub: float = daynight.cloud
	# --- CLIMA: filtro temporal sobre el look (no toca los presets). Todo vale 1.0 / 0.0 sin nubes ni lluvia. ---
	var m_sol: float = lerpf(1.0, 0.18, nub) * float(_modificador.get("energia_sol", 1.0))
	var m_amb: float = lerpf(1.0, 0.88, nub)
	var m_sat: float = lerpf(1.0, 0.92, nub)
	var g_cielo: float = nub * 0.5       # cuanto se grisea el cielo
	var g_niebla: float = nub * 0.3      # cuanto se grisea la niebla
	var tinte: Color = _modificador.get("tinte", Color.WHITE) as Color
	# humedad del dia (0 seco .. 1 muy humedo): decide suavidad del sol, rayos y niebla juntos
	var dd0: Dictionary = Time.get_date_dict_from_system()
	var hd0: float = fposmod(sin(float(int(dd0.year) * 400 + int(dd0.month) * 31 + int(dd0.day)) * 12.9898) * 43758.5453, 1.0)
	var hum_n: float = hd0
	var gris_t: Color = Color(0.36, 0.4, 0.45).lerp(p.color_cielo_alto, 0.25 * (1.0 - _w_dia) + 0.1) * lerpf(1.0, 0.35, _w_noche)
	var gris_h: Color = Color(0.55, 0.58, 0.6) * lerpf(1.0, 0.3, _w_noche)
	var cielo_alto: Color = p.color_cielo_alto.lerp(gris_t, g_cielo)
	var cielo_hor: Color = p.color_cielo_horizonte.lerp(gris_h, g_cielo)
	sky_mat.set_shader_parameter("top_color", cielo_alto)
	sky_mat.set_shader_parameter("cloud_cover", clampf(0.15 + nub * 0.75, 0.0, 1.0))
	sky_mat.set_shader_parameter("horizon_color", cielo_hor)
	sky_mat.set_shader_parameter("ground_color", cielo_hor.darkened(0.55))

	# sol
	sun.light_color = p.color_sol
	sun.light_energy = p.energia_sol * smoothstep(-0.03, 0.22, e) * m_sol * lerpf(1.08, 0.95, hum_n * _w_dia + (1.0 - _w_dia) * 0.5)
	sun.visible = sun.light_energy > 0.01
	sun.shadow_opacity = 1.0
	sun.shadow_blur = 0.55 if on else 1.0     # sombras mas definidas (la del personaje)

	# visibilidad nocturna local: luna tapada, bosque cerrado o cueva = más oscuro; playa y claros = más claro
	var vis: float = 1.0
	if noche != null:
		noche.set_luna(daynight.moon_dir)
		vis = noche.visibilidad
	daynight.moon_light().light_energy *= lerpf(1.0, vis, _w_noche)
	daynight.moon_light().visible = daynight.moon_light().light_energy > 0.01

	# ambiente: el cielo ilumina; el tinte da color a las sombras
	var luna_alta: float = smoothstep(0.0, 0.45, daynight.moon_dir.y) * (0.4 + 0.6 * daynight.moon_phase)   # luna alta y llena = más luz de cielo
	env.ambient_light_energy = p.energia_ambiente * lerpf(1.0, lerpf(0.2, 1.0, vis) * lerpf(0.6, 1.0, luna_alta), _w_noche)
	env.ambient_light_energy *= m_amb
	env.ambient_light_color = p.color_ambiente * tinte
	env.ambient_light_sky_contribution = p.contribucion_cielo if on else 1.0

	# niebla: profundidad (siempre) + altura (solo look activo)
	env.fog_light_color = p.color_niebla.lerp(Color(0.5, 0.55, 0.58) * lerpf(1.0, 0.3, _w_noche), g_niebla)
	# humedad del día: hay días secos y días muy húmedos (cambia la niebla baja y la de profundidad)
	var dd: Dictionary = Time.get_date_dict_from_system()
	var hd: float = fposmod(sin(float(int(dd.year) * 400 + int(dd.month) * 31 + int(dd.day)) * 12.9898) * 43758.5453, 1.0)
	var hum_dia: float = lerpf(0.35, 1.8, hd)
	env.fog_density = (p.densidad_niebla + daynight.fog_local) * lerpf(0.8, 1.25, hd) + (daynight.fog_boost + daynight.fog_clima)
	if on and calidad >= Calidad.MEDIA:
		env.fog_height = 2.4
		env.fog_height_density = p.niebla_altura * hum_dia + (daynight.fog_boost + daynight.fog_clima) * 6.0
	else:
		env.fog_height_density = 0.0

	# postproceso
	env.tonemap_exposure = p.exposicion
	env.adjustment_saturation = p.saturacion * m_sat * (1.0 if on else 0.88)
	env.adjustment_contrast = p.contraste
	env.glow_enabled = on and calidad >= Calidad.MEDIA
	env.glow_intensity = p.intensidad_bloom

	# agua: refleja el cielo actual y el brillo del sol
	var wm: ShaderMaterial = daynight.water_mat()
	if wm != null:
		wm.set_shader_parameter("sky_color", p.color_cielo_horizonte)
		wm.set_shader_parameter("zenith_color", p.color_cielo_alto)
		wm.set_shader_parameter("sun_dir", daynight.sun_dir)
		wm.set_shader_parameter("sun_glow", smoothstep(0.0, 0.25, e) * (1.0 - smoothstep(0.55, 0.9, e) * 0.6))
		wm.set_shader_parameter("sun_tint", Vector3(p.color_sol.r, p.color_sol.g, p.color_sol.b))
		wm.set_shader_parameter("sky_reflect", 0.6 if on else 0.25)
		wm.set_shader_parameter("noctiluca", _w_noche * daynight.night_amount if on else 0.0)
		if player != null:
			wm.set_shader_parameter("player_pos", player.global_position)

	# extras del look
	if _haces != null:
		_haces.activo = on
		var luz_dir: Vector3 = daynight.sun_dir
		var luz_col: Color = p.color_sol
		var fuerza: float = p.intensidad_haces * smoothstep(0.02, 0.14, e) * lerpf(0.45, 1.0, hum_n)
		if e <= 0.02 and daynight.moon_dir.y > 0.06:
			luz_dir = daynight.moon_dir
			luz_col = Color(0.55, 0.72, 1.0)
			fuerza = 0.0     # la luna no hace haces duros: su luz es suave y viene de la luz direccional y el ambiente
		_haces.set_luz(luz_dir, luz_col, fuerza)
		_haces.set_bruma(p.color_niebla.lerp(Color.WHITE, 0.15), clampf(p.niebla_altura / 0.04 + (daynight.fog_boost + daynight.fog_clima) * 40.0, 0.0, 1.0))
	if _ins != null:
		_ins.call("set_noche", _w_noche)
		_flut.call("set_noche", _w_noche)
		_part.call("set_hora", daynight.hour, _w_noche)
	if _destello != null:
		_destello.set_sol(daynight.sun_dir, p.color_sol, smoothstep(0.05, 0.3, e) * lerpf(1.0, 0.0, clampf(nub * 1.6, 0.0, 1.0)), on and calidad >= Calidad.MEDIA)
	if _contacto != null:
		_contacto.visible = on and calidad >= Calidad.MEDIA
		_contacto.set_fuerza(lerpf(0.5, 0.3, _w_noche))

# ------------------------------------------------------------------ calidad, DOF, entrada

func _aplicar_calidad() -> void:
	match calidad:
		Calidad.BAJA:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 80.0
			if _haces != null:
				_haces.set_cantidades(0, 0)
		Calidad.MEDIA:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 140.0
			if _haces != null:
				_haces.set_cantidades(6, 0)
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 180.0
			if _haces != null:
				_haces.set_cantidades(12, 0)
	_aplicar_dof()

func _aplicar_dof() -> void:
	var quiere: bool = look_cinematografico_activo and calidad == Calidad.ALTA and dof_activo
	_cam_attr.dof_blur_far_enabled = quiere
	if env_node != null:
		env_node.camera_attributes = _cam_attr if quiere else null

func _edge(k: Key) -> bool:
	var down: bool = Input.is_physical_key_pressed(k)
	var was: bool = bool(_keys.get(k, false))
	_keys[k] = down
	return down and not was

func _process(delta: float) -> void:
	if _edge(KEY_F2):
		look_cinematografico_activo = not look_cinematografico_activo
		_aplicar_dof()
		_guardar_cfg()
	if _edge(KEY_F3):
		_overlay.visible = not _overlay.visible
	if _edge(KEY_F5):
		medir()
	if _edge(KEY_F4):
		calidad = (calidad + 1) % 3
		_aplicar_calidad()
		_guardar_cfg()
	if _overlay.visible:
		_overlay_t -= delta
		if _overlay_t <= 0.0:
			_overlay_t = 0.25
			_actualizar_overlay()

func _actualizar_overlay() -> void:
	var vp: RID = get_viewport().get_viewport_rid()
	_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(vp)
	_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(vp)
	_extras_t -= 0.25
	if _extras_t <= 0.0:
		_extras_t = 1.0
		_extras_n["luces"] = get_tree().root.find_children("*", "Light3D", true, false).filter(func(n: Node) -> bool: return (n as Light3D).is_visible_in_tree()).size()
		var np: int = 0
		for n: Node in get_tree().root.find_children("*", "GPUParticles3D", true, false):
			if (n as GPUParticles3D).is_visible_in_tree() and (n as GPUParticles3D).emitting:
				np += 1
		for n2: Node in get_tree().root.find_children("*", "CPUParticles3D", true, false):
			if (n2 as CPUParticles3D).is_visible_in_tree() and (n2 as CPUParticles3D).emitting:
				np += 1
		_extras_n["particulas"] = np
	var hh: int = int(daynight.hour)
	var mm: int = int((daynight.hour - float(hh)) * 60.0)
	_overlay.text = "LOOK %s   calidad %s   DOF %s\nhora %02d:%02d   preset: noche %.2f  día %.2f  crepúsculo %.2f (%s)\nGPU %.2f ms   CPU render %.2f ms   FPS %d   proceso %.2f ms\nluces %d   partículas %d   draw calls %d\nvisibilidad nocturna %.2f  (luna %.2f  copa %.2f  rebote %.2f  cueva %.2f)\nF2 interruptor   F3 overlay   F4 calidad   F5 medir%s" % [
		"ACTIVO" if look_cinematografico_activo else "apagado", NOMBRES_CALIDAD[calidad], "sí" if dof_activo else "no",
		hh, mm, _w_noche, _w_dia, _w_tw, actual.nombre if actual.nombre != "" else "mezcla",
		_gpu_ms, _cpu_ms, int(Engine.get_frames_per_second()), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		int(_extras_n["luces"]), int(_extras_n["particulas"]), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		noche.visibilidad if noche != null else 1.0, noche.f_luna if noche != null else 1.0, noche.f_copa if noche != null else 1.0, noche.f_rebote if noche != null else 0.0, noche.f_cueva if noche != null else 1.0,
		("\n" + _medicion) if _medicion != "" else ""]

func _cargar_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return
	look_cinematografico_activo = bool(cf.get_value("look", "activo", true))
	calidad = clampi(int(cf.get_value("look", "calidad", Calidad.MEDIA)), 0, 2)
	dof_activo = bool(cf.get_value("look", "dof", false))

func _guardar_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("look", "activo", look_cinematografico_activo)
	cf.set_value("look", "calidad", calidad)
	cf.set_value("look", "dof", dof_activo)
	cf.save(CFG_PATH)

## Mide el costo de la GPU de varias combinaciones (promedio de ~2 s cada una) y lo imprime y muestra en el overlay.
## Para decidir con números si glow y DOF valen la pena. Se llama a mano (F5).
func medir() -> void:
	var vp: RID = get_viewport().get_viewport_rid()
	var guardado: Array = [look_cinematografico_activo, calidad, dof_activo]
	var variantes: Array = [
		["look apagado", false, Calidad.MEDIA, false],
		["media (glow, haces, bruma)", true, Calidad.MEDIA, false],
		["alta", true, Calidad.ALTA, false],
		["alta + DOF", true, Calidad.ALTA, true],
	]
	var res: PackedStringArray = []
	for v: Array in variantes:
		look_cinematografico_activo = v[1]
		calidad = v[2]
		dof_activo = v[3]
		_aplicar_calidad()
		await get_tree().create_timer(0.8).timeout
		var suma: float = 0.0
		var n: int = 0
		var fps_sum: float = 0.0
		for i in 40:
			await get_tree().process_frame
			suma += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			fps_sum += Engine.get_frames_per_second()
			n += 1
		res.append("%s: GPU %.2f ms  (%d fps)" % [v[0], suma / float(n), int(fps_sum / float(n))])
	look_cinematografico_activo = guardado[0]
	calidad = guardado[1]
	dof_activo = guardado[2]
	_aplicar_calidad()
	_medicion = "\n".join(res)
	print("MEDICION LOOK\n", _medicion)
