class_name KitSinge
extends KitPart
## Singe (SingeBody: the Ashen Caldera boss's body back at his own little size)
##   1  Scorch Trail      25 s  +30% move speed for 6 s, leaving burning scorch marks behind him
##                              that last 4 s; enemies on them take 15 and burn for 5% of max HP
##                              a second for 3 s
##   2  Lava Cannonball   45 s  he tucks into a ball of coals and dives up to 18 m where you aim
##                              (untouchable in the air), crashing down for 150 within 6 m and
##                              leaving a lava pool for 3 s (4% of max HP a second)
##   3  Caldera Eruption 120 s  the ground cracks open round him and lava bombs rain down for 6 s:
##                              36 bombs within 22 m (most on enemies), each 110 within 3.5 m and a
##                              burn (4% of max HP a second for 3 s)
## Burns are EnemyManager.afflict (a % of max HP over time), like the Rogue's bleeds.
## Levels: the scorch marks' damage; the cannonball's damage; each bomb's damage.

const TRAIL_TIME := 6.0
const TRAIL_SPEED := 1.3
const TRAIL_STEP := 0.9              # metres between scorch marks
const TRAIL_LIFE := 4.0
const TRAIL_RADIUS := 1.3
const TRAIL_DAMAGE := 15.0
const TRAIL_BURN := 0.05             # of max HP per second...
const TRAIL_BURN_TIME := 3.0         # ...for 3 s
const TRAIL_REHIT := 0.5             # the same enemy takes the touch damage again after this long
const TRAIL_MAX := 40
const BALL_RANGE := 18.0
const BALL_TIME := 0.8
const BALL_HEIGHT := 5.0
const BALL_DAMAGE := 150.0
const BALL_RADIUS := 6.0
const POOL_RADIUS := 4.0
const POOL_TIME := 3.0
const POOL_BURN := 0.04
const ERUPT_TIME := 6.0
const ERUPT_RADIUS := 22.0
const ERUPT_BOMBS := 36
const BOMB_DAMAGE := 110.0
const BOMB_RADIUS := 3.5
const BOMB_FALL := 0.7
const BOMB_BURN := 0.04
const BOMB_BURN_TIME := 3.0
const BOMB_AIMED := 0.7              # this share of the bombs go for an enemy
const EMBER := Color(1.0, 0.45, 0.1)
const LAVA := Color(1.0, 0.55, 0.12)
const CHAR := Color(0.05, 0.035, 0.03)

var _trail_t := 0.0
var _trail_last := Vector3.INF
var _marks: Array = []               # {pos, t, nodes}
var _trail_tick := 0.0
var _touched := {}                   # uid -> time of its last touch damage
var _time := 0.0
var _trail_fx: CPUParticles3D
var _ball_t := -1.0
var _ball_from := Vector3.ZERO
var _ball_to := Vector3.ZERO
var _ball_marker: GroundDisc
var _pool_t := 0.0
var _pool_at := Vector3.ZERO
var _pool_tick := 0.0
var _pool_nodes: Array = []
var _erupt_t := 0.0
var _erupt_next := 0.0
var _erupt_left := 0
var _erupt_at := Vector3.ZERO
var _erupt_nodes: Array = []
var _bombs: Array = []               # {node, from, to, t}
var _bomb_mesh: SphereMesh
var trail_marks := 0                 # tests
var trail_hits := 0
var ball_hits := 0
var pool_hits := 0
var bombs_landed := 0
var bomb_hits := 0


func _exit_tree() -> void:
	if _trail_t > 0.0:
		stats.apply("move_speed", "mult", 1.0 / TRAIL_SPEED)
		_trail_t = 0.0
	for m in _marks:
		for n in m["nodes"]:
			if is_instance_valid(n):
				(n as Node).queue_free()
	for b in _bombs:
		if is_instance_valid(b["node"]):
			(b["node"] as Node).queue_free()
	for n in _pool_nodes + _erupt_nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_marks.clear()
	_bombs.clear()


func cast(i: int) -> void:
	src(i)
	match i:
		0: _scorch_trail()
		1: _cannonball()
		2: _eruption()


