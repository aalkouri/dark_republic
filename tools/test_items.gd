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
	_test_item_tiers()
	await _test_sprint()
	await _test_world_items()
	await _test_crypts_and_statues()
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _secs(t: float) -> void:
	for f in int(t * 60):
		await get_tree().physics_frame


## Sprint (Shift): faster while stamina lasts; the HUD bar shows it live; winded at 0.
func _test_sprint() -> void:
	var p: Player = main.player
	p.god_mode = true
	_check("Sprint is bound to Shift and Slide isn't any more", InputMap.has_action("sprint") and _has_key("sprint", KEY_SHIFT) and not _has_key("slide", KEY_SHIFT), "")
	p.bot = true
	p.bot_move = Vector2(0, -1)
	await _secs(1.0)
	var walk := p.horizontal_speed()
	p.bot_sprint = true
	await _secs(1.0)
	var run := p.horizontal_speed()
	_check("sprinting is ~40% faster", run > walk * 1.3, "%.1f vs %.1f m/s" % [run, walk])
	_check("...and drains stamina (the HUD bar shows it)", p.stamina < 85.0 and p.stamina > 60.0 and is_equal_approx(main.hud.stamina_bar.value, p.stamina), "%.1f, bar %.1f" % [p.stamina, main.hud.stamina_bar.value])
	await _secs(3.5)
	_check("run it dry and you're winded (back to walking)", p.winded and not p.sprinting and p.stamina < 5.0, "%.1f" % p.stamina)
	p.bot_sprint = false
	p.bot_move = Vector2.ZERO
	await _secs(2.5)
	_check("resting refills it", p.stamina > 30.0 and not p.winded, "%.1f" % p.stamina)
	p.bot = false
	p.stamina = Player.STAMINA_MAX


## Items have tiers: each drops at its tier's weight and shows in its colour; the Glass Cannon
## Skull is Legendary and rare. The Second Wind Flask (Common) raises max stamina.
func _test_item_tiers() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var d := UpgradeDB.new("res://data/upgrades.json", r)
	var all_tiered := true
	for id in d.order:
		if d.defs[id]["kind"] == "item":
			all_tiered = all_tiered and d.defs[id].has("tier")
	_check("every item has a tier", all_tiered, "")
	_check("the Glass Cannon Skull is Legendary", d.item_pick("item_skull")["rarity"] == 3, "")
	var counts := {}
	for k in 20000:
		var id := d.roll_item()
		counts[id] = int(counts.get(id, 0)) + 1
	var skull: int = counts.get("item_skull", 0)
	_check("...and much rarer than anything else (~2%)", skull > 150 and skull < 700 and skull * 3 < int(counts.get("item_hourglass", 0)) * 1 + 1000 and skull * 5 < int(counts.get("item_fang", 0)), str(counts))
	var st := Stats.new()
	st.define("max_stamina", 1.0)
	for m in d._scaled_mods(d.defs["item_flask"], d.item_tier("item_flask")):
		st.apply(m["stat"], m["op"], m["value"])
	_check("Second Wind Flask: +25% max stamina a level", is_equal_approx(st.value("max_stamina"), 1.25), "%.2f" % st.value("max_stamina"))


func _has_key(action: String, key: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
			return true
	return false


## Items only come from the world: a burnt tree drops one; picking it up pauses on its card.
func _test_world_items() -> void:
	var db: UpgradeDB = main.db
	var only_items := true
	for k in 200:
		for pk in db.draft(3, 0.0, 4):
			only_items = only_items and db.defs[pk["id"]]["kind"] != "item"
	_check("items never come up on level-up cards", only_items, "")
	_check("trees burn for 3 s", is_equal_approx(TreeFire.BURN_TIME, 3.0), "")
	var idrops: ItemDrops = main.item_drops
	var p: Player = main.player
	p.god_mode = true
	var at := p.global_position + Vector3(12, 0, 0)
	var n0 := idrops.count()
	Events.prop_burnt.emit(at)
	_check("a burnt tree drops an item", idrops.count() == n0 + 1, str(idrops.count()))
	var drop: Dictionary = idrops.drops[idrops.drops.size() - 1]
	var id: String = drop["id"]
	var before := db.level_of(id)
	await _secs(1.2)
	p.global_position = (drop["node"] as Node3D).global_position - Vector3(0, 0.9, 0)
	await _secs(0.3)
	_check("picking it up pauses the run on the item card", main.state == "item" and get_tree().paused and is_instance_valid(main.hud.item_found), main.state)
	_check("...and levels the item up", db.level_of(id) == before + 1, "%s %d" % [id, db.level_of(id)])
	main.hud.item_found._close()
	await get_tree().process_frame
	_check("Continue resumes the run", main.state == "playing" and not get_tree().paused, main.state)
	# all abilities burn trees
	var tree: Node3D = null
	for t in get_tree().get_nodes_in_group(TreeFire.GROUP):
		var tb := t as Node3D
		if not tb.has_meta("burn_state") and float(tb.get_meta("reach")) < 2.0:
			tree = tb
			break
	if tree != null:
		main.enemies.fire_hits.append(tree.global_position + Vector3(1, 0, 0))
		await _secs(0.4)
		_check("an ability hitting a goblin by a tree sets it alight", TreeFire.state_of(tree) == "burning", TreeFire.state_of(tree))
		idrops.shard_chance = 0.0
		var n_before := idrops.count()
		await _secs(TreeFire.BURN_TIME + 0.3)
		_check("...it burns out in 3 s and crumbles to dust", is_instance_valid(tree) and TreeFire.state_of(tree) == "charred" and idrops.count() == n_before, "%d drops" % idrops.count())
		var spot := tree.global_position
		await _secs(TreeFire.COLLAPSE + 0.3)
		_check("...then it's gone and its item is left where it stood", not is_instance_valid(tree) and idrops.count() == n_before + 1
			and Vector2((idrops.drops[idrops.drops.size() - 1]["to"] as Vector3).x - spot.x, (idrops.drops[idrops.drops.size() - 1]["to"] as Vector3).z - spot.z).length() < 2.5, "%d drops" % idrops.count())
	idrops.shard_chance = ItemDrops.SHARD_CHANCE
	# a rare shard instead of an item: one of this map's kinds
	idrops.shard_chance = 1.0
	var got := idrops.loot(p.global_position + Vector3(6, 0, 0))
	idrops.shard_chance = ItemDrops.SHARD_CHANCE
	_check("a rare shard drop is one of the map's shards", got.begins_with("shard:") and got.substr(6) in Wallet.map_shards("swamp"), got)


## The Graveyard's crypts and the Desert's statues: Activate for an item, then they sink away.
func _test_crypts_and_statues() -> void:
	for map in ["graveyard", "desert"]:
		Settings.selected_map = map
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
		main.player.god_mode = true
		var srcs := get_tree().get_nodes_in_group(ItemDrops.LOOT_GROUP)
		_check("%s: has loot sources (%d)" % [map, srcs.size()], srcs.size() >= (15 if map == "graveyard" else 6), "")
		if srcs.is_empty():
			continue
		var s: Node3D = srcs[0]
		var n0: int = main.item_drops.count()
		main.item_drops.open_source(s)
		_check("%s: opening one drops an item" % map, main.item_drops.count() == n0 + 1, "")
		_check("%s: ...and it can't be opened again" % map, not s.is_in_group(ItemDrops.LOOT_GROUP) and main.item_drops.open_source(s) == "", "")
		await _secs(ItemDrops.SINK_TIME + 0.3)
		_check("%s: it sinks into the ground and is gone" % map, not is_instance_valid(s), "")


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
