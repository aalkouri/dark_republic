class_name SkillScreen
extends Control
## Skill tree overlay for one character (opened from character select). Three columns —
## Defense, Offense, Special — each with two rows of three skill squares. Select a square to
## see what it does; "Learn" spends the coins. Row 2 needs a row-1 skill of the same column.

signal closed

const SQUARE := 94.0

var char_id := ""
var char_name := ""
var _font: Font
var _font_bold: Font
var _title: Label
var _sub: Label
var _info_name: Label
var _info_desc: Label
var _info_cost: Label
var _learn: Button
var _squares := {}        # skill id -> Button
var _selected := ""
var _done_btn: Button


func setup(p_font: Font, p_bold: Font) -> void:
	_font = p_font
	_font_bold = p_bold


func open(id: String, display_name: String) -> void:
	char_id = id
	char_name = display_name
	for c in get_children():
		c.queue_free()
	_squares.clear()
	_selected = ""
	_build()
	visible = true
	_refresh()
	var first: Button = _squares.values()[0]
	first.grab_focus.call_deferred()


func close() -> void:
	visible = false
	closed.emit()


func _label(text: String, size: int, col: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font_bold if bold else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _box(border: Color, width: int, fill: Color, radius := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	return s


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	var ps := _box(Color(0.75, 0.45, 0.15, 0.9), 2, Color(0.05, 0.035, 0.025, 0.96), 12)
	ps.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", ps)
	panel.position = Vector2(110, 76)
	panel.custom_minimum_size = Vector2(1380, 690)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	_title = _label("%s  ·  Skills" % char_name, 40, Color(1.0, 0.82, 0.5), true)
	v.add_child(_title)
	_sub = _label("", 18, Color(0.85, 0.78, 0.66))
	v.add_child(_sub)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(cols)
	var tree := SkillTree.tree_for(char_id)
	for ci in SkillTree.CATEGORIES.size():
		var cat: String = SkillTree.CATEGORIES[ci]
		var ccol: Color = SkillTree.CATEGORY_COLORS[ci]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		cols.add_child(col)
		var head := _label(cat.to_upper(), 28, ccol, true)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(head)
		var underline := ColorRect.new()
		underline.color = Color(ccol, 0.6)
		underline.custom_minimum_size = Vector2(0, 2)
		col.add_child(underline)
		for tier in 2:
			var tag := _label("Row %d  ·  %d coins%s" % [tier + 1, SkillTree.cost(tier), "  ·  needs row 1" if tier == 1 else ""], 14, Color(0.7, 0.65, 0.58))
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(tag)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			col.add_child(row)
			for skill in tree[cat][tier]:
				row.add_child(_square(skill, ccol))

	# Selected skill details + Learn
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", _box(Color(0.5, 0.35, 0.18, 0.7), 1, Color(0.1, 0.07, 0.05, 0.9)))
	info.custom_minimum_size = Vector2(0, 96)
	v.add_child(info)
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 20)
	info.add_child(ih)
	var it := VBoxContainer.new()
	it.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ih.add_child(it)
	_info_name = _label("Select a skill", 26, Color(1.0, 0.86, 0.55), true)
	it.add_child(_info_name)
	_info_desc = _label("", 19, Color(0.9, 0.85, 0.76))
	_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	it.add_child(_info_desc)
	_info_cost = _label("", 17, Color(0.85, 0.75, 0.55))
	it.add_child(_info_cost)
	_learn = _button("Learn", _learn_selected)
	_learn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ih.add_child(_learn)
	_done_btn = _button("Done", close)
	_done_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ih.add_child(_done_btn)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.custom_minimum_size = Vector2(190, 56)
	if _font_bold:
		b.add_theme_font_override("font", _font_bold)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(0.92, 0.86, 0.75))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.72, 0.3))
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.72, 0.3))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.42, 0.4))
	b.add_theme_stylebox_override("normal", _box(Color(0.55, 0.3, 0.12), 2, Color(0.08, 0.04, 0.02, 0.9)))
	b.add_theme_stylebox_override("hover", _box(Color(1.0, 0.6, 0.2), 3, Color(0.2, 0.07, 0.02, 0.95)))
	b.add_theme_stylebox_override("focus", _box(Color(1.0, 0.7, 0.3), 3, Color(0.2, 0.07, 0.02, 0.95)))
	b.add_theme_stylebox_override("pressed", _box(Color(1.0, 0.85, 0.5), 3, Color(0.3, 0.1, 0.02, 0.95)))
	b.add_theme_stylebox_override("disabled", _box(Color(0.25, 0.22, 0.2), 2, Color(0.05, 0.05, 0.05, 0.85)))
	b.pressed.connect(cb)
	return b


