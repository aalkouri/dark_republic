class_name ForestProps
extends RefCounted
## Procedural Magical Forest props. Each builder returns { "mesh": ArrayMesh, "colliders":
## [[Shape3D, Transform3D], ...], "light": Color, "light_at": Vector3 }, origin at the base.
## Vertex alpha = wind sway weight (leaves sway, trunks don't).
##
## Trees are grown, not modelled: a trunk that leans and bends, branches that fork two or three
## times (recursively, thinning and spreading), and lumpy leaf clumps at the branch tips in a few
## shades of the species' colour. Bark is bright so the trunks read against the grass.
##   0 Silver Birch    slender white trunk with black bark marks, airy yellow-green crown
##   1 Oak             thick light-brown trunk, wide spreading limbs, a big rich-green crown
##   2 Beech           tall smooth pale-grey trunk, bright lime crown
##   3 Maple           tan trunk, crown in autumn orange, scarlet and gold
##   4 Cherry          rosy-brown trunk, a cloud of pink and white blossom
##   5 Pine            straight orange-tan trunk, tiers of deep green boughs
##   6 Aspen           white trunk, shimmering golden crown
## Each species has SHAPES built meshes, shared by many trees (rotated and scaled), to keep the
## forest light enough to draw.
## Landmarks stay magical: giant glowing crystals and rune stones (two surfaces: body + neon).

const VARIANTS := 7
const SHAPES := 4

const STONE := Color(0.5, 0.5, 0.52, 0.0)
const MOSS := Color(0.25, 0.55, 0.18, 0.0)
# Neon colours for the landmarks (glow surface: emission = colour x 2.2)
const CYAN := Color(0.25, 0.95, 1.0, 1.0)
const MAGENTA := Color(1.0, 0.25, 0.85, 0.15)
const TEAL := Color(0.2, 1.0, 0.75, 0.05)
const GOLD := Color(1.0, 0.78, 0.3, 1.0)
const LIME := Color(0.45, 1.0, 0.3, 0.2)
const VIOLET := Color(0.7, 0.35, 1.0, 0.6)
const BLUE := Color(0.25, 0.55, 1.0, 1.0)

## Species: height range, trunk radius, bark colour, branch spread (degrees), fork depth,
## leaf clump radius, leaf colours, crown start (fraction of the height), conifer?
const SPECIES := [
	{"h": [11.0, 15.0], "r": 0.26, "bark": Color(0.92, 0.9, 0.85), "spread": 24.0, "depth": 2, "leaf_r": [1.2, 1.8],
		"leaves": [Color(0.55, 0.78, 0.22), Color(0.66, 0.85, 0.3), Color(0.45, 0.7, 0.2)], "crown": 0.45, "marks": true},
	{"h": [8.0, 11.0], "r": 0.62, "bark": Color(0.6, 0.46, 0.32), "spread": 52.0, "depth": 2, "leaf_r": [2.0, 2.8],
		"leaves": [Color(0.22, 0.6, 0.14), Color(0.3, 0.68, 0.18), Color(0.18, 0.5, 0.12)], "crown": 0.35},
	{"h": [12.0, 16.0], "r": 0.42, "bark": Color(0.74, 0.73, 0.68), "spread": 34.0, "depth": 2, "leaf_r": [1.7, 2.5],
		"leaves": [Color(0.48, 0.85, 0.2), Color(0.58, 0.9, 0.28), Color(0.4, 0.75, 0.16)], "crown": 0.4},
	{"h": [9.0, 12.0], "r": 0.4, "bark": Color(0.66, 0.52, 0.37), "spread": 40.0, "depth": 2, "leaf_r": [1.7, 2.4],
		"leaves": [Color(0.98, 0.45, 0.1), Color(0.9, 0.18, 0.1), Color(1.0, 0.72, 0.15)], "crown": 0.4},
	{"h": [6.5, 9.0], "r": 0.34, "bark": Color(0.62, 0.38, 0.32), "spread": 48.0, "depth": 2, "leaf_r": [1.4, 2.1],
		"leaves": [Color(1.0, 0.62, 0.78), Color(1.0, 0.78, 0.88), Color(0.98, 0.92, 0.95)], "crown": 0.35},
	{"h": [13.0, 18.0], "r": 0.38, "bark": Color(0.75, 0.46, 0.26), "conifer": true,
		"leaves": [Color(0.12, 0.42, 0.18), Color(0.16, 0.5, 0.22), Color(0.1, 0.36, 0.16)], "crown": 0.2},
	{"h": [10.0, 14.0], "r": 0.24, "bark": Color(0.9, 0.9, 0.84), "spread": 22.0, "depth": 2, "leaf_r": [1.2, 1.7],
		"leaves": [Color(1.0, 0.82, 0.2), Color(0.95, 0.7, 0.12), Color(1.0, 0.9, 0.4)], "crown": 0.5, "marks": true},
]

