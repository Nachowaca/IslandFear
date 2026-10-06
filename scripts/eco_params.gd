class_name EcoParams
extends Resource
## Parámetros del ecosistema. Se editan en el inspector de EcoMap (o guardando un .tres).

@export var eco_seed: int = 7
## Tamaño de celda de las capas (m). Más chico = más detalle y más memoria.
@export_range(1.0, 6.0, 0.5) var cell_size: float = 2.0
## Altura a partir de la cual consideramos que hay tierra firme (m).
@export var land_height: float = 0.35
## Altura a partir de la cual se considera cumbre / zona alta (m).
@export var high_height: float = 9.0
## Pendiente (en grados) a partir de la cual el terreno se considera roquedal.
@export_range(10.0, 80.0, 1.0) var steep_degrees: float = 32.0

@export_group("Agua y humedad")
## Humedad de fondo de toda la isla (clima tropical = alta).
@export_range(0.0, 0.8, 0.02) var base_humidity: float = 0.46
## Distancia (m) a la que la humedad del agua cae a ~37 %.
@export var humidity_reach: float = 45.0
## Cuánto humedece el mar comparado con agua dulce (0..1).
@export_range(0.0, 1.0, 0.05) var sea_humidity: float = 0.7
## Radio (m) con el que se compara la altura para detectar valles.
@export var valley_radius: float = 16.0

@export_group("Suelo y bioma")
## Ancho (m) de la franja de arena junto al mar.
@export var sand_width: float = 12.0
@export var sand_max_height: float = 2.2
## Humedad mínima para tierra fértil.
@export_range(0.0, 1.0, 0.05) var fertile_humidity: float = 0.5

@export_group("Zonas misteriosas")
@export var mystery_seed: int = 31
## Cuántos claros misteriosos (≈5-10 % de la tierra en total).
@export var mystery_count: int = 6
@export var mystery_radius: float = 11.0
## Distancia mínima entre centros (m).
@export var mystery_min_dist: float = 40.0
