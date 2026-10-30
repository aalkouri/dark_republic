class_name ArenaEdge
extends RefCounted
## The edge of the outdoor maps (the Swamp and the Magical Forest). One of the four sides, picked
## at random each load, is closed off by a great castle wall (battlements, towers, arrow slits),
## and the distant castle stands on the horizon beyond it. The other three sides are thick
## woods: several rows of tall trees packed together, so the arena ends in forest instead of a
## grey wall. Invisible walls keep you in on every side, as before.

const T := 2.0              # collision wall thickness
const TREE_ROWS := 5
const TREE_STEP := 3.2      # metres between trees along a row
const TOWER_EVERY := 55.0


## Build the edge for `style` ("swamp" or "forest"); `haze` and `night` are passed on to the
## distant castle. Returns the side the castle is on (0 north/-z, 1 east/+x, 2 south/+z, 3 west/-x).
static func build(parent: Node3D, half: float, style: String, haze: Color, night: bool) -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()   # its own dice: a new side each load, without moving the seeded layout
	var side := r.randi() % 4
	_collision(parent, half)
	for s in 4:
		if s == side:
			_castle_wall(parent, half, s, haze, night)
		else:
			_woods(parent, half, s, style, night, r)
	var bearing: float = [-PI * 0.5, 0.0, PI * 0.5, PI][side] + r.randf_range(-0.3, 0.3)
	DistantCastle.add(parent, r, haze, night, bearing)
	return side


## Invisible walls on all four sides (the berm rises under them).
static func _collision(parent: Node3D, half: float) -> void:
	var top := SwampWater.HILL_HEIGHT + SwampWater.BUMP_HEIGHT + SwampWater.EDGE_RISE + 5.0
	var bottom := -SwampWater.HILL_HEIGHT - SwampWater.BUMP_HEIGHT - 2.0
	var h := top - bottom
	var y := (top + bottom) * 0.5
	var l := half * 2.0 + T * 2.0
	for s in [[Vector3(0, y, -half - T * 0.5), Vector3(l, h, T)], [Vector3(0, y, half + T * 0.5), Vector3(l, h, T)],
			[Vector3(-half - T * 0.5, y, 0), Vector3(T, h, l)], [Vector3(half + T * 0.5, y, 0), Vector3(T, h, l)]]:
		var body := StaticBody3D.new()
		var shape := BoxShape3D.new()
		shape.size = s[1]
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		body.position = s[0]
		body.add_to_group("arena_edge")
		parent.add_child(body)


