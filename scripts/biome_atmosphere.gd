class_name BiomeAtmosphere
extends Node3D

## Atmósfera según el bioma (renderer Mobile, sin niebla volumétrica):
## - niebla de distancia local (más densa en zonas húmedas, selva, laguna y zonas misteriosas)
## - neblina baja (partículas grandes y suaves) que sigue al jugador
## - vapor en zonas calientes (pozo de la cueva y zonas misteriosas)
## - polvo/suciedad flotando, más en zonas áridas y rocosas

var terrain: IslandTerrain
var eco: EcoMap
var daynight: DayNight
var player: Node3D

const SAMPLE_EVERY := 0.3
const STEAM_VIEW := 70.0

var _mist: CPUParticles3D
var _dust: CPUParticles3D
var _steam: Array[CPUParticles3D] = []
var _tex: GradientTexture2D
var _t: float = 0.0
var _fog: float = 0.0
var _mist_k: float = 0.0
var _dust_k: float = 0.0
var _tgt_fog: float = 0.0
var _tgt_mist: float = 0.0
var _tgt_dust: float = 0.0

func _ready() -> void:
	add_to_group("biome_atmosphere")
	_tex = GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_tex.gradient = g
	_tex.fill = GradientTexture2D.FILL_RADIAL
	_tex.fill_from = Vector2(0.5, 0.5)
	_tex.fill_to = Vector2(1.0, 0.5)
	_tex.width = 64
	_tex.height = 64
	_mist = _make_mist()
	add_child(_mist)
	_dust = _make_dust()
	add_child(_dust)
	_make_steam_sources()

func _soft_material(unshaded_color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _tex
	m.albedo_color = unshaded_color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m

func _make_mist() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(9.0, 9.0)
	q.material = _soft_material(Color(0.8, 0.88, 0.95, 1.0))
	p.mesh = q
	p.amount = 26
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(26, 0.3, 26)
	p.position = Vector3(0, 0.9, 0)
	p.direction = Vector3(1, 0, 0.4)
	p.spread = 30.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.5
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	p.color_ramp = _fade_ramp()
	p.color = Color(1, 1, 1, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.04, 0.04)
	q.material = _soft_material(Color(0.78, 0.7, 0.55, 1.0))
	p.mesh = q
	p.amount = 110
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14, 2.5, 14)
	p.position = Vector3(0, 2.0, 0)
	p.direction = Vector3(1, 0.1, 0.3)
	p.spread = 180.0
	p.gravity = Vector3(0.25, -0.02, 0.1)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.8
	p.color_ramp = _fade_ramp()
	p.color = Color(1, 1, 1, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

func _make_steam_sources() -> void:
	var spots: Array[Vector3] = []
	if terrain != null:
		spots.append(Vector3(IslandTerrain.CAVE_CENTER.x, terrain.cave_floor_y + 0.3, IslandTerrain.CAVE_CENTER.y))
	if eco != null:
		for c in eco.mystery_centers:
			if spots.size() >= 4:
				break
			var h: float = 0.0
			if terrain != null:
				h = maxf(terrain.height_at(c.x, c.z), 0.0)
			spots.append(Vector3(c.x, h + 0.1, c.z))
	for s in spots:
		var p := CPUParticles3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2.2, 2.2)
		q.material = _soft_material(Color(0.92, 0.95, 1.0, 1.0))
		p.mesh = q
		p.amount = 14
		p.lifetime = 7.0
		p.preprocess = 7.0
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 2.2
		p.direction = Vector3.UP
		p.spread = 14.0
		p.gravity = Vector3(0.1, 0.35, 0.05)
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.6
		p.damping_min = 0.1
		p.damping_max = 0.3
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.5
		p.scale_amount_curve = _grow_curve()
		p.color_ramp = _fade_ramp()
		p.color = Color(1, 1, 1, 0.34)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = s
		p.visible = false
		add_child(p)
		_steam.append(p)

func _fade_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 1))
	g.add_point(0.7, Color(1, 1, 1, 1))
	return g

func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.5))
	c.add_point(Vector2(1.0, 1.4))
	return c

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_t += delta
	var pp: Vector3 = player.global_position
	_mist.global_position = Vector3(pp.x, _ground(pp) + 0.9, pp.z)
	_dust.global_position = Vector3(pp.x, _ground(pp) + 2.0, pp.z)
	if _t >= SAMPLE_EVERY:
		_t = 0.0
		_sample(pp)
	var k: float = 1.0 - exp(-0.7 * delta)
	_fog = lerpf(_fog, _tgt_fog, k)
	_mist_k = lerpf(_mist_k, _tgt_mist, k)
	_dust_k = lerpf(_dust_k, _tgt_dust, k)
	if daynight != null:
		daynight.fog_local = _fog
	var night: float = daynight.night_amount if daynight != null else 0.0
	_mist.color = Color(1, 1, 1, _mist_k * 0.09)
	_mist.visible = _mist_k > 0.02
	_dust.color = Color(1, 1, 1, _dust_k * 0.25 * (1.0 - night * 0.6))
	_dust.visible = _dust_k > 0.02
	for s in _steam:
		s.visible = s.global_position.distance_to(pp) < STEAM_VIEW

func _ground(p: Vector3) -> float:
	if terrain == null:
		return 0.0
	return maxf(terrain.height_at(p.x, p.z), 0.0)

func _sample(pp: Vector3) -> void:
	if eco == null:
		return
	var hum: float = clampf(eco.get_humedad(pp), 0.0, 1.0)
	var mist: float = clampf(eco.get_misterio(pp), 0.0, 1.0)
	var bio: int = eco.get_bioma(pp)
	var dwater: float = eco.get_dist_agua(pp)
	var near_water: float = clampf(1.0 - dwater / 18.0, 0.0, 1.0)
	var dry: float = 1.0 - hum
	if bio == EcoMap.Bioma.ARIDO or bio == EcoMap.Bioma.ROQUEDAL:
		dry = clampf(dry + 0.35, 0.0, 1.0)
	var jungle: float = 1.0 if bio == EcoMap.Bioma.SELVA else (0.5 if bio == EcoMap.Bioma.BOSQUE else 0.0)
	var cave_k: float = 0.0
	if terrain != null:
		cave_k = clampf(1.0 - Vector2(pp.x, pp.z).distance_to(IslandTerrain.CAVE_CENTER) / 26.0, 0.0, 1.0)
	var mood: float = eco.mood_niebla
	var wet: float = clampf(hum * 0.6 + jungle * 0.4 + near_water * 0.3 + mist * 0.7 + cave_k * 0.5 + mood, 0.0, 1.5)
	_tgt_fog = wet * 0.0010
	_tgt_mist = clampf(wet, 0.0, 1.0)
	_tgt_dust = clampf(dry * 0.8 + cave_k * 0.3, 0.0, 1.0) * (1.0 - _tgt_mist * 0.6)
