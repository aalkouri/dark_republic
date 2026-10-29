class_name CastleProps
extends RefCounted
## Procedural castle furniture. Builders return { "mesh", "colliders", "footprint" (half extents
## for the goblin nav grid), "burnable", and optionally "light", "light_at", "fire_at",
## "fire_size" }. Origin on the floor. Self-lit parts (flames, candles, stained glass) are a
## second surface with MeshBuilder.glow_material.
##   standing (180): columns, knight statues, suits of armour, candelabras, weapon racks
##   lying (72):     benches, toppled columns, crate stacks, barrel clusters, bookcases
##   landmarks (24): the throne, braziers

const STONE := Color(0.4, 0.37, 0.34, 0.0)
const PALE := Color(0.55, 0.52, 0.48, 0.0)
const DARK := Color(0.2, 0.19, 0.18, 0.0)
const WOOD := Color(0.34, 0.21, 0.11, 0.0)
const DARK_WOOD := Color(0.2, 0.12, 0.07, 0.0)
const IRON := Color(0.18, 0.18, 0.2, 0.0)
const STEEL := Color(0.6, 0.61, 0.66, 0.0)
const GOLD := Color(0.8, 0.6, 0.22, 0.0)
const RED := Color(0.45, 0.07, 0.08, 0.0)
const CLOTH := Color(0.45, 0.07, 0.08, 0.8)
const CANDLE := Color(0.92, 0.87, 0.72, 0.0)
const FLAME := Color(1.0, 0.62, 0.22, 0.0)
const BOOKS := [Color(0.4, 0.1, 0.1, 0.0), Color(0.12, 0.2, 0.35, 0.0), Color(0.15, 0.3, 0.15, 0.0), Color(0.45, 0.35, 0.15, 0.0)]


static func _cyl_col(r: float, h: float, y := 0.0) -> Array:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return [s, Transform3D(Basis(), Vector3(0, y + h * 0.5, 0))]


static func _box_col(size: Vector3, at: Vector3) -> Array:
	var s := BoxShape3D.new()
	s.size = size
	return [s, Transform3D(Basis(), at)]


static func _done(mb: MeshBuilder, gb: MeshBuilder, colliders: Array, footprint: Vector2, extra := {}) -> Dictionary:
	var mesh := mb.commit()
	gb.commit_into(mesh, MeshBuilder.glow_material())
	var d := {"mesh": mesh, "colliders": colliders, "footprint": footprint, "burnable": false}
	d.merge(extra, true)
	return d


# ------------------------------------------------------------------ standing

static func standing(rng: RandomNumberGenerator, room: String, i: int) -> Dictionary:
	var pick := i % 4
	if room == "armory" or room == "barracks":
		pick = [2, 3, 2, 1][i % 4]   # armour and weapon racks
	elif room == "chapel" or room == "library":
		pick = [0, 1, 0, 1][i % 4]   # candelabras and statues
	match pick:
		0: return candelabra(rng)
		1: return knight_statue(rng)
		2: return suit_of_armour(rng)
		_: return weapon_rack(rng)


