extends Node3D
## Renders game models (RosterHero / the Fire Wizard's HeroModel) with their weapons put away,
## each seen from the back, the side and the front:
##   godot --path . res://tools/render_holster.tscn -- id1,id2,... /path/out.png [rest|attack|cast]
## "attack" fires a weapon attack 0.32 s before the picture (weapon drawn), "cast" an ability.
var t := 0.0
var _heroes: Array[HeroBase] = []
var _mode := "rest"
var _fired := false
const SHOT_AT := 1.2


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var ids: Array = args[0].split(",")
	_mode = args[2] if args.size() > 2 else "rest"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 20, 0)
	add_child(sun)
	var back_light := DirectionalLight3D.new()
	back_light.rotation_degrees = Vector3(-30, 200, 0)
	back_light.light_energy = 0.7
	add_child(back_light)
	var n := ids.size()
	var gap := 1.5
	for k in n:
		for view in 3:   # 0: back, 1: side, 2: front
			var id: String = ids[k]
			var h: HeroBase = HeroModel.new() if id == "fire_wizard" else RosterHero.create(id)
			h.position = Vector3((k - (n - 1) * 0.5) * gap * 3.0 + (view - 1.0) * gap, 0, 0)
			h.rotation.y = [0.45, -PI * 0.5 + 0.45, PI + 0.45][view]   # faces -Z: 0 shows the back (the idle turns the torso ~30 deg)
			add_child(h)
			var tall := 2.3 if id in ["ogre", "thog"] else 1.8
			h.scale = Vector3.ONE * (1.8 / tall)
			_heroes.append(h)
		var lbl := Label3D.new()
		lbl.text = ids[k]
		lbl.font_size = 64
		lbl.pixel_size = 0.004
		lbl.position = Vector3((k - (n - 1) * 0.5) * gap * 3.0, 2.15, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(lbl)
	var cam := Camera3D.new()
	add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var vp := Vector2i(n * 1000, 900)
	get_window().size = vp
	cam.size = maxf(2.5, (n * gap * 3.0 + 0.2) * float(vp.y) / float(vp.x))
	cam.look_at_from_position(Vector3(0, 1.5, 8.0), Vector3(0, 1.1, 0))


func _process(dt: float) -> void:
	t += dt
	if not _fired and _mode != "rest" and t > SHOT_AT - 0.32:
		_fired = true
		for h in _heroes:
			if _mode == "attack":
				h.attack(h.global_position + h.global_transform.basis * Vector3(0, 1, -5))
			else:
				h.play_ability(0)
	if t > SHOT_AT:
		set_process(false)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[1])
		get_tree().quit()
