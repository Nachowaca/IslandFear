class_name IslandBrain
extends Node

## La mente de la isla: una IA procedural local (NO es un LLM).
##
## Observa al jugador (dónde está, cuánto se queda quieto, si se esconde en la cueva, si se acerca a sus
## lugares sagrados, qué hora es), lleva un estado emocional (hostilidad, energía, rencor) y decide con
## una "utilidad" por acción quién, cuándo y cómo atacar. Aprende: recuerda qué ataques le funcionan,
## ajusta la puntería según cómo se mueve el jugador y su memoria sobrevive a las muertes.
##
## Reglas del juego:
##  - Al principio solo hay presagios (sin daño): período de gracia.
##  - De día es más débil y NO puede alcanzar al jugador dentro de la cueva (pero acumula rencor).
##  - De noche es más fuerte; la cueva se vuelve una trampa.
##  - Cada acción cuesta energía; la energía se recupera sola, más rápido de noche.

signal thought(text: String, kind: String)   # kind: whisper | omen | attack | info
signal action_taken(action: String)

enum Mood { CALM, WATCHFUL, IRRITATED, HOSTILE, FURIOUS }
const MOOD_NAMES: Array[String] = ["Calma", "Vigilante", "Irritada", "Hostil", "Furiosa"]

@export var aggression: float = 1.0          ## multiplica la velocidad a la que se enfurece
@export var day_length_seconds: float = 300.0   ## cuánto dura un "día" de estudio (tiempo de juego)
@export var study_days_min: float = 2.0         ## la isla te estudia entre min y max días antes de atacar
@export var study_days_max: float = 3.0
var grace_seconds: float = 100.0                ## (calculado) duración total del estudio
var voice := IslandVoice.new()
var _study_done: bool = false
var _study_bonus: float = 0.0                   ## tiempo "ganado" por provocaciones
var _last_day: int = 1
var _grievance: String = "calm"                 ## qué es lo que más le molesta de vos
var _tot: Dictionary = {}                       ## observaciones acumuladas
var _win: Dictionary = {}                       ## observaciones desde el último comentario
var _animal_timer: float = 0.0
var _pickup_count: int = -1
static var s_grievance: String = ""

# --- carácter propio (distinto en cada partida) y variables no lineales ---
var offense: float = 0.0                        ## "agravios" acumulados: SOLO sube si hacés algo malo
var _forgive: float = 1.0                       ## qué rápido perdona
var _sens: float = 1.0                          ## qué sensible es a las ofensas
var _noise: float = 0.5                         ## humor errático (caminata aleatoria)
var _curiosity: float = 0.3                     ## sube con lo nuevo que hacés
var _warned: bool = false
var _last_offense: String = "generic"
var _path: Array[Vector3] = []                  ## tus últimos pasos (para hacerles eco)
var _path_timer: float = 0.0
var _heading: Vector3 = Vector3.ZERO
var _firsts: Dictionary = {}

var terrain: IslandTerrain
var features: IslandFeatures
var player: Castaway

# --- estado emocional ---
var hostility: float = 8.0
var energy: float = 55.0
var grudge: float = 0.0
var mood: Mood = Mood.CALM
var last_thought: String = "..."
var last_action: String = "ninguna aún"
var log_lines: Array[String] = []

# --- memoria que sobrevive a las muertes ---
static var s_tries: Dictionary = {}
static var s_hits: Dictionary = {}
static var s_heat: Dictionary = {}
static var s_lead: float = 0.8
static var s_deaths: int = 0

# --- observación ---
var _world: Node3D
var _started: bool = false
var _time_on_island: float = 0.0
var _still_time: float = 0.0
var _sacred_pressure: float = 0.0
var _sacred_name: String = ""
var _in_cave: bool = false
var _cave_visit: float = 0.0
var _cave_time_day: float = 0.0
var _cave_time_night: float = 0.0
var _night: float = 0.0
var _vel_smooth: Vector3 = Vector3.ZERO
var _satisfaction: float = 0.0
var _think_timer: float = 6.0
var _global_attack_cd: float = 0.0
var _cooldowns: Dictionary = {}
var _trap_active: bool = false
var _trap_ominous: float = 0.0
var _last_mood: Mood = Mood.CALM
var _first_words: bool = false
var _rng := RandomNumberGenerator.new()

var _actions: Array[Dictionary] = [
	{"id": "whisper", "label": "Susurro", "cost": 1.0, "cd": 22.0, "min_h": 5.0, "damaging": false},
	{"id": "tremor", "label": "Temblor", "cost": 5.0, "cd": 45.0, "min_h": 12.0, "damaging": false},
	{"id": "scare_birds", "label": "Espantar aves", "cost": 3.0, "cd": 55.0, "min_h": 10.0, "damaging": false},
	{"id": "eyes", "label": "Ojos en la oscuridad", "cost": 4.0, "cd": 50.0, "min_h": 18.0, "damaging": false},
	{"id": "rockfall", "label": "Caída de rocas", "cost": 18.0, "cd": 20.0, "min_h": 30.0, "damaging": true},
	{"id": "thorns", "label": "Raíces espinosas", "cost": 22.0, "cd": 28.0, "min_h": 38.0, "damaging": true},
	{"id": "crab_rush", "label": "Plaga de cangrejos", "cost": 20.0, "cd": 70.0, "min_h": 40.0, "damaging": true},
	{"id": "echo", "label": "Eco de tus pasos", "cost": 3.0, "cd": 85.0, "min_h": 0.0, "damaging": false},
	{"id": "footsteps", "label": "Pasos detrás tuyo", "cost": 2.0, "cd": 60.0, "min_h": 0.0, "damaging": false},
	{"id": "wisp", "label": "Luz lejana", "cost": 3.0, "cd": 75.0, "min_h": 0.0, "damaging": false},
	{"id": "cave_trap", "label": "Trampa de la cueva", "cost": 35.0, "cd": 120.0, "min_h": 22.0, "damaging": true},
]

