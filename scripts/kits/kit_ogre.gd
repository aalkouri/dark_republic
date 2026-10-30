class_name KitOgre
extends KitPart
## Ogre
##   1  Bellow       30 s  enemies within 14 m flee for 4 s; you take 23% less damage (+30% armour) for 6 s
##   2  Belly Flop   45 s  leap up to 20 m to where you aim; landing: 160 within 7 m + 2 s stun
##   3  Swamp Rage  120 s  12 s: 50% bigger, +60% damage, no knockback, cleave all round (360),
##                         each kill heals 2% of max HP

const BELLOW_RADIUS := 14.0
const BELLOW_FEAR := 4.0
const BELLOW_ARMOR_TIME := 6.0
const BELLOW_ARMOR := 1.3            # damage taken / 1.3
const FLOP_RANGE := 20.0
const FLOP_TIME := 0.8
const FLOP_HEIGHT := 7.0
const FLOP_RADIUS := 7.0
const FLOP_DAMAGE := 160.0
const FLOP_STUN := 2.0
const RAGE_TIME := 12.0
const RAGE_SIZE := 1.5
const RAGE_DAMAGE := 1.6
const RAGE_HEAL := 0.02

var _armor_t := 0.0
var _flop_t := -1.0
var _flop_from := Vector3.ZERO
var _flop_to := Vector3.ZERO
var _flop_marker: GroundDisc
var _rage_t := 0.0
var _rage_fx: CPUParticles3D
var _rage_light: OmniLight3D


func cast(i: int) -> void:
	match i:
		0: _bellow()
		1: _belly_flop()
		2: _swamp_rage()


func active(name: String) -> bool:
	match name:
		"bellow": return _armor_t > 0.0
		"flop": return _flop_t >= 0.0
		"rage": return _rage_t > 0.0
	return false


func tick(dt: float) -> void:
	if _armor_t > 0.0:
		_armor_t -= dt
		if _armor_t <= 0.0:
			player.dmg_taken *= BELLOW_ARMOR
	_tick_flop(dt)
	if _rage_t > 0.0:
		_rage_t -= dt
		if _rage_t <= 0.0:
			_end_rage()


func on_kill(_at: Vector3, _type_id: int) -> void:
	if _rage_t > 0.0:
		k.heal_pct(RAGE_HEAL)


# ------------------------------------------------------------------ Bellow

func _bellow() -> void:
	play("bellow")
	var at := feet()
	for i in near(at, BELLOW_RADIUS):
		enemies.scare(i, BELLOW_FEAR)
		enemies.knock(i, enemies.pos[i] - at, 2.0, 0.2)
	if _armor_t <= 0.0:
		player.dmg_taken /= BELLOW_ARMOR
	_armor_t = BELLOW_ARMOR_TIME
	for r in 3:   # the roar rolls out in waves
		after(r * 0.12, func(): ring(feet(), BELLOW_RADIUS * (0.6 + 0.2 * r), Color(0.75, 0.95, 0.4, 0.7), 0.45))
	var breath := particles(0.5, 0.6, 60, Color(0.8, 1.0, 0.5, 0.5), Color(0.4, 0.5, 0.2, 0.0))
	breath.one_shot = true
	breath.explosiveness = 0.8
	breath.direction = Vector3(0, 0.2, -1)
	breath.spread = 35.0
	breath.initial_velocity_min = 8.0
	breath.initial_velocity_max = 14.0
	breath.position = Vector3(0, 2.0, -0.6)
	player.model.add_child(breath)
	breath.emitting = true
	get_tree().create_timer(1.5).timeout.connect(breath.queue_free)
	player.add_shake(0.55)


# ------------------------------------------------------------------ Belly Flop

