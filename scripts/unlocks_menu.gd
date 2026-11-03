class_name UnlocksMenu
extends Control
## The title's Unlocks menu: permanent upgrades bought with coins (Unlocks: Map, Free Ban,
## Reroll) and a catalogue of everything there is (weapons, tomes, items, maps), each a square.
## Hovering a square explains it. Upgrades: click to buy the next level (cost under it, level
## pips). Catalogue squares stay dark with a "?" until found in a run (maps: until their boss
## falls). Anything found through play has a red dot on its square and on its tab until you
## hover it (Wallet.new_marks). On its own layer under the coin counter, so your coins show.

signal closed

const TABS := [["upgrades", "Upgrades"], ["weapon", "Weapons"], ["tome", "Tomes"], ["item", "Items"], ["map", "Maps"]]
const SQ := 112.0
const DOT := Color(1.0, 0.22, 0.2)

var tab := "upgrades"
var _db: UpgradeDB
var _tab_btns := {}               # tab id -> Button
var _grid: GridContainer
var _tip: PanelContainer
var _tip_text: RichTextLabel
var _squares: Array = []          # {btn, key, kind, id}
var _font: Font
var _buy_sfx: AudioStreamPlayer


static func create(parent: Node, font: Font = null) -> UnlocksMenu:
	var layer := CanvasLayer.new()
	layer.layer = 85   # under the coin counter (Wallet, 90)
	parent.add_child(layer)
	var m := UnlocksMenu.new()
	m._font = font
	m.visible = false
	layer.add_child(m)
	return m


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size   # under a CanvasLayer: fill the screen
	get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_db = UpgradeDB.new("res://data/upgrades.json", RandomNumberGenerator.new())
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.01, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1180, 760)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.04, 0.97)
	sb.border_color = Color(1.0, 0.55, 0.18)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(1.0, 0.45, 0.1, 0.35)
	sb.shadow_size = 18
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)
	var title := _lbl(tr("UNLOCKS"), 44, Color(1.0, 0.65, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 12)
	vb.add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.text = tr(t[1])
		b.custom_minimum_size = Vector2(170, 46)
		b.add_theme_font_size_override("font_size", 22)
		b.focus_mode = Control.FOCUS_NONE
		var id: String = t[0]
		b.pressed.connect(func(): show_tab(id))
		var dot := _Dot.new()
		dot.name = "Dot"   # no-i18n
		dot.position = Vector2(150, 4)
		b.add_child(dot)
		tabs.add_child(b)
		_tab_btns[id] = b
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var gc := CenterContainer.new()
	gc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gc)
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 22)
	gc.add_child(_grid)
	var back := Button.new()
	back.text = tr("Back")
	back.custom_minimum_size = Vector2(200, 50)
	back.add_theme_font_size_override("font_size", 24)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	vb.add_child(back)
	_tip = PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.05, 0.04, 0.03, 0.97)
	tsb.border_color = Color(1.0, 0.6, 0.25, 0.9)
	tsb.set_border_width_all(2)
	tsb.set_corner_radius_all(8)
	tsb.content_margin_left = 14
	tsb.content_margin_right = 14
	tsb.content_margin_top = 10
	tsb.content_margin_bottom = 10
	_tip.add_theme_stylebox_override("panel", tsb)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip.z_index = 10
	add_child(_tip)
	_tip_text = RichTextLabel.new()
	_tip_text.bbcode_enabled = true
	_tip_text.fit_content = true
	_tip_text.custom_minimum_size = Vector2(320, 0)
	_tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_text.add_theme_font_size_override("normal_font_size", 18)
	_tip_text.add_theme_font_size_override("bold_font_size", 21)
	_tip.add_child(_tip_text)
	_buy_sfx = AudioStreamPlayer.new()
	_buy_sfx.bus = Settings.SFX_BUS
	if ResourceLoader.exists("res://audio/ui/forge_hammer.wav"):
		_buy_sfx.stream = load("res://audio/ui/forge_hammer.wav")
	add_child(_buy_sfx)


func _lbl(text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(2, size / 7))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func open() -> void:
	visible = true
	show_tab(tab)


func close() -> void:
	visible = false
	_tip.visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()


## The catalogue keys on a tab ("weapon:weapon_orb"... / "map:forest"...).
func keys_of(t: String) -> Array:
	var out := []
	if t == "map":
		for m in MapPicker.MAPS:
			out.append("map:" + str(m["id"]))
	elif t != "upgrades":
		for id in _db.order:
			var d: Dictionary = _db.defs[id]
			if d["kind"] == t and not d.has("signature"):
				out.append(t + ":" + id)
	return out


