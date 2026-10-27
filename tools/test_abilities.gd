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
	em.burn_dps_frac = Abilities.ULT_BURN_DPS
	em.burn_explode_frac = Abilities.ULT_EXPLODE_FRAC
	em.burn_explode_radius = Abilities.ULT_EXPLODE_RADIUS
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
	em.ignite_all(Abilities.ULT_BURN_TIME)
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
	var pm := PotionManager.new()
	pm.setup(player, ab, rng)
	add_child(pm)
	var tally := [0, 0, 0]
	for n in 20000:
		tally[pm.roll_kind()] += 1
	_check("drop odds ~30/50/20", absf(tally[0] / 200.0 - 30.0) < 1.5 and absf(tally[1] / 200.0 - 50.0) < 1.5 and absf(tally[2] / 200.0 - 20.0) < 1.5,
		"%.1f / %.1f / %.1f %%" % [tally[0] / 200.0, tally[1] / 200.0, tally[2] / 200.0])

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
	_check("collision plays Ow", hits[0] == 1, "hits %d" % hits[0])

	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