static func column(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var h := CastleBuilder.CEILING
	mb.add(MeshBuilder.box(Vector3(3.0, 1.0, 3.0)), Transform3D(Basis(), Vector3(0, 0.5, 0)), DARK)
	mb.add(MeshBuilder.cyl(1.1, 1.25, 1.0, 16), Transform3D(Basis(), Vector3(0, 1.5, 0)), STONE)
	mb.add(MeshBuilder.cyl(0.95, 1.05, h - 4.0, 16), Transform3D(Basis(), Vector3(0, 2.0 + (h - 4.0) * 0.5, 0)), PALE)
	for k in 8:   # flutes
		var a := TAU * k / 8.0
		mb.add(MeshBuilder.box(Vector3(0.12, h - 4.4, 0.12)), Transform3D(Basis(), Vector3(cos(a) * 1.0, 2.2 + (h - 4.4) * 0.5, sin(a) * 1.0)), STONE)
	mb.add(MeshBuilder.cyl(1.5, 1.0, 1.4, 16), Transform3D(Basis(), Vector3(0, h - 1.7, 0)), STONE)
	mb.add(MeshBuilder.box(Vector3(3.4, 1.0, 3.4)), Transform3D(Basis(), Vector3(0, h - 0.5, 0)), DARK)
	return _done(mb, gb, [_cyl_col(1.15, h)], Vector2(1.4, 1.4))


static func knight_statue(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var c := PALE.lerp(STONE, rng.randf())
	mb.add(MeshBuilder.box(Vector3(2.0, 1.2, 2.0)), Transform3D(Basis(), Vector3(0, 0.6, 0)), DARK)
	# A stone knight resting both hands on a greatsword
	mb.limb(Vector3(-0.3, 1.2, 0), Vector3(-0.32, 2.6, 0), 0.24, 0.22, c)
	mb.limb(Vector3(0.3, 1.2, 0), Vector3(0.32, 2.6, 0), 0.24, 0.22, c)
	mb.add(MeshBuilder.cyl(0.55, 0.45, 1.5, 10), Transform3D(Basis(), Vector3(0, 3.3, 0)), c)
	mb.add(MeshBuilder.sphere(0.5, 10, 6), Transform3D(Basis.from_scale(Vector3(1.6, 0.6, 0.9)), Vector3(0, 4.05, 0)), c)
	mb.add(MeshBuilder.sphere(0.33, 10, 6), Transform3D(Basis(), Vector3(0, 4.55, 0)), c)
	mb.add(MeshBuilder.cone(0.3, 0.45, 8), Transform3D(Basis(), Vector3(0, 4.95, 0)), c)
	mb.limb(Vector3(-0.75, 3.9, 0), Vector3(-0.2, 3.2, -0.35), 0.17, 0.14, c)
	mb.limb(Vector3(0.75, 3.9, 0), Vector3(0.2, 3.2, -0.35), 0.17, 0.14, c)
	mb.add(MeshBuilder.box(Vector3(0.14, 2.2, 0.05)), Transform3D(Basis(), Vector3(0, 2.2, -0.45)), c)
	mb.add(MeshBuilder.box(Vector3(0.7, 0.12, 0.12)), Transform3D(Basis(), Vector3(0, 3.25, -0.45)), c)
	mb.add(MeshBuilder.cyl(0.65, 0.75, 2.4, 10), Transform3D(Basis(), Vector3(0, 2.3, 0.2)), c.darkened(0.1))   # cloak
	return _done(mb, gb, [_box_col(Vector3(2.0, 5.2, 2.0), Vector3(0, 2.6, 0))], Vector2(1.0, 1.0))


static func suit_of_armour(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var metal := STEEL.lerp(IRON, rng.randf() * 0.5)
	mb.add(MeshBuilder.box(Vector3(1.0, 0.15, 1.0)), Transform3D(Basis(), Vector3(0, 0.075, 0)), DARK_WOOD)
	mb.limb(Vector3(0, 0.15, 0.3), Vector3(0, 1.0, 0.3), 0.04, 0.04, IRON)   # stand pole
	for side in [-1.0, 1.0]:
		mb.limb(Vector3(side * 0.16, 0.15, 0), Vector3(side * 0.17, 0.95, 0), 0.11, 0.1, metal)
		mb.add(MeshBuilder.box(Vector3(0.16, 0.12, 0.3)), Transform3D(Basis(), Vector3(side * 0.16, 0.2, -0.05)), metal)
		mb.add(MeshBuilder.sphere(0.17, 8, 5), Transform3D(Basis(), Vector3(side * 0.34, 1.62, 0)), metal)   # pauldrons
		mb.limb(Vector3(side * 0.36, 1.55, 0), Vector3(side * 0.42, 1.05, -0.05), 0.08, 0.07, metal)
	mb.add(MeshBuilder.cyl(0.26, 0.2, 0.6, 10), Transform3D(Basis(), Vector3(0, 1.35, 0)), metal)
	mb.add(MeshBuilder.cyl(0.2, 0.24, 0.3, 10), Transform3D(Basis(), Vector3(0, 0.98, 0)), metal)
	mb.add(MeshBuilder.cyl(0.15, 0.16, 0.32, 10), Transform3D(Basis(), Vector3(0, 1.85, 0)), metal)
	mb.add(MeshBuilder.box(Vector3(0.2, 0.03, 0.02)), Transform3D(Basis(), Vector3(0, 1.88, -0.16)), Color(0.02, 0.02, 0.02, 0))
	mb.add(MeshBuilder.cone(0.04, 0.3, 4), Transform3D(Basis(), Vector3(0, 2.15, 0)), RED)   # plume
	# Halberd
	mb.limb(Vector3(0.5, 0.15, -0.1), Vector3(0.5, 2.6, -0.1), 0.03, 0.03, DARK_WOOD)
	mb.add(MeshBuilder.box(Vector3(0.04, 0.35, 0.3)), Transform3D(Basis(), Vector3(0.5, 2.4, -0.2)), STEEL)
	return _done(mb, gb, [_box_col(Vector3(1.0, 2.2, 1.0), Vector3(0, 1.1, 0))], Vector2(0.6, 0.6))


static func candelabra(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var h := rng.randf_range(2.0, 2.6)
	mb.add(MeshBuilder.cyl(0.3, 0.45, 0.12, 10), Transform3D(Basis(), Vector3(0, 0.06, 0)), IRON)
	mb.limb(Vector3(0, 0.1, 0), Vector3(0, h, 0), 0.05, 0.04, IRON)
	for k in 5:
		var a := TAU * k / 5.0
		var tip := Vector3(cos(a) * 0.4, h, sin(a) * 0.4) if k < 4 else Vector3(0, h + 0.1, 0)
		if k < 4:
			mb.limb(Vector3(0, h - 0.25, 0), tip, 0.025, 0.025, IRON)
		mb.add(MeshBuilder.cyl(0.05, 0.05, 0.28, 6), Transform3D(Basis(), tip + Vector3(0, 0.14, 0)), CANDLE)
		gb.add(MeshBuilder.sphere(0.06, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 1.8, 1)), tip + Vector3(0, 0.36, 0)), FLAME)
	return _done(mb, gb, [_cyl_col(0.35, h)], Vector2(0.5, 0.5))


static func weapon_rack(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	for side in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(0.12, 1.8, 0.5)), Transform3D(Basis(), Vector3(side * 1.1, 0.9, 0)), WOOD)
	mb.add(MeshBuilder.box(Vector3(2.3, 0.1, 0.12)), Transform3D(Basis(), Vector3(0, 1.5, 0)), WOOD)
	mb.add(MeshBuilder.box(Vector3(2.3, 0.1, 0.5)), Transform3D(Basis(), Vector3(0, 0.3, 0)), WOOD)
	for k in 5:
		var x := -0.8 + k * 0.4
		if rng.randf() < 0.5:   # spear
			mb.limb(Vector3(x, 0.35, 0), Vector3(x + 0.05, 2.4, 0.05), 0.025, 0.02, DARK_WOOD)
			mb.add(MeshBuilder.cone(0.06, 0.3, 4), Transform3D(Basis(), Vector3(x + 0.05, 2.55, 0.05)), STEEL)
		else:   # sword
			mb.add(MeshBuilder.box(Vector3(0.07, 1.1, 0.02)), Transform3D(Basis(), Vector3(x, 1.0, 0.05)), STEEL)
			mb.add(MeshBuilder.box(Vector3(0.3, 0.05, 0.05)), Transform3D(Basis(), Vector3(x, 1.58, 0.05)), GOLD)
	return _done(mb, gb, [_box_col(Vector3(2.4, 1.8, 0.6), Vector3(0, 0.9, 0))], Vector2(1.25, 0.4), {"burnable": true, "length": 2.4})


# ------------------------------------------------------------------ lying

static func lying(rng: RandomNumberGenerator, room: String, i: int) -> Dictionary:
	var pick := i % 5
	if room == "library":
		pick = 4 if i % 2 == 0 else 0
	match pick:
		0: return bench(rng)
		1: return toppled_column(rng)
		2: return crates(rng)
		3: return barrels(rng)
		_: return bookcase(rng)


static func bench(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var l := rng.randf_range(3.0, 5.0)
	mb.add(MeshBuilder.box(Vector3(l, 0.12, 0.6)), Transform3D(Basis(), Vector3(0, 0.5, 0)), WOOD)
	for x in [-l * 0.4, l * 0.4]:
		mb.add(MeshBuilder.box(Vector3(0.12, 0.45, 0.5)), Transform3D(Basis(), Vector3(x, 0.22, 0)), DARK_WOOD)
	return _done(mb, gb, [_box_col(Vector3(l, 0.56, 0.6), Vector3(0, 0.28, 0))], Vector2(l * 0.5, 0.35), {"burnable": true, "length": l})


static func toppled_column(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var l := rng.randf_range(6.0, 10.0)
	mb.limb(Vector3(-l * 0.5, 1.0, 0), Vector3(l * 0.5, 1.0, 0), 1.0, 0.95, PALE, 14)
	for k in 3:   # broken chunks
		var x := rng.randf_range(-l * 0.5, l * 0.5)
		var s := rng.randf_range(0.4, 0.9)
		mb.add(MeshBuilder.box(Vector3(s, s * 0.7, s)), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, s * 0.35, rng.randf_range(1.3, 2.0) * (1.0 if k % 2 else -1.0))), STONE)
	var cs := CylinderShape3D.new()
	cs.radius = 1.0
	cs.height = l
	return _done(mb, gb, [[cs, Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(0, 1.0, 0))]], Vector2(l * 0.5, 1.1))


