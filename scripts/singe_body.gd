class_name SingeBody
extends Node3D
## The playable Singe: the Ashen Caldera boss's own body (SingeModel: a pot-bellied imp of
## cracked black coals with glowing seams, a big grinning head, flame hair, spindly limbs and a
## spade-tipped tail) back down to his roster size, a little imp about 1.55 m to the crown of his
## head with his hair flaming above. Faces -Z, origin at the feet. PlayableBoss lists the
## interface. He fights with his claws and his embers, so there's no weapon to put away.
##
## The model is posed through its own `pose` / `act`:
##   idle        rubbing his hands with glee, hopping from foot to foot
##   walk / run  capering along; flat out he scampers, bent low, arms flung back
##   attack      a claw flick ("swipe") that flings the embers from his right hand
##   cast        cackling with his arms up; the ultimate bounces him up and down ("raise");
##               Lava Cannonball tucks him into a ball of coals (curl)
##   hit         a flash and a jolt;  die  he fizzles down into a little heap of coals

const SCALE := 0.26                  # x SingeModel's 6 m
const ATTACK_TIME := 0.3
const CAST_TIME := 0.9
const ULT_TIME := 1.6
const SCAMPER_AT := 5.0              # m/s: faster than this he scampers

var model: SingeModel
var drawn := false                   # (nothing to draw: his weapon is his claws)
var dead := false
var attacks := 0                     # tests
var casts := 0
var curled := false
var _atk_t := 0.0
var _cast_t := 0.0
var _cast_len := CAST_TIME
var _cast_pose := "cackle"
var _flinch := 0.0
var _dim := 1.0
var _hurt := 0.0
var _overlay: StandardMaterial3D


static func create() -> SingeBody:
	return SingeBody.new()


func _ready() -> void:
	model = SingeModel.new()
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	model.pose = "walk"
	# His furnace glow and embers, sized to an imp
	model._light.omni_range = 5.0
	model._light.position = Vector3(0, 3.0, -2.0)
	for e in model._embers:
		e.scale_amount_min *= 0.35
		e.scale_amount_max *= 0.35
		e.initial_velocity_max *= 0.4
		e.initial_velocity_min *= 0.4
	model._hair_fx.scale_amount_min *= 0.16
	model._hair_fx.scale_amount_max *= 0.16
	model._hair_fx.initial_velocity_min *= 0.25
	model._hair_fx.initial_velocity_max *= 0.25
	model._hair_fx.emission_sphere_radius *= 0.3
	model._hair_fx.amount = 30
	_overlay = PlayableBoss.overlay()
	PlayableBoss.apply_overlay(model, _overlay)
	# (the flame hair is additive: no overlay there, or it'd go muddy)
	model._hair_mi.material_overlay = null


## A claw flick toward `target`: the embers leave from his right hand.
func attack(target: Vector3) -> Vector3:
	if dead:
		return tip()
	attacks += 1
	_atk_t = ATTACK_TIME
	if target != Vector3.INF:
		var to := target - global_position
		var local := global_transform.basis.orthonormalized().inverse() * to
		model.rotation.y = clampf(atan2(-local.x, -local.z), -0.9, 0.9) * 0.6
	return tip()


func tip() -> Vector3:
	if model != null and model.hands.size() > 1 and model.hands[1].is_inside_tree():
		return model.hands[1].global_transform * Vector3(0, -0.7, -0.3)
	return global_position + Vector3(0, 1.0, 0) - global_transform.basis.z * 0.4


func cast(i: int) -> void:
	if dead:
		return
	casts += 1
	_cast_pose = "raise" if i == 2 else "cackle"
	_cast_len = ULT_TIME if i == 2 else CAST_TIME
	_cast_t = _cast_len
	_atk_t = 0.0


## Tucked into a cannonball of coals (Lava Cannonball) or not.
func set_curl(on: bool) -> void:
	curled = on


func hit() -> void:
	if dead:
		return
	_flinch = 1.0
	model.flash()


## He sputters, his flame hair dies down and he fizzles into a heap of coals (the run is over).
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
		model.set_cool(clampf((model.die_t - 1.0) / 2.0, 0.0, 1.0))
		return
	_flinch = maxf(0.0, _flinch - dt * 4.0)
	_atk_t = maxf(0.0, _atk_t - dt)
	_cast_t = maxf(0.0, _cast_t - dt)
	model.curl = move_toward(model.curl, 1.0 if curled else 0.0, dt * 6.0)
	if curled:
		model.pose = "dive"
		model.act = 0.5
	elif _cast_t > 0.0:
		model.pose = _cast_pose
		model.act = 1.0 - _cast_t / _cast_len
	elif _atk_t > 0.0:
		model.pose = "swipe"
		model.act = lerpf(0.62, 1.0, 1.0 - _atk_t / ATTACK_TIME)
	elif speed > SCAMPER_AT and not airborne:
		model.pose = "scamper"
	else:
		model.pose = "walk"
		model.rotation.y = lerpf(model.rotation.y, 0.0, clampf(dt * 6.0, 0.0, 1.0))
	model.walk_speed = speed * 0.7 if not airborne else 0.0
	# A jolt back when hit; the body's spin when curled is the model's own
	model.position.z = 0.15 * _flinch
	rotation.x = 0.3 * _flinch
	PlayableBoss.tint(_overlay, _dim, maxf(_hurt, model._flash / 0.15))


func set_dim(f: float) -> void:
	_dim = f


func set_hurt(f: float) -> void:
	_hurt = f
