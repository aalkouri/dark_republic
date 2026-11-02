extends Node
## Screenshots of the minimap and the NUKE (with the HUD), one per run:
##   godot --rendering-driver opengl3 --path . res://tools/shot_minimap.tscn -- MODE OUT.png
## MODE: play (swamp, a horde, chests, power-ups) | quake (Thog's quake, ponds marked) |
##       bossarrow (Thog far off: the red rim arrow) | pickup (the NUKE pickup close up) |
##       cloud (a NUKE's mushroom cloud mid-blast; T seconds in via MODE cloud:T)

var main: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "play"
	var out: String = args[1] if args.size() > 1 else "/tmp/mm.png"
	var at := 1.8
	if mode.begins_with("cloud:"):
		at = float(mode.split(":")[1])
		mode = "cloud"
	get_tree().create_timer(2300.0, true, false, true).timeout.connect(func(): get_tree().quit(1))   # never hang
	Wallet.persist = false
	Settings.selected_character = "fire_wizard"
	Settings.selected_map = "swamp"
	Settings.show_minimap = true
	seed(5)
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	if not ("intro" in main):   # main.gd failed to load (a broken script elsewhere): don't hang
		printerr("main.gd did not load")
		get_tree().quit(1)
		return
	for f in 60 * 8:
		await get_tree().physics_frame
		if not main.intro:
			break
	print("run started at %d ms" % Time.get_ticks_msec())
	main.player.god_mode = true
	main.xp_next = 1e12
	main._next_swarm = 1e9
	var p: Vector3 = main.player.global_position
	var y: float = main.player.cam_yaw
	var fwd := Vector3(-sin(y), 0, -cos(y))
	var right := Vector3(cos(y), 0, -sin(y))
	var em: EnemyManager = main.enemies
	match mode:
		"play", "quake", "bossarrow":
			for k in 220:
				em.spawn(EnemyManager.GRUNT if k % 5 else EnemyManager.RUNNER, p + Vector3(randf_range(-60, 60), 0, randf_range(-60, 60)), 1.0, k % 30 == 0)
			main.powerups.drop(p + fwd * 18.0 + right * 10.0, PowerupManager.NUKE)
			main.powerups.drop(p - fwd * 25.0 + right * 20.0, PowerupManager.DAMAGE)
			main.potions.drop(p + right * -15.0 + fwd * 8.0, 1)
			main.keys.drop(p + right * 12.0 - fwd * 6.0, 1)
			if mode != "play":
				main.run_time = main.THOG_TIME + 0.1
				await _secs(0.5)
			if mode == "quake":
				var pc: Vector2 = main.water.pools[0]["center"]   # stand near a pond so its mark shows
				var near := Vector3(pc.x + 22.0, 0, pc.y + 12.0)
				main.player.global_position = Vector3(near.x, SwampWater.height_at(near.x, near.z) + 0.5, near.z)
				main.player.velocity = Vector3.ZERO
				main.thog._start_quake()
				await _secs(2.0)
			elif mode == "bossarrow":
				em.pos[main.thog.row()] = p - fwd * 80.0 - right * 80.0   # behind you, to the left
				await _secs(0.4)
				em.pos[main.thog.row()] = p - fwd * 80.0 - right * 80.0
			else:
				await _secs(1.0)
		"pickup":
			_no_hud()
			var at3 := p + fwd * 5.0
			at3.y = SwampWater.height_at(at3.x, at3.z)
			main.powerups.drop(at3, PowerupManager.NUKE)
			_look(at3 - fwd * 1.3 + right * 1.0 + Vector3(0, 1.75, 0), at3 + Vector3(0, 0.85, 0), 45.0)
			await _secs(0.6)
		"cloud":
			_no_hud()
			for k in 260:
				em.spawn(EnemyManager.GRUNT, p + fwd * 35.0 + Vector3(randf_range(-45, 45), 0, randf_range(-45, 45)), 1.0)
			var spot := p + fwd * 45.0
			spot.y = SwampWater.height_at(spot.x, spot.z)
			_look(spot - fwd * 85.0 + Vector3(0, 28.0, 0), spot + Vector3(0, 14.0, 0), 65.0)
			await _secs(0.3)
			main.powerups.nuke(spot)
			await _secs(at)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()


func _no_hud() -> void:
	main.hud.visible = false
	Wallet.set_shown(false)
	for c in main.hud.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false


## A camera of our own for close-ups and wide shots.
func _look(from: Vector3, target: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.global_position = from
	cam.look_at(target)
	cam.fov = fov
	cam.far = 900.0
	cam.current = true


## Advance `s` game seconds in few rendered frames (software rendering here is very slow):
## run the clock 10x fast, then back to normal for the picture.
func _secs(s: float) -> void:
	Engine.time_scale = 10.0
	for f in maxi(2, int(s * 6.0)):
		await get_tree().physics_frame
	Engine.time_scale = 1.0
