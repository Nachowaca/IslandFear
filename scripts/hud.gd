class_name Hud
extends CanvasLayer

## Interfaz: barra de salud moderna, mensajes de la isla, panel de su mente (tecla I) y pantalla de muerte.

const HEART_TEX: Texture2D = preload("res://assets/generated/ui_heart.png")

## false = barra lisa con brillo; true = barra segmentada (12 tramos)
@export var segmented: bool = false

const FRAME_SIZE: Vector2 = Vector2(340, 34)
const INNER_POS: Vector2 = Vector2(30, 5)
const INNER_SIZE: Vector2 = Vector2(328, 24)
const SEG_COUNT: int = 12

var player: Castaway
var brain: IslandBrain

# salud
var _hp_root: Control
var _lives: LivesBar
var _fill: Panel
var _fill_style: StyleBoxFlat
var _gloss: Panel
var _ghost: Panel
var _segs: Array[Panel] = []
var _heart: TextureRect
var _hp_text: Label
var _refuge_label: Label
var _hp_shown: float = 100.0
var _ghost_shown: float = 100.0
var _pulse: float = 0.0
var _beat: float = 0.0

var _flash: ColorRect
var _toast: Label
var _toast_panel: PanelContainer
var _toast_time: float = 0.0
var _panel: PanelContainer
var _panel_label: Label
var _death: Label
var _i_was_down: bool = false
var _panel_timer: float = 0.0

func _style(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.anti_aliasing = true
	return s

func _panel_node(parent: Control, pos: Vector2, size: Vector2, style: StyleBoxFlat) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)
	return p

func _ready() -> void:
	layer = 20
	# destello rojo al recibir daño
	_flash = ColorRect.new()
	_flash.color = Color(0.7, 0.0, 0.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_build_health()

	# hambre y sed, a la derecha del medidor de salud
	var needs := NeedsBar.new()
	needs.player = player
	needs.anchor_top = 1.0
	needs.anchor_bottom = 1.0
	needs.offset_left = 318.0
	needs.offset_top = -152.0
	add_child(needs)

	# mensajes de la isla
	# frases de la isla: tipografía sans legible sobre un fondo oscuro translúcido
	_toast_panel = PanelContainer.new()
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.anchor_top = 0.0
	_toast_panel.anchor_bottom = 0.0
	_toast_panel.offset_top = 96.0
	_toast_panel.offset_bottom = 96.0
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_panel.grow_vertical = Control.GROW_DIRECTION_END
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tst: StyleBoxFlat = UiTheme.panel_style(14, Color(0.5, 0.65, 0.7, 0.35), Color(0.0, 0.0, 0.0, 0.72), 1)
	tst.shadow_size = 0
	tst.content_margin_left = 30.0
	tst.content_margin_right = 30.0
	tst.content_margin_top = 14.0
	tst.content_margin_bottom = 16.0
	_toast_panel.add_theme_stylebox_override("panel", tst)
	_toast_panel.modulate.a = 0.0
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_override("font", UiTheme.sans())
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_child(_toast)
	add_child(_toast_panel)

	# panel de depuración "Mente de la isla"
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -400.0
	_panel.offset_right = -14.0
	_panel.offset_top = 14.0
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_label = Label.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(12, UiTheme.C_TEAL, Color(0.02, 0.05, 0.07, 0.9), 2))
	_panel_label.add_theme_font_size_override("font_size", 18)
	_panel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_panel_label)
	add_child(_panel)

	# pantalla de muerte
	_death = Label.new()
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death.add_theme_font_override("font", UiTheme.TITLE)
	_death.add_theme_font_size_override("font_size", 46)
	_death.add_theme_color_override("font_outline_color", Color.BLACK)
	_death.add_theme_constant_override("outline_size", 10)
	_death.modulate.a = 0.0
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_death)

	if player != null:
		player.damaged.connect(_on_damaged)
		_hp_shown = player.health
		_ghost_shown = player.health
	if brain != null:
		brain.thought.connect(_on_thought)
	if Isla.vida > 1 or Isla.ciclo > 1:
		show_toast("Vida %d de %d" % [Isla.vida, Isla.VIDAS_MAX], Color(0.5, 0.95, 0.9))

