class_name CastleFeast
extends Node3D
## The dining hall's very long table, laid with a feast. A carved oak table with an apron, turned
## legs and a gold-trimmed runner; place settings in three table sets (silver, gold and pewter
## plates with a knife and spoon, and a goblet of wine at every place); down the middle whole
## roast chickens, roast boars with apples in their mouths, platters of turkey legs, silver
## platters of fruit, meat pies, loaves, cheese wheels, wine bottles, jugs and candlesticks.
## Every one is a real rigid body under normal gravity, asleep until disturbed:
##   - walking (or landing) on the table kicks whatever you step into along your motion
##   - any blast nearby (FxManager.burst: explosions, Fire Nova, Meteor, shatters...) flings
##     the food outward from it
##   - a goblet that tips over spills its wine: a splash, and a pool of wine where it ends up
##   - a wine bottle that hits the floor shatters with the sound of breaking glass and leaves
##     a pool of wine where it broke
## Food sits on its own physics layer, so it never blocks you or the goblins, but it does hit
## the table, the floor, the walls and the rest of the food.

const LAYER_FOOD := 1 << 3        # physics layer 4
const KICK_RADIUS := 1.2          # metres around your feet that you kick (generous: it's a stampede)
const KICK_COOLDOWN := 0.25
const SPACING := 1.0              # metres between place settings along each side
const BENCH_GAP := 1.15           # benches this far out from the table's edges
# Loitering on the table brings a chandelier down on you
const STAND_TIME := 2.0           # seconds on the table top before one drops
const DROP_WARN := 1.0            # its marker shows this long before it hits
const DROP_RADIUS := 2.4
const DROP_DAMAGE := 0.15         # of the player's max HP
const DROP_LINGER := 5.0          # the wreck lies on the table this long

var rect := []                    # table top x0, z0, x1, z1
var top_y := 0.95
var items: Array[RigidBody3D] = []
var _kicked := {}                 # item -> time it was last kicked
var _time := 0.0
var kicks := 0                    # counters for tests
var blasts := 0
var player: Node3D
var _meshes := {}
var stand_t := 0.0                # seconds the player has been standing on the table
var drops := 0                    # counters for tests
var drop_hits := 0
var _falling: Array = []          # {at, t, node, marker}
var _rng := RandomNumberGenerator.new()
var _snap_sfx: AudioStreamPlayer3D
var _crash_sfx: AudioStreamPlayer3D
var _glass_sfx: Array[AudioStreamPlayer3D] = []
var _goblets: Array[RigidBody3D] = []
var _bottles: Array[RigidBody3D] = []
var _pools: Array[Node3D] = []
var spills := 0                   # counters for tests
var bottles_broken := 0
var _wine_mesh: Mesh
var _wine_mat: StandardMaterial3D
const SETS := ["silver", "gold", "pewter"]   # table sets, changing every SET_RUN metres
const SET_RUN := 6.0
const MAX_POOLS := 60
const SILVER := Color(0.78, 0.79, 0.82, 0)
const ROAST := Color(0.6, 0.32, 0.1, 0)
const PORK := Color(0.62, 0.32, 0.13, 0)
const BONE := Color(0.92, 0.88, 0.78, 0)
const SET_METAL := {"silver": Color(0.78, 0.79, 0.82, 0), "gold": Color(0.82, 0.62, 0.2, 0), "pewter": Color(0.5, 0.5, 0.53, 0)}
const SET_INNER := {"silver": Color(0.88, 0.88, 0.9, 0), "gold": Color(0.93, 0.88, 0.75, 0), "pewter": Color(0.6, 0.6, 0.62, 0)}
const CENTRE := [["whole_chicken", 3], ["roast_boar", 2], ["turkey_legs", 2], ["fruit_platter", 3], ["wine_bottle", 2],
	["candlestick", 2], ["pie", 1], ["bread", 1], ["cheese_wheel", 1], ["jug", 1]]


func build(rng: RandomNumberGenerator, table_rect: Array, height: float) -> void:
	add_to_group("castle_feast")
	rect = table_rect
	_rng.seed = rng.randi()
	_snap_sfx = _sfx("res://audio/castle/chandelier_snap.wav")
	_crash_sfx = _sfx("res://audio/castle/chandelier_crash.wav")
	top_y = height
	_furniture()
	for k in 3:
		_glass_sfx.append(_sfx("res://audio/abilities/glass_break_%d.wav" % (k + 1)))
	var x0: float = rect[0]
	var x1: float = rect[2]
	var z: float = rect[1] + 0.6
	var total := 0
	for c in CENTRE:
		total += int(c[1])
	var k := 0
	while z < float(rect[3]) - 0.6:
		var set_name: String = SETS[int((z - float(rect[1])) / SET_RUN) % SETS.size()]
		for side in [-1.0, 1.0]:   # a place setting at each side: plate (knife and spoon), goblet, a bite
			var x: float = (x0 + 0.45) if side < 0 else (x1 - 0.45)
			_add("plate_" + set_name, Vector3(x, 0, z), rng)
			var kind: String = ["chicken_leg", "bread", "apple", "cheese", "none"][rng.randi() % 5]
			if kind != "none":
				_add(kind, Vector3(x, 0.05, z + rng.randf_range(-0.05, 0.05)), rng)
			_add("goblet_" + set_name, Vector3(x + side * -0.32, 0, z + 0.26), rng)
			if rng.randf() < 0.18:
				_add("wine_bottle", Vector3(x + side * -0.5, 0, z - 0.25), rng)
		# down the middle: roasts, platters, bottles, candles
		var roll := rng.randi() % total
		var mid := "pie"
		for c in CENTRE:
			roll -= int(c[1])
			if roll < 0:
				mid = c[0]
				break
		if k < 15 and k % 3 == 1:   # every table gets its centrepieces: boar, chicken, wine, turkey, fruit
			mid = ["roast_boar", "whole_chicken", "wine_bottle", "turkey_legs", "fruit_platter"][k / 3]
		_add(mid, Vector3(rng.randf_range(-0.2, 0.2), 0, z), rng)
		if mid != "roast_boar" and rng.randf() < 0.85:   # a second dish beside it
			var extra: String = ["fruit_platter", "wine_bottle", "apple", "bread", "whole_chicken", "turkey_legs"][rng.randi() % 6]
			_add(extra, Vector3(rng.randf_range(-0.55, -0.4) if k % 2 else rng.randf_range(0.4, 0.55), 0, z + rng.randf_range(-0.2, 0.2)), rng)
		z += SPACING
		k += 1


