class_name KitVicki
extends KitPart
## Vicki
##   1  Shield Wall           30 s  a shield worth 15% of max HP for 6 s; enemies that hit you while it
##                                  holds take 2x their contact damage back
##   2  Wings of Valhalla     45 s  leap high and glide for up to 4 s (steer as you go), then dive:
##                                  140 within 6 m where you land
##   3  Ride of the Valkyries 120 s a spectral winged horse charges through the horde 3 times where you
##                                  aim: 180 to every enemy on each pass; kills during the ride heal 1%

const WALL_FRAC := 0.15
const WALL_TIME := 6.0
const WALL_THORNS := 2.0
const WING_LIFT := 22.0
const WING_GLIDE := 4.0
const WING_DIVE := 38.0
const WING_RADIUS := 6.0
const WING_DAMAGE := 140.0
const RIDE_PASSES := 3
const RIDE_LENGTH := 50.0
const RIDE_TIME := 0.9               # per pass
const RIDE_GAP := 0.25
const RIDE_WIDTH := 3.5
const RIDE_DAMAGE := 180.0
const RIDE_HEAL := 0.01

var _wall_t := 0.0
var _wall_left := 0.0               # our part of player.shield
var _bubble: MeshInstance3D
var _bubble_mat: StandardMaterial3D
var _wing_state := 0                 # 0 none, 1 rising/gliding, 2 diving
var _wing_t := 0.0
var _wings: Node3D
var _ride_t := -1.0
var _ride_pass := 0
var _ride_dir := Vector3.FORWARD
var _ride_center := Vector3.ZERO
var _ride_hit := {}
var _horse: Node3D


func cast(i: int) -> void:
	match i:
		0: _shield_wall()
		1: _wings_of_valhalla()
		2: _ride()


func active(name: String) -> bool:
	match name:
		"shield_wall": return _wall_t > 0.0
		"wings": return _wing_state != 0
		"ride": return _ride_t >= 0.0
	return false


func tick(dt: float) -> void:
	_tick_wall(dt)
	_tick_wings(dt)
	_tick_ride(dt)


func on_kill(_at: Vector3, _type_id: int) -> void:
	if _ride_t >= 0.0:
		k.heal_pct(RIDE_HEAL)


# ------------------------------------------------------------------ Shield Wall

func _shield_wall() -> void:
	play("shield_wall")
	var amount := player.max_hp * WALL_FRAC * pw(0)
	player.add_shield(amount)
	_wall_left += amount
	_wall_t = WALL_TIME
	player.thorns = WALL_THORNS
	if not is_instance_valid(_bubble):
		_bubble = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.3
		sm.height = 2.6
		_bubble_mat = glow_mat(Color(1.0, 0.85, 0.4, 0.16))
		sm.material = _bubble_mat
		_bubble.mesh = sm
		_bubble.position.y = 1.0
		_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		player.add_child(_bubble)
	ring(feet(), 3.0, k._main, 0.3)


func _tick_wall(dt: float) -> void:
	if _wall_t <= 0.0:
		return
	_wall_t -= dt
	_wall_left = minf(_wall_left, player.shield)   # hits ate into it
	if is_instance_valid(_bubble):
		_bubble_mat.albedo_color.a = 0.1 + 0.08 * sin(_wall_t * 8.0) + (0.1 if player.invuln > 0.3 else 0.0)
	if _wall_t <= 0.0 or _wall_left <= 0.0:
		player.shield = maxf(0.0, player.shield - _wall_left)
		_wall_left = 0.0
		_wall_t = 0.0
		player.thorns = 0.0
		if is_instance_valid(_bubble):
			_bubble.queue_free()


# ------------------------------------------------------------------ Wings of Valhalla

