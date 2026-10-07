class_name AmbientePreset
extends Resource

## Look del ambiente en un momento del día. Cuatro presets (noche, amanecer, día, atardecer) se mezclan
## según el sol (ver LookDirector). Los valores salen de la paleta teal + ámbar de la isla.

@export var nombre: String = ""
@export var color_cielo_alto: Color = Color.BLACK
@export var color_cielo_horizonte: Color = Color.BLACK
@export var color_sol: Color = Color.WHITE
@export var energia_sol: float = 1.0
@export var color_niebla: Color = Color.WHITE
@export var densidad_niebla: float = 0.001
@export var color_ambiente: Color = Color.WHITE     ## tinte de las sombras (frío de día, violeta al atardecer)
@export var energia_ambiente: float = 1.0
@export var contribucion_cielo: float = 1.0         ## 1 = el ambiente es solo el cielo; menos = más tinte
@export var intensidad_bloom: float = 0.7
@export var intensidad_haces: float = 0.0
@export var niebla_altura: float = 0.0              ## niebla baja: se acumula en valles y sobre el agua
@export var exposicion: float = 1.0
@export var saturacion: float = 1.1
@export var contraste: float = 1.05

const COLORES: Array[String] = ["color_cielo_alto", "color_cielo_horizonte", "color_sol", "color_niebla", "color_ambiente"]
const NUMEROS: Array[String] = ["energia_sol", "densidad_niebla", "energia_ambiente", "contribucion_cielo", "intensidad_bloom",
	"intensidad_haces", "niebla_altura", "exposicion", "saturacion", "contraste"]

## Mezcla a y b (t 0..1) y deja el resultado en `destino` (sin crear objetos nuevos).
static func mezclar(a: AmbientePreset, b: AmbientePreset, t: float, destino: AmbientePreset) -> void:
	for c: String in COLORES:
		destino.set(c, (a.get(c) as Color).lerp(b.get(c) as Color, t))
	for n: String in NUMEROS:
		destino.set(n, lerpf(float(a.get(n)), float(b.get(n)), t))

static func _crear(nom: String, alto: Color, horiz: Color, sol: Color, e_sol: float, niebla: Color, dens: float, amb: Color, e_amb: float,
		contrib: float, bloom: float, haces: float, alt_n: float, expo: float, sat: float, con: float) -> AmbientePreset:
	var p := AmbientePreset.new()
	p.nombre = nom
	p.color_cielo_alto = alto
	p.color_cielo_horizonte = horiz
	p.color_sol = sol
	p.energia_sol = e_sol
	p.color_niebla = niebla
	p.densidad_niebla = dens
	p.color_ambiente = amb
	p.energia_ambiente = e_amb
	p.contribucion_cielo = contrib
	p.intensidad_bloom = bloom
	p.intensidad_haces = haces
	p.niebla_altura = alt_n
	p.exposicion = expo
	p.saturacion = sat
	p.contraste = con
	return p

## Azul lunar desaturado, puntos cálidos emisivos.
static func noche() -> AmbientePreset:
	return _crear("Noche", Color(0.015, 0.1, 0.17), Color(0.05, 0.25, 0.3), Color(1.0, 0.5, 0.22), 0.0,
		Color(0.05, 0.25, 0.3), 0.0024, Color(0.14, 0.3, 0.62), 0.85, 0.8, 0.8, 1.0, 0.03, 0.95, 1.15, 1.08)

## Rosado y ámbar suave, bruma de la mañana.
static func amanecer() -> AmbientePreset:
	return _crear("Amanecer", Color(0.3, 0.34, 0.64), Color(1.0, 0.6, 0.45), Color(1.0, 0.68, 0.45), 1.6,
		Color(0.95, 0.68, 0.6), 0.0019, Color(0.55, 0.5, 0.8), 1.2, 0.7, 0.9, 1.0, 0.04, 1.0, 1.16, 1.08)

## Cálido y saturado, sombras azuladas.
static func dia() -> AmbientePreset:
	return _crear("Día", Color(0.2, 0.45, 0.82), Color(0.72, 0.84, 0.93), Color(1.0, 0.95, 0.86), 1.25,
		Color(0.72, 0.84, 0.93), 0.0012, Color(0.5, 0.62, 0.92), 0.7, 0.72, 0.7, 0.3, 0.0, 0.95, 1.12, 1.1)

## Ámbar y rosado, haces largos.
static func atardecer() -> AmbientePreset:
	return _crear("Atardecer", Color(0.28, 0.3, 0.6), Color(1.0, 0.52, 0.28), Color(1.0, 0.6, 0.26), 1.8,
		Color(1.0, 0.72, 0.45), 0.0018, Color(0.55, 0.45, 0.78), 1.3, 0.7, 0.9, 1.0, 0.035, 1.0, 1.18, 1.08)
