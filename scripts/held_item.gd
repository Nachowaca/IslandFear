class_name HeldItem
extends Node

## Objeto en la mano: muestra en la mano derecha el objeto elegido (si es de mano), levanta el brazo y
## permite usarlo con T. Por ahora: la linterna (necesita una batería; al agotarse deja una batería gastada,
## que es un contaminante). Las demás herramientas ya se ven en la mano; su uso llega con el bloque 6.

## rot: giro (grados) del modelo respecto del cuerpo; off: desplazamiento desde la mano (en ejes del cuerpo).
## El modelo de suelo tiene su eje largo en X y la punta en -X: con rot Y = -90 la punta mira hacia adelante.
const HAND: Dictionary = {
	"linterna": {"rot": Vector3(0, -90, 0), "off": Vector3(0.0, 0.02, -0.06)},
	"hacha": {"rot": Vector3(0, -90, 0), "off": Vector3(0.0, 0.0, -0.1), "tilt": 0.5},
	"lanza": {"rot": Vector3(0, -90, 0), "off": Vector3(0.0, 0.0, -0.1), "tilt": 0.6},
	"pala_concha": {"rot": Vector3(0, -90, 0), "off": Vector3(0.0, 0.0, -0.1)},
	"piedra_afilada": {"rot": Vector3(0, -90, 0), "off": Vector3(0.0, 0.0, -0.05)},
	"botella_vacia": {"rot": Vector3(0, -90, 0), "off": Vector3(0.0, 0.0, -0.06)},
	"botella_agua": {"rot": Vector3(0, -90, 0), "off": Vector3(0.0, 0.0, -0.06)},
	"antorcha": {"rot": Vector3(0, -90, 0), "off": Vector3(0.0, 0.0, -0.1), "tilt": 0.75},
	"cana_pescar": {"rot": Vector3(0, -90, 0), "off": Vector3(0.0, 0.0, -0.1), "tilt": 0.6},
}
## Cómo se agarra cada objeto (ver CastawayPose.hold_kind): "luz", "herramienta" o "caña".
const KIND: Dictionary = {
	"linterna": "luz", "antorcha": "luz", "hacha": "herramienta", "lanza": "herramienta", "pala_concha": "herramienta",
	"piedra_afilada": "herramienta", "cana_pescar": "caña",
}
const TORCH_TIME: float = 600.0       ## segundos de llama de una antorcha
const TORCH_ENERGY: float = 1.9
const CARGA_BATERIA: float = 300.0     ## segundos de luz por batería
const LUZ_ENERGIA: float = 3.2

var player: Castaway
var ui: InventoryUi
var terrain: IslandTerrain

var _holder: Node3D
var _spot: SpotLight3D
var _shown: String = ""
var _prev: Dictionary = {}
var _hold_w: float = 0.0
var _energy: float = 0.0
var _t: float = 0.0
var inter: Interaccion
var _pesca: Node
var _flame: Node3D
var _flame_light: OmniLight3D
var _flame_fx: CPUParticles3D
var _flame_core: MeshInstance3D
var _flame_e: float = 0.0
var _insp: Node3D
var _insp_t: float = 0.0

func _ready() -> void:
	_holder = Node3D.new()
	_holder.name = "ManoItem"
	_holder.top_level = true
	player.add_child(_holder)
	_spot = SpotLight3D.new()
	_spot.name = "LuzLinterna"
	_spot.top_level = true
	_spot.spot_range = 20.0
	_spot.spot_angle = 36.0
	_spot.spot_angle_attenuation = 0.8
	_spot.light_color = Color(1.0, 0.95, 0.8)
	_spot.shadow_enabled = false
	_spot.light_energy = 0.0
	_spot.visible = false
	player.add_child(_spot)
	call_deferred("_conectar")

func _conectar() -> void:
	if player != null and player.observar != null and not player.observar.message.is_connected(_on_observar):
		player.observar.message.connect(_on_observar)

func _on_observar(texto: String) -> void:
	if ui != null:
		ui.message(texto)

func _edge(key: Key) -> bool:
	var down: bool = Input.is_physical_key_pressed(key)
	var was: bool = bool(_prev.get(key, false))
	_prev[key] = down
	return down and not was

