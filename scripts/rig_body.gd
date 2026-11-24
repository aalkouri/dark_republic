class_name RigBody
extends Node3D
## A playable character on an AI-generated, auto-rigged model (models/<id>/<id>.glb, made by
## tools/gen_rig_clips.py: UniRig skeleton renamed to the Meshy bone names, five clips written in
## code and saved to anims.res by tools/extract_clips.gd). It stands in for the bodies that used to
## be built from primitives (HeroBody, PharaohBody, NecromancerBody, SingeBody, ToadstoolBody,
## LocoBody) and answers the same PlayableBoss interface, plus the extras their kits call:
##   animate(dt, speed, airborne)   every frame
##   attack(target) / slash(target) / shake()   the weapon move (an upper-body one-shot)
##   cast(i) / hold(secs)           a cast pose for ability slot i (2 = the ultimate)
##   hit() / die()                  flinch / topples over backwards
##   tip() / hand(k)                where shots leave from (a hand)
##   set_curl(on)                   Singe's ball form (tucked small, spinning)
##   party / destroy / turret_yaw   Loco Robotico's modes (bouncing dance / spinning turret)
## The models themselves hold nothing, so each takes the weapon its code-built predecessor made
## (Death's scythe, the Pharaoh's crook and flail, the Necromancer's staff, the Knight's sword,
## Loco's maracas, ...): the old body is built once, its in-hand weapon nodes are moved onto this
## skeleton's hands, and the rest of it is thrown away. They show while `drawn` (attacking or
## casting) and vanish after; there is no belt / back copy.
## Faces -Z, origin at the feet; the model's height is baked into the GLB.

## PlayableBoss kind -> model folder
const MODEL := {
	"pharaoh": "pharaoh", "necromancer": "necromancer", "singe": "singe", "death": "death",
	"billy_bulldog": "billy_bulldog", "cowboy": "cowboy", "platypus": "platypus",
	"bog_witch": "bog_witch", "toadstool": "toadstool_knight", "loco": "loco_robotico",
}
const DIR := "res://models/%s/%s"
const SKEL := "Armature/Skeleton3D"
const RUN_SPEED := 6.5
## Segments of the "ability" clip per slot, and of the "attack" and "hit" clips
const CAST_SEG := [[0.0, 1.0], [1.1, 2.1], [2.2, 3.4]]
const CAST_SPEED := [1.3, 1.3, 1.0]
const FIRE_SEG := [0.05, 0.8]
const FIRE_SPEED := 1.7
const HIT_SEG := [0.0, 0.95]
const DIE_TIME := 0.7

var kind := "cowboy"
var drawn := false
var dead := false
var attacks := 0                     # tests
var casts := 0
var slashes := 0
var shakes := 0
var curled := false                  # Singe
var party := false                   # Loco Robotico
var destroy := false
var turret_yaw := 0.0

var model: Node3D                    # the GLB (flinch / death tilt / curl applied here)
var skeleton: Skeleton3D
var tree: AnimationTree
var height := 1.8
var _busy_t := 0.0
var _atk_t := 0.0
var _die_t := 0.0
var _time := 0.0
var _side := 0
var _aim := 0.0
var _dim := 1.0
var _hurt := 0.0
var _overlay: StandardMaterial3D
var _hands: Array[int] = [-1, -1]    # left, right
var weapons: Array[Node3D] = []      # taken from the code-built body; shown while drawn
var stowed: Array[Node3D] = []       # (none: there is no belt / back copy)
var pose := "idle"                   # idle / run / cast / die (tests)
var _cast_t := 0.0


static func has_model(p_kind: String) -> bool:
	if not MODEL.has(p_kind):
		return false
	var id: String = MODEL[p_kind]
	return ResourceLoader.exists(DIR % [id, id + ".glb"]) and ResourceLoader.exists(DIR % [id, "anims.res"])


static func create(p_kind: String) -> RigBody:
	var b := RigBody.new()
	b.kind = p_kind
	return b


func _ready() -> void:
	var id: String = MODEL[kind]
	model = (load(DIR % [id, id + ".glb"]) as PackedScene).instantiate()
	model.rotation.y = PI            # the GLB faces +Z; the game faces -Z
	add_child(model)
	skeleton = model.get_node_or_null(SKEL)
	var old := model.find_child("AnimationPlayer", true, false)
	if old:
		old.free()
	var box := AABB()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		box = box.merge((mi as MeshInstance3D).get_aabb())
	height = maxf(box.size.y, 0.5)
	if skeleton:
		_hands = [skeleton.find_bone("LeftHand"), skeleton.find_bone("RightHand")]
		_build_tree(id)
		_take_weapons()
	_overlay = PlayableBoss.overlay()
	PlayableBoss.apply_overlay(model, _overlay)


