class_name IslandRiver
extends RefCounted

## Río fino: nace en el estanque, baja por lo más bajo del terreno y desemboca en el mar.
## Se calcula una sola vez al arrancar: trazado (A* por celdas de 2 m, prefiere terreno bajo), nivel del agua que
## solo baja, y un mapa fino (0,5 m) con la distancia al eje del río para cavar el cauce en la altura del terreno.

const CELL: float = 0.5
const HALF_W: float = 2.0          ## semiancho del lecho plano
const BANK: float = 4.6            ## hasta dónde el cauce modifica la tierra
const DEPTH: float = 0.8          ## profundidad del lecho bajo el nivel del agua
const OX: float = -142.0
const OZ: float = -202.0
const NX: int = 570
const NZ: int = 810

var pts: PackedVector2Array = PackedVector2Array()     ## eje del río (cada ~1 m), de la fuente a la boca
var wl: PackedFloat32Array = PackedFloat32Array()      ## nivel del agua en cada punto
var _dist: PackedFloat32Array = PackedFloat32Array()
var _lvl: PackedFloat32Array = PackedFloat32Array()
var valid: bool = false

## `t`: terreno (usa su altura base sin río). `pond_level`: nivel del estanque (el río arranca a esa altura).
func build(t: IslandTerrain, pond_level: float) -> void:
	var step: float = 2.0
	var gx0: float = -134.0
	var gz0: float = -196.0
	var nx: int = 135
	var nz: int = 197
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(nx * nz)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, nx, nz)
	astar.cell_size = Vector2(step, step)
	astar.offset = Vector2(gx0, gz0)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.update()
	var pc: Vector2 = IslandTerrain.POND_CENTER
	var best_goal: Vector2i = Vector2i(-1, -1)
	var best_d: float = 1.0e9
	for j in nz:
		for i in nx:
			var x: float = gx0 + float(i) * step
			var z: float = gz0 + float(j) * step
			var h: float = t.base_height_public(x, z)
			heights[j * nx + i] = h
			var w: float = 1.0 + 1.8 * maxf(0.0, h - pond_level) + (6.0 if t.is_in_cave_area(x, z, 1.1) else 0.0)
			if h < 0.35:
				w = 0.6
			astar.set_point_weight_scale(Vector2i(i, j), w)
			if h > 0.1 and h < 0.55:
				var dd: float = Vector2(x, z).distance_to(pc)
				if dd < best_d and dd > 20.0:
					best_d = dd
					best_goal = Vector2i(i, j)
	if best_goal.x < 0:
		return
	var goal_w: Vector2 = Vector2(gx0 + float(best_goal.x) * step, gz0 + float(best_goal.y) * step)
	var start_w: Vector2 = pc + (goal_w - pc).normalized() * (IslandTerrain.POND_RADIUS * 1.6 * 0.85)
	var si: Vector2i = Vector2i(clampi(roundi((start_w.x - gx0) / step), 0, nx - 1), clampi(roundi((start_w.y - gz0) / step), 0, nz - 1))
	var raw: PackedVector2Array = astar.get_point_path(si, best_goal)
	if raw.size() < 6:
		return
	# recorta en la costa y suaviza (Chaikin) para que no haya esquinas
	var cut: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in raw:
		cut.append(p)
		if t.base_height_public(p.x, p.y) < 0.3 and cut.size() > 8:
			break
	cut.insert(0, start_w)
	for it in 3:
		var nxt: PackedVector2Array = PackedVector2Array()
		nxt.append(cut[0])
		for k in cut.size() - 1:
			nxt.append(cut[k] * 0.75 + cut[k + 1] * 0.25)
			nxt.append(cut[k] * 0.25 + cut[k + 1] * 0.75)
		nxt.append(cut[cut.size() - 1])
		cut = nxt
	# remuestreo a ~1 m
	pts = _resample(cut, 1.0)
	# se prolonga 3 m hacia el mar para que desemboque limpio
	var last: Vector2 = pts[pts.size() - 1]
	var dir_end: Vector2 = (last - pts[maxi(pts.size() - 4, 0)]).normalized()
	for k in 3:
		pts.append(last + dir_end * float(k + 1))
	wl.resize(pts.size())
	var cur: float = pond_level
	for k in pts.size():
		var hh: float = t.base_height_public(pts[k].x, pts[k].y)
		cur = minf(cur - 0.004, hh - 0.14)
		cur = maxf(cur, 0.12)
		wl[k] = cur
	for k in range(1, wl.size()):         # nunca sube
		wl[k] = minf(wl[k], wl[k - 1])
	_rasterize()
	valid = true

