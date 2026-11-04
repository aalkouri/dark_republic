class_name RunStats
extends Node
## Developer stats (TEMPORARY — remove before release, with the Developer tab in Settings and
## StatsScreen). Records every real run you play (not the playtest bot, screenshots or smoke
## tests) to user://run_stats.jsonl: character, map, mode, result, time, level, kills, keys,
## shards, chests, potions, power-ups, the final build, boss HP left, what killed you, the damage
## you took by source and the damage you dealt by weapon / ability. StatsScreen reads it.
## One line per run, written when the run ends (or when you quit or restart mid-run).

const SavePaths := preload("res://scripts/save_paths.gd")
## user://run_stats.jsonl, or a throwaway copy in test and screenshot runs (SavePaths)
static var PATH: String = SavePaths.path("run_stats.jsonl")

var main: Node
var _keys := [0, 0, 0]
var _potions := {}
var _powerups := {}
var _saved := false


## Hook up to a run (main calls this once its managers exist).
func setup(p_main: Node) -> void:
	main = p_main
	main.keys.collected.connect(func(t: int): _keys[t] += 1)
	main.potions.collected.connect(func(k: int): _bump(_potions, str(PotionManager.NAMES[k]).get_slice(":", 0)))
	main.powerups.collected.connect(func(k: int): _bump(_powerups, str(PowerupManager.NAMES[k])))


static func _bump(d: Dictionary, k: String) -> void:
	d[k] = int(d.get(k, 0)) + 1


## Write this run's line ("WON", "DIED" or "QUIT"). Only once per run; quitting in the first
## few seconds isn't worth a line.
func save(result: String) -> void:
	if _saved or main == null or not Wallet.persist:
		return
	if result == "QUIT" and main.run_time < 10.0:
		return
	_saved = true
	var build := {}
	for id in main.db.levels:
		if int(main.db.levels[id]) > 0:
			build[str(main.db.defs[id]["name"]) if main.db.defs.has(id) else str(id)] = int(main.db.levels[id])
	var boss_hp := -1.0
	var b = main.get("map_boss")
	if b == null or not is_instance_valid(b):
		b = main.get("thog")
	if b != null and is_instance_valid(b) and b.has_method("hp_fraction"):
		boss_hp = b.hp_fraction()
	var line := {
		"ts": int(Time.get_unix_time_from_system()),
		"char": Settings.selected_character,
		"map": Settings.selected_map,
		"mode": Settings.game_mode,
		"result": result,
		"time": snappedf(main.run_time, 0.1),
		"level": main.level,
		"kills": main.kills,
		"elites": main.elites_killed,
		"boss": main.boss_id,
		"boss_hp": snappedf(boss_hp, 0.001),
		"keys": {"Bronze": _keys[0], "Silver": _keys[1], "Gold": _keys[2]},
		"shards": main.shards_won.duplicate(),
		"chests": main.chests_opened,
		"potions": _potions,
		"powerups": _powerups,
		"build": build,
		"ability_levels": Array(main.abilities.ab_level),
		"killed_by": main.player.last_hit_by if result == "DIED" else "",
		"damage_taken": _rounded(main.player.damage_by),
		"damage_dealt": _rounded(main.enemies.damage_by),
	}
	var f := FileAccess.open(PATH, FileAccess.READ_WRITE if FileAccess.file_exists(PATH) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(line))
	f.close()


static func _rounded(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = roundi(float(d[k]))
	return out


# ------------------------------------------------------------------ reading

## Every recorded run, oldest first.
static func load_runs() -> Array:
	var out := []
	if not FileAccess.file_exists(PATH):
		return out
	var f := FileAccess.open(PATH, FileAccess.READ)
	while f != null and not f.eof_reached():
		var l := f.get_line().strip_edges()
		if l == "":
			continue
		var d = JSON.parse_string(l)
		if d is Dictionary:
			out.append(d)
	return out


static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## Totals for a set of runs: counts, averages, bests and summed breakdowns.
static func summarize(runs: Array) -> Dictionary:
	var s := {"runs": runs.size(), "wins": 0, "deaths": 0, "quits": 0, "time": 0.0, "best_win": -1.0,
		"longest": 0.0, "level": 0.0, "kills": 0.0, "max_kills": 0, "keys": [0, 0, 0], "shards": {},
		"chests": 0, "dealt": {}, "taken": {}, "killers": {}, "boss_hp": [], "picks": {}}
	for r in runs:
		var t := float(r.get("time", 0.0))
		s["time"] += t
		s["longest"] = maxf(s["longest"], t)
		s["level"] += float(r.get("level", 0))
		s["kills"] += float(r.get("kills", 0))
		s["max_kills"] = maxi(s["max_kills"], int(r.get("kills", 0)))
		s["chests"] += int(r.get("chests", 0))
		match str(r.get("result", "")):
			"WON":
				s["wins"] += 1
				s["best_win"] = t if s["best_win"] < 0.0 else minf(s["best_win"], t)
			"DIED":
				s["deaths"] += 1
				_add(s["killers"], str(r.get("killed_by", "")), 1.0)
			_:
				s["quits"] += 1
		var k: Dictionary = r.get("keys", {})
		s["keys"][0] += int(k.get("Bronze", 0))
		s["keys"][1] += int(k.get("Silver", 0))
		s["keys"][2] += int(k.get("Gold", 0))
		for sh in r.get("shards", {}):
			_add(s["shards"], sh, float(r["shards"][sh]))
		for src in r.get("damage_dealt", {}):
			_add(s["dealt"], src, float(r["damage_dealt"][src]))
		for src in r.get("damage_taken", {}):
			_add(s["taken"], src, float(r["damage_taken"][src]))
		for p in r.get("build", {}):
			_add(s["picks"], p, 1.0)
		if float(r.get("boss_hp", -1.0)) >= 0.0 and str(r.get("result", "")) != "WON":
			s["boss_hp"].append(float(r["boss_hp"]))
	return s


static func _add(d: Dictionary, k: String, v: float) -> void:
	if k == "":
		return
	d[k] = float(d.get(k, 0.0)) + v


## A breakdown dictionary as [[name, value], ...], biggest first.
static func ranked(d: Dictionary, n := 99) -> Array:
	var all := []
	for k in d:
		all.append([k, float(d[k])])
	all.sort_custom(func(a, b): return a[1] > b[1])
	return all.slice(0, n)
