class_name SwampProps
extends RefCounted
## Procedural swamp props. Each builder returns { "mesh": ArrayMesh, "colliders": [[Shape3D, Transform3D], ...] }.
## Origin at the base, on the ground. Vertex alpha = wind sway weight (see MeshBuilder).
##   0 Bald cypress  tall, with a fluted buttressed base, knees, lumpy foliage clusters on crooked
##                   branches and long curtains of grey-green Spanish moss
##   1 Dead snag     twisted bare trunk, crooked branches, broken top, wisps of moss
##   2 Swamp willow  short leaning trunk, dome canopy with drooping curtains
##   3 Mangrove      canopy raised on arching stilt roots, hanging aerial roots

const VARIANTS := 4

const BARK := Color(0.26, 0.2, 0.15, 0.0)
const DARK_BARK := Color(0.17, 0.14, 0.11, 0.0)
const DEAD := Color(0.36, 0.34, 0.3, 0.0)
const ROOT := Color(0.22, 0.17, 0.12, 0.0)
const FOLIAGE := Color(0.17, 0.25, 0.1, 0.3)
const FOLIAGE_DARK := Color(0.11, 0.18, 0.08, 0.3)
const WILLOW := Color(0.2, 0.3, 0.12, 1.0)
const MOSS := Color(0.45, 0.48, 0.34, 1.0)
const MOSS_GRAY := Color(0.55, 0.57, 0.48, 1.0)    # Spanish moss
const FOLIAGE_LIGHT := Color(0.32, 0.42, 0.16, 0.3)
const MOSS_PATCH := Color(0.28, 0.36, 0.14, 0.0)
const DIRT := Color(0.2, 0.15, 0.1, 0.0)
const STONE := Color(0.33, 0.34, 0.31, 0.0)


static func tree(variant: int, rng: RandomNumberGenerator) -> Dictionary:
	match variant:
		0:
			return _cypress(rng)
		1:
			return _snag(rng)
		2:
			return _willow(rng)
		_:
			return _mangrove(rng)


static func _trunk_collider(r: float, h: float) -> Array:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return [s, Transform3D(Basis(), Vector3(0, h * 0.5, 0))]


static func _moss_strands(mb: MeshBuilder, rng: RandomNumberGenerator, center: Vector3, spread: float, n: int, len_min: float, len_max: float, color := MOSS) -> void:
	for k in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * spread
		var top := center + Vector3(cos(a) * d, 0, sin(a) * d)
		var l := rng.randf_range(len_min, len_max)
		mb.limb(top, top + Vector3(rng.randf_range(-0.15, 0.15), -l, rng.randf_range(-0.15, 0.15)), rng.randf_range(0.07, 0.14), 0.015, color, 5)


# ------------------------------------------------------------------ 0: bald cypress