func _ready() -> void:
	_rng.randomize()
	_world = get_parent() as Node3D
	voice.rng.randomize()
	hostility = 0.0
	_forgive = _rng.randf_range(0.6, 1.6)
	_sens = _rng.randf_range(0.7, 1.4)
	_noise = _rng.randf()
	var days: float = _rng.randf_range(study_days_min, study_days_max)
	if s_deaths > 0 and s_grievance != "":
		days = _rng.randf_range(0.3, 0.8)          # ya te conoce: estudio corto
		_grievance = s_grievance
	grace_seconds = days * day_length_seconds
	if s_deaths > 0:
		_first_words = true
		call_deferred("_say", voice.line("return", {"n": s_deaths + 1}, 1), "whisper")

# ------------------------------------------------------------------ observación

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.dead:
		return
	if not player.controllable:
		return
	if not _started:
		_started = true
	_time_on_island += delta
	var dn: Node = get_tree().get_first_node_in_group("daynight")
	if dn != null:
		_night = dn.get("night_amount")

	var vel: Vector3 = player.velocity
	var speed: float = Vector2(vel.x, vel.z).length()
	_vel_smooth = _vel_smooth.lerp(vel, clampf(delta * 3.0, 0.0, 1.0))
	if speed < 0.5:
		_still_time += delta
	else:
		_still_time = maxf(_still_time - delta * 2.0, 0.0)

	var ppos: Vector3 = player.global_position
	_in_cave = features != null and features.is_inside_cave(ppos)
	player.in_refuge = _in_cave and _night < 0.5
	if _in_cave:
		_cave_visit += delta
		if _night < 0.5:
			_cave_time_day += delta
		else:
			_cave_time_night += delta
	else:
		_cave_visit = 0.0

	# mapa de calor: dónde pasa el tiempo
	var cell := Vector2i(int(floor(ppos.x / 8.0)), int(floor(ppos.z / 8.0)))
	if not s_heat.has(cell):
		_curiosity = minf(_curiosity + 0.18, 1.0)      # pisó un lugar nuevo: la isla se interesa
	s_heat[cell] = float(s_heat.get(cell, 0.0)) + delta

	_observe(delta, speed, ppos)
	_study_movement(delta, speed, ppos)
	_update_sacred(ppos, delta)
	_update_emotions(delta)
	_update_study()

	_satisfaction = maxf(_satisfaction - delta, 0.0)
	_global_attack_cd = maxf(_global_attack_cd - delta, 0.0)
	for k: String in _cooldowns.keys():
		_cooldowns[k] = maxf(float(_cooldowns[k]) - delta, 0.0)

	# luz de la cueva según el humor de la isla
	if features != null and not _trap_active:
		var base: float = clampf((_effective_hostility() - 30.0) / 70.0, 0.0, 1.0) * 0.6 * _night
		_trap_ominous = move_toward(_trap_ominous, base, delta * 0.4)
		features.set_cave_ominous(_trap_ominous)

	if not _first_words and _time_on_island > 6.0:
		_first_words = true
		_say(voice.line("greet"), "whisper")

	_think_timer -= delta
	if _think_timer <= 0.0:
		_think()
		# tiempos de cola larga: a veces habla seguido, a veces calla un buen rato
		var eff: float = _effective_hostility()
		var mean: float = lerpf(16.0, 5.0, clampf(eff / 100.0, 0.0, 1.0)) * lerpf(1.4, 0.7, _noise)
		_think_timer = clampf(exp(_rng.randfn(log(mean), 0.65)), 2.5, 75.0)

## Mide cómo se comporta el jugador: distancia, quietud, dónde está, si corre, si molesta animales o toma cosas.
func _obs_add(key: String, v: float) -> void:
	_tot[key] = float(_tot.get(key, 0.0)) + v
	_win[key] = float(_win.get(key, 0.0)) + v

