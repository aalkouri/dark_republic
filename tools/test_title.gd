extends Node
## Title-screen checks: splash leads to the title; the title shows the menu (Play / Settings /
## Quit) with Play focused, the wizard diorama and lurking goblins, plays looping music on the
## Music bus; Settings opens and closes; Play starts the game; Main menu returns to the title.
##   godot --headless --path . res://tools/test_title.tscn

var fails := 0


func _ready() -> void:
	var splash_src: String = load("res://scripts/splash.gd").source_code
	_check("splash leads to the title", "res://scenes/title.tscn" in splash_src, "")

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
	_check("menu: Play / Characters / Settings / Quit", labels == ["PLAY", "CHARACTERS", "SETTINGS", "QUIT"], str(labels))
	_check("Play has keyboard/gamepad focus", (title._menu.get_child(0) as Button).has_focus(), "")
	_check("title text", title._title.text == "DARK REPUBLIC", title._title.text)
	_check("wizard on the dais", title.find_children("*", "HeroModel", true, false).size() == 1, "")
	_check("goblins lurk around him", title._goblins.size() == title.GOBLINS, "%d" % title._goblins.size())
	var m: AudioStreamPlayer = title._music
	_check("title music plays on the Music bus, looping", m.playing and m.bus == Settings.MUSIC_BUS and m.stream.get("loop") == true, m.bus)
	_check("title plays Menu of Shadows", m == MenuMusic.player and MenuMusic.TRACK.ends_with("menu_of_shadows.mp3"), "")

	(title._menu.get_child(2) as Button).pressed.emit()
	await get_tree().process_frame
	_check("Settings opens", title._settings.visible and not title._menu.visible, "")
	title._settings.close()
	await get_tree().process_frame
	_check("Settings closes back to the menu", not title._settings.visible and title._menu.visible, "")

	(title._menu.get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	_check("Play asks which map", title._picker != null and title._picker.visible and not title._menu.visible, "")
	var cards: Array = title._picker._cards
	_check("map cards: Swamp, then the Forest and Castle locked until Thog is beaten", cards.size() == 3 and cards[0].get_meta("id") == "swamp"
		and cards[1].get_meta("id") == "forest" and cards[2].get_meta("id") == "castle"
		and not cards[0].disabled and cards[1].disabled and cards[2].disabled, "%d" % cards.size())
	title._picker.choose("forest")
	_check("a locked map can't be picked", Settings.selected_map != "forest", Settings.selected_map)
	title._picker.cancelled.emit()
	await get_tree().process_frame
	_check("Esc on the map choice goes back to the menu", title._picker == null and title._menu.visible, "")
	(title._menu.get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	title._picker.choose("dungeon")
	_check("an unknown map can't be picked", Settings.selected_map != "dungeon" and title._picker != null, Settings.selected_map)
	(title._picker._cards[0] as Button).pressed.emit()   # The Swamp
	await get_tree().scene_changed
	await get_tree().process_frame
	var game: Node = get_tree().current_scene
	_check("Play starts the game", game.name == "Main", game.name)
	await get_tree().create_timer(1.0).timeout
	_check("entrance: wizard is a falling meteor, clock and goblins held", game.intro and game.player.meteor_form and game.run_time == 0.0 and game.enemies.count == 0,
		"intro %s form %s t %.2f enemies %d" % [game.intro, game.player.meteor_form, game.run_time, game.enemies.count])
	await get_tree().create_timer(Abilities.METEOR_FALL_TIME).timeout
	_check("entrance: he lands, the run starts and SURVIVE shows", not game.intro and not game.player.meteor_form and game.run_time > 0.0 and game.hud.intro_banner.is_showing(),
		"intro %s t %.2f" % [game.intro, game.run_time])

	await get_tree().create_timer(0.5).timeout
	game.to_title()
	await get_tree().scene_changed
	_check("Main menu returns to the title", get_tree().current_scene.name == "Title", get_tree().current_scene.name)

	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
