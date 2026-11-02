class_name PharaohBoss
extends MapBoss
## The Pharaoh, the Desert's boss: a 6 m mummified king in a gold death mask who RISES from the
## tomb before the Great Sphinx at 8:00 (the tomb's slabs grind apart, gold light and sand pour
## out, and he lifts out of the shaft) and enrages at 10:00. Killing him wins the run.
##
## Attacks (all marked on the ground first, see MapBoss):
##   FLAIL SLAM     close: a circle in front of him fills as the flail goes up, and it comes down
##                  hard on the mark (a burst of sand).
##   CURSE BEAM     a lane from him toward you; when it fills, a beam of green-gold light leaves
##                  his crook down it: damage, and you're CURSED (slowed) for a few seconds.
##   SANDSTORM      a whirling storm settles on a circle at you and hangs there for 6 s: it slows
##                  you to half speed and scours you while you stand in it.
##   SCARAB SWARM   three lanes fan out at you; swarms of black scarabs pour down each one.
##   RAISE THE DEAD four (enraged six) circles round you: mummies claw up out of the sand.
##   SAND WALK      if you run too far, he sinks into the sand and bursts up out of a marked circle
##                  beside you.
##   WRATH OF THE SANDS  his ultimate, at 75%, 50% and 10% health: he rises into the air and the
##                  Sphinx's eyes blaze; a great sandstorm fills everything round you (a huge red
##                  circle) except three golden safe spots. Be in one when it lands, or be flayed.

const SCALE := 3.2                 # x PharaohModel's 1.9 m: about 6 m tall
const TURN_RATE := 3.0
const GAP := Vector2(1.1, 1.9)
const RISE_TIME := 3.2
const SLAM_RANGE := 10.0
const SLAM_WARN := 1.4
const SLAM_RADIUS := 6.5
const SLAM_DAMAGE := 40.0
const BEAM_WARN := 1.3
const BEAM_LEN := 32.0
const BEAM_WIDTH := 4.4
const BEAM_DAMAGE := 30.0
const BEAM_COOLDOWN := 7.0
const CURSE_SLOW := 0.5
const CURSE_TIME := 3.0
const STORM_WARN := 1.5
const STORM_RADIUS := 7.0
const STORM_LIFE := 6.0
const STORM_DPS := 9.0
const STORM_SLOW := 0.5
const STORM_COOLDOWN := 10.0
const SCARAB_WARN := 1.2
const SCARAB_LEN := 26.0
const SCARAB_WIDTH := 3.0
const SCARAB_DAMAGE := 20.0
const SCARAB_COOLDOWN := 9.0
const SUMMON_WARN := 1.6
const SUMMON_COUNT := 4
const SUMMON_COOLDOWN := 18.0
const SUMMON_FIRST := 14.0
const TRAVEL_DIST := 42.0          # further than this from you for TRAVEL_AFTER s: he sand-walks
const TRAVEL_AFTER := 2.0
const TRAVEL_WARN := 1.3
const TRAVEL_RADIUS := 5.0
const TRAVEL_DAMAGE := 30.0
const WRATH_AT := [0.75, 0.5, 0.1] # health fractions that call down the Wrath of the Sands
const WRATH_WARN := 3.2
const WRATH_RADIUS := 32.0
const WRATH_SAFE := 3.6            # radius of each safe spot
const WRATH_SAFE_SPOTS := 3
const WRATH_DAMAGE := 55.0
const SAND := Color(0.92, 0.74, 0.45)
const CURSE := Color(0.55, 1.0, 0.35)

var model: PharaohModel
var tomb: Node3D
var _yaw := 0.0
var _aim := Vector3.FORWARD
var _gap := 2.0
var _beam_cd := 3.0
var _storm_cd := 6.0
var _scarab_cd := 8.0
var _summon_cd := SUMMON_FIRST
var _far_t := 0.0
var _t := 0.0
var _windup := 0.0
var _total := 0.0
var _landed := false
var _step_t := 0.0
var _wraths_done := 0
var _safe: Array[Dictionary] = []   # {disc, at}
var _wrath_at := Vector3.ZERO
var _beams: Array[Dictionary] = []  # {node, t, life}
var _swarms: Array[Dictionary] = [] # {node, from, to, t}
var _storms: Array[Dictionary] = [] # {node, t}
var _eye_beams: Array[Node3D] = []
var _storm_fx := 0.0                # the desert wind's storm level (the wrath)
var curse_hits := 0                 # tests
var _wind: DesertWind


