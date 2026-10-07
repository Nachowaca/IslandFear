class_name EcoMap
extends Node3D
## Mapa ecológico de la isla, por capas. Cada capa se calcula una vez sobre una grilla y se consulta con
## funciones rápidas: get_altura / get_pendiente / get_dist_costa (capa 1). Las demás capas se agregan después.
## Todo es determinista (sale de params.seed y del terreno).

@export var params: EcoParams
var terrain: IslandTerrain

var _n: int = 0                 ## celdas por lado
var _origin: float = 0.0        ## coordenada mundo (x y z) de la celda 0
var _alt: PackedFloat32Array
var _slope: PackedFloat32Array  ## grados
var _coast: PackedFloat32Array  ## metros hasta la orilla (0 en el agua)
var _alt_max: float = 1.0
var _slope_max: float = 1.0
var _coast_max: float = 1.0
var _agua: PackedFloat32Array   ## distancia al agua (mar o laguna), m
var _agua_max: float = 1.0
var _hum: PackedFloat32Array    ## humedad base 0..1
var _suelo: PackedByteArray
var _bioma: PackedByteArray
var _noise := FastNoiseLite.new()
var _mist: PackedFloat32Array   ## zonas misteriosas 0..1
var mystery_centers: Array[Vector3] = []

enum Suelo { ARENA, ROCA, FERTIL, SECO }
enum Bioma { COSTA, ROQUEDAL, SELVA, BOSQUE, MATORRAL, ARIDO }
const SUELO_NAMES: Array[String] = ["arena", "roca", "tierra fértil", "tierra seca"]
const BIOMA_NAMES: Array[String] = ["costa", "roquedal", "selva", "bosque", "matorral", "zona árida"]
const SUELO_COLORS: Array[Color] = [Color(0.95, 0.88, 0.5), Color(0.5, 0.5, 0.55), Color(0.25, 0.5, 0.2), Color(0.7, 0.5, 0.3)]
const BIOMA_COLORS: Array[Color] = [Color(0.95, 0.85, 0.45), Color(0.55, 0.55, 0.6), Color(0.0, 0.45, 0.2), Color(0.3, 0.65, 0.3), Color(0.7, 0.75, 0.3), Color(0.85, 0.6, 0.35)]

## Enganche para la isla viva (todavía no hace nada): offsets que se sumarán a las capas.
var mood_humedad: float = 0.0     ## + más húmedo (isla triste), - más seco
var mood_cierre: float = 0.0      ## 0..1 vegetación que se cierra (isla enojada)
var mood_niebla: float = 0.0      ## 0..1 niebla extra

func set_mood(humedad_delta: float, cierre: float, niebla: float) -> void:
	mood_humedad = humedad_delta
	mood_cierre = clampf(cierre, 0.0, 1.0)
	mood_niebla = clampf(niebla, 0.0, 1.0)

func _ready() -> void:
	if params == null:
		params = EcoParams.new()
	if terrain != null:
		build()

func build() -> void:
	var half: float = terrain.radius * 1.35
	_n = int(ceil(half * 2.0 / params.cell_size)) + 1
	_origin = -half
	_build_altura()
	_build_pendiente()
	_build_costa()
	_noise.seed = params.eco_seed
	_noise.frequency = 0.02
	_build_agua()
	_build_humedad()
	_build_suelo_bioma()
	_build_misterio()

# ------------------------------------------------------------------ capa 1: altura, pendiente, costa

func _build_altura() -> void:
	_alt.resize(_n * _n)
	_alt_max = 1.0
	for j in _n:
		for i in _n:
			var h: float = terrain.height_at(_origin + i * params.cell_size, _origin + j * params.cell_size)
			_alt[j * _n + i] = h
			_alt_max = maxf(_alt_max, h)

func _build_pendiente() -> void:
	_slope.resize(_n * _n)
	_slope_max = 1.0
	var cs: float = params.cell_size
	for j in _n:
		for i in _n:
			var hl: float = _alt[j * _n + maxi(i - 1, 0)]
			var hr: float = _alt[j * _n + mini(i + 1, _n - 1)]
			var hu: float = _alt[maxi(j - 1, 0) * _n + i]
			var hd: float = _alt[mini(j + 1, _n - 1) * _n + i]
			var g: float = Vector2((hr - hl) / (2.0 * cs), (hd - hu) / (2.0 * cs)).length()
			var deg: float = rad_to_deg(atan(g))
			_slope[j * _n + i] = deg
			_slope_max = maxf(_slope_max, deg)

