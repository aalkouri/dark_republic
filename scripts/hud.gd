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
var inv_box: VBoxContainer      # owned weapons/items (top row) and tomes (bottom row), with levels
var _inv_sig := ""
var debug_label: Label
var msg_label: Label
var intro_banner: BloodBanner
## Level-up / reward-card sounds (tools/gen_ui_sounds.py makes all the candidates in audio/ui/).
const UI_SOUNDS := {
	"levelup": "res://audio/ui/levelup_surge.wav",   # Power Surge: punch + synth stab
	"hover": "res://audio/ui/hover_tick.wav",
	"pick": "res://audio/ui/pick_shing.wav",        # weapons and items
	"pick_tome": "res://audio/ui/pick_slam.wav",    # tomes: a heavy book slam
	"ban": "res://audio/ui/ban_stamp.wav",          # BAN: stamp + "denied" drone
	"timer_tick": "res://audio/ui/timer_tick.wav",  # run clock spinning up (digital blip)
	"timer_set": "res://audio/ui/timer_set.wav",    # ...and locking in at 10:00
}

## Run clock: counts DOWN from 10:00. While the entrance plays it spins up from 00:00 to
## 10:00 in SPIN_TIME with digital blips, then locks in. Unrelenting mode counts UP instead.
const SPIN_DELAY := 0.35
const SPIN_TIME := 1.9
const TICK_EVERY := 0.05
var _spin_t := -1.0          # time since the spin-up started; -1 = no spin (clock is live)
var _tick_cd := 0.0
var _ui_players := {}
var pause_root: Control
var settings_menu: SettingsMenu
var draft_root: Control
var draft_cards: Array = []   # [Button, title Label, body Label, UpgradeIcon, level Label, BAN Button, banned veil]
var draft_bans: Label
var end_root: Control
var ability_slots: Array = []   # AbilitySlot
var tooltip: PanelContainer
var tooltip_text: RichTextLabel
var inspect_hint: Label
var buff_label: RichTextLabel
var key_box: HBoxContainer        # keys held (chests), top centre
var key_labels: Array[Label] = []
var slot_machine: SlotMachine     # the chest slot machine while it's open
var _popups: Array = []   # [Label, age, base_pos]
const POPUP_LIFE := 0.9
var _hover_slot := -1
var end_title: Label
var end_stats: Label
var end_coin_lines: Label
var end_exp: Label
var end_pot: Label
var end_unlocks: VBoxContainer       # "UNLOCKED!" after a first boss kill: cards swirl in
var unlock_cards: Array[Control] = []
var _unlock_slots: Array[Control] = []
var _unlock_ding: AudioStreamPlayer
var end_pot_icon: CoinIcon
var run_reward := {"time": 0, "bonus": 0, "total": 0}
var _pot_left := 0
var _pay_started := false
var _pay_base := 0.0
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
	info_label.offset_top = 70   # below the coin counter (Wallet)
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
	inv_label.visible = false   # replaced by the icon overlay below (kept for the debug overlay)
	root.add_child(inv_label)
	inv_box = VBoxContainer.new()
	inv_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	inv_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	inv_box.offset_left = 18
	inv_box.offset_bottom = -16
	inv_box.offset_top = -16
	inv_box.alignment = BoxContainer.ALIGNMENT_END
	inv_box.add_theme_constant_override("separation", 6)
	inv_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(inv_box)

	var hint := _label("WASD move · Space jump · Shift/Ctrl slide · 1/2/3 abilities · Wheel zoom · hold Alt inspect · Esc pause\nF1 debug · F2 spawn 200 · F3 reset cooldowns", 14)
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
	intro_banner = BloodBanner.new()
	root.add_child(intro_banner)

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
			["Main menu", func(): main.to_title()],
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
	draft_bans = _label("", 18)
	draft_bans.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_bans.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	vb.add_child(draft_bans)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	for i in 3:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		hb.add_child(col)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(300, 420)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func(): main.choose_upgrade(i))
		btn.mouse_entered.connect(func(): play_ui("hover"))
		col.add_child(btn)
		# BAN: pay 100 coins to throw this reward out of this and every later draft
		var ban := Button.new()
		ban.text = tr("BAN  ·  %d coins") % main.BAN_COST
		ban.focus_mode = Control.FOCUS_NONE
		ban.custom_minimum_size = Vector2(300, 44)
		ban.add_theme_font_size_override("font_size", 18)
		ban.add_theme_color_override("font_color", Color(1.0, 0.85, 0.82))
		ban.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.48))
		ban.add_theme_stylebox_override("normal", _ban_style(Color(0.55, 0.08, 0.06), Color(0.2, 0.03, 0.02, 0.95)))
		ban.add_theme_stylebox_override("hover", _ban_style(Color(0.95, 0.2, 0.15), Color(0.32, 0.05, 0.03, 0.97)))
		ban.add_theme_stylebox_override("pressed", _ban_style(Color(1.0, 0.35, 0.25), Color(0.4, 0.06, 0.04, 1.0)))
		ban.add_theme_stylebox_override("disabled", _ban_style(Color(0.25, 0.22, 0.2), Color(0.08, 0.07, 0.07, 0.9)))
		ban.pressed.connect(func():
			if main.ban_upgrade(i):
				play_ui("ban"))
		ban.mouse_entered.connect(func(): if not ban.disabled: play_ui("hover"))
		col.add_child(ban)
		# Shown over a banned card
		var veil := ColorRect.new()
		veil.color = Color(0.05, 0.0, 0.0, 0.78)
		veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		veil.visible = false
		var stamp := _label("BANNED", 46)
		stamp.set_anchors_preset(Control.PRESET_CENTER)
		stamp.grow_horizontal = Control.GROW_DIRECTION_BOTH
		stamp.grow_vertical = Control.GROW_DIRECTION_BOTH
		stamp.rotation = -0.35
		stamp.pivot_offset = Vector2(100, 30)
		stamp.add_theme_color_override("font_color", Color(0.9, 0.12, 0.08))
		stamp.add_theme_constant_override("outline_size", 10)
		veil.add_child(stamp)
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 18
		box.offset_top = 18
		box.offset_right = -18
		box.offset_bottom = -18
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 10)
		btn.add_child(box)
		# Centrepiece: the upgrade's icon (tome book, weapon medallion, item charm)
		# Icon centred, with the level it becomes ("Lv 2") just to its right
		var icon_row := HBoxContainer.new()
		icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
		icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_row.add_theme_constant_override("separation", 8)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(64, 0)
		icon_row.add_child(pad)
		var tome := UpgradeIcon.new()
		tome.custom_minimum_size = Vector2(120, 120)
		icon_row.add_child(tome)
		var lvl := _label("", 26)
		lvl.custom_minimum_size = Vector2(64, 0)
		lvl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lvl.add_theme_constant_override("outline_size", 6)
		icon_row.add_child(lvl)
		box.add_child(icon_row)
		var ttl := _label("", 26)
		ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ttl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(ttl)
		# What it does, in its own dark box
		var body_box := PanelContainer.new()
		body_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(0.02, 0.015, 0.01, 0.82)
		bs.border_color = Color(1, 1, 1, 0.14)
		bs.set_border_width_all(1)
		bs.set_corner_radius_all(8)
		bs.set_content_margin_all(12)
		body_box.add_theme_stylebox_override("panel", bs)
		box.add_child(body_box)
		var body := _label("", 20)
		body.add_theme_color_override("font_color", Color.WHITE)
		body.add_theme_constant_override("outline_size", 5)
		body.add_theme_constant_override("line_spacing", 4)
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_box.add_child(body)
		btn.add_child(veil)
		draft_cards.append([btn, ttl, body, tome, lvl, ban, veil])


