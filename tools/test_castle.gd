extends Node3D
## The Castle map: same size and roughly the same spawnables as the swamp; every room reachable
## on foot; you walk in through the front doors and they shut behind you for good; the feast
## flings food when you walk on the table or blast it; skeletons (and armoured epics) spawn,
## throw bones that hit you, and fall apart when killed.
##   godot --headless --path . res://tools/test_castle.tscn

var fails := 0


func _ready() -> void:
	Wallet.persist = false
	_static_checks()
	await _run_checks()
	Settings.selected_map = "swamp"
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _static_checks() -> void:
	var counts := {}
	for map in ["swamp", "castle"]:
		var root := Node3D.new()
		add_child(root)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var water := WorldBuilder.build(root, rng, 220.0, map)
		var burnable := 0
		var obstacles := 0
		var props := 0
		for c in root.get_children():
			if c is StaticBody3D and not c.is_in_group("obstacle"):
				props += 1
			if c.is_in_group(TreeFire.GROUP):
				burnable += 1
			if c.is_in_group("obstacle"):
				obstacles += 1
		counts[map] = {"props": props, "burnable": burnable, "obstacles": obstacles, "sites": water.shrine_sites.size()}
		print("  %s: %s" % [map, counts[map]])
		if map == "castle":
			var nav := CastleNav.current
			_check("castle: a walkable grid over the whole 440 m", nav != null and nav.n * CastleNav.CELL >= 440.0, "")
			var feast := root.find_children("*", "CastleFeast", true, false)
			_check("castle: one feast table", feast.size() == 1, "")
			if feast.size() == 1:
				var f: CastleFeast = feast[0]
				_check("castle: the table is laid end to end (plates, goblets, dishes)", f.items.size() >= 150, str(f.items.size()))
				var kinds := {}
				for it in f.items:
					kinds[it.get_meta("kind", "")] = true
				_check("castle: a variety of food and tableware", kinds.size() >= 8, str(kinds.keys()))
				_check("castle: food is rigid bodies with normal gravity", f.items[0].gravity_scale == 1.0 and f.items[0].mass > 0.0, "")
			_check("castle: front doors", root.find_children("*", "CastleDoors", true, false).size() == 1, "")
			_check("castle: torches and chandeliers light it", root.find_children("*", "OmniLight3D", true, false).size() >= 60,
				str(root.find_children("*", "OmniLight3D", true, false).size()))
			_check("castle: a roof", nav != null and CastleBuilder.CEILING > 10.0, "")
			_check("castle: flat floor (no pools)", water.pools.is_empty() and is_zero_approx(SwampWater.height_at(37.0, -91.0)), "")
			_check_nav(nav)
		root.free()
	var s: Dictionary = counts["swamp"]
	var c: Dictionary = counts["castle"]
	_check("castle: roughly the swamp's amount of props", absf(c["props"] - s["props"]) <= s["props"] * 0.3, "%d vs %d" % [c["props"], s["props"]])
	_check("castle: plenty that burns (furniture, banners)", c["burnable"] >= 60, str(c["burnable"]))
	_check("castle: same number of landmarks", c["obstacles"] == s["obstacles"], "%d vs %d" % [c["obstacles"], s["obstacles"]])
	_check("castle: same number of shrine sites", c["sites"] == s["sites"], "%d vs %d" % [c["sites"], s["sites"]])


## Flood the whole floor from the great hall: every room must be reachable and almost all of the
## walkable floor connected (no sealed-off pockets); outer walls and the table are solid.
func _check_nav(nav: CastleNav) -> void:
	var walk := nav.walkable_count()
	_check("castle: mostly open floor (wide halls, few corridors)", float(walk) / (nav.n * nav.n) > 0.8, "%d / %d" % [walk, nav.n * nav.n])
	var seen := PackedByteArray()
	seen.resize(nav.n * nav.n)
	var start := nav.cell_of(0, 150)
	var q: Array[Vector2i] = [start]
	seen[start.y * nav.n + start.x] = 1
	var reached := 0
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		reached += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = c + d
			if nc.x < 0 or nc.y < 0 or nc.x >= nav.n or nc.y >= nav.n:
				continue
			var k := nc.y * nav.n + nc.x
			if seen[k] or nav.blocked[k]:
				continue
			seen[k] = 1
			q.append(nc)
	_check("castle: the floor is one connected space", reached > walk * 0.97, "%d of %d" % [reached, walk])
	for r in CastleBuilder.ROOMS:
		var any := false
		var a := nav.cell_of(r[1] + 4, r[2] + 4)
		var b := nav.cell_of(r[3] - 4, r[4] - 4)
		for cz in range(a.y, b.y + 1, 3):
			for cx in range(a.x, b.x + 1, 3):
				if seen[cz * nav.n + cx]:
					any = true
		_check("castle: the %s is reachable" % r[0], any, "")
	_check("castle: outer walls are solid", nav.is_blocked(0, -219.5) and nav.is_blocked(219.5, 0) and nav.is_blocked(-219.5, 50), "")
	_check("castle: the table is solid to goblins", nav.is_blocked(0, -20) and nav.is_blocked(0.5, -10), "")
	_check("castle: open floor beside the table", not nav.is_blocked(-12, -20) and not nav.is_blocked(12, -20), "")
	var t0 := Time.get_ticks_usec()
	nav.update(1.0, Vector3(0, 1.0, -20))   # standing on the table
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check("castle: on the table, goblins can still path to both sides", nav.steps_to_player(-12, -20) > 0 and nav.steps_to_player(12, -20) > 0, "")
	_check("castle: flow-field rebuild is cheap", ms < 40.0, "%.1f ms" % ms)
	_check("castle: line of sight is blocked by walls", not nav.line_clear(Vector3(0, 0, 150), Vector3(0, 0, -150)) and nav.line_clear(Vector3(-20, 0, 150), Vector3(20, 0, 150)), "")