## Frame for side `s`: [origin on the edge line at the middle, along (unit), outward (unit)].
static func _frame(half: float, s: int) -> Array:
	match s:
		0: return [Vector3(0, 0, -half), Vector3(1, 0, 0), Vector3(0, 0, -1)]
		1: return [Vector3(half, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)]
		2: return [Vector3(0, 0, half), Vector3(-1, 0, 0), Vector3(0, 0, 1)]
	return [Vector3(-half, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]


static func _ground_y(p: Vector3) -> float:
	return SwampWater.height_at(p.x, p.z)


# ------------------------------------------------------------------ the castle wall

static func _castle_wall(parent: Node3D, half: float, s: int, haze: Color, night: bool) -> void:
	var f := _frame(half, s)
	var o: Vector3 = f[0]
	var along: Vector3 = f[1]
	var out: Vector3 = f[2]
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.5, 0.48, 0.45) if not night else Color(0.34, 0.34, 0.38)
	stone.roughness = 0.95
	var dark := StandardMaterial3D.new()
	dark.albedo_color = stone.albedo_color.darkened(0.35)
	dark.roughness = 1.0
	var slit := StandardMaterial3D.new()
	slit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slit.albedo_color = Color(1.0, 0.7, 0.3) if night else Color(0.06, 0.05, 0.05)
	var root := Node3D.new()
	root.name = "CastleWall"
	parent.add_child(root)
	var base := SwampWater.EDGE_RISE + SwampWater.HILL_HEIGHT * 0.4   # roughly the berm top
	var bottom := -4.0
	var top := base + 18.0
	var len := half * 2.0 + 30.0
	var thick := 7.0
	var mid := o + out * (T + thick * 0.5)
	var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))   # local x along the wall
	_mesh_box(root, mid + Vector3(0, (top + bottom) * 0.5, 0), Vector3(len, top - bottom, thick), basis, stone)
	# a darker plinth course and a walkway lip
	_mesh_box(root, mid + Vector3(0, base + 1.0, 0) - out * (thick * 0.5 + 0.3), Vector3(len, 2.0, 0.6), basis, dark)
	_mesh_box(root, mid + Vector3(0, top - 0.6, 0) - out * (thick * 0.5 + 0.35), Vector3(len, 1.2, 0.7), basis, dark)
	# battlements
	var n := int(len / 3.0)
	for k in n:
		var x := -len * 0.5 + 1.5 + k * 3.0
		if k % 2 == 0:
			_mesh_box(root, mid + along * x + Vector3(0, top + 1.3, 0) - out * (thick * 0.5 - 0.6), Vector3(1.6, 2.6, 1.2), basis, stone)
	# towers along it, with arrow slits
	var towers := int(len / TOWER_EVERY) + 1
	for k in towers:
		var x := -len * 0.5 + 8.0 + k * (len - 16.0) / maxf(1.0, towers - 1)
		var p := mid + along * x - out * 1.0
		var tr := 6.0
		var th := top + 12.0
		var cyl := CylinderMesh.new()
		cyl.top_radius = tr
		cyl.bottom_radius = tr * 1.08
		cyl.height = th - bottom
		cyl.radial_segments = 16
		cyl.material = stone
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.position = p + Vector3(0, (th + bottom) * 0.5, 0)
		root.add_child(mi)
		for q in 10:   # merlons round the top
			var a := TAU * q / 10.0
			_mesh_box(root, p + Vector3(cos(a) * (tr - 0.4), th + 1.2, sin(a) * (tr - 0.4)), Vector3(1.5, 2.4, 1.5), Basis(Vector3.UP, a), stone)
		var roof := CylinderMesh.new()
		roof.top_radius = 0.0
		roof.bottom_radius = tr * 0.8
		roof.height = 9.0
		roof.radial_segments = 16
		roof.material = dark
		var ri := MeshInstance3D.new()
		ri.mesh = roof
		ri.position = p + Vector3(0, th + 2.4 + 4.5, 0)
		root.add_child(ri)
		for q in 3:   # arrow slits facing the arena
			_mesh_box(root, p - out * (tr + 0.05) + Vector3(0, base + 6.0 + q * 7.0, 0), Vector3(0.6, 2.6, 0.2), basis, slit)
	# a few banners hanging down the wall face
	var banner := StandardMaterial3D.new()
	banner.albedo_color = Color(0.55, 0.08, 0.08)
	banner.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in towers - 1:
		var x := -len * 0.5 + 8.0 + (k + 0.5) * (len - 16.0) / maxf(1.0, towers - 1)
		_mesh_box(root, mid + along * x - out * (thick * 0.5 + 0.1) + Vector3(0, top - 5.0, 0), Vector3(4.0, 9.0, 0.1), basis, banner)