static func crates(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var cols := []
	var spots := [Vector3(0, 0, 0), Vector3(1.25, 0, 0.1), Vector3(0.6, 1.2, 0.05)]
	for k in rng.randi_range(2, 3):
		var p: Vector3 = spots[k]
		var s := rng.randf_range(1.0, 1.2)
		mb.add(MeshBuilder.box(Vector3(s, s, s)), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), p + Vector3(0, s * 0.5, 0)), WOOD)
		for e in 4:   # dark slats on the faces
			var a := TAU * e / 4.0
			mb.add(MeshBuilder.box(Vector3(s * 1.01, 0.08, 0.08)), Transform3D(Basis(Vector3.UP, a), p + Vector3(0, s * (0.2 + 0.6 * (e % 2)), 0) + Vector3(sin(a), 0, cos(a)) * s * 0.5), DARK_WOOD)
		cols.append(_box_col(Vector3(s, s, s), p + Vector3(0, s * 0.5, 0)))
	return _done(mb, gb, cols, Vector2(1.4, 0.7), {"burnable": true, "length": 2.4})


static func barrels(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var cols := []
	for k in rng.randi_range(2, 4):
		var a := TAU * k / 4.0 + rng.randf() * 0.4
		var p := Vector3(cos(a) * 0.75, 0, sin(a) * 0.75)
		mb.add(MeshBuilder.cyl(0.42, 0.42, 1.1, 12), Transform3D(Basis(), p + Vector3(0, 0.55, 0)), WOOD)
		mb.add(MeshBuilder.sphere(0.48, 12, 4), Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), p + Vector3(0, 0.55, 0)), WOOD)
		for y in [0.2, 0.9]:
			mb.add(MeshBuilder.cyl(0.47, 0.47, 0.06, 12), Transform3D(Basis(), p + Vector3(0, y, 0)), IRON)
		var bs := CylinderShape3D.new()
		bs.radius = 0.48
		bs.height = 1.1
		cols.append([bs, Transform3D(Basis(), p + Vector3(0, 0.55, 0))])
	return _done(mb, gb, cols, Vector2(1.3, 1.3), {"burnable": true, "length": 2.0})


