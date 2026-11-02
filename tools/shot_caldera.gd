extends Node3D
## Scripted screenshots of the Ashen Caldera's creatures and Singe (needs a display, not
## --headless). One stage per run, so each stays short:
##   godot --path . res://tools/shot_caldera.tscn -- <stage> /out/prefix [seed]
## stage: crowd (a pack of every creature coming at you, a slug's trail), rise (Singe bursting
## out of the pool), singe (capering at you), breath (fire breath), scamper (his scorch run), ult (the
## Caldera Eruption building: islands and arrows; then flooded, you on an island), dead.

var main: Node
var prefix := ""
var stage := ""


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	stage = a[0]
	prefix = a[1]
	var sd := int(a[2]) if a.size() > 2 else 3
	Wallet.persist = false
	Settings.selected_map = "caldera"
	Settings.selected_character = "fire_wizard"
	Settings.game_mode = "classic"
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	for f in 60 * 15:
		await get_tree().physics_frame
		if not main.intro:
			break
	for c in main.hud.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	main.hud.visible = false
	Wallet.set_shown(false)
	main.xp_next = 1e12
	main._next_swarm = 1e9
	main.weapons.orb_t = 1e9
	main.player.god_mode = true
	Player.zoom = 9.0
	match stage:
		"crowd": await _crowd()
		_: await _boss()
	get_tree().quit()


func _crowd() -> void:
	var em: EnemyManager = main.enemies
	var at := Vector3(28, 0, 26)
	var look := Vector3(28, 0, 6)
	_place(at, look)
	await _secs(0.5)
	var p: Vector3 = main.player.global_position
	var fwd := Vector3(0, 0, -1)
	var side := Vector3(1, 0, 0)
	var spawn := func(t: int, off: Vector3, epic := false) -> int:
		var q: Vector3 = p + side * off.x + fwd * off.z
		return em.spawn(t, q, 1.0, epic)
	# a slug crawls ahead first, laying its trail
	var sl: int = spawn.call(EnemyManager.LAVA_SLUG, Vector3(-3.0, 0, 9.0))
	for k in 5:
		spawn.call(EnemyManager.MAGMA_IMP, Vector3(2.0 + k * 0.9, 0, 15.0 + (k % 2) * 1.2))
	spawn.call(EnemyManager.MAGMA_IMP, Vector3(-1.0, 0, 13.0), true)
	spawn.call(EnemyManager.OBSIDIAN_GOLEM, Vector3(6.5, 0, 19.0))
	spawn.call(EnemyManager.OBSIDIAN_GOLEM, Vector3(-7.0, 0, 21.0), true)
	spawn.call(EnemyManager.LAVA_SLUG, Vector3(-5.5, 0, 12.0))
	for k in 3:
		spawn.call(EnemyManager.CINDER_BAT, Vector3(-4.0 + k * 4.0, 0, 12.0 + k * 2.0), k == 1)
	for f in int(60 * 2.2):
		main._spawn_budget = -1e9
		_place(at, look)
		main.player.cam_pitch = -0.12
		await get_tree().physics_frame
	await _save("crowd")


