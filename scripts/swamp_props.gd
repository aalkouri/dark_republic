class_name SwampProps
extends RefCounted
## Procedural swamp props. Each builder returns { "mesh": ArrayMesh, "colliders": [[Shape3D, Transform3D], ...] }.
## Origin at the base, on the ground. Vertex alpha = wind sway weight (see MeshBuilder).
##   0 Bald cypress  flared trunk, cypress knees, layered flat canopy, long hanging moss
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
	var h := rng.randf_range(11.0, 15.0)
	# Flared, buttressed base
	mb.add(MeshBuilder.cyl(0.4, 1.05, 2.4, 12), Transform3D(Basis(), Vector3(0, 1.2, 0)), DARK_BARK)
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf() * 0.4
		mb.limb(Vector3(0, 1.8, 0), Vector3(cos(a) * 1.25, -0.05, sin(a) * 1.25), 0.22, 0.12, DARK_BARK, 6)
	# Cypress "knees" poking out of the mud
	for k in rng.randi_range(4, 8):
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.8, 3.4)
		var kh := rng.randf_range(0.4, 0.9)
		mb.add(MeshBuilder.cone(rng.randf_range(0.12, 0.2), kh, 6), Transform3D(Basis(), Vector3(cos(a) * d, kh * 0.5 - 0.05, sin(a) * d)), DARK_BARK)
	# Trunk with a slight lean
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	var top := Vector3(0, h * 0.82, 0) + lean
	mb.limb(Vector3(0, 2.3, 0), top, 0.4, 0.17, BARK, 10)
	# Layered flat canopy pads on branches, moss hanging below each
	var pads := [[top + Vector3(0, h * 0.12, 0), 2.0]]
	for k in rng.randi_range(4, 6):
		var t := rng.randf_range(0.5, 0.95)
		var from := Vector3(0, 2.3, 0).lerp(top, t)
		var a := rng.randf() * TAU
		var reach := rng.randf_range(2.0, 3.6)
		var to := from + Vector3(cos(a) * reach, rng.randf_range(0.6, 1.6), sin(a) * reach)
		mb.limb(from, to, 0.14, 0.05, BARK, 6)
		pads.append([to + Vector3(0, 0.3, 0), rng.randf_range(1.5, 2.3)])
	for p in pads:
		var c: Vector3 = p[0]
		var r: float = p[1]
		mb.add(MeshBuilder.sphere(r, 10, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.38, 1.0)), c), FOLIAGE if rng.randf() < 0.6 else FOLIAGE_DARK)
		_moss_strands(mb, rng, c - Vector3(0, r * 0.3, 0), r * 0.85, rng.randi_range(6, 10), 1.2, 3.4)
	return {"mesh": mb.commit(), "colliders": [_trunk_collider(0.95, h)]}


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
	mb.add(MeshBuilder.sphere(radius, 14, 7), Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), crown), FOLIAGE_DARK)
	# Drooping curtains: an outer ring and an inner ring of long strands
	for ring in [[radius * 0.95, 34, 3.2, 4.8], [radius * 0.6, 16, 2.4, 3.6]]:
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
