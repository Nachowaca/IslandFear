extends CanvasLayer

## Dormir en un refugio (E cerca). Se elige cuántos minutos; la pantalla se oscurece, el reloj corre rápido
## y el sol o la luna cruzan el cielo. Se pierde un 2 % de hambre y de sed, se recupera vida y calor.
## La isla dice algo al dormirte y al despertar, según su ánimo. Se crea desde main.gd.

const OPCIONES: Array[int] = [30, 60, 120, 240, 480]     ## minutos de la isla
const DISTANCIA: float = 2.6
const COSTO_NECESIDAD: float = 2.0

enum Estado { NADA, ELEGIR, DURMIENDO }

var player: Castaway
var daynight: Node
var terrain: IslandTerrain
var estado: Estado = Estado.NADA

var _idx: int = 2
var _refugio: Node3D
var _prev: Dictionary = {}
var _veil: ColorRect
var _veil_goal: float = 0.0
var _texto: Label
var _reloj: Label
var _p: float = 0.0
var _dur: float = 6.0
var _e_prev: float = 0.0
var _minutos: int = 0
var _dormido_min: float = 0.0
var _t_dormido: float = 0.0
var _cd: float = 0.0

const FRASES_DORMIR: Dictionary = {
	"hostil": ["Dormí. Yo sigo despierta.", "Cerrá los ojos. No te los pierdo de vista."],
	"neutra": ["Cerrá los ojos. Te cuido de lejos.", "Descansá. La noche pasa sola."],
	"amiga": ["Dormí tranquilo. Yo hago la guardia.", "Andá, soñá. Acá estoy."],
}
const FRASES_DESPERTAR: Dictionary = {
	"hostil": ["Seguís acá.", "Despertaste. Todavía."],
	"neutra": ["Amaneciste. Eso me alcanza.", "Dormiste. Se te notaba cansado."],
	"amiga": ["Soñaste conmigo, ¿no?", "Buen día. Te esperaba."],
}

func _ready() -> void:
	layer = 22
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_veil = ColorRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.color = Color(0.02, 0.03, 0.08, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_veil)
	_texto = _label(root, 34, 0.38)
	_reloj = _label(root, 84, 0.13)
	_reloj.visible = false
	if player != null:
		player.damaged.connect(_on_damaged)

func _label(parent: Control, size: int, y: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.anchor_top = y
	l.anchor_bottom = y
	l.offset_top = -60.0
	l.offset_bottom = 60.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.12))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _edge(key: Key) -> bool:
	var down: bool = Input.is_physical_key_pressed(key)
	var was: bool = bool(_prev.get(key, false))
	_prev[key] = down
	return down and not was

## Refugio al alcance (o null).
func cerca() -> Node3D:
	if estado != Estado.NADA or _cd > 0.0 or player == null or not player.controllable or player.dead or player.sitting:
		return null
	var best: Node3D = null
	var bd: float = DISTANCIA
	for n: Node in get_tree().get_nodes_in_group("refugio"):
		var r: Node3D = n as Node3D
		if r == null:
			continue
		var d: float = Vector2(r.global_position.x - player.global_position.x, r.global_position.z - player.global_position.z).length()
		if d < bd:
			bd = d
			best = r
	return best

func abrir() -> void:
	var r: Node3D = cerca()
	if r == null:
		return
	_refugio = r
	estado = Estado.ELEGIR
	player.menu_lock = true
	_veil_goal = 0.45
	_actualizar_texto()

func _hora_txt(h: float) -> String:
	var hh: int = int(floor(h)) % 24
	var mm: int = int(floor((h - floor(h)) * 60.0))
	return "%02d:%02d" % [hh, mm]

func _actualizar_texto() -> void:
	var m: int = OPCIONES[_idx]
	var h: float = float(daynight.get("hour")) if daynight != null else 0.0
	var dur_txt: String = ("%d min" % m) if m < 60 else ("%d h" % int(float(m) / 60.0))
	_texto.text = "¿Cuánto querés dormir?\n◄   %s   ►\nDespertarías a las %s\nEnter: dormir     Esc: cancelar" % [dur_txt, _hora_txt(fposmod(h + float(m) / 60.0, 24.0))]

func _cerrar_menu() -> void:
	estado = Estado.NADA
	player.menu_lock = false
	_veil_goal = 0.0
	_texto.text = ""
	_cd = 0.4

