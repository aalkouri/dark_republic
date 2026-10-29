class_name MapPicker
extends Control
## "Choose your battleground": shown after Play (title screen and character select). One card
## per map with a preview picture. The Forest and the Castle are locked until Thog the Troll, the
## Swamp's boss, has been beaten ("requires"); a character can be barred from a map ("banned_maps"
## in data/characters.json: Thog can't fight in the Swamp, he's its boss). The choice is
## kept (Settings.selected_map), so Restart and the next Play default to it. Esc goes back.
##
## Locked cards are darkened with a big padlock on the picture. The first time the picker is
## opened after a map is unlocked, that card still starts locked; then its padlock rattles,
## the shackle springs open and the lock drops off the bottom of the screen, the picture
## brightens and the card becomes selectable (Wallet.seen_unlocks remembers it's been shown).

signal chosen(map: String)
signal cancelled

const MAPS := [
	{"id": "swamp", "name": "The Swamp", "blurb": "Fog, cypress trees and stinking pools.", "image": "res://images/maps/swamp.png"},
	# The Castle will need the Forest's boss once it has one; until then Thog opens both.
	{"id": "forest", "name": "Magical Forest", "blurb": "Neon trees, glowing ponds and bushes that rustle.", "image": "res://images/maps/forest.png", "requires": "thog"},
	{"id": "castle", "name": "The Castle", "blurb": "Torch-lit halls, a feast to trample, skeletons.", "image": "res://images/maps/castle.png", "requires": "toadstool_knight"},
]

const BOSS_NAMES := {"thog": "Thog the Troll in the Swamp", "toadstool_knight": "the Toadstool Knight in the Magical Forest", "arachnid": "the Arachnid in the Castle"}

var _font: Font
static var _banned := {}   # character id -> maps it can't play (from data/characters.json)
var _cards: Array[Button] = []
var _reveal: Array[Button] = []   # newly unlocked cards still to play their padlock drop
var revealing := false