## Card frame outlined thickly in the rarity colour (brighter on hover).
static func _card_style(rarity: Color, fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = rarity
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(rarity, 0.35)
	sb.shadow_size = 10
	return sb


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
	var defs: Array = main.abilities.defs()
	var kit: String = main.abilities.kit
	for i in defs.size():
		var d: Dictionary = defs[i]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(col)
		var slot := AbilitySlot.new()
		slot.icon = icons[i]
		if main.abilities.roster != null:   # roster characters: their kit's icons
			var ic: Dictionary = KitDB.ability(kit, i).get("icon", {})
			slot.glyph = str(ic.get("glyph", ""))
			slot.glyph_color = Color(str(ic.get("color", "#ffffff")))
		slot.key_text = d["key"]
		slot.is_ult = d["ult"]
		slot.unlock_level = d["unlock_level"]
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.activated.connect(func(): main.cast_ability(i))
		col.add_child(slot)
		var name := _label(d["name"], 13)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.custom_minimum_size = Vector2(112, 0)   # fixed columns; long names wrap
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
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

	key_box = HBoxContainer.new()
	key_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	key_box.offset_left = -300
	key_box.offset_right = 300
	key_box.offset_top = 196
	key_box.alignment = BoxContainer.ALIGNMENT_CENTER
	key_box.add_theme_constant_override("separation", 22)
	key_box.visible = false
	key_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(key_box)
	for t in 3:
		var kl := _label("", 20)
		kl.add_theme_color_override("font_color", Chest.TIER_COLORS[t].lightened(0.15))
		key_box.add_child(kl)
		key_labels.append(kl)

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


## A pop-up text on the HUD: starts small, swells, settles, floats up and fades (< 1 s).
func popup(text: String, at: Vector2, color: Color, size := 30) -> void:
	var l := _label(text, size)
	l.add_theme_color_override("font_color", color)
	l.pivot_offset = Vector2(0, size * 0.6)
	add_child(l)
	l.position = at
	_popups.append([l, 0.0, at])


## "+N" to the right of the health bar.
func show_heal(amount: float) -> void:
	if amount >= 0.5:
		popup("+%d" % roundi(amount), hp_bar.position + Vector2(hp_bar.size.x + 12, -6), Color(1.0, 0.22, 0.2), 30)


## "-Ns" above each ability that had time taken off its cooldown.
func show_cooldown_cuts(cuts: PackedFloat32Array) -> void:
	for i in mini(cuts.size(), ability_slots.size()):
		if cuts[i] < 0.05:
			continue
		var slot: Control = ability_slots[i]
		var r := slot.get_global_rect()
		var txt := ("-%ds" % roundi(cuts[i])) if absf(cuts[i] - roundf(cuts[i])) < 0.05 else ("-%.1fs" % cuts[i])
		popup(txt, Vector2(r.position.x + r.size.x * 0.5 - 22, r.position.y - 40), Color(0.8, 0.45, 1.0), 26)


func _update_popups(dt: float) -> void:
	for k in range(_popups.size() - 1, -1, -1):
		var p: Array = _popups[k]
		var l: Label = p[0]
		p[1] += dt
		var t: float = p[1] / POPUP_LIFE
		if t >= 1.0:
			l.queue_free()
			_popups.remove_at(k)
			continue
		var s := 1.0
		if t < 0.15:
			var kk := t / 0.15
			s = lerpf(0.35, 1.45, 1.0 - (1.0 - kk) * (1.0 - kk))
		elif t < 0.35:
			s = lerpf(1.45, 1.0, (t - 0.15) / 0.2)
		l.scale = Vector2.ONE * s
		l.position = (p[2] as Vector2) + Vector2(0, -26.0 * t)
		l.modulate.a = 1.0 if t < 0.5 else 1.0 - (t - 0.5) / 0.5


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
	end_unlocks = VBoxContainer.new()
	end_unlocks.add_theme_constant_override("separation", 8)
	end_unlocks.visible = false
	vb.add_child(end_unlocks)
	_unlock_ding = AudioStreamPlayer.new()
	_unlock_ding.bus = Settings.SFX_BUS
	_unlock_ding.volume_db = -4.0
	if ResourceLoader.exists("res://audio/coins/coin_done.wav"):
		_unlock_ding.stream = load("res://audio/coins/coin_done.wav")
	add_child(_unlock_ding)
	# Character EXP earned this run (1 per kill, banked when the run ends)
	end_exp = _label("", 20)
	end_exp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_exp.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	vb.add_child(end_exp)
	# Coins earned this run (banked here, poured into the counter)
	var coin_box := VBoxContainer.new()
	coin_box.add_theme_constant_override("separation", 4)
	vb.add_child(coin_box)
	end_coin_lines = _label("", 20)
	end_coin_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_coin_lines.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	coin_box.add_child(end_coin_lines)
	var pot_row := HBoxContainer.new()
	pot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pot_row.add_theme_constant_override("separation", 10)
	coin_box.add_child(pot_row)
	end_pot_icon = CoinIcon.new()
	end_pot_icon.custom_minimum_size = Vector2(48, 48)
	pot_row.add_child(end_pot_icon)
	end_pot = _label("", 44)
	end_pot.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	end_pot.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.0))
	end_pot.add_theme_constant_override("outline_size", 6)
	pot_row.add_child(end_pot)
	var btn := Button.new()
	btn.text = "Restart  [R]"
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(func(): main.restart())
	vb.add_child(btn)
	var menu_btn := Button.new()
	menu_btn.text = "Main menu"
	menu_btn.add_theme_font_size_override("font_size", 24)
	menu_btn.pressed.connect(func(): main.to_title())
	vb.add_child(menu_btn)