func _observe(delta: float, speed: float, ppos: Vector3) -> void:
	_obs_add("dist", speed * delta)
	if speed < 0.5:
		_obs_add("still", delta)
	elif speed > player.walk_speed * 1.15:
		_obs_add("run", delta)
	if _in_cave:
		_obs_add("cave", delta)
	elif terrain != null:
		var h: float = terrain.height_at(ppos.x, ppos.z)
		if h < 1.25:
			_obs_add("beach", delta)
		else:
			_obs_add("forest", delta)
	if _night > 0.5 and speed > 0.5:
		_obs_add("night", delta)
	if _sacred_pressure > 0.3:
		_obs_add("sacred", delta)
	_animal_timer -= delta
	if _animal_timer > 0.0:
		return
	_animal_timer = 0.5
	var bothered: bool = false
	for g: String in ["crabs", "songbirds"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			if n is Node3D and (n as Node3D).global_position.distance_to(ppos) < 3.2:
				bothered = true
				break
		if bothered:
			break
	if bothered and speed > 0.5:
		var amount: float = 0.5 * (2.0 if speed > player.walk_speed * 1.15 else 1.0)
		_obs_add("animals", amount)
		_add_offense(amount * 1.1, "animals")
		if not _study_done:
			_study_bonus += 1.0                     # molestar a sus criaturas acorta su paciencia
	var count: int = get_tree().get_nodes_in_group("pickup").size()
	if _pickup_count >= 0 and count < _pickup_count:
		_obs_add("taken", float(_pickup_count - count))
		_add_offense(0.5 * float(_pickup_count - count), "taken")   # tomar frutos molesta apenas
	_pickup_count = count

## Estudia cada movimiento: ruta, giros, dudas, regresos y primeras veces.
func _study_movement(delta: float, speed: float, ppos: Vector3) -> void:
	_path_timer -= delta
	if _path_timer > 0.0:
		return
	_path_timer = 0.4
	if _path.size() > 0 and speed > 0.5:
		var step: Vector3 = ppos - _path[_path.size() - 1]
		step.y = 0.0
		if step.length() > 0.2:
			var h: Vector3 = step.normalized()
			if _heading != Vector3.ZERO and h.dot(_heading) < 0.3:
				_obs_add("turns", 1.0)           # giro brusco: duda
			_heading = h
	_path.append(ppos)
	if _path.size() > 600:
		_path.pop_front()
	# vuelve sobre sus pasos: pasó cerca de un punto de hace más de un minuto
	if _path.size() > 160 and speed > 0.5:
		var old: Vector3 = _path[_path.size() - 1 - 150 - _rng.randi() % 10]
		if Vector2(old.x - ppos.x, old.z - ppos.z).length() < 2.0:
			_obs_add("revisit", 0.4)
	if _in_cave and not _firsts.has("cave"):
		_firsts["cave"] = true
		_say(voice.line("first_cave", {"who": _who()}, 0), "whisper")
	elif speed > player.walk_speed * 1.15 and not _firsts.has("run"):
		_firsts["run"] = true
		_say(voice.line("first_run", {"who": _who()}, 0), "whisper")
	elif _night > 0.6 and speed > 0.5 and not _firsts.has("night"):
		_firsts["night"] = true
		_say(voice.line("first_night", {"who": _who()}, 0), "whisper")

## Solo el mal que le hacés a la isla la enoja. Estar acá, quieto o de noche, no.
func _add_offense(v: float, kind: String) -> void:
	offense = minf(offense + v * _sens, 160.0)
	_last_offense = kind

## Cuánto estudio lleva y cuándo termina.
func _update_study() -> void:
	var elapsed: float = _time_on_island + _study_bonus
	var day: int = int(elapsed / day_length_seconds) + 1
	if day > _last_day and not _study_done:
		_last_day = day
		_say(voice.line("day_pass", {"n": day, "who": _who()}, _tone()), "whisper")
	if not _study_done and elapsed >= grace_seconds:
		_finish_study()

func _tone() -> int:
	var eff: float = _effective_hostility()
	return 0 if eff < 25.0 else (1 if eff < 55.0 else 2)

## Cómo te llama la isla según lo que vio de vos.
func _who() -> String:
	match _top_trait(_tot):
		"animals":
			return _pick(["cazador", "perseguidor de bichos"])
		"taken":
			return _pick(["ladrón", "recolector"])
		"cave":
			return _pick(["ermitaño", "topo"])
		"still":
			return _pick(["durmiente", "estatua"])
		"dist", "run":
			return _pick(["caminante", "inquieto"])
		"sacred":
			return _pick(["profanador", "intruso"])
	return _pick(["extraño", "náufrago", "visitante"])

## Rasgo dominante de un conjunto de observaciones (con pesos para compararlos entre sí).
func _top_trait(d: Dictionary) -> String:
	var w: Dictionary = {
		"animals": float(d.get("animals", 0.0)) * 3.0 / 4.0,
		"sacred": float(d.get("sacred", 0.0)) * 3.0 / 6.0,
		"taken": float(d.get("taken", 0.0)) * 2.0,
		"cave": float(d.get("cave", 0.0)) / 25.0,
		"still": float(d.get("still", 0.0)) / 20.0,
		"run": float(d.get("run", 0.0)) / 10.0,
		"night": float(d.get("night", 0.0)) / 25.0,
		"beach": float(d.get("beach", 0.0)) / 50.0,
		"forest": float(d.get("forest", 0.0)) / 60.0,
		"dist": float(d.get("dist", 0.0)) / 90.0,
	}
	var best: String = ""
	var bv: float = 0.6
	for k: String in w.keys():
		if float(w[k]) > bv:
			bv = float(w[k])
			best = k
	return best

func _finish_study() -> void:
	_study_done = true
	var t: String = _top_trait(_tot)
	if _grievance == "calm" or s_grievance == "":
		match t:
			"animals", "sacred", "taken", "cave", "still":
				_grievance = t
			"dist", "run":
				_grievance = "restless"
			_:
				_grievance = "calm"
		s_grievance = _grievance
	var topic: String = "verdict_%s" % _grievance
	if not (_grievance in ["animals", "sacred", "taken"]) or not IslandVoice.POOLS.has(topic):
		topic = "verdict_calm"            # lo que no daña no se castiga: solo lo anota
	_say(voice.line(topic, {"place": _sacred_name if _sacred_name != "" else "mis lugares sagrados", "who": _who()}, 1), "attack")

## Frase sobre lo que el jugador viene haciendo (comenta lo reciente, no repite lo mismo).
func _speak_about_player() -> String:
	var ctx: Dictionary = {"who": _who(), "place": _sacred_name if _sacred_name != "" else "ese lugar", "n": int(float(_tot.get("dist", 0.0)))}
	if _in_cave:
		ctx["place"] = "la cueva"
		return voice.line("cave_day" if _night < 0.5 else "cave_night", ctx, _tone())
	var t: String = _top_trait(_win)
	_win.clear()
	var tone: int = _tone()
	if t == "dist":
		ctx["n"] = int(float(_tot.get("dist", 0.0)))
	var turns: float = float(_tot.get("turns", 0.0))
	var revisit: float = float(_tot.get("revisit", 0.0))
	var roll: float = _rng.randf()
	if roll < 0.2:
		return voice.riddle(ctx)
	if roll < 0.3 and turns > 6.0:
		return voice.line("obs_turns", ctx, tone)
	if roll < 0.38 and revisit > 1.5:
		return voice.line("obs_revisit", ctx, tone)
	if t != "" and _rng.randf() < 0.75:
		var topic: String = "obs_%s" % ("walk" if t == "dist" else t)
		if IslandVoice.POOLS.has(topic):
			if t == "cave":
				ctx["place"] = "la cueva"
			return voice.line(topic, ctx, tone)
	if _night > 0.6 and _rng.randf() < 0.5:
		return voice.line("night", ctx, tone)
	if _effective_hostility() > 60.0 and _rng.randf() < 0.5:
		return voice.line("hostile", ctx, tone)
	return voice.line("generic", ctx, tone)

func _update_sacred(ppos: Vector3, delta: float) -> void:
	var inside: bool = false
	if features != null:
		for sp: Dictionary in features.sacred_spots:
			if sp["kind"] == "refuge":
				continue
			var p: Vector3 = sp["pos"]
			if Vector2(ppos.x - p.x, ppos.z - p.z).length() < float(sp["radius"]):
				inside = true
				_sacred_name = sp["name"]
	var before: float = _sacred_pressure
	if inside:
		_sacred_pressure = minf(_sacred_pressure + delta / 7.0, 1.0)
	else:
		_sacred_pressure = maxf(_sacred_pressure - delta / 12.0, 0.0)
	if before < 0.5 and _sacred_pressure >= 0.5:
		_say(voice.line("sacred_warn", {"place": _sacred_name, "who": _who()}, _tone()), "omen")

func _update_emotions(delta: float) -> void:
	# humor errático: caminata aleatoria que vuelve lento hacia el centro
	_noise = clampf(_noise + _rng.randfn(0.0, 0.12) * sqrt(delta) - (_noise - 0.5) * 0.04 * delta, 0.0, 1.0)
	_curiosity = maxf(_curiosity - delta * 0.015, 0.05)
	# lingerar en un lugar sagrado SÍ es una ofensa
	if _sacred_pressure > 0.5:
		_add_offense(0.5 * delta * aggression, "sacred")
	# perdona: más rápido cuando la ofensa es chica, y con altibajos según el humor
	var mercy: float = _forgive * (0.5 + _noise) * (0.12 + 0.025 * offense)
	if _satisfaction > 0.0:
		mercy += 0.2
	offense = maxf(offense - mercy * delta, 0.0)
	# respuesta no lineal: pocas ofensas casi no cuentan, muchas saturan
	hostility = 100.0 * (1.0 - exp(-offense / 22.0))
	if offense < 2.0:
		_warned = false
	var regen: float = (0.55 + 0.9 * _night) * (0.8 + hostility / 100.0)
	energy = minf(energy + regen * delta, 100.0)

	var eff: float = _effective_hostility()
	var m: Mood = Mood.CALM
	if eff >= 78.0:
		m = Mood.FURIOUS
	elif eff >= 55.0:
		m = Mood.HOSTILE
	elif eff >= 35.0:
		m = Mood.IRRITATED
	elif eff >= 15.0:
		m = Mood.WATCHFUL
	if m != mood:
		mood = m
		if mood > _last_mood:
			_say(_mood_line(mood), "info")
		_last_mood = mood

func _effective_hostility() -> float:
	return clampf(hostility + (grudge * 0.5 * _night), 0.0, 100.0)

func _mood_line(m: Mood) -> String:
	return voice.line("mood_%d" % int(m), {}, _tone())

# ------------------------------------------------------------------ decisión

func _think() -> void:
	var eff: float = _effective_hostility()
	# a veces simplemente calla y observa
	if eff < 40.0 and _rng.randf() < 0.28 * (1.0 - clampf(_activity(), 0.0, 1.0)):
		return
	# antes de castigar, siempre avisa una vez
	if eff >= 22.0 and _study_done and not _warned and _global_attack_cd <= 0.0 and not _in_cave:
		_warned = true
		_global_attack_cd = _rng.randf_range(9.0, 18.0)
		_say(voice.line("warn_%s" % _last_offense if IslandVoice.POOLS.has("warn_%s" % _last_offense) else "warn_generic", {"who": _who(), "place": _sacred_name if _sacred_name != "" else "ese lugar"}, 1), "omen")
		return
	var cands: Array[Dictionary] = []
	for a: Dictionary in _actions:
		var id: String = a["id"]
		if float(_cooldowns.get(id, 0.0)) > 0.0:
			continue
		if energy < float(a["cost"]):
			continue
		if a["damaging"] and eff < float(a["min_h"]):
			continue
		var s: float = _score(a)
		if s > 0.18:
			cands.append({"a": a, "s": s})
	if cands.is_empty():
		return
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["s"]) > float(y["s"]))
	var top: Array = cands.slice(0, 3)
	var total: float = 0.0
	for c: Dictionary in top:
		total += pow(float(c["s"]), 2.0)
	var roll: float = _rng.randf() * total
	var chosen: Dictionary = top[0]["a"]
	for c: Dictionary in top:
		roll -= pow(float(c["s"]), 2.0)
		if roll <= 0.0:
			chosen = c["a"]
			break
	_execute(chosen)

