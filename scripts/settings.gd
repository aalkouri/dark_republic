extends Node
## Player settings (autoload "Settings"): audio buses, video options, controls and key
## bindings. Saved to user://settings.cfg and applied on startup.
##
## Audio: two buses under Master - "Music" (the level music) and "SFX" (everything else).
## Each has its own volume and mute.
##
## Changes from the settings menu apply live (so you can hear/see them) but are only saved
## when you press Apply; closing the menu without applying reverts them (snapshot/restore).
##
## Language: data/i18n/<locale>.json maps English text -> translation. Every Control/Label3D
## translates its text automatically; code that builds text from parts calls tr().

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

## Language choices: [locale, name shown in the dropdown (in that language)].
const LANGUAGES := [
	["en", "English"], ["es", "Español"], ["fr", "Français"], ["ar", "العربية"],
	["de", "Deutsch"], ["zh_CN", "中文 (简体)"], ["ja", "日本語"],
]
const I18N_DIR := "res://data/i18n/"

## Character picked on the character select screen (session only, not saved).
var selected_character := "fire_wizard"
var selected_map := "swamp"            # "swamp" or "forest" (MapPicker, before a run)
## Mode picked from the title's Play menu (session only): "classic" - survive 10 minutes;
## "unrelenting" - no time limit, the clock counts up and everything keeps getting harder.
var game_mode := "classic"

# Gameplay
var language := "en"
var play_intro := true       # the cinematic after the studio logo
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
	load_translations()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):   # screenshots/tests: this session only (not saved)
			language = a.split("=")[1]
	apply_language()
	# (Layouts stay left-to-right for Arabic too: project setting
	# internationalization/rendering/root_node_layout_direction = Left-to-Right.)
	apply_audio()
	apply_video()


# ------------------------------------------------------------------ language

## Register one Translation per language file (English needs none: it is the source text).
func load_translations() -> void:
	for entry in LANGUAGES:
		var loc: String = entry[0]
		var path := I18N_DIR + loc + ".json"
		if loc == "en" or not FileAccess.file_exists(path):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (d is Dictionary):
			continue
		var t := Translation.new()
		t.locale = loc
		for k in d:
			if str(d[k]) != "":
				t.add_message(k, d[k])
		TranslationServer.add_translation(t)


func apply_language() -> void:
	TranslationServer.set_locale(language)


## Right-to-left script (Arabic): text is shaped RTL; layouts stay as designed.
func is_rtl() -> bool:
	return language == "ar"


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


# ------------------------------------------------------------------ persistence

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("gameplay", "language", language)
	cf.set_value("gameplay", "play_intro", play_intro)
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
	language = cf.get_value("gameplay", "language", language)
	play_intro = cf.get_value("gameplay", "play_intro", play_intro)
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


## Set a value by name, apply it live and notify (used by the settings menu). Not saved
## until commit(); language waits for commit() too (it re-translates every screen).
func set_value(key: String, value) -> void:
	set(key, value)
	if key.begins_with("music") or key.begins_with("sfx"):
		apply_audio()
	elif key in ["window_mode", "vsync", "render_scale", "max_fps"]:
		apply_video()
	changed.emit()


const SAVED_KEYS := ["language", "play_intro", "music_volume", "music_muted", "sfx_volume", "sfx_muted",
	"window_mode", "vsync", "render_scale", "fov", "max_fps", "show_fps",
	"mouse_sensitivity", "invert_y", "bindings"]


## The saved state, to compare against (is_dirty) or go back to (restore).
func snapshot() -> Dictionary:
	var d := {}
	for k in SAVED_KEYS:
		var v = get(k)
		d[k] = v.duplicate() if v is Dictionary else v
	return d


func is_dirty(snap: Dictionary) -> bool:
	for k in SAVED_KEYS:
		if get(k) != snap[k]:
			return true
	return false


## Apply: save everything and switch the language.
func commit() -> void:
	save_settings()
	if TranslationServer.get_locale() != language:
		apply_language()
	changed.emit()


## Discard unapplied changes.
func restore(snap: Dictionary) -> void:
	var keys_changed: bool = bindings != snap["bindings"]
	for k in SAVED_KEYS:
		var v = snap[k]
		set(k, v.duplicate() if v is Dictionary else v)
	apply_audio()
	apply_video()
	if keys_changed:
		for entry in REBINDABLE:
			InputMap.erase_action(entry[0])
		load("res://scripts/main.gd").setup_inputs()
		apply_bindings()
	changed.emit()
