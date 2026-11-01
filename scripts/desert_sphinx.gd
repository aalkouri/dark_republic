class_name DesertSphinx
extends RefCounted
## The Great Sphinx: a 37 m lion couchant with a pharaoh's head, carved from the living rock and
## worn by four thousand years of wind. Faces local +Z, origin on its plinth's floor.
##
##   Body     a long, deep torso with the spine ridge, ribs and shoulder blades showing through,
##            heavy haunches, hind legs folded beside it with the paws tucked forward, the tail
##            curled round the right haunch; forelegs stretched far out in front, great paws
##            with toes and claws, cased in rows of later restoration blocks.
##   Head     the nemes headdress with its horizontal stripes (faded ochre and lapis blue), the
##            brow band, the flaring wings behind the ears and the striped lappets falling onto
##            the chest, the queue down the back; a face with almond eyes outlined in kohl,
##            eyebrows, broad cheeks, full lips, big ears, a broken nose and the stub of the
##            uraeus cobra, and the long plaited false beard.
##   Weather  erosion bands along the flanks, chunks fallen out, sand drifted on every ledge
##            (DesertProps.STONE_SHADER does the bedding lines, pits, streaks and settled sand).
##   Between  the Dream Stele between its paws, carved with glyphs under a winged sun; in front
##            of them the tomb door in the plinth, from which the Pharaoh rises.
## Its eyes are their own surface: the Pharaoh's ultimate sets them blazing.

const HEAD_AT := Vector3(0, 12.2, 6.6)
const HEAD_SCALE := 2.35
const TOMB_Z := 23.0             # the tomb door, in front of the paws
const STRIPE_A := Color(0.83, 0.7, 0.52, 0.0)
const STRIPE_B := Color(0.56, 0.58, 0.6, 0.0)    # the last of the blue paint
const BODY := Color(0.8, 0.67, 0.5, 0.0)
const PATCH := Color(0.9, 0.78, 0.6, 0.0)        # restoration masonry


