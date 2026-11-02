class_name KitNecromancer
extends KitPart
## The Necromancer (NecromancerBody: the Graveyard boss's body at player size)
##   1  Raise the Dead    30 s  up to 8 of the dead (fresh corpses first, then older dead clawing
##                              up out of the ground) rise and fight for him for 12 s, 18 a hit
##   2  Soul Drain        45 s  a green beam from his staff drains everything in a 16 m line for
##                              4 s: 40 a second; he heals 20% of what it does (up to 4% of max HP
##                              a second). The beam follows where you aim.
##   3  The Graves Open  120 s  graves burst open under every enemy within 25 m: bone spikes for
##                              300 and rooted for 1.5 s; then up to 16 of the dead rise and fight
##                              for him for 10 s
## The risen dead are AllyCrowd allies (the Dark Wizard's Raise Dead), glowing grave-green.
## Levels: the risen dead's hits; the drain's damage; the spikes' damage.

const RAISE_COUNT := 8
const RAISE_TIME := 12.0
const RAISE_HIT := 18.0
const RAISE_REACH := 25.0            # corpses this close can rise
const DRAIN_TIME := 4.0
const DRAIN_RANGE := 16.0
const DRAIN_WIDTH := 2.4
const DRAIN_DPS := 40.0
const DRAIN_TICK := 0.25
const DRAIN_HEAL := 0.2              # of the damage it does...
const DRAIN_HEAL_CAP := 0.04         # ...up to this much of max HP a second
const GRAVES_RADIUS := 25.0
const GRAVES_DAMAGE := 300.0
const GRAVES_ROOT := 1.5
const GRAVES_DELAY := 0.55           # the ground cracks, then the spikes burst
const GRAVES_RISE := 1.3             # ...and then the dead rise
const GRAVES_DEAD := 16
const GRAVES_DEAD_TIME := 10.0
const GRAVES_SPIKES := 90            # bone spikes drawn at most
const SOUL := Color(0.4, 1.0, 0.55)
const BONE := Color(0.86, 0.82, 0.7)
const DEAD_TINT := Color(0.2, 0.75, 0.4)

var dead: AllyCrowd
var _drain_t := 0.0
var _drain_tick := 0.0
var _drain_beam: MeshInstance3D
var _drain_core: MeshInstance3D
var _drain_end := Vector3.ZERO
var _graves: Array[Vector3] = []     # where the graves opened (the dead rise there)
var _spikes: Array = []              # {node, t}
var raise_count := 0                 # tests
var drain_hits := 0
var drain_healed := 0.0
var graves_hits := 0
var graves_raised := 0


func _ready() -> void:
	dead = AllyCrowd.new()
	dead.enemies = enemies
	dead.tint = DEAD_TINT
	dead.glow = Color(0.25, 1.0, 0.45)
	add_child(dead)


func _exit_tree() -> void:
	for n in [_drain_beam, _drain_core]:
		if is_instance_valid(n):
			(n as Node).queue_free()
	for s in _spikes:
		if is_instance_valid(s["node"]):
			(s["node"] as Node).queue_free()
	_spikes.clear()


func cast(i: int) -> void:
	src(i)
	match i:
		0: _raise_dead()
		1: _soul_drain()
		2: _graves_open()


func active(name: String) -> bool:
	match name:
		"drain": return _drain_t > 0.0
		"dead": return dead != null and dead.count() > 0
	return false


func tick(dt: float) -> void:
	src(1)
	_tick_drain(dt)
	src(0)
	if dead:
		dead.tick(dt, dmg() * pw(0) * RAISE_HIT / RosterKit.RAISE_HIT)
	_tick_spikes(dt)


func _body() -> NecromancerBody:
	var h := player.model as RosterHero
	return h.boss as NecromancerBody if h != null and h.boss is NecromancerBody else null


func _floor(p: Vector3) -> Vector3:
	return Vector3(p.x, SwampWater.height_at(p.x, p.z), p.z) if SwampWater.current != null else ground(p)


# ------------------------------------------------------------------ Raise the Dead

func _raise_dead() -> void:
	play("necro_raise")
	var at := feet()
	var spots: Array = k.corpses.take_recent(at, RAISE_REACH, RAISE_COUNT) if k.corpses else []
	while spots.size() < RAISE_COUNT:   # not enough fresh bodies: older dead claw up out of the ground
		var a := randf() * TAU
		var r := randf_range(2.5, 8.0)
		spots.append(at + Vector3(cos(a) * r, 0, sin(a) * r))
	for n in RAISE_COUNT:
		var p := _floor(spots[n] as Vector3)
		dead.add(p, RAISE_TIME, n * 0.06)
		raise_count += 1
		_grave_mark(p, 1.1, n * 0.06)
		for m in 5:
			mote(p + Vector3(0, 0.2, 0), Vector3(randf_range(-1, 1), randf_range(2, 4), randf_range(-1, 1)), 0.9, SOUL, 0.22)
	ring(at, 9.0, Color(SOUL, 0.7), 0.5)
	flash_light(at + Vector3(0, 2, 0), SOUL, 2.5, 12.0, 0.6)