func _process(delta: float) -> void:
	if player == null or ui == null:
		return
	_t += delta
	var e: Variant = Inventario.item_seleccionado()
	var id: String = str(e["id"]) if e != null else ""
	var want: String = id if HAND.has(id) else ""
	if want != _shown:
		_cambiar_visual(want)
	var tw: float = 1.0 if _shown != "" and not player.dead else 0.0
	_hold_w = lerpf(_hold_w, tw, 1.0 - exp(-8.0 * delta))
	player.set_hold(_hold_w)
	if _shown != "":
		var cfg: Dictionary = HAND[_shown]
		var rot: Vector3 = cfg["rot"]
		var off: Vector3 = cfg["off"]
		var body: Basis = player.global_transform.basis
		var hand: Transform3D = player.hand_transform()
		var tilt: float = float(cfg.get("tilt", 0.0))
		_holder.global_transform = Transform3D(body * Basis(Vector3.RIGHT, tilt) * Basis.from_euler(rot * (PI / 180.0)), hand.origin + body * (off + player.hold_sway()))
	if _edge(KEY_T) and player.controllable and not player.dead and not player.menu_lock:
		_usar()
	_luz(delta)
	_antorcha(delta)
	_inspeccion(delta)

func _cambiar_visual(id: String) -> void:
	for c: Node in _holder.get_children():
		c.queue_free()
	_flame = null
	if _pesca != null and _shown == "cana_pescar":
		_pesca.call("cancelar")
	if Inventario.antorcha_on:
		Inventario.antorcha_on = false       # guardar la antorcha la apaga
	_shown = id
	player.set_hold_kind(str(KIND.get(id, "")))
	if id != "":
		_holder.add_child(ItemDB.make_visual(id))
	if id == "antorcha":
		_hacer_llama()

func _usar() -> void:
	var e: Variant = Inventario.item_seleccionado()
	var sel: String = str(e["id"]) if e != null else ""
	match sel:
		"botella_vacia":
			player.pulse_use()
			if _cerca_estanque():
				Inventario.transformar_en(Inventario.seleccionado, "botella_agua")
				AudioManager.play(get_tree(), "drip", player.global_position, -6.0)
				ui.message("Llenás la botella con agua dulce.")
			else:
				ui.message("Está vacía. Cerca del estanque podrías llenarla.")
		"botella_agua":
			player.pulse_use()
			var pl: PlantaAzul = _planta_seca()
			if pl != null:
				pl.regar()
				Inventario.transformar_en(Inventario.seleccionado, "botella_vacia")
				AudioManager.play(get_tree(), "drip", pl.global_position, -4.0)
				Isla.registrar_evento("cuidado", pl.global_position, 1.5)
				ui.message("Regás el brote. Parece estirarse hacia vos.")
			elif player.sed < 99.0:
				player.add_need("sed", 40.0)
				player.play_action("drink")
				Inventario.transformar_en(Inventario.seleccionado, "botella_vacia")
				ui.message("Bebés de la botella.")
			else:
				ui.message("No tenés sed. Guardala: algo más puede necesitarla.")
		"semilla_azul":
			_plantar()
		_:
			_usar_mano()

func _cerca_estanque() -> bool:
	var c: Vector2 = IslandTerrain.POND_CENTER
	return Vector2(player.global_position.x, player.global_position.z).distance_to(c) < IslandTerrain.POND_RADIUS + 1.5

func _planta_seca() -> PlantaAzul:
	for n: Node in get_tree().get_nodes_in_group("planta_azul"):
		var pl: PlantaAzul = n as PlantaAzul
		if pl != null and not pl.regado and pl.global_position.distance_to(player.global_position) < 3.2:
			return pl
	return null

func _plantar() -> void:
	var pos: Vector3 = player.global_position - player.global_transform.basis.z * 1.1
	var h: float = terrain.height_at(pos.x, pos.z) if terrain != null else pos.y
	if h < 1.1 or (terrain != null and terrain.is_in_cave_area(pos.x, pos.z)):
		ui.message("Acá no: la semilla necesita tierra firme.")
		return
	for n: Node in get_tree().get_nodes_in_group("planta_azul"):
		if (n as Node3D).global_position.distance_to(pos) < 2.0:
			ui.message("Ya hay un brote muy cerca.")
			return
	Inventario.quitar_en(Inventario.seleccionado, 1)
	var pl := PlantaAzul.new()
	player.get_parent().add_child(pl)
	pl.global_position = Vector3(pos.x, h, pos.z)
	player.play_action("pickup")
	AudioManager.play(get_tree(), "step_grass", pos, -6.0)
	Isla.registrar_evento("cuidado", pos, 0.8)
	ui.message("Plantás la semilla. El brote tiene sed.")