func _build_health() -> void:
	_hp_root = Control.new()
	_hp_root.anchor_left = 0.0
	_hp_root.anchor_right = 0.0
	_hp_root.anchor_top = 1.0
	_hp_root.anchor_bottom = 1.0
	_hp_root.offset_left = 16.0
	_hp_root.offset_right = 16.0 + FRAME_SIZE.x
	_hp_root.offset_top = -148.0     # sobre el reloj, abajo a la izquierda
	_hp_root.offset_bottom = -78.0
	_hp_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_root.pivot_offset = Vector2(0.0, 70.0)
	_hp_root.scale = Vector2(0.85, 0.85)
	add_child(_hp_root)

	# marco oscuro redondeado con borde azul
	var frame: Panel = _panel_node(_hp_root, Vector2(34, 18), FRAME_SIZE - Vector2(34, 0), _style(Color(0.04, 0.05, 0.15, 0.92), 13, Color(0.27, 0.58, 0.88), 2))
	frame.size = Vector2(FRAME_SIZE.x - 34.0, FRAME_SIZE.y)
	var inner: Vector2 = INNER_SIZE - Vector2(34.0, 0.0)

	# estela de daño (clara) y relleno brillante
	_ghost = _panel_node(frame, Vector2(INNER_POS.x - 24.0, INNER_POS.y), Vector2(inner.x, inner.y), _style(Color(1.0, 0.78, 0.82, 0.55), 10))
	_fill_style = _style(Color(0.93, 0.1, 0.25), 10)
	_fill_style.shadow_color = Color(1.0, 0.2, 0.3, 0.45)
	_fill_style.shadow_size = 6
	_fill = _panel_node(frame, Vector2(INNER_POS.x - 24.0, INNER_POS.y), Vector2(inner.x, inner.y), _fill_style)
	_gloss = _panel_node(_fill, Vector2(6, 3), Vector2(inner.x - 12.0, 8), _style(Color(1.0, 0.7, 0.78, 0.5), 5))

	# modo segmentado
	var seg_w: float = (inner.x - float(SEG_COUNT - 1) * 4.0) / float(SEG_COUNT)
	for i in SEG_COUNT:
		var sp: Panel = _panel_node(frame, Vector2(INNER_POS.x - 24.0 + float(i) * (seg_w + 4.0), INNER_POS.y), Vector2(seg_w, inner.y), _style(Color(0.1, 0.25, 0.5, 0.75), 5))
		sp.visible = false
		_segs.append(sp)

	# número
	_hp_text = Label.new()
	_hp_text.position = Vector2(frame.size.x - 74.0, 5.0)
	_hp_text.size = Vector2(64.0, 22.0)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_text.add_theme_font_size_override("font_size", 13)
	_hp_text.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.1))
	_hp_text.add_theme_constant_override("outline_size", 4)
	_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_hp_text)

	# corazón que sobresale a la izquierda
	_heart = TextureRect.new()
	_heart.texture = HEART_TEX
	_heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_heart.size = Vector2(64, 64)
	_heart.position = Vector2(-2, 3)
	_heart.pivot_offset = Vector2(32, 32)
	_heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_root.add_child(_heart)

	# indicador de refugio
	_refuge_label = Label.new()
	_refuge_label.position = Vector2(46, 56)
	_refuge_label.add_theme_font_size_override("font_size", 13)
	_refuge_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.9))
	_refuge_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_refuge_label.add_theme_constant_override("outline_size", 4)
	_refuge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_root.add_child(_refuge_label)

	# las 7 vidas, sobre el medidor de salud
	_lives = LivesBar.new()
	_lives.position = Vector2(40, -10)
	_lives.size = Vector2(LivesBar.STEP * float(LivesBar.TOTAL) + 8.0, 24)
	_lives.alive = Isla.vidas_restantes()
	_hp_root.add_child(_lives)

func _on_damaged(amount: float, source: String) -> void:
	_flash.color.a = clampf(0.12 + amount * 0.008, 0.12, 0.3)
	_pulse = clampf(0.2 + amount * 0.01, 0.2, 0.45)
	if source != "":
		show_toast("Herido por %s" % source, Color(0.95, 0.35, 0.3))

func _on_thought(text: String, kind: String) -> void:
	var c: Color = Color(0.86, 0.82, 1.0)
	match kind:
		"omen":
			c = Color(1.0, 0.86, 0.5)
		"attack":
			c = Color(1.0, 0.52, 0.46)
		"info":
			c = Color(0.88, 0.92, 0.92)
	show_toast(text, c)

