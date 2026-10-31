extends Node
## The Forge: shard recipes and costs, forging, forged stats in a run (own weapon and the
## Legendary card), the Fireballs' every-5th-hit explosion and the other weapons' level 1
## specials, and the character select's shard
## row, pulsing weapon and forge menu.
##   godot --headless --path . res://tools/test_forge.tscn

var fails := 0


func _ready() -> void:
	Wallet.persist = false
	Wallet.forge = {}
	_reset_shards()
	_test_costs()
	_test_forging()
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	await _test_select()
	await _test_run()
	await _test_specials()
	Wallet.forge = {}
	_reset_shards()
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _reset_shards() -> void:
	for k in Wallet.SHARDS:
		Wallet.shards[k] = 0


func _test_costs() -> void:
	var all_five := true
	for sty in WeaponSystem.STYLES:
		var r: Dictionary = Forge.RECIPES.get(sty, {})
		var n := 0
		for kind in r:
			n += int(r[kind])
		all_five = all_five and n == 5
	_check("every weapon has a recipe of exactly 5 shards", all_five and Forge.RECIPES.size() == WeaponSystem.STYLES.size(), "")
	_check("Ice Wizard: 5 ice", Forge.cost("ice", 1) == {"ice": 5}, str(Forge.cost("ice", 1)))
	_check("Fire Wizard: 5 fire", Forge.cost("fire", 1) == {"fire": 5}, str(Forge.cost("fire", 1)))
	_check("the Sock: 2 dark + 3 lightning", Forge.cost("static", 1) == {"lightning": 3, "dark": 2}, str(Forge.cost("static", 1)))
	var rising := true
	var last := 0
	for lvl in range(1, Forge.MAX_LEVEL + 1):
		var c := Forge.cost("static", lvl)
		var n := 0
		for kind in c:
			n += int(c[kind])
		rising = rising and n == Forge.TOTALS[lvl - 1] and n > last
		last = n
	_check("costs rise steeply up to level 10 (5 ... 100 shards)", rising and last == 100, "%d" % last)
	_check("nothing past level 10", Forge.cost("fire", 11).is_empty(), "")
	var missing := []
	for sty in WeaponSystem.STYLES:
		if not Forge.SPECIALS.has(sty):
			missing.append(sty)
	_check("every weapon has a level 1 forge special", missing.is_empty() and Forge.SPECIALS.size() == WeaponSystem.STYLES.size(), str(missing))
	Wallet.forge = {"ice": 1}
	_check("...listed in the forge menu / tooltip", Forge.describe("ice", 1).has(Forge.SPECIALS["ice"]) and Forge.has_special("ice") and not Forge.has_special("club"), str(Forge.describe("ice", 1)))
	Wallet.forge = {}


func _test_forging() -> void:
	_check("can't forge without the shards", not Forge.can_afford("ice") and not Forge.forge("ice"), "")
	Wallet.shards["ice"] = 7
	_check("with 5 ice shards the Frost Shards can be forged", Forge.can_afford("ice"), "")
	_check("forging spends them and raises the level", Forge.forge("ice") and Forge.level_of("ice") == 1 and Wallet.shards["ice"] == 2, str(Wallet.shards))
	_check("level 2 needs 10", Forge.next_cost("ice") == {"ice": 10} and not Forge.can_afford("ice"), str(Forge.next_cost("ice")))
	_check("each level: +25% damage, +8% attack rate; +1 shot at 4 and 8",
		is_equal_approx(Forge.damage_mult(4), 2.0) and is_equal_approx(Forge.rate_mult(10), 1.8) and Forge.count_bonus(3) == 0 and Forge.count_bonus(4) == 1 and Forge.count_bonus(10) == 2, "")
	Wallet.forge = {}
	_reset_shards()