## Distancia a la orilla (transformada de distancia en dos pasadas, aproximación chamfer).
func _build_costa() -> void:
	_coast.resize(_n * _n)
	var inf: float = 1e9
	for k in _n * _n:
		_coast[k] = inf if _alt[k] >= params.land_height else 0.0
	var cs: float = params.cell_size
	var dg: float = cs * 1.41421
	for j in _n:
		for i in _n:
			var k: int = j * _n + i
			var v: float = _coast[k]
			if i > 0: v = minf(v, _coast[k - 1] + cs)
			if j > 0:
				v = minf(v, _coast[k - _n] + cs)
				if i > 0: v = minf(v, _coast[k - _n - 1] + dg)
				if i < _n - 1: v = minf(v, _coast[k - _n + 1] + dg)
			_coast[k] = v
	for j in range(_n - 1, -1, -1):
		for i in range(_n - 1, -1, -1):
			var k: int = j * _n + i
			var v: float = _coast[k]
			if i < _n - 1: v = minf(v, _coast[k + 1] + cs)
			if j < _n - 1:
				v = minf(v, _coast[k + _n] + cs)
				if i < _n - 1: v = minf(v, _coast[k + _n + 1] + dg)
				if i > 0: v = minf(v, _coast[k + _n - 1] + dg)
			_coast[k] = v
	_coast_max = 1.0
	for k in _n * _n:
		if _coast[k] < inf * 0.5:
			_coast_max = maxf(_coast_max, _coast[k])
		else:
			_coast[k] = 0.0

# ------------------------------------------------------------------ capa 2: agua

## Fuentes de agua: el mar (distancia a la costa) y la laguna. Más fuentes (arroyos, manantiales) se suman acá.
func _build_agua() -> void:
	_agua.resize(_n * _n)
	_agua_max = 1.0
	for j in _n:
		for i in _n:
			var k: int = j * _n + i
			var w: Vector3 = cell_world(i, j)
			var dp: float = maxf(Vector2(w.x, w.z).distance_to(IslandTerrain.POND_CENTER) - IslandTerrain.POND_RADIUS, 0.0)
			var d: float = minf(_coast[k], dp) if _alt[k] >= params.land_height else 0.0
			_agua[k] = d
			_agua_max = maxf(_agua_max, d)

## Distancia al agua más cercana (mar o laguna), en metros.
func get_dist_agua(pos: Vector3) -> float:
	return _agua[_cell(pos)]

# ------------------------------------------------------------------ capa 3: humedad

func _build_humedad() -> void:
	_hum.resize(_n * _n)
	var ring: int = int(round(params.valley_radius / params.cell_size))
	for j in _n:
		for i in _n:
			var k: int = j * _n + i
			if _alt[k] < params.land_height:
				_hum[k] = 1.0
				continue
			var w: Vector3 = cell_world(i, j)
			var mean: float = 0.0
			for a in 8:
				var ang: float = a * TAU / 8.0
				var ii: int = clampi(i + int(round(cos(ang) * ring)), 0, _n - 1)
				var jj: int = clampi(j + int(round(sin(ang) * ring)), 0, _n - 1)
				mean += _alt[jj * _n + ii]
			mean /= 8.0
			var valle: float = clampf((mean - _alt[k]) / 2.5, 0.0, 1.0)
			var cerca: float = maxf(params.sea_humidity * exp(-_coast[k] / params.humidity_reach), exp(-_agua[k] / params.humidity_reach))
			var alt_n: float = clampf(_alt[k] / params.high_height, 0.0, 1.5)
			var pend_n: float = clampf(_slope[k] / 60.0, 0.0, 1.0)
			var ruido: float = _noise.get_noise_2d(w.x, w.z)
			var h: float = params.base_humidity + 0.5 * cerca + 0.3 * valle - 0.3 * alt_n - 0.15 * pend_n + 0.25 * ruido
			_hum[k] = clampf(h, 0.0, 1.0)

## Humedad 0..1 (incluye el ajuste del humor de la isla).
func get_humedad(pos: Vector3) -> float:
	return clampf(_hum[_cell(pos)] + mood_humedad, 0.0, 1.0)

# ------------------------------------------------------------------ capas 4 y 5: suelo y bioma

func _build_suelo_bioma() -> void:
	_suelo.resize(_n * _n)
	_bioma.resize(_n * _n)
	for k in _n * _n:
		_suelo[k] = _suelo_en(k)
		_bioma[k] = _argmax(_pesos_en(k))

func _suelo_en(k: int) -> int:
	if _coast[k] < params.sand_width and _alt[k] < params.sand_max_height:
		return Suelo.ARENA
	if _slope[k] >= params.steep_degrees or _alt[k] > params.high_height * 1.15:
		return Suelo.ROCA
	if _hum[k] >= params.fertile_humidity:
		return Suelo.FERTIL
	return Suelo.SECO