func _square(skill: Dictionary, ccol: Color) -> Control:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 4)
	var b := Button.new()
	b.custom_minimum_size = Vector2(SQUARE, SQUARE)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("color", ccol)
	b.set_meta("skill", skill)
	var icon := SkillIcon.new()
	icon.kind = skill["icon"]
	icon.color = ccol
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 14
	icon.offset_top = 12
	icon.offset_right = -14
	icon.offset_bottom = -16
	b.add_child(icon)
	b.set_meta("icon", icon)
	var badge := _label("", 15, Color(1, 1, 1), true)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -30
	badge.offset_top = -24
	badge.offset_right = -6
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.add_child(badge)
	b.set_meta("badge", badge)
	b.focus_entered.connect(_select.bind(skill["id"]))
	b.mouse_entered.connect(func(): b.grab_focus())
	b.pressed.connect(func():
		_select(skill["id"])
		if SkillTree.blocked_reason(char_id, skill["id"]) == "":
			_learn.grab_focus())
	holder.add_child(b)
	var name := _label(skill["name"], 13, Color(0.86, 0.8, 0.7))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.custom_minimum_size = Vector2(SQUARE, 34)   # room for two lines, so rows line up
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	holder.add_child(name)
	_squares[skill["id"]] = b
	return holder


func _select(skill_id: String) -> void:
	_selected = skill_id
	_refresh()


func _learn_selected() -> void:
	if _selected == "" or not SkillTree.learn(char_id, _selected):
		return
	_refresh()
	var b: Button = _squares[_selected]
	var tw := create_tween()
	b.pivot_offset = b.size * 0.5
	tw.tween_property(b, "scale", Vector2(1.15, 1.15), 0.08)
	tw.tween_property(b, "scale", Vector2.ONE, 0.15)
	b.grab_focus()


func _refresh() -> void:
	var lvl := Wallet.char_level(char_id)
	_sub.text = "lvl %d   ·   %d / 18 skills learned   ·   each skill learned raises lvl by 1" % [lvl, Wallet.skills_of(char_id).size()]
	for id in _squares:
		var b: Button = _squares[id]
		var ccol: Color = b.get_meta("color")
		var learned := Wallet.has_skill(char_id, id)
		var reason := SkillTree.blocked_reason(char_id, id)
		var locked_row := reason.begins_with("Learn a")
		var icon: SkillIcon = b.get_meta("icon")
		var badge: Label = b.get_meta("badge")
		icon.dim = 0.35 if locked_row else (1.0 if learned else 0.7)
		icon.locked = locked_row
		var border := Color(1.0, 0.82, 0.3) if learned else (Color(0.3, 0.28, 0.26) if locked_row else ccol.darkened(0.15))
		var fill := Color(0.22, 0.15, 0.05, 0.95) if learned else Color(0.06, 0.05, 0.05, 0.92)
		b.add_theme_stylebox_override("normal", _box(border, 3 if learned else 2, fill))
		b.add_theme_stylebox_override("hover", _box(Color(1.0, 0.85, 0.5), 3, fill.lightened(0.08)))
		b.add_theme_stylebox_override("focus", _box(Color(1.0, 0.9, 0.6), 4, fill.lightened(0.08)))
		b.add_theme_stylebox_override("pressed", _box(Color(1.0, 0.95, 0.7), 4, fill.lightened(0.12)))
		badge.text = "✓" if learned else ""
		badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	if _selected == "":
		_info_name.text = "Select a skill"
		_info_desc.text = "Skills last for every run with this character."
		_info_cost.text = ""
		_learn.disabled = true
		return
	var info := SkillTree.find(char_id, _selected)
	var s: Dictionary = info["skill"]
	_info_name.text = s["name"]
	_info_desc.text = s["desc"]
	var why := SkillTree.blocked_reason(char_id, _selected)
	if why == "Learned":
		_info_cost.text = "Learned"
		_info_cost.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	else:
		_info_cost.text = "%s  ·  Cost %s coins%s" % [info["category"], Wallet.fmt(SkillTree.cost(info["tier"])), ("   ·   " + why) if why != "" else ""]
		_info_cost.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55) if why == "" else Color(1.0, 0.5, 0.4))
	_learn.disabled = why != ""


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
