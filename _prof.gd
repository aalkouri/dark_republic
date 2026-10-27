extends SceneTree
func _init():
	var em = load("res://scripts/enemy_manager.gd").new()
	em.rng = RandomNumberGenerator.new(); em.rng.seed = 1
	root.add_child(em)
	await process_frame
	for i in 1400:
		var a = em.rng.randf()*TAU; var d = em.rng.randf_range(8, 50)
		em.spawn(0, Vector3(cos(a)*d, 0, sin(a)*d))
	for f in 60: em.tick(1.0/60.0, Vector3.ZERO)
	var t0 = Time.get_ticks_usec()
	for f in 120: em.tick(1.0/60.0, Vector3.ZERO)
	print("tick avg ms: ", (Time.get_ticks_usec()-t0)/120.0/1000.0)
	t0 = Time.get_ticks_usec()
	for f in 120: em._build_grid(Vector3.ZERO)
	print("grid avg ms: ", (Time.get_ticks_usec()-t0)/120.0/1000.0)
	quit()