## Where he rises: the tomb door before the sphinx's paws.
static func rise_point() -> Vector3:
	var t: Vector3 = DesertBuilder.sphinx.get("tomb", Vector3.ZERO)
	return t


func stats() -> Dictionary:
	return {"name": "The Pharaoh", "hp": 5800.0, "speed": 3.4, "radius": 2.0, "height": 6.2, "damage": 42.0, "xp": 400.0}


func display_name() -> String:
	return "THE PHARAOH"


func bar_color() -> Color:
	return Color(0.86, 0.66, 0.16)


func sounds() -> Dictionary:
	return {
		"roar": "res://audio/desert/pharaoh_roar.wav",
		"curse": "res://audio/desert/pharaoh_curse.wav",
		"storm": "res://audio/desert/sandstorm.wav",
		"summon": "res://audio/desert/pharaoh_summon.wav",
		"scarab": "res://audio/desert/scarabs.wav",
		"rise": "res://audio/desert/tomb_rumble.wav",
		"slam": "res://audio/thog/slam.wav",
		"fall": "res://audio/thog/fall.wav",
		"step": "res://audio/bosses/armor_step.wav",
	}


func _build_model() -> void:
	model = PharaohModel.new()
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	var i := row()
	if i >= 0:
		var to := player.global_position - em.pos[i]
		_yaw = atan2(-to.x, -to.z)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.75, 0.35)
	glow.light_energy = 1.6
	glow.omni_range = 16.0
	glow.position = Vector3(0, 6.5, -3.0)
	add_child(glow)
	tomb = main.get_tree().get_first_node_in_group("sphinx_tomb") as Node3D
	_sync(0.0)
	_start_rise()


func _physics_process(dt: float) -> void:
	super(dt)
	_tick_fx(dt)
	if state == "dead" or state == "dying":
		return
	if main.state != "playing":
		return
	if state == "walk" and _wraths_done < WRATH_AT.size() and hp_fraction() <= WRATH_AT[_wraths_done]:
		while _wraths_done < WRATH_AT.size() and hp_fraction() <= WRATH_AT[_wraths_done]:
			_wraths_done += 1
		_start("wrath")
	_sync(dt)


func _on_hurt() -> void:
	model.flash()


# ------------------------------------------------------------------ rising from the tomb

func _start_rise() -> void:
	state = "attack"
	attack = "rise"
	_t = 0.0
	em.troll_busy = true
	em.boss_contact = false
	model.pose = "rise"
	model.rise = 0.0
	model.position.y = -7.0
	play_sfx("rise")
	shake(0.6)
	main.hud.flash_message("THE PHARAOH RISES FROM HIS TOMB!", 3.5)
	if tomb != null:
		var tw := create_tween().set_parallel(true)
		for n in ["SlabL", "SlabR"]:
			var slab := tomb.get_node_or_null(n) as Node3D
			if slab != null:
				tw.tween_property(slab, "position:x", slab.position.x * 2.9, 1.2).set_trans(Tween.TRANS_SINE)
		var glow := tomb.get_node_or_null("Glow") as OmniLight3D
		if glow != null:
			tw.tween_property(glow, "light_energy", 6.0, 1.0)


