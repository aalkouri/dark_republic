class_name SingeBoss
extends MapBoss
## Singe, the Living Cinder, the Ashen Caldera's boss: the little coal imp from the roster swollen
## into a 6 m imp king (SingeModel), gleeful and cackling, who BURSTS UP OUT OF THE GREAT LAVA
## POOL at 8:00 and enrages after 2 minutes. Killing him wins the run (and records his defeat as
## "singe", which puts him on the roster).
##
## Attacks (all marked on the ground first, see MapBoss):
##   CLAW SWIPE     close: a wedge in front of him fills, then he rakes his claws through it.
##   FIRE BREATH    a cone from his grin toward you; when it fills he spews fire down it, and the
##                  ground in it burns for a few seconds after.
##   LAVA DIVE      he cannonballs into the nearest lava (or straight through the crust) and pops
##                  out under a marked circle near you (also when you run too far from him).
##   METEOR CALL    he juggles lava bombs over his head, then flings them onto five (enraged
##                  seven) marked circles round you.
##   SUMMON         Magma Imps, his minions, claw out of marked cracks round you; every other time
##                  an Obsidian Golem with them.
##   SCORCH RUN     he scampers round you in a loop, every footfall marked first, leaving a trail
##                  of scorch marks: step on one and you burn for SCORCH_BURN s.
##   CALDERA ERUPTION  his ultimate, at 75%, 50% and 10% health: he throws up his arms cackling, the
##                  volcano erupts, the ground's cracks race open and pulse for 10 s - then the
##                  whole floor floods with lava for FLOOD_TIME s. Only the raised basalt islands
##                  that burst up round you (a glowing arrow over each) are safe.
## Death: he sputters, fizzles and gutters out into a small heap of cooling coals, with one last
## puff of smoke; the lava dims.

const TURN_RATE := 3.0
const GAP := Vector2(0.9, 1.6)
const RISE_TIME := 3.0
const SWIPE_RANGE := 8.5
const SWIPE_WARN := 1.15
const SWIPE_RADIUS := 10.0
const SWIPE_HALF := deg_to_rad(60.0)
const SWIPE_DAMAGE := 34.0
const BREATH_WARN := 1.35
const BREATH_LEN := 18.0
const BREATH_HALF := deg_to_rad(24.0)
const BREATH_DAMAGE := 30.0
const BREATH_COOLDOWN := 8.0
const BURN_DPS := 10.0
const BURN_LIFE := 4.0
const LEAP_TIME := 0.9
const LAVA_REACH := 30.0
const DIVE_WARN := 1.4
const DIVE_RADIUS := 6.0
const DIVE_DAMAGE := 34.0
const DIVE_COOLDOWN := 16.0
const TRAVEL_DIST := 42.0
const TRAVEL_AFTER := 2.0
const METEOR_WARN := 1.8
const METEOR_RADIUS := 3.0
const METEOR_DAMAGE := 26.0
const METEOR_COUNT := 5
const METEOR_COOLDOWN := 12.0
const SUMMON_WARN := 1.5
const SUMMON_COOLDOWN := 19.0
const SUMMON_FIRST := 14.0
const SCAMPER_COOLDOWN := 15.0
const SCAMPER_FIRST := 8.0
const SCAMPER_LEAD := 1.1          # the first footfall's marker fills this long (>= MIN_WARN)
const SCAMPER_SPEED := 12.0
const SCAMPER_MARKS := 12
const SCAMPER_RING := 8.0
const SCORCH_R := 1.6
const SCORCH_LIFE := 6.0
const SCORCH_BURN := 3.0           # seconds you burn after stepping on a scorch mark
const ERUPTION_AT := [0.75, 0.5, 0.1]
const ERUPTION_WARN := 10.0
const FLOOD_TIME := 8.5
const FLOOD_HIT := 0.35            # share of max HP (through shields) if caught when it floods...
const FLOOD_TICK := 0.06           # ...and every second you stay in it
const ISLANDS := 4
const ISLAND_R := 3.2
const ISLAND_H := 1.4
const FIRE := Color(1.0, 0.42, 0.08)
const SCORCH := Color(0.3, 0.09, 0.02)

var model: SingeModel
var _yaw := 0.0
var _aim := Vector3.FORWARD
var _gap := 2.0
var _breath_cd := 4.0
var _dive_cd := 10.0
var _meteor_cd := 7.0
var _summon_cd := SUMMON_FIRST
var _scamper_cd := SCAMPER_FIRST
var _summons := 0
var _far_t := 0.0
var _t := 0.0
var _windup := 0.0
var _total := 0.0
var _landed := false
var _eruptions_done := 0
var _flooding := false
var _flood_over := false
var _flood_t := 0.0
var _flood_tick := 0.0
var islands: Array[Dictionary] = []   # {body, at, top}
var _arrows: Node3D
var _fires: Array[Dictionary] = []    # {node, t, life}
var _scorches: Array[Dictionary] = [] # {at, t, touched}
var _path: Array[Dictionary] = []     # the scorch run: {at, time}
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO
var _breath_fx: CPUParticles3D
var _rise_at := Vector3.ZERO
var breath_hits := 0                  # tests
var flood_hits := 0
var scorch_hits := 0
var scorch_marks := 0


