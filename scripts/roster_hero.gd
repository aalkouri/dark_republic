class_name RosterHero
extends HeroBase
## A playable roster character (Ice, Thunder and Dark Wizards so far): the rigged Higgsfield/Meshy
## model from models/<id>/ with its Lean clip set (idle, run, hit, attack, ability) driven by an
## AnimationTree, holding its weapon from RosterWeapons. Faces -Z, origin at the feet, 1.8 m.
##
## Layers, bottom to top:
##   locomotion  idle / run blended by ground speed (run sped up when faster)
##   cast0..2    upper-body one-shots: a segment of the ability clip per slot
##   hit         upper-body flinch
##   fire        upper-body one-shot: the staff thrust from the attack clip, every weapon shot
## Upper-body layers leave the legs running. A spine twist turns the torso toward each target.

const DIR := "res://models/%s"
const SKEL := "Armature/Skeleton3D"
const UPPER_BONES := HeroModel.UPPER_BONES
const RUN_SPEED := 6.5
const MAX_TWIST := deg_to_rad(80.0)
const HIT_SEG := [0.1, 0.95]
const STAFF_HEAD := Vector3(0.0, 0.9, 0.0)   # staff space (RosterWeapons._staff)

## Per character: clip segments [start, end] picked from contact sheets of the clips, the
## playback speed of the thrust, the colours of its magic and its idle particles.
const CFG := {
	"ice_wizard": {
		"fire": [1.35, 2.05], "fire_speed": 1.5,
		"cast": [[0.3, 1.0], [0.3, 1.0], [1.6, 2.4]], "cast_speed": [1.3, 1.3, 1.1],
		"main": Color(0.6, 0.88, 1.0), "deep": Color(0.2, 0.45, 0.85), "light": Color(0.92, 0.98, 1.0),
	},
	"thunder_wizard": {
		"fire": [1.5, 2.15], "fire_speed": 1.5,
		"cast": [[1.2, 2.0], [1.2, 2.0], [0.3, 1.2]], "cast_speed": [1.3, 1.3, 1.1],
		"main": Color(1.0, 0.9, 0.35), "deep": Color(0.5, 0.35, 1.0), "light": Color(1.0, 1.0, 0.85),
	},
	"dark_wizard": {
		"fire": [0.65, 1.4], "fire_speed": 1.6,
		"cast": [[0.0, 1.3], [0.0, 1.3], [0.0, 1.3]], "cast_speed": [1.4, 1.4, 1.1],
		"main": Color(0.7, 0.32, 1.0), "deep": Color(0.2, 0.05, 0.32), "light": Color(0.9, 0.72, 1.0),
	},
}

var char_id := ""
var tree: AnimationTree
var skeleton: Skeleton3D
var weapon: Node3D
var twist: SpineTwist
var _rig: Node3D
var _mats: Array[StandardMaterial3D] = []
var _base_albedo: Array[Color] = []
var _particles: Array[CPUParticles3D] = []
var _dim := 1.0
var _hurt := 0.0
var _time := 0.0
var _speed := 0.0
var _twist_hold := 0.0
var _requested := {}


static func is_playable(id: String) -> bool:
	return CFG.has(id) and ResourceLoader.exists((DIR % id).path_join(id + ".glb"))


static func create(id: String) -> RosterHero:
	var h := RosterHero.new()
	h.char_id = id
	return h


## The character's magic colours: "main", "deep", "light".
static func color(id: String, key: String) -> Color:
	return CFG.get(id, CFG["ice_wizard"])[key]


func _ready() -> void:
	var dir := DIR % char_id
	_rig = (load(dir.path_join(char_id + ".glb")) as PackedScene).instantiate()
	_rig.rotation.y = PI            # the GLB faces +Z; the game faces -Z
	add_child(_rig)
	skeleton = _rig.get_node(SKEL)
	var old_player := _rig.get_node_or_null("AnimationPlayer")
	if old_player:
		old_player.free()
	_prepare_materials()
	_build_tree()
	weapon = RosterWeapons.attach(char_id, skeleton)
	twist = SpineTwist.new()
	skeleton.add_child(twist)

	var cfg: Dictionary = CFG[char_id]
	var fill := OmniLight3D.new()
	fill.light_color = (cfg["main"] as Color).lerp(Color.WHITE, 0.4)
	fill.light_energy = 0.7
	fill.omni_range = 2.6
	fill.position = Vector3(0.0, 1.5, -0.9)
	fill.shadow_enabled = false
	add_child(fill)
	_add_motes(cfg)


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


