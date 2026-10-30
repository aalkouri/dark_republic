class_name RosterHero
extends HeroBase
## A playable roster character (everyone but the Fire Wizard): the rigged Higgsfield/Meshy
## model from models/<id>/ with its Lean clip set (idle, run, hit, attack, ability) driven by an
## AnimationTree, holding its weapon from RosterWeapons. Faces -Z, origin at the feet, 1.8 m.
##
## Layers, bottom to top:
##   locomotion  idle / run blended by ground speed (run sped up when faster)
##   cast0..2    upper-body one-shots: a segment of the ability clip per slot
##   hit         upper-body flinch
##   fire        upper-body one-shot: the staff thrust from the attack clip, every weapon shot
## Upper-body layers leave the legs running. A spine twist turns the torso toward each target.
## The Ghast has no skeleton: it hovers and sways, lunging and swelling instead of animating.

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
	"merlin": {
		"fire": [0.6, 2.2], "fire_speed": 1.7,
		"cast": [[1.6, 3.2], [1.6, 3.2], [0.0, 1.6]], "cast_speed": [1.3, 1.3, 1.0],
		"main": Color(0.5, 0.68, 1.0), "deep": Color(0.25, 0.2, 0.75), "light": Color(0.88, 0.94, 1.0),
	},
	"ogre": {
		"fire": [0.75, 1.87], "fire_speed": 1.4,
		"cast": [[0.4, 1.5], [1.5, 2.7], [0.4, 1.5]], "cast_speed": [1.2, 1.4, 1.0],
		"main": Color(0.62, 0.85, 0.3), "deep": Color(0.35, 0.25, 0.1), "light": Color(0.9, 1.0, 0.6),
		"motes": false,
	},
	"ghast": {
		"fire": [], "fire_speed": 1.0, "cast": [[], [], []], "cast_speed": [1.0, 1.0, 1.0],
		"main": Color(0.72, 0.95, 1.0), "deep": Color(0.15, 0.3, 0.38), "light": Color(0.95, 1.0, 1.0),
	},
	"vampire_hunter": {
		"fire": [0.9, 2.6], "fire_speed": 2.0,
		"cast": [[1.2, 2.6], [1.2, 2.6], [1.2, 2.6]], "cast_speed": [1.4, 1.4, 1.2],
		"main": Color(0.92, 0.94, 1.0), "deep": Color(0.55, 0.08, 0.12), "light": Color(1.0, 1.0, 0.92),
		"motes": false,
	},
	"vicki": {
		"fire": [1.1, 2.3], "fire_speed": 1.8,
		"cast": [[0.4, 1.4], [0.6, 2.4], [1.6, 2.8]], "cast_speed": [1.2, 1.4, 1.1],
		"main": Color(1.0, 0.85, 0.45), "deep": Color(0.25, 0.45, 0.8), "light": Color(1.0, 0.98, 0.85),
		"motes": false,
	},
	"rogue": {
		"fire": [1.1, 2.1], "fire_speed": 2.0,
		"cast": [[0.3, 1.8], [0.3, 1.8], [0.3, 2.2]], "cast_speed": [1.5, 1.8, 1.5],
		"main": Color(0.75, 0.95, 0.55), "deep": Color(0.1, 0.16, 0.1), "light": Color(0.95, 1.0, 0.85),
		"motes": false,
	},
	"gaiden": {
		"fire": [0.75, 2.1], "fire_speed": 2.6,
		"cast": [[0.2, 1.4], [0.2, 1.4], [0.2, 1.4]], "cast_speed": [1.6, 1.4, 1.2],
		"main": Color(1.0, 0.25, 0.3), "deep": Color(0.12, 0.08, 0.14), "light": Color(1.0, 0.85, 0.85),
		"motes": false,
		"weapon_when_attacking": true,   # the katana is only drawn while he swings or casts
	},
	"dr_croc": {
		"fire": [1.2, 3.2], "fire_speed": 2.2,
		"cast": [[0.0, 1.6], [5.2, 6.8], [0.0, 1.6]], "cast_speed": [1.3, 1.3, 1.1],
		"main": Color(0.55, 1.0, 0.3), "deep": Color(0.12, 0.35, 0.1), "light": Color(0.88, 1.0, 0.7),
		"motes": false,
		# Mutagen form (set_mutant): his coat torn to rags (tools/gen_croc_ripped_coat.py) and bulk
		"mutant_skin": "res://models/dr_croc/dr_croc_ripped.jpg",
	},
	# Thog plays on the Ogre's rig, re-skinned troll blue and a size up, until he has his own model
	# (the same stand-in the Swamp boss uses). "model" = whose model folder; "skin" replaces the
	# albedo texture; "scale" sizes the rig; "weapon_scale" sizes the club.
	# An Argyle Sock has no model: SockBody builds it in code ("procedural")
	"argyle_sock": {
		"procedural": "sock",
		"fire": [], "fire_speed": 1.0, "cast": [[], [], []], "cast_speed": [1.0, 1.0, 1.0],
		"main": Color(0.72, 0.35, 1.0), "deep": Color(0.38, 0.16, 0.55), "light": Color(0.92, 0.8, 1.0),
		"motes": false,
	},
	"thog": {
		"model": "ogre", "skin": "res://models/ogre/thog_skin.jpg", "scale": 1.2, "weapon_scale": 1.35,
		"fire": [0.8, 1.8667], "fire_speed": 1.3,
		"cast": [[1.4, 2.4], [0.4, 1.5], [0.4, 1.9]], "cast_speed": [1.2, 1.4, 1.0],
		"main": Color(0.45, 0.68, 1.0), "deep": Color(0.15, 0.25, 0.5), "light": Color(0.82, 0.9, 1.0),
		"motes": false,
	},
}

