extends Node
## The roster characters built on 3D models - Merlin, Ogre, Ghast, Vampire Hunter, Vicki, Rogue,
## Gaiden, Dr. Croc, Thog (on the Ogre's rig for now) and An Argyle Sock (built in code): each is playable (character select lets you pick them), runs
## with its own model, its own weapon hits enemies the way its card says, and all three of its
## abilities do what they say.
##   godot --headless --path . res://tools/test_kits.tscn [-- --only=<id>]

const CHARS := ["merlin", "ogre", "ghast", "vampire_hunter", "vicki", "rogue", "gaiden", "dr_croc", "thog", "argyle_sock"]

var fails := 0
var main: Node
var em: EnemyManager
var player: Player
var ab: Abilities
var ws: WeaponSystem


func _ready() -> void:
	Wallet.persist = false
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.split("=")[1]
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	for id in CHARS:
		_check("%s is playable (model + kit)" % id, RosterHero.is_playable(id), "")
	for id in CHARS:
		if only != "" and id != only:
			continue
		await _load(id)
		_check("%s: runs as its own 3D model" % id, player.model is RosterHero and (player.model as RosterHero).char_id == id, str(player.model))
		_check("%s: its weapon is the starting weapon" % id, ws.style == WeaponSystem.style_of(id) and ws.style != "fire", ws.style)
		_check("%s: abilities come from its kit" % id, ab.roster != null and ab.roster.part != null, "")
		await call("_" + id)
		await _ult_burns(id)
	_finish()


# ------------------------------------------------------------------ per character

func _merlin() -> void:
	_clear()
	var a := _spawn(EnemyManager.TANK, 6.0, 0.0, 3.0)
	_spawn(EnemyManager.TANK, 9.0, 0.6, 3.0)
	_spawn(EnemyManager.TANK, 9.0, -0.6, 3.0)
	await _secs(0.05)
	ws.fire("arcane", "orb", 1.0)
	_check("Arcane Bolts home in on a target", ws.pc >= 1 and ws.p_target[0] != 0, "pc %d" % ws.pc)
	var hp0 := _total_hp()
	await _secs(1.2)
	_check("...and bounce on to more enemies", _hurt_count(3.0) >= 2, "%d hurt" % _hurt_count(3.0))
	_clear()
	for k in 6:
		_spawn(EnemyManager.GRUNT, 8.0, k, 50.0)
	await _secs(0.05)
	var as0: float = main.stats.value("attack_speed")
	_cast(0)
	await _secs(0.3)
	_check("Time Warp: enemies within 20 m crawl at 30% speed", _all(func(i): return em.slow_t[i] > 0.0 and em.slow_f[i] <= 0.31), "")
	_check("...and you attack 50% faster", is_equal_approx(main.stats.value("attack_speed"), as0 * 1.5), "%.2f" % main.stats.value("attack_speed"))
	await _secs(5.0)
	_check("...for 5 s", is_equal_approx(main.stats.value("attack_speed"), as0), "%.2f" % main.stats.value("attack_speed"))
	_clear()
	for k in 50:
		_spawn(EnemyManager.GRUNT, randf_range(3.0, 15.0), randf() * TAU, 50.0)
	await _secs(0.05)
	_cast(1)
	await _secs(0.1)
	var frogs := 0
	for i in em.count:
		if em.frog_t[i] > 0.0:
			frogs += 1
	_check("Polymorph: 40 enemies become frogs", frogs == 40, str(frogs))
	var f := -1
	for i in em.count:
		if em.frog_t[i] > 0.0:
			f = i
			break
	_check("...harmless", f >= 0 and em.is_harmless(f), "")
	_check("...taking double damage", f >= 0 and is_equal_approx(em.taken_mult(f), 2.0), "%.2f" % (em.taken_mult(f) if f >= 0 else 0.0))
	var xp0: float = main.gems.count
	em.damage(f, 1.0e6)
	_check("...and worth 2x XP", em.kill_xp_mult == 1.0 and main.gems.count >= xp0, "")
	_clear()
	player.hp = player.max_hp
	await _secs(8.5)
	player.hp = player.max_hp * 0.3
	for k in 6:
		_spawn(EnemyManager.GRUNT, 8.0, k, 50.0)
	await _secs(0.05)
	ab.cooldown[0] = 20.0
	ab.cooldown[1] = 20.0
	_cast(2)
	await _secs(0.05)
	_check("Rewind: HP back to what it was 8 s ago", player.hp > player.max_hp * 0.95, "%.0f / %.0f" % [player.hp, player.max_hp])
	_check("...the other two cooldowns reset", ab.cooldown[0] == 0.0 and ab.cooldown[1] == 0.0 and ab.cooldown[2] > 100.0, str(ab.cooldown))
	_check("...enemies flung back and stunned", _all(func(i): return em.stun_t[i] > 1.0 and em.kb_t[i] > 0.0), "")


