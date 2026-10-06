class_name SoundBank
extends RefCounted

## Sintetizador de sonidos 100% por código (sin archivos de audio).
## Todas las funciones son estáticas y no tocan el árbol de escenas: se pueden ejecutar en un hilo.

const SR_LO: int = 11025
const SR_MID: int = 16000
const SR_HI: int = 22050

class Buf:
	var d: PackedFloat32Array = PackedFloat32Array()
	var sr: int = 22050
	func _init(seconds: float, rate: int) -> void:
		sr = rate
		d.resize(int(seconds * float(rate)))

# ------------------------------------------------------------------ utilidades

static func _wav(data: PackedFloat32Array, rate: int, loop: bool = false, peak: float = 0.85) -> AudioStreamWAV:
	var m: float = 0.0001
	for v: float in data:
		m = maxf(m, absf(v))
	var g: float = peak / m
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, clampi(int(data[i] * g * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = data.size()
	return s

## Hace que el final enlace con el principio (crossfade) para loops sin costura.
static func _loopify(src: PackedFloat32Array, n: int, fade: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = src[i]
	for i in fade:
		var k: float = float(i) / float(fade)
		out[i] = src[i] * k + src[n + i] * (1.0 - k)
	return out

static func _alpha(fc: float, sr: int) -> float:
	return 1.0 - exp(-TAU * fc / float(sr))

## Tono con barrido de frecuencia y decaimiento.
static func _tone(b: Buf, t0: float, dur: float, f0: float, f1: float, amp: float, attack: float = 0.01, harm2: float = 0.0, decay_pow: float = 1.5) -> void:
	var i0: int = int(t0 * float(b.sr))
	var n: int = int(dur * float(b.sr))
	var ph: float = 0.0
	var att: float = maxf(attack * float(b.sr), 1.0)
	for k in n:
		var i: int = i0 + k
		if i >= b.d.size():
			break
		var u: float = float(k) / float(n)
		ph += TAU * lerpf(f0, f1, u) / float(b.sr)
		var env: float = minf(float(k) / att, 1.0) * pow(1.0 - u, decay_pow)
		b.d[i] += (sin(ph) + harm2 * sin(2.0 * ph)) * env * amp

## Ráfaga corta de ruido filtrado (granos de crujido, salpicaduras...).
static func _grain(b: Buf, t0: float, dur: float, cutoff: float, amp: float, rng: RandomNumberGenerator, decay: float = 4.0) -> void:
	var i0: int = int(t0 * float(b.sr))
	var n: int = int(dur * float(b.sr))
	var a: float = _alpha(cutoff, b.sr)
	var y: float = 0.0
	for k in n:
		var i: int = i0 + k
		if i >= b.d.size():
			break
		var u: float = float(k) / float(n)
		y += a * ((rng.randf() * 2.0 - 1.0) - y)
		b.d[i] += y * amp * exp(-u * decay)

# ------------------------------------------------------------------ ambientes en loop

static func waves() -> AudioStreamWAV:
	var sr: int = SR_LO
	var L: float = 22.0
	var n: int = int(L * float(sr))
	var fade: int = int(float(sr) * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var y1: float = 0.0
	var y2: float = 0.0
	for i in n + fade:
		var t: float = float(i) / float(sr)
		var s1: float = 0.5 + 0.5 * sin(TAU * t / (L / 2.0) + 0.3)
		var s2: float = 0.5 + 0.5 * sin(TAU * t / (L / 3.0) + 1.7)
		var swell: float = s1 * s1 * 0.6 + s2 * s2 * 0.4
		var a: float = _alpha(lerpf(250.0, 2400.0, swell), sr)
		y1 += a * ((rng.randf() * 2.0 - 1.0) - y1)
		y2 += a * (y1 - y2)
		raw[i] = y2 * (0.12 + 0.88 * swell)
	return _wav(_loopify(raw, n, fade), sr, true)

static func wind(night: bool) -> AudioStreamWAV:
	var sr: int = SR_LO
	var L: float = 16.0
	var n: int = int(L * float(sr))
	var fade: int = int(float(sr) * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23 if night else 22
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var y1: float = 0.0
	var y2: float = 0.0
	var ph: float = 0.0
	for i in n + fade:
		var t: float = float(i) / float(sr)
		var g1: float = 0.5 + 0.5 * sin(TAU * t / (L / 2.0) + 0.9)
		var g2: float = 0.5 + 0.5 * sin(TAU * t / (L / 5.0) + 0.2)
		var gust: float = 0.35 + 0.65 * g1 * (0.6 + 0.4 * g2)
		var a: float = _alpha((260.0 if night else 420.0) + 500.0 * gust, sr)
		y1 += a * ((rng.randf() * 2.0 - 1.0) - y1)
		y2 += a * (y1 - y2)
		var f: float = (520.0 + 200.0 * sin(TAU * t * 2.0 / L)) if night else (780.0 + 120.0 * sin(TAU * t * 3.0 / L))
		ph += TAU * f / float(sr)
		var whistle: float = sin(ph) * 0.05 * gust * gust * (1.6 if night else 1.0)
		raw[i] = y2 * gust * 3.0 + whistle
	return _wav(_loopify(raw, n, fade), sr, true)

static func rustle() -> AudioStreamWAV:
	var sr: int = SR_LO
	var L: float = 10.0
	var n: int = int(L * float(sr))
	var fade: int = int(float(sr) * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var lp: float = 0.0
	var lp2: float = 0.0
	var a1: float = _alpha(1800.0, sr)
	var a2: float = _alpha(5200.0, sr)
	for i in n + fade:
		var t: float = float(i) / float(sr)
		var x: float = rng.randf() * 2.0 - 1.0
		lp += a1 * (x - lp)
		var hp: float = x - lp
		lp2 += a2 * (hp - lp2)
		var e1: float = 0.5 + 0.5 * sin(TAU * t * 3.0 / L + 0.4)
		var e2: float = 0.5 + 0.5 * sin(TAU * t * 7.0 / L + 2.1)
		raw[i] = lp2 * (0.1 + 0.9 * e1 * e1 * e2)
	return _wav(_loopify(raw, n, fade), sr, true, 0.7)

static func crickets() -> AudioStreamWAV:
	var sr: int = SR_MID
	var L: float = 8.0
	var fade: int = int(float(sr) * 0.5)
	var b := Buf.new(L + 0.5, sr)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for v in 5:
		var f: float = rng.randf_range(3900.0, 4600.0)
		var t: float = rng.randf() * 0.4
		while t < L + 0.4:
			var pulses: int = rng.randi_range(3, 4)
			for p in pulses:
				_tone(b, t + float(p) * 0.022, 0.016, f, f, 0.1, 0.002, 0.0, 1.2)
			t += rng.randf_range(0.28, 0.55)
	return _wav(_loopify(b.d, int(L * float(sr)), fade), sr, true, 0.6)

static func drone() -> AudioStreamWAV:
	var sr: int = SR_LO
	var L: float = 16.0
	var n: int = int(L * float(sr))
	var raw := PackedFloat32Array()
	raw.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var y: float = 0.0
	var a: float = _alpha(120.0, sr)
	for i in n:
		var t: float = float(i) / float(sr)
		y += a * ((rng.randf() * 2.0 - 1.0) - y)
		raw[i] = 0.5 * sin(TAU * 55.0 * t) + 0.5 * sin(TAU * 55.75 * t) \
			+ 0.25 * sin(TAU * 82.5 * t) * (0.6 + 0.4 * sin(TAU * t / 8.0)) \
			+ 0.3 * sin(TAU * 27.5 * t) + y * 1.2
	return _wav(raw, sr, true, 0.7)

static func cave_hum() -> AudioStreamWAV:
	var sr: int = SR_LO
	var L: float = 12.0
	var n: int = int(L * float(sr))
	var raw := PackedFloat32Array()
	raw.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var y: float = 0.0
	var a: float = _alpha(180.0, sr)
	for i in n:
		var t: float = float(i) / float(sr)
		y += a * ((rng.randf() * 2.0 - 1.0) - y)
		raw[i] = (0.5 * sin(TAU * 62.0 * t) + 0.35 * sin(TAU * 93.0 * t)) * (0.7 + 0.3 * sin(TAU * t / 6.0)) + y * 0.8
	return _wav(raw, sr, true, 0.6)

static func pond() -> AudioStreamWAV:
	var sr: int = SR_LO
	var L: float = 8.0
	var fade: int = int(float(sr) * 0.5)
	var b := Buf.new(L + 0.5, sr)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var y: float = 0.0
	var a: float = _alpha(900.0, sr)
	for i in b.d.size():
		y += a * ((rng.randf() * 2.0 - 1.0) - y)
		b.d[i] = y * 0.18 * (0.7 + 0.3 * sin(TAU * float(i) / float(sr) * 0.5))
	for k in 30:
		var f: float = rng.randf_range(500.0, 1300.0)
		_tone(b, rng.randf() * L, rng.randf_range(0.04, 0.09), f, f * 1.6, rng.randf_range(0.1, 0.3), 0.004, 0.0, 2.0)
	return _wav(_loopify(b.d, int(L * float(sr)), fade), sr, true, 0.6)

# ------------------------------------------------------------------ pasos

static func step(kind: String, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 97 + kind.hash() % 1000
	var b := Buf.new(0.45, SR_HI)
	match kind:
		"sand":
			_tone(b, 0.0, 0.06, 110.0, 70.0, 0.22, 0.004)
			for i in 11:
				_grain(b, rng.randf() * 0.15, rng.randf_range(0.008, 0.02), rng.randf_range(2500.0, 4200.0), rng.randf_range(0.2, 0.45), rng, 3.0)
		"grass":
			var a: float = _alpha(4200.0, b.sr)
			var a0: float = _alpha(1400.0, b.sr)
			var y: float = 0.0
			var y0: float = 0.0
			var n: int = int(0.24 * float(b.sr))
			for i in n:
				var u: float = float(i) / float(n)
				var x: float = rng.randf() * 2.0 - 1.0
				y0 += a0 * (x - y0)
				y += a * ((x - y0) - y)
				var env: float = pow(sin(PI * pow(u, 0.7)), 2.0)
				b.d[i] += y * env * 0.7
			_tone(b, 0.0, 0.05, 90.0, 60.0, 0.12, 0.004)
			for i in 3:
				_grain(b, rng.randf() * 0.18, 0.004, 6000.0, 0.15, rng, 2.0)
		"water":
			_grain(b, 0.0, 0.3, 2800.0, 0.9, rng, 5.0)
			_grain(b, 0.0, 0.18, 900.0, 0.8, rng, 3.5)
			for i in 3:
				var f: float = rng.randf_range(450.0, 900.0)
				_tone(b, 0.02 + rng.randf() * 0.18, rng.randf_range(0.04, 0.09), f, f * 2.0, 0.25, 0.004, 0.0, 2.0)
		"stone":
			_grain(b, 0.0, 0.01, 5200.0, 0.9, rng, 2.5)
			_tone(b, 0.0, 0.1, 150.0, 90.0, 0.7, 0.002)
			_tone(b, 0.0, 0.05, 820.0, 700.0, 0.2, 0.002, 0.0, 2.5)
		"wood":
			_tone(b, 0.0, 0.1, 120.0, 80.0, 0.7, 0.004)
			_grain(b, 0.0, 0.05, 700.0, 0.4, rng, 5.0)
	return _wav(b.d, SR_HI, false, 0.8)

# ------------------------------------------------------------------ fauna

static func bird(seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 131 + 7
	var b := Buf.new(1.8, SR_HI)
	var t: float = 0.05
	var base: float = rng.randf_range(2300.0, 4200.0)
	var style: int = seed_value % 3
	for k in rng.randi_range(4, 9):
		var f0: float
		var f1: float
		var dur: float
		var gap: float
		match style:
			0:
				f0 = base * (1.0 + 0.03 * float(k))
				f1 = f0 * 1.25
				dur = 0.05
				gap = rng.randf_range(0.02, 0.04)
			1:
				f0 = base * pow(1.1, float(k))
				f1 = f0 * 1.1
				dur = 0.09
				gap = rng.randf_range(0.04, 0.08)
			_:
				f0 = base * rng.randf_range(0.8, 1.4)
				f1 = f0 * rng.randf_range(0.7, 1.4)
				dur = rng.randf_range(0.05, 0.12)
				gap = rng.randf_range(0.03, 0.08)
		_tone(b, t, dur, f0, f1, 0.5, 0.008, 0.25, 1.2)
		t += dur + gap
	return _wav(b.d, SR_HI, false, 0.7)

static func _gull_call(b: Buf, t0: float, dur: float, f0: float, f1: float, rng: RandomNumberGenerator) -> void:
	var i0: int = int(t0 * float(b.sr))
	var n: int = int(dur * float(b.sr))
	var ph: float = 0.0
	var weights: Array[float] = [1.0, 0.7, 0.5, 0.3, 0.15]
	for k in n:
		var i: int = i0 + k
		if i >= b.d.size():
			break
		var u: float = float(k) / float(n)
		var f: float = lerpf(f0, f1, u) * (1.0 + 0.06 * sin(TAU * 28.0 * u * dur))
		ph += TAU * f / float(b.sr)
		var s: float = 0.0
		for h in 5:
			s += weights[h] * sin(ph * float(h + 1))
		var env: float = minf(u / 0.12, 1.0) * pow(1.0 - u, 1.3)
		b.d[i] += (s * 0.35 + (rng.randf() * 2.0 - 1.0) * 0.12) * env

static func gull(seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 211 + 3
	var b := Buf.new(2.4, SR_HI)
	var t: float = 0.05
	_gull_call(b, t, 0.28, rng.randf_range(750.0, 900.0), rng.randf_range(1400.0, 1600.0), rng)
	t += 0.34
	for k in rng.randi_range(2, 4):
		var dur: float = rng.randf_range(0.36, 0.55)
		_gull_call(b, t, dur, rng.randf_range(1000.0, 1300.0), rng.randf_range(680.0, 900.0), rng)
		t += dur + rng.randf_range(0.08, 0.16)
	return _wav(b.d, SR_HI, false, 0.7)

static func owl(seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 71 + 5
	var b := Buf.new(2.6, SR_MID)
	var base: float = rng.randf_range(320.0, 400.0)
	_tone(b, 0.05, 0.35, base, base * 0.97, 0.8, 0.08, 0.35, 0.8)
	_tone(b, 0.55, 0.28, base * 0.97, base * 0.94, 0.7, 0.08, 0.35, 0.8)
	_tone(b, 0.95, 0.28, base * 0.95, base * 0.92, 0.7, 0.08, 0.35, 0.8)
	_tone(b, 1.4, 0.85, base * 0.92, base * 0.82, 0.85, 0.1, 0.35, 0.9)
	return _wav(b.d, SR_MID, false, 0.6)

static func frog(seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 17 + 9
	var b := Buf.new(1.0, SR_MID)
	var f: float = rng.randf_range(190.0, 260.0)
	for g in 2:
		for p in rng.randi_range(4, 7):
			_tone(b, 0.05 + float(g) * 0.45 + float(p) * 0.045, 0.035, f * 1.3, f, 0.5, 0.004, 0.4, 1.2)
	return _wav(b.d, SR_MID, false, 0.55)

# ------------------------------------------------------------------ misterio de noche

static func pad(seed_value: int) -> AudioStreamWAV:
	var b := Buf.new(10.0, SR_LO)
	var chords: Array = [[196.0, 277.2, 98.0], [220.0, 233.1, 110.0], [174.6, 246.9, 87.3]]
	var ch: Array = chords[seed_value % 3]
	for k in b.d.size():
		var t: float = float(k) / float(b.sr)
		var u: float = t / 10.0
		var env: float = pow(sin(PI * u), 1.5)
		var s: float = 0.0
		for f: float in ch:
			s += sin(TAU * f * t + 0.5 * sin(TAU * 0.3 * t)) + 0.6 * sin(TAU * f * 1.004 * t)
		b.d[k] = s * env * 0.2
	return _wav(b.d, SR_LO, false, 0.5)

static func creak(seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 5 + 1
	var b := Buf.new(1.5, SR_HI)
	var ph: float = 0.0
	var base: float = rng.randf_range(80.0, 120.0)
	for k in b.d.size():
		var u: float = float(k) / float(b.d.size())
		var f: float = base * (1.0 - 0.3 * u) * (1.0 + 0.05 * sin(TAU * 3.0 * u * 1.5))
		ph += TAU * f / float(b.sr)
		var stick: float = fmod(u * 24.0, 1.0)                 # estira-y-afloja
		var s: float = 0.0
		for h in range(1, 13):
			var hf: float = float(h) * f
			s += sin(ph * float(h)) * exp(-pow((hf - 700.0) / 450.0, 2.0)) / float(h) * 3.0
		b.d[k] = s * (0.3 + 0.7 * stick) * pow(sin(PI * u), 0.8)
	return _wav(b.d, SR_HI, false, 0.55)

static func drip(seed_value: int) -> AudioStreamWAV:
	var b := Buf.new(0.9, SR_HI)
	var f: float = 1000.0 + 450.0 * float(seed_value % 4)
	_tone(b, 0.0, 0.2, f, f * 1.3, 0.8, 0.002, 0.0, 2.2)
	_tone(b, 0.2, 0.2, f, f * 1.3, 0.3, 0.002, 0.0, 2.2)
	_tone(b, 0.38, 0.2, f, f * 1.3, 0.12, 0.002, 0.0, 2.2)
	return _wav(b.d, SR_HI, false, 0.55)

# ------------------------------------------------------------------ eventos

static func heartbeat() -> AudioStreamWAV:
	var b := Buf.new(0.9, SR_LO)
	_tone(b, 0.0, 0.16, 62.0, 42.0, 0.9, 0.01, 0.0, 1.4)
	_tone(b, 0.3, 0.14, 55.0, 38.0, 0.7, 0.01, 0.0, 1.4)
	return _wav(b.d, SR_LO, false, 0.8)

static func boom() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var b := Buf.new(1.8, SR_HI)
	_tone(b, 0.0, 1.3, 95.0, 30.0, 1.0, 0.004, 0.2, 1.2)
	_grain(b, 0.0, 0.9, 380.0, 1.1, rng, 3.0)
	_grain(b, 0.0, 0.08, 4500.0, 0.6, rng, 6.0)
	return _wav(b.d, SR_HI, false, 0.9)

static func rumble() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 92
	var b := Buf.new(3.0, SR_LO)
	var a: float = _alpha(130.0, b.sr)
	var y: float = 0.0
	for i in b.d.size():
		var u: float = float(i) / float(b.d.size())
		y += a * ((rng.randf() * 2.0 - 1.0) - y)
		b.d[i] = (y * 2.2 + 0.4 * sin(TAU * 38.0 * float(i) / float(b.sr))) * pow(sin(PI * u), 1.2)
	return _wav(b.d, SR_LO, false, 0.8)

static func crack(seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 13 + 2
	var b := Buf.new(0.7, SR_HI)
	for i in 7:
		_grain(b, rng.randf() * 0.35, rng.randf_range(0.004, 0.02), rng.randf_range(2500.0, 6500.0), rng.randf_range(0.4, 0.9), rng, 3.0)
	_tone(b, 0.0, 0.18, 130.0, 60.0, 0.6, 0.003)
	return _wav(b.d, SR_HI, false, 0.8)
