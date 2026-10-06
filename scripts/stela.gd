class_name Stela
extends Node3D
## Piedra tallada con un mensaje (pista de otro náufrago o tumba de una vida anterior del jugador).
## Se lee con F. El texto está grabado en la cara frontal (se ve oscuro con un borde claro, como un relieve).

var text: String = ""
var is_tomb: bool = false
var _rng := RandomNumberGenerator.new()

static func create(msg: String, tomb: bool, seed_value: int) -> Stela:
	var s := Stela.new()
	s.text = msg
	s.is_tomb = tomb
	s._rng.seed = seed_value
	return s

func _ready() -> void:
	add_to_group("stela")
	set_meta("texto", text)
	_build()

static var _grain: NoiseTexture2D

func _stone_material() -> StandardMaterial3D:
	if _grain == null:
		var gn := FastNoiseLite.new()
		gn.noise_type = FastNoiseLite.TYPE_CELLULAR
		gn.frequency = 0.035
		gn.fractal_type = FastNoiseLite.FRACTAL_FBM
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.55, 0.55, 0.55))
		ramp.set_color(1, Color(1, 1, 1))
		_grain = NoiseTexture2D.new()
		_grain.width = 256
		_grain.height = 256
		_grain.seamless = true
		_grain.noise = gn
		_grain.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.66, 0.64, 0.6)
	m.albedo_texture = _grain
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.4, 1.4, 1.4)
	m.roughness = 1.0
	return m

func _build() -> void:
	var mat: StandardMaterial3D = _stone_material()
	var slab := Node3D.new()
	slab.name = "Slab"
	slab.rotation = Vector3(_rng.randf_range(-0.05, 0.05), 0.0, _rng.randf_range(-0.07, 0.07))
	if is_tomb:
		slab.scale = Vector3.ONE * 1.3
	add_child(slab)
	var w: float = 1.25
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 1.25, 0.26)
	bm.material = mat
	body.mesh = bm
	body.position.y = 0.625
	slab.add_child(body)
	var top := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = w * 0.5
	cm.bottom_radius = w * 0.5
	cm.height = 0.26
	cm.radial_segments = 14
	cm.material = mat
	top.mesh = cm
	top.rotation.x = PI * 0.5
	top.position.y = 1.25
	slab.add_child(top)
	# la piedra se hunde un poco en el suelo y tiene una base de piedras
	for i in 4:
		if NatureKit.exists("Pebble_Round_%d" % (i + 1)):
			var pb: Node3D = NatureKit.make("Pebble_Round_%d" % (i + 1), Color.WHITE, 60.0)
			var a: float = _rng.randf() * TAU
			pb.position = Vector3(cos(a) * 0.55, 0.0, sin(a) * 0.35 + 0.1)
			pb.scale = Vector3.ONE * _rng.randf_range(1.2, 2.4)
			pb.rotation.y = _rng.randf() * TAU
			add_child(pb)
	if is_tomb:
		for i in 6:
			var pb2: Node3D = NatureKit.make("Pebble_Square_%d" % _rng.randi_range(1, 6), Color.WHITE, 60.0)
			pb2.position = Vector3(_rng.randf_range(-0.45, 0.45), 0.0, _rng.randf_range(0.45, 1.1))
			pb2.scale = Vector3.ONE * _rng.randf_range(1.4, 2.4)
			pb2.rotation.y = _rng.randf() * TAU
			add_child(pb2)
	# tallado: una copia clara desplazada (el borde iluminado) y encima la oscura
	var lines: PackedStringArray = text.split("\n")
	var size_px: int = 44 if lines.size() <= 3 else 36
	var center_y: float = 0.72 + 0.03 * float(lines.size())
	for pass_i in 2:
		var lb := Label3D.new()
		lb.text = text
		lb.font = UiTheme.TITLE
		lb.font_size = size_px
		lb.pixel_size = 0.0021
		lb.line_spacing = -2.0
		lb.double_sided = false
		lb.shaded = true
		lb.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		lb.outline_size = 0
		if pass_i == 0:
			lb.modulate = Color(1.0, 0.98, 0.92)
			lb.render_priority = 1
			lb.position = Vector3(0.008, center_y - 0.008, 0.1335)
		else:
			lb.modulate = Color(0.05, 0.045, 0.04)
			lb.render_priority = 2
			lb.position = Vector3(0.0, center_y, 0.137)
		slab.add_child(lb)
	# colisión
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 1.8, 0.4)
	cs.shape = bs
	cs.position.y = 0.9
	sb.add_child(cs)
	add_child(sb)
