extends Node
## Playable roster characters (Ice, Thunder and Dark Wizards): each starts a real run as that
## character and checks the model, entrance, weapon and all three abilities.
##   godot --headless --path . res://tools/test_roster.tscn [-- --only=ice_wizard]

const CHARS := ["ice_wizard", "thunder_wizard", "dark_wizard"]
var fails := 0
var main: Node


func _ready() -> void:
	Wallet.persist = false
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.split("=")[1]
	Engine.time_scale = 3.0   # the abilities last seconds; run them faster
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	for id in CHARS:
		if only != "" and id != only:
			continue
		await _start(id)
		await call("_test_" + id)
	Engine.time_scale = 1.0
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _start(id: String) -> void:
	print("--- ", id)
	Settings.selected_character = id
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	main = get_tree().current_scene
	main.player.god_mode = true
	_check("plays as its own rigged model", main.player.model is RosterHero and (main.player.model as RosterHero).char_id == id, str(main.player.model))
	_check("model holds its staff", (main.player.model as RosterHero).weapon != null, "")
	_check("no ash footprints", not main.player.footprints, "")
	_check("ability bar shows its kit", main.abilities.defs()[0]["name"] == KitDB.ability(id, 0)["name"]
		and (main.hud.ability_slots[2] as AbilitySlot).glyph == KitDB.ability(id, 2)["icon"]["glyph"], str(main.abilities.defs()[0]))
	_check("arrives as a comet in its colours", main.intro and main.player.meteor_form and not main.player.model.visible, "")
	await _secs(Abilities.METEOR_FALL_TIME + 0.4)
	_check("comet lands and the run starts", not main.intro and not main.player.meteor_form and main.player.model.visible, "")
	main.abilities.level = 10
	main.abilities.reset_cooldowns()
	main.xp_next = 1e12   # no level-up cards (they pause the game)


## Clear the field and put `n` goblins in a ring at `r` metres around the player
## (`hp` = HP multiplier on a 10-HP goblin).
func _ring(n: int, r: float, hp := 100000.0) -> Array:
	var e: EnemyManager = main.enemies
	for i in e.count:
		e.dead[i] = 1
	e._dead_count = e.count
	var at: Vector3 = main.player.global_position
	var out := []
	for k in n:
		var a := TAU * k / n
		var i := e.spawn(EnemyManager.GRUNT, at + Vector3(cos(a), 0, sin(a)) * r, hp)
		out.append(e.uid[i])
	await _frames(2)
	return out


func _idx(u: int) -> int:
	var e: EnemyManager = main.enemies
	for i in e.count:
		if e.uid[i] == u and not e.dead[i]:
			return i
	return -1


func _cast(i: int) -> void:
	main.abilities.cooldown[i] = 0.0
	main.cast_ability(i)
	_check("  %s cast and on cooldown" % main.abilities.defs()[i]["name"], main.abilities.cooldown[i] > 0.0, "")


# ------------------------------------------------------------------ Ice

