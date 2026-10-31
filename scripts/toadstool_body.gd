class_name ToadstoolBody
extends Node3D
## The playable Toadstool Knight: the Forest boss's body (ToadstoolModel: silver plate, a big red
## spotted toadstool cap, a violet spore-glowing sword) at player size - he's small, about 1.45 m
## to the top of his cap. Faces -Z, origin at the feet.
##
## ToadstoolModel plays whole clips for the boss; here an AnimationTree drives the same rig so his
## legs keep running while he fights:
##   locomotion  idle / run blended by ground speed
##   slash       upper-body one-shot: the overhead cut, every Spore Blade swing (aimed with a spine twist)
##   cast        upper-body one-shot: blade swept low, then thrust forward
##   hit         upper-body flinch
## die() plays the death (he staggers and topples backwards). Spores drift off his cap.
## RosterHero drives it for the playable knight; RosterModel shows him on character select.

const SCALE := 0.8                    # x ToadstoolModel's 1.8 m
const SKEL := "Armature/Skeleton3D"   # no-i18n
const RUN_SPEED := 6.5
const SLASH_SPEED := 2.6
const CAST_SPEED := 1.4
const HIT_SEG := [0.1, 0.9]
const MAX_TWIST := deg_to_rad(80.0)

var model: ToadstoolModel
var tree: AnimationTree
var twist: SpineTwist
var dead := false
var slashes := 0                      # tests
var casts := 0
var _twist_hold := 0.0
var _spores: CPUParticles3D
var _death: AnimationPlayer
var _death_end := 0.0


static func create() -> ToadstoolBody:
	return ToadstoolBody.new()


func _ready() -> void:
	model = ToadstoolModel.new()
	model.animated = false
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	var sk := model._skeleton()
	_build_tree()
	if sk:
		twist = SpineTwist.new()
		sk.add_child(twist)
	# A few spores drifting up off the cap
	_spores = Abilities._flame_particles(0.09, 1.8, 10)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.6, 1.0, 0.8))
	grad.set_color(1, Color(0.5, 0.2, 0.8, 0.0))
	_spores.color_ramp = grad
	_spores.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_spores.emission_sphere_radius = 0.3
	_spores.gravity = Vector3(0, 0.35, 0)
	_spores.initial_velocity_min = 0.05
	_spores.initial_velocity_max = 0.25
	(_spores.mesh as QuadMesh).size = Vector2(0.07, 0.07)
	_spores.position = Vector3(0, 1.45, 0)
	add_child(_spores)


func _clip(name: String, seg: Array, loop := false) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = "c/" + name
	if not seg.is_empty():
		n.use_custom_timeline = true
		n.start_offset = seg[0]
		n.timeline_length = seg[1] - seg[0]
		n.stretch_time_scale = false
		n.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return n


func _one_shot(fade_in: float, fade_out: float) -> AnimationNodeOneShot:
	var os := AnimationNodeOneShot.new()
	os.fadein_time = fade_in
	os.fadeout_time = fade_out
	os.filter_enabled = true
	for b in HeroModel.UPPER_BONES:
		os.set_filter_path(NodePath("%s:%s" % [SKEL, b]), true)
	return os


func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.add_animation_library("c", load(ToadstoolModel.DIR.path_join("anims.res")))
	var bt := AnimationNodeBlendTree.new()
	var walk := AnimationNodeBlendSpace1D.new()
	walk.add_blend_point(_clip("idle", []), 0.0, -1, "idle")
	walk.add_blend_point(_clip("run", []), RUN_SPEED, -1, "run")
	walk.min_space = 0.0
	walk.max_space = RUN_SPEED
	bt.add_node("loco", walk, Vector2(0, 0))
	bt.add_node("loco_speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("loco_speed", 0, "loco")
	var slash: Array = ToadstoolModel.SEG["slash"]
	var cast: Array = ToadstoolModel.SEG["cast"]
	var layers := [
		["cast", "ability", [cast[1], cast[2]], 0.1, 0.25, CAST_SPEED],
		["hit", "hit", HIT_SEG, 0.05, 0.2, 1.6],
		["slash", "attack", [slash[1], slash[2]], 0.06, 0.18, SLASH_SPEED],
	]
	var prev := "loco_speed"
	var x := 400
	for l in layers:
		var name: String = l[0]
		bt.add_node(name, _one_shot(l[3], l[4]), Vector2(x, 0))
		bt.add_node(name + "_clip", _clip(l[1], l[2]), Vector2(x - 200, 200))
		bt.add_node(name + "_speed", AnimationNodeTimeScale.new(), Vector2(x - 100, 200))
		bt.connect_node(name + "_speed", 0, name + "_clip")
		bt.connect_node(name, 0, prev)
		bt.connect_node(name, 1, name + "_speed")
		prev = name
		x += 300
	bt.connect_node("output", 0, prev)
	tree.tree_root = bt
	model._rig.add_child(tree)
	tree.active = true
	for l in layers:
		tree.set("parameters/%s_speed/scale" % l[0], l[5])
	tree.set("parameters/loco_speed/scale", 1.0)


func _fire(layer: String) -> void:
	if tree != null and tree.active:
		tree.set("parameters/%s/request" % layer, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## The overhead cut toward `target` (world space): the torso turns to face it.
func slash(target := Vector3.INF) -> void:
	if dead:
		return
	slashes += 1
	_fire("slash")
	if twist != null and target != Vector3.INF:
		var to := target - global_position
		var local := global_transform.basis.orthonormalized().inverse() * to
		twist.target_angle = clampf(atan2(-local.x, -local.z), -MAX_TWIST, MAX_TWIST)
		_twist_hold = 0.45


func cast() -> void:
	if dead:
		return
	casts += 1
	_fire("cast")


func hit() -> void:
	if not dead:
		_fire("hit")


## He staggers and topples over backwards (the run is over).
func die() -> void:
	if dead:
		return
	dead = true
	tree.active = false
	_spores.emitting = false
	_death = AnimationPlayer.new()
	model._rig.add_child(_death)
	_death.root_node = NodePath("..")
	_death.add_animation_library("c", load(ToadstoolModel.DIR.path_join("anims.res")))
	var seg: Array = ToadstoolModel.SEG["death"]
	_death.play("c/" + str(seg[0]), 0.1, 0.8)
	_death.seek(float(seg[1]), true)
	_death_end = float(seg[2])
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(model, "rotation:x", 1.35, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(model, "position:y", 0.12, 0.7)


## Where the sword's tip is (world space).
func tip() -> Vector3:
	if model != null and is_instance_valid(model.blade) and model.blade.is_inside_tree():
		return model.blade.global_transform * Vector3(0, ToadstoolModel.BLADE_TIP, 0)
	return global_position + Vector3(0, 1.0, 0) - global_transform.basis.z * 0.6


## Every frame: ground speed (m/s) and whether he's in the air.
func animate(dt: float, speed: float, _airborne := false) -> void:
	if dead:
		if _death and _death.current_animation_position >= _death_end - 0.001:
			_death.pause()
		return
	tree.set("parameters/loco/blend_position", minf(speed, RUN_SPEED))
	tree.set("parameters/loco_speed/scale", clampf(speed / RUN_SPEED, 1.0, 2.2) if speed > RUN_SPEED else 1.0)
	_twist_hold -= dt
	if _twist_hold <= 0.0 and twist != null:
		twist.target_angle = 0.0


func is_slashing() -> bool:
	return tree != null and bool(tree.get("parameters/slash/active"))


func set_dim(f: float) -> void:
	if model:
		model.set_dim(f)


func set_hurt(f: float) -> void:
	if model:
		model.hurt = f
