class_name FxManager
extends Node3D
## Pooled, high-frequency visual effects drawn with MultiMeshes (no per-effect nodes):
##  - bursts: expanding, fading fire spheres (burn explosions, meteor impact debris)
##  - ash:    flat flakes left behind by the fire wizard that fade within ~1 s
## Per-instance alpha comes from the instance color.

const BURST_MAX := 160
const ASH_MAX := 160
const STRIDE := 16
const ASH_LIFE := 1.1

var _b_pos := PackedVector3Array()
var _b_rad := PackedFloat32Array()
var _b_age := PackedFloat32Array()
var _b_life := PackedFloat32Array()
var _b_col: Array[Color] = []
var _b_count := 0
var _b_buf := PackedFloat32Array()
var _b_mm: MultiMesh

var _a_pos := PackedVector3Array()
var _a_rot := PackedFloat32Array()
var _a_size := PackedFloat32Array()
var _a_age := PackedFloat32Array()
var _a_count := 0
var _a_next := 0
var _a_buf := PackedFloat32Array()
var _a_mm: MultiMesh


func _ready() -> void:
	_b_pos.resize(BURST_MAX)
	_b_rad.resize(BURST_MAX)
	_b_age.resize(BURST_MAX)
	_b_life.resize(BURST_MAX)
	_b_col.resize(BURST_MAX)
	_b_buf.resize(BURST_MAX * STRIDE)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 14
	sphere.rings = 7
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.vertex_color_use_as_albedo = true
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sphere.material = bm
	_b_mm = _make_mm(sphere, BURST_MAX)

	_a_pos.resize(ASH_MAX)
	_a_rot.resize(ASH_MAX)
	_a_size.resize(ASH_MAX)
	_a_age.resize(ASH_MAX)
	_a_buf.resize(ASH_MAX * STRIDE)
	var flake := PlaneMesh.new()
	flake.size = Vector2(1.0, 1.0)
	var am := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Soft round ash smudge; instance color alpha = fade, red channel = ember glow.
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, 0.35, d);
	vec3 ash = vec3(0.09, 0.08, 0.08);
	vec3 ember = vec3(1.0, 0.35, 0.05);
	float glow = COLOR.r * smoothstep(0.6, 0.0, d);
	ALBEDO = mix(ash, ember, glow);
	ALPHA = a * COLOR.a;
}
"""
	am.shader = sh
	flake.material = am
	_a_mm = _make_mm(flake, ASH_MAX)


func _make_mm(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 200, 1000))
	add_child(mmi)
	return mm


func burst(at: Vector3, radius: float, color := Color(1.0, 0.45, 0.1), life := 0.35) -> void:
	if _b_count >= BURST_MAX:
		return
	var i := _b_count
	_b_count += 1
	_b_pos[i] = at
	_b_rad[i] = radius
	_b_age[i] = 0.0
	_b_life[i] = life
	_b_col[i] = color


func ash(at: Vector3) -> void:
	var i: int
	if _a_count < ASH_MAX:
		i = _a_count
		_a_count += 1
	else:
		i = _a_next   # overwrite the oldest
		_a_next = (_a_next + 1) % ASH_MAX
	_a_pos[i] = at
	_a_rot[i] = randf() * TAU
	_a_size[i] = randf_range(0.28, 0.42)
	_a_age[i] = 0.0


func _process(dt: float) -> void:
	# Bursts
	var i := 0
	while i < _b_count:
		_b_age[i] += dt
		var tt := _b_age[i] / _b_life[i]
		if tt >= 1.0:
			_b_count -= 1
			_b_pos[i] = _b_pos[_b_count]
			_b_rad[i] = _b_rad[_b_count]
			_b_age[i] = _b_age[_b_count]
			_b_life[i] = _b_life[_b_count]
			_b_col[i] = _b_col[_b_count]
			continue
		var r := _b_rad[i] * (0.35 + 0.65 * (1.0 - (1.0 - tt) * (1.0 - tt)))
		var c: Color = _b_col[i]
		var hot := 1.0 - tt
		_put(_b_buf, i, Basis.from_scale(Vector3.ONE * r), _b_pos[i],
			Color(c.r, c.g + 0.4 * hot * hot, c.b + 0.2 * hot * hot * hot, 0.75 * hot))
		i += 1
	_b_mm.buffer = _b_buf
	_b_mm.visible_instance_count = _b_count

	# Ash (fixed slots; dead flakes are scaled to zero)
	for k in _a_count:
		_a_age[k] += dt
		var tt := _a_age[k] / ASH_LIFE
		if tt >= 1.0:
			_put(_a_buf, k, Basis.from_scale(Vector3.ZERO), _a_pos[k], Color(0, 0, 0, 0))
			continue
		var s := _a_size[k] * (1.0 - 0.4 * tt)
		var basis := Basis(Vector3.UP, _a_rot[k]).scaled(Vector3(s, 1.0, s))
		var ember := maxf(0.0, 1.0 - tt * 3.5)
		_put(_a_buf, k, basis, _a_pos[k], Color(ember, 0, 0, 0.85 * (1.0 - tt * tt)))
	_a_mm.buffer = _a_buf
	_a_mm.visible_instance_count = _a_count


static func _put(buf: PackedFloat32Array, i: int, b: Basis, o: Vector3, c: Color) -> void:
	var k := i * STRIDE
	buf[k] = b.x.x; buf[k + 1] = b.y.x; buf[k + 2] = b.z.x; buf[k + 3] = o.x
	buf[k + 4] = b.x.y; buf[k + 5] = b.y.y; buf[k + 6] = b.z.y; buf[k + 7] = o.y
	buf[k + 8] = b.x.z; buf[k + 9] = b.y.z; buf[k + 10] = b.z.z; buf[k + 11] = o.z
	buf[k + 12] = c.r; buf[k + 13] = c.g; buf[k + 14] = c.b; buf[k + 15] = c.a