func active(name: String) -> bool:
	match name:
		"trail": return _trail_t > 0.0
		"ball": return _ball_t >= 0.0
		"pool": return _pool_t > 0.0
		"eruption": return _erupt_t > 0.0 or not _bombs.is_empty()
	return false


func tick(dt: float) -> void:
	_time += dt
	src(0)
	_tick_trail(dt)
	src(1)
	_tick_ball(dt)
	_tick_pool(dt)
	src(2)
	_tick_eruption(dt)


func _body() -> SingeBody:
	var h := player.model as RosterHero
	return h.boss as SingeBody if h != null and h.boss is SingeBody else null


func _floor(p: Vector3) -> Vector3:
	return Vector3(p.x, SwampWater.height_at(p.x, p.z), p.z) if SwampWater.current != null else ground(p)


func _burn_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = LAVA
	m.emission_enabled = true
	m.emission = LAVA
	m.emission_energy_multiplier = 3.0
	return m


# ------------------------------------------------------------------ Scorch Trail

func _scorch_trail() -> void:
	play("scorch_trail")
	if _trail_t <= 0.0:
		stats.apply("move_speed", "mult", TRAIL_SPEED)
	_trail_t = TRAIL_TIME
	_trail_last = Vector3.INF
	if not is_instance_valid(_trail_fx):   # flames licking up off his heels
		_trail_fx = particles(0.32, 0.6, 40, Color(1.0, 0.8, 0.3, 0.95), Color(0.8, 0.15, 0.02, 0.0))
		_trail_fx.local_coords = false
		_trail_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_trail_fx.emission_sphere_radius = 0.35
		_trail_fx.gravity = Vector3(0, 2.5, 0)
		_trail_fx.position.y = 0.2
		player.add_child(_trail_fx)
	_trail_fx.emitting = true
	ring(feet(), 3.0, Color(EMBER, 0.8), 0.3)


func _tick_trail(dt: float) -> void:
	if _trail_t > 0.0:
		_trail_t -= dt
		var p := feet()
		if _trail_last == Vector3.INF or p.distance_to(_trail_last) >= TRAIL_STEP:
			_trail_last = p
			if player.is_on_floor():
				_add_mark(_floor(p))
		if _trail_t <= 0.0:
			stats.apply("move_speed", "mult", 1.0 / TRAIL_SPEED)
			if is_instance_valid(_trail_fx):
				_trail_fx.emitting = false
	# Marks burn out after TRAIL_LIFE
	for n in range(_marks.size() - 1, -1, -1):
		var m: Dictionary = _marks[n]
		m["t"] = float(m["t"]) - dt
		var f := clampf(float(m["t"]) / 1.0, 0.0, 1.0)
		var glow: GroundDisc = m["nodes"][1]
		if is_instance_valid(glow):
			glow.alpha = 0.55 * f * (0.8 + 0.2 * sin(_time * 9.0 + n))
		if float(m["t"]) <= 0.0:
			for node in m["nodes"]:
				if is_instance_valid(node):
					var nd := node as Node3D
					var tw := nd.create_tween()
					tw.tween_property(nd, "scale", Vector3(0.01, 1, 0.01), 0.4)
					tw.tween_callback(nd.queue_free)
			_marks.remove_at(n)
	if _marks.is_empty():
		return
	_trail_tick -= dt
	if _trail_tick > 0.0:
		return
	_trail_tick = 0.15
	var d := TRAIL_DAMAGE * dmg() * pw(0)
	for m in _marks:
		for i in near(m["pos"], TRAIL_RADIUS + 0.4):
			var u: int = enemies.uid[i]
			enemies.afflict(i, TRAIL_BURN, TRAIL_BURN_TIME)
			if _time - float(_touched.get(u, -99.0)) >= TRAIL_REHIT:
				_touched[u] = _time
				enemies.damage(i, d)
				trail_hits += 1