static func create(font: Font) -> MapPicker:
	var m := MapPicker.new()
	m._font = font
	return m


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 26)
	center.add_child(v)
	var title := _label("CHOOSE YOUR BATTLEGROUND", 44, Color(1.0, 0.7, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	v.add_child(row)
	for m in MAPS:
		row.add_child(_card(m))
	var hint := _label("Enter: choose   ·   Esc: back", 18, Color(0.8, 0.75, 0.68, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	# Focus the saved choice (or the first open map)
	var focus: Button = null
	for c in _cards:
		if not c.disabled and (focus == null or c.get_meta("id") == Settings.selected_map):
			focus = c
	if focus:
		focus.grab_focus.call_deferred()
	if not _reveal.is_empty():
		revealing = true
		for k in _reveal.size():
			Wallet.mark_unlock_seen("map:" + str(_reveal[k].get_meta("id")))
			get_tree().create_timer(0.7 + k * 0.75, true).timeout.connect(_unlock_card.bind(_reveal[k], k == _reveal.size() - 1))


## Why `map` can't be played right now with `char_id`, or "" if it can.
static func lock_reason(map: String, char_id: String = "") -> String:
	if char_id == "":
		char_id = Settings.selected_character
	for m in MAPS:
		if m["id"] != map:
			continue
		var boss: String = m.get("requires", "")
		if boss != "" and not Wallet.has_defeated(boss):
			return I18n.f("Defeat %s to unlock", I18n.t(BOSS_NAMES.get(boss, boss)))
		if map in banned_maps(char_id):
			return I18n.f("%s can't fight here: it's home turf", _char_name(char_id))
		return ""
	return "Unknown map"


static func banned_maps(char_id: String) -> Array:
	if _banned.is_empty():
		var f := FileAccess.open("res://data/characters.json", FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text()) if f else null
		_banned["_loaded"] = []
		if data is Dictionary:
			for c in data.get("characters", []):
				_banned[c["id"]] = c.get("banned_maps", [])
				_banned["name:" + str(c["id"])] = c.get("name", c["id"])
	return _banned.get(char_id, [])


static func _char_name(char_id: String) -> String:
	banned_maps(char_id)
	return TranslationServer.translate(str(_banned.get("name:" + char_id, char_id))).split(" ")[0]


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _card(m: Dictionary) -> Button:
	var reason := lock_reason(m["id"])
	# Unlocked since the picker was last seen: starts locked and plays the padlock drop
	var fresh: bool = reason == "" and m.get("requires", "") != "" and not Wallet.unlock_seen("map:" + str(m["id"]))
	if fresh:
		reason = tr("Defeat %s to unlock") % tr(BOSS_NAMES.get(m["requires"], m["requires"]))
	var locked := reason != ""
	var b := Button.new()
	b.custom_minimum_size = Vector2(380, 330)
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = locked
	b.set_meta("id", m["id"])
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.07, 0.05, 0.05, 0.95)
	normal.border_color = Color(0.4, 0.32, 0.26, 0.9)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(12)
	var hot := normal.duplicate() as StyleBoxFlat
	hot.border_color = Color(1.0, 0.6, 0.2)
	hot.set_border_width_all(4)
	hot.shadow_color = Color(1.0, 0.45, 0.1, 0.35)
	hot.shadow_size = 14
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("disabled", normal)
	for st in ["hover", "focus", "pressed"]:
		b.add_theme_stylebox_override(st, hot)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_right = -14
	v.offset_top = 14
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(352, 198)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img: String = m["image"]
	if img != "" and ResourceLoader.exists(img):
		pic.texture = load(img)
	v.add_child(pic)
	if locked:   # the picture darkened, with a padlock on it
		pic.modulate = Color(0.32, 0.3, 0.3)
		var lock := Padlock.new()
		lock.size = Vector2(96, 120)
		lock.position = Vector2(14, 14) + Vector2(352 - 96, 198 - 120) * 0.5 + Vector2(0, 6)   # over the picture (not dimmed with it)
		lock.pivot_offset = Vector2(48, 30)   # hangs from the shackle when it rattles
		b.set_meta("lock", lock)
		b.add_child(lock)   # after the picture and text, so it draws on top, undimmed
	var name := _label(tr(str(m["name"])).to_upper(), 26, Color(0.95, 0.88, 0.75) if not locked else Color(0.6, 0.55, 0.5))
	v.add_child(name)
	var blurb := _label(tr(m["blurb"]) if not locked else reason + ".", 17, Color(0.82, 0.76, 0.68) if not locked else Color(1.0, 0.55, 0.4))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(blurb)
	b.set_meta("pic", pic)
	b.set_meta("name", name)
	b.set_meta("blurb", blurb)
	b.set_meta("blurb_text", m["blurb"])
	if fresh:
		_reveal.append(b)
	b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
	b.pressed.connect(func(): choose(m["id"]))
	_cards.append(b)
	return b


## The padlock drop: rattle, shackle springs open, the lock falls off the bottom of the screen
## while the card lights up and becomes selectable.
func _unlock_card(b: Button, last: bool) -> void:
	if not is_instance_valid(b) or not b.has_meta("lock"):
		return
	var lock: Padlock = b.get_meta("lock")
	var pic: Control = b.get_meta("pic")
	var tw := create_tween()
	for k in 6:   # rattle
		tw.tween_property(lock, "rotation", (0.22 if k % 2 == 0 else -0.22) * (1.0 - k / 6.0), 0.05)
	tw.tween_property(lock, "rotation", 0.0, 0.05)
	tw.tween_property(lock, "open", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.15)
	tw.tween_callback(func():
		# Off the card and onto the whole screen, so it can fall past the card's edge
		var gp := lock.global_position
		lock.reparent(self)
		lock.global_position = gp
		lock.z_index = 10
		var y0 := lock.position.y
		var x0 := lock.position.x
		var drift := randf_range(-60.0, 60.0)
		var spin := randf_range(1.5, 3.0) * (1.0 if randf() < 0.5 else -1.0)
		var fall := create_tween()
		fall.tween_method(func(t: float):
			lock.position = Vector2(x0 + drift * t, y0 - 120.0 * t + 1500.0 * t * t)
			lock.rotation = spin * t, 0.0, 1.0, 1.1)
		fall.tween_callback(lock.queue_free)
		# The card lights up
		var light := create_tween().set_parallel(true)
		light.tween_property(pic, "modulate", Color(1.5, 1.4, 1.2), 0.15)
		light.chain().tween_property(pic, "modulate", Color.WHITE, 0.5)
		var name: Label = b.get_meta("name")
		name.add_theme_color_override("font_color", Color(0.95, 0.88, 0.75))
		var blurb: Label = b.get_meta("blurb")
		blurb.text = b.get_meta("blurb_text")
		blurb.add_theme_color_override("font_color", Color(0.82, 0.76, 0.68))
		b.remove_meta("lock")
		b.disabled = false
		b.pivot_offset = b.size * 0.5
		var pop := create_tween()
		pop.tween_property(b, "scale", Vector2.ONE * 1.06, 0.1)
		pop.tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if last:
			revealing = false
			b.grab_focus())


func choose(id: String) -> void:
	for m in MAPS:
		if m["id"] == id and lock_reason(id) == "":
			Settings.selected_map = id
			chosen.emit(id)
			return   # unknown and locked maps are ignored


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()


## A chunky gold padlock drawn in code. `open` 0..1 springs the shackle up and swings it aside.
class Padlock extends Control:
	var open := 0.0:
		set(v):
			open = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var body := Rect2(w * 0.08, h * 0.42, w * 0.84, h * 0.56)
		# Shackle: a thick arc over the body; opening lifts it and swings it about its left leg
		var lift := open * h * 0.14
		var cx := w * 0.5
		var r := w * 0.28
		var base_y := body.position.y + 4.0
		var pts := PackedVector2Array()
		var left := Vector2(cx - r, base_y)
		for k in 25:
			var a := PI + PI * k / 24.0
			var p := Vector2(cx + cos(a) * r, base_y - h * 0.08 + sin(a) * r * 1.15)
			if k == 0:
				pts.append(Vector2(cx - r, base_y))
			pts.append(p)
		pts.append(Vector2(cx + r, base_y))
		var swing := -open * 0.9
		for i in pts.size():
			var q := pts[i] - left
			pts[i] = left + q.rotated(swing) + Vector2(0, -lift)
		draw_polyline(pts, Color(0.25, 0.2, 0.12), 15.0, true)
		draw_polyline(pts, Color(0.78, 0.74, 0.68), 10.0, true)
		draw_polyline(pts, Color(0.95, 0.93, 0.88, 0.6), 3.0, true)
		# Body: gold with a darker rim, a shine and a keyhole
		var rim := Rect2(body.position - Vector2(3, 3), body.size + Vector2(6, 6))
		draw_rect(rim, Color(0.35, 0.22, 0.05), true)
		draw_rect(body, Color(0.93, 0.7, 0.2), true)
		draw_rect(Rect2(body.position, Vector2(body.size.x, body.size.y * 0.22)), Color(1.0, 0.86, 0.45), true)
		var kc := body.get_center() + Vector2(0, -4)
		draw_circle(kc, w * 0.075, Color(0.18, 0.1, 0.02))
		draw_colored_polygon(PackedVector2Array([kc + Vector2(-w * 0.04, 0), kc + Vector2(w * 0.04, 0), kc + Vector2(w * 0.06, h * 0.17), kc + Vector2(-w * 0.06, h * 0.17)]), Color(0.18, 0.1, 0.02))
