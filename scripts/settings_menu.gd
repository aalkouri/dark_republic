class_name SettingsMenu
extends Control
## Settings screen with Video, Sound and Controls tabs. Built in code; every change is
## applied immediately and saved through the Settings autoload.

signal closed

var _tabs: TabContainer
var _bind_buttons := {}       # action -> Button
var _waiting_action := ""     # action currently waiting for a key press


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 560)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.06, 0.96)
	sb.border_color = Color(1.0, 0.45, 0.15, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 20)
	vb.add_child(_tabs)
	_tabs.add_child(_video_tab())
	_tabs.add_child(_sound_tab())
	_tabs.add_child(_controls_tab())

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(180, 44)
	back.add_theme_font_size_override("font_size", 20)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	vb.add_child(back)


func open() -> void:
	visible = true
	_refresh_bindings()


func close() -> void:
	_waiting_action = ""
	visible = false
	closed.emit()


## Returns true if the menu consumed this Esc press (e.g. cancelling a rebind).
func handle_escape() -> bool:
	if _waiting_action != "":
		_waiting_action = ""
		_refresh_bindings()
		return true
	close()
	return true


# ------------------------------------------------------------------ tabs

func _tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	scroll.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)
	return vb


func _video_tab() -> Control:
	var vb := _tab("Video")
	var mode := OptionButton.new()
	for t in ["Windowed", "Fullscreen", "Borderless fullscreen"]:
		mode.add_item(t)
	mode.selected = Settings.window_mode
	mode.item_selected.connect(func(i: int): Settings.set_value("window_mode", i))
	_row(vb, "Display mode", mode)
	_row(vb, "VSync", _check(Settings.vsync, func(on: bool): Settings.set_value("vsync", on)))
	_row(vb, "Render scale", _slider(0.5, 1.0, 0.05, Settings.render_scale, func(v: float): Settings.set_value("render_scale", v), "%d%%", 100.0))
	_row(vb, "Field of view", _slider(60.0, 100.0, 1.0, Settings.fov, func(v: float): Settings.set_value("fov", v), "%d°"))
	var fps := OptionButton.new()
	var caps := [0, 30, 60, 120, 144, 240]
	for c in caps:
		fps.add_item("Unlimited" if c == 0 else str(c))
	fps.selected = maxi(0, caps.find(Settings.max_fps))
	fps.item_selected.connect(func(i: int): Settings.set_value("max_fps", caps[i]))
	_row(vb, "FPS limit", fps)
	_row(vb, "Show FPS counter", _check(Settings.show_fps, func(on: bool): Settings.set_value("show_fps", on)))
	return vb.get_parent().get_parent()


func _sound_tab() -> Control:
	var vb := _tab("Sound")
	_volume_row(vb, "Music", "music_volume", "music_muted")
	_volume_row(vb, "All other audio", "sfx_volume", "sfx_muted")
	var note := Label.new()
	note.text = "\"All other audio\" covers enemy sounds, hits and effects."
	note.modulate.a = 0.6
	note.add_theme_font_size_override("font_size", 15)
	vb.add_child(note)
	return vb.get_parent().get_parent()


func _volume_row(vb: VBoxContainer, label: String, vol_key: String, mute_key: String) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var l := _label(label)
	l.custom_minimum_size.x = 190
	hb.add_child(l)
	var mute := _check(Settings.get(mute_key), func(on: bool): Settings.set_value(mute_key, on))
	mute.text = "Mute"
	# Moving the volume slider un-mutes that bar (you clearly want to hear it)
	var slider := _slider(0.0, 1.0, 0.01, Settings.get(vol_key), func(v: float):
		Settings.set_value(vol_key, v)
		if mute.button_pressed:
			mute.button_pressed = false, "%d%%", 100.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(slider)
	hb.add_child(mute)
	vb.add_child(hb)


func _controls_tab() -> Control:
	var vb := _tab("Controls")
	_row(vb, "Mouse sensitivity", _slider(0.2, 3.0, 0.05, Settings.mouse_sensitivity, func(v: float): Settings.set_value("mouse_sensitivity", v), "%.2fx"))
	_row(vb, "Invert Y axis", _check(Settings.invert_y, func(on: bool): Settings.set_value("invert_y", on)))
	var hdr := _label("Key bindings  (click, then press a key; Esc cancels)")
	hdr.modulate.a = 0.7
	vb.add_child(hdr)
	for entry in Settings.REBINDABLE:
		var action: String = entry[0]
		var b := Button.new()
		b.custom_minimum_size = Vector2(220, 36)
		b.pressed.connect(func(): _start_rebind(action))
		_bind_buttons[action] = b
		_row(vb, entry[1], b)
	var reset := Button.new()
	reset.text = "Reset keys to defaults"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(_reset_keys)
	vb.add_child(reset)
	_refresh_bindings()
	return vb.get_parent().get_parent()


# ------------------------------------------------------------------ rebinding

func _start_rebind(action: String) -> void:
	_waiting_action = action
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if not visible or _waiting_action == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_ESCAPE:
			_waiting_action = ""
		else:
			Settings.rebind(_waiting_action, event.physical_keycode)
			_waiting_action = ""
		_refresh_bindings()


func _reset_keys() -> void:
	Settings.reset_bindings()
	for entry in Settings.REBINDABLE:
		InputMap.erase_action(entry[0])
	load("res://scripts/main.gd").setup_inputs()
	_refresh_bindings()


func _refresh_bindings() -> void:
	for action in _bind_buttons:
		var b: Button = _bind_buttons[action]
		b.text = "Press a key..." if action == _waiting_action else Settings.key_text(action)


# ------------------------------------------------------------------ widgets

func _row(vb: VBoxContainer, label: String, control: Control) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var l := _label(label)
	l.custom_minimum_size.x = 260
	hb.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(control)
	vb.add_child(hb)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	return l


func _check(on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.button_pressed = on
	c.toggled.connect(cb)
	return c


## Slider with a live value label. `fmt` formats value * `mult` (e.g. "%d%%" with 100).
func _slider(lo: float, hi: float, step: float, value: float, cb: Callable, fmt: String, mult := 1.0) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size.x = 200
	var v := Label.new()
	v.custom_minimum_size.x = 64
	v.add_theme_font_size_override("font_size", 16)
	var update := func(x: float):
		v.text = fmt % (x * mult)
	update.call(value)
	s.value_changed.connect(func(x: float):
		update.call(x)
		cb.call(x))
	hb.add_child(s)
	hb.add_child(v)
	return hb
