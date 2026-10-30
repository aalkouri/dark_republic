extends Node
## The Forge: shard recipes and costs, forging, forged stats in a run (own weapon and the
## Legendary card), the Fireballs' every-5th-hit explosion, and the character select's shard
## row, pulsing weapon and forge menu.
##   godot --headless --path . res://tools/test_forge.tscn

var fails := 0


func _ready() -> void:
	Wallet.persist = false
	Wallet.forge = {}
	_reset_shards()
	_test_costs()
	_test_forging()
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	await _test_select()
	await _test_run()
	Wallet.forge = {}
	_reset_shards()
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _reset_shards() -> void:
	for k in Wallet.SHARDS:
		Wallet.shards[k] = 0


func _test_costs() -> void:
	var all_five := true
	for sty in WeaponSystem.STYLES:
		var r: Dictionary = Forge.RECIPES.get(sty, {})
		var n := 0
		for kind in r:
			n += int(r[kind])
		all_five = all_five and n == 5
	_check("every weapon has a recipe of exactly 5 shards", all_five and Forge.RECIPES.size() == WeaponSystem.STYLES.size(), "")
	_check("Ice Wizard: 5 ice", Forge.cost("ice", 1) == {"ice": 5}, str(Forge.cost("ice", 1)))
	_check("Fire Wizard: 5 fire", Forge.cost("fire", 1) == {"fire": 5}, str(Forge.cost("fire", 1)))
	_check("the Sock: 2 dark + 3 lightning", Forge.cost("static", 1) == {"lightning": 3, "dark": 2}, str(Forge.cost("static", 1)))
	var rising := true
	var last := 0
	for lvl in range(1, Forge.MAX_LEVEL + 1):
		var c := Forge.cost("static", lvl)
		var n := 0
		for kind in c:
			n += int(c[kind])
		rising = rising and n == Forge.TOTALS[lvl - 1] and n > last
		last = n
	_check("costs rise steeply up to level 10 (5 ... 100 shards)", rising and last == 100, "%d" % last)
	_check("nothing past level 10", Forge.cost("fire", 11).is_empty(), "")


func _test_forging() -> void:
	_check("can't forge without the shards", not Forge.can_afford("ice") and not Forge.forge("ice"), "")
	Wallet.shards["ice"] = 7
	_check("with 5 ice shards the Frost Shards can be forged", Forge.can_afford("ice"), "")
	_check("forging spends them and raises the level", Forge.forge("ice") and Forge.level_of("ice") == 1 and Wallet.shards["ice"] == 2, str(Wallet.shards))
	_check("level 2 needs 10", Forge.next_cost("ice") == {"ice": 10} and not Forge.can_afford("ice"), str(Forge.next_cost("ice")))
	_check("each level: +25% damage, +8% attack rate; +1 shot at 4 and 8",
		is_equal_approx(Forge.damage_mult(4), 2.0) and is_equal_approx(Forge.rate_mult(10), 1.8) and Forge.count_bonus(3) == 0 and Forge.count_bonus(4) == 1 and Forge.count_bonus(10) == 2, "")
	Wallet.forge = {}
	_reset_shards()


