extends Node3D
## Run orchestration: builds the world, owns run state (time, XP, level), drives the
## spawn director, and ticks the simulation systems in a fixed order each physics frame:
##   spawn -> enemies (move + grid) -> weapons (use grid) -> items -> gems -> contact damage
##
## Headless smoke test:
##   godot --headless --path . --fixed-fps 60 -- --smoketest --smoke-seconds=240

const ARENA_HALF := 220.0   # 440 m across
const RUN_LENGTH := 600.0
const BOSS_TIME := 300.0
const THOG_TIME := RUN_LENGTH - 120.0   # the Swamp's boss arrives with 2 minutes left
const MAX_WEAPONS := 3
const SWAMP_MUSIC := "res://audio/music/tension_drop.mp3"   # loops for the whole swamp run
const MAP_MUSIC := {"forest": "res://audio/music/bosna_grit.mp3", "castle": "res://audio/music/castle_map.mp3"}   # per-map tracks (others use SWAMP_MUSIC)
const MUSIC_VOLUME_DB := -6.0
const EPIC_BASE_CHANCE := 0.05
const EPIC_CHANCE_PER_LUCK := 0.1      # per point of the Luck stat (a Tome of Luck level = 0.1 luck = +1%)
const CONTACT_ENEMY_KNOCK := 2.5       # metres an enemy is shoved on collision

const BASE_STATS := {
	"max_hp": 100.0, "regen": 0.0, "armor": 0.0, "move_speed": 8.0,
	"damage": 1.0, "attack_speed": 1.0, "area": 1.0, "projectile_speed": 1.0,
	"projectile_count": 0.0, "pickup_range": 4.0, "xp_gain": 1.0, "luck": 0.0, "extra_jumps": 0.0,
	"orb_damage": 12.0, "orb_cooldown": 0.9, "orb_count": 1.0, "orb_pierce": 0.0, "orb_speed": 24.0,
	"aura_damage": 5.0, "aura_radius": 3.2, "aura_tick": 0.45,
	"thorns_return": 2.0, "frost_radius": 5.5, "frost_slow": 0.6,
	"slam_damage": 18.0, "slam_radius": 5.5, "slam_cooldown": 2.6,
	"bomb_chance": 0.0, "bomb_damage": 25.0, "fang_chance": 0.0,
	"coin_gain": 1.0, "ability_cdr": 1.0, "start_shield": 0.0,   # from character skills
}

static var smoke_restarts := 0
var skills_applied: Array = []   # skill ids active this run

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
var chests: ChestManager
var keys: KeyManager
var goblin_audio: GoblinAudio

var state := "playing"   # playing | paused | levelup | dead | won
var run_time := 0.0
var level := 1
var xp := 0.0
var xp_next := 0.0
var kills := 0
var elites_killed := 0              # for character EXP
var chests_opened := 0
var shards_won := {}   # elemental shards from bosses this run (banked as they drop)
var _chest_queue: Array[int] = []   # tiers of chests opened while a menu was up
var pending_levels := 0
var current_draft: Array = []
var _spawn_budget := 0.0
var _boss_spawned := false
var thog: ThogBoss                 # the Swamp boss once he's arrived
var boss_map := false              # this map has a boss you must kill to win
## Each map's boss (also the Wallet.bosses_defeated id, and the character it unlocks)
const MAP_BOSS := {"swamp": "thog", "forest": "toadstool_knight", "castle": "arachnid"}
var boss_id := ""                  # this run's boss
var boss_name := "THOG"            # for "%s DEFEATED!"
var map_boss: MapBoss              # the Forest's / Castle's boss once it has arrived
var boss_won := false              # the run was won by killing the boss
## Unrelenting mode: no time limit (the clock counts up), spawns never stop, upgrades have no
## level cap, and past 10:00 enemies hit harder and drop less XP the longer you last.
var endless := false
const ENDLESS_FROM := RUN_LENGTH              # the extra ramp starts where a normal run ends
const ENDLESS_DMG_PER_MIN := 0.12             # +12% enemy contact damage per minute past 10:00
const ENDLESS_XP_PER_MIN := 0.06              # XP drops shrink: 1 / (1 + 0.06 per minute past 10:00)
const GHAST_FEAT := "unrelenting_swamp_15"
const GHAST_FEAT_TIME := 900.0                # 15:00 in the Swamp on Unrelenting
var first_boss_kill := false       # ...for the first time (unlocks shown on the end screen)
var _thog_at := THOG_TIME
var _shot_thog := false
var _thog_enraged := false
var _shot_boss_win := -1.0
var _shot_boss_wait := 3.0
var _smoke_wall_ms := 600000
var _shot_thog_dist := 9.0
var _shot_thog_side := 0.0
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
var _shot_chest := -1      # --shot-chest=tier: a chest of that tier in front of you
var _shot_slot := -1       # --shot-slot=tier[:pull_after_s[:levels a,b,c]]: the slot machine
var _shot_slot_pull := -1.0
var _shot_slot_levels := PackedInt32Array()
var _shot_ignite := false
var _shot_zoom := 0.0
var _shot_turn := 0.0
var _shot_level := 0
var _shot_epic := false
var _shot_ban := -1   # --shot-ban=i: ban reward card i in the --shot-draft screenshot
var _shot_give := []   # --shot-give=id:levels,...  owned upgrades for screenshots
var _shot_intro := false   # --shot-intro: screenshot runs play the entrance too
var intro := false         # true while the entrance meteor is falling (first 3 s)
var _shot_draft: Array = []
var _frames_dir := ""      # --frames=DIR:START:COUNT  debug: dump COUNT frames from START s (game keeps running)
var _frames_start := 0.0
var _frames_left := 0
var _frames_n := 0   # --shot-draft=id[:rarity],... : show these level-up cards
var _shot_inspect := -1
var _shot_inv: Array = []   # --shot-inv=id,id: own these upgrades and hover the first (with --shot-inspect)
var _shot_keys := PackedInt32Array()   # --shot-keys=b,s,g
var _shot_castle := false   # --shot-castle: look toward the castle on the horizon
var _shot_settings_tab := -1
var _forced_seed := -1
var _shot_pitch := -99.0
var _shot_nohud := false
var _shot_pos := Vector3.INF
var _shot_yaw := 0.0
var castle_doors: CastleDoors   # the castle's front doors (null outdoors)
var _walk_in := false
var _shot_slow := -1.0   # --shot-slow=T: crawl (time scale 0.02) from T, to catch short effects