func _wings_of_valhalla() -> void:
	play("wings")
	_wing_state = 1
	_wing_t = WING_GLIDE
	player.launch(WING_LIFT)
	player.glide = true
	if not is_instance_valid(_wings):
		_wings = Node3D.new()
		_wings.position = Vector3(0, 1.45, 0.15)
		var mat := glow_mat(Color(1.0, 0.95, 0.75, 0.55))
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.name = "L" if side < 0.0 else "R"
			var wing := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(1.8, 0.9, 0.04)
			pm.left_to_right = 0.0 if side > 0.0 else 1.0
			pm.material = mat
			wing.mesh = pm
			wing.position = Vector3(0.95 * side, 0.1, 0)
			wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(wing)
			_wings.add_child(pivot)
		player.model.add_child(_wings)
	fx.burst(feet() + Vector3(0, 0.4, 0), 2.5, k._light, 0.3)


func _tick_wings(dt: float) -> void:
	if _wing_state == 0:
		return
	if is_instance_valid(_wings):   # flap
		var f := sin(Time.get_ticks_msec() * 0.012) * (0.5 if _wing_state == 1 else 0.1)
		(_wings.get_node("L") as Node3D).rotation.z = -0.25 + f
		(_wings.get_node("R") as Node3D).rotation.z = 0.25 - f
	if _wing_state == 1:
		_wing_t -= dt
		if randf() < dt * 20.0:
			mote(chest() + Vector3(randf_range(-1, 1), 0.4, 0.3), Vector3(0, -1, 0), 0.8, k._light, 0.1, false, 0.0)
		var landed := player.is_on_floor() and _wing_t < WING_GLIDE - 0.4
		if _wing_t <= 0.0 or landed:
			_wing_state = 2
			player.glide = false
			player.velocity.y = -WING_DIVE
	elif _wing_state == 2:
		player.velocity.y = minf(player.velocity.y, -WING_DIVE)
		if player.is_on_floor():
			_wing_state = 0
			_dive_land(feet())