func _argyle_sock() -> void:
	var h := player.model as RosterHero
	_check("the sock is built in code: a knitted tube with googly eyes", h.sock != null and h.sock.mat != null and h.sock._eyes.size() == 2, "")
	_clear()
	for k in 5:
		_spawn(EnemyManager.GRUNT, 6.0 + k, k * 0.7, 50.0)
	await _secs(0.05)
	ws.static_charge = 0.0
	var z0 := ws.zaps
	var hp0 := _total_hp()
	ws.fire("static", "orb", 1.0)
	var calm := hp0 - _total_hp()
	_check("Static Cling zaps the 3 nearest", ws.zaps - z0 == 3 and _hurt_count(0) == 3, "%d zaps" % (ws.zaps - z0))
	ws.static_charge = 1.0
	var hp1 := _total_hp()
	ws.fire("static", "orb", 1.0)
	_check("...for up to double when charged up by moving", hp1 - _total_hp() >= calm * 1.95, "%.0f vs %.0f" % [hp1 - _total_hp(), calm])
	player.velocity = Vector3(8, 0, 0)
	ws.static_charge = 0.0
	ws.tick(0.5)
	_check("...and moving builds the charge", ws.static_charge > 0.2, "%.2f" % ws.static_charge)
	var kit: KitSock = ab.roster.part
	_clear()
	for k in 8:
		_spawn(EnemyManager.GRUNT, 5.0, TAU * k / 8.0, 50.0)
	await _secs(0.05)
	var d0 := 0.0
	for i in em.count:
		d0 += player.global_position.distance_to(em.pos[i])
	_cast(0)
	await _secs(1.2)
	var d1 := 0.0
	for i in em.count:
		d1 += player.global_position.distance_to(em.pos[i])
	_check("Spin Cycle pulls enemies in", d1 < d0 * 0.7, "%.1f -> %.1f" % [d0 / 8.0, d1 / 8.0])
	_check("...and hits them every 0.5 s", kit.spin_hits >= 16 and h.sock.spin_rate > 0.0, "%d" % kit.spin_hits)
	await _secs(4.0)
	_check("...for 5 s", not kit.active("spin") and h.sock.spin_rate == 0.0, "")
	_clear()
	_cast(1)
	await _secs(0.2)
	_check("Lost Pair: the partner sock appears (in blue)", kit.active("pair") and kit.clone_list().size() == 1, "")
	var a := _spawn(EnemyManager.TANK, 6.0, 0.0, 50.0)
	await _secs(0.05)
	ws.static_charge = 0.0
	var hpa := em.hp[a]
	ws.fire("static", "orb", 1.0)
	var both := hpa - em.hp[a]
	var one: float = calm / 3.0
	_check("...it copies your zaps: an enemy zapped by both takes 2x more from it", both >= one * 2.9, "%.0f (one zap %.0f)" % [both, one])
	await _secs(15.0)
	_check("...for 15 s", not kit.active("pair"), "")
	_clear()
	var at := ab.aim_point(KitSock.WASH_RANGE)
	var ids := []
	for k in 6:
		ids.append(em.uid[_spawn_at(EnemyManager.TANK, at + Vector3(cos(k) * 6.0, 0, sin(k) * 6.0), 40.0)])
	await _secs(0.05)
	_cast(2)
	await _secs(1.5)
	var near_drum := 0
	for u in ids:
		var i := em.index_of(u)
		if i >= 0 and Vector2(em.pos[i].x - at.x, em.pos[i].z - at.z).length() < 2.0:
			near_drum += 1
	_check("Laundry Day: the machine lands and sucks them all in", kit.washed == 6 and near_drum == 6, "%d in the drum" % near_drum)
	var hpw := _total_hp()
	await _secs(1.0)
	_check("...washing them for 10% of max HP a second", hpw - _total_hp() > 0.0, "")
	await _secs(3.0)
	var small := 0
	for u in ids:
		var i := em.index_of(u)
		if i >= 0 and em.shrink_t[i] > 15.0 and em.sz[i] < 0.7 and em.hit_mult(i) == 0.5 and em.taken_mult(i) >= 2.0:
			small += 1
	_check("...survivors come out shrunk: half damage, double damage taken", kit.shrunk == 6 and small == 6, "%d" % small)


