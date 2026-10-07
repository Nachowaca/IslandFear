extends SceneTree

func _init() -> void:
	var img: Image = Image.load_from_file("res://docs/ref/islarefe.jpg")
	var w: int = img.get_width()
	var h: int = img.get_height()
	var m := Image.create(w, h, false, Image.FORMAT_L8)
	for y in h:
		for x in w:
			var c: Color = img.get_pixel(x, y)
			var r: float = c.r * 255.0
			var g: float = c.g * 255.0
			var b: float = c.b * 255.0
			var land: bool = (g - b > 10.0) or (r - b > 14.0) or (r > 150.0 and g > 150.0 and b > 140.0 and y > 150)
			m.set_pixel(x, y, Color(1, 1, 1) if land else Color(0, 0, 0))
	DirAccess.make_dir_recursive_absolute("res://assets/terrain")
	m.save_png("res://assets/terrain/mask_raw.png")
	print(w, "x", h)
	quit()
