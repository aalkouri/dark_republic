extends Node3D
## The Ashen Caldera:
##   - it builds: lava rivers and pools carved into the ground (no swamp water anywhere: the
##     ground never dips below 0 and SwampWater keeps no pools), rock bridges and stepping stones,
##     the forge-temple, the falls, the sunken colossus, the cinder cone, the swamp's prop and
##     landmark counts, chest sites off the lava, ground scatter in chunks drawn near the camera,
##     crater cliffs and invisible walls round the edge;
##   - lava burns the player (damage over time + a burn) and doesn't slow them; the stepping
##     stones and the bridges cross it safely;
##   - no goblins: imps, bats, golems and slugs spawn instead; the minute's swarm is an eruption
##     (lava bombs on circles marked at least 1 s, hurting only the player) with imps and bats,
##     and no on-screen text;
##   - bats fly and reach the player on top of a basalt column; slugs' trails burn the player but
##     not enemies; golems shake the ground and shatter; imps burst into embers and rock;
##   - Singe bursts up out of the great pool at 8:00, a 6 m coal imp towering over his imps; his
##     claw swipe, fire breath, lava dive, meteors, summons and scorch run are all marked first
##     (>= 1 s), and his scorch marks burn you for a few seconds; the Caldera Eruption at 75% gives
##     10 s of warning, raises safe islands with arrows over them, floods the ground, and burns
##     anyone off the islands; killing him wins and is recorded ("singe"), he gutters out into a
##     heap of cooling coals, and the lava dims;
##   - the map picker lists the Caldera, locked until the Necromancer is beaten; Singe on the
##     roster is now locked behind his defeat (and banned from the Caldera).
##   godot --headless --path . res://tools/test_caldera.tscn

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
	for map in ["swamp", "caldera"]:
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
			if c is StaticBody3D and not c.is_in_group("obstacle") and not c.is_in_group("arena_edge") and not c.is_in_group("rock_bridge") and not c.is_in_group("stepping_stones"):
				props += 1
			if c.is_in_group(TreeFire.GROUP):
				burnable += 1
			if c.is_in_group("obstacle"):
				obstacles += 1
		counts[map] = {"props": props, "burnable": burnable, "obstacles": obstacles, "sites": water.chest_sites.size()}
		print("  %s: %s (%d ms)" % [map, counts[map], ms])
		if map == "caldera":
			_check("caldera: builds in reasonable time", ms < 15000, "%d ms" % ms)
			_check("caldera: the world knows it's the caldera", CalderaBuilder.active and not DesertBuilder.active, "")
			_check("caldera: no swamp water at all (SwampWater keeps no pools)", water.pools.is_empty(), str(water.pools.size()))
			var lowest := INF
			for k in range(0, water.hgrid.size(), 31):
				lowest = minf(lowest, water.hgrid[k])
			_check("caldera: the ground never dips below 0 (no swamp-water slowdown, even in the lava beds)", lowest > 0.2, "%.2f" % lowest)
			var lava := root.get_children().filter(func(n): return n.is_in_group("lava"))
			_check("caldera: three lava rivers and the pools drawn", CalderaBuilder.rivers.size() == 3 and CalderaBuilder.pools.size() >= 4 and lava.size() >= 7, "%d rivers, %d pools, %d surfaces" % [CalderaBuilder.rivers.size(), CalderaBuilder.pools.size(), lava.size()])
			_check("caldera: every lava surface glows (its own animated shader)", CalderaBuilder.lava_mats.size() >= 4, str(CalderaBuilder.lava_mats.size()))
			var great := {}
			for p in CalderaBuilder.pools:
				if p["kind"] == "great":
					great = p
			_check("caldera: the great lava pool (Singe's lair) north of the start", not great.is_empty() and (great["c"] as Vector2).y < -50.0, "")
			# the lava is carved into the ground: its bed lies under its surface
			var rv: Dictionary = CalderaBuilder.rivers[1]
			var pts: PackedVector2Array = rv["pts"]
			var mid := pts[pts.size() / 2]
			var k_mid := pts.size() / 2
			for s in rv["bridges"] + rv["stones"]:
				if absi(int(s) - k_mid) < 8:
					k_mid += 16
			mid = pts[k_mid]
			var lv := CalderaBuilder.lava_level(mid.x, mid.y)
			var bed := water.ground_height(mid.x, mid.y)
			_check("caldera: river beds are carved under the lava's surface", lv > CalderaBuilder.LAVA_NONE + 1.0 and bed < lv - 0.2, "bed %.2f lava %.2f" % [bed, lv])
			_check("caldera: feet in a river are in the lava", CalderaBuilder.in_lava(Vector3(mid.x, bed + 0.05, mid.y)), "")
			_check("caldera: ...but a few metres up the bank are not", not CalderaBuilder.in_lava(Vector3(mid.x, bed + 3.0, mid.y)), "")
			_check("caldera: crossings: rock bridges and stepping stones", CalderaBuilder.bridges.size() >= 3 and CalderaBuilder.stones.size() >= 20, "%d bridges, %d stones" % [CalderaBuilder.bridges.size(), CalderaBuilder.stones.size()])
			var dry_stones := true
			for st in CalderaBuilder.stones:
				if CalderaBuilder.in_lava(st + Vector3(0, 0.02, 0)):
					dry_stones = false
			_check("caldera: standing on a stepping stone is out of the lava", dry_stones, "")
			var dry_bridges := true
			for b in CalderaBuilder.bridges:
				var at: Vector3 = b["at"]
				if CalderaBuilder.in_lava(Vector3(at.x, water.ground_height(at.x, at.z) + 0.02, at.z)):
					dry_bridges = false
			_check("caldera: the rock bridges stand over the lava", dry_bridges, "")
			_check("caldera: the dwarven forge-temple with its giant anvil", root.find_children("ForgeTemple", "", false, false).size() == 1 and (root.find_children("ForgeTemple", "", false, false)[0] as Node).has_meta("anvil"), "")
			_check("caldera: the smith-god's colossus sinking in a lava pool", root.find_children("SmithGod", "", false, false).size() == 1, "")
			_check("caldera: the lava falls on the ridge", root.find_children("LavaFalls", "", false, false).size() == 1, "")
			var cone: Dictionary = CalderaBuilder.cone
			_check("caldera: the cinder cone is baked into the ground", not cone.is_empty() and water.ground_height((cone["c"] as Vector2).x + 9.0, (cone["c"] as Vector2).y) > (cone["at"] as Vector3).y + 20.0, "")
			_check("caldera: the cinder cone smokes in its corner", root.find_children("CinderCone", "", false, false).size() == 1, "")
			var wet := 0
			for s in water.chest_sites:
				if CalderaBuilder.lava_dist(s.x, s.z) < ChestManager.SITE_RADIUS + 2.0 or CalderaBuilder.on_cone(s.x, s.z, 2.0):
					wet += 1
			_check("caldera: no chest site in or by the lava (or on the cone)", wet == 0, str(wet))
			var chunks := 0
			for n in root.find_children("*", "MultiMeshInstance3D", false, false):
				if n.get_meta("chunk", false) and (n as MultiMeshInstance3D).visibility_range_end <= 80.0:
					chunks += 1
			_check("caldera: ground scatter in chunks drawn near the camera", chunks >= 60, str(chunks))
			_check("caldera: crater cliffs all round the edge", root.get_children().filter(func(n): return n.is_in_group("edge_cliffs")).size() == 4, "")
			_check("caldera: invisible walls round the edge", root.get_children().filter(func(n): return n.is_in_group("arena_edge")).size() == 4, "")
			var kinds := {}
			for n in root.get_children():
				if n.is_in_group("obstacle"):
					kinds[n.get_meta("kind", "")] = true
			_check("caldera: landmarks of every kind (columns, spires, braziers, fumaroles, sulphur, bones)", kinds.size() == 6, str(kinds.keys()))
		root.free()
	var s: Dictionary = counts["swamp"]
	var d: Dictionary = counts["caldera"]
	_check("caldera: roughly the swamp's amount of props", absf(d["props"] - s["props"]) <= s["props"] * 0.3, "%d vs %d" % [d["props"], s["props"]])
	_check("caldera: plenty that burns (charred trees and logs)", d["burnable"] >= 60, str(d["burnable"]))
	_check("caldera: same number of landmarks", d["obstacles"] == s["obstacles"], "%d vs %d" % [d["obstacles"], s["obstacles"]])
	_check("caldera: same number of chest sites", d["sites"] == s["sites"], "%d vs %d" % [d["sites"], s["sites"]])