static var _cache := {}


## A tree of species `variant` (one of its SHAPES shared meshes).
static func tree(variant: int, rng: RandomNumberGenerator) -> Dictionary:
	var key := Vector2i(variant % VARIANTS, rng.randi() % SHAPES)
	if not _cache.has(key):
		var r2 := RandomNumberGenerator.new()
		r2.seed = 7919 * (key.x + 1) + 104729 * (key.y + 1)
		_cache[key] = _grow_tree(SPECIES[key.x], r2)
	return _cache[key]


static func clear_cache() -> void:
	_cache.clear()


static func _trunk_collider(r: float, h: float) -> Array:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return [s, Transform3D(Basis(), Vector3(0, h * 0.5, 0))]


static func _finish(mb: MeshBuilder, gb: MeshBuilder, colliders: Array, light: Color, light_at: Vector3) -> Dictionary:
	var mesh := mb.commit()
	gb.commit_into(mesh, MeshBuilder.glow_material())
	return {"mesh": mesh, "colliders": colliders, "light": light, "light_at": light_at}


static func _crystal(gb: MeshBuilder, at: Vector3, dir: Vector3, size: float, color: Color) -> void:
	var up := dir.normalized()
	var side := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := side.cross(up).normalized()
	var basis := Basis(x, up, x.cross(up))
	gb.add(MeshBuilder.cone(size * 0.28, size, 5), Transform3D(basis, at + up * size * 0.5), color)


# ------------------------------------------------------------------ trees