## Where he rises: the middle of the great lava pool.
static func rise_point() -> Vector3:
	for p in CalderaBuilder.pools:
		if p["kind"] == "great":
			var c: Vector2 = p["c"]
			return Vector3(c.x, SwampWater.height_at(c.x, c.y), c.y)
	return Vector3.ZERO


func stats() -> Dictionary:
	return {"name": "Singe", "hp": 6400.0, "speed": 4.2, "radius": 1.9, "height": 6.0, "damage": 44.0, "xp": 400.0}


func display_name() -> String:
	return "SINGE"


func bar_color() -> Color:
	return Color(1.0, 0.5, 0.1)


func sounds() -> Dictionary:
	return {
		"cackle": "res://audio/caldera/singe_cackle.wav",
		"giggle": "res://audio/caldera/singe_giggle.wav",
		"breath": "res://audio/caldera/singe_breath.wav",
		"splash": "res://audio/caldera/singe_splash.wav",
		"emerge": "res://audio/caldera/singe_emerge.wav",
		"swipe": "res://audio/caldera/singe_swipe.wav",
		"scamper": "res://audio/caldera/singe_scamper.wav",
		"fizzle": "res://audio/caldera/singe_fizzle.wav",
		"puff": "res://audio/caldera/singe_puff.wav",
		"bomb": "res://audio/caldera/bomb_impact.wav",
		"summon": "res://audio/caldera/crack_open.wav",
		"eruption": "res://audio/caldera/eruption.wav",
		"flood": "res://audio/caldera/flood.wav",
	}


func _build_model() -> void:
	model = SingeModel.new()
	add_child(model)
	var i := row()
	if i >= 0:
		var to := player.global_position - em.pos[i]
		_yaw = atan2(-to.x, -to.z)
		_rise_at = em.pos[i]
	rotation.y = _yaw
	_breath_fx = _fire_stream()
	_breath_fx.top_level = true   # aimed down the cone each frame
	add_child(_breath_fx)
	_sync(0.0)
	_start_rise()


func _physics_process(dt: float) -> void:
	super(dt)
	_tick_fx(dt)
	if state == "dead" or state == "dying":
		return
	if main.state != "playing":
		return
	if state == "walk" and _eruptions_done < ERUPTION_AT.size() and hp_fraction() <= ERUPTION_AT[_eruptions_done]:
		while _eruptions_done < ERUPTION_AT.size() and hp_fraction() <= ERUPTION_AT[_eruptions_done]:
			_eruptions_done += 1
		_start("eruption")
	_sync(dt)


func _on_hurt() -> void:
	model.flash()


# ------------------------------------------------------------------ bursting out of the pool

func _start_rise() -> void:
	state = "attack"
	attack = "rise"
	_t = 0.0
	em.troll_busy = true
	em.boss_contact = false
	model.pose = "rise"
	model.rise = 0.0
	play_sfx("emerge")
	shake(0.6)
	main.hud.flash_message("SINGE BURSTS FROM THE LAVA!", 3.5)
	if CalderaAmbience.current != null:
		CalderaAmbience.current.rumble(0.5)


func _tick_rise(dt: float) -> void:
	var f := clampf((_t - 0.4) / (RISE_TIME - 1.2), 0.0, 1.0)
	model.rise = 1.0 - pow(1.0 - f, 3.0)   # pops up like a jack-in-the-box
	if fx and fmod(_t, 0.2) < dt and _t < RISE_TIME - 0.8:   # lava thrown up as he breaks the surface
		fx.burst(_rise_at + Vector3(randf_range(-3, 3), 0.8, randf_range(-3, 3)), 2.5, FIRE, 0.5)
	if f >= 1.0 and not _landed:
		_landed = true
		play_sfx("cackle")
	if _t >= RISE_TIME:
		model.rise = 1.0
		model.pose = "walk"
		em.boss_contact = true
		_done(0.5)


# ------------------------------------------------------------------ deciding

