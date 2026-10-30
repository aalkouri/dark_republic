class_name KitCroc
extends KitPart
## Dr. Croc
##   1  Mutagen      30 s  +50% attack speed and +30% move speed for 8 s; you take +10% damage
##   2  Death Roll   45 s  roll 15 m where you aim, grabbing enemies in your path: 50 every 0.25 s
##                         while held, flung away at the end
##   3  Toxic Spill 120 s  a 20 m flood of acid round you for 10 s: 4% of max HP per second;
##                         enemies that die in it burst for 30% of their max HP within 3 m

const MUTAGEN_TIME := 8.0
const MUTAGEN_HASTE := 1.5
const MUTAGEN_SPEED := 1.3
const MUTAGEN_FRAIL := 1.1
const ROLL_RANGE := 15.0
const ROLL_TIME := 1.1
const ROLL_GRAB := 1.8
const ROLL_MAX := 14
const ROLL_DAMAGE := 50.0
const ROLL_TICK := 0.25
const ROLL_FLING := 8.0
const SPILL_RADIUS := 20.0
const SPILL_TIME := 10.0
const SPILL_DPS := 0.04
const SPILL_BURST := 0.3
const SPILL_BLAST := 3.0

var _mutagen_t := 0.0
var _bubbles: CPUParticles3D
var _roll_t := -1.0
var _roll_from := Vector3.ZERO
var _roll_to := Vector3.ZERO
var _held: Array = []               # uids
var _roll_tick := 0.0
var _spill_t := 0.0
var _spill_tick := 0.0
var _spill_at := Vector3.ZERO
var _spill_root: Node3D


func cast(i: int) -> void:
	match i:
		0: _mutagen()
		1: _death_roll()
		2: _toxic_spill()


func active(name: String) -> bool:
	match name:
		"mutagen": return _mutagen_t > 0.0
		"roll": return _roll_t >= 0.0
		"spill": return _spill_t > 0.0
	return false


func tick(dt: float) -> void:
	_tick_mutagen(dt)
	_tick_roll(dt)
	_tick_spill(dt)


# ------------------------------------------------------------------ Mutagen

func _mutagen() -> void:
	play("mutagen")
	if _mutagen_t <= 0.0:
		stats.apply("attack_speed", "mult", MUTAGEN_HASTE)
		stats.apply("move_speed", "mult", MUTAGEN_SPEED)
		player.dmg_taken *= MUTAGEN_FRAIL
		_bubbles = particles(0.22, 0.9, 40, Color(0.75, 1.0, 0.4, 0.9), Color(0.3, 0.8, 0.1, 0.0))
		_bubbles.emission_sphere_radius = 0.5
		_bubbles.position.y = 1.0
		_bubbles.gravity = Vector3(0, 2.5, 0)
		player.add_child(_bubbles)
	_mutagen_t = MUTAGEN_TIME
	fx.burst(chest() + Vector3(0, 0.6, 0), 2.0, k._main, 0.35)


func _tick_mutagen(dt: float) -> void:
	if _mutagen_t <= 0.0:
		return
	_mutagen_t -= dt
	if _mutagen_t <= 0.0:
		stats.apply("attack_speed", "mult", 1.0 / MUTAGEN_HASTE)
		stats.apply("move_speed", "mult", 1.0 / MUTAGEN_SPEED)
		player.dmg_taken /= MUTAGEN_FRAIL
		if is_instance_valid(_bubbles):
			_bubbles.queue_free()


# ------------------------------------------------------------------ Death Roll

func _death_roll() -> void:
	play("death_roll")
	var to := aim_point(ROLL_RANGE) - feet()
	to.y = 0.0
	var dir := to.normalized() if to.length() > 1.0 else aim_dir()
	_roll_from = feet()
	_roll_to = ground(_roll_from + dir * ROLL_RANGE)
	var q := PhysicsRayQueryParameters3D.create(_roll_from + Vector3(0, 0.8, 0), _roll_to + Vector3(0, 0.8, 0))
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():   # stop at the wall
		_roll_to = ground(_roll_from.lerp(_roll_to, maxf(0.0, (_roll_from.distance_to(hit["position"]) - 0.8) / ROLL_RANGE)))
	_roll_t = 0.0
	_roll_tick = ROLL_TICK
	_held.clear()
	begin_scripted()


