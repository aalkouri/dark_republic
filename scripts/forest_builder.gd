class_name ForestBuilder
extends RefCounted
## The Magical Forest arena. Same size, terrain generator, counts and placement rules as the
## swamp (WorldBuilder), so it plays the same: 180 trees (7 kinds, ForestProps), 72 fallen logs,
## 24 landmarks (glowing crystal clusters and rune stones), 14 ponds, grass and walls. On top:
## walk-through bushes that rustle and shed leaves (BushField), and fireflies.
##
## Always after dark so the neon shows: 50% purple twilight, 50% deep blue night.
## A few trees carry a real coloured light (LIGHT_EVERY); the rest glow through emission and bloom.

const LIGHT_EVERY := 5          # every 5th tree and every 3rd landmark lights the ground around it
const LIGHT_RANGE := 11.0
const BUSHES := 260

const GROUND := {
	"base_col": Color(0.13, 0.15, 0.2),
	"grass_col": Color(0.09, 0.26, 0.24),
	"mud_col": Color(0.2, 0.12, 0.26),
}
const POND := {
	"deep": Color(0.02, 0.06, 0.1),
	"shallow": Color(0.04, 0.16, 0.2),
	"scum": Color(0.2, 0.85, 0.8),
	"glow": 0.9,
	"bed": Color(0.05, 0.05, 0.09),
}


static func build(parent: Node3D, rng: RandomNumberGenerator, half: float) -> SwampWater:
	var twilight := rng.randf() < 0.5
	_environment(parent, rng, twilight)

	var water := SwampWater.generate(rng, WorldBuilder.POOLS, half, 35.0)
	water.build_terrain(rng, half, WorldBuilder.SHRINE_SITES, Shrine.ZONE_RADIUS)
	var patches := WorldBuilder._patch_map(rng, half + 10.0)
	WorldBuilder._ground(parent, half, water, patches, GROUND)
	water.build_meshes(parent, POND)
	_grass(parent, rng, half, water, patches)
	_glow_reeds(parent, rng, water)
	WorldBuilder._walls(parent, half, Color(0.12, 0.11, 0.16))

	var placed: Array[Vector3] = []
	for i in WorldBuilder.TREES:
		var p := WorldBuilder._free_point(rng, half - 6.0, 12.0, water, 3.0, placed, 4.5)
		var t := ForestProps.tree(i % ForestProps.VARIANTS, rng)
		p.y = WorldBuilder._low_point(water, p, 1.2) - 0.15
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		WorldBuilder._prop(parent, t, xf, true)
		if i % LIGHT_EVERY == 0:
			_light(parent, t, xf)
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
		if i % 3 == 0:
			_light(parent, lm, xf)
		placed.append(p)

	var bushes := BushField.new()
	bushes.scatter(rng, half, water, placed, patches, BUSHES)
	parent.add_child(bushes)
	parent.add_child(_fireflies())
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