static func build(night: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var mb := MeshBuilder.new()
	var eye_mb := MeshBuilder.new()
	var col := BODY
	var sh := func(c: Color, amt: float) -> Color: return DesertProps._shade(c, rng, amt)
	# ---- torso: a deep barrel from the rump to the chest (an elliptical drum, rounded ends)
	mb.add(MeshBuilder.cyl(1.0, 1.0, 15.0, 36, 8), Transform3D(Basis.from_scale(Vector3(4.3, 3.8, 1.0)) * Basis(Vector3(1, 0, 0), PI / 2), Vector3(0, 4.1, -6.5)), sh.call(col, 0.02))
	mb.add(MeshBuilder.sphere(1.0, 36, 18), Transform3D(Basis.from_scale(Vector3(4.3, 3.8, 2.6)), Vector3(0, 4.1, -14.0)), sh.call(col, 0.02))
	# the belly sags a little between the legs, the back dips behind the shoulders
	mb.add(MeshBuilder.sphere(1.0, 32, 16), Transform3D(Basis.from_scale(Vector3(3.9, 1.6, 7.5)), Vector3(0, 1.4, -6.0)), sh.call(col, 0.02))
	# erosion bands along the flanks: shallow softer layers worn back between harder ones
	for k in 3:
		var y := 2.2 + k * 1.6
		var rx := 4.3 * sqrt(maxf(0.0, 1.0 - pow((y - 4.1) / 3.8, 2.0))) + 0.04
		for sd in [-1.0, 1.0]:
			mb.add(MeshBuilder.sphere(1.0, 16, 6), Transform3D(Basis.from_scale(Vector3(0.07, 0.3, 7.4)), Vector3(sd * rx, y, -6.8)), sh.call(col.darkened(0.07), 0.02))
	# the spine ridge and shoulder blades
	mb.add(MeshBuilder.sphere(1.0, 16, 8), Transform3D(Basis.from_scale(Vector3(0.9, 0.5, 8.6)), Vector3(0, 7.75, -6.5)), sh.call(col, 0.03))
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.sphere(1.0, 14, 8), Transform3D(Basis(Vector3(0, 0, 1), sd * 0.35).scaled(Vector3(1.5, 2.4, 2.6)), Vector3(sd * 2.9, 6.4, 0.6)), sh.call(col, 0.03))
	# ---- haunches, hind legs folded, hind paws tucked forward
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.sphere(1.0, 32, 16), Transform3D(Basis.from_scale(Vector3(2.0, 3.4, 4.4)), Vector3(sd * 3.2, 3.6, -11.8)), sh.call(col, 0.02))
		mb.limb(Vector3(sd * 4.0, 1.6, -15.0), Vector3(sd * 4.6, 1.0, -7.5), 1.5, 1.2, sh.call(col, 0.04), 12)   # folded hind leg
		_paw(mb, Transform3D(Basis(), Vector3(sd * 4.7, 0.0, -6.0)), sh.call(col, 0.03), 0.85, rng)
	# ---- tail: up off the rump, down and round the right haunch, a tuft at the end
	var tail: Array[Vector3] = []
	for k in 16:
		var t := k / 15.0
		var a := t * PI * 0.95
		tail.append(Vector3(0.6 + sin(a) * 5.4, lerpf(3.4, 0.55, sqrt(t)), -17.0 + (1.0 - cos(a)) * 5.0))
	for k in tail.size() - 1:
		mb.limb(tail[k], tail[k + 1], lerpf(0.55, 0.32, k / 15.0), lerpf(0.55, 0.32, (k + 1) / 15.0), sh.call(col, 0.03), 8)
	mb.add(MeshBuilder.sphere(0.6, 8, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.6)), tail[-1] + Vector3(0.1, 0, 0.5)), sh.call(col.darkened(0.06), 0.03))
	# ---- chest and neck
	mb.add(MeshBuilder.sphere(1.0, 28, 16), Transform3D(Basis.from_scale(Vector3(4.2, 4.6, 3.6)), Vector3(0, 5.0, 2.6)), sh.call(col, 0.03))
	mb.limb(Vector3(0, 6.5, 2.0), Vector3(0, 10.3, 5.6), 3.0, 2.3, sh.call(col, 0.03), 14)
	# ---- forelegs stretched out in front, paws cased in restoration blocks
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.sphere(1.0, 12, 8), Transform3D(Basis.from_scale(Vector3(1.9, 2.6, 2.4)), Vector3(sd * 3.3, 2.6, 4.6)), sh.call(col, 0.04))   # elbow
		mb.limb(Vector3(sd * 3.3, 1.4, 5.5), Vector3(sd * 3.25, 1.15, 17.0), 1.45, 1.2, sh.call(col, 0.03), 14)
		_paw(mb, Transform3D(Basis(), Vector3(sd * 3.25, 0.0, 18.4)), sh.call(col, 0.03), 1.15, rng)
		# rows of later restoration blocks along the outside of the foreleg
		for row in 3:
			for b in 9:
				var z := 6.5 + b * 1.25 + (0.6 if row % 2 else 0.0)
				if z > 17.0:
					continue
				var y := 0.35 + row * 0.62
				mb.add(MeshBuilder.box(Vector3(0.25, 0.56, 1.18)), Transform3D(Basis(), Vector3(sd * (3.25 + 1.3 - row * 0.12), y, z)), sh.call(PATCH, 0.08))
	# ---- courses of restoration masonry along the foot of both flanks
	for sd in [-1.0, 1.0]:
		for row in 2:
			for b in 17:
				var z := -15.0 + b * 1.05 + (0.5 if row % 2 else 0.0)
				var y := 0.32 + row * 0.6
				var rx := 4.3 * sqrt(maxf(0.0, 1.0 - pow((y - 4.1) / 3.8, 2.0))) + 0.06
				mb.add(MeshBuilder.box(Vector3(0.3, 0.55, 1.0)), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)), Vector3(sd * (rx * 0.92), y, z)), sh.call(PATCH, 0.08))
	# ---- chunks fallen out of the flanks (darker hollows) and a crack down the neck
	for k in 9:
		var sd := 1.0 if k % 2 == 0 else -1.0
		var at := Vector3(sd * 4.3, rng.randf_range(2.0, 6.5), rng.randf_range(-13.0, 0.0))
		mb.add(ForestProps._lumpy(rng.randf_range(0.4, 0.9), rng), Transform3D(Basis.from_scale(Vector3(0.3, 1.0, 1.0)), at), sh.call(col.darkened(0.14), 0.05))
	for k in 6:
		mb.add(MeshBuilder.box(Vector3(0.12, 0.6, 0.12)), Transform3D(Basis(Vector3(0, 0, 1), 0.3 * sin(k * 2.0)), Vector3(1.5 + sin(k) * 0.2, 8.0 + k * 0.5, 5.9 + k * 0.1)), sh.call(col.darkened(0.45), 0.02))
	# ---- the head
	head(mb, Transform3D(Basis.from_scale(Vector3.ONE * HEAD_SCALE), HEAD_AT), col, rng, true, true, eye_mb)
	# ---- the Dream Stele between the paws, and an altar before it
	var stele := DesertProps._c(DesertProps.GRANITE.lightened(0.18), DesertProps.GLYPH)
	mb.add(MeshBuilder.box(Vector3(3.6, 4.4, 0.7)), Transform3D(Basis(), Vector3(0, 2.2, 8.2)), stele)
	mb.add(MeshBuilder.cyl(1.8, 1.8, 0.7, 16), Transform3D(Basis(Vector3(1, 0, 0), PI / 2), Vector3(0, 4.4, 8.2)), stele)
	mb.add(MeshBuilder.sphere(0.45, 10, 6), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.3)), Vector3(0, 5.0, 8.6)), DesertProps._c(Color(0.75, 0.52, 0.22)))   # sun disc
	for sd in [-1.0, 1.0]:   # its wings
		mb.add(MeshBuilder.box(Vector3(1.3, 0.22, 0.1)), Transform3D(Basis(Vector3(0, 0, 1), sd * 0.2), Vector3(sd * 1.0, 5.05, 8.58)), DesertProps._c(Color(0.32, 0.42, 0.62)))
		mb.add(MeshBuilder.box(Vector3(1.0, 0.16, 0.1)), Transform3D(Basis(Vector3(0, 0, 1), sd * 0.24), Vector3(sd * 0.9, 4.82, 8.58)), DesertProps._c(Color(0.62, 0.42, 0.2)))
	mb.add(MeshBuilder.box(Vector3(2.2, 0.9, 1.2)), Transform3D(Basis(), Vector3(0, 0.45, 11.0)), DesertProps._c(DesertProps.LIMESTONE, DesertProps.GLYPH))
	var mesh := mb.commit(DesertProps.stone_material())
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.12, 0.09, 0.06)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.75, 0.25)
	eye_mat.emission_energy_multiplier = 0.0
	eye_mat.roughness = 0.4
	eye_mb.commit_into(mesh, eye_mat)
	var colliders: Array = [
		DesertProps._box_col(Vector3(9.4, 8.0, 19.0), Vector3(0, 4.0, -7.0)),
		DesertProps._box_col(Vector3(8.4, 9.0, 6.0), Vector3(0, 4.5, 3.0)),
		DesertProps._box_col(Vector3(6.8, 7.0, 6.0), Vector3(0, 11.0, 6.4)),
		DesertProps._box_col(Vector3(13.0, 3.6, 7.0), Vector3(0, 1.8, -12.0)),
		DesertProps._box_col(Vector3(3.8, 4.4, 1.0), Vector3(0, 2.2, 8.2)),
		DesertProps._box_col(Vector3(2.2, 0.9, 1.2), Vector3(0, 0.45, 11.0)),
	]
	for sd in [-1.0, 1.0]:
		colliders.append(DesertProps._box_col(Vector3(3.0, 2.8, 15.5), Vector3(sd * 3.25, 1.4, 12.0)))
		colliders.append(DesertProps._box_col(Vector3(2.2, 2.2, 9.0), Vector3(sd * 4.6, 1.1, -7.5)))
	var eyes: Array[Vector3] = []
	for sd in [-1.0, 1.0]:
		eyes.append(HEAD_AT + Vector3(sd * 0.34, 0.12, 0.93) * HEAD_SCALE)
	return {"mesh": mesh, "colliders": colliders, "eyes": eyes, "eye_material": eye_mat}