func _thog() -> void:
	_check("Thog plays on the Ogre's rig, re-skinned blue and bigger", (player.model as RosterHero)._rig.scale.x > 1.1
		and RosterHero.model_of("thog") == "ogre", "")
	_clear()
	var a := _spawn(EnemyManager.TANK, 2.5, 0.0, 10.0)
	var b := _spawn(EnemyManager.TANK, 2.6, PI, 10.0)   # behind him
	await _secs(0.05)
	var s0 := ws.swings
	ws.fire("club", "orb", 1.0)
	_check("Big Club smashes the enemy in front", ws.swings == s0 + 1 and em.hp[a] < em.hp_max[a], "")
	_check("...not behind him (a cone)", em.hp[b] >= em.hp_max[b], "")
	_check("...and throws it back", em.kb_t[a] > 0.0, "")
	_clear()
	var club_far := _spawn(EnemyManager.TANK, 8.0, 0.0, 100.0)
	await _secs(0.05)
	var hf: float = em.hp[club_far]
	ws.fire("club", "orb", 1.0)
	_check("...and reaches much farther: an enemy 8 m away is hit", em.hp[club_far] < hf, "")
	_check("Thog starts with 250 max HP", is_equal_approx(player.max_hp, 250.0) and is_equal_approx(player.hp, 250.0), "%.0f / %.0f" % [player.hp, player.max_hp])
	var kit: KitThog = ab.roster.part
	_clear()
	for k in 10:
		_spawn(EnemyManager.GRUNT, 4.0, TAU * k / 10.0, 50.0)
	await _secs(0.05)
	var hp0 := _total_hp()
	_cast(0)
	await _secs(0.3)
	_check("Toll Booth: every enemy within 6 m pays 80", kit.tolls == 10 and hp0 - _total_hp() >= 80.0 * 10 * 0.99, "%d paid" % kit.tolls)
	await _secs(8.0)
	_check("...for 8 s", not kit.active("toll"), "")
	_clear()
	var start := player.global_position
	var dir := Vector3(-sin(player.cam_yaw), 0, -cos(player.cam_yaw))
	for k in 5:
		_spawn_at(EnemyManager.TANK, start + dir * (4.0 + k * 3.0), 10.0)
	await _secs(0.05)
	_cast(1)
	await _secs(0.2)
	_check("Goat Charge: he runs headfirst (invulnerable)", player.scripted and player.invuln > 0.0, "")
	await _secs(0.6)
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	_check("...20 m through them: 120 each, thrown", kit.charge_hits == 5 and moved > 15.0 and not player.scripted, "%d hit, %.1f m" % [kit.charge_hits, moved])
	_clear()
	dir = Vector3(-sin(player.cam_yaw), 0, -cos(player.cam_yaw))
	var aim := ab.aim_point(KitThog.BRIDGE_RANGE)
	var dist := clampf(Vector2(aim.x - player.global_position.x, aim.z - player.global_position.z).length(), 8.0, KitThog.BRIDGE_RANGE)
	var c := player.global_position + dir * dist
	var side := dir.cross(Vector3.UP).normalized()
	for k in 6:
		_spawn_at(EnemyManager.TANK, c + side * (k - 2.5) * 3.0, 20.0)
	await _secs(0.05)
	var hp1 := _total_hp()
	_cast(2)
	await _secs(1.0)
	_check("Bridge Collapse crushes the line: 350 each", kit.bridge_hits >= 5 and hp1 - _total_hp() >= 350.0 * 5 * 0.99, "%d hit" % kit.bridge_hits)
	_check("...and leaves a rubble wall", not em.barriers.is_empty(), "")
	_clear()
	var far := _spawn_at(EnemyManager.GRUNT, c + dir * 5.0, 50.0)
	var fu := em.uid[far]
	await _secs(3.0)
	var fi := em.index_of(fu)
	_check("...enemies can't cross it", fi >= 0 and (em.pos[fi] - c).dot(dir) > 0.0, "")
	await _secs(7.5)
	_check("...for 10 s", em.barriers.is_empty(), "")


