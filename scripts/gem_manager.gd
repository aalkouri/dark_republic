class_name GemManager
extends Node3D
## XP gems, data-oriented like enemies. Gems inside pickup range get "magnetised"
## and accelerate toward the player. When the cap is hit, new gems merge into existing ones.

const MAX := 800
const STRIDE := 16

var count := 0
var pos := PackedVector3Array()
var val := PackedFloat32Array()
var att := PackedFloat32Array()   # < 0: resting, >= 0: seconds since magnetised
var mm: MultiMesh
var buf := PackedFloat32Array()
var _time := 0.0


func _ready() -> void:
	pos.resize(MAX)
	val.resize(MAX)
	att.resize(MAX)
	buf.resize(MAX * STRIDE)
	var mesh := SphereMesh.new()   # 4x2 segments = chunky octahedron gem
	mesh.radius = 0.22
	mesh.height = 0.5
	mesh.radial_segments = 4
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.3, 0.6)
	mat.emission_energy_multiplier = 0.6
	mesh.material = mat
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(mmi)


func spawn(p: Vector3, v: float) -> void:
	if count >= MAX:
		val[randi() % count] += v
		return
	pos[count] = p
	val[count] = v
	att[count] = -1.0
	count += 1


## Vacuum every gem on the map (boss reward).
func magnetise_all() -> void:
	for i in count:
		att[i] = maxf(att[i], 0.0)


## Moves gems, returns XP collected this tick.
func tick(dt: float, target: Vector3, pickup_range: float) -> float:
	_time += dt
	var gained := 0.0
	var r2 := pickup_range * pickup_range
	var i := 0
	while i < count:
		var p := pos[i]
		var to := target - p
		var d2 := to.length_squared()
		if att[i] < 0.0 and d2 < r2:
			att[i] = 0.0
		if att[i] >= 0.0:
			if d2 < 1.0:
				gained += val[i]
				count -= 1
				pos[i] = pos[count]
				val[i] = val[count]
				att[i] = att[count]
				continue
			att[i] += dt
			var d := sqrt(d2)
			var step := minf((8.0 + att[i] * 50.0) * dt, d)
			p += to / d * step
			pos[i] = p
		_write(i, p)
		i += 1
	mm.buffer = buf
	mm.visible_instance_count = count
	return gained


func _write(i: int, p: Vector3) -> void:
	var v := val[i]
	var s := 1.0
	var col := Color(0.35, 0.65, 1.0)
	if v >= 20.0:
		s = 1.8
		col = Color(1.0, 0.3, 0.35)
	elif v >= 5.0:
		s = 1.35
		col = Color(0.35, 1.0, 0.5)
	var a := _time * 3.0 + float(i)
	var c := cos(a) * s
	var sn := sin(a) * s
	var b := i * STRIDE
	var y := p.y + 0.12 * sin(_time * 4.0 + float(i))
	buf[b] = c; buf[b + 1] = 0.0; buf[b + 2] = sn; buf[b + 3] = p.x
	buf[b + 4] = 0.0; buf[b + 5] = s; buf[b + 6] = 0.0; buf[b + 7] = y
	buf[b + 8] = -sn; buf[b + 9] = 0.0; buf[b + 10] = c; buf[b + 11] = p.z
	buf[b + 12] = col.r; buf[b + 13] = col.g; buf[b + 14] = col.b; buf[b + 15] = 1.0
