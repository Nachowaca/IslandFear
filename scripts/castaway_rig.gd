class_name CastawayRig
extends Node3D

## Cuerpo articulado del náufrago construido por código (low-poly, sin esqueleto).
## Cadera -> piernas (muslo/rodilla/tobillo/pie con dedos), torso -> hombros/codos/muñecas/manos con dedos,
## cuello y cabeza con cara (cejas, párpados, ojos que miran, boca, mandíbula), barba, pelo largo en mechones,
## y una túnica corta hecha de paneles rasgados que reaccionan al movimiento. Mira hacia -Z.

const HIP_Y: float = 0.92
const LEG_UP: float = 0.44
const LEG_LO: float = 0.44

const C_SKIN := Color(0.8, 0.6, 0.45)
const C_SKIN_DK := Color(0.68, 0.48, 0.35)
const C_CLOTH := Color(0.9, 0.87, 0.78)
const C_DIRT := Color(0.62, 0.55, 0.42)
const C_HAIR := Color(0.25, 0.16, 0.09)
const C_BEARD := Color(0.3, 0.2, 0.12)
const C_ROPE := Color(0.45, 0.33, 0.2)
const C_DARK := Color(0.07, 0.05, 0.04)
const C_LIP := Color(0.55, 0.3, 0.28)
const C_WHITE := Color(0.95, 0.95, 0.9)

## Expresiones: cejas izq/der (-1 bajas .. 1 altas), ángulo (+ enojo / - tristeza), párpado (<0 muy abierto, 1 cerrado),
## curva de boca (+ sonrisa / - mueca), apertura de boca.
const EXPR: Dictionary = {
	"neutral": {"rl": 0.0, "rr": 0.0, "ang": 0.05, "lid": 0.05, "curve": 0.05, "open": 0.0},
	"fear": {"rl": 0.9, "rr": 0.9, "ang": -0.7, "lid": -0.4, "curve": -0.3, "open": 0.55},
	"pain": {"rl": -0.1, "rr": -0.1, "ang": 0.9, "lid": 0.8, "curve": -0.7, "open": 0.35},
	"tired": {"rl": -0.2, "rr": -0.2, "ang": -0.45, "lid": 0.5, "curve": -0.3, "open": 0.0},
	"smile": {"rl": 0.25, "rr": 0.25, "ang": -0.1, "lid": 0.2, "curve": 0.9, "open": 0.12},
	"curious": {"rl": 0.7, "rr": 0.2, "ang": 0.0, "lid": -0.1, "curve": 0.2, "open": 0.0},
	"determined": {"rl": -0.15, "rr": -0.15, "ang": 0.6, "lid": 0.25, "curve": -0.05, "open": 0.12},
	"surprise": {"rl": 1.0, "rr": 1.0, "ang": -0.2, "lid": -0.6, "curve": 0.0, "open": 0.7},
	"suspicious": {"rl": 0.5, "rr": -0.2, "ang": 0.35, "lid": 0.35, "curve": -0.15, "open": 0.0},
	"scared_still": {"rl": 0.6, "rr": 0.6, "ang": -0.8, "lid": -0.3, "curve": -0.5, "open": 0.15},
}

var hips: Node3D
var torso: Node3D
var neck: Node3D
var head: Node3D
var jaw: Node3D
var thigh: Array[Node3D] = []
var knee: Array[Node3D] = []
var foot: Array[Node3D] = []
var toes: Array[Node3D] = []
var sole: Array[Node3D] = []
var shoulder: Array[Node3D] = []
var elbow: Array[Node3D] = []
var wrist: Array[Node3D] = []
var fingers: Array[Node3D] = []
var skirt: Array[Node3D] = []
var skirt_o: Array[Vector3] = []
var strands: Array = []
var brow: Array[Node3D] = []
var lid: Array[Node3D] = []
var eye: Array[Node3D] = []
var mouth: Array[Node3D] = []
var mouth_slot: MeshInstance3D

var _mats: Dictionary = {}
var _hair_x: Array = []
var _hair_z: Array = []
var _expr_name: String = "neutral"
var _expr_hold: float = 0.0
var _cur: Dictionary = {"rl": 0.0, "rr": 0.0, "ang": 0.05, "lid": 0.05, "curve": 0.05, "open": 0.0}
var _blink: float = 0.0
var _blink_t: float = 2.5
var _look_t: float = 2.0
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _head_yaw: float = 0.0
var _head_pitch: float = 0.0
var _eye_yaw: float = 0.0
var _eye_pitch: float = 0.0
var _rng := RandomNumberGenerator.new()

