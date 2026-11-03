extends Node
## After the boss (every map): killing him doesn't end the run.
##   - no end screen; the monsters stop coming (no new enemies over 5 s, a swarm due included);
##   - his shards lie on the ground round the corpse: as many as rolled, only the map's kinds,
##     on good ground; walking over one banks it (Wallet and the end screen's count);
##   - a portal rises where it should (the Desert: on the causeway in front of the Sphinx; the
##     Castle: near the middle of the keep, on open floor you can walk to; elsewhere near the
##     start), on flat, dry ground; the HUD says PORTAL OPEN and points to it;
##   - walking into it wins the run (end screen, "won", boss named) and banks the shards left on
##     the ground.
##   godot --headless --path . --fixed-fps 60 res://tools/test_portal.tscn

const MAPS := ["swamp", "desert", "castle", "graveyard", "forest", "caldera"]

var fails := 0
var main: Node


func _ready() -> void:
	Wallet.persist = false
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--maps="):
			only = a.split("=")[1]
	for m in MAPS:
		if only == "" or m in only.split(","):
			await _map(m)
	_finish()


func _map(map: String) -> void:
	print("--- ", map)
	Wallet.bosses_defeated = []
	await _load(map)
	var em: EnemyManager = main.enemies
	main.run_time = main.THOG_TIME + 0.1
	await _secs(0.5)
	var boss: Node = main.thog if map == "swamp" else main.map_boss
	_check("%s: the boss is here" % map, boss != null and boss.row() >= 0, "")
	if boss == null or boss.row() < 0:
		return
	await _secs(0.5)
	_clear(em)
	var bp: Vector3 = em.pos[boss.row()]
	_away_from(bp, 22.0)
	await _secs(0.1)
	var before: Dictionary = Wallet.shards.duplicate()
	var total_before := _sum(before)
	em.damage(boss.row(), 1.0e9)
	await _secs(0.2)
	var aft: BossAftermath = main.aftermath
	var rolled: Dictionary = aft.drops.remaining()
	var n := _sum(rolled)
	var kinds_ok := true
	for k in rolled:
		if not k in Wallet.map_shards(map):
			kinds_ok = false
	_check("%s: killing him doesn't end the run" % map, main.state == "playing" and not main.boss_won and main.boss_down, main.state)
	var standing := 0
	for c in main.chests.chests:
		if is_instance_valid(c) and not c.gone:
			standing += 1
	_check("%s: every chest on the map vanishes when he falls" % map, standing == 0 and main.chests.chests.size() > 0, "%d still standing of %d" % [standing, main.chests.chests.size()])
	_check("%s: he drops 1-5 shard crystals, only the map's kinds %s" % [map, str(Wallet.map_shards(map))], n >= 1 and n <= 5 and kinds_ok, str(rolled))
	_check("%s: nothing banked yet" % map, _sum(Wallet.shards) == total_before and main.shards_won.is_empty(), str(Wallet.shards))
	var fall: Vector3 = main._boss_fall_point() if is_instance_valid(boss) else bp
	await _secs(1.3)
	var near := true
	var dry := true
	for p in aft.drops.positions():
		if Vector2(p.x - aft.drops.origin.x, p.z - aft.drops.origin.z).length() > 9.0:
			near = false
		if not aft._good_ground(p):
			dry = false
	var from_corpse: bool = Vector2(aft.drops.origin.x - fall.x, aft.drops.origin.z - fall.z).length() < 1.0 or not aft._good_ground(fall)
	_check("%s: they scatter on the ground round the corpse (or the nearest good ground)" % map, near and from_corpse and aft.drops.count() == n, "%s from %s, fell at %s" % [str(aft.drops.positions()), str(aft.drops.origin), str(fall)])
	_check("%s: ...on good ground (no walls, water or lava)" % map, dry, "")
	# no more monsters, even when a swarm is due
	var uid0: int = em._next_uid
	main._next_swarm = main.run_time + 0.5
	main._spawn_budget = 50.0
	await _secs(5.0)
	_check("%s: the monsters stop coming (no new enemies in 5 s, a swarm due)" % map, em._next_uid == uid0, "%d -> %d" % [uid0, em._next_uid])
	# the portal
	for f in 60 * 4:
		if aft.portal != null and aft.portal.is_open():
			break
		await _frame()
	var pt: BossPortal = aft.portal
	_check("%s: a portal opens a few seconds after he falls" % map, pt != null and pt.is_open(), "")
	if pt == null:
		return
	var pp := pt.global_position
	_check("%s: the HUD says PORTAL OPEN (the clock makes way) and points to it" % map, aft._label.visible and not main.hud.timer_label.visible and not aft.marker().is_empty(), "")
	_check("%s: the minimap can find it (\"portal\" group)" % map, get_tree().get_first_node_in_group("portal") == pt, "")
	match map:
		"desert":
			var front_z := DesertBuilder.SPHINX_AT.y + DesertBuilder.PLINTH.y
			_check("desert: in front of the Sphinx, on the causeway", absf(pp.x) < DesertBuilder.CAUSEWAY_W and pp.z > front_z and pp.z < front_z + 20.0, str(pp))
		"castle":
			_check("castle: near the middle of the keep", Vector2(pp.x, pp.z).length() < 14.0, str(pp))
			_check("castle: on open floor you can walk to from where you stand", not CastleNav.current.is_blocked(pp.x, pp.z) and pt.steps_from(main.player.global_position) > 0, str(pt.steps_from(main.player.global_position)))
		"caldera":
			var pref: Vector2 = BossPortal.preferred("caldera")["at"]
			_check("caldera: beside the great lava pool, off the lava", Vector2(pp.x - pref.x, pp.z - pref.y).length() < 20.0 and not CalderaBuilder.near_lava(pp.x, pp.z, 2.0), str(pp))
		_:
			_check("%s: near where the run began" % map, Vector2(pp.x, pp.z).length() < 40.0, str(pp))
	var flat := true
	for k in 8:
		var a := TAU * k / 8.0
		if absf(main.water.ground_height(pp.x + cos(a) * 3.0, pp.z + sin(a) * 3.0) - pp.y) > 0.6:
			flat = false
	_check("%s: on flat, dry ground" % map, flat and not main.water.in_pool_xz(pp.x, pp.z) and absf(pp.y - main.water.ground_height(pp.x, pp.z)) < 0.05, str(pp))
	# walk over one shard
	var ps: Array = aft.drops.positions()
	var got_before := _sum(Wallet.shards)
	if not ps.is_empty():
		var s0: Vector3 = ps[0]
		main.player.global_position = Vector3(s0.x + 0.6, main.water.ground_height(s0.x, s0.z) + 0.3, s0.z)
		main.player.velocity = Vector3.ZERO
		await _secs(0.4)
	_check("%s: walking over a shard picks it up and banks it" % map, aft.drops.count() <= n - 1 and _sum(Wallet.shards) >= got_before + 1 and _sum(main.shards_won) >= 1, "%d left, wallet %d -> %d" % [aft.drops.count(), got_before, _sum(Wallet.shards)])
	var left := aft.drops.count()
	# walk into the portal (from the front)
	var front := pt.global_transform.basis.z
	var start := pp + front * 5.0
	main.player.global_position = Vector3(start.x, main.water.ground_height(start.x, start.z) + 0.4, start.z)
	main.player.velocity = Vector3.ZERO
	main.player.cam_yaw = atan2(front.x, front.z)   # looking at the portal
	main.player.bot = true
	main.player.bot_move = Vector2(0, -1)
	for f in 60 * 8:
		await _frame()
		if main.state == "won":
			break
	main.player.bot_move = Vector2.ZERO
	_check("%s: walking into it completes the map (end screen, won)" % map, main.state == "won" and main.boss_won and main.hud.end_root.visible, main.state)
	_check("%s: the end screen says YOU WON!" % map, main.hud.end_title.text == tr("YOU WON!"), main.hud.end_title.text)
	var btns := main.hud.end_root.find_children("*", "Button", true, false).filter(func(b): return (b as Button).is_visible_in_tree())
	_check("%s: the end screen's only button is Continue" % map, btns.size() == 1 and btns[0] == main.hud.end_continue, str(btns.map(func(b): return b.text)))
	_check("%s: shards left on the ground are banked on the way in (%d)" % [map, left], aft.drops.count() == 0 and _sum(Wallet.shards) == total_before + n and _sum(main.shards_won) == n, "wallet %d -> %d, rolled %d, won %s" % [total_before, _sum(Wallet.shards), n, str(main.shards_won)])
	_check("%s: the defeat was recorded (unlocks)" % map, Wallet.has_defeated(main.boss_id) and main.first_boss_kill, str(Wallet.bosses_defeated))
	get_tree().paused = false


