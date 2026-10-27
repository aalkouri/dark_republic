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
	await _check_meteor(root, player, water)
	_check("water halves jump height", absf(pool_jump / land_jump - 0.5) < 0.06, "%.2f vs %.2f m (x%.2f)" % [pool_jump, land_jump, pool_jump / land_jump])


func _check_meteor(root: Node3D, player: Player, water: SwampWater) -> void:
	var em := EnemyManager.new()
	em.rng = RandomNumberGenerator.new()
	em.water = water
	root.add_child(em)
	var fx := FxManager.new()
	root.add_child(fx)
	var ab := Abilities.new()
	ab.setup(player.stats, em, player, fx)
	ab.level = 10
	root.add_child(ab)
	await _place(player, Vector3(0, 0.3, 0))
	player.cam_yaw = 0.0
	player.cam_pitch = -0.6
	for f in 5:
		await get_tree().physics_frame
	var cast_from := player.global_position
	ab.try_cast(Abilities.METEOR)
	var target: Vector3 = ab._meteors[0]["target"]
	await get_tree().process_frame
	_check("meteor: wizard is invulnerable at once and plays the slam", player.meteor_form and player.model.is_playing("meteor"), "form %s" % player.meteor_form)
	await get_tree().create_timer(HeroModel.VANISH_TIME + 0.1).timeout
	_check("meteor: wizard vanishes after the slam", player.meteor_form and not player.model.visible, "form %s visible %s" % [player.meteor_form, player.model.visible])
	player.invuln = 0.0
	var hp0 := player.hp
	_check("meteor: invulnerable while falling", not player.hurt(50.0) and player.hp == hp0, "hp %.0f" % player.hp)
	var head: Node3D = ab._meteors[0]["head"]
	var has_hat := head.find_children("*", "MeshInstance3D", true, false).size() >= 6
	_check("meteor: falling object is the giant wizard head", has_hat and is_equal_approx(head.get_child(0).scale.x, Abilities.HEAD_SCALE), "%d meshes" % head.find_children("*", "MeshInstance3D", true, false).size())
	for f in int(60 * 1.5):
		ab.tick(1.0 / 60.0)
		await get_tree().physics_frame
	_check("meteor: still hidden mid-fall", player.meteor_form, "")
	for f in int(60 * 1.6):
		ab.tick(1.0 / 60.0)
		await get_tree().physics_frame
	_check("meteor: wizard reappears at the crash site", not player.meteor_form and player.model.visible and Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < 0.2,
		"at %s target %s" % [str(player.global_position), str(target)])
	_check("meteor: ground is burning", ab.scorch_count() == 1, "zones %d" % ab.scorch_count())
	# Burning ground: 3% max HP per second for (the remaining) 3 s
	var g := em.spawn(EnemyManager.TANK, target + Vector3(2, 0, 0), 100.0)
	em.tick(1.0 / 60.0, target + Vector3(50, 0, 0))
	var start_hp := em.hp[g]
	var burned := 0.0
	for f in 60 * 4:
		ab.tick(1.0 / 60.0)
		em.knock(g, Vector3.ZERO, 0.0)   # pin in place
		em.pos[g] = target + Vector3(2, 0, 0)
		em._build_grid(target)
	burned = (start_hp - em.hp[g]) / em.hp_max[g]
	_check("burning ground: ~3%/s while it lasts (3 s)", absf(burned - 0.09) < 0.01, "lost %.1f%% of max HP" % (burned * 100.0))
	_check("burning ground goes out", ab.scorch_count() == 0, "zones %d" % ab.scorch_count())

	# Meteor sets trees on fire; they char black after 15 s and stay charred
	var trees := get_tree().get_nodes_in_group(TreeFire.GROUP)
	var standing: Node3D = null
	for t in trees:
		if not (t as Node3D).has_meta("burn_state") and float(t.get_meta("reach")) < 2.0:
			standing = t
			break
	var hit_at := standing.global_position + Vector3(3, 0, 0)
	var lit := ab._ignite_trees(hit_at)
	var far_unlit := 0
	for t in trees:
		var tb := t as Node3D
		var dist := Vector2(tb.global_position.x - hit_at.x, tb.global_position.z - hit_at.z).length()
		if dist > Abilities.METEOR_RADIUS + float(tb.get_meta("reach")) and TreeFire.state_of(tb) != "":
			far_unlit += 1
	_check("meteor sets a tree in the blast on fire", TreeFire.state_of(standing) == "burning" and lit >= 1, "%d trees lit" % lit)
	_check("trees outside the blast don't catch", far_unlit == 0, "%d far trees burning" % far_unlit)
	var fire: TreeFire = null
	for c in standing.get_children():
		if c is TreeFire:
			fire = c
	fire.set_process(false)   # drive it manually
	for f in 60 * 7:
		fire._process(1.0 / 60.0)
	var mid_char: float = fire._mat.get_shader_parameter("char_amount")
	_check("tree is charring while it burns", mid_char > 0.4 and mid_char < 0.6 and TreeFire.state_of(standing) == "burning", "char %.2f at 7 s" % mid_char)
	var mat: ShaderMaterial = (standing.get_meta("mesh_instance") as MeshInstance3D).material_override
	for f in 60 * 8 + 2:
		if is_instance_valid(fire):
			fire._process(1.0 / 60.0)
	_check("after 15 s the tree is charred black and the fire is out", TreeFire.state_of(standing) == "charred" and is_equal_approx(mat.get_shader_parameter("char_amount"), 1.0) and is_equal_approx(mat.get_shader_parameter("burning"), 0.0), TreeFire.state_of(standing))
	_check("a charred tree can't burn again", not TreeFire.ignite(standing), "")
	var shared: ShaderMaterial = MeshBuilder.prop_material()
	var shared_char = shared.get_shader_parameter("char_amount")
	_check("only the burnt tree is blackened", shared_char == null or is_equal_approx(shared_char, 0.0), "")

	# Fire Nova reaches 18 m (was 9 m): a goblin 16 m away is hit and knocked back
	await _place(player, Vector3(0, 0.3, 0))
	em.count = 0
	var far_g := em.spawn(EnemyManager.TANK, player.global_position + Vector3(16, 0, 0), 100.0)
	var beyond := em.spawn(EnemyManager.TANK, player.global_position + Vector3(0, 0, 21), 100.0)
	em.tick(1.0 / 60.0, player.global_position)
	var hp_far := em.hp[far_g]
	var hp_beyond := em.hp[beyond]
	ab.cooldown[Abilities.SHOCKWAVE] = 0.0
	ab.try_cast(Abilities.SHOCKWAVE)
	var pushed := false
	for f in 60:
		ab.tick(1.0 / 60.0)
		em._build_grid(player.global_position)
		if em.kb_t[far_g] > 0.0:
			pushed = true
	_check("Fire Nova hits a goblin 16 m away", em.hp[far_g] < hp_far and pushed, "hp %.0f -> %.0f, knocked %s" % [hp_far, em.hp[far_g], pushed])
	_check("Fire Nova stops at 18 m", is_equal_approx(em.hp[beyond], hp_beyond), "21 m goblin hp %.0f -> %.0f" % [hp_beyond, em.hp[beyond]])


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
