class_name LookNoche
extends Node

## Visibilidad nocturna local (0..1) en la posición del jugador. Cuánta luz de luna "le llega" ahí:
## 1) la luna vista desde el punto (una loma entre medio la tapa), 2) la copa de los árboles,
## 3) el rebote del suelo claro (arena, orilla, agua) vs. el suelo oscuro del bosque, 4) la cueva (sin luna).
## Se recalcula cada 0.3 s y se suaviza; el LookDirector la usa para modular luna y ambiente.

const PASOS: int = 8
const ALCANCE: float = 56.0
const RADIO_COPA: float = 9.0
const MINIMO: float = 0.06      ## el peor lugar al aire libre (bosque cerrado, luna tapada) conserva este valor

var terrain: IslandTerrain
var eco: EcoMap
var player: Node3D

var visibilidad: float = 1.0
var f_luna: float = 1.0
var f_copa: float = 1.0
var f_rebote: float = 0.5
var f_cueva: float = 1.0
var f_valle: float = 1.0

var _t: float = 0.0
var _objetivo: float = 1.0
var _moon_dir: Vector3 = Vector3.UP

func set_luna(dir: Vector3) -> void:
	_moon_dir = dir

func _process(delta: float) -> void:
	if player == null or terrain == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.3
		_calcular(player.global_position)
	visibilidad = lerpf(visibilidad, _objetivo, 1.0 - exp(-1.2 * delta))

func _calcular(pp: Vector3) -> void:
	# 1) horizonte hacia la luna
	var hz: Vector2 = Vector2(_moon_dir.x, _moon_dir.z)
	var hl: float = hz.length()
	if hl < 0.05 or _moon_dir.y < 0.05:     # luna bajo el horizonte: no hay dirección que tapar
		f_luna = 1.0
	else:
		hz /= hl
		var pend: float = _moon_dir.y / hl
		var tapados: float = 0.0
		for i in PASOS:
			var d: float = ALCANCE * float(i + 1) / float(PASOS)
			var h: float = terrain.height_at(pp.x + hz.x * d, pp.z + hz.y * d)
			var ray: float = pp.y + 1.6 + pend * d
			tapados += clampf((h - ray) / 2.0 + 0.5, 0.0, 1.0) if h > ray - 1.0 else 0.0
		f_luna = 1.0 - clampf(tapados / float(PASOS) * 1.6, 0.0, 1.0) * 0.75
	# 2) copa
	var cuenta: float = 0.0
	var r2: float = RADIO_COPA * RADIO_COPA
	for t: Vector3 in terrain.tree_positions:
		var dx: float = t.x - pp.x
		var dz: float = t.z - pp.z
		if dx * dx + dz * dz < r2:
			cuenta += 1.0
	for p: Vector3 in terrain.palm_positions:
		var ex: float = p.x - pp.x
		var ez: float = p.z - pp.z
		if ex * ex + ez * ez < r2:
			cuenta += 0.5
	f_copa = 1.0 - clampf(cuenta / 7.0, 0.0, 1.0) * 0.8
	# 3) rebote
	f_rebote = 0.4
	if eco != null:
		var w: PackedFloat32Array = eco.get_bioma_pesos(pp)
		var costa: float = w[EcoMap.Bioma.COSTA] if w.size() > EcoMap.Bioma.COSTA else 0.0
		var arena: float = 1.0 if eco.get_suelo(pp) == EcoMap.Suelo.ARENA else 0.0
		var agua: float = clampf(1.0 - eco.get_dist_agua(pp) / 16.0, 0.0, 1.0)
		var selva: float = w[EcoMap.Bioma.SELVA] if w.size() > EcoMap.Bioma.SELVA else 0.0
		f_rebote = clampf(0.2 + costa * 0.45 + arena * 0.35 + agua * 0.2 - selva * 0.25, 0.0, 1.0)
	# 3b) hondonadas: más bajo que el entorno (20 m a la redonda) = más oscuro, el aire frío y la sombra se acumulan
	var h0: float = terrain.height_at(pp.x, pp.z)
	var prom: float = 0.0
	for k in 8:
		var ang: float = float(k) * TAU / 8.0
		prom += terrain.height_at(pp.x + cos(ang) * 20.0, pp.z + sin(ang) * 20.0)
	prom /= 8.0
	f_valle = 1.0 - clampf((prom - h0) / 4.0, 0.0, 1.0) * 0.7
	# 4) cueva
	f_cueva = 1.0
	if terrain.is_in_cave_area(pp.x, pp.z, 1.0):
		f_cueva = 0.0
	var libre: float = f_luna * f_copa * f_valle * lerpf(0.5, 1.25, f_rebote)
	_objetivo = lerpf(MINIMO, 1.0, clampf(libre, 0.0, 1.0)) * lerpf(0.3, 1.0, f_cueva)
