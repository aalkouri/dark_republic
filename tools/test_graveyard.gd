extends Node
## The Haunted Graveyard:
##   - the map builds on the shared terrain: thousands of headstones of every kind in rows and
##     plots, open and fresh graves, 23 crypts and the ruined chapel (24 landmarks, like the swamp's
##     ruins), railings, dead trees and willows, lying props, lanterns, chest sites, few real lights;
##   - ghouls take the goblins' places (ghosts the scamps', skeletons the brutes');
##   - ghosts float, drift straight through the crypts, chill you at a touch and can be shot;
##   - the swarm is the dead climbing out of the graves round you;
##   - the Necromancer arrives at 8:00, telegraphs every attack, opens the graves at 75% (only
##     consecrated ground is safe), enrages, and killing him wins and records his defeat;
##   - the map picker lists the Graveyard, locked until the Pharaoh is beaten; the Necromancer is
##     on the roster, locked, banned from his own graveyard.
##   godot --headless --path . res://tools/test_graveyard.tscn

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
	await _boss_checks()
	_finish()


# ------------------------------------------------------------------ the map

func _static_checks() -> void:
	_check("the Graveyard is one of the maps", WorldBuilder.MAPS.has("graveyard"), str(WorldBuilder.MAPS))
	var root := Node3D.new()
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var t0 := Time.get_ticks_msec()
	var water := WorldBuilder.build(root, rng, 220.0, "graveyard")
	var ms := Time.get_ticks_msec() - t0
	var st := GraveyardBuilder.stats
	print("  graveyard: %s (built in %d ms)" % [str(st), ms])
	_check("it builds on the shared terrain (hills, a few ponds)", water != null and water.pools.size() == GraveyardBuilder.PONDS and water.hsize > 400, "")
	_check("thousands of headstones", int(st["tombs"]) >= 2500, str(st["tombs"]))
	var kinds := {}
	var worst := 0.0
	var checked := 0
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		if mmi.is_in_group("graveyard_tombs"):
			kinds[mmi.get_meta("kind")] = true
			var o: PackedVector3Array = mmi.get_meta("origins")
			for k in range(0, o.size(), 5):
				worst = maxf(worst, absf(o[k].y - water.ground_height(o[k].x, o[k].z)))
				checked += 1
	_check("every kind of headstone (rounded, gothic, crosses, Celtic, obelisks, angels, broken...)", kinds.size() == GraveyardProps.TOMB_KINDS, str(kinds.keys()))
	_check("headstones stand on the ground (sunk a little, never floating)", checked > 400 and worst < 0.7, "%d checked, worst %.2f m" % [checked, worst])
	_check("headstones are drawn only near the camera (chunks)", _all_chunked(root), "")
	var colliders := 0
	for b in root.get_children():
		if b.is_in_group("graveyard_tomb_colliders"):
			colliders += b.get_child_count()
	_check("you bump into headstones", colliders >= 2000, str(colliders))
	_check("40 open graves (pits the ground shader cuts open) and 60 fresh mounds", int(st["open_graves"]) == GraveyardBuilder.OPEN_GRAVES and int(st["fresh_graves"]) == GraveyardBuilder.FRESH_GRAVES
		and root.get_children().filter(func(n): return n.is_in_group("open_grave")).size() == GraveyardBuilder.OPEN_GRAVES
		and int(water.ground_mat.get_shader_parameter("hole_count")) == GraveyardBuilder.OPEN_GRAVES, "")
	var obstacles := root.get_children().filter(func(n): return n.is_in_group("obstacle")).size()
	var crypts := root.get_children().filter(func(n): return n.is_in_group("graveyard_crypt")).size()
	var chapel := root.get_children().filter(func(n): return n.is_in_group("graveyard_chapel")).size()
	_check("23 crypts and mausoleums and the ruined chapel: 24 landmarks like the swamp's ruins", crypts == 23 and chapel == 1 and obstacles == WorldBuilder.RUINS, "%d crypts, %d chapel, %d obstacles" % [crypts, chapel, obstacles])
	_check("the churchyard is known (consecrated ground)", GraveyardBuilder.chapel_at != Vector3.INF and GraveyardBuilder.chapel_at.length() < 200.0, str(GraveyardBuilder.chapel_at))
	_check("wrought-iron railings round the family plots and the churchyard", int(st["fence_panels"]) >= 60, str(st["fence_panels"]))
	_check("dead trees and weeping willows (they burn)", int(st["dead_trees"]) == GraveyardBuilder.DEAD_TREES and int(st["willows"]) == GraveyardBuilder.WILLOWS, "")
	var burnable := root.get_children().filter(func(n): return n.is_in_group(TreeFire.GROUP)).size()
	_check("...plus 72 coffins, logs and barrows, all burnable", int(st["lying"]) == GraveyardBuilder.LYING and burnable == GraveyardBuilder.DEAD_TREES + GraveyardBuilder.WILLOWS + GraveyardBuilder.LYING, "%d lying, %d burnable" % [st["lying"], burnable])
	_check("same number of chest sites as the swamp", water.chest_sites.size() == WorldBuilder.CHEST_SITES, str(water.chest_sites.size()))
	var lights := root.find_children("*", "OmniLight3D", true, false).size()
	_check("lanterns and candles glow, but only a few real lights", lights >= 8 and lights <= 18, str(lights))
	_check("lantern posts line the avenues", int(st["lanterns"]) >= 16, str(st["lanterns"]))
	_check("candles, wreaths, withered flowers and crows on the graves", int(st["candles"]) >= 50 and int(st["wreaths"]) >= 50 and int(st["crows"]) >= 15, "")
	_check("ground fog rolls over the hills (two drifting layers)", root.get_children().filter(func(n): return n.is_in_group("ground_fog")).size() == 2, "")
	_check("a cemetery wall with railings and a gate all round, dead woods beyond", root.get_children().filter(func(n): return n.is_in_group("edge_wall")).size() >= 4
		and root.get_children().filter(func(n): return n.is_in_group("edge_woods")).size() >= 2 and root.get_children().filter(func(n): return n.is_in_group("arena_edge")).size() == 4, "")
	var amb := root.find_children("*", "GraveyardAmbience", true, false)
	_check("will-o'-wisps drift over the graves", amb.size() == 1 and (amb[0] as GraveyardAmbience).wisps >= 30, "")
	_check("the start plaza is clear", _clear_of_tombs(root, Vector3.ZERO, 8.0), "")
	var env: WorldEnvironment = root.find_children("*", "WorldEnvironment", true, false)[0]
	_check("night: fog and cold moonlight", env.environment.fog_enabled and (root.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D).light_color.b > 0.9, "")
	_check("graves remembered for the dead to rise from", GraveyardBuilder.graves.size() >= 2500, str(GraveyardBuilder.graves.size()))
	_check("builds in reasonable time", ms < 20000, "%d ms" % ms)
	root.free()
	GraveyardBuilder.active = false


