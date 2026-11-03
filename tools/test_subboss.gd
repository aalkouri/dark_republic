extends Node
## Sub-bosses and waygates (the Swamp):
##   - a sub-boss arrives at 2:00, 25-35 m away on dry ground; its HP is above an epic's and far
##     below Thog's; it's no boss (no bosses-first targeting, spawns not reduced, no frogging);
##   - Mud Slam and Bog Bolt are each marked on the ground >= 0.8 s before they land, and hit a
##     player standing in them (damage + slow);
##   - killed, it drops an inactive waygate on flat, dry ground; near it the floating text says
##     "Needs another portal to activate" and E does nothing;
##   - a second one at 4:00 drops the second gate and both activate; E at one throws you to the
##     other (in front of it, facing away), one teleport per press; then 90 s of recharge (E does
##     nothing, the text counts down), then it works again;
##   - the minimap shows the sub-boss and the gates in their own colours;
##   - the gates go when the map boss dies; there's no sub-boss on the Forest.
##   godot --headless --fixed-fps 60 --path . res://tools/test_subboss.tscn

var fails := 0
var main: Node


func _ready() -> void:
	Wallet.persist = false
	Wallet.unlock_levels["map"] = 1   # the minimap is an Unlocks purchase
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	await _swamp()
	await _forest()
	_finish()