func _furniture() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.27, 0.16, 0.08)
	wood.roughness = 0.6
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.17, 0.1, 0.05)
	dark.roughness = 0.7
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.3, 0.05, 0.05)   # a deep red runner...
	cloth.roughness = 1.0
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.82, 0.62, 0.2)    # ...with gold trim
	trim.metallic = 0.8
	trim.roughness = 0.35
	var x0: float = rect[0]
	var z0: float = rect[1]
	var x1: float = rect[2]
	var z1: float = rect[3]
	var w := x1 - x0
	var l := z1 - z0
	var c := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	var table := StaticBody3D.new()
	add_child(table)
	_solid(table, Vector3(w, 0.12, l), c + Vector3(0, top_y - 0.06, 0), wood)
	_visual(table, Vector3(w + 0.08, 0.04, l + 0.08), c + Vector3(0, top_y - 0.1, 0), dark)          # moulded edge
	for side in [-1.0, 1.0]:   # the apron under the top, with carved panels
		_visual(table, Vector3(0.05, 0.22, l - 0.4), c + Vector3(side * (w * 0.5 - 0.12), top_y - 0.23, 0), dark)
		var pz := z0 + 1.0
		while pz < z1 - 0.8:
			_visual(table, Vector3(0.03, 0.12, 0.6), Vector3(c.x + side * (w * 0.5 - 0.09), top_y - 0.23, pz), wood)
			pz += 1.2
	_visual(table, Vector3(w * 0.42, 0.012, l - 0.2), c + Vector3(0, top_y + 0.006, 0), cloth)      # runner
	for side in [-1.0, 1.0]:
		_visual(table, Vector3(0.04, 0.014, l - 0.2), c + Vector3(side * w * 0.21, top_y + 0.007, 0), trim)
	var z := z0 + 2.0
	while z < z1 - 1.0:   # turned legs: a column with rings, a bulb and a foot
		for side in [-1.0, 1.0]:
			var lx: float = c.x + side * (w * 0.5 - 0.3)
			_leg(table, Vector3(lx, 0, z), wood, dark)
		z += 6.0
	for side in [-1.0, 1.0]:   # long benches either side
		var bench := StaticBody3D.new()
		add_child(bench)
		var bx: float = c.x + side * (w * 0.5 + BENCH_GAP)
		_solid(bench, Vector3(0.7, 0.1, l - 1.0), Vector3(bx, 0.5, c.z), wood)
		_visual(bench, Vector3(0.74, 0.03, l - 0.96), Vector3(bx, 0.44, c.z), dark)
		var bz := z0 + 2.0
		while bz < z1 - 1.0:
			_visual(bench, Vector3(0.6, 0.45, 0.12), Vector3(bx, 0.22, bz), dark)
			_visual(bench, Vector3(0.66, 0.06, 0.18), Vector3(bx, 0.03, bz), dark)
			bz += 4.0


func _leg(parent: Node3D, at: Vector3, wood: Material, dark: Material) -> void:
	var h := top_y - 0.12
	var parts := [[0.07, 0.09, 0.08, 0.04, dark], [0.06, 0.06, h * 0.35, h * 0.25, wood], [0.11, 0.09, 0.16, h * 0.5, wood],
		[0.08, 0.08, 0.04, h * 0.6, dark], [0.06, 0.06, h * 0.32, h * 0.77, wood], [0.09, 0.09, 0.05, h - 0.03, dark]]
	for pt in parts:
		var cm := CylinderMesh.new()
		cm.top_radius = pt[0]
		cm.bottom_radius = pt[1]
		cm.height = pt[2]
		cm.radial_segments = 10
		cm.material = pt[4]
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.position = at + Vector3(0, float(pt[3]), 0)
		parent.add_child(mi)


