class_name NeedsBar
extends Control

## Medidores de necesidades (hambre, sed...). Verdes; al llegar al 10 % o menos se ponen rojos y titilan.
## Para sumar otro medidor: agregar una entrada a METERS y la propiedad (0..100) en el jugador.

const METERS: Array[Dictionary] = [
	{"prop": "hambre", "icon": "apple", "label": "Hambre"},
	{"prop": "sed", "icon": "drop", "label": "Sed"},
]
const BAR_W: float = 140.0
const BAR_H: float = 20.0
const ROW: float = 38.0
const LOW: float = 10.0

var player: Castaway
var _t: float = 0.0
var _shown: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(BAR_W + 110.0, ROW * float(METERS.size()) + 16.0)

func _process(delta: float) -> void:
	_t += delta
	if player != null:
		for m: Dictionary in METERS:
			var p: String = str(m["prop"])
			var v: float = float(player.get(p))
			_shown[p] = lerpf(float(_shown.get(p, v)), v, 1.0 - exp(-delta * 6.0))
	queue_redraw()

func _draw() -> void:
	UiTheme.draw_panel(self, Rect2(Vector2.ZERO, size), UiTheme.C_BRASS)
	for i in METERS.size():
		var m: Dictionary = METERS[i]
		var p: String = str(m["prop"])
		var v: float = clampf(float(_shown.get(p, 100.0)), 0.0, 100.0)
		var low: bool = float(player.get(p)) <= LOW if player != null else false
		var y: float = 8.0 + float(i) * ROW
		var blink: float = 0.5 + 0.5 * sin(_t * 7.0)
		var col: Color = Color(0.34, 0.82, 0.42)
		if low:
			col = Color(0.95, 0.15, 0.15).lerp(Color(1.0, 0.5, 0.45), blink * 0.5)
		_icon(str(m["icon"]), Vector2(26.0, y + 17.0), col)
		var r := Rect2(52.0, y + 6.0, BAR_W, BAR_H)
		draw_style_box(UiTheme.panel_style(6, Color(0.27, 0.35, 0.5, 0.9) if not low else Color(0.85, 0.2, 0.2, 0.95), Color(0.02, 0.04, 0.08, 0.95), 2), r)
		var fill := Rect2(r.position + Vector2(3, 3), Vector2((BAR_W - 6.0) * v / 100.0, BAR_H - 6.0))
		if fill.size.x > 0.5:
			draw_rect(fill, col)
			draw_rect(Rect2(fill.position, Vector2(fill.size.x, 4.0)), Color(1, 1, 1, 0.22))
		var mx: float = r.position.x + BAR_W * LOW / 100.0
		draw_line(Vector2(mx, r.position.y + 2.0), Vector2(mx, r.end.y - 2.0), Color(1, 1, 1, 0.3), 1.0)
		UiTheme.text(self, UiTheme.BOLD, Vector2(r.end.x + 10.0, r.position.y + 17.0), "%d" % int(round(v)), 20, UiTheme.C_BAD if low else UiTheme.C_TEXT, 44.0, HORIZONTAL_ALIGNMENT_LEFT, 4)

func _icon(kind: String, c: Vector2, col: Color) -> void:
	if kind == "apple":
		draw_circle(c + Vector2(-3, 1), 7.0, col)
		draw_circle(c + Vector2(3, 1), 7.0, col)
		draw_line(c + Vector2(0, -5), c + Vector2(2, -10), Color(0.45, 0.3, 0.15), 2.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(2, -9), c + Vector2(9, -10), c + Vector2(4, -5)]), Color(0.3, 0.7, 0.3))
	else:
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -11), c + Vector2(8, 2), c + Vector2(6, 8), c + Vector2(0, 10), c + Vector2(-6, 8), c + Vector2(-8, 2)]), col)
		draw_circle(c + Vector2(-2, 3), 2.2, Color(1, 1, 1, 0.4))