func _resample(poly: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array([poly[0]])
	var carry: float = 0.0
	for k in poly.size() - 1:
		var a: Vector2 = poly[k]
		var b: Vector2 = poly[k + 1]
		var seg: float = a.distance_to(b)
		var d: float = spacing - carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			d += spacing
		carry = seg - (d - spacing)
	return out

func _rasterize() -> void:
	_dist.resize(NX * NZ)
	_lvl.resize(NX * NZ)
	_dist.fill(BANK + 1.0)
	_lvl.fill(-99.0)
	var rr: int = int(ceil((BANK + 0.6) / CELL))
	# muestras cada 0,35 m interpolando entre puntos del eje
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		for s in 3:
			var f: float = float(s) / 3.0
			var p: Vector2 = a.lerp(b, f)
			var lv: float = lerpf(wl[k], wl[k + 1], f)
			var cx: int = int((p.x - OX) / CELL)
			var cy: int = int((p.y - OZ) / CELL)
			for dy in range(-rr, rr + 1):
				for dx in range(-rr, rr + 1):
					var ix: int = cx + dx
					var iy: int = cy + dy
					if ix < 0 or iy < 0 or ix >= NX or iy >= NZ:
						continue
					var q: Vector2 = Vector2(OX + (float(ix) + 0.5) * CELL, OZ + (float(iy) + 0.5) * CELL)
					var d: float = q.distance_to(p)
					var idx: int = iy * NX + ix
					if d < _dist[idx]:
						_dist[idx] = d
						_lvl[idx] = lv

## Distancia al eje del río (m) en (x, z); mayor que BANK = lejos.
func dist_at(x: float, z: float) -> float:
	if not valid:
		return 99.0
	var ix: int = int((x - OX) / CELL)
	var iy: int = int((z - OZ) / CELL)
	if ix < 0 or iy < 0 or ix >= NX or iy >= NZ:
		return 99.0
	return _dist[iy * NX + ix]

## Cava el cauce: devuelve la altura `h` ya modificada por el río (solo baja la tierra).
func carve(x: float, z: float, h: float) -> float:
	if not valid:
		return h
	var fx: float = (x - OX) / CELL - 0.5
	var fz: float = (z - OZ) / CELL - 0.5
	var ix: int = floori(fx)
	var iy: int = floori(fz)
	if ix < 0 or iy < 0 or ix >= NX - 1 or iy >= NZ - 1:
		return h
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iy)
	var k0: int = iy * NX + ix
	var d: float = lerpf(lerpf(_dist[k0], _dist[k0 + 1], tx), lerpf(_dist[k0 + NX], _dist[k0 + NX + 1], tx), tz)
	if d >= BANK:
		return h
	var near_i: int = (iy + (1 if tz > 0.5 else 0)) * NX + ix + (1 if tx > 0.5 else 0)
	var lv: float = _lvl[near_i]
	if lv < -50.0:
		return h
	var bed: float = lv - DEPTH
	var target: float
	if d < HALF_W:
		target = bed + 0.12 * (d / HALF_W) * (d / HALF_W)
	else:
		target = bed + 0.12 + (d - HALF_W) * 0.6
	if target >= h:
		return h
	var wgt: float = 1.0 - smoothstep(BANK - 1.1, BANK, d)
	return h - (h - target) * wgt
