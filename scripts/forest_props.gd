class_name ForestProps
extends RefCounted
## Procedural Magical Forest props. Each builder returns { "mesh": ArrayMesh, "colliders":
## [[Shape3D, Transform3D], ...], "light": Color, "light_at": Vector3 }, origin at the base.
## Every mesh has two surfaces: the body (MeshBuilder.prop_material) and its neon parts
## (MeshBuilder.glow_material, self-lit). Vertex alpha = wind sway weight, so hanging lights and
## vines sway with the leaves.
##   0 Lantern Willow   curving violet trunk, dark dome, long vines strung with cyan bulbs
##   1 Spiral Crystalwood  silver trunk twisting in a helix, branches tipped with magenta crystals
##   2 Mushroom Spire   stacked giant caps with glowing teal gills and spots, glowing toadstools
##   3 Starcanopy       thin twisted trunk under a flat umbrella canopy dripping strings of gold lights
##   4 Coral Tree       leafless branching coral limbs with glowing orange-pink tips
##   5 Orb Tree         trunk wrapped in green neon vines, purple orbs floating in its canopy
##   6 Ribbon Arch      two trunks arching into one, blue neon ribbons draped between them

const VARIANTS := 7

const BARK_VIOLET := Color(0.32, 0.22, 0.38, 0.0)
const BARK_SILVER := Color(0.55, 0.56, 0.62, 0.0)
const BARK_DARK := Color(0.22, 0.18, 0.26, 0.0)
const BARK_BLUE := Color(0.22, 0.26, 0.4, 0.0)
const CORAL := Color(0.5, 0.2, 0.26, 0.0)
const STALK := Color(0.72, 0.7, 0.62, 0.0)
const LEAF_TEAL := Color(0.08, 0.3, 0.32, 0.35)
const LEAF_INDIGO := Color(0.16, 0.14, 0.4, 0.35)
const LEAF_PLUM := Color(0.3, 0.12, 0.34, 0.35)
const VINE := Color(0.08, 0.14, 0.1, 1.0)
const CAP := Color(0.32, 0.18, 0.5, 0.05)
const STONE := Color(0.24, 0.24, 0.3, 0.0)
const MOSS := Color(0.08, 0.2, 0.16, 0.0)

# Neon colours (glow surface: emission = colour x 2.2). Alpha is still the sway weight.
const CYAN := Color(0.25, 0.95, 1.0, 1.0)
const MAGENTA := Color(1.0, 0.25, 0.85, 0.15)
const TEAL := Color(0.2, 1.0, 0.75, 0.05)
const GOLD := Color(1.0, 0.78, 0.3, 1.0)
const PINK := Color(1.0, 0.45, 0.4, 0.3)
const LIME := Color(0.45, 1.0, 0.3, 0.2)
const VIOLET := Color(0.7, 0.35, 1.0, 0.6)
const BLUE := Color(0.25, 0.55, 1.0, 1.0)


static func tree(variant: int, rng: RandomNumberGenerator) -> Dictionary:
	match variant:
		0: return _lantern_willow(rng)
		1: return _crystalwood(rng)
		2: return _mushroom_spire(rng)
		3: return _starcanopy(rng)
		4: return _coral(rng)
		5: return _orb_tree(rng)
		_: return _ribbon_arch(rng)


static func _trunk_collider(r: float, h: float) -> Array:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return [s, Transform3D(Basis(), Vector3(0, h * 0.5, 0))]


static func _finish(mb: MeshBuilder, gb: MeshBuilder, colliders: Array, light: Color, light_at: Vector3) -> Dictionary:
	var mesh := mb.commit()
	gb.commit_into(mesh, MeshBuilder.glow_material())
	return {"mesh": mesh, "colliders": colliders, "light": light, "light_at": light_at}


## A string of glowing beads hanging from `top`, `n` beads over `length` metres.
static func _bead_string(mb: MeshBuilder, gb: MeshBuilder, rng: RandomNumberGenerator, top: Vector3, length: float, n: int, bead: Color, r: float, cord := VINE) -> void:
	var drift := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
	var bottom := top + Vector3(0, -length, 0) + drift
	mb.limb(top, bottom, 0.035, 0.015, cord, 4)
	for k in n:
		var t := (k + 0.5 + rng.randf_range(-0.2, 0.2)) / n
		gb.add(MeshBuilder.sphere(r * rng.randf_range(0.8, 1.2), 6, 4), Transform3D(Basis(), top.lerp(bottom, t)), bead)