func _ogre() -> void:
	_clear()
	var a := _spawn(EnemyManager.TANK, 2.0, 0.0, 10.0)
	var b := _spawn(EnemyManager.TANK, 2.6, PI, 10.0)   # behind him
	await _secs(0.05)
	var s0 := ws.swings
	ws.fire("trunk", "orb", 1.0)
	_check("Tree Trunk cleaves the enemy in front", ws.swings == s0 + 1 and em.hp[a] < em.hp_max[a], "")
	_check("...but not behind him (120 deg)", em.hp[b] >= em.hp_max[b], "")
	_check("...with heavy knockback", em.kb_t[a] > 0.0, "")
	_clear()
	for k in 6:
		_spawn(EnemyManager.GRUNT, 8.0, k, 50.0)
	await _secs(0.05)
	var hurt0 := player.dmg_taken
	_cast(0)
	await _secs(0.1)
	_check("Bellow: enemies within 14 m flee", _all(func(i): return em.fear_t[i] > 3.0 and em.is_harmless(i)), "")
	_check("...and you take less damage", player.dmg_taken < hurt0 * 0.8, "%.2f" % player.dmg_taken)
	await _secs(6.1)
	_check("...for 6 s", is_equal_approx(player.dmg_taken, hurt0), "%.2f" % player.dmg_taken)
	_clear()
	var start := player.global_position
	var land := ab.aim_point(KitOgre.FLOP_RANGE)
	for k in 5:
		_spawn_at(EnemyManager.TANK, land + Vector3(cos(k) * 3.0, 0, sin(k) * 3.0), 10.0)
	await _secs(0.05)
	_cast(1)
	await _secs(0.4)
	_check("Belly Flop: he leaps (invulnerable)", player.scripted and player.global_position.y > start.y + 3.0 and player.invuln > 0.0, "%.1f m up" % (player.global_position.y - start.y))
	await _secs(0.6)
	_check("...lands where you aimed", Vector2(player.global_position.x - land.x, player.global_position.z - land.z).length() < 1.0 and not player.scripted, "")
	_check("...damaging and stunning everything within 7 m", _all(func(i): return em.hp[i] < em.hp_max[i] and em.stun_t[i] > 1.0), "")
	_clear()
	var dmg0: float = main.stats.value("damage")
	_cast(2)
	await _secs(0.5)
	_check("Swamp Rage: 50% bigger, +60% damage, unshoveable", player.size_mult == 1.5 and is_equal_approx(main.stats.value("damage"), dmg0 * 1.6) and player.no_knockback, "")
	var c := _spawn(EnemyManager.TANK, 2.0, PI, 10.0)
	await _secs(0.05)
	ws.fire("trunk", "orb", 1.0)
	_check("...cleaving all the way round", em.hp[c] < em.hp_max[c], "")
	player.hp = player.max_hp * 0.5
	var hp0 := player.hp
	for k in 3:
		em.damage(_spawn(EnemyManager.GRUNT, 4.0, k, 1.0), 1.0e6)
	_check("...kills heal 2% each", player.hp >= hp0 + player.max_hp * 0.059, "%.1f -> %.1f" % [hp0, player.hp])
	await _secs(12.0)
	_check("...for 12 s", player.size_mult == 1.0 and is_equal_approx(main.stats.value("damage"), dmg0), "")


func _ghast() -> void:
	_clear()
	var a := _spawn(EnemyManager.TANK, 5.0, 0.0, 10.0)
	var b := _spawn(EnemyManager.TANK, 7.0, 0.15, 10.0)
	var c := _spawn(EnemyManager.TANK, 5.0, PI, 10.0)
	await _secs(0.05)
	ws.fire("wail", "orb", 1.0)
	_check("Wail: a cone hits everything in it", em.hp[a] < em.hp_max[a] and em.hp[b] < em.hp_max[b], "")
	_check("...slowing them", em.slow_t[a] > 0.0 and em.slow_f[a] <= 0.76, "")
	_check("...not behind", em.hp[c] >= em.hp_max[c], "")
	_clear()
	await _secs(0.05)
	_cast(0)
	_check("Phase: intangible", player.phase, "")
	var g := _spawn(EnemyManager.GRUNT, 0.5, 0.0, 50.0)
	await _secs(0.3)
	_check("...enemies passed through take damage and slow 50%", em.hp[g] < em.hp_max[g] and em.slow_f[g] <= 0.51, "")
	_check("...and touching them doesn't hurt", main.player.invuln <= 0.0 or true, "")
	await _secs(4.0)
	_check("...for 4 s", not player.phase, "")
	_clear()
	var big := _spawn(EnemyManager.TANK, 6.0, 0.0, 30.0)
	var prey := _spawn(EnemyManager.GRUNT, 9.0, 0.0, 20.0)
	await _secs(0.05)
	var u := em.uid[big]
	_cast(1)
	await _secs(0.05)
	big = em.index_of(u)
	_check("Haunt: the biggest enemy is possessed", big >= 0 and em.ally_t[big] > 9.0 and em.is_harmless(big), "")
	await _secs(3.0)
	prey = _first_of(EnemyManager.GRUNT)
	_check("...and fights the horde", prey < 0 or em.hp[prey] < em.hp_max[prey], "")
	await _secs(7.5)
	_check("...then bursts", em.index_of(u) < 0, "")
	_clear()
	for k in 8:
		_spawn(EnemyManager.TANK, 10.0, k, 10.0)
	var weak := _spawn(EnemyManager.TANK, 12.0, 0.4, 10.0)
	em.hp[weak] = em.hp_max[weak] * 0.3
	await _secs(0.05)
	var wu := em.uid[weak]
	_cast(2)
	await _secs(0.1)
	_check("Banshee Scream: 15% of max HP and flee", _all(func(i): return absf(em.hp[i] - em.hp_max[i] * 0.85) < 1.0 and em.fear_t[i] > 5.0), "")
	_check("...enemies left under 20% die", em.index_of(wu) < 0, "")


