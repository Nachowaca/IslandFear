class_name AirFlutter
extends Node3D

## Abejas y mariposas extra alrededor del jugador. Se crea solo en _ready().

const BEE_COUNT: int = 8
const BUTTERFLY_COUNT: int = 6
const MIN_GROUND: float = 1.0          # por debajo es agua: no volar ahí
const BEE_RADIUS_MIN: float = 3.0
const BEE_RADIUS_MAX: float = 28.0
const BEE_SPEED: float = 2.2
const BEE_ALT_MIN: float = 0.3
const BEE_ALT_MAX: float = 1.5
const PAUSE_MIN: float = 0.8
const PAUSE_MAX: float = 2.0
const RESPAWN_DIST: float = 50.0       # si el jugador se aleja más, se recolocan
const BF_RADIUS_MIN: float = 10.0
const BF_RADIUS_MAX: float = 40.0
const WING_HZ: float = 70.0

var terrain: IslandTerrain
var player: Node3D

var _bees: Array[Node3D] = []
var _bee_wings: Array[Array] = []
var _bee_target: Array[Vector3] = []
var _bee_pause: Array[float] = []
var _bee_phase: Array[float] = []
var _butterflies: Array[Butterfly] = []
var _noche: float = 0.0
var _built: bool = false
var _rng := RandomNumberGenerator.new()
var _check_t: float = 0.0

func _ready() -> void:
	_rng.randomize()
	visible = false
	set_process(false)

## 0 día, 1 noche.
func set_noche(n: float) -> void:
	_noche = n
	var dia: bool = n <= 0.5
	visible = dia
	set_process(dia)
	for b: Butterfly in _butterflies:
		b.set_process(dia)

# Construye todo al primer uso con terreno y jugador disponibles
func _build() -> void:
	_built = true
	var bmesh := SphereMesh.new()
	bmesh.radius = 0.035
	bmesh.height = 0.08
	bmesh.radial_segments = 6
	bmesh.rings = 3
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.95, 0.75, 0.1)
	bmat.roughness = 1.0
	bmesh.material = bmat
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.062, 0.062, 0.014)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.08, 0.06, 0.04)
	stripe.material = smat
	var wmesh := QuadMesh.new()
	wmesh.size = Vector2(0.05, 0.03)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.9, 0.95, 1.0, 0.45)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wmesh.material = wmat
	for i in BEE_COUNT:
		var bee := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = bmesh
		body.scale = Vector3(1.0, 0.9, 1.5)
		bee.add_child(body)
		var st := MeshInstance3D.new()
		st.mesh = stripe
		st.position.z = 0.0
		bee.add_child(st)
		var wings: Array = []
		for s: float in [1.0, -1.0]:
			var piv := Node3D.new()
			piv.position = Vector3(0.0, 0.035, 0.0)
			var mi := MeshInstance3D.new()
			mi.mesh = wmesh
			mi.rotation.x = -PI / 2.0
			mi.position.x = 0.025 * s
			piv.add_child(mi)
			bee.add_child(piv)
			wings.append(piv)
		add_child(bee)
		_bees.append(bee)
		_bee_wings.append(wings)
		_bee_target.append(Vector3.ZERO)
		_bee_pause.append(_rng.randf_range(0.0, 1.0))
		_bee_phase.append(_rng.randf() * TAU)
		bee.global_position = _ground_point(BEE_RADIUS_MIN, BEE_RADIUS_MAX, 0.8)
		_bee_target[i] = bee.global_position
	var cols: Array[Color] = [
		Color(0.95, 0.9, 0.25), Color(0.97, 0.97, 0.95), Color(0.55, 0.8, 0.98),
		Color(0.98, 0.55, 0.15), Color(0.72, 0.6, 0.9), Color(0.95, 0.9, 0.25)]
	for i in BUTTERFLY_COUNT:
		var bf := Butterfly.new()
		bf.terrain = terrain
		bf.home = _ground_point(BF_RADIUS_MIN, BF_RADIUS_MAX, 0.0)
		bf.wing_color = cols[i % cols.size()]
		bf.name = "AirButterfly%d" % i
		add_child(bf)
		_butterflies.append(bf)

