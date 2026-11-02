extends Node3D
## Contact sheets of the Ashen Caldera's models from a few angles (for checking the look quickly):
##   godot --path . res://tools/render_caldera.tscn -- what /out.png
## what: crowd | props | landmarks | forge | statue | singe

var _frames: Array[Image] = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var what: String = a[0]
	var out: String = a[1]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.18, 0.12)
	env.environment.ambient_light_color = Color(0.7, 0.62, 0.58)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.8
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_color = Color(1.0, 0.85, 0.72)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.18, 0.17)
	pm.material = fm
	floor.mesh = pm
	add_child(floor)
	var cam := Camera3D.new()
	cam.fov = 40
	cam.far = 900
	add_child(cam)
	var views: Array = []   # [eye, target, (callable to pose)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	match what:
		"crowd":
			var meshes: Array = load("res://scripts/caldera_crowd.gd").preview_meshes()
			var names := ["imp", "fiend", "bat", "golem", "molten", "slug"]
			var scales := [1.0, 1.5, 1.0, 1.6, 2.4, 1.1]
			var heights := [0.95, 1.4, 0.0, 2.6, 3.9, 0.5]
			for k in meshes.size():
				for pose in [0.0, 0.25]:
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.use_colors = true
					mm.use_custom_data = true
					mm.mesh = meshes[k]
					mm.instance_count = 1
					var s: float = scales[k]
					var at := Vector3(k * 8.0, 1.6 if names[k] == "bat" else 0.0, pose * 40.0)
					mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * s), at))
					mm.set_instance_color(0, Color.WHITE)
					mm.set_instance_custom_data(0, Color(pose, 0.3 if pose == 0.0 else 0.6, 0.0, 0.0))
					var mmi := MultiMeshInstance3D.new()
					mmi.multimesh = mm
					add_child(mmi)
					var h: float = heights[k] if names[k] != "bat" else 1.6
					var d: float = maxf(h, 1.0) * 1.7 + 0.9
					var tgt := at + Vector3(0, h * 0.5 if names[k] != "bat" else 0.0, 0)
					views.append([tgt + Vector3(d * 0.55, d * 0.35 + (0.9 if names[k] == "bat" else 0.0), d * 0.9), tgt])
		"props":
			var items := [CalderaProps.charred_tree(rng), CalderaProps.petrified_tree(rng), CalderaProps.column_cluster(rng), CalderaProps.obsidian_shard(rng), CalderaProps.scoria_boulders(rng), CalderaProps.sulphur_vent(rng),
				CalderaProps.hornito(rng), CalderaProps.fallen_columns(rng), CalderaProps.charred_log(rng), CalderaProps.lava_lobe(rng), CalderaProps.beast_bones(rng), CalderaProps.forge_debris(rng), CalderaProps.lava_bomb_rock(rng)]
			for k in items.size():
				var mi := MeshInstance3D.new()
				mi.mesh = items[k]["mesh"]
				mi.position = Vector3((k % 5) * 40.0, 0, (k / 5) * 40.0)
				add_child(mi)
				var c: Vector3 = mi.position
				var big := 1.4 if k < 7 else 0.9
				views.append([c + Vector3(6, 4, 8) * big, c + Vector3(0, 1.6 * big, 0)])
		"landmarks":
			for k in 6:
				var lm := CalderaProps.landmark(rng, k, false)
				var mi := MeshInstance3D.new()
				mi.mesh = lm["mesh"]
				mi.position = Vector3(k * 60.0, 0, 0)
				add_child(mi)
				for fx in lm.get("fx", []):
					var node: Node3D = fx
					node.position += mi.position
					add_child(node)
				views.append([mi.position + Vector3(12, 9, 16), mi.position + Vector3(0, 2.8, 0)])
		"forge":
			var f := CalderaProps.forge_temple(rng, false)
			add_child(f)
			views = [[Vector3(18, 14, 34), Vector3(0, 2, 0)], [Vector3(-6, 5, 16), Vector3(0, 2.5, 0)], [Vector3(4, 4.5, 7), Vector3(0, 2.8, 1.5)], [Vector3(-20, 22, -2), Vector3(0, 0, 0)]]
		"statue":
			var st := CalderaProps.smith_statue(rng)
			var mi := MeshInstance3D.new()
			mi.mesh = st["mesh"]
			add_child(mi)
			views = [[Vector3(14, 12, 26), Vector3(0, 7, 0)], [Vector3(-22, 10, 14), Vector3(0, 8, 0)], [Vector3(4, 9, 16), Vector3(0, 8, 2)], [Vector3(26, 18, -6), Vector3(4, 10, 0)]]
		"singe":   # Singe beside one of his magma imps, then his poses
			var m: Node3D = load("res://scripts/singe_model.gd").new()
			m.name = "SingePreview"
			add_child(m)
			var imp_mesh: Mesh = load("res://scripts/caldera_crowd.gd").preview_meshes()[0]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = imp_mesh
			mm.instance_count = 1
			mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, PI * 0.15), Vector3(2.6, 0, -1.2)))
			mm.set_instance_color(0, Color.WHITE)
			mm.set_instance_custom_data(0, Color(0.0, 0.3, 0.0, 0.0))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			add_child(mmi)
			views = [[Vector3(5, 4.2, -11), Vector3(0.6, 3.0, 0)], [Vector3(-8, 5, -6), Vector3(0, 3.2, 0)], [Vector3(1.2, 5.4, -4.2), Vector3(0, 4.9, 0)], [Vector3(6, 6, 8), Vector3(0, 3, 0)]]
			for pose in ["walk", "swipe", "breath", "juggle", "summon", "scamper", "dive", "raise", "die"]:
				views.append([Vector3(5, 4.5, -11), Vector3(0, 3.0, 0), pose])
	await get_tree().process_frame
	for k in 10:
		await get_tree().process_frame
	for v in views:
		if v.size() > 2:
			var m: Node = find_child("SingePreview", true, false)
			m.call("pose_preview", v[2])
			for k in 3:
				await get_tree().process_frame
		cam.look_at_from_position(v[0], v[1])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(480, 360)
		_frames.append(img)
	var cols := 3 if views.size() <= 9 else 4
	var rows := int(ceil(views.size() / float(cols)))
	var sheet := Image.create(480 * cols, 360 * rows, false, _frames[0].get_format())
	for k in _frames.size():
		sheet.blit_rect(_frames[k], Rect2i(0, 0, 480, 360), Vector2i((k % cols) * 480, (k / cols) * 360))
	sheet.save_png(out)
	get_tree().quit()
