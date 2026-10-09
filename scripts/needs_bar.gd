class_name NeedsBar
extends Control

## Medidores de necesidades (hambre, sed...). Hambre ocre/verde, sed turquesa, marco de madera de naufragio; al llegar al 10 % o menos se ponen rojos y titilan.
## Para sumar otro medidor: agregar una entrada a METERS y la propiedad (0..100) en el jugador.

const METERS: Array[Dictionary] = [
	{"prop": "hambre", "icon": "res://assets/generated/ui_icon_hambre.png", "label": "Hambre", "col": Color(0.58, 0.62, 0.28)},
	{"prop": "sed", "icon": "res://assets/generated/ui_icon_sed.png", "label": "Sed", "col": Color(0.2, 0.6, 0.6)},
]
const ICONOS: Dictionary = {
	"hambre": preload("res://assets/generated/ui_icon_hambre.png"),
	"sed": preload("res://assets/generated/ui_icon_sed.png"),
}
const BAR_W: float = 170.0
const BAR_H: float = 20.0
const ROW: float = 34.0
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
	var full: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(full, PirateUi.WOOD_DARK)
	PirateUi.draw_wood_frame(self, full, full.grow(-6.0))
	for i in METERS.size():
		var m: Dictionary = METERS[i]
		var p: String = str(m["prop"])
		var v: float = clampf(float(_shown.get(p, 100.0)), 0.0, 100.0)
		var low: bool = float(player.get(p)) <= LOW if player != null else false
		var y: float = 8.0 + float(i) * ROW
		var blink: float = 0.5 + 0.5 * sin(_t * 7.0)
		var col: Color = m["col"]
		if low:
			col = Color(0.78, 0.18, 0.15).lerp(Color(0.95, 0.42, 0.32), blink * 0.5)
		var tex: Texture2D = ICONOS[p]
		if tex != null:
			var ib: float = 1.0 + (0.08 * blink if low else 0.0)
			var ip: Vector2 = Vector2(12.0, y + 1.0) - Vector2.ONE * (ib - 1.0) * 14.0
			draw_set_transform(ip, 0.0, Vector2.ONE * (30.0 * ib / 128.0))
			draw_texture(tex, Vector2.ZERO, Color(1, 1, 1, 1))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var r := Rect2(56.0, y + 6.0, BAR_W, BAR_H)
		draw_rect(r, Color(0.04, 0.025, 0.015))
		var fill := Rect2(r.position, Vector2(BAR_W * v / 100.0, BAR_H))
		if fill.size.x > 0.5:
			draw_rect(fill, col)
			draw_rect(Rect2(fill.position, Vector2(fill.size.x, 3.0)), Color(1, 1, 0.9, 0.16))
			draw_rect(Rect2(fill.position + Vector2(0.0, BAR_H - 4.0), Vector2(fill.size.x, 4.0)), Color(0, 0, 0, 0.18))
		PirateUi.draw_notches(self, r, 10)
		PirateUi.draw_wood_frame(self, r.grow(4.0), r)
		UiTheme.text(self, UiTheme.BOLD, Vector2(r.end.x + 12.0, r.position.y + 17.0), "%d" % int(round(v)), 18, UiTheme.C_BAD if low else Color(0.96, 0.9, 0.74), 40.0, HORIZONTAL_ALIGNMENT_LEFT, 4)
