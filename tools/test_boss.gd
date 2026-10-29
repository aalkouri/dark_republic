extends Node
## Thog the Troll, the Swamp boss: arrives at 8:00 (the Warlord no longer comes), is drawn as a
## giant (not a goblin), slams / sweeps / bellows with telegraphs, enrages after 2 minutes
## (attacks twice as fast), must be killed to win, and unlocks the Forest, the Castle and Thog.
##   godot --headless --path . res://tools/test_boss.tscn

var fails := 0
var main: Node


func _ready() -> void:
	Wallet.persist = false
	Wallet.bosses_defeated = []
	_check("before Thog: the Forest and Castle are locked", MapPicker.lock_reason("forest", "fire_wizard") != "" and MapPicker.lock_reason("castle", "fire_wizard") != "",
		MapPicker.lock_reason("forest", "fire_wizard"))
	_check("the Swamp is always open", MapPicker.lock_reason("swamp", "fire_wizard") == "", "")
	_check("Thog can't fight in the Swamp", MapPicker.lock_reason("swamp", "thog") != "", MapPicker.lock_reason("swamp", "thog"))

	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	Settings.selected_map = "swamp"
	Settings.selected_character = "fire_wizard"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	for f in 60 * 6:   # the entrance meteor
		await get_tree().physics_frame
		if not main.intro:
			break
	var player: Player = main.player
	player.god_mode = true
	var em: EnemyManager = main.enemies
	_check("the Swamp is a boss map", main.boss_map, "")

	# The Goblin Warlord no longer comes at 5:00 on the Swamp; Thog comes at 8:00
	main.run_time = main.BOSS_TIME + 0.5
	await _secs(0.2)
	_check("no Goblin Warlord on the Swamp", _count_type(em, EnemyManager.BOSS) == 0, "")
	_check("no Thog before 8:00", main.thog == null, "")
	main.run_time = main.THOG_TIME + 0.1
	await _secs(0.2)
	var thog: ThogBoss = main.thog
	_check("Thog arrives at 8:00", thog != null and thog.row() >= 0 and em.typ[thog.row()] == EnemyManager.TROLL, "")
	if thog == null:
		_finish()
		return
	var i := thog.row()
	_check("Thog is gigantic (about 10 m)", thog.model.scale.x * ThogModel.MODEL_HEIGHT >= 9.0, "%.1f m" % (thog.model.scale.x * ThogModel.MODEL_HEIGHT))
	_check("he has a lot of health (x the 8:00 multiplier)", em.hp_max[i] >= EnemyManager.THOG_HP * 5.0, str(em.hp_max[i]))
	var b := i * EnemyManager.STRIDE
	_check("he isn't drawn as a goblin", em.buf[b] == 0.0 and em.buf[b + 5] == 0.0, "")
	_check("he has a HUD health bar", thog._bar != null and thog._bar.value > 0.99, "")

	# He doesn't win you the run at 10:00 while he's alive
	main.run_time = main.RUN_LENGTH + 1.0
	await _secs(0.2)
	_check("10:00 isn't a win while Thog lives", main.state == "playing", main.state)

	# Melee: stand in front of him and wait for slams and sweeps
	player.bot = true
	player.bot_move = Vector2.ZERO
	var c0 := thog.counts.duplicate()
	var tele_seen := false
	for f in 60 * 14:
		_stand_near(thog, 8.0)
		await get_tree().physics_frame
		if thog._tele != null:
			tele_seen = true
	_check("he slams and sweeps when you're close", thog.counts["slam"] > c0["slam"] and thog.counts["sweep"] > c0["sweep"],
		"slam %d sweep %d" % [thog.counts["slam"] - c0["slam"], thog.counts["sweep"] - c0["sweep"]])
	_check("his attacks are telegraphed on the ground", tele_seen, "")
	_check("his attacks hit you", thog.counts["hits"] > c0["hits"], str(thog.counts["hits"] - c0["hits"]))

	# Bellow: from range he roars and calls goblins
	thog._bellow_cd = 0.0
	var before := em.alive_count()
	var bel: int = thog.counts["bellow"]
	for f in 60 * 9:
		_stand_near(thog, 24.0)
		await get_tree().physics_frame
		if thog.counts["bellow"] > bel and thog._landed:
			break
	_check("he bellows from range and calls goblins", thog.counts["bellow"] > bel and em.alive_count() >= before + ThogBoss.BELLOW_GOBLINS - 2,
		"%d -> %d, bellows %d, state %s %s landed %s" % [before, em.alive_count(), thog.counts["bellow"] - bel, thog.state, thog.attack, thog._landed])

	# Enrage after 2 minutes: attacks twice as fast
	await _wait_idle(thog)
	thog._start("slam")
	var calm_windup := thog._windup
	await _wait_idle(thog)
	thog.alive_time = ThogBoss.ENRAGE_AFTER - 0.05
	await _secs(0.2)
	_check("he enrages 2 minutes after arriving", thog.is_enraged, "")
	await _wait_idle(thog)
	thog._start("slam")
	_check("enraged: attacks come twice as fast", absf(thog._windup - calm_windup * 0.5) < 0.05, "%.2f vs %.2f" % [thog._windup, calm_windup])

	# Frozen solid: no new attacks
	await _wait_idle(thog)
	em.freeze(thog.row(), 3.0)
	var n0: int = thog.counts["slam"] + thog.counts["sweep"]
	for f in 50:
		_stand_near(thog, 8.0)
		await get_tree().physics_frame
	_check("frozen, he can't start an attack", thog.counts["slam"] + thog.counts["sweep"] == n0, "")

	# Burns and other "% of max HP" effects barely scratch him
	var r := thog.row()
	em.hp[r] = em.hp_max[r]
	em.burn_t[r] = 3.0
	var hp0: float = em.hp[r]
	await _secs(1.0)
	r = thog.row()
	_check("burning takes under 1% of his health a second", (hp0 - em.hp[r]) / em.hp_max[r] < 0.01, "%.2f%%" % ((hp0 - em.hp[r]) / em.hp_max[r] * 100.0))

	# Kill him: he falls, the run is won, and the maps and Thog unlock
	var dead := [false]
	thog.defeated.connect(func(): dead[0] = true)
	em.damage(thog.row(), 1.0e9)
	await _secs(0.3)
	_check("he falls when killed", dead[0] and thog.state == "dying", thog.state)
	_check("beating him is remembered", Wallet.has_defeated("thog"), "")
	_check("the Forest and Castle unlock", MapPicker.lock_reason("forest", "fire_wizard") == "" and MapPicker.lock_reason("castle", "fire_wizard") == "", "")
	for f in 60 * 6:
		await get_tree().physics_frame
		if main.state == "won":
			break
	_check("killing Thog wins the run", main.state == "won" and main.boss_won and main.first_boss_kill, main.state)
	var hud: Hud = main.hud
	var names := []
	for c in hud.unlock_cards:
		names.append((c.find_children("*", "Label", true, false)[1] as Label).text)
	_check("the end screen says so", hud.end_title.text == "THOG DEFEATED!", hud.end_title.text)
	_check("it lists what was unlocked: 2 maps and Thog", hud.end_unlocks.visible and hud.unlock_cards.size() == 3
		and "MAGICAL FOREST" in names and "THE CASTLE" in names and "THOG THE TROLL" in names, str(names))
	var start_far: bool = hud.unlock_cards[2].modulate.a < 0.05
	await get_tree().create_timer(4.0, true).timeout
	var landed := true
	for k in hud.unlock_cards.size():
		var c: Control = hud.unlock_cards[k]
		if c.global_position.distance_to(hud._unlock_slots[k].global_position) > 2.0 or absf(c.rotation) > 0.01 or c.modulate.a < 0.99:
			landed = false
	_check("the unlocks swirl in from off screen and land in their slots", start_far and landed, "")
	_finish()


func _finish() -> void:
	get_tree().paused = false
	Settings.selected_map = "swamp"
	Wallet.bosses_defeated = []
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _stand_near(thog: ThogBoss, d: float) -> void:
	var i := thog.row()
	if i < 0:
		return
	var p: Vector3 = main.enemies.pos[i]
	var dir := Vector3(-sin(thog._yaw), 0, -cos(thog._yaw))
	var at := p + dir * d
	main.player.global_position = Vector3(at.x, SwampWater.height_at(at.x, at.z) + 0.1, at.z)
	main.player.velocity = Vector3.ZERO


func _wait_idle(thog: ThogBoss) -> void:
	for f in 60 * 5:
		if thog.state != "attack":
			return
		await get_tree().physics_frame


func _secs(s: float) -> void:
	for f in int(s * 60):
		await get_tree().physics_frame


func _count_type(em: EnemyManager, t: int) -> int:
	var n := 0
	for k in em.count:
		if em.typ[k] == t and not em.dead[k]:
			n += 1
	return n


func _check(what: String, ok: bool, detail: String) -> void:
	print("  %s %s%s" % ["ok  " if ok else "FAIL", what, ("  (" + detail + ")") if detail != "" else ""])
	if not ok:
		fails += 1