func _tick_rise(dt: float) -> void:
	var f := clampf((_t - 0.6) / (RISE_TIME - 0.6), 0.0, 1.0)
	model.rise = f
	model.position.y = lerpf(-7.0, 0.0, 1.0 - pow(1.0 - f, 2.0))
	if fx and fmod(_t, 0.25) < dt:
		fx.burst(global_position + Vector3(randf_range(-2, 2), 0.5, randf_range(-2, 2)), 2.5, SAND, 0.5)
	if _t >= RISE_TIME:
		model.position.y = 0.0
		model.pose = "walk"
		em.boss_contact = true
		play_sfx("roar")
		shake(0.8)
		if tomb != null:
			var glow := tomb.get_node_or_null("Glow") as OmniLight3D
			if glow != null:
				create_tween().tween_property(glow, "light_energy", 1.5, 2.0)
		_done(0.5)


# ------------------------------------------------------------------ deciding

func _think(dt: float, i: int) -> void:
	em.troll_busy = false
	var k := speed_k()
	_gap -= dt * k
	_beam_cd -= dt * k
	_storm_cd -= dt * k
	_scarab_cd -= dt * k
	_summon_cd -= dt * k
	if em.is_held(i):
		model.walk_speed = 0.0
		return
	var spd := em.vel[i].length()
	model.pose = "walk"
	model.walk_speed = spd / SCALE * 1.4
	_step_t -= dt
	if _step_t <= 0.0 and spd > 0.6:
		_step_t = 0.7
		play_sfx("step", 0.7)
		shake(0.05)
	var d := flat_dist(player.global_position, em.pos[i])
	_far_t = _far_t + dt if d > TRAVEL_DIST else 0.0
	if _gap > 0.0:
		return
	if _far_t >= TRAVEL_AFTER:
		_start("travel")
	elif _summon_cd <= 0.0:
		_start("summon")
	elif d < SLAM_RANGE:
		_start("slam")
	elif _storm_cd <= 0.0 and d < 34.0:
		_start("storm")
	elif _beam_cd <= 0.0 and d < BEAM_LEN - 2.0:
		_start("beam")
	elif _scarab_cd <= 0.0 and d < SCARAB_LEN:
		_start("scarabs")


func _start(kind: String) -> void:
	state = "attack"
	attack = kind
	counts[kind] = int(counts.get(kind, 0)) + 1
	_t = 0.0
	_landed = false
	em.troll_busy = true
	model.walk_speed = 0.0
	var i := row()
	var to := player.global_position - em.pos[i]
	to.y = 0.0
	_aim = to.normalized() if to.length() > 0.1 else Vector3(-sin(_yaw), 0, -cos(_yaw))
	match kind:
		"slam":
			_windup = warn_time(SLAM_WARN)
			_total = _windup + 0.6
			model.pose = "slam"
			var c := ground(em.pos[i] + _aim * 5.0)
			warn_circle(c, SLAM_RADIUS, SLAM_WARN, func(): _land_slam(c))
		"beam":
			_beam_cd = BEAM_COOLDOWN
			_windup = warn_time(BEAM_WARN)
			_total = _windup + 0.5
			model.pose = "beam"
			play_sfx("curse", 0.8)
			var from := em.pos[i]
			var dir := _aim
			warn_lane(from, dir, BEAM_LEN, BEAM_WIDTH, BEAM_WARN, func(): _fire_beam(from, dir))
		"storm":
			_storm_cd = STORM_COOLDOWN
			_windup = 0.8
			_total = 1.2
			model.pose = "summon"
			var c := player_ahead(0.5)
			var r := STORM_RADIUS * (1.25 if is_enraged else 1.0)
			warn_circle(c, r, STORM_WARN, func(): _land_storm(c, r), SAND)
		"scarabs":
			_scarab_cd = SCARAB_COOLDOWN
			_windup = warn_time(SCARAB_WARN)
			_total = _windup + 0.4
			model.pose = "beam"
			var from := em.pos[i]
			for k in 3:
				var dir := _aim.rotated(Vector3.UP, deg_to_rad(-22.0 + 22.0 * k))
				warn_lane(from, dir, SCARAB_LEN, SCARAB_WIDTH, SCARAB_WARN, func(): _land_scarabs(from, dir))
		"summon":
			_summon_cd = SUMMON_COOLDOWN
			_windup = warn_time(SUMMON_WARN)
			_total = _windup + 0.3
			model.pose = "summon"
			play_sfx("summon")
			main.hud.flash_message("THE DEAD ANSWER THE PHARAOH!", 2.5)
			var pp := player.global_position
			var n := SUMMON_COUNT + (2 if is_enraged else 0)
			var a0 := randf() * TAU
			for k in n:
				var a := a0 + TAU * k / n
				var at := ground(pp + Vector3(cos(a), 0, sin(a)) * randf_range(6.0, 9.0))
				warn_circle(at, 2.2, SUMMON_WARN, func(): _raise_mummy(at), Color(0.85, 0.75, 0.5))
		"travel":   # sinks into the sand, bursts out of a marked circle beside you
			_far_t = 0.0
			_windup = 0.8
			_total = 99.0
			em.boss_contact = false
			model.pose = "rise"
			play_sfx("storm", 1.2)
		"wrath":
			_start_wrath()


