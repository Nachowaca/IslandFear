extends Node3D

## Mantaraya celeste luminosa que, de noche, sobrevuela la isla a ~300 m de la costa.
## Cada 10 minutos emite un canto suave y grave, como de un animal ancestral (sintetizado en código).

const ORBIT_R: float = 420.0            ## la isla llega a ~120 m, así que queda a ~300 m de la costa
const HEIGHT: float = 55.0
const SPEED: float = 0.02               ## rad/s (una vuelta cada ~5 min)
const SONG_EVERY: float = 600.0
const SONG_FIRST: float = 45.0          ## primer canto poco después de caer la noche

var daynight: Node

const SHADER: String = "shader_type spatial;\nrender_mode unshaded, blend_add, cull_disabled, fog_disabled, depth_draw_never;\nuniform vec3 tint = vec3(0.3, 0.95, 1.0);\nuniform float alpha = 1.0;\nuniform float flap_time = 0.0;\nvoid vertex() {\n\tfloat x = abs(VERTEX.x);\n\tfloat lag = flap_time - x * 0.32;\n\tVERTEX.y += sin(lag) * x * 0.1 + sin(lag * 2.0 + 1.0) * x * 0.02;\n\tVERTEX.z += sin(lag - 1.0) * x * 0.015;\n}\nvoid fragment() {\n\tALBEDO = COLOR.rgb * tint;\n\tALPHA = COLOR.a * alpha;\n}\n"

var _wings: Array[Node3D] = []
var _mat: ShaderMaterial
var _ang: float = 0.0
var _vis: float = 0.0
var _time: float = 0.0
var _player: AudioStreamPlayer3D
var _song_timer: float = SONG_FIRST

func _ready() -> void:
	_ang = randf() * TAU
	_build()
	visible = false

func _wing_mesh() -> ArrayMesh:
	# malla subdividida (para que se doble con la onda del shader)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx: int = 10
	var nz: int = 3
	for i in nx:
		for j in nz:
			for q: Array in [[0, 0], [1, 0], [0, 1], [1, 0], [1, 1], [0, 1]]:
				var u: float = float(i + int(q[0])) / float(nx)
				var v: float = float(j + int(q[1])) / float(nz)
				var x: float = u * 11.0
				var zl: float = lerpf(-3.2, -2.0, x / 5.0) if x < 5.0 else lerpf(-2.0, 1.4, (x - 5.0) / 6.0)
				var zt: float = lerpf(3.0, 2.3, x / 4.5) if x < 4.5 else lerpf(2.3, 1.4, (x - 4.5) / 6.5)
				var z: float = lerpf(zl, zt, v)
				var edge: float = 1.0 - absf(v - 0.5) * 2.0
				var k: float = clampf(1.0 - u * 0.85, 0.0, 1.0)
				st.set_color(Color(0.15 + 0.75 * k, 0.65 + 0.35 * k, 1.0, (0.18 + 0.82 * k) * (0.45 + 0.55 * edge)))
				st.add_vertex(Vector3(x, 0.04 * x, z))
	return st.commit()

func _part(mesh: Mesh, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _build() -> void:
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	var wm: ArrayMesh = _wing_mesh()
	for sgn: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sgn * 0.6, 0, 0)
		pivot.scale = Vector3(sgn, 1, 1)
		_part(wm, pivot)
		add_child(pivot)
		_wings.append(pivot)
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 8
	sm.rings = 4
	var body: MeshInstance3D = _part(sm, self)
	body.scale = Vector3(1.5, 0.7, 3.6)
	var tm := CylinderMesh.new()
	tm.top_radius = 0.02
	tm.bottom_radius = 0.18
	tm.height = 10.0
	tm.radial_segments = 4
	var tail: MeshInstance3D = _part(tm, self)
	tail.rotation = Vector3(PI / 2.0, 0, 0)
	tail.position = Vector3(0, 0, 8.5)
	scale = Vector3.ONE * 2.2
	_player = AudioStreamPlayer3D.new()
	_player.bus = "Ambience"
	_player.unit_size = 120.0
	_player.max_distance = 1500.0
	_player.volume_db = -4.0
	add_child(_player)

func _process(delta: float) -> void:
	_time += delta
	if daynight == null:
		daynight = get_tree().get_first_node_in_group("daynight")
		return
	var night: float = float(daynight.get("night_amount"))
	_vis = move_toward(_vis, smoothstep(0.55, 0.9, night), delta * 0.25)
	visible = _vis > 0.01
	if not visible:
		return
	_ang -= SPEED * delta
	var pulse: float = 0.8 + 0.2 * sin(_time * 1.3)
	_mat.set_shader_parameter("tint", Vector3(0.3, 0.95, 1.0) * pulse)
	_mat.set_shader_parameter("alpha", 0.85 * _vis)
	_mat.set_shader_parameter("flap_time", _time * 1.4)
	var pos := Vector3(cos(_ang) * ORBIT_R, HEIGHT + sin(_time * 0.15) * 5.0, sin(_ang) * ORBIT_R)
	position = pos
	look_at(global_position + Vector3(sin(_ang), 0.0, -cos(_ang)), Vector3.UP)
	rotate_object_local(Vector3.BACK, -0.18)             # leve inclinación al girar
	_song_timer -= delta
	if _song_timer <= 0.0 and _vis > 0.8:
		_song_timer = SONG_EVERY
		if _player.stream == null:
			_player.stream = _make_song()
		_player.play()

## Canto grave y lento: glissando con vibrato, armónicos y eco largo.
func _make_song() -> AudioStreamWAV:
	var sr: int = 16000
	var n: int = int(11.0 * float(sr))
	var d := PackedFloat32Array()
	d.resize(n)
	var ph1: float = 0.0
	var ph2: float = 0.0
	for i in n:
		var t: float = float(i) / float(sr)
		var u: float = t / 8.0
		var f: float = 82.0 + 70.0 * sin(clampf(u, 0.0, 1.0) * PI * 0.5) - 45.0 * smoothstep(0.55, 1.0, u)
		f *= 1.0 + 0.012 * sin(t * 5.2) * smoothstep(0.1, 0.5, u)
		ph1 += TAU * f / float(sr)
		ph2 += TAU * f * 1.4983 / float(sr)
		var env: float = smoothstep(0.0, 2.2, t) * (1.0 - smoothstep(6.5, 8.5, t))
		var v: float = sin(ph1) + 0.45 * sin(ph1 * 2.0) + 0.2 * sin(ph1 * 3.0) + 0.35 * sin(ph2) * smoothstep(1.5, 4.0, t)
		d[i] = v * env
	var echoes: Array = [[0.5, 0.4], [1.1, 0.28], [1.9, 0.18], [2.8, 0.1]]
	for e: Array in echoes:
		var off: int = int(float(e[0]) * float(sr))
		var g: float = e[1]
		for i in range(n - 1, off - 1, -1):
			d[i] += d[i - off] * g
	var lp: float = 0.0
	var a: float = 1.0 - exp(-TAU * 900.0 / float(sr))
	var mx: float = 0.0001
	for i in n:
		lp += (d[i] - lp) * a
		d[i] = lp
		mx = maxf(mx, absf(lp))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, clampi(int(d[i] / mx * 0.8 * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = bytes
	return w