static func _cypress(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var h := rng.randf_range(13.0, 19.0)
	# A deeply fluted, flared base: a wide bell of bark with ridged buttress roots running
	# down into the mud all round it, like an old bald cypress standing in the water
	var flare := rng.randf_range(1.25, 1.6)
	mb.add(MeshBuilder.cyl(0.5, flare, 3.2, 14, 3), Transform3D(Basis(), Vector3(0, 1.6, 0)), DARK_BARK)
	var flutes := rng.randi_range(9, 13)
	for k in flutes:
		var a := TAU * k / flutes + rng.randf_range(-0.12, 0.12)
		var dir := Vector3(cos(a), 0, sin(a))
		var top := dir * 0.42 + Vector3(0, rng.randf_range(3.2, 4.6), 0)
		var mid := dir * (flare * 0.75) + Vector3(0, rng.randf_range(0.9, 1.4), 0)
		var foot := dir * (flare + rng.randf_range(0.35, 0.9)) + Vector3(0, -0.1, 0)
		var col := DARK_BARK if k % 2 else BARK.lerp(DARK_BARK, 0.5)
		mb.limb(top, mid, 0.12, 0.2, col, 5)
		mb.limb(mid, foot, 0.2, 0.08, col, 5)
	# Cypress "knees" poking out of the mud
	for k in rng.randi_range(5, 10):
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.0, 4.2)
		var kh := rng.randf_range(0.35, 1.0)
		mb.add(MeshBuilder.cone(rng.randf_range(0.12, 0.22), kh, 6), Transform3D(Basis(), Vector3(cos(a) * d, kh * 0.5 - 0.05, sin(a) * d)), DARK_BARK)
	# A tall, slightly crooked trunk in three pieces, with bark ridges up it
	var lean := Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
	var top := Vector3(0, h * 0.86, 0) + lean
	var p1 := Vector3(0, 3.0, 0)
	var p2 := p1.lerp(top, 0.4) + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
	var p3 := p1.lerp(top, 0.75) + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
	mb.limb(p1, p2, 0.5, 0.38, BARK, 10)
	mb.limb(p2, p3, 0.38, 0.27, BARK, 9)
	mb.limb(p3, top, 0.27, 0.12, BARK, 8)
	for k in 5:   # darker ridges of bark running up the lower trunk
		var a := TAU * k / 5.0 + rng.randf() * 0.5
		var o := Vector3(cos(a), 0, sin(a))
		mb.limb(p1 + o * 0.46, p2 + o * 0.34, 0.07, 0.04, DARK_BARK, 4)
	# Crooked branches high up; on each, lumpy clusters of feathery foliage, and Spanish moss
	# hanging in long grey-green curtains along the branch and under every cluster
	var clusters: Array = [[top + Vector3(0, 0.6, 0), rng.randf_range(1.6, 2.2)]]
	for k in rng.randi_range(6, 9):
		var t := rng.randf_range(0.45, 0.98)
		var from := p1.lerp(top, t)
		var a := rng.randf() * TAU
		var reach := rng.randf_range(2.4, 4.6) * lerpf(1.0, 0.6, t)
		var elbow := from + Vector3(cos(a) * reach * 0.5, rng.randf_range(0.2, 0.8), sin(a) * reach * 0.5)
		var to := from + Vector3(cos(a + rng.randf_range(-0.4, 0.4)) * reach, rng.randf_range(0.6, 1.8), sin(a + rng.randf_range(-0.4, 0.4)) * reach)
		mb.limb(from, elbow, 0.15, 0.1, BARK, 6)
		mb.limb(elbow, to, 0.1, 0.04, BARK, 5)
		for m in rng.randi_range(3, 6):   # moss along the branch
			var at := from.lerp(to, rng.randf_range(0.25, 1.0))
			_moss_curtain(mb, rng, at, rng.randf_range(1.8, 4.6))
		clusters.append([to + Vector3(0, 0.25, 0), rng.randf_range(1.2, 2.0)])
		if rng.randf() < 0.5:
			clusters.append([elbow + Vector3(0, 0.4, 0), rng.randf_range(0.9, 1.4)])
	for c in clusters:
		var at: Vector3 = c[0]
		var r: float = c[1]
		var col := FOLIAGE if rng.randf() < 0.55 else FOLIAGE_DARK
		for b in rng.randi_range(3, 5):   # a lumpy cluster of blobs, not one smooth pad
			var o := Vector3(rng.randf_range(-0.6, 0.6) * r, rng.randf_range(-0.15, 0.25) * r, rng.randf_range(-0.6, 0.6) * r)
			var br := r * rng.randf_range(0.5, 0.8)
			mb.add(MeshBuilder.sphere(br, 8, 5), Transform3D(Basis.from_scale(Vector3(1.0, rng.randf_range(0.4, 0.6), 1.0)), at + o), col.lerp(FOLIAGE_LIGHT, rng.randf() * 0.35))
		for m in rng.randi_range(4, 8):   # moss curtains under the cluster
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * r * 0.9
			_moss_curtain(mb, rng, at + Vector3(cos(a) * d, -r * 0.25, sin(a) * d), rng.randf_range(1.6, 4.2))
	return {"mesh": mb.commit(), "colliders": [_trunk_collider(1.1, h)]}


