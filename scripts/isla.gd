extends Node

## Autoload "Isla": la memoria y las emociones de la isla (sin LLM, solo variables).
## Guarda en disco (user://isla.json) para que las 7 vidas sobrevivan al cerrar el juego.
## Uso: Isla.registrar_evento("animal_molestado", posicion_o_celda, intensidad)

signal emocion_cambiada(nombre: String, valor: float)
signal evento_registrado(tipo: String, zona: Vector3, intensidad: float)
signal etapa_cambiada(idx: int, subio: bool)

## Relación lenta (oculta para el jugador) entre la isla y el náufrago: -100 hostil … +100 aliada.
## A diferencia de las emociones (que suben y bajan rápido), el vínculo cambia despacio y es lo que decide
## si la isla puede atacar, ayudar o convivir.
const ETAPAS: Array[String] = ["Hostil", "Desconfiada", "Extraña", "Tolerante", "Aceptante", "Aliada"]
const ETAPA_LIMITES: Array[float] = [-40.0, -10.0, 15.0, 45.0, 75.0]
const VINCULO_FX: Dictionary = {
	"arbol_cortado": -8.0, "fuego": -3.0, "animal_cazado": -12.0, "animal_molestado": -0.6,
	"fruto_tomado": -0.15, "zona_sagrada": -0.5,
	"ofrenda": 7.0, "replantar": 3.0, "cuidado": 1.0, "contemplar": 0.3, "explorar": 0.2, "limpieza": 3.0, "contaminacion": -0.5,
}
const PAZ_TOPE: float = 40.0                 ## la paz sola no pasa de aquí: para más hacen falta gestos (ofrendas)

var vinculo: float = 0.0
var _etapa_prev: int = 2
var _t_dano: float = 999.0                   ## segundos desde la última ofensa

func etapa_idx() -> int:
	var i: int = 0
	for lim: float in ETAPA_LIMITES:
		if vinculo >= lim:
			i += 1
	return i

func etapa_nombre() -> String:
	return ETAPAS[etapa_idx()]

func _ajustar_vinculo(v: float) -> void:
	vinculo = clampf(vinculo + v, -100.0, 100.0)
	if v < 0.0:
		_t_dano = 0.0
	var e: int = etapa_idx()
	if e != _etapa_prev:
		var subio: bool = e > _etapa_prev
		_etapa_prev = e
		etapa_cambiada.emit(e, subio)

## Tiempo en paz: tras 90 s sin ofensas el vínculo mejora solo, y las heridas viejas sanan.
func tick_paz(delta: float) -> void:
	if _t_dano > 90.0:
		if vinculo < PAZ_TOPE:
			_ajustar_vinculo(0.02 * delta)
		if vinculo < 0.0:
			_ajustar_vinculo(0.03 * delta)

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
	"limpieza": {"cont": "", "fx": {"confianza": 0.10, "enojo": -0.08, "miedo": -0.03}, "dano": false},
	"contaminacion": {"cont": "", "fx": {"enojo": 0.04, "confianza": -0.02}, "dano": false},
	"explorar": {"cont": "", "fx": {"curiosidad": 0.05, "miedo": -0.01}, "dano": false},
	"replantar": {"cont": "", "fx": {"confianza": 0.08, "enojo": -0.05, "miedo": -0.02}, "dano": false},
	"cuidado": {"cont": "", "fx": {"confianza": 0.05, "enojo": -0.03}, "dano": false},
	"cofre": {"cont": "", "fx": {"curiosidad": 0.02}, "dano": false},
	"contemplar": {"cont": "", "fx": {"confianza": 0.03, "enojo": -0.02, "miedo": -0.02}, "dano": false},
	"muerte_jugador": {"cont": "muertes", "fx": {"curiosidad": 0.15, "enojo": -0.12, "miedo": 0.05}, "dano": false},
}

## Salud de zona (5.1): cuanto sube o baja la salud del bioma por cada unidad de cada evento.
const SALUD_FX: Dictionary = {"arbol_cortado": -0.02, "fuego": -0.015, "animal_cazado": -0.03, "animal_molestado": -0.01, "zona_sagrada": -0.01, "contaminacion": -0.03, "ofrenda": 0.06, "replantar": 0.08, "limpieza": 0.05, "cuidado": 0.03}
const SALUD_REGEN: float = 0.0002        ## por segundo, solo en paz (90 s sin ofensas)

const VIDAS_MAX: int = 7
const VINCULO_INICIO: float = 30.0     ## vínculo mínimo al abrir el juego (Tolerante: la luciérnaga viene)

var refugios: Array = []                ## refugios armados: {x, y, z, vida}; duran la vida en que se arman y la siguiente
const REFUGIO_VIDAS: int = 2

## Refugios que siguen en pie en la vida actual (los demas se pierden).
func refugios_vigentes() -> Array:
	var out: Array = []
	for r: Variant in refugios:
		if vida - int(r["vida"]) < REFUGIO_VIDAS:
			out.append(r)
	refugios = out
	return out

var tumbas: Array = []                  ## piedras de las vidas pasadas del ciclo: {x, y, z, texto}

