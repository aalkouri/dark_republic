class_name PharaohBody
extends Node3D
## The playable Pharaoh: the Desert boss's own body (PharaohModel: gold death mask and nemes,
## linen-wrapped limbs, the broad collar, a royal-blue cloak, the crook and the flail) at player
## size, about 1.8 m. Faces -Z, origin at the feet. PlayableBoss lists the interface.
##
## The model is posed by hand every frame (its own _process is off):
##   idle / run  standing tall with his arms crossed; running, a stiff mummy's jog with his arms
##               pumping, leaning in, the cloak and bandage ends streaming
##   attack      the crook thrust out at the target (the scarabs leave from its hook), the legs
##               keep running
##   cast        both arms flung up (the sands answer); the ultimate lifts him off the ground
##   hit         a jolt back and a flash;  die  his knees buckle and he crumbles into sand
## The crook and flail are tucked through his belt (crook across the small of his back, flail at
## his hip) and only drawn into his hands to attack or cast.

const SCALE := 0.95                  # x PharaohModel's 1.9 m
const ATTACK_TIME := 0.42
const CAST_TIME := 0.9
const ULT_TIME := 1.7

var model: PharaohModel
var drawn := false
var dead := false
var attacks := 0                     # tests
var casts := 0
var stowed: Array[Node3D] = []       # the crook and flail in his belt
var _drawn_t := 0.0
var _atk_t := 0.0
var _cast_t := 0.0
var _cast_len := CAST_TIME
var _cast_pose := "summon"
var _flinch := 0.0
var _dim := 1.0
var _hurt := 0.0
var _overlay: StandardMaterial3D


static func create() -> PharaohBody:
	return PharaohBody.new()


func _ready() -> void:
	model = PharaohModel.new()
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	model.set_process(false)          # posed from animate()
	model.pose = "walk"
	_build_stowed()
	_overlay = PlayableBoss.overlay()
	PlayableBoss.apply_overlay(model, _overlay)
	_set_drawn(false)
	model._update(0.0)


## Second copies of the crook and the flail, tucked through his belt (reusing their meshes).
func _build_stowed() -> void:
	var crook := Node3D.new()
	for c in model.hand_l.get_children():
		if c is MeshInstance3D:
			var mi := MeshInstance3D.new()
			mi.mesh = (c as MeshInstance3D).mesh
			crook.add_child(mi)
	# Across the small of his back, the hook up over his left hip
	crook.transform = Transform3D(Basis(Vector3(0, 0, 1), 0.95) * Basis(Vector3(0, 1, 0), PI), Vector3(-0.1, -0.12, 0.22))
	model.hips.add_child(crook)
	var flail := Node3D.new()
	for c in model.hand_r.get_children():
		if c is MeshInstance3D:
			var mi := MeshInstance3D.new()
			mi.mesh = (c as MeshInstance3D).mesh
			flail.add_child(mi)
	var head := Node3D.new()
	head.position = Vector3(0, 0.3, 0)
	flail.add_child(head)
	for s in model.flail_strands:   # the beaded strands hanging down over the handle
		for c in s.get_children():
			if c is MeshInstance3D:
				var mi := MeshInstance3D.new()
				mi.mesh = (c as MeshInstance3D).mesh
				mi.position = s.position
				mi.rotation = Vector3(0, 0, 0.35)
				head.add_child(mi)
	# Through the belt at his right hip, handle up and slanting forward
	flail.transform = Transform3D(Basis(Vector3(1, 0, 0), -0.25) * Basis(Vector3(0, 0, 1), 0.25), Vector3(-0.23, -0.18, -0.05))
	model.hips.add_child(flail)
	stowed = [crook, flail]


func _set_drawn(on: bool) -> void:
	drawn = on
	if model == null:
		return
	model.hand_l.visible = on
	model.hand_r.visible = on
	for s in stowed:
		s.visible = not on


func _draw_for(secs: float) -> void:
	_drawn_t = maxf(_drawn_t, maxf(secs + RosterHero.HOLSTER_DELAY, RosterHero.HOLSTER_MIN))
	if not drawn:
		_set_drawn(true)


## The crook thrust at `target`: scarabs leave from its hook.
func attack(target: Vector3) -> Vector3:
	if dead:
		return tip()
	attacks += 1
	_atk_t = ATTACK_TIME
	_draw_for(ATTACK_TIME)
	if target != Vector3.INF:   # turn the body a little toward it
		var to := target - global_position
		var local := global_transform.basis.orthonormalized().inverse() * to
		model.rotation.y = clampf(atan2(-local.x, -local.z), -0.9, 0.9) * 0.5
	return tip()


