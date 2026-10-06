class_name EcoDebug
extends CanvasLayer
## Overlay de debug del ecosistema. F6 = mostrar/ocultar, F7 = siguiente capa.

var eco: EcoMap
var _layer: int = 0
var _rect: TextureRect
var _label: Label
var _marker: ColorRect
var _panel: Control
const SIZE := 520.0

func _ready() -> void:
	layer = 50
	_panel = Control.new()
	_panel.visible = false
	add_child(_panel)
	_rect = TextureRect.new()
	_rect.custom_minimum_size = Vector2(SIZE, SIZE)
	_rect.size = Vector2(SIZE, SIZE)
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel.add_child(_rect)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.size = Vector2(SIZE, 60)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_label)
	_marker = ColorRect.new()
	_marker.color = Color.RED
	_marker.size = Vector2(9, 9)
	_panel.add_child(_marker)
	_place()

func _place() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_rect.position = Vector2(vs.x - SIZE - 20.0, 20.0)
	_label.position = _rect.position + Vector2(0, SIZE + 4.0)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = (event as InputEventKey).keycode
	if k == KEY_F6:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_refresh()
	elif k == KEY_F7 and _panel.visible:
		_layer = (_layer + 1) % eco.layer_names().size()
		_refresh()

func _refresh() -> void:
	_place()
	var n: int = eco.grid_size()
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for j in n:
		for i in n:
			img.set_pixel(i, j, eco.layer_color(_layer, i, j))
	_rect.texture = ImageTexture.create_from_image(img)
	_label.text = "[F7 cambia capa] %s\n%s" % [eco.layer_names()[_layer], eco.layer_legend(_layer)]

func _process(_d: float) -> void:
	if not _panel.visible:
		return
	var pl: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	var c: Vector2 = eco.world_to_cell_f(pl.global_position) / float(eco.grid_size()) * SIZE
	_marker.position = _rect.position + c - _marker.size * 0.5
