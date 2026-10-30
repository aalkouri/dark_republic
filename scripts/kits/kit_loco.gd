class_name KitLoco
extends KitPart
## Loco Robotico (built in code: LocoBody)
##   1  Party Mode     30 s  drops a disco ball: enemies within 15 m are forced to dance for 6 s
##                           (they can't move or attack) and take 5% of max HP per second
##   2  Pinata Drop    45 s  a pinata lands where you aim; enemies swarm it, and after 3 s it
##                           bursts into 20 candy bombs: 60 damage each within 3 m
##   3  DESTROY Mode  120 s  12 s: twin lasers sweep around you to 20 m (8% of max HP per second
##                           to enemies in the beams); +50% armour

const DANCE_RADIUS := 15.0
const DANCE_TIME := 6.0
const DANCE_FRAC := 0.05            # of max HP per second
const BALL_HEIGHT := 4.0
const PINATA_RANGE := 25.0
const PINATA_FLIGHT := 0.6
const PINATA_FUSE := 3.0            # seconds on the ground before it bursts
const LURE_RADIUS := 14.0           # enemies this close swarm it...
const LURE_SPEED := 4.5             # ...at this speed (m/s)
const BOMBS := 20
const BOMB_DAMAGE := 60.0
const BOMB_RADIUS := 3.0
const BOMB_SPREAD := 6.0            # candy lands within this of the pinata
const DESTROY_TIME := 12.0
const BEAM_RANGE := 20.0
const BEAM_WIDTH := 1.0             # half-width of each beam
const BEAM_FRAC := 0.08             # of max HP per second in a beam
const BEAM_SPIN := 1.3              # rad/s the beams sweep round
const DESTROY_ARMOR := 1.5          # damage taken / 1.5 (+50% armour)
const CANDY := [Color(1.0, 0.3, 0.6), Color(0.3, 0.85, 1.0), Color(1.0, 0.85, 0.2), Color(0.5, 1.0, 0.35), Color(0.75, 0.45, 1.0)]

var _party_t := 0.0
var _dancers := {}                  # uid -> phase
var _dance_tick := 0.0
var _ball: Node3D
var _ball_light: OmniLight3D
var _floor: GroundDisc
var _pinata: Node3D
var _pinata_t := -1.0               # seconds since it landed (-1 = none on the ground)
var _pinata_at := Vector3.ZERO
var _bombs: Array = []              # {node, from, to, t, flight}
var _destroy_t := 0.0
var _beam_angle := 0.0
var _beams: Array[MeshInstance3D] = []
var _beam_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var danced := 0                     # tests
var lured := 0
var bombs_burst := 0
var beam_hits := 0


func cast(i: int) -> void:
	match i:
		0: _party()
		1: _pinata_drop()
		2: _destroy()


func active(name: String) -> bool:
	match name:
		"party": return _party_t > 0.0
		"pinata": return is_instance_valid(_pinata) or not _bombs.is_empty()
		"destroy": return _destroy_t > 0.0
	return false


func tick(dt: float) -> void:
	_tick_party(dt)
	_tick_pinata(dt)
	_tick_bombs(dt)
	_tick_destroy(dt)


func _body() -> LocoBody:
	var m = player.model
	return m.loco if m is RosterHero else null


static func _hue(h: float) -> Color:
	return Color.from_hsv(fposmod(h, 1.0), 0.75, 1.0)


# ------------------------------------------------------------------ Party Mode