## A ragged curtain of Spanish moss hanging from `top`: a few strands of different lengths,
## kinked as they fall, grey-green and swaying in the wind.
static func _moss_curtain(mb: MeshBuilder, rng: RandomNumberGenerator, top: Vector3, length: float) -> void:
	var col := MOSS_GRAY if rng.randf() < 0.7 else MOSS
	for k in rng.randi_range(2, 4):
		var start := top + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.1, 0.05), rng.randf_range(-0.25, 0.25))
		var l := length * rng.randf_range(0.55, 1.0)
		var kink := start + Vector3(rng.randf_range(-0.2, 0.2), -l * 0.5, rng.randf_range(-0.2, 0.2))
		var end := kink + Vector3(rng.randf_range(-0.2, 0.2), -l * 0.5, rng.randf_range(-0.2, 0.2))
		var c2 := col
		c2.a = 0.6
		mb.limb(start, kink, rng.randf_range(0.09, 0.16), 0.06, c2, 4)
		mb.limb(kink, end, 0.06, 0.01, col, 4)


# ------------------------------------------------------------------ 1: dead snag

static func _snag(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var h := rng.randf_range(7.0, 11.0)
	var pts: Array[Vector3] = [Vector3.ZERO]
	var segs := 5
	for k in segs:
		var prev: Vector3 = pts[pts.size() - 1]
		pts.append(prev + Vector3(rng.randf_range(-0.5, 0.5), h / segs, rng.randf_range(-0.5, 0.5)))
	for k in segs:
		var r0 := lerpf(0.55, 0.12, float(k) / segs)
		var r1 := lerpf(0.55, 0.12, float(k + 1) / segs)
		mb.limb(pts[k], pts[k + 1], r0, r1 if k < segs - 1 else r1 * 1.4, DEAD, 8)
	# Jagged broken top
	var tip: Vector3 = pts[segs]
	for k in 3:
		var a := rng.randf() * TAU
		mb.limb(tip, tip + Vector3(cos(a) * 0.12, rng.randf_range(0.3, 0.8), sin(a) * 0.12), 0.08, 0.0, DEAD, 4)
	# Root flares
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf() * 0.5
		mb.limb(Vector3(0, 0.7, 0), Vector3(cos(a) * 1.1, -0.05, sin(a) * 1.1), 0.24, 0.07, DEAD, 5)
	# Crooked bare branches (two segments each), a few with moss wisps
	for k in rng.randi_range(4, 7):
		var at := pts[rng.randi_range(2, segs - 1)].lerp(pts[segs - 1], rng.randf())
		var a := rng.randf() * TAU
		var mid := at + Vector3(cos(a) * 1.3, rng.randf_range(0.3, 1.0), sin(a) * 1.3)
		var end := mid + Vector3(cos(a + rng.randf_range(-0.8, 0.8)) * 1.3, rng.randf_range(-0.2, 1.2), sin(a + rng.randf_range(-0.8, 0.8)) * 1.3)
		mb.limb(at, mid, 0.11, 0.06, DEAD, 5)
		mb.limb(mid, end, 0.06, 0.015, DEAD, 4)
		if rng.randf() < 0.5:
			_moss_strands(mb, rng, mid.lerp(end, 0.5), 0.4, 3, 0.8, 2.0)
	return {"mesh": mb.commit(), "colliders": [_trunk_collider(0.55, h)]}


# ------------------------------------------------------------------ 2: swamp willow

static func _willow(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var a0 := rng.randf() * TAU
	var lean := Vector3(cos(a0), 0, sin(a0)) * rng.randf_range(0.6, 1.3)
	var fork := Vector3(0, rng.randf_range(2.8, 3.6), 0) + lean
	mb.limb(Vector3.ZERO, fork, 0.75, 0.48, DARK_BARK, 10)
	for k in 4:
		var a := rng.randf() * TAU
		mb.limb(Vector3.ZERO, Vector3(cos(a) * 1.0, -0.05, sin(a) * 1.0) + Vector3(0, 0, 0), 0.3, 0.1, DARK_BARK, 5)
	var crown := fork + Vector3(0, rng.randf_range(2.6, 3.4), 0)
	for k in 3:
		var a := rng.randf() * TAU
		mb.limb(fork, crown + Vector3(cos(a) * 1.4, rng.randf_range(-0.4, 0.4), sin(a) * 1.4), 0.32, 0.12, BARK, 6)
	var radius := rng.randf_range(3.0, 3.8)
	mb.add(MeshBuilder.sphere(radius * 0.8, 12, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), crown), FOLIAGE_DARK)
	for k in 6:   # a lumpy crown, not a smooth dome
		var a := TAU * k / 6.0 + rng.randf() * 0.5
		var o := Vector3(cos(a) * radius * 0.55, rng.randf_range(-0.2, 0.6), sin(a) * radius * 0.55)
		mb.add(MeshBuilder.sphere(radius * rng.randf_range(0.42, 0.58), 8, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.0)), crown + o), FOLIAGE_DARK.lerp(FOLIAGE, rng.randf()))
	# Drooping curtains: an outer ring and an inner ring of long strands
	for ring in [[radius * 0.95, 34, 1.8, 5.2], [radius * 0.6, 16, 1.6, 3.8]]:
		var rr: float = ring[0]
		var n: int = ring[1]
		for k in n:
			var a := TAU * k / n + rng.randf() * 0.15
			var top := crown + Vector3(cos(a) * rr, -0.15, sin(a) * rr)
			var l := rng.randf_range(ring[2], ring[3])
			var drift := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.5)
			mb.limb(top, top + drift + Vector3(0, -l, 0), rng.randf_range(0.14, 0.22), 0.03, WILLOW, 5)
	return {"mesh": mb.commit(), "colliders": [_trunk_collider(0.8, crown.y)]}