## Cuánta "vida" muestra la isla ahora: mezcla curiosidad y humor errático.
func _activity() -> float:
	return clampf(0.15 + _curiosity * 0.55 + _noise * 0.5, 0.0, 1.2)

func _learned(id: String) -> float:
	var tries: float = float(s_tries.get(id, 0))
	var hits: float = float(s_hits.get(id, 0))
	return clampf((hits + 1.5) / (tries + 3.0) * 1.7, 0.45, 1.5)

func _score(a: Dictionary) -> float:
	var id: String = a["id"]
	var eff: float = _effective_hostility()
	var dmg: bool = a["damaging"]
	if dmg:
		if not _study_done:
			return 0.0                      # primero te estudia: solo presagios
		if id != "cave_trap" and _in_cave:
			return 0.0                      # la cueva protege
		if _global_attack_cd > 0.0:
			return 0.0
	var s: float = 0.0
	match id:
		"whisper":
			s = 0.3 + (0.25 if _in_cave else 0.0) + 0.2 * _sacred_pressure
		"tremor":
			s = 0.35 + 0.4 * _sacred_pressure + 0.12 * (1.0 - _night)
		"scare_birds":
			s = 0.3 + 0.2 * _sacred_pressure
			if get_tree().get_nodes_in_group("songbirds").is_empty():
				return 0.0
		"eyes":
			if _night < 0.5 or terrain == null or terrain.tree_positions.is_empty():
				return 0.0
			s = 0.6 * _night
		"rockfall":
			s = 0.55 + 0.35 * _sacred_pressure
			if _grievance == "sacred":
				s += 0.25
			if _still_time > 15.0:
				s += 0.2
			if player.global_position.y > 4.5:
				s += 0.15
		"thorns":
			s = 0.5 + 0.35 * _sacred_pressure
			if _still_time > 12.0:
				s += 0.35
			if _grievance == "still" or _grievance == "taken":
				s += 0.2
		"crab_rush":
			var near: int = 0
			for n: Node in get_tree().get_nodes_in_group("crabs"):
				if (n as Node3D).global_position.distance_to(player.global_position) < 45.0:
					near += 1
			if near < 3:
				return 0.0
			s = 0.45
			if _grievance == "animals":
				s += 0.5                    # se venga con sus propias criaturas
			if terrain != null and terrain.height_at(player.global_position.x, player.global_position.z) < 1.7:
				s += 0.35
		"echo":
			if _path.size() < 90:
				return 0.0
			s = 0.35 + 0.3 * _curiosity
		"footsteps":
			if _vel_smooth.length() < 0.5 and _still_time < 8.0:
				return 0.0
			s = 0.3 + 0.2 * _night
		"wisp":
			if _night < 0.35:
				return 0.0
			s = 0.3 + 0.3 * _night + 0.2 * _curiosity
		"cave_trap":
			if _night < 0.55 or not _in_cave or _cave_visit < 6.0 or _trap_active:
				return 0.0
			s = 1.0 + (0.4 if _grievance == "cave" else 0.0)
	if dmg:
		s *= _learned(id) * lerpf(0.6, 1.0, _night) * (0.6 + eff / 100.0 * 0.6)
	else:
		s *= 0.4 + 1.1 * _activity()
	s *= clampf(energy / (float(a["cost"]) * 1.4), 0.5, 1.2)
	return s + _rng.randf() * (0.08 if dmg else 0.22)       # los presagios son más impredecibles