## A great lion's paw at `xf` (toes toward +Z): a pad, four toes, claws peeping out.
static func _paw(mb: MeshBuilder, xf: Transform3D, col: Color, s: float, rng: RandomNumberGenerator) -> void:
	mb.add(MeshBuilder.sphere(1.0, 12, 8), xf * Transform3D(Basis.from_scale(Vector3(1.35, 0.9, 1.9) * s), Vector3(0, 0.75 * s, 0)), col)
	for k in 4:
		var x := (-1.5 + k) * 0.62 * s
		var at := Vector3(x, 0.45 * s, 1.75 * s - absf(x) * 0.25)
		mb.add(MeshBuilder.sphere(0.46 * s, 10, 6), xf * Transform3D(Basis.from_scale(Vector3(0.85, 0.85, 1.15)), at), DesertProps._shade(col, rng, 0.04))
		mb.add(MeshBuilder.cone(0.12 * s, 0.35 * s, 6), xf * Transform3D(Basis(Vector3(1, 0, 0), PI / 2 + 0.3), at + Vector3(0, -0.15 * s, 0.5 * s)), col.darkened(0.2))
	mb.add(MeshBuilder.sphere(0.35 * s, 8, 5), xf * Transform3D(Basis(), Vector3(1.25 * s, 0.6 * s, 0.4 * s)), col)   # dewclaw


