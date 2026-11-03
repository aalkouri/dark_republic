class_name KitKong
extends KitPart
## Kong
##   1  Chest Pound  30 s  3 shockwaves to 10 m, 50 each; the last stuns for 2 s
##   2  Log Toss     45 s  rips up a log and bowls it 30 m where you aim: 120 to every enemy
##                         it flattens
##   3  Rampage     120 s  12 s: +80% damage, +50% move speed; every 3 m he runs the ground
##                         quakes (60 within 6 m); his broken chains lash out to 25 m

const POUND_RADIUS := 10.0
const POUND_DAMAGE := 50.0
const POUND_STUN := 2.0
const LOG_RANGE := 30.0
const LOG_SPEED := 18.0
const LOG_DAMAGE := 120.0
const LOG_HIT := 2.0
const RAMPAGE_TIME := 12.0
const RAMPAGE_DAMAGE := 1.8
const RAMPAGE_SPEED := 1.5
const QUAKE_EVERY := 3.0
const QUAKE_RADIUS := 6.0
const QUAKE_DAMAGE := 60.0
const LASH_RANGE := 25.0
const LASH_DAMAGE := 40.0

var _log: Node3D
var _log_dir := Vector3.ZERO
var _log_left := 0.0
var _log_hit := {}
var _rage_t := 0.0
var _rage_mult := RAMPAGE_DAMAGE
var _walked := 0.0
var _last := Vector3.INF
var _lash_t := 0.0


func cast(i: int) -> void:
	src(i)
	match i:
		0: _chest_pound()
		1: _log_toss()
		2: _rampage()


func active(name: String) -> bool:
	match name:
		"log": return _log_left > 0.0
		"rampage": return _rage_t > 0.0
	return false


func tick(dt: float) -> void:
	src(1)
	_tick_log(dt)
	src(2)
	_tick_rampage(dt)


# ------------------------------------------------------------------ Chest Pound

func _chest_pound() -> void:
	play("chest_pound")
	for n in 3:
		after(0.35 * n, func():
			src(0)
			var at := feet()
			var d := POUND_DAMAGE * dmg() * pw(0)
			for i in near(at, POUND_RADIUS):
				enemies.damage(i, d)
				enemies.knock(i, enemies.pos[i] - at, 1.5, 0.2)
				if n == 2:
					enemies.stun(i, POUND_STUN)
			ring(at, POUND_RADIUS, Color(1.0, 0.75, 0.4, 0.7), 0.4)
			fx.burst(at + Vector3(0, 0.3, 0), 2.5, Color(0.55, 0.45, 0.35, 0.6), 0.3)
			player.add_shake(0.3))


# ------------------------------------------------------------------ Log Toss

func _log_toss() -> void:
	play("log_toss")
	if is_instance_valid(_log):
		_log.queue_free()
	_log = Node3D.new()
	var trunk := MeshInstance3D.new()
	trunk.mesh = HeroBody._cyl(0.45, 0.45, 2.6, 12)
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.36, 0.25, 0.15)
	trunk.material_override = bark
	trunk.rotation.z = PI / 2
	_log.add_child(trunk)
	_log_dir = aim_dir()
	_log.rotation.y = atan2(-_log_dir.x, -_log_dir.z)
	spawn(_log, feet() + _log_dir * 1.5 + Vector3(0, 0.45, 0))
	_log_left = LOG_RANGE
	_log_hit.clear()


func _tick_log(dt: float) -> void:
	if _log_left <= 0.0 or not is_instance_valid(_log):
		return
	var step := LOG_SPEED * dt
	_log_left -= step
	var p := _log.global_position + _log_dir * step
	p.y = ground(p).y + 0.45
	_log.global_position = p
	(_log.get_child(0) as Node3D).rotate_object_local(Vector3.UP, -step / 0.45)
	var d := LOG_DAMAGE * dmg() * pw(1)
	for i in near(p, LOG_HIT):
		if not _log_hit.has(enemies.uid[i]):
			_log_hit[enemies.uid[i]] = true
			enemies.damage(i, d)
			var side := _log_dir.cross(Vector3.UP) * (1.0 if (enemies.pos[i] - p).dot(_log_dir.cross(Vector3.UP)) > 0.0 else -1.0)
			enemies.knock(i, side + _log_dir * 0.5, 3.0, 0.3)
	if _log_left <= 0.0:
		fx.burst(p, 2.0, Color(0.5, 0.38, 0.25), 0.35)
		_log.queue_free()


# ------------------------------------------------------------------ Rampage

func _rampage() -> void:
	play("rampage")
	if _rage_t <= 0.0:
		_rage_mult = 1.0 + (RAMPAGE_DAMAGE - 1.0) * pw(2)
		stats.apply("damage", "mult", _rage_mult)
		stats.apply("move_speed", "mult", RAMPAGE_SPEED)
		player.size_mult = 1.25
	_rage_t = RAMPAGE_TIME
	_walked = 0.0
	_last = feet()
	fx.burst(chest(), 4.0, Color(1.0, 0.55, 0.2), 0.4)
	player.add_shake(0.6)


func _tick_rampage(dt: float) -> void:
	if _rage_t <= 0.0:
		return
	_rage_t -= dt
	var p := feet()
	if _last != Vector3.INF:
		_walked += Vector2(p.x - _last.x, p.z - _last.z).length()
	_last = p
	if _walked >= QUAKE_EVERY:   # every few strides the ground quakes
		_walked = 0.0
		for i in near(p, QUAKE_RADIUS):
			enemies.damage(i, QUAKE_DAMAGE * dmg())
			enemies.knock(i, enemies.pos[i] - p, 1.5, 0.2)
		ring(p, QUAKE_RADIUS, Color(1.0, 0.65, 0.3, 0.6), 0.3)
		player.add_shake(0.2)
	_lash_t -= dt
	if _lash_t <= 0.0:   # the broken chains lash out at someone
		_lash_t = 0.5
		var t := enemies.nearest_k(chest(), LASH_RANGE, 2)
		for i in t:
			enemies.damage(i, LASH_DAMAGE * dmg())
			mote(chest(), (enemies.center_of(i) - chest()) * 5.0, 0.2, Color(0.8, 0.78, 0.72), 0.15, false, 0.0)
	if _rage_t <= 0.0:
		stats.apply("damage", "mult", 1.0 / _rage_mult)
		stats.apply("move_speed", "mult", 1.0 / RAMPAGE_SPEED)
		player.size_mult = 1.0
