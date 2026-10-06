class_name LivesBar
extends Control

## Las 7 vidas del náufrago: gemas que se apagan una a una cuando la isla gana.

const TOTAL: int = 7
const STEP: float = 27.0

var alive: int = TOTAL
var _t: float = 0.0
var _burst: Array[float] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in TOTAL:
		_burst.append(0.0)

func set_alive(n: int) -> void:
	n = clampi(n, 0, TOTAL)
	for i in range(n, alive):
		if i >= 0 and i < TOTAL:
			_burst[i] = 1.0                      # destello al perder una vida
	alive = n

func _process(delta: float) -> void:
	_t += delta
	for i in TOTAL:
		_burst[i] = maxf(_burst[i] - delta * 0.9, 0.0)
	queue_redraw()

func _gem(center: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([center + Vector2(0, -r * 1.15), center + Vector2(r * 0.85, 0), center + Vector2(0, r * 1.15), center + Vector2(-r * 0.85, 0)])

func _draw() -> void:
	for i in TOTAL:
		var c: Vector2 = Vector2(12.0 + float(i) * STEP, 13.0)
		if i < alive:
			var current: bool = i == alive - 1
			var r: float = 10.5 * (1.0 + (0.1 * sin(_t * 3.0) if current else 0.0))
			draw_colored_polygon(_gem(c + Vector2(1.5, 2.0), r), Color(0, 0, 0, 0.35))
			draw_colored_polygon(_gem(c, r), Color(0.2, 0.85, 0.78))
			draw_colored_polygon(_gem(c + Vector2(-1.0, -2.0), r * 0.5), Color(0.8, 1.0, 0.97, 0.85))
			var edge: PackedVector2Array = _gem(c, r)
			edge.append(edge[0])
			draw_polyline(edge, Color(0.85, 1.0, 0.98) if current else Color(0.05, 0.3, 0.32), 1.6, true)
		else:
			var e: PackedVector2Array = _gem(c, 9.0)
			e.append(e[0])
			draw_polyline(e, Color(0.55, 0.6, 0.65, 0.5), 1.4, true)
			if _burst[i] > 0.0:
				draw_circle(c, 6.0 + (1.0 - _burst[i]) * 16.0, Color(1.0, 0.3, 0.3, _burst[i] * 0.6))