# ------------------------------------------------------------------ helpers

func _away_from(bp: Vector3, d: float) -> void:
	var p: Vector3 = main.player.global_position
	if Vector2(p.x - bp.x, p.z - bp.z).length() >= d:
		return
	for k in 16:
		var a := TAU * k / 16.0
		var q := bp + Vector3(cos(a), 0, sin(a)) * d
		if absf(q.x) > 200.0 or absf(q.z) > 200.0:
			continue
		if CastleNav.current != null and CastleNav.current.is_blocked(q.x, q.z):
			continue
		if main.water.in_pool_xz(q.x, q.z) or (CalderaBuilder.active and CalderaBuilder.near_lava(q.x, q.z, 2.0)):
			continue
		main.player.global_position = Vector3(q.x, main.water.ground_height(q.x, q.z) + 0.5, q.z)
		main.player.velocity = Vector3.ZERO
		return


func _clear(em: EnemyManager) -> void:
	for k in em.count:
		if em.dead[k] == 0 and em.typ[k] != EnemyManager.TROLL:
			em.dead[k] = 1
			em._dead_count += 1


func _sum(d: Dictionary) -> int:
	var t := 0
	for k in d:
		t += int(d[k])
	return t


func _load(map: String) -> void:
	get_tree().paused = false
	Settings.selected_map = map
	Settings.selected_character = "fire_wizard"
	Settings.game_mode = "classic"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	for f in 60 * 15:   # the entrance (meteor / castle doors)
		await get_tree().physics_frame
		if not main.intro:
			break
	main.player.god_mode = true


func _secs(s: float) -> void:
	for f in int(s * 60):
		await _frame()


## One physics frame; a level-up (the boss's XP) is taken at once so the run carries on.
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
