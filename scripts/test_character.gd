extends Node3D
## Escena de prueba del personaje nuevo (CastawayModel) en distintos estados.

const STATES: Array[String] = ["idle", "walk", "run", "crouch", "air", "death", "pickup", "eat", "drink", "cut"]
var _models: Array[CastawayModel] = []
var _t: float = 0.0

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.75)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var n: int = STATES.size()
	for i in n:
		var m := CastawayModel.new()
		m.position = Vector3(0.0, 0.0, -float(i) * 1.5)
		add_child(m)
		m.build()
		_models.append(m)
		var lb := Label3D.new()
		lb.text = STATES[i]
		lb.font_size = 64
		lb.pixel_size = 0.004
		lb.position = m.position + Vector3(0, 2.1, 0)
		lb.rotation.y = PI * 0.5
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(lb)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(12.0, 1.3, -6.7)
	cam.fov = 40.0
	cam.look_at(Vector3(0, 0.9, -6.7))
	cam.make_current()

func _physics_process(dt: float) -> void:
	_t += dt
	for i in _models.size():
		var m: CastawayModel = _models[i]
		match STATES[i]:
			"idle": m.update(dt, 0.0, false, false, 0.0)
			"walk": m.update(dt, 4.0, false, false, 0.0)
			"run": m.update(dt, 7.5, false, false, 0.0)
			"crouch": m.update(dt, 0.0, false, false, 1.0)
			"air": m.update(dt, 4.0, _t < 0.5 or _t > 3.0, false, 0.0)
			"death": m.update(dt, 0.0, false, _t > 0.3, 0.0)
			"pickup":
				m.update(dt, 0.0, false, false, 0.0)
				m.pose.act = "pickup"
				m.pose.act_w = 1.0
			_:
				m.update(dt, 0.0, false, false, 0.0)
				if fmod(_t, 2.5) < dt:
					m.play_action(STATES[i])
