class_name KitGhast
extends KitPart
## Ghast
##   1  Phase           25 s  4 s intangible: no contact damage, drifts through enemies, trees and
##                            walls; enemies passed through take 30 and are slowed 50% for 2 s
##   2  Haunt           45 s  possess the enemy with the most HP within 20 m (epics first, not the
##                            boss) for 10 s: it fights the horde for 3x damage, then bursts for 50%
##                            of its max HP within 4 m
##   3  Banshee Scream 120 s  enemies within 30 m take 15% of max HP and flee for 6 s; those left
##                            under 20% HP die (not the boss)

const PHASE_TIME := 4.0
const PHASE_DAMAGE := 30.0
const PHASE_SLOW := 0.5
const PHASE_SLOW_TIME := 2.0
const PHASE_TOUCH := 1.3
const HAUNT_RADIUS := 20.0
const HAUNT_TIME := 10.0
const HAUNT_MULT := 3.0
const HAUNT_RATE := 0.7             # seconds between its blows
const HAUNT_BURST := 0.5
const HAUNT_BURST_RADIUS := 4.0
const SCREAM_RADIUS := 30.0
const SCREAM_FRAC := 0.15
const SCREAM_FEAR := 6.0
const SCREAM_EXECUTE := 0.2

var _phase_t := 0.0
var _phase_hit := {}
var _phase_tick := 0.0
var _host := 0                      # uid of the possessed enemy
var _host_i := -1
var _host_t := 0.0
var _host_hit := 0.0
var _host_glow: OmniLight3D


func cast(i: int) -> void:
	match i:
		0: _phase()
		1: _haunt()
		2: _scream()


func active(name: String) -> bool:
	match name:
		"phase": return _phase_t > 0.0
		"haunt": return _host != 0
	return false


func tick(dt: float) -> void:
	_tick_phase(dt)
	_tick_haunt(dt)


# ------------------------------------------------------------------ Phase

func _phase() -> void:
	play("phase")
	if _phase_t <= 0.0:
		player.set_phase(true)
		player.dim_mult = 0.35
	_phase_t = PHASE_TIME
	_phase_hit = {}
	fx.burst(chest(), 2.5, k._main, 0.35)


func _tick_phase(dt: float) -> void:
	if _phase_t <= 0.0:
		return
	_phase_t -= dt
	_phase_tick -= dt
	if _phase_tick <= 0.0:
		_phase_tick = 0.08
		var d := PHASE_DAMAGE * dmg()
		for i in near(feet(), PHASE_TOUCH):
			var u := enemies.uid[i]
			if _phase_hit.has(u):
				continue
			_phase_hit[u] = true
			enemies.damage(i, d)
			enemies.slow(i, PHASE_SLOW, PHASE_SLOW_TIME)
			mote(enemies.center_of(i), Vector3(0, 2, 0), 0.6, k._light, 0.18, false, 3.0)
		mote(chest() + Vector3(randf_range(-0.4, 0.4), randf_range(-0.5, 0.6), randf_range(-0.4, 0.4)), Vector3(0, 0.6, 0), 0.9, k._main, 0.3, false, 0.0)
	if _phase_t <= 0.0:
		player.set_phase(false)
		player.dim_mult = 1.0
		fx.burst(chest(), 2.0, k._light, 0.3)


# ------------------------------------------------------------------ Haunt

func _haunt() -> void:
	play("haunt")
	var best := -1
	var best_score := -1.0
	for i in near(feet(), HAUNT_RADIUS, true):
		var score := enemies.hp[i] + (1.0e6 if enemies.epic[i] else 0.0)
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		return
	if _host != 0:
		_release()
	_host = enemies.uid[best]
	_host_i = best
	_host_t = HAUNT_TIME
	_host_hit = 0.0
	enemies.ally_t[best] = HAUNT_TIME + 0.2
	enemies.ally_goal[best] = enemies.pos[best]
	# A stream of spirit from the Ghast into its new body
	var c := enemies.center_of(best)
	for m in 16:
		var f := float(m) / 16.0
		mote(chest().lerp(c, f), Vector3(0, 0.5, 0), 0.4 + f * 0.5, k._light, 0.22, false, 2.0)
	fx.burst(c, 2.0, k._main, 0.4)
	_host_glow = OmniLight3D.new()
	_host_glow.light_color = k._main
	_host_glow.light_energy = 2.0
	_host_glow.omni_range = 5.0
	spawn(_host_glow, c)


