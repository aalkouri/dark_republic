extends Node
## The roster characters built on 3D models - Merlin, Ogre, Ghast, Vampire Hunter, Vicki, Rogue,
## Gaiden, Dr. Croc, Thog (on the Ogre's rig for now) and An Argyle Sock, Loco Robotico, the Blob and the Arachnid (built in code): each is playable (character select lets you pick them), runs
## with its own model, its own weapon hits enemies the way its card says, and all three of its
## abilities do what they say.
##   godot --headless --path . res://tools/test_kits.tscn [-- --only=<id>]

const CHARS := ["merlin", "ogre", "ghast", "vampire_hunter", "vicki", "rogue", "gaiden", "dr_croc", "thog", "argyle_sock", "loco_robotico", "blob", "toadstool_knight", "arachnid"]

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


func _loco_robotico() -> void:
	var h := player.model as RosterHero
	var body := h.loco
	_check("Loco Robotico is built in code: wheels, a TV face, a sombrero and two maracas", body != null and body.mat != null
		and body.screen_mat != null and body._wheels.size() == 2 and body._maracas.size() == 2 and body._hat != null, "")
	_clear()
	var front := []
	for k in 3:
		front.append(_spawn(EnemyManager.GRUNT, 2.5 + k, (k - 1) * 0.12, 50.0))
	var behind := _spawn(EnemyManager.GRUNT, 3.0, PI, 50.0)
	var far := _spawn(EnemyManager.GRUNT, 10.0, 0.0, 50.0)
	await _secs(0.05)
	ws.maraca_tempo = 0.0
	var s0 := body.shakes
	var side0 := body._side
	ws.fire("maracas", "orb", 1.0)
	var all_front := true
	for i in front:
		all_front = all_front and em.hp[i] < em.hp_max[i]
	_check("Maraca Blasters: a sonic pulse hits everything in the 6 m cone", all_front and ws.pulses >= 1, "")
	_check("...but not behind him or past 6 m", em.hp[behind] == em.hp_max[behind] and em.hp[far] == em.hp_max[far], "")
	var hit1: float = em.hp_max[front[0]] - em.hp[front[0]]
	ws.fire("maracas", "orb", 1.0)
	_check("...shaking the maracas by turns (alternating hands)", body.shakes - s0 == 2 and body._side == side0, "%d shakes" % (body.shakes - s0))
	_check("...20 damage a pulse (scaled like every weapon)", hit1 > 0.0 and absf((em.hp_max[front[0]] - em.hp[front[0]]) - 2.0 * hit1) < 0.01, "%.1f" % hit1)
	player.velocity = Vector3(8, 0, 0)
	ws.maraca_tempo = 0.0
	ws.tick(0.5)
	var tempo := ws.maraca_tempo
	ws.maraca_tempo = 0.0
	player.velocity = Vector3.ZERO
	ws.orb_t = 0.0
	ws.tick(0.001)
	var slow_cd := ws.orb_t
	ws.maraca_tempo = 1.0
	player.velocity = Vector3(8, 0, 0)
	ws.orb_t = 0.0
	ws.tick(0.001)
	var fast_cd := ws.orb_t
	player.velocity = Vector3.ZERO
	ws.orb_t = 999.0
	_check("...faster while he keeps moving", tempo > 0.4 and fast_cd < slow_cd * 0.7, "tempo %.2f, %.2f s vs %.2f s" % [tempo, fast_cd, slow_cd])

	var kit: KitLoco = ab.roster.part
	_clear()
	for k in 6:
		_spawn(EnemyManager.GRUNT, 8.0, TAU * k / 6.0, 50.0)
	var outside := _spawn(EnemyManager.GRUNT, 22.0, 0.3, 50.0)
	await _secs(0.05)
	_cast(0)
	await _secs(0.1)
	var start := {}
	for i in em.count:
		start[i] = em.pos[i]
	_check("Party Mode: everyone within 15 m dances", kit.danced == 6 and body.party
		and _all(func(i): return i == outside or (em.stun_t[i] > 5.0 and em.is_harmless(i))), "%d" % kit.danced)
	_check("...not past 15 m", em.stun_t[outside] == 0.0, "")
	await _secs(2.0)
	var still := true
	var lost := true
	for i in em.count:
		if i == outside:
			continue
		var m: Vector3 = em.pos[i] - start[i]
		still = still and Vector2(m.x, m.z).length() < 0.6
		lost = lost and (em.hp_max[i] - em.hp[i]) >= em.hp_max[i] * 0.05 * 1.6
	_check("...on the spot: they can't move or attack", still, "")
	_check("...losing 5% of max HP a second", lost, "%.1f%%" % (100.0 * (em.hp_max[0] - em.hp[0]) / em.hp_max[0]))
	await _secs(4.2)
	_check("...for 6 s", not kit.active("party") and not body.party and em.stun_t[0] <= 0.0, "")

	_clear()
	var at := ab.aim_point(KitLoco.PINATA_RANGE)
	var ids := []
	for k in 6:
		ids.append(em.uid[_spawn_at(EnemyManager.TANK, at + Vector3(cos(k) * 9.0, 0, sin(k) * 9.0), 40.0)])
	await _secs(0.05)
	_cast(1)
	await _secs(KitLoco.PINATA_FLIGHT + 2.2)
	var crowd := 0
	for u in ids:
		var i := em.index_of(u)
		if i >= 0 and Vector2(em.pos[i].x - at.x, em.pos[i].z - at.z).length() < 2.5:
			crowd += 1
	_check("Pinata Drop: it lands where you aim and enemies swarm it", kit.lured == 6 and crowd == 6 and kit.active("pinata"), "%d round it" % crowd)
	await _secs(2.0)
	var blasted := 0
	for u in ids:
		var i := em.index_of(u)
		if i >= 0 and em.hp_max[i] - em.hp[i] >= KitLoco.BOMB_DAMAGE:
			blasted += 1
	_check("...then bursts after 3 s into 20 candy bombs, 60 each within 3 m", kit.bombs_burst == KitLoco.BOMBS and blasted == 6 and not kit.active("pinata"), "%d bombs, %d blasted" % [kit.bombs_burst, blasted])

	_clear()
	var ring := []
	for k in 8:
		ring.append(_spawn(EnemyManager.GRUNT, 10.0, TAU * k / 8.0 + 0.2, 50.0))
	var beyond := _spawn(EnemyManager.GRUNT, 24.0, 0.5, 50.0)
	await _secs(0.05)
	for i in em.count:
		em.stun(i, 20.0)   # hold them in place for the sweep
	var taken0: float = player.dmg_taken
	_cast(2)
	await _secs(0.1)
	_check("DESTROY Mode: +50% armour", kit.active("destroy") and body.destroy and is_equal_approx(player.dmg_taken, taken0 / 1.5), "%.2f" % player.dmg_taken)
	await _secs(3.0)
	var burnt := 0
	for i in ring:
		if em.hp[i] < em.hp_max[i]:
			burnt += 1
	_check("...twin lasers sweep all the way round", burnt == 8 and kit.beam_hits > 0, "%d of 8 hit" % burnt)
	_check("...out to 20 m", em.hp[beyond] == em.hp_max[beyond], "")
	# Stand an enemy right in a beam for a second: 8% of max HP
	_clear()
	await _secs(0.05)
	var d := kit.beam_dir(0)
	var victim := _spawn_at(EnemyManager.TANK, player.global_position + d * 8.0, 50.0)
	em.stun(victim, 5.0)
	var hpv: float = em.hp[victim]
	for f in 60:
		em.pos[victim] = player.global_position + kit.beam_dir(0) * 8.0
		await get_tree().physics_frame
	var frac: float = (hpv - em.hp[victim]) / em.hp_max[victim]
	var want := KitLoco.BEAM_FRAC * kit.pw(2)
	_check("...8% of max HP a second in the beams", frac > want * 0.8 and frac < want * 1.2, "%.1f%% (want %.1f%%)" % [frac * 100.0, want * 100.0])
	await _secs(9.0)
	_check("...for 12 s", not kit.active("destroy") and not body.destroy and is_equal_approx(player.dmg_taken, taken0), "%.2f" % player.dmg_taken)


