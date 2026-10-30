class_name KitThog
extends KitPart
## Thog the Troll (unlocked by beating him in the Swamp; plays on the Ogre's rig for now)
##   1  Toll Booth       30 s  for 8 s, every enemy that comes within 6 m pays the toll: 80 damage
##                             and an XP gem
##   2  Goat Charge      45 s  charge 20 m headfirst where you aim: 120 to everything hit, thrown 8 yd
##   3  Bridge Collapse 120 s  a stone bridge crashes down across where you aim (25 m long): 350
##                             damage; the rubble stays 10 s as a wall enemies can't cross

const TOLL_TIME := 8.0
const TOLL_RADIUS := 6.0
const TOLL_DAMAGE := 80.0
const CHARGE_LENGTH := 20.0
const CHARGE_TIME := 0.55
const CHARGE_WIDTH := 2.2
const CHARGE_DAMAGE := 120.0
const CHARGE_THROW := 8.0 * YARD
const BRIDGE_LENGTH := 25.0
const BRIDGE_RANGE := 18.0
const BRIDGE_DAMAGE := 350.0
const BRIDGE_HALF_W := 2.4
const BRIDGE_FALL := 0.6
const RUBBLE_TIME := 10.0

var _toll_t := 0.0
var _paid := {}
var _toll_disc: GroundDisc
var _charge_t := -1.0
var _charge_from := Vector3.ZERO
var _charge_to := Vector3.ZERO
var _charge_hit := {}
var _rubble: Array = []         # {t, node, barrier}
var tolls := 0                  # tests
var charge_hits := 0
var bridge_hits := 0
var last_bridge := Vector3.INF  # where the last bridge came down (tests)


func _exit_tree() -> void:
	for r in _rubble:
		enemies.barriers.erase(r["barrier"])
	if player.scripted and _charge_t >= 0.0:
		player.scripted = false


func cast(i: int) -> void:
	match i:
		0: _toll()
		1: _charge()
		2: _bridge()


func active(name: String) -> bool:
	match name:
		"toll": return _toll_t > 0.0
		"charge": return _charge_t >= 0.0
		"rubble": return not _rubble.is_empty()
	return false


func tick(dt: float) -> void:
	_tick_toll(dt)
	_tick_charge(dt)
	_tick_rubble(dt)


# ------------------------------------------------------------------ Toll Booth

func _toll() -> void:
	play("toll_booth")
	_toll_t = TOLL_TIME
	_paid = {}
	if not is_instance_valid(_toll_disc):
		_toll_disc = GroundDisc.create(TOLL_RADIUS, Color(1.0, 0.8, 0.3, 0.5), true)
		_toll_disc.set_ring(0.9)
		spawn(_toll_disc, feet())


func _tick_toll(dt: float) -> void:
	if _toll_t <= 0.0:
		return
	_toll_t -= dt
	_toll_disc.global_position = feet()
	_toll_disc.alpha = 0.5 * clampf(_toll_t, 0.0, 1.0)
	for i in near(feet(), TOLL_RADIUS):
		var u := enemies.uid[i]
		if _paid.has(u):
			continue
		_paid[u] = true
		tolls += 1
		var p := enemies.pos[i]
		enemies.damage(i, TOLL_DAMAGE * dmg() * pw(0))
		k.drop_xp.emit(p + Vector3(0, 0.5, 0), 1.0)   # the toll
		mote(p + Vector3(0, 1.0, 0), Vector3(0, 3.0, 0), 0.6, Color(1.0, 0.85, 0.3), 0.2)
	if _toll_t <= 0.0:
		_toll_disc.queue_free()


# ------------------------------------------------------------------ Goat Charge

func _charge() -> void:
	play("goat_charge")
	_charge_from = feet()
	var dir := aim_dir()
	_charge_to = _charge_from + dir * CHARGE_LENGTH
	_charge_to = ground(_charge_to)
	_charge_t = 0.0
	_charge_hit = {}
	begin_scripted()
	player.invuln = maxf(player.invuln, CHARGE_TIME + 0.2)


func _tick_charge(dt: float) -> void:
	if _charge_t < 0.0:
		return
	_charge_t += dt
	var f := clampf(_charge_t / CHARGE_TIME, 0.0, 1.0)
	var dir := _charge_to - _charge_from
	dir.y = 0.0
	dir = dir.normalized()
	var p := ground(_charge_from.lerp(_charge_to, f))
	player.global_position = p + Vector3(0, 0.05, 0)
	for i in near(p, CHARGE_WIDTH):
		var u := enemies.uid[i]
		if _charge_hit.has(u):
			continue
		_charge_hit[u] = true
		charge_hits += 1
		enemies.damage(i, CHARGE_DAMAGE * dmg() * pw(1))
		var side := (enemies.pos[i] - p).normalized() * 0.6 + dir
		enemies.knock(i, side, CHARGE_THROW, 0.35)
	if randf() < dt * 30.0 and fx:
		fx.burst(p + Vector3(0, 0.3, 0), 1.2, Color(0.55, 0.45, 0.3), 0.25)
	if f >= 1.0:
		_charge_t = -1.0
		end_scripted(p)
		player.add_shake(0.4)