func _think(dt: float, i: int) -> void:
	em.troll_busy = false
	var k := speed_k()
	_gap -= dt * k
	_breath_cd -= dt * k
	_dive_cd -= dt * k
	_meteor_cd -= dt * k
	_summon_cd -= dt * k
	_scamper_cd -= dt * k
	if em.is_held(i):
		model.walk_speed = 0.0
		return
	model.pose = "walk"
	model.walk_speed = em.vel[i].length()
	var d := flat_dist(player.global_position, em.pos[i])
	_far_t = _far_t + dt if d > TRAVEL_DIST else 0.0
	if _gap > 0.0:
		return
	if _far_t >= TRAVEL_AFTER:
		_start("dive")
	elif _summon_cd <= 0.0:
		_start("summon")
	elif d < SWIPE_RANGE:
		_start("swipe")
	elif _scamper_cd <= 0.0 and d < 24.0:
		_start("scamper")
	elif _breath_cd <= 0.0 and d < BREATH_LEN:
		_start("breath")
	elif _meteor_cd <= 0.0 and d < 36.0:
		_start("meteor")
	elif _dive_cd <= 0.0:
		_start("dive")


func _start(kind: String) -> void:
	state = "attack"
	attack = kind
	counts[kind] = int(counts.get(kind, 0)) + 1
	_t = 0.0
	_landed = false
	em.troll_busy = true
	model.walk_speed = 0.0
	model.act = 0.0
	var i := row()
	var to := player.global_position - em.pos[i]
	to.y = 0.0
	_aim = to.normalized() if to.length() > 0.1 else Vector3(-sin(_yaw), 0, -cos(_yaw))
	match kind:
		"swipe":
			_windup = warn_time(SWIPE_WARN)
			_total = _windup + 0.6
			model.pose = "swipe"
			play_sfx("giggle", 1.1)
			var c := em.pos[i]
			var aim := _aim
			warn_wedge(c, aim, SWIPE_RADIUS, SWIPE_HALF, SWIPE_WARN, func(): _land_swipe(c, aim))
		"breath":
			_breath_cd = BREATH_COOLDOWN
			_windup = warn_time(BREATH_WARN)
			_total = _windup + 1.2
			model.pose = "breath"
			var from := em.pos[i]
			var dir := _aim
			warn_wedge(from, dir, BREATH_LEN, BREATH_HALF, BREATH_WARN, func(): _fire_breath(from, dir))
		"meteor":
			_meteor_cd = METEOR_COOLDOWN
			_windup = warn_time(METEOR_WARN)
			_total = _windup + 0.5
			model.pose = "juggle"
			play_sfx("giggle")
			var n := METEOR_COUNT + (2 if is_enraged else 0)
			var pp := player_ahead(0.8)
			var hands := em.pos[i] + Vector3(0, 7.5, 0)
			for k in n:
				var at := pp if k == 0 else ground(pp + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(4.0, 11.0))
				var secs := METEOR_WARN + k * 0.15
				lob(hands, at, warn_time(secs), FIRE, 0.8, 16.0)
				warn_circle(at, METEOR_RADIUS, secs, func(): _land_meteor(at))
		"summon":
			_summon_cd = SUMMON_COOLDOWN
			_summons += 1
			_windup = warn_time(SUMMON_WARN)
			_total = _windup + 0.6
			model.pose = "summon"
			play_sfx("cackle", 0.95)
			play_sfx("summon")
			var pp := player.global_position
			var golem := _summons % 2 == 0
			var n := 5 + (2 if is_enraged else 0)
			var a0 := randf() * TAU
			for k in n:
				var a := a0 + TAU * k / n
				var at := ground(pp + Vector3(cos(a), 0, sin(a)) * randf_range(6.0, 9.0))
				var t := EnemyManager.OBSIDIAN_GOLEM if golem and k == 0 else EnemyManager.MAGMA_IMP
				warn_circle(at, 3.0 if t == EnemyManager.OBSIDIAN_GOLEM else 2.2, SUMMON_WARN, func(): _raise(t, at), Color(1.0, 0.5, 0.15))
		"scamper":
			_scamper_cd = SCAMPER_COOLDOWN
			model.pose = "cackle"
			play_sfx("cackle", 1.15)
			_plan_scamper(em.pos[i])
		"dive":   # cannonballs into the lava, pops out of a marked circle near you
			_far_t = 0.0
			_dive_cd = DIVE_COOLDOWN
			_leap_from = em.pos[i]
			_leap_to = _nearest_lava(em.pos[i])
			_windup = LEAP_TIME + 0.5
			_total = 99.0
			em.boss_contact = false
			model.pose = "dive"
			play_sfx("giggle", 1.2)
		"eruption":
			_start_eruption()


func _done(extra_gap: float) -> void:
	state = "walk"
	attack = ""
	em.troll_busy = false
	em.boss_contact = true
	model.pose = "walk"
	model.act = 0.0
	model.sink = 0.0
	model.lift = 0.0
	model.curl = 0.0
	_gap = randf_range(GAP.x, GAP.y) + extra_gap