# ------------------------------------------------------------------ public

func show_draft(picks: Array) -> void:
	for i in draft_cards.size():
		var card: Array = draft_cards[i]
		var btn: Button = card[0]
		btn.visible = i < picks.size()
		(card[5] as Button).visible = i < picks.size()
		(card[6] as ColorRect).visible = false
		btn.disabled = false
		if i >= picks.size():
			continue
		var info: Dictionary = main.db.describe(picks[i])
		var col: Color = info["color"]
		btn.add_theme_stylebox_override("normal", _card_style(col, Color(0.07, 0.055, 0.045, 0.97)))
		btn.add_theme_stylebox_override("hover", _card_style(col.lightened(0.3), Color(0.13, 0.1, 0.07, 0.98)))
		btn.add_theme_stylebox_override("pressed", _card_style(col.lightened(0.45), Color(0.18, 0.13, 0.08, 1.0)))
		card[1].text = info["title"]
		card[1].add_theme_color_override("font_color", col.lightened(0.15))
		card[2].text = info["body"]
		var icon: Dictionary = info.get("icon", {})
		(card[4] as Label).text = tr("Lv %d") % int(info.get("next_level", 1))
		(card[4] as Label).add_theme_color_override("font_color", col.lightened(0.25))
		var art: UpgradeIcon = card[3]
		art.visible = not icon.is_empty()
		if art.visible:
			art.set_icon(icon, info["kind"])
	_refresh_bans()
	draft_root.visible = true