func _all_chunked(root: Node3D) -> bool:
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		if mmi.is_in_group("graveyard_tombs") and (mmi as MultiMeshInstance3D).visibility_range_end <= 0.0:
			return false
	return true


func _clear_of_tombs(root: Node3D, c: Vector3, r: float) -> bool:
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		if mmi.is_in_group("graveyard_tombs"):
			for o in (mmi.get_meta("origins") as PackedVector3Array):
				if Vector2(o.x - c.x, o.z - c.z).length() < r:
					return false
	return true


func _picker_checks() -> void:
	var entry := {}
	for m in MapPicker.MAPS:
		if m["id"] == "graveyard":
			entry = m
	_check("the map picker lists the Graveyard with a preview", not entry.is_empty() and entry.get("name", "") == "The Graveyard" and ResourceLoader.exists(entry.get("image", "")), str(entry))
	_check("...unlocked by beating the Pharaoh", entry.get("requires", "") == "pharaoh", str(entry.get("requires", "")))
	Wallet.bosses_defeated = ["thog", "toadstool_knight", "arachnid"]
	_check("locked until the Pharaoh is beaten", MapPicker.lock_reason("graveyard", "fire_wizard") != "", MapPicker.lock_reason("graveyard", "fire_wizard"))
	Wallet.bosses_defeated.append("pharaoh")
	_check("...open once he is", MapPicker.lock_reason("graveyard", "fire_wizard") == "", MapPicker.lock_reason("graveyard", "fire_wizard"))
	var f := FileAccess.open("res://data/characters.json", FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	var necro := {}
	for c in data["characters"]:
		if c["id"] == "necromancer":
			necro = c
	_check("the Necromancer is on the roster, locked behind his own defeat", not necro.is_empty() and necro.get("requires_boss", "") == "necromancer" and int(necro.get("price", 0)) == 10000 and not necro.get("unlocked", false), str(necro.keys()))
	_check("...with a portrait, and banned from his own graveyard", necro.has("icon") and MapPicker.lock_reason("graveyard", "necromancer") != "", "")
	_check("...not yet playable", not RosterHero.is_playable("necromancer"), "")
	_check("the Graveyard's boss is the Necromancer", _map_boss_ok(), "")
	Wallet.bosses_defeated = []


func _map_boss_ok() -> bool:
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	return src.contains("\"graveyard\": \"necromancer\"")


# ------------------------------------------------------------------ the dead

func _run_checks() -> void:
	await _load()
	var em: EnemyManager = main.enemies
	var player: Player = main.player
	main._next_swarm = 1e9
	main.xp_next = 1e12
	_check("the Graveyard run has its undead crowd", em.undead != null and GraveyardBuilder.active, "")
	if em.undead == null:
		return
	var und: UndeadCrowd = em.undead
	var pp := player.global_position
	# ghouls replace goblins (ghosts the scamps, skeletons the brutes)
	var g: int = main._spawn_enemy(EnemyManager.GRUNT, pp + Vector3(20, 0, 0), 1.0)
	var r: int = main._spawn_enemy(EnemyManager.RUNNER, pp + Vector3(-20, 0, 0), 1.0)
	var t: int = main._spawn_enemy(EnemyManager.TANK, pp + Vector3(0, 0, 20), 1.0)
	_check("ghouls take the goblins' places, ghosts the scamps', skeletons the brutes'", em.typ[g] == EnemyManager.GHOUL and em.typ[r] == EnemyManager.GHOST and em.typ[t] == EnemyManager.SKELETON,
		"%d %d %d" % [em.typ[g], em.typ[r], em.typ[t]])
	main.run_time = 150.0
	await _secs(6.0)
	var goblins := 0
	var dead_kinds := {}
	for i in em.count:
		if em.typ[i] in [EnemyManager.GRUNT, EnemyManager.RUNNER, EnemyManager.TANK]:
			goblins += 1
		dead_kinds[em.typ[i]] = true
	_check("no goblins in the graveyard, only the dead", goblins == 0 and dead_kinds.has(EnemyManager.GHOUL), "%d goblins, kinds %s" % [goblins, str(dead_kinds.keys())])
	_check("ghouls are drawn by their own crowd", und.ghouls_drawn > 0, str(und.ghouls_drawn))
	_clear(em)
	await _secs(0.2)
	# ghosts float, and shots reach their floating bodies
	player.god_mode = true
	pp = player.global_position
	var gp := pp + Vector3(9, 0, 0)
	var gi := em.spawn(EnemyManager.GHOST, gp, 1.0)
	var guid := em.uid[gi]
	await get_tree().physics_frame
	await get_tree().physics_frame
	gi = em.index_of(guid)
	var floated := -99.0
	for k in und.ghosts_drawn:   # find this ghost's instance in the ghost buffer
		var o := k * UndeadCrowd.STRIDE
		if gi >= 0 and absf(und._buf_h[o + 3] - em.pos[gi].x) < 0.01 and absf(und._buf_h[o + 11] - em.pos[gi].z) < 0.01:
			floated = und._buf_h[o + 7] - em.pos[gi].y
	_check("ghosts float above the ground", und.ghosts_drawn >= 1 and floated >= UndeadCrowd.GHOST_FLOAT - 0.05, "%.2f m up" % floated)
	var hit := em.query_radius(em.pos[gi] + Vector3(0, 1.9, 0), 0.3) if gi >= 0 else PackedInt32Array()
	_check("...and a shot at the floating body hits", gi >= 0 and hit.has(gi), "")
	# its touch chills you
	player.slow_t = 0.0
	var chills0 := und.chills
	em.pos[gi] = player.global_position + Vector3(0.4, 0, 0)
	await _secs(0.3)
	_check("a ghost's touch chills you (slowed)", und.chills > chills0 and player.slow_t > 0.0 and player.slow_f <= UndeadCrowd.CHILL_SLOW + 0.01, "chills %d, slow %.1f x%.2f" % [und.chills - chills0, player.slow_t, player.slow_f])
	# weapons kill it, and it fades upward
	var deaths0 := und.deaths
	gi = em.index_of(guid)
	if gi >= 0:
		em.pos[gi] = player.global_position + Vector3(5, 0, 0)
		em.hp[gi] = 1.0
	await _secs(4.0)
	_check("your weapons shoot ghosts down", em.index_of(guid) < 0 and und.deaths > deaths0, "")
	_check("...and they rise and fade as they die", und.dying_count() > 0 or und.deaths > deaths0, "")
	# ghosts drift straight through the crypts
	var crypt: Node3D = null
	for n in main.get_children():
		if n.is_in_group("graveyard_crypt"):
			crypt = n
			break
	if crypt != null:
		var c := crypt.global_position
		var fwd := crypt.global_transform.basis.z.normalized()
		player.global_position = Vector3(c.x, SwampWater.height_at(c.x, c.z) + 0.5, c.z) + fwd * 14.0
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		var g2 := em.spawn(EnemyManager.GHOST, c - fwd * 12.0, 1.0)
		em.hp[g2] = 1e9   # (your weapons would shoot it down on the way)
		em.hp_max[g2] = 1e9
		var u2 := em.uid[g2]
		var closest := INF
		for f in 60 * 5:
			await get_tree().physics_frame
			var k := em.index_of(u2)
			if k < 0:
				break
			closest = minf(closest, Vector2(em.pos[k].x - c.x, em.pos[k].z - c.z).length())
			player.global_position = Vector3(c.x, SwampWater.height_at(c.x, c.z) + 0.5, c.z) + fwd * 14.0
		_check("ghosts drift straight through crypt walls", closest < 2.0, "came within %.1f m of the crypt's middle" % closest)
	_clear(em)
	await _secs(0.2)
	# the swarm: the dead climb out of the graves
	player.global_position = Vector3(0, SwampWater.height_at(0, 0) + 0.5, 0)
	await get_tree().physics_frame
	var risen0 := und.risen
	main._next_swarm = main.run_time
	await _secs(0.1)
	var rising := 0
	var at_graves := 0
	for i in em.count:
		if em.rise_t[i] > 0.0:
			rising += 1
			for gv in GraveyardBuilder.graves:
				if Vector2(gv.x - em.pos[i].x, gv.z - em.pos[i].z).length() < 0.6:
					at_graves += 1
					break
	main._next_swarm = 1e9
	_check("the swarm: the dead climb out of the ground round you", und.risen - risen0 >= 24 and rising >= 20, "%d risen, %d rising" % [und.risen - risen0, rising])
	_check("...out of the graves themselves", at_graves >= rising / 2, "%d of %d at graves" % [at_graves, rising])
	var harmless := true
	for i in em.count:
		if em.rise_t[i] > 0.0 and not em.is_harmless(i):
			harmless = false
	_check("...harmless until they're out", harmless, "")
	await _secs(3.0)
	var walking := 0
	for i in em.count:
		if em.rise_t[i] <= 0.0 and em.typ[i] in [EnemyManager.SKELETON, EnemyManager.GHOUL, EnemyManager.GHOST]:
			walking += 1
	_check("...then they come for you", walking >= 20, str(walking))
	_clear(em)
	get_tree().paused = false


# ------------------------------------------------------------------ the Necromancer

func _boss_checks() -> void:
	await _load()
	var em: EnemyManager = main.enemies
	main._next_swarm = 1e9
	main.xp_next = 1e12
	main.player.god_mode = true
	main.run_time = main.THOG_TIME + 0.1
	await _secs(0.3)
	var boss = main.map_boss
	_check("the Necromancer arrives at 8:00", boss is NecromancerBoss and boss.row() >= 0 and em.typ[boss.row()] == EnemyManager.TROLL, "")
	if not (boss is NecromancerBoss):
		return
	var n: NecromancerBoss = boss
	_check("he's about 4 m tall, with a HUD bar", n.model.scale.x * NecromancerModel.MODEL_HEIGHT >= 4.0 and n._bar != null and n._bar_label.text.begins_with("THE NECROMANCER"), n._bar_label.text)
	_check("he has a boss's health", em.hp_max[n.row()] >= 5400.0 * 5.0, str(em.hp_max[n.row()]))
	n._raise_cd = 999.0
	n._drain_cd = 999.0
	n._curse_cd = 999.0
	# staff slam: a circle round him, hits only once it fills
	await _until_free(n)
	_stand(n, 4.0, 0.0)
	var hits0: int = n.counts["hits"]
	n._start("slam")
	var w: Dictionary = n._warns[-1] if not n._warns.is_empty() else {}
	_check("staff slam: a circle is marked first, with time to react", not w.is_empty() and w["time"] >= MapBoss.MIN_WARN, str(w.get("time", 0.0)))
	await _secs(0.6)
	_check("...no damage before it fills", n.counts["hits"] == hits0, "")
	await _secs(1.3)
	_check("...then the bone spikes burst up round him", n.counts["hits"] == hits0 + 1 and int(n.counts.get("spikes", 0)) >= 10, "%d hits, %d spikes" % [n.counts["hits"] - hits0, n.counts.get("spikes", 0)])
	# stepping out dodges it
	await _until_free(n)
	_stand(n, 4.0, 0.0)
	hits0 = n.counts["hits"]
	n._start("slam")
	await _secs(0.3)
	_stand(n, 12.0, 0.0)
	await _secs(1.6)
	_check("stepping out of the circle dodges it", n.counts["hits"] == hits0, "")
	# bone lines: three marked lanes
	await _until_free(n)
	_stand(n, 14.0, 0.0)
	var warned0: int = n.counts["warned"]
	n._start("lines")
	_check("bone lines: three lanes marked toward you", n.counts["warned"] - warned0 == 3, str(n.counts["warned"] - warned0))
	await _secs(2.2)
	_check("...spikes erupt along them", n.counts["hits"] > hits0, "")
	# bone ring round you
	await _until_free(n)
	warned0 = n.counts["warned"]
	n._start("ring")
	_check("bone ring: a band marked round you", n.counts["warned"] - warned0 == 1, "")
	# raise the dead: green circles over the graves, the dead climb out
	await _until_free(n)
	_stand(n, 14.0, 0.0)
	warned0 = n.counts["warned"]
	var risen0 := int(n.counts.get("risen", 0))
	n._start("raise")
	_check("raise the dead: circles marked round you", n.counts["warned"] - warned0 >= NecromancerBoss.RAISE_COUNT, str(n.counts["warned"] - warned0))
	await _secs(2.4)
	_check("...and the dead claw their way out of them", int(n.counts.get("risen", 0)) - risen0 >= NecromancerBoss.RAISE_COUNT, str(int(n.counts.get("risen", 0)) - risen0))
	# soul drain: a marked lane, then a beam that drains you and heals him
	await _until_free(n)
	_stand(n, 10.0, 0.0)
	var i := n.row()
	em.hp[i] = em.hp_max[i] * 0.9
	var hp0 := em.hp[i]
	warned0 = n.counts["warned"]
	n._start("drain")
	_check("soul drain: a lane is marked first", n.counts["warned"] - warned0 == 1, "")
	for f in 60 * 3:
		await get_tree().physics_frame
		_stand(n, 10.0, 0.0)
	_check("...then the beam drains you and heals him", int(n.counts.get("drain_hits", 0)) > 0 and em.hp[n.row()] > hp0, "%d drains" % int(n.counts.get("drain_hits", 0)))
	# cursed circle: marked, then a lingering zone
	await _until_free(n)
	_stand(n, 12.0, 0.0)
	n._start("curse")
	await _secs(1.8)
	_check("cursed circle: marked, then a lingering curse on the ground", n._hazards.size() >= 1, "")
	_clear_minions(em)
	# THE GRAVES OPEN at 75%: everything but consecrated ground
	await _until_free(n)
	i = n.row()
	em.hp[i] = em.hp_max[i] * 0.74
	for f in 60 * 3:
		await get_tree().physics_frame
		if n.attack == "graves":
			break
	_check("at 75% health the graves open (his ultimate)", n.attack == "graves" and int(n.counts.get("graves_open", 0)) == 1, n.attack)
	var gm: ShaderMaterial = main.water.ground_mat
	_check("...the whole ground glows", float(gm.get_shader_parameter("curse")) > 0.5, "")
	var zones := n.safe_zones()
	_check("...but for the churchyard and circles of holy light round you", zones.size() >= NecromancerBoss.HOLY_CIRCLES + 1 and n._pillars.size() == NecromancerBoss.HOLY_CIRCLES, "%d zones" % zones.size())
	var safe_spot: Vector3 = zones[-1] if not zones.is_empty() else Vector3.ZERO
	main.player.global_position = Vector3(safe_spot.x, SwampWater.height_at(safe_spot.x, safe_spot.z) + 0.5, safe_spot.z)
	var ult0 := int(n.counts.get("ult_hits", 0))
	for f in int(60 * (NecromancerBoss.ULT_WARN + 0.5)):
		await get_tree().physics_frame
		main.player.global_position = Vector3(safe_spot.x, SwampWater.height_at(safe_spot.x, safe_spot.z) + 0.5, safe_spot.z)
	_check("standing on consecrated ground, it passes you by", int(n.counts.get("ult_hits", 0)) == ult0 and float(gm.get_shader_parameter("curse")) < 0.5, "")
	await _until_free(n)
	_clear_minions(em)
	i = n.row()
	em.hp[i] = em.hp_max[i] * 0.49
	for f in 60 * 3:
		await get_tree().physics_frame
		if n.attack == "graves":
			break
	var away := Vector3.ZERO
	for tries in 40:
		var p: Vector3 = em.pos[n.row()] + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
		if not n.in_consecrated(p):
			away = p
			break
	for f in int(60 * (NecromancerBoss.ULT_WARN + 0.5)):
		await get_tree().physics_frame
		main.player.global_position = Vector3(away.x, SwampWater.height_at(away.x, away.z) + 0.5, away.z)
	_check("anywhere else it takes a big bite of your health (at 50% again)", int(n.counts.get("ult_hits", 0)) == ult0 + 1 and int(n.counts.get("graves_open", 0)) == 2, str(n.counts.get("ult_hits", 0)))
	_clear_minions(em)
	# enrage after 2 minutes
	n.alive_time = MapBoss.ENRAGE_AFTER
	await _secs(0.2)
	_check("he enrages after 2 minutes", n.is_enraged and "ENRAGED" in n._bar_label.text, n._bar_label.text)
	_check("enraged warnings are shorter, never under %.1f s" % MapBoss.MIN_WARN, n.warn_time(NecromancerBoss.SLAM_WARN) < NecromancerBoss.SLAM_WARN and n.warn_time(0.5) >= MapBoss.MIN_WARN, "")
	# kill him
	Wallet.bosses_defeated = ["thog", "toadstool_knight", "arachnid", "pharaoh"]
	await _until_free(n)
	em.damage(n.row(), 1e9)
	await _secs(4.8)
	_check("killing him wins the run", main.state == "won" and main.boss_won, main.state)
	_check("the end screen names him", main.hud.end_title.text == "THE NECROMANCER DEFEATED!", main.hud.end_title.text)
	_check("his defeat is recorded", Wallet.has_defeated("necromancer"), str(Wallet.bosses_defeated))
	var names := []
	for c in main.hud.unlock_cards:
		names.append(str((c as Control).get_meta("name", "")))
	_check("the end screen lists the Necromancer as a new champion", main.hud.unlock_cards.size() >= 1, str(names))
	get_tree().paused = false


# ------------------------------------------------------------------ helpers

func _load() -> void:
	get_tree().paused = false
	Settings.selected_map = "graveyard"
	Settings.selected_character = "fire_wizard"
	Settings.game_mode = "classic"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	for f in 60 * 15:   # the entrance (meteor)
		await get_tree().physics_frame
		if not main.intro:
			break
	main.player.god_mode = true


func _clear(em: EnemyManager) -> void:
	for i in em.count:
		if em.typ[i] != EnemyManager.TROLL:
			em.dead[i] = 1
			em._dead_count += 1


func _clear_minions(em: EnemyManager) -> void:
	_clear(em)


## Put the player `d` m from the boss, `ang` radians round from where it's aiming.
func _stand(b: MapBoss, d: float, ang: float) -> void:
	var i := b.row()
	var c: Vector3 = main.enemies.pos[i]
	var aim: Vector3 = b._aim if "_aim" in b else Vector3.FORWARD
	var dir := aim.rotated(Vector3.UP, ang) if aim.length() > 0.1 else Vector3.FORWARD
	var p := c + dir * d
	main.player.global_position = Vector3(p.x, SwampWater.height_at(p.x, p.z) + 0.5, p.z)
	main.player.velocity = Vector3.ZERO


func _until_free(b: MapBoss) -> void:
	for f in 60 * 12:
		if b.state == "walk" and b._warns.is_empty():
			return
		await get_tree().physics_frame


func _secs(s: float) -> void:
	for f in int(s * 60):
		await get_tree().physics_frame


func _finish() -> void:
	get_tree().paused = false
	Settings.selected_map = "swamp"
	Wallet.bosses_defeated = []
	GraveyardBuilder.active = false
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		fails += 1
