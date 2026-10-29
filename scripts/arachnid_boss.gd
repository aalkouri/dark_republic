class_name ArachnidBoss
extends MapBoss
## The Arachnid, the Castle's boss: a 10 m spider that arrives at 8:00 and enrages at 10:00.
## Beating her makes her playable.
##
## She CLIMBS: every so often she leaps to the nearest wall of the room you're in and runs up
## it, then scuttles along the wall high above you (out of reach of anything but projectiles,
## and touching her up there can't hurt you) spitting webs and venom down. From the wall she
## may crawl out across the ceiling until she's over you, then DROPS. Indoors only; anywhere
## else she stays on the ground.
##
## Attacks (all marked on the ground first, see MapBoss):
##   LUNGE         close: a red lane in front of her, then she dashes down it fangs first.
##   VENOM SPIT    globs (3, enraged 5) arc onto circles at and around you; each leaves a poison
##                 puddle for a few seconds.
##   WEB SHOT      (from the wall) a web lands on a circle at you: standing in it slows you to
##                 40% for as long as it lasts.
##   DROP          (from the ceiling or a wall) a big circle under her fills, then she lands on it
##                 hard, and a brood of spiderlings scatters from the impact.
##   BROOD         an egg sac is laid at a marked spot; spiderlings hatch from it.

const SCALE := 1.7                 # x SpiderModel: about 10 m leg span
const TURN_RATE := 4.0
const GAP := Vector2(1.0, 1.8)
const LUNGE_RANGE := 13.0
const LUNGE_LEN := 16.0
const LUNGE_WIDTH := 5.0
const LUNGE_WARN := 1.2
const LUNGE_TIME := 0.35
const LUNGE_DAMAGE := 38.0
const SPIT_WARN := 1.3
const SPIT_RADIUS := 2.6
const SPIT_DAMAGE := 18.0
const SPIT_COOLDOWN := 4.0
const PUDDLE_DPS := 7.0
const WEB_WARN := 1.2
const WEB_RADIUS := 4.0
const WEB_LIFE := 5.0
const WEB_SLOW := 0.4
const DROP_WARN := 1.5
const DROP_RADIUS := 7.0
const DROP_DAMAGE := 45.0
const DROP_BROOD := 6
const BROOD_WARN := 2.0
const BROOD_COUNT := 8
const BROOD_COOLDOWN := 20.0
const CLIMB_COOLDOWN := 16.0
const CLIMB_FIRST := 8.0
const LEAP_TIME := 0.8
const CLIMB_TIME := 1.3
const WALL_HEIGHT := 16.0          # how high she sits on the wall (doorways are 14 m tall)
const WALL_SPEED := 8.0
const WALL_TIME := Vector2(8.0, 11.0)
const WALL_SHOT_EVERY := 1.7
const CEILING_SPEED := 10.0
const CEILING_TIME := 4.5
const FACE_OFF := 1.2              # her feet this far from the wall's room boundary
const SPIDERLING := Color(0.25, 0.15, 0.3)

var model: SpiderModel
var surface := "floor"             # floor | wall | ceiling
var _face := {}                    # the wall she's on: {n (into the room), p (a point on it), t (along), lo, hi}
var _yaw := 0.0
var _aim := Vector3.FORWARD
var _gap := 2.0
var _spit_cd := 1.0
var _brood_cd := 12.0
var _climb_cd := CLIMB_FIRST
var _t := 0.0
var _phase_t := 0.0
var _shot_t := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _q_from := Quaternion.IDENTITY
var _q_to := Quaternion.IDENTITY
var _along := 0.0                  # position along the wall
var _top := Vector3.ZERO           # her spot while on a wall / the ceiling
var _lunge_dir := Vector3.FORWARD
var _lunge_hit := false
var _step_t := 0.0
var _leap_time := LEAP_TIME


func stats() -> Dictionary:
	return {"name": "The Arachnid", "hp": 5600.0, "speed": 5.2, "radius": 3.2, "height": 4.2, "damage": 45.0, "xp": 400.0}


func display_name() -> String:
	return "THE ARACHNID"


func bar_color() -> Color:
	return Color(0.55, 0.12, 0.6)


