class_name SpiderModel
extends Node3D
## The Arachnid's body, built in code: a glossy black-violet spider with eight two-jointed legs,
## a cluster of red eyes, fangs and a red hourglass on the abdomen.
##
## The legs walk themselves. Each foot stays planted in the world until the body has moved far
## enough from it, then steps to a new spot ahead (the legs go in two alternating groups of
## four, like a real spider). Feet rest on this node's local XZ plane, so whatever surface the
## node is oriented to - floor, wall or ceiling (local +Y = the surface normal) - the legs grip
## it. Two-bone IK bends each knee up away from the surface.
##
## Scale 1: about 6 m leg span, 2.4 m tall. Faces -Z.

const BODY := Color(0.11, 0.08, 0.13)
const SHEEN := Color(0.32, 0.18, 0.4)
const EYE := Color(1.0, 0.16, 0.22)
const MARK := Color(0.85, 0.06, 0.08)
const L1 := 2.0            # femur
const L2 := 2.4            # tibia
const HIP_Y := 1.5         # hips this high above the surface
const STEP_DIST := 1.3     # a foot steps when it's this far from where it wants to be
const STEP_TIME := 0.16
const STEP_HEIGHT := 0.7
# Legs: [hip x, hip z, foot x, foot z] at rest (right side; mirrored for the left)
const LEGS := [
	[0.55, -1.05, 2.6, -3.1],
	[0.75, -0.55, 3.4, -1.2],
	[0.75, -0.05, 3.4, 0.9],
	[0.55, 0.45, 2.7, 2.8],
]

var surface_root: Node3D        # the node whose local XZ is the surface (this node by default)
var rear := 0.0                 # 0..1: front legs up, body tipped back (wind-ups)
var crouch := 0.0               # 0..1: body lowered to the surface (about to pounce)
var curl := 0.0                 # 0..1: legs curled under (dead)
var pitch := 0.0                # extra body pitch, radians (+ = nose down: the player's spit)
var nudge := Vector3.ZERO       # extra body offset (local, unscaled)
var step_scaled := false        # step distance scales with the model (the player-sized one)
var _sc := 1.0                  # world scale this frame (the player's model may be scaled by its parent)
var _body: Node3D
var _legs: Array[Dictionary] = []   # {hip, rest, foot(world), from, to, t, stepping, group, seg1, seg2}
var _mats: Array[StandardMaterial3D] = []
var _eye_mat: StandardMaterial3D
var _flash := 0.0
var _enrage := 0.0
var _t := 0.0
var _group := 0
var _group_cd := 0.0


func _ready() -> void:
	if surface_root == null:
		surface_root = self
	_body = Node3D.new()
	add_child(_body)
	var mat := _mat(BODY, 0.0)
	mat.metallic = 0.3
	mat.roughness = 0.32
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.8
	# Cephalothorax and abdomen
	_blob(Vector3(0, HIP_Y + 0.25, -0.45), Vector3(1.15, 0.8, 1.35), 1.0, mat)
	_blob(Vector3(0, HIP_Y + 0.75, 1.9), Vector3(1.35, 1.05, 1.6), 1.25, mat)
	# Red hourglass on the abdomen
	var mark := _mat(MARK, 1.2)
	for s in [-1.0, 1.0]:
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.42
		cm.height = 0.6
		cm.material = mark
		c.mesh = cm
		c.position = Vector3(0, HIP_Y + 2.05, 1.9 + s * 0.3)
		c.rotation = Vector3(PI * 0.5 * s, 0, 0)
		c.scale = Vector3(1, 1, 0.25)
		_body.add_child(c)
	# Eyes: two big, six small
	_eye_mat = _mat(EYE, 3.0)
	for e in [[-0.22, 0.32, 0.14], [0.22, 0.32, 0.14], [-0.45, 0.42, 0.08], [0.45, 0.42, 0.08],
			[-0.12, 0.55, 0.07], [0.12, 0.55, 0.07], [-0.32, 0.18, 0.06], [0.32, 0.18, 0.06]]:
		var eye := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = e[2]
		sm.height = e[2] * 2.0
		sm.material = _eye_mat
		eye.mesh = sm
		eye.position = Vector3(e[0], HIP_Y + e[1], -1.72)
		_body.add_child(eye)
	# Fangs
	var fang := _mat(Color(0.75, 0.7, 0.6), 0.0)
	for s in [-1.0, 1.0]:
		var f := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.0
		cm.height = 0.7
		cm.material = fang
		f.mesh = cm
		f.position = Vector3(0.2 * s, HIP_Y - 0.25, -1.7)
		f.rotation = Vector3(-0.35, 0, 0.25 * s)
		_body.add_child(f)
	# Legs
	var leg_mat := mat
	for side in [1.0, -1.0]:
		for k in LEGS.size():
			var d: Array = LEGS[k]
			var hip := Vector3(d[0] * side, HIP_Y, d[1])
			var rest := Vector3(d[2] * side, 0.0, d[3])
			var s1 := _seg(leg_mat, 0.17, 0.12)
			var s2 := _seg(leg_mat, 0.12, 0.04)
			var group := (k + (0 if side > 0.0 else 1)) % 2
			_legs.append({"hip": hip, "rest": rest, "foot": Vector3.ZERO, "from": Vector3.ZERO, "to": Vector3.ZERO,
				"t": 0.0, "stepping": false, "group": group, "seg1": s1, "seg2": s2, "planted": false})


