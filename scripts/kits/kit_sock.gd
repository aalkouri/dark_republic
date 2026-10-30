class_name KitSock
extends KitPart
## An Argyle Sock (built in code: SockBody)
##   1  Spin Cycle    30 s  a whirlwind for 5 s: enemies within 6 m are pulled in and take 40
##                          every 0.5 s
##   2  Lost Pair     50 s  your partner sock fights beside you for 15 s, copying every zap; an
##                          enemy zapped by both of you in one volley takes 2x
##   3  Laundry Day  120 s  a washing machine falls where you aim, sucks in every enemy within
##                          10 m and washes them for 4 s (10% of max HP per second); survivors come
##                          out shrunk for 20 s: smaller, half damage, double damage taken

const SPIN_TIME := 5.0
const SPIN_RADIUS := 6.0
const SPIN_PULL := 5.0              # m/s toward you
const SPIN_DAMAGE := 40.0
const SPIN_EVERY := 0.5
const SPIN_RATE := 26.0             # rad/s the sock whirls at
const PAIR_TIME := 15.0
const PAIR_COLORS := {"a": Color(0.2, 0.36, 0.72), "b": Color(0.95, 0.55, 0.2), "line": Color(0.95, 0.95, 0.95),
	"cuff": Color(0.9, 0.92, 0.95), "toe": Color(0.12, 0.2, 0.45)}
const WASH_RANGE := 30.0
const WASH_RADIUS := 10.0
const WASH_TIME := 4.0
const WASH_FRAC := 0.10             # of max HP per second
const WASH_FALL := 0.7
const SHRINK_TIME := 20.0

var _spin_t := 0.0
var _spin_tick := 0.0
var _spin_fx: Node3D
var _pair: RosterHero
var _pair_t := 0.0
var _machine: Node3D
var _wash_t := -1.0
var _wash_at := Vector3.ZERO
var _washing: Array = []            # uids in the drum
var _wash_tick := 0.0
var spin_hits := 0                  # tests
var washed := 0
var shrunk := 0


func _exit_tree() -> void:
	if is_instance_valid(_pair):
		_pair.queue_free()


func cast(i: int) -> void:
	match i:
		0: _spin()
		1: _lost_pair()
		2: _laundry()


func active(name: String) -> bool:
	match name:
		"spin": return _spin_t > 0.0
		"pair": return _pair_t > 0.0
		"wash": return _wash_t >= 0.0 or is_instance_valid(_machine)
	return false


func tick(dt: float) -> void:
	_tick_spin(dt)
	_tick_pair(dt)
	_tick_wash(dt)


func clone_list() -> Array:
	if _pair_t > 0.0 and is_instance_valid(_pair):
		return [[_pair, _pair.global_position]]
	return []


func clone_damage() -> float:
	return 1.0   # the partner zaps as hard as you do


func _body() -> SockBody:
	var m = player.model
	return m.sock if m is RosterHero else null


# ------------------------------------------------------------------ Spin Cycle

func _spin() -> void:
	play("spin_cycle")
	_spin_t = SPIN_TIME
	_spin_tick = 0.0
	if _body():
		_body().spin_rate = SPIN_RATE
	if not is_instance_valid(_spin_fx):
		_spin_fx = Node3D.new()
		var disc := GroundDisc.create(SPIN_RADIUS, Color(0.85, 0.75, 1.0, 0.25), true)
		disc.set_ring(0.75)
		_spin_fx.add_child(disc)
		var p := particles(0.2, 0.8, 70, Color(1.0, 0.95, 0.75, 0.9), Color(0.6, 0.4, 0.9, 0.0))
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = SPIN_RADIUS * 0.8
		p.emission_ring_inner_radius = 1.0
		p.emission_ring_height = 2.0
		p.position.y = 1.0
		p.orbit_velocity_min = 1.2
		p.orbit_velocity_max = 1.8
		p.radial_accel_min = -6.0
		p.radial_accel_max = -4.0
		_spin_fx.add_child(p)
		spawn(_spin_fx, feet())