func _done(extra_gap: float) -> void:
	state = "walk"
	attack = ""
	em.troll_busy = false
	em.boss_contact = true
	model.pose = "walk"
	model.act = 0.0
	_gap = randf_range(GAP.x, GAP.y) + extra_gap


func _tick_attack(dt: float) -> void:
	_t += dt
	match attack:
		"rise":
			_tick_rise(dt)
			return
		"travel":
			_tick_travel(dt)
			return
		"wrath":
			_tick_wrath(dt)
			return
	model.act = clampf(_t / maxf(_windup, 0.01) * (0.75 if attack == "slam" else 1.0), 0.0, 1.0) if _t < _windup else minf(1.0, 0.75 + (_t - _windup) * 0.5)
	if _t >= _total:
		_done(0.0)


# ------------------------------------------------------------------ attacks landing

func _land_slam(c: Vector3) -> void:
	play_sfx("slam")
	shake(0.7)
	if player_in_circle(c, SLAM_RADIUS) and not airborne():
		hit_player(SLAM_DAMAGE, player.global_position - c)
	if fx:
		fx.burst(c + Vector3(0, 0.6, 0), SLAM_RADIUS, SAND, 0.55)
		for k in 8:
			var a := TAU * k / 8.0
			fx.burst(c + Vector3(cos(a), 0.3, sin(a)) * SLAM_RADIUS * 0.8, 1.6, SAND.darkened(0.2), 0.4)


func _fire_beam(from: Vector3, dir: Vector3) -> void:
	play_sfx("curse", 1.1)
	shake(0.3)
	var start := model.crook_tip.global_position if model.crook_tip != null else from + Vector3(0, 4, 0)
	var end := ground(from + dir * BEAM_LEN) + Vector3(0, 1.0, 0)
	_beam(start, end, CURSE, 0.45, 0.55)
	# in the lane?
	var rel := player.global_position - from
	rel.y = 0.0
	var along := rel.dot(dir)
	var across := (rel - dir * along).length()
	if along > -1.0 and along < BEAM_LEN and across < BEAM_WIDTH * 0.5 + 0.4:
		if hit_player(BEAM_DAMAGE, dir):
			curse_hits += 1
		player.apply_slow(CURSE_SLOW, CURSE_TIME)
		if fx:
			fx.burst(player.global_position + Vector3(0, 1.0, 0), 1.6, Color(0.55, 0.25, 0.8), 0.5)


func _land_storm(c: Vector3, r: float) -> void:
	play_sfx("storm")
	add_hazard(c, r, STORM_LIFE, SAND, STORM_DPS * (1.3 if is_enraged else 1.0), STORM_SLOW)
	var p := _whirl(r)
	add_child(p)
	p.global_position = c
	_storms.append({"node": p, "t": 0.0})


func _land_scarabs(from: Vector3, dir: Vector3) -> void:
	play_sfx("scarab")
	var rel := player.global_position - from
	rel.y = 0.0
	var along := rel.dot(dir)
	var across := (rel - dir * along).length()
	if along > -1.0 and along < SCARAB_LEN and across < SCARAB_WIDTH * 0.5 + 0.3 and not airborne():
		hit_player(SCARAB_DAMAGE, dir)
	var swarm := _scarab_swarm()
	add_child(swarm)
	swarm.global_position = ground(from)
	swarm.rotation.y = atan2(dir.x, dir.z)
	_swarms.append({"node": swarm, "from": ground(from), "to": ground(from + dir * SCARAB_LEN), "t": 0.0})