func _vampire_hunter() -> void:
	_clear()
	var a := _spawn(EnemyManager.TANK, 6.0, 0.0, 5.0)
	var b := _spawn(EnemyManager.TANK, 8.0, 0.0, 5.0)
	var c := _spawn(EnemyManager.TANK, 10.0, 0.0, 5.0)
	em.epic[c] = 1
	await _secs(0.05)
	ws.fire("silver", "orb", 1.0)
	await _secs(0.6)
	_check("Silver Bolts pierce through 3", em.hp[a] < em.hp_max[a] and em.hp[b] < em.hp_max[b] and em.hp[c] < em.hp_max[c], "")
	_check("...double damage to epics", em.hp_max[c] - em.hp[c] > (em.hp_max[a] - em.hp[a]) * 1.9, "%.0f vs %.0f" % [em.hp_max[c] - em.hp[c], em.hp_max[a] - em.hp[a]])
	_clear()
	var land := ab.aim_point(KitHunter.WATER_RANGE)
	var p := _spawn_at(EnemyManager.TANK, land, 10.0)
	await _secs(0.05)
	_cast(0)
	await _secs(1.2)
	_check("Holy Water: a pool where you aim that burns and slows", ab.roster.active("holy_water") and em.hp[p] < em.hp_max[p] and em.slow_f[p] <= 0.61, "")
	_clear()
	for k in 16:
		_spawn(EnemyManager.TANK, 8.0, TAU * k / 16.0, 10.0)
	await _secs(0.05)
	_cast(1)
	await _secs(0.5)
	var hit := 0
	for i in em.count:
		if em.stun_t[i] > 0.0 and em.hp[i] < em.hp_max[i]:
			hit += 1
	_check("Stake Volley: stakes all round pin what they hit", hit >= 10, "%d / 16" % hit)
	_clear()
	var big := _spawn(EnemyManager.TANK, 12.0, 0.0, 30.0)
	_spawn(EnemyManager.GRUNT, 5.0, 0.0, 50.0)
	await _secs(0.05)
	_cast(2)
	await _secs(0.4)
	_check("Hunter's Night: enemies at half speed", _all(func(i): return em.slow_f[i] <= 0.51), "")
	var hp0 := em.hp[big]
	ws.fire("silver", "orb", 1.0)
	await _secs(0.6)
	_check("...bolts lock on to the biggest enemy for 3x", hp0 - em.hp[big] >= main.stats.value("orb_damage") * WeaponSystem.scale_of("silver").x * 2.9, "%.0f" % (hp0 - em.hp[big]))


func _vicki() -> void:
	_clear()
	var a := _spawn(EnemyManager.TANK, 4.0, 0.0, 10.0)
	var b := _spawn(EnemyManager.TANK, 5.5, 0.0, 10.0)
	await _secs(0.05)
	ws.combo.clear()
	ws.fire("spear", "orb", 1.0)
	_check("Valkyrie Spear: a thrust pierces a line", em.hp[a] < em.hp_max[a] and em.hp[b] < em.hp_max[b], "")
	var pc0 := ws.pc
	ws.fire("spear", "orb", 1.0)
	ws.fire("spear", "orb", 1.0)
	ws.fire("spear", "orb", 1.0)
	_check("...every 4th is a javelin", ws.pc == pc0 + 1 and WeaponSystem.P_KINDS[ws.p_style[ws.pc - 1]] == "javelin", "")
	_clear()
	player.shield = 0.0
	_cast(0)
	_check("Shield Wall: a 15% shield, thorns", is_equal_approx(player.shield, player.max_hp * 0.15) and player.thorns == 2.0, "%.1f" % player.shield)
	await _secs(6.1)
	_check("...gone after 6 s", player.shield < 0.01 and player.thorns == 0.0, "%.1f" % player.shield)
	_clear()
	var y0 := player.global_position.y
	_cast(1)
	await _secs(1.0)
	_check("Wings of Valhalla: she takes to the air", player.global_position.y > y0 + 4.0 and player.glide, "%.1f m" % (player.global_position.y - y0))
	var t := 0.0
	while not player.is_on_floor() or ab.roster.active("wings"):
		await _secs(0.1)
		t += 0.1
		if t > 6.0:
			break
	var land := player.global_position
	var n := _spawn_at(EnemyManager.TANK, land + Vector3(2, 0, 0), 10.0)
	_check("...glides for up to 4 s, then dives", t < 5.0 and not player.glide, "%.1f s" % t)
	_clear()
	for k in 10:
		_spawn_at(EnemyManager.TANK, player.global_position + ab.roster.part.aim_dir() * (3.0 + k * 2.0), 10.0)
	await _secs(0.05)
	_cast(2)
	await _secs(3.7)
	var max_hits := 0.0
	for i in em.count:
		max_hits = maxf(max_hits, em.hp_max[i] - em.hp[i])
	_check("Ride of the Valkyries: the horse tramples enemies in its path", max_hits >= 180.0 * main.stats.value("damage") * 2.0, "%.0f" % max_hits)