func _execute(a: Dictionary) -> void:
	var id: String = a["id"]
	energy -= float(a["cost"])
	_cooldowns[id] = float(a["cd"]) * exp(_rng.randfn(0.0, 0.45))     # cola larga: a veces vuelve enseguida, a veces tarda
	last_action = "%s (%s)" % [a["label"], _reason(id)]
	action_taken.emit(id)
	if a["damaging"]:
		_global_attack_cd = 7.0
	match id:
		"whisper":
			_say(_speak_about_player(), "whisper")
		"tremor":
			_say(voice.line("tremor"), "omen")
			_do_tremor()
		"scare_birds":
			_say(voice.line("birds"), "omen")
			for b: Node in get_tree().get_nodes_in_group("songbirds"):
				(b as Bird).scare()
		"eyes":
			_say(voice.line("eyes"), "omen")
			_spawn_eyes()
		"rockfall":
			_say(voice.line("atk_rock"), "attack")
			_do_rockfall()
		"thorns":
			_say(voice.line("atk_thorn"), "attack")
			_do_thorns()
		"crab_rush":
			_say(voice.line("atk_crab_revenge" if _grievance == "animals" else "atk_crab"), "attack")
			_do_crab_rush()
		"echo":
			_do_echo()
		"footsteps":
			_do_footsteps()
		"wisp":
			_do_wisp()
		"cave_trap":
			_say(voice.line("atk_trap"), "attack")
			_do_cave_trap()