func _add_mark(at: Vector3) -> void:
	if _marks.size() >= TRAIL_MAX:   # the oldest goes out
		var old: Dictionary = _marks.pop_front()
		for node in old["nodes"]:
			if is_instance_valid(node):
				(node as Node).queue_free()
	var charm := GroundDisc.create(TRAIL_RADIUS, Color(CHAR, 0.85))
	charm.set_lift(0.05)
	spawn(charm, at)
	charm.rotation.y = randf() * TAU
	var glow := GroundDisc.create(TRAIL_RADIUS * 0.75, Color(EMBER, 0.55), true)
	glow.set_lift(0.06)
	glow.set_ring(0.35)
	spawn(glow, at)
	_marks.append({"pos": at, "t": TRAIL_LIFE, "nodes": [charm, glow]})
	trail_marks += 1
	if randf() < 0.5:
		mote(at + Vector3(0, 0.2, 0), Vector3(randf_range(-0.5, 0.5), randf_range(1.5, 3.0), randf_range(-0.5, 0.5)), 0.7, EMBER, 0.18)


# ------------------------------------------------------------------ Lava Cannonball

func _cannonball() -> void:
	play("lava_cannonball")
	_ball_from = feet()
	_ball_to = aim_point(BALL_RANGE)
	_ball_t = 0.0
	begin_scripted()
	player.invuln = maxf(player.invuln, BALL_TIME + 0.2)
	var b := _body()
	if b:
		b.set_curl(true)
	_ball_marker = GroundDisc.create(BALL_RADIUS, Color(LAVA, 0.3), true)
	_ball_marker.set_ring(0.85)
	spawn(_ball_marker, _ball_to)
	for m in 12:   # sparks thrown off as he springs
		mote(_ball_from + Vector3(0, 0.4, 0), Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3)), 0.5, EMBER, 0.2)


func _tick_ball(dt: float) -> void:
	if _ball_t < 0.0:
		return
	_ball_t += dt / BALL_TIME
	var t := minf(_ball_t, 1.0)
	var p := _ball_from.lerp(_ball_to, t) + Vector3(0, 4.0 * t * (1.0 - t) * BALL_HEIGHT, 0)
	player.velocity = (_ball_to - _ball_from).normalized() * 10.0
	player.global_position = p
	if is_instance_valid(_ball_marker):
		_ball_marker.set_fill(t)
	if randf() < dt * 40.0:   # a trail of embers behind the ball
		mote(p + Vector3(0, 0.6, 0), Vector3(randf_range(-1, 1), randf_range(0.5, 2), randf_range(-1, 1)), 0.6, EMBER, 0.25)
	if _ball_t >= 1.0:
		_ball_t = -1.0
		end_scripted(_ball_to)
		var b := _body()
		if b:
			b.set_curl(false)
		_ball_land(_ball_to)


func _ball_land(at: Vector3) -> void:
	if is_instance_valid(_ball_marker):
		_ball_marker.queue_free()
	var d := BALL_DAMAGE * dmg() * pw(1)
	for i in near(at, BALL_RADIUS):
		enemies.damage(i, d)
		enemies.knock(i, enemies.pos[i] - at, 3.0, 0.2)
		ball_hits += 1
	ring(at, BALL_RADIUS, Color(LAVA, 0.85), 0.4)
	ring(at, BALL_RADIUS * 0.55, Color(1.0, 0.85, 0.4, 0.8), 0.3)
	if fx:
		fx.burst(at + Vector3(0, 0.5, 0), BALL_RADIUS * 0.5, EMBER, 0.4)
	for m in 30:   # lava splashing out
		var a := randf() * TAU
		mote(at + Vector3(0, 0.3, 0), Vector3(cos(a) * randf_range(3, 9), randf_range(3, 8), sin(a) * randf_range(3, 9)), 0.8, LAVA if m % 3 else Color(1.0, 0.9, 0.5), 0.28, false, 14.0)
	flash_light(at + Vector3(0, 1.5, 0), EMBER, 5.0, 12.0, 0.6)
	player.add_shake(0.7)
	play("cannonball_land", 1.0)
	_lava_pool(at)


