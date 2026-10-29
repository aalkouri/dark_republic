extends Node
## Character select checks: 25 unique characters (the 20 requested, Kong, Thog plus 3), only the Fire
## Wizard unlocked; every portrait spec uses known parts; the title's Characters button opens
## the screen; locked characters can't be played; Play starts a run as the wizard; Esc/Back
## returns to the title.
##   godot --headless --path . res://tools/test_character_select.tscn

const REQUESTED := ["Ice Wizard", "Merlin", "Thunder Wizard", "Dark Wizard", "Ogre", "Ghast",
	"Vampire Hunter", "Vicki", "The Rogue", "Gaiden", "Dr. Croc", "The Arachnid", "Blob", "Death",
	"Billy Bulldog", "Cowboy", "Loco Robotico", "Singe", "An Argyle Sock", "Sentient Platypus", "Kong", "Thog the Troll"]
const BODIES := ["robe", "bulky", "slim", "coat", "ghost", "spider", "blob", "box", "imp", "sock"]
const HEADS := ["round", "hooded", "ogre", "skull", "croc", "dog", "robot", "platypus", "gorilla", "troll", "none"]
const HATS := ["wizard", "wizard_stars", "wizard_bent", "hood", "tricorn", "winged_helm", "headband",
	"goggles", "collar", "cowboy", "sombrero", "flame_hair", "top_hat", "witch", "mushroom", "none"]
const ITEMS := ["staff_fire", "staff_ice", "staff_wood", "staff_thunder", "staff_dark", "club", "chains",
	"crossbow", "spear", "daggers", "katana", "flask", "web", "scythe", "bone", "revolver", "maracas",
	"ladle", "sword", "none"]
const FX := ["embers", "snow", "stars", "sparks", "shadow", "wisps", "bubbles", "spores", "none"]

var fails := 0