func _reason(id: String) -> String:
	match id:
		"rockfall", "thorns":
			if _sacred_pressure > 0.4:
				return "defiende %s" % _sacred_name
			if _still_time > 12.0:
				return "lleva rato quieto"
			return "quiere echarlo"
		"tremor":
			return "presagio"
		"crab_rush":
			return "cerca de la costa"
		"cave_trap":
			return "se refugió de noche"
		"eyes":
			return "es de noche"
	return "su humor"

# ------------------------------------------------------------------ acciones

func _say(text: String, kind: String) -> void:
	last_thought = text
	log_lines.append(text)
	if log_lines.size() > 7:
		log_lines.pop_front()
	thought.emit(text, kind)

func _pick(arr: Array) -> String:
	return arr[_rng.randi() % arr.size()]

func _pick_whisper() -> String:
	var eff: float = _effective_hostility()
	if _in_cave and _night < 0.5:
		return _pick(["Ahí dentro no puedo tocarte. Esperaré a la noche.", "Te escondés bajo mi piel. Volverás a salir.", "El sol te protege hoy. Solo hoy."])
	if _in_cave and _night >= 0.5:
		return _pick(["Qué oscuro está ahí dentro.", "Ya no hay sol."])
	if _cave_time_day > 45.0 and _rng.randf() < 0.5:
		return "Pasás el día entre mis rocas. Lo sé."
	if _sacred_pressure > 0.4:
		return _pick(["Eso no es tuyo.", "Aléjate de %s." % _sacred_name])
	if _still_time > 20.0:
		return _pick(["Quedarte quieto no te salvará.", "Descansá mientras puedas."])
	if _night > 0.6:
		return _pick(["La noche es mía.", "Te escucho respirar.", "Cada paso tuyo me despierta."])
	if eff > 60.0:
		return _pick(["Andate.", "Este no es tu lugar.", "Cada vez me duele más tenerte."])
	return _pick(["No eres bienvenido.", "Los náufragos nunca se quedan.", "Pequeño y frágil..."])

## Una luz repite un tramo que recorriste antes, como si alguien te siguiera el rastro.
func _do_echo() -> void:
	var n: int = _path.size()
	var seg: int = mini(40, n - 60)
	var start: int = _rng.randi_range(0, n - 60 - seg)
	var w := Wisp.new()
	w.player = player
	w.terrain = terrain
	w.color = Color(0.6, 0.9, 1.0) if _rng.randf() < 0.7 else Color(1.0, 0.85, 0.5)
	w.speed = _rng.randf_range(2.0, 3.4)
	for i in range(start, start + seg):
		w.path.append(_path[i])
	_world.add_child(w)
	w.global_position = _path[start] + Vector3(0, 1.4, 0)
	if _rng.randf() < 0.4:
		_say(voice.line("echo"), "omen")

func _do_wisp() -> void:
	var ang: float = _rng.randf() * TAU
	var d: float = _rng.randf_range(14.0, 24.0)
	var pos: Vector3 = player.global_position + Vector3(cos(ang) * d, 0.0, sin(ang) * d)
	pos.y = maxf(terrain.height_at(pos.x, pos.z), 0.5) + 1.6
	var w := Wisp.new()
	w.player = player
	w.terrain = terrain
	w.life = _rng.randf_range(16.0, 34.0)
	w.color = Color(0.7, 1.0, 0.8) if _rng.randf() < 0.5 else Color(0.65, 0.8, 1.0)
	_world.add_child(w)
	w.global_position = pos
	if _rng.randf() < 0.35:
		_say(voice.line("wisp"), "omen")

## Pasos de alguien que camina detrás, a distancia, y se detiene cuando mirás.
func _do_footsteps() -> void:
	var back: Vector3 = -Vector3(_vel_smooth.x, 0.0, _vel_smooth.z)
	if back.length() < 0.3:
		back = Vector3(cos(_rng.randf() * TAU), 0.0, sin(_rng.randf() * TAU))
	back = back.normalized().rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
	var dist: float = _rng.randf_range(9.0, 14.0)
	var steps: int = _rng.randi_range(4, 8)
	for i in steps:
		if player == null or not is_instance_valid(player) or player.dead:
			return
		var pos: Vector3 = player.global_position + back * dist
		var h: float = terrain.height_at(pos.x, pos.z)
		var kind: String = "step_sand" if h < 1.25 else "step_grass"
		pos.y = h
		AudioManager.play(get_tree(), kind, pos, -8.0)
		dist = maxf(dist - _rng.randf_range(0.3, 0.9), 4.0)
		await get_tree().create_timer(_rng.randf_range(0.45, 0.8)).timeout
	if _rng.randf() < 0.3:
		_say(voice.line("footsteps"), "omen")