## A pharaoh's head in the nemes headdress (also used for the colossi and the heads in the sand).
## Head space: the cranium's centre at the origin, the face toward +Z, about 2.6 units tall.
## `eye_mb`: put the eyes on their own surface (the Sphinx's glow).
## `stripe_a` / `stripe_b`: the headcloth's colours (gold and lapis on the Pharaoh's mask).
static func head(mb: MeshBuilder, xf: Transform3D, col: Color, rng: RandomNumberGenerator, broken_nose := true, beard := true, eye_mb: MeshBuilder = null, stripe_a := STRIPE_A, stripe_b := STRIPE_B) -> void:
	var dark := col.darkened(0.3)
	var pupil := col.darkened(0.55)
	var face := Color(col.r * 1.04, col.g * 0.95, col.b * 0.9, col.a)   # a ghost of red ochre on the skin
	var put := func(arr: Array, t: Transform3D, c: Color) -> void: mb.add(arr, xf * t, c)
	# cranium, face, cheeks, jaw and chin
	put.call(MeshBuilder.sphere(1.0, 16, 10), Transform3D(Basis.from_scale(Vector3(0.9, 1.0, 0.95)), Vector3(0, 0.05, -0.05)), Color(stripe_a, col.a))
	put.call(MeshBuilder.sphere(1.0, 14, 10), Transform3D(Basis.from_scale(Vector3(0.78, 0.92, 0.62)), Vector3(0, -0.2, 0.38)), face)
	for sd in [-1.0, 1.0]:
		put.call(MeshBuilder.sphere(0.3, 10, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.95, 0.6)), Vector3(sd * 0.4, -0.3, 0.66)), face)
	put.call(MeshBuilder.sphere(0.46, 12, 7), Transform3D(Basis.from_scale(Vector3(1.05, 0.72, 0.9)), Vector3(0, -0.86, 0.5)), face)
	put.call(MeshBuilder.sphere(0.2, 8, 5), Transform3D(Basis.from_scale(Vector3(1.3, 0.8, 1.0)), Vector3(0, -1.0, 0.82)), face)   # chin
	# brow and eyes: almond eyes outlined in kohl, the cosmetic line sweeping out to the temples,
	# long eyebrows above
	put.call(MeshBuilder.box(Vector3(1.25, 0.12, 0.22)), Transform3D(Basis(Vector3(1, 0, 0), -0.25), Vector3(0, 0.3, 0.86)), face)
	for sd in [-1.0, 1.0]:
		put.call(MeshBuilder.sphere(0.19, 10, 6), Transform3D(Basis.from_scale(Vector3(1.35, 0.62, 0.55)), Vector3(sd * 0.34, 0.11, 0.86)), Color(col.darkened(0.16), col.a))   # socket
		var eye_c := Color(col.lightened(0.18), col.a)
		var eye_t := xf * Transform3D(Basis.from_scale(Vector3(1.15, 0.5, 0.45)), Vector3(sd * 0.34, 0.12, 0.9))
		if eye_mb != null:
			eye_mb.add(MeshBuilder.sphere(0.16, 10, 6), eye_t, Color.WHITE)
		else:
			mb.add(MeshBuilder.sphere(0.16, 10, 6), eye_t, eye_c)
		put.call(MeshBuilder.sphere(0.05, 6, 4), Transform3D(Basis(), Vector3(sd * 0.34, 0.12, 0.965)), pupil)   # pupil
		put.call(MeshBuilder.box(Vector3(0.4, 0.03, 0.05)), Transform3D(Basis(Vector3(0, 0, 1), sd * 0.08), Vector3(sd * 0.34, 0.18, 0.95)), dark)   # upper lid line
		put.call(MeshBuilder.box(Vector3(0.26, 0.025, 0.04)), Transform3D(Basis(Vector3(0, 0, 1), sd * -0.1), Vector3(sd * 0.6, 0.13, 0.85)), dark)   # kohl line
		put.call(MeshBuilder.box(Vector3(0.44, 0.035, 0.05)), Transform3D(Basis(Vector3(0, 0, 1), sd * -0.12), Vector3(sd * 0.36, 0.33, 0.92)), Color(col.darkened(0.15), col.a))   # eyebrow
	# the nose: broken off (a raw, paler scar) or whole
	if broken_nose:
		put.call(MeshBuilder.box(Vector3(0.24, 0.32, 0.12)), Transform3D(Basis(Vector3(1, 0, 0), -0.2), Vector3(0, -0.08, 0.97)), Color(col.lightened(0.12), col.a))
		put.call(ForestProps._lumpy(0.1, rng), Transform3D(Basis.from_scale(Vector3(1.2, 1.0, 0.6)), Vector3(0, -0.12, 1.02)), col.lightened(0.08))
	else:
		put.call(MeshBuilder.cone(0.13, 0.42, 4), Transform3D(Basis(Vector3(1, 0, 0), -0.25) * Basis(Vector3.UP, PI / 4), Vector3(0, -0.02, 1.0)), face)
		put.call(MeshBuilder.sphere(0.12, 8, 5), Transform3D(Basis.from_scale(Vector3(1.4, 0.8, 1.0)), Vector3(0, -0.2, 1.04)), face)
	# full lips with a dark mouth line, smile creases
	put.call(MeshBuilder.sphere(0.15, 10, 5), Transform3D(Basis.from_scale(Vector3(2.0, 0.55, 0.8)), Vector3(0, -0.43, 0.94)), face)
	put.call(MeshBuilder.sphere(0.15, 10, 5), Transform3D(Basis.from_scale(Vector3(1.8, 0.6, 0.8)), Vector3(0, -0.57, 0.9)), face)
	put.call(MeshBuilder.box(Vector3(0.5, 0.025, 0.05)), Transform3D(Basis(), Vector3(0, -0.5, 1.0)), dark)
	for sd in [-1.0, 1.0]:
		put.call(MeshBuilder.box(Vector3(0.025, 0.14, 0.04)), Transform3D(Basis(Vector3(0, 0, 1), sd * 0.4), Vector3(sd * 0.3, -0.45, 0.93)), dark)
	# big ears, standing out in front of the headcloth
	for sd in [-1.0, 1.0]:
		put.call(MeshBuilder.sphere(1.0, 10, 6), Transform3D(Basis(Vector3.UP, sd * 0.3).scaled(Vector3(0.12, 0.34, 0.24)), Vector3(sd * 0.9, -0.05, 0.25)), face)
		put.call(MeshBuilder.sphere(1.0, 8, 5), Transform3D(Basis(Vector3.UP, sd * 0.3).scaled(Vector3(0.05, 0.22, 0.14)), Vector3(sd * 0.95, -0.05, 0.29)), dark)
	# the nemes: a striped headcloth over the cranium (horizontal bands), the brow band, wings
	# flaring out behind the ears, two striped lappets falling onto the chest, the queue behind
	var bands := 13
	for k in bands:
		var y := lerpf(1.0, -0.3, float(k) / bands)
		var rr := sqrt(maxf(0.0, 1.0 - pow((y - 0.05) / 1.1, 2.0))) * 1.0 + 0.07
		var c := stripe_a if k % 2 == 0 else stripe_b
		var gap := 0.0 if y > 0.46 else deg_to_rad(82.0)   # the face shows below the brow band
		var segs := 18
		for q in segs:
			var th0 := gap + (TAU - 2.0 * gap) * float(q) / segs
			var th1 := gap + (TAU - 2.0 * gap) * float(q + 1) / segs
			var th := (th0 + th1) * 0.5
			var seg_len := 2.0 * rr * sin((th1 - th0) * 0.5) + 0.02
			put.call(MeshBuilder.box(Vector3(seg_len, 1.3 / bands + 0.012, 0.08)), Transform3D(Basis(Vector3.UP, th), Vector3(sin(th) * rr, y, cos(th) * rr - 0.1)), Color(DesertProps._shade(c, rng, 0.05), col.a))
	put.call(MeshBuilder.sphere(1.0, 14, 8), Transform3D(Basis.from_scale(Vector3(0.88, 0.3, 0.92)), Vector3(0, 1.0, -0.1)), Color(stripe_a, col.a))   # crown
	# the brow band across the forehead, a fold of cloth above it
	for q in 9:
		var th := deg_to_rad(-80.0 + q * 20.0)
		put.call(MeshBuilder.box(Vector3(0.22, 0.12, 0.09)), Transform3D(Basis(Vector3.UP, th), Vector3(sin(th) * 0.98, 0.47, cos(th) * 0.98 - 0.08)), Color(col.darkened(0.1), col.a))
	for sd in [-1.0, 1.0]:
		# the wing: a flared fold of cloth behind each ear, striped
		for k in 7:
			var y := 0.35 - k * 0.2
			var c := stripe_a if k % 2 == 0 else stripe_b
			put.call(MeshBuilder.box(Vector3(0.34 + k * 0.03, 0.2, 0.95)), Transform3D(Basis(Vector3(0, 0, 1), sd * (0.25 + k * 0.03)), Vector3(sd * (1.08 + k * 0.04), y, -0.12)), Color(DesertProps._shade(c, rng, 0.06), col.a))
		# the lappet: a long striped panel down in front of the shoulder
		for k in 14:
			var t := float(k) / 13.0
			var c := stripe_a if k % 2 == 0 else stripe_b
			put.call(MeshBuilder.box(Vector3(0.62 + t * 0.12, 0.2, 0.22)), Transform3D(Basis(Vector3(1, 0, 0), -0.12), Vector3(sd * (1.02 + t * 0.12), -1.0 - t * 2.1, 0.28 + t * 0.32)), Color(DesertProps._shade(c, rng, 0.06), col.a))
	for k in 8:   # the queue: a plaited tail of cloth down the back
		put.call(MeshBuilder.cyl(0.32 - k * 0.012, 0.34 - k * 0.012, 0.32, 10), Transform3D(Basis(), Vector3(0, -0.6 - k * 0.3, -1.0 - k * 0.04)), Color((stripe_a if k % 2 == 0 else stripe_b), col.a))
	# the uraeus: the rearing cobra on the brow (broken, only its body left on the old ones)
	put.call(MeshBuilder.cyl(0.07, 0.09, 0.4, 8), Transform3D(Basis(Vector3(1, 0, 0), 0.2), Vector3(0, 0.72, 0.95)), Color(col.darkened(0.05), col.a))
	if not broken_nose:
		put.call(MeshBuilder.sphere(0.14, 8, 5), Transform3D(Basis.from_scale(Vector3(1.0, 1.2, 0.4)), Vector3(0, 0.98, 0.98)), Color(col.darkened(0.05), col.a))
	# the false beard: a long plaited braid curling forward at the tip
	if beard:
		for k in 9:
			var t := float(k) / 8.0
			var at := Vector3(0, -1.15 - t * 1.0, 0.72 + t * 0.12 + t * t * 0.18)
			put.call(MeshBuilder.cyl(0.2 + t * 0.04, 0.2 + t * 0.04, 0.13, 10), Transform3D(Basis(Vector3(1, 0, 0), -0.2 - t * 0.3), at), Color(col.darkened(0.12 if k % 2 else 0.0), col.a))