var char_id := ""
var tree: AnimationTree
var skeleton: Skeleton3D
var weapon: Node3D
var _weapon_show := 0.0          # seconds the weapon stays drawn (weapon_when_attacking)
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
var _floaty := false        # no skeleton (the Ghast)
var _lunge := 0.0           # floaty attack / cast pulses
var _swell := 0.0
var _flinch := 0.0
var _airborne := false
var bulk: CrocBulk            # Dr. Croc's Mutagen form: swollen chest and arms
var mutant := 0.0           # ...how far into it, 0..1
var ripped := false         # ...his lab coat torn (the mutant skin swapped in)
var _flash := 0.0           # a pulse of light over the whole model (transforming)
var _base_tex: Array[Texture2D] = []


static func is_playable(id: String) -> bool:
	if not CFG.has(id):
		return false
	if CFG[id].has("procedural"):
		return true
	var m := model_of(id)
	return ResourceLoader.exists((DIR % m).path_join(m + ".glb"))


## Which model folder a character plays on (Thog borrows the Ogre's for now).
static func model_of(id: String) -> String:
	return str(CFG.get(id, {}).get("model", id))


static func create(id: String) -> RosterHero:
	var h := RosterHero.new()
	h.char_id = id
	return h


## The character's magic colours: "main", "deep", "light".
static func color(id: String, key: String) -> Color:
	return CFG.get(id, CFG["ice_wizard"])[key]


var sock: SockBody          # An Argyle Sock: built in code, no rig
var sock_colors := {}       # ...in other colours (the Lost Pair), set before it's added


func _ready() -> void:
	var cfg0: Dictionary = CFG[char_id]
	if cfg0.get("procedural", "") == "sock":
		sock = SockBody.create(sock_colors)
		_rig = sock
		add_child(sock)
		_floaty = true
		return
	var mid := model_of(char_id)
	var dir := DIR % mid
	_rig = (load(dir.path_join(mid + ".glb")) as PackedScene).instantiate()
	_rig.rotation.y = PI            # the GLB faces +Z; the game faces -Z
	_rig.scale = Vector3.ONE * float(cfg0.get("scale", 1.0))
	add_child(_rig)
	skeleton = _rig.get_node_or_null(SKEL)
	_floaty = skeleton == null
	var old_player := _rig.get_node_or_null("AnimationPlayer")
	if old_player:
		old_player.free()
	_prepare_materials()
	if cfg0.has("skin") and ResourceLoader.exists(cfg0["skin"]):
		var skin: Texture2D = load(cfg0["skin"])
		for m in _mats:
			m.albedo_texture = skin
	if not _floaty:
		_build_tree()
		weapon = RosterWeapons.attach(mid, skeleton)
		if weapon:
			weapon.scale *= float(cfg0.get("weapon_scale", 1.0))
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
	if cfg.get("motes", true):
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
				_base_tex.append(mat.albedo_texture)


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
		"merlin":   # twinkling stars
			p.gravity = Vector3(0, 0.25, 0)
			p.initial_velocity_min = 0.05
			p.initial_velocity_max = 0.3
			p.lifetime = 1.6
		"ghast":   # trailing mist
			p.gravity = Vector3(0, 0.4, 0)
			p.scale_amount_max = 2.4
			p.emission_ring_radius = 0.45
			p.position.y = 0.2
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
	tree.add_animation_library("c", load((DIR % model_of(char_id)).path_join("anims.res")))
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
	if _floaty:
		_lunge = 1.0
		return staff_tip()
	_fire("fire")
	var to := target - global_position
	var local := global_transform.basis.orthonormalized().inverse() * to
	twist.target_angle = clampf(atan2(-local.x, -local.z), -MAX_TWIST, MAX_TWIST)
	_twist_hold = 0.45
	return staff_tip()


func staff_tip() -> Vector3:
	if sock:
		return sock.tip()
	if _floaty:   # the Ghast's mouth
		return global_transform * Vector3(0, 1.45, -0.35)
	if weapon == null or not weapon.is_inside_tree():
		return global_position + Vector3(0, 1.5, 0)
	return weapon.global_transform * STAFF_HEAD


func set_motion(speed: float, airborne: bool) -> void:
	_speed = speed
	_airborne = airborne


func play_hit() -> void:
	if _floaty:
		_flinch = 1.0
		return
	_fire("hit")


func play_ability(i: int) -> void:
	if _floaty:
		_swell = 1.0
		return
	_fire("cast%d" % clampi(i, 0, 2))