func _do_tremor() -> void:
	AudioManager.play(get_tree(), "rumble", player.global_position, -2.0)
	for i in 9:
		if player != null and is_instance_valid(player):
			player.add_shake(0.75)
		await get_tree().create_timer(0.3).timeout

func _predict(lead_t: float) -> Vector3:
	var p: Vector3 = player.global_position
	var v: Vector3 = Vector3(_vel_smooth.x, 0.0, _vel_smooth.z)
	var aim: Vector3 = p + v * lead_t * s_lead
	var gy: float = terrain.height_at(aim.x, aim.z)
	if gy < 0.5:
		aim = p
		gy = terrain.height_at(aim.x, aim.z)
	aim.y = gy
	return aim

func _do_rockfall() -> void:
	var n: int = 1 + int(_effective_hostility() / 40.0)
	n = clampi(n, 1, 3)
	var warn: float = lerpf(1.8, 1.0, clampf(hostility / 100.0, 0.0, 1.0))
	for i in n:
		if player == null or player.dead:
			return
		var aim: Vector3 = _predict(warn + 1.1)
		if i > 0:
			aim += Vector3(_rng.randf_range(-3.0, 3.0), 0.0, _rng.randf_range(-3.0, 3.0))
			aim.y = terrain.height_at(aim.x, aim.z)
		var r := Rockfall.new()
		r.player = player
		r.target = aim
		r.warn_time = warn
		r.damage = 14.0 + hostility * 0.1
		r.finished.connect(_on_attack_finished.bind("rockfall"))
		_world.add_child(r)
		await get_tree().create_timer(0.55).timeout

func _do_thorns() -> void:
	var p: Vector3 = player.global_position
	var center: Vector3 = p
	if _still_time < 12.0:
		center = _predict(1.2)
	center.y = terrain.height_at(center.x, center.z)
	var t := ThornRoots.new()
	t.player = player
	t.terrain = terrain
	t.center = center
	t.radius = 2.8 + hostility / 100.0
	t.warn_time = lerpf(2.0, 1.3, clampf(hostility / 100.0, 0.0, 1.0))
	t.damage = 10.0 + hostility * 0.08
	t.finished.connect(_on_attack_finished.bind("thorns"))
	_world.add_child(t)

func _do_crab_rush() -> void:
	var crabs: Array[Node] = get_tree().get_nodes_in_group("crabs")
	crabs.sort_custom(func(a: Node, b: Node) -> bool:
		return (a as Node3D).global_position.distance_to(player.global_position) < (b as Node3D).global_position.distance_to(player.global_position))
	var count: int = 0
	for c: Node in crabs:
		if count >= 14:
			break
		if (c as Node3D).global_position.distance_to(player.global_position) > 45.0:
			break
		(c as Crab).make_hostile(26.0)
		count += 1
	_on_attack_finished(false, player.global_position, player.global_position, "crab_rush", true)

func _spawn_eyes() -> void:
	if terrain == null:
		return
	var ppos: Vector3 = player.global_position
	var spawned: int = 0
	var order: Array[int] = []
	for i in terrain.tree_positions.size():
		order.append(i)
	order.shuffle()
	for i: int in order:
		if spawned >= 4:
			break
		var tp: Vector3 = terrain.tree_positions[i]
		var d: float = Vector2(tp.x - ppos.x, tp.z - ppos.z).length()
		if d < 12.0 or d > 26.0:
			continue
		var ts: float = terrain.tree_scales[i]
		var dir: Vector3 = (Vector3(ppos.x, 0, ppos.z) - Vector3(tp.x, 0, tp.z)).normalized()
		var e := WatcherEyes.new()
		e.player = player
		e.eye_color = Color(1.0, 0.75, 0.2) if _effective_hostility() < 50.0 else Color(1.0, 0.2, 0.15)
		e.life = _rng.randf_range(10.0, 18.0)
		_world.add_child(e)
		e.global_position = tp + dir * 0.55 * ts + Vector3(0, 1.7 * ts, 0)
		spawned += 1

