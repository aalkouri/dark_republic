class_name ForestBuilder
extends RefCounted
## The Magical Forest arena: a bright, sunlit woodland, as unlike the gloomy swamp as possible.
## Same size, terrain generator and placement rules as the swamp (WorldBuilder), so it plays the
## same, but greener and thicker: TREES realistic trees of 7 species with bright bark
## (ForestProps), 72 mossy fallen logs, 24 landmarks (glowing crystal clusters and rune stones,
## the magic in it), 14 clear blue ponds, a carpet of bright grass with wildflowers and ferns
## everywhere (no bare dirt), BUSHES walk-through flowering bushes (BushField).
##
## Time of day, a third each: sunny noon, warm golden afternoon (butterflies flutter about by
## day), or a moonlit night (fireflies blink in the dark and the flowering bushes glow).

const TIMES := ["noon", "golden", "night"]
static var force_time := ""     # tests / screenshots: pick the time of day (--forest-time=...)
static var time_of_day := ""    # what the last build chose

const TREES := 320
const BUSHES := 480
const LIGHT_EVERY := 3          # every 3rd landmark lights the ground around it
const LIGHT_RANGE := 11.0
const GRASS_STEP := 1.15        # metres between grass tufts
const CHUNK := 40.0             # grass, flowers and ferns are drawn in chunks of this size...
const DRAW_DIST := 75.0         # ...each only within this distance of the camera

const GROUND := {
	"base_col": Color(0.36, 0.62, 0.16),
	"grass_col": Color(0.42, 0.74, 0.18),
	"mud_col": Color(0.62, 0.74, 0.22),      # sunny meadow, not mud
	"wet_amount": 0.0,
}
const POND := {
	"deep": Color(0.03, 0.22, 0.38),
	"shallow": Color(0.12, 0.5, 0.6),
	"scum": Color(0.3, 0.62, 0.2),           # lily pads
	"glow": 0.0,
	"bed": Color(0.55, 0.5, 0.36),           # sandy
}
const FLOWERS := [Color(1.0, 1.0, 0.95), Color(1.0, 0.86, 0.15), Color(1.0, 0.45, 0.7), Color(0.65, 0.4, 1.0),
	Color(0.35, 0.6, 1.0), Color(1.0, 0.3, 0.2)]
const BUSH_LEAVES := [Color(0.35, 0.72, 0.2, 0.0), Color(0.45, 0.8, 0.25, 0.0), Color(0.3, 0.66, 0.24, 0.0), Color(0.52, 0.82, 0.2, 0.0)]
const BUSH_FLOWERS := [Color(1.0, 0.3, 0.45, 1.0), Color(1.0, 0.95, 0.9, 1.0), Color(0.7, 0.45, 1.0, 1.0), Color(1.0, 0.82, 0.2, 1.0)]


