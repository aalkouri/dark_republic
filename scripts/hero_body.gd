class_name HeroBody
extends Node3D
## The six roster characters built in code from primitives and posed by hand every frame:
## Death, Billy Bulldog, Cowboy, the Sentient Platypus, the Bog Witch and Kong. One jointed
## humanoid (hips, torso, head, two-part arms and legs) dressed differently per kind (KINDS):
## a robed skeleton with a scythe, a stocky bulldog on his hind legs, a gunslinger, a platypus in
## a top hat, a hunched witch with her ladle, a gorilla dragging his broken shackles.
## Faces -Z, origin at the feet, ~1.8 m (Kong bigger, Billy smaller). PlayableBoss lists the
## interface (RosterHero / RosterModel drive it the same way as the boss bodies):
##   animate(dt, speed, airborne)   walk / run cycle, idle breathing, the current action
##   attack(target) -> Vector3      the weapon move (per kind: spin, bite, shot, kick, lob)
##   tip() -> Vector3  cast(i)  hit()  die()  drawn  set_dim(f)  set_hurt(f)

const KINDS := ["death", "billy_bulldog", "cowboy", "platypus", "bog_witch", "kong"]
const ATTACK_TIME := 0.35
const CAST_TIME := 0.8
const ULT_TIME := 1.4

var kind := "cowboy"
var drawn := false
var dead := false
var attacks := 0                     # tests
var casts := 0

var model: Node3D                    # everything (flinch / death tilt applied here)
var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Array[Node3D] = []        # [shoulder, elbow, hand]
var arm_r: Array[Node3D] = []
var leg_l: Array[Node3D] = []        # [hip, knee]
var leg_r: Array[Node3D] = []
var tail: Node3D
var weapon: Node3D                   # in the right hand (null: fights bare-handed)
var robe: Node3D                     # Death / the Bog Witch: a robe hiding the legs
var _phase := 0.0
var _time := 0.0
var _atk_t := 0.0
var _cast_t := 0.0
var _cast_len := CAST_TIME
var _ult := false
var _flinch := 0.0
var _die_t := 0.0
var _dim := 1.0
var _hurt := 0.0
var _overlay: StandardMaterial3D
var _mats := {}
var _leg_len := 0.9
var _arm_len := 0.62
var _scale := 1.0


static func create(p_kind: String) -> HeroBody:
	var b := HeroBody.new()
	b.kind = p_kind
	return b


func _ready() -> void:
	model = Node3D.new()
	add_child(model)
	match kind:
		"death": _build_death()
		"billy_bulldog": _build_bulldog()
		"platypus": _build_platypus()
		"bog_witch": _build_witch()
		"kong": _build_kong()
		_: _build_cowboy()
	model.scale = Vector3.ONE * _scale
	_overlay = PlayableBoss.overlay()
	PlayableBoss.apply_overlay(model, _overlay)


# ------------------------------------------------------------------ the skeleton

## Hips at leg height; torso, neck/head, arms and legs as pivots with meshes hung off them.
func _skeleton(leg_len: float, torso_h: float, arm_len: float, shoulder_w: float, hip_w: float) -> void:
	_leg_len = leg_len
	_arm_len = arm_len
	hips = _node(model, Vector3(0, leg_len, 0))
	torso = _node(hips, Vector3.ZERO)
	head = _node(torso, Vector3(0, torso_h + 0.04, 0))
	for sd in [-1.0, 1.0]:
		var sh := _node(torso, Vector3(sd * shoulder_w, torso_h - 0.06, 0))
		var el := _node(sh, Vector3(0, -arm_len * 0.5, 0))
		var ha := _node(el, Vector3(0, -arm_len * 0.5, 0))
		var hp := _node(hips, Vector3(sd * hip_w, 0, 0))
		var kn := _node(hp, Vector3(0, -leg_len * 0.5, 0))
		if sd < 0.0:
			arm_l = [sh, el, ha]
			leg_l = [hp, kn]
		else:
			arm_r = [sh, el, ha]
			leg_r = [hp, kn]


