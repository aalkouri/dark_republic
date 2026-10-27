extends SceneTree
## Imports a roster character from Higgsfield/Meshy GLBs (the same rigged model, one clip per
## file): copies the first GLB in as models/<id>/<id>.glb and merges every clip into
## models/<id>/anims.res as idle / run / hit / attack / ability.
##   godot --headless --path . --script res://tools/import_character.gd -- <id> <dir with .glb files>
## Run `godot --headless --path . --import` afterwards so the new GLB is imported.

const KEYS := {
	"Idle": "idle", "Run_02": "run", "Run_03": "run", "RunFast": "run", "Hit_Reaction": "hit",
	"mage_soell_cast_3": "attack", "mage_soell_cast_4": "attack", "mage_soell_cast_5": "attack",
	"mage_soell_cast_6": "attack", "mage_soell_cast_7": "attack", "mage_soell_cast_8": "ability",
	"Charged_Spell_Cast": "ability", "Charged_Spell_Cast_1": "ability", "Charged_Ground_Slam": "ability",
	"Heavy_Hammer_Swing": "attack", "Side_Shot": "attack", "Draw_and_Shoot_Left": "ability",
	"Thrust_Slash": "attack", "Sword_Judgment": "ability", "Double_Combo_Attack": "attack",
	"Double_Blade_Spin": "ability", "Left_Slash": "attack", "Charged_Slash": "ability",
	"Over_Shoulder_Throw": "attack", "Crouch_Charge_and_Throw": "ability",
}
const LOOPING := ["idle", "run"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0]
	var src: String = args[1]
	var out_dir := "res://models/%s" % id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var lib := AnimationLibrary.new()
	var copied := false
	var files := Array(DirAccess.get_files_at(src)).filter(func(f): return f.ends_with(".glb"))
	files.sort()
	for f in files:
		var path := src.path_join(f)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			push_error("can't read " + f)
			continue
		var scene := doc.generate_scene(state)
		var aps := scene.find_children("*", "AnimationPlayer", true, false)
		var key := ""
		if not aps.is_empty():
			var ap := aps[0] as AnimationPlayer
			for an in ap.get_animation_list():
				var raw := an.split("|")[1] if "|" in an else str(an)
				if not KEYS.has(raw):
					print("skip clip ", raw)
					continue
				key = KEYS[raw]
				var anim := (ap.get_animation(an) as Animation).duplicate(true) as Animation
				anim.loop_mode = Animation.LOOP_LINEAR if key in LOOPING else Animation.LOOP_NONE
				if key in ["idle", "run", "hit"]:
					_lock_root_xz(anim)
				lib.add_animation(key, anim)
				print("clip %-8s %-24s %.2fs" % [key, raw, anim.length])
		# The idle file (or the first file) becomes the model
		if not copied and (key == "idle" or f == files[-1] or aps.is_empty()):
			DirAccess.copy_absolute(path, ProjectSettings.globalize_path(out_dir.path_join(id + ".glb")))
			copied = true
		scene.free()
	if not copied and not files.is_empty():
		DirAccess.copy_absolute(src.path_join(files[0]), ProjectSettings.globalize_path(out_dir.path_join(id + ".glb")))
	if lib.get_animation_list().size() > 0:
		ResourceSaver.save(lib, out_dir.path_join("anims.res"), ResourceSaver.FLAG_COMPRESS)
	print("imported %s: %s" % [id, lib.get_animation_list()])
	quit()


func _lock_root_xz(anim: Animation) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and str(anim.track_get_path(t)).ends_with(":Hips"):
			var first: Vector3 = anim.track_get_key_value(t, 0)
			for k in anim.track_get_key_count(t):
				var v: Vector3 = anim.track_get_key_value(t, k)
				anim.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))