func show_toast(text: String, color: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_time = 5.0

## Apaga las gemas que correspondan según las vidas que quedan.
func refresh_lives() -> void:
	if _lives != null:
		_lives.set_alive(Isla.vidas_restantes())

## Final del juego tras la séptima vida: pantalla negra con título y texto.
func show_ending(title: String, body: String) -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	box.modulate.a = 0.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 54)
	t.add_theme_color_override("font_color", Color(0.6, 0.95, 0.9))
	box.add_child(t)
	var b := Label.new()
	b.text = body
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(1000, 0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 26)
	box.add_child(b)
	var tw: Tween = create_tween()
	tw.tween_property(bg, "color:a", 1.0, 2.0)
	tw.tween_property(box, "modulate:a", 1.0, 2.5)

func show_death(text: String) -> void:
	_death.text = text
	var tw: Tween = create_tween()
	tw.tween_property(_death, "modulate:a", 1.0, 1.5)

func _update_health(delta: float) -> void:
	if player == null:
		return
	var target: float = player.health
	_hp_shown = lerpf(_hp_shown, target, 1.0 - exp(-delta * 9.0))
	if _hp_shown >= _ghost_shown:
		_ghost_shown = _hp_shown                      # curación: sin estela
	else:
		_ghost_shown = lerpf(_ghost_shown, _hp_shown, 1.0 - exp(-delta * 1.6))
	var k: float = clampf(_hp_shown / player.max_health, 0.0, 1.0)
	var kg: float = clampf(_ghost_shown / player.max_health, 0.0, 1.0)
	var inner_w: float = INNER_SIZE.x - 34.0

	_fill.visible = not segmented
	_ghost.visible = not segmented
	if not segmented:
		var w: float = inner_w * k
		_fill.visible = w > 3.0
		_fill.size.x = maxf(w, 0.0)
		_gloss.size.x = maxf(w - 12.0, 0.0)
		_ghost.size.x = maxf(inner_w * kg, 0.0)
		# color: rojo vivo, más oscuro y titilante con poca salud
		var low: float = clampf((0.35 - k) / 0.35, 0.0, 1.0)
		var blink: float = 0.5 + 0.5 * sin(_beat * TAU * 1.0)
		var base: Color = Color(0.93, 0.1, 0.25).lerp(Color(0.75, 0.05, 0.12), low)
		_fill_style.bg_color = base.lerp(Color(1.0, 0.35, 0.4), low * blink * 0.5)
		_fill_style.shadow_color = Color(1.0, 0.2, 0.3, 0.3 + 0.3 * low * blink)
	else:
		var lit: int = int(ceil(k * float(SEG_COUNT) - 0.001))
		for i in SEG_COUNT:
			var on: bool = i < lit
			var sb: StyleBoxFlat = (_segs[i].get_theme_stylebox("panel") as StyleBoxFlat)
			sb.bg_color = Color(0.95, 0.15, 0.3) if on else Color(0.1, 0.25, 0.5, 0.75)
			_segs[i].visible = true

	_hp_text.text = str(int(round(_hp_shown)))
	_refuge_label.text = "Refugio" if player.in_refuge else ""

	# el corazón late: lento y sutil normal, rápido y marcado con poca salud
	var low_k: float = clampf((0.5 - k) / 0.5, 0.0, 1.0)
	_beat += delta * lerpf(0.9, 2.6, low_k)
	var thump: float = pow(maxf(sin(_beat * TAU), 0.0), 8.0)
	_pulse = move_toward(_pulse, 0.0, delta * 1.2)
	var s: float = 1.0 + thump * lerpf(0.05, 0.16, low_k) + _pulse
	_heart.scale = Vector2(s, s)
	var tint: float = 1.0 - clampf(_pulse * 1.5, 0.0, 0.5)
	_heart.modulate = Color(1.0, tint, tint)
	if player.dead:
		_heart.modulate = Color(0.4, 0.4, 0.45)

func _process(delta: float) -> void:
	_update_health(delta)
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 1.2)
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast_panel.modulate.a = clampf(_toast_time / 1.2, 0.0, 1.0)
	var down: bool = Input.is_physical_key_pressed(KEY_I)
	if down and not _i_was_down:
		_panel.visible = not _panel.visible
	_i_was_down = down
	if _panel.visible and brain != null:
		_panel_timer -= delta
		if _panel_timer <= 0.0:
			_panel_timer = 0.25
			var lines: Array[String] = ["MENTE DE LA ISLA   (I: ocultar)", ""]
			lines.append_array(brain.status_lines())
			lines.append("")
			lines.append("Piensa:")
			for l: String in brain.log_lines:
				lines.append(" · " + l)
			_panel_label.text = "\n".join(lines)