static func _environment(parent: Node3D, rng: RandomNumberGenerator, twilight: bool) -> void:
	var sh := Shader.new()
	sh.code = WorldBuilder.SKY_SHADER
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("night", 1.0)   # stars and a moon in both
	sky_mat.set_shader_parameter("seed", rng.randf() * 50.0)
	if twilight:
		sky_mat.set_shader_parameter("top_color", Color(0.06, 0.03, 0.14))
		sky_mat.set_shader_parameter("horizon_color", Color(0.32, 0.12, 0.3))
		sky_mat.set_shader_parameter("ground_color", Color(0.05, 0.03, 0.07))
		sky_mat.set_shader_parameter("cloud_dark", Color(0.12, 0.05, 0.16))
		sky_mat.set_shader_parameter("cloud_light", Color(0.55, 0.28, 0.48))
		sky_mat.set_shader_parameter("body_color", Color(1.0, 0.82, 0.95))
		sky_mat.set_shader_parameter("body_size", 0.06)
		sky_mat.set_shader_parameter("coverage", 0.35)
	else:
		sky_mat.set_shader_parameter("top_color", Color(0.01, 0.02, 0.06))
		sky_mat.set_shader_parameter("horizon_color", Color(0.03, 0.1, 0.14))
		sky_mat.set_shader_parameter("ground_color", Color(0.01, 0.02, 0.03))
		sky_mat.set_shader_parameter("cloud_dark", Color(0.02, 0.04, 0.08))
		sky_mat.set_shader_parameter("cloud_light", Color(0.15, 0.3, 0.38))
		sky_mat.set_shader_parameter("body_color", Color(0.75, 0.95, 1.0))
		sky_mat.set_shader_parameter("body_size", 0.05)
		sky_mat.set_shader_parameter("coverage", 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_luminance_cap = 4.0   # one over-bright pixel can't bloom into a big white flash
	env.fog_enabled = true
	env.fog_sky_affect = 0.1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if twilight:
		env.ambient_light_color = Color(0.3, 0.2, 0.42)
		env.ambient_light_energy = 1.2
		env.fog_light_color = Color(0.16, 0.07, 0.18)
		env.fog_density = 0.013
	else:
		env.ambient_light_color = Color(0.14, 0.22, 0.34)
		env.ambient_light_energy = 1.25
		env.fog_light_color = Color(0.03, 0.08, 0.11)
		env.fog_density = 0.014
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var az := rng.randf() * TAU
	var el := deg_to_rad(rng.randf_range(25.0, 45.0))
	var to_light := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
	var light := DirectionalLight3D.new()
	light.basis = Basis.looking_at(-to_light, Vector3.UP)
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 80.0
	light.light_color = Color(0.85, 0.6, 1.0) if twilight else Color(0.55, 0.8, 1.0)
	light.light_energy = 0.45
	parent.add_child(light)


# ------------------------------------------------------------------ grass, reeds, fireflies

## Dark blue-green grass whose tips glow faintly (same density rule as the swamp grass).
static func _grass(parent: Node3D, rng: RandomNumberGenerator, half: float, water: SwampWater, patches: Image) -> void:
	var xforms: Array[Transform3D] = []
	var step := 1.35
	var extent := half + 10.0
	var z := -half
	while z < half:
		var x := -half
		while x < half:
			var px := x + rng.randf_range(-0.6, 0.6)
			var pz := z + rng.randf_range(-0.6, 0.6)
			var m := WorldBuilder._sample(patches, extent, px, pz)
			if m.g > 0.6 and m.r < 0.57 and not water.near_pool(px, pz, 0.8) and Vector2(px, pz).length() > 3.0:
				var s := rng.randf_range(0.7, 1.35)
				xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(px, water.ground_height(px, pz) - 0.04, pz)))   # on the hills, not at y = 0
			x += step
		z += step
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf() * 0.5
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var h := rng.randf_range(0.35, 0.8)
		var base := out * rng.randf_range(0.0, 0.12)
		var tip := base + out * rng.randf_range(0.12, 0.35) + Vector3(0, h, 0)
		var base_col := Color(0.03, 0.07, 0.08, 0.0)
		var tip_col: Color = [Color(0.15, 0.55, 0.6, 1.0), Color(0.2, 0.3, 0.7, 1.0), Color(0.35, 0.2, 0.6, 1.0)][k % 3]
		st.set_normal(Vector3.UP)
		st.set_color(base_col)
		st.add_vertex(base - side * 0.035)
		st.set_color(base_col)
		st.add_vertex(base + side * 0.035)
		st.set_color(tip_col)
		st.add_vertex(tip)
	var mesh := st.commit()
	var mat := MeshBuilder.prop_material().duplicate() as ShaderMaterial
	mat.set_shader_parameter("glow", 0.55)
	mesh.surface_set_material(0, mat)
	WorldBuilder._multimesh(parent, mesh, xforms)


## Glowing reeds ringing the ponds: thin stems topped with luminous seed heads.
static func _glow_reeds(parent: Node3D, rng: RandomNumberGenerator, water: SwampWater) -> void:
	var xforms: Array[Transform3D] = []
	for p in water.pools:
		var c: Vector2 = p["center"]
		for k in rng.randi_range(18, 30):
			var th := rng.randf() * TAU
			var r := water.outline_radius(p, th) * rng.randf_range(0.85, 1.15)
			var pos := Vector3(c.x + cos(th) * r, 0, c.y + sin(th) * r)
			pos.y = water.exact_height(pos.x, pos.z) - 0.05
			var s := rng.randf_range(0.8, 1.25)
			xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), pos))
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf()
		var top := Vector3(cos(a) * 0.15, rng.randf_range(1.1, 1.7), sin(a) * 0.15)
		mb.limb(Vector3.ZERO, top, 0.02, 0.008, Color(0.08, 0.2, 0.2, 0.5), 4)
		if k % 2 == 0:
			gb.add(MeshBuilder.cyl(0.045, 0.045, 0.22, 6), Transform3D(Basis(), top + Vector3(0, -0.15, 0)), Color(0.3, 0.9, 1.0, 1.0))
	var mesh := mb.commit()
	gb.commit_into(mesh, MeshBuilder.glow_material())
	WorldBuilder._multimesh(parent, mesh, xforms)


## Fireflies drifting around the player (the emitter follows the camera's player).
static func _fireflies() -> Node3D:
	var f := Fireflies.new()
	return f
