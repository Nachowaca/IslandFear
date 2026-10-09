extends Node

## Autoload "Inventario": 10 espacios con apilado. Se vacía al morir (no se guarda en disco).

signal cambiado
signal seleccion_cambiada(indice: int)

const ESPACIOS: int = 10
const MAX_PILA: int = 9

var espacios: Array = []        ## cada uno: null o {"id": String, "n": int}
var seleccionado: int = 0
const COFRE_ESPACIOS: int = 30
var cofre: Array = []           ## baúl de la playa: 30 celdas, cada una null o {"id", "n"}
var descubiertos: Dictionary = {}   ## item_id -> true (investigados)
var linterna_carga: float = 0.0     ## segundos de luz que le quedan a la batería puesta
var linterna_on: bool = false

const COFRE_PATH: String = "user://cofre.json"

func _ready() -> void:
	vaciar()
	_cofre_cargar()

## Vacía la mochila (al morir). El baúl NO se toca: guarda su contenido entre vidas.
func vaciar() -> void:
	espacios.clear()
	for i in ESPACIOS:
		espacios.append(null)
	seleccionado = 0
	descubiertos.clear()
	linterna_carga = 0.0
	linterna_on = false
	cambiado.emit()

## Vacía el baúl (solo al empezar un ciclo nuevo de 7 vidas).
func vaciar_cofre() -> void:
	cofre.clear()
	for k in COFRE_ESPACIOS:
		cofre.append(null)
	_cofre_guardar()
	cambiado.emit()

func cofre_cantidad() -> int:
	var t: int = 0
	for e: Variant in cofre:
		if e != null:
			t += int(e["n"])
	return t

func _cofre_cargar() -> void:
	cofre.clear()
	for k in COFRE_ESPACIOS:
		cofre.append(null)
	if not FileAccess.file_exists(COFRE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(COFRE_PATH))
	if parsed is Array:
		var arr: Array = parsed
		for i in mini(arr.size(), COFRE_ESPACIOS):
			var e: Variant = arr[i]
			if e is Dictionary and e.has("id") and e.has("n"):
				cofre[i] = {"id": str(e["id"]), "n": int(e["n"])}

func _cofre_guardar() -> void:
	var f: FileAccess = FileAccess.open(COFRE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(cofre))

## La isla se entera de que guardás cosas en el baúl.
func _avisar_isla(n: int) -> void:
	var c: Node = get_tree().get_first_node_in_group("cofre") if is_inside_tree() else null
	var pos: Vector3 = (c as Node3D).global_position if c is Node3D else Vector3.ZERO
	Isla.registrar_evento("cofre", pos, float(n))

## Devuelve cuántas unidades NO entraron (0 = entró todo).
func agregar(id: String, n: int) -> int:
	var resto: int = n
	for i in ESPACIOS:                              # primero completa pilas existentes
		var e: Variant = espacios[i]
		if e != null and str(e["id"]) == id and int(e["n"]) < MAX_PILA:
			var cabe: int = MAX_PILA - int(e["n"])
			var t: int = mini(cabe, resto)
			e["n"] = int(e["n"]) + t
			resto -= t
			if resto <= 0:
				break
	var i: int = 0
	while resto > 0 and i < ESPACIOS:               # luego espacios vacíos
		if espacios[i] == null:
			var t2: int = mini(MAX_PILA, resto)
			espacios[i] = {"id": id, "n": t2}
			resto -= t2
		i += 1
	if resto < n:
		cambiado.emit()
	return resto

## Agrega a una lista de celdas cualquiera (mochila o baúl). Devuelve lo que NO entró.
func _agregar_a(arr: Array, id: String, n: int) -> int:
	var resto: int = n
	for i in arr.size():
		var e: Variant = arr[i]
		if e != null and str(e["id"]) == id and int(e["n"]) < MAX_PILA:
			var t: int = mini(MAX_PILA - int(e["n"]), resto)
			e["n"] = int(e["n"]) + t
			resto -= t
			if resto <= 0:
				return 0
	for i in arr.size():
		if resto <= 0:
			break
		if arr[i] == null:
			var t2: int = mini(MAX_PILA, resto)
			arr[i] = {"id": id, "n": t2}
			resto -= t2
	return resto

## Guarda en el baúl. Devuelve lo que NO entró.
## Una vez por vida la isla deja una semilla de paz en el baúl (si no hay ya una en la mochila o el baúl).
func sembrar_paz() -> void:
	if cantidad("semilla_paz") > 0:
		return
	for e: Variant in cofre:
		if e != null and str(e["id"]) == "semilla_paz":
			return
	if _agregar_a(cofre, "semilla_paz", 1) < 1:
		_cofre_guardar()
		cambiado.emit()

func cofre_agregar(id: String, n: int) -> int:
	var resto: int = _agregar_a(cofre, id, n)
	if resto < n:
		_cofre_guardar()
		_avisar_isla(n - resto)
		cambiado.emit()
	return resto

## Pasa hasta n unidades de una celda a la otra lista (mochila <-> baúl). Devuelve cuántas pasaron.
func mover(desde_cofre: bool, i: int, n: int) -> int:
	var src: Array = cofre if desde_cofre else espacios
	var dst: Array = espacios if desde_cofre else cofre
	var e: Variant = src[i]
	if e == null:
		return 0
	var toma: int = mini(n, int(e["n"]))
	var resto: int = _agregar_a(dst, str(e["id"]), toma)
	var movido: int = toma - resto
	if movido > 0:
		e["n"] = int(e["n"]) - movido
		if int(e["n"]) <= 0:
			src[i] = null
		_cofre_guardar()
		if not desde_cofre:
			_avisar_isla(movido)
		cambiado.emit()
	return movido

func quitar_en(i: int, n: int) -> int:
	var e: Variant = espacios[i]
	if e == null:
		return 0
	var t: int = mini(n, int(e["n"]))
	e["n"] = int(e["n"]) - t
	if int(e["n"]) <= 0:
		espacios[i] = null
	cambiado.emit()
	return t

func quitar(id: String, n: int) -> bool:
	if cantidad(id) < n:
		return false
	var falta: int = n
	for i in ESPACIOS:
		var e: Variant = espacios[i]
		if e != null and str(e["id"]) == id:
			falta -= quitar_en(i, falta)
			if falta <= 0:
				break
	return true

func cantidad(id: String) -> int:
	var total: int = 0
	for e: Variant in espacios:
		if e != null and str(e["id"]) == id:
			total += int(e["n"])
	return total

func tiene(id: String) -> bool:
	return cantidad(id) > 0

func item_seleccionado() -> Variant:
	return espacios[seleccionado]

## Cambia una unidad del espacio i por otro objeto (la botella vacía pasa a llena, etc.).
func transformar_en(i: int, nuevo_id: String) -> void:
	var e: Variant = espacios[i]
	if e == null:
		return
	if int(e["n"]) <= 1:
		espacios[i] = {"id": nuevo_id, "n": 1}
		cambiado.emit()
	else:
		quitar_en(i, 1)
		agregar(nuevo_id, 1)

func seleccionar(i: int) -> void:
	seleccionado = posmod(i, ESPACIOS)
	seleccion_cambiada.emit(seleccionado)
	cambiado.emit()

func descubrir(id: String) -> void:
	descubiertos[id] = true