func sounds() -> Dictionary:
	return {
		"roar": "res://audio/bosses/spider_screech.wav",
		"hiss": "res://audio/bosses/spider_hiss.wav",
		"step": "res://audio/bosses/spider_skitter.wav",
		"spit": "res://audio/bosses/spider_spit.wav",
		"web": "res://audio/bosses/spider_web.wav",
		"splat": "res://audio/bosses/spore_splat.wav",
		"thud": "res://audio/thog/slam.wav",
		"fall": "res://audio/thog/fall.wav",
	}


func _build_model() -> void:
	model = SpiderModel.new()
	model.scale = Vector3.ONE * SCALE
	model.top_level = true
	add_child(model)
	var i := row()
	if i >= 0:
		var to := player.global_position - em.pos[i]
		_yaw = atan2(-to.x, -to.z)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.9, 0.5, 0.8)
	fill.light_energy = 1.4
	fill.omni_range = 14.0
	fill.position = Vector3(0, 6.0, 0)
	add_child(fill)
	_sync_floor(0.0)
	model.plant_all()
	play_sfx("roar")


func can_climb() -> bool:
	return CastleNav.current != null


func _physics_process(dt: float) -> void:
	super(dt)
	if state == "dead" or state == "dying":
		return
	if main.state != "playing":
		return
	if surface == "floor" and (state == "walk" or attack in ["spit", "brood"]):
		_sync_floor(dt)


func _on_hurt() -> void:
	model.flash()


# ------------------------------------------------------------------ on the floor

func _think(dt: float, i: int) -> void:
	em.troll_busy = false
	var k := speed_k()
	_gap -= dt * k
	_spit_cd -= dt * k
	_brood_cd -= dt * k
	_climb_cd -= dt * k
	if em.is_held(i):
		return
	_step_t -= dt
	if _step_t <= 0.0 and em.vel[i].length() > 0.8:
		_step_t = 0.35
		play_sfx("step")
	if _gap > 0.0:
		return
	var d := flat_dist(player.global_position, em.pos[i])
	if _climb_cd <= 0.0 and can_climb() and _pick_wall(em.pos[i]):
		_start_leap()
	elif d < LUNGE_RANGE:
		_start("lunge")
	elif _brood_cd <= 0.0:
		_start("brood")
	elif _spit_cd <= 0.0:
		_start("spit")


func _start(kind: String) -> void:
	state = "attack"
	attack = kind
	counts[kind] = int(counts.get(kind, 0)) + 1
	_t = 0.0
	em.troll_busy = true
	var i := row()
	var to := player.global_position - em.pos[i]
	to.y = 0.0
	_aim = to.normalized() if to.length() > 0.1 else Vector3(-sin(_yaw), 0, -cos(_yaw))
	match kind:
		"lunge":
			_lunge_dir = _aim
			_lunge_hit = false
			model.rear = 0.0
			model.crouch = 0.8
			play_sfx("hiss")
			warn_lane(em.pos[i], _lunge_dir, LUNGE_LEN, LUNGE_WIDTH, LUNGE_WARN, _begin_lunge)
		"spit":
			_spit_cd = SPIT_COOLDOWN
			model.rear = 0.7
			_spit_volley(em.pos[i] + Vector3(0, 3.0, 0) + _aim * 2.0, 3 + (2 if is_enraged else 0), false)
			_end_after(warn_time(SPIT_WARN) * 0.5)
		"brood":
			_brood_cd = BROOD_COOLDOWN
			model.rear = 0.3
			var at := ground(em.pos[i] + _aim * 6.0)
			_lay_eggs(at)
			_end_after(0.8)


func _end_after(secs: float) -> void:
	_phase_t = secs


func _tick_attack(dt: float) -> void:
	_t += dt
	match attack:
		"lunge":
			if _phase_t > 0.0:   # dashing down the lane
				_phase_t -= dt
				var i := row()
				if i >= 0:
					var step := _lunge_dir * (LUNGE_LEN / LUNGE_TIME) * dt
					var np := em.pos[i] + step
					if CastleNav.current == null or not CastleNav.current.is_blocked(np.x, np.z):
						em.pos[i] = ground(np)
					_sync_floor(dt)
					if not _lunge_hit and flat_dist(player.global_position, em.pos[i]) < LUNGE_WIDTH * 0.6 + 1.5:
						_lunge_hit = true
						hit_player(LUNGE_DAMAGE, _lunge_dir)
				if _phase_t <= 0.0:
					model.crouch = 0.0
					_done(0.3)
		"spit", "brood":
			_phase_t -= dt
			if _phase_t <= 0.0:
				model.rear = 0.0
				_done(0.0)
		"leap":
			_tick_leap(dt)
		"climb":
			_tick_climb(dt)
		"wall":
			_tick_wall(dt)
		"to_ceiling":
			_tick_to_ceiling(dt)
		"ceiling":
			_tick_ceiling(dt)
		"drop":
			_tick_drop(dt)


