class_name KitRogue
extends KitPart
## The Rogue
##   1  Smoke Bomb                 25 s  8 m smoke cloud; invisible for 4 s (enemies lose track of
##                                       you); your first attack after it deals 3x damage
##   2  Pickpocket                 40 s  dash 12 m through up to 10 enemies: 70 each, each drops an
##                                       extra XP gem
##   3  Death by a Thousand Cuts  120 s  over 3 s, strike the 20 nearest enemies: 120 each plus a
##                                       bleed; invulnerable throughout, then back where you started

const SMOKE_RADIUS := 8.0
const SMOKE_TIME := 4.0
const AMBUSH_MULT := 3.0
const DASH_RANGE := 12.0
const DASH_TIME := 0.28
const DASH_MAX := 10
const DASH_DAMAGE := 70.0
const DASH_WIDTH := 1.8
const CUTS_TARGETS := 20
const CUTS_TIME := 3.0
const CUTS_RADIUS := 25.0
const CUTS_DAMAGE := 120.0

var _smoke_t := 0.0
var _ambush := false
var _cloud: Node3D
var _dash_t := -1.0
var _dash_from := Vector3.ZERO
var _dash_to := Vector3.ZERO
var _dash_hit := {}
var _cuts_t := -1.0
var _cuts_home := Vector3.ZERO
var _cuts_queue: Array = []         # uids still to strike
var _cuts_next := 0.0
var _cuts_step := 0.15


func cast(i: int) -> void:
	match i:
		0: _smoke_bomb()
		1: _pickpocket()
		2: _thousand_cuts()


func active(name: String) -> bool:
	match name:
		"smoke": return _smoke_t > 0.0
		"ambush": return _ambush
		"dash": return _dash_t >= 0.0
		"cuts": return _cuts_t >= 0.0
	return false


func weapon_mult() -> float:
	return AMBUSH_MULT if _ambush else 1.0


func weapon_fired() -> void:
	if _ambush:
		_ambush = false
		fx.burst(chest(), 1.5, k._main, 0.25)


func tick(dt: float) -> void:
	_tick_smoke(dt)
	_tick_dash(dt)
	_tick_cuts(dt)


# ------------------------------------------------------------------ Smoke Bomb

