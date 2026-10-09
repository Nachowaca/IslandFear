class_name PirateUi
extends Control

## Ayudas de dibujo pirata (madera de naufragio, latón, cuerda) para el HUD inferior izquierdo.
## Como nodo, dibuja el marco de madera + remaches + muescas sobre una barra (hijo de la barra).

const WOOD_DARK: Color = Color(0.13, 0.085, 0.05)
const WOOD_MID: Color = Color(0.27, 0.18, 0.1)
const WOOD_LIGHT: Color = Color(0.38, 0.26, 0.15)
const BRASS: Color = Color(0.72, 0.56, 0.24)
const BRASS_DARK: Color = Color(0.36, 0.26, 0.1)
const ROPE: Color = Color(0.7, 0.6, 0.38, 0.35)

## Rectángulo interior de la pista (relleno) en coordenadas locales.
var track: Rect2 = Rect2()
var notches: int = 10

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_notches(self, track, notches)
	draw_wood_frame(self, Rect2(Vector2.ZERO, size), track)

## Marco de tablones: borde de madera alrededor de `hole`, veta y remaches de latón en las esquinas.
static func draw_wood_frame(c: CanvasItem, outer: Rect2, hole: Rect2) -> void:
	var top: Rect2 = Rect2(outer.position, Vector2(outer.size.x, hole.position.y - outer.position.y))
	var bottom: Rect2 = Rect2(Vector2(outer.position.x, hole.end.y), Vector2(outer.size.x, outer.end.y - hole.end.y))
	var left: Rect2 = Rect2(Vector2(outer.position.x, hole.position.y), Vector2(hole.position.x - outer.position.x, hole.size.y))
	var right: Rect2 = Rect2(Vector2(hole.end.x, hole.position.y), Vector2(outer.end.x - hole.end.x, hole.size.y))
	for r: Rect2 in [top, bottom, left, right]:
		c.draw_rect(r, WOOD_MID)
	# veta
	for r: Rect2 in [top, bottom]:
		c.draw_line(Vector2(r.position.x, r.position.y + r.size.y * 0.4), Vector2(r.end.x, r.position.y + r.size.y * 0.4), WOOD_DARK, 1.0)
		c.draw_line(Vector2(r.position.x, r.position.y + 1.0), Vector2(r.end.x, r.position.y + 1.0), WOOD_LIGHT, 1.0)
	# sombra interior y contorno
	c.draw_rect(hole.grow(1.0), Color(0.03, 0.02, 0.01, 0.9), false, 1.5)
	c.draw_rect(outer, WOOD_DARK, false, 1.5)
	# remaches
	var inset: float = 4.0
	for p: Vector2 in [outer.position + Vector2(inset, inset), Vector2(outer.end.x - inset, outer.position.y + inset), Vector2(outer.position.x + inset, outer.end.y - inset), outer.end - Vector2(inset, inset)]:
		rivet(c, p, 2.2)

static func rivet(c: CanvasItem, p: Vector2, r: float) -> void:
	c.draw_circle(p + Vector2(0.6, 0.8), r, Color(0, 0, 0, 0.5))
	c.draw_circle(p, r, BRASS_DARK)
	c.draw_circle(p, r * 0.7, BRASS)
	c.draw_circle(p + Vector2(-r * 0.25, -r * 0.25), r * 0.28, Color(1.0, 0.93, 0.65, 0.8))

## Muescas de cuerda: marcas cada 1/n de la pista con un tejido diagonal tenue.
static func draw_notches(c: CanvasItem, track_rect: Rect2, n: int) -> void:
	if track_rect.size.x <= 0.0:
		return
	var y0: float = track_rect.position.y
	var y1: float = track_rect.end.y
	var x: float = track_rect.position.x + 3.0
	while x < track_rect.end.x:
		c.draw_line(Vector2(x, y1), Vector2(x + 4.0, y0), ROPE, 1.0)
		x += 6.0
	for i in range(1, n):
		var nx: float = track_rect.position.x + track_rect.size.x * float(i) / float(n)
		c.draw_line(Vector2(nx, y0), Vector2(nx, y1), Color(0.05, 0.03, 0.02, 0.6), 1.5)
		c.draw_line(Vector2(nx + 1.0, y0), Vector2(nx + 1.0, y1), Color(0.8, 0.65, 0.35, 0.18), 1.0)