func _party() -> void:
	play("party_mode")
	var at := feet()
	_party_t = DANCE_TIME
	_dance_tick = 0.0
	if _body():
		_body().party = true
	for i in near(at, DANCE_RADIUS):
		enemies.stun(i, DANCE_TIME)
		_dancers[enemies.uid[i]] = randf() * TAU
		danced += 1
	# The disco ball comes down on a string and hangs there spinning
	if is_instance_valid(_ball):
		_ball.queue_free()
	_ball = _make_ball()
	spawn(_ball, at + Vector3(0, BALL_HEIGHT + 6.0, 0))
	var tw := _ball.create_tween()
	tw.tween_property(_ball, "global_position", at + Vector3(0, BALL_HEIGHT, 0), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if is_instance_valid(_floor):
		_floor.queue_free()
	_floor = GroundDisc.create(DANCE_RADIUS, Color(1.0, 0.4, 0.9, 0.22), true)
	_floor.set_ring(0.7)
	spawn(_floor, at)
	ring(at, DANCE_RADIUS, Color(1.0, 0.5, 0.95, 0.8), 0.5)


func _tick_party(dt: float) -> void:
	if _party_t <= 0.0:
		return
	_party_t -= dt
	var t := DANCE_TIME - _party_t
	if is_instance_valid(_ball):
		_ball.rotation.y += dt * 2.5
		var c := _hue(t * 0.6)
		_ball_light.light_color = c
		_ball_light.light_energy = 3.0 + 1.5 * sin(t * 14.0)
		if is_instance_valid(_floor):
			_floor.color = Color(c, 0.22)
			_floor.rotation.y += dt * 1.5
	# The dancers shuffle side to side on the spot (no net drift), and lose HP
	_dance_tick -= dt
	var pay := _dance_tick <= 0.0
	if pay:
		_dance_tick = 0.25
	for u in _dancers.keys():
		var i := enemies.index_of(u)
		if i < 0 or enemies.stun_t[i] <= 0.0:
			_dancers.erase(u)
			continue
		var ph: float = _dancers[u]
		var w := 9.0
		var right := Vector3(cos(ph), 0, sin(ph))
		enemies.pos[i] += right * cos(t * w + ph) * 0.18 * w * dt
		if pay:
			enemies.dot_damage(i, enemies.hp_max[i] * DANCE_FRAC * pw(0) * 0.25 * enemies.pct_scale(i))
		if randf() < dt * 1.2:   # music notes
			mote(enemies.pos[i] + Vector3(0, 1.4, 0), Vector3(randf_range(-0.5, 0.5), 1.6, randf_range(-0.5, 0.5)), 0.8, _hue(t * 0.6 + randf() * 0.3), 0.16)
	if _party_t <= 0.0:
		_dancers.clear()
		if _body():
			_body().party = false
		if is_instance_valid(_ball):
			var b := _ball
			var tw := b.create_tween()
			tw.tween_property(b, "global_position", b.global_position + Vector3(0, 8.0, 0), 0.5).set_ease(Tween.EASE_IN)
			tw.tween_callback(b.queue_free)
		_ball = null
		if is_instance_valid(_floor):
			_floor.queue_free()
		_floor = null


## A mirror ball: a faceted silver sphere on a string, with a coloured light inside the party.
func _make_ball() -> Node3D:
	var root := Node3D.new()
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	mb.add(MeshBuilder.sphere(0.6, 12, 8), Transform3D(), Color(0.75, 0.78, 0.85, 0))
	for k in 40:   # mirror tiles catching the light
		var y := randf_range(-0.85, 0.85)
		var a := randf() * TAU
		var r := sqrt(1.0 - y * y)
		var n := Vector3(cos(a) * r, y, sin(a) * r)
		gb.add(MeshBuilder.box(Vector3(0.12, 0.12, 0.02)), Transform3D(Basis.looking_at(n, Vector3.UP if absf(y) < 0.95 else Vector3.RIGHT), n * 0.61), Color(0.9, 0.95, 1.0, 0))
	mb.add(MeshBuilder.cyl(0.01, 0.01, 8.0, 4), Transform3D(Basis(), Vector3(0, 4.6, 0)), Color(0.8, 0.8, 0.8, 0))
	var mesh := mb.commit(MeshBuilder.prop_material())
	gb.commit_into(mesh, MeshBuilder.glow_material())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	_ball_light = OmniLight3D.new()
	_ball_light.omni_range = DANCE_RADIUS
	_ball_light.light_energy = 3.0
	_ball_light.shadow_enabled = false
	root.add_child(_ball_light)
	return root


# ------------------------------------------------------------------ Pinata Drop

func _pinata_drop() -> void:
	play("pinata_drop")
	if is_instance_valid(_pinata):
		_pinata.queue_free()
	var from := chest() + Vector3(0, 0.6, 0)
	var to := ground(aim_point(PINATA_RANGE))
	_pinata_at = to
	_pinata_t = -1.0
	_pinata = _make_pinata()
	spawn(_pinata, from)
	_pinata.rotation.y = player.model.rotation.y
	var p := _pinata
	var tw := p.create_tween()
	tw.tween_method(func(f: float):
		p.global_position = from.lerp(to, f) + Vector3(0, 5.0 * f * (1.0 - f), 0)
		p.rotation.z = sin(f * PI * 3.0) * 0.4, 0.0, 1.0, PINATA_FLIGHT)
	tw.tween_callback(_land_pinata)


func _land_pinata() -> void:
	if not is_instance_valid(_pinata):
		return
	_pinata.global_position = _pinata_at
	_pinata_t = 0.0
	if fx:
		fx.burst(_pinata_at + Vector3(0, 0.3, 0), 1.5, Color(1.0, 0.75, 0.4), 0.3)
	ring(_pinata_at, LURE_RADIUS, Color(1.0, 0.75, 0.3, 0.6), 0.5)
	for i in near(_pinata_at, LURE_RADIUS, true):
		lured += 1


func _tick_pinata(dt: float) -> void:
	if _pinata_t < 0.0 or not is_instance_valid(_pinata):
		return
	_pinata_t += dt
	# Every enemy nearby drops what it's doing and crowds round the pinata, swinging at it
	for i in near(_pinata_at, LURE_RADIUS, true):
		var to := _pinata_at - enemies.pos[i]
		to.y = 0.0
		var d := to.length()
		if d > 1.0:
			enemies.pos[i] += to / d * minf(LURE_SPEED * dt, d - 1.0)
		enemies.vel[i] = Vector3.ZERO
	var shake := 0.15 + 0.25 * _pinata_t / PINATA_FUSE
	_pinata.rotation = Vector3(sin(_pinata_t * 23.0) * shake, _pinata.rotation.y, cos(_pinata_t * 19.0) * shake)
	_pinata.position.y = _pinata_at.y + absf(sin(_pinata_t * 9.0)) * 0.15
	if _pinata_t >= PINATA_FUSE:
		_burst_pinata()


func _burst_pinata() -> void:
	_pinata_t = -1.0
	var at := _pinata_at
	_pinata.queue_free()
	_pinata = null
	player.add_shake(0.35)
	if fx:
		fx.burst(at + Vector3(0, 1.0, 0), 2.5, Color(1.0, 0.5, 0.8), 0.4)
	flash_light(at + Vector3(0, 1.5, 0), Color(1.0, 0.7, 0.9), 5.0, 10.0, 0.4)
	for k in 12:   # confetti
		mote(at + Vector3(0, 1.0, 0), Vector3(randf_range(-5, 5), randf_range(3, 7), randf_range(-5, 5)), 1.2, CANDY[k % CANDY.size()], 0.14, false, 1.5)
	for k in BOMBS:
		var a := TAU * k / BOMBS + randf_range(-0.2, 0.2)
		var r := BOMB_SPREAD * sqrt(randf_range(0.02, 1.0))
		var to := ground(at + Vector3(cos(a) * r, 0, sin(a) * r))
		var n := _make_candy(CANDY[k % CANDY.size()])
		spawn(n, at + Vector3(0, 1.0, 0))
		_bombs.append({"node": n, "from": at + Vector3(0, 1.0, 0), "to": to, "t": 0.0, "flight": randf_range(0.45, 0.9)})


func _tick_bombs(dt: float) -> void:
	for k in range(_bombs.size() - 1, -1, -1):
		var b: Dictionary = _bombs[k]
		b["t"] += dt / float(b["flight"])
		var f: float = minf(b["t"], 1.0)
		var n: Node3D = b["node"]
		n.global_position = (b["from"] as Vector3).lerp(b["to"], f) + Vector3(0, 3.5 * f * (1.0 - f) * 2.0, 0)
		n.rotation += Vector3(9.0, 6.0, 0.0) * dt
		if f >= 1.0:
			var at: Vector3 = b["to"]
			n.queue_free()
			_bombs.remove_at(k)
			bombs_burst += 1
			for i in near(at, BOMB_RADIUS):
				var away := enemies.pos[i] - at
				away.y = 0.0
				enemies.damage(i, BOMB_DAMAGE * dmg() * pw(1), away.normalized() * 4.0 if away.length() > 0.05 else Vector3.ZERO)
			if fx:
				fx.burst(at + Vector3(0, 0.4, 0), BOMB_RADIUS * 0.7, CANDY[k % CANDY.size()], 0.3)
	if not _bombs.is_empty():
		player.add_shake(0.05)


## A donkey pinata: a striped barrel of a body, neck and head, ears, legs and a paper tail.
func _make_pinata() -> Node3D:
	var root := Node3D.new()
	var mb := MeshBuilder.new()
	var stripes := [Color(1.0, 0.3, 0.6, 0), Color(1.0, 0.85, 0.2, 0), Color(0.3, 0.85, 1.0, 0), Color(0.5, 1.0, 0.35, 0), Color(0.75, 0.45, 1.0, 0)]
	var along := Basis(Vector3.RIGHT, PI / 2)   # cylinders along Z
	for k in 7:   # the body, in fringed paper bands
		mb.add(MeshBuilder.cyl(0.42, 0.42, 0.17, 16), Transform3D(along, Vector3(0, 1.0, -0.51 + k * 0.17)), stripes[k % 5])
	for k in 4:   # the neck, rising forward
		mb.add(MeshBuilder.cyl(0.2, 0.22, 0.16, 12), Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 1.35 + k * 0.13, -0.55 - k * 0.07)), stripes[(k + 2) % 5])
	mb.add(MeshBuilder.box(Vector3(0.32, 0.3, 0.55)), Transform3D(Basis(), Vector3(0, 1.85, -0.9)), stripes[1])   # head
	mb.add(MeshBuilder.box(Vector3(0.28, 0.24, 0.2)), Transform3D(Basis(), Vector3(0, 1.8, -1.2)), stripes[0])    # muzzle
	for sx in [-1.0, 1.0]:
		mb.add(MeshBuilder.cyl(0.02, 0.07, 0.32, 6), Transform3D(Basis(Vector3.FORWARD, sx * 0.3), Vector3(sx * 0.12, 2.15, -0.8)), stripes[3])   # ears
		mb.add(MeshBuilder.sphere(0.04, 6, 4), Transform3D(Basis(), Vector3(sx * 0.12, 1.92, -1.15)), Color(0.05, 0.05, 0.05, 0))                # eyes
		for z in [-0.4, 0.4]:
			mb.add(MeshBuilder.cyl(0.09, 0.09, 0.62, 8), Transform3D(Basis(), Vector3(sx * 0.22, 0.42, z)), stripes[(int(z * 10) + 5) % 5])        # legs
	mb.add(MeshBuilder.cyl(0.05, 0.02, 0.5, 6), Transform3D(Basis(Vector3.RIGHT, 0.9), Vector3(0, 1.05, 0.75)), stripes[4])   # tail
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(MeshBuilder.prop_material())
	root.add_child(mi)
	return root


