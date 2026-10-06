class_name FloatingRock
extends Node3D

## Roca misteriosa que flota sobre un círculo de runas. Gira lento, sube y baja, y fragmentos orbitan.
## De noche las runas y el corazón de la roca brillan en turquesa. Registrada como lugar sagrado.

var ground_y: float = 0.0
var _rock: Node3D
var _frags: Array[Dictionary] = []
var _runes: Array[MeshInstance3D] = []
var _rune_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _light: OmniLight3D
var _beam_mat: StandardMaterial3D
var _t: float = 0.0
const FLOAT_H := 5.2

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

func _ready() -> void:
	add_to_group("floating_rock")
	_rune_mat = StandardMaterial3D.new()
	_rune_mat.albedo_color = Color(0.1, 0.25, 0.25)
	_rune_mat.emission_enabled = true
	_rune_mat.emission = Color(0.3, 1.0, 0.9)
	_rune_mat.emission_energy_multiplier = 0.4
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(0.2, 0.9, 0.85)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(0.3, 1.0, 0.9)
	_core_mat.emission_energy_multiplier = 1.2
	_build_circle()
	_build_rock()
	_build_beam()
	_light = OmniLight3D.new()
	_light.light_color = Color(0.4, 1.0, 0.9)
	_light.omni_range = 18.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, FLOAT_H * 0.55, 0)
	add_child(_light)

## Círculo de piedras bajas con runas que brillan.
func _build_circle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var disc := CylinderMesh.new()
	disc.top_radius = 4.6
	disc.bottom_radius = 5.0
	disc.height = 0.12
	disc.radial_segments = 20
	var dm := MeshInstance3D.new()
	dm.mesh = disc
	dm.material_override = _mat(Color(0.34, 0.34, 0.33))
	dm.position = Vector3(0, 0.02, 0)
	add_child(dm)
	for i in 10:
		var a: float = TAU * i / 10.0
		var pos: Vector3 = Vector3(cos(a) * 4.0, 0.0, sin(a) * 4.0)
		var slab := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.7 + rng.randf() * 0.5, 0.4)
		slab.mesh = bm
		slab.material_override = _mat(Color(0.42, 0.42, 0.41))
		slab.position = pos + Vector3(0, bm.size.y * 0.5, 0)
		slab.rotation = Vector3(rng.randf_range(-0.08, 0.08), -a + PI * 0.5, rng.randf_range(-0.1, 0.1))
		add_child(slab)
		# runa brillante en la cara interior
		var rune := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.12, 0.34, 0.03)
		rune.mesh = rm
		rune.material_override = _rune_mat
		var inward: Vector3 = -Vector3(cos(a), 0, sin(a))
		rune.position = pos + inward * 0.22 + Vector3(0, bm.size.y * 0.55, 0)
		rune.rotation = slab.rotation
		add_child(rune)
		_runes.append(rune)
	# anillo de runas en el suelo
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.55
	tm.outer_radius = 2.75
	tm.rings = 24
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = _rune_mat
	ring.position = Vector3(0, 0.1, 0)
	ring.scale = Vector3(1, 0.15, 1)
	add_child(ring)

func _build_rock() -> void:
	_rock = Node3D.new()
	_rock.position = Vector3(0, FLOAT_H, 0)
	add_child(_rock)
	if NatureKit.exists("Rock_Medium_2"):
		var big: Node3D = NatureKit.make("Rock_Medium_2", Color(0.9, 0.95, 0.95), 400.0)
		big.scale = Vector3(1.8, 2.3, 1.8)
		_rock.add_child(big)
	# corazón brillante enterrado en la roca
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	sm.radial_segments = 8
	sm.rings = 4
	core.mesh = sm
	core.material_override = _core_mat
	core.position = Vector3(0, 1.2, 0)
	_rock.add_child(core)
	# fragmentos orbitando
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 7:
		var f: Node3D
		if NatureKit.exists("Rock_Medium_1"):
			f = NatureKit.make("Rock_Medium_%d" % rng.randi_range(1, 3), Color.WHITE, 400.0)
		else:
			f = Node3D.new()
		f.scale = Vector3.ONE * rng.randf_range(0.18, 0.4)
		add_child(f)
		_frags.append({"node": f, "r": rng.randf_range(3.2, 5.4), "a": rng.randf() * TAU, "sp": rng.randf_range(0.15, 0.4) * (1.0 if i % 2 == 0 else -1.0), "h": rng.randf_range(FLOAT_H - 0.5, FLOAT_H + 3.2), "ph": rng.randf() * TAU})

## Columna de luz tenue que baja de la roca hasta el círculo.
func _build_beam() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 2.4
	cm.height = FLOAT_H
	cm.radial_segments = 12
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(0.4, 1.0, 0.9, 0.05)
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = _beam_mat
	mi.position = Vector3(0, FLOAT_H * 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _process(delta: float) -> void:
	_t += delta
	var bob: float = sin(_t * 0.7) * 0.28
	_rock.position.y = FLOAT_H + bob
	_rock.rotation.y += delta * 0.12
	_rock.rotation.z = sin(_t * 0.4) * 0.05
	for f: Dictionary in _frags:
		f["a"] = float(f["a"]) + float(f["sp"]) * delta
		var n: Node3D = f["node"]
		var a: float = f["a"]
		n.position = Vector3(cos(a) * float(f["r"]), float(f["h"]) + sin(_t * 0.9 + float(f["ph"])) * 0.3, sin(a) * float(f["r"]))
		n.rotation += Vector3(0.3, 0.5, 0.2) * delta
	var dn: Node = get_tree().get_first_node_in_group("daynight")
	var night: float = float(dn.get("night_amount")) if dn != null else 0.0
	var pulse: float = 0.75 + 0.25 * sin(_t * 1.1)
	_rune_mat.emission_energy_multiplier = 0.4 + night * 3.5 * pulse
	_core_mat.emission_energy_multiplier = 1.0 + night * 3.0 * pulse
	_beam_mat.albedo_color.a = 0.035 + night * 0.09
	_light.light_energy = lerpf(_light.light_energy, 0.4 + night * 2.2 * pulse, minf(delta * 2.0, 1.0))
