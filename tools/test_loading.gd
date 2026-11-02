extends Node
## Loading screen checks (scripts/loader.gd, autoload "Loader"): it's registered as an autoload;
## data/tips.json has 25+ non-empty, distinct tips, all translated into every language; going
## into a run shows the overlay at once with the map's name, picture and a tip, the tips rotate
## after TIP_TIME and a key press skips to the next one, and the overlay fades once the run is
## built; the end screen's Characters button and character select's Back use it too; a quick
## change that isn't known to be slow doesn't flash it; no script changes scene behind its back.
##   godot --headless --path . res://tools/test_loading.tscn

var fails := 0


func _ready() -> void:
	var loader: Node = get_node_or_null("/root/Loader")
	_check("Loader is an autoload", loader != null and loader.get_script().resource_path == "res://scripts/loader.gd", str(loader))
	if loader == null:
		_done()
		return
	_check("it draws above everything (coin counter included)", Loader.layer > Wallet.layer, "%d" % Loader.layer)

	# --- the tips
	var tips: Array = Loader.tips
	var uniq := {}
	for t in tips:
		uniq[t] = true
	_check("25+ tips, none empty, all different", tips.size() >= 25 and uniq.size() == tips.size()
		and tips.all(func(t): return (t as String).strip_edges().length() > 10), "%d tips" % tips.size())
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/tips.json"))
	_check("they come from data/tips.json (an array of strings)", raw is Array and (raw as Array).size() == tips.size(), "")
	for loc in ["es", "fr", "ar", "de", "zh_CN", "ja"]:
		TranslationServer.set_locale(loc)
		var untranslated := tips.filter(func(t): return TranslationServer.translate(t) == t)
		_check("every tip is translated (%s)" % loc, untranslated.is_empty() and Loader.tr("TIP") != "TIP" and Loader.tr("LOADING") != "LOADING",
			str(untranslated.slice(0, 2)))
	TranslationServer.set_locale("en")
	var seen := {}
	var prev := -1
	var repeats := 0
	for k in tips.size() * 3:
		var i: int = Loader._pick_tip()
		seen[i] = true
		if i == prev:
			repeats += 1
		prev = i
	_check("tips come up in random order, every one of them, never the same twice in a row", seen.size() == tips.size() and repeats == 0, "%d seen, %d repeats" % [seen.size(), repeats])

	# --- every scene change in the game goes through it
	var offenders := []
	for f in DirAccess.get_files_at("res://scripts"):
		if not f.ends_with(".gd") or f == "loader.gd":
			continue
		var lines := FileAccess.get_file_as_string("res://scripts/" + f).split("\n")
		for n in lines.size():
			var l := lines[n]
			if ("change_scene_to" in l or "reload_current_scene" in l) and not "tests go straight in" in l:
				offenders.append("%s:%d" % [f, n + 1])
	_check("no script changes scene except through Loader.go", offenders.is_empty(), str(offenders))

	# Survive scene changes: hand "current scene" to a throwaway node
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in

	# --- into a run: shown straight away, with the map and the character
	Settings.selected_map = "swamp"
	Settings.selected_character = "fire_wizard"
	Settings.game_mode = "classic"
	_check("a run is a known slow transition", Loader.is_slow("res://scenes/main.tscn"), "")
	Loader.hold = true
	Loader.go("res://scenes/main.tscn")
	Loader.go("res://scenes/title.tscn")
	_check("a second go() while busy is ignored", Loader.last_path == "res://scenes/main.tscn", Loader.last_path)
	_check("Loader.go into a run shows the loading screen at once", Loader.showing and Loader._root.visible and Loader.busy, "")
	_check("...with the map's name and the character", Loader._heading_box.visible and Loader._heading.text == "THE SWAMP" and Loader._sub.text == "The Fire Wizard",
		"%s / %s" % [Loader._heading.text, Loader._sub.text])
	_check("...over the map's preview picture", Loader._bg.texture != null, "")
	_check("...and a tip", Loader._tip_label.text != "" and tips.has(Loader._tip_label.text) and Loader._tip_label.text == Loader.current_tip(), Loader._tip_label.text)
	_check("TIP heading, spinner and LOADING", Loader._tip_head.text == "TIP" and Loader._spinner.is_visible_in_tree(), "")
	await get_tree().scene_changed
	var game: Node = get_tree().current_scene
	_check("the run loads behind it", game.name == "Main", game.name)
	for f in 6:
		await get_tree().process_frame
	_check("hold keeps the loading screen up after the run is ready", Loader.showing and Loader._root.modulate.a > 0.99, "")
	var first: String = Loader.current_tip()
	var t0 := Loader._tip_t
	await get_tree().create_timer(Loader.TIP_TIME - t0 - 0.3, true, false, true).timeout
	_check("the tip stays up for a while", Loader.current_tip() == first, "")
	await get_tree().create_timer(0.8, true, false, true).timeout
	_check("tips rotate after %.1f s" % Loader.TIP_TIME, Loader.current_tip() != first and Loader.current_tip() != "", Loader.current_tip())
	await get_tree().create_timer(Loader.TIP_FADE + 0.1, true, false, true).timeout
	_check("...with a crossfade to the new one", Loader._tip_label.text == Loader.current_tip() and Loader._tip_label.modulate.a > 0.99, "")
	var before: String = Loader.current_tip()
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("any key skips to the next tip", Loader.current_tip() != before, "")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_SPACE
	up.pressed = false
	Input.parse_input_event(up)
	Loader.hold = false
	var fin := [false]
	Loader.finished.connect(func(_p): fin[0] = true, CONNECT_ONE_SHOT)
	await _wait_idle(3.0)
	_check("then the loading screen fades out", fin[0] and not Loader.showing and not Loader._root.visible and not Loader.busy, "")
	_check("the run is playing underneath", is_instance_valid(game) and get_tree().current_scene == game and not get_tree().paused, "")

	# --- the end screen's Characters button: back to the roster behind it
	var shown: int = Loader.shown_count
	game.to_character_select()
	await get_tree().process_frame
	_check("leaving a run shows the loading screen", Loader.showing and Loader.shown_count == shown + 1, "")
	_check("...with just the game's name, no map", Loader._heading.text == "DARK REPUBLIC" and not Loader._sub.visible and Loader._bg.texture == null, Loader._heading.text)
	await get_tree().scene_changed
	var cs: Node = get_tree().current_scene
	_check("Characters goes back to character select", cs.name == "CharacterSelect", cs.name)
	await _wait_idle(3.0)
	_check("...and the loading screen is gone", not Loader.showing and not Loader.busy, "")

	# --- character select's Back to the title (builds its swamp diorama): behind it too
	shown = Loader.shown_count
	cs._back()
	var t_end := Time.get_ticks_msec() + 3000
	while not Loader.busy and Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
	_check("Back to the title goes through the loading screen", Loader.busy and Loader.showing and Loader.shown_count == shown + 1, "")
	await get_tree().scene_changed
	_check("...to the title", get_tree().current_scene.name == "Title", get_tree().current_scene.name)
	await _wait_idle(3.0)
	_check("...which then shows", not Loader.showing, "")

	# --- a quick change that isn't known to be slow never flashes the overlay
	var keep := load("res://scenes/character_select.tscn")   # cached: the background load is instant
	shown = Loader.shown_count
	Loader.go("res://scenes/character_select.tscn", false)
	await get_tree().scene_changed
	await _wait_idle(3.0)
	_check("a quick change doesn't flash the loading screen", Loader.shown_count == shown and not Loader.showing, "%d shown, took %.2f s" % [Loader.shown_count - shown, Loader.last_duration])
	keep = null
	_done()


func _wait_idle(limit: float) -> void:
	var t_end := Time.get_ticks_msec() + int(limit * 1000.0)
	while (Loader.busy or Loader.showing) and Time.get_ticks_msec() < t_end:
		await get_tree().process_frame


func _done() -> void:
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
