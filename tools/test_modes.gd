extends Node
## Run clock + game modes: the clock spins up 00:00 -> 10:00 during the entrance (with digital
## blips) and then counts down; the title's Play opens three mode cards; Quickplay picks a
## playable character and an open map; Unrelenting counts up, never ends at 10:00, removes
## upgrade caps, ramps enemy damage up and XP down past 10:00, and 15:00 in the Swamp earns
## the feat Ghast needs.
##   godot --headless --path . res://tools/test_modes.tscn

var fails := 0


func _ready() -> void:
	var progress := ProjectSettings.globalize_path(Wallet.PATH)
	var backup := FileAccess.get_file_as_bytes(Wallet.PATH) if FileAccess.file_exists(Wallet.PATH) else PackedByteArray()

	# ---- Classic: clock spin-up then countdown
	Settings.game_mode = "classic"
	Settings.selected_map = "swamp"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for f in 3:
		await get_tree().process_frame
	var hud: Hud = main.hud
	_check("classic run starts with the entrance and the clock spin-up", main.intro and hud._spin_t >= 0.0, "intro %s spin %.2f" % [main.intro, hud._spin_t])
	hud._spin_t = 0.0
	var seen := []
	var t := 0.0
	while t < 2.6:
		seen.append(hud._clock_text(0.1))
		t += 0.1
	var rising := true
	for k in range(1, seen.size()):
		rising = rising and seen[k] >= seen[k - 1]
	_check("clock spins up from 00:00 to 10:00", seen[0] == "00:00" and seen[-1] == "10:00" and rising and "05:00" < seen[12], str(seen))
	_check("digital blips play while it spins", hud._ui_players.has("timer_tick") and hud._ui_players["timer_tick"].stream != null, "")
	_check("a lock-in beep when it reaches 10:00", hud._ui_players.has("timer_set") and hud._ui_players["timer_set"].stream != null, "")
	main.intro = false
	hud._clock_text(0.016)
	main.run_time = 75.2
	_check("then it counts down", hud._clock_text(0.016) == "08:45", hud._clock_text(0.016))
	main.run_time = 700.0
	_check("never below 00:00", hud._clock_text(0.016) == "00:00", "")
	main.queue_free()
	await get_tree().process_frame

	# ---- Unrelenting
	Settings.game_mode = "unrelenting"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for f in 3:
		await get_tree().process_frame
	hud = main.hud
	_check("unrelenting: no spin-up, the clock counts up", main.endless and hud._spin_t < 0.0 and hud._clock_text(0.016) == "00:00", "")
	_check("unrelenting: upgrades have no level cap", main.db.uncapped, "")
	main.db.levels["tome_damage"] = 99
	_check("...a maxed upgrade is still offered", "tome_damage" in main.db._eligible(4), "")
	main.intro = false
	main.player.god_mode = true
	main.run_time = 605.0
	main._physics_process(0.016)
	_check("unrelenting: 10:00 doesn't end the run", main.state == "playing", main.state)
	_check("...clock keeps counting up", hud._clock_text(0.016) == "10:05", hud._clock_text(0.016))
	main.run_time = 1200.0
	_check("enemies hit harder the longer it goes", main.enemy_damage_mult() > 2.0, "%.2f" % main.enemy_damage_mult())
	_check("...and drop less XP", main.xp_drop_mult() < 0.65, "%.2f" % main.xp_drop_mult())
	_check("...and keep spawning (spawn rate still climbing)", main.hp_mult() > 10.0, "")
	Wallet.feats.erase(main.GHAST_FEAT)
	main.run_time = 901.0
	main._physics_process(0.016)
	_check("15:00 in the Swamp on Unrelenting earns Ghast's feat", Wallet.has_feat(main.GHAST_FEAT), str(Wallet.feats))
	main.queue_free()
	await get_tree().process_frame

	# ---- Ghast needs the feat
	var cs: Node = load("res://scenes/character_select.tscn").instantiate()
	Settings.game_mode = "unrelenting"
	add_child(cs)
	await get_tree().process_frame
	var reqs: Array = cs.requirements(cs.index_of("ghast"))
	var texts := []
	for r in reqs:
		texts.append(r["text"])
	_check("Ghast's unlock requirements include 15:00 on Unrelenting", "Survive 15:00 in the Swamp on Unrelenting" in texts and reqs[-1]["met"], str(texts))
	Wallet.feats.erase("unrelenting_swamp_15")
	reqs = cs.requirements(cs.index_of("ghast"))
	_check("...and it blocks the unlock until earned", not reqs[-1]["met"] and not cs.can_unlock(cs.index_of("ghast")), "")
	_check("character select shows the Unrelenting tag", cs.find_children("*", "Label", true, false).any(func(l): return l.text == "UNRELENTING"), "")
	# Weapon corner: icon + name; hovering it shows damage and what it does
	cs._show(cs.index_of("vicki"))
	cs._on_slot_hover(cs.WEAPON_HOVER, true)
	var tip: String = cs._tooltip_text.get_parsed_text()
	_check("weapon hover: name, damage, rate and description", cs._tooltip.visible and "Valkyrie Spear" in tip and "Damage: 30" in tip and "0.7 s" in tip and "javelin" in tip, tip.replace("\n", " | "))
	cs._on_slot_hover(cs.WEAPON_HOVER, false)
	_check("weapon corner has no description text; ability names are hidden", not cs._weapon_short.visible and cs._ability_names.all(func(l): return not l.visible), "")
	cs.queue_free()

	# ---- Title: Play opens the mode cards; Quickplay's pick
	var title: Node = load("res://scenes/title.tscn").instantiate()
	add_child(title)
	for f in 3:
		await get_tree().process_frame
	title._play()
	await get_tree().create_timer(0.9).timeout
	var modes: ModeMenu = title._modes
	var names := []
	for b in modes.cards:
		names.append(b.get_meta("mode"))
	_check("Play reveals Classic / Quickplay / Unrelenting cards", modes.is_open() and modes.visible and names == ["classic", "quickplay", "unrelenting"], str(names))
	_check("cards are on screen and clickable after the reveal", modes.cards.all(func(b): return not b.disabled and b.get_global_rect().end.x < 1600 and b.scale.is_equal_approx(Vector2.ONE) or b.has_focus()), "")
	modes.close()
	await get_tree().create_timer(0.3).timeout
	_check("Esc / back folds them away and gives Play its focus back", not modes.is_open() and not modes.visible and (title._menu.get_child(0) as Button).has_focus(), "")
	var pick: Dictionary = title.quickplay_pick(7)
	_check("Quickplay picks a playable character and an open map", pick["character"] != "" and MapPicker.lock_reason(pick["map"], pick["character"]) == "", str(pick))
	title.queue_free()

	if backup.is_empty():
		DirAccess.remove_absolute(progress)
	else:
		var f := FileAccess.open(Wallet.PATH, FileAccess.WRITE)
		f.store_buffer(backup)
	Settings.game_mode = "classic"
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
