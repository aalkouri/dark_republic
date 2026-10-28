class_name LightningFx
extends MultiMeshInstance3D
## Jagged lightning bolts for Chain Lightning, Overcharge, Thunderclap and Storm Lord: every
## bolt is a polyline of short stretched boxes in one additive MultiMesh (a white-hot core plus
## a wide coloured glow per segment), flickering and fading over its short life.

const MAX := 6000
const STRIDE := 16   # 12 transform + 4 colour

var _a := PackedVector3Array()
var _b := PackedVector3Array()
var _w := PackedFloat32Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _col: Array[Color] = []
var _n := 0
var _buf := PackedFloat32Array()


func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_fog = true
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = box
	multimesh.instance_count = MAX
	multimesh.visible_instance_count = 0
	custom_aabb = AABB(Vector3(-500, -100, -500), Vector3(1000, 300, 1000))
	_a.resize(MAX)
	_b.resize(MAX)
	_w.resize(MAX)
	_age.resize(MAX)
	_life.resize(MAX)
	_col.resize(MAX)
	_buf.resize(MAX * STRIDE)


## A jagged bolt from `from` to `to`. `jag` = sideways wander as a fraction of the length.
func bolt(from: Vector3, to: Vector3, color: Color, width := 0.07, life := 0.16, jag := 0.18, fork := true) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.01:
		return
	var segs := clampi(int(length / 0.7), 3, 24)
	var dir := d / length
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	var prev := from
	for k in range(1, segs + 1):
		var t := float(k) / segs
		var p := from + d * t
		if k < segs:
			var amp := length * jag * sin(t * PI) * 0.5
			p += side * randf_range(-amp, amp) + up * randf_range(-amp, amp)
		_seg(prev, p, color, width, life)
		if fork and k < segs - 1 and randf() < 0.18:   # small side branches
			var bd := (side * randf_range(-1, 1) + up * randf_range(-1, 1) + dir).normalized()
			var bl := length * randf_range(0.08, 0.2)
			_seg(p, p + bd * bl, color, width * 0.6, life * 0.8)
		prev = p


func _seg(a: Vector3, b: Vector3, color: Color, width: float, life: float) -> void:
	for layer in 2:   # glow, then core
		var i := _n
		if _n < MAX:
			_n += 1
		else:
			i = randi() % MAX
		_a[i] = a
		_b[i] = b
		_w[i] = width * (2.6 if layer == 0 else 1.0)
		_col[i] = Color(color, 0.3) if layer == 0 else Color(color.lerp(Color.WHITE, 0.75), 1.0)
		_age[i] = 0.0
		_life[i] = life


func count() -> int:
	return _n


func _physics_process(dt: float) -> void:   # ages with game time (pauses with the game)
	var i := 0
	while i < _n:
		_age[i] += dt
		if _age[i] >= _life[i]:
			var last := _n - 1
			_a[i] = _a[last]
			_b[i] = _b[last]
			_w[i] = _w[last]
			_age[i] = _age[last]
			_life[i] = _life[last]
			_col[i] = _col[last]
			_n -= 1
			continue
		var a := _a[i]
		var b := _b[i]
		var d := b - a
		var z := d
		var x := d.cross(Vector3.UP)
		if x.length_squared() < 0.0001:
			x = Vector3.RIGHT
		x = x.normalized() * _w[i]
		var y := x.cross(d).normalized() * _w[i]
		var c := (a + b) * 0.5
		var o := i * STRIDE
		_buf[o] = x.x; _buf[o + 1] = y.x; _buf[o + 2] = z.x; _buf[o + 3] = c.x
		_buf[o + 4] = x.y; _buf[o + 5] = y.y; _buf[o + 6] = z.y; _buf[o + 7] = c.y
		_buf[o + 8] = x.z; _buf[o + 9] = y.z; _buf[o + 10] = z.z; _buf[o + 11] = c.z
		var f := 1.0 - _age[i] / _life[i]
		var flick := 0.7 + 0.3 * sin(_age[i] * 90.0 + float(i))
		var col := _col[i]
		_buf[o + 12] = col.r
		_buf[o + 13] = col.g
		_buf[o + 14] = col.b
		_buf[o + 15] = col.a * f * flick
		i += 1
	multimesh.buffer = _buf
	multimesh.visible_instance_count = _n
