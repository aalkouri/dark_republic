extends Node
## Playtest bot: plays real runs (no god mode) and reports wins and deaths.
##   godot --headless --fixed-fps 60 --path . res://tools/playtest.tscn -- \
##       --chars=fire_wizard,ice_wizard --runs=5 --map=swamp --out=/tmp/results.txt
##
## How it plays: kites the horde (steering away from nearby goblins, weighted by distance and
## size), keeps clear of Thog and steps out of his red attack markers, stays off ponds and away
## heads for a chest it holds the key to, drifts toward XP gems when it's safe, keeps away from the arena edge and
## sidesteps when it's stuck on a tree. It casts abilities when a crowd is close (or the boss
## is), aims the Fire Wizard's Meteor at the thickest crowd, and picks level-up cards from a
## priority list: its weapon, then damage, health, armour, regen, area, attack speed, speed.
## A run ends when it dies (time of death reported) or wins (kills the map's boss).
## Each run's details (upgrades taken in order, potions and power-ups picked up) are also
## appended as one JSON line to <out>.jsonl.

const UPGRADE_PRIORITY := {
	"weapon_orb": 100, "tome_damage": 60, "tome_vitality": 55, "tome_armor": 50, "tome_quantity": 50,
	"tome_regen": 45, "tome_haste": 45, "tome_area": 40, "weapon_frost": 42, "weapon_aura": 40, "tome_swift": 38,
	"weapon_thorns": 36,
	"weapon_slam": 35, "item_fang": 34, "tome_magnet": 30, "tome_xp": 28, "item_bomb": 26,
	"tome_velocity": 20, "tome_luck": 15, "item_feather": 10,
}
const SAFE_RADIUS := 14.0
const LOG_EVERY := 60.0
const MAX_RUN := 1500.0          # give up after 25 minutes of game time

var chars: PackedStringArray = ["fire_wizard"]
var runs := 5
var map := "swamp"
var out_path := "user://playtest.txt"
var main: Node
var _queue: Array = []
var _cur := {}
var _results: Array = []
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _side := 1.0
var _dodge_t := 0.0
var _wander := 0.0
var _log_t := 0.0
var _picks: Array = []           # upgrade titles taken this run, in order
var _potions := {}               # potion name -> count picked up
var _keys := [0, 0, 0]           # keys picked up this run: bronze, silver, gold
var _powerups := {}              # power-up name -> count picked up
var _chests := 0                 # chests opened (slot machine pulls)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Wallet.persist = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--chars="):
			chars = a.split("=")[1].split(",")
		elif a.begins_with("--runs="):
			runs = int(a.split("=")[1])
		elif a.begins_with("--map="):
			map = a.split("=")[1]
		elif a.begins_with("--out="):
			out_path = a.split("=")[1]
	for c in chars:
		for k in runs:
			_queue.append({"char": c, "n": k + 1})
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	_next()


func _next() -> void:
	if _queue.is_empty():
		_finish()
		return
	_cur = _queue.pop_front()
	get_tree().paused = false
	Settings.selected_map = map
	Settings.selected_character = _cur["char"]
	Settings.game_mode = "classic"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	_stuck_t = 0.0
	_log_t = 0.0
	_wander = randf() * TAU
	_picks = []
	_potions = {}
	_keys = [0, 0, 0]
	_powerups = {}
	_chests = 0
	main.potions.collected.connect(func(k: int): _bump(_potions, PotionManager.NAMES[k].get_slice(":", 0)))
	main.keys.collected.connect(func(tier: int): _keys[tier] += 1)
	main.powerups.collected.connect(func(k: int): _bump(_powerups, PowerupManager.NAMES[k]))


