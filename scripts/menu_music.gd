extends Node
## Autoload "MenuMusic": the menu theme ("Menu of Shadows"), looping. Shared by the title screen
## and character select so the song carries on uninterrupted between them; it fades out only when
## a run starts.

const TRACK := "res://audio/music/menu_of_shadows.mp3"
const VOLUME_DB := -6.0

var player: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	player.bus = Settings.MUSIC_BUS
	player.volume_db = VOLUME_DB
	if ResourceLoader.exists(TRACK):
		var stream := (load(TRACK) as AudioStreamMP3).duplicate() as AudioStreamMP3
		stream.loop = true
		player.stream = stream
	add_child(player)


## Start the theme (fading in), or keep it going if it's already playing.
func play(fade_in := 0.6) -> void:
	if _tween:
		_tween.kill()
	if player.stream == null:
		return
	if not player.playing:
		player.volume_db = -40.0 if fade_in > 0.0 else VOLUME_DB
		player.play()
	if player.volume_db < VOLUME_DB:
		_tween = create_tween()
		_tween.tween_property(player, "volume_db", VOLUME_DB, maxf(fade_in, 0.01))


## Fade out and stop (leaving the menus for a run).
func fade_out(time := 0.45) -> void:
	if _tween:
		_tween.kill()
	if not player.playing:
		return
	_tween = create_tween()
	_tween.tween_property(player, "volume_db", -40.0, time)
	_tween.tween_callback(player.stop)