func _tick_attack(dt: float) -> void:
	_t += dt
	match attack:
		"rise":
			_tick_rise(dt)
			return
		"dive":
			_tick_dive(dt)
			return
		"eruption":
			_tick_eruption(dt)
			return
		"scamper":
			_tick_scamper(dt)
			return
	model.act = clampf(_t / maxf(_windup, 0.01) * 0.7, 0.0, 0.7) if _t < _windup else minf(1.0, 0.7 + (_t - _windup) * 1.5)
	if _t >= _total:
		_done(0.0)


# ------------------------------------------------------------------ attacks landing

func _land_swipe(c: Vector3, aim: Vector3) -> void:
	play_sfx("swipe")
	shake(0.5)
	var to := player.global_position - c
	to.y = 0.0
	if to.length() < SWIPE_RADIUS and to.length() > 0.01 and absf(to.normalized().angle_to(aim)) <= SWIPE_HALF + 0.05 and not airborne():
		var side := Vector3(-aim.z, 0, aim.x)
		hit_player(SWIPE_DAMAGE, side * signf(side.dot(to)) + to.normalized() * 0.5)
		player.ignite()
	if fx:   # three raking streaks of sparks
		for k in 7:
			var a := -SWIPE_HALF + 2.0 * SWIPE_HALF * k / 6.0
			fx.burst(c + aim.rotated(Vector3.UP, a) * SWIPE_RADIUS * 0.7 + Vector3(0, 0.8, 0), 1.6, FIRE, 0.35)


func _in_cone(from: Vector3, dir: Vector3, p: Vector3) -> bool:
	var rel := p - from
	rel.y = 0.0
	if rel.length() > BREATH_LEN or rel.length() < 0.01:
		return rel.length() < 0.01
	return absf(rel.normalized().angle_to(dir)) <= BREATH_HALF + 0.04


func _fire_breath(from: Vector3, dir: Vector3) -> void:
	play_sfx("breath")
	shake(0.3)
	_breath_fx.restart()
	_breath_fx.emitting = true
	if _in_cone(from, dir, player.global_position) and not airborne():
		if hit_player(BREATH_DAMAGE, dir):
			breath_hits += 1
		player.ignite()
	# the ground in the cone burns for a few seconds
	for k in 4:
		var along := 4.5 + k * (BREATH_LEN - 5.5) / 3.0
		var spots := 1 if k < 2 else 2
		for s in spots:
			var off := 0.0 if spots == 1 else (s - 0.5) * along * tan(BREATH_HALF) * 1.1
			var at := ground(from + dir * along + Vector3(-dir.z, 0, dir.x) * off)
			_burning_ground(at, 1.6 + along * 0.1, BURN_LIFE)


func _burning_ground(at: Vector3, r: float, life: float) -> void:
	add_hazard(at, r, life, FIRE, BURN_DPS * (1.25 if is_enraged else 1.0))
	_flames(at, r, life, 30)


func _flames(at: Vector3, r: float, life: float, amount: int) -> void:
	var fl := Abilities._flame_particles(1.0, 0.8, amount)
	fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fl.emission_sphere_radius = r * 0.7
	add_child(fl)
	fl.top_level = true
	fl.global_position = at + Vector3(0, 0.3, 0)
	_fires.append({"node": fl, "t": 0.0, "life": life})


func _land_meteor(at: Vector3) -> void:
	play_sfx("bomb", randf_range(0.85, 1.1))
	shake(0.35)
	if player_in_circle(at, METEOR_RADIUS) and not airborne():
		hit_player(METEOR_DAMAGE, player.global_position - at)
		player.ignite()
	if fx:
		fx.burst(at + Vector3(0, 0.8, 0), METEOR_RADIUS, FIRE, 0.5)
		fx.burst(at + Vector3(0, 0.4, 0), METEOR_RADIUS * 0.8, Color(0.18, 0.14, 0.12), 0.6)
	_burning_ground(at, 2.2, 2.5)


func _raise(t: int, at: Vector3) -> void:
	if fx:
		fx.burst(at + Vector3(0, 0.6, 0), 2.2, FIRE, 0.5)
	var hpm: float = main.hp_mult()
	if em.caldera != null:
		em.caldera.raise(t, at, hpm * 0.7)
	else:
		main._spawn_enemy(t, at, hpm * 0.7)


# ------------------------------------------------------------------ the scorch run

