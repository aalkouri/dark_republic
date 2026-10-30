extends Node
## Intro (the anime short): after the studio logo the splash goes to the intro (unless
## Settings > Gameplay turns it off); it plays video/intro_anime.ogv (~30 s, sound effects on the
## SFX bus), and any key, click or pad button skips to the title.
##   godot --headless --path . res://tools/test_intro.tscn

var fails := 0


func _ready() -> void:
	var splash: Control = load("res://scripts/splash.gd").new()
	Settings.play_intro = true
	_check("splash goes to the intro", splash.next_scene() == "res://scenes/intro.tscn", splash.next_scene())
	Settings.play_intro = false
	_check("...or straight to the title when the intro is turned off", splash.next_scene() == "res://scenes/title.tscn", splash.next_scene())
	Settings.play_intro = true
	splash.free()

	var intro: Node = load("res://scenes/intro.tscn").instantiate()
	add_child(intro)
	for f in 5:
		await get_tree().process_frame
	_check("about 30 seconds long", intro.LENGTH >= 28.0 and intro.LENGTH <= 33.0, str(intro.LENGTH))
	_check("the anime video is loaded", intro._player != null and intro._player.stream != null, "")
	_check("its sound plays on the SFX bus", intro._player.bus == Settings.SFX_BUS, intro._player.bus)
	_check("the coin counter is hidden during the intro", not Wallet.panel.visible, "")
	var v: VideoStream = load(intro.VIDEO)
	_check("video file is in the project", v != null, intro.VIDEO)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	intro._input(ev)
	_check("any key skips (fades to the title)", intro._leaving and intro.NEXT_SCENE == "res://scenes/title.tscn", "")
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