static func build(parent: Node3D, rng: RandomNumberGenerator, half: float) -> SwampWater:
	var pick: String = TIMES[rng.randi() % TIMES.size()]
	time_of_day = force_time if TIMES.has(force_time) else pick
	_environment(parent, rng, time_of_day)

	var water := SwampWater.generate(rng, WorldBuilder.POOLS, half, 35.0)
	water.build_terrain(rng, half, WorldBuilder.CHEST_SITES, ChestManager.SITE_RADIUS)
	var patches := WorldBuilder._patch_map(rng, half + 10.0)
	WorldBuilder._ground(parent, half, water, patches, GROUND)
	water.build_meshes(parent, POND)
	_grass(parent, rng, half, water)
	_flowers_and_ferns(parent, rng, half, water)
	_reeds(parent, rng, water)
	WorldBuilder._walls(parent, half, Color(0.45, 0.42, 0.36))

	var placed: Array[Vector3] = []
	for i in TREES:
		var p := WorldBuilder._free_point(rng, half - 6.0, 12.0, water, 3.0, placed, 4.0)
		var t := ForestProps.tree(i % ForestProps.VARIANTS, rng)
		p.y = WorldBuilder._low_point(water, p, 1.0) - 0.15
		var s := rng.randf_range(0.85, 1.2)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s)), p)
		WorldBuilder._prop(parent, t, xf, true)
		placed.append(p)

	for i in WorldBuilder.FALLEN:
		var fallen := ForestProps.fallen_log(rng)
		var length: float = fallen["length"]
		var r: float = fallen["radius"]
		var p := WorldBuilder._free_point(rng, half - length * 0.5 - 4.0, 14.0, water, length * 0.5 + 2.0, placed, length * 0.5 + 1.0)
		var tilt := deg_to_rad(rng.randf_range(2.0, 8.0))
		var yaw := rng.randf() * TAU
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), -tilt)
		var along := Basis(Vector3.UP, yaw) * Vector3(1, 0, 0) * length * 0.5
		var low := minf(water.ground_height(p.x + along.x, p.z + along.z), water.ground_height(p.x - along.x, p.z - along.z))
		var y := (low - p.y) + r * 0.8 + sin(tilt) * length * 0.5
		WorldBuilder._prop(parent, fallen, Transform3D(basis, p + Vector3(0, y, 0)), true)
		placed.append(p)

	for i in WorldBuilder.RUINS:
		var p := WorldBuilder._free_point(rng, half - 15.0, 25.0, water, 4.0, placed, 6.0)
		p.y = WorldBuilder._low_point(water, p, 2.5) - 0.3
		var lm := ForestProps.landmark(rng, i)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		WorldBuilder._prop(parent, lm, xf)
		var body := parent.get_child(parent.get_child_count() - 1)
		body.add_to_group("obstacle")
		body.set_meta("reach", 3.0)
		if i % LIGHT_EVERY == 0:
			_light(parent, lm, xf)
		placed.append(p)

	var bushes := BushField.new()
	bushes.leaf_colors = BUSH_LEAVES
	bushes.berry_colors = BUSH_FLOWERS
	bushes.glow_berry = 2.2 if time_of_day == "night" else 0.35   # blossoms glow in the dark
	bushes.glow_leaf = 0.12
	bushes.leaf_darken = 0.15
	bushes.scatter(rng, half, water, placed, patches, BUSHES)
	parent.add_child(bushes)
	parent.add_child(Fireflies.new() if time_of_day == "night" else Butterflies.new())
	return water


## A real light in the prop's neon colour (no shadows).
static func _light(parent: Node3D, data: Dictionary, xf: Transform3D) -> void:
	var l := OmniLight3D.new()
	l.light_color = data.get("light", Color.WHITE)
	l.light_energy = 1.6
	l.omni_range = LIGHT_RANGE
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.position = xf * (data.get("light_at", Vector3(0, 3, 0)) as Vector3)
	parent.add_child(l)


# ------------------------------------------------------------------ sky, light, fog

