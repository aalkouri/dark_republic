extends Node
## Pause menu + settings checks: Esc opens a menu with Settings; Settings has Video, Sound and
## Controls tabs; Sound has separate Music / other-audio volume with mute; values apply to the
## audio buses, persist, and key rebinding works.
##   godot --headless --path . res://tools/test_settings.tscn

var fails := 0


func _ready() -> void:
	var saved_path := ProjectSettings.globalize_path(Settings.PATH)
	DirAccess.remove_absolute(saved_path)   # start from defaults
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for f in 5:
		await get_tree().process_frame

	# Esc -> pause menu with a Settings button
	_press("pause")
	await get_tree().process_frame
	var hud: Hud = main.hud
	var names := []
	for b in hud.pause_root.find_children("*", "Button", true, false):
		names.append((b as Button).text)
	_check("Esc opens the pause menu", main.state == "paused" and hud.pause_root.visible, "state %s" % main.state)
	_check("pause menu has Settings among its options", "Settings" in names and names.size() >= 3, str(names))

	# Settings -> tabs
	for b in hud.pause_root.find_children("*", "Button", true, false):
		if b.text == "Settings":
			b.pressed.emit()
	await get_tree().process_frame
	var menu: SettingsMenu = hud.settings_menu
	var tabs := []
	for c in menu._tabs.get_children():
		tabs.append(String(c.name))
	_check("Settings opens", menu.visible and not hud.pause_root.visible, "")
	_check("tabs are Video, Sound, Controls", tabs == ["Video", "Sound", "Controls"], str(tabs))
	var sound: Node = menu._tabs.get_child(1)
	var sliders := sound.find_children("*", "HSlider", true, false).size()
	var mutes := sound.find_children("*", "CheckBox", true, false)
	_check("Sound tab: two volume sliders, each with a Mute box", sliders == 2 and mutes.size() == 2 and mutes[0].text == "Mute", "%d sliders, %d checkboxes" % [sliders, mutes.size()])

	# Music and other audio are independent buses
	Settings.set_value("music_volume", 0.5)
	Settings.set_value("sfx_volume", 0.25)
	var mi := AudioServer.get_bus_index(Settings.MUSIC_BUS)
	var si := AudioServer.get_bus_index(Settings.SFX_BUS)
	_check("music volume applies to the Music bus only", is_equal_approx(AudioServer.get_bus_volume_db(mi), linear_to_db(0.5)) and is_equal_approx(AudioServer.get_bus_volume_db(si), linear_to_db(0.25)),
		"music %.1f dB, sfx %.1f dB" % [AudioServer.get_bus_volume_db(mi), AudioServer.get_bus_volume_db(si)])
	(mutes[0] as CheckBox).button_pressed = true   # mute music via the UI
	_check("music mute mutes only music", AudioServer.is_bus_mute(mi) and not AudioServer.is_bus_mute(si), "music %s sfx %s" % [AudioServer.is_bus_mute(mi), AudioServer.is_bus_mute(si)])
	(mutes[1] as CheckBox).button_pressed = true
	_check("other-audio mute", AudioServer.is_bus_mute(si), "")
	_check("level music plays on the Music bus", main.music.bus == Settings.MUSIC_BUS, main.music.bus)
	var music_slider := sound.find_children("*", "HSlider", true, false)[0] as HSlider
	music_slider.value = 0.6   # moving a volume bar un-mutes it (and only it)
	_check("moving the music slider unchecks its Mute", not (mutes[0] as CheckBox).button_pressed and not AudioServer.is_bus_mute(mi) and (mutes[1] as CheckBox).button_pressed,
		"music mute %s, sfx mute %s" % [(mutes[0] as CheckBox).button_pressed, (mutes[1] as CheckBox).button_pressed])
	var sfx_slider := sound.find_children("*", "HSlider", true, false)[1] as HSlider
	sfx_slider.value = 0.25
	sfx_slider.value = 0.3
	_check("moving the other-audio slider unchecks its Mute", not (mutes[1] as CheckBox).button_pressed and not AudioServer.is_bus_mute(si), "")
	sfx_slider.value = 0.25
	(mutes[0] as CheckBox).button_pressed = true
	_check("goblin death sounds play on the SFX bus", main.goblin_audio._voices[0].bus == Settings.SFX_BUS, main.goblin_audio._voices[0].bus)

	# Persistence
	var cf := ConfigFile.new()
	cf.load(Settings.PATH)
	_check("settings saved", cf.get_value("sound", "music_muted", false) == true and is_equal_approx(cf.get_value("sound", "sfx_volume", 1.0), 0.25), "")

	# Rebinding
	menu._start_rebind("jump")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.pressed = true
	menu._input(ev)
	var has_e := false
	for e in InputMap.action_get_events("jump"):
		if e is InputEventKey and e.physical_keycode == KEY_E:
			has_e = true
	_check("rebind jump to E", has_e and menu._bind_buttons["jump"].text != "Press a key...", menu._bind_buttons["jump"].text)

	# Esc closes Settings back to the pause menu, Esc again resumes
	_press("pause")
	await get_tree().process_frame
	_check("Esc closes Settings back to the pause menu", not menu.visible and hud.pause_root.visible and main.state == "paused", "")
	_press("pause")
	await get_tree().process_frame
	_check("Esc again resumes", main.state == "playing" and not get_tree().paused, "state %s" % main.state)

	# Hold Alt: pause + cursor + ability tooltips with numbers
	Input.action_press("inspect")
	await get_tree().process_frame
	await get_tree().process_frame
	_check("holding Alt pauses the game", main.state == "inspect" and get_tree().paused and hud.inspect_hint.visible, "state %s" % main.state)
	_check("holding Alt frees the cursor", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mode %d" % Input.mouse_mode)
	main.abilities.level = 10
	var tips := []
	for i in 3:
		hud._on_slot_hover(i, true)
		hud._update_tooltip()
		tips.append(hud.tooltip_text.get_parsed_text())
		_check("tooltip shows for ability %d" % (i + 1), hud.tooltip.visible, "")
		hud._on_slot_hover(i, false)
	_check("Inferno tooltip has its numbers", "5%" in tips[0] and "10 s" in tips[0] and "50%" in tips[0], tips[0].replace("\n", " | "))
	_check("Fire Nova tooltip has damage + reach", "80 damage" in tips[1] and "18 m" in tips[1] and "5 yd" in tips[1], tips[1].replace("\n", " | "))
	_check("Meteor tooltip has damage + burn", "250 damage" in tips[2] and "3%" in tips[2] and "ULTIMATE" in tips[2], tips[2].replace("\n", " | "))
	main.stats.apply("damage", "add", 0.5)
	hud._on_slot_hover(2, true)
	hud._update_tooltip()
	_check("tooltip damage follows the Damage stat", "375 damage" in hud.tooltip_text.get_parsed_text(), "")
	hud._on_slot_hover(2, false)
	hud._update_tooltip()
	_check("tooltip hides when not hovering", not hud.tooltip.visible, "")
	Input.action_release("inspect")
	await get_tree().process_frame
	await get_tree().process_frame
	_check("releasing Alt resumes", main.state == "playing" and not get_tree().paused and not hud.inspect_hint.visible, "state %s" % main.state)

	# All ability slots the same size, names aligned
	var sizes := []
	var label_y := []
	for slot in hud.ability_slots:
		sizes.append((slot as Control).size)
		var lbl: Label = (slot as Control).get_parent().get_child(1)
		label_y.append(lbl.global_position.y)
	_check("ability slots are the same size", sizes[0] == sizes[1] and sizes[1] == sizes[2], str(sizes))
	_check("ability names are aligned", is_equal_approx(label_y[0], label_y[2]) and is_equal_approx(label_y[1], label_y[2]), str(label_y))

	# Potion pop-ups: "+N" by the health bar and above the head; "-Ns" above each ability
	main.player.hp = 50.0
	main.potions._apply(PotionManager.RED)
	var texts := []
	for p in hud._popups:
		texts.append((p[0] as Label).text)
	var heal_pop: Label = hud._popups[hud._popups.size() - 1][0]
	_check("red potion: +10 next to the health bar", "+10" in texts and heal_pop.position.x > hud.hp_bar.position.x + hud.hp_bar.size.x and absf(heal_pop.position.y - hud.hp_bar.position.y) < 30, str(texts))
	var head_txt := []
	for l in main.numbers._labels:
		if l.visible:
			head_txt.append(l.text)
	_check("red potion: red +10 above the wizard", "+10" in head_txt, str(head_txt))
	main.player.hp = main.player.max_hp
	var n_before: int = hud._popups.size()
	main.potions._apply(PotionManager.RED)
	_check("no heal pop-up at full health", hud._popups.size() == n_before, "")
	main.abilities.cooldown = PackedFloat32Array([20.0, 0.0, 100.0])
	n_before = hud._popups.size()
	main.potions._apply(PotionManager.PURPLE)
	var cut_txt := []
	for k in range(n_before, hud._popups.size()):
		cut_txt.append((hud._popups[k][0] as Label).text)
	_check("purple potion: time cut shown above abilities on cooldown", cut_txt == ["-9s", "-36s"], str(cut_txt))
	var slot_r: Rect2 = (hud.ability_slots[2] as Control).get_global_rect()
	var cut_pop: Label = hud._popups[hud._popups.size() - 1][0]
	_check("cut pop-up sits above its ability", cut_pop.position.y < slot_r.position.y and absf(cut_pop.position.x - slot_r.get_center().x) < 40, "")
	for f in 70:
		hud._update_popups(1.0 / 60.0)
	_check("pop-ups fade out within a second", hud._popups.size() == 0, "%d left" % hud._popups.size())

	DirAccess.remove_absolute(saved_path)
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