func _test_select() -> void:
	Wallet.unlocked_chars = []
	get_tree().change_scene_to_file.call_deferred("res://scenes/character_select.tscn")
	await get_tree().scene_changed
	for f in 5:
		await get_tree().process_frame
	var cs = get_tree().current_scene
	var picked: int = cs._picked
	cs._on_tile_hover(5, true)
	_check("hovering a character shows its panel", cs._shown == 5, "%d" % cs._shown)
	cs._on_tile_hover(5, false)
	await get_tree().process_frame
	_check("...and moving off the tiles goes back to the last one clicked", cs._shown == picked, "%d vs %d" % [cs._shown, picked])
	var k := -1
	for i in cs.characters.size():
		if cs.characters[i]["id"] == "argyle_sock":
			k = i
	cs._show(k)
	await get_tree().process_frame
	_check("the Sock's weapon shows its forge cost: 5 shard crystals", cs._forge_style == "static" and cs._shard_row.get_child_count() == 5, "%s %d" % [cs._forge_style, cs._shard_row.get_child_count()])
	var lit := 0
	for ic in cs._shard_row.get_children():
		if ic is ShardIcon and ic.modulate.v > 0.9:
			lit += 1
	_check("none lit with no shards", lit == 0, "%d" % lit)
	Wallet.shards["dark"] = 2
	cs._refresh_forge()
	await get_tree().process_frame
	lit = 0
	var dark_lit := 0
	for ic in cs._shard_row.get_children():
		if ic is ShardIcon and ic.modulate.v > 0.9:
			lit += 1
			if ic.kind == "dark":
				dark_lit += 1
	_check("they light up one by one as you collect them", lit == 2 and dark_lit == 2, "%d lit" % lit)
	await get_tree().process_frame
	_check("not ready yet: no pulse, no plus signs", not cs._pluses.active, "")
	Wallet.shards["lightning"] = 3
	cs._refresh_forge()
	var grew := 0.0
	for f in 40:
		await get_tree().process_frame
		grew = maxf(grew, cs._weapon_icon.scale.x)
	_check("all collected: the weapon pulses under green plus signs", cs._pluses.active and grew > 1.03 and cs._pluses._plus.size() > 0, "x%.2f, %d pluses" % [grew, cs._pluses._plus.size()])
	cs.open_forge()
	await get_tree().process_frame
	var fm: ForgeMenu = cs._forge_menu
	_check("clicking it opens the forge with a Forge Weapon button", fm != null and not fm._btn.disabled and fm._btn.text == "Forge Weapon", "")
	_check("the forge shows what it will do", fm._next.text.contains("Damage +25%") and fm._next.text.contains("Attack rate +8%"), fm._next.text)
	_check("forging works", fm.do_forge() and Forge.level_of("static") == 1 and Wallet.shards["dark"] == 0 and Wallet.shards["lightning"] == 0, str(Wallet.shards))
	_check("...and the button greys out for level 2", fm._btn.disabled, "")
	# Short on shards: buy the missing ones with coins
	Wallet.coins = 0
	fm._refresh()
	_check("short on shards: a Buy button offers them for coins (greyed out when you can't afford it)", fm._buy.visible and fm._buy.disabled, fm._buy_label.text)
	Wallet.coins = 5000
	fm._refresh()
	_check("...10 missing shards for 1,500 coins", fm._buy_label.text.contains("10") and fm._buy_label.text.contains("1,500") and not fm._buy.disabled, fm._buy_label.text)
	_check("...buying them makes the next forge possible", fm.buy_missing() and Wallet.coins == 3500 and Forge.can_afford("static") and not fm._btn.disabled and not fm._buy.visible, "%d coins" % Wallet.coins)
	Wallet.coins = 0
	_reset_shards()
	fm._refresh()
	fm.closed.emit()
	await get_tree().process_frame
	_check("back on the character select: Forged +1, the level-2 cost (4 dark crystals, lightning x6)", cs._forge_label.text == "Forged +1"
		and cs._shard_row.get_child_count() == 6, "%s %d" % [cs._forge_label.text, cs._shard_row.get_child_count()])
	# Fire Wizard: 5 fire
	cs._show(0)
	await get_tree().process_frame
	var fire_ok: bool = cs._forge_style == "fire" and cs._shard_row.get_child_count() == 5
	for ic in cs._shard_row.get_children():
		fire_ok = fire_ok and ic is ShardIcon and ic.kind == "fire"
	_check("the Fire Wizard needs 5 fire shards", fire_ok, "")