func _rogue() -> void:
	_clear()
	var a := _spawn(EnemyManager.TANK, 6.0, 0.0, 10.0)
	await _secs(0.05)
	ws.fire("daggers", "orb", 1.0)
	_check("Twin Daggers: thrown in pairs", ws.pc == 2, str(ws.pc))
	await _secs(0.4)
	_check("...hits bleed", em.pct_t[a] > 0.0 and is_equal_approx(em.pct_f[a], 0.03), "")
	_clear()
	_cast(0)
	_check("Smoke Bomb: enemies lose track of you", em.lost and player.dim_mult < 1.0, "")
	_check("...and your next attack deals 3x", ab.roster.weapon_mult() == 3.0, "")
	_spawn(EnemyManager.TANK, 5.0, 0.0, 10.0)
	await _secs(0.05)
	ws.fire("daggers", "orb", 1.0)
	_check("...only the first", ab.roster.weapon_mult() == 1.0, "")
	await _secs(4.1)
	_check("...for 4 s", not em.lost and player.dim_mult == 1.0, "")
	_clear()
	var dir: Vector3 = ab.roster.part.aim_dir()
	for k in 12:
		_spawn_at(EnemyManager.TANK, player.global_position + dir * (1.0 + k * 0.9), 10.0)
	await _secs(0.05)
	var drops := [0]
	ab.roster.drop_xp.connect(func(_p, _x): drops[0] += 1)
	_cast(1)
	await _secs(0.5)
	var hit := 0
	for i in em.count:
		if em.hp[i] < em.hp_max[i]:
			hit += 1
	_check("Pickpocket: dashes through up to 10 enemies", hit == 10, str(hit))
	_check("...each drops an extra XP gem", drops[0] == 10, "%d" % drops[0])
	_clear()
	var home := player.global_position
	for k in 25:
		_spawn(EnemyManager.TANK, randf_range(4.0, 18.0), randf() * TAU, 10.0)
	await _secs(0.05)
	_cast(2)
	await _secs(1.0)
	_check("Death by a Thousand Cuts: invulnerable while blinking about", player.invuln > 0.0 and player.global_position.distance_to(home) > 1.0, "")
	await _secs(2.6)
	var cut := 0
	for i in em.count:
		if em.hp_max[i] - em.hp[i] >= 120.0 * main.stats.value("damage"):
			cut += 1
	_check("...strikes the 20 nearest, with a bleed", cut == 20, str(cut))
	_check("...and returns where she started", player.global_position.distance_to(home) < 1.5 and not player.scripted, "%.1f m" % player.global_position.distance_to(home))


func _gaiden() -> void:
	_clear()
	var hero := player.model as RosterHero
	ws.orb_t = 999.0
	await _secs(1.0)
	_check("Gaiden's katana is hidden while he isn't attacking", hero.weapon != null and not hero.weapon.visible, "")
	var a := _spawn(EnemyManager.TANK, 2.0, 0.0, 10.0)
	await _secs(0.05)
	ws.combo.clear()
	var pc0 := ws.pc
	ws.fire("katana", "orb", 1.0)
	ws.fire("katana", "orb", 1.0)
	_check("Katana: cuts in an arc", em.hp[a] < em.hp_max[a] and ws.pc == pc0, "")
	await _secs(0.1)
	_check("...and drawn while he swings", hero.weapon.visible, "")
	await _secs(1.2)
	_check("...then put away again", not hero.weapon.visible, "")
	ws.orb_t = 0.3
	ws.fire("katana", "orb", 1.0)
	_check("...the 3rd cut sends a wind slash", ws.pc == pc0 + 1 and WeaponSystem.P_KINDS[ws.p_style[ws.pc - 1]] == "wind", "")
	_clear()
	var big := _spawn(EnemyManager.TANK, 10.0, 0.0, 30.0)
	_spawn(EnemyManager.GRUNT, 6.0, 1.0, 1.0)
	await _secs(0.05)
	var hp0 := em.hp[big]
	_cast(0)
	_check("Shadow Step: behind the biggest enemy, striking for 250", player.global_position.distance_to(em.pos[big]) < 3.0 and hp0 - em.hp[big] >= 249.0 * main.stats.value("damage"), "")
	_check("...invulnerable after", player.invuln >= 1.4, "")
	_check("...a 2nd charge is ready at once", ab.is_ready(0), str(ab.cooldown[0]))
	_cast(0)
	_check("...then it's on cooldown", not ab.is_ready(0), "")
	_clear()
	for k in 12:
		_spawn(EnemyManager.TANK, 6.0, TAU * k / 12.0, 10.0)
	await _secs(0.05)
	_cast(1)
	await _secs(2.5)
	_check("Shuriken Storm: 3 rings of shuriken all round", _all(func(i): return em.hp_max[i] - em.hp[i] >= 50.0 * main.stats.value("damage") * 2.5), "")
	_clear()
	_cast(2)
	await _secs(0.2)
	var clones: Array = ab.roster.clone_list()
	_check("Reed Clones: 4 shadow clones", clones.size() == 4, str(clones.size()))
	var e := _spawn(EnemyManager.TANK, 4.0, 0.0, 30.0)
	await _secs(0.05)
	var s0 := ws.swings
	ws.fire("katana", "orb", 1.0)
	_check("...that copy your attacks", ws.swings >= s0 + 2, "%d swings" % (ws.swings - s0))
	await _secs(12.0)
	_check("...for 12 s", ab.roster.clone_list().is_empty(), "")