func _solid(body: StaticBody3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var s := BoxShape3D.new()
	s.size = size
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position = at
	body.add_child(cs)
	_visual(body, size, at, mat)


func _visual(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = at
	parent.add_child(mi)


# ------------------------------------------------------------------ food

## [mesh builder, collision shape, mass kg, centre height] per kind (meshes built once, shared)
func _kind(kind: String) -> Array:
	if _meshes.has(kind):
		return _meshes[kind]
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var shape: Shape3D
	var mass := 0.3
	var h := 0.05
	match kind:
		"chicken_leg":
			mb.add(MeshBuilder.sphere(0.06, 8, 5), Transform3D(Basis.from_scale(Vector3(1.4, 1, 1)), Vector3(0.03, 0, 0)), Color(0.55, 0.3, 0.1, 0))
			mb.limb(Vector3(-0.03, 0, 0), Vector3(-0.12, 0.02, 0), 0.015, 0.015, Color(0.9, 0.87, 0.78, 0))
			shape = _sphere(0.06)
			mass = 0.15
			h = 0.06
		"bread":
			mb.add(MeshBuilder.sphere(0.1, 10, 6), Transform3D(Basis.from_scale(Vector3(1.6, 0.7, 1.0)), Vector3.ZERO), Color(0.72, 0.48, 0.2, 0))
			shape = _box(Vector3(0.3, 0.13, 0.19))
			mass = 0.3
			h = 0.07
		"apple":
			var red := Color(0.65, 0.08, 0.06, 0) if randf() < 0.6 else Color(0.45, 0.6, 0.12, 0)
			mb.add(MeshBuilder.sphere(0.045, 8, 6), Transform3D(), red)
			mb.limb(Vector3(0, 0.04, 0), Vector3(0.005, 0.07, 0), 0.006, 0.004, Color(0.25, 0.15, 0.05, 0))
			shape = _sphere(0.045)
			mass = 0.15
			h = 0.045
		"cheese":
			mb.add(MeshBuilder.cyl(0.0, 0.11, 0.08, 3), Transform3D(Basis(Vector3(1, 0, 0), PI / 2), Vector3.ZERO), Color(0.9, 0.75, 0.3, 0))
			shape = _box(Vector3(0.18, 0.08, 0.16))
			mass = 0.2
			h = 0.04
		"roast":
			mb.add(MeshBuilder.cyl(0.28, 0.24, 0.03, 16), Transform3D(Basis(), Vector3(0, -0.06, 0)), Color(0.75, 0.75, 0.78, 0))
			mb.add(MeshBuilder.sphere(0.15, 10, 6), Transform3D(Basis.from_scale(Vector3(1.3, 0.85, 1.0)), Vector3(0, 0.05, 0)), Color(0.55, 0.28, 0.08, 0))
			for s in [-1.0, 1.0]:
				mb.add(MeshBuilder.sphere(0.06, 8, 5), Transform3D(Basis.from_scale(Vector3(1.5, 1, 1)), Vector3(0.17, 0.05, s * 0.09)), Color(0.5, 0.25, 0.07, 0))
			shape = _cyl(0.28, 0.25)
			mass = 1.5
			h = 0.075
		"roast_pig":
			mb.add(MeshBuilder.box(Vector3(0.75, 0.04, 0.42)), Transform3D(Basis(), Vector3(0, -0.12, 0)), Color(0.7, 0.68, 0.7, 0))
			mb.add(MeshBuilder.sphere(0.18, 12, 6), Transform3D(Basis.from_scale(Vector3(1.8, 0.85, 1.0)), Vector3(0, 0.04, 0)), Color(0.6, 0.3, 0.12, 0))
			mb.add(MeshBuilder.sphere(0.1, 10, 6), Transform3D(Basis(), Vector3(0.33, 0.06, 0)), Color(0.58, 0.29, 0.11, 0))
			mb.add(MeshBuilder.sphere(0.04, 8, 5), Transform3D(Basis(), Vector3(0.43, 0.05, 0)), Color(0.75, 0.1, 0.08, 0))   # apple in its mouth
			shape = _box(Vector3(0.75, 0.32, 0.42))
			mass = 4.0
			h = 0.14
		"pie":
			mb.add(MeshBuilder.cyl(0.16, 0.13, 0.06, 14), Transform3D(), Color(0.78, 0.55, 0.25, 0))
			mb.add(MeshBuilder.sphere(0.15, 12, 4), Transform3D(Basis.from_scale(Vector3(1, 0.25, 1)), Vector3(0, 0.03, 0)), Color(0.82, 0.6, 0.3, 0))
			shape = _cyl(0.16, 0.08)
			mass = 0.6
			h = 0.04
		"grapes":
			mb.add(MeshBuilder.cyl(0.16, 0.1, 0.06, 12), Transform3D(Basis(), Vector3(0, -0.03, 0)), Color(0.75, 0.57, 0.2, 0))
			for g in 14:
				var a := g * 2.4
				var r := 0.03 + (g % 5) * 0.018
				mb.add(MeshBuilder.sphere(0.028, 6, 4), Transform3D(Basis(), Vector3(cos(a) * r, 0.02 + (g / 5) * 0.03, sin(a) * r)), Color(0.3, 0.08, 0.35, 0))
			shape = _cyl(0.16, 0.12)
			mass = 0.5
			h = 0.05
		"jug":
			mb.add(MeshBuilder.cyl(0.06, 0.1, 0.3, 12), Transform3D(), Color(0.5, 0.3, 0.18, 0))
			mb.add(MeshBuilder.sphere(0.1, 10, 6), Transform3D(Basis.from_scale(Vector3(1, 0.6, 1)), Vector3(0, -0.06, 0)), Color(0.5, 0.3, 0.18, 0))
			shape = _cyl(0.1, 0.32)
			mass = 1.0
			h = 0.16
		"candlestick":
			mb.add(MeshBuilder.cyl(0.08, 0.1, 0.03, 10), Transform3D(Basis(), Vector3(0, -0.2, 0)), Color(0.75, 0.57, 0.2, 0))
			mb.add(MeshBuilder.cyl(0.02, 0.025, 0.25, 8), Transform3D(Basis(), Vector3(0, -0.07, 0)), Color(0.75, 0.57, 0.2, 0))
			mb.add(MeshBuilder.cyl(0.025, 0.025, 0.16, 8), Transform3D(Basis(), Vector3(0, 0.13, 0)), Color(0.92, 0.87, 0.72, 0))
			gb.add(MeshBuilder.sphere(0.025, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 1.8, 1)), Vector3(0, 0.25, 0)), Color(1.0, 0.62, 0.22, 0))
			shape = _cyl(0.09, 0.45)
			mass = 0.6
			h = 0.215
		"whole_chicken":
			_platter(mb, 0.24, -0.075, SILVER)
			mb.add(MeshBuilder.sphere(0.12, 10, 7), Transform3D(Basis.from_scale(Vector3(1.35, 0.85, 1.0)), Vector3(0, 0.0, 0)), ROAST)
			mb.add(MeshBuilder.sphere(0.08, 8, 5), Transform3D(Basis.from_scale(Vector3(1.3, 0.7, 1.2)), Vector3(0.03, 0.06, 0)), ROAST.lightened(0.12))   # glistening breast
			for sd in [-1.0, 1.0]:
				mb.add(MeshBuilder.sphere(0.05, 8, 5), Transform3D(Basis(Vector3.UP, sd * 0.4).scaled(Vector3(1.7, 1.0, 1.0)), Vector3(-0.11, -0.01, sd * 0.08)), ROAST.darkened(0.1))
				mb.limb(Vector3(-0.17, 0.0, sd * 0.11), Vector3(-0.22, 0.02, sd * 0.13), 0.012, 0.01, BONE, 5)
				mb.add(MeshBuilder.sphere(0.017, 6, 4), Transform3D(Basis(), Vector3(-0.225, 0.02, sd * 0.132)), BONE)
				mb.add(MeshBuilder.sphere(0.04, 7, 4), Transform3D(Basis.from_scale(Vector3(1.4, 0.6, 1.0)), Vector3(0.05, 0.02, sd * 0.11)), ROAST.darkened(0.05))
			_garnish(mb, 0.2, -0.05, 7)
			shape = _cyl(0.24, 0.22)
			mass = 1.2
			h = 0.085
		"roast_boar":
			mb.add(MeshBuilder.box(Vector3(0.95, 0.03, 0.5)), Transform3D(Basis(), Vector3(0, -0.155, 0)), SILVER)
			mb.add(MeshBuilder.box(Vector3(0.97, 0.03, 0.52)), Transform3D(Basis(), Vector3(0, -0.165, 0)), SILVER.darkened(0.2))
			mb.add(MeshBuilder.sphere(0.2, 12, 7), Transform3D(Basis.from_scale(Vector3(1.9, 0.9, 1.05)), Vector3(-0.03, 0.02, 0)), PORK)
			mb.add(MeshBuilder.sphere(0.13, 10, 6), Transform3D(Basis.from_scale(Vector3(1.6, 0.6, 0.9)), Vector3(-0.05, 0.13, 0)), PORK.lightened(0.1))   # crackling back
			mb.add(MeshBuilder.sphere(0.12, 10, 6), Transform3D(Basis.from_scale(Vector3(1.1, 0.95, 0.95)), Vector3(0.36, 0.03, 0)), PORK.darkened(0.05))
			mb.limb(Vector3(0.42, 0.0, 0), Vector3(0.52, -0.01, 0), 0.07, 0.055, PORK.darkened(0.1), 8)   # snout
			mb.add(MeshBuilder.sphere(0.055, 8, 6), Transform3D(Basis(), Vector3(0.575, -0.005, 0)), Color(0.75, 0.08, 0.06, 0))   # apple in its mouth
			mb.limb(Vector3(0.58, 0.045, 0), Vector3(0.585, 0.075, 0.005), 0.006, 0.004, Color(0.25, 0.15, 0.05, 0))
			for sd in [-1.0, 1.0]:
				mb.add(MeshBuilder.cone(0.04, 0.08, 5), Transform3D(Basis(Vector3(1, 0, 0), sd * 0.5), Vector3(0.32, 0.14, sd * 0.06)), PORK.darkened(0.2))   # ears
				mb.add(MeshBuilder.sphere(0.012, 5, 3), Transform3D(Basis(), Vector3(0.44, 0.07, sd * 0.06)), Color(0.05, 0.03, 0.02, 0))   # eyes
				for fb in [-1.0, 1.0]:   # legs tucked under
					mb.limb(Vector3(fb * 0.22, -0.08, sd * 0.12), Vector3(fb * 0.33, -0.13, sd * 0.15), 0.05, 0.035, PORK.darkened(0.15), 6)
			mb.limb(Vector3(-0.4, 0.04, 0), Vector3(-0.47, 0.08, 0.03), 0.015, 0.006, PORK.darkened(0.2), 4)   # tail
			for k in 6:   # apples and greens round the platter
				var ax := -0.38 + k * 0.15
				mb.add(MeshBuilder.sphere(0.04, 7, 5), Transform3D(Basis(), Vector3(ax, -0.11, 0.2 * (1.0 if k % 2 else -1.0))), Color(0.7, 0.08, 0.06, 0) if k % 3 else Color(0.45, 0.6, 0.12, 0))
			_garnish(mb, 0.42, -0.13, 10)
			shape = _box(Vector3(0.97, 0.36, 0.52))
			mass = 5.0
			h = 0.17
		"turkey_legs":
			_platter(mb, 0.22, -0.035, SILVER)
			for k in 6:
				var a := TAU * k / 6.0 + 0.3
				var out := Vector3(cos(a), 0, sin(a))
				var y := 0.0 if k % 2 else 0.03
				mb.add(MeshBuilder.sphere(0.055, 8, 5), Transform3D(Basis(Vector3.UP, -a).scaled(Vector3(1.8, 1.0, 1.05)), out * 0.06 + Vector3(0, y, 0)), ROAST.darkened(0.05 * k))
				mb.limb(out * 0.14 + Vector3(0, y, 0), out * 0.22 + Vector3(0, y + 0.01, 0), 0.016, 0.013, BONE, 5)
				mb.add(MeshBuilder.sphere(0.022, 6, 4), Transform3D(Basis(), out * 0.225 + Vector3(0, y + 0.01, 0)), BONE)
			shape = _cyl(0.22, 0.12)
			mass = 0.9
			h = 0.05
		"fruit_platter":
			_platter(mb, 0.27, -0.04, SILVER)
			mb.add(MeshBuilder.cyl(0.27, 0.27, 0.035, 18), Transform3D(Basis(), Vector3(0, -0.03, 0)), SILVER.darkened(0.15))   # raised rim
			var fruit := [Color(0.7, 0.08, 0.06, 0), Color(0.45, 0.6, 0.12, 0), Color(0.95, 0.55, 0.1, 0), Color(0.35, 0.1, 0.32, 0), Color(0.75, 0.7, 0.2, 0)]
			for k in 13:
				var a := k * 2.4
				var r := 0.04 + (k % 4) * 0.05
				var at := Vector3(cos(a) * r, -0.005 + (0.05 if k > 9 else 0.0), sin(a) * r)
				var fc: Color = fruit[k % fruit.size()]
				if k % 5 == 4:   # a pear
					mb.add(MeshBuilder.sphere(0.04, 7, 5), Transform3D(Basis(), at), fc)
					mb.add(MeshBuilder.sphere(0.027, 6, 4), Transform3D(Basis(), at + Vector3(0, 0.045, 0)), fc)
				else:
					mb.add(MeshBuilder.sphere(0.04 if k % 5 != 3 else 0.03, 7, 5), Transform3D(Basis(), at), fc)
				mb.limb(at + Vector3(0, 0.035, 0), at + Vector3(0.004, 0.06, 0), 0.005, 0.003, Color(0.25, 0.15, 0.05, 0))
			for g in 12:   # a bunch of grapes over the edge
				var gr := 0.02 + (g % 4) * 0.014
				mb.add(MeshBuilder.sphere(0.022, 6, 4), Transform3D(Basis(), Vector3(0.17 + cos(g * 2.4) * gr, 0.0 + (g / 4) * 0.025, sin(g * 2.4) * gr)), Color(0.3, 0.08, 0.35, 0))
			shape = _cyl(0.27, 0.2)
			mass = 1.2
			h = 0.06
		"wine_bottle":
			var glass := Color(0.07, 0.2, 0.09, 0) if randf() < 0.6 else Color(0.18, 0.09, 0.05, 0)
			mb.add(MeshBuilder.cyl(0.042, 0.042, 0.2, 12), Transform3D(Basis(), Vector3(0, -0.05, 0)), glass)
			mb.add(MeshBuilder.sphere(0.042, 12, 6), Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), Vector3(0, 0.05, 0)), glass)
			mb.add(MeshBuilder.cyl(0.014, 0.017, 0.1, 10), Transform3D(Basis(), Vector3(0, 0.1, 0)), glass)
			mb.add(MeshBuilder.cyl(0.0425, 0.0425, 0.08, 12), Transform3D(Basis(), Vector3(0, -0.06, 0)), Color(0.88, 0.82, 0.66, 0))   # label
			mb.add(MeshBuilder.cyl(0.0175, 0.0175, 0.03, 8), Transform3D(Basis(), Vector3(0, 0.155, 0)), Color(0.6, 0.1, 0.12, 0))   # wax seal
			shape = _cyl(0.045, 0.33)
			mass = 1.2
			h = 0.15
		"cheese_wheel":
			mb.add(MeshBuilder.cyl(0.14, 0.14, 0.09, 16), Transform3D(), Color(0.85, 0.66, 0.25, 0))
			mb.add(MeshBuilder.cyl(0.13, 0.13, 0.092, 16), Transform3D(), Color(0.95, 0.82, 0.42, 0))
			mb.add(MeshBuilder.cyl(0.18, 0.18, 0.02, 14), Transform3D(Basis(), Vector3(0, -0.055, 0)), Color(0.4, 0.25, 0.12, 0))   # board
			shape = _cyl(0.18, 0.11)
			mass = 1.0
			h = 0.055
		_:
			if kind.begins_with("plate_"):   # a plate in one of the table sets, knife and spoon beside it
				var metal: Color = SET_METAL.get(kind.substr(6), SILVER)
				mb.add(MeshBuilder.cyl(0.17, 0.12, 0.025, 16), Transform3D(), metal)
				mb.add(MeshBuilder.cyl(0.12, 0.12, 0.028, 16), Transform3D(), SET_INNER.get(kind.substr(6), Color(0.85, 0.83, 0.78, 0)))
				mb.add(MeshBuilder.box(Vector3(0.022, 0.006, 0.16)), Transform3D(Basis(), Vector3(0.215, -0.008, 0.03)), SILVER.lightened(0.1))   # knife blade
				mb.add(MeshBuilder.box(Vector3(0.026, 0.014, 0.09)), Transform3D(Basis(), Vector3(0.215, -0.005, -0.09)), metal.darkened(0.25))   # ...handle
				mb.add(MeshBuilder.box(Vector3(0.014, 0.006, 0.15)), Transform3D(Basis(), Vector3(-0.21, -0.008, -0.04)), metal)   # spoon handle
				mb.add(MeshBuilder.sphere(0.03, 8, 4), Transform3D(Basis.from_scale(Vector3(0.8, 0.25, 1.2)), Vector3(-0.21, -0.006, 0.06)), metal)
				shape = _cyl(0.17, 0.03)
				mass = 0.4
				h = 0.015
			elif kind.begins_with("goblet_"):   # wine is a separate mesh, so it can spill
				var metal: Color = SET_METAL.get(kind.substr(7), SILVER)
				mb.add(MeshBuilder.cyl(0.05, 0.055, 0.015, 12), Transform3D(Basis(), Vector3(0, -0.085, 0)), metal)
				mb.add(MeshBuilder.cyl(0.012, 0.012, 0.09, 8), Transform3D(Basis(), Vector3(0, -0.04, 0)), metal)
				mb.add(MeshBuilder.sphere(0.02, 8, 5), Transform3D(Basis(), Vector3(0, -0.03, 0)), metal.darkened(0.15))   # knop
				mb.add(MeshBuilder.cyl(0.06, 0.035, 0.09, 12), Transform3D(Basis(), Vector3(0, 0.045, 0)), metal)
				mb.add(MeshBuilder.cyl(0.062, 0.062, 0.012, 12), Transform3D(Basis(), Vector3(0, 0.085, 0)), metal.lightened(0.1))   # rim band
				mb.add(MeshBuilder.sphere(0.008, 5, 3), Transform3D(Basis(), Vector3(0.055, 0.05, 0)), Color(0.7, 0.05, 0.1, 0))   # a jewel
				shape = _cyl(0.05, 0.19)
				mass = 0.25
				h = 0.095
			else:
				push_warning("CastleFeast: unknown kind " + kind)
				shape = _sphere(0.05)
	var mesh := mb.commit()
	gb.commit_into(mesh, MeshBuilder.glow_material())
	_meshes[kind] = [mesh, shape, mass, h]
	return _meshes[kind]