func _test_run() -> void:
	Wallet.forge = {"fire": 2}
	Settings.selected_character = "fire_wizard"
	Settings.selected_map = "swamp"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	var main = get_tree().current_scene
	main.player.god_mode = true
	for f in 60 * 5:
		await get_tree().physics_frame
		if not main.intro:
			break
	main.xp_next = 1e12
	_check("forged +2: Fireballs deal +50% damage", is_equal_approx(main.stats.value("orb_damage"), 12.0 * 1.5), "%.1f" % main.stats.value("orb_damage"))
	_check("...and fire 16% faster", is_equal_approx(main.stats.value("orb_cooldown"), 0.9 / 1.16), "%.3f" % main.stats.value("orb_cooldown"))
	# every 5th Fireball hit explodes like a level 1 Blast Bomb
	var ws: WeaponSystem = main.weapons
	var em: EnemyManager = main.enemies
	ws.orb_t = 999.0
	for i in em.count:
		em.dead[i] = 1
	em._dead_count = em.count
	em.count = 0
	var p: Vector3 = main.player.global_position
	var target := em.spawn(EnemyManager.GRUNT, p + Vector3(5, 0, 0), 100000.0)
	var bystander := em.spawn(EnemyManager.GRUNT, p + Vector3(6.5, 0, 0.5), 100000.0)
	var kind := WeaponSystem.P_KINDS.find("fire")
	var h0: float = em.hp[bystander]
	for k in 5:
		var at: Vector3 = em.center_of(target)
		ws.spawn_projectile(at + Vector3(-1.5, 0, 0), Vector3(15, 0, 0), 0.3, 1.0, 0, kind)
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(0.3).timeout
	_check("forged Fireballs: every 5th hit explodes", ws.fire_hits >= 5 and h0 - em.hp[bystander] > 20.0, "%d hits, bystander -%.0f" % [ws.fire_hits, h0 - em.hp[bystander]])
	# Legendary card: another character's run uses the forged weapon
	Wallet.forge = {"fire": 4}
	Settings.selected_character = "ice_wizard"
	Wallet.unlocked_chars = ["ice_wizard"]
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	main = get_tree().current_scene
	_check("the Fireballs Legendary card is forged too (+100%, +1 shot)", main.db.defs.has("sig_fire")
		and is_equal_approx(main.stats.value("sig_fire_damage"), WeaponSystem.SIG_BASE["damage"] * 2.0)
		and is_equal_approx(main.stats.value("sig_fire_count"), WeaponSystem.SIG_BASE["count"] + 1.0), "%.1f / %.0f" % [main.stats.value("sig_fire_damage"), main.stats.value("sig_fire_count")])