func _usar_mano() -> void:
	match _shown:
		"linterna":
			player.pulse_use()
			if Inventario.linterna_on:
				Inventario.linterna_on = false
				ui.message("Apagás la linterna.")
			elif Inventario.linterna_carga > 0.0:
				Inventario.linterna_on = true
				ui.message("Encendés la linterna.")
			elif Inventario.quitar("bateria", 1):
				Inventario.linterna_carga = CARGA_BATERIA
				Inventario.linterna_on = true
				ui.message("Ponés una batería. La linterna se enciende.")
			else:
				ui.message("La linterna no tiene pilas.")
		"antorcha":
			_usar_antorcha()
		"cana_pescar":
			if _pesca == null:
				_pesca = (load("res://scripts/pesca.gd") as GDScript).new() as Node
				_pesca.set("player", player)
				_pesca.set("terrain", terrain)
				_pesca.set("ui", ui)
				add_child(_pesca)
			player.pulse_use()
			_pesca.call("usar")
		"hacha", "piedra_afilada":
			if inter != null:
				inter.cortar_con_mano(_shown)
		"lanza":
			player.play_action("cut")
			ui.message("Nada a quien lanzarle. La isla no necesita que cacen en ella.")
		"":
			pass
		_:
			ui.message("%s: todavía no sabés cómo usarlo así." % ItemDB.display_name(_shown))

func _luz(delta: float) -> void:
	var activa: bool = Inventario.linterna_on and _shown == "linterna" and not player.dead
	if activa:
		Inventario.linterna_carga -= delta
		if Inventario.linterna_carga <= 0.0:
			Inventario.linterna_carga = 0.0
			Inventario.linterna_on = false
			activa = false
			_gastada()
	var flick: float = 1.0
	if Inventario.linterna_carga < 30.0:
		flick = 0.8 + 0.2 * sin(_t * 23.0) * sin(_t * 7.0)     # la pila se está yendo
	_energy = lerpf(_energy, LUZ_ENERGIA * flick if activa else 0.0, 1.0 - exp(-10.0 * delta))
	_spot.light_energy = _energy
	_spot.visible = _energy > 0.02
	if _spot.visible:
		var body: Basis = player.global_transform.basis
		_spot.global_transform = Transform3D(body * Basis(Vector3.RIGHT, -0.1), _holder.global_position + body * Vector3(0, 0.05, -0.25))

## La batería se agotó: queda una batería gastada (contaminante) en el inventario o en el suelo.
func _gastada() -> void:
	var resto: int = Inventario.agregar("bateria_gastada", 1)
	if resto == 0:
		ui.message("La batería se agotó. Guardás la batería gastada: no conviene dejarla en la isla.")
		return
	var it := WorldItem.new()
	it.item_id = "bateria_gastada"
	it.display_name = ItemDB.display_name("bateria_gastada")
	it.add_child(ItemDB.make_visual("bateria_gastada"))
	player.get_parent().add_child(it)
	it.global_position = player.global_position + Vector3(0, 0.1, 0) - player.global_transform.basis.z * 0.8
	ui.message("La batería se agotó. No tenés lugar: la dejás en el suelo.")

# ------------------------------------------------------------------ antorcha

func _hacer_llama() -> void:
	_flame = Node3D.new()
	_flame.name = "Llama"
	_flame.position = Vector3(-0.44, 0.07, 0.0)
	_flame.visible = false
	_holder.add_child(_flame)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.65, 0.2)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.12)
	fm.emission_energy_multiplier = 2.5
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var core := SphereMesh.new()
	core.radius = 0.06
	core.height = 0.2
	core.radial_segments = 6
	core.rings = 3
	core.material = fm
	_flame_core = MeshInstance3D.new()
	_flame_core.mesh = core
	_flame_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.add_child(_flame_core)
	_flame_fx = CPUParticles3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.025
	pm.height = 0.05
	pm.radial_segments = 4
	pm.rings = 2
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(1.0, 0.55, 0.15)
	pmat.emission_enabled = true
	pmat.emission = Color(1.0, 0.45, 0.1)
	pmat.emission_energy_multiplier = 2.0
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.material = pmat
	_flame_fx.mesh = pm
	_flame_fx.amount = 14
	_flame_fx.lifetime = 0.7
	_flame_fx.local_coords = false
	_flame_fx.direction = Vector3.UP
	_flame_fx.spread = 25.0
	_flame_fx.gravity = Vector3(0, 1.5, 0)
	_flame_fx.initial_velocity_min = 0.3
	_flame_fx.initial_velocity_max = 0.8
	_flame_fx.scale_amount_min = 0.5
	_flame_fx.scale_amount_max = 1.2
	_flame_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.add_child(_flame_fx)
	_flame_light = OmniLight3D.new()
	_flame_light.light_color = Color(1.0, 0.62, 0.28)
	_flame_light.omni_range = 11.0
	_flame_light.omni_attenuation = 1.3
	_flame_light.light_energy = 0.0
	_flame_light.shadow_enabled = false
	_flame_light.position = Vector3(0, 0.15, 0)
	_flame.add_child(_flame_light)