# ------------------------------------------------------------------ 3: mangrove

static func _mangrove(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var hub := Vector3(0, rng.randf_range(2.3, 2.9), 0)
	# Arching stilt roots
	var roots := rng.randi_range(6, 9)
	for k in roots:
		var a := TAU * k / roots + rng.randf() * 0.4
		var dir := Vector3(cos(a), 0, sin(a))
		var mid := hub + dir * rng.randf_range(1.2, 1.7) + Vector3(0, rng.randf_range(-0.1, 0.3), 0)
		var foot := dir * rng.randf_range(2.2, 3.0) + Vector3(0, -0.1, 0)
		mb.limb(hub, mid, 0.2, 0.16, ROOT, 6)
		mb.limb(mid, foot, 0.16, 0.12, ROOT, 6)
	var h := rng.randf_range(7.0, 9.5)
	var top := Vector3(rng.randf_range(-0.3, 0.3), h * 0.7, rng.randf_range(-0.3, 0.3))
	mb.limb(hub, top, 0.42, 0.26, BARK, 8)
	var clumps := [top + Vector3(0, 1.0, 0)]
	for k in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var to := top + Vector3(cos(a) * rng.randf_range(1.8, 2.8), rng.randf_range(-0.6, 0.8), sin(a) * rng.randf_range(1.8, 2.8))
		mb.limb(top.lerp(hub, rng.randf_range(0.0, 0.3)), to, 0.16, 0.07, BARK, 6)
		clumps.append(to)
		# Aerial roots dangling from branches
		if rng.randf() < 0.7:
			mb.limb(to, Vector3(to.x, rng.randf_range(0.5, 2.0), to.z), 0.05, 0.03, ROOT, 4)
	for c in clumps:
		var r := rng.randf_range(1.5, 2.2)
		mb.add(MeshBuilder.sphere(r, 10, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.0)), c), FOLIAGE if rng.randf() < 0.5 else FOLIAGE_DARK)
		for m in rng.randi_range(1, 3):
			var a := rng.randf() * TAU
			_moss_curtain(mb, rng, c + Vector3(cos(a) * r * 0.6, -r * 0.3, sin(a) * r * 0.6), rng.randf_range(1.0, 2.6))
	var root_cage := CylinderShape3D.new()
	root_cage.radius = 2.4
	root_cage.height = hub.y
	return {"mesh": mb.commit(), "colliders": [[root_cage, Transform3D(Basis(), Vector3(0, hub.y * 0.5, 0))], _trunk_collider(0.45, h)]}


# ------------------------------------------------------------------ fallen tree