# ------------------------------------------------------------------ construcción

func _mat(c: Color) -> StandardMaterial3D:
	var key: String = c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		_mats[key] = m
	return _mats[key]

func _add(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

func _sphere(r: float, seg: int = 14, rings: int = 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s

func _cyl(rt: float, rb: float, h: float, seg: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

func _caps(r: float, h: float, seg: int = 8, rings: int = 3) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = seg
	c.rings = rings
	return c

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _node(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n

func build() -> void:
	_rng.randomize()
	hips = _node(self, "Hips", Vector3(0, HIP_Y, 0))
	_add(hips, _sphere(0.13, 12, 6), C_DIRT, Vector3.ZERO, Vector3.ZERO, Vector3(1.15, 0.7, 0.85))
	_build_legs()
	_build_torso()
	_build_arms()
	_build_head()
	_build_skirt()

func _build_legs() -> void:
	for i in 2:
		var sg: float = 1.0 if i == 0 else -1.0
		var th: Node3D = _node(hips, "Thigh" + ("L" if i == 0 else "R"), Vector3(0.1 * sg, -0.02, 0))
		thigh.append(th)
		_add(th, _cyl(0.078, 0.058, LEG_UP, 10), C_SKIN, Vector3(0, -LEG_UP * 0.5, 0))
		_add(th, _cyl(0.09, 0.084, 0.2, 10), C_DIRT, Vector3(0, -0.1, 0))      # resto de pantalón roto
		var kn: Node3D = _node(th, "Knee", Vector3(0, -LEG_UP, 0))
		knee.append(kn)
		_add(kn, _sphere(0.058, 10, 6), C_SKIN)
		_add(kn, _cyl(0.058, 0.04, LEG_LO, 10), C_SKIN, Vector3(0, -LEG_LO * 0.5, 0))
		_add(kn, _cyl(0.046, 0.046, 0.07, 8), C_CLOTH, Vector3(0, -LEG_LO + 0.07, 0))   # venda en el tobillo
		var ft: Node3D = _node(kn, "Foot", Vector3(0, -LEG_LO, 0))
		foot.append(ft)
		var so: Node3D = _node(ft, "Sole", Vector3(0, -0.04, 0))
		sole.append(so)
		_add(ft, _sphere(0.045, 8, 5), C_SKIN)
		_add(ft, _box(Vector3(0.09, 0.05, 0.12)), C_SKIN, Vector3(0, -0.015, 0.03))
		_add(ft, _box(Vector3(0.085, 0.04, 0.1)), C_SKIN, Vector3(0, -0.02, -0.06))
		var tp: Node3D = _node(ft, "Toes", Vector3(0, -0.022, -0.11))
		toes.append(tp)
		_add(tp, _box(Vector3(0.085, 0.026, 0.07)), C_SKIN, Vector3(0, -0.004, -0.03))
		for t in 5:
			_add(tp, _sphere(0.0135, 6, 4), C_SKIN_DK, Vector3((float(t) - 2.0) * 0.017, 0.0, -0.068))

func _build_torso() -> void:
	torso = _node(hips, "Torso", Vector3(0, 0.06, 0))
	_add(torso, _cyl(0.15, 0.15, 0.18, 10), C_CLOTH, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.8))
	_add(torso, _cyl(0.17, 0.145, 0.46, 10), C_CLOTH, Vector3(0, 0.23, 0), Vector3.ZERO, Vector3(1, 1, 0.72))
	_add(torso, _sphere(0.17, 12, 6), C_CLOTH, Vector3(0, 0.44, 0), Vector3.ZERO, Vector3(1.0, 0.45, 0.7))
	_add(torso, _cyl(0.16, 0.16, 0.045, 12), C_ROPE, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1, 1, 0.84))   # cuerda de cinturón
	_add(torso, _sphere(0.03, 6, 4), C_ROPE, Vector3(0.05, 0.0, -0.14))
	_add(torso, _caps(0.012, 0.16, 5, 2), C_ROPE, Vector3(0.07, -0.08, -0.14), Vector3(0, 0, 0.12))
	_add(torso, _box(Vector3(0.1, 0.02, 0.1)), C_SKIN_DK, Vector3(0, 0.49, -0.07), Vector3(-0.5, 0, 0))   # escote
	# retazos rotos de tela en el pecho
	_add(torso, PrismMesh.new(), C_DIRT, Vector3(0.1, 0.12, -0.125), Vector3(PI, 0, 0.3), Vector3(0.05, 0.07, 0.015))
	neck = _node(torso, "Neck", Vector3(0, 0.5, 0))
	_add(neck, _cyl(0.048, 0.055, 0.1, 8), C_SKIN)
	head = _node(neck, "Head", Vector3(0, 0.14, 0))

func _build_arms() -> void:
	for i in 2:
		var sg: float = 1.0 if i == 0 else -1.0
		var sh: Node3D = _node(torso, "Arm" + ("L" if i == 0 else "R"), Vector3(0.215 * sg, 0.42, 0))
		shoulder.append(sh)
		_add(sh, _sphere(0.068, 10, 6), C_CLOTH)
		_add(sh, _caps(0.056, 0.3, 10, 4), C_CLOTH, Vector3(0, -0.14, 0))
		var el: Node3D = _node(sh, "Elbow", Vector3(0, -0.29, 0))
		elbow.append(el)
		_add(el, _sphere(0.05, 8, 5), C_SKIN)
		_add(el, _cyl(0.048, 0.036, 0.26, 8), C_SKIN, Vector3(0, -0.13, 0))
		_add(el, _cyl(0.064, 0.06, 0.07, 8), C_DIRT, Vector3(0, -0.03, 0))      # puño de manga roto
		var wr: Node3D = _node(el, "Wrist", Vector3(0, -0.27, 0))
		wrist.append(wr)
		_add(wr, _box(Vector3(0.07, 0.085, 0.032)), C_SKIN, Vector3(0, -0.045, 0))
		var fg: Node3D = _node(wr, "Fingers", Vector3(0, -0.09, 0))
		fingers.append(fg)
		for f in 4:
			var flen: float = [0.055, 0.065, 0.06, 0.048][f]
			_add(fg, _caps(0.0095, flen, 6, 2), C_SKIN, Vector3((float(f) - 1.5) * 0.019, -flen * 0.45, 0))
		var thumb: Node3D = _node(wr, "Thumb", Vector3(-0.036 * sg, -0.04, -0.01))
		_add(thumb, _caps(0.011, 0.06, 6, 2), C_SKIN, Vector3(0, -0.02, 0), Vector3(0, 0, 0.35 * sg))

func _build_head() -> void:
	_add(head, _sphere(0.115, 20, 12), C_SKIN, Vector3(0, 0.012, 0), Vector3.ZERO, Vector3(0.93, 1.08, 1.02))
	_add(head, _sphere(0.1, 18, 10), C_SKIN, Vector3(0, -0.055, -0.022), Vector3.ZERO, Vector3(0.9, 1.0, 0.88))
	for sg: float in [1.0, -1.0]:
		_add(head, _sphere(0.03, 8, 5), C_SKIN, Vector3(0.06 * sg, -0.02, -0.082))                      # pómulos
		_add(head, _sphere(0.026, 8, 5), C_SKIN_DK, Vector3(0.108 * sg, -0.005, 0.0), Vector3.ZERO, Vector3(0.45, 1.0, 0.8))  # orejas
	_add(head, _box(Vector3(0.13, 0.014, 0.03)), C_SKIN, Vector3(0, 0.043, -0.1))                      # arco de las cejas
	_add(head, _cyl(0.0, 0.03, 0.065, 5), C_SKIN, Vector3(0, -0.025, -0.112), Vector3(-PI / 2.0 - 0.15, 0, 0))   # nariz
	_add(head, _sphere(0.011, 6, 4), C_SKIN_DK, Vector3(0.016, -0.045, -0.118))
	_add(head, _sphere(0.011, 6, 4), C_SKIN_DK, Vector3(-0.016, -0.045, -0.118))
	# ojos
	for i in 2:
		var sg: float = 1.0 if i == 0 else -1.0
		var holder: Node3D = _node(head, "Eye" + ("L" if i == 0 else "R"), Vector3(0.045 * sg, 0.025, -0.1))
		eye.append(holder)
		_add(holder, _sphere(0.021, 10, 6), C_WHITE, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.6))
		_add(holder, _sphere(0.0115, 8, 5), Color(0.25, 0.17, 0.1), Vector3(0, 0, -0.011), Vector3.ZERO, Vector3(1, 1, 0.5))
		_add(holder, _sphere(0.006, 6, 4), C_DARK, Vector3(0, 0, -0.0145), Vector3.ZERO, Vector3(1, 1, 0.5))
		var ld: Node3D = _node(head, "Lid" + ("L" if i == 0 else "R"), Vector3(0.045 * sg, 0.06, -0.105))
		lid.append(ld)
		_add(ld, _box(Vector3(0.054, 0.026, 0.02)), C_SKIN)
		var br: Node3D = _node(head, "Brow" + ("L" if i == 0 else "R"), Vector3(0.045 * sg, 0.068, -0.103))
		brow.append(br)
		_add(br, _box(Vector3(0.058, 0.012, 0.016)), C_HAIR)
	# boca
	mouth_slot = _add(head, _box(Vector3(0.04, 0.012, 0.01)), C_DARK, Vector3(0, -0.072, -0.104))
	for i in 2:
		var sg: float = 1.0 if i == 0 else -1.0
		var m: Node3D = _node(head, "Lip" + ("L" if i == 0 else "R"), Vector3(0.0, -0.07, -0.108))
		mouth.append(m)
		_add(m, _box(Vector3(0.022, 0.008, 0.012)), C_LIP, Vector3(0.011 * sg, 0, 0))
	# bigote
	for sg: float in [1.0, -1.0]:
		_add(head, _caps(0.014, 0.075, 6, 3), C_BEARD, Vector3(0.026 * sg, -0.054, -0.106), Vector3(0, 0, -1.25 * sg))
	# mandíbula + barba (se mueve al hablar / abrir la boca)
	jaw = _node(head, "Jaw", Vector3(0, -0.03, -0.02))
	_add(jaw, _sphere(0.072, 12, 7), C_BEARD, Vector3(0, -0.09, -0.04), Vector3.ZERO, Vector3(1.0, 1.15, 0.9))
	_add(jaw, _sphere(0.05, 10, 6), C_BEARD, Vector3(0.068, -0.045, -0.03), Vector3.ZERO, Vector3(0.75, 1.3, 1.0))
	_add(jaw, _sphere(0.05, 10, 6), C_BEARD, Vector3(-0.068, -0.045, -0.03), Vector3.ZERO, Vector3(0.75, 1.3, 1.0))
	_add(jaw, _sphere(0.052, 10, 6), C_BEARD, Vector3(0, -0.15, -0.045), Vector3.ZERO, Vector3(1, 1.2, 0.9))
	_add(jaw, _cyl(0.05, 0.008, 0.15, 7), C_BEARD, Vector3(0, -0.22, -0.05), Vector3(0.12, 0, 0))
	# pelo: gorro, flequillo y mechones largos
	_add(head, _sphere(0.128, 16, 9), C_HAIR, Vector3(0, 0.05, 0.022), Vector3.ZERO, Vector3(0.98, 0.8, 1.0))
	for k in 4:
		var x: float = (float(k) - 1.5) * 0.045
		_add(head, _sphere(0.03, 8, 5), C_HAIR, Vector3(x, 0.095 - absf(x) * 0.25, -0.088), Vector3(0, 0, x * 3.0), Vector3(1.2, 0.6, 0.8))
	var xs: Array[float] = [-0.085, -0.045, 0.0, 0.045, 0.085, -0.11, 0.11]
	for si in xs.size():
		var scale_len: float = _rng.randf_range(0.72, 1.05) if si < 5 else 0.55
		var chain: Array[Node3D] = []
		var parent: Node3D = head
		var root_pos: Vector3 = Vector3(xs[si], 0.03, 0.115 - absf(xs[si]) * 0.55)
		var lens: Array[float] = [0.14, 0.14, 0.13, 0.12]
		for j in 4:
			var seg: Node3D = _node(parent, "Hair%d_%d" % [si, j], root_pos if j == 0 else Vector3(0, -lens[j - 1] * scale_len, 0))
			var l: float = lens[j] * scale_len
			var r0: float = lerpf(0.042, 0.022, float(j) / 4.0)
			var r1: float = lerpf(0.042, 0.022, float(j + 1) / 4.0) * (0.5 if j == 3 else 1.0)
			_add(seg, _cyl(r0, r1, l, 7), C_HAIR, Vector3(0, -l * 0.5, 0))
			chain.append(seg)
			parent = seg
		strands.append(chain)
		_hair_x.append([0.0, 0.0, 0.0, 0.0])
		_hair_z.append([0.0, 0.0, 0.0, 0.0])

func _build_skirt() -> void:
	_add(hips, _cyl(0.165, 0.205, 0.14, 12), C_CLOTH, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1, 1, 0.92))
	var n: int = 10
	for j in n:
		var phi: float = TAU * float(j) / float(n)
		var o: Vector3 = Vector3(sin(phi), 0.0, -cos(phi))
		var h: Node3D = _node(hips, "Skirt%d" % j, o * Vector3(0.2, 0.0, 0.185) + Vector3(0, -0.06, 0))
		h.rotation.y = PI - phi
		var plen: float = _rng.randf_range(0.34, 0.5)
		_add(h, _box(Vector3(0.14, plen, 0.016)), C_CLOTH, Vector3(0, -plen * 0.5, 0))
		_add(h, _box(Vector3(0.14, 0.07, 0.018)), C_DIRT, Vector3(0, -plen + 0.035, 0))
		_add(h, PrismMesh.new(), C_CLOTH, Vector3(_rng.randf_range(-0.03, 0.03), -plen - 0.02, 0), Vector3(0, 0, PI), Vector3(0.07, 0.07, 0.016))
		skirt.append(h)
		skirt_o.append(o)

