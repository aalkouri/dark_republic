class_name NecromancerModel
extends Node3D
## The Necromancer, built in code (about MODEL_HEIGHT tall at scale 1, facing +Z): a gaunt
## sorcerer in a long tattered robe of black and grave-purple with a deep hood over a bare
## skull whose eyes burn green, a mantle of bone and little skulls at the shoulders, a belt hung
## with skull trinkets and a grimoire, long bony hands, and a tall twisted staff crowned with a
## horned skull clutching a green soul-flame. He hovers a hand's breadth off the ground, the
## ragged hem streaming; souls circle him.
## Poses (pose()): idle, walk, cast (staff raised), slam (staff brought down), summon (both arms
## flung up), channel (staff levelled at you), rise (the ultimate: lifted, arms spread), die.

const MODEL_HEIGHT := 2.7
const SOUL_GREEN := Color(0.4, 1.0, 0.55)

var body: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var staff_tip: Node3D
var hover := 0.25            # metres off the ground (model scale)
var lift := 0.0              # extra lift (the ultimate)
var crumble := 0.0           # dying: 0..1, the robe collapses
var _pose := "idle"
var _pose_t := 0.0
var _t := 0.0
var _souls: Array[MeshInstance3D] = []
var _overlay: StandardMaterial3D
var _flash_t := 0.0
var _glow: ShaderMaterial
var _light: OmniLight3D
var _flames: CPUParticles3D
var _rot := {}               # current rotations (lerped toward the pose)


func _ready() -> void:
	_glow = MeshBuilder.glow_material().duplicate() as ShaderMaterial
	_glow.set_shader_parameter("glow", 3.0)
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.albedo_color = Color(1.0, 0.95, 0.95, 0.0)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body = _part(_build_body(), Vector3(0, 0, 0))
	head = _part(_build_head(), Vector3(0, 2.28, 0.04), body)
	arm_l = _part(_build_arm(1.0, false), Vector3(0.3, 2.08, 0.0), body)
	arm_r = _part(_build_arm(-1.0, true), Vector3(-0.3, 2.08, 0.0), body)
	staff_tip = Node3D.new()
	staff_tip.position = Vector3(-0.08, 0.95, 0.42)   # in arm_r space: the soul-flame atop the staff
	arm_r.add_child(staff_tip)
	_light = OmniLight3D.new()
	_light.light_color = SOUL_GREEN
	_light.light_energy = 1.8
	_light.omni_range = 9.0
	staff_tip.add_child(_light)
	# souls circling him
	var sm := MeshBuilder.new()
	sm.add(MeshBuilder.sphere(0.07, 8, 5), Transform3D(), Color(0.5, 1.0, 0.7, 0.0))
	sm.add(MeshBuilder.cone(0.06, 0.3, 6), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, -0.15)), Color(0.3, 0.8, 0.5, 0.0))
	var soul_mesh := sm.commit(_glow)
	for k in 5:
		var s := MeshInstance3D.new()
		s.mesh = soul_mesh
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		_souls.append(s)