## Every weapon forged to level 1, in a run as Thog (Big Club): the specials, worked out by
## style, so the other weapons are fired here as they would be from a Legendary card.
func _test_specials() -> void:
	Wallet.forge = {}
	for sty in WeaponSystem.STYLES:
		Wallet.forge[sty] = 1
	Settings.selected_character = "thog"
	Wallet.unlocked_chars = ["thog"]
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	var main = get_tree().current_scene
	main.player.god_mode = true
	for f in 60 * 5:
		await get_tree().physics_frame
		if not main.intro:
			break
	main.xp_next = 1e12
	var ws: WeaponSystem = main.weapons
	var em: EnemyManager = main.enemies
	ws.orb_t = 999.0
	_check("forged weapons have their specials on in the run", ws.special.size() == WeaponSystem.STYLES.size(), str(ws.special.keys()))
	var p: Vector3 = main.player.global_position
	var chest := p + Vector3(0, 0.9, 0)
	# Frost Shards: every 5th hit freezes
	var t: int = _fresh(em, p, [Vector3(5, 0, 0)])[0]
	ws.ice_hits = 0
	var frozen_at := -1
	for k in 5:
		_hit(ws, em, t, "ice")
		if frozen_at < 0 and em.freeze_t[t] > 0.0:
			frozen_at = k + 1
	_check("forged Frost Shards: the 5th hit freezes for 1.5 s", frozen_at == 5 and is_equal_approx(em.freeze_t[t], Forge.ICE_FREEZE_TIME), "frozen on hit %d" % frozen_at)
	# Shadow Bolts: every hit curses
	var ts: Array = _fresh(em, p, [Vector3(5, 0, 0), Vector3(5, 0, 3), Vector3(5, 0, -3), Vector3(-5, 0, 0)])
	var cursed := 0
	for e in ts:
		_hit(ws, em, e, "dark")
		cursed += 1 if em.curse_t[e] > 0.0 else 0
	_check("forged Shadow Bolts: every hit curses", cursed == ts.size(), "%d / %d" % [cursed, ts.size()])
	# Twin Daggers: bleeds deal double
	t = _fresh(em, p, [Vector3(5, 0, 0)])[0]
	_hit(ws, em, t, "dagger")
	_check("forged Twin Daggers: bleeds deal double", is_equal_approx(em.pct_f[t], WeaponSystem.BLEED_FRAC * 2.0), "%.3f" % em.pct_f[t])
	# Arcane Bolts (Merlin): triple damage to epics (elites) and bosses
	var ab: Array = _fresh(em, p, [Vector3(5, 0, 0), Vector3(-30, 0, 0)])
	em.epic[ab[1]] = 1
	var hn: float = em.hp[ab[0]]
	var he: float = em.hp[ab[1]]
	_hit(ws, em, ab[0], "arcane")
	_hit(ws, em, ab[1], "arcane")
	var dn: float = hn - em.hp[ab[0]]
	var de: float = he - em.hp[ab[1]]
	_check("Arcane Bolts deal triple damage to epics", dn > 0.0 and is_equal_approx(de / dn, WeaponSystem.ARCANE_EPIC), "normal -%.2f, epic -%.2f" % [dn, de])
	# Bosses in range are targeted before any other enemy (and only when in range)
	var bt: Array = _fresh(em, p, [Vector3(3, 0, 0), Vector3(0, 0, 3)])
	var boss: int = em.spawn(EnemyManager.BOSS, p + Vector3(16, 0, 0), 1.0)
	em._build_grid(p)
	var near1: PackedInt32Array = em.nearest_k(p, 20.0, 2)
	var near2: PackedInt32Array = em.nearest_k(p, 8.0, 1)
	_check("targeting: a boss in range comes first", near1.size() == 2 and near1[0] == boss, str(near1))
	_check("targeting: a boss out of range is ignored", near2.size() == 1 and near2[0] != boss, str(near2))
	_check("bouncing bolts jump to a boss in range first", ws._next_target(p, PackedInt32Array(), 20.0) == boss, "")
	em.dead[boss] = 1
	# Chain Lightning: chains to 2 more enemies
	var line := []
	for k in 12:
		line.append(Vector3(4.0 + 2.0 * k, 0, 0))
	var arcs := []
	for on in [false, true]:
		if on:
			ws.special["thunder"] = true
		else:
			ws.special.erase("thunder")
		ts = _fresh(em, p, line)
		ws._fire_chain(chest, 1.0, "orb")
		var n := 0
		for e in ts:
			n += 1 if em.hp[e] < em.hp_max[e] else 0
		arcs.append(n)
	_check("forged Chain Lightning: chains to 2 more enemies", arcs[1] == arcs[0] + Forge.THUNDER_JUMPS, "%d -> %d" % arcs)
	# Big Club (Thog's own weapon): smashes stun
	t = _fresh(em, p, [Vector3(3, 0, 0)])[0]
	ws._swing(p, 1.0, "orb", null, WeaponSystem.CLUB_REACH, WeaponSystem.CLUB_ARC, "club")
	_check("forged Big Club: smashes stun for 0.6 s", em.stun_t[t] > 0.0 and em.hp[t] < em.hp_max[t], "%.2f s" % em.stun_t[t])
	# Wail: enemies hit flee in fear
	t = _fresh(em, p, [Vector3(3, 0, 0)])[0]
	ws._swing(p, 1.0, "orb", null, WeaponSystem.WAIL_REACH, WeaponSystem.WAIL_ARC, "wail")
	_check("forged Wail: enemies hit flee in fear", em.fear_t[t] > 0.0, "%.2f s" % em.fear_t[t])
	# Tree Trunk: every 4th swing is a full 360 sweep (an enemy behind is only hit then)
	ts = _fresh(em, p, [Vector3(2, 0, 0), Vector3(-2.2, 0, 0)])
	ws.combo.erase("trunkorb")
	var behind_at := -1
	for k in 4:
		ws._swing(p, 1.0, "orb", null, WeaponSystem.TRUNK_REACH, WeaponSystem.TRUNK_ARC, "trunk")
		if behind_at < 0 and em.hp[ts[1]] < em.hp_max[ts[1]]:
			behind_at = k + 1
	_check("forged Tree Trunk: every 4th swing sweeps all the way round", behind_at == 4, "behind hit on swing %d" % behind_at)
	# Valkyrie Spear: every 3rd throw is a javelin
	_fresh(em, p, [Vector3(4, 0, 0)])
	ws.combo.erase("spearorb")
	var jav := WeaponSystem.P_KINDS.find("javelin")
	var jav_at := -1
	for k in 3:
		var before := _count_kind(ws, jav)
		ws._thrust(p, 1.0, "orb", null)
		if jav_at < 0 and _count_kind(ws, jav) > before:
			jav_at = k + 1
	_check("forged Valkyrie Spear: the 3rd throw is a javelin", jav_at == 3, "javelin on throw %d" % jav_at)
	# Static Cling: zaps hit 2 more enemies
	var ring := []
	for k in 10:
		ring.append(Vector3(cos(k * 0.6), 0, sin(k * 0.6)) * 5.0)
	ts = _fresh(em, p, ring)
	var z0 := ws.zaps
	ws._fire_static(chest, 1.0, "orb")
	var want := WeaponSystem.STATIC_TARGETS + maxi(0, ws._count("orb") - 1) + Forge.STATIC_TARGETS
	_check("forged Static Cling: zaps hit 2 more enemies", ws.zaps - z0 == want, "%d zaps, want %d" % [ws.zaps - z0, want])
	# Maraca Blasters: pulses knock enemies back
	t = _fresh(em, p, [Vector3(3, 0, 0)])[0]
	ws._fire_maracas(p, 1.0, "orb", null)
	_check("forged Maraca Blasters: pulses knock enemies back", em.kb_t[t] > 0.0, "kb %.2f s" % em.kb_t[t])
	# Acid Body: enemies it kills burst for 25% of their max HP within 3 m
	var r := ws.acid_radius("orb")
	ts = _fresh(em, p, [Vector3(r - 0.6, 0, 0), Vector3(r + 1.4, 0, 0)])
	em.hp[ts[0]] = 0.01
	em.hp_max[ts[0]] = 400.0
	var b0 := ws.acid_bursts
	var h1: float = em.hp[ts[1]]
	ws._fire_acid(p, 1.0, "orb", null)
	_check("forged Acid Body: its kills burst, hurting enemies nearby", ws.acid_bursts == b0 + 1 and h1 - em.hp[ts[1]] > 50.0,
		"%d bursts, bystander -%.0f" % [ws.acid_bursts - b0, h1 - em.hp[ts[1]]])


## Clear the field and spawn sturdy goblins at these offsets from `p` (indexed at once).
func _fresh(em: EnemyManager, p: Vector3, offsets: Array) -> Array:
	for i in em.count:
		em.dead[i] = 1
	em.count = 0
	em._dead_count = 0
	var out := []
	for o in offsets:
		out.append(em.spawn(EnemyManager.GRUNT, p + o, 100000.0))
	em._build_grid(p)
	return out


## One projectile of `kind` hitting enemy `e` right away.
func _hit(ws: WeaponSystem, em: EnemyManager, e: int, kind: String) -> void:
	ws.spawn_projectile(em.center_of(e), Vector3(0.01, 0, 0), 0.5, 1.0, 0, WeaponSystem.P_KINDS.find(kind))
	ws._update_projectiles(0.0)


func _count_kind(ws: WeaponSystem, kind: int) -> int:
	var n := 0
	for i in ws.pc:
		n += 1 if ws.p_style[i] == kind else 0
	return n


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		fails += 1