func tip() -> Vector3:
	if model != null and is_instance_valid(model.crook_tip) and model.crook_tip.is_inside_tree():
		return model.crook_tip.global_position
	return global_position + Vector3(0, 1.5, 0) - global_transform.basis.z * 0.5


func cast(i: int) -> void:
	if dead:
		return
	casts += 1
	_cast_pose = "raise" if i == 2 else "summon"
	_cast_len = ULT_TIME if i == 2 else CAST_TIME
	_cast_t = _cast_len
	_atk_t = 0.0
	_draw_for(_cast_len)


func hit() -> void:
	if dead:
		return
	_flinch = 1.0
	model.flash()


## His knees buckle, he slumps and crumbles into a heap of sand (the run is over).
func die() -> void:
	if dead:
		return
	dead = true
	model.pose = "die"
	model.die_t = 0.0


func animate(dt: float, speed: float, airborne := false) -> void:
	if model == null:
		return
	if dead:
		model.die_t += dt
		model._update(dt)
		return
	_flinch = maxf(0.0, _flinch - dt * 4.0)
	_atk_t = maxf(0.0, _atk_t - dt)
	_cast_t = maxf(0.0, _cast_t - dt)
	if drawn:
		_drawn_t -= dt
		if _drawn_t <= 0.0:
			_set_drawn(false)
	var run := clampf(speed / RosterHero.RUN_SPEED, 0.0, 1.0)
	model.walk_speed = speed / SCALE * 0.62 if not airborne else 0.0
	if _cast_t > 0.0:
		model.pose = _cast_pose
		model.act = 1.0 - _cast_t / _cast_len
	elif _atk_t > 0.0:
		model.pose = "beam"
		model.act = (1.0 - _atk_t / ATTACK_TIME) if _atk_t > 0.12 else _atk_t / 0.12 * 0.33
	else:
		model.pose = "walk"
		model.act = 0.0
		model.rotation.y = lerpf(model.rotation.y, 0.0, clampf(dt * 6.0, 0.0, 1.0))
	model._update(dt)
	var sw := sin(model._phase) * clampf(model.walk_speed / 1.2, 0.0, 1.0)
	# The legs keep running through attacks and casts
	if model.pose != "walk" and run > 0.08:
		model.hip_r.rotation.x = sw * 0.6
		model.hip_l.rotation.x = -sw * 0.6
		model.knee_r.rotation.x = -absf(sw) * 0.6 if sw > 0.0 else 0.0
		model.knee_l.rotation.x = -absf(sw) * 0.6 if sw <= 0.0 else 0.0
	elif model.pose == "walk" and run > 0.08:
		# Running: a longer stride, and the arms come off his chest and pump
		var k := clampf(run * 1.5, 0.0, 1.0)
		model.hip_r.rotation.x = sw * lerpf(0.45, 0.75, k)
		model.hip_l.rotation.x = -sw * lerpf(0.45, 0.75, k)
		model.sh_r.rotation = Vector3(lerpf(0.55, -sw * 0.7 + 0.15, k), lerpf(-0.55, -0.12, k), 0.0)
		model.sh_l.rotation = Vector3(lerpf(0.55, sw * 0.7 + 0.15, k), lerpf(0.55, 0.12, k), 0.0)
		model.el_r.rotation.x = lerpf(2.15, 1.1, k)
		model.el_l.rotation.x = lerpf(2.15, 1.1, k)
	if airborne:   # knees tucked in the air
		model.knee_r.rotation.x = -0.7
		model.knee_l.rotation.x = -0.5
		model.hip_r.rotation.x = 0.5
		model.hip_l.rotation.x = 0.2
	# Lean into the run; jolt back when hit
	model.rotation.x = -0.16 * run + 0.3 * sin(_flinch * PI * 0.5) * _flinch
	model.position.z = 0.12 * _flinch
	PlayableBoss.tint(_overlay, _dim, maxf(_hurt, model._flash / 0.15 if model._flash > 0.0 else 0.0))


func is_attacking() -> bool:
	return _atk_t > 0.0


func set_dim(f: float) -> void:
	_dim = f


func set_hurt(f: float) -> void:
	_hurt = f
