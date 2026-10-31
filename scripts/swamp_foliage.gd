class_name SwampFoliage
extends RefCounted
## The Swamp's floor cover, all as MultiMeshes (cheap to draw, no collision, no gameplay effect):
##   - Lily pads floating thick on every pool, densest near the shore, in mixed greens with a
##     notch cut in each, and here and there a yellow spatterdock flower.
##   - Spatterdock: big upright heart-shaped leaves on stalks crowding the shallows round the shore.
##   - Ferns: arching fronds in clumps over the grassy ground and at the foot of the trees.
##   - Sedge: dense clumps of tall marsh grass on the wetter ground near the water.
##   - Shore debris on the muddy banks: half-sunk stones, fallen sticks and twigs, and gnarled
##     roots arching out of the mud (the banks' mud itself is drawn by the ground shader).

const PAD_COLORS: Array[Color] = [Color(0.22, 0.42, 0.12), Color(0.3, 0.5, 0.14), Color(0.36, 0.52, 0.16), Color(0.18, 0.34, 0.1)]
const GROUP := "swamp_foliage"


static func build(parent: Node3D, rng: RandomNumberGenerator, half: float, water: SwampWater, patches: Image, extent: float, trees: Array[Vector3]) -> void:
	_lily_pads(parent, rng, water)
	_spatterdock(parent, rng, water)
	_ferns(parent, rng, half, water, patches, extent, trees)
	_sedge(parent, rng, water)
	_shore_debris(parent, rng, water)


# ------------------------------------------------------------------ lily pads

static func _lily_pads(parent: Node3D, rng: RandomNumberGenerator, water: SwampWater) -> void:
	var meshes: Array[ArrayMesh] = []
	for c in PAD_COLORS:
		meshes.append(_pad_mesh(c))
	var sets: Array = [[], [], [], []]
	var flowers: Array[Transform3D] = []
	for p in water.pools:
		var c: Vector2 = p["center"]
		var y: float = float(p.get("base", 0.0)) + float(p["water_y"]) + 0.015
		var area := PI * float(p["r"]) * float(p["r"])
		var n := int(area * rng.randf_range(0.9, 1.4))
		for k in n:
			var th := rng.randf() * TAU
			# denser toward the shore (most pads within the outer half of the pool)
			var f := 1.0 - pow(rng.randf(), 2.2) * 0.95
			var r := water.outline_radius(p, th) * f * 0.97
			var pos := Vector3(c.x + cos(th) * r, y, c.y + sin(th) * r)
			if not water.in_pool_xz(pos.x, pos.z):
				continue
			var s := rng.randf_range(0.35, 0.85)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1.0, s)), pos + Vector3(0, rng.randf() * 0.01, 0))
			(sets[rng.randi() % sets.size()] as Array).append(xf)
			if rng.randf() < 0.035:
				flowers.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos + Vector3(0, 0.02, 0)))
	for i in sets.size():
		var xs: Array[Transform3D] = []
		xs.assign(sets[i])
		_multimesh(parent, meshes[i], xs, "LilyPads")   # no-i18n
	_multimesh(parent, _flower_mesh(), flowers, "LilyFlowers")   # no-i18n