func _test_ice_wizard() -> void:
	var w: WeaponSystem = main.weapons
	_check("weapon: Frost Shards", w.style == "ice" and main.db.defs["weapon_orb"]["name"] == "Frost Shards", w.style)
	var ring := await _ring(6, 6.0)
	await _secs(1.5)
	var slowed := 0
	for u in ring:
		var i := _idx(u)
		if i >= 0 and main.enemies.slow_t[i] > 0.0:
			slowed += 1
	_check("Frost Shards slow what they hit", slowed > 0, "%d slowed" % slowed)

	ring = await _ring(10, 8.0)
	var far: Array = await _extra(4, 20.0)
	_cast(0)
	await _secs(0.6)
	var frozen := 0
	for u in ring:
		var i := _idx(u)
		if i >= 0 and main.enemies.freeze_t[i] > 0.0:
			frozen += 1
	var far_frozen := 0
	for u in far:
		var i := _idx(u)
		if i >= 0 and main.enemies.freeze_t[i] > 0.0:
			far_frozen += 1
	_check("Flash Freeze freezes goblins within 15 m, not beyond", frozen == 10 and far_frozen == 0, "%d near, %d far" % [frozen, far_frozen])
	var i0 := _idx(ring[0])
	var before: float = main.enemies.hp[i0]
	main.enemies.damage(i0, 100.0)
	_check("frozen goblins take +50% damage", is_equal_approx(before - main.enemies.hp[i0], 150.0), "%.0f" % (before - main.enemies.hp[i0]))
	main.player.global_position = main.enemies.pos[i0] + Vector3(0, 0, 0.3)
	var hp0: float = main.player.hp
	main.player.god_mode = false
	main.player.invuln = 0.0
	main._contact_damage()
	_check("frozen goblins can't hurt you", main.player.hp == hp0, "%.0f -> %.0f" % [hp0, main.player.hp])
	main.player.god_mode = true
	# Shatter: kill a frozen 200-HP goblin next to a frozen 10-HP one (its shatter: 40% of 200)
	var pair: Array = await _ring(2, 0.0, 1.0)
	main.enemies.hp_max[_idx(pair[0])] = 200.0
	main.enemies.pos[_idx(pair[1])] = main.enemies.pos[_idx(pair[0])] + Vector3(1.0, 0, 0)
	for u in pair:
		main.enemies.freeze(_idx(u), 3.0)
	var shattered := [0]
	main.enemies.shattered.connect(func(_p, _r): shattered[0] += 1)
	main.enemies.damage(_idx(pair[0]), 999.0)
	await _frames(4)
	_check("frozen goblins shatter and the shatter chains", shattered[0] >= 2 and _idx(pair[1]) < 0, "%d shatters" % shattered[0])

	var base: float = main.stats.value("move_speed")
	_cast(1)
	_check("Glacial Path: +60% move speed", is_equal_approx(main.stats.value("move_speed"), base * 1.6), "%.2f" % main.stats.value("move_speed"))
	main.player.bot = true
	main.player.bot_move = Vector2(0, -1)
	await _secs(2.0)
	var roster: RosterKit = main.abilities.roster
	_check("Glacial Path leaves an ice trail", roster._patches.size() >= 5, "%d patches" % roster._patches.size())
	var p: Vector3 = roster._patches[1]["pos"]
	var gi: int = main.enemies.spawn(EnemyManager.GRUNT, p, 1000.0)
	var gu: int = main.enemies.uid[gi]
	await _secs(0.5)
	var gj := _idx(gu)
	_check("the trail slows and hurts goblins", gj >= 0 and main.enemies.slow_t[gj] > 0.0 and main.enemies.hp[gj] < main.enemies.hp_max[gj], "")
	main.player.bot_move = Vector2.ZERO
	await _secs(4.5)
	_check("speed returns to normal after 6 s", is_equal_approx(main.stats.value("move_speed"), base), "%.2f" % main.stats.value("move_speed"))

	ring = await _ring(12, 15.0, 25.0)
	_cast(2)
	await _secs(1.0)
	var i1 := _idx(ring[0])
	_check("Absolute Zero: blizzard slows goblins inside by 80%", roster.active("zero") and main.enemies.slow_t[i1] > 0.0 and is_equal_approx(main.enemies.slow_f[i1], 0.2), "")
	_check("blizzard drains 4% of max HP per second", main.enemies.hp[i1] < main.enemies.hp_max[i1] * 0.98, "%.0f/%.0f" % [main.enemies.hp[i1], main.enemies.hp_max[i1]])
	await _secs(7.3)
	frozen = 0
	for u in ring:
		var i := _idx(u)
		if i >= 0 and main.enemies.freeze_t[i] > 0.0:
			frozen += 1
	_check("when it ends, everything inside freezes", frozen == 12, "%d" % frozen)
	await _secs(2.4)
	var alive := 0
	for u in ring:
		if _idx(u) >= 0:
			alive += 1
	_check("...then shatters for 200 (+50% frozen: 250-HP goblins die)", alive == 0, "%d alive" % alive)