func _tick_haunt(dt: float) -> void:
	if _host == 0:
		return
	var i := _host_i
	if i < 0 or i >= enemies.count or enemies.uid[i] != _host or enemies.dead[i]:
		i = enemies.index_of(_host)
		_host_i = i
	if i < 0:   # it died
		_release()
		return
	_host_t -= dt
	var p := enemies.pos[i]
	if is_instance_valid(_host_glow):
		_host_glow.global_position = enemies.center_of(i) + Vector3(0, 0.8, 0)
	# Hunt the nearest goblin; strike everything in reach every HAUNT_RATE s
	var reach := enemies.t_radius[enemies.typ[i]] * enemies.sz[i] + 1.2
	var prey := enemies.nearest_k(p, 18.0, 1)
	enemies.ally_goal[i] = enemies.pos[prey[0]] if not prey.is_empty() else feet()
	_host_hit -= dt
	if _host_hit <= 0.0 and not prey.is_empty() and enemies.pos[prey[0]].distance_to(p) < reach + 1.0:
		_host_hit = HAUNT_RATE
		var d := enemies.t_damage[enemies.typ[i]] * HAUNT_MULT * dmg()
		for e in enemies.query_radius(p + Vector3(0, 0.8, 0), reach, false):
			enemies.damage(e, d, (enemies.pos[e] - p).normalized() * 6.0)
		fx.burst(enemies.center_of(i) + (enemies.pos[prey[0]] - p).normalized() * reach * 0.6, 1.0, k._light, 0.2)
	if randf() < dt * 8.0:
		mote(enemies.center_of(i) + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)), Vector3(0, 1.2, 0), 0.8, k._main, 0.2, false, 0.0)
	if _host_t <= 0.0:
		_burst(i)


## Its time is up: the body bursts.
func _burst(i: int) -> void:
	var at := enemies.pos[i]
	var d := enemies.hp_max[i] * HAUNT_BURST
	enemies.ally_t[i] = 0.0
	for e in enemies.query_radius(at + Vector3(0, 0.8, 0), HAUNT_BURST_RADIUS, false):
		if e != i:
			enemies.damage(e, d)
	enemies.damage(i, enemies.hp[i] + 1.0)
	fx.burst(at + Vector3(0, 0.8, 0), HAUNT_BURST_RADIUS * 1.2, k._light, 0.4)
	ring(at, HAUNT_BURST_RADIUS, k._main, 0.35)
	play("haunt_burst")
	_release()


func _release() -> void:
	_host = 0
	_host_i = -1
	if is_instance_valid(_host_glow):
		_host_glow.queue_free()


# ------------------------------------------------------------------ Banshee Scream

func _scream() -> void:
	play("banshee")
	var at := feet()
	var n := 0
	for i in near(at, SCREAM_RADIUS):
		enemies.damage(i, enemies.hp_max[i] * SCREAM_FRAC * enemies.pct_scale(i))
		enemies.scare(i, SCREAM_FEAR)
		if not enemies.dead[i] and not enemies.is_boss(i) and enemies.hp[i] < enemies.hp_max[i] * SCREAM_EXECUTE:
			enemies.damage(i, enemies.hp[i] + 1.0)
			n += 1
	for r in 4:
		after(r * 0.1, func(): ring(feet(), SCREAM_RADIUS * (0.55 + 0.15 * r), Color(0.8, 0.97, 1.0, 0.8), 0.6))
	fx.burst(chest() + Vector3(0, 0.6, 0), 6.0, k._light, 0.5)
	flash_light(chest() + Vector3(0, 3, 0), Color(0.7, 0.95, 1.0), 5.0, 35.0, 0.6)
	player.add_shake(0.8)
	print_verbose("Banshee Scream executed %d" % n)
