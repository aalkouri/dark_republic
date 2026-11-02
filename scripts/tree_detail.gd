class_name TreeDetail
## Extra detail for the trees and fallen trees inside the arena (not the ones lining its edge,
## which ArenaEdge builds on its own): ridged bark with knots, bracket fungus and moss up the
## trunks; and for fallen trees a natural torn-up root mass (clods of earth, roots splaying out
## and dangling, stones caught in it) and a splintered break, instead of a flat disc.


## Ridges of bark running along a trunk segment a -> b (radii ra, rb), a knot or two, and now
## and then a bracket fungus or a moss patch. Colours keep alpha 0 (trunks don't sway).
static func bark(mb: MeshBuilder, rng: RandomNumberGenerator, a: Vector3, b: Vector3, ra: float, rb: float, col: Color, ridges := 6, fungus := true) -> void:
	var axis := (b - a)
	var length := axis.length()
	if length < 0.05:
		return
	var up := axis / length
	var side := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	var other := up.cross(side).normalized()
	var dark := Color(col.r * 0.62, col.g * 0.6, col.b * 0.58, 0.0)
	var light := Color(minf(col.r * 1.18, 1.0), minf(col.g * 1.15, 1.0), minf(col.b * 1.1, 1.0), 0.0)
	for k in ridges:   # long raised ridges, slightly wandering, darker in the furrows between
		var ang := TAU * k / ridges + rng.randf_range(-0.25, 0.25)
		var t0 := rng.randf_range(0.0, 0.25)
		var t1 := rng.randf_range(0.65, 1.0)
		var o0 := (side * cos(ang) + other * sin(ang)) * lerpf(ra, rb, t0) * 0.93
		var ang2 := ang + rng.randf_range(-0.2, 0.2)
		var o1 := (side * cos(ang2) + other * sin(ang2)) * lerpf(ra, rb, t1) * 0.93
		var w := lerpf(ra, rb, 0.5) * rng.randf_range(0.1, 0.16)
		mb.limb(a + axis * t0 + o0, a + axis * t1 + o1, w, w * 0.6, dark if k % 2 == 0 else light, 4)
	for k in rng.randi_range(1, 2):   # knots where old branches were
		var t := rng.randf_range(0.15, 0.85)
		var ang := rng.randf() * TAU
		var o := (side * cos(ang) + other * sin(ang))
		var rr := lerpf(ra, rb, t)
		mb.add(MeshBuilder.sphere(rr * rng.randf_range(0.22, 0.32), 7, 4), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.0)), a + axis * t + o * rr * 0.9), dark)
		mb.add(MeshBuilder.sphere(rr * 0.12, 6, 3), Transform3D(Basis(), a + axis * t + o * rr * 1.12), Color(0.08, 0.06, 0.05, 0.0))
	if fungus and rng.randf() < 0.55:   # shelf fungus: a little stack of pale brackets
		var t := rng.randf_range(0.1, 0.6)
		var ang := rng.randf() * TAU
		var o := (side * cos(ang) + other * sin(ang))
		var rr := lerpf(ra, rb, t)
		var fcol := Color(0.78, 0.68, 0.5, 0.0) if rng.randf() < 0.6 else Color(0.62, 0.38, 0.2, 0.0)
		for s in rng.randi_range(2, 3):
			var at := a + axis * (t + s * 0.035) + o * rr * 1.02
			var fs := rr * rng.randf_range(0.28, 0.42) * (1.0 - s * 0.2)
			mb.add(MeshBuilder.sphere(fs, 8, 4), Transform3D(Basis.from_scale(Vector3(1.0, 0.28, 1.0)), at + o * fs * 0.5), fcol)
	if rng.randf() < 0.5:   # a patch of moss on the shady side
		var t := rng.randf_range(0.0, 0.4)
		var ang := rng.randf() * TAU
		var o := (side * cos(ang) + other * sin(ang))
		var rr := lerpf(ra, rb, t)
		mb.add(MeshBuilder.sphere(rr * 0.55, 7, 4), Transform3D(Basis.from_scale(Vector3(0.6, 1.4, 0.6)), a + axis * t + o * rr * 0.82), Color(0.24, 0.34, 0.12, 0.0))