func _swamp() -> void:
	print("--- swamp")
	await _load("swamp")
	var em: EnemyManager = main.enemies
	var sb: SubBosses = main.sub_bosses
	var pl: Player = main.player
	_check("swamp: sub-bosses are on, at 2:00 and 4:00", sb.enabled() and sb.times == [120.0, 240.0], str(sb.times))
	main.run_time = 115.0
	await _secs(1.0)
	_check("no sub-boss before 2:00", sb.spawned == 0, "")
	main.run_time = 119.8
	await _secs(0.5)
	_check("a sub-boss arrives at 2:00", sb.spawned == 1 and sb.bosses.size() == 1, "%d" % sb.spawned)
	if sb.bosses.is_empty():
		return
	var b: SubBoss = sb.bosses[0]
	var i := b.row()
	var d := MapBoss.flat_dist(em.pos[i], pl.global_position)
	_check("...25-35 m away, on dry ground", d > 24.0 and d < 36.5 and not main.water.in_pool_xz(em.pos[i].x, em.pos[i].z), "%.1f m" % d)
	var hpm: float = main.hp_mult()
	var epic_hp := em.t_hp[EnemyManager.GRUNT] * hpm * EnemyManager.EPIC_HP
	var thog_hp := EnemyManager.THOG_HP * (1.0 + 8.0 * 0.35 + 64.0 * 0.04)
	_check("its HP is well above an epic's and far below Thog's", em.hp_max[i] > epic_hp * 4.0 and em.hp_max[i] < thog_hp * 0.1, "%.0f (epic %.0f, Thog %.0f)" % [em.hp_max[i], epic_hp, thog_hp])
	_check("it's a big crowd row of its own type, not a boss", em.typ[i] == EnemyManager.SUB_BOSS and not em.is_boss(i) and em.t_scale[em.typ[i]] >= 2.0 and em.type_names[em.typ[i]] == "Bog Shaman", em.type_names[em.typ[i]])
	_check("spawns aren't reduced for it (main.boss_up() is the real boss only)", not main.boss_up(), "")
	em.frog(i, 5.0)
	_check("it can't be polymorphed", em.frog_t[i] <= 0.0, "")
	var mm: Minimap = main.hud.minimap
	mm.refresh()
	await _frame()
	_check("minimap: the sub-boss has its own blip", mm.shown["subbosses"].size() == 1 and mm.shown["bosses"].is_empty(), str(mm.shown["subbosses"]))

	# --- Mud Slam
	_clear(em)
	pl.god_mode = false
	var bp := em.pos[i]
	_put(bp + Vector3(3.0, 0, 0))
	b.cd_slam = 99.0
	b.cd_bolt = 99.0
	await _secs(0.2)
	b.cd_slam = 0.0
	var t0 := -1.0
	var hit_t := -1.0
	var h0 := b.counts["hits"] as int
	var hp0 := pl.hp
	var tt := 0.0
	for f in 60 * 3:
		await _frame()
		tt += 1.0 / 60.0
		pl.invuln = 0.0
		if t0 < 0.0 and b.casting == "slam":
			t0 = tt
		if b.counts["hits"] > h0:
			hit_t = tt
			break
		_put_rel(b, Vector3(3.0, 0, 0))   # stay in the circle
	_check("Mud Slam: marked on the ground >= 0.8 s before it lands", t0 >= 0.0 and hit_t - t0 >= 0.8 and b.counts["slam_warn"] >= 0.8, "warn %.2f s, landed after %.2f s" % [b.counts["slam_warn"], hit_t - t0])
	_check("...and it hits you standing in it (damage + slow)", hit_t > 0.0 and pl.hp < hp0 and pl.slow_t > 0.0, "hp %.0f -> %.0f, slow %.1f" % [hp0, pl.hp, pl.slow_t])

	# --- Bog Bolt
	await _secs(0.3)
	pl.hp = pl.stats.value("max_hp")
	i = b.row()
	_put_rel(b, Vector3(0, 0, 12.0))
	b.cd_slam = 99.0
	b.cd_bolt = 0.0
	t0 = -1.0
	hit_t = -1.0
	h0 = b.counts["hits"]
	hp0 = pl.hp
	tt = 0.0
	for f in 60 * 3:
		await _frame()
		tt += 1.0 / 60.0
		pl.invuln = 0.0
		if t0 < 0.0 and b.casting == "bolt":
			t0 = tt
		if b.counts["hits"] > h0:
			hit_t = tt
			break
	_check("Bog Bolt: its lane is marked >= 0.8 s before it lands", t0 >= 0.0 and hit_t - t0 >= 0.8 and b.counts["bolt_warn"] >= 0.8, "warn %.2f s, landed after %.2f s" % [b.counts["bolt_warn"], hit_t - t0])
	_check("...and it hits you standing in the lane", hit_t > 0.0 and pl.hp < hp0, "hp %.0f -> %.0f" % [hp0, pl.hp])
	_check("the sub-boss stood still while casting", b.counts["slams"] >= 1 and b.counts["bolts"] >= 1, str(b.counts))
	pl.god_mode = true

	# --- the first gate
	var kills0: int = main.elites_killed
	em.damage(b.row(), 1.0e9)
	await _secs(0.5)
	_check("killing it drops a waygate", sb.gates.size() == 1 and main.elites_killed == kills0 + 1, "%d gates" % sb.gates.size())
	if sb.gates.size() != 1:
		return
	var g1: Waygate = sb.gates[0]
	var gp := g1.global_position
	_check("...on flat, dry ground", _flat(gp) and not main.water.in_pool_xz(gp.x, gp.z), str(gp))
	_check("...inactive", g1.state == "inactive" and not g1.is_active(), g1.state)
	await _secs(1.5)
	_put(gp + g1.front() * 10.0)
	await _secs(0.2)
	_check("far away there's no floating text", not g1.text_visible(), "")
	_put(g1.arrival())
	await _secs(0.2)
	_check("near it: \"Needs another portal to activate\"", g1.text_visible() and g1._text.text == tr("Needs another portal to activate") and not g1.prompt.visible, g1._text.text)
	await _press_e()
	_check("...and E does nothing", sb.teleports == 0, "")

	# --- the second sub-boss and gate
	main.run_time = 239.8
	await _secs(0.5)
	_check("a second sub-boss arrives at 4:00", sb.spawned == 2 and sb.bosses.size() == 1, "%d" % sb.spawned)
	if sb.bosses.is_empty():
		return
	var b2: SubBoss = sb.bosses[0]
	_check("the first gate stays inactive while it lives", g1.state == "inactive", g1.state)
	em.damage(b2.row(), 1.0e9)
	await _secs(1.5)
	_check("killing it drops the second gate and both activate", sb.gates.size() == 2 and sb.gates[0].is_active() and sb.gates[1].is_active(), "%d gates" % sb.gates.size())
	if sb.gates.size() != 2:
		return
	var g2: Waygate = sb.gates[1]
	_check("the gates are apart", MapBoss.flat_dist(g1.global_position, g2.global_position) > 8.0, "%.1f m" % MapBoss.flat_dist(g1.global_position, g2.global_position))
	mm.refresh()
	await _frame()
	var wcols := {}
	for w in mm.shown["waygates"]:
		wcols[w["state"]] = w["col"]
	_check("minimap: both gates shown, in the active colour", mm.shown["waygates"].size() == 2 and wcols.get("active") == Minimap.WAYGATE_COLS[1], str(mm.shown["waygates"]))

	# --- teleport
	_clear(em)
	_put(g1.arrival())
	await _secs(0.3)
	_check("near an active gate: Press E", g1.prompt.visible and not g1.text_visible(), "")
	for k in 6:   # a few goblins round where you'll land
		em.spawn(EnemyManager.GRUNT, g2.arrival() + Vector3(cos(k) * 1.5, 0, sin(k) * 1.5), 1.0)
	pl.bot_activate = true
	for f in 12:   # E held for a while: one teleport only
		await _frame()
	pl.bot_activate = false
	await _frame()
	var at := pl.global_position
	var f2 := g2.front()
	var look := Vector3(-sin(pl.cam_yaw), 0, -cos(pl.cam_yaw))
	_check("E teleports you to the other gate, once", sb.teleports == 1 and MapBoss.flat_dist(at, g2.arrival()) < 1.5, "%d teleports, %.1f m from the arrival" % [sb.teleports, MapBoss.flat_dist(at, g2.arrival())])
	_check("...landing in front of it, facing away", look.dot(f2) > 0.95, "%.2f" % look.dot(f2))
	var crowd := 0
	for k in em.count:
		if not em.dead[k] and em.typ[k] == EnemyManager.GRUNT and MapBoss.flat_dist(em.pos[k], g2.arrival()) < 3.0:
			crowd += 1
	await _secs(0.4)
	crowd = 0
	for k in em.count:
		if not em.dead[k] and em.typ[k] == EnemyManager.GRUNT and MapBoss.flat_dist(em.pos[k], g2.arrival()) < 3.0:
			crowd += 1
	_check("...and the goblins there are shoved back", crowd <= 1, "%d still within 3 m" % crowd)
	_check("both gates recharge for 90 s", g1.state == "cooldown" and g2.state == "cooldown" and absf(g2.cooldown_left - 90.0) < 1.5, "%s %s %.1f" % [g1.state, g2.state, g2.cooldown_left])
	_put(g2.arrival())
	await _secs(0.2)
	_check("...the text counts down (Recharging 1:2x), no Press E", g2.text_visible() and g2._text.text.begins_with("Recharging 1:") and g2._text.text == tr("Recharging %d:%02d") % [int(ceilf(g2.cooldown_left)) / 60, int(ceilf(g2.cooldown_left)) % 60] and not g2.prompt.visible, g2._text.text)
	await _press_e()
	_check("...E does nothing while recharging", sb.teleports == 1, "%d" % sb.teleports)
	mm.refresh()
	await _frame()
	_check("minimap: recharging gates in their own colour", mm.shown["waygates"].size() == 2 and (mm.shown["waygates"][0]["col"] as Color) == Minimap.WAYGATE_COLS[2], "")
	# wait it out (the real 90 s)
	for s in 87:
		await _secs(1.0)
		_clear(em)
		_put(g2.arrival())
	await _press_e()
	_check("at 88 s it's still recharging", sb.teleports == 1 and g2.state == "cooldown", "%s %.1f" % [g2.state, g2.cooldown_left])
	await _secs(2.5)
	_check("after 90 s both gates glow again", g1.is_active() and g2.is_active(), "%s %s" % [g1.state, g2.state])
	await _press_e()
	_check("...and E works again (back to the first gate)", sb.teleports == 2 and MapBoss.flat_dist(pl.global_position, g1.arrival()) < 1.5, "%d" % sb.teleports)

	# --- the map boss
	main.run_time = main.THOG_TIME + 0.1
	await _secs(0.5)
	_check("Thog arrives; the gates are still there", main.thog != null and sb.gates.size() == 2, "")
	if main.thog == null:
		return
	em.damage(main.thog.row(), 1.0e9)
	await _secs(2.0)
	_check("when the map boss dies the gates go", sb.gates.is_empty() and get_tree().get_nodes_in_group("waygate").is_empty() and not is_instance_valid(g1) and not is_instance_valid(g2), "%d left" % get_tree().get_nodes_in_group("waygate").size())
	get_tree().paused = false