## The chest slot machine (game paused). `done` is called with (ability, levels) when the
## player presses Continue.
func show_slot_machine(tier: int, done: Callable) -> SlotMachine:
	hide_slot_machine()
	slot_machine = SlotMachine.new()
	slot_machine.setup(main.abilities, tier, main.rng)
	slot_machine.finished.connect(func(a: int, n: int): done.call(a, n))
	add_child(slot_machine)
	return slot_machine


func hide_slot_machine() -> void:
	if is_instance_valid(slot_machine):
		slot_machine.queue_free()
	slot_machine = null


## Grey out a banned card and stamp it.
func mark_banned(i: int) -> void:
	var card: Array = draft_cards[i]
	(card[0] as Button).disabled = true
	(card[6] as ColorRect).visible = true
	(card[5] as Button).visible = false
	_refresh_bans()


func _refresh_bans() -> void:
	draft_bans.text = tr("Bans left: %d / %d   ·   %d coins each") % [main.bans_left, main.BANS_PER_RUN, main.BAN_COST]
	for i in draft_cards.size():
		(draft_cards[i][5] as Button).disabled = not main.can_ban(i)


static func _ban_style(border: Color, fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	return sb


func hide_draft() -> void:
	draft_root.visible = false


func set_paused(p: bool) -> void:
	pause_root.visible = p


func show_end(won: bool) -> void:
	end_title.text = (tr("%s DEFEATED!") % tr(main.boss_name) if main.boss_won else tr("YOU SURVIVED!")) if won else tr("YOU DIED")
	end_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if won else Color(1.0, 0.35, 0.3))
	end_stats.text = tr("Time %s   ·   Level %d   ·   Kills %d") % [_fmt_time(main.run_time), main.level, main.kills]
	show_unlocks(unlocks_for(main.boss_id) if main.first_boss_kill else [])
	end_root.visible = true
	# EXP for the character played (kills, elites, boss, chests, time alive, win bonus), banked now
	var cid := Settings.selected_character
	run_exp = Wallet.run_exp(main.kills, main.elites_killed, 1 if main.boss_won else 0, main.chests_opened, main.run_time, won)
	var gained_levels := Wallet.add_char_exp(cid, int(run_exp["total"]))
	var lvl := Wallet.char_level(cid)
	var next := Wallet.next_level_exp(cid)
	var progress := (tr("%s / %s EXP") % [Wallet.fmt(Wallet.char_exp_of(cid)), Wallet.fmt(next)]) if next >= 0 else tr("max level")
	end_exp.text = tr("EXP +%s   ·   lvl %d  (%s)") % [Wallet.fmt(int(run_exp["total"])), lvl, progress]
	end_exp.text += "\n" + exp_breakdown(run_exp)
	if gained_levels > 0:
		end_exp.text += "\n" + (tr("LEVEL UP!  lvl %d   ·   +%d skill points") if gained_levels > 1 else tr("LEVEL UP!  lvl %d   ·   +%d skill point")) % [lvl, gained_levels]
		end_exp.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	else:
		end_exp.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	# Coins: shown here, banked when they pour into the counter
	run_reward = Wallet.run_reward(main.run_time, main.kills, main.stats.value("coin_gain"))
	var bonus_line := tr("Kills %s   →   +%s bonus") % [Wallet.fmt(main.kills), Wallet.fmt(run_reward["bonus"])] if run_reward["bonus"] > 0 \
		else tr("Kills %s   →   +0 bonus  (100 coins per 1,000 kills)") % Wallet.fmt(main.kills)
	end_coin_lines.text = tr("Survived %s   →   %s coins") % [_fmt_time(main.run_time), Wallet.fmt(run_reward["time"])] + "\n" + bonus_line
	if run_reward["extra"] > 0:
		end_coin_lines.text += "\n" + tr("Skills  →   +%s coins") % Wallet.fmt(run_reward["extra"])
	_pot_left = run_reward["total"]
	end_pot.text = "+" + Wallet.fmt(_pot_left)
	_pay_started = false
	get_tree().create_timer(0.8, true).timeout.connect(_start_payout)