static func bookcase(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var w := rng.randf_range(3.0, 4.5)
	var h := 4.0
	mb.add(MeshBuilder.box(Vector3(w, h, 0.15)), Transform3D(Basis(), Vector3(0, h * 0.5, 0.35)), WOOD)
	var px := -w * 0.5 + 0.5   # the back's planks, so it doesn't read as a black slab
	while px < w * 0.5 - 0.2:
		mb.add(MeshBuilder.box(Vector3(0.05, h - 0.1, 0.04)), Transform3D(Basis(), Vector3(px, h * 0.5, 0.44)), DARK_WOOD)
		px += 0.5
	mb.add(MeshBuilder.box(Vector3(w + 0.2, 0.18, 0.95)), Transform3D(Basis(), Vector3(0, h + 0.09, 0)), DARK_WOOD)   # crown
	for side in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(0.12, h, 0.8)), Transform3D(Basis(), Vector3(side * w * 0.5, h * 0.5, 0)), DARK_WOOD)
	for shelf in 5:
		var y := 0.1 + shelf * 0.95
		mb.add(MeshBuilder.box(Vector3(w, 0.08, 0.8)), Transform3D(Basis(), Vector3(0, y, 0)), DARK_WOOD)
		if shelf < 4:
			var x := -w * 0.5 + 0.15
			while x < w * 0.5 - 0.2:
				var bw := rng.randf_range(0.08, 0.16)
				var bh := rng.randf_range(0.5, 0.8)
				mb.add(MeshBuilder.box(Vector3(bw, bh, 0.55)), Transform3D(Basis(Vector3(0, 0, 1), rng.randf_range(-0.08, 0.08)), Vector3(x + bw * 0.5, y + 0.04 + bh * 0.5, 0)), BOOKS[rng.randi() % BOOKS.size()])
				x += bw + 0.01
	return _done(mb, gb, [_box_col(Vector3(w, h, 0.8), Vector3(0, h * 0.5, 0))], Vector2(w * 0.5, 0.5), {"burnable": true, "length": w})


