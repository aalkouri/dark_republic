extends Node
## Character bonuses: every character with a roster card has 3 starting stat bonuses with real
## stat names; Gaiden's are crit 6%, move speed x1.2 and jump height x1.6; a run as Gaiden starts
## with them; the jump height multiplier raises the jump apex; bar colours by size (x1.2 red,
## x1.35 yellow, x1.6 green); the character select shows "LVL N" for everyone with a card
## (Ghast, the Pharaoh, the Necromancer included) and the bonuses panel under it.
##   godot --headless --fixed-fps 60 --path . res://tools/test_bonuses.tscn

const CharBonuses := preload("res://scripts/char_bonuses.gd")

var fails := 0


func _ready() -> void:
	Wallet.persist = false
	Wallet.coins = 0
	Wallet.unlocked_chars = []
	Wallet.char_exp = {}
	var base_stats: Dictionary = load("res://scripts/main.gd").BASE_STATS
	_check("jump_height is a base stat (1.0)", is_equal_approx(float(base_stats.get("jump_height", 0.0)), 1.0), "")

	# Data: 3 valid bonuses per card
	var all: Array = load("res://scripts/character_select.gd").load_characters()
	var bad := []
	var cards := 0
	for c in all:
		if c.get("mystery", false):
			if not CharBonuses.of(str(c["id"])).is_empty():
				bad.append(str(c["id"]) + " (mystery with bonuses)")
			continue
		cards += 1
		var list := CharBonuses.of(str(c["id"]))
		var stats_seen := {}
		var ok := list.size() == 3
		for b in list:
			ok = ok and base_stats.has(str(b.get("stat", ""))) and CharBonuses.BASE.has(str(b["stat"])) \
				and str(b.get("mode", "")) in ["mult", "set", "flat"] and CharBonuses.ratio(b) > 1.0
			stats_seen[str(b.get("stat", ""))] = true
		if not ok or stats_seen.size() != 3:
			bad.append(str(c["id"]))
	_check("every roster card (%d) has 3 different valid bonuses" % cards, bad.is_empty() and cards >= 25, str(bad))
	for st in CharBonuses.BASE:
		if not is_equal_approx(float(CharBonuses.BASE[st]), float(base_stats.get(st, -99.0))):
			bad.append(st)
	_check("CharBonuses.BASE matches main.gd's BASE_STATS", bad.is_empty(), str(bad))

	var g := CharBonuses.of("gaiden")
	var gmap := {}
	for b in g:
		gmap[str(b["stat"])] = b
	_check("Gaiden: crit chance 6% (instead of 3%)", gmap.has("crit_chance") and is_equal_approx(float(gmap["crit_chance"]["value"]), 0.06) and gmap["crit_chance"]["mode"] == "set", str(gmap.get("crit_chance")))
	_check("Gaiden: move speed x1.2", gmap.has("move_speed") and is_equal_approx(float(gmap["move_speed"]["value"]), 1.2) and gmap["move_speed"]["mode"] == "mult", "")
	_check("Gaiden: jump height x1.6", gmap.has("jump_height") and is_equal_approx(float(gmap["jump_height"]["value"]), 1.6) and gmap["jump_height"]["mode"] == "mult", "")
	_check("value text: 6%, x1.2, x1.6", CharBonuses.value_text(gmap["crit_chance"]) == "6%" and CharBonuses.value_text(gmap["move_speed"]) == "x1.2" and CharBonuses.value_text(gmap["jump_height"]) == "x1.6",
		"%s %s %s" % [CharBonuses.value_text(gmap["crit_chance"]), CharBonuses.value_text(gmap["move_speed"]), CharBonuses.value_text(gmap["jump_height"])])

	# Tiers and colours
	var m12 := {"stat": "move_speed", "value": 1.2, "mode": "mult"}
	var m135 := {"stat": "area", "value": 1.35, "mode": "mult"}
	var m16 := {"stat": "jump_height", "value": 1.6, "mode": "mult"}
	_check("x1.2 is small: red", CharBonuses.tier(m12) == "small" and CharBonuses.tier_color("small").r > 0.7 and CharBonuses.tier_color("small").g < 0.4, CharBonuses.tier(m12))
	_check("x1.35 is medium: yellow", CharBonuses.tier(m135) == "medium" and CharBonuses.tier_color("medium").r > 0.7 and CharBonuses.tier_color("medium").g > 0.6 and CharBonuses.tier_color("medium").b < 0.4, CharBonuses.tier(m135))
	_check("x1.6 is big: green", CharBonuses.tier(m16) == "big" and CharBonuses.tier_color("big").g > 0.7 and CharBonuses.tier_color("big").r < 0.5, CharBonuses.tier(m16))
	_check("crit 6% vs 3% (x2) is big", CharBonuses.tier(gmap["crit_chance"]) == "big", "%.2f" % CharBonuses.ratio(gmap["crit_chance"]))
	_check("ability cooldown x0.8 counts as a x1.25 boost (small), shown -20%", is_equal_approx(CharBonuses.ratio({"stat": "ability_cdr", "value": 0.8, "mode": "mult"}), 1.25) and CharBonuses.value_text({"stat": "ability_cdr", "value": 0.8, "mode": "mult"}) == "-20%", "")
	_check("flat armor +5 counts as big, +2 small", CharBonuses.tier({"stat": "armor", "value": 5, "mode": "flat"}) == "big" and CharBonuses.tier({"stat": "armor", "value": 2, "mode": "flat"}) == "small", "")
	_check("bar length grows with the boost", CharBonuses.bar_fill(m12) < CharBonuses.bar_fill(m135) and CharBonuses.bar_fill(m135) < CharBonuses.bar_fill(m16) and CharBonuses.bar_fill(gmap["crit_chance"]) >= 0.99, "")

	# A run as Gaiden starts with the bonuses
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	Settings.selected_character = "gaiden"
	Settings.selected_map = "swamp"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	var main: Node = get_tree().current_scene
	var st = main.stats
	_check("run as Gaiden: crit chance 6%", is_equal_approx(st.value("crit_chance"), 0.06), "%.3f" % st.value("crit_chance"))
	_check("run as Gaiden: move speed 1.2x normal", is_equal_approx(st.value("move_speed"), float(base_stats["move_speed"]) * 1.2), "%.2f" % st.value("move_speed"))
	_check("run as Gaiden: jump height 1.6x", is_equal_approx(st.value("jump_height"), 1.6), "%.2f" % st.value("jump_height"))
	var t := 0.0
	while main.intro and t < 15.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	for f in 30:
		await get_tree().process_frame
	_check("the run's crit chance is Gaiden's 6% (headless tests roll no crits, so it's read from the stats)", is_equal_approx(main.stats.value("crit_chance"), 0.06), "%.3f" % main.stats.value("crit_chance"))
	var p: Node = main.player
	p.bot = true
	p.bot_move = Vector2.ZERO
	main.enemies.process_mode = Node.PROCESS_MODE_DISABLED   # nothing knocks us about mid-jump
	var rise16: float = await _jump_rise(p)
	st.apply("jump_height", "mult", 1.0 / 1.6)
	var rise10: float = await _jump_rise(p)
	_check("jump height x1.6 raises the apex 1.6x", rise10 > 0.5 and absf(rise16 / rise10 - 1.6) < 0.12, "%.2f m vs %.2f m (x%.2f)" % [rise16, rise10, rise16 / maxf(0.01, rise10)])
	st.apply("jump_height", "mult", 1.6)

	# Character select: level for every card, bonuses panel under it
	main.to_title()
	await get_tree().scene_changed
	get_tree().change_scene_to_file.call_deferred("res://scenes/character_select.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	var cs: Node = get_tree().current_scene
	for cid in ["ghast", "pharaoh", "necromancer", "singe", "thog", "death"]:
		var k: int = cs.index_of(cid)
		if k < 0:
			_check("%s has a card" % cid, false, "")
			continue
		cs._tiles[k].grab_focus()
		await get_tree().process_frame
		_check("%s (locked) shows LVL 0 top left" % cid, cs._level_box.visible and cs._level_label.text == "LVL 0" and cs._level_label.is_visible_in_tree(), cs._level_label.text)
	for cid in ["gaiden", "ogre", "ghast", "pharaoh", "fire_wizard", "thunder_wizard"]:
		cs._tiles[cs.index_of(cid)].grab_focus()
		await get_tree().process_frame
		await get_tree().process_frame
		var rows: Array = cs._bonus_box.get_children().filter(func(n): return n.has_meta("bonus") and not n.is_queued_for_deletion())
		_check("%s: STARTING BONUSES panel with 3 rows under the level" % cid, cs._bonus_box.is_visible_in_tree() and rows.size() == 3, "%d rows" % rows.size())
		var lb: Rect2 = cs._level_label.get_global_rect()
		var bb: Rect2 = cs._bonus_box.get_global_rect()
		var stage: Control = cs._level_box.get_parent()
		var sr: Rect2 = stage.get_global_rect()
		_check("%s: panel under the level, inside the preview's left side, clear of the name" % cid, bb.position.y > lb.end.y and bb.end.y <= sr.end.y + 1.0 and bb.end.x < sr.position.x + sr.size.x * 0.34 and bb.end.y < cs._name.get_global_rect().position.y,
			"bonus %s, stage %s" % [bb, sr])
	cs._tiles[cs.index_of("gaiden")].grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	var tiers := {}
	for row in cs._bonus_box.get_children():
		if row.has_meta("bonus") and not row.is_queued_for_deletion():
			var bar: ProgressBar = row.get_child(1)
			var nm: String = (row.get_child(0).get_child(0) as Label).text
			tiers[nm] = [str(bar.get_meta("tier")), (bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color, bar.value]
	_check("Gaiden's bars: move speed red, jump height green, crit green", tiers.has("Move Speed") and tiers["Move Speed"][0] == "small" and tiers["Move Speed"][1].is_equal_approx(CharBonuses.tier_color("small"))
		and tiers.has("Jump Height") and tiers["Jump Height"][0] == "big" and tiers["Jump Height"][1].is_equal_approx(CharBonuses.tier_color("big"))
		and tiers.has("Critical Hit Chance") and tiers["Critical Hit Chance"][0] == "big", str(tiers))

	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


## Jump from standing and return how far the feet rose at the apex.
func _jump_rise(p: Node) -> float:
	var t := 0.0
	while not p.is_on_floor() and t < 5.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	for f in 10:
		await get_tree().physics_frame
	var y0: float = p.global_position.y
	var top := y0
	p.bot_jump = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	p.bot_jump = false
	for f in 150:
		await get_tree().physics_frame
		top = maxf(top, p.global_position.y)
		if p.is_on_floor() and f > 10:
			break
	return top - y0


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