func _tick_roll(dt: float) -> void:
	if _roll_t < 0.0:
		return
	_roll_t += dt / ROLL_TIME
	var t := minf(_roll_t, 1.0)
	var p := _roll_from.lerp(_roll_to, t)
	var dir := (_roll_to - _roll_from)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else aim_dir()
	player.global_position = p
	player.velocity = dir * 12.0
	player.model.rotation.z = t * TAU * 3.0   # spinning along the way
	# Grab whatever's in the way
	for i in near(p, ROLL_GRAB, true):
		if _held.size() >= ROLL_MAX:
			break
		var u := enemies.uid[i]
		if not _held.has(u):
			_held.append(u)
	# Carry them round with him, stunned
	var k2 := 0
	for u in _held:
		var i := enemies.index_of(u)
		if i < 0:
			continue
		var a := float(k2) / maxf(1.0, _held.size()) * TAU + _roll_t * 20.0
		enemies.pos[i] = p + Vector3(cos(a) * 1.3, 0.0, sin(a) * 1.3) + dir * 0.6
		enemies.stun(i, 0.4)
		k2 += 1
	_roll_tick -= dt
	if _roll_tick <= 0.0:
		_roll_tick += ROLL_TICK
		var d := ROLL_DAMAGE * dmg()
		for u in _held:
			var i := enemies.index_of(u)
			if i >= 0:
				enemies.damage(i, d)
		fx.burst(p + Vector3(0, 0.5, 0), 1.6, Color(0.55, 0.5, 0.3), 0.2)
	if _roll_t >= 1.0:
		_roll_t = -1.0
		player.model.rotation.z = 0.0
		end_scripted(_roll_to)
		for u in _held:   # flung away
			var i := enemies.index_of(u)
			if i >= 0:
				enemies.knock(i, enemies.pos[i] - _roll_to + dir * 0.5, ROLL_FLING, 0.35)
				enemies.stun(i, 0.8)
		_held.clear()
		ring(_roll_to, 4.0, k._main, 0.3)
		player.add_shake(0.35)


# ------------------------------------------------------------------ Toxic Spill

func _toxic_spill() -> void:
	play("toxic_spill")
	_spill_at = feet()
	_spill_t = SPILL_TIME
	_spill_tick = 0.0
	enemies.burst_center = _spill_at
	enemies.burst_radius = SPILL_RADIUS
	enemies.burst_frac = SPILL_BURST
	enemies.burst_blast = SPILL_BLAST
	if is_instance_valid(_spill_root):
		_spill_root.queue_free()
	_spill_root = Node3D.new()
	spawn(_spill_root, _spill_at)
	var flood := GroundDisc.create(SPILL_RADIUS, Color(0.4, 0.95, 0.15, 0.32), true)
	_spill_root.add_child(flood)
	var rim := GroundDisc.create(SPILL_RADIUS, Color(0.7, 1.0, 0.35, 0.5), true)
	rim.set_ring(0.95)
	_spill_root.add_child(rim)
	var bubbles := particles(0.4, 1.0, 160, Color(0.7, 1.0, 0.35, 0.8), Color(0.25, 0.6, 0.05, 0.0))
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	bubbles.emission_sphere_radius = SPILL_RADIUS * 0.9
	bubbles.scale = Vector3(1, 0.04, 1)
	bubbles.gravity = Vector3(0, 0.8, 0)
	bubbles.initial_velocity_max = 0.6
	_spill_root.add_child(bubbles)
	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 1.0, 0.25)
	light.light_energy = 2.0
	light.omni_range = SPILL_RADIUS * 1.2
	light.position.y = 5.0
	_spill_root.add_child(light)
	_spill_root.scale = Vector3(0.05, 1, 0.05)
	_spill_root.create_tween().tween_property(_spill_root, "scale", Vector3.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	player.add_shake(0.4)


func _tick_spill(dt: float) -> void:
	if _spill_t <= 0.0:
		return
	_spill_t -= dt
	_spill_tick -= dt
	if _spill_tick <= 0.0:
		_spill_tick = 0.25
		for i in near(_spill_at, SPILL_RADIUS):
			enemies.dot_damage(i, enemies.hp_max[i] * SPILL_DPS * 0.25 * enemies.pct_scale(i))
	if _spill_t <= 0.0:
		enemies.burst_radius = 0.0
		var root := _spill_root
		_spill_root = null
		if is_instance_valid(root):
			var tw := root.create_tween()
			tw.tween_property(root, "scale", Vector3(0.02, 1, 0.02), 0.8).set_ease(Tween.EASE_IN)
			tw.tween_callback(root.queue_free)