# ------------------------------------------------------------------ landmarks

static func brazier(rng: RandomNumberGenerator, scale := 1.0) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var s := scale
	for k in 3:
		var a := TAU * k / 3.0
		mb.limb(Vector3(cos(a) * 0.9 * s, 0, sin(a) * 0.9 * s), Vector3(cos(a) * 0.4 * s, 1.4 * s, sin(a) * 0.4 * s), 0.08 * s, 0.06 * s, IRON)
	mb.add(MeshBuilder.cyl(0.9 * s, 0.5 * s, 0.6 * s, 14), Transform3D(Basis(), Vector3(0, 1.6 * s, 0)), IRON)
	gb.add(MeshBuilder.sphere(0.75 * s, 12, 4), Transform3D(Basis.from_scale(Vector3(1, 0.3, 1)), Vector3(0, 1.9 * s, 0)), Color(1.0, 0.35, 0.08, 0.0))   # glowing coals
	return _done(mb, gb, [_cyl_col(0.9 * s, 1.9 * s)], Vector2(1.0 * s, 1.0 * s), {
		"light": Color(1.0, 0.55, 0.25), "light_at": Vector3(0, 3.2 * s, 0), "light_energy": 2.4, "light_range": 14.0,
		"fire_at": Vector3(0, 2.0 * s, 0), "fire_size": 0.75 * s})


static func throne(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	# Dais: three broad steps
	for k in 3:
		mb.add(MeshBuilder.box(Vector3(14.0 - k * 3.0, 0.5, 10.0 - k * 2.4)), Transform3D(Basis(), Vector3(0, 0.25 + k * 0.5, 0)), DARK if k % 2 == 0 else STONE)
	mb.add(MeshBuilder.box(Vector3(3.2, 0.05, 7.0)), Transform3D(Basis(), Vector3(0, 1.53, 1.5)), RED)
	# The throne: tall back, arms, gold trim, a red seat
	var y := 1.5
	mb.add(MeshBuilder.box(Vector3(2.6, 1.0, 2.0)), Transform3D(Basis(), Vector3(0, y + 0.5, -1.4)), DARK)
	mb.add(MeshBuilder.box(Vector3(2.2, 0.15, 1.8)), Transform3D(Basis(), Vector3(0, y + 1.05, -1.3)), RED)
	mb.add(MeshBuilder.box(Vector3(2.8, 5.0, 0.4)), Transform3D(Basis(), Vector3(0, y + 2.5, -2.4)), DARK)
	mb.add(MeshBuilder.box(Vector3(2.2, 4.2, 0.1)), Transform3D(Basis(), Vector3(0, y + 2.7, -2.18)), RED)
	for side in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(0.35, 0.9, 2.0)), Transform3D(Basis(), Vector3(side * 1.25, y + 1.45, -1.4)), DARK)
		mb.add(MeshBuilder.cone(0.25, 0.9, 6), Transform3D(Basis(), Vector3(side * 1.2, y + 5.45, -2.4)), GOLD)
	mb.add(MeshBuilder.cone(0.35, 1.2, 6), Transform3D(Basis(), Vector3(0, y + 5.6, -2.4)), GOLD)
	gb.add(MeshBuilder.sphere(0.22, 10, 6), Transform3D(Basis(), Vector3(0, y + 4.4, -2.1)), Color(0.9, 0.15, 0.2, 0.0))   # a glowing ruby
	return _done(mb, gb, [_box_col(Vector3(14.0, 1.5, 10.0), Vector3(0, 0.75, 0)), _box_col(Vector3(2.8, 5.0, 2.4), Vector3(0, y + 2.5, -1.6))],
		Vector2(7.0, 5.0), {"light": Color(1.0, 0.4, 0.35), "light_at": Vector3(0, 5.0, 2.0), "light_energy": 1.5, "light_range": 14.0})


