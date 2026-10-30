extends Node3D
## Magical Forest map: same size and layout rules as the swamp, but a bright sunlit wood: more
## trees (7 realistic species with bright bark), more bushes, grass, flowers and ferns all over;
## walk-through bushes that shake, rustle and throw leaves; a run starts on it.
##   godot --headless --path . res://tools/test_forest.tscn

var fails := 0


func _ready() -> void:
	Wallet.persist = false
	var counts := {}
	for map in ["swamp", "forest"]:
		var root := Node3D.new()
		add_child(root)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var water := WorldBuilder.build(root, rng, 220.0, map)
		var burnable := 0
		var obstacles := 0
		var meshes := {}
		var glowing := 0
		for c in root.get_children():
			if c.is_in_group(TreeFire.GROUP):
				burnable += 1
			if c.is_in_group("obstacle"):
				obstacles += 1
			if c is StaticBody3D:
				for mi in c.find_children("*", "MeshInstance3D", false, false):
					var m := (mi as MeshInstance3D).mesh
					meshes[m] = true
					if m is ArrayMesh and m.get_surface_count() >= 2 and m.surface_get_material(1) == MeshBuilder.glow_material():
						glowing += 1
		var lights := root.find_children("*", "OmniLight3D", true, false).size()
		var bushes := root.find_children("*", "BushField", true, false)
		counts[map] = {"burnable": burnable, "obstacles": obstacles, "pools": water.pools.size(),
			"glowing": glowing, "lights": lights, "bushes": (bushes[0] as BushField).pos.size() if not bushes.is_empty() else 0}
		print("  %s: %s" % [map, counts[map]])
		# Plants sit on the rolling ground (not at y = 0, floating over every dip)
		var worst := 0.0
		var checked := 0
		var span := Vector2(INF, -INF)
		for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
			var origins: PackedVector3Array = mmi.get_meta("origins", PackedVector3Array())
			if origins.size() < 1000:
				continue   # the grass fields (reeds ring pools and dip into the water)
			for k in range(0, origins.size(), 7):
				var o := origins[k]
				worst = maxf(worst, absf(o.y - water.ground_height(o.x, o.z)))
				span = Vector2(minf(span.x, o.y), maxf(span.y, o.y))
				checked += 1
		_check("%s: grass sits on the hills (%d tufts checked)" % [map, checked], checked > 1000 and worst < 0.1 and span.y - span.x > 2.0, "worst %.2f m off, tufts from %.1f to %.1f m high" % [worst, span.x, span.y])
		if not bushes.is_empty():
			var bf := bushes[0] as BushField
			var off := 0.0
			for p in bf.pos:
				off = maxf(off, p.y - water.ground_height(p.x, p.z))
			_check("%s: no bush floats above the ground" % map, off <= 0.0, "%.2f m" % off)
		if map == "forest":
			_check("forest: %d trees + 72 fallen logs (more than the swamp's %d)" % [ForestBuilder.TREES, WorldBuilder.TREES], burnable == ForestBuilder.TREES + WorldBuilder.FALLEN and ForestBuilder.TREES > WorldBuilder.TREES, str(burnable))
			_check("forest: 24 landmarks", obstacles == WorldBuilder.RUINS, str(obstacles))
			_check("forest: 14 ponds", water.pools.size() == WorldBuilder.POOLS, str(water.pools.size()))
			_check("forest: only the landmarks glow (the trees are natural)", glowing == obstacles, "%d glowing" % glowing)
			_check("forest: landmark lights only", lights >= 6 and lights <= 10, str(lights))
			_check("forest: ~480 bushes", counts[map]["bushes"] >= 440, str(counts[map]["bushes"]))
			var we: WorldEnvironment = root.find_children("*", "WorldEnvironment", true, false)[0]
			var sun: DirectionalLight3D = root.find_children("*", "DirectionalLight3D", true, false)[0]
			_check("forest: daylight, vivid colours", sun.light_energy >= 1.3 and we.environment.adjustment_saturation > 1.1, "sun %.2f" % sun.light_energy)
			var ground_mi: MeshInstance3D = null
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).mesh
				if m and m.get_surface_count() > 0 and m.surface_get_material(0) is ShaderMaterial and (m.surface_get_material(0) as ShaderMaterial).get_shader_parameter("grass_col") != null:
					ground_mi = mi
					break
			var gm := ground_mi.mesh.surface_get_material(0) as ShaderMaterial if ground_mi else null
			var mud: Color = gm.get_shader_parameter("mud_col") if gm else Color.BLACK
			_check("forest: bright green ground, no dirt patches", gm != null and mud.g > mud.r and mud.g > 0.5 and float(gm.get_shader_parameter("wet_amount")) == 0.0, str(mud))
			var chunks := 0
			for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
				if mmi.has_meta("chunk"):
					chunks += 1
			_check("forest: grass, flowers and ferns everywhere, drawn in near-camera chunks", chunks > 150, str(chunks))
			var bark_ok := true
			for v in ForestProps.VARIANTS:
				var b: Color = ForestProps.SPECIES[v]["bark"]
				if b.get_luminance() < 0.4:
					bark_ok = false
			_check("forest: every species has bright bark", bark_ok, "")
			_check("forest: fireflies", root.find_children("*", "Fireflies", true, false).size() == 1, "")
			await _test_bushes(bushes[0] as BushField)
			await _test_bush_fire(bushes[0] as BushField)
		root.free()
	_check("same landmarks and ponds as the swamp", counts["swamp"]["obstacles"] == counts["forest"]["obstacles"] and counts["swamp"]["pools"] == counts["forest"]["pools"], "")
	_check("the swamp has no bushes or neon", counts["swamp"]["bushes"] == 0 and counts["swamp"]["glowing"] == 0, "")
	_check("7 tree kinds", ForestProps.VARIANTS == 7, "")

	# A run on the forest
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	Settings.selected_map = "forest"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	for f in 5:
		await get_tree().process_frame
	var main: Node = get_tree().current_scene
	_check("a run starts on the forest", main.find_children("*", "BushField", true, false).size() == 1, "")
	Settings.selected_map = "swamp"
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


