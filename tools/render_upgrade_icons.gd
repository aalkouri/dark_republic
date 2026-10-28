extends SceneTree
## Renders every level-up icon (tomes, weapons, items) with its name:
##   godot --path . --script res://tools/render_upgrade_icons.gd -- /out.png
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.05)
	bg.size = Vector2(1000, 560)
	root.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(20, 20)
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 24)
	bg.add_child(grid)
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/upgrades.json"))
	for u in d["upgrades"]:
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(140, 0)
		var t := UpgradeIcon.create(u["icon"], u["kind"])
		t.custom_minimum_size = Vector2(128, 128)
		t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(t)
		var l := Label.new()
		l.text = str(u["name"]).trim_prefix("Tome of ")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		grid.add_child(v)
	root.size = Vector2i(1000, 560)
	for f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().get_region(Rect2i(0, 0, 1000, 560)).save_png(out)
	quit()
