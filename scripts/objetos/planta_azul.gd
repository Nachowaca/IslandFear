class_name PlantaAzul
extends Node3D

## Brote nacido de una semilla brillante. Seco no crece: hay que regarlo con una botella con agua (T).
## Regado, crece unos minutos y se vuelve un arbolito luminoso que da frutos dorados (ofrenda y comida).
## Cuidarlo es un gesto hacia la isla.

const GROW_TIME: float = 120.0
const FRUTOS: int = 3

var regado: bool = false
var madura: bool = false
var _edad: float = 0.0
var _tronco: MeshInstance3D
var _copa: MeshInstance3D
var _luz: OmniLight3D
var _mat_copa: StandardMaterial3D
var _frutos: Array[WorldItem] = []

func _ready() -> void:
	add_to_group("planta_azul")
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.3, 0.25, 0.28)
	bark.roughness = 1.0
	_tronco = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.06
	cyl.height = 1.0
	cyl.radial_segments = 6
	_tronco.mesh = cyl
	_tronco.material_override = bark
	_tronco.position = Vector3(0, 0.5, 0)
	add_child(_tronco)
	_mat_copa = StandardMaterial3D.new()
	_mat_copa.albedo_color = Color(0.3, 0.6, 0.9)
	_mat_copa.emission_enabled = true
	_mat_copa.emission = Color(0.3, 0.65, 1.0)
	_mat_copa.emission_energy_multiplier = 1.4
	_copa = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.5
	sp.height = 0.9
	sp.radial_segments = 8
	sp.rings = 5
	_copa.mesh = sp
	_copa.material_override = _mat_copa
	add_child(_copa)
	_luz = OmniLight3D.new()
	_luz.light_color = Color(0.4, 0.7, 1.0)
	_luz.omni_range = 4.0
	add_child(_luz)
	_aplicar(0.0)

func regar() -> bool:
	if regado:
		return false
	regado = true
	return true

func _process(delta: float) -> void:
	if not regado or madura:
		return
	_edad += delta
	var k: float = clampf(_edad / GROW_TIME, 0.0, 1.0)
	_aplicar(k)
	if k >= 1.0:
		_madurar()

## k 0..1: tamaño. Sin regar queda como brote chiquito (0).
func _aplicar(k: float) -> void:
	var h: float = lerpf(0.3, 2.4, k)
	_tronco.scale = Vector3(lerpf(0.6, 1.4, k), h, lerpf(0.6, 1.4, k))
	_tronco.position.y = h * 0.5
	var cs: float = lerpf(0.25, 1.6, k)
	_copa.scale = Vector3(cs, cs * 0.8, cs)
	_copa.position.y = h + cs * 0.2
	_luz.position.y = h + 0.3
	_luz.light_energy = lerpf(0.5, 1.6, k)
	_mat_copa.emission_energy_multiplier = lerpf(1.0, 1.8, k) if regado else 0.6

func _madurar() -> void:
	madura = true
	_mat_copa.albedo_color = Color(0.35, 0.65, 0.5)
	_mat_copa.emission = Color(0.5, 0.9, 0.6)
	for k in FRUTOS:
		var a: float = TAU * float(k) / float(FRUTOS) + 0.5
		var it := WorldItem.new()
		it.item_id = "fruto_dorado"
		it.display_name = ItemDB.display_name("fruto_dorado")
		it.edible = true
		it.nutrition = 0.35
		it.hydration = 0.15
		add_child(it)
		it.add_child(ItemDB.make_visual("fruto_dorado"))
		it.position = Vector3(cos(a) * 0.9, 0.0, sin(a) * 0.9)
		_frutos.append(it)