## Lay out his loop round you: footfalls on a ring, each marked on the ground from the start and
## filling until the moment he gets there.
func _plan_scamper(from: Vector3) -> void:
	_path.clear()
	var pp := ground(player.global_position)
	var rel := from - pp
	rel.y = 0.0
	var a0 := atan2(rel.z, rel.x) if rel.length() > 0.5 else randf() * TAU
	var spin := 1.0 if randf() < 0.5 else -1.0
	var lead := warn_time(SCAMPER_LEAD)
	_path.append({"at": from, "time": lead})
	var dist := 0.0
	var prev := from
	for k in SCAMPER_MARKS:
		var a := a0 + spin * (0.35 + TAU * 0.85 * k / (SCAMPER_MARKS - 1))
		var r := SCAMPER_RING + sin(k * 1.7) * 1.2
		var at := ground(pp + Vector3(cos(a), 0, sin(a)) * r)
		dist += flat_dist(prev, at)
		prev = at
		var secs := SCAMPER_LEAD + dist / SCAMPER_SPEED
		var when := warn_time(secs)
		_path.append({"at": at, "time": when})
		warn_circle(at, SCORCH_R, secs, func(): _scorch(at), Color(1.0, 0.35, 0.05))
	_total = float(_path[_path.size() - 1]["time"]) + 0.5


func _tick_scamper(dt: float) -> void:
	var i := row()
	if i < 0 or _path.is_empty():
		_done(0.0)
		return
	var first: float = _path[0]["time"]
	if _t < first:   # crouched, cackling, then off
		model.pose = "cackle"
		if _t + dt >= first:
			play_sfx("scamper")
		return
	model.pose = "scamper"
	var at: Vector3 = _path[_path.size() - 1]["at"]
	for k in range(1, _path.size()):
		var t1: float = _path[k]["time"]
		if _t <= t1:
			var t0: float = _path[k - 1]["time"]
			var a: Vector3 = _path[k - 1]["at"]
			var b: Vector3 = _path[k]["at"]
			at = a.lerp(b, clampf((_t - t0) / maxf(t1 - t0, 0.01), 0.0, 1.0))
			break
	var step := at - em.pos[i]
	step.y = 0.0
	if step.length() > 0.01:
		_aim = step.normalized()
	em.pos[i] = ground(at)
	em.vel[i] = Vector3.ZERO
	global_position = em.pos[i]
	if _t >= _total:
		_path.clear()
		_done(0.3)


func _scorch(at: Vector3) -> void:
	scorch_marks += 1
	add_hazard(at, SCORCH_R, SCORCH_LIFE, SCORCH, 0.0)
	_flames(at, SCORCH_R * 0.8, SCORCH_LIFE, 10)
	_scorches.append({"at": at, "t": 0.0, "touched": false})
	if fx:
		fx.burst(at + Vector3(0, 0.3, 0), 1.2, FIRE, 0.3)


func _tick_scorches(dt: float) -> void:
	var pp := player.global_position
	for k in range(_scorches.size() - 1, -1, -1):
		var s: Dictionary = _scorches[k]
		s["t"] += dt
		if s["t"] >= SCORCH_LIFE:
			_scorches.remove_at(k)
			continue
		var on := flat_dist(pp, s["at"]) < SCORCH_R and not airborne()
		if on:
			player.ignite()
			player.burn_left = maxf(player.burn_left, SCORCH_BURN)
			if not s["touched"]:
				scorch_hits += 1
				counts["hits"] += 1
		s["touched"] = on


# ------------------------------------------------------------------ lava dive

## The nearest lava within LAVA_REACH (he leaps in there), or where he stands if there's none.
func _nearest_lava(from: Vector3) -> Vector3:
	var best := from
	var best_d := INF
	for ring in range(2, int(LAVA_REACH) + 1, 2):
		for k in 16:
			var a := TAU * k / 16.0
			var x := from.x + cos(a) * ring
			var z := from.z + sin(a) * ring
			if CalderaBuilder.lava_dist(x, z) < -0.5:
				var d := float(ring)
				if d < best_d:
					best_d = d
					best = ground(Vector3(x, 0, z))
		if best_d < INF:
			break
	return best


func _tick_dive(dt: float) -> void:
	var i := row()
	if i < 0:
		return
	if _t < LEAP_TIME:   # a cannonball leap into the lava
		var f := _t / LEAP_TIME
		model.curl = clampf(f * 3.0, 0.0, 1.0)
		var at := _leap_from.lerp(_leap_to, f)
		em.pos[i] = ground(at)
		em.vel[i] = Vector3.ZERO
		global_position = em.pos[i]
		model.lift = sin(f * PI) * maxf(4.0, _leap_from.distance_to(_leap_to) * 0.3)
		return
	if _t < _windup:   # SPLOOSH, and down
		if not _landed:
			_landed = true
			model.lift = 0.0
			play_sfx("splash")
			shake(0.5)
			if fx:
				fx.burst(global_position + Vector3(0, 1.0, 0), 4.0, FIRE, 0.6)
				for k in 6:
					var a := TAU * k / 6.0
					fx.burst(global_position + Vector3(cos(a) * 2.5, 0.6, sin(a) * 2.5), 1.6, FIRE, 0.45)
		model.sink = 9.0 * clampf((_t - LEAP_TIME) / 0.4, 0.0, 1.0)
		return
	if not has_meta("dive_marked"):
		set_meta("dive_marked", true)
		model.sink = 9.0
		model.curl = 0.0
		var at := player_ahead(0.6)
		em.pos[i] = at
		em.vel[i] = Vector3.ZERO
		global_position = at
		warn_circle(at, DIVE_RADIUS, DIVE_WARN, func(): _burst_out(at), FIRE)
		_total = _t + warn_time(DIVE_WARN) + 1.0
	if _t >= _total - 1.0:
		model.sink = lerpf(model.sink, 0.0, clampf(dt * 9.0, 0.0, 1.0))
	if _t >= _total:
		remove_meta("dive_marked")
		model.sink = 0.0
		_done(0.4)


