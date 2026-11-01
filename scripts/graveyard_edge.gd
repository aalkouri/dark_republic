class_name GraveyardEdge
extends RefCounted
## The edge of the Haunted Graveyard: on all four sides a high cemetery wall (a stone plinth wall
## with tall wrought-iron railings between stone piers, urns on every eighth pier) following the
## berm, with the great cemetery gate (closed, lanterns lit) in the middle of the south side.
## Beyond it, dead woods: rows of bare black trees against the night sky.
## Invisible walls keep you in (ArenaEdge).

const PIER_EVERY := 3.2
const WALL_H := 1.1
const RAIL_H := 2.0
const WOOD_ROWS := 3
const WOOD_STEP := 4.2


static func build(parent: Node3D, half: float, _haze: Color) -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()
	ArenaEdge._collision(parent, half)
	var piers: Array[Transform3D] = []
	var urns: Array[Transform3D] = []
	var walls: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	var trees: Array = [[], [], []]
	for s in 4:
		var f := ArenaEdge._frame(half, s)
		var o: Vector3 = f[0]
		var along: Vector3 = f[1]
		var out: Vector3 = f[2]
		var base := o + out * 0.9
		var len := half * 2.0 + 4.0
		var n := int(len / PIER_EVERY)
		var yaw := atan2(along.x, along.z) - PI * 0.5   # local +X runs along the side
		var basis := Basis(Vector3.UP, yaw)
		for k in n + 1:
			var x := -len * 0.5 + k * PIER_EVERY
			var p := base + along * x
			p.y = _ground(p)
			var is_gate := s == 2 and absf(x) < 4.0
			if not is_gate:
				if k % 8 == 0:
					urns.append(Transform3D(basis, p))
				else:
					piers.append(Transform3D(basis, p))
			if k == n:
				break
			var q := base + along * (x + PIER_EVERY)
			q.y = _ground(q)
			if s == 2 and absf(x + PIER_EVERY * 0.5) < 4.4:
				continue   # the gateway
			var a := p + along * 0.4
			var b := q - along * 0.4
			var y := minf(p.y, q.y)
			var ax := Vector3(b.x - a.x, 0, b.z - a.z) / 2.4
			walls.append(Transform3D(Basis(ax, Vector3.UP, ax.cross(Vector3.UP).normalized()), Vector3(a.x, y, a.z)))
			rails.append(Transform3D(Basis(ax, Vector3.UP, ax.cross(Vector3.UP).normalized()), Vector3(a.x, y + WALL_H + 0.16, a.z)))
		# the dead woods beyond
		for row in WOOD_ROWS:
			var d := 5.0 + row * 4.5
			var x := -len * 0.5 - 10.0 + r.randf() * WOOD_STEP
			while x < len * 0.5 + 10.0:
				var p := base + along * (x + r.randf_range(-1.0, 1.0)) + out * (d + r.randf_range(-1.2, 1.2))
				p.y = _ground(base + along * x) - 0.3
				var sc := r.randf_range(0.9, 1.5) * (1.0 + 0.15 * row)
				(trees[r.randi() % 3] as Array).append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(sc, sc * r.randf_range(0.9, 1.3), sc)), p))
				x += WOOD_STEP * r.randf_range(0.7, 1.2)
	_mm(parent, GraveyardProps.wall_pier(WALL_H + RAIL_H + 0.3), piers, "EdgeWall")
	_mm(parent, GraveyardProps.wall_pier(WALL_H + RAIL_H + 0.3, true), urns, "EdgeWall")
	_mm(parent, GraveyardProps.wall_section(2.4, WALL_H), walls, "EdgeWall")
	_mm(parent, GraveyardProps.fence_panel(RAIL_H, 2.4), rails, "EdgeWall")
	for k in 3:
		var arr: Array[Transform3D] = []
		for t in trees[k]:
			arr.append(t)
		_mm(parent, _bare_tree(k), arr, "EdgeWoods")
	# the great gate
	var gf := ArenaEdge._frame(half, 2)
	var gp: Vector3 = gf[0] + (gf[2] as Vector3) * 0.9
	gp.y = _ground(gp)
	var gate := GraveyardProps.gate(5.6, 3.4)
	var mi := MeshInstance3D.new()
	mi.mesh = gate["mesh"]
	mi.name = "CemeteryGate"   # no-i18n
	mi.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3(1.25, 1.25, 1.25)), gp - Vector3(0, 0.2, 0))
	mi.add_to_group("edge_wall")
	parent.add_child(mi)


static func _ground(p: Vector3) -> float:
	return SwampWater.height_at(p.x, p.z)


static func _mm(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], node_name: String) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = node_name
	mmi.add_to_group("edge_wall" if node_name == "EdgeWall" else "edge_woods")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.set_meta("count", xforms.size())
	parent.add_child(mmi)


## A cheap bare tree for the woods beyond the wall: a crooked trunk and a spray of branches.
static func _bare_tree(k: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 990 + k
	var mb := MeshBuilder.new()
	var bark := Color(0.12, 0.11, 0.1, 0.0)
	var h := rng.randf_range(10.0, 15.0)
	var p := Vector3.ZERO
	var dir := Vector3.UP
	for s in 3:
		var q := p + dir * h * 0.25
		mb.limb(p, q, 0.45 - s * 0.1, 0.35 - s * 0.1, bark, 6)
		p = q
		dir = (dir + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))).normalized()
	for b in 7:
		var a := TAU * b / 7.0 + rng.randf()
		var from := p - dir * rng.randf_range(0.0, h * 0.35)
		var bd := Vector3(cos(a), rng.randf_range(0.4, 1.0), sin(a)).normalized()
		var mid := from + bd * h * rng.randf_range(0.15, 0.25)
		mb.limb(from, mid, 0.14, 0.07, bark, 4)
		for t in 2:
			var td := (bd + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.0, 0.6), rng.randf_range(-0.7, 0.7))).normalized()
			mb.limb(mid, mid + td * h * 0.15, 0.06, 0.01, bark, 3)
	return mb.commit()
