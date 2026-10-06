extends Node

## Autoload "Isla": la memoria y las emociones de la isla (sin LLM, solo variables).
## Guarda en disco (user://isla.json) para que las 7 vidas sobrevivan al cerrar el juego.
## Uso: Isla.registrar_evento("animal_molestado", posicion_o_celda, intensidad)

signal emocion_cambiada(nombre: String, valor: float)

const EMOCIONES: Array[String] = ["confianza", "enojo", "miedo", "curiosidad"]
const SAVE_PATH: String = "user://isla.json"
const CELDA: float = 8.0
## Qué tan rápido vuelve cada emoción a su base (1/segundos). El enojo cuesta más soltarlo que la curiosidad.
const DECAIMIENTO: Dictionary = {"confianza": 0.008, "enojo": 0.012, "miedo": 0.03, "curiosidad": 0.02}
const CONTADORES: Array[String] = ["arboles_cortados", "fuegos", "animales_cazados", "ofrendas", "tiempo_corriendo", "tiempo_explorando", "animales_molestados", "frutos_tomados", "tiempo_en_sagrado", "muertes"]

## Efecto de cada evento: contador que suma, emociones que mueve (por unidad de intensidad) y si es destructivo (marca el mapa de daño).
const EVENTOS: Dictionary = {
	"arbol_cortado": {"cont": "arboles_cortados", "fx": {"enojo": 0.10, "confianza": -0.06, "miedo": 0.02}, "dano": true},
	"fuego": {"cont": "fuegos", "fx": {"enojo": 0.06, "miedo": 0.08, "curiosidad": 0.04}, "dano": true},
	"animal_cazado": {"cont": "animales_cazados", "fx": {"enojo": 0.18, "confianza": -0.12}, "dano": true},
	"animal_molestado": {"cont": "animales_molestados", "fx": {"enojo": 0.04, "confianza": -0.02}, "dano": true},
	"fruto_tomado": {"cont": "frutos_tomados", "fx": {"enojo": 0.01, "curiosidad": 0.02}, "dano": false},
	"zona_sagrada": {"cont": "tiempo_en_sagrado", "fx": {"enojo": 0.05, "miedo": 0.02}, "dano": true},
	"ofrenda": {"cont": "ofrendas", "fx": {"confianza": 0.15, "enojo": -0.10, "miedo": -0.04}, "dano": false},
	"explorar": {"cont": "", "fx": {"curiosidad": 0.05, "miedo": -0.01}, "dano": false},
	"cuidado": {"cont": "", "fx": {"confianza": 0.05, "enojo": -0.03}, "dano": false},
	"muerte_jugador": {"cont": "muertes", "fx": {"curiosidad": 0.15, "enojo": -0.12, "miedo": 0.05}, "dano": false},
}

const VIDAS_MAX: int = 7

var vida: int = 1                       ## vida en curso (1..7)
var ciclo: int = 1                      ## cuántas veces se completaron las 7 vidas + 1
var ultimo_final: String = ""
var _voz := IslandVoice.new()
var base: Dictionary = {"confianza": 0.45, "enojo": 0.15, "miedo": 0.1, "curiosidad": 0.5}
var valor: Dictionary = {}
var sensibilidad: float = 1.0
var total: Dictionary = {}              ## acumulado de todas las vidas
var vida_actual: Dictionary = {}        ## solo la vida en curso
var calor_paso: Dictionary = {}         ## Vector2i -> segundos que pasó ahí
var calor_dano: Dictionary = {}         ## Vector2i -> daño que causó ahí

var _emitido: Dictionary = {}
var _guardar_t: float = 30.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	for c: String in CONTADORES:
		total[c] = 0.0
		vida_actual[c] = 0.0
	if not cargar():
		_personalidad_inicial()
	for e: String in EMOCIONES:
		if not valor.has(e):
			valor[e] = base[e]
		_emitido[e] = float(valor[e])

## Primera vez que se juega: cada isla nace con un carácter algo distinto.
func _personalidad_inicial() -> void:
	for e: String in EMOCIONES:
		base[e] = clampf(float(base[e]) + _rng.randf_range(-0.1, 0.1), 0.05, 0.95)
		valor[e] = base[e]
	sensibilidad = _rng.randf_range(0.8, 1.3)

func _process(delta: float) -> void:
	for e: String in EMOCIONES:
		var v: float = float(valor[e])
		v = lerpf(v, float(base[e]), 1.0 - exp(-float(DECAIMIENTO[e]) * delta))
		valor[e] = v
		_notificar(e)
	_guardar_t -= delta
	if _guardar_t <= 0.0:
		_guardar_t = 30.0
		guardar()

func _exit_tree() -> void:
	guardar()

# ------------------------------------------------------------------ API

func celda_de(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELDA)), int(floor(pos.z / CELDA)))

func get_emocion(nombre: String) -> float:
	return float(valor.get(nombre, 0.0))