## Pesos (suman 1) de cada bioma en la celda k, con transiciones suaves.
func _pesos_en(k: int) -> PackedFloat32Array:
	var w := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if _alt[k] < params.land_height:
		w[Bioma.COSTA] = 1.0
		return w
	var h: float = _hum[k]
	var costa: float = 1.0 - smoothstep(params.sand_width * 0.5, params.sand_width * 1.4, _coast[k])
	var roca: float = clampf(smoothstep(params.steep_degrees - 10.0, params.steep_degrees + 4.0, _slope[k]) + smoothstep(params.high_height, params.high_height * 1.4, _alt[k]) * 0.8, 0.0, 1.0)
	var tierra: float = (1.0 - costa) * (1.0 - roca)
	w[Bioma.COSTA] = costa
	w[Bioma.ROQUEDAL] = (1.0 - costa) * roca
	w[Bioma.SELVA] = tierra * smoothstep(0.55, 0.72, h)
	w[Bioma.BOSQUE] = tierra * _campana(h, 0.5, 0.16)
	w[Bioma.MATORRAL] = tierra * _campana(h, 0.32, 0.14)
	w[Bioma.ARIDO] = tierra * (1.0 - smoothstep(0.12, 0.28, h))
	var s: float = 0.0
	for v in w:
		s += v
	if s < 0.0001:
		w[Bioma.MATORRAL] = 1.0
		return w
	for b in 6:
		w[b] /= s
	return w

func _campana(x: float, c: float, a: float) -> float:
	var d: float = (x - c) / a
	return exp(-d * d)

func _argmax(w: PackedFloat32Array) -> int:
	var best: int = 0
	for b in w.size():
		if w[b] > w[best]:
			best = b
	return best

## Tipo de suelo (enum Suelo).
func get_suelo(pos: Vector3) -> int:
	return _suelo[_cell(pos)]

func get_suelo_nombre(pos: Vector3) -> String:
	return SUELO_NAMES[get_suelo(pos)]

## Bioma dominante (enum Bioma).
func get_bioma(pos: Vector3) -> int:
	return _bioma[_cell(pos)]

func get_bioma_nombre(pos: Vector3) -> String:
	return BIOMA_NAMES[get_bioma(pos)]

## Peso de cada bioma en esa posición (transición gradual). Índice = enum Bioma.
func get_bioma_pesos(pos: Vector3) -> PackedFloat32Array:
	return _pesos_en(_cell(pos))

# ------------------------------------------------------------------ capa 7: zonas misteriosas

## Claros raros repartidos con distancia mínima, con su propia semilla (no cambian si cambia el resto).
func _build_misterio() -> void:
	_mist.resize(_n * _n)
	mystery_centers.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = params.mystery_seed
	var tries: int = 0
	while mystery_centers.size() < params.mystery_count and tries < 4000:
		tries += 1
		var c := Vector3(rng.randf_range(-125.0, 125.0), 0.0, rng.randf_range(-185.0, 185.0))
		c.y = terrain.height_at(c.x, c.z)
		if c.y < 2.5 or c.y > params.high_height * 0.9 or _slope[_cell(c)] > 18.0:
			continue
		if _coast[_cell(c)] < params.mystery_radius + 8.0:
			continue
		if terrain.is_in_pond_area(c.x, c.z, 1.6) or terrain.is_in_cave_area(c.x, c.z, 1.6):
			continue
		var ok: bool = true
		for o: Vector3 in mystery_centers:
			if Vector2(o.x - c.x, o.z - c.z).length() < params.mystery_min_dist:
				ok = false
				break
		if ok:
			mystery_centers.append(c)
	for j in _n:
		for i in _n:
			var w: Vector3 = cell_world(i, j)
			var best: float = 0.0
			for c2: Vector3 in mystery_centers:
				var r: float = params.mystery_radius * (1.0 + 0.25 * _noise.get_noise_2d(w.x * 3.0, w.z * 3.0))
				best = maxf(best, 1.0 - smoothstep(r * 0.55, r, Vector2(w.x - c2.x, w.z - c2.z).length()))
			_mist[j * _n + i] = best

## Intensidad 0..1 de zona misteriosa en esa posición.
func get_misterio(pos: Vector3) -> float:
	return _mist[_cell(pos)]

# ------------------------------------------------------------------ consultas

func _cell(pos: Vector3) -> int:
	var i: int = clampi(int(round((pos.x - _origin) / params.cell_size)), 0, _n - 1)
	var j: int = clampi(int(round((pos.z - _origin) / params.cell_size)), 0, _n - 1)
	return j * _n + i

