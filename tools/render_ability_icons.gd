extends SceneTree
## Renders every character's three ability slots (data/abilities.json) on one sheet:
##   godot --path . --script res://tools/render_ability_icons.gd -- /out.png
const W := 1500
const H := 680


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.05)
	bg.size = Vector2(W, H)
	root.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.position = Vector2(16, 16)
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 14)
	bg.add_child(grid)
	var kits := KitDB.kits()
	for id in kits:
		if id == "fire_wizard":
			continue
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		var l := Label.new()
		l.text = id
		l.add_theme_font_size_override("font_size", 13)
		v.add_child(l)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		for i in 3:
			var a := KitDB.ability(id, i)
			var s := AbilitySlot.new()
			s.glyph = a["icon"]["glyph"]
			s.glyph_color = Color(a["icon"]["color"])
			s.key_text = KitDB.KEYS[i]
			s.is_ult = i == 2
			row.add_child(s)
		v.add_child(row)
		var n := Label.new()
		n.text = " / ".join([KitDB.ability(id, 0)["name"], KitDB.ability(id, 1)["name"], KitDB.ability(id, 2)["name"]])
		n.add_theme_font_size_override("font_size", 10)
		n.custom_minimum_size = Vector2(250, 0)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(n)
		grid.add_child(v)
	root.size = Vector2i(W, H)
	for f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().get_region(Rect2i(0, 0, W, H)).save_png(out)
	quit()