func _belly_flop() -> void:
	play("belly_flop")
	_flop_from = feet()
	_flop_to = aim_point(FLOP_RANGE)
	_flop_t = 0.0
	begin_scripted()
	player.invuln = maxf(player.invuln, FLOP_TIME + 0.2)
	_flop_marker = GroundDisc.create(FLOP_RADIUS, Color(1.0, 0.75, 0.3, 0.3), true)
	_flop_marker.set_ring(0.85)
	spawn(_flop_marker, _flop_to)


func _tick_flop(dt: float) -> void:
	if _flop_t < 0.0:
		return
	_flop_t += dt / FLOP_TIME
	var t := minf(_flop_t, 1.0)
	var e := t * t * (3.0 - 2.0 * t) if t < 0.5 else t
	var p := _flop_from.lerp(_flop_to, e) + Vector3(0, 4.0 * t * (1.0 - t) * FLOP_HEIGHT, 0)
	player.velocity = (_flop_to - _flop_from).normalized() * 10.0
	player.global_position = p
	if is_instance_valid(_flop_marker):
		_flop_marker.set_fill(t)
	if _flop_t >= 1.0:
		_flop_t = -1.0
		end_scripted(_flop_to)
		_flop_land(_flop_to)


func _flop_land(at: Vector3) -> void:
	if is_instance_valid(_flop_marker):
		_flop_marker.queue_free()
	var d := FLOP_DAMAGE * dmg()
	for i in near(at, FLOP_RADIUS):
		enemies.stun(i, FLOP_STUN)
		enemies.damage(i, d)
		enemies.knock(i, enemies.pos[i] - at, 2.5, 0.2)
	ring(at, FLOP_RADIUS, Color(0.95, 0.8, 0.5), 0.4)
	ring(at, FLOP_RADIUS * 0.6, Color(0.7, 0.55, 0.3), 0.3)
	fx.burst(at + Vector3(0, 0.5, 0), FLOP_RADIUS * 0.6, Color(0.6, 0.5, 0.35), 0.45)
	for m in 24:   # mud and water flying
		var a := randf() * TAU
		mote(at + Vector3(0, 0.3, 0), Vector3(cos(a) * randf_range(4, 9), randf_range(4, 9), sin(a) * randf_range(4, 9)), 0.7, Color(0.45, 0.4, 0.25), 0.25, false, 14.0)
	player.add_shake(0.8)
	play("slam", 2.0)


# ------------------------------------------------------------------ Swamp Rage

func _swamp_rage() -> void:
	play("swamp_rage")
	if _rage_t <= 0.0:
		stats.apply("damage", "mult", RAGE_DAMAGE)
		player.size_mult = RAGE_SIZE
		player.no_knockback = true
		_rage_fx = particles(0.35, 0.7, 50, Color(1.0, 0.45, 0.2, 0.8), Color(0.5, 0.05, 0.0, 0.0))
		_rage_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		_rage_fx.emission_ring_axis = Vector3.UP
		_rage_fx.emission_ring_radius = 0.8
		_rage_fx.emission_ring_inner_radius = 0.5
		_rage_fx.emission_ring_height = 0.1
		_rage_fx.gravity = Vector3(0, 3.0, 0)
		_rage_fx.position.y = 0.2
		player.add_child(_rage_fx)
		_rage_light = OmniLight3D.new()
		_rage_light.light_color = Color(1.0, 0.35, 0.15)
		_rage_light.light_energy = 1.6
		_rage_light.omni_range = 6.0
		_rage_light.position.y = 2.0
		player.add_child(_rage_light)
	_rage_t = RAGE_TIME
	fx.burst(chest(), 4.0, Color(1.0, 0.4, 0.15), 0.4)
	player.add_shake(0.6)


func _end_rage() -> void:
	stats.apply("damage", "mult", 1.0 / RAGE_DAMAGE)
	player.size_mult = 1.0
	player.no_knockback = false
	if is_instance_valid(_rage_fx):
		_rage_fx.queue_free()
	if is_instance_valid(_rage_light):
		_rage_light.queue_free()
