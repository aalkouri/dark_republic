class_name KitWitch
extends KitPart
## Bog Witch
##   1  Bubbling Cauldron  35 s  a cauldron stands for 15 s, spitting a glob at an enemy within
##                               15 m every second (50); you heal 2% of max HP a second next to it
##   2  Hex of Silence     45 s  enemies within 20 m are hexed for 8 s (+25% damage taken); a
##                               hexed enemy that dies passes the hex on to its 2 nearest
##   3  Swamp's Fury      120 s  the ground within 30 m turns to bog for 12 s: enemies slowed 70%;
##                               every second hands drag the 3 nearest under (elites and the boss
##                               take 25% of max HP instead)

const CAULDRON_TIME := 15.0
const CAULDRON_RANGE := 15.0
const CAULDRON_DAMAGE := 50.0
const CAULDRON_HEAL := 0.02
const CAULDRON_NEAR := 3.0
const HEX_RADIUS := 20.0
const HEX_TIME := 8.0
const HEX_SPREAD := 2
const FURY_RADIUS := 30.0
const FURY_TIME := 12.0
const FURY_SLOW := 0.3
const FURY_DRAG := 3
const FURY_BIG := 0.25

var _cauldron: Node3D
var _cauldron_t := 0.0
var _spit_t := 0.0
var _heal_t := 0.0
var _hexed := {}                 # uid -> [time left, last position]
var _fury_t := 0.0
var _fury_tick := 0.0
var _fury_at := Vector3.ZERO
var _fury_disc: GroundDisc


func cast(i: int) -> void:
	src(i)
	match i:
		0: _place_cauldron()
		1: _hex()
		2: _swamp_fury()


func active(name: String) -> bool:
	match name:
		"cauldron": return _cauldron_t > 0.0
		"hex": return not _hexed.is_empty()
		"fury": return _fury_t > 0.0
	return false


func tick(dt: float) -> void:
	src(0)
	_tick_cauldron(dt)
	src(1)
	_tick_hex(dt)
	src(2)
	_tick_fury(dt)


# ------------------------------------------------------------------ Bubbling Cauldron

func _place_cauldron() -> void:
	play("cauldron")
	if is_instance_valid(_cauldron):
		_cauldron.queue_free()
	_cauldron = Node3D.new()
	var pot := MeshInstance3D.new()
	pot.mesh = HeroBody._sph(0.55)
	pot.scale = Vector3(1.0, 0.8, 1.0)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.12, 0.13)
	iron.metallic = 0.6
	pot.material_override = iron
	pot.position.y = 0.45
	_cauldron.add_child(pot)
	var brew := MeshInstance3D.new()
	brew.mesh = HeroBody._cyl(0.44, 0.44, 0.04, 16)
	brew.material_override = glow_mat(Color(0.55, 0.95, 0.2, 0.9), false)
	brew.position.y = 0.78
	_cauldron.add_child(brew)
	var steam := particles(0.25, 1.2, 24, Color(0.6, 1.0, 0.3, 0.5), Color(0.3, 0.5, 0.15, 0.0))
	steam.position.y = 0.8
	steam.gravity = Vector3(0, 1.5, 0)
	_cauldron.add_child(steam)
	spawn(_cauldron, ground(feet() - aim_dir() * -1.5))
	_cauldron_t = CAULDRON_TIME
	_spit_t = 0.3


func _tick_cauldron(dt: float) -> void:
	if _cauldron_t <= 0.0:
		return
	_cauldron_t -= dt
	var at := _cauldron.global_position
	_spit_t -= dt
	if _spit_t <= 0.0:
		_spit_t = 1.0
		var t := enemies.nearest_k(at + Vector3(0, 0.8, 0), CAULDRON_RANGE, 1)
		if not t.is_empty():
			var i: int = t[0]
			enemies.damage(i, CAULDRON_DAMAGE * dmg() * pw(0))
			enemies.slow(i, 0.8, 1.5)
			var to := enemies.center_of(i)
			mote(at + Vector3(0, 1.0, 0), (to - at) * 3.0 + Vector3(0, 3, 0), 0.35, Color(0.6, 1.0, 0.25), 0.25, false, 0.0)
			fx.burst(to, 1.0, Color(0.55, 0.9, 0.2, 0.7), 0.25)
	_heal_t -= dt
	if _heal_t <= 0.0:
		_heal_t = 1.0
		if feet().distance_to(at) < CAULDRON_NEAR:
			k.heal_pct(CAULDRON_HEAL)
	if _cauldron_t <= 0.0:
		_cauldron.queue_free()


