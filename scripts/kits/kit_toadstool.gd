class_name KitToadstool
extends KitPart
## The Toadstool Knight (ToadstoolBody: the Forest boss's body at player size)
##   1  Fungal Shield     30 s  a shield worth 20% of max HP for 8 s (a red toadstool cap over him);
##                              when it breaks or runs out it bursts into spores: 60 within 8 m,
##                              plus poison
##   2  Fairy Ring        45 s  a 10 m ring of mushrooms springs up around you for 10 s; enemies that
##                              cross it take 50 and wander confused for 3 s
##   3  The Fungus Court 120 s  6 giant toadstool guardians rise in a 12 m ring around you for 15 s;
##                              each draws enemies to it and slams every 1.5 s: 80 within 4 m
## Levels: the shield and its burst; the ring's damage; the guardians' slams (pw).

const SHIELD_FRAC := 0.2
const SHIELD_TIME := 8.0
const BURST_DAMAGE := 60.0
const BURST_RADIUS := 8.0
const BURST_POISON := 0.02           # of max HP per second...
const BURST_POISON_TIME := 4.0       # ...for 4 s
const RING_RADIUS := 10.0
const RING_TIME := 10.0
const RING_DAMAGE := 50.0
const RING_CONFUSE := 3.0
const RING_BAND := 1.0               # an enemy this close to the ring line is crossing it
const RING_REHIT := 1.0              # the same enemy can be caught again after this long
const RING_SHROOMS := 30
const COURT_COUNT := 6
const COURT_RADIUS := 12.0
const COURT_TIME := 15.0
const COURT_EVERY := 1.5
const COURT_DAMAGE := 80.0
const COURT_SLAM_RADIUS := 4.0
const COURT_DRAW := 9.0              # enemies this close to a guardian are drawn to it...
const COURT_DRAW_SPEED := 3.5        # ...at this speed (m/s)...
const COURT_HUDDLE := 1.6            # ...until they crowd round its stem
const COURT_HEIGHT := 3.4
const CAP_RED := Color(0.78, 0.09, 0.06)
const SPOT := Color(0.97, 0.94, 0.86)
const STEM := Color(0.93, 0.88, 0.76)
const SPORE := Color(0.78, 0.5, 1.0)

var _shield_t := 0.0
var _shield_left := 0.0              # our part of player.shield
var _cap: Node3D
var _ring_t := 0.0
var _ring_at := Vector3.ZERO
var _ring_tick := 0.0
var _ring_seen := {}                 # uid -> ring time when last caught
var _ring_nodes: Array = []
var _court_t := 0.0
var _guards: Array = []              # {node, pos, t (to next slam), squash}
var _drawn_seen := {}                # uids drawn in this Court (tests)
var shield_bursts := 0               # tests
var burst_hits := 0
var ring_hits := 0
var court_slams := 0
var slam_hits := 0
var drawn := 0


func _exit_tree() -> void:   # the run is over: no tweens, just go
	for n in _ring_nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	for g in _guards:
		if is_instance_valid(g["node"]):
			(g["node"] as Node).queue_free()
	_ring_nodes.clear()
	_guards.clear()


func cast(i: int) -> void:
	match i:
		0: _fungal_shield()
		1: _fairy_ring()
		2: _fungus_court()


func active(name: String) -> bool:
	match name:
		"shield": return _shield_t > 0.0
		"ring": return _ring_t > 0.0
		"court": return _court_t > 0.0
	return false


func tick(dt: float) -> void:
	_tick_shield(dt)
	_tick_ring(dt)
	_tick_court(dt)


## Ground height under a point without a physics ray (the ring and the court are wide).
func _floor(p: Vector3) -> Vector3:
	return Vector3(p.x, SwampWater.height_at(p.x, p.z), p.z) if SwampWater.current != null else ground(p)


