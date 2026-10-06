class_name ItemDB
extends RefCounted

## Catálogo de objetos del juego. Una entrada por item_id.
## hint = lo que se aprende al INVESTIGAR (a propósito vago: la isla guarda misterio).
## food: se puede probar/comer. offering: sirve como ofrenda para la isla.

const DEFS: Dictionary = {
	"madera": {"name": "Tronco", "color": Color(0.45, 0.3, 0.17), "shape": "log", "food": false, "offering": false,
		"hint": "Madera seca y pesada. Sirve para hacer fuego y construir. Hace falta algo afilado para trabajarla."},
	"rama": {"name": "Rama", "color": Color(0.5, 0.36, 0.2), "shape": "stick", "food": false, "offering": false,
		"hint": "Una rama firme. Buena para un mango, una palanca o para alimentar el fuego."},
	"piedra": {"name": "Piedra", "color": Color(0.55, 0.56, 0.6), "shape": "rock", "food": false, "offering": false,
		"hint": "Una piedra del tamaño de la mano. Si la golpeás contra otra, quizás se lasque y quede con filo."},
	"arcilla": {"name": "Arcilla", "color": Color(0.7, 0.5, 0.32), "shape": "rock", "food": false, "offering": false,
		"hint": "Barro denso y pegajoso. Se endurece con el calor."},
	"coco": {"name": "Coco", "color": Color(0.33, 0.21, 0.11), "shape": "ball", "food": true, "nutrition": 0.15, "hydration": 0.30, "offering": true,
		"hint": "Un coco caído. Dentro hay agua y pulpa. Es seguro."},
	"bayas": {"name": "Bayas", "color": Color(0.75, 0.1, 0.2), "shape": "berries", "food": true, "nutrition": 0.07, "hydration": 0.10, "offering": true,
		"hint": "Bayas rojas de un arbusto bajo. Las aves las picotean: debería ser seguro comerlas."},
	"raiz": {"name": "Raíz comestible", "color": Color(0.9, 0.5, 0.15), "shape": "root", "food": true, "nutrition": 0.22, "hydration": 0.04, "offering": true,
		"hint": "Un tubérculo naranja. Crudo es duro, pero nutre."},
	"hierba": {"name": "Hierba medicinal", "color": Color(0.5, 0.75, 0.35), "shape": "herb", "food": true, "heal": 12.0, "hydration": 0.03, "offering": true,
		"hint": "Hoja aromática de olor limpio. Huele a algo que cura."},
	"hongo_comestible": {"name": "Hongo pardo", "color": Color(0.55, 0.38, 0.22), "shape": "mushroom", "food": true, "nutrition": 0.05, "hydration": 0.07, "offering": true,
		"hint": "Sombrero pardo y liso, sin manchas. Se parece a los que se comen, pero no estás seguro."},
	"hongo_venenoso": {"name": "Hongo rojo", "color": Color(0.8, 0.1, 0.1), "shape": "mushroom", "food": true, "poison": 18.0, "offering": false,
		"hint": "Sombrero rojo con manchas blancas. En la naturaleza los colores vivos suelen ser una advertencia."},
	"piedra_afilada": {"name": "Cuchilla de piedra", "color": Color(0.7, 0.72, 0.78), "shape": "blade", "food": false, "offering": false, "tool": "corte",
		"hint": "Una lasca de piedra con filo. Corta lianas, hojas y fibras. Para talar un árbol hace falta algo más pesado."},
	"hacha": {"name": "Hacha de piedra", "color": Color(0.5, 0.36, 0.2), "shape": "axe", "food": false, "offering": false, "tool": "tala",
		"hint": "Una cuchilla atada a un mango de rama. Pesada y torpe, pero sirve para talar. Hacen falta varios golpes por árbol."},
	"cuerda": {"name": "Cuerda", "color": Color(0.72, 0.64, 0.46), "shape": "rope", "food": false, "offering": false,
		"hint": "Fibras trenzadas. Resiste bastante. Sirve para atar herramientas."},
	"liana": {"name": "Liana", "color": Color(0.3, 0.5, 0.22), "shape": "vine", "food": false, "offering": false,
		"hint": "Un tallo largo y flexible. Trenzando varias se hace cuerda."},
	"hoja_grande": {"name": "Hoja grande", "color": Color(0.25, 0.55, 0.2), "shape": "leaf", "food": false, "offering": false,
		"hint": "Una hoja de palmera, larga y fibrosa. Con varias se puede trenzar cuerda."},
	"paja": {"name": "Paja seca", "color": Color(0.85, 0.75, 0.4), "shape": "straw", "food": false, "offering": false,
		"hint": "Hierba reseca que prende con una chispa. Perfecta como yesca."},
	"lanza": {"name": "Lanza", "color": Color(0.5, 0.36, 0.2), "shape": "spear", "food": false, "offering": false, "tool": "caza",
		"hint": "Una rama larga con la cuchilla atada en la punta. Para cazar, cuando haya a quién."},
	"concha": {"name": "Concha", "color": Color(0.95, 0.78, 0.72), "shape": "shell", "food": false, "offering": true,
		"hint": "Una concha de nácar. Ya no hay nadie dentro. Es hermosa; a la isla quizás le guste."},
}

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {"name": id.capitalize(), "color": Color(0.7, 0.7, 0.7), "shape": "ball", "food": false, "offering": false, "hint": "No sabés qué es."})

