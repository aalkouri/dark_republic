extends SceneTree
## Saves the clips baked into rigged GLBs (tools/gen_rig_clips.py) as models/<id>/anims.res, the
## library RosterHero plays ("idle" and "run" loop).
##   godot --headless --path . --script res://tools/extract_clips.gd -- <id> [<id> ...]


func _initialize() -> void:
	for id in OS.get_cmdline_user_args():
		var path := "res://models/%s/%s.glb" % [id, id]
		var scene := (load(path) as PackedScene).instantiate()
		var ap: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
		var sk: Skeleton3D = scene.get_node_or_null("Armature/Skeleton3D")
		if ap == null or sk == null:
			print("FAIL %s: no clips or no Armature/Skeleton3D" % id)
			continue
		var lib := AnimationLibrary.new()
		for an in ap.get_animation_list():
			var anim: Animation = ap.get_animation(an).duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR if an in ["idle", "run"] else Animation.LOOP_NONE
			lib.add_animation(an, anim)
		ResourceSaver.save(lib, "res://models/%s/anims.res" % id)
		print("%s: %d bones, clips %s" % [id, sk.get_bone_count(), ", ".join(lib.get_animation_list())])
		scene.free()
	quit()