## A round pad with a wedge-shaped notch, a slightly darker rim and a raised middle.
static func _pad_mesh(col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 14
	var notch := 0.42   # radians cut out
	var rim := col.darkened(0.25)
	var mid := col.lightened(0.12)
	for k in seg:
		var a0 := notch * 0.5 + (TAU - notch) * k / seg
		var a1 := notch * 0.5 + (TAU - notch) * (k + 1) / seg
		st.set_normal(Vector3.UP)
		st.set_color(Color(mid.r, mid.g, mid.b, 0.0))
		st.add_vertex(Vector3(0, 0.012, 0))
		st.set_color(Color(rim.r, rim.g, rim.b, 0.0))
		st.add_vertex(Vector3(cos(a1), 0, sin(a1)))
		st.set_color(Color(rim.r, rim.g, rim.b, 0.0))
		st.add_vertex(Vector3(cos(a0), 0, sin(a0)))
	var m := st.commit()
	m.surface_set_material(0, MeshBuilder.foliage_material())
	return m


## A small yellow cup of petals on a pad.
static func _flower_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	for k in 6:
		var a := TAU * k / 6.0
		var o := Vector3(cos(a), 0, sin(a))
		mb.limb(o * 0.03, o * 0.11 + Vector3(0, 0.12, 0), 0.05, 0.035, Color(0.95, 0.82, 0.2, 0.0), 4)
	mb.add(MeshBuilder.sphere(0.05, 6, 4), Transform3D(Basis(), Vector3(0, 0.06, 0)), Color(0.8, 0.55, 0.12, 0.0))
	return mb.commit(MeshBuilder.foliage_material())


# ------------------------------------------------------------------ spatterdock

static func _spatterdock(parent: Node3D, rng: RandomNumberGenerator, water: SwampWater) -> void:
	var xforms: Array[Transform3D] = []
	for p in water.pools:
		var c: Vector2 = p["center"]
		var y: float = float(p.get("base", 0.0)) + float(p["water_y"])
		for k in int(TAU * float(p["r"]) * rng.randf_range(0.5, 0.8)):
			var th := rng.randf() * TAU
			var r := water.outline_radius(p, th) * rng.randf_range(0.72, 0.95)
			var pos := Vector3(c.x + cos(th) * r, y - 0.05, c.y + sin(th) * r)
			var s := rng.randf_range(0.8, 1.3)
			xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), pos))
	_multimesh(parent, _spatter_mesh(rng), xforms, "Spatterdock")   # no-i18n


## A clump of big heart-shaped leaves held up on stalks, tilted every which way.
static func _spatter_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var leaf_cols: Array[Color] = [Color(0.3, 0.5, 0.15, 1.0), Color(0.38, 0.56, 0.18, 1.0), Color(0.24, 0.42, 0.12, 1.0)]
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf() * 0.6
		var out := Vector3(cos(a), 0, sin(a))
		var top := out * rng.randf_range(0.15, 0.45) + Vector3(0, rng.randf_range(0.35, 0.8), 0)
		mb.limb(Vector3.ZERO, top, 0.025, 0.02, Color(0.3, 0.42, 0.15, 0.5), 4)
		# the leaf: a flattened, notched disc tilted up toward the sky and outward
		var tilt := Basis(out.cross(Vector3.UP).normalized(), deg_to_rad(rng.randf_range(15.0, 45.0)))
		var basis := tilt * Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(0.42, 0.04, 0.34) * rng.randf_range(0.8, 1.2))
		mb.add(MeshBuilder.sphere(1.0, 10, 3), Transform3D(basis, top + out * 0.12), leaf_cols[k % leaf_cols.size()])
	return mb.commit(MeshBuilder.prop_material())


# ------------------------------------------------------------------ ferns

static func _ferns(parent: Node3D, rng: RandomNumberGenerator, half: float, water: SwampWater, patches: Image, extent: float, trees: Array[Vector3]) -> void:
	var xforms: Array[Transform3D] = []
	var step := 3.2
	var z := -half
	while z < half:
		var x := -half
		while x < half:
			var px := x + rng.randf_range(-1.4, 1.4)
			var pz := z + rng.randf_range(-1.4, 1.4)
			var m := WorldBuilder._sample(patches, extent, px, pz)
			if m.g > 0.45 and m.r < 0.6 and rng.randf() < 0.55 and not water.near_pool(px, pz, 1.2) and Vector2(px, pz).length() > 4.0:
				_add_plant(xforms, rng, water, px, pz, rng.randf_range(0.7, 1.3))
			x += step
		z += step
	for t in trees:   # a ring of ferns at the foot of every tree
		for k in rng.randi_range(2, 5):
			var a := rng.randf() * TAU
			var d := rng.randf_range(1.6, 3.4)
			var px := t.x + cos(a) * d
			var pz := t.z + sin(a) * d
			if not water.near_pool(px, pz, 0.6):
				_add_plant(xforms, rng, water, px, pz, rng.randf_range(0.8, 1.4))
	_multimesh(parent, _fern_mesh(rng), xforms, "Ferns")   # no-i18n


static func _add_plant(xforms: Array[Transform3D], rng: RandomNumberGenerator, water: SwampWater, x: float, z: float, s: float) -> void:
	xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s)), Vector3(x, water.ground_height(x, z) - 0.05, z)))


