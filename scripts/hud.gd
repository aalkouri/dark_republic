class_name Hud
extends CanvasLayer
## All UI, built in code: bars, timer, run info, level-up draft cards, pause and end screens.

var main  # main.gd (untyped to avoid a cyclic class reference)

var hp_bar: ProgressBar
var hp_label: Label
var shield_bar: ProgressBar
var xp_bar: ProgressBar
var level_label: Label
var timer_label: Label
var info_label: Label
var inv_label: Label
var debug_label: Label
var msg_label: Label
var pause_root: Control
var settings_menu: SettingsMenu
var draft_root: Control
var draft_cards: Array = []   # [Button, rarity Label, title Label, body Label]
var end_root: Control
var ability_slots: Array = []   # AbilitySlot
var tooltip: PanelContainer
var tooltip_text: RichTextLabel
var inspect_hint: Label
var buff_label: RichTextLabel
var _hover_slot := -1
var end_title: Label
var end_stats: Label
var show_debug := false
var _msg_t := 0.0


func setup(m) -> void:
	main = m
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# XP bar across the top
	xp_bar = _bar(Color(0.35, 0.65, 1.0))
	xp_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	xp_bar.offset_bottom = 12
	root.add_child(xp_bar)
	level_label = _label("LV 1", 22)
	level_label.position = Vector2(20, 18)
	root.add_child(level_label)

	hp_bar = _bar(Color(0.9, 0.25, 0.25))
	hp_bar.position = Vector2(20, 52)
	hp_bar.size = Vector2(320, 24)
	root.add_child(hp_bar)
	shield_bar = _bar(Color(0.3, 0.65, 1.0))
	shield_bar.position = Vector2(20, 78)
	shield_bar.size = Vector2(320, 8)
	shield_bar.visible = false
	root.add_child(shield_bar)
	hp_label = _label("", 16)
	hp_label.position = Vector2(30, 53)
	root.add_child(hp_label)

	timer_label = _label("00:00", 40)
	timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.offset_left = -150
	timer_label.offset_right = 150
	timer_label.offset_top = 18
	root.add_child(timer_label)

	info_label = _label("", 18)
	info_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_label.offset_left = -320
	info_label.offset_right = -20
	info_label.offset_top = 20
	root.add_child(info_label)

	debug_label = _label("", 14)
	debug_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.offset_left = -420
	debug_label.offset_right = -20
	debug_label.offset_top = 130
	debug_label.visible = false
	root.add_child(debug_label)

	inv_label = _label("", 16)
	inv_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	inv_label.offset_left = 20
	inv_label.offset_top = -220
	inv_label.offset_right = 520
	inv_label.offset_bottom = -20
	inv_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	root.add_child(inv_label)

	var hint := _label("WASD move · Space jump · Shift/Ctrl slide · 1/2/3 abilities · hold Alt inspect · Esc pause\nF1 debug · F2 spawn 200 · F3 reset cooldowns", 14)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.offset_left = -800
	hint.offset_right = -20
	hint.offset_top = -60
	hint.modulate.a = 0.6
	root.add_child(hint)

	msg_label = _label("", 34)
	msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.offset_left = -500
	msg_label.offset_right = 500
	msg_label.offset_top = 150
	msg_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	root.add_child(msg_label)

	_build_ability_bar(root)
	_build_pause(root)
	_build_draft(root)
	_build_end(root)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", max(2, size / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _dim(root: Control) -> Control:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, 0.6)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	root.add_child(c)
	return c


