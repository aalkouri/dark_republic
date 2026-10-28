extends Node
## Checks gameplay numbers against the design spec (abilities, epics, potions, shield).
##   godot --headless --path . --fixed-fps 60 res://tools/test_abilities.tscn

var fails := 0


func _ready() -> void:
	load("res://scripts/main.gd").setup_inputs()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var em := EnemyManager.new()
	em.rng = rng
	em.arena_half = 200.0
	add_child(em)
	em.burn_dps_frac = Abilities.INFERNO_BURN_DPS
	em.burn_explode_frac = Abilities.INFERNO_EXPLODE_FRAC
	em.burn_explode_radius = Abilities.INFERNO_EXPLODE_RADIUS
	var far := Vector3(0, 0, 50)   # "player" far away so steering is negligible during knockback
	var dt := 1.0 / 60.0

	# 1) Knockback distance: 5 yards
	var i := em.spawn(EnemyManager.TANK, Vector3(0, 0, 0), 100.0)
	em.tick(dt, far)
	var before := em.pos[i]
	em.knock(i, Vector3(1, 0, 0), Abilities.SHOCK_KNOCKBACK, 0.3)
	for f in 18:
		em.tick(dt, far)
	var moved := em.pos[i].x - before.x
	_check("knockback = 5 yd (4.572 m)", absf(moved - 4.572) < 0.05, "moved %.3f m" % moved)

	# 2) Burn: 5% max HP / s for 10 s -> exactly 50% of max HP
	em.count = 0
	var j := em.spawn(EnemyManager.TANK, Vector3(0, 0, 0), 2.0)
	var max_hp := em.hp_max[j]
	em.ignite_all(Abilities.INFERNO_BURN_TIME)
	for f in 60 * 12:
		em.tick(dt, em.pos[j])   # standing on the player = no movement
	var lost := (max_hp - em.hp[j]) / max_hp
	_check("burn total = 50% max HP", absf(lost - 0.5) < 0.01, "lost %.3f" % lost)
	_check("burn stops after 10 s", em.burn_t[j] <= 0.0, "burn_t %.3f" % em.burn_t[j])

	# 3) Death while burning explodes for 50% of max HP within 2 yd
	em.count = 0
	var a := em.spawn(EnemyManager.GRUNT, Vector3(0, 0, 0), 10.0)       # 100 hp -> 50 explosion
	var near := em.spawn(EnemyManager.TANK, Vector3(1.5, 0, 0), 10.0)   # within 1.83 m + radius
	var out := em.spawn(EnemyManager.TANK, Vector3(4.0, 0, 0), 10.0)    # outside the blast
	em.tick(dt, Vector3(0, 0, 0))
	var near_hp := em.hp[near]
	var out_hp := em.hp[out]
	em.burn_t[a] = 5.0
	em.damage(a, 1.0e6)
	em.tick(dt, Vector3(0, 0, 0))   # explosion resolves on the next tick
	var near_loss := near_hp - em.hp[near]
	var expected := 100.0 * 0.5
	_check("explosion hits within 2 yd for 50%", absf(near_loss - expected) < 1.0, "near lost %.1f (expected %.1f)" % [near_loss, expected])
	_check("explosion misses outside radius", absf(out_hp - em.hp[out]) < 0.01, "far lost %.2f" % (out_hp - em.hp[out]))

	# 4) Not burning -> no explosion
	em.count = 0
	var c := em.spawn(EnemyManager.GRUNT, Vector3(0, 0, 0), 10.0)
	var n2 := em.spawn(EnemyManager.TANK, Vector3(1.0, 0, 0), 10.0)
	em.tick(dt, Vector3.ZERO)
	var hp2 := em.hp[n2]
	em.damage(c, 1.0e6)
	em.tick(dt, Vector3.ZERO)
	_check("no explosion without burn", absf(hp2 - em.hp[n2]) < 0.01, "lost %.2f" % (hp2 - em.hp[n2]))

	# 5) Epic enemies: 1.5x size, 4x HP, emit epic_killed on death
	em.count = 0
	var got := [0]
	em.epic_killed.connect(func(_p): got[0] += 1)
	var ne := em.spawn(EnemyManager.GRUNT, Vector3(0, 0, 0), 1.0, false)
	var ep := em.spawn(EnemyManager.GRUNT, Vector3(3, 0, 0), 1.0, true)
	_check("epic has 4x HP", is_equal_approx(em.hp[ep], em.hp[ne] * 4.0), "%.1f vs %.1f" % [em.hp[ep], em.hp[ne]])
	_check("epic is 1.5x size", is_equal_approx(em.sz[ep], 1.5), "sz %.2f" % em.sz[ep])
	em.damage(ne, 1.0e6)
	em.damage(ep, 1.0e6)
	_check("only epics signal a drop", got[0] == 1, "signals %d" % got[0])

	# 6) Potions: drop odds and effects
	var stats := Stats.new()
	for k in ["max_hp", "regen", "armor", "move_speed", "extra_jumps", "damage"]:
		stats.define(k, {"max_hp": 200.0, "move_speed": 8.0, "damage": 1.0}.get(k, 0.0))
	var player := Player.new()
	player.stats = stats
	add_child(player)
	var ab := Abilities.new()
	ab.setup(stats, em, player, null)
	add_child(ab)
	_check("Inferno has its cast sound on the SFX bus", ab.inferno_sfx.stream != null and ab.inferno_sfx.bus == Settings.SFX_BUS, "")
	var pm := PotionManager.new()
	pm.setup(player, ab, rng)
	add_child(pm)
	var tally := [0, 0, 0]
	for n in 20000:
		tally[pm.roll_kind()] += 1
	_check("drop odds ~30/50/20", absf(tally[0] / 200.0 - 30.0) < 1.5 and absf(tally[1] / 200.0 - 50.0) < 1.5 and absf(tally[2] / 200.0 - 20.0) < 1.5,
		"%.1f / %.1f / %.1f %%" % [tally[0] / 200.0, tally[1] / 200.0, tally[2] / 200.0])

	ab.level = 1
	_check("level 1: only Inferno is usable", ab.is_unlocked(Abilities.INFERNO) and not ab.is_unlocked(Abilities.SHOCKWAVE) and not ab.is_unlocked(Abilities.METEOR), "")
	_check("locked abilities can't be cast", not ab.try_cast(Abilities.SHOCKWAVE) and not ab.try_cast(Abilities.METEOR), "")
	ab.level = 4
	_check("level 4: Fire Nova still locked", not ab.is_unlocked(Abilities.SHOCKWAVE), "")
	ab.level = 5
	_check("level 5: Fire Nova unlocks", ab.is_unlocked(Abilities.SHOCKWAVE) and not ab.is_unlocked(Abilities.METEOR), "")
	ab.level = 9
	_check("level 9: Meteor still locked", not ab.is_unlocked(Abilities.METEOR), "")
	ab.level = 10
	_check("level 10: Meteor unlocks", ab.is_unlocked(Abilities.METEOR), "")
	_check("ability 2 is named Fire Nova, reach doubled to 18 m", Abilities.DEFS[Abilities.SHOCKWAVE]["name"] == "Fire Nova" and is_equal_approx(Abilities.SHOCK_RADIUS, 18.0), "")
	# Ready pulse on the ability bar: grows/brightens and returns to normal each pulse
	var slot := AbilitySlot.new()
	add_child(slot)
	slot.size = Vector2(78, 78)
	slot.set_locked(false)
	slot.set_cooldown(0.0, 0.0)
	var peak_scale := 1.0
	var peak_bright := 1.0
	var end_scale := 0.0
	for f in int(AbilitySlot.PULSE_PERIOD * 60.0):
		slot._process(1.0 / 60.0)
		peak_scale = maxf(peak_scale, slot.scale.x)
		peak_bright = maxf(peak_bright, slot.modulate.r)
	end_scale = slot.scale.x
	_check("ready slot pulses bigger and brighter", peak_scale > 1.07 and peak_bright > 1.4, "peak scale %.3f, brightness %.2f" % [peak_scale, peak_bright])
	_check("pulse returns to normal size at the end", absf(end_scale - 1.0) < 0.01, "end scale %.3f" % end_scale)
	slot.set_cooldown(0.5, 10.0)
	slot._process(1.0 / 60.0)
	_check("no pulse while on cooldown", is_equal_approx(slot.scale.x, 1.0) and is_equal_approx(slot.modulate.r, 1.0), "scale %.3f" % slot.scale.x)
	slot.set_locked(true)
	slot.set_cooldown(0.0, 0.0)
	slot._process(1.0 / 60.0)
	_check("no pulse while locked", is_equal_approx(slot.scale.x, 1.0), "scale %.3f" % slot.scale.x)
	slot.queue_free()

	var d_inf: Dictionary = Abilities.DEFS[Abilities.INFERNO]
	var d_met: Dictionary = Abilities.DEFS[Abilities.METEOR]
	_check("slot 1 is Inferno, 30 s", d_inf["key"] == "1" and d_inf["name"] == "Inferno" and d_inf["cooldown"] == 30.0 and not d_inf["ult"], str(d_inf))
	_check("slot 3 is the Meteor ultimate, 2 min", d_met["key"] == "3" and d_met["name"] == "Meteor" and d_met["cooldown"] == 120.0 and d_met["ult"], str(d_met))
	ab.cooldown = PackedFloat32Array([20.0, 40.0, 100.0])
	pm._apply(PotionManager.PURPLE)
	_check("purple cuts 30% of each full cooldown", is_equal_approx(ab.cooldown[0], 11.0) and is_equal_approx(ab.cooldown[1], 26.5) and is_equal_approx(ab.cooldown[2], 64.0),
		"%s" % str(ab.cooldown))
	player.hp = 100.0
	pm._apply(PotionManager.RED)
	_check("red heals 10% max HP", is_equal_approx(player.hp, 120.0), "hp %.1f" % player.hp)
	pm._apply(PotionManager.BLUE)
	_check("blue grants 10% max HP shield", is_equal_approx(player.shield, 20.0), "shield %.1f" % player.shield)
	player.invuln = 0.0
	player.hurt(30.0)   # armor 0 -> 30 dmg: 20 to shield, 10 to hp
	_check("shield absorbs first", is_equal_approx(player.shield, 0.0) and is_equal_approx(player.hp, 110.0), "shield %.1f hp %.1f" % [player.shield, player.hp])
	_check("hit starts 0.5 s immunity", is_equal_approx(player.invuln, 0.5), "invuln %.2f" % player.invuln)
	var hp_before := player.hp
	player.hurt(30.0)
	_check("no damage while immune", is_equal_approx(player.hp, hp_before), "hp %.1f" % player.hp)

	# 7) Goblin audio: all clips load; no ambient clip repeats within 5 s
	em.count = 0
	for k in 40:
		em.spawn(EnemyManager.GRUNT, Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(-10, 10)))
	em.tick(dt, Vector3.ZERO)
	var ga := GoblinAudio.new()
	var anchor := Node3D.new()
	add_child(anchor)
	ga.setup(em, anchor, rng)
	add_child(ga)
	_check("all 5 ambient clips + collision clip load", ga.ambient_count() == 5 and ga._collision != null, "ambient %d" % ga.ambient_count())
	var plays := {}
	var total := [0]
	var min_gap := [999.0]
	ga.played.connect(func(clip: int, at: float):
		if clip < 0:
			return
		total[0] += 1
		if plays.has(clip):
			min_gap[0] = minf(min_gap[0], at - plays[clip])
		plays[clip] = at)
	for f in 60 * 90:
		ga.tick(dt)
	_check("same clip never within 5 s", min_gap[0] >= 5.0 - 0.001, "min gap %.2f s over %d plays" % [min_gap[0], total[0]])
	_check("every clip gets used", plays.size() == 5, "%d clips used" % plays.size())
	var hits := [0]
	ga.played.connect(func(clip: int, _at: float): if clip == -1: hits[0] += 1)
	ga.play_collision()
	_check("collision plays the grunt", hits[0] == 1, "hits %d" % hits[0])

	# 7b) Staff attack: the cast plays on the upper body, the torso turns toward the target and
	#     the projectile leaves from the staff tip in his hand
	var wiz: HeroModel = player.model
	var target := player.global_position + wiz.global_transform.basis.x * 6.0 + Vector3(0, 0.5, 0)
	var tip := wiz.attack(target)
	await get_tree().process_frame
	var hand_pos := wiz.skeleton.global_transform * wiz.skeleton.get_bone_global_pose(wiz.skeleton.find_bone("RightHand")).origin
	_check("fireball cast plays (upper-body one-shot)", wiz.is_playing("fire"), "")
	_check("tip is on the staff in his hand", tip.distance_to(hand_pos) < 1.3 and tip.y > hand_pos.y - 0.4, "%.2f m from the hand" % tip.distance_to(hand_pos))
	_check("torso turns toward a target on his right", wiz.twist.target_angle < -0.5, "%.2f rad" % wiz.twist.target_angle)
	_check("staff_tip() matches", wiz.staff_tip().distance_to(tip) < 0.5, "")
	wiz.play_ability(Abilities.SHOCKWAVE)
	await get_tree().process_frame
	_check("Fire Nova plays the ground slam", wiz.is_playing("nova"), "")
	var ws := WeaponSystem.new()
	var wstats := Stats.new()
	for k in ["damage", "attack_speed", "area", "projectile_speed", "projectile_count", "orb_damage", "orb_cooldown", "orb_count", "orb_pierce", "orb_speed"]:
		wstats.define(k, {"damage": 1.0, "attack_speed": 1.0, "area": 1.0, "projectile_speed": 1.0, "orb_damage": 10.0, "orb_cooldown": 1.0, "orb_count": 3.0, "orb_speed": 20.0}.get(k, 0.0))
	em.count = 0
	for k in 3:
		em.spawn(EnemyManager.GRUNT, player.global_position + Vector3(4 + k, 0, -3 + k * 3))
	em.tick(dt, player.global_position)
	ws.setup(wstats, null, em, player)
	add_child(ws)
	ws._fire_orbs(player.global_position + Vector3(0, 0.9, 0), 1.0)
	var spawn_err := 0.0
	for k in ws.pc:
		spawn_err = maxf(spawn_err, ws.p_pos[k].distance_to(wiz.staff_tip()))
	_check("every orb spawns at the staff tip", ws.pc == 3 and spawn_err < 0.01, "%d orbs, max offset %.3f m" % [ws.pc, spawn_err])
	for f in 40:
		wiz._process(dt)
	_check("torso turns back to facing after the cast", wiz.twist.target_angle == 0.0, "%.2f rad" % wiz.twist.target_angle)

	# 8) Damage numbers + health bars
	var dn := DamageNumbers.new()
	add_child(dn)
	em.numbers = dn
	em.count = 0
	var g := em.spawn(EnemyManager.TANK, Vector3(0, 0, 0), 10.0)
	em.tick(dt, Vector3(0, 0, 30))
	em.damage(g, 50.0)
	_check("a hit spawns a damage number", dn.active_count() == 1, "active %d" % dn.active_count())
	for f in 50:
		dn._process(dt)
	_check("number gone in under 1 s", dn.active_count() == 0, "active %d after %.2f s" % [dn.active_count(), 50 * dt])
	_check("number lifetime < 1 s", DamageNumbers.LIFE < 1.0, "%.2f s" % DamageNumbers.LIFE)
	em.tick(dt, Vector3(0, 0, 30))
	var frac := em.bar_buf[12]
	_check("health bar shows hp fraction", absf(frac - (550.0 - 50.0) / 550.0) < 0.01, "bar %.3f" % frac)
	# Burn: totalled and shown about twice a second, not every frame
	em.ignite_all(10.0)
	var shown := 0
	for f in 62:
		var a0 := dn.active_count()
		dn._new_this_frame = 0
		em.tick(dt, Vector3(0, 0, 30))
		if dn.active_count() > a0:
			shown += dn.active_count() - a0
		dn._process(dt)
	_check("burn numbers ~2 per second", shown >= 2 and shown <= 3, "%d numbers in 1 s" % shown)

	# 9) Corpses: fall over, stay, gone 3 s after death
	var cm := CorpseManager.new()
	add_child(cm)
	em.corpses = cm
	em.count = 0
	var victim := em.spawn(EnemyManager.GRUNT, Vector3(2, 0, 2), 1.0)
	em.vel[victim] = Vector3(0, 0, 3)
	em.damage(victim, 1e6)
	_check("dead goblin leaves a corpse", cm.active_count() == 1, "corpses %d" % cm.active_count())
	for f in 30:
		cm._process(dt)
	# The fall is the baked death animation: clip = death, playing forward, facing kept
	var fwd := Vector3(cm._buf[2], cm._buf[6], cm._buf[10]).normalized()   # corpse's local +Z
	_check("corpse plays the death animation", is_equal_approx(cm._buf[12], cm._clip_death) and cm._buf[13] > 0.15, "clip %.2f phase %.2f" % [cm._buf[12], cm._buf[13]])
	_check("corpse keeps facing where it ran (falls backwards from there)", fwd.z > 0.9, "fwd %s" % str(fwd))
	for f in 120:
		cm._process(dt)
	_check("corpse still there at 2.5 s", cm.active_count() == 1, "")
	for f in 31:
		cm._process(dt)
	_check("corpse gone after 3 s", cm.active_count() == 0, "after %.2f s" % ((30 + 120 + 31) * dt))
	# Mass kill: pool recycles instead of growing without bound
	em.count = 0
	for k in 700:
		var e := em.spawn(EnemyManager.GRUNT, Vector3(k % 30, 0, k / 30), 1.0)
		if e < 0:
			break
	for k in em.count:
		em.damage(k, 1e6)
	_check("mass kills stay within the corpse pool", cm._count <= CorpseManager.MAX, "%d" % cm._count)

	# 10) Potions: slow spin, leaning bottle, blink every 0.3 s in the last 5 s
	pm.drop(Vector3(50, 0, 50), PotionManager.RED)
	var pot: Dictionary = pm._potions[pm._potions.size() - 1]
	var spinner: Node3D = pot["bottle"]
	var tilt_node: Node3D = spinner.get_child(0)
	_check("potion leans", rad_to_deg(absf(tilt_node.rotation.z)) > 15.0, "%.0f deg" % rad_to_deg(tilt_node.rotation.z))
	var y0 := spinner.rotation.y
	for f in 60:
		pm.tick(dt, 0.1)
	var turned := angle_difference(y0, spinner.rotation.y)
	_check("potion spins slowly (< 1 turn per 5 s)", absf(turned) > 0.5 and absf(turned) < TAU / 5.0, "%.2f rad in 1 s" % turned)
	var blinks := 0
	var prev := true
	var t := 0.0
	while t < PotionManager.LIFETIME:
		var v := PotionManager.is_visible_at(t)
		if t < PotionManager.LIFETIME - 5.0:
			_check("no blinking before the last 5 s", v, "t %.2f" % t) if not v else null
		if prev and not v:
			blinks += 1
		prev = v
		t += 0.01
	_check("blinks every 0.3 s for the last 5 s", blinks >= 16 and blinks <= 17, "%d blinks" % blinks)

	# 11) Power-ups from elites
	var gm := GemManager.new()
	add_child(gm)
	var pdb := UpgradeDB.new("res://data/upgrades.json", rng)
	var pstats := Stats.new()
	for k in ["max_hp", "regen", "armor", "move_speed", "extra_jumps", "damage"]:
		pstats.define(k, {"max_hp": 100.0, "move_speed": 8.0, "damage": 1.0}.get(k, 0.0))
	var pu := PowerupManager.new()
	pu.setup(player, pstats, em, gm, pdb, rng)
	add_child(pu)
	_check("power-up chance 2% base", is_equal_approx(pu.drop_chance(), 0.02), "%.3f" % pu.drop_chance())
	pdb.levels["tome_luck"] = 3
	_check("+1% per Luck level", is_equal_approx(pu.drop_chance(), 0.05), "%.3f at Luck 3" % pu.drop_chance())
	pdb.levels.erase("tome_luck")
	var drops := 0
	var kinds := {}
	for n in 20000:
		var before_n := pu.count()
		pu.on_elite_killed(Vector3(500, 0, 500))
		if pu.count() > before_n:
			drops += 1
			kinds[pu._pickups[pu._pickups.size() - 1]["kind"]] = true
	_check("elite drop rate ~2%", absf(drops / 20000.0 - 0.02) < 0.004, "%.2f%%" % (drops / 200.0))
	_check("all four power-ups can drop", kinds.size() == 4, "%d kinds" % kinds.size())
	# Magnet: every gem on the map heads to the player
	for k in 30:
		gm.spawn(Vector3(rng.randf_range(-80, 80), 0.5, rng.randf_range(-80, 80)), 1.0)
	pu.activate(PowerupManager.MAGNET)
	var all_pulled := true
	for k in gm.count:
		if gm.att[k] < 0.0:
			all_pulled = false
	var got_xp := 0.0
	for f in 60 * 6:
		got_xp += gm.tick(dt, player.global_position + Vector3(0, 0.9, 0), 0.1)
	_check("Magnet pulls every orb onto the player", all_pulled and gm.count == 0 and got_xp >= 30.0, "%d left, %.0f xp collected" % [gm.count, got_xp])
	# Fear: goblins run away
	em.count = 0
	var fg := em.spawn(EnemyManager.GRUNT, Vector3(10, 0, 0), 1.0)
	pu.activate(PowerupManager.FEAR)
	for f in 30:
		em.tick(dt, Vector3.ZERO)
	_check("Fear Idol: goblins move away from you", em.vel[fg].x > 2.0 and em.pos[fg].x > 10.0, "vel %s" % str(em.vel[fg]))
	for f in 60 * 15 + 2:
		pu.tick(dt, 0.1)
	_check("Fear lasts 15 s", not em.fear, "")
	# 5x damage for 10 s
	pu.activate(PowerupManager.DAMAGE)
	var dg := em.spawn(EnemyManager.TANK, Vector3(5, 0, 0), 100.0)
	var dh := em.hp[dg]
	em.damage(dg, 10.0)
	_check("5x Damage multiplies damage", is_equal_approx(dh - em.hp[dg], 50.0), "dealt %.0f" % (dh - em.hp[dg]))
	for f in 60 * 10 + 2:
		pu.tick(dt, 0.1)
	dh = em.hp[dg]
	em.damage(dg, 10.0)
	_check("5x Damage ends after 10 s", is_equal_approx(dh - em.hp[dg], 10.0), "dealt %.0f" % (dh - em.hp[dg]))
	# Movement +80% for 15 s, refresh doesn't stack
	pu.activate(PowerupManager.SPEED)
	pu.activate(PowerupManager.SPEED)
	_check("Movement Enhancer +80%", is_equal_approx(pstats.value("move_speed"), 8.0 * 1.8), "%.2f" % pstats.value("move_speed"))
	for f in 60 * 15 + 2:
		pu.tick(dt, 0.1)
	_check("Movement Enhancer ends after 15 s", is_equal_approx(pstats.value("move_speed"), 8.0), "%.2f" % pstats.value("move_speed"))

	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
