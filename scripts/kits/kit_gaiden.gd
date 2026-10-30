class_name KitGaiden
extends KitPart
## Gaiden
##   1  Shadow Step     20 s  teleport behind the enemy with the most HP within 20 m and strike for
##                            250; invulnerable 1.5 s afterwards; holds 2 charges
##   2  Shuriken Storm  45 s  3 rings of 12 shuriken over 2 s: 50 each, they pierce
##   3  Reed Clones    120 s  4 shadow clones for 12 s that copy your attacks at 60% damage

const STEP_RADIUS := 20.0
const STEP_DAMAGE := 250.0
const STEP_IMMUNE := 1.5
const STEP_CHARGES := 2
const STORM_RINGS := 3
const STORM_PER_RING := 12
const STORM_TIME := 2.0
const STORM_DAMAGE := 50.0
const STORM_SPEED := 20.0
const STORM_RANGE := 22.0
const CLONE_COUNT := 4
const CLONE_TIME := 12.0
const CLONE_RING := 2.4

var charges := STEP_CHARGES
var _recharge := 0.0
var _storm_left := 0
var _storm_t := 0.0
var _clones: Array = []             # {model, offset}
var _clone_t := 0.0
var _clone_spin := 0.0


func cast(i: int) -> void:
	match i:
		0: _shadow_step()
		1: _shuriken_storm()
		2: _reed_clones()


func active(name: String) -> bool:
	match name:
		"storm": return _storm_left > 0
		"clones": return not _clones.is_empty()
	return false


## Shadow Step keeps a second charge: casting it only starts the cooldown when none are left.
func adjust_cooldown(i: int, cd: float) -> float:
	if i != 0:
		return cd
	if charges == STEP_CHARGES:
		_recharge = cd
	charges -= 1
	return 0.0 if charges > 0 else _recharge


func clone_damage() -> float:
	return RosterKit.CLONE_DAMAGE * pw(2)   # Reed Clones hit harder as the ability levels up


func clone_list() -> Array:
	var out := []
	for c in _clones:
		var m: Node3D = c["model"]
		out.append([m, m.global_position])
	return out


func tick(dt: float) -> void:
	if charges < STEP_CHARGES:
		_recharge -= dt
		if _recharge <= 0.0:
			charges += 1
			var c := k.hub.cooldown
			c[0] = 0.0
			k.hub.cooldown = c
			if charges < STEP_CHARGES:
				_recharge = float(k.hub.defs()[0]["cooldown"])
	_tick_storm(dt)
	_tick_clones(dt)


# ------------------------------------------------------------------ Shadow Step

func _shadow_step() -> void:
	play("shadow_step")
	var best := -1
	for i in near(feet(), STEP_RADIUS):
		if best < 0 or enemies.hp[i] > enemies.hp[best]:
			best = i
	var from := feet()
	if best < 0:   # nobody about: a short blink forward
		var to := ground(from + aim_dir() * 8.0)
		_puff(from)
		player.global_position = to + Vector3(0, 0.05, 0)
		_puff(to)
		return
	var ep := enemies.pos[best]
	var through := ep - from
	through.y = 0.0
	var dir := through.normalized() if through.length() > 0.1 else aim_dir()
	var at := ground(ep + dir * (enemies.t_radius[enemies.typ[best]] * enemies.sz[best] + 0.9))
	_puff(from)
	player.global_position = at + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	_puff(at)
	player.model.attack(enemies.center_of(best))
	enemies.damage(best, STEP_DAMAGE * dmg() * pw(0), dir * 3.0)
	player.invuln = maxf(player.invuln, STEP_IMMUNE)
	if k.weapons:
		k.weapons._sector(ep + Vector3(0, 1.0, 0), -dir, 2.2, 120.0, Color(1.0, 0.3, 0.35, 0.85), 0.25, 0.6)
	player.add_shake(0.3)


func _puff(at: Vector3) -> void:
	fx.burst(at + Vector3(0, 0.9, 0), 1.6, Color(0.25, 0.2, 0.3), 0.3)
	for m in 8:
		var a := TAU * m / 8.0
		mote(at + Vector3(0, 0.8, 0), Vector3(cos(a) * 3.0, randf_range(0.5, 2.0), sin(a) * 3.0), 0.5, k._deep.lerp(k._main, 0.2), 0.3, false, 6.0)


# ------------------------------------------------------------------ Shuriken Storm

func _shuriken_storm() -> void:
	play("shuriken")
	_storm_left = STORM_RINGS
	_storm_t = 0.0


func _tick_storm(dt: float) -> void:
	if _storm_left <= 0:
		return
	_storm_t -= dt
	if _storm_t > 0.0:
		return
	_storm_t = STORM_TIME / STORM_RINGS
	var ring_i := STORM_RINGS - _storm_left
	_storm_left -= 1
	if k.weapons == null:
		return
	var from := chest() + Vector3(0, 0.2, 0)
	var kind := WeaponSystem.P_KINDS.find("shuriken")
	var off := ring_i * (TAU / STORM_PER_RING / STORM_RINGS)   # each ring turned a little: a spiral
	for s in STORM_PER_RING:
		var a := off + TAU * s / STORM_PER_RING
		var dir := Vector3(cos(a), 0.0, sin(a))
		k.weapons.spawn_projectile(from + dir * 0.5, dir * STORM_SPEED, STORM_RANGE / STORM_SPEED, STORM_DAMAGE * dmg() * pw(1), 99, kind)
	player.model.attack(from + Vector3(cos(off), 0, sin(off)) * 5.0)
	play("whirl", -6.0)


# ------------------------------------------------------------------ Reed Clones

func _reed_clones() -> void:
	play("reed_clones")
	_clone_t = CLONE_TIME
	if not _clones.is_empty():
		return
	for c in CLONE_COUNT:
		var m := RosterHero.create("gaiden")
		spawn(m, feet())
		m.set_dim(0.15)
		var a := TAU * c / CLONE_COUNT
		_clones.append({"model": m, "angle": a})
		_puff(feet() + Vector3(cos(a), 0, sin(a)) * CLONE_RING)


func _tick_clones(dt: float) -> void:
	if _clones.is_empty():
		return
	_clone_t -= dt
	_clone_spin += dt * 0.6
	var center := feet()
	var sp := Vector2(player.velocity.x, player.velocity.z).length()
	for c in _clones:
		var m: RosterHero = c["model"]
		var a: float = c["angle"] + _clone_spin
		var want := ground(center + Vector3(cos(a), 0, sin(a)) * CLONE_RING)
		var was := m.global_position
		m.global_position = was.lerp(want, 1.0 - exp(-10.0 * dt))
		var mv := m.global_position - was
		mv.y = 0.0
		if mv.length() > 0.01:
			m.rotation.y = lerp_angle(m.rotation.y, atan2(-mv.x, -mv.z), 1.0 - exp(-12.0 * dt))
		m.set_motion(maxf(sp, mv.length() / maxf(dt, 0.001)), false)
		m.set_dim(0.15)
	if _clone_t <= 0.0:
		for c in _clones:
			var m: Node3D = c["model"]
			_puff(m.global_position)
			m.queue_free()
		_clones.clear()
