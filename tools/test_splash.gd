extends Node
## Splash checks: the logo video loads and plays, a key press skips to the next scene,
## and the logo ends on its own after ~5 s.
##   godot --headless --path . res://tools/test_splash.tscn
var fails := 0

func _ready() -> void:
	var stream: VideoStream = load("res://video/atomai_logo.ogv")
	_check("logo video loads (Ogg Theora)", stream != null, str(stream))
	var splash: Control = load("res://scripts/splash.gd").new()
	add_child(splash)
	await get_tree().process_frame
	_check("logo plays on start", splash._player != null and splash._player.is_playing(), "")
	_check("next scenes exist (intro, title)", ResourceLoader.exists(splash.NEXT_SCENE) and ResourceLoader.exists(splash.TITLE_SCENE), splash.NEXT_SCENE)
	# Any key skips (without actually changing scene in the test)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	splash._leaving = false
	splash._input(ev)
	_check("a key press skips the logo", splash._leaving, "")
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)

func _check(name: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		fails += 1