## A round silver platter with a rim, its top at height `y`.
func _platter(mb: MeshBuilder, r: float, y: float, col: Color) -> void:
	mb.add(MeshBuilder.cyl(r, r * 0.85, 0.02, 18), Transform3D(Basis(), Vector3(0, y, 0)), col)
	mb.add(MeshBuilder.cyl(r * 1.04, r * 1.04, 0.012, 18), Transform3D(Basis(), Vector3(0, y + 0.004, 0)), col.darkened(0.2))


## Sprigs of greens round a dish.
func _garnish(mb: MeshBuilder, r: float, y: float, n: int) -> void:
	for k in n:
		var a := TAU * k / n + 0.2
		mb.add(MeshBuilder.sphere(0.025, 5, 3), Transform3D(Basis.from_scale(Vector3(1.5, 0.5, 1.0)), Vector3(cos(a) * r, y, sin(a) * r * 0.9)), Color(0.2, 0.42, 0.12, 0))


func _cyl(r: float, h: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return s


func _sphere(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


func _box(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


## Put one item on the table top at `at` (x, extra lift, z).
func _add(kind: String, at: Vector3, rng: RandomNumberGenerator) -> void:
	var k := _kind(kind)
	var body := RigidBody3D.new()
	body.mass = k[2]
	body.collision_layer = LAYER_FOOD
	body.collision_mask = 1 | LAYER_FOOD
	body.can_sleep = true
	body.sleeping = true
	body.angular_damp = 0.6
	body.continuous_cd = false
	body.position = Vector3(at.x, top_y + float(k[3]) + at.y + 0.002, at.z)
	body.rotation.y = rng.randf() * TAU if not kind.begins_with("plate_") else (0.0 if at.x > 0 else PI)
	body.set_meta("kind", kind)
	var mi := MeshInstance3D.new()
	mi.mesh = k[0]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = k[1]
	body.add_child(cs)
	add_child(body)
	items.append(body)
	if kind.begins_with("goblet_"):
		var wine := MeshInstance3D.new()
		wine.name = "Wine"   # no-i18n
		wine.mesh = _wine_surface()
		wine.position.y = 0.084
		body.add_child(wine)
		_goblets.append(body)
	elif kind == "wine_bottle":
		_bottles.append(body)


# ------------------------------------------------------------------ interaction

var _hooked := false   # FxManager is created after the map: hook up on the first physics frame


func _physics_process(dt: float) -> void:
	_time += dt
	if not _hooked:
		_hook_bursts()
	_tick_wine()
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
		if player == null:
			return
	var p := player.global_position
	_tick_chandeliers(dt, p)
	if p.x < float(rect[0]) - 1.5 or p.x > float(rect[2]) + 1.5 or p.z < float(rect[1]) - 1.5 or p.z > float(rect[3]) + 1.5:
		return
	if p.y < top_y - 0.6:
		return   # beside the table, not on it
	var v: Vector3 = player.get("velocity") if player.get("velocity") != null else Vector3.ZERO
	var hv := Vector3(v.x, 0, v.z)
	var speed := hv.length()
	var landing := v.y < -4.0
	if speed < 0.6 and not landing:
		return
	for it in items:
		var ip := it.global_position
		if absf(ip.z - p.z) > KICK_RADIUS or absf(ip.x - p.x) > KICK_RADIUS or ip.y > p.y + 1.2 or ip.y < p.y - 1.0:
			continue
		if _time - float(_kicked.get(it, -10.0)) < KICK_COOLDOWN:
			continue
		_kicked[it] = _time
		var away := Vector3(ip.x - p.x, 0, ip.z - p.z)
		var dir := (hv.normalized() * 0.75 + away.normalized() * 0.5).normalized() if speed > 0.6 else away.normalized()
		var push := clampf(2.2 + speed * 0.45, 2.0, 8.0) + (3.0 if landing else 0.0)
		it.apply_central_impulse((dir * push + Vector3(0, randf_range(2.5, 4.5), 0)) * it.mass)
		it.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * it.mass * 0.15)
		kicks += 1


# ------------------------------------------------------------------ falling chandeliers

## Standing on the table top for STAND_TIME s drops a chandelier where you were: a marker on
## the table fills for DROP_WARN s, then it crashes down for DROP_DAMAGE of your max HP if
## you're still under it. Keep standing there and another follows every STAND_TIME s.
func _tick_chandeliers(dt: float, p: Vector3) -> void:
	var on_table := p.x >= float(rect[0]) and p.x <= float(rect[2]) and p.z >= float(rect[1]) and p.z <= float(rect[3]) \
		and p.y > top_y - 0.25 and p.y < top_y + 0.4
	stand_t = stand_t + dt if on_table else 0.0
	if stand_t >= STAND_TIME:
		stand_t = 0.0
		_drop(Vector3(p.x, top_y, p.z))
	for k in range(_falling.size() - 1, -1, -1):
		var f: Dictionary = _falling[k]
		f["t"] += dt
		var t: float = f["t"]
		var at: Vector3 = f["at"]
		var node: Node3D = f["node"]
		if t < DROP_WARN:
			var marker: GroundDisc = f["marker"]
			marker.set_fill(t / DROP_WARN)
			marker.alpha = 0.45 + 0.2 * sin(t * 30.0)
			var fall := clampf((t - DROP_WARN * 0.35) / (DROP_WARN * 0.65), 0.0, 1.0)   # it gives, then plummets
			var shake := 0.08 * (1.0 - fall) * sin(t * 60.0)
			node.position = Vector3(at.x + shake, lerpf(float(f["top"]), at.y, fall * fall), at.z)
			continue
		if not f.get("landed", false):
			f["landed"] = true
			_crash(at, f)
		if t >= DROP_WARN + DROP_LINGER:
			node.queue_free()
			_falling.remove_at(k)


func _drop(at: Vector3) -> void:
	drops += 1
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = CastleProps.chandelier(_rng)["mesh"]
	node.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.42)
	light.light_energy = 2.0
	light.omni_range = 8.0
	light.position.y = 0.5
	node.add_child(light)
	add_child(node)
	var top := CastleBuilder.CEILING - 7.0
	node.position = Vector3(at.x, top, at.z)
	var marker := GroundDisc.create(DROP_RADIUS, Color(1.0, 0.25, 0.1, 0.5))
	marker.set_fill(0.0)
	marker.set_lift(0.04)
	add_child(marker)
	marker.global_position = at
	_falling.append({"at": at, "t": 0.0, "node": node, "marker": marker, "top": top})
	_play(_snap_sfx, at)


func _crash(at: Vector3, f: Dictionary) -> void:
	(f["marker"] as GroundDisc).queue_free()
	var node: Node3D = f["node"]
	node.position = at
	node.rotation = Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf() * TAU, _rng.randf_range(-0.25, 0.25))   # lands askew
	var light := node.get_child(1) as OmniLight3D
	node.create_tween().tween_property(light, "light_energy", 0.0, 1.2)   # candles snuffed
	blast(at + Vector3(0, 0.3, 0), DROP_RADIUS)
	_play(_crash_sfx, at)
	if player != null and is_instance_valid(player):
		var pp := player.global_position
		if Vector2(pp.x - at.x, pp.z - at.z).length() <= DROP_RADIUS and pp.y < at.y + 2.5:
			if player.has_method("hurt") and player.hurt(float(player.get("max_hp")) * DROP_DAMAGE, "Falling Chandelier"):
				drop_hits += 1
		if player.has_method("add_shake"):
			player.add_shake(0.5 if Vector2(pp.x - at.x, pp.z - at.z).length() < 12.0 else 0.2)
	for fx in get_tree().root.find_children("*", "FxManager", true, false):
		(fx as FxManager).burst(at + Vector3(0, 0.6, 0), DROP_RADIUS, Color(1.0, 0.75, 0.4), 0.3)
		break


