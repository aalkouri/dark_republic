class_name GoblinMesh
extends RefCounted
## Builds the shared goblin mesh used by every enemy instance (one MultiMesh draw).
## Short and pot-bellied with stubby legs and comically large ears; about half the
## wizard's height at scale 1. Origin at the feet, facing +Z.
##
## Vertex color = part color; vertex alpha marks how the part is tinted per instance:
##   1.0 clothing (takes the enemy type's color), 0.5 skin, 0.0 fixed (eyes, teeth, nails).

const HEIGHT := 0.95   # top of head at scale 1 (ears stick out sideways)

const SKIN := Color(0.42, 0.64, 0.24, 0.5)
const EAR_INNER := Color(0.85, 0.5, 0.5, 0.5)
const CLOTH := Color(1, 1, 1, 1.0)
const EYE := Color(1.0, 0.9, 0.2, 0.0)
const PUPIL := Color(0.05, 0.03, 0.02, 0.0)
const TOOTH := Color(0.95, 0.92, 0.8, 0.0)
const DARK := Color(0.18, 0.12, 0.08, 0.0)

const SHADER := """
shader_type spatial;
// Per-instance data comes from INSTANCE_CUSTOM: rgb = clothing tint,
// a = burn (0..1) + 2 if hit-flashing + 4 if epic.
varying vec3 tint;
varying float burn;
varying float flash;
varying float epic;

void vertex() {
	float a = INSTANCE_CUSTOM.a;
	epic = step(3.5, a);
	a -= epic * 4.0;
	flash = step(1.5, a);
	a -= flash * 2.0;
	burn = clamp(a, 0.0, 1.0);
	tint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec3 col = COLOR.rgb;
	float mask = COLOR.a;
	float cloth = step(0.75, mask);
	float skin = step(0.25, mask) * (1.0 - cloth);
	col = mix(col, tint, cloth);
	col = mix(col, col * vec3(0.95, 0.55, 1.35), skin * epic * 0.85);
	col = mix(col, vec3(1.0, 0.42, 0.08), burn * 0.65 * (cloth + skin));
	EMISSION = vec3(1.0, 0.32, 0.04) * burn * 0.9 + vec3(0.45, 0.1, 0.8) * epic * 0.25 * (cloth + skin);
	// Hit: a brief reddish tint. (A pure-white flash read as bright white dots on goblins
	// far away in the fog.)
	ALBEDO = mix(col, col * vec3(1.45, 0.55, 0.45), flash * 0.6);
	ROUGHNESS = 0.85;
}
"""

var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()


static func build() -> ArrayMesh:
	var g := GoblinMesh.new()
	g._build()
	return g._commit()


func _build() -> void:
	# Stubby legs and big flat feet
	for side in [-1.0, 1.0]:
		_add(_cyl(0.065, 0.075, 0.2, 8), Transform3D(Basis(), Vector3(0.11 * side, 0.12, 0.0)), SKIN)
		_add(_box(Vector3(0.13, 0.06, 0.22)), Transform3D(Basis(), Vector3(0.12 * side, 0.03, 0.05)), SKIN)
	# Pot belly + loincloth
	_add(_sphere(0.27, 12, 7), Transform3D(Basis.from_scale(Vector3(1.0, 0.95, 0.9)), Vector3(0, 0.36, 0)), SKIN)
	_add(_cyl(0.245, 0.29, 0.16, 14), Transform3D(Basis(), Vector3(0, 0.25, 0)), CLOTH)
	# Arms hanging forward, with little claws
	for side in [-1.0, 1.0]:
		var arm := Basis(Vector3(0, 0, 1), deg_to_rad(18.0 * side)) * Basis(Vector3(1, 0, 0), deg_to_rad(-25.0))
		_add(_cyl(0.045, 0.055, 0.32, 8), Transform3D(arm, Vector3(0.27 * side, 0.36, 0.05)), SKIN)
		_add(_sphere(0.06, 8, 4), Transform3D(Basis(), Vector3(0.33 * side, 0.21, 0.12)), SKIN)
	# Big head
	var head_y := 0.68
	_add(_sphere(0.26, 14, 8), Transform3D(Basis.from_scale(Vector3(1.05, 0.95, 1.0)), Vector3(0, head_y, 0.02)), SKIN)
	# Comically large ears: long, flat, pointing out and slightly up/back
	for side in [-1.0, 1.0]:
		var ear := Basis(Vector3(0, 1, 0), deg_to_rad(20.0 * side)) \
			* Basis(Vector3(0, 0, 1), deg_to_rad(-72.0 * side)) \
			* Basis.from_scale(Vector3(1.0, 1.0, 0.28))
		var at := Vector3(0.22 * side, head_y + 0.06, -0.02)
		var length := 0.85
		var ear_x := Transform3D(ear, at + ear * Vector3(0, length * 0.5, 0))
		_add(_cone(0.2, length, 12), ear_x, SKIN)
		var inner := Transform3D(ear, at + ear * Vector3(0, length * 0.42, 0.12)).scaled_local(Vector3(0.62, 0.8, 0.5))
		_add(_cone(0.2, length, 10), inner, EAR_INNER)
	# Long pointy nose
	_add(_cone(0.07, 0.2, 8), Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(80.0)), Vector3(0, head_y - 0.02, 0.33)), SKIN)
	# Eyes
	for side in [-1.0, 1.0]:
		_add(_sphere(0.065, 10, 6), Transform3D(Basis(), Vector3(0.1 * side, head_y + 0.06, 0.2)), EYE)
		_add(_sphere(0.032, 8, 4), Transform3D(Basis(), Vector3(0.1 * side, head_y + 0.06, 0.26)), PUPIL)
		# Angry brow
		var brow := Basis(Vector3(0, 0, 1), deg_to_rad(-22.0 * side))
		_add(_box(Vector3(0.12, 0.03, 0.05)), Transform3D(brow, Vector3(0.1 * side, head_y + 0.14, 0.22)), DARK)
	# Grin with two teeth
	_add(_box(Vector3(0.2, 0.03, 0.04)), Transform3D(Basis(), Vector3(0, head_y - 0.12, 0.24)), DARK)
	for side in [-1.0, 1.0]:
		_add(_box(Vector3(0.035, 0.05, 0.03)), Transform3D(Basis(), Vector3(0.05 * side, head_y - 0.095, 0.255)), TOOTH)


# ------------------------------------------------------------------ assembly

func _add(arrays: Array, xf: Transform3D, color: Color) -> void:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base := _verts.size()
	var nb := xf.basis.inverse().transposed()
	for k in v.size():
		_verts.append(xf * v[k])
		_norms.append((nb * n[k]).normalized())
		_cols.append(color)
	for k in idx:
		_idx.append(base + k)


func _commit() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_COLOR] = _cols
	arrays[Mesh.ARRAY_INDEX] = _idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mesh.surface_set_material(0, mat)
	return mesh


static func _sphere(r: float, seg: int, rings: int) -> Array:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m.get_mesh_arrays()


static func _cyl(top: float, bottom: float, h: float, seg: int) -> Array:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m.get_mesh_arrays()


static func _cone(r: float, h: float, seg: int) -> Array:
	return _cyl(0.0, r, h, seg)


static func _box(size: Vector3) -> Array:
	var m := BoxMesh.new()
	m.size = size
	return m.get_mesh_arrays()