static func _crystal(gb: MeshBuilder, at: Vector3, dir: Vector3, size: float, color: Color) -> void:
	var up := dir.normalized()
	var side := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := side.cross(up).normalized()
	var basis := Basis(x, up, x.cross(up))
	gb.add(MeshBuilder.cone(size * 0.28, size, 5), Transform3D(basis, at + up * size * 0.5), color)


# ------------------------------------------------------------------ 0: lantern willow

static func _lantern_willow(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var h := rng.randf_range(9.0, 12.0)
	var bend := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
	var pts: Array[Vector3] = []
	for k in 6:
		var t := k / 5.0
		pts.append(Vector3(0, t * h * 0.8, 0) + bend * (t * t))
	for k in 5:
		mb.limb(pts[k], pts[k + 1], lerpf(0.55, 0.22, k / 5.0), lerpf(0.55, 0.22, (k + 1) / 5.0), BARK_VIOLET, 9)
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf() * 0.5
		mb.limb(Vector3(0, 0.8, 0), Vector3(cos(a) * 1.1, -0.05, sin(a) * 1.1), 0.22, 0.08, BARK_VIOLET, 5)
	var crown: Vector3 = pts[5] + Vector3(0, 1.0, 0)
	mb.add(MeshBuilder.sphere(4.2, 12, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.45, 1.0)), crown), LEAF_TEAL)
	# Curtains of vines, each strung with cyan bulbs
	for k in 26:
		var a := TAU * k / 26.0 + rng.randf_range(-0.1, 0.1)
		var d := rng.randf_range(2.6, 4.0)
		var top := crown + Vector3(cos(a) * d, -0.9, sin(a) * d)
		_bead_string(mb, gb, rng, top, rng.randf_range(3.5, h * 0.62), rng.randi_range(3, 6), CYAN, 0.09)
	return _finish(mb, gb, [_trunk_collider(0.6, h)], Color(0.3, 0.9, 1.0), crown - Vector3(0, 2.5, 0))


# ------------------------------------------------------------------ 1: spiral crystalwood