static func _grow_tree(sp: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var h := rng.randf_range(sp["h"][0], sp["h"][1])
	var r: float = sp["r"] * rng.randf_range(0.85, 1.15)
	var bark := Color(sp["bark"], 0.0)   # alpha = sway: trunks stand still
	var leaves: Array = sp["leaves"]
	if sp.get("conifer", false):
		_conifer(mb, rng, h, r, bark, leaves)
	else:
		# Trunk: a few segments leaning and bending a little, up to where the crown starts
		var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.0, 0.08)
		var crown_at := h * float(sp["crown"])
		var p := Vector3.ZERO
		var dir := (Vector3.UP + lean).normalized()
		var segs := 4
		var rr := r
		for k in segs:
			var q := p + dir * (crown_at / segs)
			var r_next := rr * 0.9
			mb.limb(p, q, rr, r_next, _shade(bark, rng, 0.06), 10)
			if sp.get("marks", false):   # birch / aspen: black marks on the white bark
				for m in rng.randi_range(2, 4):
					var t := rng.randf()
					var a := rng.randf() * TAU
					var at := p.lerp(q, t) + Vector3(cos(a), 0, sin(a)) * lerpf(rr, r_next, t) * 0.92
					mb.add(MeshBuilder.box(Vector3(rr * rng.randf_range(0.4, 0.9), 0.06, 0.06)), Transform3D(Basis(Vector3.UP, -a), at), Color(0.12, 0.1, 0.09, 0.0))
			p = q
			rr = r_next
			dir = (dir + Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))).normalized()
		# Root flare
		for k in 5:
			var a := TAU * k / 5.0 + rng.randf() * 0.5
			mb.limb(Vector3(0, 0.6, 0), Vector3(cos(a) * r * 2.2, -0.1, sin(a) * r * 2.2), r * 0.45, r * 0.12, _shade(bark, rng, 0.08), 5)
		# Branches forking up into the crown; leaf clumps at the tips
		var tips: Array[Vector3] = []
		var n := rng.randi_range(3, 4)
		for k in n:
			var a := TAU * k / n + rng.randf_range(-0.4, 0.4)
			var out := Vector3(cos(a), 0, sin(a))
			var bdir := dir.slerp(out, deg_to_rad(float(sp["spread"]) + rng.randf_range(-8, 8)) / (PI * 0.5)).normalized()
			_branch(mb, rng, p, bdir, (h - crown_at) * rng.randf_range(0.55, 0.7), rr * 0.75, int(sp["depth"]), sp, tips)
		tips.append(p + dir * (h - crown_at) * 0.7)   # the leader
		var lr: Array = sp["leaf_r"]
		# A dense core to the crown, then clumps along the branches and at every tip
		var centre := Vector3.ZERO
		for t in tips:
			centre += t
		centre /= tips.size()
		var spread := 0.0
		for t in tips:
			spread = maxf(spread, Vector2(t.x - centre.x, t.z - centre.z).length())
		var airy: bool = sp.get("marks", false)   # birch and aspen keep an open, airy crown
		for c in (1 if airy else 3):
			var col: Color = leaves[rng.randi() % leaves.size()]
			var off := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.6, 0.0), rng.randf_range(-0.3, 0.3)) * spread
			mb.add(_lumpy(maxf(spread * (0.4 if airy else 0.65), float(lr[1])), rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.0)), centre + off), _shade(Color(col, 0.3), rng, 0.08))
		for t in tips:
			var mid := p.lerp(t, 0.6) + Vector3(0, -0.3, 0)
			var col2: Color = leaves[rng.randi() % leaves.size()]
			mb.add(_lumpy(float(lr[0]) * rng.randf_range(0.8, 1.0), rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.75, 1.0)), mid), _shade(Color(col2, 0.3), rng, 0.08))
		for t in tips:
			var cr := rng.randf_range(lr[0], lr[1])
			for c in 2:
				var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.6), rng.randf_range(-1, 1)) * cr * 0.6
				var col: Color = leaves[rng.randi() % leaves.size()]
				mb.add(_lumpy(cr * rng.randf_range(0.7, 1.0), rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.0)), t + off), _shade(Color(col, 0.35), rng, 0.08))
	var mesh := mb.commit()
	var col_r := r * 0.95
	return {"mesh": mesh, "colliders": [_trunk_collider(col_r, h * 0.6)], "light": Color.WHITE, "light_at": Vector3(0, h * 0.5, 0)}


## A branch from `p` along `dir`, forking `depth` more times; tip positions go into `tips`.
static func _branch(mb: MeshBuilder, rng: RandomNumberGenerator, p: Vector3, dir: Vector3, length: float, r: float, depth: int, sp: Dictionary, tips: Array[Vector3]) -> void:
	var mid := p + dir * length * 0.5 + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.1, 0.2), rng.randf_range(-0.2, 0.2)) * length * 0.3
	var end := p + dir * length
	var bark := Color(sp["bark"], 0.0)
	mb.limb(p, mid, r, r * 0.8, Color(_shade(bark, rng, 0.06), 0.05), 6)
	mb.limb(mid, end, r * 0.8, r * 0.6, Color(_shade(bark, rng, 0.06), 0.12), 6)
	if depth <= 1 or r < 0.05:
		tips.append(end)
		return
	var n := rng.randi_range(2, 3)
	for k in n:
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized().rotated(dir, TAU * k / n + rng.randf())
		var spread := deg_to_rad(float(sp["spread"]) * rng.randf_range(0.6, 1.0))
		var nd := (dir * cos(spread) + side * sin(spread) + Vector3(0, 0.15, 0)).normalized()
		_branch(mb, rng, end, nd, length * rng.randf_range(0.6, 0.75), r * 0.62, depth - 1, sp, tips)


