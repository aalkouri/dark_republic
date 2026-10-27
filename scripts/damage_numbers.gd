class_name DamageNumbers
extends Node3D
## Floating damage numbers. Each one pops in small, swells big, settles, then floats up and
## fades out, all within LIFE seconds. Pooled Label3D nodes; when the pool is full the oldest
## number is recycled. A per-frame cap keeps mass hits (meteor, Inferno chains) readable.

const LIFE := 0.75
const POOL := 180
const MAX_NEW_PER_FRAME := 40
const NORMAL := 0
const BURN := 1
const COLORS := [Color(1.0, 0.95, 0.8), Color(1.0, 0.55, 0.15)]

var _labels: Array[Label3D] = []
var _age := PackedFloat32Array()
var _base := PackedVector3Array()
var _next := 0
var _new_this_frame := 0
var _font: Font


func _ready() -> void:
	_age.resize(POOL)
	_age.fill(LIFE)
	_base.resize(POOL)
	_font = ThemeDB.fallback_font


func add(at: Vector3, amount: float, kind := NORMAL) -> void:
	if _new_this_frame >= MAX_NEW_PER_FRAME or amount < 0.5:
		return
	_new_this_frame += 1
	var i := _next
	_next = (_next + 1) % POOL
	if i >= _labels.size():
		_labels.append(_make_label())
	var l := _labels[i]
	l.text = str(roundi(amount))
	l.modulate = COLORS[kind]
	l.outline_modulate = Color(0.1, 0.02, 0.0, 1.0) if kind == BURN else Color(0, 0, 0, 1)
	l.visible = true
	_base[i] = at + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	_age[i] = 0.0
	_apply(i)


func _make_label() -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.font = _font
	l.font_size = 64
	l.outline_size = 14
	l.pixel_size = 0.0075
	l.double_sided = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.visible = false
	add_child(l)
	return l


func _process(dt: float) -> void:
	_new_this_frame = 0
	for i in _labels.size():
		if _age[i] >= LIFE:
			continue
		_age[i] += dt
		if _age[i] >= LIFE:
			_labels[i].visible = false
			continue
		_apply(i)


## Animation curve: 0-15% pop from small to big, 15-35% settle, then rise and fade.
func _apply(i: int) -> void:
	var t := _age[i] / LIFE
	var s: float
	if t < 0.15:
		var k := t / 0.15
		s = lerpf(0.35, 1.45, 1.0 - (1.0 - k) * (1.0 - k))
	elif t < 0.35:
		s = lerpf(1.45, 1.0, (t - 0.15) / 0.2)
	else:
		s = 1.0
	var l := _labels[i]
	l.scale = Vector3.ONE * s
	l.position = _base[i] + Vector3(0, 0.25 + t * 0.9, 0)
	l.modulate.a = 1.0 if t < 0.5 else 1.0 - (t - 0.5) / 0.5
	l.outline_modulate.a = l.modulate.a


func active_count() -> int:
	var n := 0
	for i in _labels.size():
		if _age[i] < LIFE:
			n += 1
	return n
