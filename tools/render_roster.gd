extends Node3D
## Renders roster models side by side for a quick look:
##   godot --path . res://tools/render_roster.tscn -- id1,id2,... /path/out.png
var t := 0.0
func _ready():
	var ids: Array = OS.get_cmdline_user_args()[0].split(",")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	add_child(sun)
	for k in ids.size():
		var m := RosterModel.create(ids[k])
		m.position = Vector3((k - (ids.size() - 1) * 0.5) * 1.6, 0, 0)
		m.rotation.y = PI + 0.35
		add_child(m)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	cam.look_at_from_position(Vector3(0, 1.3, 5.4 + ids.size() * 0.4), Vector3(0, 0.95, 0))
func _process(dt):
	t += dt
	if t > 0.4:
		set_process(false)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[1])
		get_tree().quit()