## Pine: a straight trunk under stacked, drooping tiers of boughs, narrowing to the top.
static func _conifer(mb: MeshBuilder, rng: RandomNumberGenerator, h: float, r: float, bark: Color, leaves: Array) -> void:
	mb.limb(Vector3.ZERO, Vector3(0, h, 0), r, r * 0.15, _shade(bark, rng, 0.05), 10)
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf() * 0.5
		mb.limb(Vector3(0, 0.5, 0), Vector3(cos(a) * r * 2.0, -0.1, sin(a) * r * 2.0), r * 0.4, r * 0.1, _shade(bark, rng, 0.06), 5)
	var tiers := rng.randi_range(9, 11)
	for k in tiers:
		var t := float(k) / tiers
		var y := lerpf(h * 0.15, h * 0.93, t)
		var rad := lerpf(3.8, 0.7, t) * rng.randf_range(0.92, 1.08)
		var col: Color = leaves[rng.randi() % leaves.size()]
		# a drooping skirt of needles: a wide cone with a lumpy edge
		mb.add(MeshBuilder.cone(rad, rad * 1.1, 12), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(0, y + rad * 0.55, 0)), _shade(Color(col, 0.25), rng, 0.08))
		for m in 5:
			var a := TAU * m / 5.0 + rng.randf()
			mb.add(_lumpy(rad * 0.32, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.45, 1.0)), Vector3(cos(a) * rad * 0.75, y + 0.1, sin(a) * rad * 0.75)), _shade(Color(col, 0.3), rng, 0.08))


## A sphere with its surface pushed in and out, so leaf clumps aren't perfect balls.
static func _lumpy(r: float, rng: RandomNumberGenerator) -> Array:
	var arr := MeshBuilder.sphere(r, 8, 5)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var seed := rng.randf() * 100.0
	for k in v.size():
		var d := v[k].normalized() if v[k].length() > 0.0001 else Vector3.UP
		# the same direction always gets the same bump, so the sphere's seam stays closed
		var bump := 1.0 + 0.16 * sin(d.x * 5.1 + seed) * sin(d.y * 4.3 + seed * 0.7) + 0.1 * sin(d.z * 7.7 + d.x * 3.0 + seed * 1.3)
		v[k] = d * r * bump
	arr[Mesh.ARRAY_VERTEX] = v
	return arr


static func _shade(c: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	var f := 1.0 + rng.randf_range(-amount, amount)
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), c.a)


# ------------------------------------------------------------------ fallen logs

## A mossy fallen trunk: bright bark, a broken root plate at one end, moss and toadstools.
static func fallen_log(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var length := rng.randf_range(8.0, 14.0)
	var r := rng.randf_range(0.45, 0.8)
	var a := Vector3(-length * 0.5, 0, 0)
	var b := Vector3(length * 0.5, 0, 0)
	var sp: Dictionary = SPECIES[[0, 1, 2, 3][rng.randi() % 4]]
	var bark := Color(sp["bark"], 0.0)
	mb.limb(a, b, r, r * 0.6, bark, 12)
	var plate_r := r * rng.randf_range(2.2, 2.8)
	var plate_basis := Basis(Vector3(0, 0, 1), deg_to_rad(90.0))
	mb.add(MeshBuilder.cyl(plate_r, plate_r * 0.9, 0.45, 14), Transform3D(plate_basis, a + Vector3(-0.15, 0, 0)), Color(0.42, 0.32, 0.22, 0.0))
	for k in 8:
		var ang := rng.randf() * TAU
		var start := a + Vector3(-0.2, cos(ang), sin(ang)) * plate_r * 0.85
		mb.limb(start, start + Vector3(rng.randf_range(-0.9, -0.2), cos(ang) * 0.8, sin(ang) * 0.8), 0.09, 0.02, Color(0.5, 0.38, 0.26, 0.0), 4)
	# Moss along the top
	for k in rng.randi_range(4, 7):
		var t := rng.randf_range(-0.45, 0.45)
		var rr := lerpf(r, r * 0.6, t + 0.5)
		mb.add(_lumpy(rr * 0.7, rng), Transform3D(Basis.from_scale(Vector3(1.6, 0.35, 1.0)), Vector3(t * length, rr * 0.85, rng.randf_range(-0.2, 0.2) * rr)), _shade(MOSS, rng, 0.15))
	# Red-capped toadstools by its side
	for k in rng.randi_range(3, 6):
		var t := rng.randf_range(-0.45, 0.45) * length
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var at := Vector3(t, -r * 0.6, side * (r + rng.randf_range(0.2, 0.6)))
		var hh := rng.randf_range(0.2, 0.4)
		mb.limb(at, at + Vector3(0, hh, 0), 0.04, 0.035, Color(0.95, 0.92, 0.85, 0.0), 6)
		mb.add(MeshBuilder.sphere(rng.randf_range(0.12, 0.2), 8, 4), Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 1.0)), at + Vector3(0, hh, 0)), Color(0.9, 0.12, 0.08, 0.0))
	var body_shape := CylinderShape3D.new()
	body_shape.radius = r * 0.85
	body_shape.height = length
	var plate_shape := CylinderShape3D.new()
	plate_shape.radius = plate_r
	plate_shape.height = 0.45
	return {
		"mesh": mb.commit(), "radius": r, "length": length, "light": Color.WHITE, "light_at": Vector3(0, r + 0.5, 0),
		"colliders": [[body_shape, Transform3D(plate_basis, Vector3.ZERO)], [plate_shape, Transform3D(plate_basis, a + Vector3(-0.15, 0, 0))]],
	}


