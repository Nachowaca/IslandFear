class_name Interaccion
extends Node

## Interacción del jugador con el mundo.
## E recoger / beber / echar leña · G dejar (Shift+G todo) · F investigar · R probar (comer)
## Q cortar (cuchilla: lianas y hojas; hacha: talar) · C combinar objetos (rueda: elegir, E: fabricar)
## 1-9, 0 o rueda: elegir objeto. La isla se entera de lo que hacés (ofrendas, talar, fuego...).

var player: Castaway
var terrain: IslandTerrain
var features: IslandFeatures
var ui: InventoryUi

var _prev: Dictionary = {}
var _target: WorldItem
var _fire: Campfire
var _plant: Node3D
var _stela: Stela
var _craft_open: bool = false
var _craft_idx: int = 0
var _cut_cd: float = 0.0
var _pan: float = 0.0
var _crafting: bool = false
var _craft_t: float = 0.0
var _craft_dur: float = 2.2
var _craft_recipe: Dictionary = {}
var _aviso: Dictionary = {}
var _aviso_t: float = 0.0
var _rng := RandomNumberGenerator.new()

const SPOT_INFO: Dictionary = {
	"heart": ["Algo antiguo late bajo la piedra. Sentís que te observan los años.", "Hay marcas gastadas, casi borradas. Alguien, hace mucho, dejó algo aquí.", "El aire es más denso. No es un lugar para quedarse."],
	"refuge": ["Una cueva de piedra fría. De día parece un refugio; de noche, quién sabe.", "El techo gotea. Adentro la isla parece contener el aliento."],
	"wreck": ["Maderas de otro naufragio. Otros llegaron antes que vos.", "Cuadernas rotas y tablas grises de sal. Nadie volvió a buscar esto."],
}
const FUEL_SECONDS: Dictionary = {"madera": 120.0, "rama": 50.0, "paja": 18.0}

func _ready() -> void:
	_rng.randomize()

func _edge(key: Key) -> bool:
	var down: bool = Input.is_physical_key_pressed(key)
	var was: bool = bool(_prev.get(key, false))
	_prev[key] = down
	return down and not was

func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.controllable:
		return
	var step: int = 0
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = -1
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = 1
	elif event is InputEventPanGesture:              # trackpad de Mac: el scroll llega como gesto, no como rueda
		_pan += (event as InputEventPanGesture).delta.y
		if absf(_pan) >= 1.0:
			step = 1 if _pan > 0.0 else -1
			_pan = 0.0
	if step != 0:
		_cambiar(step)

func _cambiar(step: int) -> void:
	if _crafting:
		return
	if _craft_open:
		_craft_idx = posmod(_craft_idx + step, Recipes.LIST.size())
		_refrescar_craft()
	else:
		Inventario.seleccionar(Inventario.seleccionado + step)


func _process(delta: float) -> void:
	if player == null or ui == null:
		return
	_cut_cd = maxf(_cut_cd - delta, 0.0)
	player.menu_lock = _craft_open
	_avisar_recetas(delta)
	if _crafting:
		_craft_t += delta
		ui.set_progress(_craft_t / _craft_dur, "Fabricando…")
		if player.dead or not _craft_open or _craft_t >= _craft_dur:
			var fin: bool = _craft_t >= _craft_dur and not player.dead
			_crafting = false
			ui.set_progress(-1.0)
			if fin:
				_terminar_crear(_craft_recipe)
	var cam: Camera3D = player.get_camera()
	if not player.controllable or player.dead or cam == null or not cam.current:
		ui.set_prompt("")
		return
	for i in 10:
		var key: Key = (KEY_1 + i) as Key if i < 9 else KEY_0
		if _edge(key):
			Inventario.seleccionar(i)
			_mostrar_seleccion()
	_target = _buscar_objetivo()
	_fire = _fogata_cercana()
	_plant = _planta_delante()
	_stela = _stela_delante()
	var partes: Array[String] = []
	if not _craft_open:
		if _target != null:
			partes.append("E: beber" if _target.item_id == "agua_dulce" else "E: recoger %s" % _target.display_name)
			partes.append("F: investigar")
		elif _stela != null:
			partes.append("F: leer la piedra")
		elif _fire != null:
			partes.append("E: echar leña al fuego")
		if _plant != null:
			partes.append("Q: cortar")
	ui.set_prompt("    ".join(partes))
	if _craft_open and not _crafting:
		if _edge(KEY_UP):
			_cambiar(-1)
		if _edge(KEY_DOWN):
			_cambiar(1)
	if _edge(KEY_C):
		_craft_open = not _craft_open
		_craft_idx = clampi(_craft_idx, 0, Recipes.LIST.size() - 1)
		_refrescar_craft()
	if _edge(KEY_E):
		if _craft_open:
			if not _crafting:
				_crear()
		else:
			_recoger()
	if _craft_open:
		_refrescar_craft()
	if _edge(KEY_G):
		_dejar(Input.is_physical_key_pressed(KEY_SHIFT))
	if _edge(KEY_F):
		_investigar()
	if _edge(KEY_R):
		_probar()
	if _edge(KEY_Q):
		_cortar()

