extends Node3D
## Run orchestration: builds the world, owns run state (time, XP, level), drives the
## spawn director, and ticks the simulation systems in a fixed order each physics frame:
##   spawn -> enemies (move + grid) -> weapons (use grid) -> items -> gems -> contact damage
##
## Headless smoke test:
##   godot --headless --path . --fixed-fps 60 -- --smoketest --smoke-seconds=240

const ARENA_HALF := 110.0
const RUN_LENGTH := 600.0
const BOSS_TIME := 300.0
const MAX_WEAPONS := 3
const SWAMP_MUSIC := "res://audio/music/tension_drop.mp3"   # loops for the whole swamp run
const MUSIC_VOLUME_DB := -6.0
const EPIC_BASE_CHANCE := 0.05
const EPIC_CHANCE_PER_LUCK := 0.01     # per Tome of Luck level
const CONTACT_ENEMY_KNOCK := 2.5       # metres an enemy is shoved on collision

const BASE_STATS := {
	"max_hp": 100.0, "regen": 0.0, "armor": 0.0, "move_speed": 8.0,
	"damage": 1.0, "attack_speed": 1.0, "area": 1.0, "projectile_speed": 1.0,
	"projectile_count": 0.0, "pickup_range": 4.0, "xp_gain": 1.0, "luck": 0.0, "extra_jumps": 0.0,
	"orb_damage": 12.0, "orb_cooldown": 0.9, "orb_count": 1.0, "orb_pierce": 0.0, "orb_speed": 24.0,
	"aura_damage": 5.0, "aura_radius": 3.2, "aura_tick": 0.45,
	"slam_damage": 18.0, "slam_radius": 5.5, "slam_cooldown": 2.6,
	"bomb_chance": 0.0, "bomb_damage": 25.0, "fang_chance": 0.0,
}

static var smoke_restarts := 0

var rng := RandomNumberGenerator.new()
var stats: Stats
var db: UpgradeDB
var player: Player
var enemies: EnemyManager
var weapons: WeaponSystem
var gems: GemManager
var items: ItemEffects
var hud: Hud
var water: SwampWater
var numbers: DamageNumbers
var corpses: CorpseManager
var music: AudioStreamPlayer
var fx: FxManager
var abilities: Abilities
var potions: PotionManager
var powerups: PowerupManager
var goblin_audio: GoblinAudio

var state := "playing"   # playing | paused | levelup | dead | won
var run_time := 0.0
var level := 1
var xp := 0.0
var xp_next := 0.0
var kills := 0
var pending_levels := 0
var current_draft: Array = []
var _spawn_budget := 0.0
var _boss_spawned := false
var _next_swarm := 60.0

var perf := {"enemies": 0.0, "weapons": 0.0, "gems": 0.0}

# Smoke test
var smoke := false
var smoke_seconds := 240.0
var _smoke_acc := {"enemies": 0.0, "weapons": 0.0, "gems": 0.0, "frames": 0}
var _smoke_log_t := 0.0
var _smoke_phase := 0
var _smoke_phase_t := 0.0
var _smoke_wall_start := 0
var _smoke_casts := [0, 0, 0]
var _smoke_contacts := 0
var _smoke_immune_knocks := 0
var _smoke_epics := 0

