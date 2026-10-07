extends Node

## Autoload "Inventario": 10 espacios con apilado. Se vacía al morir (no se guarda en disco).

signal cambiado
signal seleccion_cambiada(indice: int)

const ESPACIOS: int = 10
const MAX_PILA: int = 9

var espacios: Array = []        ## cada uno: null o {"id": String, "n": int}
var seleccionado: int = 0
var descubiertos: Dictionary = {}   ## item_id -> true (investigados)
var linterna_carga: float = 0.0     ## segundos de luz que le quedan a la batería puesta
var linterna_on: bool = false

func _ready() -> void:
	vaciar()

func vaciar() -> void:
	espacios.clear()
	for i in ESPACIOS:
		espacios.append(null)
	seleccionado = 0
	descubiertos.clear()
	linterna_carga = 0.0
	linterna_on = false
	cambiado.emit()

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