func _burst_out(at: Vector3) -> void:
	play_sfx("emerge", 1.15)
	play_sfx("cackle", 1.05)
	shake(0.7)
	model.sink = 4.0
	model.pose = "summon"
	if player_in_circle(at, DIVE_RADIUS) and not airborne():
		hit_player(DIVE_DAMAGE, player.global_position - at)
		player.ignite()
	if fx:
		fx.burst(at + Vector3(0, 1.0, 0), DIVE_RADIUS, FIRE, 0.6)
		for k in 8:
			var a := TAU * k / 8.0
			fx.burst(at + Vector3(cos(a), 0.4, sin(a)) * DIVE_RADIUS * 0.8, 1.8, Color(0.2, 0.15, 0.12), 0.5)
	_burning_ground(at, 3.5, 3.0)


# ------------------------------------------------------------------ the Caldera Eruption

func _start_eruption() -> void:
	_windup = ERUPTION_WARN
	_total = ERUPTION_WARN + FLOOD_TIME + 1.0
	_flooding = false
	_flood_over = false
	_flood_t = 0.0
	model.pose = "raise"
	play_sfx("cackle", 0.85)
	play_sfx("eruption")
	shake(0.6)
	main.hud.flash_message(tr("CALDERA ERUPTION! GET ONTO THE ROCKS!"), ERUPTION_WARN - 0.5)
	if CalderaAmbience.current != null:
		CalderaAmbience.current.rumble(0.7)
	_flood_ground(0.0, 0.0)
	# raised basalt islands burst up round you, 7-13 m off, each with a glowing arrow over it
	var pp := ground(player.global_position)
	var a0 := randf() * TAU
	for k in ISLANDS:
		var at := pp
		for tries in 12:
			var a := a0 + TAU * k / ISLANDS + randf_range(-0.35, 0.35)
			at = ground(pp + Vector3(cos(a), 0, sin(a)) * randf_range(7.0, 13.0))
			if CalderaBuilder.lava_dist(at.x, at.z) > CalderaBuilder.BANK + ISLAND_R:
				break
		islands.append(_island(at))
	_show_arrows()


func _tick_eruption(dt: float) -> void:
	model.act = clampf(_t / 0.8, 0.0, 1.0)
	var f := clampf(_t / ERUPTION_WARN, 0.0, 1.0)
	for isl in islands:   # the islands heave up out of the ground
		var body: Node3D = isl["body"]
		body.position.y = lerpf(body.position.y, float(isl["top"]), clampf(dt * 3.0, 0.0, 1.0))
	if not _flooding and not _flood_over:
		_flood_ground(f, 0.0)
		player.add_shake(lerpf(0.15, 0.55, f))
		if fmod(_t, 2.4) < dt and CalderaAmbience.current != null:
			CalderaAmbience.current.rumble(0.3)
		if fmod(_t, 3.0) < dt:
			play_sfx("giggle", randf_range(0.9, 1.15))
	if not _flooding and not _flood_over and _t >= ERUPTION_WARN:
		_flooding = true
		_flood_t = 0.0
		_flood_tick = 1.0
		play_sfx("flood")
		play_sfx("eruption", 0.85)
		player.add_shake(1.5)
		if CalderaAmbience.current != null:
			var v := main.get_node_or_null("CinderCone")
			if v != null and v.has_method("erupt"):
				v.erupt(1.6)
		_flood_ground(0.0, 1.0)
		if not on_island(player.global_position):
			if player.hurt_true(FLOOD_HIT):
				flood_hits += 1
				counts["hits"] += 1
			player.ignite()
	if _flooding:
		_flood_t += dt
		_flood_tick -= dt
		if _flood_tick <= 0.0:
			_flood_tick = 1.0
			if not on_island(player.global_position) and _flood_t < FLOOD_TIME:
				if player.hurt_true(FLOOD_TICK):
					flood_hits += 1
				player.ignite()
		if _flood_t >= FLOOD_TIME:
			_end_flood()
	if _arrows != null:   # bob and spin
		for a in _arrows.get_children():
			var base: float = a.get_meta("y")
			(a as Node3D).position.y = base + sin(_t * 4.0 + float(a.get_meta("ph"))) * 0.6
			(a as Node3D).rotation.y += dt * 2.0
	if _t >= _total:
		_done(0.8)


