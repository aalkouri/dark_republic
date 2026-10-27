extends Node
## Player settings (autoload "Settings"): audio buses, video options, controls and key
## bindings. Saved to user://settings.cfg and applied on startup.
##
## Audio: two buses under Master - "Music" (the level music) and "SFX" (everything else).
## Each has its own volume and mute.

signal changed

const PATH := "user://settings.cfg"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

## Actions shown on the Controls tab, in order, with display names.
const REBINDABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"],
	["move_left", "Move left"], ["move_right", "Move right"],
	["jump", "Jump"], ["slide", "Slide"],
	["ability_1", "Ability 1 - Inferno"], ["ability_2", "Ability 2 - Fire Nova"],
	["ability_3", "Ultimate - Meteor"], ["pause", "Pause / menu"],
	["inspect", "Inspect abilities (hold)"],
]

## Character picked on the character select screen (session only, not saved).
var selected_character := "fire_wizard"

# Sound
var music_volume := 0.8      # 0..1 (linear)
var music_muted := false
var sfx_volume := 1.0
var sfx_muted := false
# Video
var window_mode := 0         # 0 windowed, 1 fullscreen, 2 borderless fullscreen
var vsync := true
var render_scale := 1.0      # 0.5..1.0
var fov := 75.0
var max_fps := 0             # 0 = unlimited
var show_fps := true
# Controls
var mouse_sensitivity := 1.0 # multiplier
var invert_y := false
var bindings := {}           # action -> physical keycode (only for remapped actions)


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	load_settings()
	apply_audio()
	apply_video()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


# ------------------------------------------------------------------ apply

func apply_audio() -> void:
	_set_bus(MUSIC_BUS, music_volume, music_muted)
	_set_bus(SFX_BUS, sfx_volume, sfx_muted)


func _set_bus(bus_name: String, vol: float, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(vol, 0.0001)))
	AudioServer.set_bus_mute(idx, muted or vol <= 0.001)


func apply_video() -> void:
	Engine.max_fps = max_fps
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = render_scale
	if DisplayServer.get_name() == "headless":
		return
	match window_mode:
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Re-apply saved key remaps on top of the defaults (call after the default InputMap exists).
func apply_bindings() -> void:
	for action in bindings:
		if InputMap.has_action(action):
			_set_key(action, int(bindings[action]))


func rebind(action: String, keycode: int) -> void:
	_set_key(action, keycode)
	bindings[action] = keycode
	save_settings()
	changed.emit()


func _set_key(action: String, keycode: int) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	var k := InputEventKey.new()
	k.physical_keycode = keycode
	InputMap.action_add_event(action, k)


## Display text for an action's keyboard binding(s), e.g. "W / Up".
func key_text(action: String) -> String:
	var names := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			names.append(OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code) if DisplayServer.get_name() != "headless" else code))
	return " / ".join(names) if not names.is_empty() else "-"


func reset_bindings() -> void:
	bindings.clear()
	save_settings()


# ------------------------------------------------------------------ persistence

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("sound", "music_volume", music_volume)
	cf.set_value("sound", "music_muted", music_muted)
	cf.set_value("sound", "sfx_volume", sfx_volume)
	cf.set_value("sound", "sfx_muted", sfx_muted)
	cf.set_value("video", "window_mode", window_mode)
	cf.set_value("video", "vsync", vsync)
	cf.set_value("video", "render_scale", render_scale)
	cf.set_value("video", "fov", fov)
	cf.set_value("video", "max_fps", max_fps)
	cf.set_value("video", "show_fps", show_fps)
	cf.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cf.set_value("controls", "invert_y", invert_y)
	cf.set_value("controls", "bindings", bindings)
	cf.save(PATH)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	music_volume = cf.get_value("sound", "music_volume", music_volume)
	music_muted = cf.get_value("sound", "music_muted", music_muted)
	sfx_volume = cf.get_value("sound", "sfx_volume", sfx_volume)
	sfx_muted = cf.get_value("sound", "sfx_muted", sfx_muted)
	window_mode = cf.get_value("video", "window_mode", window_mode)
	vsync = cf.get_value("video", "vsync", vsync)
	render_scale = cf.get_value("video", "render_scale", render_scale)
	fov = cf.get_value("video", "fov", fov)
	max_fps = cf.get_value("video", "max_fps", max_fps)
	show_fps = cf.get_value("video", "show_fps", show_fps)
	mouse_sensitivity = cf.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cf.get_value("controls", "invert_y", invert_y)
	bindings = cf.get_value("controls", "bindings", bindings)


## Set a value by name, apply it, save, and notify (used by the settings menu).
func set_value(key: String, value) -> void:
	set(key, value)
	if key.begins_with("music") or key.begins_with("sfx"):
		apply_audio()
	elif key in ["window_mode", "vsync", "render_scale", "max_fps"]:
		apply_video()
	save_settings()
	changed.emit()