func _bump(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1


func _physics_process(dt: float) -> void:
	if main == null or not is_instance_valid(main) or _cur.is_empty():
		return
	var st: String = main.state
	if st == "levelup":
		_pick_upgrade()
		return
	if st == "chest":   # pull the handle, then take the prize
		var sm: SlotMachine = main.hud.slot_machine
		if sm != null:
			if sm._state == "ready":
				sm.pull()
			elif sm.is_done():
				_chests += 1
				sm._finish()
		return
	if st == "dead" or st == "won" or main.run_time > MAX_RUN:
		_record(st)
		return
	if main.intro or st != "playing":
		return
	_steer(dt)
	_cast()
	_log_t += dt
	if _log_t >= LOG_EVERY:
		_log_t = 0.0
		print("  [%s #%d] %s  lvl %d  hp %d/%d  kills %d  enemies %d" % [_cur["char"], _cur["n"], _fmt(main.run_time), main.level,
			int(main.player.hp), int(main.player.max_hp), main.kills, main.enemies.alive_count()])


# ------------------------------------------------------------------ results

func _record(st: String) -> void:
	var won: bool = st == "won"
	var r := {"char": _cur["char"], "n": _cur["n"], "won": won, "time": main.run_time, "level": main.level,
		"kills": main.kills, "boss_hp": _boss_hp()}
	_results.append(r)
	var detail := r.duplicate()
	detail["result"] = "WON" if won else ("DIED" if st == "dead" else "TIMEOUT")
	detail["time_s"] = r["time"]
	detail["upgrades"] = _picks
	detail["potions"] = _potions
	detail["powerups"] = _powerups
	detail["chests"] = _chests
	detail["ability_levels"] = Array(main.abilities.ab_level)
	detail["keys_left"] = Array(main.keys.keys)
	detail["keys"] = {"Bronze": _keys[0], "Silver": _keys[1], "Gold": _keys[2]}
	detail["shards"] = main.shards_won.duplicate()
	var jf := FileAccess.open(out_path + ".jsonl", FileAccess.READ_WRITE if FileAccess.file_exists(out_path + ".jsonl") else FileAccess.WRITE)
	if jf:
		jf.seek_end()
		jf.store_line(JSON.stringify(detail))
		jf.close()
	var line := "%s #%d: %s at %s  (lvl %d, %d kills%s)" % [r["char"], r["n"], "WON" if won else ("DIED" if st == "dead" else "TIMEOUT"),
		_fmt(r["time"]), r["level"], r["kills"], "" if won or r["boss_hp"] < 0 else ", Thog at %d%% HP" % roundi(r["boss_hp"] * 100)]
	print("RESULT " + line)
	var f := FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()
	_cur = {}
	main = null
	_next.call_deferred()


func _boss_hp() -> float:
	var b = main.get("map_boss")
	if b == null:
		b = main.get("thog")
	if b == null or not is_instance_valid(b) or not b.has_method("hp_fraction"):
		return -1.0
	return b.hp_fraction()


func _finish() -> void:
	print("PLAYTEST DONE")
	for c in chars:
		var w := 0
		var deaths: Array[String] = []
		for r in _results:
			if r["char"] == c:
				if r["won"]:
					w += 1
				else:
					deaths.append(_fmt(r["time"]))
		print("SUMMARY %s: %d/%d won; deaths at %s" % [c, w, runs, ", ".join(deaths) if not deaths.is_empty() else "-"])
	get_tree().quit()


static func _fmt(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# ------------------------------------------------------------------ level-ups

func _pick_upgrade() -> void:
	var draft: Array = main.current_draft
	var best := -1
	var best_s := -1e9
	for k in draft.size():
		if draft[k].get("banned", false):
			continue
		var id: String = draft[k]["id"]
		var s: float = UPGRADE_PRIORITY.get(id, 25)
		if id.begins_with("sig_"):
			s = 70.0
		s += int(draft[k].get("rarity", 0)) * 8.0
		if s > best_s:
			best_s = s
			best = k
	var pick := best if best >= 0 else 0
	if pick < draft.size():
		_picks.append(str(draft[pick].get("title", draft[pick]["id"])))
	main.choose_upgrade(pick)


# ------------------------------------------------------------------ movement

func _steer(dt: float) -> void:
	var player: Player = main.player
	player.bot = true   # read bot_move instead of the keyboard
	var em: EnemyManager = main.enemies
	var p := player.global_position
	var v := Vector3.ZERO
	var threat := 0.0
	# Away from the horde
	for i in em.query_radius(p + Vector3(0, 0.8, 0), SAFE_RADIUS, false):
		if em.is_harmless(i):
			continue
		var d := em.pos[i] - p
		d.y = 0.0
		var dist := maxf(d.length() - em.t_radius[em.typ[i]] * em.sz[i], 0.3)
		var w := (2.0 if em.epic[i] else 1.0) * em.t_damage[em.typ[i]] / 16.0 / (dist * dist)
		v -= d.normalized() * w
		threat += w
	# Thog: keep away from him, and out of his red markers
	var b = main.get("map_boss")
	if b == null:
		b = main.get("thog")
	if b != null and is_instance_valid(b) and b.has_method("row") and b.row() >= 0:
		var bp: Vector3 = em.pos[b.row()]
		var bd := Vector3(p.x - bp.x, 0, p.z - bp.z)
		var keep := 14.0
		if bd.length() < keep:
			v += bd.normalized() * (keep - bd.length()) * 0.8
			threat += 2.0
		var tele = b.get("_tele")
		if tele != null and is_instance_valid(tele):
			var tc: Vector3 = (tele as Node3D).global_position
			var r: float = (tele as Node3D).scale.x + 2.5
			var out := Vector3(p.x - tc.x, 0, p.z - tc.z)
			if out.length() < r:
				v += (out.normalized() if out.length() > 0.1 else Vector3(1, 0, 0)) * 6.0
				threat += 10.0
		for w in b.get("_warns") if b.get("_warns") != null else []:
			var node = w.get("disc") if w is Dictionary else null
			if node != null and is_instance_valid(node):
				var c: Vector3 = (node as Node3D).global_position
				var out2 := Vector3(p.x - c.x, 0, p.z - c.z)
				if out2.length() < (node as Node3D).scale.x + 2.0:
					v += out2.normalized() * 6.0
					threat += 10.0
	# Gems when it's calm
	if threat < 0.6 and main.gems.count > 0:
		var best := Vector3.INF
		var bd2 := 30.0 * 30.0
		var gm: GemManager = main.gems
		for k in mini(gm.count, 400):
			var dd := p.distance_squared_to(gm.pos[k])
			if dd < bd2:
				bd2 = dd
				best = gm.pos[k]
		if best != Vector3.INF:
			v += Vector3(best.x - p.x, 0, best.z - p.z).normalized() * 0.6
	# A chest we hold the key to, when it's calm
	if threat < 0.6:
		var bestc: Chest = null
		var bdc := 45.0
		for c in main.chests.chests:
			if not c.is_open and main.keys.has_key(c.tier) and p.distance_to(c.global_position) < bdc:
				bdc = p.distance_to(c.global_position)
				bestc = c
		if bestc != null:
			v += Vector3(bestc.global_position.x - p.x, 0, bestc.global_position.z - p.z).normalized() * 1.2
	# Keep off the ponds and away from the arena edge
	var water: SwampWater = main.water
	var quaking: bool = b != null and is_instance_valid(b) and b.has_method("is_quaking") and b.is_quaking()
	if quaking and water:   # Thog's quake: the only safe place is in a pool - run for the nearest
		var best_c := Vector2.INF
		for pool in water.pools:
			var c3: Vector2 = pool["center"]
			if best_c == Vector2.INF or Vector2(p.x, p.z).distance_to(c3) < Vector2(p.x, p.z).distance_to(best_c):
				best_c = c3
		if best_c != Vector2.INF:
			v = Vector3(best_c.x - p.x, 0, best_c.y - p.z).normalized() * 50.0
	elif water:
		for pool in water.pools:
			var c2: Vector2 = pool["center"]
			var away := Vector3(p.x - c2.x, 0, p.z - c2.y)
			var r2: float = water.max_radius(pool) + 3.0
			if away.length() < r2:
				v += away.normalized() * (r2 - away.length()) * 0.4
	var from_c := Vector2(p.x, p.z).length()
	if from_c > 120.0:
		v -= Vector3(p.x, 0, p.z).normalized() * (from_c - 120.0) * 0.05
	# Nothing pressing: circle the middle of the map at a steady pace
	if v.length() < 0.15:
		_wander += dt * 0.15
		var target := Vector3(cos(_wander), 0, sin(_wander)) * 60.0
		v = (target - Vector3(p.x, 0, p.z)).normalized()
	# Stuck on a tree or wall: sidestep for a moment
	_dodge_t -= dt
	var moved := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
	_stuck_t = _stuck_t + dt if moved < 0.04 else maxf(0.0, _stuck_t - dt * 2.0)
	_last_pos = p
	if _stuck_t > 0.4:
		_dodge_t = 0.7
		_side = -_side
		_stuck_t = 0.0
		player.bot_jump = true
	else:
		player.bot_jump = false
	if _dodge_t > 0.0:
		v = v.normalized().rotated(Vector3.UP, PI * 0.5 * _side)
	v.y = 0.0
	v = v.normalized() if v.length() > 0.01 else Vector3.FORWARD
	# Camera-relative input
	var yaw: float = player.cam_yaw
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	player.bot_move = Vector2(v.dot(right), -v.dot(fwd))


# ------------------------------------------------------------------ abilities

func _cast() -> void:
	var ab: Abilities = main.abilities
	var em: EnemyManager = main.enemies
	var player: Player = main.player
	var p := player.global_position
	var near := em.query_radius(p + Vector3(0, 0.8, 0), 12.0, false).size()
	var boss_near := false
	var b = main.get("map_boss") if main.get("map_boss") != null else main.get("thog")
	if b != null and is_instance_valid(b) and b.has_method("row") and b.row() >= 0:
		boss_near = em.pos[b.row()].distance_to(p) < 25.0
	for k in 3:
		if not ab.is_ready(k):
			continue
		var want := near >= 10 or boss_near or (k < 2 and near >= 6)
		if Settings.selected_character == "merlin" and k == 2:
			want = player.hp < player.max_hp * 0.4 or near >= 25
		if want:
			if k == Abilities.METEOR and ab.roster == null:
				_face_crowd()
			main.cast_ability(k)


## Turn the camera toward the thickest crowd within 40 m (the Meteor lands where you look).
func _face_crowd() -> void:
	var em: EnemyManager = main.enemies
	var player: Player = main.player
	var p := player.global_position
	var best := Vector3.ZERO
	var best_n := 0
	for i in em.nearest_k(p, 40.0, 12):
		var n := em.query_radius(em.pos[i] + Vector3(0, 0.8, 0), 8.0, false).size()
		if n > best_n:
			best_n = n
			best = em.pos[i]
	if best_n > 0:
		var to := best - p
		player.cam_yaw = atan2(-to.x, -to.z)