func _empezar() -> void:
	_minutos = OPCIONES[_idx]
	_dur = clampf(float(_minutos) / 40.0, 4.0, 14.0)
	_p = 0.0
	_e_prev = 0.0
	_dormido_min = 0.0
	_t_dormido = 0.0
	estado = Estado.DURMIENDO
	player.sleeping = true
	player.velocity = Vector3.ZERO
	player.global_position = _refugio.call("cama_pos")
	player.rotation.y = _refugio.global_rotation.y
	_refugio.set("durmiendo", true)
	player.add_need("hambre", -COSTO_NECESIDAD)
	player.add_need("sed", -COSTO_NECESIDAD)
	_veil_goal = 0.62
	_texto.text = ""
	_reloj.visible = true
	_decir(FRASES_DORMIR)

func _despertar() -> void:
	if estado != Estado.DURMIENDO:
		return
	estado = Estado.NADA
	player.sleeping = false
	player.menu_lock = false
	var fr: float = clampf(_dormido_min / 480.0, 0.0, 1.0)
	player.health = minf(player.health + 60.0 * fr, 100.0)
	player.temp = minf(player.temp + _dormido_min / 3.0, 100.0)
	_refugio.set("durmiendo", false)
	var lado: Vector3 = -_refugio.global_transform.basis.z * 1.7
	var pos: Vector3 = _refugio.global_position + lado
	if terrain != null:
		pos.y = terrain.height_at(pos.x, pos.z)
	player.global_position = pos
	player.velocity = Vector3.ZERO
	_veil_goal = 0.0
	_reloj.visible = false
	_texto.text = ""
	_cd = 0.6
	Isla.registrar_evento("contemplar", pos, 2.0)
	_decir(FRASES_DESPERTAR)

func _decir(tabla: Dictionary) -> void:
	var e: int = Isla.etapa_idx()
	var clave: String = "hostil" if e <= 1 else ("amiga" if e >= 4 else "neutra")
	var arr: Array = tabla[clave]
	var brain: Node = get_tree().current_scene.get_node_or_null("IslandBrain")
	if brain != null:
		brain.call("_say", str(arr[randi() % arr.size()]), "whisper")

func _on_damaged(_a: float, _s: String) -> void:
	if estado == Estado.DURMIENDO:
		_despertar()

func _process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	_veil.color.a = lerpf(_veil.color.a, _veil_goal, 1.0 - exp(-3.0 * delta))
	if player == null:
		return
	match estado:
		Estado.ELEGIR:
			if _edge(KEY_LEFT) or _edge(KEY_A):
				_idx = maxi(_idx - 1, 0)
				_actualizar_texto()
			if _edge(KEY_RIGHT) or _edge(KEY_D):
				_idx = mini(_idx + 1, OPCIONES.size() - 1)
				_actualizar_texto()
			if _edge(KEY_ENTER) or _edge(KEY_KP_ENTER) or _edge(KEY_E):
				_empezar()
			elif _edge(KEY_ESCAPE) or _edge(KEY_Q):
				_cerrar_menu()
		Estado.DURMIENDO:
			_t_dormido += delta
			_p = minf(_p + delta / _dur, 1.0)
			var e: float = smoothstep(0.0, 1.0, _p)
			var dm: float = float(_minutos) * (e - _e_prev)
			_e_prev = e
			_dormido_min += dm
			if daynight != null:
				daynight.call("avanzar_horas", dm / 60.0)
				var h: float = float(daynight.call("_current_hour"))
				var hh: int = int(floor(h)) % 24
				var mm: int = int(floor((h - floor(h)) * 60.0))
				var ss: int = int(floor(fposmod(h * 3600.0, 60.0)))
				_reloj.text = "%02d:%02d:%02d" % [hh, mm, ss]
			if _p >= 1.0:
				_despertar()
			elif _t_dormido > 2.0 and (_edge(KEY_E) or _edge(KEY_SPACE) or _edge(KEY_ESCAPE) or _edge(KEY_W) or _edge(KEY_S)):
				_despertar()
			else:
				_edge(KEY_E)
				_edge(KEY_SPACE)
				_edge(KEY_ESCAPE)
				_edge(KEY_W)
				_edge(KEY_S)