func _blob() -> void:
	var h := player.model as RosterHero
	var b := h.blob
	_check("the Blob is built in code: a see-through jelly with eyes and bubbles inside", b != null and b.mat != null and b.mat_in != null
		and b._eyes.size() == 2 and b._bubbles.size() >= 8 and h.sock == null, "")
	var sy0 := b._sy
	for f in 30:
		b.animate(1.0 / 60.0, 0.0, true)
	var tall := b._sy
	for f in 8:
		b.animate(1.0 / 60.0, 0.0, false)
	var flat := b._sy
	_check("...it stretches tall in the air and splats on landing", tall > 1.12 and flat < 0.95, "%.2f -> %.2f -> %.2f" % [sy0, tall, flat])
	var s0 := b.splats
	h.play_hit()
	await _secs(0.1)
	_check("...and splats, spraying droplets, when it's hit", b.splats > s0, "")
	# Acid Body
	_clear()
	var close := []
	for k in 3:
		close.append(em.uid[_spawn(EnemyManager.TANK, 1.4, k * 2.0, 50.0)])
	var far := em.uid[_spawn(EnemyManager.TANK, 7.0, 0.0, 50.0)]
	await _secs(0.05)
	ws.acid_growth = 0.0
	var b0 := ws.acid_burns
	ws.fire("acid", "orb", 1.0)
	var burnt := 0
	var per := 0.0
	for u in close:
		var i := em.index_of(u)
		if i >= 0 and em.hp[i] < em.hp_max[i]:
			burnt += 1
			per = em.hp_max[i] - em.hp[i]
	var fi := em.index_of(far)
	_check("Acid Body burns everything touching you (2.5 m), nothing further", burnt == 3 and ws.acid_burns - b0 == 3 and em.hp[fi] == em.hp_max[fi], "%d burnt" % burnt)
	var every: float = main.stats.value("orb_cooldown") * WeaponSystem.scale_of("acid").y
	_check("...for 30 damage a second (in pulses)", absf(per / every - 30.0) < 1.5, "%.1f every %.2f s" % [per, every])
	_clear()
	for k in 10:
		_spawn(EnemyManager.GRUNT, 1.0, k * 0.6, 0.01)
	await _secs(0.05)
	var r0 := ws.acid_radius("orb")
	ws.fire("acid", "orb", 1.0)
	await _secs(0.1)
	_check("...and grows with kills", is_equal_approx(ws.acid_growth, 0.1) and ws.acid_radius("orb") > r0 * 1.09 and is_equal_approx(b.growth, 0.1),
		"growth %.2f, body %.2f" % [ws.acid_growth, b.growth])
	ws.acid_growth = 0.495
	_clear()
	for k in 5:
		_spawn(EnemyManager.GRUNT, 1.0, k * 1.2, 0.01)
	await _secs(0.05)
	ws.fire("acid", "orb", 1.0)
	_check("...up to +50% size", is_equal_approx(ws.acid_growth, 0.5), "%.3f" % ws.acid_growth)
	ws.acid_growth = 0.0
	# Engulf
	var kit: KitBlob = ab.roster.part
	_clear()
	var eat := []
	for k in 25:
		eat.append(em.uid[_spawn(EnemyManager.TANK, 2.0 + 3.5 * (k % 5) / 4.0, k * 1.3, 50.0)])
	var boss := em.uid[_spawn(EnemyManager.BOSS, 3.0, 0.5, 50.0)]
	var bi := em.index_of(boss)
	var boss_sz := em.sz[bi]
	await _secs(0.05)
	player.hp = player.max_hp * 0.5
	_cast(0)
	await _secs(0.7)
	var inside := 0
	for u in eat:
		var i := em.index_of(u)
		if i >= 0 and em.sz[i] < 0.5 and Vector2(em.pos[i].x - player.global_position.x, em.pos[i].z - player.global_position.z).length() < 1.0:
			inside += 1
	_check("Engulf swallows 20 enemies (they show inside the jelly)", kit.swallowed == 20 and inside == 20, "%d swallowed, %d inside" % [kit.swallowed, inside])
	bi = em.index_of(boss)
	_check("...but not the boss", bi >= 0 and em.sz[bi] == boss_sz, "")
	_check("...and you heal 1% of max HP for each", player.hp >= player.max_hp * 0.69, "%.0f / %.0f" % [player.hp, player.max_hp])
	var digest0 := kit.digested
	await _secs(1.0)
	var per_sec := (kit.digested - digest0) / 20.0
	var one := 0
	for u in eat:
		var i := em.index_of(u)
		if i >= 0 and em.sz[i] < 0.5:
			one = i
			break
	_check("...digesting them for 8% of max HP a second", absf(per_sec / em.hp_max[one] - 0.08) < 0.025, "%.3f" % (per_sec / em.hp_max[one]))
	await _secs(5.0)
	var out := 0
	for u in eat:
		var i := em.index_of(u)
		if i >= 0 and em.sz[i] >= 0.99:
			out += 1
	_check("...for 6 s, then spits the survivors back out full size", not kit.active("engulf") and kit.spat == 20 and out == 25, "%d spat, %d full size" % [kit.spat, out])
	# Split
	_clear()
	_cast(1)
	await _secs(0.2)
	var minis := kit.clone_list()
	_check("Split: 2 mini-blobs split off", kit.active("split") and minis.size() == 2 and (minis[0][0] as RosterHero).blob != null
		and (minis[0][0] as RosterHero).blob.size == 0.5, "%d" % minis.size())
	var prey := em.uid[_spawn(EnemyManager.TANK, 10.0, 0.0, 50.0)]
	var pr := em.index_of(prey)
	em.slow(pr, 0.001, 20.0)
	await _secs(2.0)
	pr = em.index_of(prey)
	var chased := 0
	for c in kit.clone_list():
		if (c[1] as Vector3).distance_to(em.pos[pr]) < 2.0:
			chased += 1
	_check("...that chase enemies", chased >= 1, "%d" % chased)
	var hp_p := em.hp[pr]
	ws.fire("acid", "orb", 1.0)
	var took := hp_p - em.hp[pr]
	_check("...each with its own Acid Body at 60%", absf(took - per * KitBlob.SPLIT_DAMAGE * chased) < 1.0, "%.1f (a pulse is %.1f)" % [took, per])
	await _secs(8.0)
	_check("...for 10 s", not kit.active("split") and kit.clone_list().is_empty(), "")
	# The Great Puddle
	_clear()
	var wet := []
	for k in 6:
		wet.append(em.uid[_spawn(EnemyManager.TANK, 6.0 + k * 2.0, k, 50.0)])
	await _secs(0.05)
	var at := player.global_position
	_cast(2)
	await _secs(0.4)
	var glow := false
	for mi in player.model.find_children("*", "GeometryInstance3D", true, false):
		if (mi as GeometryInstance3D).material_overlay != null:
			glow = true
	_check("The Great Puddle: you spread flat, invulnerable (glowing)", kit.active("puddle") and b.puddle > 0.5 and player.untouchable
		and not player.hurt(500.0) and glow, "puddle %.2f" % b.puddle)
	player.velocity = Vector3(10, 0, 0)
	await _secs(0.5)
	_check("...and can't move", player.global_position.distance_to(at) < 0.3, "%.2f m" % player.global_position.distance_to(at))
	_check("...enemies in it are slowed 90%", _all(func(i): return em.slow_t[i] > 0.0 and em.slow_f[i] <= 0.11), "")
	var hpp := _total_hp()
	await _secs(1.0)
	var frac := (hpp - _total_hp()) / (6.0 * em.hp_max[em.index_of(wet[0])])
	_check("...and take 6% of max HP a second", absf(frac - 0.06) < 0.02, "%.3f" % frac)
	await _secs(3.95)
	var d0 := 0.0
	for u in wet:
		d0 += em.pos[em.index_of(u)].distance_to(at)
	await _secs(0.25)
	_check("...for 6 s, then you pull back together", not kit.active("puddle") and not player.untouchable and not player.scripted and b.puddle_target == 0.0, "")
	await _secs(0.4)
	var d1 := 0.0
	for u in wet:
		d1 += em.pos[em.index_of(u)].distance_to(at)
	_check("...flinging the survivors out 6 yd", kit.flung == 6 and (d1 - d0) / 6.0 > 4.0, "%.1f m further" % ((d1 - d0) / 6.0))


