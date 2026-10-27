class_name HeroModel
extends Node3D
## The fire wizard as a rigged, textured model (generated with Higgsfield / Meshy) driven by an
## AnimationTree. Faces -Z, origin at the feet, 1.8 m tall.
##
## Layers, bottom to top:
##   locomotion  idle / walk / run blended by ground speed (run sped up at high speed)
##   jump        full-body one-shot (airborne tuck) when leaving the ground
##   nova        full-body one-shot: staff slammed into the ground
##   inferno     upper-body one-shot: both arms thrown to the sky
##   meteor      full-body one-shot: overhead wind-up and slam, then he vanishes
##   hit         upper-body one-shot flinch
##   fire        upper-body one-shot: the short staff thrust from the cast clip, every fireball
## Upper-body layers only touch the spine, arms and head, so the legs keep running underneath.
## A spine twist (SpineTwist) turns the torso toward the fireball's target.
##
## Same interface as the old procedural WizardModel: attack(), staff_tip(), set_dim(), set_hurt().

const SCENE := "res://models/wizard/wizard.glb"
const ANIMS := "res://models/wizard/wizard_anims.res"
const SKEL := "Armature/Skeleton3D"
const UPPER_BONES := ["Spine02", "Spine01", "Spine", "neck", "Head", "head_end", "headfront",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"]

# Clip segments [start, end] in seconds, picked from the clips' poses
const FIRE_SEG := [2.28, 2.85]       # wind-up at the shoulder -> thrust (peak ~2.45) -> recover
const NOVA_SEG := [1.35, 2.65]       # rise -> slam (~1.75) -> hold
const INFERNO_SEG := [1.5, 2.5]      # arms thrown up (~1.9)
const METEOR_SEG := [0.6, 1.42]      # both arms overhead -> slam down (~1.35), then he vanishes
const HIT_SEG := [0.15, 1.05]
const JUMP_SEG := [0.5, 1.05]        # airborne tuck
const FIRE_SPEED := 1.25
const WALK_SPEED := 2.5              # m/s where the walk clip looks right
const RUN_SPEED := 6.5               # m/s where the run clip looks right
const MAX_TWIST := deg_to_rad(80.0)
const TIP := Vector3(0.0, 1.0, 0.0)    # in the flame above the coal, staff space (metres)
const VANISH_TIME := 0.55            # slam lands ~(1.35 - 0.6) / 1.4 s in

var tree: AnimationTree
var skeleton: Skeleton3D
var staff: Node3D
var twist: SpineTwist
var _rig: Node3D
var flame: StaffFlame
var _mats: Array[StandardMaterial3D] = []
var _base_albedo: Array[Color] = []
var _staff_mats: Array = []          # [material, albedo, emission energy]
var _particles: Array[CPUParticles3D] = []
var _dim := 1.0
var _hurt := 0.0
var _time := 0.0
var _speed := 0.0
var _airborne := false
var _twist_hold := 0.0
var _vanish_t := -1.0
var _requested := {}


func _ready() -> void:
	_rig = (load(SCENE) as PackedScene).instantiate()
	_rig.rotation.y = PI            # the GLB faces +Z; the game faces -Z
	add_child(_rig)
	skeleton = _rig.get_node(SKEL)
	var old_player := _rig.get_node_or_null("AnimationPlayer")
	if old_player:
		old_player.free()
	_prepare_materials()
	_build_tree()
	_build_staff()
	twist = SpineTwist.new()
	skeleton.add_child(twist)

	# Soft warm fill so he reads against the dark swamp (the old model glowed on its own)
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.72, 0.5)
	fill.light_energy = 0.7
	fill.omni_range = 2.6
	fill.position = Vector3(0.0, 1.5, -0.9)
	fill.shadow_enabled = false
	add_child(fill)

	# A few embers drifting off the coat hem
	var hem := Abilities._flame_particles(0.18, 0.7, 14)
	hem.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	hem.emission_ring_axis = Vector3.UP
	hem.emission_ring_radius = 0.32
	hem.emission_ring_inner_radius = 0.2
	hem.emission_ring_height = 0.05
	hem.position.y = 0.12
	add_child(hem)
	_particles.append(hem)


# ------------------------------------------------------------------ building

