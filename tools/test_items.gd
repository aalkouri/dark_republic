extends Node
## The four newer items (Cursed Coin, Glass Cannon Skull, Hourglass, Mirror Shard) in a real run.
##   godot --headless --path . --fixed-fps 60 res://tools/test_items.tscn

var fails := 0
var main: Node


func _ready() -> void:
	Wallet.persist = false
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	Settings.selected_character = "fire_wizard"
	Settings.selected_map = "swamp"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	main = get_tree().current_scene
	for f in 60 * 8:
		await get_tree().physics_frame
		if not main.intro:
			break
	main.xp_next = 1e12
	main._next_swarm = 1e9
	var db: UpgradeDB = main.db
	var st: Stats = main.stats
	var p: Player = main.player

	for id in ["item_coin", "item_skull", "item_hourglass", "item_mirror"]:
		_check("%s is an item with an icon glyph" % id, db.defs.has(id) and db.defs[id]["kind"] == "item" and db.defs[id]["icon"].has("glyph"), "")
		_check("%s's card describes it" % id, db.describe({"id": id, "rarity": 0})["body"] != "", "")
	_check("skull card shows the drawback as -10% Max HP", "-10% Max HP" in db.describe({"id": "item_skull", "rarity": 3})["body"], db.describe({"id": "item_skull", "rarity": 3})["body"])

	# Glass Cannon Skull: +20% damage, -10% max HP per level, HP clamped down
	var dmg0 := st.value("damage")
	db.apply({"id": "item_skull", "rarity": 3}, st)   # fixed: rarity doesn't scale it
	_check("skull: +20% damage", is_equal_approx(st.value("damage"), dmg0 * 1.2) or is_equal_approx(st.value("damage"), dmg0 + 0.2 * st.base_of("damage")), "%.3f" % st.value("damage"))
	_check("skull: max HP -10% and HP no higher than it", p.max_hp < 100.0 and p.hp <= p.max_hp + 0.01, "%.1f / %.1f" % [p.hp, p.max_hp])

	# Cursed Coin: more damage taken, coins on kills, banked with the run's coins
	db.apply({"id": "item_coin", "rarity": 0}, st)
	_check("coin: 2% drop chance, +6% damage taken", is_equal_approx(st.value("coin_drop_chance"), 0.02) and is_equal_approx(st.value("damage_taken"), 1.06), "")
	p.invuln = 0.0
	p.shield = 0.0
	var hp0 := p.hp
	p.hurt(10.0)
	_check("coin: a 10 hit takes 10.6", absf((hp0 - p.hp) - 10.6) < 0.05, "%.2f" % (hp0 - p.hp))
	st.apply("coin_drop_chance", "flat", 1.0)
	var c0: int = main.item_coins
	for k in 5:
		main._on_enemy_killed(p.global_position + Vector3(4, 0, 0), 0)
	_check("coin: kills drop coins", main.item_coins - c0 == 5, str(main.item_coins - c0))
	st.apply("coin_drop_chance", "flat", -1.0)

	# Hourglass: an elite kill cuts every running cooldown
	db.apply({"id": "item_hourglass", "rarity": 0}, st)
	main.abilities.cooldown = PackedFloat32Array([10.0, 0.5, 30.0])
	main.enemies.epic_killed.emit(p.global_position + Vector3(5, 0, 0))
	var cd: PackedFloat32Array = main.abilities.cooldown
	_check("hourglass: -1 s on each cooldown (never below 0)", is_equal_approx(cd[0], 9.0) and is_equal_approx(cd[1], 0.0) and is_equal_approx(cd[2], 29.0), str(cd))

	# Mirror Shard: dodges (capped at 60%)
	db.apply({"id": "item_mirror", "rarity": 0}, st)
	_check("mirror: 4% dodge", is_equal_approx(st.value("dodge_chance"), 0.04), "")
	st.apply("dodge_chance", "flat", 5.0)
	var dodges := 0
	var got := [0]
	p.dodged.connect(func(): got[0] += 1)
	for k in 400:
		p.invuln = 0.0
		var h := p.hp
		p.hurt(0.01)
		if is_equal_approx(h, p.hp):
			dodges += 1
		p.hp = p.max_hp
	_check("mirror: dodge capped near 60%", dodges > 200 and dodges < 280, "%d / 400" % dodges)
	_check("mirror: each dodge signalled", got[0] == dodges, "%d vs %d" % [got[0], dodges])

	_test_draft_slots()
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


## Level-up drafts: while weapon / tome slots are open, a new one of each is always offered.
func _test_draft_slots() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var d := UpgradeDB.new("res://data/upgrades.json", r)
	d.levels["weapon_orb"] = 1   # the starting weapon
	var both := true
	for k in 300:
		var kinds := _new_kinds(d, d.draft(3, 0.0, 4))
		both = both and kinds.has("weapon") and kinds.has("tome")
	_check("open weapon and tome slots: every draft has a new weapon and a new tome", both, "")
	var tomes := 0
	for id in d.order:
		if d.defs[id]["kind"] == "tome" and tomes < 4:
			d.levels[id] = 1
			tomes += 1
	var w_ok := true
	for k in 300:
		w_ok = w_ok and _new_kinds(d, d.draft(3, 0.0, 4)).has("weapon")
	_check("tomes full, weapons open: every draft has a new weapon", w_ok, "")
	for id in d.order:
		if d.defs[id]["kind"] == "tome":
			d.levels.erase(id)
	var ws := 0
	for id in d.order:
		if d.defs[id]["kind"] == "weapon" and not d.defs[id].has("signature") and ws < 4:
			d.levels[id] = 1
			ws += 1
	var t_ok := true
	var no_new_w := true
	for k in 300:
		var picks := d.draft(3, 0.0, 4)
		var kinds := _new_kinds(d, picks)
		t_ok = t_ok and kinds.has("tome")
		no_new_w = no_new_w and not kinds.has("weapon")
	_check("weapons full, tomes open: every draft has a new tome (and no new weapon)", t_ok and no_new_w, "")


func _new_kinds(d: UpgradeDB, picks: Array) -> Dictionary:
	var out := {}
	for pk in picks:
		if d.level_of(pk["id"]) == 0:
			out[d.defs[pk["id"]]["kind"]] = true
	return out


func _check(what: String, ok: bool, info: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what + ("" if ok or info == "" else "   (" + info + ")"))
	if not ok:
		fails += 1
