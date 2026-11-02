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
uniform float glow = 0.0;          // self-lit parts (magical forest): emission = colour * glow
uniform float up_normal = 0.0;     // 1 = light it as if facing the sky (grass, ferns: no dark back faces)
uniform float occludes = 1.0;      // 0 = never thins out between the camera and the player
// The camera and the player's chest (set every frame by the player): props in between thin out
global uniform vec3 occl_cam;
global uniform vec3 occl_target;
varying vec3 lpos;
varying vec3 wpos;
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
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
// 4x4 ordered dither threshold (0..1) for this pixel
float bayer(vec2 fc) {
	ivec2 p = ivec2(mod(fc, 4.0));
	int i = p.x + p.y * 4;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}
void fragment() {
	// Never let a bad normal through (NaN pixels bloom into white flashes on some GPUs)
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	if (up_normal > 0.5) { NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz); }
	// See-through: anything between the camera and the player (a cone around the line from the
	// camera to their chest) is dithered away to about a quarter, so trees never hide you. Only in
	// the camera's own pass (perspective), so shadows stay whole.
	if (occludes > 0.5 && up_normal < 0.5 && PROJECTION_MATRIX[3][3] == 0.0) {
		vec3 seg = occl_target - occl_cam;
		float len2 = max(dot(seg, seg), 1e-4);
		float t = dot(wpos - occl_cam, seg) / len2;
		if (t > 0.0 && t < 0.97) {
			float d = length(wpos - (occl_cam + seg * t));
			float r = mix(2.4, 1.3, t);
			float fade = (1.0 - smoothstep(r * 0.65, r, d)) * smoothstep(0.0, 0.06, t);
			if (fade * 0.75 > bayer(FRAGCOORD.xy)) { discard; }
		}
	}
	// Vertex colors are authored in sRGB
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	// Charring creeps in patchily, then covers everything
	float patch = noise(lpos * 2.3);
	float c = smoothstep(patch * 0.6, patch * 0.6 + 0.4, char_amount);
	col = mix(col, vec3(0.03, 0.026, 0.022), c);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	EMISSION = col * glow * (1.0 - c);
	if (burning > 0.0) {
		float e = noise(lpos * 4.0 + vec3(0.0, -TIME * 2.0, 0.0)) * 0.7 + noise(lpos * 11.0 - vec3(TIME)) * 0.3;
		EMISSION = vec3(1.0, 0.32, 0.04) * smoothstep(0.45, 0.85, e) * burning * 2.2;
	}
}
"""

static var _prop_material: ShaderMaterial
static var _glow_material: ShaderMaterial

var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()


static func prop_material() -> ShaderMaterial:
	if _prop_material == null:
		_register_occlusion()
		var sh := Shader.new()
		sh.code = PROP_SHADER
		_prop_material = ShaderMaterial.new()
		_prop_material.shader = sh
	return _prop_material


## The shader globals the see-through effect reads (registered once, before the shader compiles).
static var _occl_registered := false

static func _register_occlusion() -> void:
	if _occl_registered:
		return
	_occl_registered = true
	for n in ["occl_cam", "occl_target"]:
		RenderingServer.global_shader_parameter_add(n, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0, -1000, 0))


## Where the camera and the player are this frame, for the see-through effect.
static func set_occlusion(cam_pos: Vector3, target: Vector3) -> void:
	_register_occlusion()
	RenderingServer.global_shader_parameter_set("occl_cam", cam_pos)
	RenderingServer.global_shader_parameter_set("occl_target", target)


## The prop material with self-lit colours (glowing mushrooms, runes, lanterns).
static var _foliage_material: ShaderMaterial

## The prop material for ground foliage (grass, ferns, flowers): always lit from above.
static func foliage_material() -> ShaderMaterial:
	if _foliage_material == null:
		_foliage_material = prop_material().duplicate() as ShaderMaterial
		_foliage_material.set_shader_parameter("up_normal", 1.0)
	return _foliage_material


static func glow_material() -> ShaderMaterial:
	if _glow_material == null:
		_glow_material = prop_material().duplicate() as ShaderMaterial
		_glow_material.set_shader_parameter("glow", 2.2)
	return _glow_material


func is_empty() -> bool:
	return _verts.is_empty()


## Append these parts to `mesh` as another surface (e.g. a glowing one).
func commit_into(mesh: ArrayMesh, material: Material) -> void:
	if _verts.is_empty():
		return
	var m := commit(material)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(0))
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


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
