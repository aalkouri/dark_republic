extends Node
## Skill trees: structure (3 categories x 2 rows x 3), per-character trees (wizard authored,
## others a fixed random draw), levels from EXP (1 per kill, table up to lvl 10), skill points
## (one per level), learning rules (row 2 needs row 1, Special locked until lvl 5), effects in
## a run, and the Skills button / screen (points "N/10", Special padlock).
##   godot --headless --path . res://tools/test_skills.tscn

var fails := 0


func _ready() -> void:
	Wallet.persist = false
	Wallet.coins = 0
	Wallet.char_exp = {}
	Wallet.char_skills = {}

	var t := SkillTree.tree_for("fire_wizard")
	var shape_ok := t.size() == 3
	for cat in SkillTree.CATEGORIES:
		shape_ok = shape_ok and t[cat].size() == 2 and t[cat][0].size() == 3 and t[cat][1].size() == 3
	_check("3 categories x 2 rows x 3 skills", shape_ok, "")
	_check("Defense / Offense / Special", SkillTree.CATEGORIES == ["Defense", "Offense", "Special"], "")
	_check("wizard has his own fire skills", t["Offense"][0][0]["name"] == "Kindling", t["Offense"][0][0]["name"])
	var k1 := SkillTree.tree_for("kong")
	_check("other characters get a fixed draw", JSON.stringify(k1) == JSON.stringify(SkillTree.tree_for("kong")), "")
	_check("draws differ between characters", JSON.stringify(k1) != JSON.stringify(SkillTree.tree_for("thog")), "")
	var ids := {}
	for cat in SkillTree.CATEGORIES:
		for tier in 2:
			for sk in k1[cat][tier]:
				ids[sk["id"]] = true
	_check("no duplicate skills in a tree", ids.size() == 18, "%d" % ids.size())

	# Levels from EXP
	var table := [[0, 0], [1999, 0], [2000, 1], [10000, 2], [50000, 3], [1000000, 4], [5000000, 5],
		[15000000, 6], [50000000, 7], [100000000, 8], [500000000, 9], [1000000000, 10], [5000000000, 10]]
	var table_ok := true
	for e in table:
		table_ok = table_ok and Wallet.level_for(e[0]) == e[1]
	_check("EXP table: lvl 1 at 2,000 ... lvl 10 at 1 billion, 10 is max", table_ok, "")
	_check("1 EXP per kill, levels reported", Wallet.add_char_exp("fire_wizard", 2500) == 1 and Wallet.char_level("fire_wizard") == 1, "")
	_check("skill points = level", Wallet.skill_points_total("fire_wizard") == 1 and Wallet.skill_points_free("fire_wizard") == 1, "")

	# Learning rules
	_check("row 2 needs a row-1 skill of the column", SkillTree.blocked_reason("fire_wizard", "wildfire").begins_with("Learn a offense"), SkillTree.blocked_reason("fire_wizard", "wildfire"))
	_check("learning uses a skill point (coins untouched)", SkillTree.learn("fire_wizard", "kindling") and Wallet.skill_points_free("fire_wizard") == 0 and Wallet.coins == 0, "")
	_check("learning doesn't change lvl", Wallet.char_level("fire_wizard") == 1, "")
	_check("no points left -> blocked", SkillTree.blocked_reason("fire_wizard", "ember_hide").begins_with("No skill points"), SkillTree.blocked_reason("fire_wizard", "ember_hide"))
	Wallet.set_char_exp("fire_wizard", 1000000)   # lvl 4
	_check("row 2 opens after a row-1 skill", SkillTree.learn("fire_wizard", "wildfire"), "")
	_check("can't learn twice", not SkillTree.learn("fire_wizard", "wildfire"), "")
	_check("row 2 in another column still locked", SkillTree.blocked_reason("fire_wizard", "phoenix_heart") != "", "")
	SkillTree.learn("fire_wizard", "ember_hide")
	_check("Special locked below lvl 5", SkillTree.category_locked("fire_wizard", "Special") and SkillTree.blocked_reason("fire_wizard", "gold_sense") == "Unlocks at level 5", SkillTree.blocked_reason("fire_wizard", "gold_sense"))
	Wallet.set_char_exp("fire_wizard", 5000000)   # lvl 5
	_check("Special opens at lvl 5", not SkillTree.category_locked("fire_wizard", "Special") and SkillTree.learn("fire_wizard", "gold_sense"), "")
	_check("4 skills learned with 5 points: 1 left", Wallet.skill_points_free("fire_wizard") == 1, "%d" % Wallet.skill_points_free("fire_wizard"))

	# Effects in a run
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	Settings.selected_character = "fire_wizard"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	var main: Node = get_tree().current_scene
	_check("skills apply at run start", main.skills_applied.size() == 4, str(main.skills_applied))
	_check("Ember Hide: +20 max HP", is_equal_approx(main.stats.value("max_hp"), 120.0) and is_equal_approx(main.player.max_hp, 120.0), "%.0f" % main.stats.value("max_hp"))
	_check("Kindling: +10% damage", is_equal_approx(main.stats.value("damage"), 1.1), "%.2f" % main.stats.value("damage"))
	_check("Wildfire: +1 fireball", is_equal_approx(main.stats.value("projectile_count"), 1.0), "")
	var r := Wallet.run_reward(100.0, 0, main.stats.value("coin_gain"))
	_check("Gold Sense: +15% coins", r["total"] == 115 and r["extra"] == 15, str(r))
	# Shield and cooldown skills
	main.stats.apply("ability_cdr", "mult", 0.8)
	main.abilities.cooldown[0] = 0.0
	main.abilities.try_cast(0)
	_check("Time Warp: abilities recharge 20% faster", is_equal_approx(main.abilities.cooldown[0], Abilities.DEFS[0]["cooldown"] * 0.8), "%.1f s" % main.abilities.cooldown[0])

	# Character select: Skills between Back and Play, the screen, learning from it
	main.to_title()
	await get_tree().scene_changed
	get_tree().change_scene_to_file.call_deferred("res://scenes/character_select.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	var cs: Node = get_tree().current_scene
	var row: Node = cs._skills_btn.get_parent()
	_check("Skills sits between Back and Play", row.get_children().find(cs._skills_btn) == 1 and row.get_child(0) == cs._back_btn and row.get_child(2) == cs._play_btn, "")
	_check("Skills enabled for the wizard", not cs._skills_btn.disabled, "")
	cs._tiles[cs.index_of("ogre")].grab_focus()
	await get_tree().process_frame
	_check("Skills disabled for locked characters", cs._skills_btn.disabled, "")
	cs._tiles[0].grab_focus()
	await get_tree().process_frame
	cs._skills_btn.pressed.emit()
	await get_tree().process_frame
	var sc: SkillScreen = cs.skills
	_check("Skills opens the tree", sc.visible and sc._squares.size() == 18, "%d squares" % sc._squares.size())
	_check("learned skills marked", (sc._squares["kindling"].get_meta("badge") as Label).text != "", "")
	_check("skill points shown as level/10", sc._points.text == "5/10" and sc._points_free.text == "1 to spend", "%s, %s" % [sc._points.text, sc._points_free.text])
	_check("Special padlock gone at lvl 5", not sc._lock_overlay.visible, "")
	sc._select("ashen_ward")
	_check("a free point lets you learn", not sc._learn.disabled, "")
	sc._learn_selected()
	_check("Learn uses the point", Wallet.skill_points_free("fire_wizard") == 0 and sc._points_free.text == "0 to spend", sc._points_free.text)
	sc._select("smoulder")
	(sc._squares["kindling"] as Button).mouse_entered.emit()
	await get_tree().process_frame
	_check("hovering another skill doesn't select it", sc._selected == "smoulder", sc._selected)
	sc._learn.grab_focus()
	await get_tree().process_frame
	var sel_box := (sc._squares["smoulder"] as Button).get_theme_stylebox("normal") as StyleBoxFlat
	_check("the clicked skill stays highlighted when focus moves away", sel_box.border_width_left == 5 and sc._selected == "smoulder", "%d" % sel_box.border_width_left)
	_check("no points: Learn disabled", sc._learn.disabled and "No skill points" in sc._info_cost.text, sc._info_cost.text)
	sc.close()
	await get_tree().process_frame
	# Below lvl 5 the Special column is greyed out under a padlock
	Wallet.set_char_exp("kong", 0)
	Wallet.set_char_exp("fire_wizard", 60000)   # lvl 3
	cs._skills_btn.pressed.emit()
	await get_tree().process_frame
	_check("Special padlock below lvl 5", sc._lock_overlay.visible and sc._lock_overlay.message == "Unlocks at level 5", "")
	_check("points show 3/10", sc._points.text == "3/10", sc._points.text)
	sc.close()
	await get_tree().process_frame
	var lvl_label := cs._tiles[0].get_meta("lvl") as Label
	_check("tile shows lvl from EXP", lvl_label.visible and lvl_label.text == "lvl 3", lvl_label.text)

	# Tome icons on the level-up cards
	var db := UpgradeDB.new("res://data/upgrades.json", RandomNumberGenerator.new())
	var glyphs := ["blade", "clock", "boot", "heart", "expand", "arrow", "magnet", "eye", "shield", "cross", "clover", "triple"]
	var bad := []
	var covers := {}
	for id in db.defs:
		var d: Dictionary = db.defs[id]
		if d["kind"] == "tome":
			var icon: Dictionary = d.get("icon", {})
			if not glyphs.has(icon.get("glyph", "")) or not Color.html_is_valid(str(icon.get("cover", ""))):
				bad.append(id)
			covers[icon.get("cover", "")] = true
			if db.describe({"id": id, "rarity": 0})["icon"] != icon:
				bad.append(id + " (describe)")
	_check("every tome has an icon (glyph + cover colour)", bad.is_empty(), str(bad))
	_check("every tome cover is a different colour", covers.size() == 12, "%d" % covers.size())
	var missing := []
	for id in db.defs:
		if db.describe({"id": id, "rarity": 0})["icon"].is_empty():
			missing.append(id)
	db.banned["tome_damage"] = true
	var seen_banned := false
	for k in 300:
		for pk in db.draft(3, 0.0, 3):
			if pk["id"] == "tome_damage":
				seen_banned = true
	_check("a banned reward never shows up in later drafts", not seen_banned, "")
	db.banned.clear()
	_check("every weapon and item has an icon too", missing.is_empty(), str(missing))

	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
