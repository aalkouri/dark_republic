class_name Player
extends CharacterBody3D
## Kinematic character controller with Quake-style acceleration.
##  - Ground: friction + capped acceleration toward the camera-relative wish direction.
##  - Air: classic air-strafe acceleration (small wishspeed cap) plus mild air control,
##    so strafing while turning gains speed.
##  - Bunny hop: no friction on the frame you jump, plus a short grace window after
##    landing, so chained jumps keep momentum.
##  - Slide: hold slide while running for a burst + very low friction; slopes accelerate you.
##  - Coyote time and jump buffering for forgiving input.

signal died

const GRAVITY := 30.0
const JUMP_VELOCITY := 10.5
const GROUND_ACCEL := 12.0
const FRICTION := 7.0
const STOP_SPEED := 3.0
const AIR_ACCEL := 14.0
const AIR_CAP := 1.0
const AIR_CONTROL := 5.0
const SLIDE_FRICTION := 0.45
const SLIDE_BOOST := 5.0
const SLIDE_MIN_SPEED := 4.0
const SLIDE_COOLDOWN := 0.8
const SLIDE_STEER := 6.0
const SLOPE_GAIN := 1.3
const MAX_HSPEED := 32.0
const COYOTE := 0.12
const JUMP_BUFFER := 0.12
const BHOP_GRACE := 0.06
const MOUSE_SENS := 0.0025
const PAD_LOOK_SPEED := 3.0
const IFRAMES := 0.5             # immunity after an enemy collision
const IMMUNE_DIM := 0.5           # character brightness while immune
const KNOCK_SPEED := 11.0
const KNOCK_POP := 4.0
const WATER_SPEED_MULT := 0.5
const WATER_JUMP_HEIGHT_MULT := 0.5   # jump height scales with v^2, so velocity * sqrt(0.5)
const WATER_DRAG := 6.0               # how fast extra momentum bleeds off in water

var stats: Stats
var hp := 100.0
var max_hp := 100.0
var invuln := 0.0
var god_mode := false
var shield := 0.0
var water: SwampWater
var in_water := false
## While true the wizard has turned into the meteor: hidden, untouchable, no collision,
## and Abilities drives his position along the meteor's path (the camera follows).
var meteor_form := false
var _collider: CollisionShape3D
const SPRING_NORMAL := 6.5
const SPRING_METEOR := 14.0
var face_camera := false   # screenshot/portrait mode

# Bot input (used by the headless smoke test)
var bot := false
var bot_move := Vector2.ZERO
var bot_jump := false
var bot_slide := false

var sliding := false
var cam_yaw := 0.0
var cam_pitch := -0.3

var _coyote := 0.0
var _jump_buf := 0.0
var _air_jumps := 0
var _land_grace := 0.0
var _prev_floor := false
var _slide_cd := 0.0

var rig: Node3D
var spring: SpringArm3D
var cam: Camera3D
var model: WizardModel
var fx: FxManager          # set by main; used for the ash trail
var _ash_dist := 0.0
var _ash_side := 1.0
var _shake := 0.0


func _ready() -> void:
	max_hp = stats.value("max_hp")
	hp = max_hp
	stats.changed.connect(_on_stat_changed)

	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)

	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)
	_collider = col

	_build_model()

	rig = Node3D.new()
	rig.top_level = true
	add_child(rig)
	spring = SpringArm3D.new()
	spring.spring_length = 6.5
	spring.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring.shape = probe
	spring.add_excluded_object(get_rid())
	rig.add_child(spring)
	cam = Camera3D.new()
	cam.fov = Settings.fov
	cam.far = 400.0
	spring.add_child(cam)
	cam.current = true
	rig.global_position = global_position + Vector3(0, 1.6, 0)


func _build_model() -> void:
	model = WizardModel.new()
	add_child(model)


func _on_stat_changed(stat: String) -> void:
	if stat == "max_hp":
		var new_max := stats.value("max_hp")
		hp += maxf(0.0, new_max - max_hp)
		max_hp = new_max


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * Settings.mouse_sensitivity
		var dy: float = event.relative.y * (-1.0 if Settings.invert_y else 1.0)
		cam_yaw -= event.relative.x * sens
		cam_pitch = clampf(cam_pitch - dy * sens, -1.25, 0.4)


