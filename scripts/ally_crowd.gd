class_name AllyCrowd
extends Node3D
## Raise Dead's risen goblins: shadowy allies drawn with the goblin crowd's baked mesh and
## animations (in their own MultiMesh, shadow-tinted), that claw out of the ground, chase the
## nearest goblin, hit it every RosterKit.RAISE_RATE seconds and explode when their time is up.

const MAX := 64
const STRIDE := 20
const SCALE := 1.15
const RISE_TIME := 0.5
const SEEK := 20.0
const REACH := 0.8
const TINT := Color(0.32, 0.18, 0.45)

var enemies: EnemyManager
var _pos := PackedVector3Array()
var _face := PackedVector2Array()
var _life := PackedFloat32Array()
var _delay := PackedFloat32Array()
var _rise := PackedFloat32Array()
var _atk := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _n := 0
var _buf := PackedFloat32Array()
var _mm: MultiMesh
var _vat: VatCrowd
var _clip_run := 0.0
var _clip_attack := 0.25
var _attack_rate := 1.0


func _ready() -> void:
	for a in [_life, _delay, _rise, _atk, _phase]:
		a.resize(MAX)
	_pos.resize(MAX)
	_face.resize(MAX)
	_buf.resize(MAX * STRIDE)
	_vat = VatCrowd.load_bake(EnemyManager.GOBLIN_VAT)
	_clip_run = float(_vat.clip_index["run"]) / 4.0
	_clip_attack = float(_vat.clip_index["attack"]) / 4.0
	_attack_rate = 1.0 / float(_vat.clip_length["attack"])
	_vat.material.set_shader_parameter("ghost", 1.0)   # its own material: only allies glow
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _vat.mesh
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.top_level = true
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(mmi)


## Raise one ally at `at` (on the ground) for `life` seconds, after `delay`.
func add(at: Vector3, life: float, delay := 0.0) -> void:
	if _n >= MAX:
		return
	var i := _n
	_n += 1
	_pos[i] = at
	_face[i] = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_life[i] = life
	_delay[i] = delay
	_rise[i] = 0.0
	_atk[i] = randf() * 0.4
	_phase[i] = randf()


func count() -> int:
	return _n


func tick(dt: float, dmg_mult: float) -> void:
	var kit := get_parent() as RosterKit
	var i := 0
	while i < _n:
		if _delay[i] > 0.0:
			_delay[i] -= dt
			_write(i, 0.0, _clip_run)
			i += 1
			continue
		_life[i] -= dt
		if _life[i] <= 0.0:
			if kit:
				kit.ally_expired(_pos[i])
			_remove(i)
			continue
		_rise[i] = minf(1.0, _rise[i] + dt / RISE_TIME)
		var clip := _clip_run
		var p := _pos[i]
		if _rise[i] >= 1.0:
			var t := enemies.nearest_k(p, SEEK, 1)
			if not t.is_empty():
				var e := t[0]
				var tp := enemies.pos[e]
				var to := Vector2(tp.x - p.x, tp.z - p.z)
				var dist := to.length()
				if dist > 0.001:
					_face[i] = to / dist
				var reach := enemies.t_radius[enemies.typ[e]] * enemies.sz[e] + REACH
				if dist <= reach:
					clip = _clip_attack
					_phase[i] = fmod(_phase[i] + dt * _attack_rate, 1.0)
					_atk[i] -= dt
					if _atk[i] <= 0.0:
						_atk[i] = RosterKit.RAISE_RATE
						enemies.damage(e, RosterKit.RAISE_HIT * dmg_mult)
				else:
					var step := minf(RosterKit.RAISE_SPEED * dt, dist - reach * 0.8)
					p.x += _face[i].x * step
					p.z += _face[i].y * step
					_phase[i] = fmod(_phase[i] + dt * RosterKit.RAISE_SPEED / (EnemyManager.STRIDE_LEN * SCALE), 1.0)
			p.y = SwampWater.height_at(p.x, p.z)
			_pos[i] = p
		_write(i, _rise[i], clip)
		i += 1
	_mm.buffer = _buf
	_mm.visible_instance_count = _n


func _remove(i: int) -> void:
	var last := _n - 1
	_pos[i] = _pos[last]
	_face[i] = _face[last]
	_life[i] = _life[last]
	_delay[i] = _delay[last]
	_rise[i] = _rise[last]
	_atk[i] = _atk[last]
	_phase[i] = _phase[last]
	_n -= 1


func _write(i: int, rise: float, clip: float) -> void:
	var b := i * STRIDE
	var s := SCALE * maxf(rise, 0.001)
	var f := Vector3(_face[i].x, 0.0, _face[i].y)
	var basis := Basis(Vector3(f.z, 0, -f.x), Vector3.UP, f).scaled(Vector3.ONE * s)
	var y := _pos[i].y - (1.0 - rise) * 0.9   # clawing up out of the ground
	_buf[b] = basis.x.x; _buf[b + 1] = basis.y.x; _buf[b + 2] = basis.z.x; _buf[b + 3] = _pos[i].x
	_buf[b + 4] = basis.x.y; _buf[b + 5] = basis.y.y; _buf[b + 6] = basis.z.y; _buf[b + 7] = y
	_buf[b + 8] = basis.x.z; _buf[b + 9] = basis.y.z; _buf[b + 10] = basis.z.z; _buf[b + 11] = _pos[i].z
	_buf[b + 12] = clip
	_buf[b + 13] = _phase[i]
	_buf[b + 14] = 0.0
	_buf[b + 15] = 1.0
	_buf[b + 16] = TINT.r
	_buf[b + 17] = TINT.g
	_buf[b + 18] = TINT.b
	_buf[b + 19] = EnemyManager.FX_SHADOW