static func _crystalwood(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var h := rng.randf_range(10.0, 14.0)
	var segs := 14
	var turns := rng.randf_range(1.0, 1.6)
	var prev := Vector3.ZERO
	for k in range(1, segs + 1):
		var t := float(k) / segs
		var a := t * turns * TAU
		var p := Vector3(cos(a) * 0.6 * t, t * h, sin(a) * 0.6 * t)
		mb.limb(prev, p, lerpf(0.5, 0.12, float(k - 1) / segs), lerpf(0.5, 0.12, t), BARK_SILVER, 8)
		if k % 3 == 0:   # crystal shards growing out of the trunk
			var out := Vector3(cos(a), 0.4, sin(a))
			_crystal(gb, p, out, rng.randf_range(0.35, 0.6), MAGENTA)
		if k >= 6 and k % 2 == 0:   # branches with crystal clusters
			var ba := rng.randf() * TAU
			var end := p + Vector3(cos(ba) * rng.randf_range(1.8, 3.2), rng.randf_range(0.5, 1.8), sin(ba) * rng.randf_range(1.8, 3.2))
			mb.limb(p, end, 0.1, 0.03, BARK_SILVER, 5)
			for c in rng.randi_range(3, 5):
				_crystal(gb, end, Vector3(rng.randf_range(-1, 1), rng.randf_range(0.4, 1.4), rng.randf_range(-1, 1)), rng.randf_range(0.4, 0.9), MAGENTA)
		prev = p
	for c in 7:   # a crown of big crystals
		_crystal(gb, prev, Vector3(rng.randf_range(-0.8, 0.8), 1.0, rng.randf_range(-0.8, 0.8)), rng.randf_range(0.8, 1.6), MAGENTA)
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf()
		mb.limb(Vector3(0, 0.6, 0), Vector3(cos(a) * 1.0, -0.05, sin(a) * 1.0), 0.2, 0.06, BARK_SILVER, 5)
	return _finish(mb, gb, [_trunk_collider(0.55, h)], Color(1.0, 0.3, 0.85), prev)


# ------------------------------------------------------------------ 2: mushroom spire

static func _mushroom_spire(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var h := rng.randf_range(8.0, 12.0)
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	mb.limb(Vector3.ZERO, Vector3(0, h, 0) + lean, 0.75, 0.4, STALK, 12)
	mb.add(MeshBuilder.sphere(1.0, 10, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.4, 1.0)), Vector3(0, 0.1, 0)), STALK)
	# Three stacked caps, glowing gills underneath and glowing spots on top
	var caps := [[0.55, 3.6], [0.78, 2.6], [1.0, 1.8]]
	for c in caps:
		var at: Vector3 = Vector3(0, h * float(c[0]), 0) + lean * float(c[0])
		var r: float = c[1] * rng.randf_range(0.9, 1.1)
		mb.add(MeshBuilder.sphere(r, 14, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.32, 1.0)), at + Vector3(0, 0.25, 0)), CAP)
		gb.add(MeshBuilder.cyl(r * 0.92, r * 0.25, 0.08, 16), Transform3D(Basis(), at + Vector3(0, 0.12, 0)), TEAL)
		for s in int(r * 3):
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * r * 0.75
			var y := 0.25 + r * 0.32 * sqrt(maxf(0.0, 1.0 - (d / r) * (d / r)))
			gb.add(MeshBuilder.sphere(rng.randf_range(0.1, 0.22), 6, 3), Transform3D(Basis.from_scale(Vector3(1, 0.4, 1)), at + Vector3(cos(a) * d, y, sin(a) * d)), TEAL)
	# Little glowing toadstools around the foot
	for k in rng.randi_range(5, 9):
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.2, 3.0)
		var sh := rng.randf_range(0.25, 0.6)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		mb.limb(p, p + Vector3(0, sh, 0), 0.05, 0.04, STALK, 5)
		gb.add(MeshBuilder.sphere(sh * 0.45, 8, 4), Transform3D(Basis.from_scale(Vector3(1, 0.5, 1)), p + Vector3(0, sh, 0)), TEAL)
	return _finish(mb, gb, [_trunk_collider(0.8, h)], Color(0.2, 1.0, 0.75), Vector3(0, h * 0.5, 0))


# ------------------------------------------------------------------ 3: starcanopy

static func _starcanopy(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var h := rng.randf_range(11.0, 15.0)
	var prev := Vector3.ZERO
	for k in range(1, 7):
		var t := k / 6.0
		var p := Vector3(sin(t * 5.0) * 0.5, t * h, cos(t * 4.0) * 0.5)
		mb.limb(prev, p, lerpf(0.45, 0.2, (k - 1) / 6.0), lerpf(0.45, 0.2, t), BARK_DARK, 8)
		prev = p
	# Flat umbrella canopy on a few spreading limbs
	var top := prev
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf() * 0.4
		mb.limb(top - Vector3(0, 1.0, 0), top + Vector3(cos(a) * 3.5, 0.3, sin(a) * 3.5), 0.14, 0.05, BARK_DARK, 5)
	var cr := rng.randf_range(5.0, 6.5)
	mb.add(MeshBuilder.sphere(cr, 16, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.16, 1.0)), top + Vector3(0, 0.6, 0)), LEAF_INDIGO)
	# Strings of gold fairy lights hanging from under the canopy
	for k in 34:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * cr * 0.92
		var start := top + Vector3(cos(a) * d, 0.0, sin(a) * d)
		_bead_string(mb, gb, rng, start, rng.randf_range(1.0, 2.6), rng.randi_range(3, 5), GOLD, 0.07, Color(0.1, 0.08, 0.06, 1.0))
	return _finish(mb, gb, [_trunk_collider(0.5, h)], Color(1.0, 0.75, 0.35), top - Vector3(0, 1.5, 0))


# ------------------------------------------------------------------ 4: coral tree

