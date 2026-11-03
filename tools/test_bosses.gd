extends Node
## The Forest's Toadstool Knight and the Castle's Arachnid (MapBoss):
##   - each arrives at 8:00 on its map as a giant with a HUD health bar;
##   - every attack is marked on the ground first and only hurts once its marker has filled,
##     never in under MapBoss.MIN_WARN seconds (enraged too), and stepping out of it dodges it;
##   - the Knight's slash, fairy ring, spore mortar (lobbed pods) and Fungus Court;
##   - the Arachnid climbs a wall of your room, scuttles along it out of contact range while
##     her hitbox still reaches her, shoots webs / venom, then comes down with a marked drop
##     and spiderlings; her lunge is a marked lane;
##   - killing them opens the portal and stepping through wins the run; the Knight unlocks the
##     Castle and himself, the Arachnid herself.
## Also: Thog's enraged wind-ups respect MIN_WARN.
##   godot --headless --path . res://tools/test_bosses.tscn

var fails := 0
var main: Node


func _ready() -> void:
	Wallet.persist = false
	Wallet.bosses_defeated = ["thog"]
	_check("the Castle is locked until the Toadstool Knight falls", MapPicker.lock_reason("castle", "fire_wizard") != "", MapPicker.lock_reason("castle", "fire_wizard"))
	_check("the Knight can't fight in the Forest, the Arachnid not in the Castle", MapPicker.lock_reason("forest", "toadstool_knight") != "" and MapPicker.lock_reason("castle", "arachnid") != "", "")
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	await _forest()
	await _castle()
	await _thog_min_warn()
	_finish()


# ------------------------------------------------------------------ the Toadstool Knight