func _extra(n: int, r: float) -> Array:
	var e: EnemyManager = main.enemies
	var at: Vector3 = main.player.global_position
	var out := []
	for k in n:
		var a := TAU * (k + 0.5) / n
		out.append(e.uid[e.spawn(EnemyManager.GRUNT, at + Vector3(cos(a), 0, sin(a)) * r, 100000.0)])
	await _frames(2)
	return out


# ------------------------------------------------------------------ Thunder

func _test_thunder_wizard() -> void:
	var w: WeaponSystem = main.weapons
	_check("weapon: Chain Lightning", w.style == "thunder" and main.db.defs["weapon_orb"]["name"] == "Chain Lightning", w.style)
	var ring := await _ring(8, 2.5, 100000.0)
	await _secs(1.5)
	var hurt := 0
	for u in ring:
		var i := _idx(u)
		if i >= 0 and main.enemies.hp[i] < main.enemies.hp_max[i]:
			hurt += 1
	_check("Chain Lightning arcs between goblins (one shot, several hit)", hurt >= 3 and w.lightning.count() >= 0, "%d hurt" % hurt)

	var base: float = main.stats.value("move_speed")
	ring = await _ring(8, 4.0)
	_cast(0)
	_check("Overcharge: +40% move speed", is_equal_approx(main.stats.value("move_speed"), base * 1.4), "%.2f" % main.stats.value("move_speed"))
	await _frames(2)
	var hurt0 := _hurt_count(ring)
	main.player.bot = true
	main.player.bot_jump = true
	await _secs(0.4)
	main.player.bot_jump = false
	await _secs(1.5)
	var roster: RosterKit = main.abilities.roster
	_check("every jump and landing releases a shock", hurt0 == 8 and _total_damage(ring) >= 40.0 * 3 * 8 * 0.9, "%.0f total" % _total_damage(ring))
	# Extra mid-air jumps (Feather / skill tree) shock as well: take-off + air jump + landing = 3
	main.stats.apply("extra_jumps", "flat", 1.0)
	main.weapons.orb_t = 999.0   # keep Chain Lightning out of the count
	var ring2 := await _ring(8, 4.0, 100000.0)
	var air := [0]
	main.player.air_jumped.connect(func(): air[0] += 1)
	main.player.bot_jump = true
	await _frames(2)
	main.player.bot_jump = false
	await _secs(0.3)
	main.player.bot_jump = true
	await _frames(2)
	main.player.bot_jump = false
	await _secs(1.5)
	var dmg2 := _total_damage(ring2)
	_check("an air jump during Overcharge shocks too", air[0] == 1 and dmg2 >= 40.0 * 3 * 8 * 0.9, "%d air jumps, %.0f total" % [air[0], dmg2])
	main.stats.apply("extra_jumps", "flat", -1.0)
	main.weapons.orb_t = 0.0
	await _secs(5.0)
	_check("speed returns to normal after 8 s", is_equal_approx(main.stats.value("move_speed"), base), "")

	# Thunderclap: the 12 goblins with the most HP are struck and stunned; weaker ones aren't
	var e: EnemyManager = main.enemies
	ring = await _ring(16, 12.0, 10000.0)
	for k in 4:   # four weaklings
		e.hp[_idx(ring[k])] = 50.0
	_cast(1)
	await _secs(1.4)
	var stunned := 0
	var weak_hit := 0
	for k in ring.size():
		var i := _idx(ring[k])
		if i >= 0 and e.stun_t[i] > 0.0:
			stunned += 1
			if k < 4:
				weak_hit += 1
	_check("Thunderclap: 12 bolts on the goblins with the most HP, stunning them", stunned == 12 and weak_hit == 0, "%d stunned, %d weak" % [stunned, weak_hit])
	_check("bolts deal 120 damage", e.hp_max[_idx(ring[10])] - e.hp[_idx(ring[10])] >= 120.0, "%.0f" % e.hp[_idx(ring[10])])

	ring = await _ring(20, 10.0, 100000.0)
	_cast(2)
	await _secs(3.0)
	_check("Storm Lord: a storm cloud follows you", roster.active("storm") and is_instance_valid(roster._storm_cloud), "")
	var dmg := _total_damage(ring)
	_check("bolts strike goblins within 18 m (90 each, chaining)", dmg >= 90.0 * 8, "%.0f" % dmg)
	await _secs(8.0)
	_check("the storm ends after 10 s", not roster.active("storm"), "")


