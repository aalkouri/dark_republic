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
	var chars: Array = load("res://scripts/character_select.gd").load_characters()
	_check("25 characters", chars.size() == 25, "%d" % chars.size())
	var names := chars.map(func(c): return c["name"])
	var missing := REQUESTED.filter(func(n): return n not in names)
	_check("all 22 requested characters present", missing.is_empty(), str(missing))
	var ids := {}
	for c in chars:
		ids[c["id"]] = true
	_check("ids unique", ids.size() == chars.size(), "")
	var unlocked := chars.filter(func(c): return c.get("unlocked", false))
	_check("only the Fire Wizard is unlocked", unlocked.size() == 1 and unlocked[0]["id"] == "fire_wizard", str(unlocked.size()))
	var bad := []
	for c in chars:
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
	_check("25 tiles", cs._tiles.size() == 25, "%d" % cs._tiles.size())
	_check("wizard tile focused first", cs._tiles[0].has_focus() and cs._shown == 0, "")
	_check("wizard previews as a live 3D model", cs._view_box.visible and not cs._big_icon.visible
		and cs.find_children("*", "HeroModel", true, false).size() == 1, "")
	var locked_icons := 0
	for t in cs._tiles:
		if (t.get_meta("icon") as CharacterIcon).locked:
			locked_icons += 1
	_check("24 tiles show the padlock", locked_icons == 24, "%d" % locked_icons)
	# Character level: hidden at 0, "lvl N" in the bottom-left when 1+
	Wallet.persist = false
	var lvl0 := cs._tiles[0].get_meta("lvl") as Label
	_check("level 0 shows nothing", not lvl0.visible, lvl0.text)
	Wallet.set_char_level("fire_wizard", 3)
	cs.refresh_levels()
	_check("level 3 shows 'lvl 3'", lvl0.visible and lvl0.text == "lvl 3", lvl0.text)
	_check("label sits in the tile's bottom-left", lvl0.position.x < 20 and lvl0.position.y > cs.TILE * 0.6, str(lvl0.position))
	Wallet.set_char_level("fire_wizard", 0)
	cs.refresh_levels()

	var k: int = cs.index_of("ogre")
	cs._tiles[k].grab_focus()
	await get_tree().process_frame
	_check("focusing a locked character previews its portrait", cs._shown == k and cs._big_icon.visible
		and not cs._view_box.visible and cs._name.text == "Ogre", cs._name.text)
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
		and cs._play_btn.has_focus() and not cs._play_btn.disabled and cs._status.text == "SELECTED", cs._status.text)

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
	get_tree().current_scene._play_btn.pressed.emit()
	await get_tree().scene_changed
	_check("Play starts a run", get_tree().current_scene.name == "Main", get_tree().current_scene.name)

	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
