extends SceneTree
## Vertex-animation baker. Turns rigged Meshy/Higgsfield GLBs (the same model, one clip per
## file) into a crowd-friendly format: a static mesh plus textures holding every vertex's
## position and normal for every frame. A shader replays them, so a MultiMesh of thousands
## of animated characters costs one draw call and no skeletons.
##
##   godot --headless --path . --script res://tools/bake_vat.gd -- <glb dir> <out dir> <clips>
##   <clips> = "run=Name:frames:loop,attack=Name:frames:loop,death=Name:frames:hold"
##
## Writes into <out dir>: vat_mesh.res (ArrayMesh, vertex order = texture columns),
## vat_pos.exr / vat_nrm.png (as Images in .res), albedo.png, vat.json (clip table).

const TEX_W := 4096


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src_dir: String = args[0]
	var out_dir: String = args[1]
	var clip_specs := {}   # meshy name -> [key, frames, loop]
	var order: Array = []
	for spec in args[2].split(","):
		var kv := spec.split("=")
		var parts := kv[1].split(":")
		clip_specs[parts[0]] = [kv[0], int(parts[1]), parts[2] == "loop"]
		order.append(parts[0])

	# Load every GLB; the first supplies the mesh, all supply clips
	var clips := {}        # meshy name -> Animation
	var base: Node = null
	for f in DirAccess.get_files_at(src_dir):
		if not f.ends_with(".glb"):
			continue
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(src_dir.path_join(f), state) != OK:
			push_error("can't read " + f)
			continue
		var scene := doc.generate_scene(state)
		var ap := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for an in ap.get_animation_list():
			var raw := an.split("|")[1] if "|" in an else str(an)
			if clip_specs.has(raw):
				clips[raw] = ap.get_animation(an)
		if base == null:
			base = scene
	for name in order:
		if not clips.has(name):
			push_error("missing clip " + name)
			quit(1)
			return

	var mi := base.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var sk := base.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skin := mi.skin
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var nv := verts.size()
	var per := bones.size() / nv          # influences per vertex (4 or 8)
	# Skeleton space -> model root space (the Armature is scaled 0.01)
	var to_root := _rel(base, sk)
	var bind_bone := PackedInt32Array()
	for j in skin.get_bind_count():
		var bb := skin.get_bind_bone(j)
		if bb < 0:
			bb = sk.find_bone(skin.get_bind_name(j))
		bind_bone.append(bb)
	print("verts %d  tris %d  influences %d  binds %d  bones %d" % [nv, (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, per, skin.get_bind_count(), sk.get_bone_count()])

	# Bake frames
	var total := 0
	for name in order:
		total += int(clip_specs[name][1])
	var rows := int(ceil(float(nv * total) / TEX_W))
	var pos_img := Image.create_empty(TEX_W, rows, false, Image.FORMAT_RGBF)
	var nrm_img := Image.create_empty(TEX_W, rows, false, Image.FORMAT_RGB8)
	var table := {}
	var frame := 0
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for name in order:
		var spec: Array = clip_specs[name]
		var anim: Animation = clips[name]
		var frames: int = spec[1]
		var loop: bool = spec[2]
		table[spec[0]] = {"start": frame, "frames": frames, "length": anim.length, "loop": loop}
		for fi in frames:
			# Loops sample [0, length) so frame N wraps to frame 0; one-shots include the end
			var t := anim.length * float(fi) / float(frames if loop else frames - 1)
			_pose(sk, anim, t)
			var mats: Array[Transform3D] = []
			var globals := _globals(sk)
			for j in bind_bone.size():
				mats.append(to_root * globals[bind_bone[j]] * skin.get_bind_pose(j))
			for v in nv:
				var p := Vector3.ZERO
				var n := Vector3.ZERO
				for k in per:
					var w := weights[v * per + k]
					if w <= 0.0:
						continue
					var m: Transform3D = mats[bones[v * per + k]]
					p += (m * verts[v]) * w
					n += (m.basis * norms[v]) * w
				n = n.normalized()
				var idx := frame * nv + v
				pos_img.set_pixel(idx % TEX_W, idx / TEX_W, Color(p.x, p.y, p.z))
				nrm_img.set_pixel(idx % TEX_W, idx / TEX_W, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
				lo = lo.min(p)
				hi = hi.max(p)
			frame += 1
		print("baked %-8s %3d frames  %.2fs" % [spec[0], frames, anim.length])

	# Static mesh in the same vertex order (rest pose in root space, for bounds/fallback)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var rest := PackedVector3Array()
	_pose_rest(sk)
	var rg := _globals(sk)
	for v in nv:
		var p := Vector3.ZERO
		for k in per:
			var w := weights[v * per + k]
			if w > 0.0:
				p += (to_root * rg[bind_bone[bones[v * per + k]]] * skin.get_bind_pose(bones[v * per + k]) * verts[v]) * w
		rest.append(p)
	out[Mesh.ARRAY_VERTEX] = rest
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV]
	out[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	# Vertex index for the texture lookup, as an exact float in CUSTOM0.x
	var ids := PackedFloat32Array()
	ids.resize(nv)
	for v in nv:
		ids[v] = float(v)
	out[Mesh.ARRAY_CUSTOM0] = ids
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {},
		Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	ResourceSaver.save(mesh, out_dir.path_join("vat_mesh.res"), ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(ImageTexture.create_from_image(pos_img), out_dir.path_join("vat_pos.res"), ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(ImageTexture.create_from_image(nrm_img), out_dir.path_join("vat_nrm.res"), ResourceSaver.FLAG_COMPRESS)
	var mat := mi.get_active_material(0)
	if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
		var img := (mat as BaseMaterial3D).albedo_texture.get_image()
		if img.get_width() > 1024:
			img.resize(1024, 1024 * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(out_dir.path_join("albedo.png")))
	var info := {"verts": nv, "tex_w": TEX_W, "frames": total, "clips": table,
		"aabb": [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]}
	var fa := FileAccess.open(out_dir.path_join("vat.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(info, "  "))
	fa.close()
	print("saved to ", out_dir, "  bounds ", lo, " .. ", hi, "  texture %dx%d" % [TEX_W, rows])
	quit()


func _rel(root: Node, n: Node) -> Transform3D:
	var t := Transform3D()
	var cur := n
	while cur != root and cur != null:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _pose(sk: Skeleton3D, anim: Animation, t: float) -> void:
	_pose_rest(sk)
	for tr in anim.get_track_count():
		var bone := sk.find_bone(str(anim.track_get_path(tr)).get_slice(":", 1))
		if bone < 0:
			continue
		match anim.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(tr, t))
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(bone, anim.position_track_interpolate(tr, t))
			Animation.TYPE_SCALE_3D:
				sk.set_bone_pose_scale(bone, anim.scale_track_interpolate(tr, t))


func _pose_rest(sk: Skeleton3D) -> void:
	for b in sk.get_bone_count():
		var r := sk.get_bone_rest(b)
		sk.set_bone_pose_position(b, r.origin)
		sk.set_bone_pose_rotation(b, r.basis.get_rotation_quaternion())
		sk.set_bone_pose_scale(b, r.basis.get_scale())


## Bone global poses computed directly (the skeleton's own cache doesn't refresh off-tree).
func _globals(sk: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(sk.get_bone_count())
	for b in sk.get_bone_count():   # parents come before children in Meshy rigs; guard anyway
		out[b] = _g(sk, b, out)
	return out


func _g(sk: Skeleton3D, b: int, cache: Array[Transform3D]) -> Transform3D:
	var local := Transform3D(Basis(sk.get_bone_pose_rotation(b)) * Basis.from_scale(sk.get_bone_pose_scale(b)), sk.get_bone_pose_position(b))
	var p := sk.get_bone_parent(b)
	return local if p < 0 else _g(sk, p, cache) * local
