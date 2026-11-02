extends Node
## Screenshot of the loading screen while a run loads behind it:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . \
##     res://tools/shot_loading.tscn -- --out=/tmp/load.png [--map=forest] [--char=ice_wizard]
##     [--to=title] [--lang=es] [--wait=1.5]
## Loader.hold keeps the overlay up after the run is ready; the picture is taken `wait` s after
## Loader.go(), while the run is still loading behind it.

func _ready() -> void:
	var out := "/tmp/load.png"
	var dest := "res://scenes/main.tscn"
	var wait := 1.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.split("=")[1]
		elif a.begins_with("--map="):
			Settings.selected_map = a.split("=")[1]
		elif a.begins_with("--char="):
			Settings.selected_character = a.split("=")[1]
		elif a.begins_with("--to="):
			dest = "res://scenes/%s.tscn" % a.split("=")[1]
		elif a.begins_with("--wait="):
			wait = float(a.split("=")[1])
		elif a.begins_with("--lang="):
			TranslationServer.set_locale(a.split("=")[1])
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	Loader.hold = true
	Loader.go(dest)
	await get_tree().create_timer(wait, true, false, true).timeout   # mid-load (or after: hold keeps it up)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("SHOT saved ", out)
	get_tree().quit()