var run_exp := {}


## "Kills 1,200 · Elites +350 · Boss +2,000 · Chests +500 · Time +1,000 · Win +1,262" (zero parts left out).
static func exp_breakdown(e: Dictionary) -> String:
	var parts: Array[String] = []
	for k in [["kills", "Kills %s"], ["elites", "Elites +%s"], ["boss", "Boss +%s"], ["chests", "Chests +%s"], ["time", "Time +%s"], ["win", "Win +%s"]]:
		if int(e.get(k[0], 0)) > 0:
			parts.append(I18n.t(k[1]) % Wallet.fmt(int(e[k[0]])))
	return "   ·   ".join(parts)


func _start_payout() -> void:
	if not end_root.visible or _pay_started:
		return
	_pay_started = true
	_pay_base = Wallet.displayed
	Wallet.payout(run_reward["total"], end_pot_icon.get_global_rect().get_center())


# ------------------------------------------------------------------ unlock reveal

## What beating `boss` opens up, read from the data: maps whose card "requires" it, then
## characters whose "requires_boss" is it. [{tag, name, hint, color}]
static func unlocks_for(boss: String) -> Array:
	var out := []
	for m in MapPicker.MAPS:
		if m.get("requires", "") == boss:
			out.append({"tag": "NEW MAP", "name": m["name"], "hint": "Choose it after Play", "color": Color(0.45, 0.85, 1.0)})
	var f := FileAccess.open("res://data/characters.json", FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f else null
	if data is Dictionary:
		for c in data.get("characters", []):
			if c.get("requires_boss", "") == boss:
				out.append({"tag": "NEW CHAMPION", "name": c["name"], "color": Color(1.0, 0.62, 0.25),
					"hint": I18n.t("Now for sale in Characters: %s coins") % Wallet.fmt(int(c.get("price", 0)))})
	return out


## The "UNLOCKED!" block of the end screen: each unlock is a card that flies in from off
## screen on a swirling spiral (spinning, growing, trailing sparks) and lands in its slot with
## a pop, a flash and a ding, one after another.
func show_unlocks(items: Array) -> void:
	for c in end_unlocks.get_children():
		c.queue_free()
	for c in unlock_cards:
		c.queue_free()
	unlock_cards.clear()
	_unlock_slots.clear()
	end_unlocks.visible = not items.is_empty()
	if items.is_empty():
		return
	var head := _label("UNLOCKED!", 34)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	head.modulate.a = 0.0
	end_unlocks.add_child(head)
	var htw := create_tween()
	htw.tween_interval(0.4)
	htw.tween_property(head, "modulate:a", 1.0, 0.4)
	for k in items.size():
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(660, 66)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		end_unlocks.add_child(slot)
		_unlock_slots.append(slot)
		var card := _unlock_card(items[k])
		card.modulate.a = 0.0
		end_root.add_child(card)
		unlock_cards.append(card)
		get_tree().create_timer(0.8 + k * 0.65, true).timeout.connect(_fly_unlock.bind(k))


func _unlock_card(item: Dictionary) -> Control:
	var col: Color = item["color"]
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(660, 66)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.04, 0.95)
	sb.border_color = col
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(col, 0.45)
	sb.shadow_size = 12
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var tag := _label(item["tag"], 18)
	tag.add_theme_color_override("font_color", col)
	tag.custom_minimum_size = Vector2(150, 0)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(tag)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var name := _label(tr(str(item["name"])).to_upper(), 28)
	name.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	text.add_child(name)
	var hint := _label(item["hint"], 16)
	hint.add_theme_color_override("font_color", Color(0.8, 0.76, 0.7))
	text.add_child(hint)
	# Sparks trailing behind it while it flies
	var sparks := CPUParticles2D.new()
	sparks.name = "Sparks"
	sparks.amount = 60
	sparks.lifetime = 0.6
	sparks.local_coords = false
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sparks.emission_rect_extents = Vector2(300, 26)
	sparks.direction = Vector2(0, -1)
	sparks.spread = 180.0
	sparks.gravity = Vector2.ZERO
	sparks.initial_velocity_min = 20.0
	sparks.initial_velocity_max = 90.0
	sparks.scale_amount_min = 2.0
	sparks.scale_amount_max = 5.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	grad.set_color(1, Color(col, 0.0))
	sparks.color_ramp = grad
	sparks.emitting = false
	sparks.position = Vector2(330, 33)
	card.add_child(sparks)
	return card