func _physics_process(dt: float) -> void:
	if meteor_form:
		_follow_camera(dt)
		return
	var input: Vector2
	var jump_pressed: bool
	var slide_held: bool
	if bot:
		input = bot_move
		jump_pressed = bot_jump
		slide_held = bot_slide
	else:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		jump_pressed = Input.is_action_just_pressed("jump")
		slide_held = Input.is_action_pressed("slide")
		var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		cam_yaw -= look.x * PAD_LOOK_SPEED * dt
		cam_pitch = clampf(cam_pitch - look.y * PAD_LOOK_SPEED * dt, -1.25, 0.4)

	var fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var wish := right * input.x - fwd * input.y
	var wish_len := minf(wish.length(), 1.0)
	var wishdir := wish.normalized() if wish_len > 0.01 else Vector3.ZERO
	var move_speed := stats.value("move_speed")
	in_water = water != null and water.in_water(global_position)
	if in_water:
		move_speed *= WATER_SPEED_MULT

	if jump_pressed:
		_jump_buf = JUMP_BUFFER
	_jump_buf -= dt
	_slide_cd -= dt
	_land_grace -= dt

	var on_floor := is_on_floor()
	if on_floor:
		if not _prev_floor:
			_land_grace = BHOP_GRACE
		_coyote = COYOTE
		_air_jumps = int(stats.value("extra_jumps"))
	else:
		_coyote -= dt
	_prev_floor = on_floor

	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var hspeed := hv.length()

	# --- Jump (ground, coyote, or air jump)
	var jumped := false
	if _jump_buf > 0.0:
		if _coyote > 0.0:
			jumped = true
		elif _air_jumps > 0:
			_air_jumps -= 1
			jumped = true
			if wish_len > 0.1:  # air jumps let you redirect without losing speed
				hv = wishdir * maxf(hspeed, move_speed * 0.8)
	if jumped:
		velocity.y = JUMP_VELOCITY * (sqrt(WATER_JUMP_HEIGHT_MULT) if in_water else 1.0)
		_jump_buf = 0.0
		_coyote = 0.0
		on_floor = false
		sliding = false

	# --- Slide state
	if on_floor and slide_held and hspeed > SLIDE_MIN_SPEED and not in_water:
		if not sliding:
			sliding = true
			if _slide_cd <= 0.0:
				hv += hv / hspeed * SLIDE_BOOST
				_slide_cd = SLIDE_COOLDOWN
	elif sliding:
		sliding = false

	# --- Horizontal movement
	if on_floor:
		if sliding:
			hv = _friction(hv, SLIDE_FRICTION, dt)
			var n := get_floor_normal()
			var g := Vector3(0.0, -GRAVITY, 0.0)
			var along := g - n * g.dot(n)
			hv += Vector3(along.x, 0.0, along.z) * SLOPE_GAIN * dt
			if wish_len > 0.1:
				var sp := hv.length()
				hv = hv.move_toward(wishdir * sp, SLIDE_STEER * dt).normalized() * sp
		else:
			if _land_grace <= 0.0 or wish_len < 0.1:
				hv = _friction(hv, FRICTION, dt)
			hv = _accelerate(hv, wishdir, move_speed * wish_len, GROUND_ACCEL, dt)
		velocity.y = 0.0
	else:
		if wish_len > 0.1:
			if hv.length() < move_speed:
				hv = _accelerate(hv, wishdir, move_speed, AIR_CONTROL, dt)
			hv = _accelerate(hv, wishdir, AIR_CAP, AIR_ACCEL, dt)
		velocity.y -= GRAVITY * dt

	# Water: bleed off any speed above the (halved) move speed
	if in_water and hv.length() > move_speed:
		hv = hv.normalized() * maxf(move_speed, hv.length() - WATER_DRAG * move_speed * dt)
	if hv.length() > MAX_HSPEED:
		hv = hv.normalized() * MAX_HSPEED
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()

	if global_position.y < -25.0:
		global_position = Vector3(0, 3, 0)
		velocity = Vector3.ZERO

	hp = minf(hp + stats.value("regen") * dt, max_hp)
	invuln -= dt
	_update_visuals(dt)


func _accelerate(hv: Vector3, wishdir: Vector3, wishspeed: float, accel: float, dt: float) -> Vector3:
	if wishdir == Vector3.ZERO:
		return hv
	var add := wishspeed - hv.dot(wishdir)
	if add <= 0.0:
		return hv
	return hv + wishdir * minf(accel * wishspeed * dt, add)


