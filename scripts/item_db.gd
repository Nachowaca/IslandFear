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
	"tela_grande": {"name": "Tela grande", "color": Color(0.78, 0.72, 0.58), "shape": "cloth_l", "food": false, "offering": false,
		"hint": "Un lienzo grande, curtido por el sol y la sal. Cubriría a una persona."},
	"tela_chica": {"name": "Tela chica", "color": Color(0.7, 0.5, 0.38), "shape": "cloth_s", "food": false, "offering": false,
		"hint": "Un retazo de tela. Sirve para envolver, vendar o atar."},
	"linterna": {"name": "Linterna", "color": Color(0.25, 0.27, 0.3), "shape": "flashlight", "food": false, "offering": false,
		"hint": "Una linterna de metal. Aprieto el botón y no pasa nada: le faltan las pilas."},
	"bateria": {"name": "Batería", "color": Color(0.2, 0.5, 0.25), "shape": "battery", "food": false, "offering": false,
		"hint": "Una pila cilíndrica. Todavía guarda carga. Parece de otro mundo."},
	"botella_vacia": {"name": "Botella vacía", "color": Color(0.5, 0.75, 0.8), "shape": "bottle", "food": false, "offering": false,
		"hint": "Una botella de vidrio con tapón. Podría llevar agua: con T cerca del estanque la llenás."},
	"semilla_azul": {"name": "Semilla brillante", "color": Color(0.3, 0.7, 1.0), "shape": "seed", "food": false, "offering": false,
		"hint": "Una semilla con un brillo azul tenue. Está viva. Con T la plantás en tierra firme. Va a necesitar agua."},
	"resina": {"name": "Resina", "color": Color(0.8, 0.5, 0.1), "shape": "resin", "food": false, "offering": false,
		"hint": "Una gota dura de savia ámbar. Pegajosa si se la calienta."},
	"espina": {"name": "Espina larga", "color": Color(0.9, 0.88, 0.78), "shape": "thorn", "food": false, "offering": false,
		"hint": "Una espina curva y firme. Atada a una cuerda podría pescar."},
	"pala_concha": {"name": "Pala de concha", "color": Color(0.85, 0.75, 0.7), "shape": "shovel", "food": false, "offering": false, "tool": "cavar",
		"hint": "Una concha enorme atada a un palo. Sirve para cavar."},
	"bateria_gastada": {"name": "Batería gastada", "color": Color(0.35, 0.33, 0.3), "shape": "battery", "food": false, "offering": false, "contaminante": true,
		"hint": "Una pila vacía y corroída. Huele a metal y a químico. La isla no la querría cerca."},
	"botella_agua": {"name": "Botella con agua", "color": Color(0.4, 0.65, 0.95), "shape": "bottle", "food": false, "offering": false,
		"hint": "Una botella llena de agua dulce. Con T bebés, o regás algo que tenga sed."},
	"fruto_dorado": {"name": "Fruto dorado", "color": Color(1.0, 0.8, 0.25), "shape": "goldfruit", "food": true, "nutrition": 0.35, "hydration": 0.15, "heal": 15.0, "offering": true,
		"hint": "Un fruto que brilla como una brasa tibia. Nació de una semilla cuidada. Huele a algo vivo."},
	"caracola": {"name": "Caracola grande", "color": Color(0.95, 0.7, 0.6), "shape": "conch", "food": false, "offering": true,
		"hint": "Una caracola enorme. Si la acercás al oído, el mar susurra algo largo."},
	"perla": {"name": "Perla", "color": Color(0.95, 0.95, 1.0), "shape": "pearl", "food": false, "offering": true,
		"hint": "Una perla lisa y fría. Rara. Alguien la querría."},
	"vidrio_marino": {"name": "Vidrio marino", "color": Color(0.45, 0.8, 0.65), "shape": "seaglass", "food": false, "offering": true,
		"hint": "Un trozo de vidrio gastado por el mar hasta ser suave. De lo roto, algo bello."},
	"pluma": {"name": "Pluma", "color": Color(0.9, 0.9, 0.85), "shape": "feather", "food": false, "offering": true,
		"hint": "Una pluma larga, ligera. Una de las aves de la isla la dejó caer."},
	"cristal_cueva": {"name": "Cristal de cueva", "color": Color(0.5, 0.85, 1.0), "shape": "crystal", "food": false, "offering": true,
		"hint": "Un cristal que guarda una luz fría. Parece parte de la isla."},
	"flor_luminosa": {"name": "Flor luminosa", "color": Color(0.55, 0.95, 0.8), "shape": "glowflower", "food": false, "offering": true,
		"hint": "Una flor que brilla sola. Se marchita rápido fuera del suelo, pero ahora da luz."},
	"moneda_pirata": {"name": "Moneda antigua", "color": Color(0.85, 0.7, 0.25), "shape": "coin", "food": false, "offering": true,
		"hint": "Una moneda de oro opaco con un rostro gastado. Otros náufragos la perdieron."},
	"figurilla_barro": {"name": "Figurilla de barro", "color": Color(0.7, 0.45, 0.3), "shape": "figurine", "food": false, "offering": true,
		"hint": "Una figura tosca, hecha con tus manos. Imperfecta, pero hecha para alguien."},
	"lata_oxidada": {"name": "Lata oxidada", "color": Color(0.55, 0.3, 0.18), "shape": "can", "food": false, "offering": false, "contaminante": true,
		"hint": "Una lata roída. Suelta óxido. No pertenece a este lugar."},
	"botella_plastico": {"name": "Botella de plástico", "color": Color(0.7, 0.85, 0.95), "shape": "pbottle", "food": false, "offering": false, "contaminante": true,
		"hint": "Plástico del mar. No se pudre. La isla tardará siglos en digerirlo."},
	"bolsa_plastico": {"name": "Bolsa de plástico", "color": Color(0.9, 0.9, 0.9), "shape": "bag", "food": false, "offering": false, "contaminante": true,
		"hint": "Una bolsa deshilachada. Los animales la confunden con comida."},
	"red_enredada": {"name": "Red enredada", "color": Color(0.3, 0.45, 0.35), "shape": "net", "food": false, "offering": false, "contaminante": true,
		"hint": "Una red de pesca perdida, hecha un nudo. Atrapa a lo que pasa."},
	"antorcha": {"name": "Antorcha", "color": Color(0.45, 0.3, 0.16), "shape": "torch", "food": false, "offering": false, "tool": "luz",
		"hint": "Una rama con paja seca atada en la punta. Con T se enciende (cerca de una fogata, o chocando dos piedras). Dura unos diez minutos y se apaga en el agua."},
	"cana_pescar": {"name": "Caña de pescar", "color": Color(0.5, 0.36, 0.2), "shape": "rod", "food": false, "offering": false, "tool": "pesca",
		"hint": "Una rama larga con cuerda y una espina de anzuelo. Con T lanzás frente al agua; cuando el flotador se hunde, T otra vez."},
	"pescado": {"name": "Pescado crudo", "color": Color(0.6, 0.7, 0.78), "shape": "fish", "food": true, "nutrition": 0.2, "hydration": 0.0, "offering": false,
		"hint": "Un pez fresco. Crudo alimenta, pero a la brasa seguramente sabría mejor."},
	"sal": {"name": "Sal marina", "color": Color(0.95, 0.95, 0.92), "shape": "salt", "food": false, "offering": false,
		"hint": "Cristales blancos que se secaron en la roca. Conservan la comida."},
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

