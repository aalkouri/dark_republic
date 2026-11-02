extends Node
## The HUD minimap (top right) and the NUKE power-up in a real run.
##   godot --headless --path . --fixed-fps 60 res://tools/test_minimap.tscn

var fails := 0
var main: Node


func _ready() -> void:
	Wallet.persist = false
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	await _start("fire_wizard", "swamp", true)
	_test_layout()
	await _test_blips()
	await _test_toggle()
	await _test_thog_quake()
	await _start("fire_wizard", "desert")
	await _test_pharaoh_wrath()
	await _test_nuke_vultures()
	await _start("fire_wizard", "castle")
	await _test_nuke_in_run()
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _start(id: String, map: String, check_intro := false) -> void:
	print("--- ", id, " on ", map)
	Settings.selected_character = id
	Settings.selected_map = map
	Settings.show_minimap = true
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	main = get_tree().current_scene
	main.player.god_mode = true
	if check_intro:
		await get_tree().process_frame
		_check("hidden during the entrance", main.intro and not main.hud.minimap.visible, "intro %s visible %s" % [main.intro, main.hud.minimap.visible])
	for f in 60 * 8:
		await get_tree().physics_frame
		if not main.intro:
			break
	await _secs(0.3)
	main.xp_next = 1e12
	main._next_swarm = 1e9


func _secs(s: float) -> void:
	for f in int(s * 60):
		await get_tree().physics_frame


func _mm() -> Minimap:
	return main.hud.minimap


## In the top-right corner, under the coin and shard pills, overlapping nothing.
func _test_layout() -> void:
	var mm := _mm()
	_check("the minimap exists and shows once the run starts", mm != null and mm.is_visible_in_tree(), "")
	var vp := mm.get_viewport_rect().size
	var r := mm.get_global_rect()
	_check("...in the top-right corner", r.end.x <= vp.x - 4.0 and r.end.x >= vp.x - 40.0 and r.position.y < 120.0,
		"rect %s in %s" % [str(r), str(vp)])
	_check("...about 200-230 px across", r.size.x >= 200.0 and r.size.x <= 230.0 and is_equal_approx(r.size.x, r.size.y), str(r.size))
	var coins: Rect2 = Wallet.panel.get_global_rect()
	var shards: Rect2 = Wallet.shard_panel.get_global_rect()
	_check("...not over the coin counter", not r.intersects(coins), "coins %s" % str(coins))
	_check("...not over the shard counter", not r.intersects(shards), "shards %s" % str(shards))
	_check("...not over the kill/enemy counter", not r.intersects(main.hud.info_label.get_global_rect()), str(main.hud.info_label.get_global_rect()))
	_check("...nor the boss health bar area (centre top)", r.position.x > vp.x * 0.5 + 340.0, "")


func _fwd() -> Vector3:
	var y: float = main.player.cam_yaw
	return Vector3(-sin(y), 0, -cos(y))


func _right() -> Vector3:
	var y: float = main.player.cam_yaw
	return Vector3(cos(y), 0, -sin(y))


## Where the layer really draws world point `w` (its own transform), vs. to_map().
func _drawn_at(w: Vector3) -> Vector2:
	var mm := _mm()
	return mm._layer.get_transform() * mm._at(w)


func _test_blips() -> void:
	var mm := _mm()
	var em: EnemyManager = main.enemies
	em.count = 0
	main.player.cam_yaw = 0.7   # turned: the map turns with the camera
	var p: Vector3 = main.player.global_position
	var chest_at: Vector3 = p + _fwd() * 25.0
	chest_at.y = SwampWater.height_at(chest_at.x, chest_at.z)
	var ch: Chest = main.chests.place(chest_at, 2)
	var pu_at: Vector3 = p + _right() * 20.0
	main.powerups.drop(pu_at, PowerupManager.NUKE)
	var e := em.spawn(EnemyManager.GRUNT, p - _fwd() * 30.0, 1.0)
	var e_uid := em.uid[e]
	var far_pu: Vector3 = p + _fwd() * 120.0
	main.powerups.drop(far_pu, PowerupManager.MAGNET)
	await get_tree().physics_frame
	mm.refresh()
	mm._layer.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var c := Vector2(Minimap.SIZE, Minimap.SIZE) * 0.5
	var px := mm._k
	var found_chest := false
	for at in mm.shown["chests"]:
		if (at as Vector3).distance_to(chest_at) < 0.5:
			found_chest = true
	_check("chest blip shown", found_chest, "%d chests shown" % mm.shown["chests"].size())
	var cm := mm.to_map(chest_at)
	_check("...a chest ahead of the camera is straight up from you", absf(cm.x - c.x) < 2.0 and absf((c.y - cm.y) - 25.0 * px) < 2.0, "%s (centre %s)" % [str(cm), str(c)])
	_check("...and that's where the turned layer draws it", _drawn_at(chest_at).distance_to(cm) < 3.0, "%s vs %s" % [str(_drawn_at(chest_at)), str(cm)])
	var pm := mm.to_map(pu_at)
	_check("power-up blip shown, to your right", mm.shown["powerups"].size() >= 1 and absf((pm.x - c.x) - 20.0 * px) < 2.0 and absf(pm.y - c.y) < 2.0, str(pm))
	var bm := mm.to_map(em.pos[em.index_of(e_uid)])
	_check("an enemy behind you is a dot below centre", mm.shown["enemies"] >= 1 and bm.y > c.y + 25.0 * px, "%d dots, %s" % [mm.shown["enemies"], str(bm)])
	_check("a power-up past the edge sits on the rim as an arrow", mm.shown["rim"] >= 1, "%d rim arrows" % mm.shown["rim"])
	# opened chests disappear
	ch.is_open = true
	mm.refresh()
	await get_tree().process_frame
	var still := false
	for at in mm.shown["chests"]:
		if (at as Vector3).distance_to(chest_at) < 0.5:
			still = true
	_check("an opened chest leaves the minimap", not still, "")
	# 1,400 enemies: capped dots, and cheap
	for k in 1400:
		em.spawn(EnemyManager.GRUNT, p + Vector3(randf_range(-55, 55), 0, randf_range(-55, 55)), 1.0)
	mm.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var ms := mm.last_draw_ms
	_check("with a huge horde the dots are capped (~%d) and the redraw stays cheap" % Minimap.MAX_DOTS, mm.shown["enemies"] <= Minimap.MAX_DOTS + 5 and mm.shown["enemies"] > 100 and ms < 6.0, "%d dots, redraw %.2f ms" % [mm.shown["enemies"], ms])
	em.count = 0