## The plinth the sphinx lies on: two broad steps of blocks up to a floor of worn flagstones,
## braziers at its corners and a pair of small obelisks flanking the front steps.
static func plinth_mesh(at: Vector3, half: Vector2, run: float, rise: float, steps: int, base: float, night: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "SphinxPlinth"   # no-i18n
	root.position = Vector3(at.x, base, at.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var q := DesertProps._Quads.new()
	for k in steps:
		var y0 := k * rise
		var y1 := y0 + rise
		for side in 4:
			var o := (half.x if side < 2 else half.y) - k * run
			var along_half := (half.y if side < 2 else half.x) - k * run - (0.0 if side < 2 else run)
			var a := -along_half
			while a < along_half - 0.01:
				var b := minf(a + rng.randf_range(1.4, 2.2), along_half)
				if along_half - b < 0.6:
					b = along_half
				var c := DesertProps._shade(DesertProps.LIMESTONE.darkened(0.1), rng, 0.08)
				q.block(side, o + rng.randf_range(-0.04, 0.02), o - run, a, b, y0, y1 - rng.randf_range(0.0, 0.05), c)
				a = b
	# the floor: flagstones in rows
	var top := steps * rise
	var fx := half.x - steps * run
	var fz := half.y - steps * run
	var z := -fz
	while z < fz - 0.01:
		var z1 := minf(z + 2.0, fz)
		var x := -fx + (0.0 if int(z) % 4 == 0 else 1.0)
		x = -fx
		while x < fx - 0.01:
			var x1 := minf(x + rng.randf_range(1.6, 2.6), fx)
			var c := DesertProps._shade(DesertProps.LIMESTONE.darkened(0.06), rng, 0.07)
			q.quad(Vector3(x, top, z1), Vector3(x1, top, z1), Vector3(x1, top, z), Vector3(x, top, z), Vector3.UP, c, Vector2(x1 - x, z1 - z))
			x = x1
		z = z1
	var mi := MeshInstance3D.new()
	mi.mesh = q.commit(DesertProps.stone_material())
	root.add_child(mi)
	# obelisks either side of the front steps, braziers at the corners
	var body := StaticBody3D.new()
	root.add_child(body)
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	for sd in [-1.0, 1.0]:
		var p := Vector3(sd * 6.0, top, half.y - steps * run - 1.6)
		mb.add(MeshBuilder.box(Vector3(1.6, 0.6, 1.6)), Transform3D(Basis(), p + Vector3(0, 0.3, 0)), DesertProps._c(DesertProps.LIMESTONE))
		mb.add(MeshBuilder.cyl(0.42, 0.62, 6.0, 4), Transform3D(Basis(Vector3.UP, PI / 4), p + Vector3(0, 3.6, 0)), DesertProps._c(DesertProps.GRANITE.lightened(0.2), DesertProps.GLYPH))
		gb.add(MeshBuilder.cone(0.42, 0.6, 4), Transform3D(Basis(Vector3.UP, PI / 4), p + Vector3(0, 6.9, 0)), Color(1, 0.9, 0.6))
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.6, 6.6, 1.6)
		var cs := CollisionShape3D.new()
		cs.shape = bs
		cs.position = p + Vector3(0, 3.3, 0)
		body.add_child(cs)
	var omi := MeshInstance3D.new()
	var om := mb.commit(DesertProps.stone_material())
	gb.commit_into(om, DesertProps.gold_material())
	omi.mesh = om
	root.add_child(omi)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * (fx - 1.2), top, sz * (fz - 1.2))
			var b := DesertProps.brazier()
			var bmi := MeshInstance3D.new()
			bmi.mesh = b["mesh"]
			bmi.position = p
			root.add_child(bmi)
			var fl := Abilities._flame_particles(0.5, 0.7, 24)
			fl.position = p + Vector3(0, 1.35, 0)
			root.add_child(fl)
			if night:
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.6, 0.25)
				l.light_energy = 2.4
				l.omni_range = 14.0
				l.position = p + Vector3(0, 1.8, 0)
				root.add_child(l)
	return root


