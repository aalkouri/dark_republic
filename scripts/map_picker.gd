class_name MapPicker
extends Control
## "Choose your battleground": shown after Play (title screen and character select). One card
## per map with a preview picture (a card can be marked "locked": true for a map not built yet). The choice is
## kept (Settings.selected_map), so Restart and the next Play default to it. Esc goes back.

signal chosen(map: String)
signal cancelled

const MAPS := [
	{"id": "swamp", "name": "The Swamp", "blurb": "Fog, cypress trees and stinking pools.", "image": "res://images/maps/swamp.png"},
	{"id": "forest", "name": "Magical Forest", "blurb": "Neon trees, glowing ponds and bushes that rustle.", "image": "res://images/maps/forest.png"},
	{"id": "castle", "name": "The Castle", "blurb": "Torch-lit halls, a feast to trample, skeletons.", "image": "res://images/maps/castle.png"},
]

var _font: Font
var _cards: Array[Button] = []


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
	# Focus the saved choice
	for c in _cards:
		if c.get_meta("id") == Settings.selected_map:
			c.grab_focus.call_deferred()


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
	var locked: bool = m.get("locked", false)
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
	if locked:   # a dark card with a padlock-ish "?"
		var q := _label("?", 120, Color(0.5, 0.45, 0.4, 0.8))
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.position = Vector2(0, 20)
		q.size = Vector2(352, 198)
		pic.add_child(q)
	var name := _label(str(m["name"]).to_upper(), 26, Color(0.95, 0.88, 0.75) if not locked else Color(0.6, 0.55, 0.5))
	v.add_child(name)
	var blurb := _label(m["blurb"], 17, Color(0.82, 0.76, 0.68) if not locked else Color(0.55, 0.5, 0.46))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(blurb)
	b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
	b.pressed.connect(func(): choose(m["id"]))
	_cards.append(b)
	return b


func choose(id: String) -> void:
	for m in MAPS:
		if m["id"] == id and not m.get("locked", false):
			Settings.selected_map = id
			chosen.emit(id)
			return   # unknown and locked maps are ignored


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
