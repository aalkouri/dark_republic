extends SceneTree
## Re-targets another character's clips (models/<from>/anims.res) onto a model rigged with the
## same Meshy skeleton but a different rest pose (bone axes and proportions differ, so copying
## the local rotations straight across twists the body). Each frame, every bone's rotation away
## from its rest is taken in skeleton space and applied to the target's rest; the Hips' movement
## is scaled by the ratio of hip heights. Clips are resampled at 30 fps.
##   godot --headless --path . --script res://tools/retarget_clips.gd -- <from id> <target .glb> <out anims.res>

const FPS := 30.0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var src_sk := _skeleton("res://models/%s/%s.glb" % [a[0], a[0]])
	var dst_sk := _skeleton(a[1])
	var lib_in: AnimationLibrary = load("res://models/%s/anims.res" % a[0])
	var lib_out := AnimationLibrary.new()
	var hips_s := src_sk.find_bone("Hips")
	var hips_d := dst_sk.find_bone("Hips")
	var ratio := dst_sk.get_bone_global_rest(hips_d).origin.y / src_sk.get_bone_global_rest(hips_s).origin.y
	for an in lib_in.get_animation_list():
		var anim: Animation = lib_in.get_animation(an)
		lib_out.add_animation(an, _retarget(anim, src_sk, dst_sk, ratio))
		print("retargeted %-8s %.2fs" % [an, anim.length])
	ResourceSaver.save(lib_out, a[2], ResourceSaver.FLAG_COMPRESS)
	quit()


func _skeleton(path: String) -> Skeleton3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	doc.append_from_file(path, st)
	var scene := doc.generate_scene(st)
	return scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func _retarget(anim: Animation, s: Skeleton3D, d: Skeleton3D, ratio: float) -> Animation:
	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = anim.loop_mode
	var prefix := ""
	# Which source bones the clip drives (rotation tracks) and the Hips position track
	var rot_tracks := {}
	var hips_pos := -1
	for t in anim.get_track_count():
		var p := str(anim.track_get_path(t))
		prefix = p.get_slice(":", 0)
		var bone := p.get_slice(":", 1)
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot_tracks[bone] = t
		elif anim.track_get_type(t) == Animation.TYPE_POSITION_3D and bone == "Hips":
			hips_pos = t
	# Output tracks: every target bone, in order (parents before children)
	var out_rot := {}
	for b in d.get_bone_count():
		var n := d.get_bone_name(b)
		if s.find_bone(n) < 0:
			continue
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, NodePath("%s:%s" % [prefix, n]))
		out_rot[b] = t
	var out_hips := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(out_hips, NodePath("%s:Hips" % prefix))
	var hs := s.find_bone("Hips")
	var hd := d.find_bone("Hips")
	var frames := int(ceil(anim.length * FPS))
	for f in frames + 1:
		var time := minf(f / FPS, anim.length)
		# Source pose at this time: local rotations from the clip, rest where it has none
		var s_glob: Array[Quaternion] = []
		s_glob.resize(s.get_bone_count())
		for b in s.get_bone_count():
			var n := s.get_bone_name(b)
			var lq := s.get_bone_rest(b).basis.get_rotation_quaternion()
			if rot_tracks.has(n):
				lq = anim.rotation_track_interpolate(rot_tracks[n], time)
			var par := s.get_bone_parent(b)
			s_glob[b] = (s_glob[par] * lq) if par >= 0 else lq
		# Target: the same rotation away from rest, in skeleton space
		var d_glob: Array[Quaternion] = []
		d_glob.resize(d.get_bone_count())
		for b in d.get_bone_count():
			var n := d.get_bone_name(b)
			var rest_g := d.get_bone_global_rest(b).basis.get_rotation_quaternion()
			var g := rest_g
			var sb := s.find_bone(n)
			if sb >= 0:
				var s_rest_g := s.get_bone_global_rest(sb).basis.get_rotation_quaternion()
				g = s_glob[sb] * s_rest_g.inverse() * rest_g
			d_glob[b] = g.normalized()
			var par := d.get_bone_parent(b)
			var local := (d_glob[par].inverse() * d_glob[b]) if par >= 0 else d_glob[b]
			if out_rot.has(b):
				out.rotation_track_insert_key(out_rot[b], time, local.normalized())
		# Hips: the source's offset from its rest, scaled to the target's size
		var sp := s.get_bone_rest(hs).origin
		if hips_pos >= 0:
			sp = anim.position_track_interpolate(hips_pos, time)
		var off := sp - s.get_bone_rest(hs).origin
		out.position_track_insert_key(out_hips, time, d.get_bone_rest(hd).origin + off * ratio)
	return out