func _ready() -> void:
	Wallet.set_shown(true)
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_inputs()
	Settings.apply_bindings()

	var args := OS.get_cmdline_user_args()
	smoke = args.has("--smoketest")
	if Wallet.persist and not smoke and Settings.last_played != Settings.selected_character:
		Settings.last_played = Settings.selected_character   # the title screen shows them next time
		Settings.save_settings()
	for a in args:
		if a.begins_with("--smoke-seconds="):
			smoke_seconds = float(a.split("=")[1])
	for a in args:
		if a.begins_with("--char="):   # play as this character (tests, screenshots)
			Settings.selected_character = a.split("=")[1]
		elif a.begins_with("--map="):   # play on this map (tests, screenshots)
			Settings.selected_map = a.split("=")[1]
		elif a.begins_with("--forest-time="):   # noon / golden / night (screenshots)
			ForestBuilder.force_time = a.split("=")[1]
		elif a.begins_with("--thog-at=") or a.begins_with("--boss-at="):   # bring the map's boss early (tests, screenshots)
			_thog_at = float(a.split("=")[1])
		elif a.begins_with("--smoke-wall="):   # wall-clock limit for long smoke runs (seconds)
			_smoke_wall_ms = int(a.split("=")[1]) * 1000
		elif a.begins_with("--shot-boss-win="):   # --shot-boss-win=T[,wait]: win by killing Thog (first time) at T, shoot `wait` s later
			var v := a.split("=")[1].split(",")
			_shot_boss_win = float(v[0])
			_shot_boss_wait = float(v[1]) if v.size() > 1 else 3.0
		elif a == "--thog-enraged":   # Thog arrives already enraged (screenshots)
			_thog_enraged = true
		elif a.begins_with("--shot-thog"):   # --shot-thog[=distance[,side angle in degrees]]
			_shot_thog = true
			var v := a.split("=")[1].split(",") if a.contains("=") else PackedStringArray()
			_shot_thog_dist = float(v[0]) if v.size() > 0 else 9.0
			_shot_thog_side = deg_to_rad(float(v[1])) if v.size() > 1 else 0.0
		elif a.begins_with("--shot="):
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
		elif a.begins_with("--shot-give="):
			for c in a.split("=")[1].split(","):
				var parts := c.split(":")
				_shot_give.append([parts[0], int(parts[1]) if parts.size() > 1 else 1])
		elif a.begins_with("--shot-ban="):
			_shot_ban = int(a.split("=")[1])
		elif a == "--shot-intro":
			_shot_intro = true
		elif a == "--shot-epic":
			_shot_epic = true
		elif a.begins_with("--frames="):
			var fp := a.split("=")[1].split(":")
			_frames_dir = fp[0]
			_frames_start = float(fp[1])
			_frames_left = int(fp[2])
			RenderingServer.frame_post_draw.connect(_dump_frame)
		elif a.begins_with("--shot-draft="):
			for c in a.split("=")[1].split(","):
				var parts := c.split(":")
				_shot_draft.append({"id": parts[0], "rarity": int(parts[1]) if parts.size() > 1 else 0})
		elif a.begins_with("--shot-level="):
			_shot_level = int(a.split("=")[1])
		elif a.begins_with("--shot-zoom="):
			_shot_zoom = float(a.split("=")[1])
			if _shot_zoom == 0.0:
				_shot_zoom = 0.001   # first person
		elif a.begins_with("--shot-turn="):
			_shot_turn = deg_to_rad(float(a.split("=")[1]))
		elif a == "--shot-ignite":
			_shot_ignite = true
		elif a.begins_with("--shot-timescale="):
			Engine.time_scale = float(a.split("=")[1])
		elif a == "--shot-castle":
			_shot_castle = true
		elif a.begins_with("--shot-inv="):
			_shot_inv = Array(a.split("=")[1].split(","))
		elif a.begins_with("--shot-keys="):
			for v in a.split("=")[1].split(","):
				_shot_keys.append(int(v))
		elif a.begins_with("--shot-chest="):
			_shot_chest = int(a.split("=")[1])
		elif a.begins_with("--shot-slot="):
			var sp := a.split("=")[1].split(":")
			_shot_slot = int(sp[0])
			if sp.size() > 1:
				_shot_slot_pull = float(sp[1])
			if sp.size() > 2:
				for lv in sp[2].split(","):
					_shot_slot_levels.append(int(lv))
		elif a == "--shot-powerups":
			_shot_powerups = true
		elif a == "--shot-potions":
			_shot_potions = true
		elif a == "--shot-pool":
			_shot_pool = true
		elif a == "--shot-front":
			_shot_front = true
		elif a.begins_with("--shot-pos="):   # x,y,z[,yaw degrees]: start the screenshot run here
			var v := a.split("=")[1].split(",")
			_shot_pos = Vector3(float(v[0]), float(v[1]), float(v[2]))
			_shot_yaw = deg_to_rad(float(v[3])) if v.size() > 3 else 0.0
		elif a == "--shot-nohud":   # clean pictures (map previews)
			_shot_nohud = true
		elif a.begins_with("--shot-slow="):
			_shot_slow = float(a.split("=")[1])
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
	var kit_hp := float(KitDB.kit(Settings.selected_character).get("max_hp", 0.0))
	if kit_hp > 0.0:   # some characters start tougher (Thog: a melee bruiser, 250 HP)
		stats.apply("max_hp", "flat", kit_hp - float(BASE_STATS["max_hp"]))
	skills_applied = SkillTree.apply(Settings.selected_character, stats)   # skill tree bonuses
	db = UpgradeDB.new("res://data/upgrades.json", rng)

	water = WorldBuilder.build(self, rng, ARENA_HALF, Settings.selected_map)
	boss_id = MAP_BOSS.get(Settings.selected_map, "")
	boss_map = boss_id != ""
	endless = Settings.game_mode == "unrelenting"
	db.uncapped = endless

	fx = FxManager.new()
	add_child(fx)

	player = Player.new()
	player.fx = fx
	player.water = water
	player.stats = stats
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.global_position = Vector3(0, water.ground_height(0, 0) + 0.5, 0)
	player.died.connect(_on_player_died)
	if stats.value("start_shield") > 0.0:
		player.add_shield(stats.value("max_hp") * stats.value("start_shield"))

	enemies = EnemyManager.new()
	enemies.player = player
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

	# The character: Fire Wizard, or a playable roster character with its own weapon and kit
	var who := Settings.selected_character if RosterHero.is_playable(Settings.selected_character) else "fire_wizard"
	weapons = WeaponSystem.new()
	weapons.style = WeaponSystem.style_of(who)
	WeaponSystem.retheme_card(db, weapons.style)
	WeaponSystem.add_signature_weapons(db, stats, weapons.style)   # unlocked characters' weapons
	Forge.apply(stats, "orb", weapons.style)   # your own weapon, as forged
	weapons.setup(stats, db, enemies, player)
	weapons._fx_mgr = fx
	add_child(weapons)

	abilities = Abilities.new()
	abilities.kit = who
	abilities.setup(stats, enemies, player, fx)
	add_child(abilities)
	abilities.cast.connect(func(i: int):
		if abilities.roster != null or i != Abilities.METEOR:   # the Meteor plays its own arms-up as he vanishes
			player.model.play_ability(i))
	goblin_audio = GoblinAudio.new()
	goblin_audio.setup(enemies, player, rng)
	add_child(goblin_audio)

	potions = PotionManager.new()
	potions.setup(player, abilities, rng)
	add_child(potions)
	potions.collected.connect(func(k: int): hud.flash_message(PotionManager.NAMES[k], 1.5))
	potions.healed.connect(func(amount: float):
		hud.show_heal(amount)
		numbers.add(player.global_position + Vector3(0, 2.6, 0), amount, DamageNumbers.HEAL))
	potions.cooldowns_cut.connect(func(cuts: PackedFloat32Array): hud.show_cooldown_cuts(cuts))
	keys = KeyManager.new()
	keys.setup(player, rng)
	add_child(keys)
	keys.collected.connect(func(t: int): hud.flash_message(tr("%s!") % tr(KeyManager.NAMES[t]), 1.8))
	enemies.epic_killed.connect(func(p: Vector3):
		elites_killed += 1
		potions.on_elite_killed(p)
		keys.on_elite_killed(p + Vector3(0.8, 0, 0)))
	chests = ChestManager.new()
	chests.setup(player, water, keys, rng)
	add_child(chests)
	chests.spawn_all()
	chests.open_requested.connect(_on_chest_opened)

	powerups = PowerupManager.new()
	powerups.setup(player, stats, enemies, gems, db, rng)
	add_child(powerups)
	powerups.collected.connect(func(k: int): hud.flash_message(PowerupManager.PICKUP_TEXT[k], 2.5))
	enemies.epic_killed.connect(func(p: Vector3): powerups.on_elite_killed(p))

	enemies.exploded.connect(func(p: Vector3, r: float): fx.burst(p, r * 1.4, Color(1.0, 0.4, 0.08), 0.35))
	enemies.burst.connect(func(p: Vector3, r: float): fx.burst(p, r * 1.3, Color(0.55, 1.0, 0.25), 0.35))
	if abilities.roster:
		weapons.kit = abilities.roster
		abilities.roster.weapons = weapons
		abilities.roster.drop_xp.connect(func(p: Vector3, amount: float): gems.spawn(p + Vector3(0, 0.5, 0), amount * xp_drop_mult()))
		abilities.roster.healed.connect(func(amount: float):
			hud.show_heal(amount)
			numbers.add(player.global_position + Vector3(0, 2.6, 0), amount, DamageNumbers.HEAL))

	items = ItemEffects.new()
	items.setup(stats, enemies, player, rng)
	weapons.items = items
	add_child(items)

	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	# Main runs while paused (menus, input); all gameplay nodes freeze with the pause.
	for n in [fx, enemies, numbers, corpses, powerups, chests, keys, gems, weapons, abilities, potions, goblin_audio, items]:
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
	# Entrance: everything holds still while the wizard comes down as a meteor; the run (and
	# the "SURVIVE" banner) starts when he lands. Screenshot/smoke runs skip it unless asked.
	# Indoors (the castle) there's no sky: you walk in through the front doors, which slam
	# shut behind you.
	castle_doors = find_children("*", "CastleDoors", true, false).pop_front() as CastleDoors
	Abilities.ceiling = CastleBuilder.CEILING if castle_doors != null else INF
	if (smoke or shot_path != "") and not _shot_intro:
		if castle_doors:
			player.global_position = CastleBuilder.INSIDE + Vector3(0, 0.5, 0)
			castle_doors.close_now()
		hud.intro_banner.show_text(_banner_text())
	elif castle_doors:
		intro = true
		if not endless:
			hud.start_clock_spin()
		player.global_position = CastleBuilder.PORCH + Vector3(0, 0.5, 0)
		_walk_in = true
	else:
		intro = true
		if not endless:
			hud.start_clock_spin()
		abilities.entrance_landed.connect(_on_entrance_landed, CONNECT_ONE_SHOT)
		abilities.entrance_meteor(Vector3(0, water.ground_height(0, 0), 0))


