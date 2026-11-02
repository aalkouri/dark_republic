extends Node3D
## The Desert map:
##   - it builds: the Great Sphinx on its plinth, four stepped pyramids (one great) baked into the
##     height grid, two oases at most, the swamp's prop and landmark counts, chest sites off the
##     stone, ground scatter in chunks drawn near the camera, towering edge dunes;
##   - the player can walk up a pyramid's steps to its summit;
##   - no goblins: zombies (and mummies and vultures) spawn instead, swarm rings are zombies, and
##     zombies climb the pyramids (their height follows the slope, they slow and lean in);
##   - vultures fly (well above the ground), and swoop down to hit a player standing on a summit;
##   - mummies claw out of the sand and their touch curses (slows); the dead leave corpses;
##   - the Pharaoh rises from the tomb before the sphinx at 8:00; his slam, curse beam,
##     sandstorm, scarabs and summons are all marked first; his Wrath of the Sands comes at 75%
##     with three safe spots (and the sphinx's eyes blaze); killing him wins and is recorded;
##   - the map picker lists the Desert, locked until the Arachnid is beaten.
##   godot --headless --path . res://tools/test_desert.tscn

var fails := 0
var main: Node


func _ready() -> void:
	Wallet.persist = false
	_static_checks()
	_picker_checks()
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	await _run_checks()
	get_tree().paused = false
	Settings.selected_map = "swamp"
	Wallet.bosses_defeated = []
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ the map

func _static_checks() -> void:
	var counts := {}
	for map in ["swamp", "desert"]:
		var root := Node3D.new()
		add_child(root)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var t0 := Time.get_ticks_msec()
		var water := WorldBuilder.build(root, rng, 220.0, map)
		var ms := Time.get_ticks_msec() - t0
		var props := 0
		var burnable := 0
		var obstacles := 0
		for c in root.get_children():
			if c is StaticBody3D and not c.is_in_group("obstacle") and not c.is_in_group("arena_edge"):
				props += 1
			if c.is_in_group(TreeFire.GROUP):
				burnable += 1
			if c.is_in_group("obstacle"):
				obstacles += 1
		counts[map] = {"props": props, "burnable": burnable, "obstacles": obstacles, "sites": water.chest_sites.size()}
		print("  %s: %s (%d ms)" % [map, counts[map], ms])
		if map == "desert":
			_check("desert: builds in reasonable time", ms < 15000, "%d ms" % ms)
			_check("desert: the world knows it's the desert", DesertBuilder.active, "")
			var sph := root.find_children("Sphinx", "StaticBody3D", false, false)
			_check("desert: the Great Sphinx lies on its plinth, solid", sph.size() == 1 and (sph[0] as Node).get_child_count() >= 8, "")
			if sph.size() == 1:
				var mesh: ArrayMesh = ((sph[0] as Node).get_child(0) as MeshInstance3D).mesh
				var verts := 0
				for s in mesh.get_surface_count():
					verts += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				_check("desert: the sphinx is richly detailed (many parts)", verts > 20000, "%d vertices" % verts)
				_check("desert: the sphinx's eyes are their own glowing surface", (sph[0] as Node).get_meta("eye_material", null) is StandardMaterial3D and mesh.get_surface_count() >= 2, "")
			_check("desert: the tomb door before its paws", root.find_children("SphinxTomb", "", false, false).size() == 1, "")
			var pyr := root.find_children("Pyramid*", "Node3D", false, false)
			_check("desert: four pyramids", pyr.size() == 4 and DesertBuilder.pyramids.size() == 4, str(pyr.size()))
			var big := 0.0
			var climbable := true
			for p in DesertBuilder.pyramids:
				var c: Vector2 = p["c"]
				var top := water.ground_height(c.x, c.y)
				var base: float = p["base"]
				big = maxf(big, top - base)
				# the baked slope: no steeper than the player can walk (50 degrees)
				var hw: float = p["half"]
				for e in [2.0, 6.0, 10.0]:
					var y0 := water.ground_height(c.x + hw - e, c.y)
					var y1 := water.ground_height(c.x + hw - e - 1.0, c.y)
					if y1 - y0 > tan(deg_to_rad(45.0)):
						climbable = false
				_check("desert: pyramid at %s is baked into the ground (summit %.1f m up)" % [str(c), top - base], absf((top - base) - float(p["h"])) < 0.6, "")
			_check("desert: one great pyramid, 20 m+", big >= 20.0, "%.1f" % big)
			_check("desert: the steps climb at under 45 degrees", climbable, "")
			_check("desert: no pools of water at all", water.pools.size() == 0, str(water.pools.size()))
			var on_stone := 0
			for s in water.chest_sites:
				if DesertBuilder.on_stone(s.x, s.z, 1.0):
					on_stone += 1
			_check("desert: no chest site on a pyramid or the plinth", on_stone == 0, str(on_stone))
			var lowest := INF
			for k in range(0, water.hgrid.size(), 97):
				lowest = minf(lowest, water.hgrid[k])
			_check("desert: the ground never dips below 0 (no swamp-water slowdown)", lowest >= 0.0, "%.2f" % lowest)
			var chunks := 0
			for n in root.find_children("*", "MultiMeshInstance3D", false, false):
				if n.get_meta("chunk", false) and (n as MultiMeshInstance3D).visibility_range_end <= 80.0:
					chunks += 1
			_check("desert: ground scatter in chunks drawn near the camera", chunks >= 60, str(chunks))
			_check("desert: towering dunes all round the edge", root.get_children().filter(func(n): return n.is_in_group("edge_dunes")).size() == 4, "")
			_check("desert: invisible walls round the edge", root.get_children().filter(func(n): return n.is_in_group("arena_edge")).size() == 4, "")
			_check("desert: the sphinx's body blocks the horde", DesertBuilder.barriers.size() == 1, "")
		root.free()
	var s: Dictionary = counts["swamp"]
	var d: Dictionary = counts["desert"]
	_check("desert: roughly the swamp's amount of props", absf(d["props"] - s["props"]) <= s["props"] * 0.3, "%d vs %d" % [d["props"], s["props"]])
	_check("desert: plenty that burns (palms, acacias, dead trees)", d["burnable"] >= 90, str(d["burnable"]))
	_check("desert: same number of landmarks", d["obstacles"] == s["obstacles"], "%d vs %d" % [d["obstacles"], s["obstacles"]])
	_check("desert: same number of chest sites", d["sites"] == s["sites"], "%d vs %d" % [d["sites"], s["sites"]])


