extends Node3D
## Swamp world checks: pool sizes/depths, recessed collision, and the water rules
## (50% move speed, 50% jump height) measured with the real player controller.
##   godot --headless --path . --fixed-fps 60 res://tools/test_swamp.tscn

var fails := 0


func _ready() -> void:
	load("res://scripts/main.gd").setup_inputs()
	for seed in [11, 222, 3333]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var root := Node3D.new()
		add_child(root)
		var water := WorldBuilder.build(root, rng, 110.0)
		_check_pools(water, seed)
		if seed == 11:
			await _check_movement(root, water)
		root.queue_free()
		await get_tree().process_frame
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check_pools(water: SwampWater, seed: int) -> void:
	_check("seed %d: 4 pools" % seed, water.pools.size() == 4, "%d" % water.pools.size())
	var widest := 0.0
	var deepest := 0.0
	var lumpiness := 0.0
	for p in water.pools:
		var rmin := 1e9
		var rmax := 0.0
		for k in 720:
			var th := TAU * k / 720.0
			var dia := water.outline_radius(p, th) + water.outline_radius(p, th + PI)
			widest = maxf(widest, dia)
			var r := water.outline_radius(p, th)
			rmin = minf(rmin, r)
			rmax = maxf(rmax, r)
		lumpiness = maxf(lumpiness, rmax / rmin)
		for ri in 40:
			for k in 90:
				deepest = maxf(deepest, -water.bed_height(p, ri / 40.0, TAU * k / 90.0))
	_check("seed %d: diameter <= 10 yd (9.14 m)" % seed, widest <= 9.144, "widest %.2f m" % widest)
	_check("seed %d: depth < character height (1.8 m)" % seed, deepest < 1.8, "deepest %.2f m" % deepest)
	_check("seed %d: shapes are irregular" % seed, lumpiness > 1.05, "max/min radius %.2f" % lumpiness)


func _check_movement(root: Node3D, water: SwampWater) -> void:
	# Let physics register the world, then check the heightmap is recessed at a pool.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var p: Dictionary = water.pools[0]
	var c: Vector2 = p["center"]
	var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, 10, c.y), Vector3(c.x, -10, c.y))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var expect := water.ground_height(c.x, c.y)
	_check("collision is recessed at pool centre", not hit.is_empty() and absf(hit["position"].y - expect) < 0.15,
		"hit %.2f expected %.2f" % [hit["position"].y if not hit.is_empty() else 99.0, expect])

	var stats := Stats.new()
	for k in ["max_hp", "regen", "armor", "move_speed", "extra_jumps", "damage"]:
		stats.define(k, {"max_hp": 100.0, "move_speed": 8.0, "damage": 1.0}.get(k, 0.0))
	var player := Player.new()
	player.stats = stats
	player.water = water
	player.bot = true
	root.add_child(player)

	# Pool: stand at the centre, walk for 0.8 s (stays inside), measure speed and a jump.
	var deep_spot := Vector3(c.x, expect + 0.2, c.y)
	var pool_speed: float = await _measure_speed(player, deep_spot)
	_check("player registers as in water", player.in_water, "in_water %s" % player.in_water)
	var pool_jump: float = await _measure_jump(player, deep_spot)

	# Dry land: far from every pool
	var dry := Vector3(0, 0.3, 0)
	var land_speed: float = await _measure_speed(player, dry)
	var land_jump: float = await _measure_jump(player, dry)

	_check("water halves move speed", absf(pool_speed / land_speed - 0.5) < 0.05, "%.2f vs %.2f m/s (x%.2f)" % [pool_speed, land_speed, pool_speed / land_speed])
	_check("water halves jump height", absf(pool_jump / land_jump - 0.5) < 0.06, "%.2f vs %.2f m (x%.2f)" % [pool_jump, land_jump, pool_jump / land_jump])


func _place(player: Player, at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.bot_move = Vector2.ZERO
	player.bot_jump = false
	for f in 30:
		await get_tree().physics_frame


func _measure_speed(player: Player, at: Vector3) -> float:
	await _place(player, at)
	player.bot_move = Vector2(0, -1)
	for f in 24:
		await get_tree().physics_frame
	var total := 0.0
	for f in 12:
		await get_tree().physics_frame
		total += player.horizontal_speed()
	player.bot_move = Vector2.ZERO
	return total / 12.0


func _measure_jump(player: Player, at: Vector3) -> float:
	await _place(player, at)
	var y0 := player.global_position.y
	player.bot_jump = true
	await get_tree().physics_frame
	player.bot_jump = false
	var peak := y0
	for f in 60:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	return peak - y0


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
