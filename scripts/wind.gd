class_name Wind
extends RefCounted

## Fábrica de materiales de follaje que se mecen con el viento.

const SHADER: Shader = preload("res://shaders/wind_foliage.gdshader")

static var _registro: Array = []
static var _mood: float = 0.0
static var _gust: float = 0.0
static var _clima: float = 0.0

static func get_mood() -> float:
	return _mood

## Ánimo de la isla (-1 tensa/enojada … +1 serena): la flora se mece y se ve distinta, muy sutil.
static func set_mood(k: float) -> void:
	_mood = clampf(k, -1.0, 1.0)
	var vivos: Array = []
	for w: WeakRef in _registro:
		var mat: ShaderMaterial = w.get_ref() as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("mood", _mood)
			vivos.append(w)
	_registro = vivos

## Racha de viento que sacude toda la vegetación (0 = normal, 1 = muy fuerte). La usa la isla.
static func set_gust(k: float) -> void:
	_gust = k
	_aplicar_viento()

## Viento del clima (0..1): se suma a las rachas de la isla.
static func set_clima(k: float) -> void:
	_clima = k
	_aplicar_viento()

static func _aplicar_viento() -> void:
	var k: float = clampf(_gust + _clima, 0.0, 1.4)
	var vivos: Array = []
	for w: WeakRef in _registro:
		var mat: ShaderMaterial = w.get_ref() as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("gust_strength", 1.0 + k * 3.5)
			mat.set_shader_parameter("speed", 1.2 + k * 2.0)
			vivos.append(w)
	_registro = vivos

## Registra un material con shader de viento ya creado (para que las rachas lo afecten).
static func register(m: ShaderMaterial) -> void:
	_registro.append(weakref(m))
	m.set_shader_parameter("mood", _mood)

static func make(color: Color, base_y: float, height_ref: float, sway: float, flutter: float = 0.0, speed: float = 1.2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	_registro.append(weakref(m))
	m.set_shader_parameter("mood", _mood)
	m.shader = SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("base_y", base_y)
	m.set_shader_parameter("height_ref", height_ref)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("flutter", flutter)
	m.set_shader_parameter("speed", speed)
	return m