# Punto en tierra firme alrededor del jugador (y = suelo + alt)
func _ground_point(rmin: float, rmax: float, alt: float) -> Vector3:
	var c: Vector3 = player.global_position
	var p := Vector3(c.x, 0.0, c.z)
	for t in 12:
		var a: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(rmin, rmax)
		var x: float = c.x + cos(a) * r
		var z: float = c.z + sin(a) * r
		var h: float = terrain.height_at(x, z)
		if h >= MIN_GROUND:
			return Vector3(x, h + alt, z)
		p = Vector3(x, maxf(h, MIN_GROUND) + alt, z)
	return p

func _process(delta: float) -> void:
	if terrain == null or player == null:
		return
	if not _built:
		_build()
		set_noche(_noche)
	_time_check(delta)
	var t: float = Time.get_ticks_msec() * 0.001
	for i in _bees.size():
		_update_bee(i, delta, t)

# Recoloca mariposas y abejas lejanas
func _time_check(delta: float) -> void:
	_check_t += delta
	if _check_t < 1.0:
		return
	_check_t = 0.0
	var pp: Vector3 = player.global_position
	for b: Butterfly in _butterflies:
		if b.global_position.distance_to(pp) > RESPAWN_DIST:
			b.home = _ground_point(BF_RADIUS_MIN, BF_RADIUS_MAX, 0.0)
			b.global_position = b.home + Vector3(0, 1.0, 0)
	for i in _bees.size():
		if _bees[i].global_position.distance_to(pp) > RESPAWN_DIST:
			_bees[i].global_position = _ground_point(BEE_RADIUS_MIN, BEE_RADIUS_MAX, 0.8)
			_bee_target[i] = _bees[i].global_position
			_bee_pause[i] = 0.5

func _update_bee(i: int, delta: float, t: float) -> void:
	var bee: Node3D = _bees[i]
	var wings: Array = _bee_wings[i]
	var flap: float = sin(t * WING_HZ + _bee_phase[i]) * 0.9
	(wings[0] as Node3D).rotation.z = flap
	(wings[1] as Node3D).rotation.z = -flap
	var ph: float = _bee_phase[i]
	var wob := Vector3(sin(t * 9.0 + ph) * 0.02, sin(t * 13.0 + ph) * 0.025, cos(t * 7.0 + ph) * 0.02)
	if _bee_pause[i] > 0.0:
		# flotando sobre la "flor"
		_bee_pause[i] -= delta
		bee.global_position += wob * delta * 6.0
		if _bee_pause[i] <= 0.0:
			var tp: Vector3 = _ground_point(BEE_RADIUS_MIN, BEE_RADIUS_MAX, 0.0)
			# acercar un poco al punto actual para vuelos cortos
			var cur: Vector3 = bee.global_position
			var mid: Vector3 = cur.lerp(tp, 0.5)
			var gh: float = terrain.height_at(mid.x, mid.z)
			if gh >= MIN_GROUND:
				tp = mid
			tp.y = terrain.height_at(tp.x, tp.z) + _rng.randf_range(BEE_ALT_MIN, BEE_ALT_MAX)
			_bee_target[i] = tp
		return
	var to: Vector3 = _bee_target[i] - bee.global_position
	var d: float = to.length()
	if d < 0.15:
		_bee_pause[i] = _rng.randf_range(PAUSE_MIN, PAUSE_MAX)
		return
	var step: Vector3 = to / d * minf(BEE_SPEED * delta, d)
	bee.global_position += step + wob * delta * 3.0
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 0.05:
		var yaw: float = atan2(flat.x, flat.z)
		bee.rotation.y = lerp_angle(bee.rotation.y, yaw, minf(1.0, delta * 8.0))
