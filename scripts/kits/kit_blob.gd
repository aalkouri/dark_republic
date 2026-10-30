class_name KitBlob
extends KitPart
## The Blob (built in code: BlobBody)
##   1  Engulf            30 s  swallows up to 20 enemies within 6 m (not the boss): they shrink
##                              and swirl about inside the jelly for 6 s, digested for 8% of max HP
##                              per second; you heal 1% of max HP per enemy swallowed. Survivors
##                              are spat back out.
##   2  Split             45 s  2 mini-blobs split off for 10 s and chase enemies, each with its
##                              own Acid Body at 60% damage (they copy your burn pulses)
##   3  The Great Puddle 120 s  you spread out into a 20 m puddle for 6 s: you can't move but
##                              you're invulnerable; enemies in it are slowed 90% and take 6% of
##                              max HP per second; then you pull back together and the survivors
##                              are flung out 6 yd

const ENGULF_RADIUS := 6.0
const ENGULF_MAX := 20
const ENGULF_TIME := 6.0
const ENGULF_FRAC := 0.08            # of max HP per second
const ENGULF_HEAL := 0.01            # of your max HP per enemy swallowed
const ENGULF_SIZE := 0.35            # swallowed enemies shrink to fit inside
const ENGULF_SPIT := 4.0
const SPLIT_COUNT := 2
const SPLIT_TIME := 10.0
const SPLIT_DAMAGE := 0.6
const SPLIT_SIZE := 0.5
const SPLIT_SPEED := 7.5
const SPLIT_LEASH := 16.0            # they don't wander further than this from you
const SPLIT_SEEK := 22.0
const SPLIT_COLORS := {"body": Color(0.62, 0.95, 0.28), "rim": Color(0.9, 1.0, 0.65)}
const PUDDLE_RADIUS := 20.0
const PUDDLE_TIME := 6.0
const PUDDLE_SLOW := 0.1             # 90% slow
const PUDDLE_FRAC := 0.06            # of max HP per second
const PUDDLE_FLING := 6.0 * YARD

var _engulfed: Array = []            # [uid, size before]
var _engulf_t := 0.0
var _engulf_tick := 0.0
var _minis: Array = []               # RosterHero (half-size blobs)
var _mini_discs: Array = []          # GroundDisc under each
var _split_t := 0.0
var _puddle_t := 0.0
var _puddle_tick := 0.0
var _puddle_at := Vector3.ZERO
var _pool: AcidPuddle
var _pool_rim: GroundDisc
var swallowed := 0                   # tests
var spat := 0
var digested := 0.0
var puddle_hits := 0
var flung := 0


func _exit_tree() -> void:
	for m in _minis:
		if is_instance_valid(m):
			m.queue_free()


func cast(i: int) -> void:
	match i:
		0: _engulf()
		1: _split()
		2: _great_puddle()


func active(name: String) -> bool:
	match name:
		"engulf": return _engulf_t > 0.0
		"split": return _split_t > 0.0
		"puddle": return _puddle_t > 0.0
	return false


func tick(dt: float) -> void:
	_tick_engulf(dt)
	_tick_split(dt)
	_tick_puddle(dt)


func clone_list() -> Array:
	var out := []
	if _split_t > 0.0:
		for m in _minis:
			if is_instance_valid(m):
				out.append([m, m.global_position])
	return out


func clone_damage() -> float:
	return SPLIT_DAMAGE * pw(1)


func _body() -> BlobBody:
	var m = player.model
	return m.blob if m is RosterHero else null


## Live rows of the given uids, in one pass over the crowd: uid -> row.
func _rows(uids: Dictionary) -> Dictionary:
	var out := {}
	for i in enemies.count:
		if not enemies.dead[i] and uids.has(enemies.uid[i]):
			out[enemies.uid[i]] = i
	return out


# ------------------------------------------------------------------ Engulf

func _engulf() -> void:
	play("engulf")
	_spit_out()
	var at := feet()
	var cand := Array(near(at, ENGULF_RADIUS, true))
	cand.sort_custom(func(a: int, b: int): return at.distance_squared_to(enemies.pos[a]) < at.distance_squared_to(enemies.pos[b]))
	for i in cand.slice(0, ENGULF_MAX):
		_engulfed.append([enemies.uid[i], enemies.sz[i]])
		enemies.sz[i] *= ENGULF_SIZE
		enemies.stun(i, 0.4)
		swallowed += 1
	k.heal_pct(ENGULF_HEAL * _engulfed.size())
	_engulf_t = ENGULF_TIME
	_engulf_tick = 0.0
	ring(at, ENGULF_RADIUS, Color(0.55, 1.0, 0.3, 0.7), 0.35)
	for n in 14:   # slime lashes out and back in
		var a := TAU * n / 14.0
		var d := Vector3(cos(a), 0, sin(a))
		mote(at + d * ENGULF_RADIUS * 0.9 + Vector3(0, 0.6, 0), -d * 12.0, 0.45, Color(0.6, 1.0, 0.3), 0.3, true)
	if _body():
		_body().fullness = _engulfed.size()