static func _coral(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var h := rng.randf_range(4.0, 5.5)
	mb.limb(Vector3.ZERO, Vector3(0, h, 0), 0.6, 0.38, CORAL, 10)
	var tips: Array[Vector3] = []
	_coral_branch(mb, rng, Vector3(0, h, 0), Vector3(0, 1, 0), 3.2, 0.38, 3, tips)
	for t in tips:
		gb.add(MeshBuilder.sphere(rng.randf_range(0.14, 0.24), 8, 4), Transform3D(Basis(), t), PINK)
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf()
		mb.limb(Vector3(0, 0.5, 0), Vector3(cos(a) * 1.0, -0.05, sin(a) * 1.0), 0.25, 0.08, CORAL, 5)
	return _finish(mb, gb, [_trunk_collider(0.65, h + 5.0)], Color(1.0, 0.45, 0.4), Vector3(0, h + 3.0, 0))


static func _coral_branch(mb: MeshBuilder, rng: RandomNumberGenerator, from: Vector3, dir: Vector3, length: float, r: float, depth: int, tips: Array[Vector3]) -> void:
	for k in rng.randi_range(2, 3):
		var d := (dir + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.2, 0.7), rng.randf_range(-0.9, 0.9))).normalized()
		var to := from + d * length * rng.randf_range(0.8, 1.1)
		mb.limb(from, to, r, r * 0.6, CORAL, 6)
		if depth > 1:
			_coral_branch(mb, rng, to, d, length * 0.68, r * 0.6, depth - 1, tips)
		else:
			tips.append(to)


# ------------------------------------------------------------------ 5: orb tree

static func _orb_tree(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var h := rng.randf_range(9.0, 13.0)
	mb.limb(Vector3.ZERO, Vector3(0, h * 0.75, 0), 0.65, 0.3, BARK_DARK, 10)
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf() * 0.4
		mb.limb(Vector3(0, 0.9, 0), Vector3(cos(a) * 1.3, -0.05, sin(a) * 1.3), 0.25, 0.08, BARK_DARK, 5)
	# Two neon vines spiralling up the trunk
	for v in 2:
		var prev := Vector3(0, 0.2, 0)
		for k in range(1, 25):
			var t := k / 24.0
			var a := t * TAU * 3.0 + v * PI
			var r := lerpf(0.68, 0.33, t)
			var p := Vector3(cos(a) * r, 0.2 + t * h * 0.72, sin(a) * r)
			gb.limb(prev, p, 0.05, 0.05, LIME, 4)
			prev = p
	# Leafy clusters, with big purple orbs floating among them
	var crown := Vector3(0, h * 0.8, 0)
	for k in 7:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.5, 2.8)
		var c := crown + Vector3(cos(a) * d, rng.randf_range(-0.5, 2.2), sin(a) * d)
		mb.limb(crown - Vector3(0, 1.0, 0), c, 0.15, 0.06, BARK_DARK, 5)
		mb.add(MeshBuilder.sphere(rng.randf_range(1.3, 2.0), 10, 5), Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), c), LEAF_PLUM)
	for k in 16:
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.2, 4.6)
		var p := crown + Vector3(cos(a) * d, rng.randf_range(-2.5, 2.8), sin(a) * d)
		gb.add(MeshBuilder.sphere(rng.randf_range(0.28, 0.5), 10, 6), Transform3D(Basis(), p), VIOLET)
	return _finish(mb, gb, [_trunk_collider(0.7, h)], Color(0.7, 0.35, 1.0), crown)


# ------------------------------------------------------------------ 6: ribbon arch