static var _candy_mesh := {}

## A wrapped sweet with a lit fuse: a ball with twisted wrapper ends.
func _make_candy(c: Color) -> Node3D:
	var key := c.to_html()
	if not _candy_mesh.has(key):
		var mb := MeshBuilder.new()
		mb.add(MeshBuilder.sphere(0.16, 10, 6), Transform3D(), Color(c, 0))
		for sx in [-1.0, 1.0]:
			mb.add(MeshBuilder.cone(0.12, 0.16, 8), Transform3D(Basis(Vector3.FORWARD, sx * PI / 2), Vector3(sx * 0.22, 0, 0)), Color(c.lightened(0.4), 0))
		_candy_mesh[key] = mb.commit(MeshBuilder.glow_material())
	var mi := MeshInstance3D.new()
	mi.mesh = _candy_mesh[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------------ DESTROY Mode

func _destroy() -> void:
	play("destroy_mode")
	if _destroy_t <= 0.0:
		player.dmg_taken /= DESTROY_ARMOR
	_destroy_t = DESTROY_TIME
	var d := aim_dir()
	_beam_angle = atan2(d.x, d.z)
	if _body():
		_body().destroy = true
	if _beams.is_empty():
		_beam_mat = glow_mat(Color(1.0, 0.15, 0.08, 0.85))
		_core_mat = glow_mat(Color(1.0, 0.85, 0.7, 1.0))
		for k in 2:
			var beam := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.28
			cm.bottom_radius = 0.28
			cm.height = 1.0
			cm.radial_segments = 10
			cm.material = _beam_mat
			beam.mesh = cm
			var core := MeshInstance3D.new()
			var cc := CylinderMesh.new()
			cc.top_radius = 0.1
			cc.bottom_radius = 0.1
			cc.height = 1.0
			cc.radial_segments = 6
			cc.material = _core_mat
			core.mesh = cc
			beam.add_child(core)
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			spawn(beam, feet())
			_beams.append(beam)
	for b in _beams:
		b.visible = true
	ring(feet(), BEAM_RANGE, Color(1.0, 0.2, 0.1, 0.7), 0.5)
	player.add_shake(0.4)


## Unit direction of beam `k` (0 or 1, opposite each other).
func beam_dir(k: int) -> Vector3:
	var a := _beam_angle + (PI if k == 1 else 0.0)
	return Vector3(sin(a), 0.0, cos(a))


func _tick_destroy(dt: float) -> void:
	if _destroy_t <= 0.0:
		return
	_destroy_t -= dt
	_beam_angle = wrapf(_beam_angle + BEAM_SPIN * dt, -PI, PI)
	var body := _body()
	if body:
		body.turret_yaw = _beam_angle
	var at := feet()
	var y := 1.05
	for k in 2:
		var d := beam_dir(k)
		var from := (body.hand(1 - k) if body else at + Vector3(0, y, 0) + d * 0.8)
		var end := at + d * BEAM_RANGE + Vector3(0, 0.6, 0)
		var mid := (from + end) * 0.5
		var len := from.distance_to(end)
		var b := _beams[k]
		var up := (end - from).normalized()
		var side := up.cross(Vector3.UP).normalized()
		var fwd := side.cross(up)
		var flick := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.05 + k)
		b.global_transform = Transform3D(Basis(side * flick, up * len, fwd * flick), mid)
		if randf() < dt * 30.0:   # sparks where it scorches the ground
			var p := at + d * randf_range(2.0, BEAM_RANGE)
			mote(p + Vector3(0, 0.3, 0), Vector3(randf_range(-1, 1), 2.5, randf_range(-1, 1)), 0.4, Color(1.0, 0.5, 0.2), 0.14)
	# Everything in either beam burns
	for i in near(at, BEAM_RANGE + 1.0):
		var off := enemies.pos[i] - at
		off.y = 0.0
		var d0 := beam_dir(0)
		var along := off.dot(d0)
		var across := absf(off.dot(Vector3(d0.z, 0, -d0.x)))
		if absf(along) > BEAM_RANGE or across > BEAM_WIDTH + enemies.t_radius[enemies.typ[i]] * enemies.sz[i]:
			continue
		enemies.dot_damage(i, enemies.hp_max[i] * BEAM_FRAC * pw(2) * dt * enemies.pct_scale(i))
		beam_hits += 1
	if _destroy_t <= 0.0:
		player.dmg_taken *= DESTROY_ARMOR
		if body:
			body.destroy = false
		for b in _beams:
			b.visible = false
