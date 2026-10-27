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
const IFRAMES := 0.45

var stats: Stats
var hp := 100.0
var max_hp := 100.0
var invuln := 0.0
var god_mode := false

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
var _hurt_flash := 0.0

var rig: Node3D
var spring: SpringArm3D
var cam: Camera3D
var model: Node3D
var _body_mat: StandardMaterial3D


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
	cam.fov = 75.0
	cam.far = 400.0
	spring.add_child(cam)
	cam.current = true
	rig.global_position = global_position + Vector3(0, 1.6, 0)


func _build_model() -> void:
	model = Node3D.new()
	add_child(model)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.45, 0.75, 1.0)
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(1, 0.1, 0.1)
	_body_mat.emission_energy_multiplier = 0.0
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.8
	cap.material = _body_mat
	body.mesh = cap
	body.position.y = 0.9
	model.add_child(body)

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.05, 0.08)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.07
		em.height = 0.14
		em.material = eye_mat
		eye.mesh = em
		eye.position = Vector3(0.14 * side, 1.45, -0.36)
		model.add_child(eye)

	var club := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.16, 0.16, 1.1)
	var club_mat := StandardMaterial3D.new()
	club_mat.albedo_color = Color(0.55, 0.36, 0.2)
	cm.material = club_mat
	club.mesh = cm
	club.position = Vector3(0.55, 1.0, -0.35)
	club.rotation = Vector3(deg_to_rad(-30.0), 0.0, 0.0)
	model.add_child(club)


func _on_stat_changed(stat: String) -> void:
	if stat == "max_hp":
		var new_max := stats.value("max_hp")
		hp += maxf(0.0, new_max - max_hp)
		max_hp = new_max


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * MOUSE_SENS
		cam_pitch = clampf(cam_pitch - event.relative.y * MOUSE_SENS, -1.25, 0.4)


func _physics_process(dt: float) -> void:
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
		velocity.y = JUMP_VELOCITY
		_jump_buf = 0.0
		_coyote = 0.0
		on_floor = false
		sliding = false

	# --- Slide state
	if on_floor and slide_held and hspeed > SLIDE_MIN_SPEED:
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
	if hv.length() > 0.5:
		target_yaw = atan2(-hv.x, -hv.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-15.0 * dt))
	var squash := Vector3(1.15, 0.55, 1.15) if sliding else Vector3.ONE
	model.scale = model.scale.lerp(squash, 1.0 - exp(-20.0 * dt))

	_hurt_flash = maxf(0.0, _hurt_flash - dt * 4.0)
	_body_mat.emission_energy_multiplier = _hurt_flash * 3.0

	var head := global_position + Vector3(0.0, 1.0 if sliding else 1.6, 0.0)
	rig.global_position = rig.global_position.lerp(head, 1.0 - exp(-20.0 * dt))
	rig.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	var fov_target := 75.0 + clampf((hv.length() - 9.0) * 0.9, 0.0, 22.0)
	cam.fov = lerpf(cam.fov, fov_target, 1.0 - exp(-6.0 * dt))


func hurt(amount: float) -> void:
	if god_mode or invuln > 0.0 or hp <= 0.0:
		return
	var armor := stats.value("armor")
	amount *= 20.0 / (20.0 + armor)
	hp -= amount
	invuln = IFRAMES
	_hurt_flash = 1.0
	Events.player_damaged.emit(amount)
	if hp <= 0.0:
		hp = 0.0
		died.emit()


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
