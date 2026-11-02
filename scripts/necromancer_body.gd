class_name NecromancerBody
extends Node3D
## The playable Necromancer: the Graveyard boss's own body (NecromancerModel: the tattered robe,
## the hood over a burning-eyed skull, the bone mantle, the horned-skull staff with its soul-
## flame) at player size, about 1.85 m to the hood's peak. Faces -Z, origin at the feet.
## PlayableBoss lists the interface.
##
## He hovers a hand's breadth off the ground, the hem streaming, souls circling him:
##   idle / run  hovering upright; running, he leans into it and glides
##   attack      the staff levelled at the target ("channel"): soul bolts leave from its flame
##   cast        both arms flung up ("summon"); Soul Drain holds the staff levelled for its beam;
##               the ultimate lifts him up, arms spread ("rise")
##   hit         a jolt back and a flash;  die  the robe collapses empty into the dirt
## The staff is slung across his back and only drawn to attack or cast (the boss model holds it
## baked into his right arm; here the arm is built empty and the staff is a separate piece).

const SCALE := 0.62                  # x NecromancerModel's 2.7 m (with the hood's peak and the hover, ~1.85 m)
const ATTACK_TIME := 0.45
const CAST_TIME := 0.9
const ULT_TIME := 1.8

## The boss model with an empty right hand: the staff is built separately (Rig.staff_mesh()).
class Rig extends NecromancerModel:
	func _build_arm(sd: float, _staff: bool) -> ArrayMesh:
		return super(sd, false)

	## The staff alone, in the right arm's space (where the boss holds it).
	func staff_mesh() -> ArrayMesh:
		var mb := MeshBuilder.new()
		var gb := MeshBuilder.new()
		var bone := Color(0.82, 0.78, 0.68, 0.0)
		var wr := Vector3(-0.1, -0.85, 0.3)
		var hand := wr + Vector3(0, -0.06, 0.1)
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
		gb.add(MeshBuilder.sphere(0.09, 10, 6), Transform3D(Basis.from_scale(Vector3(1, 1.4, 1)), top + Vector3(0, 0.36, 0.0)), Color(0.45, 1.0, 0.6, 0.0))
		gb.add(MeshBuilder.cone(0.07, 0.25, 8), Transform3D(Basis(), top + Vector3(0, 0.55, 0.0)), Color(0.35, 0.95, 0.5, 0.0))
		for k in 3:   # trinkets hung from the staff
			mb.limb(top + Vector3(0.0, -0.08, 0.0), top + Vector3(sin(k * 2.0) * 0.08, -0.32 - k * 0.05, cos(k * 2.0) * 0.08), 0.005, 0.005, Color(0.25, 0.2, 0.15, 0.4), 3)
			mb.add(MeshBuilder.sphere(0.025, 5, 4), Transform3D(Basis(), top + Vector3(sin(k * 2.0) * 0.08, -0.34 - k * 0.05, cos(k * 2.0) * 0.08)), Color(bone, 0.5))
		return _finish(mb, gb)

	## Where the staff's middle is in its own space (slinging it on the back).
	static func staff_center() -> Vector3:
		return Vector3(-0.1, -0.685, 0.435)


var model: Rig
var staff: Node3D                    # in his hand (shown while drawn)
var stowed: Array[Node3D] = []       # ...and slung across his back
var drawn := false
var dead := false
var attacks := 0                     # tests
var casts := 0
var _drawn_t := 0.0
var _atk_t := 0.0
var _cast_t := 0.0
var _cast_pose := "summon"
var _hold_t := 0.0                   # Soul Drain: staff levelled this long
var _flinch := 0.0
var _lean := 0.0
var _hurt := 0.0


static func create() -> NecromancerBody:
	return NecromancerBody.new()