static func chandelier(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	mb.limb(Vector3(0, 7.0, 0), Vector3(0, 0.6, 0), 0.04, 0.04, IRON)   # chain to the ceiling
	for ring in [[2.2, 0.0, 10], [1.3, 0.7, 6]]:
		var r: float = ring[0]
		var y: float = ring[1]
		var nc: int = ring[2]
		mb.add(MeshBuilder.cyl(r, r, 0.12, 20), Transform3D(Basis(), Vector3(0, y, 0)), IRON)
		for k in nc:
			var a := TAU * k / nc
			var p := Vector3(cos(a) * r, y + 0.2, sin(a) * r)
			mb.add(MeshBuilder.cyl(0.06, 0.06, 0.3, 6), Transform3D(Basis(), p), CANDLE)
			gb.add(MeshBuilder.sphere(0.07, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 1.8, 1)), p + Vector3(0, 0.25, 0)), FLAME)
		for k in 4:
			var a := TAU * k / 4.0
			mb.limb(Vector3(0, y + 0.8, 0), Vector3(cos(a) * r, y, sin(a) * r), 0.03, 0.03, IRON)
	return _done(mb, gb, [], Vector2.ZERO)


# ------------------------------------------------------------------ wall decor (MultiMesh)

## An iron sconce with a torch and a glowing flame; -Z faces into the room.
static func sconce(rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	mb.add(MeshBuilder.box(Vector3(0.3, 0.5, 0.08)), Transform3D(Basis(), Vector3(0, 0, -0.04)), IRON)
	mb.limb(Vector3(0, 0, -0.05), Vector3(0, 0.45, -0.45), 0.04, 0.04, IRON)
	mb.limb(Vector3(0, 0.2, -0.4), Vector3(0, 0.75, -0.45), 0.06, 0.07, DARK_WOOD)
	gb.add(MeshBuilder.cone(0.13, 0.4, 8), Transform3D(Basis(), Vector3(0, 0.95, -0.45)), FLAME)
	var mesh := mb.commit()
	gb.commit_into(mesh, MeshBuilder.glow_material())
	return mesh


## A long hanging banner (red, gold edge, a gold emblem); sways.
static func banner(rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	mb.add(MeshBuilder.cyl(0.06, 0.06, 2.6, 6), Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(0, 3.0, -0.1)), IRON)
	for k in 6:   # cloth in strips so it sways more toward the bottom
		var y := 2.6 - k * 1.0
		mb.add(MeshBuilder.box(Vector3(2.2, 1.0, 0.04)), Transform3D(Basis(), Vector3(0, y, -0.1)), Color(CLOTH.r, CLOTH.g, CLOTH.b, k / 6.0 * 0.8))
	mb.add(MeshBuilder.box(Vector3(0.9, 0.9, 0.05)), Transform3D(Basis(Vector3(0, 0, 1), PI / 4), Vector3(0, 0.6, -0.13)), Color(GOLD.r, GOLD.g, GOLD.b, 0.4))
	mb.add(MeshBuilder.cone(1.1, 1.0, 3), Transform3D(Basis(Vector3(1, 0, 0), PI) * Basis(Vector3.UP, PI / 6), Vector3(0, -3.3, -0.1)), Color(CLOTH.r, CLOTH.g, CLOTH.b, 0.8))
	return mb.commit()


## A tall pointed stained-glass window lit by the moon outside; -Z faces into the room.
static func stained_window(rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var w := 3.0
	var h := 8.0
	mb.add(MeshBuilder.box(Vector3(w + 0.6, 0.4, 0.3)), Transform3D(Basis(), Vector3(0, -h * 0.5, -0.1)), DARK)
	var palette := [Color(0.15, 0.25, 0.7, 0.0), Color(0.6, 0.12, 0.15, 0.0), Color(0.15, 0.45, 0.25, 0.0), Color(0.6, 0.48, 0.15, 0.0), Color(0.35, 0.15, 0.55, 0.0)]
	var cols := 4
	var rows := 9
	for r in rows:
		for c in cols:
			var x := -w * 0.5 + (c + 0.5) * w / cols
			var y := -h * 0.5 + (r + 0.5) * h / rows
			if r == rows - 1 and absf(x) > w * 0.3:
				continue   # the pointed top
			var col: Color = palette[(r * 3 + c * 7 + rng.randi() % 2) % palette.size()]
			gb.add(MeshBuilder.box(Vector3(w / cols - 0.07, h / rows - 0.07, 0.04)), Transform3D(Basis(), Vector3(x, y, -0.02)), col)
	for c in cols + 1:   # lead
		mb.add(MeshBuilder.box(Vector3(0.06, h, 0.08)), Transform3D(Basis(), Vector3(-w * 0.5 + c * w / cols, 0, -0.05)), IRON)
	var mesh := mb.commit()
	var glass := MeshBuilder.glow_material().duplicate() as ShaderMaterial
	glass.set_shader_parameter("glow", 1.4)
	gb.commit_into(mesh, glass)
	return mesh