func _lava_pool(at: Vector3) -> void:
	for n in _pool_nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_pool_nodes.clear()
	_pool_at = at
	_pool_t = POOL_TIME
	_pool_tick = 0.0
	var crust := GroundDisc.create(POOL_RADIUS * 1.15, Color(0.12, 0.05, 0.03, 0.85))
	crust.set_lift(0.05)
	spawn(crust, at)
	var lava := GroundDisc.create(POOL_RADIUS, Color(LAVA, 0.75), true)
	lava.set_lift(0.07)
	spawn(lava, at)
	var steam := particles(0.4, 1.0, 24, Color(1.0, 0.7, 0.3, 0.8), Color(0.5, 0.15, 0.05, 0.0))
	steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	steam.emission_sphere_radius = POOL_RADIUS * 0.7
	steam.gravity = Vector3(0, 1.8, 0)
	spawn(steam, at + Vector3(0, 0.2, 0))
	_pool_nodes = [crust, lava, steam]


func _tick_pool(dt: float) -> void:
	if _pool_t <= 0.0:
		return
	_pool_t -= dt
	if _pool_nodes.size() > 1 and is_instance_valid(_pool_nodes[1]):
		(_pool_nodes[1] as GroundDisc).alpha = 0.75 * clampf(_pool_t / 0.6, 0.0, 1.0) * (0.85 + 0.15 * sin(_time * 7.0))
	_pool_tick -= dt
	if _pool_tick <= 0.0:
		_pool_tick = 0.25
		for i in near(_pool_at, POOL_RADIUS):
			enemies.afflict(i, POOL_BURN, 0.5)
			pool_hits += 1
	if _pool_t <= 0.0:
		for n in _pool_nodes:
			if is_instance_valid(n):
				var nd := n as Node3D
				var tw := nd.create_tween()
				tw.tween_property(nd, "scale", Vector3(0.01, 1, 0.01), 0.5)
				tw.tween_callback(nd.queue_free)
		_pool_nodes.clear()


# ------------------------------------------------------------------ Caldera Eruption