func _fogata_encendida_cerca() -> bool:
	for n: Node in get_tree().get_nodes_in_group("campfire"):
		var cf: Campfire = n as Campfire
		if cf != null and cf.is_burning() and cf.global_position.distance_to(player.global_position) < 3.5:
			return true
	return false

func _en_agua() -> bool:
	return terrain != null and terrain.height_at(player.global_position.x, player.global_position.z) < 0.38

func _usar_antorcha() -> void:
	player.pulse_use()
	if Inventario.antorcha_on:
		Inventario.antorcha_on = false
		ui.message("Apagás la antorcha.")
		return
	if _en_agua():
		ui.message("Con el agua no prende.")
		return
	if _fogata_encendida_cerca():
		Inventario.antorcha_on = true
		ui.message("Encendés la antorcha en la fogata.")
	elif Inventario.cantidad("piedra") >= 2:
		Inventario.antorcha_on = true
		AudioManager.play(get_tree(), "crack", player.global_position, -10.0)
		ui.message("Chocás dos piedras: la paja prende.")
	else:
		ui.message("Para encenderla hace falta una fogata cerca o dos piedras para la chispa.")

func _antorcha(delta: float) -> void:
	var activa: bool = Inventario.antorcha_on and _shown == "antorcha" and not player.dead
	if activa and _en_agua():
		Inventario.antorcha_on = false
		activa = false
		ui.message("El agua apaga la antorcha.")
	if activa:
		Inventario.antorcha_carga -= delta
		if Inventario.antorcha_carga <= 0.0:
			Inventario.antorcha_on = false
			Inventario.antorcha_carga = TORCH_TIME
			activa = false
			Inventario.quitar("antorcha", 1)
			ui.message("La antorcha se consumió del todo.")
	if _flame == null or not is_instance_valid(_flame):
		return
	var flick: float = 1.0 + 0.18 * sin(_t * 17.0) * sin(_t * 5.3) + 0.08 * sin(_t * 41.0)
	if Inventario.antorcha_carga < 60.0:
		flick *= 0.75 + 0.25 * sin(_t * 9.0)
	_flame_e = lerpf(_flame_e, TORCH_ENERGY * flick if activa else 0.0, 1.0 - exp(-9.0 * delta))
	_flame_light.light_energy = _flame_e
	_flame.visible = activa or _flame_e > 0.05
	_flame_fx.emitting = activa
	_flame_core.scale = Vector3(1.0, 1.0 + 0.25 * sin(_t * 23.0), 1.0) * clampf(_flame_e / TORCH_ENERGY, 0.0, 1.2)

# ------------------------------------------------------------------ inspeccionar en mano

## Muestra el objeto delante de la cámara, girando despacio unos segundos (F con un objeto elegido).
func inspeccionar(id: String) -> void:
	if _insp != null and is_instance_valid(_insp):
		_insp.queue_free()
	_insp = Node3D.new()
	_insp.top_level = true
	_insp.add_child(ItemDB.make_visual(id))
	player.add_child(_insp)
	_insp_t = 4.5

func _inspeccion(delta: float) -> void:
	if _insp == null or not is_instance_valid(_insp):
		return
	var cam: Camera3D = player.get_camera()
	if _insp_t <= 0.0 or player.dead or cam == null:
		_insp.queue_free()
		_insp = null
		return
	_insp_t -= delta
	var cb: Basis = cam.global_transform.basis
	var w: float = clampf(minf(_insp_t, 4.5 - _insp_t) / 0.4, 0.0, 1.0)
	var pos: Vector3 = cam.global_position + cb * Vector3(0.0, -0.12 - 0.1 * (1.0 - w), -0.7 + 0.2 * (1.0 - w))
	_insp.global_transform = Transform3D(cb * Basis(Vector3.UP, _t * 1.3) * Basis(Vector3.RIGHT, 0.35), pos)
	_insp.scale = Vector3.ONE * (1.4 * maxf(w, 0.02))