func _mat(c: Color, emit: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = c if emit > 0.0 else Color.BLACK
	m.emission_energy_multiplier = maxf(emit, 1.0)
	if emit <= 0.0:
		_mats.append(m)
	return m


func _blob(at: Vector3, scl: Vector3, r: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.material = m
	mi.mesh = sm
	mi.position = at
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_body.add_child(mi)


func _seg(m: Material, r0: float, r1: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r0
	cm.height = 1.0
	cm.radial_segments = 6
	cm.material = m
	mi.mesh = cm
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi


func flash() -> void:
	_flash = 0.1


func set_enrage(k: float) -> void:
	_enrage = k


## Put every foot down where it wants to be right now (after a jump or teleport).
func plant_all() -> void:
	for l in _legs:
		l["foot"] = _ideal(l)
		l["stepping"] = false
		l["planted"] = true


func _ideal(l: Dictionary) -> Vector3:
	var r: Vector3 = l["rest"]
	if curl > 0.0:
		r = r.lerp(Vector3(r.x * 0.35, 0.0, r.z * 0.35), curl)
	return global_transform * r


func _process(dt: float) -> void:
	_t += dt
	_sc = global_transform.basis.get_scale().x
	# Body: breathing bob, rear-up and crouch
	var lift := HIP_Y * (-0.45 * crouch) + 0.06 * sin(_t * 3.0) - curl * 1.0
	_body.position = Vector3(0, lift + rear * 0.6, 0) + nudge
	_body.rotation = Vector3(rear * 0.55 - pitch, 0, 0)
	# Feet: step when too far from where they want to be, one group at a time
	_group_cd -= dt
	var any_stepping := false
	for l in _legs:
		if not l["planted"]:
			l["foot"] = _ideal(l)
			l["planted"] = true
		if l["stepping"]:
			any_stepping = true
	if not any_stepping and _group_cd <= 0.0:
		var stepped := false
		for l in _legs:
			if l["group"] != _group:
				continue
			var want := _ideal(l)
			var sd := STEP_DIST * (_sc if step_scaled else 1.0)
			if (l["foot"] as Vector3).distance_to(want) > sd * (0.6 if curl > 0.0 else 1.0):
				l["from"] = l["foot"]
				var lead := (want - (l["foot"] as Vector3)).normalized() * sd * 0.35
				l["to"] = want + lead
				l["t"] = 0.0
				l["stepping"] = true
				stepped = true
		_group = 1 - _group
		if stepped:
			_group_cd = STEP_TIME * 0.5
	var up := global_transform.basis.y.normalized()
	for k in _legs.size():
		var l: Dictionary = _legs[k]
		if l["stepping"]:
			l["t"] += dt / STEP_TIME
			var f := minf(l["t"], 1.0)
			l["foot"] = (l["from"] as Vector3).lerp(l["to"], f) + up * sin(f * PI) * STEP_HEIGHT * _sc
			if f >= 1.0:
				l["stepping"] = false
		var foot: Vector3 = l["foot"]
		# Front legs lift and claw the air while rearing up
		if rear > 0.0 and k % 4 == 0:
			var hip_w: Vector3 = _body.global_transform * (l["hip"] as Vector3)
			foot = foot.lerp(hip_w + (global_transform.basis * Vector3(0, 2.2, -2.2)) + up * sin(_t * 9.0 + k) * 0.4 * _sc, rear)
		_pose_leg(l, foot)
	# Colours: sheen, enrage glow, hit flash
	_flash = maxf(_flash - dt, 0.0)
	var glow := Color(0.8, 0.05, 0.1) * (_enrage * (0.18 + 0.1 * sin(_t * 8.0))) + Color(1, 1, 1) * (_flash * 3.0)
	for m in _mats:
		m.emission = glow
	_eye_mat.emission_energy_multiplier = 3.0 + 3.0 * _enrage


## Two-bone IK: hip (on the body) to foot (world), knee bent away from the surface.
func _pose_leg(l: Dictionary, foot: Vector3) -> void:
	var s := _sc
	var hip: Vector3 = _body.global_transform * (l["hip"] as Vector3)
	var up := global_transform.basis.y.normalized()
	var a := L1 * s
	var b := L2 * s
	var to := foot - hip
	var d := clampf(to.length(), 0.05, (a + b) * 0.999)
	var dir := to.normalized() if to.length() > 0.001 else -up
	# Bend direction: perpendicular to the hip-foot line, towards "up"
	var bend := (up - dir * up.dot(dir))
	bend = bend.normalized() if bend.length() > 0.001 else global_transform.basis.z
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var knee := hip + dir * x + bend * h
	var end := hip + dir * d
	_place(l["seg1"], hip, knee, s)
	_place(l["seg2"], knee, end, s)


func _place(mi: MeshInstance3D, p0: Vector3, p1: Vector3, s: float) -> void:
	var v := p1 - p0
	var len := v.length()
	if len < 0.001:
		return
	var y := v / len
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x * s, y * len, z * s), (p0 + p1) * 0.5)