func _do_cave_trap() -> void:
	if features == null:
		return
	_trap_active = true
	features.seal_cave()
	_trap_ominous = 1.0
	features.set_cave_ominous(1.0)
	# ojos rojos al fondo de la cueva
	var back: Vector3 = features.cave_center - features.cave_dir * 3.0
	for k in 3:
		var side: Vector3 = Vector3(-features.cave_dir.z, 0.0, features.cave_dir.x)
		var e := WatcherEyes.new()
		e.player = player
		e.eye_color = Color(1.0, 0.15, 0.1)
		e.life = 16.0
		e.flee_distance = 0.0
		_world.add_child(e)
		e.global_position = back + side * (float(k) - 1.0) * 1.3 + Vector3(0, 1.5 + 0.5 * float(k % 2), 0)
	# rocas cayendo del techo mientras dura la trampa
	for i in 5:
		await get_tree().create_timer(2.6).timeout
		if player == null or player.dead or not is_instance_valid(player):
			break
		if not features.is_inside_cave(player.global_position):
			break
		var aim: Vector3 = player.global_position + Vector3(_vel_smooth.x, 0.0, _vel_smooth.z) * 1.0 * s_lead
		aim.y = features.cave_center.y
		var r := Rockfall.new()
		r.player = player
		r.target = aim
		r.fall_height = 3.1
		r.warn_time = 1.3
		r.damage = 16.0
		r.radius = 1.8
		r.finished.connect(_on_attack_finished.bind("cave_trap"))
		_world.add_child(r)
	await get_tree().create_timer(2.0).timeout
	features.open_cave()
	_trap_active = false
	_say(voice.line("trap_end"), "omen")

# ------------------------------------------------------------------ aprendizaje

func _on_attack_finished(hit: bool, aim: Vector3, ppos: Vector3, kind: String, no_learn: bool = false) -> void:
	if no_learn:
		s_tries[kind] = int(s_tries.get(kind, 0)) + 1
		return
	s_tries[kind] = int(s_tries.get(kind, 0)) + 1
	if hit:
		s_hits[kind] = int(s_hits.get(kind, 0)) + 1
		_satisfaction = 20.0
		offense = maxf(offense - 6.0, 0.0)
		_say(voice.line("hit"), "info")
	else:
		# ajusta la puntería: si el jugador se movía y falló, corrige cuánto anticipa
		var v: Vector3 = Vector3(_vel_smooth.x, 0.0, _vel_smooth.z)
		if v.length() > 0.5 and ppos != Vector3.ZERO:
			var err: Vector3 = Vector3(ppos.x - aim.x, 0.0, ppos.z - aim.z)
			var along: float = err.dot(v.normalized())
			s_lead = clampf(s_lead + clampf(along / (v.length() * 2.4) * 0.5, -0.25, 0.25), 0.0, 1.6)
		if ppos != Vector3.ZERO and Vector2(ppos.x - aim.x, ppos.z - aim.z).length() < 4.5:
			_say(voice.line("miss"), "info")

# ------------------------------------------------------------------ panel de depuración

func notify_death() -> void:
	s_deaths += 1

func hottest_zone() -> String:
	var best_cell: Vector2i = Vector2i.ZERO
	var best: float = 0.0
	for c: Vector2i in s_heat.keys():
		if float(s_heat[c]) > best:
			best = float(s_heat[c])
			best_cell = c
	if best <= 0.0:
		return "—"
	var wx: float = float(best_cell.x) * 8.0 + 4.0
	var wz: float = float(best_cell.y) * 8.0 + 4.0
	if features != null and Vector2(wx - features.cave_center.x, wz - features.cave_center.z).length() < 11.0:
		return "la cueva"
	if terrain != null and terrain.height_at(wx, wz) < 1.3:
		return "la playa"
	if features != null:
		for sp: Dictionary in features.sacred_spots:
			var p: Vector3 = sp["pos"]
			if Vector2(wx - p.x, wz - p.z).length() < float(sp["radius"]) and sp["kind"] != "refuge":
				return str(sp["name"])
	return "el interior"

func status_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("Estado: %s" % MOOD_NAMES[mood])
	lines.append("Agravios: %.1f (solo suben si le hacés mal)   Curiosidad: %d%%   Humor: %d%%" % [offense, int(_curiosity * 100.0), int(_noise * 100.0)])
	lines.append("Hostilidad: %d / 100" % int(_effective_hostility()))
	lines.append("Energía: %d / 100" % int(energy))
	lines.append("Rencor: %d" % int(grudge))
	lines.append("Hora: %s" % ("noche" if _night > 0.5 else "día"))
	if not _study_done:
		var left: float = maxf(grace_seconds - _time_on_island - _study_bonus, 0.0)
		lines.append("Te estudia: día %d de %.1f (faltan %d s)" % [_last_day, grace_seconds / day_length_seconds, int(left)])
	else:
		lines.append("Veredicto: %s" % _grievance)
	lines.append("Te vio: %d m, quieto %d s, corrió %d s, animales %d s, tomó %d" % [int(float(_tot.get("dist", 0.0))), int(float(_tot.get("still", 0.0))), int(float(_tot.get("run", 0.0))), int(float(_tot.get("animals", 0.0))), int(float(_tot.get("taken", 0.0)))])
	lines.append("Te ve en: %s" % ("la cueva" if _in_cave else "descubierto"))
	lines.append("Zona que más visitás: %s" % hottest_zone())
	var parts: Array[String] = []
	for id: String in ["rockfall", "thorns", "crab_rush", "cave_trap"]:
		var t: int = int(s_tries.get(id, 0))
		if t > 0:
			parts.append("%s %d/%d" % [id, int(s_hits.get(id, 0)), t])
	lines.append("Aciertos: %s" % (", ".join(parts) if not parts.is_empty() else "ninguno aún"))
	lines.append("Anticipación (puntería): %.2f" % s_lead)
	lines.append("Muertes que recuerda: %d" % s_deaths)
	lines.append("Última acción: %s" % last_action)
	return lines