## A toadstool built from primitives: a cream stem and a glossy red, white-spotted cap; `h` m tall.
static func make_toadstool(h: float, seed_n: int, eyes := false) -> Node3D:
	var root := Node3D.new()
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = STEM
	stem_mat.roughness = 0.85
	var stem := CylinderMesh.new()
	stem.top_radius = h * 0.1
	stem.bottom_radius = h * 0.15
	stem.height = h * 0.62
	stem.radial_segments = 14
	stem.material = stem_mat
	var smi := MeshInstance3D.new()
	smi.mesh = stem
	smi.position.y = h * 0.31
	root.add_child(smi)
	var red := StandardMaterial3D.new()
	red.albedo_color = CAP_RED
	red.roughness = 0.3
	red.clearcoat_enabled = true
	red.clearcoat = 0.6
	var cr := h * 0.42
	var dome := SphereMesh.new()
	dome.radius = cr
	dome.height = cr
	dome.is_hemisphere = true
	dome.radial_segments = 20
	dome.rings = 8
	dome.material = red
	var cap := MeshInstance3D.new()
	cap.mesh = dome
	cap.scale = Vector3(1.0, 0.62, 1.0)
	cap.position.y = h * 0.6
	root.add_child(cap)
	var white := StandardMaterial3D.new()
	white.albedo_color = SPOT
	white.roughness = 0.6
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	for k in 9:
		var a := rng.randf() * TAU
		var e := rng.randf_range(0.2, 1.25)
		var n := Vector3(cos(a) * cos(e), sin(e) * 0.62, sin(a) * cos(e)).normalized()
		var spot := SphereMesh.new()
		var r := cr * rng.randf_range(0.09, 0.16)
		spot.radius = r
		spot.height = r * 0.7
		spot.radial_segments = 8
		spot.rings = 4
		spot.material = white
		var sp := MeshInstance3D.new()
		sp.mesh = spot
		sp.position = Vector3(cos(a) * cos(e) * cr, h * 0.6 + sin(e) * cr * 0.62, sin(a) * cos(e) * cr)
		sp.basis = Basis(Quaternion(Vector3.UP, n))
		root.add_child(sp)
	if eyes:   # two glowing eyes on the stem, just under the cap
		var glow := KitPart.glow_mat(Color(1.0, 0.85, 0.4), false)
		for side in [-1.0, 1.0]:
			var eye := SphereMesh.new()
			eye.radius = h * 0.025
			eye.height = h * 0.05
			eye.material = glow
			var ei := MeshInstance3D.new()
			ei.mesh = eye
			ei.position = Vector3(side * h * 0.045, h * 0.5, -h * 0.105)
			root.add_child(ei)
	return root


# ------------------------------------------------------------------ Fungal Shield

