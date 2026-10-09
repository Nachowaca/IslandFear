class_name AudioManager
extends Node

## Ambiente sonoro realista, todo sintetizado por código (ver sound_bank.gd):
##  - Capas continuas: olas (más fuertes cerca de la costa), viento (de día / de noche), hojas, grillos,
##    zumbido grave nocturno, laguna (3D) y zumbido de la cueva.
##  - Eventos aleatorios: pájaros y gaviotas de día; búho, ranas, crujidos y acordes misteriosos de noche.
##  - Pasos según el suelo: arena, pasto, agua (y piedra dentro de la cueva).
##  - La cueva apaga lo de afuera (filtro) y añade reverberación.
##  - La isla "se calla" cuando se enfurece (menos grillos y pájaros, más zumbido grave).
## F8: silenciar / activar.

const BUS_AMB: String = "Ambience"
const BUS_FX: String = "Fx"

@export var master_db: float = -3.0

var terrain: IslandTerrain
var features: IslandFeatures
var player: Castaway
var brain: IslandBrain
var weather: Weather

var _bank: Dictionary = {}               # id -> Array[AudioStreamWAV]
var _thread: Thread
var _beds: Dictionary = {}               # id -> AudioStreamPlayer
var _bed_vol: Dictionary = {}
var _pond_player: AudioStreamPlayer3D
var _timers: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _lowpass: AudioEffectLowPassFilter
var _reverb: AudioEffectReverb
var _cave: float = 0.0
var _night: float = 0.0
var _forest: float = 0.0
var _forest_timer: float = 0.0
var _active_3d: int = 0
var _close: float = 0.0   # 0 = lejos de la isla (navegando), 1 = en la isla
var _f8_was_down: bool = false

static func play(tree: SceneTree, id: String, pos: Vector3, db: float = 0.0) -> void:
	var m: Node = tree.get_first_node_in_group("audio")
	if m != null:
		(m as AudioManager).play_world(id, pos, db)

func _ready() -> void:
	add_to_group("audio")
	_rng.randomize()
	_setup_buses()
	if player != null:
		player.stepped.connect(_on_step)
	_thread = Thread.new()
	_thread.start(_generate)

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()

# ------------------------------------------------------------------ buses

func _setup_buses() -> void:
	AudioServer.set_bus_volume_db(0, master_db)
	for bus_name: String in [BUS_AMB, BUS_FX]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20500.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_AMB), _lowpass)
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.4
	_reverb.damping = 0.6
	_reverb.wet = 0.04
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_FX), _reverb)

# ------------------------------------------------------------------ síntesis en segundo plano

func _generate() -> void:
	_emit("waves", SoundBank.waves())
	_emit("wind", SoundBank.wind(false))
	_emit("rustle", SoundBank.rustle())
	for kind: String in ["sand", "grass", "water", "stone", "wood"]:
		for v in 4:
			_emit("step_" + kind, SoundBank.step(kind, v))
	for v in 6:
		_emit("bird", SoundBank.bird(v))
	for v in 4:
		_emit("gull", SoundBank.gull(v))
	_emit("pond", SoundBank.pond())
	_emit("wind_night", SoundBank.wind(true))
	_emit("crickets", SoundBank.crickets())
	_emit("drone", SoundBank.drone())
	_emit("cave_hum", SoundBank.cave_hum())
	_emit("rain", SoundBank.rain())
	for v in 3:
		_emit("owl", SoundBank.owl(v))
		_emit("frog", SoundBank.frog(v))
		_emit("pad", SoundBank.pad(v))
		_emit("creak", SoundBank.creak(v))
		_emit("crack", SoundBank.crack(v))
	for v in 4:
		_emit("drip", SoundBank.drip(v))
	_emit("heart", SoundBank.heartbeat())
	_emit("boom", SoundBank.boom())
	_emit("rumble", SoundBank.rumble())

func _emit(id: String, stream: AudioStreamWAV) -> void:
	call_deferred("_on_asset", id, stream)

func _on_asset(id: String, stream: AudioStreamWAV) -> void:
	if not _bank.has(id):
		_bank[id] = []
	(_bank[id] as Array).append(stream)
	match id:
		"waves", "wind", "wind_night", "rustle", "crickets", "drone", "cave_hum", "rain":
			var p := AudioStreamPlayer.new()
			p.bus = BUS_AMB
			p.stream = stream
			p.volume_db = -80.0
			add_child(p)
			p.play()
			_beds[id] = p
			_bed_vol[id] = 0.0
		"pond":
			if terrain != null:
				_pond_player = AudioStreamPlayer3D.new()
				_pond_player.bus = BUS_AMB
				_pond_player.stream = stream
				_pond_player.unit_size = 7.0
				_pond_player.max_distance = 50.0
				_pond_player.volume_db = -2.0
				_pond_player.position = Vector3(IslandTerrain.POND_CENTER.x, terrain.pond_water_level, IslandTerrain.POND_CENTER.y)
				add_child(_pond_player)
				_pond_player.play()