func _tick_spin(dt: float) -> void:
	if _spin_t <= 0.0:
		return
	_spin_t -= dt
	var at := feet()
	_spin_fx.global_position = at
	_spin_fx.rotation.y += dt * 6.0
	# The whirlwind drags everything nearby in toward the sock
	for i in near(at, SPIN_RADIUS):
		if enemies.is_boss(i):
			continue
		var to := at - enemies.pos[i]
		to.y = 0.0
		var d := to.length()
		if d > 1.2:
			enemies.pos[i] += to / d * minf(SPIN_PULL * dt, d - 1.2)
	_spin_tick -= dt
	if _spin_tick <= 0.0:
		_spin_tick = SPIN_EVERY
		for i in near(at, SPIN_RADIUS):
			enemies.damage(i, SPIN_DAMAGE * dmg())
			spin_hits += 1
	if _spin_t <= 0.0:
		if _body():
			_body().spin_rate = 0.0
		_spin_fx.queue_free()
		_spin_fx = null


# ------------------------------------------------------------------ Lost Pair

func _lost_pair() -> void:
	play("lost_pair")
	if not is_instance_valid(_pair):
		_pair = RosterHero.create("argyle_sock")
		_pair.sock_colors = PAIR_COLORS
		spawn(_pair, _pair_spot())
		if fx:
			fx.burst(_pair_spot() + Vector3(0, 1.0, 0), 1.6, Color(1.0, 0.95, 0.8), 0.35)
	_pair_t = PAIR_TIME


func _pair_spot() -> Vector3:
	var right := Vector3(cos(player.cam_yaw), 0.0, -sin(player.cam_yaw))
	return ground(feet() + right * 1.8)


func _tick_pair(dt: float) -> void:
	if _pair_t <= 0.0:
		return
	_pair_t -= dt
	var want := _pair_spot()
	var p := _pair.global_position.lerp(want, 1.0 - exp(-6.0 * dt))
	_pair.global_position = p
	_pair.rotation.y = lerp_angle(_pair.rotation.y, player.model.rotation.y, 1.0 - exp(-10.0 * dt))
	_pair.set_motion(Vector2(player.velocity.x, player.velocity.z).length(), not player.is_on_floor())
	if _pair_t <= 0.0:
		if fx:
			fx.burst(_pair.global_position + Vector3(0, 1.0, 0), 1.6, Color(0.6, 0.75, 1.0), 0.35)
		_pair.queue_free()
		_pair = null


# ------------------------------------------------------------------ Laundry Day

func _laundry() -> void:
	play("laundry_day")
	_wash_at = ground(aim_point(WASH_RANGE))
	if is_instance_valid(_machine):
		_machine.queue_free()
	_machine = _make_machine()
	spawn(_machine, _wash_at + Vector3(0, 22.0, 0))
	_machine.rotation.y = randf() * TAU
	var mark := GroundDisc.create(WASH_RADIUS, Color(0.55, 0.85, 1.0, 0.3), true)
	mark.set_ring(0.9)
	spawn(mark, _wash_at)
	var tw := _machine.create_tween()
	tw.tween_property(_machine, "global_position", _wash_at, WASH_FALL).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		mark.queue_free()
		_land_machine())


func _land_machine() -> void:
	player.add_shake(0.7)
	if fx:
		fx.burst(_wash_at + Vector3(0, 0.6, 0), 4.0, Color(0.8, 0.9, 1.0), 0.5)
	ring(_wash_at, WASH_RADIUS, Color(0.6, 0.85, 1.0, 0.8), 0.4)
	_washing.clear()
	for i in near(_wash_at, WASH_RADIUS, true):   # bosses don't fit in the drum
		_washing.append(enemies.uid[i])
		washed += 1
	_wash_t = 0.0
	_wash_tick = 0.0