func _build_pause(root: Control) -> void:
	pause_root = _dim(root)
	pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	center.add_child(vb)
	var title := _label("PAUSED", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	for item in [["Resume", func(): main.resume_from_pause()],
			["Settings", func(): open_settings()],
			["Restart run", func(): main.restart()],
			["Quit to desktop", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(300, 52)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(item[1])
		vb.add_child(b)

	settings_menu = SettingsMenu.new()
	settings_menu.visible = false
	settings_menu.closed.connect(func(): pause_root.visible = main.state == "paused")
	root.add_child(settings_menu)


func open_settings() -> void:
	pause_root.visible = false
	settings_menu.open()


func settings_open() -> bool:
	return settings_menu.visible


func _build_draft(root: Control) -> void:
	draft_root = _dim(root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	draft_root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 24)
	center.add_child(vb)
	var title := _label("LEVEL UP!", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	for i in 3:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(300, 230)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func(): main.choose_upgrade(i))
		hb.add_child(btn)
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 16
		box.offset_top = 14
		box.offset_right = -16
		box.offset_bottom = -14
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 8)
		btn.add_child(box)
		var rar := _label("", 15)
		var ttl := _label("", 24)
		ttl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var body := _label("", 17)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for l in [rar, ttl, body]:
			box.add_child(l)
		draft_cards.append([btn, rar, ttl, body])


func _build_ability_bar(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -26
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 14)
	root.add_child(bar)
	var icons := [AbilitySlot.Icon.INFERNO, AbilitySlot.Icon.SHOCKWAVE, AbilitySlot.Icon.METEOR]
	for i in Abilities.DEFS.size():
		var d: Dictionary = Abilities.DEFS[i]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(col)
		var slot := AbilitySlot.new()
		slot.icon = icons[i]
		slot.key_text = d["key"]
		slot.is_ult = d["ult"]
		slot.unlock_level = d["unlock_level"]
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.activated.connect(func(): main.cast_ability(i))
		col.add_child(slot)
		var name := _label(d["name"], 13)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if d["ult"] else Color(1, 1, 1, 0.85))
		col.add_child(name)
		ability_slots.append(slot)
		slot.hovered.connect(func(on: bool): _on_slot_hover(i, on))
	_build_tooltip(root)


func _build_tooltip(root: Control) -> void:
	tooltip = PanelContainer.new()
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.custom_minimum_size = Vector2(380, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.045, 0.04, 0.95)
	sb.border_color = Color(1.0, 0.5, 0.18, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	tooltip.add_theme_stylebox_override("panel", sb)
	tooltip_text = RichTextLabel.new()
	tooltip_text.bbcode_enabled = true
	tooltip_text.fit_content = true
	tooltip_text.scroll_active = false
	tooltip_text.custom_minimum_size = Vector2(380, 0)
	tooltip_text.add_theme_font_size_override("normal_font_size", 16)
	tooltip_text.add_theme_font_size_override("bold_font_size", 16)
	tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_child(tooltip_text)
	root.add_child(tooltip)

	buff_label = RichTextLabel.new()
	buff_label.bbcode_enabled = true
	buff_label.fit_content = true
	buff_label.scroll_active = false
	buff_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	buff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buff_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	buff_label.offset_left = -400
	buff_label.offset_right = 400
	buff_label.offset_top = 64
	buff_label.add_theme_font_size_override("normal_font_size", 20)
	buff_label.add_theme_constant_override("outline_size", 5)
	buff_label.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(buff_label)

	inspect_hint = _label("PAUSED  ·  hover an ability for details  ·  release Alt to resume", 20)
	inspect_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	inspect_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inspect_hint.offset_left = -500
	inspect_hint.offset_right = 500
	inspect_hint.offset_top = 92
	inspect_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	inspect_hint.visible = false
	root.add_child(inspect_hint)


func _on_slot_hover(i: int, on: bool) -> void:
	_hover_slot = i if on else (-1 if _hover_slot == i else _hover_slot)


func set_inspect(on: bool) -> void:
	inspect_hint.visible = on
	if not on:
		tooltip.visible = false


func _update_tooltip() -> void:
	var show := _hover_slot >= 0 and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not settings_menu.visible
	if not show:
		tooltip.visible = false
		return
	tooltip_text.text = main.abilities.describe(_hover_slot)
	tooltip.visible = true
	tooltip.reset_size()
	var slot: Control = ability_slots[_hover_slot]
	var r := slot.get_global_rect()
	var vp := get_viewport().get_visible_rect().size
	var pos := Vector2(r.position.x + r.size.x * 0.5 - tooltip.size.x * 0.5, r.position.y - tooltip.size.y - 34)
	pos.x = clampf(pos.x, 10, vp.x - tooltip.size.x - 10)
	pos.y = maxf(pos.y, 10)
	tooltip.position = pos


func _build_end(root: Control) -> void:
	end_root = _dim(root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	center.add_child(vb)
	end_title = _label("", 56)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(end_title)
	end_stats = _label("", 22)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(end_stats)
	var btn := Button.new()
	btn.text = "Restart  [R]"
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(func(): main.restart())
	vb.add_child(btn)


# ------------------------------------------------------------------ public

func show_draft(picks: Array) -> void:
	for i in draft_cards.size():
		var card: Array = draft_cards[i]
		var btn: Button = card[0]
		btn.visible = i < picks.size()
		if i >= picks.size():
			continue
		var info: Dictionary = main.db.describe(picks[i])
		card[1].text = info["subtitle"]
		card[1].add_theme_color_override("font_color", info["color"])
		card[2].text = info["title"]
		card[2].add_theme_color_override("font_color", info["color"])
		card[3].text = info["body"]
	draft_root.visible = true


func hide_draft() -> void:
	draft_root.visible = false


func set_paused(p: bool) -> void:
	pause_root.visible = p


func show_end(won: bool) -> void:
	end_title.text = "YOU SURVIVED!" if won else "YOU GOT BONKED"
	end_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if won else Color(1.0, 0.35, 0.3))
	end_stats.text = "Time %s   ·   Level %d   ·   Kills %d" % [_fmt_time(main.run_time), main.level, main.kills]
	end_root.visible = true


func flash_message(text: String, duration := 3.0) -> void:
	msg_label.text = text
	_msg_t = duration


func toggle_debug() -> void:
	show_debug = not show_debug
	debug_label.visible = show_debug


static func _fmt_time(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]


func _process(dt: float) -> void:
	if main == null or main.player == null:
		return
	var p: Player = main.player
	hp_bar.max_value = p.max_hp
	hp_bar.value = p.hp
	hp_label.text = "%d / %d" % [ceili(p.hp), roundi(p.max_hp)]
	shield_bar.visible = p.shield > 0.5
	if shield_bar.visible:
		hp_label.text += "   +%d shield" % ceili(p.shield)
		shield_bar.max_value = p.max_hp
		shield_bar.value = minf(p.shield, p.max_hp)
	xp_bar.max_value = main.xp_next
	xp_bar.value = main.xp
	level_label.text = "LV %d" % main.level
	timer_label.text = _fmt_time(main.run_time)
	info_label.text = "Kills %d\nEnemies %d\nSpeed %.1f m/s" % [main.kills, main.enemies.alive_count(), p.horizontal_speed()]
	if Settings.show_fps:
		info_label.text += "\nFPS %d" % Engine.get_frames_per_second()

	var lines := []
	for id in main.db.order:
		var lv: int = main.db.level_of(id)
		if lv > 0 and main.db.defs[id]["kind"] != "tome":
			lines.append("%s  Lv %d" % [main.db.defs[id]["name"], lv])
	var tomes := 0
	for id in main.db.levels:
		if main.db.defs[id]["kind"] == "tome":
			tomes += main.db.levels[id]
	if tomes > 0:
		lines.append("Tomes ×%d" % tomes)
	inv_label.text = "\n".join(lines)

	_update_tooltip()
	buff_label.text = "[center]%s[/center]" % main.powerups.status_text()
	for i in ability_slots.size():
		ability_slots[i].set_locked(not main.abilities.is_unlocked(i))
		ability_slots[i].set_cooldown(main.abilities.fraction_remaining(i), main.abilities.cooldown[i])

	if show_debug:
		var pf: Dictionary = main.perf
		debug_label.text = "sim ms  enemies %.2f  weapons %.2f  gems %.2f\nprojectiles %d  gems %d  burning %d  potions %d\nhp mult %.2f  epic chance %d%%" % [
			pf["enemies"], pf["weapons"], pf["gems"], main.weapons.pc, main.gems.count, main.enemies.burning_count(), main.potions.count(), main.hp_mult(), roundi(main.epic_chance() * 100.0)]

	if _msg_t > 0.0:
		_msg_t -= dt
		msg_label.modulate.a = clampf(_msg_t, 0.0, 1.0)
