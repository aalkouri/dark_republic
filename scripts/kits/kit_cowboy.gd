class_name KitCowboy
extends KitPart
## Cowboy
##   1  Lasso      25 s  ropes the enemy with the most HP within 20 m (not the boss) and swings
##                       it round him for 3 s: 60 to every enemy it hits, then hurls it 15 m
##   2  Dynamite   40 s  3 sticks in a fan; each explodes after 1.5 s: 120 within 5 m
##   3  High Noon 120 s  everything within 30 m freezes for 2 s while he marks up to 30 of them,
##                       then he fires: 300 to each

const LASSO_RANGE := 20.0
const LASSO_TIME := 3.0
const LASSO_R := 3.5
const LASSO_DAMAGE := 60.0
const LASSO_HIT := 1.6
const LASSO_THROW := 15.0
const DYN_COUNT := 3
const DYN_FUSE := 1.5
const DYN_RADIUS := 5.0
const DYN_DAMAGE := 120.0
const DYN_DIST := 9.0
const NOON_RANGE := 30.0
const NOON_MARKS := 30
const NOON_TIME := 2.0
const NOON_DAMAGE := 300.0

var _lasso_uid := -1
var _lasso_t := 0.0
var _lasso_hit := {}
var _rope: MeshInstance3D
var _sticks: Array = []          # {node, from, to, t, fuse}
var _noon_t := 0.0
var _noon: Array = []            # uids


func cast(i: int) -> void:
	src(i)
	match i:
		0: _lasso()
		1: _dynamite()
		2: _high_noon()


func active(name: String) -> bool:
	match name:
		"lasso": return _lasso_t > 0.0
		"dynamite": return not _sticks.is_empty()
		"high_noon": return _noon_t > 0.0
	return false


func tick(dt: float) -> void:
	src(0)
	_tick_lasso(dt)
	src(1)
	_tick_dynamite(dt)
	src(2)
	if _noon_t > 0.0:
		_noon_t -= dt
		if _noon_t <= 0.0:
			_fire_noon()


# ------------------------------------------------------------------ Lasso

func _lasso() -> void:
	play("lasso")
	var best := -1
	for i in near(chest(), LASSO_RANGE, true):
		if best < 0 or enemies.hp[i] > enemies.hp[best]:
			best = i
	if best < 0:
		return
	_lasso_uid = enemies.uid[best]
	_lasso_t = LASSO_TIME
	_lasso_hit.clear()
	enemies.stun(best, LASSO_TIME + 0.5)
	_rope = MeshInstance3D.new()
	_rope.mesh = HeroBody._cyl(0.025, 0.025, 1.0, 6)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.6, 0.35)
	_rope.material_override = m
	spawn(_rope, chest())


func _tick_lasso(dt: float) -> void:
	if _lasso_t <= 0.0:
		return
	_lasso_t -= dt
	var i := enemies.index_of(_lasso_uid)
	if i < 0:
		_lasso_t = 0.0
		if is_instance_valid(_rope):
			_rope.queue_free()
		return
	var ang := (LASSO_TIME - _lasso_t) * 7.0
	var c := feet()
	var p := c + Vector3(cos(ang), 0, sin(ang)) * LASSO_R
	enemies.pos[i] = Vector3(p.x, enemies.pos[i].y, p.z)
	var d := LASSO_DAMAGE * dmg() * pw(0)
	for e in near(enemies.pos[i], LASSO_HIT):
		if e != i and not _lasso_hit.has(enemies.uid[e]):
			_lasso_hit[enemies.uid[e]] = true
			enemies.damage(e, d)
			enemies.knock(e, enemies.pos[e] - c, 3.0, 0.2)
	var hand := chest() + Vector3(0, 0.6, 0)
	var tip := enemies.center_of(i)
	_rope.global_position = (hand + tip) * 0.5
	_rope.scale = Vector3(1, hand.distance_to(tip), 1)
	_rope.look_at(tip, Vector3.UP if absf((tip - hand).normalized().y) < 0.95 else Vector3.RIGHT)
	_rope.rotate_object_local(Vector3.RIGHT, PI / 2)
	if _lasso_t <= 0.0:   # let go: hurled away the way you look
		enemies.damage(i, d)
		enemies.knock(i, aim_dir(), LASSO_THROW, 0.6)
		if is_instance_valid(_rope):
			_rope.queue_free()