func _sfx(path: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = Settings.SFX_BUS
	p.unit_size = 14.0
	p.max_polyphony = 3
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p


func _play(p: AudioStreamPlayer3D, at: Vector3) -> void:
	if p and p.stream:
		p.global_position = at
		p.play()


func _hook_bursts() -> void:
	for f in get_tree().root.find_children("*", "FxManager", true, false):
		var fx := f as FxManager
		if fx and not fx.burst_fired.is_connected(blast):
			fx.burst_fired.connect(blast)
			_hooked = true


## Fling food outward from an explosion at `at` with radius `radius` (any burst near the table).
func blast(at: Vector3, radius: float) -> void:
	var reach := radius * 1.3 + 0.5
	if at.x < float(rect[0]) - reach or at.x > float(rect[2]) + reach or at.z < float(rect[1]) - reach or at.z > float(rect[3]) + reach:
		return
	var hit := false
	for it in items:
		var d := it.global_position - at
		var dist := d.length()
		if dist > reach:
			continue
		var f := 1.0 - dist / reach
		var dir := (d + Vector3(0, 0.6, 0)).normalized() if dist > 0.01 else Vector3.UP
		it.apply_central_impulse(dir * (3.0 + radius * 1.6) * f * it.mass)
		it.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * it.mass * 0.2 * f)
		hit = true
	if hit:
		blasts += 1