func _run_checks() -> void:
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	Settings.selected_map = "castle"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	var main: Node = get_tree().current_scene
	var doors: CastleDoors = main.castle_doors
	var player: Player = main.player
	_check("a run starts in the castle", doors != null and CastleNav.current != null, "")
	if doors == null:
		return
	player.god_mode = true
	_check("you start outside, doors open", player.global_position.z > 220.0 and doors.is_open and main.intro,
		"z=%.1f" % player.global_position.z)
	_check("no goblins before you're in", main.enemies.count == 0, str(main.enemies.count))
	var shut := [false]
	doors.shut.connect(func(): shut[0] = true)
	for f in 60 * 12:
		await get_tree().physics_frame
		if shut[0]:
			break
	_check("you walk in and the doors slam shut", shut[0] and not doors.is_open and not main.intro, "z=%.1f" % player.global_position.z)
	_check("you're inside after the walk-in", player.global_position.z < 220.0 - 1.0, "z=%.1f" % player.global_position.z)
	_check("the door slam has a sound", doors._sfx.stream != null, "")

	# Try to walk back out
	player.bot = true
	player.bot_move = Vector2(0, 1)
	player.cam_yaw = 0.0
	for f in 60 * 3:
		await get_tree().physics_frame
	_check("the shut doors can't be re-entered (walked into them for 3 s)", player.global_position.z < 220.0, "z=%.1f" % player.global_position.z)

	# Clear the floor so the next checks are deterministic
	var em: EnemyManager = main.enemies

	# The feast: walk along the table top
	var feast: CastleFeast = get_tree().get_first_node_in_group("castle_feast")
	var top := 0
	for it in feast.items:
		if it.global_position.y > feast.top_y - 0.1:
			top += 1
	player.global_position = Vector3(0, feast.top_y + 0.6, -9)
	player.velocity = Vector3.ZERO
	player.bot_move = Vector2(0, -1)   # walk north along the table
	for f in 60 * 2:
		await get_tree().physics_frame
	player.bot_move = Vector2.ZERO
	_check("walking on the table kicks food about", feast.kicks >= 5, "%d kicks, walked to z=%.1f" % [feast.kicks, player.global_position.z])
	_check("you can stand on the table", player.global_position.y > feast.top_y - 0.2, "y=%.2f" % player.global_position.y)
	for f in 60 * 2:
		await get_tree().physics_frame
	var after := 0
	var floor := 0
	for it in feast.items:
		if it.global_position.y > feast.top_y - 0.1:
			after += 1
		elif it.global_position.y < 0.6:
			floor += 1
	_check("kicked food falls off onto the floor (normal gravity)", floor > 0 and after < top, "%d on the floor" % floor)
	var b0 := feast.blasts
	main.fx.burst(Vector3(0, feast.top_y + 0.5, -38), 4.0)
	await get_tree().physics_frame
	_check("explosions near the table blast the food", feast.blasts > b0 and feast.awake_count() > 0, "")
	var nova_b := feast.blasts
	player.global_position = Vector3(0, feast.top_y + 0.6, -25)
	main.abilities._erupt_shockwave()
	await get_tree().physics_frame
	_check("Fire Nova sweeps the table", feast.blasts > nova_b, "")

	# Loitering on the table: a chandelier comes down where you stood
	player.god_mode = false
	player.hp = player.max_hp
	player.invuln = 0.0
	player.global_position = Vector3(0, feast.top_y + 0.05, -20)
	player.velocity = Vector3.ZERO
	feast.stand_t = 0.0
	var ch_d0 := feast.drops
	for f in int(60 * 1.8):
		await get_tree().physics_frame
	_check("standing on the table under 2 s: nothing falls", feast.drops == ch_d0, "")
	for f in int(60 * 0.3):
		await get_tree().physics_frame
	_check("after 2 s a chandelier drops at your spot, marked on the table", feast.drops == ch_d0 + 1
		and (feast._falling[-1]["at"] as Vector3).distance_to(Vector3(0, feast.top_y, -20)) < 0.5, "")
	var ch_h0 := player.hp
	var ch_hits0 := feast.drop_hits
	for f in int(60 * 0.7):
		await get_tree().physics_frame
	_check("...and doesn't hit before its 1 s warning is up", feast.drop_hits == ch_hits0 and player.hp == ch_h0, "")
	player.invuln = 0.0
	for f in int(60 * 0.4):
		await get_tree().physics_frame
	_check("...staying put costs 15% of max HP", feast.drop_hits == ch_hits0 + 1 and absf((ch_h0 - player.hp) - player.max_hp * 0.15) < 1.0, "%.1f lost" % (ch_h0 - player.hp))
	# Dodge: step off the marked spot in time
	player.hp = player.max_hp
	player.invuln = 0.0
	player.global_position = Vector3(0, feast.top_y + 0.05, -30)
	feast.stand_t = 0.0
	for f in int(60 * 2.1):
		await get_tree().physics_frame
	player.global_position = Vector3(-8, 0.1, -30)   # off the table, out of reach
	ch_hits0 = feast.drop_hits
	for f in int(60 * 1.2):
		await get_tree().physics_frame
	_check("stepping out of the marker dodges it", feast.drop_hits == ch_hits0, "")
	player.god_mode = true

	# Skeletons
	_check("skeletons are part of the castle's spawns", main._pick_type(0.0) == EnemyManager.SKELETON or _some_skeleton(main), "")
	player.global_position = Vector3(-40, 0.5, 150)   # open floor in the great hall
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var sk := em.skeletons
	var t0 := sk.thrown
	var h0 := sk.bone_hits
	var i := em.spawn(EnemyManager.SKELETON, Vector3(-30, 0, 150))
	var j := em.spawn(EnemyManager.SKELETON, Vector3(-50, 0, 150), 1.0, true)
	_check("skeletons spawn (and an armoured epic)", i >= 0 and j >= 0 and em.typ[i] == EnemyManager.SKELETON and em.epic[j], "")
	await get_tree().physics_frame
	await get_tree().process_frame
	_check("plain and armoured skeletons are drawn by their own meshes", sk._mm.visible_instance_count >= 1 and sk._mm_armored.visible_instance_count >= 1,
		"%d / %d" % [sk._mm.visible_instance_count, sk._mm_armored.visible_instance_count])
	for f in 60 * 6:
		player.global_position = Vector3(-40, player.global_position.y, 150)   # hold still: an easy target
		player.invuln = 0.0
		await get_tree().physics_frame
	_check("skeletons throw bones", sk.thrown - t0 >= 2, str(sk.thrown - t0))
	_check("thrown bones hit you", sk.bone_hits - h0 >= 1, str(sk.bone_hits - h0))
	var d0 := sk._d_n
	for k in em.count:
		if em.typ[k] == EnemyManager.SKELETON and not em.dead[k]:
			em.damage(k, 99999.0)
	await get_tree().physics_frame
	_check("killed skeletons fall apart into bones", sk._d_n > d0, "%d -> %d" % [d0, sk._d_n])
	_check("bone clatter has a sound", sk._clatter != null, "")

	# Goblins don't walk through walls: one starts in the west gallery, the player in the dining hall
	player.global_position = Vector3(20, 0.5, -20)
	var g := em.spawn(EnemyManager.GRUNT, Vector3(-80, 0, -20))
	var inside_wall := 0
	for f in 60 * 4:
		await get_tree().physics_frame
		if g < em.count and not em.dead[g] and CastleNav.current.is_blocked(em.pos[g].x, em.pos[g].z):
			inside_wall += 1
	var p := em.pos[g] if g < em.count else Vector3.ZERO
	_check("goblins path around walls toward you", g < em.count and p.distance_to(Vector3(20, 0, -20)) < Vector3(-80, 0, -20).distance_to(Vector3(20, 0, -20)) - 8.0,
		"at %s" % str(p))
	_check("goblins don't end up inside walls", inside_wall < 10, str(inside_wall))


func _some_skeleton(main: Node) -> bool:
	for k in 200:
		if main._pick_type(60.0) == EnemyManager.SKELETON:
			return true
	return false


func _check(what: String, ok: bool, detail: String) -> void:
	print("  %s %s%s" % ["ok  " if ok else "FAIL", what, ("  (" + detail + ")") if detail != "" else ""])
	if not ok:
		fails += 1
