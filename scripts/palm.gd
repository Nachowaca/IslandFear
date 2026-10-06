@tool
class_name Palm
extends Node3D

## Palmera low-poly: tronco inclinado + frondas dispuestas en círculo.
const FROND_COUNT := 7

func _ready() -> void:
	for c: Node in get_children():
		c.queue_free()
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.45, 0.32, 0.2)
	var leaf_mat: ShaderMaterial = Wind.make(Color(0.2, 0.5, 0.2), -0.9, 1.8, 0.22, 0.05, 1.4)

	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.2
	cyl.height = 3.2
	cyl.radial_segments = 6
	cyl.material = trunk_mat
	trunk.mesh = cyl
	trunk.position = Vector3(0.15, 1.6, 0)
	trunk.rotation.z = -0.1
	add_child(trunk)

	var top := Node3D.new()
	top.position = Vector3(0.32, 3.15, 0)
	add_child(top)
	for i in FROND_COUNT:
		var pivot := Node3D.new()
		pivot.rotation.y = TAU * i / FROND_COUNT
		top.add_child(pivot)
		var leaf := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.6, 1.8, 0.04)
		prism.material = leaf_mat
		leaf.mesh = prism
		# punta hacia afuera y algo caída
		leaf.rotation = Vector3(0, 0, -1.2)
		leaf.position = Vector3(0.8, -0.15, 0)
		pivot.add_child(leaf)