func _raise_mummy(at: Vector3) -> void:
	if fx:
		fx.burst(at + Vector3(0, 0.6, 0), 2.2, SAND, 0.5)
	var hpm: float = main.hp_mult()
	main._spawn_enemy(EnemyManager.MUMMY, at, hpm * 0.7)


# ------------------------------------------------------------------ sand walk

func _tick_travel(dt: float) -> void:
	var i := row()
	if i < 0:
		return
	if _t < _windup:   # sinking into a whirl of sand
		model.position.y = -7.0 * (_t / _windup)
		if fx and fmod(_t, 0.2) < dt:
			fx.burst(global_position + Vector3(0, 0.6, 0), 3.0, SAND, 0.45)
		return
	if not _landed:
		_landed = true
		model.position.y = -7.0
		var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var at := ground(player.global_position + side * 6.0)
		em.pos[i] = at
		em.vel[i] = Vector3.ZERO
		global_position = at
		warn_circle(at, TRAVEL_RADIUS, TRAVEL_WARN, func(): _burst_out(at), SAND)
		_total = _t + warn_time(TRAVEL_WARN) + 0.9
	if _t >= _total - 0.9:
		model.position.y = lerpf(model.position.y, 0.0, clampf(dt * 10.0, 0.0, 1.0))
	if _t >= _total:
		model.position.y = 0.0
		_done(0.3)


func _burst_out(at: Vector3) -> void:
	play_sfx("roar", 1.1)
	shake(0.7)
	model.position.y = -2.0
	if player_in_circle(at, TRAVEL_RADIUS) and not airborne():
		hit_player(TRAVEL_DAMAGE, player.global_position - at)
	if fx:
		fx.burst(at + Vector3(0, 1.0, 0), TRAVEL_RADIUS, SAND, 0.6)


# ------------------------------------------------------------------ the Wrath of the Sands

func _start_wrath() -> void:
	_windup = warn_time(WRATH_WARN)
	_total = _windup + 1.5
	model.pose = "raise"
	model.act = 0.0
	play_sfx("roar", 0.8)
	play_sfx("storm", 0.8)
	shake(0.5)
	main.hud.flash_message("WRATH OF THE SANDS! FIND SHELTER!", 3.0)
	_wrath_at = ground(player.global_position)
	warn_circle(_wrath_at, WRATH_RADIUS, WRATH_WARN, _land_wrath)
	# three golden safe spots round you, 9-15 m off
	var a0 := randf() * TAU
	for k in WRATH_SAFE_SPOTS:
		var a := a0 + TAU * k / WRATH_SAFE_SPOTS + randf_range(-0.3, 0.3)
		var at := ground(_wrath_at + Vector3(cos(a), 0, sin(a)) * randf_range(9.0, 15.0))
		var d := GroundDisc.create(1.0, Color(1.0, 0.85, 0.3), false)
		d.alpha = 0.7
		d.set_lift(0.22)
		add_child(d)
		d.global_position = at
		d.scale = Vector3(WRATH_SAFE, 1, WRATH_SAFE)
		_safe.append({"disc": d, "at": at})
	_sphinx_eyes(true)
	_storm_fx = 0.6


func _tick_wrath(dt: float) -> void:
	model.act = clampf(_t / 0.6, 0.0, 1.0)
	model.position.y = lerpf(model.position.y, 1.2 if _t < _windup + 0.6 else 0.0, clampf(dt * 3.0, 0.0, 1.0))
	if _t >= _total:
		model.position.y = 0.0
		_done(0.6)


## Minimap: the Wrath of the Sands' golden safe spots while it's coming (MapBoss API).
func map_safe_zones() -> Array:
	var out: Array = []
	for s in _safe:
		out.append({"pos": s["at"], "radius": WRATH_SAFE})
	return out