func _picker_checks() -> void:
	var ids: Array = MapPicker.MAPS.map(func(m): return m["id"])
	_check("the map picker lists the Desert", "desert" in ids and "desert" in WorldBuilder.MAPS, str(ids))
	Wallet.bosses_defeated = ["thog", "toadstool_knight"]
	_check("the Desert is locked until the Arachnid falls", MapPicker.lock_reason("desert", "fire_wizard") != "", MapPicker.lock_reason("desert", "fire_wizard"))
	Wallet.bosses_defeated = ["thog", "toadstool_knight", "arachnid"]
	_check("...and opens once she has", MapPicker.lock_reason("desert", "fire_wizard") == "", MapPicker.lock_reason("desert", "fire_wizard"))
	_check("the Pharaoh can't fight in the Desert (his home turf)", MapPicker.lock_reason("desert", "pharaoh") != "", "")
	var f := FileAccess.open("res://data/characters.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var ph := {}
	for c in data["characters"]:
		if c["id"] == "pharaoh":
			ph = c
	_check("the Pharaoh is in the roster, locked behind his defeat", not ph.is_empty() and ph.get("requires_boss", "") == "pharaoh" and int(ph.get("price", 0)) == 10000 and "desert" in ph.get("banned_maps", []), str(ph.keys()))
	_check("...with a portrait (nemes, crook and flail)", ph.has("icon") and ph["icon"].get("hat", "") == "nemes" and ph["icon"].get("item", "") == "crook_flail", "")
	_check("...and not yet playable", not RosterHero.is_playable("pharaoh"), "")
	_check("the desert's sounds exist", ResourceLoader.exists("res://audio/desert/zombie_groan_1.wav") and ResourceLoader.exists("res://audio/desert/pharaoh_roar.wav") and ResourceLoader.exists("res://audio/desert/vulture_screech_1.wav"), "")


# ------------------------------------------------------------------ a run in the desert

func _run_checks() -> void:
	Settings.selected_map = "desert"
	Settings.selected_character = "fire_wizard"
	Settings.game_mode = "classic"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	for f in 60 * 15:
		await get_tree().physics_frame
		if not main.intro:
			break
	var em: EnemyManager = main.enemies
	var player: Player = main.player
	main.xp_next = 1e12
	main._next_swarm = 1e9
	main.weapons.orb_t = 1e9   # hold fire: these checks script the kills
	player.god_mode = true
	_check("a run starts in the desert with its own crowd", em.desert != null and DesertBuilder.active, "")
	if em.desert == null:
		return
	# --- no goblins
	var goblins := 0
	var kinds := {}
	for k in 400:
		var t: int = main._pick_type(float(k % 9))
		kinds[t] = true
		if t == EnemyManager.GRUNT or t == EnemyManager.RUNNER or t == EnemyManager.TANK:
			goblins += 1
	_check("no goblins in the desert's spawns", goblins == 0, str(kinds.keys()))
	_check("zombies, mummies and vultures all spawn", kinds.has(EnemyManager.ZOMBIE) and kinds.has(EnemyManager.MUMMY) and kinds.has(EnemyManager.VULTURE) and kinds.has(EnemyManager.ZOMBIE_RUNNER) and kinds.has(EnemyManager.ZOMBIE_BRUTE), str(kinds.keys()))
	var gi := em.spawn(EnemyManager.GRUNT, player.global_position + Vector3(20, 0, 0))
	var ti := em.spawn(EnemyManager.TANK, player.global_position + Vector3(-20, 0, 0))
	_check("a goblin spawned anywhere turns into its zombie", em.typ[gi] == EnemyManager.ZOMBIE and em.typ[ti] == EnemyManager.ZOMBIE_BRUTE, "%d %d" % [em.typ[gi], em.typ[ti]])
	var n0 := em.count
	main._next_swarm = main.run_time
	await get_tree().physics_frame
	main._next_swarm = 1e9
	var swarm_ok := em.count > n0 + 10
	for k in range(n0, em.count):
		if em.typ[k] != EnemyManager.ZOMBIE_RUNNER:
			swarm_ok = false
	_check("the swarm ring is a ring of sprinting zombies", swarm_ok, "%d spawned" % (em.count - n0))
	_clear(em)
	await get_tree().physics_frame
	main._spawn_budget = -1e9

	# --- climb the great pyramid
	var pyr: Dictionary = DesertBuilder.pyramids[0]
	var c: Vector2 = pyr["c"]
	var hw: float = pyr["half"]
	var base: float = pyr["base"]
	var summit: float = base + float(pyr["h"])
	var start := Vector3(c.x, 0, c.y + hw + 3.0)
	player.global_position = Vector3(start.x, SwampWater.height_at(start.x, start.z) + 0.6, start.z)
	player.velocity = Vector3.ZERO
	player.bot = true
	player.cam_yaw = 0.0   # facing -z: straight up the face toward the summit
	player.bot_move = Vector2(0, -1)
	var best_y := -INF
	for f in 60 * 14:
		main._spawn_budget = -1e9
		_clear(em)
		await get_tree().physics_frame
		best_y = maxf(best_y, player.global_position.y)
		var e := minf(hw - absf(player.global_position.x - c.x), hw - absf(player.global_position.z - c.y))
		if e > hw - DesertBuilder.PYRAMID_TOP:   # on the summit: stop
			player.bot_move = Vector2.ZERO
		if f % 40 == 20 and player.global_position.y < summit - 0.5:
			player.bot_jump = true
		elif f % 40 == 24:
			player.bot_jump = false
	player.bot_move = Vector2.ZERO
	player.bot_jump = false
	await _secs(0.5)
	var on_top := player.global_position.y > summit - 1.0 and Vector2(player.global_position.x - c.x, player.global_position.z - c.y).length() < DesertBuilder.PYRAMID_TOP + 2.5
	_check("the player climbs the great pyramid's steps to its summit (%.0f m up)" % (summit - base), on_top, "y %.1f (summit %.1f, best %.1f) at %s" % [player.global_position.y, summit, best_y, str(Vector2(player.global_position.x - c.x, player.global_position.z - c.y))])
	if not on_top:   # carry on from the summit anyway
		player.global_position = Vector3(c.x, summit + 0.6, c.y)
		await _secs(0.3)

	# --- a zombie climbs up after you
	var zi := em.spawn(EnemyManager.ZOMBIE, Vector3(c.x + hw + 4.0, 0, c.y))
	var zu := em.uid[zi]
	var z_best := -INF
	var follows := true
	var climbed := false
	var leaned := false
	for f in 60 * 28:
		player.global_position = Vector3(c.x, summit + 0.5, c.y)
		player.velocity = Vector3.ZERO
		main._spawn_budget = -1e9
		await get_tree().physics_frame
		var k := em.index_of(zu)
		if k < 0:
			break
		var p := em.pos[k]
		if absf(p.y - SwampWater.height_at(p.x, p.z)) > 0.05:
			follows = false
		z_best = maxf(z_best, p.y - base)
		if em.desert.climbing > 0:
			climbed = true
		if DesertBuilder.pyramid_at(p.x, p.z).size() > 0 and p.y - base > 6.0:
			leaned = true
		if Vector2(p.x - c.x, p.z - c.y).length() < 3.0:
			break
	_check("a zombie climbs the pyramid after you (its height follows the slope)", follows and z_best > 10.0, "rose %.1f m" % z_best)
	_check("...slowing and leaning in to claw up the steps", climbed and leaned, "")
	_clear(em)
	await get_tree().physics_frame

	# --- vultures fly up to you on the summit and still hit you
	player.god_mode = false
	player.hp = player.max_hp
	var hp_hits := [0]
	var vi := em.spawn(EnemyManager.VULTURE, Vector3(c.x + 18.0, 0, c.y + 6.0))
	var vu := em.uid[vi]
	var max_air := 0.0
	var reached := false
	for f in 60 * 16:
		player.global_position = Vector3(c.x, summit + 0.5, c.y)
		player.velocity = Vector3.ZERO
		main._spawn_budget = -1e9
		var hp0 := player.hp
		await get_tree().physics_frame
		if player.hp < hp0:
			hp_hits[0] += 1
			player.hp = player.max_hp
		var k := em.index_of(vu)
		if k < 0:
			break
		var p := em.pos[k]
		max_air = maxf(max_air, p.y - SwampWater.height_at(p.x, p.z))
		if Vector2(p.x - c.x, p.z - c.y).length() < 1.5 and absf(p.y - (summit + 0.5)) < 1.5:
			reached = true
		if hp_hits[0] > 0 and reached:
			break
	_check("vultures fly (well above the ground)", max_air > 3.0, "%.1f m up" % max_air)
	_check("a vulture swoops to you on top of the pyramid...", reached, "")
	_check("...and hits you there", hp_hits[0] > 0, str(hp_hits[0]))
	player.god_mode = true
	_clear(em)
	await get_tree().physics_frame
	var vk := em.spawn(EnemyManager.VULTURE, player.global_position + Vector3(8, 0, 0))
	await _secs(0.5)
	var vy := em.pos[vk].y
	var hit_ok := false
	em.damage(vk, 1e6)
	hit_ok = em.dead[vk] == 1
	_check("vultures can be shot down (their row is at their height)", hit_ok and vy > SwampWater.height_at(em.pos[vk].x, em.pos[vk].z) + 1.0, "y %.1f" % vy)

	# --- back down to the sand: mummies, the dead
	player.global_position = Vector3(30, SwampWater.height_at(30, 30) + 0.6, 30)
	player.velocity = Vector3.ZERO
	await _secs(0.4)
	_clear(em)
	await get_tree().physics_frame
	var pp := player.global_position
	var mi := em.spawn(EnemyManager.MUMMY, pp + Vector3(1.0, 0, 0))
	var mu := em.uid[mi]
	_check("a mummy claws its way out of the sand (harmless while it rises)", em.rise_t[mi] > 0.0 and em.is_harmless(mi), "")
	var curses0: int = em.desert.curses
	player.slow_t = 0.0
	for f in 60 * 3:
		player.global_position = Vector3(pp.x, player.global_position.y, pp.z)
		main._spawn_budget = -1e9
		await get_tree().physics_frame
		var k := em.index_of(mu)
		if k >= 0:
			em.pos[k] = Vector3(pp.x + 0.6, em.pos[k].y, pp.z)   # keep it touching you
		if em.desert.curses > curses0:
			break
	_check("a mummy's touch curses you (slowed)", em.desert.curses > curses0 and player.slow_t > 0.0 and player.slow_f < 1.0, "%d curses, slow %.2f" % [em.desert.curses - curses0, player.slow_f])
	_check("mummies are drawn by their own mesh", em.desert.drawn(DesertCrowd.M_MUMMY) >= 1, "")
	var c0: int = em.desert.corpse_count()
	var zz := em.spawn(EnemyManager.ZOMBIE, pp + Vector3(6, 0, 0))
	var vv := em.spawn(EnemyManager.VULTURE, pp + Vector3(-6, 0, 0))
	await get_tree().physics_frame
	em.damage(em.index_of(em.uid[zz]), 1e6)
	em.damage(em.index_of(em.uid[vv]), 1e6)
	await get_tree().physics_frame
	_check("the dead fall (and vultures tumble from the sky) and sink into the sand", em.desert.corpse_count() >= c0 + 2, "%d -> %d" % [c0, em.desert.corpse_count()])
	_clear(em)
	await get_tree().physics_frame

	# --- the Pharaoh
	await _pharaoh(em)


func _pharaoh(em: EnemyManager) -> void:
	var player: Player = main.player
	main.run_time = main.THOG_TIME + 0.1
	await _secs(0.3)
	var boss = main.map_boss
	_check("the Pharaoh arrives at 8:00", boss is PharaohBoss and boss.row() >= 0, str(boss))
	if not (boss is PharaohBoss):
		return
	var b: PharaohBoss = boss
	var tomb := PharaohBoss.rise_point()
	_check("...rising out of the tomb before the sphinx", b.attack == "rise" and MapBoss.flat_dist(em.pos[b.row()], tomb) < 3.0 and b.model.position.y < -1.0, "%s, %.1f m from the tomb" % [b.attack, MapBoss.flat_dist(em.pos[b.row()], tomb)])
	_check("...a 6 m giant with a HUD bar", b.model.scale.x * PharaohModel.MODEL_HEIGHT >= 5.5 and b._bar != null, "")
	await _secs(PharaohBoss.RISE_TIME + 0.3)
	_check("...and once he's out, he comes for you", b.state != "attack" or b.attack != "rise", b.attack)
	# the slam
	await _until_free(b)
	b._summon_cd = 999.0
	b._storm_cd = 999.0
	b._beam_cd = 999.0
	b._scarab_cd = 999.0
	_stand(b, 5.0)
	var hits0: int = b.counts["hits"]
	b._start("slam")
	_check("slam: a circle is marked first (%.1f s+)" % MapBoss.MIN_WARN, b._warns.size() >= 1 and b._warns[-1]["time"] >= MapBoss.MIN_WARN, "")
	await _secs(0.7)
	_check("...nothing lands before it fills", b.counts["hits"] == hits0, "")
	await _secs(1.2)
	_check("...then the flail comes down on it", b.counts["hits"] == hits0 + 1, str(b.counts["hits"] - hits0))
	# the curse beam
	await _until_free(b)
	_stand(b, 12.0)
	var ch0 := b.curse_hits
	player.slow_t = 0.0
	b._start("beam")
	_check("curse beam: a lane is marked first", b._warns.size() >= 1 and b._warns[-1]["time"] >= MapBoss.MIN_WARN, "")
	await _secs(1.7)
	_check("...the beam leaves his crook down it and curses you (slowed)", b.curse_hits == ch0 + 1 and player.slow_t > 0.0, "")
	# the sandstorm
	await _until_free(b)
	_stand(b, 16.0)
	var hz0 := b._hazards.size()
	b._start("storm")
	_check("sandstorm: its circle is marked first", b._warns.size() >= 1, "")
	await _secs(1.8)
	_check("...then the storm hangs there (slows and scours)", b._hazards.size() > hz0 and float(b._hazards[-1]["slow"]) < 1.0 and float(b._hazards[-1]["dps"]) > 0.0, "")
	# scarabs
	await _until_free(b)
	_stand(b, 14.0)
	var w0 := b._warns.size()
	b._start("scarabs")
	_check("scarab swarm: three lanes marked", b._warns.size() == w0 + 3, str(b._warns.size() - w0))
	await _secs(1.6)
	# the dead answer
	await _until_free(b)
	var m0 := _count_type(em, EnemyManager.MUMMY)
	b._start("summon")
	_check("raise the dead: circles marked round you", b._warns.size() >= PharaohBoss.SUMMON_COUNT, "")
	await _secs(2.0)
	_check("...and mummies claw up out of them", _count_type(em, EnemyManager.MUMMY) >= m0 + PharaohBoss.SUMMON_COUNT, "%d -> %d" % [m0, _count_type(em, EnemyManager.MUMMY)])
	_clear(em, true)
	# the Wrath of the Sands at 75%
	await _until_free(b)
	em.hp[b.row()] = em.hp_max[b.row()] * 0.74
	for f in 60 * 6:
		await get_tree().physics_frame
		if int(b.counts.get("wrath", 0)) > 0:
			break
	_check("at 75%% health: the Wrath of the Sands", int(b.counts.get("wrath", 0)) == 1, "%s/%s hp %.2f done %d main %s" % [b.state, b.attack, b.hp_fraction(), b._wraths_done, main.state])
	_check("...a huge marked storm with three golden safe spots", b._safe.size() == PharaohBoss.WRATH_SAFE_SPOTS and b._warns.size() >= 1 and float(b._warns[-1]["time"]) >= 3.0, "%d safe spots" % b._safe.size())
	var sph := get_tree().get_first_node_in_group("sphinx")
	await _secs(0.8)
	var eye: StandardMaterial3D = sph.get_meta("eye_material") if sph != null else null
	_check("...and the sphinx's eyes blaze", eye != null and eye.emission_energy_multiplier > 1.0, "")
	# shelter in a safe spot: no harm
	if not b._safe.is_empty():
		var at: Vector3 = b._safe[0]["at"]
		var h0: int = b.counts["hits"]
		for f in 60 * 4:
			player.global_position = Vector3(at.x, SwampWater.height_at(at.x, at.z) + 0.3, at.z)
			player.velocity = Vector3.ZERO
			await get_tree().physics_frame
			if b._safe.is_empty():
				break
		_check("...sheltering in a safe spot, it passes you by", b.counts["hits"] == h0, "")
	# at 50%, caught in the open: flayed
	await _until_free(b)
	em.hp[b.row()] = em.hp_max[b.row()] * 0.49
	for f in 60 * 6:
		await get_tree().physics_frame
		if int(b.counts.get("wrath", 0)) > 1:
			break
	var h1: int = b.counts["hits"]
	var open_at: Vector3 = b._wrath_at
	for f in 60 * 4:
		player.global_position = Vector3(open_at.x, SwampWater.height_at(open_at.x, open_at.z) + 0.3, open_at.z)
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		if b._safe.is_empty():
			break
	await _secs(0.1)
	_check("at 50%%: caught in the open, the storm flays you", int(b.counts.get("wrath", 0)) == 2 and b.counts["hits"] == h1 + 1, "")
	# kill him
	em.damage(b.row(), 1e9)
	await _secs(5.0)
	_check("killing the Pharaoh wins the run", main.state == "won", main.state)
	_check("...and records his defeat", Wallet.has_defeated("pharaoh"), "")


# ------------------------------------------------------------------ helpers

func _clear(em: EnemyManager, keep_boss := true) -> void:
	for k in em.count:
		if em.dead[k] == 0 and not (keep_boss and em.typ[k] == EnemyManager.TROLL):
			em.dead[k] = 1
			em._dead_count += 1


func _stand(b: MapBoss, d: float) -> void:
	var i := b.row()
	var c: Vector3 = main.enemies.pos[i]
	var aim: Vector3 = b._aim if b._aim.length() > 0.1 else Vector3.FORWARD
	var p := c + aim * d
	main.player.global_position = Vector3(p.x, SwampWater.height_at(p.x, p.z) + 0.5, p.z)
	main.player.velocity = Vector3.ZERO


func _until_free(b: MapBoss) -> void:
	for f in 60 * 8:
		if b.state == "walk" and b._warns.is_empty():
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
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		fails += 1