func _tick_engulf(dt: float) -> void:
	if _engulf_t <= 0.0:
		return
	_engulf_t -= dt
	var want := {}
	for e in _engulfed:
		want[e[0]] = true
	var rows := _rows(want)
	var at := feet()
	var body := _body()
	var inside := 0.42 * (body.scale.x if body else 1.0)
	var n := maxi(1, rows.size())
	var k2 := 0
	var t := ENGULF_TIME - _engulf_t
	# They swirl about inside the jelly, waving
	for e in _engulfed:
		if not rows.has(e[0]):
			continue
		var i: int = rows[e[0]]
		var a := t * 1.4 + TAU * k2 / n
		var r := inside * (0.3 + 0.7 * fmod(k2 * 0.618, 1.0))
		var goal := at + Vector3(cos(a) * r, 0, sin(a) * r)
		enemies.pos[i] = enemies.pos[i].lerp(goal, minf(1.0, dt * (14.0 if t > 0.3 else 8.0)))
		enemies.vel[i] = Vector3.ZERO
		enemies.stun(i, 0.3)
		k2 += 1
	if body:
		body.fullness = rows.size()
	_engulf_tick -= dt
	if _engulf_tick <= 0.0:
		_engulf_tick = 0.25
		for u in rows:
			var i: int = rows[u]
			var d: float = enemies.hp_max[i] * ENGULF_FRAC * pw(0) * 0.25 * enemies.pct_scale(i)
			enemies.dot_damage(i, d)
			digested += d
			if enemies.dead[i] and k.weapons != null:   # eating makes it grow too
				k.weapons.acid_growth = minf(WeaponSystem.ACID_GROW_MAX, k.weapons.acid_growth + WeaponSystem.ACID_GROW)
		if randf() < 0.6:
			mote(at + Vector3(randf_range(-0.4, 0.4), 0.3, randf_range(-0.4, 0.4)), Vector3(0, 1.2, 0), 0.8, Color(0.7, 1.0, 0.4), 0.12)
	if _engulf_t <= 0.0:
		_spit_out()


## Whatever's left is spat back out, full size again.
func _spit_out() -> void:
	if _engulfed.is_empty():
		return
	var want := {}
	for e in _engulfed:
		want[e[0]] = true
	var rows := _rows(want)
	var at := feet()
	for e in _engulfed:
		if not rows.has(e[0]):
			continue
		var i: int = rows[e[0]]
		enemies.sz[i] = e[1]
		var out := enemies.pos[i] - at
		out.y = 0.0
		enemies.knock(i, out if out.length() > 0.05 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), ENGULF_SPIT, 0.3)
		enemies.stun(i, 0.6)
		spat += 1
	_engulfed.clear()
	_engulf_t = 0.0
	if _body():
		_body().fullness = 0
	if fx and not rows.is_empty():
		fx.burst(at + Vector3(0, 0.7, 0), 1.5, Color(0.6, 1.0, 0.3), 0.3)


# ------------------------------------------------------------------ Split

func _split() -> void:
	play("split")
	_clear_minis()
	var right := Vector3(cos(player.cam_yaw), 0.0, -sin(player.cam_yaw))
	for n in SPLIT_COUNT:
		var m := RosterHero.create("blob")
		var opts := SPLIT_COLORS.duplicate()
		opts["size"] = SPLIT_SIZE
		opts["seed"] = float(n) * 3.7 + 1.0
		m.blob_opts = opts
		var at := ground(feet() + right * (1.6 if n == 0 else -1.6))
		spawn(m, at)
		_minis.append(m)
		var disc := GroundDisc.create(1.0, Color(0.45, 1.0, 0.2, 0.18), true)
		spawn(disc, at)
		_mini_discs.append(disc)
		if fx:
			fx.burst(at + Vector3(0, 0.5, 0), 1.0, Color(0.6, 1.0, 0.3), 0.3)
	_split_t = SPLIT_TIME


func _clear_minis() -> void:
	for m in _minis:
		if is_instance_valid(m):
			if fx:
				fx.burst(m.global_position + Vector3(0, 0.4, 0), 0.9, Color(0.6, 1.0, 0.3), 0.3)
			m.queue_free()
	for d in _mini_discs:
		if is_instance_valid(d):
			d.queue_free()
	_minis.clear()
	_mini_discs.clear()