## A tab has a dot while any of its squares has one.
func tab_has_new(t: String) -> bool:
	for k in keys_of(t):
		if Wallet.is_new(k):
			return true
	return false


static func any_new() -> bool:
	return not Wallet.new_marks.is_empty()


func show_tab(t: String) -> void:
	tab = t
	for c in _grid.get_children():
		c.queue_free()
	_squares.clear()
	_tip.visible = false
	if t == "upgrades":
		for u in Unlocks.LIST:
			_add_square("upgrade:" + str(u["id"]), "upgrade", str(u["id"]))
	else:
		for k in keys_of(t):
			_add_square(k, t, str(k).split(":")[1])
	_refresh_tabs()


func _refresh_tabs() -> void:
	for id in _tab_btns:
		var b: Button = _tab_btns[id]
		(b.get_node("Dot") as Control).visible = tab_has_new(id)
		b.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3) if id == tab else Color(0.85, 0.8, 0.72))


func _unlocked(kind: String, id: String) -> bool:
	match kind:
		"upgrade":
			return true
		"map":
			return MapPicker.lock_reason(id) == ""
	return Wallet.is_discovered(kind + ":" + id)


func _add_square(key: String, kind: String, id: String) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_grid.add_child(col)
	var b := Button.new()
	b.custom_minimum_size = Vector2(SQ, SQ)
	b.focus_mode = Control.FOCUS_NONE
	var open := _unlocked(kind, id)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.07) if open else Color(0.06, 0.05, 0.05)
	sb.border_color = Color(0.55, 0.38, 0.2) if open else Color(0.25, 0.22, 0.2)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	b.add_theme_stylebox_override("normal", sb)
	var hsb := sb.duplicate() as StyleBoxFlat
	hsb.border_color = Color(1.0, 0.65, 0.25)
	b.add_theme_stylebox_override("hover", hsb)
	b.add_theme_stylebox_override("pressed", hsb)
	col.add_child(b)
	var art: Control = null
	match kind:
		"upgrade":
			var u := Unlocks.find(id)
			var ic := SkillIcon.new()
			ic.kind = str(u["glyph"])
			ic.color = Color.html(str(u["color"]))
			ic.dim = 1.0 if Wallet.unlock_level(id) > 0 else 0.55
			art = ic
		"map":
			if open:
				var tex := TextureRect.new()
				var path := "res://images/maps/%s.png" % id
				if ResourceLoader.exists(path):
					tex.texture = load(path)
				tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				art = tex
		_:
			if open:
				art = UpgradeIcon.create(_db.defs[id].get("icon", {}), kind)
	if art != null:
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.offset_left = 10
		art.offset_top = 10
		art.offset_right = -10
		art.offset_bottom = -10
		b.add_child(art)
	if not open:
		var q := _lbl("?", 54, Color(0.45, 0.4, 0.36))
		q.set_anchors_preset(Control.PRESET_FULL_RECT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(q)
	var dot := _Dot.new()
	dot.position = Vector2(SQ - 22, 4)
	dot.visible = Wallet.is_new(key)
	b.add_child(dot)
	# Under it: the name; upgrades add their level pips and the next level's cost
	var name_s := _name_of(kind, id) if open else "???"
	var nl := _lbl(name_s, 15, Color(0.9, 0.85, 0.78) if open else Color(0.5, 0.46, 0.42))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.custom_minimum_size = Vector2(SQ, 0)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(nl)
	if kind == "upgrade":
		var pips := _Pips.new()
		pips.n = Unlocks.max_level(id)
		pips.lit = Wallet.unlock_level(id)
		pips.custom_minimum_size = Vector2(SQ, 12)
		col.add_child(pips)
		var cost := Unlocks.next_cost(id)
		var cl := _lbl(tr("MAX") if cost == 0 else Wallet.fmt(cost), 17, Color(1.0, 0.85, 0.35) if cost > 0 and Wallet.coins >= cost else (Color(0.55, 1.0, 0.6) if cost == 0 else Color(0.7, 0.45, 0.4)))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(cl)
		b.pressed.connect(func(): buy(id))
	var sq := {"btn": b, "key": key, "kind": kind, "id": id, "dot": dot}
	_squares.append(sq)
	b.mouse_entered.connect(func(): _hover(sq, true))
	b.mouse_exited.connect(func(): _hover(sq, false))


func _name_of(kind: String, id: String) -> String:
	match kind:
		"upgrade":
			return tr(str(Unlocks.find(id)["name"]))
		"map":
			for m in MapPicker.MAPS:
				if m["id"] == id:
					return tr(str(m["name"]))
			return id
	return tr(str(_db.defs[id]["name"]))


## Buy the next level of an upgrade (click its square).
func buy(id: String) -> bool:
	if not Unlocks.buy(id):
		return false
	if _buy_sfx.stream != null:
		_buy_sfx.play()
	show_tab(tab)
	return true


func _hover(sq: Dictionary, on: bool) -> void:
	if not on:
		_tip.visible = false
		return
	if Wallet.is_new(str(sq["key"])):   # seen: its dot (and maybe its tab's) goes
		Wallet.clear_new(str(sq["key"]))
		(sq["dot"] as Control).visible = false
		_refresh_tabs()
	_tip_text.text = _describe(str(sq["kind"]), str(sq["id"]))
	_tip.visible = true
	_tip.reset_size()
	var r := (sq["btn"] as Control).get_global_rect()
	var vp := get_viewport_rect().size
	var p := Vector2(r.end.x + 12, r.position.y)
	if p.x + _tip.size.x > vp.x - 10:
		p.x = r.position.x - _tip.size.x - 12
	p.y = clampf(p.y, 10, vp.y - _tip.size.y - 10)
	_tip.position = p


func _describe(kind: String, id: String) -> String:
	var lines: Array[String] = []
	if not _unlocked(kind, id):
		lines.append("[b]???[/b]")
		if kind == "map":
			lines.append(MapPicker.lock_reason(id))
		else:
			lines.append(tr("Not found yet: pick it up in a run to add it here."))
		return "\n".join(lines)
	lines.append("[b]%s[/b]" % _name_of(kind, id))
	match kind:
		"upgrade":
			var u := Unlocks.find(id)
			var lv := Wallet.unlock_level(id)
			var mx := Unlocks.max_level(id)
			lines.append(tr(str(u["desc"])))
			lines.append("[color=#ffd27a]%s[/color]" % (tr("Level %d / %d") % [lv, mx]))
			if lv > 0:
				lines.append("[color=#9cff9c]%s[/color]" % (tr("Now: %s") % tr(str(u["levels"][lv - 1]))))
			if lv < mx:
				lines.append("[color=#cfe8ff]%s[/color]" % (tr("Next: %s") % tr(str(u["levels"][lv]))))
				var cost := Unlocks.next_cost(id)
				lines.append(("[color=#ffd24a]%s[/color]" if Wallet.coins >= cost else "[color=#ff8a7a]%s[/color]") % (tr("Click to buy: %s coins") % Wallet.fmt(cost)))
			else:
				lines.append("[color=#9cff9c]%s[/color]" % tr("Fully upgraded"))
		"map":
			for m in MapPicker.MAPS:
				if m["id"] == id:
					lines.append(tr(str(m["blurb"])))
		_:
			var d: Dictionary = _db.defs[id]
			lines.append(_db.text(str(d["desc"])))
			if d.has("tier"):
				lines.append("[color=#ffd27a]%s[/color]" % tr(str(d["tier"]).capitalize()))
			lines.append("[color=#aaaaaa]%s[/color]" % (tr("Max level %d") % int(d["max_level"])))
	return "\n".join(lines)


## A red notification dot.
class _Dot extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(18, 18)
		size = Vector2(18, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(Vector2(9, 9), 8.5, Color(0, 0, 0, 0.6))
		draw_circle(Vector2(9, 9), 7.0, UnlocksMenu.DOT)
		draw_circle(Vector2(7, 7), 2.2, Color(1, 0.75, 0.7))


## Level pips under an upgrade: lit for each level bought.
class _Pips extends Control:
	var n := 1
	var lit := 0

	func _draw() -> void:
		var w := 14.0
		var gap := 5.0
		var x0 := (size.x - (n * w + (n - 1) * gap)) * 0.5
		for k in n:
			var r := Rect2(x0 + k * (w + gap), 1, w, 9)
			draw_rect(r, Color(1.0, 0.75, 0.25) if k < lit else Color(0.25, 0.2, 0.16))
			draw_rect(r, Color(0, 0, 0, 0.7), false, 1.0)
