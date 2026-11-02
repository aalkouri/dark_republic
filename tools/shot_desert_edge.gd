extends Node
## Screenshot the Desert's edge: godot --path . res://tools/shot_desert_edge.tscn -- --out=/out.png
func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.split("=")[1]
	Settings.selected_map = "desert"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 4:
		await get_tree().process_frame
	var main: Node = get_tree().current_scene
	main._next_swarm = 1e9
	var p: Node3D = main.player
	p.global_position = Vector3(40, SwampWater.height_at(40, -200) + 1.0, -200)
	p.cam_yaw = 0.35   # facing the north edge, a little to the side
	for f in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