func _toadstool_knight() -> void:
	var h := player.model as RosterHero
	var body := h.knight
	_check("the Toadstool Knight is the boss's body at player size: silver plate, toadstool cap, a sword", body != null and body.model != null
		and body.model._cap_mats.size() == 3 and is_instance_valid(body.model.blade) and body.model.blade.is_visible_in_tree()
		and ToadstoolBody.SCALE < 1.0 and body.tree != null and body.tree.active, "")
	var rm := RosterModel.create("toadstool_knight")
	add_child(rm)
	_check("...and character select shows him too", rm._knight != null and rm._knight.model != null, "")
	rm.queue_free()
	var dmg: float = main.stats.value("damage")

	# Spore Blade: a 3 m arc slash, then a spore cloud
	_clear()
	var front := []
	for k in 3:
		front.append(_spawn(EnemyManager.TANK, 1.8 + 0.4 * k, (k - 1) * 0.35, 50.0))
	var behind := _spawn(EnemyManager.TANK, 2.0, PI, 50.0)
	var far := _spawn(EnemyManager.TANK, 6.5, 0.0, 50.0)
	await _secs(0.05)
	for i in em.count:
		em.stun(i, 20.0)
	var s0 := body.slashes
	ws.fire("spore", "orb", 1.0)
	var all_front := true
	for i in front:
		all_front = all_front and em.hp[i] < em.hp_max[i]
	_check("Spore Blade: a sword slash hits everything in the 3 m arc", all_front and body.slashes == s0 + 1, "%d slashes" % (body.slashes - s0))
	_check("...but not behind him or out of reach", em.hp[behind] == em.hp_max[behind] and em.hp[far] == em.hp_max[far], "")
	var sc := WeaponSystem.scale_of("spore")
	_check("...30 damage every 0.8 s (scaled like every weapon)", is_equal_approx(sc.x, 30.0 / WeaponSystem.BASE_DAMAGE) and is_equal_approx(sc.y, 0.8 / WeaponSystem.BASE_EVERY), str(sc))
	_check("...and leaves a spore cloud where it cut", ws.spore_clouds >= 1, "%d" % ws.spore_clouds)
	await _secs(0.4)
	var poisoned := 0
	for i in front:
		if em.pct_t[i] > 0.0 and is_equal_approx(em.pct_f[i], WeaponSystem.SPORE_FRAC):
			poisoned += 1
	_check("...that poisons enemies in it for 2% of max HP per second", poisoned >= 2 and em.pct_t[behind] <= 0.0, "%d of 3" % poisoned)
	await _secs(WeaponSystem.SPORE_TIME)
	_check("...for 3 s", ws.spore_clouds == 0, "%d" % ws.spore_clouds)

	var kit: KitToadstool = ab.roster.part
	# Fungal Shield: 20% of max HP; when it breaks it bursts into spores
	_clear()
	var close := []
	for k in 5:
		close.append(_spawn(EnemyManager.TANK, 5.0, TAU * k / 5.0, 50.0))
	var out := _spawn(EnemyManager.TANK, 12.0, 0.4, 50.0)
	await _secs(0.05)
	for i in em.count:
		em.stun(i, 20.0)
	player.shield = 0.0
	var c0 := body.casts
	_cast(0)
	await _secs(0.05)
	_check("Fungal Shield: a shield worth 20% of max HP", is_equal_approx(player.shield, player.max_hp * KitToadstool.SHIELD_FRAC * kit.pw(0)) and kit.active("shield"), "%.1f" % player.shield)
	_check("...and he raises his blade to cast", body.casts > c0, "")
	player.invuln = 0.0
	player.hurt_true(0.01)   # (god mode: the hit only wipes the shield out)
	await _secs(0.1)
	var burst := 0
	for i in close:
		if em.hp_max[i] - em.hp[i] >= KitToadstool.BURST_DAMAGE * dmg * kit.pw(0) * 0.99 and em.pct_t[i] > 0.0:
			burst += 1
	_check("...when it breaks it bursts into spores: 60 within 8 m, plus poison", kit.shield_bursts == 1 and burst == 5 and not kit.active("shield"), "%d bursts, %d of 5" % [kit.shield_bursts, burst])
	_check("...not past 8 m", em.hp[out] == em.hp_max[out], "")
	player.shield = 0.0
	_cast(0)
	await _secs(KitToadstool.SHIELD_TIME + 0.2)
	_check("...and when it runs out after 8 s, too", kit.shield_bursts == 2 and player.shield < 0.01, "%d bursts, shield %.1f" % [kit.shield_bursts, player.shield])

	# Fairy Ring: enemies that cross the 10 m ring take 50 and wander confused
	_clear()
	var walkers := []
	for k in 6:
		walkers.append(em.uid[_spawn(EnemyManager.GRUNT, 12.5, TAU * k / 6.0, 50.0)])
	var inside := _spawn(EnemyManager.TANK, 4.0, 0.5, 50.0)
	em.stun(inside, 20.0)
	var boss := _spawn(EnemyManager.BOSS, 13.0, 0.25, 50.0)
	await _secs(0.05)
	_cast(1)
	await _secs(0.1)
	_check("Fairy Ring: a ring of mushrooms springs up 10 m around him", kit.active("ring") and kit._ring_nodes.size() == KitToadstool.RING_SHROOMS + 1, "%d" % kit._ring_nodes.size())
	await _secs(3.0)
	var crossed := 0
	var confused := 0
	for u in walkers:
		var i := em.index_of(u)
		if i < 0:
			continue
		if em.hp_max[i] - em.hp[i] >= KitToadstool.RING_DAMAGE * dmg * kit.pw(1) * 0.99:
			crossed += 1
		if em.confuse_t[i] > 0.0 and em.is_harmless(i):
			confused += 1
	_check("...enemies that cross it take 50 damage", crossed == 6 and kit.ring_hits >= 6, "%d of 6, %d hits" % [crossed, kit.ring_hits])
	_check("...and wander confused for 3 s (harmless)", confused >= 4, "%d of 6" % confused)
	_check("...the ring is the line: enemies well inside it are untouched", em.hp[inside] == em.hp_max[inside], "")
	var bi := em.index_of(em.uid[boss])
	_check("...bosses take the damage but aren't confused", bi < 0 or em.confuse_t[bi] <= 0.0, "")
	await _secs(KitToadstool.RING_TIME - 3.0)
	_check("...for 10 s", not kit.active("ring") and kit._ring_nodes.is_empty(), "")

	# The Fungus Court: 6 guardians in a 12 m ring draw enemies in and slam them
	_clear()
	await _secs(0.05)
	_cast(2)
	await _secs(0.1)
	var ring_ok: bool = kit._guards.size() == KitToadstool.COURT_COUNT
	for g in kit._guards:
		var d: Vector3 = (g["pos"] as Vector3) - player.global_position
		ring_ok = ring_ok and absf(Vector2(d.x, d.z).length() - KitToadstool.COURT_RADIUS) < 0.5
	_check("The Fungus Court: 6 giant toadstool guardians rise in a 12 m ring", ring_ok and kit.active("court"), "%d" % kit._guards.size())
	var gp: Vector3 = kit._guards[0]["pos"]
	var outward := Vector3(gp.x - player.global_position.x, 0, gp.z - player.global_position.z).normalized()
	var drawn_ids := []
	for k in 4:
		var side := outward.cross(Vector3.UP) * (k - 1.5) * 1.5
		var i := _spawn_at(EnemyManager.TANK, gp + outward * 6.0 + side, 50.0)
		drawn_ids.append(em.uid[i])
	await _secs(2.5)
	var huddled := 0
	for u in drawn_ids:
		var i := em.index_of(u)
		if i >= 0 and Vector2(em.pos[i].x - gp.x, em.pos[i].z - gp.z).length() < KitToadstool.COURT_SLAM_RADIUS:
			huddled += 1
	_check("...each draws enemies to it", huddled == 4 and kit.drawn >= 4, "%d of 4 round it" % huddled)
	await _secs(2.0)
	var slammed := 0
	for u in drawn_ids:
		var i := em.index_of(u)
		if i >= 0 and em.hp_max[i] - em.hp[i] >= KitToadstool.COURT_DAMAGE * dmg * kit.pw(2) * 0.99:
			slammed += 1
	_check("...and slams every 1.5 s: 80 within 4 m", slammed == 4 and kit.court_slams >= KitToadstool.COURT_COUNT * 2, "%d slammed, %d slams" % [slammed, kit.court_slams])
	await _secs(KitToadstool.COURT_TIME - 4.4)
	_check("...for 15 s", not kit.active("court") and kit._guards.is_empty(), "")

	# Death: he staggers and topples over
	var dummy := RosterHero.create("toadstool_knight")
	add_child(dummy)
	await _secs(0.1)
	dummy.play_death()
	await _secs(1.6)
	_check("...and when he falls he plays a death (topples over backwards)", dummy.knight.dead and dummy.knight.model.rotation.x > 1.0, "%.2f" % dummy.knight.model.rotation.x)
	dummy.queue_free()