func _picker_checks() -> void:
	var ids: Array = MapPicker.MAPS.map(func(m): return m["id"])
	_check("the map picker lists the Ashen Caldera", "caldera" in ids and "caldera" in WorldBuilder.MAPS, str(ids))
	Wallet.bosses_defeated = ["thog", "toadstool_knight", "arachnid", "pharaoh"]
	_check("the Caldera is locked until the Necromancer falls", MapPicker.lock_reason("caldera", "fire_wizard") != "", MapPicker.lock_reason("caldera", "fire_wizard"))
	Wallet.bosses_defeated = ["thog", "toadstool_knight", "arachnid", "pharaoh", "necromancer"]
	_check("...and opens once he has", MapPicker.lock_reason("caldera", "fire_wizard") == "", MapPicker.lock_reason("caldera", "fire_wizard"))
	_check("Singe can't fight in the Caldera (his home turf)", MapPicker.lock_reason("caldera", "singe") != "", "")
	var f := FileAccess.open("res://data/characters.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var singe := {}
	var mysteries := 0
	for c in data["characters"]:
		if c["id"] == "singe":
			singe = c
		if c.get("mystery", false):
			mysteries += 1
	_check("the old wyrm boss is gone from the roster", not JSON.stringify(data).to_lower().contains("ashfang") and not JSON.stringify(data).to_lower().contains("wyrm"), "")
	_check("Singe is the Caldera boss's unlock: his defeat and 10,000 coins", singe.get("requires_boss", "") == "singe" and int(singe.get("price", 0)) == 10000 and "caldera" in singe.get("banned_maps", []), str(singe.keys()))
	_check("...keeping his name, epithet and imp portrait", singe.get("name", "") == "Singe" and singe.get("epithet", "") == "The Living Cinder" and singe["icon"].get("body", "") == "imp" and singe["icon"].get("hat", "") == "flame_hair", "")
	_check("...the roster keeps its three mystery slots", data["characters"].size() == 30 and mysteries == 3, "%d, %d mysteries" % [data["characters"].size(), mysteries])
	_check("...and his kit on the select screen", KitDB.kit("singe").get("abilities", []).size() == 3, "")
	_check("the caldera's sounds exist", ResourceLoader.exists("res://audio/caldera/lava_bubble.wav") and ResourceLoader.exists("res://audio/caldera/singe_cackle.wav") and ResourceLoader.exists("res://audio/caldera/singe_fizzle.wav") and ResourceLoader.exists("res://audio/caldera/golem_shatter.wav") and ResourceLoader.exists("res://audio/caldera/eruption.wav"), "")
	_check("the caldera's music is set", main_music_ok(), "")


func main_music_ok() -> bool:
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	return src.contains("\"caldera\": \"res://audio/music/") and src.contains("\"caldera\": \"singe\"")


# ------------------------------------------------------------------ a run in the caldera

func _run_checks() -> void:
	Settings.selected_map = "caldera"
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
	_check("a run starts in the caldera with its own crowd", em.caldera != null and CalderaBuilder.active and CalderaAmbience.current != null, "")
	if em.caldera == null:
		return
	# --- no goblins
	var goblins := 0
	var kinds := {}
	for k in 500:
		var t: int = main._pick_type(float(k % 9))
		kinds[t] = true
		if t == EnemyManager.GRUNT or t == EnemyManager.RUNNER or t == EnemyManager.TANK or t == EnemyManager.ZOMBIE or t == EnemyManager.SKELETON or t == EnemyManager.GHOUL or t == EnemyManager.GHOST or t == EnemyManager.MUMMY or t == EnemyManager.VULTURE:
			goblins += 1
	_check("no goblins (or zombies, skeletons, ghosts...) in the caldera's spawns", goblins == 0, str(kinds.keys()))
	_check("imps, bats, golems and slugs all spawn", kinds.has(EnemyManager.MAGMA_IMP) and kinds.has(EnemyManager.CINDER_BAT) and kinds.has(EnemyManager.OBSIDIAN_GOLEM) and kinds.has(EnemyManager.LAVA_SLUG), str(kinds.keys()))
	var gi := em.spawn(EnemyManager.GRUNT, player.global_position + Vector3(20, 0, 0))
	var ri := em.spawn(EnemyManager.RUNNER, player.global_position + Vector3(0, 0, 20))
	var ti := em.spawn(EnemyManager.TANK, player.global_position + Vector3(-20, 0, 0))
	_check("a goblin spawned anywhere turns into its caldera counterpart (imp, bat, golem)", em.typ[gi] == EnemyManager.MAGMA_IMP and em.typ[ri] == EnemyManager.CINDER_BAT and em.typ[ti] == EnemyManager.OBSIDIAN_GOLEM, "%d %d %d" % [em.typ[gi], em.typ[ri], em.typ[ti]])
	_clear(em)
	await get_tree().physics_frame
	main._spawn_budget = -1e9
	# imps come in packs
	var i0 := em.spawn(EnemyManager.MAGMA_IMP, player.global_position + Vector3(25, 0, 0))
	var i1 := em.spawn(EnemyManager.MAGMA_IMP, player.global_position + Vector3(-25, 0, 0))
	_check("magma imps run in packs (one spawned right after another joins it)", em.pos[i1].distance_to(em.pos[i0]) < 4.0, "%.1f m apart" % em.pos[i1].distance_to(em.pos[i0]))
	_clear(em)
	await get_tree().physics_frame

	# --- the eruption swarm
	var amb := CalderaAmbience.current
	main.hud.msg_label.text = ""
	var n0 := em.count
	var b0 := amb.bombs_landed
	main._next_swarm = main.run_time
	await get_tree().physics_frame
	main._next_swarm = 1e9
	var swarm_ok := em.count > n0 + 10
	var only := true
	for k in range(n0, em.count):
		if em.typ[k] != EnemyManager.MAGMA_IMP and em.typ[k] != EnemyManager.CINDER_BAT:
			only = false
	_check("the minute's swarm: imps and bats come for you", swarm_ok and only, "%d came" % (em.count - n0))
	_check("...and the volcano erupts: lava bombs onto marked circles round you", amb.pending_bombs() >= 6, str(amb.pending_bombs()))
	_check("...every circle marked at least %.0f s before its bomb lands" % CalderaAmbience.MIN_WARN, amb.min_bomb_warning() >= CalderaAmbience.MIN_WARN, "%.2f s" % amb.min_bomb_warning())
	_check("...with no on-screen text", main.hud.msg_label.text == "", main.hud.msg_label.text)
	# bombs hurt only the player: imps stood under every bomb are untouched
	var under: Array[int] = []
	for b in amb._bombs:
		var at: Vector3 = b["at"]
		var u := em.spawn(EnemyManager.LAVA_SLUG, at)
		if u >= 0:
			em.slow(u, 0.0, 30.0)   # stay put under it
			under.append(em.uid[u])
	player.god_mode = false
	player.hp = player.max_hp
	var bh0 := amb.bomb_hits
	for f in 60 * 5:
		player.velocity = Vector3.ZERO
		if player.hp < player.max_hp * 0.5:
			player.hp = player.max_hp
		await get_tree().physics_frame
		if amb.pending_bombs() == 0:
			break
	var untouched := true
	for u in under:
		var k := em.index_of(u)
		if k < 0 or em.hp[k] < em.hp_max[k] - 0.01:
			untouched = false
	_check("...the bombs land (%d)" % (amb.bombs_landed - b0), amb.bombs_landed - b0 >= 6, "")
	_check("...one hits you where you stand", amb.bomb_hits > bh0, str(amb.bomb_hits - bh0))
	_check("...and none hurts an enemy", untouched and under.size() >= 4, "%d checked" % under.size())
	player.god_mode = true
	_clear(em)
	await get_tree().physics_frame
	main._spawn_budget = -1e9

	# --- lava burns, without slowing; the stones and bridges cross it
	await _lava(em)

	# --- bats reach you on a basalt column
	await _bats(em)

	# --- slugs' trails, golems, imps
	await _creatures(em)

	# --- performance at 1,400
	await _perf(em)

	# --- Singe
	await _singe(em)


func _lava(em: EnemyManager) -> void:
	var player: Player = main.player
	var amb := CalderaAmbience.current
	var rv: Dictionary = CalderaBuilder.rivers[1]
	var pts: PackedVector2Array = rv["pts"]
	var k_mid := pts.size() / 2
	for s in rv["bridges"] + rv["stones"]:
		if absi(int(s) - k_mid) < 8:
			k_mid += 16
	var q := pts[k_mid]
	player.god_mode = false
	player.hp = player.max_hp
	player.burn_left = 0.0
	var hits0 := amb.lava_hits
	for f in 60 * 2:
		player.global_position = Vector3(q.x, SwampWater.height_at(q.x, q.y) + 0.05, q.y)
		player.velocity = Vector3.ZERO
		main._spawn_budget = -1e9
		await get_tree().physics_frame
	_check("standing in lava burns you (damage over time)", amb.lava_hits >= 3 and player.hp < player.max_hp - 15.0, "%d burns, hp %.0f" % [amb.lava_hits - hits0, player.hp])
	_check("...and sets you burning for a moment", player.burn_left > 0.0, "%.2f" % player.burn_left)
	_check("...without slowing you like swamp water", not player.in_water, "")
	player.hp = player.max_hp
	player.burn_left = 0.0
	# the stepping stones: walk across a line of them, bank to bank
	var line: Array = []
	for rv2 in CalderaBuilder.rivers:
		for s in rv2["stones"]:
			var k: int = s
			var p2: PackedVector2Array = rv2["pts"]
			line = [p2[k], (p2[mini(k + 2, p2.size() - 1)] - p2[maxi(k - 2, 0)]).normalized(), float(rv2["w"])]
			break
		if not line.is_empty():
			break
	if not line.is_empty():
		var c: Vector2 = line[0]
		var fwd: Vector2 = line[1]
		var side := Vector2(-fwd.y, fwd.x)
		var reach: float = float(line[2]) + CalderaBuilder.BANK * 0.55 + 0.6
		var from := c - side * (reach + 1.2)
		var to := c + side * (reach + 1.2)
		player.global_position = Vector3(from.x, SwampWater.height_at(from.x, from.y) + 0.4, from.y)
		player.velocity = Vector3.ZERO
		await _secs(0.3)
		var h1 := amb.lava_hits
		player.bot = true
		var dir := Vector3(to.x - from.x, 0, to.y - from.y).normalized()
		player.cam_yaw = atan2(-dir.x, -dir.z)
		player.bot_move = Vector2(0, -1)
		var crossed := false
		for f in 60 * 6:
			main._spawn_budget = -1e9
			_clear(em)
			await get_tree().physics_frame
			var pp := player.global_position
			if Vector2(pp.x - c.x, pp.z - c.y).dot(side) > reach + 0.6:
				crossed = true
				break
		player.bot_move = Vector2.ZERO
		player.bot = false
		_check("walking across the basalt stepping stones, the lava never touches you", crossed and amb.lava_hits == h1, "crossed %s, %d burns" % [crossed, amb.lava_hits - h1])
	var b: Dictionary = CalderaBuilder.bridges[0]
	var at: Vector3 = b["at"]
	var h2 := amb.lava_hits
	for f in 60:
		player.global_position = Vector3(at.x, SwampWater.height_at(at.x, at.z) + 0.05, at.z)
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
	_check("...nor on a rock bridge", amb.lava_hits == h2, str(amb.lava_hits - h2))
	player.global_position = Vector3(0, SwampWater.height_at(0, 0) + 0.5, 0)
	player.velocity = Vector3.ZERO
	player.god_mode = true
	player.burn_left = 0.0
	player.hp = player.max_hp
	await _secs(0.2)


func _bats(em: EnemyManager) -> void:
	var player: Player = main.player
	var top := Vector3.INF
	# find the tallest column of a column field: its colliders are cylinders
	for n in main.get_children():
		if n.is_in_group("obstacle") and n.get_meta("kind", "") == "columns":
			for cs in n.get_children():
				if cs is CollisionShape3D and (cs as CollisionShape3D).shape is CylinderShape3D:
					var sh: CylinderShape3D = (cs as CollisionShape3D).shape
					var tp := (n as Node3D).global_transform * ((cs as CollisionShape3D).position + Vector3(0, sh.height * 0.5, 0))
					if top == Vector3.INF or tp.y - SwampWater.height_at(tp.x, tp.z) > top.y - SwampWater.height_at(top.x, top.z):
						top = tp
			break
	_check("a basalt column field to climb", top != Vector3.INF and top.y - SwampWater.height_at(top.x, top.z) > 3.0, str(top))
	if top == Vector3.INF:
		return
	var up := top + Vector3(0, 0.1, 0)
	player.global_position = up
	player.velocity = Vector3.ZERO
	await _secs(0.4)
	_check("the player can stand on a column top", absf(player.global_position.y - top.y) < 0.6, "%.2f vs %.2f" % [player.global_position.y, top.y])
	player.god_mode = false
	player.hp = player.max_hp
	_clear(em)
	await get_tree().physics_frame
	var vi := em.spawn(EnemyManager.CINDER_BAT, Vector3(top.x + 18.0, 0, top.z + 6.0))
	var vu := em.uid[vi]
	var max_air := 0.0
	var reached := false
	var hits := 0
	for f in 60 * 18:
		player.global_position = Vector3(top.x, player.global_position.y, top.z)
		player.velocity = Vector3.ZERO
		main._spawn_budget = -1e9
		var hp0 := player.hp
		await get_tree().physics_frame
		if player.hp < hp0:
			hits += 1
			player.hp = player.max_hp
		var k := em.index_of(vu)
		if k < 0:
			break
		var p := em.pos[k]
		max_air = maxf(max_air, p.y - SwampWater.height_at(p.x, p.z))
		if Vector2(p.x - top.x, p.z - top.z).length() < 1.5 and absf(p.y - (player.global_position.y + 0.5)) < 1.5:
			reached = true
		if hits > 0 and reached:
			break
	_check("cinder bats fly (well above the crowd)", max_air > 3.0, "%.1f m up" % max_air)
	_check("a bat dives to you on top of the column...", reached, "")
	_check("...and hits you there", hits > 0, str(hits))
	player.god_mode = true
	_clear(em)
	await get_tree().physics_frame
	var bk := em.spawn(EnemyManager.CINDER_BAT, player.global_position + Vector3(8, 0, 0))
	await _secs(0.5)
	var by := em.pos[bk].y
	var e0 := em.caldera._e_n
	em.damage(bk, 1e6)
	_check("bats can be shot down (their row is at their height)", em.dead[bk] == 1 and by > SwampWater.height_at(em.pos[bk].x, em.pos[bk].z) + 1.0, "y %.1f" % by)
	await get_tree().physics_frame
	_check("...they leave an ember trail and burst into sparks", em.caldera._e_n > 0, "%d embers" % em.caldera._e_n)
	player.global_position = Vector3(0, SwampWater.height_at(0, 0) + 0.5, 0)
	player.velocity = Vector3.ZERO
	await _secs(0.3)


func _creatures(em: EnemyManager) -> void:
	var player: Player = main.player
	var cc := em.caldera
	var pp := player.global_position
	# a slug lays a trail
	var si := em.spawn(EnemyManager.LAVA_SLUG, pp + Vector3(9, 0, 0))
	var su := em.uid[si]
	var t0 := cc.trail_pos.size()
	for f in 60 * 3:
		player.global_position = pp
		player.velocity = Vector3.ZERO
		main._spawn_budget = -1e9
		await get_tree().physics_frame
	_check("a lava slug leaves a trail of burning lava behind it", cc.trail_pos.size() >= t0 + 3, "%d blobs" % (cc.trail_pos.size() - t0))
	var k := em.index_of(su)
	if k >= 0:
		em.dead[k] = 1
		em._dead_count += 1
	await get_tree().physics_frame
	# an imp standing on the trail is unharmed; the player standing on it burns
	var blob: Vector3 = cc.trail_pos[cc.trail_pos.size() - 1] if cc.trail_pos.size() > 0 else pp
	var ii := em.spawn(EnemyManager.MAGMA_IMP, blob)
	var iu := em.uid[ii]
	em.stun(ii, 10.0)
	player.god_mode = false
	player.hp = player.max_hp
	var th0 := cc.trail_hits
	for f in 60 * 2:
		player.global_position = Vector3(blob.x, SwampWater.height_at(blob.x, blob.z) + 0.05, blob.z)
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		var ki := em.index_of(iu)
		if ki >= 0:
			em.stun(ki, 10.0)
	var ki2 := em.index_of(iu)
	_check("...standing on the trail burns you", cc.trail_hits > th0 and player.hp < player.max_hp, "%d burns" % (cc.trail_hits - th0))
	_check("...but enemies don't mind it", ki2 >= 0 and em.hp[ki2] >= em.hp_max[ki2] - 0.01, "")
	player.god_mode = true
	await _secs(float(CalderaCrowd.TRAIL_LIFE) + 0.3)
	_check("...and it fades after a few seconds", cc.trail_pos.size() == 0, str(cc.trail_pos.size()))
	_clear(em)
	await get_tree().physics_frame
	# a golem's heavy steps shake the ground near you; it shatters when killed
	player.global_position = Vector3(0, SwampWater.height_at(0, 0) + 0.5, 0)
	pp = player.global_position
	var gi := em.spawn(EnemyManager.OBSIDIAN_GOLEM, pp + Vector3(9, 0, 0))
	var gu := em.uid[gi]
	var st0 := cc.stomps
	for f in 60 * 2:
		player.global_position = pp
		player.velocity = Vector3.ZERO
		main._spawn_budget = -1e9
		await get_tree().physics_frame
	_check("an obsidian golem's heavy steps shake the ground near you", cc.stomps > st0, str(cc.stomps - st0))
	_check("...it's drawn by its own mesh", cc.drawn(CalderaCrowd.M_GOLEM) >= 1, "")
	var sh0 := cc.shatters
	var d0 := cc.debris_count()
	var c0 := cc.corpse_count()
	em.damage(em.index_of(gu), 1e6)
	await get_tree().physics_frame
	_check("...and shatters into glass shards when it dies (no corpse)", cc.shatters == sh0 + 1 and cc.debris_count() >= d0 + 15 and cc.corpse_count() == c0, "%d debris" % (cc.debris_count() - d0))
	# imps burst into embers and rock chunks
	var ia := em.spawn(EnemyManager.MAGMA_IMP, pp + Vector3(6, 0, 0))
	await get_tree().physics_frame
	var d1 := cc.debris_count()
	var c1 := cc.corpse_count()
	em.damage(em.index_of(em.uid[ia]), 1e6)
	await get_tree().physics_frame
	_check("an imp bursts into embers and cooling rock chunks, crumbling away", cc.debris_count() >= d1 + 4 and cc.corpse_count() == c1 + 1, "")
	var sl := em.spawn(EnemyManager.LAVA_SLUG, pp + Vector3(-6, 0, 0))
	await get_tree().physics_frame
	em.damage(em.index_of(em.uid[sl]), 1e6)
	await get_tree().physics_frame
	_check("a slug melts into a puddle", cc.corpse_count() == c1 + 2 and int(cc.deaths.get(EnemyManager.LAVA_SLUG, 0)) >= 1, "")
	var ep := em.spawn(EnemyManager.MAGMA_IMP, pp + Vector3(0, 0, 7), 1.0, true)
	var eg := em.spawn(EnemyManager.OBSIDIAN_GOLEM, pp + Vector3(0, 0, -9), 1.0, true)
	await _secs(0.2)
	_check("epics: the Ember Fiend and the Molten Golem have their own looks", cc.drawn(CalderaCrowd.M_FIEND) >= 1 and cc.drawn(CalderaCrowd.M_MOLTEN) >= 1, "")
	_clear(em)
	await _secs(0.2)


func _perf(em: EnemyManager) -> void:
	var player: Player = main.player
	player.global_position = Vector3(0, SwampWater.height_at(0, 0) + 0.5, 0)
	player.velocity = Vector3.ZERO
	_clear(em)
	await get_tree().physics_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var types := [EnemyManager.MAGMA_IMP, EnemyManager.MAGMA_IMP, EnemyManager.MAGMA_IMP, EnemyManager.CINDER_BAT, EnemyManager.OBSIDIAN_GOLEM, EnemyManager.LAVA_SLUG]
	for k in 1400:
		var a := rng.randf() * TAU
		var d := rng.randf_range(8.0, 50.0)
		em.spawn(types[k % types.size()], player.global_position + Vector3(cos(a) * d, 0, sin(a) * d))
	var acc := 0.0
	var n := 0
	for f in 60 * 4:
		main._spawn_budget = -1e9
		player.global_position = Vector3(0, player.global_position.y, 0)
		await get_tree().physics_frame
		if f > 60:
			acc += float(main.perf["enemies"])
			n += 1
	var ms := acc / maxf(n, 1)
	print("PERF caldera crowd at %d enemies: %.2f ms/tick" % [em.alive_count(), ms])
	_check("1,400 caldera enemies tick in reasonable time (%.1f ms)" % ms, ms < 30.0, "")
	_clear(em)
	await _secs(0.3)


func _singe(em: EnemyManager) -> void:
	var player: Player = main.player
	player.global_position = Vector3(0, SwampWater.height_at(0, 0) + 0.5, 0)
	main.run_time = main.THOG_TIME + 0.1
	await _secs(0.3)
	var boss = main.map_boss
	_check("Singe arrives at 8:00", boss is SingeBoss and boss.row() >= 0, str(boss))
	if not (boss is SingeBoss):
		return
	var b: SingeBoss = boss
	var lair := SingeBoss.rise_point()
	_check("...bursting up out of the great lava pool", b.attack == "rise" and MapBoss.flat_dist(em.pos[b.row()], lair) < 3.0 and b.model.rise < 0.5, "%s, %.1f m from the pool" % [b.attack, MapBoss.flat_dist(em.pos[b.row()], lair)])
	_check("...with his name on the HUD bar", b._bar != null and b.display_name() == "SINGE", b.display_name())
	await _secs(SingeBoss.RISE_TIME + 0.3)
	_check("...and once he's out, he comes for you", b.attack != "rise", b.attack)
	var top := b.model.head.global_position.y - em.pos[b.row()].y
	_check("a giant coal imp (head ~5 m up, flame hair over it), far bigger than his imps", top > 4.2 and top < 6.0 and b.model._hair_mi != null and top > CalderaCrowd.IMP_HEIGHT * 4.0, "%.1f m" % top)
	await _until_free(b)
	b._summon_cd = 999.0
	b._breath_cd = 999.0
	b._meteor_cd = 999.0
	b._dive_cd = 999.0
	b._scamper_cd = 999.0
	# claw swipe
	_stand(b, 6.0)
	var hits0: int = b.counts["hits"]
	b._start("swipe")
	_check("claw swipe: a wedge is marked first (%.1f s+)" % MapBoss.MIN_WARN, b._warns.size() >= 1 and float(b._warns[-1]["time"]) >= MapBoss.MIN_WARN, "")
	await _secs(0.8)
	_check("...nothing lands before it fills", b.counts["hits"] == hits0, "")
	await _secs(1.0)
	_check("...then his claws rake through it", b.counts["hits"] == hits0 + 1, str(b.counts["hits"] - hits0))
	# fire breath
	await _until_free(b)
	_stand(b, 10.0)
	var bh0 := b.breath_hits
	var hz0 := b._hazards.size()
	b._start("breath")
	_check("fire breath: a cone is marked first", b._warns.size() >= 1 and float(b._warns[-1]["time"]) >= MapBoss.MIN_WARN, "")
	await _secs(1.8)
	_check("...he spews fire down it and burns you", b.breath_hits == bh0 + 1 and player.burn_left > 0.0, "")
	_check("...and leaves the ground burning", b._hazards.size() >= hz0 + 4 and float(b._hazards[-1]["dps"]) > 0.0, str(b._hazards.size() - hz0))
	# meteor call
	await _until_free(b)
	_stand(b, 16.0)
	var w0 := b._warns.size()
	b._start("meteor")
	var mins := INF
	for k in range(w0, b._warns.size()):
		mins = minf(mins, float(b._warns[k]["time"]))
	_check("meteor call: he juggles, then flings bombs onto %d marked circles, each %.0f s+" % [b._warns.size() - w0, MapBoss.MIN_WARN], b._warns.size() - w0 >= SingeBoss.METEOR_COUNT and mins >= MapBoss.MIN_WARN and b.model.pose == "juggle", "%.2f" % mins)
	await _secs(2.8)
	# summon
	await _until_free(b)
	var imps0 := _count_type(em, EnemyManager.MAGMA_IMP)
	var w1 := b._warns.size()
	b._start("summon")
	_check("summon: marked cracks round you", b._warns.size() - w1 >= 5 and float(b._warns[-1]["time"]) >= MapBoss.MIN_WARN, "")
	await _secs(2.2)
	_check("...and his magma imps claw out of them", _count_type(em, EnemyManager.MAGMA_IMP) >= imps0 + 4, "%d -> %d" % [imps0, _count_type(em, EnemyManager.MAGMA_IMP)])
	_clear(em, true)
	b._start("summon")
	await _secs(2.2)
	_check("...every other time an obsidian golem with them", _count_type(em, EnemyManager.OBSIDIAN_GOLEM) >= 1, "")
	_clear(em, true)
	# the scorch run
	await _until_free(b)
	_stand(b, 10.0)
	var w3 := b._warns.size()
	var pp0 := player.global_position
	b._start("scamper")
	var mins3 := INF
	for k in range(w3, b._warns.size()):
		mins3 = minf(mins3, float(b._warns[k]["time"]))
	_check("scorch run: every footfall of his loop round you is marked first (%.0f s+)" % MapBoss.MIN_WARN, b._warns.size() - w3 == SingeBoss.SCAMPER_MARKS and mins3 >= MapBoss.MIN_WARN, "%d marks, %.2f s" % [b._warns.size() - w3, mins3])
	var far := 0.0
	for f in 60 * 6:
		player.global_position = Vector3(pp0.x, player.global_position.y, pp0.z)
		await get_tree().physics_frame
		far = maxf(far, MapBoss.flat_dist(b.global_position, pp0))
		if b.attack != "scamper":
			break
	_check("...he scampers round you leaving scorch marks", b.scorch_marks == SingeBoss.SCAMPER_MARKS and b._scorches.size() > 0, "%d marks" % b.scorch_marks)
	var sh0 := b.scorch_hits
	player.burn_left = 0.0
	var sat: Vector3 = b._scorches[0]["at"] if not b._scorches.is_empty() else pp0
	player.global_position = Vector3(sat.x, SwampWater.height_at(sat.x, sat.z) + 0.4, sat.z)
	player.velocity = Vector3.ZERO
	await _secs(0.1)
	_check("...step on one and you burn for a few seconds", b.scorch_hits == sh0 + 1 and player.burn_left > 2.0, "%.1f s" % player.burn_left)
	player.global_position = pp0
	await _secs(0.2)
	# lava dive
	await _until_free(b)
	var w2 := b._warns.size()
	b._start("dive")
	await _secs(0.4)
	_check("lava dive: he cannonballs into the lava, tucked in a ball", b.model.curl > 0.9, "%.2f" % b.model.curl)
	await _secs(1.3)
	_check("...and a circle is marked by you where he'll pop out (%.0f s+)" % MapBoss.MIN_WARN, b._warns.size() > w2 and float(b._warns[-1]["time"]) >= MapBoss.MIN_WARN and MapBoss.flat_dist(b.global_position, player.global_position) < 8.0, "")
	await _secs(2.6)
	_check("...then he pops out of it", b.attack != "dive", b.attack)
	_clear(em, true)
	# the Caldera Eruption at 75%
	await _until_free(b)
	em.hp[b.row()] = em.hp_max[b.row()] * 0.74
	for f in 60 * 4:
		await get_tree().physics_frame
		if int(b.counts.get("eruption", 0)) > 0:
			break
	_check("at 75%% health: the Caldera Eruption", int(b.counts.get("eruption", 0)) == 1, "%s/%s hp %.2f" % [b.state, b.attack, b.hp_fraction()])
	_check("...10 s of warning", is_equal_approx(b._windup, SingeBoss.ERUPTION_WARN) and not b.is_flooding(), "%.1f" % b._windup)
	_check("...raised basalt islands burst up round you, each under a glowing arrow", b.islands.size() == SingeBoss.ISLANDS and b.arrow_count() == SingeBoss.ISLANDS, "%d islands, %d arrows" % [b.islands.size(), b.arrow_count()])
	await _secs(1.5)
	var gm := CalderaBuilder.ground_mat
	_check("...the ground's cracks race open and pulse as it builds", gm != null and float(gm.get_shader_parameter("flood_warn")) > 0.05 and float(gm.get_shader_parameter("flood")) == 0.0, "")
	# shelter on an island: the flood passes you by
	var isl: Dictionary = b.islands[0]
	var iat: Vector3 = isl["at"]
	player.god_mode = false
	player.hp = player.max_hp
	var fh0 := b.flood_hits
	player.global_position = Vector3(iat.x, float(isl["top"]) + 0.6, iat.z)
	player.velocity = Vector3.ZERO
	var flooded := false
	for f in 60 * 12:
		player.global_position = Vector3(iat.x, player.global_position.y, iat.z)
		player.velocity = Vector3.ZERO
		if player.hp < player.max_hp * 0.5:
			player.hp = player.max_hp
		await get_tree().physics_frame
		if b.is_flooding():
			flooded = true
		if flooded and b._flood_t > 2.5:
			break
	_check("...then the whole floor floods with lava", flooded and float(gm.get_shader_parameter("flood")) > 0.5, "")
	_check("...sheltering on an island, it passes you by", b.flood_hits == fh0, str(b.flood_hits - fh0))
	player.god_mode = true
	await _until_free(b)
	_check("...and the islands sink again after", b.islands.is_empty() and b.arrow_count() == 0 and float(gm.get_shader_parameter("flood")) == 0.0, "")
	# at 50%, caught on the open ground
	em.hp[b.row()] = em.hp_max[b.row()] * 0.49
	for f in 60 * 4:
		await get_tree().physics_frame
		if int(b.counts.get("eruption", 0)) > 1:
			break
	player.god_mode = false
	player.hp = player.max_hp
	var fh1 := b.flood_hits
	var open := player.global_position
	for f in 60 * 13:
		player.global_position = Vector3(open.x, player.global_position.y, open.z)
		player.velocity = Vector3.ZERO
		if player.hp < player.max_hp * 0.3:
			player.hp = player.max_hp
		await get_tree().physics_frame
		if b.is_flooding() and b._flood_t > 1.5:
			break
	_check("at 50%%: caught off the islands, the flood burns you badly", int(b.counts.get("eruption", 0)) == 2 and b.flood_hits >= fh1 + 2, "%d burns" % (b.flood_hits - fh1))
	player.god_mode = true
	# kill it
	em.damage(b.row(), 1e9)
	await _secs(5.0)
	_check("killing Singe doesn't end the run (a portal opens instead)", main.state != "won" and main.boss_down, main.state)
	_check("...and records his defeat (\"singe\")", Wallet.has_defeated("singe"), str(Wallet.bosses_defeated))
	var dimmed := CalderaBuilder.lava_mats.size() > 0 and float((CalderaBuilder.lava_mats[0] as ShaderMaterial).get_shader_parameter("dim")) < 0.9
	_check("...he gutters out into a heap of cooling coals, and the lava dims", dimmed and b.model._cool > 0.3 and b.model._pile.visible and not b.model._root.visible, "")
	await _through_portal()
	_check("stepping through the portal wins the run", main.state == "won", main.state)


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
	for f in 60 * 25:
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


## The boss is down: the run goes on until you step through the portal that opens (level-ups
## from his XP are taken as they come). Returns once the end screen is up (or after 15 s).
func _through_portal() -> void:
	for f in 60 * 15:
		await get_tree().physics_frame
		if main.state == "levelup":
			main.choose_upgrade(0)
		var pt: BossPortal = main.aftermath.portal
		if pt != null and pt.is_open() and main.state == "playing" and not main.aftermath.entering:
			main.player.global_position = pt.global_position + Vector3(0, 0.4, 0)
			main.player.velocity = Vector3.ZERO
		if main.state == "won":
			return


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		fails += 1