## Talla una tumba donde murió el jugador, con un epitafio según cómo vivió esa vida (llamar ANTES de cerrar_vida).
func registrar_tumba(pos: Vector3, causa: String) -> void:
	var texto: String = StelaTexts.epitafio(vida, causa, vida_actual)
	tumbas.append({"x": pos.x, "y": pos.y, "z": pos.z, "texto": texto})
	if tumbas.size() > VIDAS_MAX:
		tumbas.pop_front()

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
var eco: EcoMap                          ## mapa ecológico (lo asigna main.gd)
var bioma_tiempo: Dictionary = {}       ## nombre de bioma -> segundos que pasó el jugador ahí
var bioma_eventos: Dictionary = {}      ## nombre de bioma -> {tipo de evento: cantidad}
var salud_zona: Dictionary = {}          ## nombre de bioma -> salud 0..1 (1 = sana; no se muestra al jugador)

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
	# punto de partida de las pruebas: arranca en paz (Tolerante) como mínimo
	vinculo = maxf(vinculo, VINCULO_INICIO)
	_etapa_prev = etapa_idx()
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
	_t_dano += delta
	if _t_dano > 90.0:
		for bn: String in salud_zona.keys():
			salud_zona[bn] = minf(float(salud_zona[bn]) + SALUD_REGEN * delta, 1.0)
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
	if VINCULO_FX.has(tipo):
		_ajustar_vinculo(float(VINCULO_FX[tipo]) * intensidad)
	var pos3: Vector3 = zona if zona is Vector3 else Vector3(float(cell.x) * CELDA, 0.0, float(cell.y) * CELDA)
	if eco != null and is_instance_valid(eco):
		var bn: String = eco.get_bioma_nombre(pos3)
		var ev_b: Dictionary = bioma_eventos.get(bn, {})
		ev_b[tipo] = float(ev_b.get(tipo, 0.0)) + intensidad
		bioma_eventos[bn] = ev_b
		if SALUD_FX.has(tipo):
			salud_zona[bn] = clampf(float(salud_zona.get(bn, 1.0)) + float(SALUD_FX[tipo]) * intensidad, 0.0, 1.0)
	evento_registrado.emit(tipo, pos3, intensidad)

## Para contadores que son tiempo (tiempo_corriendo, tiempo_explorando...).
func sumar_tiempo(contador: String, segundos: float) -> void:
	_sumar(contador, segundos)

## Suma tiempo del jugador en un bioma (lo llama el cerebro cada frame).
func sumar_bioma(nombre: String, segundos: float) -> void:
	bioma_tiempo[nombre] = float(bioma_tiempo.get(nombre, 0.0)) + segundos

## Bioma donde más tiempo pasó ("" si todavía no hay datos suficientes) y qué fracción del tiempo total fue.
func bioma_favorito(min_segundos: float = 60.0) -> Dictionary:
	var tot: float = 0.0
	var best: String = ""
	var bt: float = 0.0
	for b: String in bioma_tiempo.keys():
		var v: float = float(bioma_tiempo[b])
		tot += v
		if v > bt:
			bt = v
			best = b
	if tot < min_segundos:
		return {"nombre": "", "fraccion": 0.0}
	return {"nombre": best, "fraccion": bt / tot}

## Cuánto de un tipo de evento ocurrió en un bioma (tala, fuego, fruto tomado...).
func eventos_en_bioma(nombre: String, tipo: String) -> float:
	return float((bioma_eventos.get(nombre, {}) as Dictionary).get(tipo, 0.0))

## Salud (0..1) de la zona donde está `pos`. 1 = sana.
func salud_en(pos: Vector3) -> float:
	if eco == null or not is_instance_valid(eco):
		return 1.0
	return float(salud_zona.get(eco.get_bioma_nombre(pos), 1.0))

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
	vinculo *= 0.5                       # la relación se enfría con la muerte, pero no se borra
	_etapa_prev = etapa_idx()
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
	tumbas.clear()
	refugios.clear()
	vinculo = 0.0
	_etapa_prev = etapa_idx()
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
	bioma_tiempo.clear()
	bioma_eventos.clear()
	salud_zona.clear()
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
		"vida": vida, "ciclo": ciclo, "ultimo_final": ultimo_final, "vinculo": vinculo, "tumbas": tumbas, "refugios": refugios, "base": base, "valor": valor, "sensibilidad": sensibilidad,
		"total": total, "vida_actual": vida_actual,
		"calor_paso": _claves(calor_paso), "calor_dano": _claves(calor_dano),
		"bioma_tiempo": bioma_tiempo, "bioma_eventos": bioma_eventos, "salud_zona": salud_zona,
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
	vinculo = float(d.get("vinculo", 0.0))
	tumbas = d.get("tumbas", []) as Array
	refugios = d.get("refugios", []) as Array
	_etapa_prev = etapa_idx()
	sensibilidad = float(d.get("sensibilidad", 1.0))
	for e: String in EMOCIONES:
		base[e] = float((d.get("base", {}) as Dictionary).get(e, base[e]))
		valor[e] = float((d.get("valor", {}) as Dictionary).get(e, base[e]))
	for c: String in CONTADORES:
		total[c] = float((d.get("total", {}) as Dictionary).get(c, 0.0))
		vida_actual[c] = float((d.get("vida_actual", {}) as Dictionary).get(c, 0.0))
	calor_paso = _celdas(d.get("calor_paso", {}))
	calor_dano = _celdas(d.get("calor_dano", {}))
	bioma_tiempo = d.get("bioma_tiempo", {}) as Dictionary
	bioma_eventos = d.get("bioma_eventos", {}) as Dictionary
	salud_zona = d.get("salud_zona", {}) as Dictionary
	return true