func is_playing(layer: String) -> bool:
	if _floaty:
		return false
	return bool(tree.get("parameters/%s/active" % layer)) or _time - float(_requested.get(layer, -10.0)) < 0.1


func _fire(layer: String) -> void:
	if tree == null:
		return
	tree.set("parameters/%s/request" % layer, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_requested[layer] = _time
	if bool(CFG.get(char_id, {}).get("weapon_when_attacking", false)):
		var seg = CFG[char_id]["fire"] if layer == "fire" else CFG[char_id]["cast"][int(layer.substr(4))]
		var spd: float = CFG[char_id]["fire_speed"] if layer == "fire" else CFG[char_id]["cast_speed"][int(layer.substr(4))]
		var dur := (float(seg[1]) - float(seg[0])) / maxf(spd, 0.01) if seg.size() == 2 else 0.6
		_weapon_show = maxf(_weapon_show, dur + 0.08)


## Characters whose weapon only appears while they attack (Gaiden's katana).
func _update_weapon_shown(dt: float) -> void:
	if weapon == null or not bool(CFG.get(char_id, {}).get("weapon_when_attacking", false)):
		return
	_weapon_show = maxf(0.0, _weapon_show - dt)
	weapon.visible = _weapon_show > 0.0


func set_dim(f: float) -> void:
	if is_equal_approx(f, _dim):
		return
	_dim = f
	if sock:
		sock.set_dim(f)
	for k in _mats.size():
		var c := _base_albedo[k]
		_mats[k].albedo_color = Color(c.r * f, c.g * f, c.b * f, c.a)
	for p in _particles:
		p.color = Color(f, f, f, 1.0)


func set_hurt(amount: float) -> void:
	if is_equal_approx(amount, _hurt):
		return
	_hurt = amount
	if sock:
		sock.set_hurt(clampf(amount, 0.0, 1.0))
	_apply_emission()


## Light the whole model up (0..1) in its magic colour: Dr. Croc strobing as he transforms.
func set_flash(amount: float) -> void:
	if is_equal_approx(amount, _flash):
		return
	_flash = amount
	_apply_emission()


func _apply_emission() -> void:
	var e := Color(1.0, 0.85, 0.75) * clampf(_hurt, 0.0, 1.0)
	var c: Color = CFG.get(char_id, {}).get("light", Color.WHITE)
	e = Color(maxf(e.r, c.r * _flash), maxf(e.g, c.g * _flash), maxf(e.b, c.b * _flash))
	for m in _mats:
		m.emission = e


## Dr. Croc's Mutagen form, 0 (himself) .. 1 (hulking): the chest and arms bulk out and, past
## halfway, the lab coat is torn to rags. (The kit grows the whole model through size_mult.)
func set_mutant(f: float) -> void:
	mutant = clampf(f, 0.0, 1.0)
	if skeleton != null:
		if bulk == null:
			bulk = CrocBulk.new()
			skeleton.add_child(bulk)
		bulk.amount = mutant
	var want := mutant > 0.5
	if want == ripped:
		return
	ripped = want
	var path := str(CFG.get(char_id, {}).get("mutant_skin", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	var skin: Texture2D = load(path) if ripped else null
	for k in _mats.size():
		if _base_tex[k] != null:
			_mats[k].albedo_texture = skin if ripped else _base_tex[k]


func _process(dt: float) -> void:
	_time += dt
	if sock:   # hops along, leans into its zaps, puffs up when it casts
		_lunge = maxf(0.0, _lunge - dt * 5.0)
		_swell = maxf(0.0, _swell - dt * 1.8)
		_flinch = maxf(0.0, _flinch - dt * 5.0)
		sock.animate(dt, _speed, _airborne, _lunge, _swell, _flinch)
		return
	if _floaty:   # hover, sway, lunge at targets, swell when casting, jerk back when hit
		_lunge = maxf(0.0, _lunge - dt * 4.0)
		_swell = maxf(0.0, _swell - dt * 1.8)
		_flinch = maxf(0.0, _flinch - dt * 5.0)
		var lean := clampf(_speed / RUN_SPEED, 0.0, 1.0)
		var l := sin(_lunge * PI)
		_rig.position = Vector3(0.0, 0.35 + 0.08 * sin(_time * 1.8) + 0.25 * sin(_swell * PI), -0.35 * l + 0.25 * _flinch)
		_rig.rotation = Vector3(-0.35 * lean - 0.4 * l + 0.3 * _flinch, PI + 0.08 * sin(_time * 0.7), 0.05 * sin(_time * 1.1))
		_rig.scale = Vector3.ONE * (1.0 + 0.25 * sin(_swell * PI) + 0.08 * l)
		return
	_update_weapon_shown(dt)
	tree.set("parameters/loco/blend_position", minf(_speed, RUN_SPEED))
	tree.set("parameters/loco_speed/scale", clampf(_speed / RUN_SPEED, 1.0, 2.2) if _speed > RUN_SPEED else 1.0)
	_twist_hold -= dt
	if _twist_hold <= 0.0:
		twist.target_angle = 0.0