## Arching fronds: each a thin rachis bending out and down, with leaflets either side.
static func _fern_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := 9
	for k in fronds:
		var a := TAU * k / fronds + rng.randf() * 0.4
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var length := rng.randf_range(0.9, 1.4)
		var rise := rng.randf_range(0.5, 0.85)
		var col := Color(0.2, 0.36, 0.1) if k % 2 else Color(0.26, 0.42, 0.13)
		var segs := 7
		for j in segs:
			var t0 := float(j) / segs
			var t1 := float(j + 1) / segs
			var p0 := out * length * t0 + Vector3(0, rise * sin(t0 * PI * 0.8), 0)
			var p1 := out * length * t1 + Vector3(0, rise * sin(t1 * PI * 0.8), 0)
			var w0 := 0.2 * (1.0 - t0 * 0.85) * (0.35 if j == 0 else 1.0)
			var w1 := 0.2 * (1.0 - t1 * 0.85)
			var c0 := Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, t0)
			var c1 := Color(col.r, col.g, col.b, t1)
			for sgn: float in [-1.0, 1.0]:   # a leaflet strip each side of the stem, drooping a little
				var e0: Vector3 = p0 + side * w0 * sgn + Vector3(0, -0.04, 0)
				var e1: Vector3 = p1 + side * w1 * sgn + Vector3(0, -0.04, 0)
				for v in [[p0, c0], [e0, c0], [p1, c1], [p1, c1], [e0, c0], [e1, c1]]:
					st.set_normal(Vector3.UP)
					st.set_color(v[1])
					st.add_vertex(v[0])
	var m := st.commit()
	m.surface_set_material(0, MeshBuilder.foliage_material())
	return m


# ------------------------------------------------------------------ sedge

static func _sedge(parent: Node3D, rng: RandomNumberGenerator, water: SwampWater) -> void:
	var xforms: Array[Transform3D] = []
	for p in water.pools:
		var c: Vector2 = p["center"]
		for k in int(TAU * float(p["r"]) * rng.randf_range(0.9, 1.3)):
			var th := rng.randf() * TAU
			var r := water.outline_radius(p, th) * rng.randf_range(1.02, 1.45)
			var px := c.x + cos(th) * r
			var pz := c.y + sin(th) * r
			_add_plant(xforms, rng, water, px, pz, rng.randf_range(0.8, 1.4))
	_multimesh(parent, _sedge_mesh(rng), xforms, "Sedge")   # no-i18n


## A dense clump of long blades, arching out from the middle (thicker and taller than tufts).
static func _sedge_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 16:
		var a := rng.randf() * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var h := rng.randf_range(0.6, 1.25)
		var base := out * rng.randf_range(0.0, 0.15)
		var mid := base + out * rng.randf_range(0.1, 0.25) + Vector3(0, h * 0.6, 0)
		var tip := base + out * rng.randf_range(0.35, 0.7) + Vector3(0, h, 0)
		var w := 0.045
		var c0 := Color(0.14, 0.2, 0.07, 0.0)
		var c1 := Color(0.3, 0.4, 0.14, 0.6)
		var c2 := Color(0.45, 0.48, 0.2, 1.0) if k % 4 else Color(0.5, 0.44, 0.22, 1.0)
		for v in [[base - side * w, c0], [base + side * w, c0], [mid + side * w * 0.7, c1],
				[base - side * w, c0], [mid + side * w * 0.7, c1], [mid - side * w * 0.7, c1],
				[mid - side * w * 0.7, c1], [mid + side * w * 0.7, c1], [tip, c2]]:
			st.set_normal(Vector3.UP)
			st.set_color(v[1])
			st.add_vertex(v[0])
	var m := st.commit()
	m.surface_set_material(0, MeshBuilder.foliage_material())
	return m


# ------------------------------------------------------------------ shore debris