# Screenshot mode (for checking visuals): -- --shot=/path/out.png --shot-at=6 --shot-cast=0@2,1@5
var shot_path := ""
var shot_at := 5.0
var shot_casts := {}   # time -> ability index
var _shot_spawn := 0
var _shot_front := false
var _shot_pool := false
var _shot_potions := false
var _shot_powerups := false
var _shot_ignite := false
var _shot_zoom := 0.0
var _shot_turn := 0.0
var _shot_level := 0
var _shot_inspect := -1
var _shot_settings_tab := -1
var _forced_seed := -1
var _shot_pitch := -99.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_inputs()
	Settings.apply_bindings()

	var args := OS.get_cmdline_user_args()
	smoke = args.has("--smoketest")
	for a in args:
		if a.begins_with("--smoke-seconds="):
			smoke_seconds = float(a.split("=")[1])
	for a in args:
		if a.begins_with("--shot="):
			shot_path = a.split("=")[1]
		elif a.begins_with("--shot-at="):
			shot_at = float(a.split("=")[1])
		elif a.begins_with("--shot-cast="):
			for c in a.split("=")[1].split(","):
				var parts := c.split("@")
				shot_casts[float(parts[1])] = int(parts[0])
		elif a.begins_with("--shot-spawn="):
			_shot_spawn = int(a.split("=")[1])
		elif a.begins_with("--seed="):
			_forced_seed = int(a.split("=")[1])
		elif a.begins_with("--shot-settings="):
			_shot_settings_tab = int(a.split("=")[1])
		elif a.begins_with("--shot-inspect="):
			_shot_inspect = int(a.split("=")[1])
		elif a.begins_with("--shot-level="):
			_shot_level = int(a.split("=")[1])
		elif a.begins_with("--shot-zoom="):
			_shot_zoom = float(a.split("=")[1])
		elif a.begins_with("--shot-turn="):
			_shot_turn = deg_to_rad(float(a.split("=")[1]))
		elif a == "--shot-ignite":
			_shot_ignite = true
		elif a.begins_with("--shot-timescale="):
			Engine.time_scale = float(a.split("=")[1])
		elif a == "--shot-powerups":
			_shot_powerups = true
		elif a == "--shot-potions":
			_shot_potions = true
		elif a == "--shot-pool":
			_shot_pool = true
		elif a == "--shot-front":
			_shot_front = true
		elif a.begins_with("--shot-pitch="):
			_shot_pitch = float(a.split("=")[1])
	if smoke:
		rng.seed = 1337
		_smoke_wall_start = Time.get_ticks_msec()
	else:
		rng.randomize()
	if _forced_seed >= 0:
		rng.seed = _forced_seed

	stats = Stats.new()
	for k in BASE_STATS:
		stats.define(k, BASE_STATS[k])
	db = UpgradeDB.new("res://data/upgrades.json", rng)

	water = WorldBuilder.build(self, rng, ARENA_HALF)

	fx = FxManager.new()
	add_child(fx)

	player = Player.new()
	player.fx = fx
	player.water = water
	player.stats = stats
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.global_position = Vector3(0, 0.5, 0)
	player.died.connect(_on_player_died)

	enemies = EnemyManager.new()
	enemies.arena_half = ARENA_HALF
	enemies.rng = rng
	enemies.water = water
	add_child(enemies)
	numbers = DamageNumbers.new()
	add_child(numbers)
	enemies.numbers = numbers
	corpses = CorpseManager.new()
	add_child(corpses)
	enemies.corpses = corpses

	gems = GemManager.new()
	add_child(gems)

	weapons = WeaponSystem.new()
	weapons.setup(stats, db, enemies, player)
	add_child(weapons)

	abilities = Abilities.new()
	abilities.setup(stats, enemies, player, fx)
	add_child(abilities)
	goblin_audio = GoblinAudio.new()
	goblin_audio.setup(enemies, player, rng)
	add_child(goblin_audio)

	potions = PotionManager.new()
	potions.setup(player, abilities, rng)
	add_child(potions)
	potions.collected.connect(func(k: int): hud.flash_message(PotionManager.NAMES[k], 1.5))
	enemies.epic_killed.connect(func(p: Vector3): potions.drop(p))
	powerups = PowerupManager.new()
	powerups.setup(player, stats, enemies, gems, db, rng)
	add_child(powerups)
	powerups.collected.connect(func(k: int): hud.flash_message(PowerupManager.PICKUP_TEXT[k], 2.5))
	enemies.epic_killed.connect(func(p: Vector3): powerups.on_elite_killed(p))

	enemies.exploded.connect(func(p: Vector3, r: float): fx.burst(p, r * 1.4, Color(1.0, 0.4, 0.08), 0.35))

	items = ItemEffects.new()
	items.setup(stats, enemies, player, rng)
	add_child(items)

	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	# Main runs while paused (menus, input); all gameplay nodes freeze with the pause.
	for n in [fx, enemies, numbers, corpses, powerups, gems, weapons, abilities, potions, goblin_audio, items]:
		(n as Node).process_mode = Node.PROCESS_MODE_PAUSABLE

	Events.enemy_killed.connect(_on_enemy_killed)
	db.apply({"id": "weapon_orb", "rarity": 0}, stats)   # starting weapon
	xp_next = _xp_for(level)

	_start_music()
	if smoke:
		player.bot = true
		player.god_mode = true
		print("SMOKE start (restart #%d)" % smoke_restarts)
		var ms: AudioStream = music.stream if music else null
		print("SMOKE music %s loop=%s playing=%s" % [ms.resource_path if ms else "none", str(ms.get("loop")) if ms else "-", str(music.playing) if music else "-"])
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.flash_message("Survive 10 minutes. A Big Bonker arrives at 5:00.", 4.0)


