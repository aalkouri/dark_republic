extends Node3D
## Renders the Magical Forest's 7 trees, a fallen log and both landmarks side by side at night:
##   godot --path . res://tools/render_forest_props.tscn -- /out.png
var t := 0.0
func _ready():
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.03, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.3, 0.55)
	e.ambient_light_energy = 0.6
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.1
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-40, 30, 0)
	moon.light_color = Color(0.6, 0.65, 1.0)
	moon.light_energy = 0.35
	add_child(moon)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 60)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.05, 0.08, 0.07)
	pm.material = gm
	ground.mesh = pm
	add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var items := []
	for v in ForestProps.VARIANTS:
		items.append(ForestProps.tree(v, rng))
	items.append(ForestProps.fallen_log(rng))
	items.append(ForestProps.landmark(rng, 0))
	items.append(ForestProps.landmark(rng, 1))
	var bsh := Shader.new()
	bsh.code = BushField.SHADER
	var bmat := ShaderMaterial.new()
	bmat.shader = bsh
	for k in 4:
		items.append({"mesh": BushField._bush_mesh(rng, k, bmat)})
	for k in items.size():
		var mi := MeshInstance3D.new()
		mi.mesh = items[k]["mesh"]
		mi.position = Vector3((k - (items.size() - 1) * 0.5) * 14.0, 0, 0)
		if k == ForestProps.VARIANTS:
			mi.position.y = 0.6
		add_child(mi)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50
	var cx := float(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 0.0
	var dist := 30.0 if OS.get_cmdline_user_args().size() > 1 else 80.0
	cam.look_at_from_position(Vector3(cx, 7, dist), Vector3(cx, 6, 0))
func _process(dt):
	t += dt
	if t > 0.6:
		set_process(false)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		get_tree().quit()