func _forest() -> void:
	await _load("forest")
	var em: EnemyManager = main.enemies
	var player: Player = main.player
	main.run_time = main.THOG_TIME + 0.1
	await _secs(0.3)
	var boss = main.map_boss
	_check("Forest: the Toadstool Knight arrives at 8:00", boss is ToadstoolBoss and boss.row() >= 0 and em.typ[boss.row()] == EnemyManager.TROLL, "")
	if not (boss is ToadstoolBoss):
		return
	var k: ToadstoolBoss = boss
	_check("he's about 6 m tall with a HUD bar", k.model.scale.x * ToadstoolModel.MODEL_HEIGHT >= 5.5 and k._bar != null and k._bar_label.text.begins_with("THE TOADSTOOL KNIGHT"), k._bar_label.text)
	_check("he has a boss's health", em.hp_max[k.row()] >= ToadstoolBoss.HP * 5.0, str(em.hp_max[k.row()]))
	k._court_cd = 999.0
	k._ring_cd = 999.0
	k._mortar_cd = 999.0
	# Slash: marked wedge; standing in it, the hit only lands when the marker fills
	await _until_free(k)
	_stand(k, 6.0, 0.0)
	var hits0: int = k.counts["hits"]
	var warned0: int = k.counts["warned"]
	k._gap = 0.0
	k._start("slash")
	var w: Dictionary = k._warns[-1] if not k._warns.is_empty() else {}
	_check("slash: a wedge is marked on the ground first", k.counts["warned"] == warned0 + 1 and not w.is_empty(), "")
	_check("...with at least %.1f s to react" % MapBoss.MIN_WARN, not w.is_empty() and w["time"] >= MapBoss.MIN_WARN, str(w.get("time", 0.0)))
	await _secs(0.5)
	_check("...no damage before it fills", k.counts["hits"] == hits0, "")
	await _secs(1.4)
	_check("...then the cut lands on whoever's still in it", k.counts["hits"] == hits0 + 1, str(k.counts["hits"]))
	_check("...and leaves a spore cloud", k._hazards.size() >= 1, "")
	# Dodge: step out of the marked wedge in time
	await _until_free(k)
	_stand(k, 6.0, 0.0)
	hits0 = k.counts["hits"]
	k._start("slash")
	await _secs(0.3)
	_stand(k, 7.0, PI)   # behind him
	await _secs(1.6)
	_check("stepping out of the marker dodges it", k.counts["hits"] == hits0, str(k.counts["hits"] - hits0))
	# Fairy ring around you
	await _until_free(k)
	k._start("ring")
	_check("fairy ring: a ring band is marked around you", k._warns.size() >= 1, "")
	# Spore mortar: lobbed pods, each with its own marker that fills as it flies
	await _until_free(k)
	_stand(k, 20.0, 0.0)
	warned0 = k.counts["warned"]
	k._start("mortar")
	await _secs(0.7)
	_check("spore mortar: 5 pods lobbed, each landing on a marked circle", k._lobs.size() >= 5 and k.counts["warned"] - warned0 >= 5, "%d lobs, %d marks" % [k._lobs.size(), k.counts["warned"] - warned0])
	# Fungus Court
	await _until_free(k)
	k._start("court")
	await _secs(2.0)
	_check("Fungus Court: three guardians rise at marked spots", k._guardians.size() == 3, str(k._guardians.size()))
	await _secs(3.0)
	_check("...and slam around themselves (marked)", k.counts["warned"] - warned0 >= 9, str(k.counts["warned"] - warned0))
	# Enraged: faster, but never less than MIN_WARN of warning
	_check("he enrages after 3 minutes and keeps the goblins to 90 while he's up", k.enrage_after == 180.0 and not k.is_enraged and main._live_cap() == 90, "%.0f s, cap %d" % [k.enrage_after, main._live_cap()])
	k.alive_time = k.enrage_after
	await _secs(0.2)
	_check("...and then he's enraged", k.is_enraged and "ENRAGED" in k._bar_label.text, k._bar_label.text)
	_check("enraged warnings are shorter but never under %.1f s" % MapBoss.MIN_WARN, k.warn_time(ToadstoolBoss.SLASH_WARN) < ToadstoolBoss.SLASH_WARN and k.warn_time(0.5) >= MapBoss.MIN_WARN, "%.2f" % k.warn_time(ToadstoolBoss.SLASH_WARN))
	# Kill him
	em.damage(k.row(), 1e9)
	await _secs(4.8)
	_check("killing him doesn't end the run: a portal opens instead", main.state != "won" and main.boss_down, main.state)
	await _through_portal()
	_check("stepping through the portal wins the run", main.state == "won" and main.boss_won, main.state)
	_check("the end screen names him", main.hud.end_title.text == "YOU WON!", main.hud.end_title.text)
	_check("the Castle unlocks", Wallet.has_defeated("toadstool_knight") and MapPicker.lock_reason("castle", "fire_wizard") == "", "")
	var names := []
	for c in main.hud.unlock_cards:
		names.append(str((c as Control).get_meta("name", "")))
	_check("the end screen lists the Castle and the Toadstool Knight", main.hud.unlock_cards.size() == 2, str(names))
	get_tree().paused = false


# ------------------------------------------------------------------ the Arachnid