## Altura del terreno (m).
func get_altura(pos: Vector3) -> float:
	return terrain.height_at(pos.x, pos.z)

## Pendiente en grados (0 = plano).
func get_pendiente(pos: Vector3) -> float:
	return _slope[_cell(pos)]

## Distancia a la orilla en metros (0 si está en el agua).
func get_dist_costa(pos: Vector3) -> float:
	return _coast[_cell(pos)]

func is_tierra(pos: Vector3) -> bool:
	return get_altura(pos) >= params.land_height

# ------------------------------------------------------------------ para el overlay de debug

func grid_size() -> int:
	return _n

func cell_world(i: int, j: int) -> Vector3:
	return Vector3(_origin + i * params.cell_size, 0.0, _origin + j * params.cell_size)

func world_to_cell_f(pos: Vector3) -> Vector2:
	return Vector2((pos.x - _origin) / params.cell_size, (pos.z - _origin) / params.cell_size)

## Nombres de las capas disponibles (el overlay las recorre).
func layer_names() -> PackedStringArray:
	return PackedStringArray(["Altura", "Pendiente", "Distancia a la costa", "Distancia al agua", "Humedad", "Suelo", "Bioma", "Zonas misteriosas"])

## Color de la celda (i, j) para la capa `layer`.
func layer_color(layer: int, i: int, j: int) -> Color:
	var k: int = j * _n + i
	var h: float = _alt[k]
	match layer:
		0:
			if h < params.land_height:
				return Color(0.1, 0.25, 0.6).lerp(Color(0.3, 0.55, 0.85), clampf((h + 4.0) / 4.0, 0.0, 1.0))
			var t: float = clampf(h / _alt_max, 0.0, 1.0)
			if t < 0.5:
				return Color(0.35, 0.7, 0.3).lerp(Color(0.75, 0.65, 0.3), t * 2.0)
			return Color(0.75, 0.65, 0.3).lerp(Color(0.95, 0.95, 0.95), (t - 0.5) * 2.0)
		1:
			if h < params.land_height:
				return Color(0.1, 0.2, 0.4)
			var s: float = clampf(_slope[k] / 60.0, 0.0, 1.0)
			var c: Color = Color(0.2, 0.7, 0.3).lerp(Color(0.95, 0.85, 0.2), clampf(s * 2.0, 0.0, 1.0))
			if _slope[k] >= params.steep_degrees:
				c = Color(0.85, 0.2, 0.15)
			return c
		2:
			if h < params.land_height:
				return Color(0.1, 0.2, 0.4)
			var d: float = clampf(_coast[k] / _coast_max, 0.0, 1.0)
			return Color(0.95, 0.9, 0.5).lerp(Color(0.1, 0.45, 0.2), d)
		3:
			if h < params.land_height:
				return Color(0.1, 0.2, 0.4)
			return Color(0.2, 0.6, 0.95).lerp(Color(0.85, 0.75, 0.4), clampf(_agua[k] / _agua_max, 0.0, 1.0))
		4:
			if h < params.land_height:
				return Color(0.1, 0.2, 0.4)
			return Color(0.8, 0.55, 0.2).lerp(Color(0.15, 0.4, 0.95), _hum[k])
		5:
			if h < params.land_height:
				return Color(0.1, 0.2, 0.4)
			return SUELO_COLORS[_suelo[k]]
		6:
			if h < params.land_height:
				return Color(0.1, 0.2, 0.4)
			return BIOMA_COLORS[_bioma[k]]
		7:
			if h < params.land_height:
				return Color(0.1, 0.2, 0.4)
			return Color(0.15, 0.3, 0.15).lerp(Color(0.8, 0.3, 0.95), _mist[k])
	return Color.MAGENTA

func layer_legend(layer: int) -> String:
	match layer:
		0: return "Altura: azul = agua, verde = bajo, ocre = medio, blanco = cima (máx %.1f m)" % _alt_max
		1: return "Pendiente: verde = suave, amarillo = media, rojo = roquedal (> %d°)" % int(params.steep_degrees)
		2: return "Distancia a la costa: amarillo = orilla, verde oscuro = interior (máx %d m)" % int(_coast_max)
		3: return "Distancia al agua (mar o laguna): azul = junto al agua, ocre = lejos (máx %d m)" % int(_agua_max)
		4: return "Humedad: azul = húmedo, marrón = seco"
		5: return "Suelo: amarillo = arena, gris = roca, verde = fértil, marrón = seco"
		7: return "Zonas misteriosas: violeta = claro misterioso (%d zonas)" % mystery_centers.size()
		6: return "Bioma: amarillo = costa, gris = roquedal, verde oscuro = selva, verde = bosque, lima = matorral, naranja = árido"
	return ""
