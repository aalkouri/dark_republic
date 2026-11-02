extends Node
## Run-start entrances: every playable character starts a real run (with the intro) on an
## outdoor map, the maps taken in turn, and arrives its own way. Checks: entrance_landed fires
## exactly once within 5 s, the world holds still meanwhile, the hero is seen arriving and ends
## standing visible on the target, the intro ends, goblins near the target are hurt and knocked
## back, the comet orb is only the Thunder Wizard's (the Fire Wizard keeps his giant head), and
## no two characters share an entrance.
##   godot --headless --fixed-fps 60 --path . res://tools/test_entrances.tscn [-- --only=ogre]

const MAPS := ["swamp", "forest", "desert", "graveyard", "caldera"]
var fails := 0
var main: Node


func _ready() -> void:
	Wallet.persist = false
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.split("=")[1]
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in

	var ids: Array[String] = ["fire_wizard"]
	for id in RosterHero.CFG.keys():
		if RosterHero.is_playable(id):
			ids.append(id)
	var kinds := {}
	for id in HeroEntrances.SPECS.keys():
		var k := HeroEntrances.kind_of(id)
		_check("%s's entrance (%s) is unique" % [id, k], not kinds.has(k) and k != "comet" and k != "giant_head", str(kinds.get(k, "")))
		kinds[k] = id
		var spec: Array = HeroEntrances.SPECS[id]
		_check("%s's entrance lasts 2.5-3.5 s, the hit before the landing" % id,
			float(spec[1]) >= 2.5 and float(spec[1]) <= 3.5 and float(spec[2]) < float(spec[1]), str(spec))
		_check("%s has an entrance function" % id, has_method_in_script("_" + id), "")
		_check("%s has its own entrance sound" % id, ResourceLoader.exists(HeroEntrances.SOUND_DIR + id + ".wav"), "")

	var n := 0
	for id in ids:
		if only != "" and id != only:
			continue
		await _run(id, MAPS[n % MAPS.size()])
		n += 1
	get_tree().paused = false
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func has_method_in_script(m: String) -> bool:
	for d in (load("res://scripts/hero_entrances.gd") as Script).get_script_method_list():
		if d["name"] == m:
			return true
	return false


func _run(id: String, map: String) -> void:
	print("--- %s on %s" % [id, map])
	get_tree().paused = false
	Settings.selected_character = id
	Settings.selected_map = map
	Settings.game_mode = "classic"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	var ab: Abilities = main.abilities
	var em: EnemyManager = main.enemies
	var player: Player = main.player
	player.god_mode = true
	main.xp_next = 1e12
	var landed := [0]
	ab.entrance_landed.connect(func() -> void: landed[0] += 1)
	var target := Vector3(0, SwampWater.height_at(0, 0), 0)
	_check("%s: the run starts with the entrance, the world held still" % id, main.intro and player.meteor_form and main.run_time == 0.0, "intro %s" % main.intro)

	var own := HeroEntrances.has_entrance(id)
	var kit_own := HeroEntrances.last_kind == "kit"   # a kit's own entrance (the Sock's washing machine)
	if id == "thunder_wizard":
		_check("thunder: still the comet orb (kept)", HeroEntrances.last_kind == "comet" and ab._meteors.size() == 1 and not is_instance_valid(ab.entrance), HeroEntrances.last_kind)
	elif id == "fire_wizard":
		_check("fire wizard: still the giant flaming head (kept)", HeroEntrances.last_kind == "giant_head" and ab._meteors.size() == 1, HeroEntrances.last_kind)
	elif kit_own:
		_check("%s: no comet orb, its kit's own entrance" % id, ab._meteors.is_empty() and not is_instance_valid(ab.entrance), HeroEntrances.last_kind)
	else:
		_check("%s: has its own entrance (not the comet)" % id, own, HeroEntrances.last_kind)
		_check("%s: no comet orb, its own entrance (%s)" % [id, HeroEntrances.kind_of(id)],
			HeroEntrances.last_kind == HeroEntrances.kind_of(id) and ab._meteors.is_empty() and is_instance_valid(ab.entrance), HeroEntrances.last_kind)

	# Goblins standing around the spot (the field is empty during the entrance)
	var rows: Array[int] = []
	for k in 6:
		var a := TAU * k / 6.0
		var r := em.spawn(EnemyManager.GRUNT, target + Vector3(cos(a), 0, sin(a)) * 3.5, 100000.0)
		rows.append(r)
	var seen := false
	var frames := 0
	var knocked := 0
	while landed[0] == 0 and frames < 60 * 5:
		await get_tree().physics_frame
		frames += 1
		if own and is_instance_valid(ab.entrance) and player.model.visible and frames < 60 * 3:
			seen = true
		if main.run_time > 0.0 and landed[0] == 0:
			break
		if landed[0] == 0:
			knocked = 0
			for i in rows:
				if em.kb_t[i] > 0.0:
					knocked += 1
	var secs := frames / 60.0
	_check("%s: entrance_landed within 5 s" % id, landed[0] == 1, "%.2f s" % secs)
	if own:
		var spec: Array = HeroEntrances.SPECS[id]
		_check("%s: lands on time (%.1f s)" % [id, float(spec[1])], absf(secs - float(spec[1])) < 0.1, "%.2f s" % secs)
		_check("%s: the hero is seen arriving (not hidden the whole time)" % id, seen, "")
	_check("%s: the world held still until the landing" % id, main.run_time == 0.0 or landed[0] == 1, "t %.2f" % main.run_time)
	var hurt := 0
	for i in rows:
		if em.hp[i] < em.hp_max[i]:
			hurt += 1
	if own:   # (the comet and the giant head keep their old impact)
		_check("%s: the arrival hurts the goblins around the spot" % id, hurt == rows.size(), "%d / %d" % [hurt, rows.size()])
		_check("%s: ...and knocks them back" % id, knocked == rows.size(), "%d / %d" % [knocked, rows.size()])
	await get_tree().physics_frame
	var off := Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length()
	_check("%s: ends standing on the target, visible, the run started" % id,
		off < 0.3 and absf(player.global_position.y - target.y) < 0.6 and player.model.visible and not player.meteor_form and not main.intro,
		"off %.2f dy %.2f visible %s form %s intro %s" % [off, player.global_position.y - target.y, player.model.visible, player.meteor_form, main.intro])
	if own:
		var m: Node3D = player.model
		_check("%s: the model is back to normal (no leftover offset or squash)" % id,
			m.position.length() < 0.01 and absf(m.scale.y - player.size_mult) < 0.25, "pos %s scale %s" % [m.position, m.scale])
		if id == "ghast":
			var opaque := true
			var rh := m as RosterHero
			for k in rh._mats.size():
				if not is_equal_approx(rh._mats[k].albedo_color.a, rh._base_albedo[k].a):
					opaque = false
			_check("ghast: solid again after fading in", opaque, "")
	# Debris lingers a little, then the entrance cleans itself up; it never lands twice
	for f in int(60 * (HeroEntrances.LINGER + 0.5)):
		await get_tree().physics_frame
	_check("%s: landed exactly once" % id, landed[0] == 1, str(landed[0]))
	if own:
		_check("%s: the entrance's props are gone after it" % id, not is_instance_valid(ab.entrance), "")
	_check("%s: the run carries on (clock running)" % id, main.run_time > 2.0 and not main.intro, "t %.2f" % main.run_time)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