# ------------------------------------------------------------------ reproducción

func _pick(id: String) -> AudioStreamWAV:
	if not _bank.has(id):
		return null
	var arr: Array = _bank[id]
	if arr.is_empty():
		return null
	return arr[_rng.randi() % arr.size()]

func _play3d(id: String, pos: Vector3, db: float, pitch: float = 1.0, bus: String = BUS_FX, unit: float = 6.0, maxd: float = 90.0) -> void:
	var s: AudioStreamWAV = _pick(id)
	if s == null or _active_3d > 28:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = bus
	p.unit_size = unit
	p.max_distance = maxd
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.global_position = pos
	_active_3d += 1
	p.finished.connect(func() -> void:
		_active_3d -= 1
		p.queue_free())
	p.play()

func _play2d(id: String, db: float, bus: String = BUS_AMB) -> void:
	var s: AudioStreamWAV = _pick(id)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

## Sonidos del mundo disparados desde otros scripts (rocas, raíces, temblores).
func play_world(id: String, pos: Vector3, db: float = 0.0) -> void:
	_play3d(id, pos, db, _rng.randf_range(0.92, 1.08), BUS_FX, 14.0, 160.0)

func _on_step(surface: String, power: float) -> void:
	var p: Vector3 = player.global_position
	var s: String = surface
	if features != null and features.is_inside_cave(p):
		s = "stone"
	var vol: float = clampf(power / 8.0, 0.0, 1.4)
	var pitch: float = _rng.randf_range(0.9, 1.1) * (0.8 if power > 9.0 else 1.0)
	_play3d("step_" + s, p + Vector3(0, 0.1, 0), lerpf(-14.0, -3.0, clampf(vol, 0.0, 1.0)), pitch, BUS_FX, 3.0, 40.0)

# ------------------------------------------------------------------ mezcla

func _process(delta: float) -> void:
	var f8: bool = Input.is_physical_key_pressed(KEY_F8)
	if f8 and not _f8_was_down:
		AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
	_f8_was_down = f8
	if player == null or terrain == null:
		return

	var p: Vector3 = player.global_position
	var h: float = terrain.height_at(p.x, p.z)
	var dn: Node = get_tree().get_first_node_in_group("daynight")
	if dn != null:
		_night = dn.get("night_amount")
	var in_cave: bool = features != null and features.is_inside_cave(p)
	_cave = move_toward(_cave, 1.0 if in_cave else 0.0, delta * 1.5)
	var hostile: float = 0.0
	if brain != null:
		hostile = clampf(brain._effective_hostility() / 100.0, 0.0, 1.0)

	_forest_timer -= delta
	if _forest_timer <= 0.0:
		_forest_timer = 0.5
		var cnt: int = 0
		for tp: Vector3 in terrain.tree_positions:
			if Vector2(tp.x - p.x, tp.z - p.z).length() < 14.0:
				cnt += 1
		_forest = clampf(float(cnt) / 7.0, 0.0, 1.0)

	# a medida que la barca se acerca, los sonidos de la isla pasan de menos a más
	var dist_center: float = Vector2(p.x, p.z).length()
	var close: float = smoothstep(0.0, 1.0, 1.0 - clampf((dist_center - 55.0) / 75.0, 0.0, 1.0))
	var shore: float = clampf(1.0 - (h - 0.9) / 3.5, 0.15, 1.0)
	var exposure: float = clampf((h - 2.0) / 5.0, 0.0, 1.0) + 0.15 * shore
	var open: float = 1.0 - 0.9 * _cave
	var day: float = 1.0 - _night

	_set_bed("waves", 0.6 * shore * (1.0 - 0.85 * _cave) * (0.4 + 0.6 * close), delta)
	_set_bed("wind", (0.25 + 0.3 * exposure) * day * open, delta)
	_set_bed("wind_night", (0.3 + 0.3 * exposure) * _night * open, delta)
	_set_bed("rustle", _forest * 0.55 * (1.0 - 0.3 * _night) * (1.0 - _cave) * close, delta)
	_set_bed("crickets", _night * (1.0 - 0.7 * shore) * (1.0 - 0.85 * _cave) * (1.0 - 0.7 * hostile) * 0.6 * close, delta)
	_set_bed("drone", (0.04 + _night * 0.3 + hostile * 0.3) * (0.25 + 0.75 * close), delta)
	_close = close
	_set_bed("cave_hum", _cave * 0.5, delta)
	if weather != null:
		_set_bed("rain", weather.intensity * (0.55 - 0.3 * _cave) * lerpf(1.0, 0.4, _night), delta)   # bajo techo se oye, pero lejos

	# la cueva apaga lo de afuera y añade eco
	_lowpass.cutoff_hz = lerpf(20500.0, 2200.0, _cave)
	_reverb.wet = lerpf(0.04, 0.4, _cave)
	_reverb.room_size = lerpf(0.4, 0.85, _cave)

	_events(delta, p, day, hostile, shore)

