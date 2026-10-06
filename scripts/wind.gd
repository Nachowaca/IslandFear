class_name Wind
extends RefCounted

## Fábrica de materiales de follaje que se mecen con el viento.

const SHADER: Shader = preload("res://shaders/wind_foliage.gdshader")

static func make(color: Color, base_y: float, height_ref: float, sway: float, flutter: float = 0.0, speed: float = 1.2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("base_y", base_y)
	m.set_shader_parameter("height_ref", height_ref)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("flutter", flutter)
	m.set_shader_parameter("speed", speed)
	return m