# ------------------------------------------------------------------ Bridge Collapse

func _bridge() -> void:
	play("bridge_collapse")
	var dir := aim_dir()
	var aim := aim_point(BRIDGE_RANGE)
	var dist := clampf(Vector2(aim.x - feet().x, aim.z - feet().z).length(), 8.0, BRIDGE_RANGE)
	var c := ground(feet() + dir * dist)
	last_bridge = c
	var side := dir.cross(Vector3.UP).normalized()   # the bridge lies across your aim
	var a := c - side * BRIDGE_LENGTH * 0.5
	var b := c + side * BRIDGE_LENGTH * 0.5
	var slab := _make_bridge()
	spawn(slab, c + Vector3(0, 18.0, 0))
	slab.rotation.y = atan2(-side.z, side.x)   # its length (local X) along `side`
	# A dark shadow on the ground marks where it will land
	var mark := GroundDisc.create(1.0, Color(0.1, 0.05, 0.02, 0.5), false)
	spawn(mark, c)
	mark.scale = Vector3(BRIDGE_LENGTH * 0.55, 1, BRIDGE_LENGTH * 0.55)
	var tw := slab.create_tween()
	tw.tween_property(slab, "global_position", c + Vector3(0, 0.4, 0), BRIDGE_FALL).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): _bridge_lands(a, b, slab, mark))


func _bridge_lands(a: Vector3, b: Vector3, slab: Node3D, mark: Node3D) -> void:
	mark.queue_free()
	var seg := b - a
	seg.y = 0.0
	var n := 0
	for i in near((a + b) * 0.5, BRIDGE_LENGTH * 0.5 + BRIDGE_HALF_W):
		var rel := enemies.pos[i] - a
		rel.y = 0.0
		var along := clampf(rel.dot(seg.normalized()), 0.0, seg.length())
		var lat := rel - seg.normalized() * along
		if lat.length() > BRIDGE_HALF_W + enemies.t_radius[enemies.typ[i]]:
			continue
		n += 1
		enemies.damage(i, BRIDGE_DAMAGE * dmg() * pw(2))
		# anything left under the rubble is shoved out to one side
		var push := lat.normalized() if lat.length() > 0.1 else seg.normalized().cross(Vector3.UP)
		enemies.knock(i, push, BRIDGE_HALF_W + 1.0, 0.2)
	bridge_hits += n
	if fx:
		for k2 in 9:
			fx.burst(a.lerp(b, k2 / 8.0) + Vector3(0, 0.8, 0), 3.0, Color(0.55, 0.5, 0.45), 0.6)
	player.add_shake(1.0)
	var barrier := [Vector2(a.x, a.z), Vector2(b.x, b.z), BRIDGE_HALF_W * 0.6]
	enemies.barriers.append(barrier)
	_rubble.append({"t": RUBBLE_TIME, "node": slab, "barrier": barrier})


func _tick_rubble(dt: float) -> void:
	for k2 in range(_rubble.size() - 1, -1, -1):
		var r: Dictionary = _rubble[k2]
		r["t"] -= dt
		if r["t"] <= 0.0:
			enemies.barriers.erase(r["barrier"])
			var node: Node3D = r["node"]
			var tw := node.create_tween()
			tw.tween_property(node, "position:y", node.position.y - 3.0, 1.0)
			tw.tween_callback(node.queue_free)
			_rubble.remove_at(k2)


## A broken stone bridge span: an arch of blocks with a low parapet.
func _make_bridge() -> Node3D:
	var mb := MeshBuilder.new()
	var stone := Color(0.45, 0.43, 0.4, 0)
	var dark := Color(0.32, 0.3, 0.28, 0)
	var segs := 10
	for s in segs:
		var x := lerpf(-BRIDGE_LENGTH * 0.5, BRIDGE_LENGTH * 0.5, (s + 0.5) / segs)
		var y := sin((s + 0.5) / segs * PI) * 1.4
		mb.add(MeshBuilder.box(Vector3(BRIDGE_LENGTH / segs - 0.12, 0.9, BRIDGE_HALF_W * 1.5)), Transform3D(Basis(Vector3.BACK, randf_range(-0.06, 0.06)), Vector3(x, y, 0)), stone if s % 2 else dark)
		for side in [-1.0, 1.0]:
			mb.add(MeshBuilder.box(Vector3(BRIDGE_LENGTH / segs - 0.3, 0.6, 0.35)), Transform3D(Basis(), Vector3(x, y + 0.75, side * BRIDGE_HALF_W * 0.7)), dark)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(MeshBuilder.prop_material())
	var root := Node3D.new()
	root.add_child(mi)
	return root
