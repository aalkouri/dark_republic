class_name CorpseManager
extends Node3D
## Dead goblins: they play the baked death animation (falling backwards), lie on the ground,
## then sink out of sight, gone LIFETIME seconds after death. One MultiMesh with the shared
## goblin mesh; if the pool fills (mass kills), the oldest corpse is recycled.

const LIFETIME := 3.0
const FALL_TIME := 0.35      # (kept for tests) time until the body is mostly down
const DEATH_SPEED := 1.6     # death clip playback speed
const SINK_TIME := 0.45      # last part of the lifetime: sink into the ground
const MAX := 600
const STRIDE := 20           # 12 transform + 4 color + 4 custom (tint, fx)
const CHAR := Color(0.16, 0.12, 0.1)

var _pos := PackedVector3Array()
var _dir := PackedVector2Array()     # facing (x, z) at death
var _scale := PackedFloat32Array()
var _tint: Array[Color] = []
var _fx := PackedFloat32Array()      # 4 if epic (keeps the purple glow)
var _age := PackedFloat32Array()
var _side := PackedFloat32Array()    # small random sideways lean so piles look natural
var _count := 0
var _next := 0
var _buf := PackedFloat32Array()
var _mm: MultiMesh
var _vat: VatCrowd
var _clip_death := 0.5
var _death_len := 1.0


func _ready() -> void:
	_pos.resize(MAX)
	_dir.resize(MAX)
	_scale.resize(MAX)
	_tint.resize(MAX)
	_fx.resize(MAX)
	_age.resize(MAX)
	_side.resize(MAX)
	_buf.resize(MAX * STRIDE)
	for i in MAX:
		for k in 4:
			_buf[i * STRIDE + 12 + k] = 1.0
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_vat = VatCrowd.load_bake(EnemyManager.GOBLIN_VAT)
	_clip_death = float(_vat.clip_index["death"]) / 4.0
	_death_len = float(_vat.clip_length["death"]) / DEATH_SPEED
	_mm.mesh = _vat.mesh
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(mmi)


## Add a corpse. `facing` is the direction the goblin was facing (it falls the other way).
func add(at: Vector3, facing: Vector3, scale: float, tint: Color, epic: bool, burned: bool) -> void:
	var i: int
	if _count < MAX:
		i = _count
		_count += 1
	else:
		i = _next   # recycle the oldest
		_next = (_next + 1) % MAX
	var f := Vector2(facing.x, facing.z)
	_dir[i] = f.normalized() if f.length_squared() > 0.0001 else Vector2(0, 1)
	_pos[i] = at
	_scale[i] = scale
	_tint[i] = CHAR if burned else tint
	_fx[i] = 4.0 if epic and not burned else 0.0
	_age[i] = 0.0
	_side[i] = 0.0


## Raise Dead: up to `n` bodies still lying within `radius` of `near` (freshest first). They're
## removed from the ground; returns their positions.
func take_recent(near: Vector3, radius: float, n: int) -> Array:
	var cand := []
	for i in _count:
		if _age[i] >= LIFETIME - SINK_TIME:
			continue
		var p := _pos[i]
		if Vector2(p.x - near.x, p.z - near.z).length() <= radius:
			cand.append(i)
	cand.sort_custom(func(a, b): return _age[a] < _age[b])
	var out := []
	for i in cand.slice(0, n):
		out.append(_pos[i])
		_age[i] = LIFETIME   # gone
	return out


func _process(dt: float) -> void:
	for i in _count:
		_age[i] += dt
		_write(i)
	_mm.buffer = _buf
	_mm.visible_instance_count = _count


func _write(i: int) -> void:
	var b := i * STRIDE
	var age := _age[i]
	if age >= LIFETIME:
		for k in 12:
			_buf[b + k] = 0.0   # gone (scaled to nothing)
		return
	var s := _scale[i]
	var f := Vector3(_dir[i].x, 0.0, _dir[i].y)
	var basis := Basis(Vector3(f.z, 0, -f.x), Vector3.UP, f).scaled(Vector3.ONE * s)   # local +Z = facing
	# The death clip does the falling; sink into the ground at the end
	var y := _pos[i].y
	var sink_start := LIFETIME - SINK_TIME
	if age > sink_start:
		y -= ((age - sink_start) / SINK_TIME) * 0.6 * s
	_buf[b] = basis.x.x; _buf[b + 1] = basis.y.x; _buf[b + 2] = basis.z.x; _buf[b + 3] = _pos[i].x
	_buf[b + 4] = basis.x.y; _buf[b + 5] = basis.y.y; _buf[b + 6] = basis.z.y; _buf[b + 7] = y
	_buf[b + 8] = basis.x.z; _buf[b + 9] = basis.y.z; _buf[b + 10] = basis.z.z; _buf[b + 11] = _pos[i].z
	_buf[b + 12] = _clip_death
	_buf[b + 13] = clampf(age / _death_len, 0.0, 1.0)
	var c: Color = _tint[i]
	_buf[b + 16] = c.r
	_buf[b + 17] = c.g
	_buf[b + 18] = c.b
	_buf[b + 19] = _fx[i]


## Corpses still visible (for tests/debug).
func active_count() -> int:
	var n := 0
	for i in _count:
		if _age[i] < LIFETIME:
			n += 1
	return n


func age_of_newest() -> float:
	var best := 1e9
	for i in _count:
		best = minf(best, _age[i])
	return best


## How far through the death animation a corpse is (0..1).
func fall_angle(i: int) -> float:
	return clampf(_age[i] / _death_len, 0.0, 1.0)