func _node(parent: Node3D, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	parent.add_child(n)
	return n


func _mat(c: Color, rough := 0.8, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var key := c.to_html() + str(rough) + str(metal) + str(glow)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = glow
		_mats[key] = m
	return _mats[key]


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = 12
	m.rings = 4
	return m


static func _sph(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 7
	return m


static func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func _cyl(top: float, bottom: float, h: float, seg := 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


## Limbs: a capsule from each joint down to the next (upper arm, forearm; thigh, shin).
func _limbs(arm_col: Color, hand_col: Color, leg_col: Color, foot_col: Color, arm_rad: float, leg_r_: float, hand_r := 0.06, foot := Vector3(0.12, 0.08, 0.24)) -> void:
	for arm in [arm_l, arm_r]:
		_mesh(arm[0], _cap(arm_rad, _arm_len * 0.5 + arm_rad), _mat(arm_col), Vector3(0, -_arm_len * 0.25, 0))
		_mesh(arm[1], _cap(arm_rad * 0.9, _arm_len * 0.5 + arm_rad), _mat(arm_col), Vector3(0, -_arm_len * 0.25, 0))
		_mesh(arm[2], _sph(hand_r), _mat(hand_col), Vector3(0, -hand_r * 0.6, 0))
	for leg in [leg_l, leg_r]:
		_mesh(leg[0], _cap(leg_r_, _leg_len * 0.5 + leg_r_), _mat(leg_col), Vector3(0, -_leg_len * 0.25, 0))
		_mesh(leg[1], _cap(leg_r_ * 0.9, _leg_len * 0.5 + leg_r_), _mat(leg_col), Vector3(0, -_leg_len * 0.25, 0))
		_mesh(leg[1], _box(foot), _mat(foot_col), Vector3(0, -_leg_len * 0.5 + foot.y * 0.5, -foot.z * 0.25))


# ------------------------------------------------------------------ the six

func _build_cowboy() -> void:
	_skeleton(0.92, 0.62, 0.62, 0.22, 0.1)
	var shirt := Color(0.62, 0.32, 0.2)
	var skin := Color(0.89, 0.71, 0.56)
	_limbs(shirt, skin, Color(0.22, 0.3, 0.48), Color(0.32, 0.2, 0.12), 0.055, 0.075, 0.055, Vector3(0.11, 0.1, 0.26))
	_mesh(torso, _cap(0.2, 0.66), _mat(shirt), Vector3(0, 0.32, 0))
	_mesh(torso, _box(Vector3(0.36, 0.42, 0.3)), _mat(Color(0.35, 0.22, 0.12)), Vector3(0, 0.36, 0))   # vest
	_mesh(torso, _box(Vector3(0.42, 0.07, 0.34)), _mat(Color(0.25, 0.15, 0.08)), Vector3(0, 0.04, 0))  # belt
	_mesh(torso, _box(Vector3(0.1, 0.07, 0.04)), _mat(Color(0.9, 0.75, 0.3), 0.3, 0.8), Vector3(0, 0.04, -0.18))   # buckle
	_mesh(head, _sph(0.14), _mat(skin), Vector3(0, 0.15, 0))
	_mesh(head, _cyl(0.13, 0.15, 0.08), _mat(Color(0.75, 0.15, 0.12)), Vector3(0, 0.02, 0))   # bandana
	_mesh(head, _box(Vector3(0.2, 0.03, 0.04)), _mat(Color(0.3, 0.2, 0.12)), Vector3(0, 0.12, -0.13))   # moustache
	_eyes(head, Vector3(0, 0.18, -0.125), 0.045, Color(0.15, 0.1, 0.05))
	_mesh(head, _cyl(0.36, 0.36, 0.03, 20), _mat(Color(0.55, 0.36, 0.18)), Vector3(0, 0.27, 0))   # brim
	_mesh(head, _cyl(0.12, 0.15, 0.17), _mat(Color(0.55, 0.36, 0.18)), Vector3(0, 0.36, 0))   # crown
	_mesh(head, _cyl(0.152, 0.152, 0.04), _mat(Color(0.2, 0.12, 0.06)), Vector3(0, 0.3, 0))   # band
	weapon = _node(arm_r[2], Vector3(0, -0.05, 0))
	var gun := _mat(Color(0.25, 0.25, 0.28), 0.35, 0.8)
	_mesh(weapon, _box(Vector3(0.05, 0.05, 0.26)), gun, Vector3(0, 0.0, -0.12))   # barrel
	_mesh(weapon, _cyl(0.04, 0.04, 0.07), gun, Vector3(0, 0.0, -0.02), Vector3(PI / 2, 0, 0))   # cylinder
	_mesh(weapon, _box(Vector3(0.045, 0.12, 0.06)), _mat(Color(0.45, 0.28, 0.15)), Vector3(0, -0.06, 0.04), Vector3(0.3, 0, 0))   # grip


func _build_death() -> void:
	_skeleton(0.95, 0.62, 0.66, 0.22, 0.1)
	var robe_col := Color(0.07, 0.065, 0.08)
	var bone := Color(0.9, 0.88, 0.8)
	_limbs(robe_col, bone, robe_col, robe_col, 0.06, 0.07, 0.05)
	robe = _mesh(hips, _cyl(0.2, 0.42, 0.98, 14), _mat(robe_col, 0.95), Vector3(0, -0.45, 0))
	_mesh(torso, _cap(0.2, 0.7), _mat(robe_col, 0.95), Vector3(0, 0.32, 0))
	_mesh(head, _sph(0.135), _mat(bone, 0.6), Vector3(0, 0.15, 0))   # skull
	_mesh(head, _box(Vector3(0.14, 0.07, 0.1)), _mat(bone, 0.6), Vector3(0, 0.05, -0.05))   # jaw
	for sd in [-1.0, 1.0]:   # hollow sockets with a cold blue glint
		_mesh(head, _sph(0.038), _mat(Color(0.02, 0.02, 0.03)), Vector3(sd * 0.05, 0.17, -0.115))
		_mesh(head, _sph(0.016), _mat(Color(0.35, 0.88, 1.0), 0.5, 0.0, 3.0), Vector3(sd * 0.05, 0.17, -0.135))
	_mesh(head, _sph(0.2), _mat(robe_col, 0.95), Vector3(0, 0.19, 0.11), Vector3.ZERO, Vector3(1.05, 1.15, 0.9))   # hood (open at the front)
	weapon = _node(arm_r[2], Vector3(0, -0.03, 0))
	weapon.rotation.x = 1.3   # the shaft stands upright in his grip (the arm is raised -1.3)
	var shaft := _mat(Color(0.25, 0.18, 0.12))
	_mesh(weapon, _cyl(0.022, 0.022, 1.9), shaft, Vector3(0, 0.3, 0))
	var steel := _mat(Color(0.78, 0.8, 0.86), 0.25, 0.9)
	for k in 4:   # a curved blade: four segments sweeping forward and down from the top
		var a := 0.25 + k * 0.32
		_mesh(weapon, _box(Vector3(0.02, 0.09 - k * 0.015, 0.26)), steel, Vector3(0, 1.22 - sin(a) * 0.18 * k * 0.6, -0.12 - k * 0.22), Vector3(-a * 0.5, 0, 0))


func _build_bulldog() -> void:
	_scale = 0.85
	_skeleton(0.62, 0.62, 0.55, 0.27, 0.13)
	var fur := Color(0.8, 0.62, 0.4)
	var pale := Color(0.95, 0.9, 0.82)
	_limbs(fur, pale, fur, pale, 0.085, 0.1, 0.075, Vector3(0.14, 0.08, 0.2))
	_mesh(torso, _sph(0.3), _mat(fur), Vector3(0, 0.32, 0), Vector3.ZERO, Vector3(1.05, 1.15, 0.9))   # barrel chest
	_mesh(torso, _sph(0.22), _mat(pale), Vector3(0, 0.3, -0.13), Vector3.ZERO, Vector3(1.0, 1.1, 0.6))   # pale belly
	_mesh(head, _sph(0.2), _mat(fur), Vector3(0, 0.15, -0.02), Vector3.ZERO, Vector3(1.2, 0.95, 1.0))   # big square head
	_mesh(head, _sph(0.13), _mat(pale), Vector3(0, 0.08, -0.17), Vector3.ZERO, Vector3(1.35, 0.85, 0.8))   # muzzle / jowls
	_mesh(head, _sph(0.045), _mat(Color(0.12, 0.08, 0.06), 0.3), Vector3(0, 0.14, -0.27))   # nose
	for sd in [-1.0, 1.0]:
		_mesh(head, _box(Vector3(0.025, 0.04, 0.02)), _mat(Color(1, 1, 0.95)), Vector3(sd * 0.06, 0.06, -0.27))   # underbite fangs
		_mesh(head, _sph(0.07), _mat(Color(0.55, 0.38, 0.24)), Vector3(sd * 0.2, 0.28, 0.0), Vector3(0, 0, sd * 0.6), Vector3(1.0, 0.5, 0.7))   # ears
	_eyes(head, Vector3(0, 0.22, -0.17), 0.075, Color(0.18, 0.1, 0.04))
	_mesh(head, _cyl(0.2, 0.22, 0.06), _mat(Color(0.12, 0.12, 0.13)), Vector3(0, -0.05, 0))   # spiked collar
	for k in 8:
		var a := TAU * k / 8.0
		_mesh(head, _cyl(0.0, 0.025, 0.06), _mat(Color(0.8, 0.8, 0.85), 0.3, 0.8), Vector3(cos(a) * 0.22, -0.05, sin(a) * 0.22), Vector3(0, 0, -PI / 2).rotated(Vector3.UP, -a))
	tail = _node(hips, Vector3(0, 0.08, 0.26))
	_mesh(tail, _cap(0.04, 0.16), _mat(fur), Vector3(0, 0.06, 0.02), Vector3(0.6, 0, 0))


func _build_platypus() -> void:
	_scale = 0.9
	_skeleton(0.7, 0.62, 0.55, 0.22, 0.11)
	var fur := Color(0.48, 0.32, 0.21)
	var bill := Color(0.22, 0.2, 0.18)
	_limbs(fur, bill, fur, Color(0.3, 0.26, 0.2), 0.065, 0.08, 0.06, Vector3(0.18, 0.04, 0.24))   # webbed feet
	_mesh(torso, _sph(0.27), _mat(fur), Vector3(0, 0.32, 0), Vector3.ZERO, Vector3(0.95, 1.3, 0.85))
	_mesh(torso, _box(Vector3(0.34, 0.36, 0.06)), _mat(Color(0.2, 0.22, 0.32)), Vector3(0, 0.38, -0.2))   # waistcoat
	_mesh(head, _sph(0.17), _mat(fur), Vector3(0, 0.15, 0))
	_mesh(head, _box(Vector3(0.2, 0.06, 0.26)), _mat(bill, 0.5), Vector3(0, 0.1, -0.24))   # the bill
	_mesh(head, _cyl(0.1, 0.1, 0.06), _mat(bill, 0.5), Vector3(0, 0.1, -0.36), Vector3(PI / 2, 0, 0), Vector3(1.0, 1.0, 0.45))
	_eyes(head, Vector3(0, 0.2, -0.14), 0.07, Color(0.05, 0.05, 0.05))
	_mesh(head, _cyl(0.05, 0.05, 0.01), _mat(Color(0.9, 0.8, 0.35), 0.3, 0.9), Vector3(0.07, 0.2, -0.16), Vector3(PI / 2, 0, 0))   # monocle
	_mesh(head, _cyl(0.14, 0.14, 0.02, 18), _mat(Color(0.08, 0.08, 0.09)), Vector3(0, 0.3, 0))   # top hat brim
	_mesh(head, _cyl(0.1, 0.1, 0.24), _mat(Color(0.08, 0.08, 0.09)), Vector3(0, 0.43, 0))
	_mesh(head, _cyl(0.102, 0.102, 0.04), _mat(Color(0.5, 0.1, 0.12)), Vector3(0, 0.34, 0))
	tail = _node(hips, Vector3(0, 0.02, 0.22))
	_mesh(tail, _box(Vector3(0.28, 0.05, 0.4)), _mat(Color(0.32, 0.22, 0.14)), Vector3(0, -0.05, 0.2), Vector3(-0.3, 0, 0))   # beaver tail
	for leg in [leg_l, leg_r]:   # the venom spur on each heel
		_mesh(leg[1], _cyl(0.0, 0.02, 0.08), _mat(Color(0.8, 1.0, 0.4), 0.5, 0.0, 1.0), Vector3(0, -_leg_len * 0.42, 0.06), Vector3(-PI / 2, 0, 0))


func _build_witch() -> void:
	_skeleton(0.9, 0.58, 0.6, 0.2, 0.1)
	var robe_col := Color(0.16, 0.24, 0.13)
	var skin := Color(0.55, 0.7, 0.42)
	_limbs(robe_col, skin, robe_col, Color(0.1, 0.08, 0.06), 0.06, 0.07, 0.055)
	robe = _mesh(hips, _cyl(0.2, 0.46, 0.94, 14), _mat(robe_col, 0.95), Vector3(0, -0.43, 0))
	_mesh(torso, _cap(0.19, 0.64), _mat(robe_col, 0.95), Vector3(0, 0.3, 0))
	_mesh(torso, _cyl(0.24, 0.24, 0.06), _mat(Color(0.3, 0.22, 0.1)), Vector3(0, 0.08, 0))   # rope belt
	_mesh(head, _sph(0.13), _mat(skin), Vector3(0, 0.14, 0))
	_mesh(head, _cyl(0.0, 0.035, 0.12), _mat(skin), Vector3(0, 0.12, -0.17), Vector3(-PI / 2 - 0.4, 0, 0))   # hooked nose
	_mesh(head, _sph(0.02), _mat(Color(0.45, 0.35, 0.2)), Vector3(0.05, 0.08, -0.12))   # wart
	_eyes(head, Vector3(0, 0.17, -0.11), 0.045, Color(0.95, 0.85, 0.25), 1.5)
	_mesh(head, _sph(0.16), _mat(Color(0.35, 0.35, 0.33)), Vector3(0, 0.12, 0.05), Vector3.ZERO, Vector3(1.05, 1.0, 1.0))   # grey hair
	_mesh(head, _cyl(0.34, 0.34, 0.025, 20), _mat(Color(0.1, 0.13, 0.08)), Vector3(0, 0.25, 0))   # hat brim
	var cone := _mesh(head, _cyl(0.0, 0.16, 0.48), _mat(Color(0.1, 0.13, 0.08)), Vector3(0.03, 0.5, 0.03), Vector3(0.18, 0, -0.12))   # bent cone
	cone.scale = Vector3.ONE
	weapon = _node(arm_r[2], Vector3(0, -0.03, 0))
	_mesh(weapon, _cyl(0.018, 0.018, 0.7), _mat(Color(0.45, 0.3, 0.18)), Vector3(0, -0.2, 0))   # ladle handle
	_mesh(weapon, _sph(0.09), _mat(Color(0.4, 0.38, 0.35), 0.4, 0.6), Vector3(0, -0.58, 0), Vector3.ZERO, Vector3(1, 0.55, 1))   # bowl
	_mesh(weapon, _sph(0.065), _mat(Color(0.6, 0.85, 0.2), 0.3, 0.0, 1.2), Vector3(0, -0.55, 0), Vector3.ZERO, Vector3(1, 0.4, 1))   # bile in it


func _build_kong() -> void:
	_scale = 1.15
	_skeleton(0.6, 0.72, 0.9, 0.36, 0.14)
	var fur := Color(0.22, 0.2, 0.19)
	var face := Color(0.34, 0.31, 0.28)
	_limbs(fur, face, fur, face, 0.11, 0.11, 0.1, Vector3(0.16, 0.08, 0.24))
	_mesh(torso, _sph(0.4), _mat(fur), Vector3(0, 0.42, 0.04), Vector3.ZERO, Vector3(1.1, 1.0, 0.85))   # huge chest
	_mesh(torso, _sph(0.26), _mat(face), Vector3(0, 0.4, -0.2), Vector3.ZERO, Vector3(1.0, 0.85, 0.5))   # bare chest
	head.position.z = -0.12
	_mesh(head, _sph(0.2), _mat(fur), Vector3(0, 0.1, 0))
	_mesh(head, _sph(0.15), _mat(face), Vector3(0, 0.06, -0.12), Vector3.ZERO, Vector3(1.15, 0.9, 0.8))   # muzzle
	_mesh(head, _box(Vector3(0.3, 0.06, 0.1)), _mat(fur), Vector3(0, 0.18, -0.14))   # heavy brow
	_eyes(head, Vector3(0, 0.13, -0.17), 0.08, Color(0.85, 0.54, 0.16))
	for sd in [-1.0, 1.0]:
		_mesh(head, _sph(0.02), _mat(Color(0.05, 0.04, 0.04)), Vector3(sd * 0.03, 0.06, -0.25))   # nostrils
	for arm in [arm_l, arm_r]:   # iron shackles with broken chain links
		var cuff := _mesh(arm[1], _cyl(0.13, 0.13, 0.1), _mat(Color(0.35, 0.33, 0.32), 0.4, 0.8), Vector3(0, -_arm_len * 0.42, 0))
		cuff.name = "Shackle"   # no-i18n
	weapon = _node(arm_r[2], Vector3(0, -0.05, 0))
	for k in 5:
		var link := TorusMesh.new()
		link.inner_radius = 0.025
		link.outer_radius = 0.05
		_mesh(weapon, link, _mat(Color(0.4, 0.38, 0.36), 0.4, 0.8), Vector3(0, -0.07 * k, 0), Vector3(0, PI / 2 * (k % 2), PI / 2))


## Two eyes `spread` apart (white with a dark pupil, or glowing).
func _eyes(parent: Node3D, at: Vector3, spread: float, col: Color, glow := 0.0) -> void:
	for sd in [-1.0, 1.0]:
		var p := at + Vector3(sd * spread * 0.5, 0, 0)
		if glow > 0.0:
			_mesh(parent, _sph(0.024), _mat(col, 0.4, 0.0, glow), p)
		else:
			_mesh(parent, _sph(0.032), _mat(Color(0.97, 0.97, 0.95), 0.3), p)
			_mesh(parent, _sph(0.018), _mat(col, 0.3), p + Vector3(0, 0, -0.018))


# ------------------------------------------------------------------ the interface

func attack(target: Vector3) -> Vector3:
	if dead:
		return tip()
	attacks += 1
	_atk_t = ATTACK_TIME
	drawn = true
	if target != Vector3.INF:
		var to := target - global_position
		var local := global_transform.basis.orthonormalized().inverse() * to
		model.rotation.y = clampf(atan2(-local.x, -local.z), -1.0, 1.0) * 0.6
	return tip()


func tip() -> Vector3:
	if weapon != null and weapon.is_inside_tree():
		return weapon.global_transform * Vector3(0, 0, -0.25)
	if head != null and head.is_inside_tree():
		return head.global_transform * Vector3(0, 0.1, -0.3)
	return global_position + Vector3(0, 1.0, 0)


func cast(i: int) -> void:
	if dead:
		return
	casts += 1
	_ult = i == 2
	_cast_len = ULT_TIME if _ult else CAST_TIME
	_cast_t = _cast_len
	_atk_t = 0.0
	drawn = true


func hit() -> void:
	if not dead:
		_flinch = 1.0


func die() -> void:
	dead = true
	_die_t = 0.0


func set_dim(f: float) -> void:
	_dim = f


func set_hurt(f: float) -> void:
	_hurt = f


# ------------------------------------------------------------------ posing

func animate(dt: float, speed: float, airborne := false) -> void:
	if model == null:
		return
	_time += dt
	if dead:
		_die_t += dt
		var f := clampf(_die_t / 0.8, 0.0, 1.0)
		model.rotation.x = lerpf(0.0, PI * 0.5, f * f)   # topples backwards...
		model.position.y = -0.25 * f
		if kind == "death":   # ...or, for Death, the robe empties and sinks
			model.rotation.x = 0.0
			model.scale = Vector3(_scale, _scale * maxf(0.05, 1.0 - f), _scale)
		PlayableBoss.tint(_overlay, _dim, _hurt)
		return
	_flinch = maxf(0.0, _flinch - dt * 4.0)
	_atk_t = maxf(0.0, _atk_t - dt)
	_cast_t = maxf(0.0, _cast_t - dt)
	if _atk_t <= 0.0 and _cast_t <= 0.0:
		drawn = false
		model.rotation.y = lerpf(model.rotation.y, 0.0, clampf(dt * 6.0, 0.0, 1.0))
	var run := clampf(speed / 8.0, 0.0, 1.5) if not airborne else 0.0
	_phase += dt * (2.0 + speed * 1.1)
	var s := sin(_phase)
	var c := cos(_phase)
	var breath := sin(_time * 2.0) * 0.02
	var hunch := {"bog_witch": 0.35, "kong": 0.4, "billy_bulldog": 0.1}.get(kind, 0.0) as float
	# walk / run: legs swing, knees bend on the back stroke, arms counter-swing, a little bob
	var swing := 0.65 * run
	leg_l[0].rotation.x = s * swing
	leg_r[0].rotation.x = -s * swing
	leg_l[1].rotation.x = -maxf(0.0, -c) * swing * 1.2
	leg_r[1].rotation.x = -maxf(0.0, c) * swing * 1.2
	if airborne:
		leg_l[0].rotation.x = -0.5
		leg_r[0].rotation.x = 0.3
		leg_l[1].rotation.x = 0.8
		leg_r[1].rotation.x = 0.4
	hips.position.y = _leg_len + absf(s) * 0.05 * run - 0.03 * run
	torso.rotation.x = -hunch - 0.15 * run + breath
	torso.rotation.y = s * 0.12 * run
	var arm_swing := 0.55 * run + 0.06
	arm_l[0].rotation = Vector3(-s * arm_swing, 0, -0.12)
	arm_r[0].rotation = Vector3(s * arm_swing, 0, 0.12)
	arm_l[1].rotation.x = -0.3 - 0.3 * run
	arm_r[1].rotation.x = -0.3 - 0.3 * run
	head.rotation.x = hunch * 0.8 + 0.1 * run
	if kind == "kong":   # long arms hang low, knuckles near the ground
		arm_l[0].rotation.z = -0.25
		arm_r[0].rotation.z = 0.25
	if kind == "death":   # Death glides: no stride, the robe sways
		leg_l[0].rotation.x = 0.0
		leg_r[0].rotation.x = 0.0
		hips.position.y = _leg_len + 0.08 + sin(_time * 1.6) * 0.04
		if robe:
			robe.rotation.x = 0.12 * run + sin(_time * 1.6) * 0.03
	if tail:
		tail.rotation.y = sin(_time * (8.0 if kind == "billy_bulldog" else 2.0)) * 0.4
	if weapon and kind == "death":   # the scythe held upright, blade over his shoulder
		arm_r[0].rotation.x = -0.4
		arm_r[1].rotation.x = -0.9
	# the current action on top
	if _cast_t > 0.0:
		var f := 1.0 - _cast_t / _cast_len
		var up := sin(f * PI)
		arm_l[0].rotation = Vector3(-2.6 * up, 0, -0.35 * up)
		arm_r[0].rotation = Vector3(-2.6 * up, 0, 0.35 * up)
		arm_l[1].rotation.x = -0.2
		arm_r[1].rotation.x = -0.2
		torso.rotation.x -= 0.25 * up
		if _ult:
			hips.position.y += 0.25 * up
			if kind == "kong":   # beats his chest
				arm_l[0].rotation = Vector3(-1.3, 0, 0.6 + 0.3 * sin(_time * 30.0))
				arm_r[0].rotation = Vector3(-1.3, 0, -0.6 - 0.3 * sin(_time * 30.0 + 1.5))
				arm_l[1].rotation.x = -1.6
				arm_r[1].rotation.x = -1.6
	elif _atk_t > 0.0:
		var f := 1.0 - _atk_t / ATTACK_TIME
		var e := sin(f * PI)
		match kind:
			"death", "kong":   # a full spin with the scythe / chains held out
				model.rotation.y = f * TAU
				arm_r[0].rotation = Vector3(-1.4, 0, 1.2)
				arm_r[1].rotation.x = -0.1
			"billy_bulldog":   # a lunging bite
				torso.rotation.x -= 0.6 * e
				hips.position.z = -0.35 * e
				head.rotation.x = -0.3 * e
			"platypus":   # a kick with the spur
				leg_r[0].rotation.x = -1.5 * e
				leg_r[1].rotation.x = 0.4 * e
				torso.rotation.x += 0.3 * e
			"bog_witch":   # an overhead lob with the ladle
				arm_r[0].rotation = Vector3(lerpf(-3.0, -0.6, f), 0, 0.2)
				arm_r[1].rotation.x = -0.3
			_:   # the Cowboy: arm up, aim, recoil
				arm_r[0].rotation = Vector3(-1.5 + 0.25 * e, 0, 0.1)
				arm_r[1].rotation.x = -0.05
	else:
		hips.position.z = lerpf(hips.position.z, 0.0, clampf(dt * 10.0, 0.0, 1.0))
	model.position.z = 0.15 * _flinch
	model.rotation.x = -0.25 * _flinch
	PlayableBoss.tint(_overlay, _dim, _hurt)