func _hurt_count(ring: Array) -> int:
	var n := 0
	for u in ring:
		var i := _idx(u)
		if i >= 0 and main.enemies.hp[i] < main.enemies.hp_max[i]:
			n += 1
	return n


func _total_damage(ring: Array) -> float:
	var t := 0.0
	for u in ring:
		var i := _idx(u)
		if i >= 0:
			t += main.enemies.hp_max[i] - main.enemies.hp[i]
	return t


# ------------------------------------------------------------------ Dark

func _test_dark_wizard() -> void:
	var w: WeaponSystem = main.weapons
	_check("weapon: Shadow Bolts", w.style == "dark" and main.db.defs["weapon_orb"]["name"] == "Shadow Bolts", w.style)
	var e: EnemyManager = main.enemies
	var ring := await _ring(30, 7.0, 100000.0)
	await _secs(6.0)
	var cursed := 0
	for u in ring:
		var i := _idx(u)
		if i >= 0 and e.curse_t[i] > 0.0:
			cursed += 1
	_check("Shadow Bolts sometimes curse", cursed > 0, "%d cursed" % cursed)
	var i0 := _idx(ring[0])
	e.curse(i0, 2.0)
	var h := e.hp[i0]
	e.damage(i0, 100.0)
	_check("cursed goblins take +25% damage", is_equal_approx(h - e.hp[i0], 125.0), "%.0f" % (h - e.hp[i0]))

	ring = await _ring(10, 8.0, 1000.0)
	main.player.hp = 50.0
	_cast(0)
	await _secs(2.05)
	var i1 := _idx(ring[0])
	var frac := e.hp[i1] / e.hp_max[i1]
	_check("Siphon drains 6% max HP per second", frac < 1.0 - 0.06 * 1.6 and frac > 0.7, "%.2f" % frac)
	_check("...and heals you 1 HP per goblin per second (cap 5%)", main.player.hp > 54.0 and main.player.hp < 62.0, "%.1f" % main.player.hp)
	await _secs(2.5)

	ring = await _ring(6, 12.0, 100000.0)
	_cast(1)
	await _secs(1.5)
	var roster: RosterKit = main.abilities.roster
	_check("Raise Dead: 15 dead goblins rise", roster.allies.count() == 15, "%d" % roster.allies.count())
	await _secs(4.0)
	_check("the risen fight the horde", _total_damage(ring) > 0.0, "%.0f" % _total_damage(ring))
	await _secs(10.5)
	_check("they explode after 15 s", roster.allies.count() == 0, "%d left" % roster.allies.count())

	ring = await _ring(10, 6.0, 1.0)
	_cast(2)
	await _secs(0.5)
	_check("Eclipse: goblins lose track of you", e.lost, "")
	_check("you deal +100% damage", is_equal_approx(e.bonus_mult, 2.0), "%.1f" % e.bonus_mult)
	var big := await _extra(8, 9.0)
	e.damage(_idx(ring[0]), 9999.0)
	await _secs(1.5)
	_check("kills release wisps that hit other goblins for 60", _total_damage(big) >= 60.0 * 2.0, "%.0f" % _total_damage(big))
	await _secs(7.0)
	_check("after 8 s everything's back to normal", not e.lost and is_equal_approx(e.bonus_mult, 1.0) and roster._dimmed.is_empty(), "")


# ------------------------------------------------------------------ helpers

func _secs(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout


func _frames(n: int) -> void:
	for f in n:
		await get_tree().physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s %s  [%s]" % ["ok   " if ok else "FAIL ", name, detail])
	if not ok:
		fails += 1