## A fallen tree lying along local X, root plate at -X, broken top at +X.
static func fallen_log(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var length := rng.randf_range(8.0, 14.0)
	var r := rng.randf_range(0.45, 0.8)
	var a := Vector3(-length * 0.5, 0, 0)
	var b := Vector3(length * 0.5, 0, 0)
	mb.limb(a, b, r, r * 0.6, BARK if rng.randf() < 0.5 else DEAD, 12)
	# Broken, splintered tip
	for k in 4:
		var ang := TAU * k / 4.0 + rng.randf() * 0.5
		var off := Vector3(0, cos(ang), sin(ang)) * r * 0.35
		mb.limb(b + off, b + off + Vector3(rng.randf_range(0.3, 0.8), 0, 0), r * 0.25, 0.0, DEAD, 4)
	# Upturned root plate with dirt and tendrils
	var plate_r := r * rng.randf_range(2.4, 3.0)
	var plate_basis := Basis(Vector3(0, 0, 1), deg_to_rad(90.0))
	mb.add(MeshBuilder.cyl(plate_r, plate_r * 0.9, 0.45, 14), Transform3D(plate_basis, a + Vector3(-0.15, 0, 0)), DIRT)
	for k in 10:
		var ang := rng.randf() * TAU
		var start := a + Vector3(-0.2, cos(ang), sin(ang)) * plate_r * 0.85
		var end := start + Vector3(rng.randf_range(-0.9, -0.2), cos(ang) * 0.8, sin(ang) * 0.8)
		mb.limb(start, end, 0.09, 0.02, ROOT, 4)
	# Snapped branch stubs
	for k in rng.randi_range(3, 5):
		var t := rng.randf_range(-0.3, 0.45) * length
		var ang := rng.randf_range(-PI * 0.8, PI * 0.8)
		var dir := Vector3(rng.randf_range(0.0, 0.5), cos(ang), sin(ang)).normalized()
		var base := Vector3(t, 0, 0) + dir * r * 0.7
		mb.limb(base, base + dir * rng.randf_range(0.6, 1.4), r * 0.28, r * 0.12, DEAD, 5)
	# Moss patches along the top, a few hanging wisps
	for k in rng.randi_range(4, 7):
		var t := rng.randf_range(-0.45, 0.4) * length
		var rr := lerpf(r, r * 0.6, (t / length) + 0.5)
		mb.add(MeshBuilder.sphere(rng.randf_range(0.35, 0.7), 8, 4), Transform3D(Basis.from_scale(Vector3(1.3, 0.25, 0.9)), Vector3(t, rr * 0.92, rng.randf_range(-0.2, 0.2))), MOSS_PATCH)
	for k in 3:
		var t := rng.randf_range(-0.4, 0.4) * length
		mb.limb(Vector3(t, 0, r * 0.9), Vector3(t, -r * 0.9, r * 1.05), 0.06, 0.01, MOSS, 4)

	var body_shape := CylinderShape3D.new()
	body_shape.radius = r * 0.85
	body_shape.height = length
	var plate_shape := CylinderShape3D.new()
	plate_shape.radius = plate_r
	plate_shape.height = 0.45
	return {
		"mesh": mb.commit(),
		"radius": r,
		"length": length,
		"colliders": [[body_shape, Transform3D(plate_basis, Vector3.ZERO)], [plate_shape, Transform3D(plate_basis, a + Vector3(-0.15, 0, 0))]],
	}


# ------------------------------------------------------------------ ruined pillar

static func ruin(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var h := rng.randf_range(5.0, 11.0)
	var r := rng.randf_range(1.1, 1.6)
	mb.add(MeshBuilder.cyl(r * 0.92, r, h, 10), Transform3D(Basis(), Vector3(0, h * 0.5, 0)), STONE)
	mb.add(MeshBuilder.cyl(r * 1.25, r * 1.3, 0.6, 10), Transform3D(Basis(), Vector3(0, 0.3, 0)), STONE)
	# Mossy, broken top
	mb.add(MeshBuilder.sphere(r * 1.05, 10, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.25, 1.0)), Vector3(0, h, 0)), MOSS_PATCH)
	_moss_strands(mb, rng, Vector3(0, h - 0.1, 0), r * 0.95, 8, 0.8, 2.5)
	# Fallen chunks at the base
	for k in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		var s := rng.randf_range(0.5, 1.1)
		mb.add(MeshBuilder.box(Vector3(s, s * 0.7, s * 1.2)), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(cos(a) * (r + 1.3), s * 0.3, sin(a) * (r + 1.3))), STONE)
	return {"mesh": mb.commit(), "colliders": [_trunk_collider(r, h)]}