static func _shore_debris(parent: Node3D, rng: RandomNumberGenerator, water: SwampWater) -> void:
	var stones: Array[Transform3D] = []
	var sticks: Array[Transform3D] = []
	var roots: Array[Transform3D] = []
	for p in water.pools:
		var c: Vector2 = p["center"]
		var per := TAU * float(p["r"])
		for k in int(per * rng.randf_range(0.9, 1.3)):
			var th := rng.randf() * TAU
			var r := water.outline_radius(p, th) + rng.randf_range(-0.2, 3.5)
			var px := c.x + cos(th) * r
			var pz := c.y + sin(th) * r
			if water.in_pool_xz(px, pz):
				continue
			var y := water.ground_height(px, pz)
			var pick := rng.randf()
			var yaw := Basis(Vector3.UP, rng.randf() * TAU)
			if pick < 0.5:   # a stone, half sunk
				var s := rng.randf_range(0.12, 0.45)
				stones.append(Transform3D(yaw.scaled(Vector3(s, s * rng.randf_range(0.45, 0.8), s * rng.randf_range(0.7, 1.2))), Vector3(px, y - s * 0.2, pz)))
			elif pick < 0.85:   # a stick or a few twigs
				var s := rng.randf_range(0.6, 1.4)
				sticks.append(Transform3D(yaw.scaled(Vector3.ONE * s), Vector3(px, y + 0.02, pz)))
			else:   # a root arching out of the mud, toward the water
				var s := rng.randf_range(0.7, 1.3)
				var face := Basis(Vector3.UP, -th + PI * 0.5 + rng.randf_range(-0.5, 0.5))
				roots.append(Transform3D(face.scaled(Vector3.ONE * s), Vector3(px, y - 0.05, pz)))
	_multimesh(parent, _stone_mesh(rng), stones, "ShoreStones")   # no-i18n
	_multimesh(parent, _stick_mesh(rng), sticks, "ShoreSticks")   # no-i18n
	_multimesh(parent, _root_mesh(rng), roots, "ShoreRoots")   # no-i18n


static func _stone_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	mb.add(MeshBuilder.sphere(1.0, 7, 4), Transform3D(), Color(0.33, 0.32, 0.28, 0.0))
	# a patch of moss on top
	mb.add(MeshBuilder.sphere(0.7, 6, 3), Transform3D(Basis.from_scale(Vector3(1.0, 0.35, 0.9)), Vector3(0.15, 0.75, 0.0)), Color(0.22, 0.32, 0.1, 0.0))
	return mb.commit(MeshBuilder.prop_material())


static func _stick_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var col := Color(0.24, 0.18, 0.12, 0.0)
	mb.limb(Vector3(-0.6, 0.03, 0), Vector3(0.6, 0.05, 0.08), 0.035, 0.02, col, 5)
	mb.limb(Vector3(0.1, 0.04, 0.03), Vector3(0.35, 0.05, 0.3), 0.018, 0.008, col, 4)
	mb.limb(Vector3(-0.2, 0.03, 0.25), Vector3(0.3, 0.02, 0.45), 0.02, 0.01, col.darkened(0.2), 4)
	mb.limb(Vector3(-0.4, 0.02, -0.3), Vector3(0.0, 0.03, -0.42), 0.015, 0.008, col.lightened(0.15), 4)
	return mb.commit(MeshBuilder.prop_material())


static func _root_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var col := Color(0.2, 0.15, 0.1, 0.0)
	var pts: Array[Vector3] = [Vector3(-0.9, -0.1, 0), Vector3(-0.45, 0.28, 0.05), Vector3(0.0, 0.36, -0.04), Vector3(0.45, 0.22, 0.06), Vector3(0.95, -0.12, 0.0)]
	for k in pts.size() - 1:
		mb.limb(pts[k], pts[k + 1], lerpf(0.11, 0.05, float(k) / 4.0), lerpf(0.11, 0.05, float(k + 1) / 4.0), col, 6)
	mb.limb(Vector3(0.0, 0.34, 0.0), Vector3(0.3, -0.1, 0.55), 0.05, 0.02, col.darkened(0.15), 5)
	return mb.commit(MeshBuilder.prop_material())


## One MultiMesh per 40 m chunk, each drawn only within DRAW_DIST of the camera (like the
## Magical Forest's grass), so thousands of pads, ferns and stones stay cheap.
static func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], node_name: String) -> void:
	var chunks := {}
	for xf in xforms:
		var key := Vector2i(floori(xf.origin.x / ForestBuilder.CHUNK), floori(xf.origin.z / ForestBuilder.CHUNK))
		if not chunks.has(key):
			chunks[key] = [] as Array[Transform3D]
		(chunks[key] as Array[Transform3D]).append(xf)
	for key in chunks:
		var xs: Array[Transform3D] = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xs.size()
		for k in xs.size():
			mm.set_instance_transform(k, xs[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [node_name, key.x, key.y]   # no-i18n
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = ForestBuilder.DRAW_DIST
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.add_to_group(GROUP)
		mmi.set_meta("chunk", true)
		mmi.set_meta("origins", PackedVector3Array(xs.map(func(x: Transform3D): return x.origin)))   # tests
		parent.add_child(mmi)