func _ready() -> void:
	model = Rig.new()
	model.scale = Vector3.ONE * SCALE
	model.rotation.y = PI            # the boss model faces +Z
	add_child(model)
	var mesh := model.staff_mesh()
	staff = Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_overlay = model._overlay
	staff.add_child(mi)
	model.arm_r.add_child(staff)
	# Slung diagonally across his back (the model's back is -Z), the skull over his left shoulder
	var back := Node3D.new()
	var bmi := MeshInstance3D.new()
	bmi.mesh = mesh
	bmi.material_overlay = model._overlay
	back.add_child(bmi)
	var basis := Basis(Vector3(0, 0, 1), -0.75)
	back.transform = Transform3D(basis, Vector3(0.0, 1.3, -0.5) - basis * Rig.staff_center())
	model.body.add_child(back)
	stowed = [back]
	_set_drawn(false)
	model.pose("idle")


func _set_drawn(on: bool) -> void:
	drawn = on
	if staff:
		staff.visible = on
	for s in stowed:
		s.visible = not on


func _draw_for(secs: float) -> void:
	_drawn_t = maxf(_drawn_t, maxf(secs + RosterHero.HOLSTER_DELAY, RosterHero.HOLSTER_MIN))
	if not drawn:
		_set_drawn(true)


## The staff levelled at `target`: soul bolts leave from the flame atop it.
func attack(target: Vector3) -> Vector3:
	if dead:
		return tip()
	attacks += 1
	_atk_t = ATTACK_TIME
	_draw_for(ATTACK_TIME)
	if target != Vector3.INF:
		var to := target - global_position
		var local := global_transform.basis.orthonormalized().inverse() * to
		model.rotation.y = PI + clampf(atan2(-local.x, -local.z), -0.9, 0.9) * 0.5
	return tip()


func tip() -> Vector3:
	if model != null and is_instance_valid(model.staff_tip) and model.staff_tip.is_inside_tree():
		return model.staff_tip.global_position
	return global_position + Vector3(0, 1.7, 0)


func cast(i: int) -> void:
	if dead:
		return
	casts += 1
	_cast_pose = "rise" if i == 2 else "summon"
	_cast_t = ULT_TIME if i == 2 else CAST_TIME
	_atk_t = 0.0
	_draw_for(_cast_t)


## Hold the staff levelled for `secs` (Soul Drain's beam).
func hold(secs: float) -> void:
	_hold_t = secs
	_cast_t = 0.0
	_draw_for(secs)


func hit() -> void:
	if dead:
		return
	_flinch = 1.0
	model.flash()


## He shrieks and the robe collapses empty into the dirt (the run is over).
func die() -> void:
	if dead:
		return
	dead = true
	model.pose("die")


func animate(dt: float, speed: float, _airborne := false) -> void:
	if model == null:
		return
	if dead:
		model.crumble = minf(1.0, model.crumble + dt / 1.6)
		return
	_flinch = maxf(0.0, _flinch - dt * 4.0)
	_atk_t = maxf(0.0, _atk_t - dt)
	_cast_t = maxf(0.0, _cast_t - dt)
	_hold_t = maxf(0.0, _hold_t - dt)
	if drawn:
		_drawn_t -= dt
		if _drawn_t <= 0.0:
			_set_drawn(false)
	var run := clampf(speed / RosterHero.RUN_SPEED, 0.0, 1.0)
	if _cast_t > 0.0:
		model.pose(_cast_pose)
	elif _hold_t > 0.0 or _atk_t > 0.0:
		model.pose("channel")
	else:
		model.pose("walk" if run > 0.08 else "idle")
		model.rotation.y = lerpf(model.rotation.y, PI, clampf(dt * 6.0, 0.0, 1.0))
	model.lift = lerpf(model.lift, 0.55 if _cast_pose == "rise" and _cast_t > 0.0 else 0.0, clampf(dt * 5.0, 0.0, 1.0))
	# Gliding: he leans into the run; a jolt back when hit
	_lean = lerpf(_lean, run, clampf(dt * 6.0, 0.0, 1.0))
	rotation.x = -0.22 * _lean + 0.28 * _flinch
	position.z = 0.12 * _flinch
	if _hurt > 0.5 and model._flash_t <= 0.0:
		model.flash()


func set_dim(f: float) -> void:
	if model != null and model._light != null:
		model._light.light_color = NecromancerModel.SOUL_GREEN * clampf(f, 0.3, 1.0)


func set_hurt(f: float) -> void:
	_hurt = f