func _end_flood() -> void:
	if not _flooding and islands.is_empty():
		return
	_flooding = false
	_flood_over = true
	_flood_ground(0.0, 0.0)
	_hide_arrows()
	for isl in islands:   # the islands sink back
		var body: Node3D = isl["body"]
		var tw := create_tween()
		tw.tween_property(body, "position:y", body.position.y - ISLAND_H - 1.0, 1.5)
		tw.tween_callback(body.queue_free)
	islands.clear()
	_total = _t + 1.0


func is_flooding() -> bool:
	return _flooding


## Minimap: the eruption's raised basalt islands until the flood is over (MapBoss API).
func map_safe_zones() -> Array:
	var out: Array = []
	if _flood_over:
		return out
	for isl in islands:
		out.append({"pos": isl["at"], "radius": ISLAND_R})
	return out


## Is `p` up on one of the eruption's islands (safe from the flood)?
func on_island(p: Vector3) -> bool:
	for isl in islands:
		var at: Vector3 = isl["at"]
		if flat_dist(p, at) < ISLAND_R + 0.3 and p.y > float(isl["top"]) - 0.7:
			return true
	return false


func _flood_ground(warn: float, flood: float) -> void:
	var m := CalderaBuilder.ground_mat
	if m == null:
		return
	m.set_shader_parameter("flood_warn", warn)
	m.set_shader_parameter("flood", flood)


## One safe island: a raised knot of basalt columns `ISLAND_H` over the highest ground under it,
## rising out of the ground (solid: you stand on top).
func _island(at: Vector3) -> Dictionary:
	var top := at.y
	for k in 8:
		var a := TAU * k / 8.0
		top = maxf(top, SwampWater.height_at(at.x + cos(a) * ISLAND_R, at.z + sin(a) * ISLAND_R))
	top += ISLAND_H
	var body := StaticBody3D.new()
	body.name = "SafeIsland"   # no-i18n
	body.add_to_group("safe_island")
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var pts := CalderaProps._hex_pack(19, 1.24)
	for p in pts:
		var q: Vector2 = p
		if q.length() > ISLAND_R:
			continue
		var h := 3.6 + rng.randf_range(-0.12, 0.08) - q.length() * 0.05
		CalderaProps.hex_column(mb, Vector3(q.x, -3.6, q.y), 0.71, h, 0.0, rng, true, CalderaProps.HOT if rng.randf() < 0.25 else CalderaProps.ROCK)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(CalderaProps.rock_material())
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = ISLAND_R
	shape.height = 3.6
	cs.shape = shape
	cs.position = Vector3(0, -1.8, 0)
	body.add_child(cs)
	main.add_child(body)
	body.global_position = Vector3(at.x, top - ISLAND_H - 1.0, at.z)   # its columns' tops rise to `top`
	if fx:
		fx.burst(at + Vector3(0, 0.6, 0), ISLAND_R, Color(0.25, 0.2, 0.18), 0.5)
	return {"body": body, "at": at, "top": top}


## A big glowing arrow over every island, pointing down: get up here! (like Thog's quake)
func _show_arrows() -> void:
	_hide_arrows()
	_arrows = Node3D.new()
	_arrows.name = "EruptionArrows"   # no-i18n
	_arrows.top_level = true
	main.add_child(_arrows)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.45, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.95, 0.75)
	mat.disable_fog = true
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.9, 2.4, 0.9)
	var head_m := CylinderMesh.new()
	head_m.top_radius = 1.7
	head_m.bottom_radius = 0.0
	head_m.height = 2.0
	head_m.radial_segments = 4
	for isl in islands:
		var at: Vector3 = isl["at"]
		var y: float = float(isl["top"]) + 5.5
		var a := Node3D.new()
		a.position = Vector3(at.x, y, at.z)
		a.set_meta("y", y)
		a.set_meta("ph", randf() * TAU)
		var s := MeshInstance3D.new()
		s.mesh = shaft
		s.material_override = mat
		s.position.y = 2.2
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.add_child(s)
		var h := MeshInstance3D.new()
		h.mesh = head_m
		h.material_override = mat
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.add_child(h)
		_arrows.add_child(a)


func _hide_arrows() -> void:
	if _arrows != null and is_instance_valid(_arrows):
		_arrows.queue_free()
	_arrows = null