## Registra algo que hizo el jugador. `zona` puede ser una posición (Vector3) o una celda (Vector2i).
func registrar_evento(tipo: String, zona: Variant = Vector2i.ZERO, intensidad: float = 1.0) -> void:
	if not EVENTOS.has(tipo):
		push_warning("Isla: evento desconocido '%s'" % tipo)
		return
	var ev: Dictionary = EVENTOS[tipo]
	var cell: Vector2i = zona if zona is Vector2i else celda_de(zona as Vector3)
	var cont: String = ev["cont"]
	if cont != "":
		_sumar(cont, intensidad)
	if bool(ev["dano"]):
		calor_dano[cell] = float(calor_dano.get(cell, 0.0)) + intensidad
	var fx: Dictionary = ev["fx"]
	for e: String in fx.keys():
		_mover(e, float(fx[e]) * intensidad * sensibilidad)

## Para contadores que son tiempo (tiempo_corriendo, tiempo_explorando...).
func sumar_tiempo(contador: String, segundos: float) -> void:
	_sumar(contador, segundos)

func sumar_paso(pos: Vector3, segundos: float) -> void:
	var cell: Vector2i = celda_de(pos)
	calor_paso[cell] = float(calor_paso.get(cell, 0.0)) + segundos

func vidas_restantes() -> int:
	return maxi(VIDAS_MAX - vida + 1, 0)

## Puntos de "destrucción" y de "cuidado" de un conjunto de contadores.
func _perfil_puntos(c: Dictionary) -> Dictionary:
	var dest: float = float(c.get("animales_cazados", 0.0)) * 2.0 + float(c.get("arboles_cortados", 0.0)) + float(c.get("fuegos", 0.0)) * 0.5 + float(c.get("animales_molestados", 0.0)) * 0.4 + float(c.get("tiempo_en_sagrado", 0.0)) * 0.08
	var cuid: float = float(c.get("ofrendas", 0.0)) * 3.0
	var calma: float = clampf(float(c.get("tiempo_explorando", 0.0)) / 240.0, 0.0, 1.0)
	cuid += calma * 2.0 * (1.0 - clampf(dest / 20.0, 0.0, 1.0))      # recorrer en paz también es respeto
	return {"dest": dest, "cuid": cuid, "calma": calma}

## Al morir: la personalidad base se desplaza según cómo jugó esta vida, y empieza la siguiente.
## Devuelve {"fin": true} si se acabaron las 7 vidas.
func cerrar_vida() -> Dictionary:
	var p: Dictionary = _perfil_puntos(vida_actual)
	var d: float = clampf(float(p["dest"]) / 30.0, 0.0, 1.0)
	var c: float = clampf(float(p["cuid"]) / 9.0, 0.0, 1.0)
	var calma: float = float(p["calma"])
	_desplazar("enojo", 0.10 * d - 0.06 * c)
	_desplazar("confianza", -0.12 * d + 0.12 * c)
	_desplazar("miedo", 0.05 * d - 0.03 * c)
	_desplazar("curiosidad", 0.04 * calma - 0.02 * d)
	vida += 1
	for k: String in CONTADORES:
		vida_actual[k] = 0.0
	for e: String in EMOCIONES:
		valor[e] = base[e]                # la nueva vida empieza desde la nueva personalidad
	guardar()
	return {"fin": vida > VIDAS_MAX, "vidas_restantes": vidas_restantes()}

func _desplazar(nombre: String, v: float) -> void:
	base[nombre] = clampf(float(base[nombre]) + v, 0.05, 0.95)

## El final tras la séptima vida: convivir o no, según lo acumulado. El texto se compone con piezas variables.
func calcular_final() -> Dictionary:
	var p: Dictionary = _perfil_puntos(total)
	var dest: float = float(p["dest"])
	var cuid: float = float(p["cuid"])
	var perfil: String = "neutral"
	if dest >= 25.0:
		perfil = "destructor"
	elif float(total.get("ofrendas", 0.0)) >= 3.0 or cuid > 8.0:
		perfil = "cuidador"
	elif float(total.get("tiempo_explorando", 0.0)) > 600.0:
		perfil = "explorador"
	var puntaje: float = float(base["confianza"]) - 0.8 * float(base["enojo"]) + clampf(cuid / 20.0, 0.0, 1.0) * 0.5 - clampf(dest / 40.0, 0.0, 1.0) * 0.6 + _rng.randf_range(-0.1, 0.1)
	var tipo: String = "convivir" if puntaje > 0.15 else "no_convivir"
	_voz.rng.randomize()
	var titulo: String = _voz.line("final_titulo_" + tipo)
	var cuerpo: String = "%s %s\n\n%s" % [_voz.line("final_ap_" + perfil), _voz.line("final_cuerpo_" + tipo), _voz.line("final_cierre")]
	return {"tipo": tipo, "perfil": perfil, "puntaje": puntaje, "titulo": titulo, "cuerpo": cuerpo}