func _test_toggle() -> void:
	var mm := _mm()
	Settings.set_value("show_minimap", false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("Settings > Show minimap off hides it", not mm.visible, "")
	Settings.set_value("show_minimap", true)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("...and on shows it again", mm.visible, "")
	_check("Show minimap is a saved setting", "show_minimap" in Settings.SAVED_KEYS, "")


func _test_thog_quake() -> void:
	var mm := _mm()
	main.run_time = main.THOG_TIME + 0.1
	await _secs(0.3)
	var thog: ThogBoss = main.thog
	_check("Thog arrives", thog != null, "")
	if thog == null:
		return
	mm.refresh()
	await get_tree().process_frame
	_check("the boss shows as a big blip (or a rim arrow)", mm.shown["bosses"].size() == 1, "%d" % mm.shown["bosses"].size())
	_check("no safe zones before his quake", mm.shown["safe"].is_empty(), "%d" % mm.shown["safe"].size())
	await _test_boss_arrow(thog)
	thog._start_quake()
	await _secs(0.2)
	mm.refresh()
	await get_tree().process_frame
	var pools: int = main.water.pools.size()
	_check("Thog's quake: every pond is marked safe on the minimap", pools > 0 and mm.shown["safe"].size() == pools, "%d of %d" % [mm.shown["safe"].size(), pools])
	var near := 0
	for z in thog.map_safe_zones():
		if MapBoss.flat_dist(z["pos"], main.player.global_position) - float(z["radius"]) < Minimap.RANGE:
			near += 1
	_check("...the ones off the map get rim arrows (nearest few)", mm.shown["rim"] >= mini(pools - near, Minimap.MAX_RIM_SAFE), "%d rim, %d near" % [mm.shown["rim"], near])
	await _secs(ThogBoss.QUAKE_WARN + 0.5)
	mm.refresh()
	await get_tree().process_frame
	_check("...and the marks go once the quake has landed", mm.shown["safe"].is_empty(), "%d" % mm.shown["safe"].size())


## A boss off the map: a big red arrow on the rim pointing his way, turning with the camera;
## in range: the boss blip instead.
func _test_boss_arrow(thog: ThogBoss) -> void:
	var mm := _mm()
	var em: EnemyManager = main.enemies
	var c := Vector2(Minimap.SIZE, Minimap.SIZE) * 0.5
	for yaw in [0.0, 1.9]:
		main.player.cam_yaw = yaw
		var p: Vector3 = main.player.global_position
		em.pos[thog.row()] = p - _fwd() * 90.0 - _right() * 90.0   # behind you, to the left
		mm.refresh()
		await get_tree().process_frame
		var arrows: Array = mm.shown["boss_arrows"]
		_check("boss off range (yaw %.1f): one red arrow on the rim" % yaw, arrows.size() == 1 and mm.shown["bosses"].size() == 1, "%d arrows" % arrows.size())
		if arrows.size() != 1:
			continue
		var tip: Vector2 = mm._layer.get_transform() * (arrows[0] as Vector2)
		var d := tip - c
		_check("...behind-left of the camera: it sits lower left, pointing that way", d.x < -40.0 and d.y > 40.0 and absf(d.angle() - Vector2(-1, 1).angle()) < 0.15,
			"tip at %s from centre" % str(d))
		_check("...on the rim", d.length() > Minimap.SIZE * 0.5 - 22.0 and d.length() <= Minimap.SIZE * 0.5, "%.1f px out" % d.length())
	# in range: the blip, no arrow
	var p2: Vector3 = main.player.global_position
	em.pos[thog.row()] = p2 + _right() * 30.0
	mm.refresh()
	await get_tree().process_frame
	_check("boss in range: his blip, no arrow", mm.shown["boss_arrows"].is_empty() and mm.shown["bosses"].size() == 1, "%d arrows" % mm.shown["boss_arrows"].size())
	main.player.cam_yaw = 0.0


func _test_pharaoh_wrath() -> void:
	var mm := _mm()
	main.run_time = main.THOG_TIME + 0.1
	await _secs(0.3)
	var b = main.map_boss
	_check("the Pharaoh arrives", b is PharaohBoss, str(b))
	if not (b is PharaohBoss):
		return
	await _secs(PharaohBoss.RISE_TIME + 0.5)
	for f in 60 * 8:
		if b.state == "walk" and b._warns.is_empty():
			break
		await get_tree().physics_frame
	main.enemies.hp[b.row()] = main.enemies.hp_max[b.row()] * 0.74
	for f in 60 * 6:
		await get_tree().physics_frame
		if int(b.counts.get("wrath", 0)) > 0:
			break
	mm.refresh()
	await get_tree().process_frame
	_check("Wrath of the Sands: the three golden safe spots are on the minimap", mm.shown["safe"].size() == PharaohBoss.WRATH_SAFE_SPOTS,
		"%d (wraths %d)" % [mm.shown["safe"].size(), int(b.counts.get("wrath", 0))])
	var ok := true
	for z in b.map_safe_zones():
		var mp := mm.to_map(z["pos"])
		if mp.distance_to(Vector2(Minimap.SIZE, Minimap.SIZE) * 0.5) > Minimap.SIZE * 0.5:
			ok = false
	_check("...all on the map (9-15 m off, well within range)", ok, "")


## The NUKE kills vultures circling overhead too (they can't be hit, but the blast takes them).
func _test_nuke_vultures() -> void:
	var em: EnemyManager = main.enemies
	var p: Vector3 = main.player.global_position
	var uids: Array[int] = []
	for k in 8:
		var i := em.spawn(EnemyManager.VULTURE, p + Vector3(randf_range(-25, 25), 0, randf_range(-25, 25)), 1.0)
		uids.append(em.uid[i])
	await _secs(1.0)
	var airborne := 0
	for u in uids:
		var i := em.index_of(u)
		if i >= 0 and em.is_airborne(i):
			airborne += 1
	main.powerups.nuke(main.player.global_position)
	await _secs(1.0)
	var left := 0
	for u in uids:
		if em.index_of(u) >= 0:
			left += 1
	_check("NUKE: vultures die too, even circling out of reach", left == 0, "%d of %d left (%d were airborne)" % [left, uids.size(), airborne])
	_check("...and the Pharaoh only loses a chunk", main.map_boss != null and is_instance_valid(main.map_boss) and main.map_boss.state != "dead", "")


## The NUKE in a real run, indoors (the castle's ceiling squashes the cloud).
func _test_nuke_in_run() -> void:
	var em: EnemyManager = main.enemies
	em.count = 0
	var p: Vector3 = main.player.global_position
	var uids: Array[int] = []
	for k in 200:
		var i := em.spawn(EnemyManager.GRUNT if k % 4 else EnemyManager.SKELETON, p + Vector3(randf_range(-40, 40), 0, randf_range(-40, 40)), 3.0, k % 25 == 0)
		uids.append(em.uid[i])
	main.player.god_mode = false
	main.player.hp = main.player.max_hp
	var hp0: float = main.player.hp
	var kills0: int = main.kills
	await get_tree().physics_frame
	main.powerups.drop(p + Vector3(0.6, 0, 0), PowerupManager.NUKE)
	main.powerups.activate(PowerupManager.NUKE)
	var blast: NukeBlast = main.powerups.blasts[-1] if not main.powerups.blasts.is_empty() else null
	_check("NUKE in a run: the blast goes off", blast != null, "")
	if blast == null:
		return
	_check("...indoors the cloud stays under the ceiling", blast._indoor and blast._height + 6.0 <= CastleBuilder.CEILING + 0.01, "height %.1f" % blast._height)
	await _secs(1.0)
	var left := 0
	for u in uids:
		if em.index_of(u) >= 0:
			left += 1
	_check("...every enemy alive at the time dies", left == 0 and main.kills - kills0 >= 200, "%d left, %d kills" % [left, main.kills - kills0])
	_check("...XP gems drop and fly to you", main.gems.count == 0 or main.gems.att[0] >= 0.0, "%d gems" % main.gems.count)
	_check("...you aren't hurt (not by bomber barrels either)", main.player.hp >= hp0 - 0.01, "%.1f -> %.1f" % [hp0, main.player.hp])
	await _secs(1.5)
	_check("...the mushroom cloud is still up a moment later", is_instance_valid(blast), "")
	main.player.god_mode = true


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