func _part(mesh: ArrayMesh, at: Vector3, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.position = at
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_overlay = _overlay
	n.add_child(mi)
	(parent if parent != null else self).add_child(n)
	return n


func _finish(mb: MeshBuilder, gb: MeshBuilder) -> ArrayMesh:
	var m := mb.commit()
	gb.commit_into(m, _glow)
	return m


## Robe, mantle, belt (origin at the hem; the hood's back and the shoulders included).
func _build_body() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var black := Color(0.06, 0.05, 0.07, 0.0)
	var purple := Color(0.2, 0.08, 0.24, 0.0)
	var trim := Color(0.42, 0.34, 0.16, 0.0)
	var bone := Color(0.8, 0.76, 0.66, 0.0)
	# the robe: a long cone of cloth from the chest to the ground, an open front showing purple
	mb.add(MeshBuilder.cyl(0.32, 0.62, 1.7, 14, 3), Transform3D(Basis(), Vector3(0, 0.95, 0)), black)
	mb.add(MeshBuilder.cyl(0.3, 0.42, 1.6, 10), Transform3D(Basis.from_scale(Vector3(0.6, 1.0, 0.4)), Vector3(0, 0.95, 0.2)), purple)
	for k in 2:   # gold-trimmed edges of the opening
		var sd := 1.0 if k == 0 else -1.0
		mb.limb(Vector3(sd * 0.12, 1.75, 0.3), Vector3(sd * 0.3, 0.12, 0.52), 0.025, 0.03, trim, 5)
	# tattered hem strips (sway)
	for k in 16:
		var a := TAU * k / 16.0
		var l := 0.3 + 0.25 * fmod(k * 0.618, 1.0)
		mb.add(MeshBuilder.box(Vector3(0.2, l, 0.02)), Transform3D(Basis(Vector3.UP, -a), Vector3(sin(a) * 0.6, 0.12 - l * 0.5 + 0.1, cos(a) * 0.6)), Color(black, 0.6))
	# chest, a high collar, the back of the hood
	mb.add(MeshBuilder.cyl(0.36, 0.3, 0.55, 12), Transform3D(Basis(), Vector3(0, 1.95, 0)), black)
	mb.add(MeshBuilder.cyl(0.36, 0.3, 0.35, 12, 1), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.8)), Vector3(0, 2.3, -0.05)), purple)
	# a mantle of bone: plates and little skulls on both shoulders, a ribcage pectoral
	for sd in [1.0, -1.0]:
		for k in 3:
			mb.add(MeshBuilder.sphere(0.13 - k * 0.02, 8, 5), Transform3D(Basis.from_scale(Vector3(1.2, 0.5, 1.0)), Vector3(sd * (0.3 + k * 0.08), 2.18 - k * 0.07, -0.02)), bone.darkened(k * 0.08))
		var sk := Vector3(sd * 0.38, 2.25, 0.05)
		mb.add(MeshBuilder.sphere(0.08, 8, 6), Transform3D(Basis.from_scale(Vector3(0.9, 1.0, 1.05)), sk), bone)
		for e in [-1.0, 1.0]:
			mb.add(MeshBuilder.sphere(0.018, 5, 4), Transform3D(Basis(), sk + Vector3(e * 0.028, 0.0, 0.07)), Color(0.05, 0.05, 0.05, 0.0))
			gb.add(MeshBuilder.sphere(0.01, 4, 3), Transform3D(Basis(), sk + Vector3(e * 0.028, 0.0, 0.08)), SOUL_GREEN)
		for k in 3:   # bone spikes
			mb.add(MeshBuilder.cone(0.03, 0.22, 5), Transform3D(Basis(Vector3(0, 0, 1), -sd * (0.4 + k * 0.25)), Vector3(sd * (0.3 + k * 0.08), 2.27, -0.06)), bone)
	for k in 4:
		mb.add(MeshBuilder.cyl(0.22 - k * 0.015, 0.22 - k * 0.015, 0.02, 12, 1), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.55)), Vector3(0, 1.85 + k * 0.08, 0.13)), bone)
	# the belt: a cord with skull trinkets, a chained grimoire at the hip
	mb.add(MeshBuilder.cyl(0.34, 0.34, 0.06, 14), Transform3D(Basis(), Vector3(0, 1.62, 0)), Color(0.15, 0.1, 0.06, 0.0))
	for k in 5:
		var a := -0.9 + k * 0.45
		mb.add(MeshBuilder.sphere(0.045, 6, 5), Transform3D(Basis(), Vector3(sin(a) * 0.37, 1.52, cos(a) * 0.37)), bone)
	var book := Vector3(0.38, 1.35, 0.1)
	mb.add(MeshBuilder.box(Vector3(0.08, 0.3, 0.22)), Transform3D(Basis(Vector3(0, 0, 1), 0.15), book), Color(0.24, 0.08, 0.06, 0.0))
	mb.add(MeshBuilder.box(Vector3(0.085, 0.26, 0.18)), Transform3D(Basis(Vector3(0, 0, 1), 0.15), book), Color(0.8, 0.76, 0.62, 0.0))
	gb.add(MeshBuilder.box(Vector3(0.09, 0.08, 0.08)), Transform3D(Basis(Vector3(0, 0, 1), 0.15), book + Vector3(0, 0.03, 0.0)), SOUL_GREEN)
	mb.limb(Vector3(0.3, 1.6, 0.12), book + Vector3(0, 0.15, 0), 0.008, 0.008, Color(0.3, 0.3, 0.32, 0.0), 3)
	# runes glowing faintly down the purple front
	for k in 5:
		gb.add(MeshBuilder.box(Vector3(0.05, 0.08, 0.01)), Transform3D(Basis(Vector3(0, 0, 1), k * 0.7), Vector3(0, 0.4 + k * 0.24, 0.38 + (1.4 - k * 0.24) * 0.09)), Color(0.35, 0.9, 0.5, 0.0))
	return _finish(mb, gb)