func _friction(hv: Vector3, friction: float, dt: float) -> Vector3:
	var sp := hv.length()
	if sp < 0.01:
		return Vector3.ZERO
	var drop := maxf(sp, STOP_SPEED) * friction * dt
	return hv * (maxf(sp - drop, 0.0) / sp)


func _update_visuals(dt: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var target_yaw := cam_yaw
	if face_camera:
		target_yaw = cam_yaw + PI
	elif hv.length() > 0.5:
		target_yaw = atan2(-hv.x, -hv.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-15.0 * dt))
	var squash := Vector3(1.15, 0.55, 1.15) if sliding else Vector3.ONE
	model.scale = model.scale.lerp(squash, 1.0 - exp(-20.0 * dt))

	model.set_dim(IMMUNE_DIM if invuln > 0.0 else 1.0)
	_update_ash(dt)

	var head := global_position + Vector3(0.0, 1.0 if sliding else 1.6, 0.0)
	rig.global_position = rig.global_position.lerp(head, 1.0 - exp(-20.0 * dt))
	rig.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	var fov_target := Settings.fov + clampf((hv.length() - 9.0) * 0.9, 0.0, 22.0)
	cam.fov = lerpf(cam.fov, fov_target, 1.0 - exp(-6.0 * dt))
	_shake = maxf(0.0, _shake - dt * 1.8)
	var sk := _shake * _shake
	cam.h_offset = randf_range(-1.0, 1.0) * sk * 0.5
	cam.v_offset = randf_range(-1.0, 1.0) * sk * 0.5


## Ash footprints: a flake every ~0.45 m travelled on the ground, alternating feet.
func _update_ash(dt: float) -> void:
	if fx == null or not is_on_floor() or in_water:
		return
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var sp := hv.length()
	if sp < 1.0:
		return
	_ash_dist += sp * dt
	var step := 0.3 if sliding else 0.45
	while _ash_dist >= step:
		_ash_dist -= step
		var side := Vector3(-hv.z, 0.0, hv.x) / sp
		var jitter := Vector3(randf_range(-0.06, 0.06), 0.0, randf_range(-0.06, 0.06))
		var off := side * (0.0 if sliding else 0.17 * _ash_side)
		fx.ash(global_position + off + jitter + Vector3(0, 0.03, 0))
		_ash_side = -_ash_side


func add_shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.0)


## Applies contact damage and starts the immunity window. Returns false if already immune.
## Shield absorbs damage before HP.
func enter_meteor_form() -> void:
	meteor_form = true
	model.visible = false
	_collider.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	sliding = false
	spring.spring_length = SPRING_METEOR


func exit_meteor_form(at: Vector3) -> void:
	meteor_form = false
	global_position = at + Vector3(0, 0.05, 0)
	velocity = Vector3.ZERO
	model.visible = true
	_collider.set_deferred("disabled", false)
	spring.spring_length = SPRING_NORMAL
	invuln = maxf(invuln, 0.25)   # a moment to get bearings after landing


func _follow_camera(dt: float) -> void:
	var head := global_position + Vector3(0.0, 1.6, 0.0)
	rig.global_position = rig.global_position.lerp(head, 1.0 - exp(-12.0 * dt))
	rig.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	_shake = maxf(0.0, _shake - dt * 1.8)
	var sk := _shake * _shake
	cam.h_offset = randf_range(-1.0, 1.0) * sk * 0.5
	cam.v_offset = randf_range(-1.0, 1.0) * sk * 0.5


func hurt(amount: float) -> bool:
	if meteor_form or invuln > 0.0 or hp <= 0.0:
		return false
	invuln = IFRAMES
	if god_mode:
		return true
	var armor := stats.value("armor")
	amount *= 20.0 / (20.0 + armor)
	var absorbed := minf(shield, amount)
	shield -= absorbed
	amount -= absorbed
	hp -= amount
	Events.player_damaged.emit(amount)
	if hp <= 0.0:
		hp = 0.0
		died.emit()
	return true


## Shove the player along `dir` (horizontal) with a small hop.
func knockback(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	velocity.x = dir.x * KNOCK_SPEED
	velocity.z = dir.z * KNOCK_SPEED
	if is_on_floor():
		velocity.y = KNOCK_POP
	sliding = false


func add_shield(amount: float) -> void:
	shield += amount


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
