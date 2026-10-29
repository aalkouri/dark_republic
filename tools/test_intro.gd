extends Node
## Intro cinematic ("The Sock Incident"): after the studio logo the splash goes to the intro
## (unless Settings > Gameplay turns it off); it has the cast and the horde, runs ~30 s, and
## any key, click or pad button skips to the title.
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
	_check("the wizard is asleep by the fire", intro._wizard != null, "")
	var cast := ["ogre", "vicki", "gaiden", "ghast", "dr_croc"]
	_check("heroes answer the call: " + ", ".join(cast), cast.all(func(id): return intro._heroes.has(id)), str(intro._heroes.keys()))
	_check("a goblin horde (and the sock thief)", intro._horde.size() >= 100 and intro._thief != null, str(intro._horde.size()))
	_check("the title card is there for the end", intro._title != null and intro._title.text == "DARK REPUBLIC", "")
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
