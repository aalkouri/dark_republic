extends Node3D
## Contact sheets of the Desert's models from a few angles (for checking the look quickly):
##   godot --path . res://tools/render_desert.tscn -- what /out.png
## what: sphinx | pyramid | props | crowd | pharaoh

var _frames: Array[Image] = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var what: String = a[0]
	var out: String = a[1]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.85)
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.68)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.8, 0.62, 0.42)
	pm.material = fm
	floor.mesh = pm
	add_child(floor)
	var cam := Camera3D.new()
	cam.fov = 40
	cam.far = 800
	add_child(cam)
	var views: Array = []   # [eye, target]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	match what:
		"sphinx":
			var sp := DesertSphinx.build(false)
			var mi := MeshInstance3D.new()
			mi.mesh = sp["mesh"]
			add_child(mi)
			views = [[Vector3(30, 14, 40), Vector3(0, 6, 0)], [Vector3(-42, 10, 0), Vector3(0, 6, -2)], [Vector3(0, 13, 26), Vector3(0, 11, 6)],
				[Vector3(9, 13, 18), Vector3(0, 12.2, 6.6)], [Vector3(25, 6, -30), Vector3(0, 5, -8)], [Vector3(-10, 4, 30), Vector3(0, 2, 14)]]
		"props":
			var items := [DesertProps.palm(rng, 0), DesertProps.palm(rng, 2), DesertProps.acacia(rng), DesertProps.dead_tree(rng), DesertProps.boulders(rng), DesertProps.rock_pillar(rng),
				DesertProps.fallen_column(rng), DesertProps.buried_head(rng), DesertProps.camel_skeleton(rng), DesertProps.mud_wall(rng), DesertProps.sarcophagus(rng), DesertProps.fallen_obelisk(rng),
				DesertProps.landmark(rng, 0), DesertProps.landmark(rng, 1), DesertProps.landmark(rng, 2), DesertProps.landmark(rng, 3), DesertProps.landmark(rng, 4)]
			for k in items.size():
				var mi := MeshInstance3D.new()
				mi.mesh = items[k]["mesh"]
				mi.position = Vector3((k % 6) * 40.0, 0, (k / 6) * 40.0)
				add_child(mi)
				var c: Vector3 = mi.position
				var big := 1.0 if k < 12 else 2.0
				views.append([c + Vector3(8, 6, 11) * big, c + Vector3(0, 2.5 * big, 0)])
		"crowd":
			var meshes: Array = load("res://scripts/desert_crowd.gd").preview_meshes()
			for k in meshes.size():
				var mi := MeshInstance3D.new()
				mi.mesh = meshes[k]
				mi.position = Vector3(k * 6.0, 0, 0)
				add_child(mi)
				views.append([mi.position + Vector3(2.2, 1.8, 4.2), mi.position + Vector3(0, 0.95, 0)])
				views.append([mi.position + Vector3(-3.0, 1.4, 1.5), mi.position + Vector3(0, 0.9, 0)])
		"pharaoh":
			var m: Node3D = load("res://scripts/pharaoh_model.gd").new()
			m.name = "PharaohPreview"
			add_child(m)
			views = [[Vector3(3, 2.0, -5), Vector3(0, 1.1, 0)], [Vector3(-0.5, 1.75, -1.3), Vector3(0, 1.6, 0)], [Vector3(-5, 2, -3), Vector3(0, 1.1, 0)], [Vector3(2, 1.8, 4.5), Vector3(0, 1.1, 0)]]
			for pose in ["slam", "beam", "summon", "walk"]:
				views.append([Vector3(3.5, 2.0, -5), Vector3(0, 1.1, 0), pose])
	await get_tree().process_frame
	for v in views:
		if v.size() > 2:
			var m: Node = find_child("PharaohPreview", true, false)
			m.call("pose_preview", v[2])
		cam.look_at_from_position(v[0], v[1])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(480, 360)
		_frames.append(img)
	var cols := 3 if views.size() <= 9 else 4
	var rows := int(ceil(views.size() / float(cols)))
	var sheet := Image.create(480 * cols, 360 * rows, false, _frames[0].get_format())
	for k in _frames.size():
		sheet.blit_rect(_frames[k], Rect2i(0, 0, 480, 360), Vector2i((k % cols) * 480, (k / cols) * 360))
	sheet.save_png(out)
	get_tree().quit()
