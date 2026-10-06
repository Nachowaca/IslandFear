class_name WorldItem
extends Node3D

## Objeto recolectable del mundo. Todavía no se recoge (eso viene con el sistema de interacción),
## pero ya lleva sus datos: qué es, cuánto da y si es comestible / venenoso.
## Está en el grupo "pickup" para que el sistema de interacción lo encuentre.

@export var item_id: String = "madera"
@export var display_name: String = "Madera"
@export var amount: int = 1
@export var edible: bool = false
@export var poisonous: bool = false
@export var hydration: float = 0.0 ## cuánta sed calma
@export var nutrition: float = 0.0 ## cuánta hambre calma
@export var interact_radius: float = 1.6

func _ready() -> void:
	add_to_group("pickup")

func get_prompt() -> String:
	return "E: recoger %s" % display_name