static func _mesh_box(parent: Node3D, at: Vector3, size: Vector3, basis: Basis, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.transform = Transform3D(basis, at)
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ the woods

static func _woods(parent: Node3D, half: float, s: int, style: String, night: bool, r: RandomNumberGenerator) -> void:
	var f := _frame(half, s)
	var o: Vector3 = f[0]
	var along: Vector3 = f[1]
	var out: Vector3 = f[2]
	var meshes := _tree_meshes(style, night)
	var xforms: Array = []
	for m in meshes:
		xforms.append([])
	var len := half * 2.0 + 40.0
	for row in TREE_ROWS:
		var d := T + 0.5 + row * 3.4
		var x := -len * 0.5 + r.randf() * TREE_STEP
		while x < len * 0.5:
			var p := o + along * (x + r.randf_range(-0.8, 0.8)) + out * (d + r.randf_range(-0.8, 0.8))
			p.y = _ground_y(o + along * x + out * 1.0) - 0.4
			var sc := r.randf_range(0.85, 1.45) * (1.0 + 0.12 * row)
			var t := Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(sc, sc * r.randf_range(0.9, 1.25), sc)), p)
			xforms[r.randi() % meshes.size()].append(t)
			x += TREE_STEP * r.randf_range(0.8, 1.2)
	for k in meshes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k]
		mm.instance_count = xforms[k].size()
		for i in xforms[k].size():
			mm.set_instance_transform(i, xforms[k][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "EdgeWoods"
		mmi.add_to_group("edge_woods")
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		mmi.set_meta("trees", xforms[k].size())


## Two or three simple tall trees for the edge woods, in the map's look.
static func _tree_meshes(style: String, night: bool) -> Array:
	var out: Array = []
	var dim := 0.6 if night else 1.0
	if style == "forest":
		out.append(_tree(Color(0.62, 0.5, 0.38) * dim, Color(0.3, 0.68, 0.32) * dim, "round", 14.0))
		out.append(_tree(Color(0.55, 0.42, 0.3) * dim, Color(0.18, 0.5, 0.3) * dim, "pine", 17.0))
		out.append(_tree(Color(0.7, 0.62, 0.52) * dim, Color(0.55, 0.78, 0.35) * dim, "round", 12.0))
	else:
		out.append(_tree(Color(0.28, 0.24, 0.2) * dim, Color(0.2, 0.26, 0.14) * dim, "cypress", 16.0))
		out.append(_tree(Color(0.25, 0.22, 0.18) * dim, Color(0.16, 0.22, 0.12) * dim, "round", 13.0))
		out.append(_tree(Color(0.3, 0.27, 0.22) * dim, Color(0.24, 0.3, 0.16) * dim, "pine", 15.0))
	return out


static func _tree(trunk_col: Color, leaf_col: Color, shape: String, h: float) -> ArrayMesh:
	var am := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.35
	trunk.bottom_radius = 0.6
	trunk.height = h * 0.55
	trunk.radial_segments = 7
	_add(am, trunk, Vector3(0, h * 0.275, 0), Vector3.ONE, trunk_col)
	match shape:
		"pine":
			for k in 3:
				var c := CylinderMesh.new()
				c.top_radius = 0.0
				c.bottom_radius = 3.4 - k * 0.8
				c.height = h * 0.38
				c.radial_segments = 8
				_add(am, c, Vector3(0, h * (0.42 + k * 0.17), 0), Vector3.ONE, leaf_col.lightened(0.05 * k))
		"cypress":
			var c := SphereMesh.new()
			c.radius = 2.4
			c.height = h * 0.75
			c.radial_segments = 8
			c.rings = 5
			_add(am, c, Vector3(0, h * 0.68, 0), Vector3.ONE, leaf_col)
		_:
			for k in 3:
				var b := SphereMesh.new()
				b.radius = 3.2 - k * 0.5
				b.height = (3.2 - k * 0.5) * 1.8
				b.radial_segments = 8
				b.rings = 5
				_add(am, b, Vector3((k - 1) * 1.2, h * (0.62 + k * 0.1), (k % 2) * 0.8), Vector3.ONE, leaf_col.lightened(0.06 * k))
	return am


## Append a primitive mesh's triangles to `am`, offset and coloured (its own surface).
static func _add(am: ArrayMesh, prim: PrimitiveMesh, at: Vector3, sc: Vector3, col: Color) -> void:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = verts[i] * sc + at
	arrays[Mesh.ARRAY_VERTEX] = verts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	am.surface_set_material(am.get_surface_count() - 1, m)