## Landmarks (the swamp's ruined pillars): alternately a cluster of giant glowing crystals and a
## standing stone carved with glowing runes.
static func landmark(rng: RandomNumberGenerator, kind: int) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	if kind % 2 == 0:
		var col: Color = [CYAN, MAGENTA, VIOLET, TEAL][rng.randi() % 4]
		mb.add(MeshBuilder.sphere(2.2, 10, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.35, 1.0)), Vector3.ZERO), STONE)
		var tall := rng.randf_range(5.0, 9.0)
		_crystal(gb, Vector3(0, 0.2, 0), Vector3(rng.randf_range(-0.15, 0.15), 1, rng.randf_range(-0.15, 0.15)), tall, Color(col, 0.0))
		for k in rng.randi_range(5, 8):
			var a := rng.randf() * TAU
			var d := rng.randf_range(0.6, 1.8)
			_crystal(gb, Vector3(cos(a) * d, 0.1, sin(a) * d), Vector3(cos(a), rng.randf_range(1.0, 2.5), sin(a)), rng.randf_range(1.2, tall * 0.6), Color(col, 0.0))
		return _finish(mb, gb, [_trunk_collider(1.3, tall)], col, Vector3(0, tall * 0.5, 0))
	var h := rng.randf_range(5.0, 9.0)
	var w := rng.randf_range(1.4, 2.0)
	var rune: Color = [CYAN, GOLD, LIME, BLUE][rng.randi() % 4]
	mb.add(MeshBuilder.box(Vector3(w, h, w * 0.6)), Transform3D(Basis(Vector3(0, 0, 1), rng.randf_range(-0.06, 0.06)), Vector3(0, h * 0.5, 0)), STONE)
	mb.add(MeshBuilder.sphere(w * 0.9, 8, 4), Transform3D(Basis.from_scale(Vector3(1.2, 0.3, 0.9)), Vector3(0, h, 0)), MOSS)
	# Runes: glowing strokes on both faces
	for face in [1.0, -1.0]:
		for k in rng.randi_range(4, 6):
			var y := h * (0.2 + 0.12 * k)
			var x := rng.randf_range(-w * 0.25, w * 0.25)
			var sz := Vector3(rng.randf_range(0.08, w * 0.45), rng.randf_range(0.08, 0.35), 0.04)
			gb.add(MeshBuilder.box(sz), Transform3D(Basis(Vector3(0, 0, 1), rng.randf_range(-0.6, 0.6)), Vector3(x, y, face * w * 0.31)), Color(rune, 0.0))
	gb.add(MeshBuilder.cyl(w * 1.2, w * 1.2, 0.06, 16), Transform3D(Basis(), Vector3(0, 0.03, 0)), Color(rune, 0.0))
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, w * 0.6)
	return _finish(mb, gb, [[box, Transform3D(Basis(), Vector3(0, h * 0.5, 0))]], rune, Vector3(0, 2.0, w))
