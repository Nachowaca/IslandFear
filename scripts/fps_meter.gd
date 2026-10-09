extends CanvasLayer
## Medidor de rendimiento arriba a la derecha (herramienta de desarrollo). Tecla F12 lo muestra/oculta.

var _label: Label
var _acc: float = 0.0
var _min_fps: float = 9999.0
var _shown_min: float = 0.0

func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(1, 1, 0.6))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -320.0
	_label.offset_right = -14.0
	_label.offset_top = 10.0
	add_child(_label)

func _process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_F12) and not _f12:
		_label.visible = not _label.visible
	_f12 = Input.is_physical_key_pressed(KEY_F12)
	if delta > 0.0:
		_min_fps = minf(_min_fps, 1.0 / delta)
	_acc += delta
	if _acc >= 0.5:
		_acc = 0.0
		_shown_min = _min_fps
		_min_fps = 9999.0
		var prims: float = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0
		_label.text = "%d FPS (mín %d)\n%.1f ms\n%d draws  %.1f M tri" % [Engine.get_frames_per_second(), int(_shown_min), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), prims]

var _f12: bool = false
