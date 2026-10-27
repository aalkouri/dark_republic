extends Node
## Skill trees: structure (3 categories x 2 rows x 3), per-character trees (wizard authored,
## others a fixed random draw), learning rules (coins, row 2 needs row 1, lvl +1), effects in
## a run, and the Skills button / screen on character select.
##   godot --headless --path . res://tools/test_skills.tscn

var fails := 0


func _ready() -> void:
	Wallet.persist = false
	Wallet.coins = 0
	Wallet.char_levels = {}
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

	# Learning rules
	_check("can't learn without coins", SkillTree.blocked_reason("fire_wizard", "kindling") == "Not enough coins", SkillTree.blocked_reason("fire_wizard", "kindling"))
	Wallet.coins = 1000
	_check("row 2 needs a row-1 skill of the column", SkillTree.blocked_reason("fire_wizard", "wildfire").begins_with("Learn a offense"), SkillTree.blocked_reason("fire_wizard", "wildfire"))
	_check("learn row 1", SkillTree.learn("fire_wizard", "kindling") and Wallet.coins == 850, "%d" % Wallet.coins)
	_check("learning raises lvl by 1", Wallet.char_level("fire_wizard") == 1, "")
	_check("row 2 opens after a row-1 skill", SkillTree.learn("fire_wizard", "wildfire") and Wallet.coins == 450, "%d" % Wallet.coins)
	_check("can't learn twice", not SkillTree.learn("fire_wizard", "wildfire"), "")
	_check("row 2 in another column still locked", SkillTree.blocked_reason("fire_wizard", "phoenix_heart") != "", "")
	SkillTree.learn("fire_wizard", "ember_hide")
	SkillTree.learn("fire_wizard", "gold_sense")
	_check("lvl = skills learned", Wallet.char_level("fire_wizard") == 4, "%d" % Wallet.char_level("fire_wizard"))

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
	Wallet.coins = 100
	sc._select("phoenix_heart")
	_check("can't learn what you can't afford", sc._learn.disabled and "Not enough coins" in sc._info_cost.text, sc._info_cost.text)
	Wallet.coins = 500
	sc._select("ashen_ward")
	_check("affordable row-1 skill can be learned", not sc._learn.disabled, "")
	sc._learn_selected()
	_check("Learn spends coins and raises lvl", Wallet.coins == 350 and Wallet.char_level("fire_wizard") == 5, "%d coins, lvl %d" % [Wallet.coins, Wallet.char_level("fire_wizard")])
	sc.close()
	await get_tree().process_frame
	var lvl_label := cs._tiles[0].get_meta("lvl") as Label
	_check("tile shows the new lvl after closing", lvl_label.visible and lvl_label.text == "lvl 5", lvl_label.text)

	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