func _dive_land(at: Vector3) -> void:
	var d := WING_DAMAGE * dmg() * pw(1)
	for i in near(at, WING_RADIUS):
		enemies.damage(i, d)
		enemies.knock(i, enemies.pos[i] - at, 3.0, 0.25)
	ring(at, WING_RADIUS, k._main, 0.4)
	fx.burst(at + Vector3(0, 0.6, 0), WING_RADIUS * 0.6, Color(1.0, 0.9, 0.55), 0.4)
	for m in 18:
		var a := TAU * m / 18.0
		mote(at + Vector3(0, 0.3, 0), Vector3(cos(a) * 9.0, 2.0, sin(a) * 9.0), 0.5, k._light, 0.16, false, 10.0)
	player.add_shake(0.6)
	play("slam", 1.0)
	if is_instance_valid(_wings):
		var w := _wings
		_wings = null
		var tw := w.create_tween()
		tw.tween_property(w, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
		tw.tween_callback(w.queue_free)


# ------------------------------------------------------------------ Ride of the Valkyries

func _ride() -> void:
	play("valkyries")
	var to := aim_point(30.0) - feet()
	to.y = 0.0
	_ride_dir = to.normalized() if to.length() > 1.0 else aim_dir()
	_ride_center = feet()
	_ride_pass = 0
	_ride_t = 0.0
	_ride_hit = {}
	if not is_instance_valid(_horse):
		_horse = _build_horse()
		spawn(_horse, _ride_center)
	_horse.visible = true


func _tick_ride(dt: float) -> void:
	if _ride_t < 0.0:
		return
	_ride_t += dt
	var t := _ride_t / RIDE_TIME
	if t > 1.0:   # between passes: the horse wheels round out of sight
		_horse.visible = false
		if _ride_t >= RIDE_TIME + RIDE_GAP:
			_ride_pass += 1
			_ride_t = 0.0
			_ride_hit = {}
			if _ride_pass >= RIDE_PASSES:
				_ride_t = -1.0
				_horse.queue_free()
				_horse = null
		return
	_horse.visible = true
	# Passes alternate direction and shift sideways a little
	var dir := _ride_dir * (1.0 if _ride_pass % 2 == 0 else -1.0)
	var side := Vector3(-_ride_dir.z, 0, _ride_dir.x) * (_ride_pass - 1) * 3.0
	var p := _ride_center + side - dir * RIDE_LENGTH * 0.5 + dir * RIDE_LENGTH * t
	p = ground(p)
	_horse.global_position = p + Vector3(0, 0.4 + 0.25 * absf(sin(_ride_t * 18.0)), 0)
	_horse.global_basis = Basis.looking_at(dir, Vector3.UP)
	var d := RIDE_DAMAGE * dmg() * pw(2)
	for i in near(p, RIDE_WIDTH):
		var u := enemies.uid[i]
		if _ride_hit.has(u):
			continue
		_ride_hit[u] = true
		var away := enemies.pos[i] - p
		away -= dir * away.dot(dir)
		enemies.damage(i, d)
		enemies.knock(i, away if away.length() > 0.1 else Vector3(-dir.z, 0, dir.x), 4.0, 0.3)
	if randf() < dt * 30.0:
		mote(p + Vector3(randf_range(-1, 1), randf_range(0.5, 2.5), randf_range(-1, 1)), -dir * 4.0, 0.6, k._main, 0.22, false, 2.0)


## A ghostly winged horse built from glowing shapes (about 2.6 m long). Faces -Z.
func _build_horse() -> Node3D:
	var root := Node3D.new()
	var body := glow_mat(Color(0.75, 0.88, 1.0, 0.5))
	var mane := glow_mat(Color(1.0, 0.85, 0.45, 0.7))
	var parts := [
		["cap", Vector3(0, 1.5, 0), Vector3(PI * 0.5, 0, 0), Vector3(0.55, 2.4, 0.55), body],   # barrel
		["cap", Vector3(0, 2.15, -1.25), Vector3(-0.6, 0, 0), Vector3(0.32, 1.2, 0.32), body],  # neck
		["cap", Vector3(0, 2.6, -1.75), Vector3(PI * 0.5 + 0.4, 0, 0), Vector3(0.24, 0.9, 0.24), body],  # head
		["box", Vector3(0, 2.45, -1.05), Vector3(-0.6, 0, 0), Vector3(0.08, 1.0, 0.25), mane],  # mane
		["box", Vector3(0, 1.6, 1.35), Vector3(0.6, 0, 0), Vector3(0.12, 0.9, 0.2), mane],      # tail
	]
	for leg in [[-0.3, -0.85], [0.3, -0.85], [-0.3, 0.85], [0.3, 0.85]]:
		parts.append(["cap", Vector3(leg[0], 0.6, leg[1]), Vector3(0.35 if leg[1] < 0 else -0.35, 0, 0), Vector3(0.14, 1.3, 0.14), body])
	for p in parts:
		var mi := MeshInstance3D.new()
		var m: PrimitiveMesh
		if p[0] == "cap":
			var cm := CapsuleMesh.new()
			cm.radius = p[3].x
			cm.height = p[3].y
			m = cm
		else:
			var bm := BoxMesh.new()
			bm.size = p[3]
			m = bm
		m.material = p[4]
		mi.mesh = m
		mi.position = p[1]
		mi.rotation = p[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	for side in [-1.0, 1.0]:   # wings swept back
		var w := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(2.6, 1.2, 0.04)
		pm.left_to_right = 0.0 if side > 0.0 else 1.0
		pm.material = mane
		w.mesh = pm
		w.position = Vector3(1.3 * side, 2.2, -0.2)
		w.rotation = Vector3(0, 0.35 * side, 0.3 * side)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(w)
	var light := OmniLight3D.new()
	light.light_color = Color(0.8, 0.9, 1.0)
	light.light_energy = 2.5
	light.omni_range = 9.0
	light.position.y = 2.0
	root.add_child(light)
	var trail := particles(0.4, 0.5, 60, Color(1, 0.95, 0.8, 0.8), Color(0.5, 0.7, 1.0, 0.0))
	trail.position.y = 1.4
	trail.emission_sphere_radius = 0.8
	root.add_child(trail)
	return root
