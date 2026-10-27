extends Node
## Micro-benchmark for the enemy crowd simulation (no rendering).
##   godot --headless --path . res://tools/bench_enemies.tscn

func _ready() -> void:
	var em := EnemyManager.new()
	em.rng = RandomNumberGenerator.new()
	em.rng.seed = 1
	add_child(em)
	for n in [500, 1000, 1400]:
		em.count = 0
		for i in n:
			var a := em.rng.randf() * TAU
			var d := em.rng.randf_range(8.0, 50.0)
			em.spawn(0, Vector3(cos(a) * d, 0, sin(a) * d))
		for f in 60:
			em.tick(1.0 / 60.0, Vector3.ZERO)
		var t0 := Time.get_ticks_usec()
		for f in 120:
			em.tick(1.0 / 60.0, Vector3.ZERO)
		var tick_ms := (Time.get_ticks_usec() - t0) / 120000.0
		t0 = Time.get_ticks_usec()
		for f in 120:
			em._build_grid(Vector3.ZERO)
		print("BENCH n=%d  tick %.2f ms  (grid build %.2f ms)" % [n, tick_ms, (Time.get_ticks_usec() - t0) / 120000.0])
	get_tree().quit()
