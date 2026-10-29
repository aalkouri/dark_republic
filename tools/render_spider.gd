extends Node3D
## Preview the procedural spider (SpiderModel) walking on a floor and up a wall:
##   godot --path . res://tools/render_spider.tscn -- /out.png
var _frames: Array[Image] = []

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.environment.ambient_light_energy = 0.9
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(30, 20, 1)
	wall.mesh = bm
	wall.position = Vector3(0, 10, -12.5)
	add_child(wall)
	var sp := SpiderModel.new()
	add_child(sp)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50
	cam.look_at_from_position(Vector3(14, 9, 10), Vector3(0, 3, -4))
	# Walk forward across the floor, then on the wall (normal +Z), climbing up
	sp.global_transform = Transform3D(Basis(), Vector3(-6, 0, 2))
	await get_tree().process_frame
	sp.plant_all()
	for f in 160:
		var t := f / 60.0
		if f < 80:
			sp.global_position = Vector3(-6 + t * 6.0, 0, 2 - t * 2.0)
			sp.rotation = Vector3(0, -0.6, 0)
		else:
			if f == 80:
				sp.global_transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0, 3, -12))
				sp.plant_all()
			sp.global_position = Vector3(0, 3 + (t - 1.33) * 5.0, -12)
		if f in [20, 60, 100, 150]:
			sp.rear = 1.0 if f == 60 else 0.0
		await get_tree().process_frame
		if f in [20, 60, 100, 150]:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.resize(480, 300)
			_frames.append(img)
	var sheet := Image.create(960, 600, false, _frames[0].get_format())
	for k in _frames.size():
		sheet.blit_rect(_frames[k], Rect2i(0, 0, 480, 300), Vector2i((k % 2) * 480, (k / 2) * 300))
	sheet.save_png(out)
	get_tree().quit()
