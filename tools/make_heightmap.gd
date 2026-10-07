extends SceneTree

## Genera res://assets/terrain/island_height.res (Image RF, metros) a partir de la silueta de islarefe.jpg.
## Resolución de trabajo: 375x550 (mitad de la referencia). 1 px = 0.714 m.

const W: int = 375
const H: int = 550
const M_PER_PX: float = 0.714

func _init() -> void:
	var src: Image = Image.load_from_file("res://docs/ref/islarefe.jpg")
	src.resize(W, H, Image.INTERPOLATE_BILINEAR)
	var land: PackedByteArray = PackedByteArray()
	land.resize(W * H)
	for y in H:
		for x in W:
			var c: Color = src.get_pixel(x, y)
			var r: float = c.r * 255.0
			var g: float = c.g * 255.0
			var b: float = c.b * 255.0
			var l: bool = (g - b > 10.0) or (r - b > 14.0) or (r > 150.0 and g > 150.0 and b > 140.0 and y > 75)
			land[y * W + x] = 1 if l else 0
	for y in H:
		for x in W:
			if x < 10 or y < 10 or x > W - 10 or y > H - 10:
				land[y * W + x] = 0
	land = _close(land, 3)
	land = _fill_holes(land)
	land = _largest(land)
	land = _close(land, 2)
	land = _smooth_mask(land, 2)
	# --- rasgos de costa: [tipo, centro en metros]. Se pegan a la costa más cercana.
	var feats: Array = [["beach", Vector2(100.0, 38.0)], ["dune", Vector2(98.0, -85.0)], ["dune", Vector2(-40.0, -165.0)], ["cove", Vector2(-100.0, -60.0)], ["cove", Vector2(25.0, 50.0)]]
	var d_first: PackedFloat32Array = _distance(land)
	var fpos: Array[Vector2] = []
	for f: Array in feats:
		var cm: Vector2 = f[1]
		var cpx: Vector2 = Vector2(cm.x / M_PER_PX + float(W) * 0.5, cm.y / M_PER_PX + float(H) * 0.5)
		var bestp: Vector2 = cpx
		var bestd: float = 1.0e9
		for yy in range(maxi(int(cpx.y) - 45, 2), mini(int(cpx.y) + 45, H - 2)):
			for xx in range(maxi(int(cpx.x) - 45, 2), mini(int(cpx.x) + 45, W - 2)):
				var ii: int = yy * W + xx
				if land[ii] == 1 and d_first[ii] <= 1.5:
					var dd: float = Vector2(xx, yy).distance_to(cpx)
					if dd < bestd:
						bestd = dd
						bestp = Vector2(xx, yy)
		fpos.append(bestp)
		if f[0] == "cove":
			var acc: Vector2 = Vector2.ZERO
			var cnt: int = 0
			for yy in range(int(bestp.y) - 26, int(bestp.y) + 27):
				for xx in range(int(bestp.x) - 26, int(bestp.x) + 27):
					if xx >= 0 and yy >= 0 and xx < W and yy < H and land[yy * W + xx] == 1:
						acc += Vector2(xx, yy) - bestp
						cnt += 1
			var inward: Vector2 = (acc / maxf(float(cnt), 1.0)).normalized()
			var bite: Vector2 = bestp + inward * 9.0
			for yy in range(int(bite.y) - 20, int(bite.y) + 21):
				for xx in range(int(bite.x) - 20, int(bite.x) + 21):
					if xx >= 0 and yy >= 0 and xx < W and yy < H:
						var rr: float = Vector2(xx, yy).distance_to(bite)
						if rr < 17.0 + 3.0 * sin(float(xx) * 0.7 + float(yy) * 0.5):
							land[yy * W + xx] = 0
	land = _largest(land)
	# distancia a la costa (px) hacia adentro
	var dist: PackedFloat32Array = _distance(land)
	var inv: PackedByteArray = land.duplicate()
	for q in inv.size():
		inv[q] = 1 - inv[q]
	var dout: PackedFloat32Array = _distance(inv)
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var n2 := FastNoiseLite.new()
	n2.seed = 77
	n2.frequency = 0.07
	var dn := FastNoiseLite.new()
	dn.seed = 5
	dn.frequency = 0.045
	var spine: Array[Vector2] = [Vector2(60, 75), Vector2(37, 150), Vector2(75, 215), Vector2(117, 260), Vector2(125, 350), Vector2(112, 425), Vector2(120, 500)]
	var img := Image.create(W, H, false, Image.FORMAT_RF)
	var prev: Image = Image.create(W, H, false, Image.FORMAT_L8)
	var hmax: float = 0.0
	for y in H:
		for x in W:
			var i: int = y * W + x
			if land[i] == 0:
				img.set_pixel(x, y, Color(maxf(-0.3 - dout[i] * M_PER_PX * 0.3, -4.5), 0, 0))
				continue
			var dm: float = dist[i] * M_PER_PX
			# playa baja que sube suave y luego el interior
			var base: float = 0.0
			base = 1.45 * smoothstep(0.0, 7.0, dm)
			base += 4.0 * smoothstep(6.0, 60.0, dm)
			base += 2.0 * smoothstep(40.0, 110.0, dm)
			var nv: float = noise.get_noise_2d(float(x), float(y))
			var nd: float = n2.get_noise_2d(float(x), float(y))
			base += nv * 2.6 * smoothstep(5.0, 40.0, dm) + nd * 0.5 * smoothstep(8.0, 30.0, dm)
			# rasgos de costa: playa grande, médanos y calas escalonadas
			for fi in feats.size():
				var fk: float = 1.0 - smoothstep(30.0, 62.0, Vector2(x, y).distance_to(fpos[fi]) * M_PER_PX)
				if fk <= 0.0:
					continue
				var kind: String = feats[fi][0]
				var target: float = base
				if kind == "beach":
					target = lerpf(0.45 + 0.95 * smoothstep(0.0, 32.0, dm), base, smoothstep(26.0, 62.0, dm))
				elif kind == "dune":
					var rv: float = 1.0 - absf(dn.get_noise_2d(float(x) * 0.8, float(y) * 2.2))
					var dh: float = 0.5 + 0.8 * smoothstep(0.0, 6.0, dm) + 1.7 * rv * rv * smoothstep(4.0, 14.0, dm) * (1.0 - smoothstep(26.0, 38.0, dm))
					target = lerpf(dh, base, smoothstep(30.0, 60.0, dm))
				else:
					var sv: float = (dm + dn.get_noise_2d(float(x) * 1.5, float(y) * 1.5) * 1.6) / 5.0
					var stepped: float = floorf(sv) + smoothstep(0.65, 1.0, sv - floorf(sv))
					target = lerpf(0.45 + maxf(stepped, 0.0) * 0.55, base, smoothstep(28.0, 50.0, dm))
				base = lerpf(base, target, fk)
			# cordillera al oeste (acantilado rocoso)
			var dsp: float = 1.0e9
			for k in spine.size() - 1:
				dsp = minf(dsp, _seg_dist(Vector2(x, y), spine[k], spine[k + 1]))
			var ridge: float = 1.0 - smoothstep(6.0, 34.0, dsp)
			var ridge_h: float = ridge * (7.0 + 5.0 * (0.5 + 0.5 * noise.get_noise_2d(float(x) * 1.7 + 50.0, float(y) * 1.7)))
			base += ridge_h * smoothstep(2.0, 14.0, dm)
			# valle central un poco más bajo en la selva
			hmax = maxf(hmax, base)
			img.set_pixel(x, y, Color(base, 0, 0))
			prev.set_pixel(x, y, Color(base / 22.0, 0, 0))
	DirAccess.make_dir_recursive_absolute("res://assets/terrain")
	ResourceSaver.save(img, "res://assets/terrain/island_height.res")
	prev.save_png("res://assets/terrain/height_preview.png")
	var mk := Image.create(W, H, false, Image.FORMAT_L8)
	for y in H:
		for x in W:
			mk.set_pixel(x, y, Color(1, 1, 1) if land[y * W + x] == 1 else Color(0, 0, 0))
	mk.save_png("res://assets/terrain/mask_clean.png")
	print("hmax ", hmax)
	quit()

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _close(m: PackedByteArray, r: int) -> PackedByteArray:
	return _erode(_dilate(m, r), r)

