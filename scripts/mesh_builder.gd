class_name MeshBuilder
extends RefCounted
## Merges transformed primitive meshes into one ArrayMesh with per-part vertex colors.
## Vertex alpha is a wind-sway weight used by PROP_SHADER (0 = rigid, 1 = sways fully).

const PROP_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float wind = 1.0;
uniform float char_amount = 0.0;   // 0 = normal, 1 = burnt black
uniform float burning = 0.0;       // ember glow while on fire
varying vec3 lpos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	lpos = VERTEX;
	float w = COLOR.a;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * 1.1 + wp.x * 0.13 + wp.z * 0.09;
	float s = sin(t + VERTEX.y * 0.15) * 0.10 + sin(t * 2.3 + VERTEX.x) * 0.04;
	VERTEX.x += s * w * wind;
	VERTEX.z += s * 0.7 * w * wind;
}
void fragment() {
	// Never let a bad normal through (NaN pixels bloom into white flashes on some GPUs)
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	// Vertex colors are authored in sRGB
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	// Charring creeps in patchily, then covers everything
	float patch = noise(lpos * 2.3);
	float c = smoothstep(patch * 0.6, patch * 0.6 + 0.4, char_amount);
	col = mix(col, vec3(0.03, 0.026, 0.022), c);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	if (burning > 0.0) {
		float e = noise(lpos * 4.0 + vec3(0.0, -TIME * 2.0, 0.0)) * 0.7 + noise(lpos * 11.0 - vec3(TIME)) * 0.3;
		EMISSION = vec3(1.0, 0.32, 0.04) * smoothstep(0.45, 0.85, e) * burning * 2.2;
	}
}
"""

static var _prop_material: ShaderMaterial

var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()


static func prop_material() -> ShaderMaterial:
	if _prop_material == null:
		var sh := Shader.new()
		sh.code = PROP_SHADER
		_prop_material = ShaderMaterial.new()
		_prop_material.shader = sh
	return _prop_material


func add(arrays: Array, xf: Transform3D, color: Color) -> void:
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


## A tapered cylinder between two points.
func limb(a: Vector3, b: Vector3, r_a: float, r_b: float, color: Color, seg := 8) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		return
	var up := d / len
	var side := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := side.cross(up).normalized()
	var z := x.cross(up)
	var basis := Basis(x, up, z)
	add(cyl(r_b, r_a, len, seg), Transform3D(basis, (a + b) * 0.5), color)


func commit(material: Material = null) -> ArrayMesh:
	# Degenerate parts (zero-radius tips, collapsed triangles) can carry zero/NaN normals;
	# on some GPUs those shade as NaN pixels that the glow blows up into flashing white dots.
	for k in _norms.size():
		var n := _norms[k]
		if not n.is_finite() or n.length_squared() < 1e-8:
			_norms[k] = Vector3.UP
		else:
			_norms[k] = n.normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_COLOR] = _cols
	arrays[Mesh.ARRAY_INDEX] = _idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material if material else prop_material())
	return mesh


static func sphere(r: float, seg := 10, rings := 6) -> Array:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m.get_mesh_arrays()


static func cyl(top: float, bottom: float, h: float, seg := 8, rings := 1) -> Array:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = rings
	return m.get_mesh_arrays()


static func cone(r: float, h: float, seg := 6) -> Array:
	return cyl(0.0, r, h, seg)


static func box(size: Vector3) -> Array:
	var m := BoxMesh.new()
	m.size = size
	return m.get_mesh_arrays()