# ------------------------------------------------------------------ wine

## The dark red surface of the wine in a goblet (shared).
func _wine_surface() -> Mesh:
	if _wine_mesh == null:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.054
		cm.bottom_radius = 0.054
		cm.height = 0.004
		cm.radial_segments = 12
		cm.material = _wine_material()
		_wine_mesh = cm
	return _wine_mesh


func _wine_material() -> StandardMaterial3D:
	if _wine_mat == null:
		_wine_mat = StandardMaterial3D.new()
		_wine_mat.albedo_color = Color(0.32, 0.015, 0.05)
		_wine_mat.roughness = 0.08
		_wine_mat.metallic_specular = 0.7
	return _wine_mat


## Goblets that tip over spill (a splash, then a pool where they come to rest); bottles that
## reach the floor shatter (glass breaking, a pool of wine where they broke).
func _tick_wine() -> void:
	for g in _goblets:
		if g.sleeping or g.get_meta("spilled", false):
			continue
		if g.global_transform.basis.y.normalized().dot(Vector3.UP) < 0.35:   # tipped past ~70 degrees
			g.set_meta("spilled", true)
			var wine := g.get_node_or_null("Wine")
			if wine:
				wine.visible = false
			spills += 1
			_splash(g.global_position, 14)
			g.set_meta("pool_at", _time)
	for g in _goblets:   # the pool appears where it settles (or after a moment)
		if g.has_meta("pool_at") and (g.linear_velocity.length() < 0.6 or _time - float(g.get_meta("pool_at")) > 1.2):
			g.remove_meta("pool_at")
			_pool_below(g.global_position, randf_range(0.18, 0.3))
	for k in range(_bottles.size() - 1, -1, -1):
		var b := _bottles[k]
		if not is_instance_valid(b) or b.sleeping:
			continue
		if b.global_position.y < 0.3:   # hit the floor: smash
			_bottles.remove_at(k)
			items.erase(b)
			bottles_broken += 1
			var at := Vector3(b.global_position.x, 0.0, b.global_position.z)
			var sfx: AudioStreamPlayer3D = _glass_sfx[randi() % _glass_sfx.size()] if not _glass_sfx.is_empty() else null
			_play(sfx, at)
			_splash(at + Vector3(0, 0.1, 0), 26)
			_shards(at)
			_pool(at, randf_range(0.45, 0.7))
			b.queue_free()


