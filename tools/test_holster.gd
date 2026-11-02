extends Node
## Weapons are put away when not in use: every playable character with a weapon carries it on
## its back or belt (RosterWeapons.STOW), draws it to attack or cast, and puts it back after a
## moment. Checks each one at rest, firing, firing again, after the delay, that shots still
## leave from the weapon head, the character select preview, and a real run's opening.
##   godot --headless --path . res://tools/test_holster.tscn

const RIGGED := ["ice_wizard", "thunder_wizard", "dark_wizard", "merlin", "ogre", "vampire_hunter",
	"vicki", "rogue", "gaiden", "dr_croc", "thog"]
const NO_WEAPON := ["ghast", "argyle_sock", "blob", "arachnid"]
var fails := 0
var stage: Node3D


func _ready() -> void:
	Wallet.persist = false
	stage = Node3D.new()
	add_child(stage)
	for id in RIGGED:
		await _rigged(id)
	await _knight()
	await _loco()
	await _wizard()
	for id in NO_WEAPON:
		var h := RosterHero.create(id)
		stage.add_child(h)
		await _frames(2)
		_check("%s: no held weapon to put away (its weapon is its body)" % id, h.weapons.is_empty() and h.stowed.is_empty(), "")
		h.attack(h.global_position + Vector3(0, 1, -5))
		h.free()
	for id in RIGGED:
		await _preview(id)
	await _run_opening()
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _rigged(id: String) -> void:
	print("--- ", id)
	var h := RosterHero.create(id)
	h.position = Vector3(3, 0, 0)
	stage.add_child(h)
	await _frames(3)
	var n := RosterWeapons.count(RosterHero.model_of(id))
	_check("%s: has its weapon(s) in hand and put away (%d)" % [id, n], h.weapons.size() == n and h.stowed.size() == n and n > 0, "%d/%d" % [h.weapons.size(), h.stowed.size()])
	_check("%s: at rest it's put away (hand copy hidden, back/belt copy shown)" % id, _state(h) == "stowed", _state(h))
	# The stowed copy is on the body: near the torso, not in front of the hands
	for w in h.stowed:
		var local := h.global_transform.affine_inverse() * w.global_position
		var scale := float(RosterHero.CFG[id].get("scale", 1.0)) * (2.3 / 1.8 if RosterHero.model_of(id) == "ogre" else 1.0)
		_check("%s: put away on the body (%.2f, %.2f, %.2f)" % [id, local.x, local.y, local.z],
			Vector2(local.x, local.z).length() < 0.6 * scale and local.y > 0.6 * scale and local.y < 1.7 * scale, "")
	var target := h.global_position + Vector3(0, 1, -6)
	var tip := h.attack(target)
	_check("%s: an attack draws it" % id, _state(h) == "drawn", _state(h))
	var head: Vector3 = (h.weapon.get_parent() as Node3D).global_transform * (h._weapon_rest * RosterHero.STAFF_HEAD)
	var hand := h.skeleton.global_transform * h.skeleton.get_bone_global_pose(h.skeleton.find_bone("RightHand")).origin
	_check("%s: the shot leaves from the weapon head (%.2f m from the hand)" % [id, tip.distance_to(hand)],
		tip.distance_to(head) < 0.01 and tip.distance_to(hand) < 1.6 * float(RosterHero.CFG[id].get("scale", 1.0)) * float(RosterHero.CFG[id].get("weapon_scale", 1.0)) * (1.3 if RosterHero.model_of(id) == "ogre" else 1.0), "%.2f" % tip.distance_to(head))
	await _secs(0.06)
	var head2: Vector3 = h.weapon.global_transform * RosterHero.STAFF_HEAD
	_check("%s: ...and the weapon in hand is drawn there (mid-flourish ok)" % id, h.weapon.visible and h.staff_tip().distance_to(head2) < 0.6, "%.2f" % h.staff_tip().distance_to(head2))
	await _secs(0.7)
	h.attack(target)
	await _secs(0.7)
	_check("%s: stays out while attacking again" % id, _state(h) == "drawn", _state(h))
	await _secs(2.6)
	_check("%s: put away again after a pause" % id, _state(h) == "stowed", _state(h))
	h.play_hit()
	await _secs(0.1)
	_check("%s: getting hit doesn't draw it" % id, _state(h) == "stowed", _state(h))
	h.play_ability(1)
	await _secs(0.1)
	_check("%s: a cast draws it" % id, _state(h) == "drawn", _state(h))
	await _secs(4.0)
	_check("%s: ...and puts it back after" % id, _state(h) == "stowed", _state(h))
	h.free()