func _fungal_shield() -> void:
	play("fungal_shield")
	if _shield_t > 0.0:   # a fresh cast replaces the old one (no burst)
		player.shield = maxf(0.0, player.shield - _shield_left)
		_shield_left = 0.0
	var amount := player.max_hp * SHIELD_FRAC * pw(0)
	player.add_shield(amount)
	_shield_left = amount
	_shield_t = SHIELD_TIME
	if not is_instance_valid(_cap):   # a translucent toadstool cap held over him like a dome
		_cap = make_toadstool(2.6, 11)
		_cap.get_child(0).free()   # no stem
		for mi in _cap.find_children("*", "MeshInstance3D", true, false):
			var src: StandardMaterial3D = ((mi as MeshInstance3D).mesh as PrimitiveMesh).material
			var mat := src.duplicate() as StandardMaterial3D
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.42
			mat.emission_enabled = true
			mat.emission = mat.albedo_color * 0.35
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			(mi as MeshInstance3D).material_override = mat
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cap.position.y = -0.1
		player.add_child(_cap)
	_cap.scale = Vector3.ONE * 0.2
	_cap.create_tween().tween_property(_cap, "scale", Vector3.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	ring(feet(), 2.5, Color(0.95, 0.3, 0.2, 0.7), 0.3)


func _tick_shield(dt: float) -> void:
	if _shield_t <= 0.0:
		return
	_shield_t -= dt
	_shield_left = minf(_shield_left, player.shield)   # hits ate into it
	if is_instance_valid(_cap):
		_cap.rotation.y += dt * 0.6
		var s := 1.0 + 0.03 * sin(_shield_t * 7.0) + (0.06 if player.invuln > 0.3 else 0.0)
		_cap.scale = Vector3(s, s, s) if _cap.scale.x > 0.9 else _cap.scale
	if _shield_left <= 0.001:   # broken
		_shield_t = 0.0
		_spore_burst()
	elif _shield_t <= 0.0:   # ran out: what's left goes up in spores too
		player.shield = maxf(0.0, player.shield - _shield_left)
		_shield_left = 0.0
		_spore_burst()


## The cap bursts into spores: BURST_DAMAGE within BURST_RADIUS, plus poison.
func _spore_burst() -> void:
	shield_bursts += 1
	play("spore_burst")
	var at := feet()
	var d := BURST_DAMAGE * dmg() * pw(0)
	for i in near(at, BURST_RADIUS):
		enemies.damage(i, d)
		enemies.afflict(i, BURST_POISON, BURST_POISON_TIME)
		burst_hits += 1
	ring(at, BURST_RADIUS, Color(SPORE, 0.75), 0.4)
	for n in 26:
		var a := TAU * n / 26.0
		var dir := Vector3(cos(a), randf_range(0.1, 0.5), sin(a))
		mote(at + Vector3(0, 1.2, 0), dir * randf_range(8.0, 14.0), 0.7, SPORE, 0.35)
	if fx:
		fx.burst(at + Vector3(0, 1.0, 0), 2.5, SPORE, 0.4)
	flash_light(at + Vector3(0, 1.5, 0), SPORE, 3.0, BURST_RADIUS * 1.2, 0.5)
	if is_instance_valid(_cap):
		var cap := _cap
		_cap = null
		var tw := cap.create_tween()
		tw.tween_property(cap, "scale", Vector3.ONE * 1.6, 0.15).set_ease(Tween.EASE_OUT)
		tw.tween_callback(cap.queue_free)


# ------------------------------------------------------------------ Fairy Ring

func _fairy_ring() -> void:
	play("fairy_ring")
	_clear_ring()
	_ring_at = _floor(feet())
	_ring_t = RING_TIME
	_ring_tick = 0.0
	_ring_seen.clear()
	var glow := GroundDisc.create(RING_RADIUS + 0.6, Color(0.85, 0.65, 1.0, 0.35), true)
	glow.set_ring((RING_RADIUS - 0.6) / (RING_RADIUS + 0.6))
	spawn(glow, _ring_at + Vector3(0, 0.06, 0))
	_ring_nodes.append(glow)
	for n in RING_SHROOMS:
		var a := TAU * n / RING_SHROOMS + randf_range(-0.05, 0.05)
		var p := _floor(_ring_at + Vector3(cos(a), 0, sin(a)) * (RING_RADIUS + randf_range(-0.3, 0.3)))
		var h := randf_range(0.35, 0.75)
		var m := make_toadstool(h, n + 3)
		m.rotation.y = randf() * TAU
		spawn(m, p)
		_ring_nodes.append(m)
		m.scale = Vector3.ONE * 0.05
		var tw := m.create_tween()   # they spring up in a wave around the ring
		tw.tween_interval(0.25 * float(n) / RING_SHROOMS)
		tw.tween_property(m, "scale", Vector3.ONE, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	ring(_ring_at, RING_RADIUS, Color(0.9, 0.7, 1.0, 0.8), 0.45)
	flash_light(_ring_at + Vector3(0, 2.0, 0), Color(0.8, 0.55, 1.0), 2.0, RING_RADIUS * 1.5, 0.8)


func _tick_ring(dt: float) -> void:
	if _ring_t <= 0.0:
		return
	_ring_t -= dt
	var t := RING_TIME - _ring_t
	_ring_tick -= dt
	if _ring_tick <= 0.0:
		_ring_tick = 0.1
		var d := RING_DAMAGE * dmg() * pw(1)
		for i in near(_ring_at, RING_RADIUS + RING_BAND + 0.5):
			var off := enemies.pos[i] - _ring_at
			off.y = 0.0
			var reach := RING_BAND + enemies.t_radius[enemies.typ[i]] * enemies.sz[i]
			if absf(off.length() - RING_RADIUS) > reach:
				continue
			var u: int = enemies.uid[i]
			if t - float(_ring_seen.get(u, -99.0)) < RING_REHIT:
				continue
			_ring_seen[u] = t
			enemies.damage(i, d)
			enemies.confuse(i, RING_CONFUSE)
			ring_hits += 1
			mote(enemies.center_of(i), Vector3(0, 2.0, 0), 0.6, Color(0.9, 0.7, 1.0), 0.25)
	if randf() < dt * 14.0:   # spores glitter up off the ring
		var a := randf() * TAU
		var p := _ring_at + Vector3(cos(a), 0, sin(a)) * RING_RADIUS
		mote(p + Vector3(0, 0.5, 0), Vector3(0, 1.4, 0), 0.9, Color(0.85, 0.65, 1.0), 0.14)
	if _ring_t <= 0.0:
		_clear_ring()


func _clear_ring() -> void:
	for n in _ring_nodes:
		if is_instance_valid(n):
			var node := n as Node3D
			var tw := node.create_tween()
			tw.tween_property(node, "scale", Vector3(node.scale.x, 0.01, node.scale.z), 0.3).set_ease(Tween.EASE_IN)
			tw.tween_callback(node.queue_free)
	_ring_nodes.clear()
	_ring_t = 0.0


# ------------------------------------------------------------------ The Fungus Court

func _fungus_court() -> void:
	play("fungus_court")
	_clear_court()
	_drawn_seen.clear()
	_court_t = COURT_TIME
	var at := feet()
	for n in COURT_COUNT:
		var a := TAU * n / COURT_COUNT + player.cam_yaw
		var p := _floor(at + Vector3(cos(a), 0, sin(a)) * COURT_RADIUS)
		var g := make_toadstool(COURT_HEIGHT, 101 + n, true)
		spawn(g, p - Vector3(0, COURT_HEIGHT, 0))
		var to := at - p   # they face you
		g.rotation.y = atan2(-to.x, -to.z) + PI
		var tw := g.create_tween()
		tw.tween_interval(0.08 * n)
		tw.tween_property(g, "global_position", p, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_guards.append({"node": g, "pos": p, "t": 0.6 + COURT_EVERY * float(n) / COURT_COUNT, "squash": 0.0})
		if fx:
			fx.burst(p + Vector3(0, 0.5, 0), 2.0, Color(0.55, 0.42, 0.3), 0.4)
		ring(p, COURT_SLAM_RADIUS, Color(1.0, 0.82, 0.3, 0.6), 0.4)
	player.add_shake(0.45)
	flash_light(at + Vector3(0, 3.0, 0), Color(1.0, 0.82, 0.3), 3.0, COURT_RADIUS * 1.6, 1.0)


func _tick_court(dt: float) -> void:
	if _court_t <= 0.0:
		return
	_court_t -= dt
	var d := COURT_DAMAGE * dmg() * pw(2)
	for g in _guards:
		var node: Node3D = g["node"]
		if not is_instance_valid(node):
			continue
		var p: Vector3 = g["pos"]
		# Every enemy nearby is drawn in to the guardian, crowding round its stem
		for i in near(p, COURT_DRAW, true):
			var to := p - enemies.pos[i]
			to.y = 0.0
			var l := to.length()
			if l > COURT_HUDDLE:
				enemies.pos[i] += to / l * minf(COURT_DRAW_SPEED * dt, l - COURT_HUDDLE)
				enemies.vel[i] = Vector3.ZERO
				if not _drawn_seen.has(enemies.uid[i]):
					_drawn_seen[enemies.uid[i]] = true
					drawn += 1
		g["t"] -= dt
		if g["t"] <= 0.0:
			g["t"] = COURT_EVERY
			g["squash"] = 1.0
			court_slams += 1
			for i in near(p, COURT_SLAM_RADIUS):
				enemies.damage(i, d)
				slam_hits += 1
			ring(p, COURT_SLAM_RADIUS, Color(1.0, 0.75, 0.3, 0.8), 0.3)
			if fx:
				fx.burst(p + Vector3(0, 0.4, 0), 1.6, Color(0.6, 0.5, 0.35), 0.3)
			play("court_slam", -8.0)
		# The slam: it squashes down hard, then springs back up
		g["squash"] = maxf(0.0, float(g["squash"]) - dt * 3.0)
		var sq: float = sin(float(g["squash"]) * PI)
		if node.global_position.distance_to(p) < 0.05 or float(g["squash"]) > 0.0:
			node.scale = Vector3(1.0 + 0.25 * sq, 1.0 - 0.3 * sq, 1.0 + 0.25 * sq)
	if _court_t <= 0.0:
		_clear_court()


func _clear_court() -> void:
	for g in _guards:
		var node: Node3D = g["node"]
		if is_instance_valid(node):
			var tw := node.create_tween()
			tw.tween_property(node, "global_position", (g["pos"] as Vector3) - Vector3(0, COURT_HEIGHT, 0), 0.6).set_ease(Tween.EASE_IN)
			tw.tween_callback(node.queue_free)
	_guards.clear()
	_court_t = 0.0
