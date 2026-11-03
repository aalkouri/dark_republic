class_name ItemFound
extends Control
## "You found an item!": the card shown (game paused) when you pick up an item off the ground.
## The item's charm icon, its name in its rarity colour, NEW ITEM or LEVEL n, what it does and
## the stat lines it just added. Continue (or the Activate key / Enter / Space / Esc) to go on.

signal closed

var _done := false
var _t := 0.0
var _card: PanelContainer


func build(db: UpgradeDB, pick: Dictionary, before: int, lines: Array) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var d: Dictionary = db.defs[pick["id"]]
	var rarity: Dictionary = db.rarities[int(pick["rarity"])]
	var col := Color.html(str(rarity["color"]))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(460, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.055, 0.045, 0.97)
	sb.border_color = col
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(col, 0.4)
	sb.shadow_size = 18
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	_card.add_theme_stylebox_override("panel", sb)
	center.add_child(_card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	_card.add_child(box)
	box.add_child(_lbl(tr("ITEM FOUND!"), 22, Color(1.0, 0.9, 0.6)))
	var art := UpgradeIcon.create(d.get("icon", {}), "item")
	art.custom_minimum_size = Vector2(128, 128)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(art)
	box.add_child(_lbl(tr(str(d["name"])), 38, col.lightened(0.15)))
	var lv := before + 1
	var tag := tr("NEW ITEM") if before == 0 else (tr("LEVEL %d") % lv)
	var maxed: bool = lv >= int(d["max_level"])
	box.add_child(_lbl("%s   ·   %s%s" % [tr(str(rarity["name"])), tag, ("   ·   " + tr("MAX")) if maxed else ""], 22, col.lightened(0.3)))
	var desc := _lbl(db.text(str(d["desc"])), 22, Color(0.92, 0.9, 0.85))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(390, 0)
	box.add_child(desc)
	if not lines.is_empty():
		box.add_child(_lbl("\n".join(lines), 22, Color(0.6, 1.0, 0.65)))
	if before > 0:
		box.add_child(_lbl(tr("Lv %d → %d") % [before, lv], 18, Color(0.75, 0.75, 0.8)))
	var btn := Button.new()
	btn.text = tr("Continue")
	btn.add_theme_font_size_override("font_size", 24)
	btn.custom_minimum_size = Vector2(220, 52)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(_close)
	box.add_child(btn)
	_card.pivot_offset = Vector2(230, 260)
	_card.scale = Vector2.ONE * 0.6
	_card.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "modulate:a", 1.0, 0.18)
	btn.grab_focus.call_deferred()


func _lbl(text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(2, size / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(dt: float) -> void:
	_t += dt
	if _card:
		_card.pivot_offset = _card.size * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if _t < 0.35:   # don't let the key you were holding skip it
		return
	if event.is_action_pressed("activate") or event.is_action_pressed("pause") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if _done:
		return
	_done = true
	closed.emit()