func _boss() -> void:
	var player: Player = main.player
	var em: EnemyManager = main.enemies
	var lair := SingeBoss.rise_point()
	var stand := lair + Vector3(6, 0, 34) if stage != "rise" else lair + Vector3(12, 0, 17)
	_place(stand, lair)
	main._spawn_budget = -1e9
	main.run_time = main.THOG_TIME + 0.05
	for f in 60 * 2:
		await _hold(stand, lair)
	var b: SingeBoss = main.map_boss
	if stage == "rise":
		for f in 25:
			await _hold(stand + Vector3(-5, 0, 3), lair + Vector3(0, 3, 0))
		player.cam_pitch = 0.05
		await _save("singe_rise")
		return
	for f in int(60 * 2.0):
		await _hold(stand, lair)
	b._summon_cd = 999.0
	b._dive_cd = 999.0
	b._meteor_cd = 999.0
	b._breath_cd = 999.0
	b._gap = 999.0
	b._scamper_cd = 999.0
	if stage == "singe":   # he capers out of the pool after you
		var away := lair + Vector3(-12, 0, 17)
		for f in 60 * 5:
			_clear(em)
			await _hold(away, b.global_position + Vector3(0, 3, 0))
			if MapBoss.flat_dist(b.global_position, main.player.global_position) < 12.0:
				break
		var i := b.row()
		var to: Vector3 = main.player.global_position - em.pos[i]
		to.y = 0.0
		var cam: Vector3 = em.pos[i] + to.normalized() * 12.0 + Vector3(-to.z, 0, to.x).normalized() * 6.0
		for f in 20:
			await _hold(cam, b.global_position + Vector3(0, 3, 0))
		player.cam_pitch = -0.1
		Player.zoom = 6.0
		await _hold(cam, b.global_position + Vector3(0, 3.5, 0))
		await _save("singe")
		return
	var i2 := b.row()
	var to2 := (stand - em.pos[i2])
	to2.y = 0.0
	var side := stand + Vector3(-to2.z, 0, to2.x).normalized() * 16.0 - to2.normalized() * 6.0
	if stage == "breath":
		b._start("breath")
		var target := b.global_position + to2.normalized() * 10.0 + Vector3(0, 2, 0)
		for f in int(60 * (SingeBoss.BREATH_WARN + 0.45)):
			_clear(em)
			await _hold(side, target)
		player.cam_pitch = -0.12
		await _save("singe_breath")
		return
	if stage == "scamper":
		b._start("scamper")
		for f in int(60 * 2.6):
			_clear(em)
			await _hold(side, stand)
		player.cam_pitch = -0.3
		Player.zoom = 12.0
		await _hold(side, stand)
		await _save("singe_scamper")
		return
	if stage == "ult":
		em.hp[b.row()] = em.hp_max[b.row()] * 0.74
		for f in 60 * 4:
			_clear(em)
			await _hold(side, b.global_position + Vector3(0, 5, 0))
		var isl: Dictionary = b.islands[0] if not b.islands.is_empty() else {}
		var look := b.global_position + Vector3(0, 6, 0)
		Player.zoom = 14.0
		player.cam_pitch = -0.25
		await _hold(side, look)
		await _save("ult_warn")
		if not isl.is_empty():
			var top := Vector3((isl["at"] as Vector3).x, float(isl["top"]) + 0.4, (isl["at"] as Vector3).z)
			player.global_position = top
			for f in 60 * 7:
				_clear(em)
				player.global_position = Vector3(top.x, player.global_position.y, top.z)
				player.velocity = Vector3.ZERO
				player.cam_yaw = atan2(-(b.global_position.x - top.x), -(b.global_position.z - top.z))
				player.cam_pitch = -0.3
				await get_tree().physics_frame
			await _save("ult_flood")
		return
	if stage == "dead":
		Player.zoom = 12.0
		em.damage(b.row(), 1e9)
		for f in 60 * 6:
			await _hold(side, b.global_position)
		player.cam_pitch = -0.2
		await _save("singe_dead")


func _place(p: Vector3, look: Vector3) -> void:
	var player: Player = main.player
	player.global_position = Vector3(p.x, SwampWater.height_at(p.x, p.z) + 0.3, p.z)
	player.velocity = Vector3.ZERO
	var to := look - player.global_position
	player.cam_yaw = atan2(-to.x, -to.z)


func _hold(p: Vector3, look: Vector3) -> void:
	_place(p, look)
	main._spawn_budget = -1e9
	await get_tree().physics_frame


func _secs(s: float) -> void:
	for f in int(s * 60):
		await get_tree().physics_frame


func _save(n: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [prefix, n])
	print("SHOT ", n)


func _clear(em: EnemyManager) -> void:
	for k in em.count:
		if em.dead[k] == 0 and em.typ[k] != EnemyManager.TROLL:
			em.dead[k] = 1
			em._dead_count += 1
