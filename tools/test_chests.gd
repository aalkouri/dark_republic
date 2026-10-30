extends Node
## Chests, keys, the slot machine and ability levels.
##   godot --headless --path . res://tools/test_chests.tscn

var fails := 0
var main: Node


func _ready() -> void:
	Wallet.persist = false
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	_test_odds()
	_test_shards()
	_test_levels_math()
	for map in ["swamp", "forest", "castle"]:
		await _start("fire_wizard", map)
		_test_placement(map)
	await _start("thunder_wizard", "swamp")
	await _test_keys_and_open()
	await _test_levels_in_game()
	await _test_tooltip()
	await _test_new_weapons()
	await _test_convert()
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _start(id: String, map: String) -> void:
	print("--- ", id, " on ", map)
	Settings.selected_character = id
	Settings.selected_map = map
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	main = get_tree().current_scene
	main.player.god_mode = true
	await _secs(Abilities.METEOR_FALL_TIME + 0.6)
	main.xp_next = 1e12


func _secs(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


## The slot machine's odds: three of a kind about TRIPLE_ODDS of the time per tier; otherwise
## the most common symbol wins +1; maxed abilities never win.
func _test_odds() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	var all := [0, 1, 2]
	for tier in 3:
		var n := 20000
		var triples := 0
		var pairs := 0
		for k in n:
			var s := SlotMachine.roll(tier, all, r)
			if s[0] == s[1] and s[1] == s[2]:
				triples += 1
			elif s[0] == s[1] or s[0] == s[2] or s[1] == s[2]:
				pairs += 1
		var rate := float(triples) / n
		_check("tier %d: three of a kind %.1f%% (want %d%%)" % [tier, rate * 100.0, roundi(SlotMachine.TRIPLE_ODDS[tier] * 100.0)],
			absf(rate - SlotMachine.TRIPLE_ODDS[tier]) < 0.01, "")
		# the rest: 18 of the 24 non-triple combos have a pair
		_check("tier %d: pairs are 3/4 of the rest" % tier, absf(float(pairs) / (n - triples) - 0.75) < 0.02, "%.3f" % (float(pairs) / (n - triples)))
	var w := SlotMachine.winner_of(PackedInt32Array([1, 1, 1]), all, r)
	_check("three of a kind: +3 levels to it", w[0] == 1 and w[1] == 3, str(w))
	w = SlotMachine.winner_of(PackedInt32Array([2, 0, 2]), all, r)
	_check("a pair: +1 to the pair", w[0] == 2 and w[1] == 1, str(w))
	var seen := {}
	for k in 200:
		w = SlotMachine.winner_of(PackedInt32Array([0, 1, 2]), all, r)
		seen[w[0]] = true
	_check("all different: +1 to one of them at random", seen.size() == 3, str(seen.keys()))
	var only_two := [0, 2]   # ability 1 is maxed
	var bad := 0
	for k in 3000:
		var s := SlotMachine.roll(2, only_two, r)
		var ww := SlotMachine.winner_of(s, only_two, r)
		if ww[0] == 1:
			bad += 1
	_check("a maxed ability is never the one levelled", bad == 0, "%d" % bad)


func _test_shards() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var lo := 99
	var hi := 0
	var kinds := {}
	for k in 2000:
		var won := Wallet.roll_boss_shards(r)
		var n := 0
		for kind in won:
			n += int(won[kind])
			kinds[kind] = true
		lo = mini(lo, n)
		hi = maxi(hi, n)
	_check("a boss drops 1-5 shards", lo == 1 and hi == 5, "%d..%d" % [lo, hi])
	_check("of all four kinds, at random", kinds.size() == 4 and kinds.has("fire") and kinds.has("ice") and kinds.has("lightning") and kinds.has("dark"), str(kinds.keys()))
	var before: int = Wallet.shards["ice"]
	Wallet.add_shards({"ice": 2})
	_check("shards bank into the wallet and the counter shows them", Wallet.shards["ice"] == before + 2
		and (Wallet.shard_labels["ice"] as Label).text == str(before + 2) and Wallet.shard_panel != null, "")
	Wallet.shards["ice"] = before
	Wallet._refresh_shards()


func _test_levels_math() -> void:
	_check("level 1 = 1x, level 10 = 4x", is_equal_approx(Abilities.power_at(1), 1.0) and is_equal_approx(Abilities.power_at(10), 4.0), "")
	_check("level 4 = 2x, level 7 = 3x", is_equal_approx(Abilities.power_at(4), 2.0) and is_equal_approx(Abilities.power_at(7), 3.0), "")
	_check("cooldown: level 1 full, level 10 -40%", is_equal_approx(Abilities.cd_mult_at(1), 1.0) and is_equal_approx(Abilities.cd_mult_at(10), 0.6), "")
	var ok := true
	for kit in Abilities.LEVEL_STATS:
		ok = ok and (Abilities.LEVEL_STATS[kit] as Array).size() == 3
	_check("every playable character says what its levels raise", ok and Abilities.LEVEL_STATS.size() >= 14, "%d kits" % Abilities.LEVEL_STATS.size())


func _test_placement(map: String) -> void:
	var cm: ChestManager = main.chests
	var n := cm.chests.size()
	_check("%s: %d-%d chests placed" % [map, ChestManager.MIN_CHESTS, ChestManager.MAX_CHESTS], n >= ChestManager.MIN_CHESTS and n <= ChestManager.MAX_CHESTS, "%d" % n)
	var tiers := [0, 0, 0]
	for c in cm.chests:
		tiers[c.tier] += 1
	_check("%s: bronze most common" % map, tiers[0] >= tiers[2], str(tiers))
	_check("%s: no shrines left" % map, get_tree().get_nodes_in_group("shrines").is_empty() and main.get("shrines") == null, "")
	var r := RandomNumberGenerator.new()
	r.seed = 99
	cm.rng = r
	var count := [0, 0, 0]
	for k in 6000:
		count[cm.roll_tier()] += 1
	_check("chest tiers: bronze > silver > gold", count[0] > count[1] and count[1] > count[2] and count[2] > 300, str(count))


func _test_keys_and_open() -> void:
	var km: KeyManager = main.keys
	var cm: ChestManager = main.chests
	var r := RandomNumberGenerator.new()
	r.seed = 5
	km.rng = r
	var dropped := 0
	for k in 2000:
		if km.on_elite_killed(Vector3(500, 0, 500)):
			dropped += 1
	_check("elites drop keys now and then (~%d%%)" % roundi(KeyManager.DROP_CHANCE * 100.0), absf(dropped / 2000.0 - KeyManager.DROP_CHANCE) < 0.03, "%d" % dropped)
	var tiers := [0, 0, 0]
	for k in 6000:
		tiers[km.roll_tier()] += 1
	_check("keys: bronze usually, silver sometimes, gold rarely", tiers[0] > tiers[1] * 2 and tiers[1] > tiers[2] * 2, str(tiers))
	km.keys = PackedInt32Array([0, 0, 0])
	for d in km._drops:
		(d["node"] as Node).queue_free()
	km._drops.clear()
	# A silver chest right next to you, no key: it stays shut and says which key it needs
	var p: Vector3 = main.player.global_position
	var c := cm.place(p + Vector3(1.0, 0, 0), 1)
	await _secs(0.3)
	_check("no key: chest stays shut", not c.is_open and main.state == "playing", main.state)
	_check("...and says it needs a Silver Key", c._hint.visible and c._hint.text.contains("Silver"), c._hint.text)
	# The wrong key doesn't open it
	km.keys[0] = 1
	await _secs(0.3)
	_check("a bronze key doesn't open a silver chest", not c.is_open, "")
	# Walk over a dropped silver key: picked up
	km.drop(main.player.global_position + Vector3(0, 0, 0.5), 1)
	await _secs(0.6)
	_check("silver key picked up", km.keys[1] == 0 or c.is_open, str(km.keys))
	await _secs(0.3)
	_check("with the key: the chest opens and the game pauses for the slot machine", c.is_open and main.state == "chest" and get_tree().paused
		and main.hud.slot_machine != null, main.state)
	_check("the key was used", km.keys[1] == 0 and km.keys[0] == 1, str(km.keys))
	var sm: SlotMachine = main.hud.slot_machine
	_check("slot machine shows the chest tier's odds", sm._odds.text.contains("15%"), sm._odds.text)
	var reels_ok := true
	for rr in 3:
		reels_ok = reels_ok and sm.showing(rr) >= 0 and sm.showing(rr) <= 2
	_check("three reels of your three abilities", reels_ok and sm._strips.size() == 3, "")
	var before: PackedInt32Array = main.abilities.ab_level.duplicate()
	var t0: float = main.run_time
	sm.pull()
	_check("pulling the handle spins the reels", sm._state == "spinning", sm._state)
	await _secs(1.0)
	_check("game stays paused while they spin", is_equal_approx(main.run_time, t0) and get_tree().paused, "")
	await _secs(2.6)
	_check("reels stop, left to right, on the rolled result", sm.is_done() and sm.showing(0) == sm.result[0] and sm.showing(1) == sm.result[1]
		and sm.showing(2) == sm.result[2], "%s vs %d %d %d" % [str(sm.result), sm.showing(0), sm.showing(1), sm.showing(2)])
	var gained := 0
	for i in 3:
		gained += main.abilities.ab_level[i] - before[i]
	_check("the winner levelled up (+1, or +3 on three of a kind)", main.abilities.ab_level[sm.winner] - before[sm.winner] == sm.levels and gained == sm.levels,
		"%s -> %s" % [str(before), str(main.abilities.ab_level)])
	sm._finish()
	await _secs(0.2)
	_check("Continue: back to the run", main.state == "playing" and not get_tree().paused and main.hud.slot_machine == null, main.state)
	main._award_shards()
	var got := 0
	for kind in main.shards_won:
		got += int(main.shards_won[kind])
	main.hud._show_end_shards(main.shards_won)
	_check("defeating a boss: 1-5 shards, listed on the end screen", got >= 1 and got <= 5 and main.hud.end_shards.visible
		and main.hud.end_shards.get_child_count() == 1 + 2 * main.shards_won.size(), str(main.shards_won))
	_check("opened chests count for character EXP", main.chests_opened == 1 and Wallet.run_exp(0, 0, 0, 1, 0.0, false)["chests"] == Wallet.EXP_PER_CHEST, "")


func _test_levels_in_game() -> void:
	var ab: Abilities = main.abilities
	ab.ab_level = PackedInt32Array([1, 1, 1])
	ab.level = 10
	ab.reset_cooldowns()
	var base_cd: float = ab.defs()[1]["cooldown"]
	main.cast_ability(1)
	var cd1 := ab.cooldown[1]
	ab.reset_cooldowns()
	ab.level_up(1, 9)
	_check("level_up caps at 10", ab.ab_level[1] == 10 and ab.level_up(1, 3) == 0, str(ab.ab_level))
	main.cast_ability(1)
	_check("level 10 cooldown is 40% shorter", is_equal_approx(ab.cooldown[1], cd1 * 0.6), "%.1f vs %.1f (base %.0f)" % [ab.cooldown[1], cd1, base_cd])
	# Thunderclap damage x4 at level 10
	var e: EnemyManager = main.enemies
	for i in e.count:
		e.dead[i] = 1
	e._dead_count = e.count
	e.count = 0
	var p: Vector3 = main.player.global_position
	main.weapons.orb_t = 999.0   # keep Chain Lightning out of the count
	var g := e.spawn(EnemyManager.GRUNT, p + Vector3(6, 0, 0), 10000.0)
	ab.reset_cooldowns()
	var hp0: float = e.hp[g]
	main.cast_ability(1)
	await _secs(1.5)
	var dealt: float = hp0 - e.hp[g]
	_check("Thunderclap at level 10 hits for 4x (480)", absf(dealt - RosterKit.CLAP_DAMAGE * 4.0 * main.stats.value("damage")) < 1.0, "%.0f" % dealt)
	# Overcharge shocks scale with its level too
	ab.ab_level[0] = 4
	_check("pw(): level 4 = 2x", is_equal_approx(ab.roster.pw(0), 2.0), "")
	_check("ability bar shows the level badge", (main.hud.ability_slots[1] as AbilitySlot).ab_level == 10, "")
	# Every ability maxed: a chest heals instead of a slot machine
	ab.ab_level = PackedInt32Array([10, 10, 10])
	main.player.hp = 10.0
	main._open_slot_machine(2)
	_check("all maxed: no slot machine, full heal", main.state == "playing" and is_equal_approx(main.player.hp, main.player.max_hp), main.state)
	ab.ab_level = PackedInt32Array([1, 1, 1])


func _test_tooltip() -> void:
	var ab: Abilities = main.abilities
	ab.ab_level = PackedInt32Array([3, 1, 10])
	var t0 := ab.describe(0)
	var t2 := ab.describe(2)
	_check("tooltip: level and what it raises", t0.contains("Level 3 / 10") and t0.contains("shock damage") and t0.contains("cooldown"), t0)
	_check("tooltip: current and next level numbers", t0.contains("x1.67") and t0.contains("x2"), t0)
	_check("tooltip: max level", t2.contains("Max level") and t2.contains("x4"), t2)


## Level-up: Convert a Legendary card into a chest key (60/30/10), a big key flies to the
## counter; BAN shows the coin; Alt-inspect tooltips on the inventory.
func _test_convert() -> void:
	var hud: Hud = main.hud
	var r := RandomNumberGenerator.new()
	r.seed = 3
	main.rng = r
	var tally := [0, 0, 0]
	for k in 3000:
		main.state = "levelup"
		main.current_draft = [{"id": "tome_damage", "rarity": 3}, {"id": "tome_armor", "rarity": 0}]
		main.pending_levels = 2   # keep the draft open
		var before: PackedInt32Array = main.keys.keys.duplicate()
		var t: int = main.convert_upgrade(0)
		tally[t] += 1
		if k == 0:
			_check("Convert: one key more", main.keys.keys[t] == before[t] + 1, str(main.keys.keys))
	_check("Convert odds: 60% bronze, 30% silver, 10% gold", absf(tally[0] / 3000.0 - 0.6) < 0.03 and absf(tally[1] / 3000.0 - 0.3) < 0.03
		and absf(tally[2] / 3000.0 - 0.1) < 0.02, str(tally))
	main.state = "levelup"
	main.current_draft = [{"id": "tome_damage", "rarity": 3}, {"id": "tome_armor", "rarity": 0}]
	main.pending_levels = 1
	_check("only Legendary cards convert", main.convert_upgrade(1) == -1, "")
	hud.show_draft(main.current_draft)
	_check("the Convert button only shows on the Legendary card", (hud.draft_cards[0][7] as Button).visible and not (hud.draft_cards[1][7] as Button).visible, "")
	_check("BAN shows the coin icon instead of the word", (hud.draft_cards[0][5] as Button).text == "" and not (hud.draft_cards[0][5] as Button).find_children("*", "CoinIcon", true, false).is_empty(), "")
	main.convert_upgrade(0)
	await get_tree().process_frame
	_check("...the last pick: the draft closes and play resumes", main.state == "playing" and not hud.draft_root.visible, main.state)
	_check("a big key pops up", not hud._key_pops.is_empty(), "")
	await _secs(Hud.KEY_POP_HOLD + Hud.KEY_POP_FLY + 0.3)
	_check("...and flies into the key counter at the bottom left", hud._key_pops.is_empty() and hud.key_labels[0].text != "", "")
	# Alt-inspect tooltips on the inventory chips
	main.db.apply({"id": "tome_damage", "rarity": 0}, main.stats)
	var tip := hud.upgrade_tooltip("tome_damage")
	_check("inventory tooltip: name, level, what it does and the stat", tip.contains("Tome of Damage") and tip.contains("Damage: 1 -> 1.12"), tip)
	var tip2 := hud.upgrade_tooltip("weapon_orb")
	_check("...and for the main weapon its numbers", tip2.contains("Damage") and tip2.contains("Cooldown"), tip2)


## Thorns and Ice Aura: weapons anyone can draft, as often as a tome.
func _test_new_weapons() -> void:
	var db: UpgradeDB = main.db
	_check("Thorns and Ice Aura are in the pool, as common as tomes", db.defs.has("weapon_thorns") and db.defs.has("weapon_frost")
		and int(db.defs["weapon_thorns"]["weight"]) == int(db.defs["tome_damage"]["weight"]) and int(db.defs["weapon_frost"]["weight"]) == int(db.defs["tome_damage"]["weight"]), "")
	_check("...with their own icons", db.defs["weapon_thorns"]["icon"]["glyph"] == "thorns" and db.defs["weapon_frost"]["icon"]["glyph"] == "frost_aura", "")
	var e: EnemyManager = main.enemies
	for i in e.count:
		e.dead[i] = 1
	e._dead_count = e.count
	e.count = 0
	var p: Vector3 = main.player.global_position
	main.weapons.orb_t = 999.0
	# Thorns: an enemy that hits you takes its damage back (x2 at level 1)
	db.apply({"id": "weapon_thorns", "rarity": 0}, main.stats)
	var g := e.spawn(EnemyManager.GRUNT, p + Vector3(0.2, 0, 0), 1000.0)
	await get_tree().physics_frame   # into the crowd's spatial grid
	e.pos[g] = main.player.global_position + Vector3(0.2, 0, 0)
	e.tick(0.0, main.player.global_position)
	var h0: float = e.hp[g]
	main.player.invuln = 0.0
	main._contact_damage()
	var back: float = h0 - e.hp[g]
	var want: float = e.t_damage[EnemyManager.GRUNT] * main.enemy_damage_mult() * main.stats.value("thorns_return") * main.stats.value("damage")
	_check("Thorns: whatever hits you takes its damage back", back > 0.0 and absf(back - want) < 1.0, "%.1f vs %.1f" % [back, want])
	e.dead[g] = 1
	# Ice Aura: enemies within its radius are slowed, those outside aren't
	db.apply({"id": "weapon_frost", "rarity": 0}, main.stats)
	var r: float = main.stats.value("frost_radius")
	var near := e.spawn(EnemyManager.GRUNT, p + Vector3(r * 0.6, 0, 0), 1000.0)
	var far := e.spawn(EnemyManager.GRUNT, p + Vector3(r + 6.0, 0, 0), 1000.0)
	await _secs(0.5)
	_check("Ice Aura slows everything around you", e.slow_t[near] > 0.0 and e.slow_f[near] <= 0.61, "slow %.2f" % e.slow_f[near])
	_check("...but not beyond its radius", e.slow_t[far] <= 0.0, "")
	_check("...and shows on the ground", main.weapons.frost_mesh.visible, "")


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