func _fly_unlock(k: int) -> void:
	if k >= unlock_cards.size() or not end_root.visible:
		return
	var card := unlock_cards[k]
	var slot := _unlock_slots[k]
	card.size = slot.size
	card.pivot_offset = card.size * 0.5
	var target := slot.global_position
	var a0 := 2.2 * k + 0.6                 # each comes in from a different side
	var dir := 1.0 if k % 2 == 0 else -1.0  # and swirls the other way to the last one
	var reach := get_viewport().get_visible_rect().size.length() * 0.75
	var sparks := card.get_node("Sparks") as CPUParticles2D
	sparks.emitting = true
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var e := 1.0 - pow(1.0 - t, 3.0)
		var r := reach * (1.0 - e)
		var ang := a0 + dir * (1.0 - e) * TAU * 1.25
		card.global_position = target + Vector2(cos(ang), sin(ang)) * r
		card.rotation = dir * (1.0 - e) * TAU * 1.5
		card.scale = Vector2.ONE * lerpf(0.3, 1.0, e)
		card.modulate.a = clampf(t * 3.0, 0.0, 1.0), 0.0, 1.0, 1.2)
	tw.tween_callback(func():
		sparks.emitting = false
		card.global_position = target
		card.rotation = 0.0
		if _unlock_ding.stream:
			_unlock_ding.pitch_scale = 1.1 + 0.12 * k
			_unlock_ding.play()
		_land_burst(card))
	tw.tween_property(card, "scale", Vector2.ONE * 1.15, 0.08)
	tw.parallel().tween_property(card, "modulate", Color(1.8, 1.7, 1.3, 1.0), 0.08)
	tw.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "modulate", Color.WHITE, 0.45)