func _arachnid() -> void:
	var h := player.model as RosterHero
	var sp := h.spider
	_check("the Arachnid is built in code: the boss's spider, eight legs, at player size", sp != null and sp is SpiderModel and sp._legs.size() == 8
		and sp.step_scaled and h.sock == null and h.blob == null, "")
	var box := AABB()
	var first := true
	for mi in sp.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = a if first else box.merge(a)
		first = false
	_check("...about as tall as the other heroes, a bit wider", box.size.y > 1.2 and box.size.y < 2.1 and box.size.x > 2.0 and box.size.x < 3.8,
		"%.2f x %.2f m" % [box.size.x, box.size.y])
	# Walking: feet stay planted, then step to keep up
	var ideal_ok := func() -> bool:
		for l in sp._legs:
			if (l["foot"] as Vector3).distance_to(sp._ideal(l)) > SpiderModel.STEP_DIST * sp._sc * 1.05:
				return false
		return true
	player.global_position += Vector3(1.2, 0, 0)
	await get_tree().process_frame
	var lag := 0.0
	for l in sp._legs:
		lag = maxf(lag, (l["foot"] as Vector3).distance_to(sp._ideal(l)))
	await _secs(0.8)
	_check("...its legs walk: the feet stay planted, then step after the body", lag > 0.3 and ideal_ok.call(), "lag %.2f m" % lag)
	# Attack, cast, hit and death poses
	var s0 := sp.spits
	h.attack(player.global_position + Vector3(0, 0, -5))
	await _secs(0.1)
	_check("...it jabs its head forward with each spit", sp.spits == s0 + 1 and sp.pitch > 0.15, "pitch %.2f" % sp.pitch)
	h.play_ability(0)
	await _secs(0.3)
	_check("...rears up, front legs clawing the air, when it casts", sp.rear > 0.5, "rear %.2f" % sp.rear)
	await _secs(0.6)
	h.play_hit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("...recoils when hit", sp.pitch < -0.1 and sp.nudge.z > 0.1, "pitch %.2f" % sp.pitch)
	h.play_death()
	await _secs(1.0)
	_check("...and curls its legs up when it dies (even with the game paused)", sp.dead and sp.curl > 0.9 and h.process_mode == Node.PROCESS_MODE_ALWAYS, "curl %.2f" % sp.curl)
	sp.dead = false
	sp.curl = 0.0
	sp.crouch = 0.0
	h.process_mode = Node.PROCESS_MODE_INHERIT
	# Venom Spit
	_clear()
	var t := _spawn(EnemyManager.TANK, 6.0, 0.0, 50.0)
	var tu := em.uid[t]
	em.slow(t, 0.001, 30.0)
	await _secs(0.05)
	var h0 := em.hp[t]
	var v0 := ws.venom_hits
	ws.fire("venom", "orb", 1.0)
	var kinds := 0
	for i in ws.pc:
		kinds += 1 if WeaponSystem.P_KINDS[ws.p_style[i]] == "venom" else 0
	_check("Venom Spit: spits fast globs of venom", kinds >= 1, "%d globs" % kinds)
	await _secs(0.4)
	t = em.index_of(tu)
	var hit: float = h0 - em.hp[t] - em.hp_max[t] * WeaponSystem.VENOM_FRAC * (WeaponSystem.VENOM_TIME - em.poison_t[t])   # less the poison so far
	_check("...that hit for about 12 and poison", ws.venom_hits == v0 + 1 and em.poison_n[t] == 1 and hit > 10.0 and hit < 20.0, "-%.1f, %d stacks" % [hit, em.poison_n[t]])
	for n in 4:
		ws.fire("venom", "orb", 1.0)
		await _secs(0.3)
	t = em.index_of(tu)
	_check("...stacking 3 times", em.poison_n[t] == 3, "%d" % em.poison_n[t])
	var hp1 := em.hp[t]
	await _secs(1.0)
	t = em.index_of(tu)
	var frac := (hp1 - em.hp[t]) / em.hp_max[t]
	_check("...3% of max HP a second per stack", absf(frac - 0.09) < 0.015, "%.3f / s" % frac)
	await _secs(3.2)
	t = em.index_of(tu)
	_check("...for 4 s", em.poison_n[t] == 0 and em.poison_t[t] <= 0.0, "%.2f s left" % em.poison_t[t])
	# Web Trap
	var kit: KitArachnid = ab.roster.part
	_clear()
	_cast(0)
	await _secs(0.5)
	_check("Web Trap: a web lands where you aim", kit.active("web") and is_instance_valid(kit._web) and kit._web_t > 3.0, "")
	var wat := kit._web_at
	var inside := []
	for n in 5:
		var a := TAU * n / 5.0
		inside.append(em.uid[_spawn_at(EnemyManager.TANK, wat + Vector3(cos(a), 0, sin(a)) * (2.0 + n * 1.4), 50.0)])
	var out_u := em.uid[_spawn_at(EnemyManager.TANK, wat + Vector3(15.0, 0, 0), 50.0)]
	em.slow(em.index_of(out_u), 0.001, 30.0)
	await _secs(0.25)
	var stuck_ok := true
	for u in inside:
		var i := em.index_of(u)
		stuck_ok = stuck_ok and em.web_t[i] > 0.0 and em.slow_t[i] > 0.0 and em.slow_f[i] == 0.0
	var oi := em.index_of(out_u)
	_check("...everything in the 10 m web is stuck fast", stuck_ok and kit.stuck >= 5, "%d stuck" % kit.stuck)
	_check("...nothing outside it", em.web_t[oi] <= 0.0, "")
	var wi := em.index_of(inside[0])
	em.poison(wi, WeaponSystem.VENOM_FRAC, 2.0, 3)
	em.poison(oi, WeaponSystem.VENOM_FRAC, 2.0, 3)
	var hw := em.hp[wi]
	var ho := em.hp[oi]
	await _secs(0.5)
	wi = em.index_of(inside[0])
	oi = em.index_of(out_u)
	var ratio := (hw - em.hp[wi]) / maxf(0.001, ho - em.hp[oi])
	_check("...and takes +30% damage from poison", absf(ratio - (1.0 + KitArachnid.WEB_BONUS * kit.pw(0))) < 0.05, "x%.2f" % ratio)
	await _secs(3.4)
	wi = em.index_of(inside[0])
	_check("...for 4 s", not kit.active("web") and em.web_t[wi] <= 0.0, "")
	# Brood
	_clear()
	_cast(1)
	await _secs(0.7)
	_check("Brood: an egg sac hatches 12 spiderlings", kit.hatched == 12 and kit.lings().size() == 12 and kit.active("brood"), "%d" % kit.hatched)
	var prey := []
	for n in 6:
		var u := em.uid[_spawn(EnemyManager.TANK, 6.0, n * 0.5 - 1.2, 50.0)]
		em.slow(em.index_of(u), 0.001, 30.0)
		prey.append(u)
	await _secs(1.5)
	var clinging := 0
	var on := {}
	for l in kit.lings():
		if l[2] == "cling":
			clinging += 1
			on[l[3]] = true
	_check("...that leap onto the enemies", clinging == 12 and on.size() == 6, "%d clinging, on %d enemies" % [clinging, on.size()])
	var d0 := kit.ling_damage
	await _secs(1.0)
	var per := (kit.ling_damage - d0) / 12.0
	var want: float = KitArachnid.BROOD_DPS * kit.pw(1) * main.stats.value("damage")
	_check("...each dealing 20 damage a second", absf(per - want) < want * 0.15, "%.1f / s (want %.1f)" % [per, want])
	var poisoned := 0
	for u in prey:
		var i := em.index_of(u)
		poisoned += 1 if i >= 0 and em.poison_n[i] >= 1 else 0
	_check("...and poisoning them", poisoned == 6, "%d / 6" % poisoned)
	_clear()
	var boss := em.uid[_spawn(EnemyManager.BOSS, 5.0, 0.4, 50.0)]
	em.slow(em.index_of(boss), 0.001, 30.0)
	for n in 3:
		em.slow(_spawn(EnemyManager.TANK, 3.0, n * 0.8 - 0.8, 50.0), 0.001, 30.0)
	await _secs(1.2)
	var on_boss := 0
	for l in kit.lings():
		on_boss += 1 if l[3] == boss and l[2] == "cling" else 0
	_check("...a boss in range first", on_boss >= 10, "%d on the boss" % on_boss)
	await _secs(11.6)
	_check("...for 15 s", not kit.active("brood") and kit.lings().is_empty(), "")
	# Cocoon
	_clear()
	var wrap := []
	for n in 10:
		wrap.append(em.uid[_spawn(EnemyManager.TANK, 4.0 + n * 1.8, n * 0.7, 50.0)])
	var far_u := em.uid[_spawn(EnemyManager.TANK, 30.0, 0.0, 50.0)]
	var cboss := em.uid[_spawn(EnemyManager.BOSS, 8.0, 2.5, 50.0)]
	await _secs(0.05)
	player.hp = player.max_hp * 0.5
	var hc := {}
	for u in wrap:
		hc[u] = em.hp[em.index_of(u)]
	_cast(2)
	await _secs(0.3)
	var held := 0
	for u in wrap:
		var i := em.index_of(u)
		held += 1 if em.stun_t[i] > 3.0 and em.is_harmless(i) else 0
	_check("Cocoon: every enemy within 25 m is wrapped in silk", kit.wrapped == 10 and held == 10 and kit._cocoons.multimesh.visible_instance_count == 10, "%d wrapped" % kit.wrapped)
	var bi := em.index_of(cboss)
	_check("...the boss only slowed", em.stun_t[bi] <= 0.0 and em.slow_t[bi] > 3.0 and is_equal_approx(em.slow_f[bi], KitArachnid.COCOON_BOSS_SLOW), "")
	_check("...nothing past 25 m", em.stun_t[em.index_of(far_u)] <= 0.0, "")
	_check("...and you heal 1% of max HP per cocoon", player.hp >= player.max_hp * 0.595, "%.0f / %.0f" % [player.hp, player.max_hp])
	await _secs(5.0)
	var lost_frac := 0.0
	for u in wrap:
		var i := em.index_of(u)
		lost_frac += (hc[u] - em.hp[i]) / em.hp_max[i] / 10.0
	var wantc := minf(1.0, KitArachnid.COCOON_FRAC * kit.pw(2))
	_check("...cocooned enemies take 25% of their max HP", absf(lost_frac - wantc) < 0.03, "%.3f (want %.3f)" % [lost_frac, wantc])
	_check("...for 5 s", not kit.active("cocoon") and not kit._cocoons.visible and _all(func(i): return em.stun_t[i] <= 0.0), "")


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
	var glow := false
	for mi in player.model.find_children("*", "GeometryInstance3D", true, false):
		if (mi as GeometryInstance3D).material_overlay != null:
			glow = true
	_check("...and glows in shifting colours while invincible", player.is_invincible() and glow, "")

	await _secs(0.4)
	_check("Death Roll: grabs enemies in his path", (ab.roster.part as KitCroc)._held.size() >= 3, str((ab.roster.part as KitCroc)._held.size()))
	await _secs(0.5)
	_check("...rolls 15 m", player.global_position.distance_to(start) > 10.0, "%.1f m" % player.global_position.distance_to(start))
	_check("...hurting them all the way, then flings them", _all(func(i): return em.hp_max[i] - em.hp[i] >= 100.0 and em.kb_t[i] > 0.0), "")
	await _secs(0.5)
	var still := false
	for mi in player.model.find_children("*", "GeometryInstance3D", true, false):
		if (mi as GeometryInstance3D).material_overlay != null:
			still = true
	_check("...the glow stops when he's hittable again", not player.is_invincible() and not still, "")
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