## A grave opening: a dark, green-lit pit of cracked earth that fades after a while.
func _grave_mark(at: Vector3, r: float, delay := 0.0) -> void:
	var pit := GroundDisc.create(r, Color(0.05, 0.08, 0.05, 0.85))
	pit.set_lift(0.05)
	spawn(pit, at)
	var glow := GroundDisc.create(r * 1.5, Color(SOUL, 0.35), true)
	glow.set_lift(0.06)
	glow.set_ring(0.55)
	spawn(glow, at)
	pit.scale = Vector3(0.01, 1, 0.01)
	glow.scale = Vector3(0.01, 1, 0.01)
	var tw := pit.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(pit, "scale", Vector3.ONE, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.0)
	tw.tween_property(pit, "alpha", 0.0, 1.5)
	tw.tween_callback(pit.queue_free)
	var tg := glow.create_tween()
	tg.tween_interval(delay)
	tg.tween_property(glow, "scale", Vector3.ONE, 0.25).set_ease(Tween.EASE_OUT)
	tg.tween_property(glow, "alpha", 0.0, 1.2)
	tg.tween_callback(glow.queue_free)


# ------------------------------------------------------------------ Soul Drain

func _soul_drain() -> void:
	play("soul_drain")
	_drain_t = DRAIN_TIME
	_drain_tick = 0.0
	var b := _body()
	if b:
		b.hold(DRAIN_TIME)
	if not is_instance_valid(_drain_beam):
		_drain_beam = _beam_mesh(0.42, Color(SOUL, 0.5))
		_drain_core = _beam_mesh(0.13, Color(0.85, 1.0, 0.9, 0.95))