# ------------------------------------------------------------------ búsqueda

func _cam_fwd() -> Vector3:
	var f: Vector3 = -player.get_camera().global_transform.basis.z
	f.y = 0.0
	return f.normalized()

func _buscar_objetivo() -> WorldItem:
	var fwd: Vector3 = _cam_fwd()
	var best: WorldItem = null
	var best_d: float = INF
	for g: String in ["pickup", "dropped_item"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			var it: WorldItem = n as WorldItem
			if it == null or it.is_queued_for_deletion():
				continue
			var d: Vector3 = it.global_position - player.global_position
			var flat: Vector3 = Vector3(d.x, 0.0, d.z)
			var dist: float = flat.length()
			if dist > it.interact_radius + 0.5 or absf(d.y) > 2.2:
				continue
			if it.item_id != "agua_dulce" and dist > 0.5 and fwd.dot(flat.normalized()) < 0.15:
				continue                      # solo lo que tenés delante
			if dist < best_d:
				best_d = dist
				best = it
	return best

func _fogata_cercana() -> Campfire:
	var best: Campfire = null
	var best_d: float = 2.6
	for n: Node in get_tree().get_nodes_in_group("campfire"):
		var c: Campfire = n as Campfire
		if c == null:
			continue
		var d: float = Vector2(c.global_position.x - player.global_position.x, c.global_position.z - player.global_position.z).length()
		if d < best_d:
			best_d = d
			best = c
	return best

func _planta_delante() -> Node3D:
	if terrain == null:
		return null
	var fwd: Vector3 = _cam_fwd()
	var best: Node3D = null
	var best_d: float = 2.8
	for arr: Array in [terrain.tree_nodes, terrain.palm_nodes]:
		for n: Node3D in arr:
			if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
				continue
			var d: Vector3 = n.global_position - player.global_position
			var flat: Vector3 = Vector3(d.x, 0.0, d.z)
			var dist: float = flat.length()
			if dist < best_d and (dist < 1.2 or fwd.dot(flat.normalized()) > 0.3):
				best_d = dist
				best = n
	return best

## Piedra tallada delante (a menos de 3 m, en el campo de visión).
func _stela_delante() -> Stela:
	var fwd: Vector3 = _cam_fwd()
	var best: Stela = null
	var best_d: float = 3.2
	for n: Node in get_tree().get_nodes_in_group("stela"):
		var s: Stela = n as Stela
		if s == null:
			continue
		var d: Vector3 = s.global_position - player.global_position
		var flat: Vector3 = Vector3(d.x, 0.0, d.z)
		var dist: float = flat.length()
		if dist < best_d and (dist < 1.3 or fwd.dot(flat.normalized()) > 0.35):
			best_d = dist
			best = s
	return best

func _mostrar_seleccion() -> void:
	var e: Variant = Inventario.item_seleccionado()
	if e == null:
		ui.message("Espacio vacío")
		return
	var id: String = str(e["id"])
	var suf: String = "" if Inventario.descubiertos.has(id) else "  (sin investigar)"
	ui.message("%s%s" % [ItemDB.display_name(id), suf])

func _sonido(id: String, pos: Vector3, db: float = -6.0) -> void:
	AudioManager.play(get_tree(), id, pos, db)

# ------------------------------------------------------------------ recoger, dejar

func _recoger() -> void:
	if _target == null:
		if _fire != null:
			_avivar()
		return
	var it: WorldItem = _target
	if it.item_id == "agua_dulce":
		if player.sed >= 99.0:
			ui.message("No tenés sed.")
			return
		player.add_need("sed", 35.0)
		player.play_action("drink")
		ui.message("Bebés agua fresca del estanque.")
		_sonido("drip", player.global_position)
		Isla.registrar_evento("cuidado", player.global_position, 0.2)
		return
	var resto: int = Inventario.agregar(it.item_id, it.amount)
	if resto >= it.amount:
		ui.message("Inventario lleno.")
		return
	var tomadas: int = it.amount - resto
	player.play_action("pickup")
	_sonido("step_grass", it.global_position)
	if resto > 0:
		it.amount = resto
		ui.message("+%d %s (no entra todo)" % [tomadas, it.display_name])
	else:
		it.remove_from_group("pickup")
		it.remove_from_group("dropped_item")
		it.queue_free()
		ui.message("+%d %s" % [tomadas, it.display_name])

## Crea un objeto en el mundo (lo soltado no cuenta como "tomado" de la isla).
func _spawn_item(id: String, n: int, pos: Vector3) -> WorldItem:
	var d: Dictionary = ItemDB.get_def(id)
	var it := WorldItem.new()
	it.item_id = id
	it.display_name = str(d["name"])
	it.amount = n
	it.edible = bool(d.get("food", false))
	it.poisonous = d.has("poison")
	it.nutrition = float(d.get("nutrition", 0.0))
	it.hydration = float(d.get("hydration", 0.0))
	it.add_child(ItemDB.make_visual(id))
	it.rotation.y = _rng.randf() * TAU
	get_parent().add_child(it)
	it.global_position = pos
	it.remove_from_group("pickup")
	it.add_to_group("dropped_item")
	return it

func _dejar(todo: bool) -> void:
	var i: int = Inventario.seleccionado
	var e: Variant = Inventario.espacios[i]
	if e == null:
		ui.message("No hay nada que dejar.")
		return
	var fwd: Vector3 = -player.global_transform.basis.z
	var pos: Vector3 = player.global_position + fwd * 1.0
	var h: float = terrain.height_at(pos.x, pos.z) if terrain != null else pos.y
	if h < 0.5:
		ui.message("Se perdería en el agua.")
		return
	pos.y = h
	var id: String = str(e["id"])
	var n: int = Inventario.quitar_en(i, int(e["n"]) if todo else 1)
	var it: WorldItem = _spawn_item(id, n, pos)
	_sonido("step_grass", pos)
	ui.message("Dejás %d %s" % [n, it.display_name])
	_ofrenda(id, pos)

## Dejar algo valioso junto a un lugar sagrado es una ofrenda: la isla lo nota.
func _ofrenda(id: String, pos: Vector3) -> void:
	if features == null or not bool(ItemDB.get_def(id).get("offering", false)):
		return
	for n: Node in get_tree().get_nodes_in_group("stela"):      # una ofrenda ante una piedra tallada también cuenta
		var sn: Node3D = n as Node3D
		if sn != null and Vector2(pos.x - sn.global_position.x, pos.z - sn.global_position.z).length() < 2.4:
			Isla.registrar_evento("ofrenda", pos, 0.6)
			ui.message("Dejás una ofrenda ante la piedra tallada. La isla lo siente.")
			return
	for sp: Dictionary in features.sacred_spots:
		if str(sp["kind"]) == "refuge":
			continue
		var p: Vector3 = sp["pos"]
		if Vector2(pos.x - p.x, pos.z - p.z).length() < float(sp["radius"]) + 1.5:
			Isla.registrar_evento("ofrenda", pos, 1.0)
			ui.message("Dejás una ofrenda en %s. La isla lo siente." % str(sp["name"]).to_lower())
			return

# ------------------------------------------------------------------ probar / comer

## R: probar (comer) el objeto elegido. Comida buena sacia; el hongo equivocado envenena.
func _probar() -> void:
	var i: int = Inventario.seleccionado
	var e: Variant = Inventario.espacios[i]
	if e == null:
		ui.message("No tenés nada elegido para probar.")
		return
	var id: String = str(e["id"])
	var d: Dictionary = ItemDB.get_def(id)
	if not bool(d.get("food", false)):
		ui.message("%s no parece comestible." % str(d["name"]))
		return
	Inventario.quitar_en(i, 1)
	Inventario.descubrir(id)
	var partes: Array[String] = []
	var hambre: float = float(d.get("nutrition", 0.0)) * 100.0
	var sed: float = float(d.get("hydration", 0.0)) * 100.0
	if hambre > 0.0:
		player.add_need("hambre", hambre)
		partes.append("hambre +%d" % int(hambre))
	if sed > 0.0:
		player.add_need("sed", sed)
		partes.append("sed +%d" % int(sed))
	if float(d.get("heal", 0.0)) > 0.0:
		player.heal(float(d["heal"]))
		partes.append("salud +%d" % int(float(d["heal"])))
	_sonido("step_grass", player.global_position)
	player.play_action("eat")
	if d.has("poison"):
		player.take_damage(float(d["poison"]), "hongo venenoso")
		player.add_need("hambre", -12.0)
		player.express("pain", 2.5)
		ui.message("¡Sabe amargo! Te sentís mal: %s" % str(d["name"]))
		ui.show_info("Era venenoso. Los colores vivos eran una advertencia.")
	else:
		player.express("smile", 1.2)
		ui.message("Comés %s%s" % [str(d["name"]).to_lower(), (" (" + ", ".join(partes) + ")") if not partes.is_empty() else ""])

# ------------------------------------------------------------------ cortar


func _cortar() -> void:
	if _cut_cd > 0.0:
		return
	if _plant == null:
		ui.message("No hay nada para cortar delante.")
		return
	var hacha: bool = Inventario.tiene("hacha")
	var cuchilla: bool = Inventario.tiene("piedra_afilada")
	if not hacha and not cuchilla:
		ui.message("Necesitás algo afilado: una cuchilla de piedra o un hacha.")
		return
	_cut_cd = 0.55
	player.play_action("cut")
	var planta: Node3D = _plant
	var es_palma: bool = terrain.palm_nodes.has(planta)
	var pos: Vector3 = planta.global_position
	# con cuchilla: cortar lianas del árbol o una hoja de la palmera
	if cuchilla:
		if es_palma and int(planta.get_meta("hojas", 0)) > 0:
			if Inventario.agregar("hoja_grande", 1) > 0:
				ui.message("Inventario lleno.")
				return
			planta.set_meta("hojas", int(planta.get_meta("hojas")) - 1)
			_sonido("step_grass", pos, -4.0)
			ui.message("Cortás una hoja grande.")
			return
		if not es_palma and int(planta.get_meta("lianas", 0)) > 0:
			if Inventario.agregar("liana", 1) > 0:
				ui.message("Inventario lleno.")
				return
			planta.set_meta("lianas", int(planta.get_meta("lianas")) - 1)
			for k in range(planta.get_child_count() - 1, -1, -1):
				var c: Node = planta.get_child(k)
				if c.name.begins_with("Liana"):
					c.queue_free()
					break
			_sonido("step_grass", pos, -4.0)
			ui.message("Cortás una liana.")
			return
	if not hacha:
		ui.message("Con una cuchilla no podés talar: hace falta un hacha." if not es_palma else "No quedan hojas al alcance.")
		return
	# con hacha: golpes hasta talar
	var necesarios: int = 3 if es_palma else (5 if planta.scale.x > 1.1 else 4)
	var golpes: int = int(planta.get_meta("golpes", 0)) + 1
	planta.set_meta("golpes", golpes)
	_sonido("crack", pos, -2.0)
	player.add_shake(0.12)
	player.express("determined", 0.8)
	if golpes < necesarios:
		ui.message("¡Golpe! (%d/%d)" % [golpes, necesarios])
		return
	var dir: Vector3 = pos - player.global_position
	dir.y = 0.0
	dir = dir.normalized()
	terrain.fell_tree(planta, dir)
	ui.message("¡Cae %s!" % ("el árbol de la costa" if es_palma else "el árbol"))
	_sonido("boom", pos, -8.0)
	Isla.registrar_evento("arbol_cortado", pos, 1.0)
	await get_tree().create_timer(1.3).timeout
	if not is_inside_tree():
		return
	for k in 2:
		var lp: Vector3 = pos + dir * (1.4 + float(k) * 1.5) + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
		lp.y = terrain.height_at(lp.x, lp.z)
		_spawn_item("madera", 2, lp)
	for k in 2:
		var rp: Vector3 = pos + dir * _rng.randf_range(0.8, 3.0) + Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
		rp.y = terrain.height_at(rp.x, rp.z)
		_spawn_item("hoja_grande" if es_palma else "rama", 1, rp)

# ------------------------------------------------------------------ combinar (C)

## Avisa cuando juntás lo necesario para fabricar algo nuevo.
func _avisar_recetas(delta: float) -> void:
	_aviso_t -= delta
	if _aviso_t > 0.0:
		return
	_aviso_t = 0.5
	for r: Dictionary in Recipes.LIST:
		var id: String = str(r["id"])
		var ok: bool = Recipes.can(r)
		if ok and not _aviso.get(id, false) and not _craft_open:
			ui.message("Ya podés fabricar: %s  (C)" % str(r["name"]))
			_aviso[id] = true
			return
		if not ok:
			_aviso[id] = false

func _refrescar_craft() -> void:
	if not _craft_open:
		ui.hide_recipes()
		return
	var list: Array[Dictionary] = []
	for r: Dictionary in Recipes.LIST:
		var outs: Array = (r["out"] as Dictionary).keys()
		list.append({"name": r["name"], "desc": r["desc"], "ing": Recipes.ingredients_text(r), "ok": Recipes.can(r), "icon": str(outs[0]) if not outs.is_empty() else "fuego"})
	ui.show_recipes(list, _craft_idx)

func _crear() -> void:
	var r: Dictionary = Recipes.LIST[_craft_idx]
	if not Recipes.can(r):
		ui.message("Te faltan materiales: %s" % Recipes.ingredients_text(r))
		return
	_craft_recipe = r                       # tarda unos segundos, con un círculo de espera
	_craft_dur = 3.0 if str(r.get("special", "")) == "fuego" else 2.2
	_craft_t = 0.0
	_crafting = true
	player.play_action("cut")
	_sonido("crack", player.global_position, -10.0)

func _terminar_crear(r: Dictionary) -> void:
	if not Recipes.can(r):
		ui.message("Te faltan materiales: %s" % Recipes.ingredients_text(r))
		return
	if str(r.get("special", "")) == "fuego":
		_encender()
		return
	for id: String in (r["consume"] as Dictionary).keys():
		Inventario.quitar(id, int(r["consume"][id]))
	for id2: String in (r["out"] as Dictionary).keys():
		var resto: int = Inventario.agregar(id2, int(r["out"][id2]))
		if resto > 0:
			var pos: Vector3 = player.global_position - player.global_transform.basis.z * 1.0
			pos.y = terrain.height_at(pos.x, pos.z)
			_spawn_item(id2, resto, pos)
		Inventario.descubrir(id2)
	_sonido("crack", player.global_position, -6.0)
	player.express("determined", 1.2)
	ui.message("Fabricás: %s" % str(r["name"]))
	_refrescar_craft()

## Chocar dos piedras junto a paja o leña. La paja prende casi siempre; solo con leña cuesta más.
func _encender() -> void:
	var fwd: Vector3 = -player.global_transform.basis.z
	var pos: Vector3 = player.global_position + fwd * 1.3
	var h: float = terrain.height_at(pos.x, pos.z)
	if h < 0.8:
		ui.message("Acá el suelo está mojado: no prende.")
		return
	pos.y = h
	var paja: bool = Inventario.tiene("paja")
	var lena: String = "rama" if Inventario.tiene("rama") else ("madera" if Inventario.tiene("madera") else "")
	var chance: float = 0.95 if (paja and lena != "") else (0.85 if paja else 0.3)
	_sonido("crack", player.global_position, -2.0)
	player.express("determined", 1.0)
	if _rng.randf() > chance:
		if paja and _rng.randf() < 0.5:
			Inventario.quitar("paja", 1)
		ui.message("Las chispas saltan pero no prenden. Probá de nuevo.")
		return
	var seg: float = 0.0
	if paja:
		Inventario.quitar("paja", 1)
		seg += float(FUEL_SECONDS["paja"])
	if lena != "":
		Inventario.quitar(lena, 1)
		seg += float(FUEL_SECONDS[lena])
	var fire := Campfire.new()
	fire.fuel = seg
	get_parent().add_child(fire)
	fire.global_position = pos
	_craft_open = false
	ui.hide_recipes()
	ui.message("¡El fuego prende!")
	Isla.registrar_evento("fuego", pos, 1.0)

## Echar leña a una fogata cercana con el objeto elegido (madera, rama o paja).
func _avivar() -> void:
	var e: Variant = Inventario.item_seleccionado()
	if e == null or not FUEL_SECONDS.has(str(e["id"])):
		ui.message("Elegí leña (madera, rama o paja) para echar al fuego.")
		return
	var id: String = str(e["id"])
	Inventario.quitar_en(Inventario.seleccionado, 1)
	_fire.add_fuel(float(FUEL_SECONDS[id]))
	_sonido("crack", _fire.global_position, -8.0)
	ui.message("Echás %s al fuego." % ItemDB.display_name(id).to_lower())

# ------------------------------------------------------------------ investigar

func _investigar() -> void:
	var texto: String = ""
	var pos: Vector3 = player.global_position
	if _target != null:
		var id: String = _target.item_id
		Inventario.descubrir(id)
		if id == "agua_dulce":
			texto = "Agua dulce y quieta. Los peces nadan tranquilos: debe ser potable."
		else:
			texto = "%s: %s" % [_target.display_name, str(ItemDB.get_def(id)["hint"])]
		pos = _target.global_position
	elif _stela != null:
		var linea: String = _stela.text.replace("\n", " · ")
		texto = ("Una tumba tallada. " if _stela.is_tomb else "Una piedra con marcas talladas por alguien que llegó antes que vos. ") + "Dice: «%s»" % linea
		pos = _stela.global_position
	elif _fire != null:
		texto = "Una fogata. Da luz y calor, y se apaga si no le echás leña." + (" Todavía arde." if _fire.is_burning() else " Ya no arde: solo quedan brasas.")
	elif _plant != null:
		var es_palma: bool = terrain.palm_nodes.has(_plant)
		if es_palma:
			texto = "Un árbol de la costa, torcido por el viento. Tiene hojas anchas y fibrosas; con una cuchilla podés cortar algunas (quedan %d). Con un hacha se puede talar." % int(_plant.get_meta("hojas", 0))
		else:
			var l: int = int(_plant.get_meta("lianas", 0))
			texto = "Un árbol de tronco grueso. " + (("Del follaje cuelgan %d lianas: con una cuchilla se cortan. " % l) if l > 0 else "No cuelgan lianas. ") + "Para talarlo hace falta un hacha."
		pos = _plant.global_position
	else:
		var sp: Dictionary = _lugar_cercano()
		if not sp.is_empty():
			var arr: Array = SPOT_INFO.get(str(sp["kind"]), ["Un lugar extraño."])
			texto = "%s. %s" % [str(sp["name"]), str(arr[_rng.randi() % arr.size()])]
			pos = sp["pos"]
		else:
			var e: Variant = Inventario.item_seleccionado()
			if e != null:
				var id2: String = str(e["id"])
				Inventario.descubrir(id2)
				texto = "%s: %s" % [ItemDB.display_name(id2), str(ItemDB.get_def(id2)["hint"])]
			else:
				ui.message("No hay nada que investigar acá.")
				return
	ui.show_info(texto)
	Isla.registrar_evento("explorar", pos, 0.3)      # investigar despierta la curiosidad de la isla

func _lugar_cercano() -> Dictionary:
	if features == null:
		return {}
	var best: Dictionary = {}
	var best_d: float = INF
	for sp: Dictionary in features.sacred_spots:
		var p: Vector3 = sp["pos"]
		var d: float = Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length()
		if d < float(sp["radius"]) + 3.0 and d < best_d:
			best_d = d
			best = sp
	return best