static func _environment(parent: Node3D, rng: RandomNumberGenerator, time: String) -> void:
	var golden := time == "golden"
	var night := time == "night"
	var sh := Shader.new()
	sh.code = WorldBuilder.SKY_SHADER
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("night", 1.0 if night else 0.0)
	sky_mat.set_shader_parameter("seed", rng.randf() * 50.0)
	if night:    # clear moonlit night, deep blue, lots of stars
		sky_mat.set_shader_parameter("top_color", Color(0.02, 0.04, 0.12))
		sky_mat.set_shader_parameter("horizon_color", Color(0.08, 0.16, 0.28))
		sky_mat.set_shader_parameter("ground_color", Color(0.02, 0.04, 0.05))
		sky_mat.set_shader_parameter("cloud_dark", Color(0.04, 0.06, 0.12))
		sky_mat.set_shader_parameter("cloud_light", Color(0.25, 0.32, 0.45))
		sky_mat.set_shader_parameter("body_color", Color(0.92, 0.96, 1.0))
		sky_mat.set_shader_parameter("body_size", 0.06)
		sky_mat.set_shader_parameter("coverage", 0.15)
	elif golden:   # warm late afternoon
		sky_mat.set_shader_parameter("top_color", Color(0.22, 0.45, 0.85))
		sky_mat.set_shader_parameter("horizon_color", Color(1.0, 0.78, 0.5))
		sky_mat.set_shader_parameter("ground_color", Color(0.35, 0.4, 0.2))
		sky_mat.set_shader_parameter("cloud_dark", Color(0.85, 0.6, 0.5))
		sky_mat.set_shader_parameter("cloud_light", Color(1.0, 0.95, 0.85))
		sky_mat.set_shader_parameter("body_color", Color(1.0, 0.85, 0.55))
		sky_mat.set_shader_parameter("body_size", 0.06)
		sky_mat.set_shader_parameter("coverage", 0.3)
	else:        # bright sunny noon, fair-weather clouds
		sky_mat.set_shader_parameter("top_color", Color(0.16, 0.42, 0.92))
		sky_mat.set_shader_parameter("horizon_color", Color(0.62, 0.84, 1.0))
		sky_mat.set_shader_parameter("ground_color", Color(0.3, 0.42, 0.22))
		sky_mat.set_shader_parameter("cloud_dark", Color(0.72, 0.78, 0.88))
		sky_mat.set_shader_parameter("cloud_light", Color(1.0, 1.0, 1.0))
		sky_mat.set_shader_parameter("body_color", Color(1.0, 0.97, 0.85))
		sky_mat.set_shader_parameter("body_size", 0.05)
		sky_mat.set_shader_parameter("coverage", 0.35)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_luminance_cap = 4.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.25   # vivid
	env.fog_enabled = true
	env.fog_sky_affect = 0.05
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.fog_light_color = Color(0.85, 0.75, 0.6) if golden else Color(0.66, 0.8, 0.95)
	env.fog_density = 0.006
	if night:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.32, 0.42, 0.62)
		env.ambient_light_energy = 0.9
		env.fog_light_color = Color(0.05, 0.09, 0.16)
		env.fog_density = 0.01
		env.glow_intensity = 0.9
		env.glow_bloom = 0.06
		env.glow_hdr_threshold = 0.9
		env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	WorldBuilder._add_distant_castle(parent, env.fog_light_color, night)

	var az := rng.randf() * TAU
	var el := deg_to_rad(rng.randf_range(22.0, 32.0) if golden else (rng.randf_range(35.0, 50.0) if night else rng.randf_range(50.0, 65.0)))
	var to_light := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
	var light := DirectionalLight3D.new()
	light.basis = Basis.looking_at(-to_light, Vector3.UP)
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 80.0
	light.light_color = Color(1.0, 0.82, 0.6) if golden else Color(1.0, 0.97, 0.9)
	light.light_energy = 1.35 if golden else 1.5
	if night:   # moonlight
		light.light_color = Color(0.6, 0.72, 1.0)
		light.light_energy = 0.5
	parent.add_child(light)


# ------------------------------------------------------------------ grass, flowers, ferns, reeds

## A thick carpet of bright grass over all the ground (not in the ponds), in chunks that are only
## drawn near the camera.
static func _grass(parent: Node3D, rng: RandomNumberGenerator, half: float, water: SwampWater) -> void:
	var chunks := {}
	var z := -half
	while z < half:
		var x := -half
		while x < half:
			var px := x + rng.randf_range(-0.5, 0.5)
			var pz := z + rng.randf_range(-0.5, 0.5)
			if not water.near_pool(px, pz, 0.6) and Vector2(px, pz).length() > 3.0:
				var s := rng.randf_range(0.8, 1.4)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(px, water.ground_height(px, pz) - 0.04, pz))
				_chunk_add(chunks, xf)
			x += GRASS_STEP
		z += GRASS_STEP
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 14:
		var a := TAU * k / 14.0 + rng.randf() * 0.5
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var h := rng.randf_range(0.18, 0.42)
		var base := out * rng.randf_range(0.0, 0.2)
		var tip := base + out * rng.randf_range(0.08, 0.22) + Vector3(0, h, 0)
		var base_col := Color(0.36, 0.64, 0.16, 0.0)
		var tip_col: Color = [Color(0.6, 0.9, 0.28, 1.0), Color(0.5, 0.84, 0.22, 1.0), Color(0.72, 0.95, 0.36, 1.0)][k % 3]
		st.set_normal(Vector3.UP)
		st.set_color(base_col)
		st.add_vertex(base - side * 0.05)
		st.set_color(base_col)
		st.add_vertex(base + side * 0.05)
		st.set_color(tip_col)
		st.add_vertex(tip)
	var mesh := st.commit()
	mesh.surface_set_material(0, MeshBuilder.foliage_material())
	_chunk_meshes(parent, chunks, mesh)