func in_safe_spot(p: Vector3) -> bool:
	for s in _safe:
		if flat_dist(p, s["at"]) < WRATH_SAFE:
			return true
	return false


func _land_wrath() -> void:
	play_sfx("storm", 0.6)
	shake(1.0)
	_storm_fx = 1.0
	var pp := player.global_position
	if flat_dist(pp, _wrath_at) < WRATH_RADIUS and not in_safe_spot(pp):
		hit_player(WRATH_DAMAGE, pp - _wrath_at)
		player.apply_slow(0.6, 3.0)
	if fx:
		for k in 14:
			var a := TAU * k / 14.0
			fx.burst(_wrath_at + Vector3(cos(a) * WRATH_RADIUS * 0.6, 1.5, sin(a) * WRATH_RADIUS * 0.6), 6.0, SAND, 0.8)
	for s in _safe:
		(s["disc"] as Node).queue_free()
	_safe.clear()
	get_tree().create_timer(4.0, false).timeout.connect(func():
		_storm_fx = 0.0
		_sphinx_eyes(false))


## The Great Sphinx's eyes blaze (and two beams of light fall from them) while the wrath lasts.
func _sphinx_eyes(on: bool) -> void:
	var sp := main.get_tree().get_first_node_in_group("sphinx") as Node3D
	for b in _eye_beams:
		if is_instance_valid(b):
			b.queue_free()
	_eye_beams.clear()
	if sp == null:
		return
	var mat := sp.get_meta("eye_material", null) as StandardMaterial3D
	if mat != null:
		create_tween().tween_property(mat, "emission_energy_multiplier", 9.0 if on else 0.0, 0.6)
	if on:
		var pts: Array = sp.get_meta("eye_points", [])
		for p in pts:
			var from: Vector3 = sp.global_transform * (p as Vector3)
			var bn := _beam(from, _wrath_at + Vector3(0, 0.5, 0), Color(1.0, 0.8, 0.3), 0.25, WRATH_WARN + 4.0)
			_eye_beams.append(bn)


# ------------------------------------------------------------------ effects

## A glowing beam from `a` to `b` that fades over `life` seconds.
func _beam(a: Vector3, b: Vector3, c: Color, r: float, life: float) -> Node3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = maxf(a.distance_to(b), 0.1)
	cm.radial_segments = 8
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c, 0.85)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	cm.material = m
	mi.mesh = cm
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var mid := (a + b) * 0.5
	var dir := (b - a).normalized()
	var side := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := side.cross(dir).normalized()
	mi.global_transform = Transform3D(Basis(x, dir, x.cross(dir)), mid)
	_beams.append({"node": mi, "t": 0.0, "life": life, "mat": m})
	return mi


## A column of whirling sand (the sandstorm zone).
func _whirl(r: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 160
	p.lifetime = 1.6
	p.preprocess = 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_radius = r * 0.9
	p.emission_ring_inner_radius = r * 0.2
	p.emission_ring_height = 0.5
	p.emission_ring_axis = Vector3.UP
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, 0.5, 0)
	p.tangential_accel_min = 12.0
	p.tangential_accel_max = 18.0
	p.radial_accel_min = -3.0
	p.radial_accel_max = -1.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Abilities._soft_dot()
	q.material = m
	p.mesh = q
	p.color = Color(0.9, 0.72, 0.45, 0.45)
	return p


## A carpet of black scarabs that scurries down a lane.
func _scarab_swarm() -> Node3D:
	var root := Node3D.new()
	root.top_level = true
	var mb := MeshBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = randi()
	for k in 40:
		var at := Vector3(r.randf_range(-SCARAB_WIDTH * 0.5, SCARAB_WIDTH * 0.5), 0.08, r.randf_range(-2.5, 2.5))
		var yaw := r.randf_range(-0.4, 0.4)
		mb.add(MeshBuilder.sphere(0.12, 8, 5), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.8, 0.45, 1.1)), at), Color(0.06, 0.08, 0.1))
		mb.add(MeshBuilder.sphere(0.06, 6, 4), Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, 0, 0.13).rotated(Vector3.UP, yaw)), Color(0.1, 0.12, 0.08))
		mb.add(MeshBuilder.box(Vector3(0.02, 0.02, 0.08)), Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0.02, 0.07, -0.02).rotated(Vector3.UP, yaw)), Color(0.3, 0.6, 0.55))   # iridescent sheen
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	root.add_child(mi)
	return root