## Reinicia el ciclo de 7 vidas, distinto cada vez: la isla recuerda cómo terminó el anterior y nace con otro carácter.
func nuevo_ciclo(tipo_final: String) -> void:
	ciclo += 1
	vida = 1
	ultimo_final = tipo_final
	for k: String in CONTADORES:
		total[k] = 0.0
		vida_actual[k] = 0.0
	for cell: Vector2i in calor_paso.keys():
		calor_paso[cell] = float(calor_paso[cell]) * 0.25
	calor_dano.clear()
	var nuevo: Dictionary = {"confianza": 0.45, "enojo": 0.15, "miedo": 0.1, "curiosidad": 0.5}
	for e: String in EMOCIONES:
		nuevo[e] = clampf(float(nuevo[e]) + _rng.randf_range(-0.25, 0.25), 0.05, 0.95)
	if tipo_final == "convivir":
		nuevo["confianza"] = clampf(float(nuevo["confianza"]) - 0.12, 0.05, 0.95)     # tras la paz, esta isla desconfía de volver a perderla
		nuevo["miedo"] = clampf(float(nuevo["miedo"]) + 0.1, 0.05, 0.95)
	else:
		nuevo["curiosidad"] = clampf(float(nuevo["curiosidad"]) + 0.15, 0.05, 0.95)  # tras la soledad, esta isla está ansiosa por conocer
		nuevo["enojo"] = clampf(float(nuevo["enojo"]) - 0.05, 0.05, 0.95)
	base = nuevo
	for e: String in EMOCIONES:
		valor[e] = base[e]
	sensibilidad = _rng.randf_range(0.7, 1.4)
	guardar()

func reiniciar_memoria() -> void:
	vida = 1
	ciclo = 1
	ultimo_final = ""
	for c: String in CONTADORES:
		total[c] = 0.0
		vida_actual[c] = 0.0
	calor_paso.clear()
	calor_dano.clear()
	base = {"confianza": 0.45, "enojo": 0.15, "miedo": 0.1, "curiosidad": 0.5}
	_personalidad_inicial()
	guardar()

func resumen() -> String:
	return "Confianza %d%%  Enojo %d%%  Miedo %d%%  Curiosidad %d%%" % [int(get_emocion("confianza") * 100.0), int(get_emocion("enojo") * 100.0), int(get_emocion("miedo") * 100.0), int(get_emocion("curiosidad") * 100.0)]

# ------------------------------------------------------------------ interno

func _sumar(contador: String, v: float) -> void:
	total[contador] = float(total.get(contador, 0.0)) + v
	vida_actual[contador] = float(vida_actual.get(contador, 0.0)) + v

func _mover(nombre: String, delta_v: float) -> void:
	valor[nombre] = clampf(float(valor.get(nombre, 0.0)) + delta_v, 0.0, 1.0)
	_notificar(nombre)

func _notificar(nombre: String) -> void:
	var v: float = float(valor[nombre])
	if absf(v - float(_emitido.get(nombre, -1.0))) >= 0.02:
		_emitido[nombre] = v
		emocion_cambiada.emit(nombre, v)

# ------------------------------------------------------------------ guardado

func _claves(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Vector2i in d.keys():
		out["%d,%d" % [k.x, k.y]] = d[k]
	return out

func _celdas(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in d.keys():
		var p: PackedStringArray = k.split(",")
		if p.size() == 2:
			out[Vector2i(int(p[0]), int(p[1]))] = float(d[k])
	return out

func guardar() -> void:
	var data: Dictionary = {
		"vida": vida, "ciclo": ciclo, "ultimo_final": ultimo_final, "base": base, "valor": valor, "sensibilidad": sensibilidad,
		"total": total, "vida_actual": vida_actual,
		"calor_paso": _claves(calor_paso), "calor_dano": _claves(calor_dano),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()

func cargar() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary):
		return false
	var d: Dictionary = parsed
	vida = clampi(int(d.get("vida", 1)), 1, VIDAS_MAX)
	ciclo = int(d.get("ciclo", 1))
	ultimo_final = str(d.get("ultimo_final", ""))
	sensibilidad = float(d.get("sensibilidad", 1.0))
	for e: String in EMOCIONES:
		base[e] = float((d.get("base", {}) as Dictionary).get(e, base[e]))
		valor[e] = float((d.get("valor", {}) as Dictionary).get(e, base[e]))
	for c: String in CONTADORES:
		total[c] = float((d.get("total", {}) as Dictionary).get(c, 0.0))
		vida_actual[c] = float((d.get("vida_actual", {}) as Dictionary).get(c, 0.0))
	calor_paso = _celdas(d.get("calor_paso", {}))
	calor_dano = _celdas(d.get("calor_dano", {}))
	return true