func _castle() -> void:
	await _load("castle")
	var em: EnemyManager = main.enemies
	main._next_swarm = 1e9   # no bomber waves knocking you about during these checks
	main.run_time = main.THOG_TIME + 0.1
	await _secs(0.3)
	var boss = main.map_boss
	_check("Castle: the Arachnid arrives at 8:00", boss is ArachnidBoss and boss.row() >= 0, "")
	if not (boss is ArachnidBoss):
		return
	var a: ArachnidBoss = boss
	_check("she's huge (about 10 m across)", a.model.scale.x * 6.0 >= 9.5, "")
	# Lunge: a marked lane, then the dash
	await _until_free(a)
	a._climb_cd = 999.0
	a._brood_cd = 999.0
	_stand(a, 7.0, 0.0)
	var hits0: int = a.counts["hits"]
	a._start("lunge")
	_check("lunge: a lane is marked first", a._warns.size() >= 1 and a._warns[-1]["time"] >= MapBoss.MIN_WARN, "")
	await _secs(0.6)
	_check("...no bite before it fills", a.counts["hits"] == hits0, "")
	await _secs(1.4)
	_check("...then she dashes down it", a.counts["hits"] == hits0 + 1, str(a.counts["hits"] - hits0))
	# Climbing
	await _until_free(a)
	_stand(a, 14.0, 0.0)
	a._climb_cd = 0.0
	a._gap = 0.0
	await _secs(0.2)
	_check("she leaps for a wall of your room", a.attack in ["leap", "climb"], a.attack)
	for f in 60 * 6:
		await get_tree().physics_frame
		if a.surface == "wall":
			break
	_check("...and climbs it", a.surface == "wall", a.surface + " / " + a.attack)
	if a.surface == "wall":
		var n: Vector3 = a._face["n"]
		var up := a.model.global_transform.basis.y.normalized()
		_check("on the wall: high up, belly to the wall", a.model.global_position.y >= 10.0 and up.dot(n) > 0.9, "y %.1f, up·n %.2f" % [a.model.global_position.y, up.dot(n)])
		_check("...touching her can't hurt you up there, but shots still reach her", not em.boss_contact and em.t_height[EnemyManager.TROLL] >= a.model.global_position.y, "height %.1f" % em.t_height[EnemyManager.TROLL])
		var warned0: int = a.counts["warned"]
		await _secs(2.6)
		_check("...and she rains webs or venom down (marked)", a.counts["warned"] > warned0, str(a.counts["warned"] - warned0))
		# Time's up on the wall: ceiling and/or a marked drop
		a._phase_t = 0.0
		var saw_drop_mark := false
		var runners0 := _count_type(em, EnemyManager.RUNNER)
		for f in 60 * 9:
			await get_tree().physics_frame
			if a.attack == "drop" and not a._warns.is_empty():
				saw_drop_mark = true
			if a.surface == "floor":
				break
		_check("she comes back down with a marked drop", saw_drop_mark and a.surface == "floor" and em.boss_contact, a.surface)
		_check("...and spiderlings scatter from it", _count_type(em, EnemyManager.RUNNER) > runners0, "")
	# Webs: she always leaves a trail on the floor; stepping in one webs you
	var webs: SpiderWebs = a.webs
	await _until_free(a)
	for f in 60 * 3:
		await get_tree().physics_frame
		if not webs.trail.is_empty():
			break
	_check("she leaves a trail of webs as she walks", not webs.trail.is_empty(), str(webs.trail.size()))
	if not webs.trail.is_empty():
		var tw: Dictionary = webs.trail[-1]
		var at: Vector3 = tw["at"]
		_check("...that fade after about 3 s", SpiderWebs.TRAIL_LIFE <= 3.5, "")
		var pl: Player = main.player
		pl.web_t = 0.0
		pl.slow_t = 0.0
		a._gap = 99.0
		pl.global_position = Vector3(at.x, SwampWater.height_at(at.x, at.z) + 0.3, at.z)
		pl.velocity = Vector3.ZERO
		await _secs(0.2)
		_check("standing in a web: half speed and no jumping", pl.web_t > 3.5 and pl.slow_t > 3.5 and pl.slow_f <= SpiderWebs.SLOW + 0.001, "web %.1f slow %.1f x%.2f" % [pl.web_t, pl.slow_t, pl.slow_f])
		var y0 := pl.global_position.y
		pl.bot_jump = true
		await _secs(0.3)
		pl.bot_jump = false
		_check("...you can't jump out", pl.global_position.y < y0 + 0.4, "rose %.2f" % (pl.global_position.y - y0))
	# The web swath (her ultimate) at 75% health: one half of the keep
	await _until_free(a)
	a._climb_cd = 999.0
	var sw0 := webs.swath_count
	em.hp[a.row()] = em.hp_max[a.row()] * 0.74
	for f in 60 * 4:
		await get_tree().physics_frame
		if webs.swath_count > sw0:
			break
	_check("at 75% health her web swath covers half the keep", webs.swath_count == sw0 + 1 and not webs.swaths.is_empty(), "")
	if not webs.swaths.is_empty():
		var half: String = webs.swaths[-1]["half"]
		await _secs(SpiderWebs.SPREAD + 0.2)
		var inside := {"west": Vector3(-60, 0, 0), "east": Vector3(60, 0, 0), "north": Vector3(0, 0, -60), "south": Vector3(0, 0, 60)}
		var opposite := {"west": "east", "east": "west", "north": "south", "south": "north"}
		_check("...webbing anywhere on that side", webs.in_web(inside[half] + Vector3(37, 0, 41) * (0.0 if half in ["west", "east"] else 0.0)), half)
		var far: Vector3 = inside[opposite[half]]
		var trail_near := false
		for w in webs.trail:
			if Vector2((w["at"] as Vector3).x - far.x, (w["at"] as Vector3).z - far.z).length() < 4.0:
				trail_near = true
		_check("...but not the other side", trail_near or not webs.in_web(far), "")
		_check("...for a minute", SpiderWebs.SWATH_LIFE == 60.0, "")
	# Kill her
	em.damage(a.row(), 1e9)
	await _secs(4.8)
	_check("killing her doesn't end the run: a portal opens instead", main.state != "won" and main.boss_down, main.state)
	await _through_portal()
	_check("stepping through the portal wins the run", main.state == "won", main.state)
	_check("...and makes her playable", Wallet.has_defeated("arachnid"), "")
	get_tree().paused = false