## The hood and the skull in it (origin at the neck).
func _build_head() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var black := Color(0.06, 0.05, 0.07, 0.0)
	var bone := Color(0.84, 0.8, 0.7, 0.0)
	mb.add(MeshBuilder.sphere(0.26, 12, 8), Transform3D(Basis.from_scale(Vector3(1.0, 1.15, 1.1)), Vector3(0, 0.2, -0.03)), black)
	mb.add(MeshBuilder.cone(0.16, 0.42, 8), Transform3D(Basis(Vector3(1, 0, 0), -2.2), Vector3(0, 0.45, -0.22)), black)   # the hood's peak
	mb.add(MeshBuilder.sphere(0.2, 10, 7), Transform3D(Basis.from_scale(Vector3(0.95, 1.1, 0.5)), Vector3(0, 0.17, 0.14)), Color(0.01, 0.01, 0.015, 0.0))
	# the skull
	var sk := Vector3(0, 0.16, 0.12)
	mb.add(MeshBuilder.sphere(0.14, 10, 8), Transform3D(Basis.from_scale(Vector3(0.9, 1.0, 1.0)), sk), bone)
	mb.add(MeshBuilder.box(Vector3(0.13, 0.07, 0.1)), Transform3D(Basis(), sk + Vector3(0, -0.12, 0.06)), bone.darkened(0.1))
	for k in 6:
		mb.add(MeshBuilder.box(Vector3(0.012, 0.025, 0.01)), Transform3D(Basis(), sk + Vector3(-0.04 + k * 0.016, -0.1, 0.115)), Color(0.95, 0.93, 0.85, 0.0))
	for sd in [1.0, -1.0]:
		mb.add(MeshBuilder.sphere(0.042, 8, 5), Transform3D(Basis(), sk + Vector3(sd * 0.05, 0.02, 0.1)), Color(0.02, 0.02, 0.02, 0.0))
		gb.add(MeshBuilder.sphere(0.022, 6, 4), Transform3D(Basis(), sk + Vector3(sd * 0.05, 0.02, 0.125)), SOUL_GREEN)
	mb.add(MeshBuilder.cone(0.02, 0.04, 3), Transform3D(Basis(Vector3(1, 0, 0), PI), sk + Vector3(0, -0.04, 0.13)), Color(0.05, 0.05, 0.05, 0.0))
	# a circlet of bone spikes about the brow
	for k in 7:
		var a := -0.9 + k * 0.3
		mb.add(MeshBuilder.cone(0.018, 0.12, 4), Transform3D(Basis(Vector3(1, 0, 0), -0.3) * Basis(Vector3(0, 0, 1), -a * 0.4), sk + Vector3(sin(a) * 0.13, 0.12, cos(a) * 0.05 - 0.02)), bone)
	return _finish(mb, gb)