func arrow_count() -> int:
	return _arrows.get_child_count() if _arrows != null and is_instance_valid(_arrows) else 0


# ------------------------------------------------------------------ effects

## The breath: a spreading spew of fire from his grin.
func _fire_stream() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 220
	p.lifetime = 0.8
	p.explosiveness = 0.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3(0, 0, 1)
	p.spread = rad_to_deg(BREATH_HALF) * 0.8
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 28.0
	p.gravity = Vector3(0, -4.0, 0)
	p.damping_min = 4.0
	p.damping_max = 8.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.8))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	grad.add_point(0.4, Color(1.0, 0.4, 0.05, 0.85))
	grad.set_color(grad.get_point_count() - 1, Color(0.25, 0.08, 0.04, 0.0))
	p.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_fog = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Abilities._soft_dot()
	quad.material = mat
	p.mesh = quad
	return p


## A basis whose local +Z points along `dir`.
static func _basis_toward(dir: Vector3) -> Basis:
	var z := dir
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


func _tick_fx(dt: float) -> void:
	if _breath_fx != null and model != null and model.mouth != null:
		var dir := _aim
		dir.y = -0.2
		_breath_fx.global_transform = Transform3D(_basis_toward(dir.normalized()), model.mouth.global_position)
	if state != "dead" and state != "dying":
		_tick_scorches(dt)
	for k in range(_fires.size() - 1, -1, -1):
		var f: Dictionary = _fires[k]
		f["t"] += dt
		var node = f["node"]
		if not is_instance_valid(node):
			_fires.remove_at(k)
			continue
		if f["t"] >= f["life"] - 0.6:
			(node as CPUParticles3D).emitting = false
		if f["t"] >= f["life"] + 1.0:
			(node as Node).queue_free()
			_fires.remove_at(k)


# ------------------------------------------------------------------ enrage, death, drawing

func _on_enrage() -> void:
	model.set_enrage(1.0)
	play_sfx("cackle", 0.8)
	var aura := Abilities._flame_particles(1.2, 1.0, 60)
	aura.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	aura.emission_sphere_radius = 1.4
	aura.position = Vector3(0, 0.8, 0)
	model.head.add_child(aura)


func _on_die() -> void:
	model.pose = "die"
	model.die_t = 0.0
	model.sink = 0.0
	model.lift = 0.0
	model.curl = 0.0
	play_sfx("fizzle")
	main.hud.flash_message("SINGE GUTTERS OUT!", 3.0)
	_flooding = false
	_flood_ground(0.0, 0.0)
	_hide_arrows()
	for isl in islands:
		(isl["body"] as Node).queue_free()
	islands.clear()
	_scorches.clear()
	CalderaBuilder.dim_lava(self, 0.35, 4.0)


func _tick_death(dt: float) -> bool:
	model.die_t = _die_t
	model.set_cool(clampf((_die_t - 2.4) / 3.5, 0.0, 1.0))
	if fx and _die_t < 2.6 and fmod(_die_t, 0.25) < dt:   # sputtering sparks as he shrinks
		fx.burst(global_position + Vector3(randf_range(-1.5, 1.5), randf_range(1.0, 4.0) * (1.0 - _die_t / 3.0), randf_range(-1.5, 1.5)), 1.4, FIRE, 0.35)
	if _die_t > 2.9 and not has_meta("puffed"):   # one last puff of smoke
		set_meta("puffed", true)
		play_sfx("puff")
		if fx:
			fx.burst(global_position + Vector3(0, 1.2, 0), 3.0, Color(0.42, 0.4, 0.38), 1.2)
			fx.burst(global_position + Vector3(0, 2.4, 0), 2.2, Color(0.5, 0.48, 0.46), 1.4)
	return _die_t > 7.0


func _sync(dt: float) -> void:
	var i := row()
	if i < 0:
		return
	global_position = em.pos[i]
	if state == "walk":
		var v := em.vel[i]
		var want := _yaw
		var to := player.global_position - em.pos[i]
		if Vector2(v.x, v.z).length() > 0.4:
			want = atan2(-v.x, -v.z)
		elif to.length() > 0.1:
			want = atan2(-to.x, -to.z)
		_yaw = rotate_toward(_yaw, want, TURN_RATE * dt)
	elif attack == "scamper" or attack == "dive":
		var dir := _aim if attack == "scamper" else (_leap_to - _leap_from)
		if Vector2(dir.x, dir.z).length() > 0.1:
			_yaw = rotate_toward(_yaw, atan2(-dir.x, -dir.z), 10.0 * dt)
	elif attack != "rise" and attack != "eruption":
		_yaw = rotate_toward(_yaw, atan2(-_aim.x, -_aim.z), 6.0 * dt)
	rotation.y = _yaw