func _begin_lunge() -> void:
	_phase_t = LUNGE_TIME
	play_sfx("hiss", 1.2)
	shake(0.3)


func _done(extra_gap: float) -> void:
	state = "walk"
	attack = ""
	em.troll_busy = false
	_gap = randf_range(GAP.x, GAP.y) + extra_gap


## Globs from `from` onto circles at and around the player.
func _spit_volley(from: Vector3, n: int, webs: bool) -> void:
	var secs := warn_time(WEB_WARN if webs else SPIT_WARN)
	play_sfx("web" if webs else "spit")
	for k in n:
		var at := player_ahead(secs * 0.5) if k == 0 else ground(player.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(3.0, 7.0))
		if webs:
			lob(from, at + Vector3(0, 0.3, 0), secs, Color(0.92, 0.92, 0.95), 0.7, 3.0)
			warn_circle(at, WEB_RADIUS, WEB_WARN, func(): _land_web(at), Color(0.9, 0.9, 1.0))
		else:
			lob(from, at + Vector3(0, 0.3, 0), secs, Color(0.55, 1.0, 0.25), 0.45, 5.0)
			warn_circle(at, SPIT_RADIUS, SPIT_WARN, func(): _land_spit(at))


func _land_spit(at: Vector3) -> void:
	play_sfx("splat", 1.2)
	if player_in_circle(at, SPIT_RADIUS) and not airborne():
		hit_player(SPIT_DAMAGE, player.global_position - at)
	add_hazard(at, SPIT_RADIUS, 3.0, Color(0.4, 0.9, 0.2), PUDDLE_DPS)


func _land_web(at: Vector3) -> void:
	play_sfx("web", 0.8)
	add_hazard(at, WEB_RADIUS, WEB_LIFE, Color(0.85, 0.85, 0.92), 0.0, WEB_SLOW)


func _lay_eggs(at: Vector3) -> void:
	var sac := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.1
	sm.height = 1.8
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.88, 0.85, 0.75)
	m.roughness = 0.9
	sm.material = m
	sac.mesh = sm
	sac.top_level = true
	add_child(sac)
	sac.global_position = at + Vector3(0, 0.8, 0)
	var tw := create_tween().set_loops(8)
	tw.tween_property(sac, "scale", Vector3(1.12, 0.92, 1.12), 0.12)
	tw.tween_property(sac, "scale", Vector3.ONE, 0.12)
	warn_circle(at, 3.5, BROOD_WARN, func():
		sac.queue_free()
		_hatch(at, BROOD_COUNT), Color(0.9, 0.85, 0.7))


## Spiderlings: fast little runners in the spider's colours.
func _hatch(at: Vector3, n: int) -> void:
	play_sfx("splat", 0.8)
	if fx:
		fx.burst(at + Vector3(0, 0.5, 0), 2.5, Color(0.88, 0.85, 0.75), 0.4)
	var hpm: float = main.hp_mult()
	for k in n:
		var a := TAU * k / n
		main._spawn_enemy(EnemyManager.RUNNER, ground(at + Vector3(cos(a), 0, sin(a)) * 1.5), hpm * 0.6)


# ------------------------------------------------------------------ climbing