## A sleeve and a bony hand; the right one holds the staff (origin at the shoulder).
func _build_arm(sd: float, staff: bool) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var black := Color(0.06, 0.05, 0.07, 0.0)
	var purple := Color(0.2, 0.08, 0.24, 0.0)
	var bone := Color(0.82, 0.78, 0.68, 0.0)
	var el := Vector3(sd * 0.12, -0.45, 0.08)
	var wr := Vector3(sd * 0.1, -0.85, 0.3)
	mb.limb(Vector3.ZERO, el, 0.11, 0.13, black, 8)
	mb.limb(el, wr, 0.13, 0.2, black, 8)
	mb.add(MeshBuilder.cyl(0.21, 0.21, 0.04, 10), Transform3D(Basis.looking_at(wr - el, Vector3.UP) * Basis(Vector3(1, 0, 0), PI * 0.5), wr), purple)
	for k in 4:   # ragged cuff
		mb.add(MeshBuilder.box(Vector3(0.07, 0.22, 0.01)), Transform3D(Basis(Vector3.UP, k * 1.4) * Basis(Vector3(1, 0, 0), 0.4), wr + Vector3(cos(k * 1.6) * 0.15, -0.1, sin(k * 1.6) * 0.15)), Color(black, 0.6))
	# skeletal hand: palm and four long finger bones, a thumb
	var hand := wr + Vector3(0, -0.06, 0.1)
	mb.add(MeshBuilder.box(Vector3(0.09, 0.03, 0.1)), Transform3D(Basis(), hand), bone)
	if staff:
		for f in 4:
			mb.limb(hand + Vector3(-0.04 + f * 0.027, 0, 0.05), hand + Vector3(-0.04 + f * 0.027, -0.05, 0.02), 0.01, 0.008, bone, 4)
		# the staff: a gnarled shaft, spiralling bands, a horned skull holding the soul-flame
		var lo := hand + Vector3(0, -1.3, -0.05)
		var hi := hand + Vector3(0, 1.75, 0.12)
		var wood := Color(0.13, 0.09, 0.07, 0.0)
		var segs := 6
		for k in segs:
			var a := lo.lerp(hi, float(k) / segs) + Vector3(sin(k * 1.7) * 0.025, 0, cos(k * 2.1) * 0.025)
			var b := lo.lerp(hi, float(k + 1) / segs) + Vector3(sin((k + 1) * 1.7) * 0.025, 0, cos((k + 1) * 2.1) * 0.025)
			mb.limb(a, b, 0.035, 0.032, wood, 6)
			mb.add(MeshBuilder.cyl(0.042, 0.042, 0.03, 8), Transform3D(Basis(), b), Color(0.32, 0.3, 0.3, 0.0))
		var top := hi
		mb.add(MeshBuilder.sphere(0.1, 10, 7), Transform3D(Basis.from_scale(Vector3(0.9, 1.0, 1.15)), top + Vector3(0, 0.08, 0.02)), bone)
		mb.add(MeshBuilder.box(Vector3(0.09, 0.05, 0.08)), Transform3D(Basis(), top + Vector3(0, -0.01, 0.07)), bone.darkened(0.1))
		for e in [1.0, -1.0]:
			mb.limb(top + Vector3(e * 0.07, 0.12, -0.02), top + Vector3(e * 0.2, 0.3, -0.08), 0.03, 0.02, bone.darkened(0.15), 5)
			mb.limb(top + Vector3(e * 0.2, 0.3, -0.08), top + Vector3(e * 0.18, 0.46, 0.02), 0.02, 0.004, bone.darkened(0.2), 4)
			gb.add(MeshBuilder.sphere(0.018, 5, 4), Transform3D(Basis(), top + Vector3(e * 0.035, 0.1, 0.11)), SOUL_GREEN)
		# the soul-flame cradled between the horns
		gb.add(MeshBuilder.sphere(0.09, 10, 6), Transform3D(Basis.from_scale(Vector3(1, 1.4, 1)), top + Vector3(0, 0.36, 0.0)), Color(0.45, 1.0, 0.6, 0.0))
		gb.add(MeshBuilder.cone(0.07, 0.25, 8), Transform3D(Basis(), top + Vector3(0, 0.55, 0.0)), Color(0.35, 0.95, 0.5, 0.0))
		for k in 3:   # trinkets hung from the staff
			mb.limb(top + Vector3(0.0, -0.08, 0.0), top + Vector3(sin(k * 2.0) * 0.08, -0.32 - k * 0.05, cos(k * 2.0) * 0.08), 0.005, 0.005, Color(0.25, 0.2, 0.15, 0.4), 3)
			mb.add(MeshBuilder.sphere(0.025, 5, 4), Transform3D(Basis(), top + Vector3(sin(k * 2.0) * 0.08, -0.34 - k * 0.05, cos(k * 2.0) * 0.08)), Color(bone, 0.5))
	else:
		for f in 4:
			var base := hand + Vector3(-0.035 + f * 0.023, 0, 0.05)
			var mid := base + Vector3((f - 1.5) * 0.02, -0.04, 0.09)
			mb.limb(base, mid, 0.009, 0.007, bone, 4)
			mb.limb(mid, mid + Vector3((f - 1.5) * 0.015, -0.06, 0.05), 0.007, 0.004, bone, 4)
		mb.limb(hand + Vector3(sd * -0.05, 0, 0.0), hand + Vector3(sd * -0.08, -0.03, 0.08), 0.009, 0.006, bone, 4)
		gb.add(MeshBuilder.sphere(0.05, 8, 5), Transform3D(Basis(), hand + Vector3(0, -0.02, 0.18)), Color(0.4, 1.0, 0.55, 0.0))   # a wisp in his palm
	return _finish(mb, gb)