func _clip(n: String, seg: Array) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = "c/" + n
	if not seg.is_empty():
		a.use_custom_timeline = true
		a.start_offset = seg[0]
		a.timeline_length = seg[1] - seg[0]
		a.stretch_time_scale = false
		a.loop_mode = Animation.LOOP_NONE
	return a


func _build_tree(id: String) -> void:
	tree = AnimationTree.new()
	tree.add_animation_library("c", load(DIR % [id, "anims.res"]))
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(_clip("idle", []), 0.0, -1, "idle")
	loco.add_blend_point(_clip("run", []), RUN_SPEED, -1, "run")
	loco.min_space = 0.0
	loco.max_space = RUN_SPEED
	bt.add_node("loco", loco, Vector2(0, 0))
	bt.add_node("loco_speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("loco_speed", 0, "loco")
	var layers := []
	for k in 3:
		layers.append(["cast%d" % k, "ability", CAST_SEG[k], 0.1, 0.3, CAST_SPEED[k]])
	layers.append(["hit", "hit", HIT_SEG, 0.05, 0.2, 1.6])
	layers.append(["fire", "attack", FIRE_SEG, 0.06, 0.18, FIRE_SPEED])
	var prev := "loco_speed"
	var x := 400
	for l in layers:
		var n: String = l[0]
		var os := AnimationNodeOneShot.new()
		os.fadein_time = l[3]
		os.fadeout_time = l[4]
		os.filter_enabled = true
		for b in HeroModel.UPPER_BONES:
			os.set_filter_path(NodePath("%s:%s" % [SKEL, b]), true)
		bt.add_node(n, os, Vector2(x, 0))
		bt.add_node(n + "_clip", _clip(l[1], l[2]), Vector2(x - 200, 200))
		bt.add_node(n + "_speed", AnimationNodeTimeScale.new(), Vector2(x - 100, 200))
		bt.connect_node(n + "_speed", 0, n + "_clip")
		bt.connect_node(n, 0, prev)
		bt.connect_node(n, 1, n + "_speed")
		prev = n
		x += 300
	bt.connect_node("output", 0, prev)
	tree.tree_root = bt
	model.add_child(tree)
	tree.active = true
	for l in layers:
		tree.set("parameters/%s_speed/scale" % l[0], l[5])
	tree.set("parameters/loco_speed/scale", 1.0)


## Builds the old code-built body just long enough to lift its weapon(s) into this model's hands.
func _take_weapons() -> void:
	var donor: Node3D
	match kind:
		"pharaoh": donor = PharaohBody.create()
		"necromancer": donor = NecromancerBody.create()
		"toadstool": donor = ToadstoolBody.create()
		"loco": donor = LocoBody.create()
		"singe": return
		_: donor = HeroBody.create(kind) if kind in HeroBody.KINDS else null
	if donor == null:
		return
	add_child(donor)
	var take := []   # [node, hand (0 left, 1 right)]
	if donor is PharaohBody:
		take = [[donor.model.hand_l, 0], [donor.model.hand_r, 1]]
	elif donor is NecromancerBody:
		take = [[donor.staff, 1]]
	elif donor is ToadstoolBody:
		take = [[donor.model.blade, 1]]
	elif donor is LocoBody:
		take = [[donor._hand_maracas[0], 0], [donor._hand_maracas[1], 1]] if donor._hand_maracas.size() >= 2 else []
	elif donor is HeroBody and donor.weapon != null:
		take = [[donor.weapon, 1]]
	for t in take:
		var w: Node3D = t[0]
		var bone: int = _hands[t[1]]
		if w == null or bone < 0:
			continue
		var gb := w.global_transform.basis
		var att := BoneAttachment3D.new()
		skeleton.add_child(att)
		att.bone_idx = bone
		w.get_parent().remove_child(w)
		att.add_child(w)
		# in the hand, turned as the old body held it at rest
		var hand_g := skeleton.global_transform * skeleton.get_bone_global_rest(bone)
		w.transform = hand_g.affine_inverse() * Transform3D(gb, hand_g.origin)
		w.visible = false
		weapons.append(w)
	donor.free()


func _show_weapons(on: bool) -> void:
	drawn = on
	for w in weapons:
		w.visible = on and not dead


func _fire(layer: String) -> void:
	if tree:
		tree.set("parameters/%s/request" % layer, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _busy(secs: float) -> void:
	_busy_t = maxf(_busy_t, secs + RosterHero.HOLSTER_DELAY)
	_show_weapons(true)


# ------------------------------------------------------------------ the interface

func attack(target: Vector3) -> Vector3:
	if dead:
		return tip()
	attacks += 1
	_side = 1
	if kind == "loco":   # a maraca shake, alternating hands
		shakes += 1
		_side = shakes % 2
	elif kind == "toadstool":
		slashes += 1
	_atk_t = (FIRE_SEG[1] - FIRE_SEG[0]) / FIRE_SPEED
	_busy(_atk_t)
	_fire("fire")
	if target != Vector3.INF and is_inside_tree():
		var local := global_transform.basis.orthonormalized().inverse() * (target - global_position)
		_aim = clampf(atan2(-local.x, -local.z), -1.0, 1.0) * 0.6
	return tip()


## The Toadstool Knight's cut (ToadstoolBody's name for the attack).
func slash(target := Vector3.INF) -> void:
	attack(target)


## Loco Robotico's maraca shake: returns the hand that shook (0 left, 1 right).
func shake() -> int:
	attack(Vector3.INF)
	return _side


func draw(dur := 0.6) -> void:
	_busy(dur)


func is_attacking() -> bool:
	return _atk_t > 0.0


func is_slashing() -> bool:
	return _atk_t > 0.0


## Where shots leave from: a hand (the right one, or the one that shook last).
func tip(side := -1) -> Vector3:
	return hand(_side if side < 0 else side)


func hand(k: int) -> Vector3:
	var b: int = _hands[clampi(k, 0, 1)]
	if skeleton == null or b < 0 or not is_inside_tree():
		return global_position + Vector3(0, height * 0.6, 0) if is_inside_tree() else Vector3(0, height * 0.6, 0)
	return skeleton.global_transform * skeleton.get_bone_global_pose(b).origin


func cast(i := 0) -> void:
	if dead:
		return
	casts += 1
	var k := clampi(i, 0, 2)
	var secs: float = (CAST_SEG[k][1] - CAST_SEG[k][0]) / CAST_SPEED[k]
	_cast_t = maxf(_cast_t, secs)
	_busy(secs)
	_atk_t = 0.0
	_fire("cast%d" % k)


## Hold a cast pose for `secs` (the Necromancer's Soul Drain beam): hands pushed forward.
func hold(secs: float) -> void:
	if dead:
		return
	_cast_t = maxf(_cast_t, secs)
	_busy(secs)
	_fire("cast0")


func set_curl(on: bool) -> void:
	curled = on


func hit() -> void:
	if not dead:
		_fire("hit")


func die() -> void:
	dead = true
	_show_weapons(false)
	_die_t = 0.0


func animate(dt: float, speed: float, airborne := false, _swell := 0.0, _flinch := 0.0) -> void:
	_time += dt
	_atk_t = maxf(0.0, _atk_t - dt)
	_cast_t = maxf(0.0, _cast_t - dt)
	pose = "die" if dead else ("cast" if _cast_t > 0.0 else ("run" if speed > 0.5 and not airborne else "idle"))
	if _busy_t > 0.0:
		_busy_t -= dt
		if _busy_t <= 0.0:
			_show_weapons(false)
	if tree:
		tree.set("parameters/loco/blend_position", 0.0 if (dead or airborne) else minf(speed, RUN_SPEED))
		tree.set("parameters/loco_speed/scale", maxf(1.0, speed / RUN_SPEED))
	var rot := Vector3(0.0, PI, 0.0)
	var pos := Vector3.ZERO
	var scl := 1.0
	if dead:   # topples over backwards
		_die_t = minf(_die_t + dt, DIE_TIME)
		var k := _die_t / DIE_TIME
		rot.x = -k * k * 1.5
		pos.y = 0.08 * height * k
	elif curled:   # tucked into a ball, rolling
		scl = 0.55
		rot.x = fmod(_time * 16.0, TAU)
		pos.y = height * 0.28
	elif destroy:   # DESTROY Mode: the whole robot turns with the beam
		rot.y = PI + turret_yaw - global_rotation.y + rotation.y
	elif party:   # Party Mode: bouncing and swaying
		pos.y = absf(sin(_time * 9.0)) * 0.1 * height
		rot.y = PI + sin(_time * 4.5) * 0.5
		rot.z = sin(_time * 9.0) * 0.08
	else:
		_aim = lerpf(_aim, 0.0, minf(1.0, dt * 3.0)) if _atk_t <= 0.0 else _aim
		rot.y = PI + _aim
	model.rotation = rot
	model.position = pos
	model.scale = Vector3.ONE * scl


func set_dim(f: float) -> void:
	_dim = f
	PlayableBoss.tint(_overlay, _dim, _hurt)


func set_hurt(f: float) -> void:
	_hurt = f
	PlayableBoss.tint(_overlay, _dim, _hurt)
