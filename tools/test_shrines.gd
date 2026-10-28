extends Node3D
## Shrine checks: placement (1-8, clear of obstacles), 5-yd zone timer that resets on leaving,
## chest tier per difficulty, chain lengths/counts/hits/burn, shrine fire, nova timing/hits,
## and jumping over hazards.
##   godot --headless --path . --fixed-fps 60 res://tools/test_shrines.tscn

var fails := 0
const DT := 1.0 / 60.0


func _ready() -> void:
	load("res://scripts/main.gd").setup_inputs()
	# --- Placement over several seeds
	var counts := []
	var clear := true
	for seed in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var root := Node3D.new()
		add_child(root)
		var water := WorldBuilder.build(root, rng, 110.0)
		var sm := ShrineManager.new()
		sm.setup(null, water, rng)
		root.add_child(sm)
		sm.spawn_all(110.0)
		counts.append(sm.shrines.size())
		for s in sm.shrines:
			if water.near_pool(s.position.x, s.position.z, Shrine.ZONE_RADIUS):
				clear = false
			for b in get_tree().get_nodes_in_group(TreeFire.GROUP):
				var nb := b as Node3D
				if Vector2(nb.global_position.x - s.position.x, nb.global_position.z - s.position.z).length() < Shrine.ZONE_RADIUS:
					clear = false
		root.queue_free()
		await get_tree().process_frame
	var lo: int = counts.min()
	var hi: int = counts.max()
	_check("4-14 shrines per run (the map is 440 m across)", lo >= ShrineManager.MIN_SHRINES and hi <= ShrineManager.MAX_SHRINES and hi > lo, str(counts))
	_check("shrine zones are clear of pools and trees", clear, "")
	_check("zone is 10 yards", is_equal_approx(Shrine.ZONE_RADIUS, 9.144), "%.3f m" % Shrine.ZONE_RADIUS)

	# --- A test player
	var stats := Stats.new()
	for k in ["max_hp", "regen", "armor", "move_speed", "extra_jumps", "damage"]:
		stats.define(k, {"max_hp": 100.0, "move_speed": 8.0, "damage": 1.0}.get(k, 0.0))
	var player := Player.new()
	player.stats = stats
	player.bot = true
	add_child(player)
	await get_tree().physics_frame

	# --- Zone timer + reset + chest tier (nova D1, standing where rings won't matter: use jump height)
	for d in [1, 2, 3]:
		var s := _shrine(Shrine.NOVA, d)
		var got := [null]
		s.completed.connect(func(x): got[0] = x)
		_put(player, s, Vector2(3.0, 0.0), 5.0)   # inside, floating above the rings
		_run(s, player, 6.0)
		var mid := s.progress
		_put(player, s, Vector2(Shrine.ZONE_RADIUS + 2.0, 0.0), 5.0)    # step out
		_run(s, player, DT)
		var after_leave := s.progress
		_put(player, s, Vector2(3.0, 0.0), 5.0)
		_run(s, player, 10.05)
		_check("D%d: time builds while inside" % d, mid > 5.9, "%.2f s" % mid)
		_check("D%d: leaving loses all seconds" % d, after_leave == 0.0, "%.2f" % after_leave)
		_check("D%d: 10 s inside completes the shrine" % d, s.done and got[0] == s, "")
		var sm2 := ShrineManager.new()
		sm2.setup(player, null, RandomNumberGenerator.new())
		add_child(sm2)
		sm2._on_completed(s)
		var chest: Chest = sm2.get_child(sm2.get_child_count() - 1)
		_check("D%d reward: %s chest" % [d, ["Bronze", "Silver", "Gold"][d - 1]], chest.tier == d - 1, Chest.TIER_NAMES[chest.tier])
		sm2.queue_free()
		s.queue_free()

	# --- Chains
	var full := Shrine.ZONE_RADIUS - Shrine.PILLAR_RADIUS
	var expect_len := [full, full, full]   # every difficulty reaches the zone edge
	for d in [1, 2, 3]:
		var s := _shrine(Shrine.CHAINS, d)
		_check("chains D%d: %d chain(s), %.2f m long" % [d, d, expect_len[d - 1]], s._chains.size() == d and is_equal_approx(Shrine.CHAIN_LENGTHS[d - 1], expect_len[d - 1]), "")
		# Stand on chain 0's path, at the middle of its length
		var a := s.chain_angle(0)
		var mid_r: float = Shrine.PILLAR_RADIUS + float(Shrine.CHAIN_LENGTHS[d - 1]) * 0.5
		var on_chain: Vector2 = Vector2(cos(a), sin(a)) * mid_r
		_check("chains D%d: touching the chain hits" % d, s.chain_hits(on_chain, 0.0), "")
		_check("chains D%d: jumping over avoids it" % d, not s.chain_hits(on_chain, 1.0), "")
		var off_chain: Vector2 = Vector2(cos(a + PI / float(d) * 0.5), sin(a + PI / float(d) * 0.5)) * (mid_r if d > 1 else 1.0)
		_check("chains D%d: away from the chains is safe" % d, not s.chain_hits(off_chain, 0.0), "")
		# Effect of a touch
		player.hp = 100.0
		player.invuln = 0.0
		player.burn_left = 0.0
		_put(player, s, on_chain, 0.0)
		s._tick_chains(0.0, player, on_chain, 0.0)
		if d == 1:
			_check("chains D1: hit costs 10% HP, no burn", is_equal_approx(player.hp, 90.0) and player.burn_left == 0.0, "hp %.1f" % player.hp)
			_check("chains: a hit starts 0.5 s immunity and knocks you back", is_equal_approx(player.invuln, Player.IFRAMES) and Vector2(player.velocity.x, player.velocity.z).length() > 5.0, "invuln %.2f" % player.invuln)
			s._tick_chains(0.0, player, on_chain, 0.0)
			_check("chains: no second hit while immune", is_equal_approx(player.hp, 90.0), "hp %.1f" % player.hp)
		else:
			_check("chains D%d: touch sets you on fire" % d, is_equal_approx(player.burn_left, Player.BURN_TIME) and is_equal_approx(player.hp, 100.0), "burn %.2f" % player.burn_left)
		s.queue_free()

	# Burn: 5%/s for 2 s, doesn't stack, re-touch refreshes
	player.hp = 100.0
	player.burn_left = 0.0
	player.ignite()
	for f in 60:
		player._tick_burn(DT)
	player.ignite()   # touched again 1 s in: refresh, not stack
	for f in 60 * 3:
		player._tick_burn(DT)
	_check("burn: 5% max HP per second, 2 s, refresh doesn't stack", absf(player.hp - 85.0) < 0.2, "hp %.1f (expected 85: 1 s + refreshed 2 s)" % player.hp)

	# D3 shrine itself burns
	var s3 := _shrine(Shrine.CHAINS, 3)
	player.burn_left = 0.0
	player.invuln = 0.0
	var a3 := s3.chain_angle(0) + PI / 3.0
	var at_pillar := Vector2(cos(a3), sin(a3)) * (Shrine.PILLAR_RADIUS + 0.45)
	s3._tick_chains(0.0, player, at_pillar, 0.5)
	_check("chains D3: touching the burning shrine burns", player.burn_left > 0.0, "")
	var s1 := _shrine(Shrine.CHAINS, 1)
	player.burn_left = 0.0
	player.invuln = 0.0
	var a1 := s1.chain_angle(0) + PI
	s1._tick_chains(0.0, player, Vector2(cos(a1), sin(a1)) * (Shrine.PILLAR_RADIUS + 0.45), 0.5)
	_check("chains D1: shrine is not on fire", player.burn_left == 0.0, "")
	s3.queue_free()
	s1.queue_free()

	# --- Nova: pulses per 10 s, slow speed, hits and jumping
	var expect_rings := [5, 10, 7]   # D3: one ring every 1.5 s
	for d in [1, 2, 3]:
		var s := _shrine(Shrine.NOVA, d)
		var emitted := [0]
		var orig_count := 0
		_put(player, s, Vector2(40, 40), 5.0)   # far away
		var total := 0
		for f in 590:   # 9.83 s - doesn't end on a pulse boundary
			var before := s.nova_count()
			s.tick(DT, player)
			if s.nova_count() > before:
				total += s.nova_count() - before
		_check("nova D%d: %d rings in 10 s" % [d, expect_rings[d - 1]], total == expect_rings[d - 1], "%d rings" % total)
		s.queue_free()
	var sn := _shrine(Shrine.NOVA, 1)
	_check("nova moves slowly (~3 s to cross the zone)", (Shrine.ZONE_RADIUS - Shrine.PILLAR_RADIUS) / Shrine.NOVA_SPEED > 2.5, "%.1f m/s" % Shrine.NOVA_SPEED)
	_check("nova hits when the ring reaches you", sn.nova_hits(2.0, Vector2(2.0, 0.0), 0.0), "")
	_check("nova: jumping over avoids it", not sn.nova_hits(2.0, Vector2(2.0, 0.0), 1.0), "")
	_check("nova: rings elsewhere miss", not sn.nova_hits(1.0, Vector2(3.0, 0.0), 0.0), "")
	player.hp = 100.0
	player.invuln = 0.0
	_put(player, sn, Vector2(Shrine.PILLAR_RADIUS + 0.05, 0.0), 0.0)
	sn.tick(DT, player)
	_check("nova hit costs 8% HP", is_equal_approx(player.hp, 92.0), "hp %.1f" % player.hp)
	_check("nova: hit gives 0.5 s immunity", is_equal_approx(player.invuln, Player.IFRAMES), "%.2f" % player.invuln)
	_put(player, sn, Vector2(Shrine.PILLAR_RADIUS + 0.05, 0.0), 0.0)
	sn.tick(DT, player)
	_check("nova: no repeat damage while immune", is_equal_approx(player.hp, 92.0), "hp %.1f" % player.hp)
	_check("nova: rings float off the ground", Shrine.NOVA_LIFT >= 0.2, "")
	sn.queue_free()

	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _shrine(pattern: int, d: int) -> Shrine:
	var s := Shrine.new()
	s.setup(pattern, d)
	s.position = Vector3(500, 0, 500)
	add_child(s)
	return s


func _put(player: Player, s: Shrine, flat: Vector2, height: float) -> void:
	player.global_position = s.global_position + Vector3(flat.x, height, flat.y)


func _run(s: Shrine, player: Player, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		s.tick(DT, player)
		t += DT


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