## Drifting motes around the hem in the character's colours: snow, sparks or shadow.
func _add_motes(cfg: Dictionary) -> void:
	var p := Abilities._flame_particles(0.14, 1.1, 16)
	var grad := Gradient.new()
	grad.set_color(0, Color(cfg["light"], 0.9))
	grad.set_color(1, Color(cfg["deep"], 0.0))
	p.color_ramp = grad
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.34
	p.emission_ring_inner_radius = 0.2
	p.emission_ring_height = 0.05
	p.position.y = 0.15
	(p.mesh as QuadMesh).size = Vector2(0.12, 0.12)   # small motes, not glows
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	match char_id:
		"ice_wizard":
			p.gravity = Vector3(0, -0.3, 0)
			p.initial_velocity_min = 0.1
			p.initial_velocity_max = 0.5
		"thunder_wizard":
			p.lifetime = 0.45
			p.initial_velocity_min = 1.5
			p.initial_velocity_max = 3.0
			p.spread = 70.0
		"dark_wizard":
			p.gravity = Vector3(0, 0.6, 0)
			p.scale_amount_max = 1.6
	add_child(p)
	_particles.append(p)


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
	for b in UPPER_BONES:
		os.set_filter_path(NodePath("%s:%s" % [SKEL, b]), true)
	return os


func _build_tree() -> void:
	var cfg: Dictionary = CFG[char_id]
	tree = AnimationTree.new()
	tree.add_animation_library("c", load((DIR % char_id).path_join("anims.res")))
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(_clip("idle", []), 0.0, -1, "idle")
	loco.add_blend_point(_clip("run", []), RUN_SPEED, -1, "run")
	loco.min_space = 0.0
	loco.max_space = RUN_SPEED
	bt.add_node("loco", loco, Vector2(0, 0))
	bt.add_node("loco_speed", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("loco_speed", 0, "loco")

	var casts: Array = cfg["cast"]
	var cast_speeds: Array = cfg["cast_speed"]
	var layers := []
	for k in 3:
		layers.append(["cast%d" % k, "ability", casts[k], 0.1, 0.3, cast_speeds[k]])
	layers.append(["hit", "hit", HIT_SEG, 0.05, 0.2, 1.6])
	layers.append(["fire", "attack", cfg["fire"], 0.06, 0.18, cfg["fire_speed"]])
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
	_rig.add_child(tree)
	tree.active = true
	for l in layers:
		tree.set("parameters/%s_speed/scale" % l[0], l[5])
	tree.set("parameters/loco_speed/scale", 1.0)


# ------------------------------------------------------------------ interface

func attack(target: Vector3) -> Vector3:
	_fire("fire")
	var to := target - global_position
	var local := global_transform.basis.orthonormalized().inverse() * to
	twist.target_angle = clampf(atan2(-local.x, -local.z), -MAX_TWIST, MAX_TWIST)
	_twist_hold = 0.45
	return staff_tip()


func staff_tip() -> Vector3:
	if weapon == null or not weapon.is_inside_tree():
		return global_position + Vector3(0, 1.5, 0)
	return weapon.global_transform * STAFF_HEAD


func set_motion(speed: float, _airborne: bool) -> void:
	_speed = speed


func play_hit() -> void:
	_fire("hit")


func play_ability(i: int) -> void:
	_fire("cast%d" % clampi(i, 0, 2))


func is_playing(layer: String) -> bool:
	return bool(tree.get("parameters/%s/active" % layer)) or _time - float(_requested.get(layer, -10.0)) < 0.1


func _fire(layer: String) -> void:
	tree.set("parameters/%s/request" % layer, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_requested[layer] = _time


func set_dim(f: float) -> void:
	if is_equal_approx(f, _dim):
		return
	_dim = f
	for k in _mats.size():
		var c := _base_albedo[k]
		_mats[k].albedo_color = Color(c.r * f, c.g * f, c.b * f, c.a)
	for p in _particles:
		p.color = Color(f, f, f, 1.0)


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