func _eruption() -> void:
	play("caldera_eruption")
	for n in _erupt_nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_erupt_nodes.clear()
	_erupt_at = feet()
	_erupt_t = ERUPT_TIME
	_erupt_left = ERUPT_BOMBS
	_erupt_next = 0.35
	# The ground cracks open round him, glowing
	var cracks := GroundDisc.create(ERUPT_RADIUS, Color(1.0, 0.35, 0.06, 0.0), true)
	cracks.set_lift(0.05)
	spawn(cracks, _erupt_at)
	var rim := GroundDisc.create(ERUPT_RADIUS, Color(1.0, 0.5, 0.1, 0.0), true)
	rim.set_ring(0.94)
	rim.set_lift(0.06)
	spawn(rim, _erupt_at)
	var smoke := particles(1.6, 2.2, 60, Color(0.3, 0.22, 0.2, 0.55), Color(0.1, 0.08, 0.08, 0.0))
	((smoke.mesh as QuadMesh).material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 1.5
	smoke.gravity = Vector3(0, 4.0, 0)
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 5.0
	spawn(smoke, _erupt_at + Vector3(0, 1.0, 0))
	var fire := particles(0.5, 0.9, 50, Color(1.0, 0.85, 0.35, 1.0), Color(0.9, 0.2, 0.02, 0.0))
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	fire.emission_ring_axis = Vector3.UP
	fire.emission_ring_radius = ERUPT_RADIUS
	fire.emission_ring_inner_radius = 2.0
	fire.emission_ring_height = 0.2
	fire.gravity = Vector3(0, 3.0, 0)
	spawn(fire, _erupt_at + Vector3(0, 0.2, 0))
	_erupt_nodes = [cracks, rim, smoke, fire]
	ring(_erupt_at, ERUPT_RADIUS, Color(LAVA, 0.8), 0.6)
	flash_light(_erupt_at + Vector3(0, 3, 0), EMBER, 5.0, ERUPT_RADIUS, 1.2)
	player.add_shake(0.6)


func _tick_eruption(dt: float) -> void:
	if _erupt_t > 0.0:
		_erupt_t -= dt
		var t := ERUPT_TIME - _erupt_t
		var a := clampf(t / 0.4, 0.0, 1.0) * clampf(_erupt_t / 0.8, 0.0, 1.0)
		if _erupt_nodes.size() > 1:
			if is_instance_valid(_erupt_nodes[0]):
				(_erupt_nodes[0] as GroundDisc).alpha = 0.16 * a * (0.8 + 0.2 * sin(t * 6.0))
			if is_instance_valid(_erupt_nodes[1]):
				(_erupt_nodes[1] as GroundDisc).alpha = 0.6 * a
		_erupt_next -= dt
		while _erupt_next <= 0.0 and _erupt_left > 0:
			_erupt_next += (ERUPT_TIME - 0.9) / ERUPT_BOMBS
			_erupt_left -= 1
			_throw_bomb()
		if _erupt_t <= 0.0:
			for n in _erupt_nodes:
				if is_instance_valid(n):
					if n is CPUParticles3D:
						(n as CPUParticles3D).emitting = false
						get_tree().create_timer(2.5).timeout.connect((n as Node).queue_free)
					else:
						(n as Node).queue_free()
			_erupt_nodes.clear()
	for n in range(_bombs.size() - 1, -1, -1):
		var b: Dictionary = _bombs[n]
		b["t"] = float(b["t"]) + dt / BOMB_FALL
		var t: float = b["t"]
		var node: Node3D = b["node"]
		var from: Vector3 = b["from"]
		var to: Vector3 = b["to"]
		if is_instance_valid(node):
			node.global_position = from.lerp(to, t) + Vector3(0, 4.0 * t * (1.0 - t) * 6.0, 0)
			node.rotation += Vector3(dt * 7.0, dt * 5.0, 0)
		if t >= 1.0:
			_bomb_land(to)
			if is_instance_valid(node):
				node.queue_free()
			_bombs.remove_at(n)


## One lava bomb, flung up out of the cracks and down on an enemy (or somewhere near).
func _throw_bomb() -> void:
	var at := feet()
	var to := Vector3.ZERO
	var pool := near(at, ERUPT_RADIUS)
	if not pool.is_empty() and randf() < BOMB_AIMED:
		var i := pool[randi() % pool.size()]
		to = _floor(enemies.pos[i])
	else:
		var a := randf() * TAU
		var r := sqrt(randf()) * ERUPT_RADIUS
		to = _floor(at + Vector3(cos(a), 0, sin(a)) * maxf(r, 3.0))
	if _bomb_mesh == null:
		_bomb_mesh = SphereMesh.new()
		_bomb_mesh.radius = 0.38
		_bomb_mesh.height = 0.7
		_bomb_mesh.radial_segments = 8
		_bomb_mesh.rings = 4
		_bomb_mesh.material = _burn_mat()
	var mi := MeshInstance3D.new()
	mi.mesh = _bomb_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trail := particles(0.3, 0.4, 14, Color(1.0, 0.7, 0.25, 0.9), Color(0.4, 0.1, 0.05, 0.0))
	trail.local_coords = false
	mi.add_child(trail)
	var from := at + Vector3(randf_range(-1.5, 1.5), 1.0, randf_range(-1.5, 1.5))
	spawn(mi, from)
	_bombs.append({"node": mi, "from": from, "to": to, "t": 0.0})


func _bomb_land(at: Vector3) -> void:
	bombs_landed += 1
	var d := BOMB_DAMAGE * dmg() * pw(2)
	for i in near(at, BOMB_RADIUS):
		enemies.damage(i, d)
		enemies.afflict(i, BOMB_BURN, BOMB_BURN_TIME)
		bomb_hits += 1
	ring(at, BOMB_RADIUS, Color(LAVA, 0.8), 0.3)
	var scorch := GroundDisc.create(BOMB_RADIUS * 0.6, Color(CHAR, 0.8))
	scorch.set_lift(0.04)
	spawn(scorch, at)
	var tw := scorch.create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(scorch, "alpha", 0.0, 1.0)
	tw.tween_callback(scorch.queue_free)
	for m in 8:
		var a := randf() * TAU
		mote(at + Vector3(0, 0.3, 0), Vector3(cos(a) * randf_range(2, 5), randf_range(3, 6), sin(a) * randf_range(2, 5)), 0.6, LAVA, 0.22, false, 14.0)
	if bombs_landed % 3 == 0:
		play("lava_bomb", -4.0)
		player.add_shake(0.15)