## Choose a wall of the room the player is in (the nearest stretch of wall to her that isn't a
## doorway). Returns false if there's none.
func _pick_wall(from: Vector3) -> bool:
	var room := _room_rect(player.global_position)
	if room.is_empty():
		return false
	var best := {}
	var best_d := INF
	var x0: float = room[0]
	var z0: float = room[1]
	var x1: float = room[2]
	var z1: float = room[3]
	for f in [
		{"n": Vector3(1, 0, 0), "fixed": x0 + FACE_OFF, "axis": "z", "wall": x0, "lo": z0 + 8.0, "hi": z1 - 8.0},
		{"n": Vector3(-1, 0, 0), "fixed": x1 - FACE_OFF, "axis": "z", "wall": x1, "lo": z0 + 8.0, "hi": z1 - 8.0},
		{"n": Vector3(0, 0, 1), "fixed": z0 + FACE_OFF, "axis": "x", "wall": z0, "lo": x0 + 8.0, "hi": x1 - 8.0},
		{"n": Vector3(0, 0, -1), "fixed": z1 - FACE_OFF, "axis": "x", "wall": z1, "lo": x0 + 8.0, "hi": x1 - 8.0},
	]:
		if f["lo"] >= f["hi"]:
			continue
		var along: float = clampf(from.z if f["axis"] == "z" else from.x, f["lo"], f["hi"])
		along = _clear_of_doors(f, along)
		if is_nan(along):
			continue
		var p := Vector3(f["fixed"], 0, along) if f["axis"] == "z" else Vector3(along, 0, f["fixed"])
		var d := flat_dist(p, from)
		if d < best_d:
			best_d = d
			best = f.duplicate()
			best["base"] = ground(p)
			best["along"] = along
	if best.is_empty() or best_d > 130.0:
		return false
	_face = best
	return true


## Slide `along` off any doorway in this wall (doorways are holes up to 14 m). NAN if nowhere.
func _clear_of_doors(f: Dictionary, along: float) -> float:
	var openings := []
	for w in CastleBuilder.WALLS:
		# CastleBuilder.WALLS: [axis it runs along, fixed coordinate, from, to, openings]
		if w[0] == f["axis"] and absf(float(w[1]) - float(f["wall"])) < 0.6:
			openings = w[4]
	if absf(float(f["wall"])) > 210.0 and f["axis"] == "x" and float(f["wall"]) > 0.0:
		openings = [[0.0, CastleBuilder.DOOR_W]]   # the front doors
	for o in openings:
		var c := float(o[0])
		var hw := float(o[1]) * 0.5 + 5.0
		if absf(along - c) < hw:
			var a := c - hw if along < c else c + hw
			if a < f["lo"] or a > f["hi"]:
				a = c + hw if along < c else c - hw
			if a < f["lo"] or a > f["hi"]:
				return NAN
			along = a
	return along


func _room_rect(p: Vector3) -> Array:
	for r in CastleBuilder.ROOMS:
		if p.x >= r[1] and p.x <= r[3] and p.z >= r[2] and p.z <= r[4]:
			return [r[1], r[2], r[3], r[4]]
	return []


## Her orientation on a surface: local +Y = the surface normal, local -Z = the way she faces.
static func _basis(up: Vector3, fwd: Vector3) -> Basis:
	var y := up.normalized()
	var z := -(fwd - y * fwd.dot(y)).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


func _start_leap() -> void:
	state = "attack"
	attack = "leap"
	counts["climb"] = int(counts.get("climb", 0)) + 1
	_climb_cd = CLIMB_COOLDOWN
	em.troll_busy = true
	em.boss_contact = false
	_t = 0.0
	_from = model.global_position
	_to = _face["base"]
	_leap_time = clampf(LEAP_TIME + flat_dist(_from, _to) / 40.0, LEAP_TIME, 2.6)   # big halls: a long bound
	_q_from = model.global_transform.basis.get_rotation_quaternion()
	var n: Vector3 = _face["n"]
	_q_to = _basis(Vector3.UP, -n).get_rotation_quaternion()
	play_sfx("hiss")


func _tick_leap(dt: float) -> void:
	_t += dt
	var f := clampf(_t / _leap_time, 0.0, 1.0)
	var p := _from.lerp(_to, f) + Vector3.UP * sin(f * PI) * (4.0 + _leap_time * 4.0)
	_set_pose(p, _q_from.slerp(_q_to, f))
	if f >= 1.0:
		attack = "climb"
		_t = 0.0
		_from = _to
		_q_from = _q_to
		var n: Vector3 = _face["n"]
		_q_to = _basis(n, Vector3.UP).get_rotation_quaternion()
		_along = _face["along"]


func _wall_point(along: float, height: float) -> Vector3:
	var p := Vector3(_face["fixed"], height, along) if _face["axis"] == "z" else Vector3(along, height, _face["fixed"])
	return p