func _ready() -> void:
	Wallet.persist = false
	Wallet.coins = 0
	Wallet.unlocked_chars = []
	Wallet.char_exp = {}
	var all: Array = load("res://scripts/character_select.gd").load_characters()
	_check("30 slots", all.size() == 30, "%d" % all.size())
	var mysteries := all.filter(func(c): return c.get("mystery", false))
	_check("5 mystery slots, no info", mysteries.size() == 5 and mysteries.all(func(c): return c["name"] == "???" and not c.has("bio") and not c.has("price")), "%d" % mysteries.size())
	var chars := all.filter(func(c): return not c.get("mystery", false))
	_check("25 characters", chars.size() == 25, "%d" % chars.size())
	var price_ok := true
	for c in chars:
		var want := 0 if c["id"] == "fire_wizard" else (2000 if c["id"] in ["ice_wizard", "thunder_wizard", "dark_wizard"] else (7000 if c["id"] == "merlin" else 10000))
		price_ok = price_ok and int(c.get("price", 0)) == want
	_check("prices: wizards 2,000, Merlin 7,000, the rest 10,000", price_ok, "")
	var names := chars.map(func(c): return c["name"])
	var missing := REQUESTED.filter(func(n): return n not in names)
	_check("all 22 requested characters present", missing.is_empty(), str(missing))
	var ids := {}
	for c in all:
		ids[c["id"]] = true
	_check("ids unique", ids.size() == all.size(), "")
	var unlocked := chars.filter(func(c): return c.get("unlocked", false))
	_check("only the Fire Wizard is unlocked", unlocked.size() == 1 and unlocked[0]["id"] == "fire_wizard", str(unlocked.size()))
	var bad := []
	for c in chars:   # (mystery slots have no portrait parts)
		var i: Dictionary = c["icon"]
		if i["body"] not in BODIES or i["head"] not in HEADS or i["hat"] not in HATS \
				or i.get("item", "none") not in ITEMS or i.get("fx", "none") not in FX or i["bg"].size() != 2:
			bad.append(c["id"])
	_check("every portrait uses known parts", bad.is_empty(), str(bad))

	# Each portrait draws without errors and differs from the others
	var sigs := {}
	for c in chars:
		var i: Dictionary = c["icon"]
		sigs["%s|%s|%s|%s|%s" % [i["body"], i["head"], i["hat"], i.get("item", ""), i["bg"]]] = true
	_check("portraits are all distinct", sigs.size() == chars.size(), "%d" % sigs.size())

	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	get_tree().change_scene_to_file.call_deferred("res://scenes/title.tscn")
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	var title: Node = get_tree().current_scene
	(title._menu.get_child(1) as Button).pressed.emit()
	await get_tree().scene_changed
	for f in 5:
		await get_tree().process_frame
	var cs: Node = get_tree().current_scene
	_check("Characters opens the select screen", cs.name == "CharacterSelect", cs.name)
	_check("30 tiles", cs._tiles.size() == 30, "%d" % cs._tiles.size())
	_check("wizard tile focused first", cs._tiles[0].has_focus() and cs._shown == 0, "")
	_check("wizard previews as a live 3D model", cs._view_box.visible and not cs._big_icon.visible
		and cs.find_children("*", "HeroModel", true, false).size() == 1, "")
	var locked_icons := 0
	for t in cs._tiles:
		if (t.get_meta("icon") as CharacterIcon).locked:
			locked_icons += 1
	_check("24 tiles show the padlock", locked_icons == 24, "%d" % locked_icons)
	var priced := 0
	for t in cs._tiles:
		if (t.get_meta("price") as Control).visible:
			priced += 1
	_check("24 locked tiles show their price", priced == 24, "%d" % priced)
	_check("menu song keeps playing from the title (no restart)", MenuMusic.player.playing and MenuMusic.player.get_playback_position() > 0.05, "%.2f" % MenuMusic.player.get_playback_position())
	_check("wizard shows 3 ability squares", cs._ability_bar.visible and cs._ability_slots.size() == 3, "")
	cs._on_slot_hover(2, true)
	await get_tree().process_frame
	var tip: String = cs._tooltip_text.text
	_check("hovering an ability explains it with its cooldown", cs._tooltip.visible and "Meteor" in tip and "Cooldown 2 min" in tip and "level 10" in tip, tip.left(80))
	cs._on_slot_hover(2, false)
	await get_tree().process_frame
	_check("tooltip hides when the mouse leaves", not cs._tooltip.visible, "")
	var m: int = cs.index_of("mystery_1")
	cs._tiles[m].grab_focus()
	await get_tree().process_frame
	_check("mystery slots show no ability squares", not cs._ability_bar.visible, "")
	# Every roster character shows its own designed kit: weapon line, three named abilities
	# with glyph icons, and tooltips from data/abilities.json
	var kit_bad: Array = []
	var glyph_names := {}
	for c in cs.characters:
		if c.get("mystery", false) or c["id"] == "fire_wizard":
			continue
		var kk: int = cs.index_of(c["id"])
		cs._tiles[kk].grab_focus()
		await get_tree().process_frame
		var why := ""
		if not cs._ability_bar.visible:
			why = "no bar"
		elif not cs._kit.text.begins_with("Weapon: "):
			why = "weapon: " + cs._kit.text
		for i in 3:
			var sl: AbilitySlot = cs._ability_slots[i]
			if sl.glyph == "" or not (sl.glyph in AbilityGlyphs.NAMES):
				why = "glyph %d '%s'" % [i, sl.glyph]
			glyph_names[sl.glyph] = true
			var nm: String = (cs._ability_names[i] as Label).text
			if nm in ["Inferno", "Fire Nova", "Meteor"] or nm == "":
				why = "name %d" % i
			cs._on_slot_hover(i, true)
			await get_tree().process_frame
			var t: String = cs._tooltip_text.text
			if not (nm in t and "Cooldown" in t and "•" in t and not "{" in t):
				why = "tooltip %d: %s" % [i, t.left(60)]
			if i == 2 and not "ULTIMATE" in t:
				why = "ult tag"
			cs._on_slot_hover(i, false)
		if why != "":
			kit_bad.append("%s (%s)" % [c["id"], why])
	_check("all 24 roster characters show their own kit", kit_bad.is_empty(), str(kit_bad))
	_check("roster kits use a good spread of icons", glyph_names.size() >= 25, "%d" % glyph_names.size())
	cs._tiles[0].grab_focus()
	await get_tree().process_frame
	var tip0: String = cs.ability_tooltip(0, cs._kit_char)
	_check("back on the wizard: his own icons and live tooltips", cs._kit_char == "fire_wizard" and (cs._ability_slots[0] as AbilitySlot).glyph == ""
		and (cs._ability_names[0] as Label).text == "Inferno" and "Inferno" in tip0, cs._kit_char)
	cs._tiles[m].grab_focus()
	await get_tree().process_frame
	_check("mystery: ??? and nothing else", cs._name.text == "???" and cs._bio.text == "" and cs._epithet.text == "" and not cs._status.visible
		and not (cs._tiles[m].get_meta("price") as Control).visible and cs._play_btn.disabled and cs._skills_btn.disabled, cs._name.text)
	# Unlocking with coins
	var iw: int = cs.index_of("ice_wizard")
	cs._tiles[iw].grab_focus()
	await get_tree().process_frame
	_check("locked: Play becomes Unlock, disabled without coins", cs._play_btn.text == "UNLOCK" and cs._play_btn.disabled and "2,000" in cs._status.text, cs._status.text)
	Wallet.coins = 2500
	cs._shown = -1
	cs._show(iw)
	_check("Unlock enabled with enough coins", not cs._play_btn.disabled, "")
	cs._play_btn.pressed.emit()
	await get_tree().process_frame
	_check("unlocking spends the price", Wallet.coins == 500 and Wallet.is_char_unlocked("ice_wizard"), "%d" % Wallet.coins)
	_check("unlocked tile: no padlock or price", not (cs._tiles[iw].get_meta("icon") as CharacterIcon).locked and not (cs._tiles[iw].get_meta("price") as Control).visible, "")
	_check("unlocked Ice Wizard is playable: Skills and Play", not cs._skills_btn.disabled and not cs._play_btn.disabled and "playable soon" not in cs._status.text, cs._status.text)
	_check("unlock count updates", cs._count_label.text == "2 of 30 unlocked", cs._count_label.text)
	var mi: int = cs.index_of("merlin")
	Wallet.unlocked_chars.append("merlin")
	cs._shown = -1
	cs._show(mi)
	_check("unlocked Merlin: Skills open, Play waits for his kit", not cs._skills_btn.disabled and cs._play_btn.disabled and "playable soon" in cs._status.text, cs._status.text)
	Wallet.unlocked_chars.erase("merlin")
	Wallet.unlocked_chars = []
	Wallet.coins = 0
	cs.refresh_levels()
	# Character level: hidden at 0, "lvl N" in the bottom-left when 1+
	Wallet.persist = false
	var lvl0 := cs._tiles[0].get_meta("lvl") as Label
	_check("level 0 shows nothing", not lvl0.visible, lvl0.text)
	Wallet.set_char_exp("fire_wizard", 50000)   # lvl 3
	cs.refresh_levels()
	_check("level 3 shows 'lvl 3'", lvl0.visible and lvl0.text == "lvl 3", lvl0.text)
	_check("label sits in the tile's bottom-left", lvl0.position.x < 20 and lvl0.position.y > cs.TILE * 0.6, str(lvl0.position))
	Wallet.set_char_exp("fire_wizard", 0)
	cs.refresh_levels()

	var og: int = cs.index_of("ogre")
	cs._tiles[og].grab_focus()
	await get_tree().process_frame
	_check("a locked character with a model previews in 3D", cs._view_box.visible and not cs._big_icon.visible
		and cs._previews.has("ogre") and (cs._previews["ogre"] as Node3D).visible and not cs._hero_preview.visible, "")
	var k: int = cs.index_of("death")
	cs._tiles[k].grab_focus()
	await get_tree().process_frame
	_check("a locked character without a model shows its portrait", cs._shown == k and cs._big_icon.visible
		and not cs._view_box.visible and cs._name.text == "Death", cs._name.text)
	_check("Play disabled for locked characters", cs._play_btn.disabled, "")
	cs._tiles[k].pressed.emit()
	await get_tree().process_frame
	_check("choosing a locked character doesn't select it", Settings.selected_character == "fire_wizard", Settings.selected_character)
	cs._play()
	await get_tree().create_timer(0.7).timeout
	_check("Play does nothing while a locked character is shown", get_tree().current_scene == cs, "")

	cs._tiles[0].pressed.emit()
	await get_tree().process_frame
	_check("choosing the wizard selects him and moves focus to Play", Settings.selected_character == "fire_wizard"
		and cs._play_btn.has_focus() and not cs._play_btn.disabled and cs._status.text.begins_with("SELECTED"), cs._status.text)

	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await get_tree().scene_changed
	_check("Esc goes back to the title", get_tree().current_scene.name == "Title", get_tree().current_scene.name)

	for f in 3:
		await get_tree().process_frame
	(get_tree().current_scene._menu.get_child(1) as Button).pressed.emit()
	await get_tree().scene_changed
	for f in 3:
		await get_tree().process_frame
	var cs2 = get_tree().current_scene
	cs2._play_btn.pressed.emit()
	await get_tree().process_frame
	_check("Play asks which map", cs2._picker != null and cs2._picker.visible, "")
	cs2._picker.choose("forest")
	await get_tree().scene_changed
	_check("Play starts a run on the chosen map", get_tree().current_scene.name == "Main" and Settings.selected_map == "forest"
		and get_tree().current_scene.find_children("*", "BushField", true, false).size() == 1, get_tree().current_scene.name)
	Settings.selected_map = "swamp"

	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