func _prepare_materials() -> void:
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			if src is StandardMaterial3D:
				var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				mat.emission_enabled = true
				mat.emission = Color.BLACK
				m.set_surface_override_material(s, mat)
				_mats.append(mat)
				_base_albedo.append(mat.albedo_color)


func _clip(name: String, seg: Array, loop := false) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = "w/" + name
	if not seg.is_empty():
		n.use_custom_timeline = true
		n.start_offset = seg[0]
		n.timeline_length = seg[1] - seg[0]
		n.stretch_time_scale = false
		n.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return n


func _one_shot(fade_in: float, fade_out: float, upper: bool) -> AnimationNodeOneShot:
	var os := AnimationNodeOneShot.new()
	os.fadein_time = fade_in
	os.fadeout_time = fade_out
	if upper:
		os.filter_enabled = true
		for b in UPPER_BONES:
			os.set_filter_path(NodePath("%s:%s" % [SKEL, b]), true)
	return os


func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.add_animation_library("w", load(ANIMS))
	var bt := AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(_clip("idle", []), 0.0, -1, "idle")
	loco.add_blend_point(_clip("walk", []), WALK_SPEED, -1, "walk")
	loco.add_blend_point(_clip("run", []), RUN_SPEED, -1, "run")
	loco.min_space = 0.0
	loco.max_space = RUN_SPEED
	bt.add_node("loco", loco, Vector2(0, 0))
	bt.add_node("loco_speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("loco_speed", 0, "loco")

	var layers := [
		# [name, clip, segment, fade in, fade out, upper body only, time scale]
		["jump", "jump", JUMP_SEG, 0.08, 0.25, false, 1.0],
		["nova", "nova", NOVA_SEG, 0.1, 0.3, false, 1.35],
		["inferno", "inferno", INFERNO_SEG, 0.12, 0.3, true, 1.3],
		["meteor", "meteor", METEOR_SEG, 0.08, 0.1, false, 1.4],
		["hit", "hit", HIT_SEG, 0.05, 0.2, true, 1.6],
		["fire", "cast", FIRE_SEG, 0.06, 0.18, true, FIRE_SPEED],
	]
	var prev := "loco_speed"
	var x := 400
	for l in layers:
		var name: String = l[0]
		bt.add_node(name, _one_shot(l[3], l[4], l[5]), Vector2(x, 0))
		bt.add_node(name + "_clip", _clip(l[1], l[2]), Vector2(x - 200, 200))
		bt.add_node(name + "_speed", AnimationNodeTimeScale.new(), Vector2(x - 100, 200))
		bt.connect_node(name + "_speed", 0, name + "_clip")
		bt.connect_node(name, 0, prev)
		bt.connect_node(name, 1, name + "_speed")
		prev = name
		x += 300
	bt.connect_node("output", 0, prev)
	tree.tree_root = bt
	_rig.add_child(tree)            # root_node ".." = the GLB scene root
	tree.active = true
	for l in layers:
		tree.set("parameters/%s_speed/scale" % l[0], l[6])
	tree.set("parameters/loco_speed/scale", 1.0)


func _build_staff() -> void:
	var attach := BoneAttachment3D.new()
	attach.bone_name = "RightHand"
	skeleton.add_child(attach)
	# Place the staff upright through the palm in the rest pose, so the hand's animation
	# carries it from there. Skeleton space is in centimetres (the Armature is scaled 0.01).
	var hand := skeleton.find_bone("RightHand")
	var fore := skeleton.find_bone("RightForeArm")
	var hand_rest := skeleton.get_bone_global_rest(hand)
	var dir := (hand_rest.origin - skeleton.get_bone_global_rest(fore).origin).normalized()
	var palm := hand_rest.origin + dir * 7.0
	var want := Transform3D(Basis().scaled(Vector3.ONE * 100.0), palm)
	staff = Node3D.new()
	staff.transform = hand_rest.affine_inverse() * want
	attach.add_child(staff)

	var wood := _std(Color(0.25, 0.14, 0.08))
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.022
	shaft.bottom_radius = 0.03
	shaft.height = 1.6
	shaft.radial_segments = 8
	shaft.material = wood
	var shaft_mi := MeshInstance3D.new()
	shaft_mi.mesh = shaft
	shaft_mi.position = Vector3(0, 0.05, 0)  # grip a bit below the middle
	staff.add_child(shaft_mi)
	# Gnarled crown cradling the burning coal
	for k in 3:
		var prong := CylinderMesh.new()
		prong.top_radius = 0.008
		prong.bottom_radius = 0.018
		prong.height = 0.22
		prong.radial_segments = 6
		prong.material = wood
		var p := MeshInstance3D.new()
		p.mesh = prong
		var a := TAU * k / 3.0
		p.position = Vector3(cos(a) * 0.05, 0.86, sin(a) * 0.05)
		p.rotation = Vector3(sin(a) * 0.45, 0.0, -cos(a) * 0.45)
		staff.add_child(p)
	flame = StaffFlame.new()
	flame.position = Vector3(0, 0.9, 0)
	staff.add_child(flame)
	for m in [wood]:
		_staff_mats.append([m, m.albedo_color, m.emission_energy_multiplier])


func _std(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


# ------------------------------------------------------------------ interface

## Thrust the staff toward `target` (world space): plays the upper-body cast and twists the
## torso toward it. Returns the staff tip, where the projectile spawns.
func attack(target: Vector3) -> Vector3:
	_fire("fire")
	var to := target - global_position
	var local := global_transform.basis.orthonormalized().inverse() * to
	# Model faces -Z: yaw of the target relative to facing, positive = to the left
	var yaw := atan2(-local.x, -local.z)
	twist.target_angle = clampf(yaw, -MAX_TWIST, MAX_TWIST)
	_twist_hold = 0.45
	return staff_tip()


func staff_tip() -> Vector3:
	return staff.global_transform * TIP


## Ground speed (m/s) and whether he's in the air; called every frame by the player.
func set_motion(speed: float, airborne: bool) -> void:
	_speed = speed
	if airborne and not _airborne:
		_fire("jump")
	_airborne = airborne


func play_hit() -> void:
	_fire("hit")


## Ability cast animations: 0 Inferno, 1 Fire Nova, 2 Meteor.
func play_ability(i: int) -> void:
	match i:
		0:
			_fire("inferno")
		1:
			_fire("nova")
		2:
			_fire("meteor")


## Meteor: raise the arms, then disappear (the player is already invulnerable).
func vanish() -> void:
	_fire("meteor")
	_vanish_t = VANISH_TIME


func reappear() -> void:
	_vanish_t = -1.0
	visible = true


## True while a one-shot layer is playing (or was just requested and starts next frame).
func is_playing(layer: String) -> bool:
	return bool(tree.get("parameters/%s/active" % layer)) or _time - float(_requested.get(layer, -10.0)) < 0.1


func _fire(layer: String) -> void:
	tree.set("parameters/%s/request" % layer, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_requested[layer] = _time


## Scale the whole character's brightness (1 = normal, 0.5 = immune).
func set_dim(f: float) -> void:
	if is_equal_approx(f, _dim):
		return
	_dim = f
	for k in _mats.size():
		var c := _base_albedo[k]
		_mats[k].albedo_color = Color(c.r * f, c.g * f, c.b * f, c.a)
	for e in _staff_mats:
		var m: StandardMaterial3D = e[0]
		var c: Color = e[1]
		m.albedo_color = Color(c.r * f, c.g * f, c.b * f, c.a)
		m.emission_energy_multiplier = e[2] * f
	for p in _particles:
		p.color = Color(f, f, f, 1.0)
	flame.set_dim(f)


func set_hurt(amount: float) -> void:
	if is_equal_approx(amount, _hurt):
		return
	_hurt = amount
	for m in _mats:
		m.emission = Color(1.0, 0.85, 0.75) * clampf(amount, 0.0, 1.0)


func _process(dt: float) -> void:
	_time += dt
	tree.set("parameters/loco/blend_position", minf(_speed, RUN_SPEED))
	tree.set("parameters/loco_speed/scale", clampf(_speed / RUN_SPEED, 1.0, 2.2) if _speed > RUN_SPEED else 1.0)
	_twist_hold -= dt
	if _twist_hold <= 0.0:
		twist.target_angle = 0.0
	if _vanish_t >= 0.0:
		_vanish_t -= dt
		if _vanish_t < 0.0:
			visible = false