func _smoke_bomb() -> void:
	play("smoke_bomb")
	if _smoke_t <= 0.0:
		enemies.lost = true
		player.dim_mult = 0.25
	_smoke_t = SMOKE_TIME
	_ambush = true
	if is_instance_valid(_cloud):
		_cloud.queue_free()
	_cloud = Node3D.new()
	spawn(_cloud, feet())
	var smoke := particles(2.2, 3.5, 120, Color(0.55, 0.58, 0.55, 0.55), Color(0.3, 0.32, 0.3, 0.0))
	((smoke.mesh as QuadMesh).material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = SMOKE_RADIUS * 0.6
	smoke.scale = Vector3(1, 0.35, 1)
	smoke.gravity = Vector3(0, 0.3, 0)
	smoke.initial_velocity_min = 0.2
	smoke.initial_velocity_max = 1.0
	smoke.position.y = 1.2
	smoke.preprocess = 0.6
	_cloud.add_child(smoke)
	fx.burst(feet() + Vector3(0, 0.8, 0), SMOKE_RADIUS * 0.5, Color(0.6, 0.62, 0.6), 0.4)
	# Every goblin near you forgets where you were
	for i in near(feet(), SMOKE_RADIUS):
		enemies.knock(i, enemies.pos[i] - feet(), 1.5, 0.2)


func _tick_smoke(dt: float) -> void:
	if _smoke_t <= 0.0:
		return
	_smoke_t -= dt
	if _smoke_t <= 0.0:
		enemies.lost = false
		player.dim_mult = 1.0
		if is_instance_valid(_cloud):
			var p := _cloud.get_child(0) as CPUParticles3D
			p.emitting = false
			get_tree().create_timer(3.5).timeout.connect(_cloud.queue_free)
		_cloud = null


# ------------------------------------------------------------------ Pickpocket

func _pickpocket() -> void:
	play("pickpocket")
	var to := aim_point(DASH_RANGE) - feet()
	to.y = 0.0
	var dir := to.normalized() if to.length() > 1.0 else aim_dir()
	_dash_from = feet()
	_dash_to = ground(_dash_from + dir * DASH_RANGE)
	# Don't dash into a wall: stop short of the first thing in the way
	var q := PhysicsRayQueryParameters3D.create(_dash_from + Vector3(0, 1.0, 0), _dash_to + Vector3(0, 1.0, 0))
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_dash_to = ground(_dash_from.lerp(_dash_to, maxf(0.0, (_dash_from.distance_to(hit["position"]) - 0.8) / DASH_RANGE)))
	_dash_t = 0.0
	_dash_hit = {}
	begin_scripted()
	player.invuln = maxf(player.invuln, DASH_TIME + 0.15)


func _tick_dash(dt: float) -> void:
	if _dash_t < 0.0:
		return
	_dash_t += dt / DASH_TIME
	var t := minf(_dash_t, 1.0)
	var p := _dash_from.lerp(_dash_to, t)
	player.global_position = p
	player.velocity = (_dash_to - _dash_from) / DASH_TIME
	mote(p + Vector3(0, 1.0, 0), Vector3.ZERO, 0.35, k._main, 0.3, false, 0.0)
	var d := DASH_DAMAGE * dmg()
	for i in near(p, DASH_WIDTH):
		if _dash_hit.size() >= DASH_MAX:
			break
		var u := enemies.uid[i]
		if _dash_hit.has(u):
			continue
		_dash_hit[u] = true
		var xp := enemies.t_xp[enemies.typ[i]]
		var at := enemies.pos[i]
		enemies.damage(i, d)
		k.drop_xp.emit(at, xp)   # helped himself
		fx.burst(enemies.center_of(i), 0.8, Color(1.0, 0.85, 0.3), 0.2)
	if _dash_t >= 1.0:
		_dash_t = -1.0
		end_scripted(_dash_to)


# ------------------------------------------------------------------ Death by a Thousand Cuts

func _thousand_cuts() -> void:
	play("thousand_cuts")
	_cuts_home = feet()
	_cuts_queue.clear()
	for i in enemies.nearest_k(feet(), CUTS_RADIUS, CUTS_TARGETS):
		_cuts_queue.append(enemies.uid[i])
	_cuts_step = CUTS_TIME / maxf(1.0, _cuts_queue.size() + 1)
	_cuts_t = 0.0
	_cuts_next = 0.0
	begin_scripted()
	player.invuln = maxf(player.invuln, CUTS_TIME + 0.3)
	player.dim_mult = 0.6


func _tick_cuts(dt: float) -> void:
	if _cuts_t < 0.0:
		return
	_cuts_t += dt
	player.invuln = maxf(player.invuln, 0.3)
	_cuts_next -= dt
	if _cuts_next <= 0.0:
		_cuts_next = _cuts_step
		var i := -1
		while i < 0 and not _cuts_queue.is_empty():
			i = enemies.index_of(_cuts_queue.pop_front())
		if i < 0:   # everyone struck: home again
			_cuts_t = -1.0
			player.dim_mult = 1.0
			fx.burst(_cuts_home + Vector3(0, 1, 0), 2.0, k._main, 0.3)
			end_scripted(_cuts_home)
			return
		# Blink to the far side of the target and cut
		var from := feet()
		var ep := enemies.pos[i]
		var through := ep - from
		through.y = 0.0
		var dir := through.normalized() if through.length() > 0.1 else aim_dir()
		var at := ground(ep + dir * (enemies.t_radius[enemies.typ[i]] * enemies.sz[i] + 0.7))
		for m in 5:   # afterimage streak
			mote(from.lerp(at, m / 5.0) + Vector3(0, 1.0, 0), Vector3.ZERO, 0.3, k._main, 0.25, false, 0.0)
		player.global_position = at
		player.velocity = -dir
		player.model.attack(enemies.center_of(i))
		enemies.damage(i, CUTS_DAMAGE * dmg(), dir * 4.0)
		enemies.afflict(i, WeaponSystem.BLEED_FRAC, WeaponSystem.BLEED_TIME)
		if k.weapons:
			k.weapons._sector(ep + Vector3(0, 0.9, 0), dir.rotated(Vector3.UP, randf_range(-0.5, 0.5)), 1.8, 90.0, Color(0.85, 1.0, 0.7, 0.8), 0.18, randf_range(-0.8, 0.8))
		play("cut", -4.0)
