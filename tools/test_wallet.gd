extends Node
## Coins: reward maths (1/s survived + 100 per 1,000 kills), coins only banked on the end
## screen, the payout animation (coins fly to the counter, pot counts down, jingle plays,
## everything lands), and the counter stays visible on every screen.
##   godot --headless --path . res://tools/test_wallet.tscn

var fails := 0


func _ready() -> void:
	Wallet.persist = false
	Wallet.coins = 0
	Wallet.displayed = 0.0
	Wallet.char_exp = {}
	Settings.selected_character = "fire_wizard"
	var r := Wallet.run_reward(125.7, 2345)
	_check("1 coin per second survived", r["time"] == 125, str(r))
	_check("100 coins per 1,000 kills", r["bonus"] == 200, str(r))
	_check("total", r["total"] == 325, str(r))
	_check("no bonus under 1,000 kills", Wallet.run_reward(10.0, 999)["bonus"] == 0, "")
	_check("thousands separator", Wallet.fmt(1234567) == "1,234,567", Wallet.fmt(1234567))

	# In-game: nothing banked until the run ends
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 5:
		await get_tree().process_frame
	var main: Node = get_tree().current_scene
	_check("counter shown in game", Wallet.panel.visible, "")
	main.run_time = 61.4
	main.kills = 1500
	await get_tree().create_timer(0.3).timeout
	_check("coins not added during the run", Wallet.coins == 0, "%d" % Wallet.coins)
	main._end_run(false)
	_check("end screen lists the coins", "61 coins" in main.hud.end_coin_lines.text and "+100 bonus" in main.hud.end_coin_lines.text, main.hud.end_coin_lines.text)
	_check("pot shows the total before paying", main.hud.end_pot.text == "+161", main.hud.end_pot.text)
	# 1,500 kills + about a minute alive (100 EXP a minute); died, so no win bonus
	var want := Wallet.run_exp(1500, 0, 0, 0, main.run_time, false)
	_check("EXP banked at the end: kills + time alive", Wallet.char_exp_of("fire_wizard") == int(want["total"]) and int(want["time"]) >= 100
		and ("EXP +%s" % Wallet.fmt(int(want["total"]))) in main.hud.end_exp.text and want["win"] == 0, main.hud.end_exp.text)
	_check("...itemised on the end screen", "Kills 1,500" in main.hud.end_exp.text and ("Time +%d" % int(want["time"])) in main.hud.end_exp.text, main.hud.end_exp.text)
	var finished := [false]
	Wallet.payout_finished.connect(func(): finished[0] = true, CONNECT_ONE_SHOT)
	await get_tree().create_timer(1.2, true).timeout
	_check("coins banked when the payout starts", Wallet.coins == 161, "%d" % Wallet.coins)
	_check("coins pour out (flying coins on screen)", Wallet._flying.size() > 0, "%d flying" % Wallet._flying.size())
	_check("jingle plays during the payout", Wallet._jingle.playing, "")
	_check("counter lags behind while coins fly", Wallet.displayed < 161.0, "%.0f" % Wallet.displayed)
	var seen_between := false   # the pot showed an in-between value while counting down
	var t := 0.0
	while not finished[0] and t < 10.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var txt: String = main.hud.end_pot.text
		if txt != "+161" and txt != "+0":
			seen_between = true
	_check("payout finishes", finished[0], "%.1f s" % t)
	_check("every coin lands in the counter", is_equal_approx(Wallet.displayed, 161.0) and Wallet._flying.is_empty(), "%.0f" % Wallet.displayed)
	_check("pot counted down gradually to zero", main.hud.end_pot.text == "+0" and seen_between, main.hud.end_pot.text)
	_check("jingle stops at the end", not Wallet._jingle.playing, "")

	main.to_title()
	await get_tree().scene_changed
	await get_tree().process_frame
	_check("counter shown on the title", Wallet.panel.visible and Wallet.label.text == "161", Wallet.label.text)
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