static func _ribbon_arch(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var h := rng.randf_range(8.0, 11.0)
	var span := rng.randf_range(2.6, 3.6)
	var left := Vector3(-span, 0, 0)
	var right := Vector3(span, 0, 0)
	var apex := Vector3(0, h, 0)
	var arcs := []
	for side in [left, right]:
		var prev: Vector3 = side
		var pts: Array[Vector3] = [side]
		for k in range(1, 9):
			var t := k / 8.0
			var p: Vector3 = (side as Vector3).lerp(apex, t) + Vector3(0, sin(t * PI) * 1.2, 0) - (side as Vector3) * sin(t * PI) * -0.15
			mb.limb(prev, p, lerpf(0.42, 0.25, (k - 1) / 8.0), lerpf(0.42, 0.25, t), BARK_BLUE, 8)
			pts.append(p)
			prev = p
		arcs.append(pts)
		for k in 4:
			var a := TAU * k / 4.0 + rng.randf()
			mb.limb(side + Vector3(0, 0.5, 0), side + Vector3(cos(a) * 0.9, -0.05, sin(a) * 0.9), 0.18, 0.06, BARK_BLUE, 5)
	mb.add(MeshBuilder.sphere(3.0, 12, 6), Transform3D(Basis.from_scale(Vector3(1.4, 0.5, 1.0)), apex + Vector3(0, 1.4, 0)), LEAF_INDIGO)
	# Neon ribbons draped between the two trunks, plus drips hanging from them
	for r in 4:
		var t := 0.35 + r * 0.15
		var a: Vector3 = arcs[0][int(t * 8)]
		var b: Vector3 = arcs[1][int(t * 8)]
		var prev := a
		for k in range(1, 11):
			var u := k / 10.0
			var p := a.lerp(b, u) + Vector3(0, -sin(u * PI) * rng.randf_range(1.0, 1.8), rng.randf_range(-0.15, 0.15))
			gb.limb(prev, p, 0.045, 0.045, BLUE, 4)
			if k % 3 == 0:
				_bead_string(mb, gb, rng, p, rng.randf_range(0.6, 1.5), 2, BLUE, 0.07)
			prev = p
	var cols := [_trunk_collider(0.45, h), _trunk_collider(0.45, h)]
	cols[0][1] = Transform3D(Basis(), left + Vector3(0, h * 0.5, 0))
	cols[1][1] = Transform3D(Basis(), right + Vector3(0, h * 0.5, 0))
	return _finish(mb, gb, cols, Color(0.3, 0.55, 1.0), apex - Vector3(0, 3.5, 0))


# ------------------------------------------------------------------ fallen logs and landmarks

## A fallen trunk overgrown with glowing shelf fungus and neon vines. Same shape data as
## SwampProps.fallen_log (length, radius, colliders along local X).
static func fallen_log(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var length := rng.randf_range(8.0, 14.0)
	var r := rng.randf_range(0.45, 0.8)
	var a := Vector3(-length * 0.5, 0, 0)
	var b := Vector3(length * 0.5, 0, 0)
	var bark: Color = [BARK_VIOLET, BARK_DARK, BARK_BLUE][rng.randi() % 3]
	mb.limb(a, b, r, r * 0.6, bark, 12)
	var plate_r := r * rng.randf_range(2.2, 2.8)
	var plate_basis := Basis(Vector3(0, 0, 1), deg_to_rad(90.0))
	mb.add(MeshBuilder.cyl(plate_r, plate_r * 0.9, 0.45, 14), Transform3D(plate_basis, a + Vector3(-0.15, 0, 0)), Color(0.1, 0.08, 0.1, 0.0))
	for k in 8:
		var ang := rng.randf() * TAU
		var start := a + Vector3(-0.2, cos(ang), sin(ang)) * plate_r * 0.85
		mb.limb(start, start + Vector3(rng.randf_range(-0.9, -0.2), cos(ang) * 0.8, sin(ang) * 0.8), 0.09, 0.02, bark, 4)
	# Glowing shelf fungus along the sides
	var fungus: Color = [CYAN, TEAL, MAGENTA, GOLD][rng.randi() % 4]
	for k in rng.randi_range(6, 11):
		var t := rng.randf_range(-0.45, 0.45) * length
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var rr := lerpf(r, r * 0.6, t / length + 0.5)
		gb.add(MeshBuilder.sphere(rng.randf_range(0.18, 0.32), 8, 4), Transform3D(Basis.from_scale(Vector3(1.2, 0.3, 1.0)), Vector3(t, rng.randf_range(-0.2, 0.5) * rr, side * rr * 0.95)), Color(fungus, 0.0))
	# A neon vine creeping along the top
	var prev := Vector3(-length * 0.45, r * 0.9, 0)
	for k in range(1, 13):
		var t := -0.45 + 0.9 * k / 12.0
		var rr := lerpf(r, r * 0.6, t + 0.5)
		var p := Vector3(t * length, rr * 0.95, sin(k * 1.3) * rr * 0.5)
		gb.limb(prev, p, 0.04, 0.04, Color(LIME, 0.0), 4)
		prev = p
	var body_shape := CylinderShape3D.new()
	body_shape.radius = r * 0.85
	body_shape.height = length
	var plate_shape := CylinderShape3D.new()
	plate_shape.radius = plate_r
	plate_shape.height = 0.45
	var mesh := mb.commit()
	gb.commit_into(mesh, MeshBuilder.glow_material())
	return {
		"mesh": mesh, "radius": r, "length": length, "light": fungus, "light_at": Vector3(0, r + 0.5, 0),
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