func _tick_wash(dt: float) -> void:
	if _wash_t < 0.0:
		return
	_wash_t += dt
	# Everything inside goes round and round the drum
	var k2 := 0
	for u in _washing:
		var i := enemies.index_of(u)
		if i < 0:
			continue
		var a := _wash_t * 9.0 + TAU * k2 / maxf(_washing.size(), 1)
		var r := 0.6 + 0.3 * sin(_wash_t * 3.0 + k2)
		enemies.pos[i] = enemies.pos[i].lerp(_wash_at + Vector3(cos(a) * r, 0, sin(a) * r), minf(1.0, dt * 12.0))
		enemies.stun(i, 0.3)
		k2 += 1
	_machine.rotation = Vector3(sin(_wash_t * 40.0) * 0.04, _machine.rotation.y, cos(_wash_t * 37.0) * 0.04)   # the spin cycle
	if randf() < dt * 25.0:
		mote(_wash_at + Vector3(randf_range(-0.8, 0.8), 1.6, randf_range(-0.8, 0.8)), Vector3(randf_range(-1, 1), 2.5, randf_range(-1, 1)), 0.9, Color(0.85, 0.95, 1.0), 0.22)   # suds
	_wash_tick -= dt
	if _wash_tick <= 0.0:
		_wash_tick = 0.25
		for u in _washing:
			var i := enemies.index_of(u)
			if i >= 0:
				enemies.dot_damage(i, enemies.hp_max[i] * WASH_FRAC * 0.25 * enemies.pct_scale(i))
	if _wash_t >= WASH_TIME:
		_wash_t = -1.0
		for u in _washing:   # survivors tumble out, shrunk
			var i := enemies.index_of(u)
			if i < 0:
				continue
			enemies.shrink(i, SHRINK_TIME)
			shrunk += 1
			var out := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
			enemies.knock(i, out, 5.0, 0.3)
		_washing.clear()
		if fx:
			fx.burst(_wash_at + Vector3(0, 1.0, 0), 3.0, Color(0.85, 0.95, 1.0), 0.4)
		var m := _machine
		_machine = null
		var tw := m.create_tween()
		tw.tween_property(m, "scale", Vector3(1.0, 0.05, 1.0), 0.6).set_ease(Tween.EASE_IN)
		tw.tween_callback(m.queue_free)


## A front-loading washing machine: white box, control panel, a round glass door with a
## sudsy drum behind it.
func _make_machine() -> Node3D:
	var root := Node3D.new()
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var white := Color(0.92, 0.93, 0.95, 0)
	var grey := Color(0.55, 0.57, 0.6, 0)
	mb.add(MeshBuilder.box(Vector3(2.4, 2.6, 2.4)), Transform3D(Basis(), Vector3(0, 1.3, 0)), white)
	mb.add(MeshBuilder.box(Vector3(2.42, 0.45, 2.42)), Transform3D(Basis(), Vector3(0, 2.4, 0)), Color(0.82, 0.83, 0.86, 0))
	for x in [-0.7, -0.35, 0.0]:   # dials
		mb.add(MeshBuilder.cyl(0.12, 0.12, 0.08, 10), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(x, 2.4, -1.24)), grey)
	gb.add(MeshBuilder.box(Vector3(0.5, 0.18, 0.03)), Transform3D(Basis(), Vector3(0.6, 2.4, -1.23)), Color(0.4, 0.9, 1.0, 0))   # display
	mb.add(MeshBuilder.cyl(0.85, 0.85, 0.1, 24), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 1.1, -1.22)), grey)   # door rim
	gb.add(MeshBuilder.cyl(0.7, 0.7, 0.06, 24), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 1.1, -1.26)), Color(0.55, 0.8, 1.0, 0))   # sudsy glass
	var mesh := mb.commit(MeshBuilder.prop_material())
	gb.commit_into(mesh, MeshBuilder.glow_material())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	return root