# ------------------------------------------------------------------ Hex of Silence

func _hex() -> void:
	play("hex")
	for i in near(feet(), HEX_RADIUS):
		_hex_one(i)
	ring(feet(), HEX_RADIUS, Color(0.65, 0.35, 0.9, 0.6), 0.6)


func _hex_one(i: int) -> void:
	enemies.curse(i, HEX_TIME)
	_hexed[enemies.uid[i]] = [HEX_TIME, enemies.pos[i]]
	mote(enemies.center_of(i), Vector3(0, 1.5, 0), 0.8, Color(0.7, 0.4, 1.0), 0.2, false, 1.0)


func _tick_hex(dt: float) -> void:
	for u in _hexed.keys():
		var h: Array = _hexed[u]
		h[0] = float(h[0]) - dt
		var i := enemies.index_of(int(u))
		if i >= 0:
			h[1] = enemies.pos[i]
		if float(h[0]) <= 0.0 or i < 0:
			_hexed.erase(u)


## A hexed enemy died: the hex jumps to its 2 nearest neighbours.
func on_kill(at: Vector3, _type_id: int) -> void:
	var dead_u := -1
	for u in _hexed:
		var p: Vector3 = _hexed[u][1]
		if Vector2(p.x - at.x, p.z - at.z).length() < 1.5:
			dead_u = int(u)
			break
	if dead_u < 0:
		return
	_hexed.erase(dead_u)
	src(1)
	var n := 0
	for j in enemies.nearest_k(at + Vector3(0, 0.6, 0), 8.0, HEX_SPREAD + 3):
		if n >= HEX_SPREAD or _hexed.has(enemies.uid[j]) or enemies.uid[j] == dead_u:
			continue
		_hex_one(j)
		n += 1


# ------------------------------------------------------------------ Swamp's Fury

func _swamp_fury() -> void:
	play("swamp_fury")
	_fury_at = feet()
	_fury_t = FURY_TIME
	_fury_tick = 0.5
	if is_instance_valid(_fury_disc):
		_fury_disc.queue_free()
	_fury_disc = GroundDisc.create(FURY_RADIUS, Color(0.25, 0.4, 0.12, 0.45))
	spawn(_fury_disc, _fury_at)
	player.add_shake(0.4)


func _tick_fury(dt: float) -> void:
	if _fury_t <= 0.0:
		return
	_fury_t -= dt
	for i in near(_fury_at, FURY_RADIUS):
		enemies.slow(i, FURY_SLOW, 0.3)
	_fury_tick -= dt
	if _fury_tick <= 0.0:
		_fury_tick = 1.0
		for i in enemies.nearest_k(feet() + Vector3(0, 0.6, 0), FURY_RADIUS, FURY_DRAG):
			if _fury_at.distance_to(enemies.pos[i]) > FURY_RADIUS:
				continue
			var at := enemies.center_of(i)
			if enemies.is_boss(i) or enemies.epic[i] == 1 or enemies.typ[i] == EnemyManager.SUB_BOSS:
				enemies.damage(i, enemies.hp_max[i] * FURY_BIG * minf(pw(2), 2.0))
			else:
				enemies.damage(i, enemies.hp[i] + 1.0)   # dragged under the bog
			fx.burst(at - Vector3(0, 0.6, 0), 1.2, Color(0.3, 0.45, 0.15, 0.8), 0.4)
	if is_instance_valid(_fury_disc):
		_fury_disc.alpha = 0.45 * clampf(_fury_t / 1.0, 0.0, 1.0)
	if _fury_t <= 0.0 and is_instance_valid(_fury_disc):
		_fury_disc.queue_free()