# ------------------------------------------------------------------ animation

func pose(kind: String) -> void:
	if kind != _pose:
		_pose = kind
		_pose_t = 0.0


func flash() -> void:
	_flash_t = 0.1


func set_enrage(on: bool) -> void:
	if on and _flames == null:
		_flames = Abilities._flame_particles(0.6, 1.0, 36)
		_flames.color = Color(0.4, 1.0, 0.45)
		_flames.emission_sphere_radius = 0.6
		_flames.position = Vector3(0, 1.4, 0)
		add_child(_flames)
		_glow.set_shader_parameter("glow", 4.5)
		_light.light_energy = 3.0


func _process(dt: float) -> void:
	_t += dt
	_pose_t += dt
	if _flash_t > 0.0:
		_flash_t -= dt
	_overlay.albedo_color.a = 0.55 if _flash_t > 0.0 else 0.0
	# target rotations for each pose (x = raise forward, z = out to the side)
	var bx := 0.0      # body lean
	var hx := 0.0      # head pitch
	var lx := 0.25     # left arm
	var lz := 0.15
	var rx := 0.15     # right arm (the staff)
	var rz := -0.1
	var bob := sin(_t * 1.6) * 0.06
	match _pose:
		"walk":
			bx = 0.12
			lx = 0.1 + sin(_t * 2.0) * 0.1
			rx = 0.25
		"cast":
			rx = 2.6
			rz = -0.25
			lx = 1.1
			hx = -0.25
		"slam":
			var t := clampf(_pose_t / 0.9, 0.0, 1.0)
			rx = lerpf(2.8, 0.9, smoothstep(0.55, 0.75, t))
			lx = 0.6
			bx = lerpf(-0.1, 0.35, smoothstep(0.55, 0.75, t))
		"summon":
			lx = 2.7
			lz = 0.6
			rx = 2.5
			rz = -0.6
			hx = -0.45
			bx = -0.1
		"channel":
			rx = 1.45
			rz = 0.15
			lx = 1.5
			lz = -0.2
			bx = 0.15
		"rise":
			lx = 1.7
			lz = 1.25
			rx = 1.7
			rz = -1.25
			hx = -0.5
			bob += sin(_t * 6.0) * 0.04
		"die":
			lx = 2.0 * (1.0 - crumble)
			lz = 1.0
			rx = 0.4
			rz = -0.9
			hx = -0.8 + crumble * 1.6
	var k := clampf(dt * 8.0, 0.0, 1.0)
	body.rotation.x = lerpf(body.rotation.x, bx, k)
	head.rotation.x = lerpf(head.rotation.x, hx, k)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, -lx, k)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, lz, k)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, -rx, k)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, rz, k)
	body.position.y = (hover + lift + bob) * (1.0 - crumble)
	body.scale = Vector3(1.0 + crumble * 0.35, maxf(1.0 - crumble * 0.85, 0.08), 1.0 + crumble * 0.35)
	# souls orbit
	for i in _souls.size():
		var a := _t * (1.2 + i * 0.13) + i * TAU / _souls.size()
		var r := 0.9 + 0.2 * sin(_t * 1.7 + i)
		var p := Vector3(cos(a) * r, 1.2 + 0.6 * sin(_t * 2.1 + i * 1.3) + lift, sin(a) * r)
		_souls[i].position = p
		if is_inside_tree():
			_souls[i].look_at(global_transform * (p + Vector3(-sin(a), 0, cos(a))), Vector3.UP)
		_souls[i].visible = crumble < 0.5
	_light.light_energy = (1.8 if _flames == null else 3.0) * (0.85 + 0.15 * sin(_t * 9.0)) * (1.0 - crumble)


## Where the soul-flame atop the staff is, in the world.
func tip_position() -> Vector3:
	return staff_tip.global_position