func _tick_climb(dt: float) -> void:
	_t += dt
	var f := clampf(_t / CLIMB_TIME, 0.0, 1.0)
	# Tip onto the wall over the first third, then run up it
	var tip := clampf(f * 3.0, 0.0, 1.0)
	var h := lerpf(0.0, WALL_HEIGHT, clampf((f - 0.15) / 0.85, 0.0, 1.0))
	_set_pose(_wall_point(_along, maxf(h, tip * 2.0)), _q_from.slerp(_q_to, tip))
	if f >= 1.0:
		attack = "wall"
		surface = "wall"
		_t = 0.0
		_phase_t = randf_range(WALL_TIME.x, WALL_TIME.y)
		_shot_t = 0.6
		main.hud.flash_message("THE ARACHNID CLIMBS THE WALLS!", 2.0)


## Scuttle along the wall to stay level with the player, raining webs and venom.
func _tick_wall(dt: float) -> void:
	_t += dt
	var pp := player.global_position
	var want: float = clampf(pp.z if _face["axis"] == "z" else pp.x, _face["lo"], _face["hi"])
	var move := clampf(want - _along, -WALL_SPEED * speed_k() * dt, WALL_SPEED * speed_k() * dt)
	_along += move
	var n: Vector3 = _face["n"]
	var side := Vector3(0, 0, signf(move)) if _face["axis"] == "z" else Vector3(signf(move), 0, 0)
	var fwd := (Vector3.UP * 0.4 + side).normalized() if absf(move) > 0.001 else Vector3.UP
	var q := _basis(n, fwd).get_rotation_quaternion()
	var cur := model.global_transform.basis.get_rotation_quaternion()
	_set_pose(_wall_point(_along, WALL_HEIGHT + sin(_t * 1.3) * 1.2), cur.slerp(q, clampf(dt * 6.0, 0.0, 1.0)))
	_shot_t -= dt * speed_k()
	if _shot_t <= 0.0:
		_shot_t = WALL_SHOT_EVERY
		var from := model.global_position + n * 2.0
		if randf() < 0.5:
			_spit_volley(from, 1 + (1 if is_enraged else 0), true)
		else:
			_spit_volley(from, 3 + (1 if is_enraged else 0), false)
	if _t >= _phase_t:
		if randf() < 0.55:
			_start_to_ceiling()
		else:
			_start_drop(player_ahead(0.3), true)


func _start_to_ceiling() -> void:
	attack = "to_ceiling"
	_t = 0.0
	_from = model.global_position
	_to = _wall_point(_along, CastleBuilder.CEILING - 0.3) + (_face["n"] as Vector3) * 2.5
	_q_from = model.global_transform.basis.get_rotation_quaternion()
	_q_to = _basis(Vector3.DOWN, _face["n"]).get_rotation_quaternion()


func _tick_to_ceiling(dt: float) -> void:
	_t += dt
	var f := clampf(_t / 0.7, 0.0, 1.0)
	_set_pose(_from.lerp(_to, f), _q_from.slerp(_q_to, f))
	if f >= 1.0:
		attack = "ceiling"
		surface = "ceiling"
		_t = 0.0
		_top = _to


## Upside down across the ceiling until she's over you (or time's up), then drop.
func _tick_ceiling(dt: float) -> void:
	_t += dt
	var pp := player.global_position
	var to := Vector3(pp.x - _top.x, 0, pp.z - _top.z)
	var step := minf(to.length(), CEILING_SPEED * speed_k() * dt)
	if to.length() > 0.01:
		var room := _room_rect(pp)
		var np := _top + to.normalized() * step
		if not room.is_empty():
			np.x = clampf(np.x, room[0] + 4.0, room[2] - 4.0)
			np.z = clampf(np.z, room[1] + 4.0, room[3] - 4.0)
		_top = np
		var q := _basis(Vector3.DOWN, to.normalized()).get_rotation_quaternion()
		var cur := model.global_transform.basis.get_rotation_quaternion()
		_set_pose(_top, cur.slerp(q, clampf(dt * 6.0, 0.0, 1.0)))
	else:
		_set_pose(_top, model.global_transform.basis.get_rotation_quaternion())
	if to.length() < 2.0 or _t >= CEILING_TIME:
		_start_drop(ground(_top), false)