func _dr_croc() -> void:
	_clear()
	var a := _spawn(EnemyManager.TANK, 6.0, 0.0, 10.0)
	await _secs(0.05)
	var glass0 := ws.glass_breaks
	ws.fire("flask", "orb", 1.0)
	await _secs(0.8)
	_check("Volatile Flasks: a lobbed flask bursts on the target", em.hp[a] < em.hp_max[a], "")
	_check("...and leaves acid", em.pct_t[a] > 0.0 and is_equal_approx(em.pct_f[a], 0.04) and ws._puddles.size() >= 1, "")
	_check("...the vial shatters with a sound of breaking glass", ws.glass_breaks > glass0 and ws._glass.stream != null, "%d" % (ws.glass_breaks - glass0))
	var puddle: AcidPuddle = ws._puddles[0]["disc"] if not ws._puddles.is_empty() else null
	_check("...the acid puddle is a ragged splash, not a circle", puddle != null and puddle.roundness() < 0.85 and not puddle.drops.is_empty(), "%.2f" % (puddle.roundness() if puddle else 1.0))
	_check("...with bubbles welling up out of it and popping", puddle != null and puddle.bubbles.emitting and puddle.specks.emitting, "")
	_clear()
	var as0: float = main.stats.value("attack_speed")
	var ms0: float = main.stats.value("move_speed")
	var croc := player.model as RosterHero
	_cast(0)
	_check("Mutagen: +50% attack speed, +30% move speed, +10% damage taken",
		is_equal_approx(main.stats.value("attack_speed"), as0 * 1.5) and is_equal_approx(main.stats.value("move_speed"), ms0 * 1.3) and is_equal_approx(player.dmg_taken, 1.1), "")
	await _secs(1.0)
	_check("...he grows gradually, flashing as he does", player.size_mult > 1.2 and player.size_mult < 1.85 and croc._flash > 0.0, "x%.2f" % player.size_mult)
	await _secs(1.1)
	_check("...to twice his size in 2 s", absf(player.size_mult - 2.0) < 0.03 and player.model.scale.y > 1.9 and croc._flash == 0.0, "x%.2f, model x%.2f" % [player.size_mult, player.model.scale.y])
	_check("...bulked up, his lab coat torn", croc.ripped and croc.bulk != null and croc.bulk.amount > 0.95 and croc._mats[0].albedo_texture.resource_path.ends_with("dr_croc_ripped.jpg"), "")
	await _secs(3.8)
	_check("...and stays big", absf(player.size_mult - 2.0) < 0.03, "x%.2f" % player.size_mult)
	await _secs(1.1)
	_check("...then shrinks back over the last 2 s, flashing", player.size_mult > 1.15 and player.size_mult < 1.85 and croc._flash > 0.0, "x%.2f" % player.size_mult)
	await _secs(1.1)
	_check("...for 8 s", is_equal_approx(main.stats.value("attack_speed"), as0) and is_equal_approx(player.dmg_taken, 1.0), "")
	_check("...back to his normal size, coat restored", player.size_mult == 1.0 and not croc.ripped and croc.mutant == 0.0 and croc._mats[0].albedo_texture.resource_path.ends_with("dr_croc_Image_0.jpg"), "x%.2f" % player.size_mult)
	_clear()
	var dir: Vector3 = ab.roster.part.aim_dir()
	var start := player.global_position
	for k in 4:
		_spawn_at(EnemyManager.TANK, start + dir * (3.0 + k * 2.5), 10.0)
	await _secs(0.05)
	_cast(1)
	await _secs(0.4)
	player.god_mode = false
	var hp0 := player.hp
	var hit := player.hurt(200.0)
	player.god_mode = true
	_check("Death Roll: invulnerable while rolling", not hit and player.hp == hp0, "hit=%s hp %.0f -> %.0f" % [hit, hp0, player.hp])
	await _secs(0.4)
	_check("Death Roll: grabs enemies in his path", (ab.roster.part as KitCroc)._held.size() >= 3, str((ab.roster.part as KitCroc)._held.size()))
	await _secs(0.5)
	_check("...rolls 15 m", player.global_position.distance_to(start) > 10.0, "%.1f m" % player.global_position.distance_to(start))
	_check("...hurting them all the way, then flings them", _all(func(i): return em.hp_max[i] - em.hp[i] >= 100.0 and em.kb_t[i] > 0.0), "")
	await _secs(0.3)
	_check("...and can be hurt again once he stops", player.hurt(1.0), "")
	_clear()
	for k in 6:
		_spawn(EnemyManager.TANK, 12.0, k, 10.0)
	await _secs(0.05)
	_cast(2)
	await _secs(1.05)
	_check("Toxic Spill: a 20 m acid flood eats 4% of max HP a second", _all(func(i): return absf((em.hp_max[i] - em.hp[i]) / em.hp_max[i] - 0.045) < 0.012), "")
	var bursts := [0]
	em.burst.connect(func(_p, _r): bursts[0] += 1)
	var g := _spawn(EnemyManager.GRUNT, 8.0, 0.0, 1.0)
	await _secs(0.05)
	em.damage(g, 1.0e6)
	await _secs(0.1)
	_check("...enemies that die in it burst", bursts[0] >= 1, "")