## A fallen tree's torn-up root mass at `at` (the end of the trunk; the trunk lies along +X):
## clods of earth heaped round the roots' hub, thick roots splaying out and snapping off, thin
## ones dangling, stones caught in the earth. Natural and ragged, no flat disc.
static func root_mass(mb: MeshBuilder, rng: RandomNumberGenerator, at: Vector3, r: float, dirt: Color, root_col: Color) -> void:
	var spread := r * rng.randf_range(2.2, 2.8)
	var dirt_dark := Color(dirt.r * 0.75, dirt.g * 0.72, dirt.b * 0.7, 0.0)
	var hub := at + Vector3(-r * 0.35, 0, 0)
	# Earth: lumpy clods clinging round the hub, thinning outward, heavier at the bottom
	for k in rng.randi_range(7, 10):
		var ang := rng.randf() * TAU
		var d := sqrt(rng.randf()) * spread * 0.7
		var c := hub + Vector3(rng.randf_range(-0.35, 0.1) * r, cos(ang) * d * 0.8 - r * 0.15, sin(ang) * d)
		var s := r * rng.randf_range(0.45, 0.9) * (1.0 - d / (spread * 1.2))
		mb.add(ForestProps._lumpy(s, rng), Transform3D(Basis.from_scale(Vector3(0.7, rng.randf_range(0.7, 1.1), rng.randf_range(0.8, 1.2))), c), dirt if k % 3 else dirt_dark)
	# Thick roots splaying out from the hub, each bending once and tapering to a snapped end
	var n := rng.randi_range(9, 13)
	for k in n:
		var ang := TAU * k / n + rng.randf_range(-0.25, 0.25)
		var out := Vector3(0, cos(ang), sin(ang))
		var len1 := spread * rng.randf_range(0.4, 0.62)
		var mid := hub + out * len1 + Vector3(rng.randf_range(-0.5, 0.1) * r, 0, 0)
		var tip := mid + (out * 0.6 + Vector3(rng.randf_range(-0.7, -0.1), -0.45, 0)).normalized() * spread * rng.randf_range(0.2, 0.42)   # bending back and drooping
		var rr := r * rng.randf_range(0.18, 0.3)
		mb.limb(hub, mid, rr, rr * 0.6, root_col, 5)
		mb.limb(mid, tip, rr * 0.6, rr * 0.12, root_col, 4)
		if rng.randf() < 0.6:   # a side root
			var fork := hub.lerp(mid, rng.randf_range(0.4, 0.8))
			var fdir := (out + Vector3(rng.randf_range(-0.8, 0.2), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))).normalized()
			mb.limb(fork, fork + fdir * spread * rng.randf_range(0.3, 0.55), rr * 0.4, rr * 0.06, root_col, 4)
	# Fine rootlets hanging down from the lower roots
	for k in rng.randi_range(8, 14):
		var ang := rng.randf_range(-PI * 0.9, PI * 0.9) + PI
		var start := hub + Vector3(rng.randf_range(-0.4, 0.1) * r, cos(ang), sin(ang)) * spread * rng.randf_range(0.3, 0.8)
		mb.limb(start, start + Vector3(rng.randf_range(-0.2, 0.2), -rng.randf_range(0.3, 0.9), rng.randf_range(-0.2, 0.2)), r * 0.05, r * 0.01, root_col, 3)
	# Stones caught in the earth
	for k in rng.randi_range(2, 4):
		var ang := rng.randf() * TAU
		var c := hub + Vector3(-r * 0.3, cos(ang), sin(ang)) * spread * rng.randf_range(0.2, 0.55)
		mb.add(ForestProps._lumpy(r * rng.randf_range(0.15, 0.28), rng), Transform3D(Basis(), c), Color(0.36, 0.35, 0.32, 0.0))


## A splintered break at `at`, the trunk running back along -`dir` (unit, horizontal): jagged
## shards of wood of different lengths round the rim and a ragged core, no flat end cap.
static func broken_end(mb: MeshBuilder, rng: RandomNumberGenerator, at: Vector3, dir: Vector3, r: float, col: Color) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.01:
		side = Vector3.FORWARD
	var other := dir.cross(side).normalized()
	var pale := Color(0.72, 0.62, 0.45, 0.0)   # the bare wood inside
	var basis_along := Basis(side, dir, side.cross(dir))   # cones point along `dir`
	mb.add(ForestProps._lumpy(r * 0.85, rng), Transform3D(basis_along * Basis.from_scale(Vector3(1.0, 0.35, 1.0)), at), pale)
	var n := rng.randi_range(7, 10)
	for k in n:
		var ang := TAU * k / n + rng.randf_range(-0.2, 0.2)
		var o := (side * cos(ang) + other * sin(ang)) * r * rng.randf_range(0.45, 0.85)
		var l := r * rng.randf_range(0.4, 1.6)
		var tilt := Basis(side, rng.randf_range(-0.25, 0.25)) * Basis(other, rng.randf_range(-0.25, 0.25))
		mb.add(MeshBuilder.cone(r * rng.randf_range(0.12, 0.22), l, 4), Transform3D(tilt * basis_along, at + o + dir * l * 0.5), pale if k % 3 else col)
