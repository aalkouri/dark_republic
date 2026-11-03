extends Node
## The last six characters (all but Kong built in code, HeroBody): Death, Billy Bulldog, Cowboy, the Sentient
## Platypus, the Bog Witch and Kong. Each one: playable, its body, its weapon hits, and each of its
## three abilities does what it says.
##   godot --headless --path . --fixed-fps 60 res://tools/test_six.tscn

var fails := 0
var main: Node
var em: EnemyManager
var player: Player
var ab: Abilities
var ws: WeaponSystem


func _ready() -> void:
	Wallet.persist = false
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	for id in HeroBody.KINDS:
		_check("%s is playable (a body and a kit)" % id, RosterHero.is_playable(id) and RosterKit.PARTS.has(id), "")
	await _death()
	await _bulldog()
	await _cowboy()
	await _platypus()
	await _witch()
	await _kong()
	get_tree().paused = false
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


## Load a run as `id`, check the body and that the weapon hurts the nearest goblin.
func _load(id: String, style: String) -> KitPart:
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
	main.set("_spawn_budget", -1.0e9)
	ab.level = 10
	await _secs(0.2)
	var body = player.model.get("boss") if player.model != null else null
	if id == "kong":   # Kong has a rigged model (models/kong/), not a HeroBody
		_check("kong: plays on his own rigged model", player.model.get("skeleton") != null and body == null, str(player.model.get("skeleton")))
	else:
		_check("%s: built in code (HeroBody '%s')" % [id, id], body is HeroBody and (body as HeroBody).kind == id, str(body))
	_clear()
	var e := _spawn(EnemyManager.GRUNT, 2.0 if WeaponSystem.MELEE.has(style) else 6.0, 0.0, 50.0)
	await _secs(0.05)
	var fired: bool = ws.fire(style, "orb", 1.0)
	await _secs(0.8)   # projectiles / lobs land
	_check("%s: the weapon (%s) hits" % [id, style], fired and em.hp[e] < em.hp_max[e], "fired %s, hp %.0f / %.0f" % [fired, em.hp[e], em.hp_max[e]])
	if body is HeroBody:
		_check("%s: the body swings / shoots" % id, (body as HeroBody).attacks >= 1, "")
	return ab.roster.part


func _death() -> void:
	var kit: KitDeath = await _load("death", "scythe")
	_clear()
	var low := _spawn(EnemyManager.GRUNT, 5.0, 0.0, 50.0)
	var high := _spawn(EnemyManager.GRUNT, 6.0, 1.0, 50.0)
	em.hp[low] = em.hp_max[low] * 0.2
	await _secs(0.05)
	_cast(0)
	_check("Harvest reaps an enemy under 30% HP, not a healthy one", em.dead[low] == 1 and em.dead[high] == 0, "")
	_check("...and its soul makes him stronger", kit.souls > 0.0, "%.2f" % kit.souls)
	_clear()
	var big := _spawn(EnemyManager.TANK, 8.0, 0.0, 30.0)
	await _secs(0.05)
	var hp0 := em.hp[big]
	_cast(1)
	await _secs(KitDeath.MARK_DELAY + 0.3)
	_check("Mark of the Inevitable: 5 s later the marked enemy takes 400", em.hp[big] < hp0 - 300.0 or em.dead[big] == 1, "%.0f -> %.0f" % [hp0, em.hp[big]])
	var t0: float = main.run_time
	_cast(2)
	await _secs(1.0)
	_check("Overtime: the run clock stops", absf(main.run_time - t0) < 0.05 and main.xp_bonus == 2.0, "%.2f -> %.2f" % [t0, main.run_time])


func _bulldog() -> void:
	var kit: KitBulldog = await _load("billy_bulldog", "bite")
	_clear()
	var e := _spawn(EnemyManager.GRUNT, 14.0, 0.0, 30.0)
	await _secs(0.05)
	var d0 := player.global_position.distance_to(em.pos[e])
	_cast(0)
	await _secs(2.0)
	_check("Fetch!: enemies near the bone rush to it, harmless", em.confuse_t[e] > 0.0 or em.dead[e] == 1, "")
	await _secs(3.0)
	_check("...then it explodes", em.hp[e] < em.hp_max[e] or em.dead[e] == 1, "")
	var sp0 := player.stats.value("move_speed")
	_cast(1)
	_check("Zoomies: double move speed", is_equal_approx(player.stats.value("move_speed"), sp0 * 2.0) and kit.active("zoomies"), "")
	_clear()
	var p := _spawn(EnemyManager.GRUNT, 8.0, 0.0, 50.0)
	await _secs(0.05)
	_cast(2)
	await _secs(0.5)
	_check("Who's a Good Boy: they stop to pet him", em.stun_t[p] > 0.0, "")
	await _secs(KitBulldog.PET_TIME)
	_check("...then the bark hurts", em.hp[p] < em.hp_max[p] or em.dead[p] == 1, "")


