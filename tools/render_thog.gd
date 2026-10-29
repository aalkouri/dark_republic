extends Node3D
## Contact sheet of Thog's clips (for picking segments):
##   godot --path . res://tools/render_thog.tscn -- clip /out.png [t0 t1 frames]
## Renders `frames` evenly spaced poses of the Ogre clip `clip` between t0 and t1.

var _frames: Array[Image] = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var clip: String = a[0]
	var out: String = a[1]
	var t0 := float(a[2]) if a.size() > 2 else 0.0
	var t1 := float(a[3]) if a.size() > 3 else -1.0
	var n := int(a[4]) if a.size() > 4 else 8
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	add_child(sun)
	var m := ThogModel.new()
	m.rotation.y = PI * 0.75
	add_child(m)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	cam.look_at_from_position(Vector3(0, 1.4, 6.0), Vector3(0, 1.15, 0))
	await get_tree().process_frame
	var lib: AnimationLibrary = load("res://models/ogre/anims.res")
	if t1 < 0.0:
		t1 = lib.get_animation(clip).length
	m.set_process(false)
	m.player.play("c/" + clip)
	m.player.speed_scale = 0.0
	for k in n:
		var t := lerpf(t0, t1, float(k) / maxf(n - 1, 1))
		m.player.seek(t, true)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(320, 360)
		_frames.append(img)
		print("frame %d t=%.2f" % [k, t])
	var cols := 4
	var rows := int(ceil(n / float(cols)))
	var sheet := Image.create(320 * cols, 360 * rows, false, _frames[0].get_format())
	for k in _frames.size():
		sheet.blit_rect(_frames[k], Rect2i(0, 0, 320, 360), Vector2i((k % cols) * 320, (k / cols) * 360))
	sheet.save_png(out)
	get_tree().quit()