func _test_select() -> void:
	Wallet.unlocked_chars = []
	get_tree().change_scene_to_file.call_deferred("res://scenes/character_select.tscn")
	await get_tree().scene_changed
	for f in 5:
		await get_tree().process_frame
	var cs = get_tree().current_scene
	var picked: int = cs._picked
	cs._on_tile_hover(5, true)
	_check("hovering a character shows its panel", cs._shown == 5, "%d" % cs._shown)
	cs._on_tile_hover(5, false)
	await get_tree().process_frame
	_check("...and moving off the tiles goes back to the last one clicked", cs._shown == picked, "%d vs %d" % [cs._shown, picked])
	var k := -1
	for i in cs.characters.size():
		if cs.characters[i]["id"] == "argyle_sock":
			k = i
	cs._show(k)
	await get_tree().process_frame
	_check("the Sock's weapon shows its forge cost: 5 shard crystals", cs._forge_style == "static" and cs._shard_row.get_child_count() == 5, "%s %d" % [cs._forge_style, cs._shard_row.get_child_count()])
	var lit := 0
	for ic in cs._shard_row.get_children():
		if ic is ShardIcon and ic.modulate.v > 0.9:
			lit += 1
	_check("none lit with no shards", lit == 0, "%d" % lit)
	Wallet.shards["dark"] = 2
	cs._refresh_forge()
	await get_tree().process_frame
	lit = 0
	var dark_lit := 0
	for ic in cs._shard_row.get_children():
		if ic is ShardIcon and ic.modulate.v > 0.9:
			lit += 1
			if ic.kind == "dark":
				dark_lit += 1
	_check("they light up one by one as you collect them", lit == 2 and dark_lit == 2, "%d lit" % lit)
	await get_tree().process_frame
	_check("not ready yet: no pulse, no plus signs", not cs._pluses.active, "")
	Wallet.shards["lightning"] = 3
	cs._refresh_forge()
	var grew := 0.0
	for f in 40:
		await get_tree().process_frame
		grew = maxf(grew, cs._weapon_icon.scale.x)
	_check("all collected: the weapon pulses under green plus signs", cs._pluses.active and grew > 1.03 and cs._pluses._plus.size() > 0, "x%.2f, %d pluses" % [grew, cs._pluses._plus.size()])
	cs.open_forge()
	await get_tree().process_frame
	var fm: ForgeMenu = cs._forge_menu
	_check("clicking it opens the forge with a Forge Weapon button", fm != null and not fm._btn.disabled and fm._btn.text == "Forge Weapon", "")
	_check("the forge shows what it will do", fm._next.text.contains("Damage +25%") and fm._next.text.contains("Attack rate +8%"), fm._next.text)
	_check("forging works", fm.do_forge() and Forge.level_of("static") == 1 and Wallet.shards["dark"] == 0 and Wallet.shards["lightning"] == 0, str(Wallet.shards))
	_check("...and the button greys out for level 2", fm._btn.disabled, "")
	fm.closed.emit()
	await get_tree().process_frame
	_check("back on the character select: Forged +1, the level-2 cost (4 dark crystals, lightning x6)", cs._forge_label.text == "Forged +1"
		and cs._shard_row.get_child_count() == 6, "%s %d" % [cs._forge_label.text, cs._shard_row.get_child_count()])
	# Fire Wizard: 5 fire
	cs._show(0)
	await get_tree().process_frame
	var fire_ok: bool = cs._forge_style == "fire" and cs._shard_row.get_child_count() == 5
	for ic in cs._shard_row.get_children():
		fire_ok = fire_ok and ic is ShardIcon and ic.kind == "fire"
	_check("the Fire Wizard needs 5 fire shards", fire_ok, "")


func _test_run() -> void:
	Wallet.forge = {"fire": 2}
	Settings.selected_character = "fire_wizard"
	Settings.selected_map = "swamp"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	var main = get_tree().current_scene
	main.player.god_mode = true
	for f in 60 * 5:
		await get_tree().physics_frame
		if not main.intro:
			break
	main.xp_next = 1e12
	_check("forged +2: Fireballs deal +50% damage", is_equal_approx(main.stats.value("orb_damage"), 12.0 * 1.5), "%.1f" % main.stats.value("orb_damage"))
	_check("...and fire 16% faster", is_equal_approx(main.stats.value("orb_cooldown"), 0.9 / 1.16), "%.3f" % main.stats.value("orb_cooldown"))
	# every 5th Fireball hit explodes like a level 1 Blast Bomb
	var ws: WeaponSystem = main.weapons
	var em: EnemyManager = main.enemies
	ws.orb_t = 999.0
	for i in em.count:
		em.dead[i] = 1
	em._dead_count = em.count
	em.count = 0
	var p: Vector3 = main.player.global_position
	var target := em.spawn(EnemyManager.GRUNT, p + Vector3(5, 0, 0), 100000.0)
	var bystander := em.spawn(EnemyManager.GRUNT, p + Vector3(6.5, 0, 0.5), 100000.0)
	var kind := WeaponSystem.P_KINDS.find("fire")
	var h0: float = em.hp[bystander]
	for k in 5:
		var at: Vector3 = em.center_of(target)
		ws.spawn_projectile(at + Vector3(-1.5, 0, 0), Vector3(15, 0, 0), 0.3, 1.0, 0, kind)
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(0.3).timeout
	_check("forged Fireballs: every 5th hit explodes", ws.fire_hits >= 5 and h0 - em.hp[bystander] > 20.0, "%d hits, bystander -%.0f" % [ws.fire_hits, h0 - em.hp[bystander]])
	# Legendary card: another character's run uses the forged weapon
	Wallet.forge = {"fire": 4}
	Settings.selected_character = "ice_wizard"
	Wallet.unlocked_chars = ["ice_wizard"]
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	main = get_tree().current_scene
	_check("the Fireballs Legendary card is forged too (+100%, +1 shot)", main.db.defs.has("sig_fire")
		and is_equal_approx(main.stats.value("sig_fire_damage"), WeaponSystem.SIG_BASE["damage"] * 2.0)
		and is_equal_approx(main.stats.value("sig_fire_count"), WeaponSystem.SIG_BASE["count"] + 1.0), "%.1f / %.0f" % [main.stats.value("sig_fire_damage"), main.stats.value("sig_fire_count")])


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		fails += 1