func _thog_min_warn() -> void:
	await _load("swamp")
	main.run_time = main.THOG_TIME + 0.1
	await _secs(0.3)
	var t: ThogBoss = main.thog
	if t == null:
		_check("Thog arrives", false, "")
		return
	t.alive_time = ThogBoss.ENRAGE_AFTER
	await _secs(0.1)
	t._start("slam")
	_check("Thog enraged: his slam still gives %.1f s of warning" % MapBoss.MIN_WARN, t._windup >= MapBoss.MIN_WARN - 0.001, "%.2f" % t._windup)


# ------------------------------------------------------------------ helpers

func _load(map: String) -> void:
	get_tree().paused = false
	Settings.selected_map = map
	Settings.selected_character = "fire_wizard"
	Settings.game_mode = "classic"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	for f in 60 * 15:   # the entrance (meteor / castle doors)
		await get_tree().physics_frame
		if not main.intro:
			break
	main.player.god_mode = true


## Put the player `d` m from the boss, `ang` radians round from where it's aiming.
func _stand(b: MapBoss, d: float, ang: float) -> void:
	var i := b.row()
	var c: Vector3 = main.enemies.pos[i]
	var aim: Vector3 = b._aim if "_aim" in b else Vector3.FORWARD
	var dir := aim.rotated(Vector3.UP, ang) if aim.length() > 0.1 else Vector3.FORWARD
	var p := c + dir * d
	if CastleNav.current != null and CastleNav.current.is_blocked(p.x, p.z):
		p = c - dir * d
	main.player.global_position = Vector3(p.x, SwampWater.height_at(p.x, p.z) + 0.5, p.z)
	main.player.velocity = Vector3.ZERO


func _until_free(b: MapBoss) -> void:
	for f in 60 * 6:
		if b.state == "walk" and b._warns.is_empty():
			return
		await get_tree().physics_frame


func _secs(s: float) -> void:
	for f in int(s * 60):
		await get_tree().physics_frame


func _count_type(em: EnemyManager, t: int) -> int:
	var n := 0
	for k in em.count:
		if em.typ[k] == t and not em.dead[k]:
			n += 1
	return n


## The boss is down: the run goes on until you step through the portal that opens (level-ups
## from his XP are taken as they come). Returns once the end screen is up (or after 15 s).
func _through_portal() -> void:
	for f in 60 * 15:
		await get_tree().physics_frame
		if main.state == "levelup":
			main.choose_upgrade(0)
		var pt: BossPortal = main.aftermath.portal
		if pt != null and pt.is_open() and main.state == "playing" and not main.aftermath.entering:
			main.player.global_position = pt.global_position + Vector3(0, 0.4, 0)
			main.player.velocity = Vector3.ZERO
		if main.state == "won":
			return


func _finish() -> void:
	get_tree().paused = false
	Settings.selected_map = "swamp"
	Wallet.bosses_defeated = []
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		fails += 1