func _set_bed(id: String, target: float, delta: float) -> void:
	if not _beds.has(id):
		return
	var v: float = lerpf(float(_bed_vol[id]), target, 1.0 - exp(-delta * 1.5))
	_bed_vol[id] = v
	(_beds[id] as AudioStreamPlayer).volume_db = linear_to_db(maxf(v, 0.0001))

func _tick(key: String, delta: float, lo: float, hi: float) -> bool:
	if not _timers.has(key):
		_timers[key] = _rng.randf_range(lo * 0.3, hi)
	_timers[key] = float(_timers[key]) - delta
	if float(_timers[key]) <= 0.0:
		_timers[key] = _rng.randf_range(lo, hi)
		return true
	return false

func _around(p: Vector3, dmin: float, dmax: float, ymin: float, ymax: float) -> Vector3:
	var a: float = _rng.randf() * TAU
	var d: float = _rng.randf_range(dmin, dmax)
	return p + Vector3(cos(a) * d, _rng.randf_range(ymin, ymax), sin(a) * d)

func _events(delta: float, p: Vector3, day: float, hostile: float, shore: float) -> void:
	var outside: bool = _cave < 0.5
	# --- de día: pájaros y gaviotas
	if _tick("bird", delta, 2.0, 6.5) and day > 0.35 and outside:
		# el escenario refleja la relación: más pájaros si la isla confía, silencio hostil si no
		var mood: float = brain.ambient_mood() if brain != null else 0.0
		var warmth: float = (1.0 + 0.4 * maxf(mood, 0.0)) * (1.0 - 0.85 * maxf(-mood, 0.0))
		if _rng.randf() < (0.3 + 0.7 * _forest) * (1.0 - 0.8 * hostile) * _close * warmth:
			_play3d("bird", _around(p, 8.0, 30.0, 4.0, 9.0), _rng.randf_range(-9.0, -3.0), _rng.randf_range(0.9, 1.15), BUS_AMB, 8.0, 80.0)
	if _tick("gull", delta, 6.0, 15.0) and day > 0.3 and outside:
		if _rng.randf() < (0.4 + 0.6 * shore) * (0.35 + 0.65 * _close):
			_play3d("gull", _around(p, 35.0, 70.0, 25.0, 45.0), _rng.randf_range(-9.0, -5.0), _rng.randf_range(0.9, 1.1), BUS_AMB, 25.0, 150.0)
	# --- de noche: misterio
	# navegando: crujidos suaves de la madera del barco
	if player != null and not player.controllable and not player.dead and _tick("boat", delta, 4.0, 9.0):
		_play2d("creak", -24.0, BUS_FX)
	if _tick("owl", delta, 16.0, 40.0) and _night > 0.6 and outside and _close > 0.3:
		_play3d("owl", _around(p, 18.0, 40.0, 6.0, 9.0), -6.0, _rng.randf_range(0.92, 1.05), BUS_AMB, 12.0, 100.0)
	if _tick("frog", delta, 4.0, 10.0) and _night > 0.4 and outside:
		var pond: Vector3 = Vector3(IslandTerrain.POND_CENTER.x, terrain.pond_water_level, IslandTerrain.POND_CENTER.y)
		if p.distance_to(pond) < 35.0 and _close > 0.5:
			_play3d("frog", pond + Vector3(_rng.randf_range(-6.0, 6.0), 0.2, _rng.randf_range(-6.0, 6.0)), -7.0, _rng.randf_range(0.9, 1.15), BUS_AMB, 5.0, 50.0)
	if _tick("creak", delta, 22.0, 55.0) and _night > 0.5 and outside:
		_play3d("creak", _around(p, 8.0, 22.0, 1.0, 4.0), -6.0, _rng.randf_range(0.85, 1.1), BUS_AMB, 8.0, 60.0)
	if _tick("pad", delta, 35.0, 75.0) and _night > 0.6:
		_play2d("pad", -16.0 - 6.0 * _cave)
	# --- cueva: goteo
	if _cave > 0.5 and features != null and _tick("drip", delta, 1.4, 4.0):
		var c: Vector3 = features.cave_center
		_play3d("drip", c + Vector3(_rng.randf_range(-2.5, 2.5), 2.5, _rng.randf_range(-2.5, 2.5)), -9.0, _rng.randf_range(0.85, 1.2), BUS_FX, 4.0, 30.0)
	# --- corazón cuando queda poca salud
	if player != null and not player.dead and player.health < 35.0:
		if _tick("heart", delta, 0.85, 0.9):
			_play2d("heart", lerpf(-2.0, -10.0, clampf(player.health / 35.0, 0.0, 1.0)), BUS_FX)