## Walk a stand-in player through a bush: it should shake, rustle (rate-limited) and sometimes
## throw leaves; standing still in it does nothing.
func _test_bushes(b: BushField) -> void:
	var p := CharacterBody3D.new()
	add_child(p)
	b.player = p
	var at := b.pos[0]
	p.global_position = at
	p.velocity = Vector3.ZERO
	for f in 10:
		await get_tree().physics_frame
	_check("standing still in a bush doesn't rustle it", b.rustles == 0 and b.shake[0] == 0.0, str(b.rustles))
	p.velocity = Vector3(5, 0, 0)
	var leaves := 0
	for f in 120:   # 2 s moving back and forth inside it
		p.global_position = at + Vector3(sin(f * 0.1) * 0.5, 0, 0)
		await get_tree().physics_frame
	_check("moving through a bush rustles it, at most ~3 times a second", b.rustles >= 3 and b.rustles <= 7, str(b.rustles))
	_check("...and shakes it", b.shake[0] > 0.5, "%.2f" % b.shake[0])
	_check("leaves fly out now and then", b.leaf_bursts >= 1 and b.leaf_bursts <= 8, str(b.leaf_bursts))
	p.global_position = at + Vector3(30, 0, 30)
	for f in 60:
		await get_tree().physics_frame
	_check("the shake settles once you leave", b.shake[0] == 0.0, "%.2f" % b.shake[0])
	p.queue_free()


## Fire reaches bushes too: they burn, char, vanish and leave a smoking scorch mark.
func _test_bush_fire(bf: BushField) -> void:
	var i := 5
	var p := bf.pos[i]
	var marks0 := get_tree().get_nodes_in_group(ScorchMark.GROUP).size()
	var lit := Abilities.ignite_area(get_tree(), p, 1.0)
	_check("fire spreads to bushes (ignite_area)", lit >= 1 and bf.is_burning(i), "%d lit" % lit)
	_check("a burning bush can't be lit again", not bf.ignite(i), "")
	await get_tree().create_timer(BushField.BURN_TIME * 0.5).timeout
	await get_tree().create_timer(BushField.BURN_TIME * 0.5 + 0.3).timeout
	_check("the burnt bush is gone", bf.burnt[i] == 1 and not bf.bushes_at(p).has(i), "")
	_check("...leaving a smoking scorch mark for the rest of the match", get_tree().get_nodes_in_group(ScorchMark.GROUP).size() > marks0, "")
	_check("...and you can't light it again", not bf.ignite(i), "")


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s %s  [%s]" % ["ok   " if ok else "FAIL ", name, detail])
	if not ok:
		fails += 1
