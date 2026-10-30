extends Control
## Startup splash: plays the AtomAI studio logo, then the anime intro (scenes/intro.tscn,
## unless turned off in Settings > Gameplay), then the title.
## Any key, mouse click or gamepad button skips it. Test/screenshot runs skip it automatically.

const LOGO := "res://video/atomai_logo.ogv"
const NEXT_SCENE := "res://scenes/intro.tscn"
const TITLE_SCENE := "res://scenes/title.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const FADE_OUT := 0.35

var _player: VideoStreamPlayer
var _leaving := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--smoketest" or a.begins_with("--shot"):
			get_tree().change_scene_to_file.call_deferred(GAME_SCENE)   # tests go straight in
			return
		if a == "--skip-intro":   # straight to the title (no logo, no cinematic)
			get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)
			return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Wallet.set_shown(false)   # the coin counter appears from the title screen on
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.12)   # matches the logo's navy, so letterboxing is invisible
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_player = VideoStreamPlayer.new()
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.expand = true
	_player.bus = Settings.MUSIC_BUS
	if ResourceLoader.exists(LOGO):
		_player.stream = load(LOGO)
	add_child(_player)
	_player.finished.connect(_go)
	if _player.stream == null:
		_go.call_deferred()
		return
	_player.play()


func _input(event: InputEvent) -> void:
	if _leaving:
		return
	var skip: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if skip:
		get_viewport().set_input_as_handled()
		_go()


func _go() -> void:
	if _leaving:
		return
	_leaving = true
	if _player and _player.is_playing():
		var tw := create_tween()
		tw.tween_property(self, "modulate", Color.BLACK, FADE_OUT)
		tw.tween_callback(func(): get_tree().change_scene_to_file(next_scene()))
	else:
		get_tree().change_scene_to_file(next_scene())


func next_scene() -> String:
	return NEXT_SCENE if Settings.play_intro else TITLE_SCENE
