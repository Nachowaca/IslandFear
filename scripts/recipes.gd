class_name Recipes
extends RefCounted

## Recetas de combinación (tecla C). "in" = lo que hay que tener, "consume" = lo que se gasta (el resto se conserva),
## "out" = lo que se obtiene. "fuego" es especial: se enciende una fogata en el suelo.

const LIST: Array[Dictionary] = [
	{"id": "piedra_afilada", "name": "Cuchilla de piedra", "desc": "Golpeás una piedra contra otra hasta lascarla.",
		"in": {"piedra": 2}, "consume": {"piedra": 1}, "out": {"piedra_afilada": 1}},
	{"id": "cuerda_liana", "name": "Cuerda de lianas", "desc": "Trenzás dos lianas.",
		"in": {"liana": 2}, "consume": {"liana": 2}, "out": {"cuerda": 1}},
	{"id": "cuerda_hojas", "name": "Cuerda de hojas", "desc": "Deshilás y trenzás hojas grandes.",
		"in": {"hoja_grande": 3}, "consume": {"hoja_grande": 3}, "out": {"cuerda": 1}},
	{"id": "hacha", "name": "Hacha de piedra", "desc": "Atás la cuchilla a una rama firme.",
		"in": {"rama": 1, "piedra_afilada": 1}, "consume": {"rama": 1, "piedra_afilada": 1}, "out": {"hacha": 1}},
	{"id": "lanza", "name": "Lanza", "desc": "Atás la cuchilla en la punta de una rama, con cuerda.",
		"in": {"rama": 1, "piedra_afilada": 1, "cuerda": 1}, "consume": {"rama": 1, "piedra_afilada": 1, "cuerda": 1}, "out": {"lanza": 1}},
	{"id": "figurilla_barro", "name": "Figurilla de barro", "desc": "Modelás arcilla con las manos, con paciencia.",
		"in": {"arcilla": 2}, "consume": {"arcilla": 2}, "out": {"figurilla_barro": 1}},
	{"id": "fuego", "name": "Encender fuego", "desc": "Chocás dos piedras junto a paja seca o leña.",
		"in": {"piedra": 2}, "any": ["paja", "rama", "madera"], "consume": {}, "out": {}, "special": "fuego"},
]

static func can(r: Dictionary) -> bool:
	for id: String in (r["in"] as Dictionary).keys():
		if Inventario.cantidad(id) < int(r["in"][id]):
			return false
	if r.has("any"):
		var ok: bool = false
		for id2: String in r["any"]:
			if Inventario.cantidad(id2) > 0:
				ok = true
		return ok
	return true

## Texto de los ingredientes, por ejemplo "2 Piedra, 1 Rama".
static func ingredients_text(r: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in (r["in"] as Dictionary).keys():
		parts.append("%d %s" % [int(r["in"][id]), ItemDB.display_name(id)])
	if r.has("any"):
		var names: Array[String] = []
		for id2: String in r["any"]:
			names.append(ItemDB.display_name(id2))
		parts.append(" o ".join(names))
	return ", ".join(parts)