func _cowboy() -> void:
	var kit: KitCowboy = await _load("cowboy", "revolver")
	var shots := 0
	ws._rev_shots = 0
	ws._rev_reload = 0.0
	_clear()
	_spawn(EnemyManager.TANK, 6.0, 0.0, 100.0)
	await _secs(0.05)
	for k in 8:
		if ws.fire("revolver", "orb", 1.0):
			shots += 1
	_check("Six-Shooter: 6 shots, then a reload", shots == 6 and ws._rev_reload > 0.0, "%d shots" % shots)
	_clear()
	var big := _spawn(EnemyManager.TANK, 8.0, 0.0, 30.0)
	var other := _spawn(EnemyManager.GRUNT, 3.5, 0.5, 50.0)
	await _secs(0.05)
	_cast(0)
	await _secs(1.5)
	_check("Lasso: ropes the biggest one and swings it into the others", kit.active("lasso") and (em.hp[other] < em.hp_max[other] or em.dead[other] == 1), "")
	await _secs(2.0)
	_clear()
	var e := _spawn(EnemyManager.GRUNT, 9.0, 0.0, 50.0)
	await _secs(0.05)
	em.stun(e, 5.0)   # hold still where the sticks land
	_cast(1)
	await _secs(KitCowboy.DYN_FUSE + 0.3)
	_check("Dynamite: the sticks blow up", em.hp[e] < em.hp_max[e] or em.dead[e] == 1, "")
	_clear()
	var n := _spawn(EnemyManager.GRUNT, 10.0, 0.0, 50.0)
	await _secs(0.05)
	_cast(2)
	await _secs(0.3)
	_check("High Noon: everything freezes...", em.freeze_t[n] > 0.0, "")
	await _secs(KitCowboy.NOON_TIME)
	_check("...then he fires", em.hp[n] < em.hp_max[n] or em.dead[n] == 1, "")


func _platypus() -> void:
	var kit: KitPlatypus = await _load("platypus", "spur")
	_check("Venom Spur poisons", em.count > 0 and em.poison_n[0] > 0, "")
	_clear()
	var e := _spawn(EnemyManager.GRUNT, 8.0, 0.0, 50.0)
	await _secs(0.05)
	_cast(0)
	_check("Electro-Bill: damage and a stun", em.stun_t[e] > 0.0 and em.hp[e] < em.hp_max[e], "")
	_clear()
	var near_egg := _spawn(EnemyManager.GRUNT, 2.5, 0.0, 50.0)
	await _secs(0.05)
	_cast(1)
	_check("Egg Clutch: 4 eggs", kit._eggs.size() == 4, "%d" % kit._eggs.size())
	await _secs(KitPlatypus.EGG_HATCH + 0.3)
	_check("...that hatch and explode", em.hp[near_egg] < em.hp_max[near_egg] or em.dead[near_egg] == 1, "")
	_clear()
	var s := _spawn(EnemyManager.GRUNT, 12.0, 0.0, 50.0)
	await _secs(0.05)
	_cast(2)
	_check("The Lecture: everyone nearby falls asleep", em.stun_t[s] > 5.0, "%.1f" % em.stun_t[s])


func _witch() -> void:
	var kit: KitWitch = await _load("bog_witch", "bile")
	_clear()
	var e := _spawn(EnemyManager.GRUNT, 8.0, 0.0, 50.0)
	await _secs(0.05)
	_cast(0)
	await _secs(1.5)
	_check("Bubbling Cauldron: it spits at enemies", kit.active("cauldron") and em.hp[e] < em.hp_max[e], "")
	_clear()
	var h := _spawn(EnemyManager.GRUNT, 6.0, 0.0, 50.0)
	await _secs(0.05)
	_cast(1)
	var n1 := em.spawn(EnemyManager.GRUNT, em.pos[h] + Vector3(1.5, 0, 0), 50.0)   # arrives after the hex
	em.tick(0.0, player.global_position)
	_check("Hex of Silence: hexed (cursed)", em.curse_t[h] > 0.0 and em.curse_t[n1] <= 0.0, "")
	em.damage(h, em.hp[h] + 1.0)
	await _secs(0.1)
	_check("...and the hex passes on when one dies", em.curse_t[n1] > 0.0, "")
	_clear()
	var f := _spawn(EnemyManager.GRUNT, 6.0, 0.0, 50.0)
	await _secs(0.05)
	_cast(2)
	await _secs(1.2)
	_check("Swamp's Fury: the bog drags them under", em.dead[f] == 1, "")


func _kong() -> void:
	var kit: KitKong = await _load("kong", "chains")
	_clear()
	var e := _spawn(EnemyManager.TANK, 6.0, 0.0, 50.0)
	await _secs(0.05)
	_cast(0)
	await _secs(1.0)
	_check("Chest Pound: three shockwaves, the last stuns", em.stun_t[e] > 0.5 and em.hp[e] < em.hp_max[e], "")
	_clear()
	var l := _spawn(EnemyManager.GRUNT, 10.0, 0.0, 50.0)
	await _secs(0.05)
	_cast(1)
	await _secs(1.2)
	_check("Log Toss: the log flattens what's in its way", em.hp[l] < em.hp_max[l] or em.dead[l] == 1, "")
	var d0 := player.stats.value("damage")
	_cast(2)
	_check("Rampage: +80% damage", is_equal_approx(player.stats.value("damage"), d0 * 1.8) and kit.active("rampage"), "%.2f" % player.stats.value("damage"))


func _cast(i: int) -> void:
	ab.cooldown[i] = 0.0
	ab.level = 10
	if not ab.try_cast(i):
		_check("cast %d" % i, false, "try_cast failed")


func _clear() -> void:
	for i in em.count:
		em.dead[i] = 1
	em.count = 0
	em.set("_dead_count", 0)
	ws.orb_t = 999.0
	main.xp_next = 1.0e12
	main.set("_spawn_budget", -1.0e9)


func _spawn(t: int, dist: float, ang: float, hpm: float) -> int:
	var fwd := Vector3(-sin(player.cam_yaw), 0, -cos(player.cam_yaw))
	var right := Vector3(cos(player.cam_yaw), 0, -sin(player.cam_yaw))
	var p := player.global_position + (fwd * cos(ang) + right * sin(ang)) * dist
	var i := em.spawn(t, p, hpm)
	em.vel[i] = Vector3.ZERO
	em.tick(0.0, player.global_position)
	return i


func _secs(s: float) -> void:
	for f in int(s * 60):
		await get_tree().physics_frame


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		fails += 1
