extends Control
## Intro: the 30-second anime short (video/intro_anime.ogv, made with Higgsfield from the game's
## character models). Five fire-wizard-led heroes asleep in the castle barracks wake to a
## stampede, rush to the wall, see Thog and the goblin horde, and the wizard ends it as the Meteor.
## Plays after the studio logo (unless Settings > Gameplay turns it off), with its sound effects on
## the SFX bus. Any key, click or gamepad button skips to the title.

const VIDEO := "res://video/intro_anime.ogv"
const NEXT_SCENE := "res://scenes/title.tscn"
const LENGTH := 30.2          # seconds, for reference (the video's own end drives the exit)
const FADE_OUT := 0.6         # the video ends on a white flash; fade from it into the title

var _player: VideoStreamPlayer
var _fade: ColorRect
var _leaving := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Wallet.set_shown(false)   # the coin counter comes back on the title screen
	var bg := ColorRect.new()
	bg.color = Color.BLACK   # letterboxing on non-16:9 windows
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_player = VideoStreamPlayer.new()
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.expand = true
	_player.bus = Settings.SFX_BUS
	if ResourceLoader.exists(VIDEO):
		_player.stream = load(VIDEO)
	add_child(_player)
	_fade = ColorRect.new()
	_fade.color = Color(1, 1, 1, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_player.finished.connect(_finish)
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


## Played to the end: hold the white flash, then cut to the title (which fades in on its own).
func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	_fade.color = Color(1, 1, 1, 1)
	get_tree().change_scene_to_file.call_deferred(NEXT_SCENE)


## Skipped: stop the video and fade to black into the title.
func _go() -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.BLACK, FADE_OUT * 0.6)
	tw.tween_callback(func():
		if _player:
			_player.stop()
		get_tree().change_scene_to_file(NEXT_SCENE))