## The tomb door in the plinth floor: a carved frame and two stone slabs over a black shaft.
## The Pharaoh slides them apart when he rises (PharaohBoss).
static func tomb_door(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "SphinxTomb"   # no-i18n
	root.add_to_group("sphinx_tomb")
	root.position = at
	var mb := MeshBuilder.new()
	var frame := DesertProps._c(DesertProps.GRANITE.lightened(0.1), DesertProps.GLYPH)
	mb.add(MeshBuilder.box(Vector3(6.0, 0.14, 0.6)), Transform3D(Basis(), Vector3(0, 0.05, -1.6)), frame)
	mb.add(MeshBuilder.box(Vector3(6.0, 0.14, 0.6)), Transform3D(Basis(), Vector3(0, 0.05, 1.6)), frame)
	mb.add(MeshBuilder.box(Vector3(0.7, 0.14, 3.8)), Transform3D(Basis(), Vector3(-2.65, 0.05, 0)), frame)
	mb.add(MeshBuilder.box(Vector3(0.7, 0.14, 3.8)), Transform3D(Basis(), Vector3(2.65, 0.05, 0)), frame)
	var fm := MeshInstance3D.new()
	fm.mesh = mb.commit(DesertProps.stone_material())
	root.add_child(fm)
	var shaft := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(4.6, 0.05, 2.6)
	sb.material = DesertProps.void_material()
	shaft.mesh = sb
	shaft.position = Vector3(0, 0.01, 0)
	root.add_child(shaft)
	for sd in [-1.0, 1.0]:
		var slab := MeshInstance3D.new()
		var smb := MeshBuilder.new()
		smb.add(MeshBuilder.box(Vector3(2.3, 0.2, 2.6)), Transform3D(), DesertProps._c(DesertProps.GRANITE.lightened(0.05), DesertProps.GLYPH))
		smb.add(MeshBuilder.sphere(0.4, 10, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.2, 1.0)), Vector3(-sd * 0.6, 0.1, 0)), DesertProps._c(Color(0.62, 0.46, 0.2)))   # half a sun disc each
		slab.mesh = smb.commit(DesertProps.stone_material())
		slab.position = Vector3(sd * 1.16, 0.1, 0)
		slab.name = "SlabL" if sd < 0 else "SlabR"   # no-i18n
		root.add_child(slab)
	var glow := OmniLight3D.new()
	glow.name = "Glow"   # no-i18n
	glow.light_color = Color(1.0, 0.75, 0.3)
	glow.light_energy = 0.0
	glow.omni_range = 16.0
	glow.position = Vector3(0, 1.2, 0)
	root.add_child(glow)
	return root