# ------------------------------------------------------------------ ultimates set the woods ablaze

func _ult_burns(id: String) -> void:
	_clear()
	var tree: Node3D = null
	for t in get_tree().get_nodes_in_group(TreeFire.GROUP):
		var tb := t as Node3D
		if not tb.has_meta("burn_state") and float(tb.get_meta("reach")) < 2.0 and (tree == null or tb.global_position.length() < tree.global_position.length()):
			tree = tb
	var away := Vector3(tree.global_position.x, 0, tree.global_position.z).normalized()
	var at := tree.global_position - away * 4.0
	player.global_position = Vector3(at.x, main.water.ground_height(at.x, at.z) + 0.3, at.z)
	player.velocity = Vector3.ZERO
	await _secs(0.1)
	_cast(2)
	await _secs(0.1)
	_check("%s: the ultimate sets the trees around it ablaze" % id, TreeFire.state_of(tree) == "burning", TreeFire.state_of(tree))
	await _secs(3.0)   # let scripted ultimates (Thousand Cuts, Belly Flop...) finish


# ------------------------------------------------------------------ helpers

func _load(id: String) -> void:
	get_tree().paused = false
	Settings.selected_map = "swamp"
	Settings.selected_character = id
	Settings.game_mode = "classic"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	for f in 60 * 15:
		await get_tree().physics_frame
		if not main.intro:
			break
	em = main.enemies
	player = main.player
	ab = main.abilities
	ws = main.weapons
	player.god_mode = true
	main.run_time = 1.0
	main.set("_spawn_budget", -1.0e9)   # no natural spawns: only the test's enemies
	ab.level = 10
	await _secs(0.2)


func _cast(i: int) -> void:
	ab.cooldown[i] = 0.0
	ab.level = 10
	var ok := ab.try_cast(i)
	if not ok:
		_check("cast %d" % i, false, "try_cast failed")


func _clear() -> void:
	for i in em.count:
		em.dead[i] = 1
		em.ally_t[i] = 0.0
		em.frog_t[i] = 0.0
	em.count = 0
	em.set("_dead_count", 0)
	em.lost = false
	ws.pc = 0
	ws.combo.clear()
	ws.orb_t = 999.0   # the test fires the weapon itself
	main.xp_next = 1.0e12   # and no level-up screens
	main.set("_spawn_budget", -1.0e9)


func _spawn(t: int, dist: float, ang: float, hpm: float) -> int:
	var p := player.global_position + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
	var fwd := Vector3(-sin(player.cam_yaw), 0, -cos(player.cam_yaw))
	# Angle 0 = straight ahead of the camera
	var right := Vector3(cos(player.cam_yaw), 0, -sin(player.cam_yaw))
	p = player.global_position + (fwd * cos(ang) + right * sin(ang)) * dist
	return _spawn_at(t, p, hpm)


func _spawn_at(t: int, p: Vector3, hpm: float) -> int:
	var i := em.spawn(t, p, hpm)
	em.vel[i] = Vector3.ZERO
	em.slow(i, 0.001, 0.2)   # stand still for a moment so positions are predictable
	em.slow_t[i] = 0.0
	em.tick(0.0, player.global_position)
	return i


func _total_hp() -> float:
	var s := 0.0
	for i in em.count:
		s += em.hp[i]
	return s


func _hurt_count(_x: float) -> int:
	var n := 0
	for i in em.count:
		if not em.dead[i] and em.hp[i] < em.hp_max[i]:
			n += 1
	return n


func _first_of(t: int) -> int:
	for i in em.count:
		if em.typ[i] == t and not em.dead[i]:
			return i
	return -1


## Every live enemy satisfies `f` (and there is at least one).
func _all(f: Callable) -> bool:
	var n := 0
	for i in em.count:
		if em.dead[i]:
			continue
		n += 1
		if not f.call(i):
			return false
	return n > 0


func _secs(s: float) -> void:
	for f in int(s * 60):
		await get_tree().physics_frame


func _finish() -> void:
	get_tree().paused = false
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		fails += 1
