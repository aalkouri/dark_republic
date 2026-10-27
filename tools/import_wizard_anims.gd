extends SceneTree
## One-off importer: pulls the animation clip out of each Meshy/Higgsfield GLB (each file is
## the same rigged wizard with one clip) and saves them all as one AnimationLibrary.
##   godot --headless --path . --script res://tools/import_wizard_anims.gd -- <dir with .glb files>
## Clip names come from the Meshy action name inside each file.

const OUT := "res://models/wizard/wizard_anims.res"
const NAMES := {
	"Idle": "idle", "Casual_Walk": "walk", "Run_02": "run", "Regular_Jump": "jump",
	"Hit_Reaction": "hit", "mage_soell_cast_1": "cast", "Charged_Ground_Slam": "nova",
	"Charged_Spell_Cast": "inferno", "mage_soell_cast_2": "meteor",
}
const LOOPING := ["idle", "walk", "run"]
const LOCK_ROOT_XZ := ["idle", "walk", "run", "hit"]   # strip root drift (in-place)
const LOCK_ROOT_XYZ := ["jump"]                         # the physics does the jumping


func _init() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	var lib := AnimationLibrary.new()
	if ResourceLoader.exists(OUT):
		lib = load(OUT)
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".glb"):
			continue
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(dir.path_join(f), state) != OK:
			push_error("can't read " + f)
			continue
		var scene := doc.generate_scene(state)
		var ap := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for an in ap.get_animation_list():
			var raw := an.split("|")[1] if "|" in an else an
			if not NAMES.has(raw):
				print("skip ", raw)
				continue
			var key: String = NAMES[raw]
			var anim := (ap.get_animation(an) as Animation).duplicate(true) as Animation
			anim.loop_mode = Animation.LOOP_LINEAR if key in LOOPING else Animation.LOOP_NONE
			if key in LOCK_ROOT_XZ or key in LOCK_ROOT_XYZ:
				_lock_root(anim, key in LOCK_ROOT_XYZ)
			lib.add_animation(key, anim)
			print("clip %-8s %.2fs  tracks %d  path %s" % [key, anim.length, anim.get_track_count(), anim.track_get_path(0)])
		scene.free()
	ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
	print("saved ", OUT, " clips: ", lib.get_animation_list())
	quit()


func _lock_root(anim: Animation, lock_y: bool) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not str(anim.track_get_path(t)).ends_with(":Hips"):
			continue
		var first: Vector3 = anim.track_get_key_value(t, 0)
		for k in anim.track_get_key_count(t):
			var v: Vector3 = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, Vector3(first.x, first.y if lock_y else v.y, first.z))