func _state(h: RosterHero) -> String:
	var hand_on := true
	var hand_off := true
	for w in h.weapons:
		hand_on = hand_on and w.visible
		hand_off = hand_off and not w.visible
	var back_on := true
	var back_off := true
	for w in h.stowed:
		back_on = back_on and w.visible
		back_off = back_off and not w.visible
	if hand_off and back_on and not h.drawn:
		return "stowed"
	if hand_on and back_off and h.drawn:
		return "drawn"
	return "mixed (hand %s, back %s, drawn %s)" % [hand_on, back_on, h.drawn]


func _knight() -> void:
	print("--- toadstool_knight")
	var h := RosterHero.create("toadstool_knight")
	stage.add_child(h)
	await _frames(3)
	var k := h.knight
	_check("Toadstool Knight: sword sheathed at his hip at rest", not h.is_drawn() and not k.model.blade.visible and k.stowed.size() == 1 and k.stowed[0].visible, "")
	var tip := h.attack(h.global_position + Vector3(0, 1, -5))
	_check("...a slash draws it", h.is_drawn() and k.model.blade.visible and not k.stowed[0].visible, "")
	_check("...shots leave from the blade tip", tip.distance_to(k.model.blade.global_transform * Vector3(0, ToadstoolModel.BLADE_TIP, 0)) < 0.01, "")
	await _secs(3.0)
	_check("...sheathed again after", not h.is_drawn() and not k.model.blade.visible and k.stowed[0].visible, "")
	h.free()


func _loco() -> void:
	print("--- loco_robotico")
	var h := RosterHero.create("loco_robotico")
	stage.add_child(h)
	await _frames(3)
	var l := h.loco
	_check("Loco Robotico: maracas tucked in his belt at rest", not h.is_drawn() and not l._hand_maracas[0].visible and l._belt_maracas[0].visible, "")
	var tip := h.attack(h.global_position + Vector3(0, 1, -5))
	_check("...a shake pulls them out", h.is_drawn() and l._hand_maracas[1].visible and not l._belt_maracas[1].visible, "")
	_check("...pulses leave from the maraca", tip.distance_to(l._hand_maracas[l._side].global_transform * Vector3(0, 0.25, 0)) < 0.05, "")
	await _secs(2.5)
	_check("...back in his belt after", not h.is_drawn() and l._belt_maracas[0].visible, "")
	h.free()


func _wizard() -> void:
	print("--- fire_wizard")
	var h := HeroModel.new()
	stage.add_child(h)
	await _frames(3)
	_check("Fire Wizard: staff on his back at rest", not h.drawn and h.staff.get_parent() == h._staff_back, "")
	var tip := h.attack(h.global_position + Vector3(0, 1, -5))
	_check("...a fireball draws it", h.drawn and h.staff.get_parent() == h._staff_hand, "")
	_check("...the fireball leaves from the staff head", tip.distance_to(h.staff.global_transform * HeroModel.TIP) < 0.01, "%.3f" % tip.distance_to(h.staff.global_transform * HeroModel.TIP))
	await _secs(0.5)
	h.attack(h.global_position + Vector3(0, 1, -5))
	await _secs(0.7)
	_check("...stays out while firing", h.drawn, "")
	await _secs(2.0)
	_check("...back on his back after", not h.drawn and h.staff.get_parent() == h._staff_back, "")
	h.play_ability(1)
	await _secs(0.05)
	_check("...casting draws it", h.drawn, "")
	h.free()


func _preview(id: String) -> void:
	var m := RosterModel.create(id)
	stage.add_child(m)
	await _frames(3)
	var ok := not m.is_drawn() and not m.stowed.is_empty()
	for w in m.stowed:
		ok = ok and w.visible
	_check("character select preview: %s relaxed, weapon put away" % id, ok, "")
	m.free()


## A real run: the hero arrives (entrance) with the weapon put away.
func _run_opening() -> void:
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	Settings.selected_character = "vicki"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	await _frames(2)
	var main := get_tree().current_scene
	var h := main.player.model as RosterHero
	_check("in a run: Vicki starts the entrance with her spear on her back", h != null and _state(h) == "stowed", _state(h) if h else "no hero")


func _frames(n: int) -> void:
	for f in n:
		await get_tree().process_frame


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()


func _check(what: String, ok: bool, info: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		fails += 1
		print("FAIL ", what, "  ", info)