func _tick_fx(dt: float) -> void:
	for k in range(_beams.size() - 1, -1, -1):
		var b: Dictionary = _beams[k]
		b["t"] += dt
		var node = b["node"]
		if not is_instance_valid(node) or b["t"] >= b["life"]:
			if is_instance_valid(node):
				(node as Node).queue_free()
			_beams.remove_at(k)
			continue
		var m: StandardMaterial3D = b["mat"]
		m.albedo_color.a = 0.85 * clampf((b["life"] - b["t"]) / 0.3, 0.0, 1.0)
	for k in range(_swarms.size() - 1, -1, -1):
		var s: Dictionary = _swarms[k]
		s["t"] += dt
		var node = s["node"]
		if not is_instance_valid(node):
			_swarms.remove_at(k)
			continue
		var f: float = clampf(s["t"] / 0.7, 0.0, 1.0)
		var p := (s["from"] as Vector3).lerp(s["to"], f)
		(node as Node3D).global_position = ground(p)
		if s["t"] >= 0.9:
			(node as Node).queue_free()
			_swarms.remove_at(k)
	for k in range(_storms.size() - 1, -1, -1):
		var s: Dictionary = _storms[k]
		s["t"] += dt
		var nv = s["node"]
		if not is_instance_valid(nv):
			_storms.remove_at(k)
			continue
		var node := nv as CPUParticles3D
		if s["t"] >= STORM_LIFE - 1.0:
			node.emitting = false
		if s["t"] >= STORM_LIFE + 1.0:
			node.queue_free()
			_storms.remove_at(k)
	if _wind == null:
		_wind = main.find_child("DesertWind", true, false) as DesertWind
	if _wind != null and _wind.storm != _storm_fx:
		_wind.storm = _storm_fx


# ------------------------------------------------------------------ enrage, death, drawing

func _on_enrage() -> void:
	model.set_enrage(1.0)
	var aura := Abilities._flame_particles(0.6, 1.0, 40)
	aura.position = Vector3(0, 1.4, 0)
	aura.emission_sphere_radius = 0.5
	aura.color = Color(1.0, 0.7, 0.25)
	model.add_child(aura)


func _on_die() -> void:
	model.pose = "die"
	model.die_t = 0.0
	play_sfx("roar", 0.65)
	main.hud.flash_message("THE PHARAOH CRUMBLES TO DUST!", 3.0)
	for s in _safe:
		(s["disc"] as Node).queue_free()
	_safe.clear()
	_storm_fx = 0.0
	_sphinx_eyes(false)
	if tomb != null:
		var glow := tomb.get_node_or_null("Glow") as OmniLight3D
		if glow != null:
			create_tween().tween_property(glow, "light_energy", 0.0, 2.0)


func _tick_death(dt: float) -> bool:
	model.die_t = _die_t
	model.position.y = minf(model.position.y, 0.0)
	if _die_t > 1.2 and not has_meta("crashed"):
		set_meta("crashed", true)
		play_sfx("fall")
		shake(0.8)
	if fx and _die_t > 1.4 and fmod(_die_t, 0.3) < dt:   # he crumbles into a heap of sand
		fx.burst(global_position + Vector3(randf_range(-1.5, 1.5), randf_range(0.5, 3.0), randf_range(-1.5, 1.5)), 2.5, SAND, 0.6)
	if _die_t > 4.5:
		model.position.y -= dt * 1.2
	if _die_t > 7.0:
		model.visible = false
		return true
	return false


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
	elif attack != "rise":
		_yaw = rotate_toward(_yaw, atan2(-_aim.x, -_aim.z), 6.0 * dt)
	rotation.y = _yaw
