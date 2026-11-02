extends Node
## Screenshots of a character's run-start entrance (needs a display, not --headless):
##   godot --fixed-fps 60 --path . res://tools/shot_entrance.tscn -- <char> <map> /out/prefix t1,t2,... [debug]
## Saves <prefix>_<t>.png at each entrance time t (seconds). Rendering is switched off between
## the captures (software GL is slow) and the game is paused for each one.

var main: Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var id := a[0]
	var map := a[1]
	var prefix := a[2]
	var times: Array[float] = []
	for s in a[3].split(","):
		times.append(float(s))
	Wallet.persist = false
	Settings.selected_character = id
	Settings.selected_map = map
	Settings.game_mode = "classic"
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	RenderingServer.render_loop_enabled = false
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	if main.get("player") == null:   # the game failed to load (a script error): don't spin
		get_tree().quit(1)
		return
	main.player.god_mode = true
	for c in main.hud.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	main.hud.visible = false
	Wallet.set_shown(false)
	var t := 0.0
	for at in times:
		while t < at - 0.0001:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		get_tree().paused = true
		RenderingServer.render_loop_enabled = true
		for f in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, str(at)])
		var e: HeroEntrances = main.abilities.entrance
		print("SHOT %s %.2f (entrance t %.2f, hero shown %s)" % [id, at, e.t if is_instance_valid(e) else -1.0, main.player.model.visible])
		if a.size() > 4 and a[4] == "debug":   # list what's drawn near the spot
			var tgt := Vector3(0, SwampWater.height_at(0, 0), 0)
			for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
				var g := n as GeometryInstance3D
				if g.is_visible_in_tree() and g.global_position.distance_to(tgt) < 3.0 and not str(g.get_path()).contains("Skeleton"):
					print("DRAWN ", g.get_path(), " ", g.get_class(), " ", g.global_position - tgt)
		RenderingServer.render_loop_enabled = false
		get_tree().paused = false
	get_tree().quit()