static func _glow(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, energy: float, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	var gm := StandardMaterial3D.new()
	gm.albedo_color = c
	gm.emission_enabled = true
	gm.emission = c
	gm.emission_energy_multiplier = energy
	var gi := MeshInstance3D.new()
	gi.mesh = mesh
	gi.material_override = gm
	gi.position = pos
	gi.rotation = rot
	gi.scale = scl
	parent.add_child(gi)

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
			_mi(root, _cyl(0.02, 0.022, 0.16), Color(0.45, 0.3, 0.17), Vector3(0.1, 0.04, 0), Vector3(0, 0, PI / 2.0))
			_mi(root, _sph(0.1), c, Vector3(-0.07, 0.04, 0), Vector3(0, 0, 0), Vector3(1.5, 0.12, 0.45))
			_mi(root, _cyl(0.0, 0.02, 0.05), c, Vector3(-0.17, 0.04, 0), Vector3(0, 0, PI / 2.0))
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
		"cloth_l":
			_mi(root, BoxMesh.new(), c, Vector3(0, 0.02, 0), Vector3(0, 0.2, 0), Vector3(0.5, 0.04, 0.4))
			_mi(root, BoxMesh.new(), c * 0.9, Vector3(0.03, 0.05, 0.02), Vector3(0, -0.3, 0), Vector3(0.4, 0.04, 0.3))
		"cloth_s":
			_mi(root, BoxMesh.new(), c, Vector3(0, 0.015, 0), Vector3(0, 0.4, 0), Vector3(0.26, 0.03, 0.2))
		"flashlight":
			_mi(root, _cyl(0.035, 0.035, 0.22), c, Vector3(0, 0.04, 0), Vector3(0, 0, PI / 2.0))
			_mi(root, _cyl(0.055, 0.04, 0.07), c * 1.3, Vector3(-0.13, 0.04, 0), Vector3(0, 0, PI / 2.0))
			_mi(root, _sph(0.04), Color(0.9, 0.85, 0.5), Vector3(-0.17, 0.04, 0), Vector3.ZERO, Vector3(0.4, 1.0, 1.0))
		"battery":
			_mi(root, _cyl(0.03, 0.03, 0.11), c, Vector3(0, 0.03, 0), Vector3(0, 0, PI / 2.0))
			_mi(root, _cyl(0.014, 0.014, 0.025), Color(0.85, 0.7, 0.2), Vector3(0.065, 0.03, 0), Vector3(0, 0, PI / 2.0))
		"bottle":
			_mi(root, _cyl(0.04, 0.04, 0.17), c, Vector3(0, 0.04, 0), Vector3(0, 0, PI / 2.0))
			_mi(root, _cyl(0.016, 0.03, 0.1), c, Vector3(0.135, 0.04, 0), Vector3(0, 0, -PI / 2.0))
			_mi(root, _cyl(0.015, 0.015, 0.02), Color(0.7, 0.6, 0.4), Vector3(0.195, 0.04, 0), Vector3(0, 0, PI / 2.0))
		"seed":
			var gm := StandardMaterial3D.new()
			gm.albedo_color = c
			gm.emission_enabled = true
			gm.emission = c
			gm.emission_energy_multiplier = 3.0
			var gi := MeshInstance3D.new()
			gi.mesh = _sph(0.06)
			gi.material_override = gm
			gi.position = Vector3(0, 0.07, 0)
			gi.scale = Vector3(1.0, 1.3, 1.0)
			root.add_child(gi)
			var gl := OmniLight3D.new()
			gl.light_color = c
			gl.light_energy = 0.7
			gl.omni_range = 2.2
			gl.position = Vector3(0, 0.15, 0)
			root.add_child(gl)
		"resin":
			_mi(root, _sph(0.06), c, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.2, 0.7, 1.0))
			_mi(root, _sph(0.035), c * 1.15, Vector3(0.07, 0.02, 0.03), Vector3.ZERO, Vector3(1.0, 0.7, 1.0))
		"thorn":
			_mi(root, _cyl(0.0, 0.02, 0.2), c, Vector3(0, 0.03, 0), Vector3(PI / 2.0, 0, 0.2))
		"shovel":
			_mi(root, _cyl(0.02, 0.025, 0.8), Color(0.5, 0.36, 0.2), Vector3(0, 0.04, 0), Vector3(PI / 2.0, 0, 0.1))
			_mi(root, _sph(0.13), c, Vector3(0, 0.05, -0.4), Vector3.ZERO, Vector3(1.0, 0.25, 0.9))
		"torch":
			_mi(root, _cyl(0.022, 0.03, 0.75), c, Vector3(0, 0.05, 0), Vector3(0, 0, PI / 2.0))
			_mi(root, _sph(0.06), Color(0.82, 0.7, 0.35), Vector3(-0.37, 0.05, 0), Vector3.ZERO, Vector3(1.3, 1.0, 1.0))
			_mi(root, _sph(0.045), Color(0.2, 0.15, 0.1), Vector3(-0.42, 0.05, 0))
		"rod":
			root.add_child((load("res://scripts/pesca.gd") as GDScript).call("make_rod_visual") as Node3D)
		"fish":
			root.add_child((load("res://scripts/pesca.gd") as GDScript).call("make_fish_visual") as Node3D)
		"salt":
			for k in 3:
				_mi(root, _sph(0.045), c, Vector3(cos(float(k) * 2.1) * 0.05, 0.02, sin(float(k) * 2.1) * 0.05), Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
		"goldfruit":
			_glow(root, _sph(0.09), c, Vector3(0, 0.09, 0), 2.5)
		"conch":
			_mi(root, _sph(0.11), c, Vector3(0, 0.06, 0), Vector3(0, 0, 0.3), Vector3(1.3, 0.8, 0.9))
			_mi(root, _cyl(0.0, 0.07, 0.12), c * 1.1, Vector3(-0.15, 0.08, 0), Vector3(0, 0, PI / 2.0))
		"pearl":
			_glow(root, _sph(0.04), c, Vector3(0, 0.04, 0), 1.2)
		"seaglass":
			_mi(root, _sph(0.05), c, Vector3(0, 0.02, 0), Vector3(0, 0.6, 0), Vector3(1.2, 0.4, 0.9))
		"feather":
			var fp := PrismMesh.new()
			fp.size = Vector3(0.05, 0.3, 0.008)
			_mi(root, fp, c, Vector3(0, 0.02, 0), Vector3(PI / 2.0, 0.4, 0))
		"crystal":
			for k in 3:
				var cp := PrismMesh.new()
				cp.size = Vector3(0.07, 0.2 - float(k) * 0.04, 0.07)
				_glow(root, cp, c, Vector3(cos(float(k) * 2.1) * 0.05, 0.1, sin(float(k) * 2.1) * 0.05), 2.0, Vector3(sin(float(k)) * 0.3, float(k), cos(float(k)) * 0.3))
		"glowflower":
			_mi(root, _cyl(0.008, 0.01, 0.2), Color(0.25, 0.5, 0.3), Vector3(0, 0.1, 0))
			_glow(root, _sph(0.06), c, Vector3(0, 0.22, 0), 2.5, Vector3.ZERO, Vector3(1, 0.6, 1))
		"coin":
			_mi(root, _cyl(0.05, 0.05, 0.008), c, Vector3(0, 0.01, 0))
		"figurine":
			_mi(root, _sph(0.06), c, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(0.9, 1.3, 0.8))
			_mi(root, _sph(0.035), c, Vector3(0, 0.15, 0))
		"can":
			_mi(root, _cyl(0.04, 0.04, 0.11), c, Vector3(0, 0.04, 0), Vector3(0, 0, PI / 2.0))
		"pbottle":
			_mi(root, _cyl(0.04, 0.04, 0.2), c, Vector3(0, 0.04, 0), Vector3(0, 0, PI / 2.0))
			_mi(root, _cyl(0.015, 0.03, 0.06), c, Vector3(0.13, 0.04, 0), Vector3(0, 0, -PI / 2.0))
		"bag":
			_mi(root, _sph(0.1), c, Vector3(0, 0.02, 0), Vector3(0, 0.4, 0), Vector3(1.4, 0.2, 1.0))
		"net":
			var nt := TorusMesh.new()
			nt.inner_radius = 0.08
			nt.outer_radius = 0.2
			nt.rings = 8
			nt.ring_segments = 4
			_mi(root, nt, c, Vector3(0, 0.05, 0), Vector3(0, 0, 0), Vector3(1.0, 0.6, 1.0))
		_:
			_mi(root, _sph(0.13), c, Vector3(0, 0.13, 0))
	return root