# ------------------------------------------------------------------ Dynamite

func _dynamite() -> void:
	play("dynamite")
	var base := aim_dir()
	for k in DYN_COUNT:
		var dir := base.rotated(Vector3.UP, (k - 1) * 0.35)
		var to := ground(feet() + dir * DYN_DIST)
		var stick := MeshInstance3D.new()
		stick.mesh = HeroBody._cyl(0.06, 0.06, 0.35, 8)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.15, 0.12)
		stick.material_override = m
		var spark := particles(0.08, 0.3, 12, Color(1.0, 0.85, 0.3, 1.0), Color(1.0, 0.3, 0.0, 0.0))
		spark.position = Vector3(0, 0.2, 0)
		stick.add_child(spark)
		spawn(stick, chest())
		_sticks.append({"node": stick, "from": chest() + Vector3(0, 0.4, 0), "to": to + Vector3(0, 0.1, 0), "t": 0.0, "fuse": DYN_FUSE})


func _tick_dynamite(dt: float) -> void:
	for k in range(_sticks.size() - 1, -1, -1):
		var s: Dictionary = _sticks[k]
		var node: Node3D = s["node"]
		s["t"] = minf(float(s["t"]) + dt / 0.55, 1.0)
		var t: float = s["t"]
		node.global_position = (s["from"] as Vector3).lerp(s["to"], t) + Vector3(0, 4.0 * t * (1.0 - t) * 2.5, 0)
		node.rotation.x += dt * 9.0 * (1.0 - t)
		s["fuse"] = float(s["fuse"]) - dt
		if float(s["fuse"]) <= 0.0:
			var at: Vector3 = s["to"]
			var d := DYN_DAMAGE * dmg() * pw(1)
			for i in near(at, DYN_RADIUS):
				enemies.damage(i, d)
				enemies.knock(i, enemies.pos[i] - at, 3.0, 0.25)
			fx.burst(at + Vector3(0, 0.6, 0), DYN_RADIUS, Color(1.0, 0.55, 0.15), 0.45)
			ring(at, DYN_RADIUS, Color(1.0, 0.7, 0.3), 0.35)
			flash_light(at + Vector3(0, 1.5, 0), Color(1.0, 0.6, 0.2), 4.0, 9.0, 0.3)
			play("boom", -1.0)
			player.add_shake(0.25)
			node.queue_free()
			_sticks.remove_at(k)


# ------------------------------------------------------------------ High Noon

func _high_noon() -> void:
	play("high_noon")
	_noon.clear()
	var all := Array(near(chest(), NOON_RANGE))
	all.sort_custom(func(a: int, b: int): return enemies.pos[a].distance_squared_to(feet()) < enemies.pos[b].distance_squared_to(feet()))
	for i in near(chest(), NOON_RANGE):
		enemies.freeze(i, NOON_TIME)
	for i in all.slice(0, NOON_MARKS):
		_noon.append(enemies.uid[i])
		var lbl := Label3D.new()   # a red crosshair on each
		lbl.text = "⌖"
		lbl.font_size = 90
		lbl.pixel_size = 0.006
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.modulate = Color(1.0, 0.25, 0.2)
		spawn(lbl, enemies.center_of(i) + Vector3(0, 0.4, 0))
		after(NOON_TIME, lbl.queue_free)
	_noon_t = NOON_TIME


func _fire_noon() -> void:
	play("gunshots", 1.0)
	var d := NOON_DAMAGE * dmg() * pw(2)
	var from := chest() + Vector3(0, 0.4, 0)
	for u in _noon:
		var i := enemies.index_of(int(u))
		if i < 0:
			continue
		var at := enemies.center_of(i)
		enemies.damage(i, d)
		mote(from, (at - from) * 6.0, 0.15, Color(1.0, 0.9, 0.6), 0.12, false, 0.0)
		fx.burst(at, 0.8, Color(1.0, 0.85, 0.5), 0.2)
	player.add_shake(0.35)