## A ring of sparks bursting out of a card as it lands.
func _land_burst(card: Control) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 70
	p.lifetime = 0.7
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(320, 30)
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 260)
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 320.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	grad.set_color(1, Color(1.0, 0.55, 0.15, 0.0))
	p.color_ramp = grad
	p.position = card.size * 0.5
	card.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0, true).timeout.connect(p.queue_free)


## Owned upgrades as icons with their level: weapons + items on the top row, tomes below,
## in the order you picked them up. Rebuilt only when something changes.
func _update_inventory() -> void:
	var gear := []
	var tomes := []
	for id in main.db.levels:
		var lv: int = main.db.levels[id]
		if lv <= 0:
			continue
		(tomes if main.db.defs[id]["kind"] == "tome" else gear).append([id, lv])
	var sig := str(gear) + str(tomes)
	if sig == _inv_sig:
		return
	_inv_sig = sig
	for c in inv_box.get_children():
		c.queue_free()
	for row in [gear, tomes]:
		if row.is_empty():
			continue
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inv_box.add_child(hb)
		for e in row:
			hb.add_child(_inv_chip(e[0], e[1]))


func _inv_chip(id: String, lv: int) -> Control:
	var d: Dictionary = main.db.defs[id]
	var chip := Control.new()
	chip.custom_minimum_size = Vector2(46, 46)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.tooltip_text = tr("%s  Lv %d") % [tr(d["name"]), lv]
	var icon := UpgradeIcon.create(d.get("icon", {}), d["kind"])
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	chip.add_child(icon)
	var n := _label(str(lv), 15)
	n.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	n.offset_left = -22
	n.offset_top = -20
	n.offset_right = 2
	n.offset_bottom = 2
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.add_theme_constant_override("outline_size", 5)
	chip.add_child(n)
	return chip


## Plays a UI sound ("levelup", "hover", "pick", "pick_tome") on the SFX bus; works while paused.
func play_ui(kind: String) -> void:
	if not _ui_players.has(kind):
		var p := AudioStreamPlayer.new()
		p.bus = Settings.SFX_BUS
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.max_polyphony = 3
		var path: String = UI_SOUNDS.get(kind, "")
		if path != "" and ResourceLoader.exists(path):
			p.stream = load(path)
		add_child(p)
		_ui_players[kind] = p
	var player: AudioStreamPlayer = _ui_players[kind]
	if player.stream != null:
		player.play()


func flash_message(text: String, duration := 3.0) -> void:
	msg_label.text = text
	_msg_t = duration


func toggle_debug() -> void:
	show_debug = not show_debug
	debug_label.visible = show_debug


## Start the 00:00 -> 10:00 spin-up (main calls this when the entrance begins).
func start_clock_spin() -> void:
	_spin_t = 0.0
	_tick_cd = 0.0


