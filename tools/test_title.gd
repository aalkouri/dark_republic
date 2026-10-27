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
	_check("wizard on the dais", title.find_children("*", "WizardModel", true, false).size() == 1, "")
	_check("goblins lurk around him", title._goblins.size() == title.GOBLINS, "%d" % title._goblins.size())
	var m: AudioStreamPlayer = title._music
	_check("title music plays on the Music bus, looping", m.playing and m.bus == Settings.MUSIC_BUS and m.stream.get("loop") == true, m.bus)

	(title._menu.get_child(2) as Button).pressed.emit()
	await get_tree().process_frame
	_check("Settings opens", title._settings.visible and not title._menu.visible, "")
	title._settings.close()
	await get_tree().process_frame
	_check("Settings closes back to the menu", not title._settings.visible and title._menu.visible, "")

	(title._menu.get_child(0) as Button).pressed.emit()
	await get_tree().scene_changed
	await get_tree().process_frame
	var game: Node = get_tree().current_scene
	_check("Play starts the game", game.name == "Main", game.name)

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