static func display_name(id: String) -> String:
	return str(get_def(id)["name"])

static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

static func _mi(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)

static func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 7
	s.rings = 4
	return s

static func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 6
	return c

## Modelo sencillo de un objeto soltado en el suelo (low-poly con primitivas).
static func make_visual(id: String) -> Node3D:
	var root := Node3D.new()
	var d: Dictionary = get_def(id)
	var c: Color = d["color"]
	match str(d["shape"]):
		"log":
			_mi(root, _cyl(0.14, 0.16, 1.0), c, Vector3(0, 0.15, 0), Vector3(PI / 2.0, 0, 0))
			_mi(root, _cyl(0.1, 0.1, 0.02), Color(0.75, 0.6, 0.4), Vector3(0, 0.15, -0.5), Vector3(PI / 2.0, 0, 0))
		"stick":
			_mi(root, _cyl(0.025, 0.035, 0.8), c, Vector3(0, 0.04, 0), Vector3(PI / 2.0, 0, 0.1))
		"rock":
			_mi(root, _sph(0.13), c, Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(1.0, 0.65, 0.85))
		"berries":
			for k in 4:
				_mi(root, _sph(0.045), c, Vector3(cos(float(k) * 1.6) * 0.08, 0.05, sin(float(k) * 1.6) * 0.08))
		"root":
			_mi(root, _cyl(0.0, 0.07, 0.2), c, Vector3(0, 0.07, 0), Vector3(PI / 2.0, 0, 0))
		"herb":
			for k in 5:
				var a: float = TAU * float(k) / 5.0
				var p := PrismMesh.new()
				p.size = Vector3(0.08, 0.24, 0.012)
				_mi(root, p, c, Vector3(cos(a) * 0.06, 0.08, sin(a) * 0.06), Vector3(sin(a) * 0.5, -a, -cos(a) * 0.5))
		"mushroom":
			_mi(root, _cyl(0.025, 0.035, 0.12), Color(0.9, 0.85, 0.72), Vector3(0, 0.06, 0))
			_mi(root, _sph(0.09), c, Vector3(0, 0.13, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
		"blade":
			_mi(root, _sph(0.1), c, Vector3(0, 0.03, 0), Vector3(0, 0.5, 0), Vector3(1.4, 0.2, 0.7))
		"axe":
			_mi(root, _cyl(0.025, 0.03, 0.7), c, Vector3(0, 0.05, 0), Vector3(PI / 2.0, 0, 0.1))
			_mi(root, _sph(0.09), Color(0.7, 0.72, 0.78), Vector3(0, 0.07, -0.3), Vector3(0, 0, 0), Vector3(0.4, 1.0, 1.2))
		"rope":
			var tor := TorusMesh.new()
			tor.inner_radius = 0.05
			tor.outer_radius = 0.12
			tor.rings = 10
			tor.ring_segments = 5
			_mi(root, tor, c, Vector3(0, 0.05, 0))
		"vine":
			_mi(root, _cyl(0.012, 0.014, 0.9), c, Vector3(0, 0.03, 0), Vector3(PI / 2.0, 0, 0.3))
		"leaf":
			var pr := PrismMesh.new()
			pr.size = Vector3(0.25, 0.9, 0.02)
			_mi(root, pr, c, Vector3(0, 0.04, 0), Vector3(PI / 2.0, 0, 0))
		"straw":
			for k in 7:
				var a2: float = float(k) * 0.9
				_mi(root, _cyl(0.004, 0.01, 0.3), c, Vector3(cos(a2) * 0.05, 0.12, sin(a2) * 0.05), Vector3(sin(a2) * 0.4, 0, cos(a2) * 0.4))
		"spear":
			_mi(root, _cyl(0.02, 0.03, 1.4), c, Vector3(0, 0.05, 0), Vector3(PI / 2.0, 0, 0.1))
			_mi(root, _sph(0.06), Color(0.7, 0.72, 0.78), Vector3(0, 0.06, -0.7), Vector3(0, 0, 0), Vector3(0.5, 0.5, 1.8))
		"shell":
			_mi(root, _sph(0.09), c, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.0, 0.45, 0.85))
		_:
			_mi(root, _sph(0.13), c, Vector3(0, 0.13, 0))
	return root