func _dilate(m: PackedByteArray, r: int) -> PackedByteArray:
	var t: PackedByteArray = m.duplicate()
	for y in H:
		for x in W:
			var v: int = 0
			for dx in range(-r, r + 1):
				var xx: int = x + dx
				if xx >= 0 and xx < W and m[y * W + xx] == 1:
					v = 1
					break
			t[y * W + x] = v
	var o: PackedByteArray = t.duplicate()
	for y in H:
		for x in W:
			var v: int = 0
			for dy in range(-r, r + 1):
				var yy: int = y + dy
				if yy >= 0 and yy < H and t[yy * W + x] == 1:
					v = 1
					break
			o[y * W + x] = v
	return o

func _erode(m: PackedByteArray, r: int) -> PackedByteArray:
	var inv: PackedByteArray = m.duplicate()
	for i in inv.size():
		inv[i] = 1 - inv[i]
	var d: PackedByteArray = _dilate(inv, r)
	for i in d.size():
		d[i] = 1 - d[i]
	return d

func _fill_holes(m: PackedByteArray) -> PackedByteArray:
	var water: PackedByteArray = PackedByteArray()
	water.resize(W * H)
	var stack: Array[int] = []
	for x in W:
		stack.append(x)
		stack.append((H - 1) * W + x)
	for y in H:
		stack.append(y * W)
		stack.append(y * W + W - 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if water[i] == 1 or m[i] == 1:
			continue
		water[i] = 1
		var x: int = i % W
		var y: int = i / W
		if x > 0: stack.append(i - 1)
		if x < W - 1: stack.append(i + 1)
		if y > 0: stack.append(i - W)
		if y < H - 1: stack.append(i + W)
	var o: PackedByteArray = m.duplicate()
	for i in o.size():
		o[i] = 0 if water[i] == 1 else 1
	return o

func _largest(m: PackedByteArray) -> PackedByteArray:
	var lab: PackedInt32Array = PackedInt32Array()
	lab.resize(W * H)
	var best: int = 0
	var best_n: int = 0
	var cur: int = 0
	for s in W * H:
		if m[s] == 0 or lab[s] != 0:
			continue
		cur += 1
		var n: int = 0
		var stack: Array[int] = [s]
		lab[s] = cur
		while not stack.is_empty():
			var i: int = stack.pop_back()
			n += 1
			var x: int = i % W
			var y: int = i / W
			for nb: int in [i - 1 if x > 0 else -1, i + 1 if x < W - 1 else -1, i - W if y > 0 else -1, i + W if y < H - 1 else -1]:
				if nb >= 0 and m[nb] == 1 and lab[nb] == 0:
					lab[nb] = cur
					stack.append(nb)
		if n > best_n:
			best_n = n
			best = cur
	var o: PackedByteArray = m.duplicate()
	for i in o.size():
		o[i] = 1 if lab[i] == best else 0
	return o

func _smooth_mask(m: PackedByteArray, r: int) -> PackedByteArray:
	var o: PackedByteArray = m.duplicate()
	for y in range(r, H - r):
		for x in range(r, W - r):
			var s: int = 0
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					s += m[(y + dy) * W + x + dx]
			o[y * W + x] = 1 if s * 2 > (2 * r + 1) * (2 * r + 1) else 0
	return o

## distancia chamfer (px) de cada píxel de tierra al agua más cercana
func _distance(m: PackedByteArray) -> PackedFloat32Array:
	var d: PackedFloat32Array = PackedFloat32Array()
	d.resize(W * H)
	for i in d.size():
		d[i] = 0.0 if m[i] == 0 else 1.0e6
	for y in H:
		for x in W:
			var i: int = y * W + x
			if d[i] == 0.0:
				continue
			var v: float = d[i]
			if x > 0: v = minf(v, d[i - 1] + 1.0)
			if y > 0:
				v = minf(v, d[i - W] + 1.0)
				if x > 0: v = minf(v, d[i - W - 1] + 1.414)
				if x < W - 1: v = minf(v, d[i - W + 1] + 1.414)
			d[i] = v
	for y in range(H - 1, -1, -1):
		for x in range(W - 1, -1, -1):
			var i: int = y * W + x
			if d[i] == 0.0:
				continue
			var v: float = d[i]
			if x < W - 1: v = minf(v, d[i + 1] + 1.0)
			if y < H - 1:
				v = minf(v, d[i + W] + 1.0)
				if x < W - 1: v = minf(v, d[i + W + 1] + 1.414)
				if x > 0: v = minf(v, d[i + W - 1] + 1.414)
			d[i] = v
	return d