## Find the surface under `from` (table or floor) and pool wine there.
func _pool_below(from: Vector3, r: float) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.3, 0), from + Vector3(0, -3.0, 0), 1)
	var hit := space.intersect_ray(q)
	var at: Vector3 = hit["position"] if not hit.is_empty() else Vector3(from.x, 0.0, from.z)
	_pool(at, r)


## A spreading, irregular pool of wine lying flat at `at`.
func _pool(at: Vector3, r: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 22
	var amps: Array[float] = []
	for k in 4:
		amps.append(randf_range(0.0, 0.22))
	var ph := randf() * TAU
	var pts: Array[Vector3] = []
	for k in seg:
		var a := TAU * k / seg
		var rr := r * (1.0 + amps[0] * sin(2.0 * a + ph) + amps[1] * sin(3.0 * a + ph * 1.7) + amps[2] * sin(5.0 * a + ph * 0.6) + amps[3] * sin(7.0 * a))
		pts.append(Vector3(cos(a) * rr, 0, sin(a) * rr))
	for k in seg:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP)
		st.add_vertex(pts[(k + 1) % seg])
		st.set_normal(Vector3.UP)
		st.add_vertex(pts[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _wine_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group("wine_pool")
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.004 + 0.0005 * (_pools.size() % 8), 0)
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3(0.15, 1.0, 0.15)
	mi.create_tween().tween_property(mi, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pools.append(mi)
	if _pools.size() > MAX_POOLS:
		var old: Node3D = _pools.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## A burst of wine droplets.
func _splash(at: Vector3, n: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = n
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -9.8, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.036
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = _wine_material()
	p.mesh = sm
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	add_child(p)
	p.global_position = at
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


## Shards of green glass skittering out from a broken bottle.
func _shards(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 12
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 85.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -9.8, 0)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.005, 0.02)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.15, 0.4, 0.2)
	m.roughness = 0.1
	bm.material = m
	p.mesh = bm
	add_child(p)
	p.global_position = at + Vector3(0, 0.05, 0)
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func awake_count() -> int:
	var n := 0
	for it in items:
		if not it.sleeping:
			n += 1
	return n