# ------------------------------------------------------------------ API

func express(expr_name: String, hold: float = 1.0) -> void:
	if EXPR.has(expr_name):
		_expr_name = expr_name
		_expr_hold = hold

## Ciclos de paso por metro: depende de la amplitud para que los pies no patinen.
func stride_per_meter(blend: float, run: float) -> float:
	var amp: float = lerpf(0.42, 0.72, run) * maxf(blend, 0.3)
	return 1.785 / maxf(sin(amp), 0.25)

func pose(dt: float, phase: float, h_speed: float, walk_speed: float, run_speed: float, air: bool, grounded: bool, vel_y: float, yaw_rate: float, accel: float, crouch: float, health_frac: float, time: float) -> void:
	if hips == null:
		return
	var blend: float = clampf(h_speed / walk_speed, 0.0, 1.0)
	var run: float = clampf((h_speed - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
	var k: float = 1.0 - exp(-28.0 * dt)
	var sway: float = sin(time * 1.5)

	# ---- piernas
	var amp: float = lerpf(0.42, 0.72, run) * blend
	var knee_flex: float = lerpf(0.75, 1.25, run)
	var th_ang: Array[float] = [0.0, 0.0]
	for i in 2:
		var sg: float = 1.0 if i == 0 else -1.0
		var p: float = phase + (0.0 if i == 0 else PI)
		var s: float = sin(p)
		var c: float = cos(p)
		var th: float = s * amp + crouch * 1.1
		var kn: float = -(maxf(0.0, c) * knee_flex * blend + 0.04) - crouch * 2.1
		var ft: float = -(th + kn) * 0.85 - maxf(0.0, -s) * 0.4 * blend
		var toe: float = maxf(0.0, -s) * 0.5 * blend
		if air:
			th = 0.55 if i == 0 else -0.25
			kn = -0.9 if i == 0 else -0.5
			ft = -(th + kn) * 0.5
			toe = 0.2
		th_ang[i] = th
		thigh[i].rotation = thigh[i].rotation.lerp(Vector3(th, 0.0, sg * (0.035 + 0.02 * (1.0 - blend))), k)
		knee[i].rotation.x = lerpf(knee[i].rotation.x, kn, k)
		foot[i].rotation.x = lerpf(foot[i].rotation.x, ft, k)
		toes[i].rotation.x = lerpf(toes[i].rotation.x, toe, k)

	# ---- cadera / torso
	var s0: float = sin(phase)
	var c0: float = cos(phase)
	hips.rotation = hips.rotation.lerp(Vector3(0.0, s0 * 0.12 * blend, c0 * 0.035 * blend + clampf(-yaw_rate * 0.01, -0.12, 0.12)), k)
	var lean: float = blend * 0.06 + run * 0.16 + clampf(accel * 0.006, -0.1, 0.12) + crouch * 0.5
	var t_rot: Vector3 = Vector3(-lean, -s0 * 0.2 * blend, -c0 * 0.04 * blend + clampf(-yaw_rate * 0.012, -0.15, 0.15))
	if air:
		t_rot = Vector3(-0.05 + clampf(vel_y * 0.01, -0.2, 0.2), 0.0, 0.0)
	torso.rotation = torso.rotation.lerp(t_rot, k)
	torso.scale.y = 1.0 + sin(time * 1.9) * 0.012 * (1.0 - blend)
	hips.position.x = lerpf(hips.position.x, sway * 0.012 * (1.0 - blend), k)

	# ---- brazos
	var arm_amp: float = lerpf(0.5, 1.0, run) * blend
	for i in 2:
		var sg: float = 1.0 if i == 0 else -1.0
		var pa: float = phase + (PI if i == 0 else 0.0)
		var sw: float = sin(pa) * arm_amp
		var sx: float = sw + sway * 0.03 * sg * (1.0 - blend)
		var sz: float = sg * (0.09 + run * 0.12 + 0.03 * (1.0 - blend))
		var el: float = 0.2 + run * 0.8 + maxf(0.0, sw) * 0.55 + blend * 0.1
		var wx: float = -sw * 0.15
		var curl: float = 0.45 + run * 0.45
		if air:
			sx = -0.5
			sz = sg * 0.95
			el = 0.5
			wx = 0.0
			curl = 0.2
		shoulder[i].rotation = shoulder[i].rotation.lerp(Vector3(sx, 0.0, sz), k)
		elbow[i].rotation.x = lerpf(elbow[i].rotation.x, el, k)
		wrist[i].rotation.x = lerpf(wrist[i].rotation.x, wx, k)
		fingers[i].rotation.z = lerpf(fingers[i].rotation.z, -sg * curl, k)

	# ---- apoyo en el suelo: la cadera sube y baja para que el pie más bajo toque siempre el suelo
	if grounded and not air:
		var low: float = minf(sole[0].global_position.y, sole[1].global_position.y) - global_position.y
		var target_y: float = clampf(hips.position.y - low, HIP_Y - 0.32, HIP_Y + 0.04)
		hips.position.y = lerpf(hips.position.y, target_y, 1.0 - exp(-45.0 * dt))
	else:
		hips.position.y = lerpf(hips.position.y, HIP_Y, 1.0 - exp(-10.0 * dt))

	_pose_head(dt, blend, lean, c0, air)
	_pose_hair(dt, h_speed, run_speed, blend, yaw_rate, vel_y, air, time)
	_pose_skirt(dt, th_ang, blend, run, time)
	_face(dt, health_frac, run, air, vel_y)

func _pose_head(dt: float, blend: float, lean: float, c0: float, air: bool) -> void:
	_look_t -= dt
	if _look_t <= 0.0:
		_look_t = _rng.randf_range(1.5, 5.5)
		if blend > 0.3:
			_look_yaw = _rng.randf_range(-0.25, 0.25) if _rng.randf() < 0.3 else 0.0
			_look_pitch = _rng.randf_range(-0.1, 0.1)
		else:
			_look_yaw = _rng.randf_range(-0.9, 0.9)
			_look_pitch = _rng.randf_range(-0.25, 0.25)
	var kh: float = 1.0 - exp(-4.0 * dt)
	_head_yaw = lerpf(_head_yaw, _look_yaw * 0.6, kh)
	_head_pitch = lerpf(_head_pitch, _look_pitch * 0.6, kh)
	var ke: float = 1.0 - exp(-14.0 * dt)
	_eye_yaw = lerpf(_eye_yaw, clampf(_look_yaw * 0.4, -0.35, 0.35), ke)
	_eye_pitch = lerpf(_eye_pitch, clampf(_look_pitch * 0.4, -0.2, 0.2), ke)
	neck.rotation = Vector3(lean * 0.5 + c0 * 0.02 * blend, 0.0, 0.0)
	head.rotation = Vector3(lean * 0.35 + _head_pitch - (0.25 if air else 0.0), _head_yaw, sin(_look_yaw) * 0.03)
	for e in eye:
		e.rotation = Vector3(_eye_pitch, _eye_yaw, 0.0)

func _pose_hair(dt: float, h_speed: float, run_speed: float, blend: float, yaw_rate: float, vel_y: float, air: bool, time: float) -> void:
	var base_x: float = -(0.1 + h_speed / run_speed * 0.55)
	if air:
		base_x += clampf(-vel_y * 0.03, -0.3, 0.5)
	var base_z: float = clampf(yaw_rate * 0.03, -0.5, 0.5)
	for si in strands.size():
		var chain: Array = strands[si]
		var hx: Array = _hair_x[si]
		var hz: Array = _hair_z[si]
		for j in chain.size():
			var lag: float = 9.0 - 1.8 * float(j)
			var wave: float = sin(time * 2.4 + float(si) * 0.8 + float(j) * 1.0) * 0.045 * (0.4 + blend)
			var tx: float = base_x * (0.45 + 0.1 * float(j)) + wave
			var tz: float = base_z * (0.4 + 0.12 * float(j)) + sin(time * 1.7 + float(si) + float(j)) * 0.02
			var kk: float = 1.0 - exp(-lag * dt)
			hx[j] = lerpf(hx[j], tx, kk)
			hz[j] = lerpf(hz[j], tz, kk)
			(chain[j] as Node3D).rotation = Vector3(hx[j], 0.0, hz[j])

func _pose_skirt(dt: float, th_ang: Array[float], blend: float, run: float, time: float) -> void:
	var k: float = 1.0 - exp(-18.0 * dt)
	for j in skirt.size():
		var o: Vector3 = skirt_o[j]
		var leg: float = th_ang[0] if o.x > 0.2 else (th_ang[1] if o.x < -0.2 else (th_ang[0] + th_ang[1]) * 0.5)
		var push: float = maxf(0.0, leg * -o.z)
		var billow: float = (0.12 + 0.3 * run) * blend * (1.0 if o.z > 0.0 else 0.35)
		var flare: float = 0.05 + 0.95 * push + billow + sin(time * 2.2 + float(j) * 1.3) * 0.035 * (0.5 + blend)
		skirt[j].rotation.x = lerpf(skirt[j].rotation.x, -flare, k)

func _face(dt: float, health_frac: float, run: float, air: bool, vel_y: float) -> void:
	_expr_hold = maxf(_expr_hold - dt, 0.0)
	var expr_name: String = _expr_name
	if _expr_hold <= 0.0:
		expr_name = "neutral"
		if health_frac < 0.3:
			expr_name = "tired"
		elif air and vel_y < -5.0:
			expr_name = "surprise"
		elif run > 0.5:
			expr_name = "determined"
	var tgt: Dictionary = EXPR[expr_name]
	var ke: float = 1.0 - exp(-11.0 * dt)
	for key: String in tgt.keys():
		_cur[key] = lerpf(float(_cur[key]), float(tgt[key]), ke)
	_blink_t -= dt
	if _blink_t <= 0.0:
		_blink = 1.0
		_blink_t = _rng.randf_range(2.0, 6.0)
	_blink = maxf(_blink - dt * 7.0, 0.0)
	var closure: float = clampf(float(_cur["lid"]) + sin(_blink * PI) * 1.0, -0.7, 1.0)
	for i in 2:
		var sg: float = 1.0 if i == 0 else -1.0
		var raise: float = float(_cur["rl"]) if i == 0 else float(_cur["rr"])
		brow[i].position.y = 0.068 + raise * 0.014
		brow[i].rotation.z = sg * float(_cur["ang"]) * 0.5
		var c: float = clampf(closure, 0.0, 1.0)
		lid[i].scale.y = lerpf(1.0, 1.9, c)
		lid[i].position.y = 0.025 + lerpf(0.036 + maxf(0.0, -closure) * 0.01, 0.0, c)
		mouth[i].rotation.z = sg * float(_cur["curve"]) * 0.5
	mouth_slot.scale.y = 0.2 + float(_cur["open"]) * 3.5
	mouth_slot.scale.x = 1.0 + float(_cur["open"]) * 0.3
	jaw.rotation.x = -float(_cur["open"]) * 0.22