## Wildflowers in drifts of one colour, and clumps of ferns, all over the forest floor.
static func _flowers_and_ferns(parent: Node3D, rng: RandomNumberGenerator, half: float, water: SwampWater) -> void:
	var flower_meshes: Array[Mesh] = []
	for c in FLOWERS:
		flower_meshes.append(_flower_mesh(rng, c))
	var flowers: Array = []
	for k in FLOWERS.size():
		flowers.append({})
	for d in 900:   # drifts
		var c := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		var kind := rng.randi() % FLOWERS.size()
		for f in rng.randi_range(6, 16):
			var p := c + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
			if water.near_pool(p.x, p.y, 0.8) or p.length() < 3.0:
				continue
			var s := rng.randf_range(0.8, 1.3)
			_chunk_add(flowers[kind], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, water.ground_height(p.x, p.y) - 0.02, p.y)))
	for k in FLOWERS.size():
		_chunk_meshes(parent, flowers[k], flower_meshes[k])
	var ferns := {}
	for f in 2600:
		var p := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		if water.near_pool(p.x, p.y, 1.0) or p.length() < 5.0:
			continue
		var s := rng.randf_range(0.8, 1.5)
		_chunk_add(ferns, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, water.ground_height(p.x, p.y) - 0.05, p.y)))
	_chunk_meshes(parent, ferns, _fern_mesh(rng))


## A little flower: a stem and a few petals round a yellow eye.
static func _flower_mesh(rng: RandomNumberGenerator, petal: Color) -> ArrayMesh:
	var mb := MeshBuilder.new()
	for k in 3:   # three stems per clump
		var a := TAU * k / 3.0 + rng.randf()
		var at := Vector3(cos(a), 0, sin(a)) * 0.12
		var h := rng.randf_range(0.25, 0.45)
		mb.limb(at, at + Vector3(0, h, 0), 0.012, 0.01, Color(0.3, 0.6, 0.15, 0.6), 3)
		for p in 5:
			var pa := TAU * p / 5.0
			mb.add(MeshBuilder.sphere(0.05, 5, 3), Transform3D(Basis.from_scale(Vector3(1.0, 0.3, 0.6)), at + Vector3(cos(pa) * 0.05, h, sin(pa) * 0.05)), Color(petal, 1.0))
		mb.add(MeshBuilder.sphere(0.028, 5, 3), Transform3D(Basis(), at + Vector3(0, h + 0.01, 0)), Color(1.0, 0.8, 0.1, 1.0))
	return mb.commit(MeshBuilder.foliage_material())


## A fern: arching fronds from one root.
static func _fern_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf() * 0.4
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var length := rng.randf_range(0.7, 1.1)
		var prev := Vector3.ZERO
		var segs := 5
		for sgm in segs:
			var t0 := float(sgm) / segs
			var t1 := float(sgm + 1) / segs
			var p0 := out * length * t0 + Vector3(0, sin(t0 * PI * 0.8) * 0.55, 0)
			var p1 := out * length * t1 + Vector3(0, sin(t1 * PI * 0.8) * 0.55, 0)
			var w0 := 0.2 * sin(t0 * PI) + 0.02
			var w1 := 0.2 * sin(t1 * PI) + 0.02
			var c0 := Color(0.3, 0.62, 0.15, t0)
			var c1 := Color(0.45, 0.8, 0.22, t1)
			for v in [[p0 - side * w0, c0], [p0 + side * w0, c0], [p1 + side * w1, c1], [p0 - side * w0, c0], [p1 + side * w1, c1], [p1 - side * w1, c1]]:
				st.set_normal(Vector3.UP)
				st.set_color(v[1])
				st.add_vertex(v[0])
			prev = p1
	var mesh := st.commit()
	mesh.surface_set_material(0, MeshBuilder.foliage_material())
	return mesh


static func _chunk_add(chunks: Dictionary, xf: Transform3D) -> void:
	var key := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
	if not chunks.has(key):
		chunks[key] = [] as Array[Transform3D]
	(chunks[key] as Array[Transform3D]).append(xf)


## One MultiMesh per chunk, faded out beyond DRAW_DIST (keeps 100k+ grass tufts cheap).
static func _chunk_meshes(parent: Node3D, chunks: Dictionary, mesh: Mesh) -> void:
	for key in chunks:
		var xforms: Array[Transform3D] = chunks[key]
		WorldBuilder._multimesh(parent, mesh, xforms)
		var mmi := parent.get_child(parent.get_child_count() - 1) as MultiMeshInstance3D
		mmi.visibility_range_end = DRAW_DIST
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.set_meta("chunk", true)


## Reeds and cattails ringing the ponds.
static func _reeds(parent: Node3D, rng: RandomNumberGenerator, water: SwampWater) -> void:
	WorldBuilder._reeds(parent, rng, water)