func _exit_tree() -> void:
	if Events.enemy_killed.is_connected(_on_enemy_killed):
		Events.enemy_killed.disconnect(_on_enemy_killed)


# ------------------------------------------------------------------ main loop

## Hold Alt: freeze the game and free the cursor to inspect abilities; release to resume.
func _process(_dt: float) -> void:
	if _shot_inspect >= 0:
		return   # screenshot mode holds inspect open without a real key press
	var held := Input.is_action_pressed("inspect")
	if held and state == "playing":
		state = "inspect"
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.set_inspect(true)
	elif not held and state == "inspect":
		hud.set_inspect(false)
		_resume()


func _physics_process(dt: float) -> void:
	if smoke:
		_smoke_tick(dt)
	if shot_path != "":
		_shot_tick()
	if state != "playing":
		return
	run_time += dt
	_spawn_director(dt)

	var t0 := Time.get_ticks_usec()
	enemies.tick(dt, player.global_position)
	var t1 := Time.get_ticks_usec()
	weapons.tick(dt)
	abilities.tick(dt)
	items.tick(dt)
	var t2 := Time.get_ticks_usec()
	var gained := gems.tick(dt, player.global_position + Vector3(0, 0.9, 0), stats.value("pickup_range"))
	potions.tick(dt, stats.value("pickup_range"))
	powerups.tick(dt, stats.value("pickup_range"))
	goblin_audio.tick(dt)
	var t3 := Time.get_ticks_usec()
	_track_perf((t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0)

	_contact_damage()
	if gained > 0.0:
		_add_xp(gained * stats.value("xp_gain"))
	if run_time >= RUN_LENGTH and state == "playing":
		_end_run(true)


func _track_perf(e: float, w: float, g: float) -> void:
	var k := 0.05
	perf["enemies"] = lerpf(perf["enemies"], e, k)
	perf["weapons"] = lerpf(perf["weapons"], w, k)
	perf["gems"] = lerpf(perf["gems"], g, k)
	_smoke_acc["enemies"] += e
	_smoke_acc["weapons"] += w
	_smoke_acc["gems"] += g
	_smoke_acc["frames"] += 1


## Enemy collisions. The first contact damages the player, starts 0.5 s of immunity and
## knocks the player and the enemies apart. While immune, any enemy that runs into the player
## is knocked back opposite to the direction it was heading.
func _contact_damage() -> void:
	if player.meteor_form:
		return   # untouchable while falling as the meteor
	var me := player.global_position
	var hits := enemies.query_radius(me + Vector3(0, 0.9, 0), 0.45)
	if hits.is_empty():
		return
	if player.invuln <= 0.0:
		var dmg := 0.0
		var push := Vector3.ZERO
		for i in hits:
			dmg = maxf(dmg, enemies.t_damage[enemies.typ[i]])
			var away := enemies.pos[i] - me
			away.y = 0.0
			push -= away.normalized() if away.length_squared() > 0.0001 else Vector3.ZERO
		player.hurt(dmg)
		goblin_audio.play_collision()
		_smoke_contacts += 1
		if push.length_squared() < 0.0001:
			push = -player.velocity
		player.knockback(push)
		for i in hits:
			enemies.knock(i, enemies.pos[i] - me, CONTACT_ENEMY_KNOCK, 0.2)
	else:
		for i in hits:
			if enemies.kb_t[i] > 0.0:
				continue   # already being knocked back
			var back := -enemies.heading(i)
			if back.length_squared() < 0.01:
				back = enemies.pos[i] - me
			enemies.knock(i, back, CONTACT_ENEMY_KNOCK, 0.2)
			goblin_audio.play_collision()
			_smoke_immune_knocks += 1


func epic_chance() -> float:
	return EPIC_BASE_CHANCE + EPIC_CHANCE_PER_LUCK * db.level_of("tome_luck")


func _spawn_enemy(t: int, p: Vector3, hpm: float) -> int:
	var is_epic := rng.randf() < epic_chance()
	if is_epic:
		_smoke_epics += 1
	return enemies.spawn(t, p, hpm, is_epic)


# ------------------------------------------------------------------ spawning

func hp_mult() -> float:
	var m := run_time / 60.0
	return 1.0 + m * 0.35 + m * m * 0.04


func _spawn_director(dt: float) -> void:
	var m := run_time / 60.0
	_spawn_budget += (1.6 + m * 2.2 + m * m * 0.5) * dt
	var hpm := hp_mult()
	while _spawn_budget >= 1.0:
		_spawn_budget -= 1.0
		if enemies.count >= EnemyManager.MAX - 60:
			_spawn_budget = 0.0
			break
		_spawn_enemy(_pick_type(m), _spawn_point(26.0, 36.0), hpm)

	# Swarm ring every minute
	if run_time >= _next_swarm:
		_next_swarm += 60.0
		var n := 24 + int(m) * 6
		for k in n:
			var a := TAU * float(k) / float(n)
			var p := player.global_position + Vector3(cos(a), 0, sin(a)) * 22.0
			_spawn_enemy(EnemyManager.RUNNER, p, hpm)
		hud.flash_message("SWARM!", 2.0)

	if not _boss_spawned and run_time >= BOSS_TIME:
		_boss_spawned = true
		enemies.spawn(EnemyManager.BOSS, _spawn_point(30.0, 32.0), hpm)
		hud.flash_message("A BIG BONKER APPROACHES", 4.0)


func _pick_type(m: float) -> int:
	var w_grunt := 10.0
	var w_runner := 4.0 * minf(m, 3.0) if m >= 1.0 else 0.0
	var w_tank := 1.5 * (m - 1.0) if m >= 2.0 else 0.0
	var r := rng.randf() * (w_grunt + w_runner + w_tank)
	if r < w_grunt:
		return EnemyManager.GRUNT
	if r < w_grunt + w_runner:
		return EnemyManager.RUNNER
	return EnemyManager.TANK


func _spawn_point(min_d: float, max_d: float) -> Vector3:
	var a := rng.randf() * TAU
	var p := player.global_position + Vector3(cos(a), 0, sin(a)) * rng.randf_range(min_d, max_d)
	return Vector3(clampf(p.x, -ARENA_HALF + 2, ARENA_HALF - 2), 0, clampf(p.z, -ARENA_HALF + 2, ARENA_HALF - 2))


func _on_enemy_killed(p: Vector3, type_id: int) -> void:
	kills += 1
	gems.spawn(p + Vector3(0, 0.5, 0), enemies.t_xp[type_id])
	if type_id == EnemyManager.BOSS:
		gems.magnetise_all()
		hud.flash_message("BIG BONKER BONKED!", 4.0)


# ------------------------------------------------------------------ progression

func _xp_for(lv: int) -> float:
	return roundf(4.0 + pow(float(lv), 1.55) * 4.0)


func _add_xp(v: float) -> void:
	xp += v
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = _xp_for(level)
		pending_levels += 1
		Events.level_up.emit(level)
		abilities.level = level
		for k in Abilities.DEFS.size():
			var d: Dictionary = Abilities.DEFS[k]
			if int(d["unlock_level"]) == level:
				hud.flash_message("NEW ABILITY UNLOCKED: %s  [%s]" % [d["name"].to_upper(), d["key"]], 4.0)
	if pending_levels > 0 and state == "playing":
		_open_draft()


func _open_draft() -> void:
	current_draft = db.draft(3, stats.value("luck"), MAX_WEAPONS)
	if current_draft.is_empty():   # everything maxed: just heal
		pending_levels = 0
		player.heal(player.max_hp)
		return
	state = "levelup"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_draft(current_draft)
	if smoke:
		choose_upgrade.call_deferred(rng.randi() % current_draft.size())


func choose_upgrade(i: int) -> void:
	if state != "levelup" or i < 0 or i >= current_draft.size():
		return
	db.apply(current_draft[i], stats)
	pending_levels -= 1
	if pending_levels > 0:
		state = "playing"
		_open_draft()
		return
	hud.hide_draft()
	_resume()


func cast_ability(i: int) -> void:
	if state != "playing":
		return
	if abilities.try_cast(i):
		if i == Abilities.INFERNO:
			hud.flash_message("INFERNO!", 2.0)
		elif i == Abilities.METEOR:
			hud.flash_message("METEOR!", 2.0)


func resume_from_pause() -> void:
	if state == "paused":
		_resume()


func _resume() -> void:
	state = "playing"
	get_tree().paused = false
	hud.set_paused(false)
	if not smoke:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_player_died() -> void:
	_end_run(false)


## Swamp music: starts with the level and repeats until the map ends.
## Keeps playing through pause and level-up menus.
func _start_music() -> void:
	music = AudioStreamPlayer.new()
	music.bus = Settings.MUSIC_BUS
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	music.volume_db = MUSIC_VOLUME_DB
	add_child(music)
	if not ResourceLoader.exists(SWAMP_MUSIC):
		return
	var stream: AudioStream = load(SWAMP_MUSIC)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	music.stream = stream
	music.play()


func _stop_music() -> void:
	if music == null or not music.playing:
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(music, "volume_db", -40.0, 1.5)
	tw.tween_callback(music.stop)


func _end_run(won: bool) -> void:
	_stop_music()
	state = "won" if won else "dead"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_end(won)


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and hud.settings_open():
		hud.settings_menu.handle_escape()
	elif event.is_action_pressed("pause"):
		if state == "playing" or state == "inspect":
			hud.set_inspect(false)
			state = "paused"
			get_tree().paused = true
			hud.set_paused(true)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif state == "paused":
			_resume()
	elif (state == "dead" or state == "won") and event.is_action_pressed("restart"):
		restart()
	elif state == "playing":
		if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.is_action_pressed("ability_1"):
			cast_ability(0)
		elif event.is_action_pressed("ability_2"):
			cast_ability(1)
		elif event.is_action_pressed("ability_3"):
			cast_ability(2)
		elif event.is_action_pressed("debug_cooldowns"):
			abilities.reset_cooldowns()
			hud.flash_message("Cooldowns reset", 1.0)
		elif event.is_action_pressed("debug_stats"):
			hud.toggle_debug()
		elif event.is_action_pressed("debug_spawn"):
			for k in 200:
				_spawn_enemy(EnemyManager.GRUNT, _spawn_point(15.0, 40.0), hp_mult())


static func setup_inputs() -> void:
	_bind("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_bind("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_bind("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_bind("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_bind("jump", [KEY_SPACE], [JOY_BUTTON_A], [])
	_bind("slide", [KEY_SHIFT, KEY_CTRL, KEY_C], [JOY_BUTTON_B, JOY_BUTTON_LEFT_SHOULDER], [])
	_bind("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])
	_bind("ability_1", [KEY_1], [JOY_BUTTON_X], [])
	_bind("ability_2", [KEY_2], [JOY_BUTTON_Y], [])
	_bind("ability_3", [KEY_3], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_bind("restart", [KEY_R], [JOY_BUTTON_BACK], [])
	_bind("debug_stats", [KEY_F1], [], [])
	_bind("debug_spawn", [KEY_F2], [], [])
	_bind("debug_cooldowns", [KEY_F3], [], [])
	_bind("inspect", [KEY_ALT], [], [])


static func _bind(action: String, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = b
		InputMap.action_add_event(action, ev)
	for a in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = a[0]
		ev.axis_value = a[1]
		InputMap.action_add_event(action, ev)


# ------------------------------------------------------------------ smoke test

func _smoke_tick(dt: float) -> void:
	if Time.get_ticks_msec() - _smoke_wall_start > 600000:
		print("SMOKE FAIL: wall-clock timeout")
		get_tree().quit(1)
		return

	if smoke_restarts > 0:
		# Second instance after reload: verify the fresh run simulates, then exit.
		if run_time > 3.0:
			print("SMOKE restart OK: run_time=%.1f enemies=%d" % [run_time, enemies.alive_count()])
			print("SMOKE PASS")
			get_tree().quit(0)
		_drive_bot(dt)
		return

	match _smoke_phase:
		0:  # normal play with the bot
			_drive_bot(dt)
			_smoke_log_t += dt
			if _smoke_log_t >= 20.0:
				_smoke_log_t = 0.0
				_smoke_report("t=%5.1f" % run_time)
			if run_time >= smoke_seconds:
				_smoke_phase = 1
				_smoke_phase_t = 0.0
				var added := 0
				while enemies.count < 1400:
					enemies.spawn(EnemyManager.GRUNT, _spawn_point(8.0, 50.0), hp_mult() * 50.0)
					added += 1
				print("SMOKE stress: added %d enemies, total %d" % [added, enemies.count])
				abilities.reset_cooldowns()
				cast_ability(Abilities.INFERNO)
				print("SMOKE inferno: burning %d" % enemies.burning_count())
				_reset_acc()
		1:  # stress at ~1400 enemies
			_drive_bot(dt)
			_smoke_phase_t += dt
			if absf(_smoke_phase_t - 5.0) < 0.5 * dt:
				print("SMOKE inferno +5s: burning %d alive %d kills %d" % [enemies.burning_count(), enemies.alive_count(), kills])
			if _smoke_phase_t >= 11.0:
				print("SMOKE inferno done: burning %d alive %d kills %d" % [enemies.burning_count(), enemies.alive_count(), kills])
				_smoke_report("STRESS")
				_smoke_phase = 2
				player.god_mode = false
				player.invuln = 0.0
				player.hurt(1.0e9)
		2:
			if state == "dead" and hud.end_root.visible:
				print("SMOKE death -> game over screen OK (level %d, kills %d)" % [level, kills])
				_smoke_phase = 3
				_smoke_restart_after_music()
			else:
				_smoke_phase_t += dt
				if _smoke_phase_t > 12.0:
					print("SMOKE FAIL: player did not die / no end screen (state=%s)" % state)
					get_tree().quit(1)


func _shot_tick() -> void:
	player.god_mode = true
	player.face_offset = _shot_turn
	if _shot_zoom > 0.0:
		player.spring.spring_length = _shot_zoom
	if _shot_ignite and run_time < 0.05:
		# Stand 11 m from the nearest standing tree, look at it, and set it on fire
		var best: Node3D = null
		for t in get_tree().get_nodes_in_group(TreeFire.GROUP):
			var tb := t as Node3D
			if float(tb.get_meta("reach")) < 2.0 and (best == null or tb.global_position.length() < best.global_position.length()):
				best = tb
		var tp := best.global_position
		var away := Vector3(tp.x, 0, tp.z).normalized()
		player.global_position = tp - away * 11.0 + Vector3(0, 0.5, 0)
		var to := tp - player.global_position
		player.cam_yaw = atan2(-to.x, -to.z)
		TreeFire.ignite(best)
	if _shot_powerups and run_time < 0.05:
		var f2 := Vector3(-sin(player.cam_yaw), 0, -cos(player.cam_yaw))
		var r2 := Vector3(cos(player.cam_yaw), 0, -sin(player.cam_yaw))
		for k in 4:
			powerups.drop(player.global_position + f2 * 6.0 + r2 * (k - 1.5) * 1.9, k)
	if _shot_potions and run_time < 0.05:
		var fwd := Vector3(-sin(player.cam_yaw), 0, -cos(player.cam_yaw))
		var right := Vector3(cos(player.cam_yaw), 0, -sin(player.cam_yaw))
		for k in 3:
			potions.drop(player.global_position + fwd * 6.5 + right * (k - 1) * 1.8, k)
	if _shot_level > 0:
		abilities.level = _shot_level
	if _shot_pool and run_time < 0.05:
		var c: Vector2 = water.pools[0]["center"]
		var r: float = water.pools[0]["r"]
		player.global_position = Vector3(c.x + r + 6.0, 0.5, c.y + 1.0)
		player.cam_yaw = atan2(-(c.x - player.global_position.x), -(c.y - player.global_position.z)) * -1.0
		var to := Vector3(c.x, 0, c.y) - player.global_position
		player.cam_yaw = atan2(-to.x, -to.z)
	player.face_camera = _shot_front
	if _shot_pitch > -90.0:
		player.cam_pitch = _shot_pitch
	if _shot_spawn > 0:
		for k in _shot_spawn:
			var t := EnemyManager.TANK if k % 9 == 0 else (EnemyManager.RUNNER if k % 3 == 0 else EnemyManager.GRUNT)
			_spawn_enemy(t, _spawn_point(14.0, 30.0), 3.0)
		_shot_spawn = 0
	for t in shot_casts.keys():
		if run_time >= t:
			abilities.reset_cooldowns()
			cast_ability(shot_casts[t])
			shot_casts.erase(t)
	if run_time >= shot_at:
		if _shot_inspect >= 0:
			state = "inspect"
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			hud.set_inspect(true)
			hud._on_slot_hover(_shot_inspect, true)
			hud._update_tooltip()
		if _shot_settings_tab >= 0:
			state = "paused"
			get_tree().paused = true
			hud.set_paused(true)
			hud.open_settings()
			hud.settings_menu._tabs.current_tab = _shot_settings_tab
		shot_path_save.call_deferred()
		set_physics_process(false)


func shot_path_save() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_path)
	print("SHOT saved ", shot_path)
	get_tree().quit()


func _smoke_restart_after_music() -> void:
	await get_tree().create_timer(1.7, true).timeout
	print("SMOKE music after run end: playing=%s" % str(music.playing))
	smoke_restarts += 1
	restart()


func _drive_bot(_dt: float) -> void:
	if state != "playing":
		return
	player.cam_yaw += 0.9 / 60.0
	player.bot_move = Vector2(0.35, -1.0)
	player.bot_jump = fmod(run_time, 1.1) < 1.0 / 60.0
	player.bot_slide = fmod(run_time, 5.0) > 4.0
	for k in 3:
		if abilities.is_ready(k) and run_time > 5.0:
			cast_ability(k)
			_smoke_casts[k] += 1


func _smoke_report(tag: String) -> void:
	var f: float = maxf(1.0, _smoke_acc["frames"])
	print("SMOKE casts meteor/shock/inferno %s | contacts %d immune-knocks %d | epics spawned %d potions on map %d shield %.0f" % [
		str(_smoke_casts), _smoke_contacts, _smoke_immune_knocks, _smoke_epics, potions.count(), player.shield])
	print("SMOKE %s | lv %2d kills %5d enemies %4d proj %3d gems %3d | hp %.0f/%.0f speed %.1f | ms/frame enemies %.2f weapons %.2f gems %.2f | weapons %s" % [
		tag, level, kills, enemies.alive_count(), weapons.pc, gems.count, player.hp, player.max_hp,
		player.horizontal_speed(),
		_smoke_acc["enemies"] / f, _smoke_acc["weapons"] / f, _smoke_acc["gems"] / f,
		str(db.levels)])
	_reset_acc()


func _reset_acc() -> void:
	_smoke_acc = {"enemies": 0.0, "weapons": 0.0, "gems": 0.0, "frames": 0}
