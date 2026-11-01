class_name DesertEdge
extends RefCounted
## The edge of the Desert: instead of woods and a castle wall, the arena is ringed by towering
## dunes (a band of sand rising 20-40 m beyond the invisible walls, crests rolling along it),
## with flat-topped sandstone mesas standing above the dunes on one side and, far off on the
## horizon, the hazy pyramids of another necropolis (they keep their distance like the sky, the
## way the castle does on the other outdoor maps).

const T := 2.0
const BAND := 130.0           # how far the edge dunes run out past the wall
const STEP_ALONG := 4.0
const STEP_OUT := 3.0


static func build(parent: Node3D, half: float, night: bool) -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()   # its own dice: a new look each load without moving the seeded layout
	_collision(parent, half)
	var mat: Material = SwampWater.current.ground_mat if SwampWater.current != null and SwampWater.current.ground_mat != null else StandardMaterial3D.new()
	for s in 4:
		_dunes(parent, half, s, mat, r)
	var mesa_side := r.randi() % 4
	_mesas(parent, half, mesa_side, night, r)
	var h := Horizon.new()
	h.name = "DistantPyramids"   # no-i18n
	h.bearing = [-PI * 0.5, 0.0, PI * 0.5, PI][(mesa_side + 2) % 4] + r.randf_range(-0.4, 0.4)
	parent.add_child(h)
	h.build(WorldBuilder.edge_haze, night)


## Invisible walls, tall enough for the highest dune and any jump from a pyramid.
static func _collision(parent: Node3D, half: float) -> void:
	var top := 90.0
	var bottom := -20.0
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


static func _frame(half: float, s: int) -> Array:
	match s:
		0: return [Vector3(0, 0, -half), Vector3(1, 0, 0), Vector3(0, 0, -1)]
		1: return [Vector3(half, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)]
		2: return [Vector3(0, 0, half), Vector3(-1, 0, 0), Vector3(0, 0, 1)]
	return [Vector3(-half, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]


## A band of great dunes along side `s`: from just inside the wall (below the ground, so no seam
## shows) up to crests 20-40 m high and down the far side.
static func _dunes(parent: Node3D, half: float, s: int, mat: Material, r: RandomNumberGenerator) -> void:
	var f := _frame(half, s)
	var o: Vector3 = f[0]
	var along: Vector3 = f[1]
	var out: Vector3 = f[2]
	var n := FastNoiseLite.new()
	n.seed = r.randi()
	n.frequency = 0.012
	var len := half * 2.0 + BAND * 2.0
	var na := int(len / STEP_ALONG) + 1
	var no := int((BAND + 6.0) / STEP_OUT) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for i in na:
		var a := -len * 0.5 + i * STEP_ALONG
		var row := []
		# the arena's ground right at the wall (clamped into the arena for the corners)
		var edge_p := o + along * clampf(a, -half + 1.0, half - 1.0) - out * 1.0
		var g0 := SwampWater.height_at(edge_p.x, edge_p.z)
		var crest := 22.0 + 18.0 * (n.get_noise_1d(a * 0.6) * 0.5 + 0.5)
		var crest_at := 38.0 + 22.0 * n.get_noise_1d(a * 0.4 + 50.0)
		for j in no:
			var d := -6.0 + j * STEP_OUT
			var up := smoothstep(-2.0, crest_at, d)
			var down := 1.0 - smoothstep(crest_at + 10.0, crest_at + 70.0, d) * 0.55
			var ripple := n.get_noise_2d(a * 1.5, d * 2.0) * 2.5 * up
			var h := g0 - 1.0 + (crest * pow(up, 1.6) + ripple) * down
			var p := o + along * a + out * d
			p.y = h
			row.append(p)
		pts.append(row)
	for i in na - 1:
		for j in no - 1:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i][j + 1]
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	# Normals face up whatever the winding (the band runs either way round)
	var arr := mesh.surface_get_arrays(0)
	var nm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for k in nm.size():
		if nm[k].y < 0.0:
			nm[k] = -nm[k]
	arr[Mesh.ARRAY_NORMAL] = nm
	var m2 := ArrayMesh.new()
	m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = m2
	mi.material_override = mat
	mi.name = "EdgeDunes"   # no-i18n
	mi.add_to_group("edge_dunes")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Flat-topped mesas of banded red and buff sandstone standing beyond the dunes on side `s`.
static func _mesas(parent: Node3D, half: float, s: int, night: bool, r: RandomNumberGenerator) -> void:
	var f := _frame(half, s)
	var o: Vector3 = f[0]
	var along: Vector3 = f[1]
	var out: Vector3 = f[2]
	var mb := MeshBuilder.new()
	for k in 7:
		var a := r.randf_range(-half * 1.1, half * 1.1)
		var d := r.randf_range(110.0, 150.0)
		var base := o + along * a + out * d
		base.y = 0.0
		var w := r.randf_range(18.0, 36.0)
		var h := r.randf_range(38.0, 60.0)
		var layers := r.randi_range(5, 8)
		var y := -6.0
		for l in layers:
			var lh := h / layers
			var rr := w * (1.0 + 0.12 * sin(l * 1.9)) * (0.82 if l == layers - 1 else 1.0)
			var col := Color(0.66, 0.38, 0.26, 0.0) if l % 2 == 0 else Color(0.8, 0.56, 0.38, 0.0)
			if night:
				col = col.darkened(0.3)
			mb.add(ForestProps._lumpy(rr, r), Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1.0, lh / (rr * 1.5), r.randf_range(0.6, 1.0))), base + Vector3(0, y + lh * 0.5, 0)), col)
			y += lh * 0.95
		# a talus of fallen rock round its foot
		mb.add(ForestProps._lumpy(w * 1.3, r), Transform3D(Basis.from_scale(Vector3(1.0, 0.22, 0.8)), base + Vector3(0, 2.0, 0)), Color(0.72, 0.5, 0.34, 0.0))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(DesertProps.stone_material())
	mi.name = "Mesas"   # no-i18n
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## The far pyramids: hazy silhouettes on the skyline in one direction, always the same distance
## away (they follow the camera, like the sky), their bases lost in the heat haze.
class Horizon extends Node3D:
	const DISTANCE := 340.0
	var bearing := 0.0

	func build(haze: Color, night: bool) -> void:
		var sh := Shader.new()
		sh.code = DistantCastle.SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("haze", haze)
		mat.set_shader_parameter("body", haze.darkened(0.45 if night else 0.22).lerp(Color(0.62, 0.48, 0.34), 0.0 if night else 0.25))
		mat.set_shader_parameter("rim", 0.0 if night else 0.08)
		mat.set_shader_parameter("mist_top", 30.0)
		for p in [[Vector3(-70, 0, 0), 62.0], [Vector3(30, 0, -40), 88.0], [Vector3(140, 0, 20), 46.0], [Vector3(-160, 0, -30), 30.0]]:
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			var hw: float = p[1]
			c.bottom_radius = hw * 1.414
			c.height = hw * 1.25
			c.radial_segments = 4
			var mi := MeshInstance3D.new()
			mi.mesh = c
			mi.material_override = mat
			mi.position = (p[0] as Vector3) + Vector3(0, hw * 0.625 - 10.0, 0)
			mi.rotation.y = PI / 4 + 0.3
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)

	func _process(_dt: float) -> void:
		var cam := get_viewport().get_camera_3d()
		var from := cam.global_position if cam != null else Vector3.ZERO
		var dir := Vector3(cos(bearing), 0.0, sin(bearing))
		global_position = Vector3(from.x, -4.0, from.z) + dir * DISTANCE
		rotation.y = atan2(-dir.x, -dir.z)
