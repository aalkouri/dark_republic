extends Node
## Screenshot the end screen: godot --path . res://tools/shot_end.tscn -- --shot=/out.png [--won]
func _ready() -> void:
	var out := ""
	var won := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			out = a.split("=")[1]
		elif a == "--won":
			won = true
	Wallet.persist = false
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 10:
		await get_tree().process_frame
	var main: Node = get_tree().current_scene
	main.run_time = 462.0
	main.kills = 1532
	main.elites_killed = 12
	main.chests_opened = 2
	main.level = 14
	main.shards_won = {"dark": 2, "ice": 1}
	main.player.last_hit_by = "Goblin Brute"
	main.player.damage_by = {"Goblin": 412.0, "Goblin Brute": 230.0}
	main.enemies.damage_by = {"Fireballs": 24180.0, "Meteor": 9800.0, "Stink Aura": 3120.0}
	main.state = "dead"
	main.hud.show_end(won)
	for f in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