## Drop (from the ceiling: straight down; from a wall: a leap) onto `at`, marked first.
func _start_drop(at: Vector3, from_wall: bool) -> void:
	attack = "drop"
	_t = 0.0
	_from = model.global_position
	_to = at
	_q_from = model.global_transform.basis.get_rotation_quaternion()
	var face_dir := Vector3(player.global_position.x - at.x, 0, player.global_position.z - at.z)
	_q_to = _basis(Vector3.UP, face_dir.normalized() if face_dir.length() > 0.1 else Vector3.FORWARD).get_rotation_quaternion()
	_phase_t = warn_time(DROP_WARN)
	model.crouch = 1.0
	play_sfx("hiss", 0.8)
	warn_circle(at, DROP_RADIUS, DROP_WARN, _land_drop)
	set_meta("from_wall", from_wall)


func _tick_drop(dt: float) -> void:
	_t += dt
	# Hold on until the last 0.4 s of the warning, then fall onto the marked circle
	var fall := clampf((_t - (_phase_t - 0.4)) / 0.4, 0.0, 1.0)
	var p := _from.lerp(_to, fall * fall)
	if get_meta("from_wall", false):
		p += Vector3.UP * sin(fall * PI) * 4.0
	_set_pose(p, _q_from.slerp(_q_to, fall))


func _land_drop() -> void:
	_set_pose(_to, _q_to)
	surface = "floor"
	em.boss_contact = true
	em.set_boss_stats({"height": stats()["height"]})
	model.crouch = 0.0
	model.plant_all()
	play_sfx("thud")
	shake(1.0)
	if fx:
		fx.burst(_to + Vector3(0, 1.0, 0), DROP_RADIUS, Color(0.5, 0.45, 0.4), 0.7)
	if player_in_circle(_to, DROP_RADIUS):
		hit_player(DROP_DAMAGE, player.global_position - _to)
	_hatch(_to, DROP_BROOD)
	_done(0.6)


## Place her (the model) at `p` with rotation `q`. While she's off the floor her crowd row sits
## on the floor below her, tall enough to reach her, so shots aimed at her still connect.
func _set_pose(p: Vector3, q: Quaternion) -> void:
	model.global_transform = Transform3D(Basis(q).scaled(Vector3.ONE * SCALE), p)
	var i := row()
	if i < 0:
		return
	var off := Vector3.ZERO
	if surface == "wall" or attack in ["climb", "wall", "to_ceiling"]:
		off = (_face.get("n", Vector3.ZERO) as Vector3) * 2.0   # just out from the wall's foot
	var base := ground(p + off)
	em.pos[i] = base
	em.vel[i] = Vector3.ZERO
	em.set_boss_stats({"height": maxf(p.y - base.y + 4.0, stats()["height"])})
	global_position = base


func _sync_floor(dt: float) -> void:
	var i := row()
	if i < 0:
		return
	var p := em.pos[i]
	var want := _yaw
	if state == "walk":
		var v := em.vel[i]
		var to := player.global_position - p
		if Vector2(v.x, v.z).length() > 0.4:
			want = atan2(-v.x, -v.z)
		elif to.length() > 0.1:
			want = atan2(-to.x, -to.z)
	else:
		want = atan2(-_aim.x, -_aim.z)
	_yaw = rotate_toward(_yaw, want, TURN_RATE * dt)
	global_position = p
	model.global_transform = Transform3D(Basis(Vector3.UP, _yaw).scaled(Vector3.ONE * SCALE), p)


# ------------------------------------------------------------------ enrage, death

func _on_enrage() -> void:
	model.set_enrage(1.0)


func _on_die() -> void:
	play_sfx("roar", 0.7)
	surface = "floor"


func _tick_death(dt: float) -> bool:
	# Falls off whatever she was on, flips over and curls her legs up
	var p := model.global_position
	var g := ground(p)
	if p.y > g.y + 0.05:
		p.y = maxf(g.y, p.y - dt * 30.0)
	var flip := clampf(_die_t / 0.8, 0.0, 1.0)
	model.global_transform = Transform3D(Basis(Vector3.FORWARD.rotated(Vector3.UP, _yaw), PI * flip).scaled(Vector3.ONE * SCALE), p + Vector3.UP * flip * 2.5)
	model.curl = clampf(_die_t / 1.5, 0.0, 1.0)
	if _die_t > 0.8 and not has_meta("crashed"):
		set_meta("crashed", true)
		play_sfx("fall")
		shake(0.8)
	if _die_t > 5.0:
		model.position.y -= dt * 0.8
	if _die_t > 8.0:
		model.visible = false
		return true
	return false