func _beam_mesh(r: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.material = glow_mat(c)
	mi.mesh = cyl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spawn(mi, feet())
	return mi


func _tick_drain(dt: float) -> void:
	if _drain_t <= 0.0:
		return
	_drain_t -= dt
	var from := feet()
	var dir := aim_dir()
	var tip := player.model.staff_tip() if player.model != null else chest() + Vector3(0, 0.8, 0)
	_drain_end = from + dir * DRAIN_RANGE + Vector3(0, 1.0, 0)
	var wob := 1.0 + 0.15 * sin(_drain_t * 30.0)
	for n in [[_drain_beam, wob], [_drain_core, 1.0]]:
		var mi: MeshInstance3D = n[0]
		if not is_instance_valid(mi):
			continue
		var len := tip.distance_to(_drain_end)
		mi.global_position = (tip + _drain_end) * 0.5
		mi.look_at(_drain_end, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		mi.scale = Vector3(float(n[1]), len, float(n[1]))
	_drain_tick -= dt
	if _drain_tick <= 0.0:
		_drain_tick = DRAIN_TICK
		var d := DRAIN_DPS * DRAIN_TICK * dmg() * pw(1)
		var dealt := 0.0
		for i in near(from + dir * DRAIN_RANGE * 0.5, DRAIN_RANGE * 0.5 + 2.0):
			var off := enemies.pos[i] - from
			off.y = 0.0
			var along := off.dot(dir)
			var side := (off - dir * along).length()
			if along < 0.0 or along > DRAIN_RANGE or side > DRAIN_WIDTH * 0.5 + enemies.t_radius[enemies.typ[i]] * enemies.sz[i]:
				continue
			var hp0 := enemies.hp[i]
			enemies.damage(i, d)
			dealt += minf(hp0, d)
			drain_hits += 1
			if randf() < 0.6:   # their souls stream back along the beam to him
				mote(enemies.center_of(i), Vector3(0, 1.5, 0), 1.2, SOUL, 0.28, true)
		var heal := minf(dealt * DRAIN_HEAL, player.max_hp * DRAIN_HEAL_CAP * DRAIN_TICK)
		if heal > 0.0:
			var before := player.hp
			k.heal_pct(heal / player.max_hp)
			drain_healed += player.hp - before
	if _drain_t <= 0.0:
		for mi in [_drain_beam, _drain_core]:
			if is_instance_valid(mi):
				var m: StandardMaterial3D = ((mi as MeshInstance3D).mesh as CylinderMesh).material
				fade_out(mi, m, 0.25)
		_drain_beam = null
		_drain_core = null


# ------------------------------------------------------------------ The Graves Open

func _graves_open() -> void:
	play("graves_open")
	var at := feet()
	ring(at, GRAVES_RADIUS, Color(SOUL, 0.6), 0.5)
	var glow := GroundDisc.create(GRAVES_RADIUS, Color(0.3, 0.9, 0.4, 0.22), true)
	spawn(glow, at)
	var tw := glow.create_tween()
	tw.tween_interval(GRAVES_RISE)
	tw.tween_property(glow, "alpha", 0.0, 1.0)
	tw.tween_callback(glow.queue_free)
	flash_light(at + Vector3(0, 4, 0), SOUL, 3.0, GRAVES_RADIUS * 1.2, GRAVES_RISE + 0.5)
	_graves.clear()
	var targets := near(at, GRAVES_RADIUS)
	for i in targets:   # a grave cracks open under each of them
		_graves.append(_floor(enemies.pos[i]))
	for n in mini(_graves.size(), GRAVES_SPIKES):
		_grave_mark(_graves[n], 0.9, randf() * 0.25)
	player.add_shake(0.35)
	after(GRAVES_DELAY, _graves_burst)
	after(GRAVES_RISE, _graves_rise)


## Bone spikes burst up out of every grave: GRAVES_DAMAGE, rooted.
func _graves_burst() -> void:
	var at := feet()
	var d := GRAVES_DAMAGE * dmg() * pw(2)
	for i in near(at, GRAVES_RADIUS + 0.5):
		enemies.stun(i, GRAVES_ROOT)
		enemies.damage(i, d)
		graves_hits += 1
	for n in mini(_graves.size(), GRAVES_SPIKES):
		_spike_cluster(_graves[n])
	if _graves.is_empty():   # nothing there: a ring of spikes round him anyway
		for n in 10:
			var a := TAU * n / 10.0
			_spike_cluster(_floor(at + Vector3(cos(a), 0, sin(a)) * 6.0))
	player.add_shake(0.7)
	play("bone_spikes", 1.0)


## A clutch of bone spikes jutting out of the ground at `p`, then sinking back.
func _spike_cluster(p: Vector3) -> void:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BONE
	mat.roughness = 0.7
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.4, 0.2)
	for s in 4:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = randf_range(0.09, 0.16)
		cone.height = randf_range(0.9, 1.7)
		cone.radial_segments = 5
		cone.rings = 1
		cone.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		var a := randf() * TAU
		mi.position = Vector3(cos(a) * 0.3, cone.height * 0.4, sin(a) * 0.3)
		mi.rotation = Vector3(randf_range(-0.35, 0.35), 0, randf_range(-0.35, 0.35))
		root.add_child(mi)
	spawn(root, p - Vector3(0, 1.4, 0))
	_spikes.append({"node": root, "t": 0.0, "at": p})
	for m in 3:
		mote(p + Vector3(0, 0.3, 0), Vector3(randf_range(-2, 2), randf_range(3, 6), randf_range(-2, 2)), 0.6, Color(0.55, 0.48, 0.38), 0.18, false, 14.0)


func _tick_spikes(dt: float) -> void:
	for n in range(_spikes.size() - 1, -1, -1):
		var s: Dictionary = _spikes[n]
		var node: Node3D = s["node"]
		if not is_instance_valid(node):
			_spikes.remove_at(n)
			continue
		s["t"] = float(s["t"]) + dt
		var t: float = s["t"]
		var up := 1.0 - pow(1.0 - clampf(t / 0.12, 0.0, 1.0), 3.0)
		var down := clampf((t - 1.4) / 0.5, 0.0, 1.0)
		node.global_position = (s["at"] as Vector3) - Vector3(0, 1.4 * (1.0 - up) + 1.6 * down, 0)
		if t > 2.0:
			node.queue_free()
			_spikes.remove_at(n)


## Then the dead rise from the graves (up to GRAVES_DEAD; more from the ground round him if few).
func _graves_rise() -> void:
	var at := feet()
	var spots: Array[Vector3] = []
	for p in _graves:
		if spots.size() < GRAVES_DEAD:
			spots.append(p)
	while spots.size() < GRAVES_DEAD:
		var a := randf() * TAU
		var r := randf_range(3.0, 12.0)
		spots.append(_floor(at + Vector3(cos(a), 0, sin(a)) * r))
	for n in GRAVES_DEAD:
		dead.add(spots[n], GRAVES_DEAD_TIME, n * 0.04)
		graves_raised += 1
	play("necro_raise", -3.0)
