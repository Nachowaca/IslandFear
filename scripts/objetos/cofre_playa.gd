class_name CofrePlaya
extends Node3D

## Baúl de madera fijo en la playa de llegada. Con E se abre (CofreUi). Tiene grabado "Welcome!".
## Guarda los objetos que la mochila no puede llevar. Frente (+Z) hacia el mar.

var _tapa: Node3D
var _tween: Tween

func _mat(c: Color, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _ready() -> void:
	add_to_group("cofre")
	var madera: StandardMaterial3D = _mat(Color(0.58, 0.34, 0.15))
	var oscura: StandardMaterial3D = _mat(Color(0.34, 0.2, 0.1))
	var laton: StandardMaterial3D = _mat(Color(0.7, 0.55, 0.25), 0.5, 0.6)
	# cuerpo
	_mi(self, _box(Vector3(0.95, 0.5, 0.62)), madera, Vector3(0, 0.25, 0))
	for x: float in [-0.3, 0.3]:
		_mi(self, _box(Vector3(0.1, 0.52, 0.66)), oscura, Vector3(x, 0.25, 0))
	# tapa abovedada con bisagra atrás
	_tapa = Node3D.new()
	_tapa.position = Vector3(0, 0.5, -0.31)
	add_child(_tapa)
	var cil := CylinderMesh.new()
	cil.top_radius = 0.31
	cil.bottom_radius = 0.31
	cil.height = 0.95
	cil.radial_segments = 10
	_mi(_tapa, cil, madera, Vector3(0, 0, 0.31), Vector3(0, 0, PI / 2.0))
	for x2: float in [-0.3, 0.3]:
		var banda := CylinderMesh.new()
		banda.top_radius = 0.325
		banda.bottom_radius = 0.325
		banda.height = 0.1
		banda.radial_segments = 10
		_mi(_tapa, banda, oscura, Vector3(x2, 0, 0.31), Vector3(0, 0, PI / 2.0))
	_mi(_tapa, _box(Vector3(0.12, 0.14, 0.05)), laton, Vector3(0, -0.04, 0.64))
	# grabado
	var lb := Label3D.new()
	lb.text = "Welcome!"
	lb.font = UiTheme.BOLD
	lb.font_size = 72
	lb.pixel_size = 0.0023
	lb.modulate = Color(0.85, 0.7, 0.4)
	lb.outline_modulate = Color(0.12, 0.07, 0.03)
	lb.outline_size = 12
	lb.shaded = false
	lb.double_sided = false
	lb.position = Vector3(0, 0.2, 0.338)
	add_child(lb)
	# colisión
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.95, 0.8, 0.62)
	cs.shape = sh
	cs.position = Vector3(0, 0.4, 0)
	body.add_child(cs)
	add_child(body)

func set_abierto(abierto: bool) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_tapa, "rotation:x", -1.15 if abierto else 0.0, 0.35).set_trans(Tween.TRANS_SINE)