func _tick_split(dt: float) -> void:
	if _split_t <= 0.0:
		return
	_split_t -= dt
	var home := feet()
	var r := k.weapons.acid_radius("orb", false) if k.weapons != null else WeaponSystem.ACID_RADIUS
	for n in _minis.size():
		var m: RosterHero = _minis[n]
		if not is_instance_valid(m):
			continue
		var p := m.global_position
		# Chase the nearest enemy (not too far from you); with none about, bob along beside you
		var goal := home + Vector3(cos(n * PI + 0.6), 0, sin(n * PI + 0.6)) * 2.0
		var prey := enemies.nearest_k(p + Vector3(0, 0.8, 0), SPLIT_SEEK, 1)
		if not prey.is_empty() and enemies.pos[prey[0]].distance_to(home) < SPLIT_LEASH:
			goal = enemies.pos[prey[0]]
		var to := goal - p
		to.y = 0.0
		var d := to.length()
		var spd := 0.0
		if d > 0.5:
			var step := minf(SPLIT_SPEED * dt, d - 0.4)
			p += to / d * step
			spd = step / maxf(dt, 0.0001)
			m.rotation.y = lerp_angle(m.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-10.0 * dt))
		p.y = ground(p).y
		m.global_position = p
		m.set_motion(spd, false)
		var disc: GroundDisc = _mini_discs[n]
		disc.global_position = p + Vector3(0, 0.06, 0)
		disc.scale = Vector3(r, 1.0, r)
	if _split_t <= 0.0:
		_clear_minis()


# ------------------------------------------------------------------ The Great Puddle

func _great_puddle() -> void:
	play("great_puddle")
	_puddle_t = PUDDLE_TIME
	_puddle_tick = 0.0
	_puddle_at = ground(feet())
	player.untouchable = true   # glows in shifting colours while invincible
	begin_scripted()
	if _body():
		_body().puddle_target = 1.0
	if is_instance_valid(_pool):
		_pool.queue_free()
	_pool = AcidPuddle.create(PUDDLE_RADIUS, _puddle_at, self)
	if _pool.shards:
		_pool.shards.emitting = false
		_pool.shards.visible = false
	_pool_rim = GroundDisc.create(PUDDLE_RADIUS, Color(0.7, 1.0, 0.35, 0.5), true)
	_pool_rim.set_ring(0.93)
	spawn(_pool_rim, _puddle_at)
	_pool_rim.scale = Vector3(PUDDLE_RADIUS * 0.3, 1.0, PUDDLE_RADIUS * 0.3)
	_pool_rim.create_tween().tween_property(_pool_rim, "scale", Vector3(PUDDLE_RADIUS, 1.0, PUDDLE_RADIUS), 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	player.add_shake(0.4)
	flash_light(_puddle_at + Vector3(0, 2.0, 0), Color(0.5, 1.0, 0.3), 3.0, PUDDLE_RADIUS * 1.2, PUDDLE_TIME)
	if fx:
		fx.burst(_puddle_at + Vector3(0, 0.4, 0), 3.5, Color(0.55, 1.0, 0.3), 0.4)


func _tick_puddle(dt: float) -> void:
	if _puddle_t <= 0.0:
		return
	_puddle_t -= dt
	player.velocity = Vector3.ZERO
	_puddle_tick -= dt
	if _puddle_tick <= 0.0:
		_puddle_tick = 0.25
		for i in near(_puddle_at, PUDDLE_RADIUS):
			enemies.slow(i, PUDDLE_SLOW, 0.4)
			enemies.dot_damage(i, enemies.hp_max[i] * PUDDLE_FRAC * pw(2) * 0.25 * enemies.pct_scale(i))
			puddle_hits += 1
	if randf() < dt * 20.0:   # it bubbles all over
		var a := randf() * TAU
		var d := sqrt(randf()) * PUDDLE_RADIUS * 0.9
		var p := _puddle_at + Vector3(cos(a) * d, 0, sin(a) * d)
		mote(Vector3(p.x, SwampWater.height_at(p.x, p.z) + 0.2 if SwampWater.current != null else p.y + 0.2, p.z), Vector3(0, 1.5, 0), 0.6, Color(0.7, 1.0, 0.4), 0.18)
	if _puddle_t <= 0.0:
		_end_puddle()


func _end_puddle() -> void:
	player.untouchable = false
	end_scripted(player.global_position)
	if _body():
		_body().puddle_target = 0.0
	# Pulling back together flings everyone still in it out
	for i in near(_puddle_at, PUDDLE_RADIUS):
		var out := enemies.pos[i] - _puddle_at
		out.y = 0.0
		enemies.knock(i, out if out.length() > 0.05 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), PUDDLE_FLING, 0.35)
		flung += 1
	ring(_puddle_at, PUDDLE_RADIUS * 0.6, Color(0.6, 1.0, 0.35, 0.8), 0.35)
	player.add_shake(0.3)
	var pool := _pool
	_pool = null
	if is_instance_valid(pool):
		var tw := pool.create_tween()
		tw.tween_property(pool, "alpha", 0.0, 0.5)
		tw.tween_callback(pool.queue_free)
	if is_instance_valid(_pool_rim):
		var rim := _pool_rim
		var tw2 := rim.create_tween()
		tw2.tween_property(rim, "scale", Vector3(0.5, 1.0, 0.5), 0.35).set_ease(Tween.EASE_IN)
		tw2.tween_callback(rim.queue_free)
	_pool_rim = null