func _clock_text(dt: float) -> String:
	if main.endless:
		return _fmt_time(main.run_time)
	if _spin_t >= 0.0:
		_spin_t += dt
		var k := clampf((_spin_t - SPIN_DELAY) / SPIN_TIME, 0.0, 1.0)
		if k >= 1.0:
			if timer_label.scale == Vector2.ONE and not timer_label.has_meta("locked"):
				timer_label.set_meta("locked", true)
				play_ui("timer_set")
				timer_label.pivot_offset = timer_label.size * 0.5
				var tw := create_tween()
				tw.tween_property(timer_label, "scale", Vector2.ONE * 1.35, 0.08)
				tw.tween_property(timer_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if not main.intro:
				_spin_t = -1.0   # the run has started: the clock is live
			return _fmt_time(main.RUN_LENGTH)
		if k > 0.0:
			_tick_cd -= dt
			if _tick_cd <= 0.0:
				_tick_cd = TICK_EVERY
				var tp: AudioStreamPlayer = _ui_players.get("timer_tick")
				if tp:
					tp.pitch_scale = 0.9 + 0.5 * k
				play_ui("timer_tick")
		# ease-out: races at first, slows as it nears 10:00 (whole seconds, like a real counter)
		return _fmt_time(floorf(main.RUN_LENGTH * (1.0 - pow(1.0 - k, 2.2))))
	var left := maxf(0.0, main.RUN_LENGTH - main.run_time)
	if left <= 0.0:
		timer_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	return _fmt_time(ceilf(left))


static func _fmt_time(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]


func _process(dt: float) -> void:
	if end_root != null and end_root.visible and _pay_started:
		# The pot counts down as the coins land in the counter
		var landed := int(round(Wallet.displayed - _pay_base))
		_pot_left = maxi(0, int(run_reward["total"]) - landed)
		end_pot.text = "+" + Wallet.fmt(_pot_left)
		end_pot_icon.spin = fmod(end_pot_icon.spin + dt * 1.5, 1.0) if _pot_left > 0 else 0.0
	if main == null or main.player == null:
		return
	var p: Player = main.player
	hp_bar.max_value = p.max_hp
	hp_bar.value = p.hp
	hp_label.text = "%d / %d" % [ceili(p.hp), roundi(p.max_hp)]
	shield_bar.visible = p.shield > 0.5
	if shield_bar.visible:
		hp_label.text += "   " + tr("+%d shield") % ceili(p.shield)
		shield_bar.max_value = p.max_hp
		shield_bar.value = minf(p.shield, p.max_hp)
	xp_bar.max_value = main.xp_next
	xp_bar.value = main.xp
	level_label.text = tr("LV %d") % main.level
	timer_label.text = _clock_text(get_process_delta_time())
	info_label.text = tr("Kills %d\nEnemies %d\nSpeed %.1f m/s") % [main.kills, main.enemies.alive_count(), p.horizontal_speed()]
	if Settings.show_fps:
		info_label.text += "\nFPS %d" % Engine.get_frames_per_second()

	var lines := []
	for id in main.db.order:
		var lv: int = main.db.level_of(id)
		if lv > 0 and main.db.defs[id]["kind"] != "tome":
			lines.append(tr("%s  Lv %d") % [tr(main.db.defs[id]["name"]), lv])
	var tomes := 0
	for id in main.db.levels:
		if main.db.defs[id]["kind"] == "tome":
			tomes += main.db.levels[id]
	if tomes > 0:
		lines.append(tr("Tomes ×%d") % tomes)
	inv_label.text = "\n".join(lines)
	_update_inventory()

	_update_tooltip()
	_update_popups(dt)
	var held: PackedInt32Array = main.keys.keys
	key_box.visible = held[0] + held[1] + held[2] > 0
	for t in 3:
		key_labels[t].visible = held[t] > 0
		key_labels[t].text = tr("%s x%d") % [tr(KeyManager.NAMES[t]), held[t]]
	if p.burn_left > 0.0:
		hp_label.text += "   " + tr("BURNING")
		hp_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	else:
		hp_label.remove_theme_color_override("font_color")
	buff_label.text = "[center]%s[/center]" % main.powerups.status_text()
	for i in ability_slots.size():
		ability_slots[i].set_locked(not main.abilities.is_unlocked(i))
		ability_slots[i].set_cooldown(main.abilities.fraction_remaining(i), main.abilities.cooldown[i])
		ability_slots[i].ab_level = main.abilities.ab_level[i]

	if show_debug:
		var pf: Dictionary = main.perf
		debug_label.text = "sim ms  enemies %.2f  weapons %.2f  gems %.2f\nprojectiles %d  gems %d  burning %d  potions %d\nhp mult %.2f  epic chance %d%%" % [
			pf["enemies"], pf["weapons"], pf["gems"], main.weapons.pc, main.gems.count, main.enemies.burning_count(), main.potions.count(), main.hp_mult(), roundi(main.epic_chance() * 100.0)]

	if _msg_t > 0.0:
		_msg_t -= dt
		msg_label.modulate.a = clampf(_msg_t, 0.0, 1.0)