func _forest() -> void:
	print("--- forest")
	await _load("forest")
	var sb: SubBosses = main.sub_bosses
	main.run_time = 119.0
	await _secs(1.5)
	main.run_time = 239.0
	await _secs(1.5)
	var n := 0
	var em: EnemyManager = main.enemies
	for k in em.count:
		if em.typ[k] == EnemyManager.SUB_BOSS:
			n += 1
	_check("forest: no sub-bosses (only the Swamp has them for now)", not sb.enabled() and sb.spawned == 0 and n == 0, "%d" % sb.spawned)
	get_tree().paused = false


# ------------------------------------------------------------------ helpers

func _press_e() -> void:
	main.player.bot_activate = true
	await _frame()
	main.player.bot_activate = false
	await _frame()


func _put(p: Vector3) -> void:
	main.player.global_position = Vector3(p.x, main.water.ground_height(p.x, p.z) + 0.3, p.z)
	main.player.velocity = Vector3.ZERO


func _put_rel(b: SubBoss, off: Vector3) -> void:
	var i := b.row()
	if i >= 0:
		_put(main.enemies.pos[i] + off)


func _flat(p: Vector3) -> bool:
	for k in 8:
		var a := TAU * k / 8.0
		if absf(main.water.ground_height(p.x + cos(a) * 2.0, p.z + sin(a) * 2.0) - p.y) > 0.6:
			return false
	return true


func _clear(em: EnemyManager) -> void:
	for k in em.count:
		if em.dead[k] == 0 and em.typ[k] != EnemyManager.TROLL and em.typ[k] != EnemyManager.SUB_BOSS:
			em.dead[k] = 1
			em._dead_count += 1


func _load(map: String) -> void:
	get_tree().paused = false
	Settings.selected_map = map
	Settings.selected_character = "fire_wizard"
	Settings.game_mode = "classic"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	for f in 60 * 15:   # the entrance
		await get_tree().physics_frame
		if not main.intro:
			break
	main.player.god_mode = true
	main._next_swarm = 1.0e9
	main.xp_next = 1.0e12


func _secs(s: float) -> void:
	for f in int(s * 60):
		await _frame()


func _frame() -> void:
	await get_tree().physics_frame
	if main != null and is_instance_valid(main) and main.state == "levelup":
		main.choose_upgrade(0)


func _finish() -> void:
	get_tree().paused = false
	Settings.selected_map = "swamp"
	Wallet.bosses_defeated = []
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		fails += 1
