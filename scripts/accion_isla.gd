class_name AccionIsla
extends Resource

## Una acción que la isla puede elegir. Se edita desde el inspector (res://data/acciones/*.tres).
## Puntaje = base + Σ(emoción × peso_emocion) + Σ(contexto × peso_contexto).
## Emociones: confianza, enojo, miedo, curiosidad (0..1).
## Contexto: noche, dia, quieto, moviendo, corriendo, en_cueva, playa, bosque, sagrado, tras_accion (0..1).

@export var id: String = ""
@export var nombre: String = ""
@export var cooldown: float = 30.0
@export var costo: float = 3.0                ## energía que gasta
@export var dano: bool = false                ## ¿puede lastimar? (solo tras el estudio, con agravios y aviso previo)
@export var min_hostilidad: float = 0.0       ## hostilidad mínima (solo acciones con daño)
@export var implementada: bool = true         ## false = solo imprime en consola por ahora
@export var base: float = 0.3
@export var peso_emocion: Dictionary = {}
@export var peso_contexto: Dictionary = {}

func puntuar(emociones: Dictionary, contexto: Dictionary) -> Dictionary:
	var total: float = base
	var razones: Array[String] = []
	for e: String in peso_emocion.keys():
		var aporte: float = float(emociones.get(e, 0.0)) * float(peso_emocion[e])
		total += aporte
		if absf(aporte) >= 0.08:
			razones.append("%s %+.2f" % [e, aporte])
	for c: String in peso_contexto.keys():
		var aporte: float = float(contexto.get(c, 0.0)) * float(peso_contexto[c])
		total += aporte
		if absf(aporte) >= 0.08:
			razones.append("%s %+.2f" % [c, aporte])
	return {"puntaje": maxf(total, 0.0), "razones": razones}
