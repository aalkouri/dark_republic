extends Node
## Title-screen checks: splash leads to the title; the title shows the menu (Play / Settings /
## Quit) with Play focused, the wizard diorama and lurking goblins, plays looping music on the
## Music bus; Settings opens and closes; Play > Classic leads to character select and the game;
## Main menu returns to the title.
##   godot --headless --path . res://tools/test_title.tscn

var fails := 0


func _ready() -> void:
	var splash_src: String = load("res://scripts/splash.gd").source_code
	_check("splash leads to the intro, then the title", "res://scenes/intro.tscn" in splash_src and "res://scenes/title.tscn" in splash_src, "")

	# Survive scene changes: hand "current scene" to a throwaway node
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	get_tree().change_scene_to_file.call_deferred("res://scenes/title.tscn")
	await get_tree().scene_changed
	for f in 5:
		await get_tree().process_frame
	var title: Node = get_tree().current_scene
	var labels := []
	for b in title._menu.get_children():
		labels.append((b as Button).text.strip_edges())
	_check("menu: Play / Unlocks / Settings / Stats / Quit (no separate Characters)", labels == ["PLAY", "UNLOCKS", "SETTINGS", "STATS", "QUIT"], str(labels))
	_check("Play has keyboard/gamepad focus", (title._menu.get_child(0) as Button).has_focus(), "")
	_check("title text", title._title.text == "DARK REPUBLIC", title._title.text)
	var puns: Array = title.load_taglines()
	var unique := {}
	for p in puns:
		unique[p] = true
	var dice := puns.filter(func(t): return (t as String).to_lower().contains("dice") or (t as String).to_lower().contains("roll") or (t as String).contains("20") or (t as String).to_lower().contains("polyhedral"))
	_check("44 different D&D puns for the tagline, none about dice", puns.size() == 44 and unique.size() == 44 and dice.is_empty() and puns.has(title._tagline.text), str(dice))
	var first: String = title._tagline.text
	title._update_tagline(title.TAGLINE_TIME + 0.01)
	_check("the tagline rotates to another pun", title._tagline.text != first and puns.has(title._tagline.text), title._tagline.text)
	_check("wizard on the dais", title.find_children("*", "HeroModel", true, false).size() == 1, "")
	_check("goblins lurk around him", title._goblins.size() == title.GOBLINS, "%d" % title._goblins.size())
	var m: AudioStreamPlayer = title._music
	_check("title music plays on the Music bus, looping", m.playing and m.bus == Settings.MUSIC_BUS and m.stream.get("loop") == true, m.bus)
	_check("title plays Menu of Shadows", m == MenuMusic.player and MenuMusic.TRACK.ends_with("menu_of_shadows.mp3"), "")

	await _test_unlocks(title)
	(title._menu.get_child(2) as Button).pressed.emit()
	await get_tree().process_frame
	_check("Settings opens", title._settings.visible and not title._menu.visible, "")
	title._settings.close()
	await get_tree().process_frame
	_check("Settings closes back to the menu", not title._settings.visible and title._menu.visible, "")

	(title._menu.get_child(0) as Button).pressed.emit()
	await get_tree().create_timer(0.8).timeout
	_check("Play opens the mode cards", title._modes.is_open(), "")
	title._modes.cards[0].pressed.emit()   # Classic
	await get_tree().scene_changed
	for f in 5:
		await get_tree().process_frame
	var cs: Node = get_tree().current_scene
	_check("Play goes to character select", cs.name == "CharacterSelect", cs.name)
	cs._play()
	await get_tree().process_frame
	_check("its Play asks which map", cs._picker != null and cs._picker.visible, "")
	var cards: Array = cs._picker._cards
	_check("map cards: Swamp, then the Forest, Castle (and the later maps) locked until their bosses are beaten", cards.size() == MapPicker.MAPS.size() and cards.size() >= 3 and cards[0].get_meta("id") == "swamp"
		and cards[1].get_meta("id") == "forest" and cards[2].get_meta("id") == "castle"
		and not cards[0].disabled and cards.slice(1).all(func(c): return c.disabled), "%d" % cards.size())
	cs._picker.choose("forest")
	_check("a locked map can't be picked", Settings.selected_map != "forest", Settings.selected_map)
	var lk: Array = cards.filter(func(c): return c.has_meta("lock"))
	_check("locked maps show a padlock", lk.size() == cards.size() - 1, str(lk.size()))
	# Thog and the Toadstool Knight beaten: the next time the picker opens, the padlocks spring
	# open and fall away
	cs._picker.cancelled.emit()
	await get_tree().process_frame
	var was_persist := Wallet.persist
	Wallet.persist = false
	Wallet.bosses_defeated = ["thog", "toadstool_knight"]
	Wallet.seen_unlocks = []
	cs._play()
	await get_tree().process_frame
	var pk: MapPicker = cs._picker
	_check("newly unlocked maps start locked for their reveal", pk.revealing and pk._cards[1].disabled and pk._cards[1].has_meta("lock"), "")
	var lock1: Control = pk._cards[1].get_meta("lock")
	var fell_off := [false]
	var t_end := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		if is_instance_valid(lock1) and lock1.global_position.y > get_viewport().get_visible_rect().size.y:
			fell_off[0] = true
	_check("their padlocks fall off the bottom of the screen", fell_off[0] and not is_instance_valid(lock1), "")
	_check("then the Forest and Castle are selectable", not pk.revealing and not pk._cards[1].disabled and not pk._cards[2].disabled, "")
	_check("the reveal is remembered", Wallet.unlock_seen("map:forest") and Wallet.unlock_seen("map:castle"), "")
	pk.cancelled.emit()
	await get_tree().process_frame
	cs._play()
	await get_tree().process_frame
	_check("next time: open straight away, no padlocks", not cs._picker.revealing and not cs._picker._cards[1].disabled and not cs._picker._cards[1].has_meta("lock"), "")
	cs._picker.cancelled.emit()
	await get_tree().process_frame
	Wallet.bosses_defeated = []
	Wallet.seen_unlocks = []
	Wallet.persist = was_persist
	cs._play()
	await get_tree().process_frame
	cs._picker.cancelled.emit()
	await get_tree().process_frame
	_check("Esc on the map choice goes back to character select", cs._picker == null and get_tree().current_scene == cs, "")
	cs._play()
	await get_tree().process_frame
	cs._picker.choose("dungeon")
	_check("an unknown map can't be picked", Settings.selected_map != "dungeon" and cs._picker != null, Settings.selected_map)
	(cs._picker._cards[0] as Button).pressed.emit()   # The Swamp
	await get_tree().scene_changed
	await get_tree().process_frame
	var game: Node = get_tree().current_scene
	_check("Play starts the game", game.name == "Main", game.name)
	await get_tree().create_timer(1.0).timeout
	_check("entrance: wizard is a falling meteor, clock and goblins held", game.intro and game.player.meteor_form and game.run_time == 0.0 and game.enemies.count == 0,
		"intro %s form %s t %.2f enemies %d" % [game.intro, game.player.meteor_form, game.run_time, game.enemies.count])
	for f in 60 * 4:   # every character's entrance is over within 3.5 s
		await get_tree().physics_frame
		if not game.intro:
			break
	await get_tree().create_timer(0.1).timeout
	_check("entrance: he lands, the run starts and SURVIVE shows", not game.intro and not game.player.meteor_form and game.run_time > 0.0 and game.hud.intro_banner.is_showing(),
		"intro %s t %.2f" % [game.intro, game.run_time])

	await get_tree().create_timer(0.5).timeout
	game.to_title()
	await get_tree().scene_changed
	_check("Main menu returns to the title", get_tree().current_scene.name == "Title", get_tree().current_scene.name)

	# The title's dais shows the character you played last
	Settings.last_played = "thunder_wizard"
	get_tree().change_scene_to_file.call_deferred("res://scenes/title.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	var t2 = get_tree().current_scene
	_check("the title shows the character you played last", t2.hero is RosterHero and (t2.hero as RosterHero).char_id == "thunder_wizard", str(t2.hero))
	Settings.last_played = "fire_wizard"

	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


## Unlocks: buying levels with coins, the catalogue tabs and the "new" dots.
func _test_unlocks(title: Node) -> void:
	var keep_persist := Wallet.persist
	var keep_coins := Wallet.coins
	Wallet.persist = false
	Wallet.unlock_levels = {}
	Wallet.discovered = []
	Wallet.new_marks = []
	Wallet.discover("tome:tome_damage")   # found in a run
	title._unlocks_dot.visible = UnlocksMenu.any_new()
	_check("the Unlocks button shows a dot when something new was found", title._unlocks_dot.visible, "")
	(title._menu.get_child(1) as Button).pressed.emit()
	await get_tree().process_frame
	var um: UnlocksMenu = title._unlocks
	_check("Unlocks opens on the Upgrades tab: Map, Free Ban, Reroll", um.visible and not title._menu.visible and um._squares.size() == 3, "%d" % um._squares.size())
	Wallet.coins = 600
	_check("Map costs 750: can't buy it with 600", not um.buy("map") and Wallet.unlock_level("map") == 0, "")
	_check("Free Ban level 1 for 500", um.buy("free_ban") and Wallet.unlock_level("free_ban") == 1 and Wallet.coins == 100, "%d coins" % Wallet.coins)
	Wallet.coins = 100000
	for k in 6:
		um.buy("reroll")
	_check("Reroll stops at level 5 (500, 1000, 2000, 5000, 10000)", Wallet.unlock_level("reroll") == 5 and Wallet.coins == 100000 - 18500, "%d, %d coins" % [Wallet.unlock_level("reroll"), Wallet.coins])
	_check("the Tomes tab has a dot (a tome found in play)", um.tab_has_new("tome") and not um.tab_has_new("weapon"), "")
	um.show_tab("tome")
	await get_tree().process_frame
	var sq: Dictionary = um._squares.filter(func(q): return q["key"] == "tome:tome_damage")[0]
	_check("...and so does the tome's square; the others are still '?'", (sq["dot"] as Control).visible and um._squares.size() >= 10, "")
	var c0 := Wallet.coins
	um._hover(sq, true)
	_check("hovering a new tome pays 150 coins", Wallet.coins == c0 + Unlocks.DISCOVERY_REWARD, "%d -> %d" % [c0, Wallet.coins])
	um._hover(sq, false)
	um._hover(sq, true)
	_check("...only once", Wallet.coins == c0 + Unlocks.DISCOVERY_REWARD, "%d" % Wallet.coins)
	_check("hovering it clears both dots and explains it", not Wallet.is_new("tome:tome_damage") and not um.tab_has_new("tome") and um._tip.visible and "Damage" in um._tip_text.text, um._tip_text.text)
	um._hover(sq, false)
	um.show_tab("map")
	await get_tree().process_frame
	_check("Maps tab: one square per map", um._squares.size() == MapPicker.MAPS.size(), "")
	um.close()
	await get_tree().process_frame
	_check("Back closes it", not um.visible and title._menu.visible, "")
	Wallet.unlock_levels = {}
	Wallet.coins = keep_coins
	Wallet.persist = keep_persist


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