## The castle entrance: walk the player in through the doors, then shut them.
func _castle_intro() -> void:
	if not _walk_in:
		return
	if player.global_position.z > CastleBuilder.INSIDE.z:
		player.bot = true
		player.bot_move = Vector2(0, -1)
		player.cam_yaw = 0.0
		return
	_walk_in = false
	player.bot = smoke
	player.bot_move = Vector2.ZERO
	castle_doors.shut.connect(_on_entrance_landed, CONNECT_ONE_SHOT)
	castle_doors.close()


func _on_entrance_landed() -> void:
	intro = false
	hud.intro_banner.show_text(_banner_text())


func _banner_text() -> String:
	return "SURVIVE"   # every mode


## Unrelenting: enemy contact damage multiplier (1 until 10:00, then climbing).
func enemy_damage_mult() -> float:
	if not endless:
		return 1.0
	return 1.0 + maxf(0.0, run_time - ENDLESS_FROM) / 60.0 * ENDLESS_DMG_PER_MIN


## Unrelenting: XP gem value multiplier (1 until 10:00, then shrinking).
func xp_drop_mult() -> float:
	if not endless:
		return 1.0
	return 1.0 / (1.0 + maxf(0.0, run_time - ENDLESS_FROM) / 60.0 * ENDLESS_XP_PER_MIN)


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
	if intro:   # entrance: only the meteor / the walk-in moves; goblins, spawns and the clock wait
		abilities.tick(dt)
		_castle_intro()
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
	keys.tick(dt, stats.value("pickup_range"))
	chests.tick(dt)
	goblin_audio.tick(dt)
	var t3 := Time.get_ticks_usec()
	_track_perf((t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0)

	_contact_damage()
	if gained > 0.0:
		_add_xp(gained * stats.value("xp_gain"))
	if endless:
		if Settings.selected_map == "swamp" and run_time >= GHAST_FEAT_TIME and Wallet.earn_feat(GHAST_FEAT):
			hud.flash_message("15:00 IN THE SWAMP!  Ghast can now be unlocked", 5.0)
	elif run_time >= RUN_LENGTH and state == "playing" and not boss_map:
		_end_run(true)   # boss maps are won by killing the boss instead


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
	if player.meteor_form or player.phase:
		return   # untouchable while falling as the meteor / phased (Ghast)
	var me := player.global_position
	var hits := enemies.query_radius(me + Vector3(0, 0.9, 0), 0.45)
	if hits.is_empty():
		return
	if player.invuln <= 0.0:
		var dmg := 0.0
		var push := Vector3.ZERO
		for i in hits:
			if enemies.is_harmless(i):
				continue   # frozen, stunned, frogs, possessed or fleeing goblins can't hit
			if enemies.typ[i] == EnemyManager.TROLL and not enemies.boss_contact:
				continue
			dmg = maxf(dmg, enemies.t_damage[enemies.typ[i]] * enemy_damage_mult() * enemies.hit_mult(i) * (EnemyManager.BOSS_DAMAGE_MULT if enemies.is_boss(i) else 1.0))
			var away := enemies.pos[i] - me
			away.y = 0.0
			push -= away.normalized() if away.length_squared() > 0.0001 else Vector3.ZERO
		if dmg <= 0.0:
			return
		player.hurt(dmg)
		_smoke_contacts += 1
		# Thorns (the weapon) and Shield Wall: whatever hits you takes its damage back
		var thorns := player.thorns
		if db.level_of("weapon_thorns") > 0:
			thorns += stats.value("thorns_return") * stats.value("damage")
		if thorns > 0.0:
			for i in hits:
				if not enemies.is_harmless(i):
					enemies.damage(i, enemies.t_damage[enemies.typ[i]] * enemy_damage_mult() * thorns)
					if db.level_of("weapon_thorns") > 0:
						fx.burst(enemies.center_of(i), 0.9, Color(0.72, 0.9, 0.3), 0.2)
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
			_smoke_immune_knocks += 1


func epic_chance() -> float:
	return EPIC_BASE_CHANCE + EPIC_CHANCE_PER_LUCK * stats.value("luck")   # Tome of Luck, skills, anything


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
		if enemies.count >= mini(LIVE_CAP, EnemyManager.MAX - 60):
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
			if CastleNav.current != null and CastleNav.current.steps_to_player(p.x, p.z) <= 0:
				p = _spawn_point(18.0, 28.0)   # indoors: that spot is a wall or cut off
			_spawn_enemy(EnemyManager.RUNNER if CastleNav.current == null or rng.randf() > SKELETON_SHARE else EnemyManager.SKELETON, p, hpm)
		hud.flash_message("SWARM!", 2.0)

	if boss_map:
		if boss_id == "thog":
			if thog == null and run_time >= _thog_at:
				spawn_thog()
		elif map_boss == null and run_time >= _thog_at:
			spawn_map_boss()
	elif not _boss_spawned and run_time >= BOSS_TIME:
		_boss_spawned = true
		enemies.spawn(EnemyManager.BOSS, _spawn_point(30.0, 32.0), hpm)
		hud.flash_message("A GOBLIN WARLORD APPROACHES", 4.0)


const LIVE_CAP := 350   # the steady trickle pauses while this many goblins are alive (swarm rings still come)
const SKELETON_SHARE := 0.35  # castle: this share of spawns are skeletons (same overall rate)


func _pick_type(m: float) -> int:
	if CastleNav.current != null and rng.randf() < SKELETON_SHARE:
		return EnemyManager.SKELETON
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
	if CastleNav.current != null:   # indoors: a floor cell the horde can reach you from
		var c := CastleNav.current
		c.update(0.0, player.global_position)
		var q := c.reachable_point(player.global_position, min_d, max_d, rng)
		if q != Vector3.INF:
			return q
	var a := rng.randf() * TAU
	var p := player.global_position + Vector3(cos(a), 0, sin(a)) * rng.randf_range(min_d, max_d)
	var q := Vector3(clampf(p.x, -ARENA_HALF + 2, ARENA_HALF - 2), 0, clampf(p.z, -ARENA_HALF + 2, ARENA_HALF - 2))
	q.y = water.ground_height(q.x, q.z)
	return q


## Thog the Troll walks out of the fog with 2 minutes left (Swamp only).
func spawn_thog() -> ThogBoss:
	thog = ThogBoss.new()
	thog.setup(self, _spawn_point(34.0, 38.0), hp_mult())
	add_child(thog)
	thog.defeated.connect(_on_thog_defeated)
	if _thog_enraged:
		thog.alive_time = ThogBoss.ENRAGE_AFTER
	hud.intro_banner.show_text("THOG THE TROLL")
	hud.flash_message("THOG THE TROLL APPROACHES", 4.0)
	return thog


## The Forest's Toadstool Knight / the Castle's Arachnid walks in with 2 minutes left.
func spawn_map_boss() -> MapBoss:
	map_boss = ArachnidBoss.new() if boss_id == "arachnid" else ToadstoolBoss.new()
	map_boss.setup(self, _spawn_point(34.0, 38.0), hp_mult())
	add_child(map_boss)
	map_boss.defeated.connect(_on_boss_defeated)
	if _thog_enraged:
		map_boss.alive_time = MapBoss.ENRAGE_AFTER
	boss_name = map_boss.display_name()
	hud.intro_banner.show_text(boss_name)
	hud.flash_message(tr("%s APPROACHES") % tr(boss_name), 4.0)
	return map_boss


func _on_thog_defeated() -> void:
	boss_name = "THOG"
	_on_boss_defeated()


## A boss fell: 1-5 elemental shards of random kinds, banked at once and listed at the end.
func _award_shards() -> void:
	var won := Wallet.roll_boss_shards(rng)
	for kind in won:
		shards_won[kind] = int(shards_won.get(kind, 0)) + int(won[kind])
	Wallet.add_shards(won)
	var parts := []
	for kind in Wallet.SHARDS:
		if won.has(kind):
			parts.append("%d %s" % [won[kind], tr(Wallet.SHARD_NAMES[kind])])
	hud.flash_message(tr("SHARDS: %s") % ", ".join(parts), 3.0)


## A map boss has fallen: gems fly in, first kills unlock things, and the run is won.
func _on_boss_defeated() -> void:
	gems.magnetise_all()
	_award_shards()
	first_boss_kill = Wallet.defeat_boss(boss_id)
	if boss_id == "thog":
		hud.flash_message("THOG IS DEFEATED!", 4.0)
	else:
		hud.flash_message(tr("%s IS DEFEATED!") % tr(boss_name), 4.0)
	if endless:
		_thog_at = INF   # Unrelenting: the run goes on (he doesn't come back)
		return
	await get_tree().create_timer(4.0, true).timeout   # he topples; gems fly in
	if state == "levelup":   # no point picking upgrades now: straight to the victory
		hud.hide_draft()
		pending_levels = 0
		state = "playing"
	if state == "chest":   # finish the slot machine first? no - the boss is down: the win comes first
		hud.hide_slot_machine()
		state = "playing"
	while state == "paused" or state == "inspect":
		await get_tree().process_frame
	if state == "playing":
		boss_won = true
		_end_run(true)


func _on_enemy_killed(p: Vector3, type_id: int) -> void:
	kills += 1
	gems.spawn(p + Vector3(0, 0.5, 0), enemies.t_xp[type_id] * xp_drop_mult() * enemies.kill_xp_mult)
	if type_id == EnemyManager.BOSS:
		gems.magnetise_all()
		_award_shards()
		hud.flash_message("GOBLIN WARLORD SLAIN!", 4.0)


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
		for k in abilities.defs().size():
			var d: Dictionary = abilities.defs()[k]
			if int(d["unlock_level"]) == level:
				hud.flash_message(tr("NEW ABILITY UNLOCKED: %s  [%s]") % [tr(d["name"]).to_upper(), d["key"]], 4.0)
	if pending_levels > 0 and state == "playing":
		_open_draft()


func _open_draft(chained := false) -> void:
	current_draft = db.draft(3, stats.value("luck"), MAX_WEAPONS)
	if not chained:
		hud.play_ui("levelup")   # once per level-up moment, not again for each stacked level
	if current_draft.is_empty():   # everything maxed: just heal
		pending_levels = 0
		player.heal(player.max_hp)
		return
	state = "levelup"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_draft(current_draft)
	if smoke:
		if bans_left > 0 and current_draft.size() > 1:   # exercise BAN too (smoke runs don't save coins)
			Wallet.coins = maxi(Wallet.coins, BAN_COST)
			ban_upgrade(current_draft.size() - 1)
		var open := []
		for k in current_draft.size():
			if not current_draft[k].get("banned", false):
				open.append(k)
		choose_upgrade.call_deferred(open[rng.randi() % open.size()])


const BANS_PER_RUN := 3
const BAN_COST := 100   # coins
var bans_left := BANS_PER_RUN


## Can reward card i be banned right now? (a ban left, 100 coins, and it isn't the last card)
func can_ban(i: int) -> bool:
	if state != "levelup" or i < 0 or i >= current_draft.size() or current_draft[i].get("banned", false):
		return false
	var open := current_draft.filter(func(p): return not p.get("banned", false)).size()
	return bans_left > 0 and Wallet.coins >= BAN_COST and open > 1


## BAN: pay 100 coins to remove reward card i from this draft and from every later draft
## this run. Three per run.
func ban_upgrade(i: int) -> bool:
	if not can_ban(i) or not Wallet.spend(BAN_COST):
		return false
	bans_left -= 1
	db.banned[current_draft[i]["id"]] = true
	current_draft[i]["banned"] = true
	hud.mark_banned(i)
	return true


const LEGENDARY := 3   # rarity index of Legendary cards
const CONVERT_ODDS := [60.0, 30.0, 10.0]   # Convert: bronze, silver, gold key


## Convert (Legendary cards only): skip the upgrade and take one chest key instead -
## 60% bronze, 30% silver, 10% gold. The key pops up big, then flies to the key counter.
func convert_upgrade(i: int) -> int:
	if state != "levelup" or i < 0 or i >= current_draft.size() or current_draft[i].get("banned", false):
		return -1
	if int(current_draft[i].get("rarity", 0)) != LEGENDARY:
		return -1
	var r := rng.randf() * 100.0
	var tier := 0 if r < CONVERT_ODDS[0] else (1 if r < CONVERT_ODDS[0] + CONVERT_ODDS[1] else 2)
	keys.keys[tier] += 1
	hud.key_popup(tier)
	pending_levels -= 1
	if pending_levels > 0:
		state = "playing"
		_open_draft(true)
		return tier
	hud.hide_draft()
	_resume()
	return tier


func choose_upgrade(i: int) -> void:
	if state != "levelup" or i < 0 or i >= current_draft.size() or current_draft[i].get("banned", false):
		return
	var is_tome: bool = db.defs[current_draft[i]["id"]]["kind"] == "tome"
	db.apply(current_draft[i], stats)
	hud.play_ui("pick_tome" if is_tome else "pick")
	pending_levels -= 1
	if pending_levels > 0:
		state = "playing"
		_open_draft(true)
		return
	hud.hide_draft()
	_resume()


func cast_ability(i: int) -> void:
	if state != "playing" or intro:
		return
	if abilities.try_cast(i):
		if i == Abilities.INFERNO or i == Abilities.METEOR:
			hud.flash_message(tr(str(abilities.defs()[i]["name"])).to_upper() + "!", 2.0)


func resume_from_pause() -> void:
	if state == "paused":
		_resume()


## A chest opened (its key used): pause for the slot machine, like a level-up.
func _on_chest_opened(c: Chest) -> void:
	chests_opened += 1
	_open_slot_machine(c.tier)


func _open_slot_machine(tier: int) -> void:
	if state != "playing" and shot_path == "":
		_chest_queue.append(tier)   # after the level-up / other chest
		return
	if abilities.levelable().is_empty():   # every ability maxed out: a full heal instead
		player.heal(player.max_hp)
		hud.flash_message(tr("Every ability is at max level!  Fully healed"), 3.0)
		return
	state = "chest"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.play_ui("levelup")
	var m := hud.show_slot_machine(tier, func(a: int, n: int): _on_slot_done(a, n))
	if smoke:   # smoke runs pull the handle and take the prize by themselves
		m.pull.call_deferred()
		get_tree().create_timer(3.5, true).timeout.connect(func(): if is_instance_valid(m): m._finish())


func _on_slot_done(a: int, n: int) -> void:
	hud.hide_slot_machine()
	var name := tr(str(abilities.defs()[a]["name"])).to_upper()
	hud.flash_message(tr("%s  LEVEL %d") % [name, abilities.ab_level[a]], 2.5)
	_resume()
	if pending_levels > 0 and state == "playing":
		_open_draft()


func _resume() -> void:
	state = "playing"
	get_tree().paused = false
	hud.set_paused(false)
	if not smoke:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not _chest_queue.is_empty():   # a chest opened while a menu was up
		_open_slot_machine.call_deferred(_chest_queue.pop_front())


func _on_player_died() -> void:
	_end_run(false)


## Level music (the map's own track, else the swamp theme): starts with the level and repeats
## until the map ends.
## Keeps playing through pause and level-up menus.
func _start_music() -> void:
	MenuMusic.fade_out(0.3)   # in case the menu theme is still going
	music = AudioStreamPlayer.new()
	music.bus = Settings.MUSIC_BUS
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	music.volume_db = MUSIC_VOLUME_DB
	add_child(music)
	var track: String = MAP_MUSIC.get(Settings.selected_map, SWAMP_MUSIC)
	if not ResourceLoader.exists(track):
		return
	var stream: AudioStream = load(track)
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


const TITLE_SCENE := "res://scenes/title.tscn"


func to_title() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE_SCENE)


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
	_bind("activate", [KEY_E], [JOY_BUTTON_DPAD_UP], [])


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
	if Time.get_ticks_msec() - _smoke_wall_start > _smoke_wall_ms:
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
				if thog != null:
					print("SMOKE thog hp %.0f%% enraged %s state %s attacks %s" % [thog.hp_fraction() * 100.0, str(thog.is_enraged), thog.state, str(thog.counts)])
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
	var boss_row := thog.row() if thog != null else (map_boss.row() if map_boss != null else -1)
	if _shot_thog and boss_row >= 0:   # --shot-thog: stand near the map's boss and watch it
		var tp := enemies.pos[boss_row]
		var to := tp - player.global_position
		to.y = 0.0
		if to.length() > _shot_thog_dist + 1.0 or to.length() < _shot_thog_dist - 3.0:
			var p := tp - to.normalized() * _shot_thog_dist
			player.global_position = Vector3(p.x, water.ground_height(p.x, p.z) + 0.5, p.z)
		player.cam_yaw = atan2(-to.x, -to.z) + _shot_thog_side
	if _shot_zoom > 0.0:
		player.spring.spring_length = _shot_zoom
		Player.zoom = _shot_zoom
	if _shot_ignite and run_time < 0.05:
		# Stand 11 m from the nearest standing tree, look at it, and set it on fire
		var best: Node3D = null
		for t in get_tree().get_nodes_in_group(TreeFire.GROUP):
			var tb := t as Node3D
			if float(tb.get_meta("reach")) < 2.0 and (best == null or tb.global_position.length() < best.global_position.length()):
				best = tb
		var tp := best.global_position
		var away := Vector3(tp.x, 0, tp.z).normalized()
		player.global_position = tp - away * 11.0
		player.global_position.y = water.ground_height(player.global_position.x, player.global_position.z) + 0.5
		var to := tp - player.global_position
		player.cam_yaw = atan2(-to.x, -to.z)
		TreeFire.ignite(best)
	if run_time < 0.05 and (not _shot_inv.is_empty() or not _shot_keys.is_empty()):
		for id in _shot_inv:
			if db.defs.has(id) and db.level_of(id) == 0:
				db.apply({"id": id, "rarity": 0}, stats)
		for t in mini(3, _shot_keys.size()):
			keys.keys[t] = _shot_keys[t]
	if _shot_castle:
		var dc := find_child("DistantCastle", true, false) as DistantCastle
		if dc != null:
			player.cam_yaw = atan2(-cos(dc.bearing), -sin(dc.bearing)) + _shot_turn
	if _shot_chest >= 0 and run_time < 0.05:
		var fwd3 := Vector3(-sin(player.cam_yaw), 0, -cos(player.cam_yaw))
		var at := player.global_position + fwd3 * 5.0
		at.y = water.ground_height(at.x, at.z)
		var c := chests.place(at, _shot_chest)
		c.rotation.y = player.cam_yaw
		keys.drop(player.global_position + fwd3 * 2.5 + Vector3(1.5, 0, 0), _shot_chest)
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
		player.global_position = Vector3(c.x + r + 6.0, water.ground_height(c.x + r + 6.0, c.y + 1.0) + 0.5, c.y + 1.0)
		player.cam_yaw = atan2(-(c.x - player.global_position.x), -(c.y - player.global_position.z)) * -1.0
		var to := Vector3(c.x, 0, c.y) - player.global_position
		player.cam_yaw = atan2(-to.x, -to.z)
	player.face_camera = _shot_front
	if _shot_pitch > -90.0:
		player.cam_pitch = _shot_pitch
	if _shot_pos != Vector3.INF and run_time < 0.05:
		player.global_position = _shot_pos
		player.cam_yaw = _shot_yaw
		if CastleNav.current != null:
			CastleNav.current.update(1.0, _shot_pos)   # spawn points near the new spot
	for g in _shot_give:
		for k in int(g[1]):
			db.apply({"id": g[0], "rarity": 0}, stats)
	_shot_give.clear()
	if _shot_spawn > 0:
		for k in _shot_spawn:
			var t := EnemyManager.TANK if k % 9 == 0 else (EnemyManager.RUNNER if k % 3 == 0 else EnemyManager.GRUNT)
			if CastleNav.current != null and k % 3 == 1:
				t = EnemyManager.SKELETON   # indoors: show some skeletons too
			if _shot_epic and k % 3 == 0:   # --shot-epic: every third one is an epic, close by
				enemies.spawn(t, _spawn_point(5.0, 9.0), 3.0, true)
			else:
				_spawn_enemy(t, _spawn_point(14.0, 30.0), 3.0)
		_shot_spawn = 0
	if _shot_nohud:
		hud.visible = false
		Wallet.set_shown(false)
		for c in hud.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
	if _shot_slow >= 0.0 and run_time >= _shot_slow:
		Engine.time_scale = 0.02
		shot_at = minf(shot_at, run_time + 0.1)
	for t in shot_casts.keys():
		if run_time >= t:
			abilities.reset_cooldowns()
			cast_ability(shot_casts[t])
			shot_casts.erase(t)
	if _shot_boss_win >= 0.0 and run_time >= _shot_boss_win:
		_shot_boss_win = -1.0
		_award_shards()
		boss_won = true
		first_boss_kill = true
		_end_run(true)
		shot_at = INF
		get_tree().create_timer(_shot_boss_wait, true).timeout.connect(shot_path_save)
	if run_time >= shot_at:
		if _shot_inspect >= 0:
			state = "inspect"
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			hud.set_inspect(true)
			hud._on_slot_hover(_shot_inspect, true)
			if not _shot_inv.is_empty():
				hud._on_slot_hover(_shot_inspect, false)
				for row in hud.inv_box.get_children():
					for chip in row.get_children():
						if chip.get_meta("id", "") == _shot_inv[0]:
							hud._on_inv_hover(_shot_inv[0], chip, true)
			hud._update_tooltip()
		if not _shot_draft.is_empty():
			state = "levelup"
			get_tree().paused = true
			current_draft = _shot_draft
			Wallet.coins = maxi(Wallet.coins, 500)   # screenshot runs don't save
			hud.show_draft(current_draft)
			if _shot_ban >= 0:
				ban_upgrade(_shot_ban)
		if _shot_slot >= 0:
			for k in mini(3, _shot_slot_levels.size()):
				abilities.ab_level[k] = _shot_slot_levels[k]
			_open_slot_machine(_shot_slot)
			if _shot_slot_pull >= 0.0:
				hud.slot_machine.pull()
				get_tree().create_timer(_shot_slot_pull, true).timeout.connect(shot_path_save)
				set_physics_process(false)
				return
		if _shot_settings_tab >= 0:
			state = "paused"
			get_tree().paused = true
			hud.set_paused(true)
			hud.open_settings()
			hud.settings_menu._tabs.current_tab = _shot_settings_tab
		shot_path_save.call_deferred()
		set_physics_process(false)


func _dump_frame() -> void:
	if _frames_left <= 0 or run_time < _frames_start:
		return
	get_viewport().get_texture().get_image().save_jpg("%s/f%04d.jpg" % [_frames_dir, _frames_n], 0.85)
	_frames_n += 1
	_frames_left -= 1
	if _frames_left == 0:
		print("FRAMES saved %d" % _frames_n)
		get_tree().quit()


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
