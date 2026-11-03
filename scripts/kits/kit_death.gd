class_name KitDeath
extends KitPart
## Death
##   1  Harvest                 30 s  reaps every enemy within 12 m under 30% HP (not the boss);
##                                    each soul +2% damage for 20 s, up to +50%
##   2  Mark of the Inevitable  45 s  marks the 8 enemies with the most HP within 30 m; after
##                                    5 s each takes 400
##   3  Overtime               120 s  the run clock and spawns stop for 10 s; +100% damage and
##                                    kills drop 2x XP

const HARVEST_RADIUS := 12.0
const HARVEST_BELOW := 0.30
const SOUL_BONUS := 0.02
const SOUL_MAX := 0.5
const SOUL_TIME := 20.0
const MARK_COUNT := 8
const MARK_RANGE := 30.0
const MARK_DELAY := 5.0
const MARK_DAMAGE := 400.0
const OVERTIME := 10.0
const OVERTIME_DAMAGE := 2.0

var souls := 0.0                 # the current soul bonus (+damage)
var _soul_t := 0.0
var _soul_applied := 1.0
var _marks: Array = []           # {uid, t, node}
var _over_t := 0.0
var _over_mult := OVERTIME_DAMAGE


func cast(i: int) -> void:
	src(i)
	match i:
		0: _harvest()
		1: _mark()
		2: _overtime()


func active(name: String) -> bool:
	match name:
		"souls": return souls > 0.0
		"mark": return not _marks.is_empty()
		"overtime": return _over_t > 0.0
	return false


func tick(dt: float) -> void:
	if _soul_t > 0.0:
		_soul_t -= dt
		if _soul_t <= 0.0:
			_set_souls(0.0)
	src(1)
	for k in range(_marks.size() - 1, -1, -1):
		var m: Dictionary = _marks[k]
		m["t"] -= dt
		var i := enemies.index_of(int(m["uid"]))
		var node: Node3D = m["node"]
		if i < 0:
			node.queue_free()
			_marks.remove_at(k)
			continue
		node.global_position = enemies.center_of(i) + Vector3(0, 1.6, 0)
		node.scale = Vector3.ONE * (1.0 + 0.25 * sin(float(m["t"]) * 10.0))
		if float(m["t"]) <= 0.0:   # time's up
			enemies.damage(i, MARK_DAMAGE * dmg() * pw(1))
			fx.burst(enemies.center_of(i), 2.0, Color(0.55, 0.9, 1.0), 0.35)
			node.queue_free()
			_marks.remove_at(k)
			play("death_toll", -4.0)
	if _over_t > 0.0:
		_over_t -= dt
		if _over_t <= 0.0:
			_end_overtime()


func _set_souls(v: float) -> void:
	stats.apply("damage", "mult", 1.0 / _soul_applied)
	souls = v
	_soul_applied = 1.0 + souls
	stats.apply("damage", "mult", _soul_applied)


# ------------------------------------------------------------------ Harvest

func _harvest() -> void:
	play("harvest")
	var at := feet()
	var reaped := 0
	for i in near(at, HARVEST_RADIUS * (0.8 + 0.2 * pw(0)), true):
		if enemies.hp[i] < enemies.hp_max[i] * HARVEST_BELOW:
			var c := enemies.center_of(i)
			enemies.damage(i, enemies.hp[i] + 1.0)
			reaped += 1
			mote(c, Vector3(0, 3, 0), 0.9, Color(0.6, 0.95, 1.0), 0.3, true, 2.0)   # its soul, drawn to him
	if reaped > 0:
		_set_souls(minf(SOUL_MAX, souls + SOUL_BONUS * reaped))
		_soul_t = SOUL_TIME
	ring(at, HARVEST_RADIUS, Color(0.55, 0.9, 1.0, 0.6), 0.5)
	ring(at, HARVEST_RADIUS * 0.6, Color(0.3, 0.3, 0.4, 0.5), 0.4)


# ------------------------------------------------------------------ Mark of the Inevitable

func _mark() -> void:
	play("mark")
	var all := Array(near(chest(), MARK_RANGE))
	all.sort_custom(func(a: int, b: int): return enemies.hp[a] > enemies.hp[b])
	for i in all.slice(0, MARK_COUNT):
		var lbl := Label3D.new()   # an hourglass sigil over its head
		lbl.text = "⧗"
		lbl.font_size = 96
		lbl.pixel_size = 0.006
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.modulate = Color(0.6, 0.95, 1.0)
		lbl.outline_size = 12
		spawn(lbl, enemies.center_of(i) + Vector3(0, 1.6, 0))
		_marks.append({"uid": enemies.uid[i], "t": MARK_DELAY, "node": lbl})


# ------------------------------------------------------------------ Overtime

func _overtime() -> void:
	play("overtime")
	var main = get_tree().current_scene
	if main != null and "time_stop" in main:
		main.time_stop = OVERTIME
		main.xp_bonus = 2.0
	if _over_t <= 0.0:
		_over_mult = 1.0 + (OVERTIME_DAMAGE - 1.0) * pw(2)
		stats.apply("damage", "mult", _over_mult)
	_over_t = OVERTIME
	fx.burst(chest(), 5.0, Color(0.55, 0.9, 1.0), 0.5)
	ring(feet(), 20.0, Color(0.55, 0.9, 1.0, 0.5), 0.8)
	player.add_shake(0.4)


func _end_overtime() -> void:
	stats.apply("damage", "mult", 1.0 / _over_mult)
	var main = get_tree().current_scene
	if main != null and "xp_bonus" in main:
		main.xp_bonus = 1.0
