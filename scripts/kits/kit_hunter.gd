class_name KitHunter
extends KitPart
## Vampire Hunter
##   1  Holy Water      30 s  a flask thrown where you aim: an 8 m pool for 6 s, 25 dmg/s, 40% slow
##   2  Stake Volley    45 s  16 stakes in a ring, 90 each; enemies hit are pinned for 2 s
##   3  Hunter's Night 120 s  10 s: enemies move at half speed; your bolts lock on to the 3 enemies
##                            with the most HP for 3x damage; each kill heals 1% of max HP

const WATER_RANGE := 25.0
const WATER_RADIUS := 4.0            # an 8 m pool
const WATER_TIME := 6.0
const WATER_DPS := 25.0
const WATER_SLOW := 0.6
const WATER_FLIGHT := 0.55
const VOLLEY_COUNT := 16
const VOLLEY_DAMAGE := 90.0
const VOLLEY_SPEED := 30.0
const VOLLEY_RANGE := 24.0
const NIGHT_TIME := 10.0
const NIGHT_RADIUS := 45.0
const NIGHT_SLOW := 0.5
const NIGHT_HEAL := 0.01

var _vial: MeshInstance3D
var _vial_t := -1.0
var _vial_from := Vector3.ZERO
var _vial_to := Vector3.ZERO
var _pools: Array = []              # {pos, t, root, tick}
var _night_t := 0.0
var _night_tick := 0.0
var _moon: OmniLight3D


func cast(i: int) -> void:
	match i:
		0: _holy_water()
		1: _stake_volley()
		2: _hunters_night()


func active(name: String) -> bool:
	match name:
		"holy_water": return not _pools.is_empty() or _vial_t >= 0.0
		"hunt": return _night_t > 0.0
	return false


func tick(dt: float) -> void:
	_tick_vial(dt)
	_tick_pools(dt)
	_tick_night(dt)


func on_kill(_at: Vector3, _type_id: int) -> void:
	if _night_t > 0.0:
		k.heal_pct(NIGHT_HEAL)


# ------------------------------------------------------------------ Holy Water

func _holy_water() -> void:
	play("holy_water")
	_vial_from = player.model.staff_tip() + Vector3(0, 0.4, 0)
	_vial_to = aim_point(WATER_RANGE)
	_vial_t = 0.0
	_vial = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.42
	sm.material = glow_mat(Color(0.75, 0.9, 1.0, 0.9), false)
	_vial.mesh = sm
	spawn(_vial, _vial_from)


func _tick_vial(dt: float) -> void:
	if _vial_t < 0.0:
		return
	_vial_t += dt / WATER_FLIGHT
	var t := minf(_vial_t, 1.0)
	_vial.global_position = _vial_from.lerp(_vial_to, t) + Vector3(0, 4.0 * t * (1.0 - t) * 4.0, 0)
	_vial.rotation.x += dt * 14.0
	if _vial_t >= 1.0:
		_vial_t = -1.0
		_vial.queue_free()
		_splash(_vial_to)


func _splash(at: Vector3) -> void:
	var root := Node3D.new()
	spawn(root, at)
	var pool := GroundDisc.create(WATER_RADIUS, Color(0.65, 0.85, 1.0, 0.4), true)
	root.add_child(pool)
	var rim := GroundDisc.create(WATER_RADIUS, Color(0.9, 0.97, 1.0, 0.55), true)
	rim.set_ring(0.9)
	root.add_child(rim)
	var sparkle := particles(0.12, 1.0, 40, Color(1, 1, 1, 0.9), Color(0.6, 0.85, 1.0, 0.0))
	sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkle.emission_sphere_radius = WATER_RADIUS * 0.8
	sparkle.gravity = Vector3(0, 1.5, 0)
	sparkle.scale = Vector3(1, 0.1, 1)
	root.add_child(sparkle)
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.85, 1.0)
	light.light_energy = 1.4
	light.omni_range = WATER_RADIUS * 2.0
	light.position.y = 1.0
	root.add_child(light)
	_pools.append({"pos": at, "t": WATER_TIME, "root": root, "tick": 0.0, "pool": pool, "rim": rim})
	fx.burst(at + Vector3(0, 0.5, 0), 2.5, Color(0.8, 0.92, 1.0), 0.35)
	play("splash")


func _tick_pools(dt: float) -> void:
	for p in range(_pools.size() - 1, -1, -1):
		var pd: Dictionary = _pools[p]
		pd["t"] -= dt
		var fade := clampf(pd["t"] / 0.6, 0.0, 1.0)
		(pd["pool"] as GroundDisc).alpha = 0.4 * fade
		(pd["rim"] as GroundDisc).alpha = (0.4 + 0.15 * sin(pd["t"] * 6.0)) * fade
		if pd["t"] <= 0.0:
			(pd["root"] as Node3D).queue_free()
			_pools.remove_at(p)
			continue
		pd["tick"] -= dt
		if pd["tick"] <= 0.0:
			pd["tick"] = 0.25
			var d := WATER_DPS * 0.25 * dmg()
			for i in near(pd["pos"], WATER_RADIUS):
				enemies.dot_damage(i, d)
				enemies.slow(i, WATER_SLOW, 0.4)


# ------------------------------------------------------------------ Stake Volley

func _stake_volley() -> void:
	play("stake_volley")
	if k.weapons == null:
		return
	var from := chest() + Vector3(0, 0.3, 0)
	var kind := WeaponSystem.P_KINDS.find("stake")
	var off := randf() * TAU
	for s in VOLLEY_COUNT:
		var a := off + TAU * s / VOLLEY_COUNT
		var dir := Vector3(cos(a), 0.0, sin(a))
		k.weapons.spawn_projectile(from + dir * 0.6, dir * VOLLEY_SPEED, VOLLEY_RANGE / VOLLEY_SPEED, VOLLEY_DAMAGE * dmg(), 1, kind)
	ring(feet(), 3.0, k._light, 0.25)
	player.add_shake(0.25)


# ------------------------------------------------------------------ Hunter's Night

func _hunters_night() -> void:
	play("hunters_night")
	if _night_t <= 0.0:
		k._dim_world(true, 0.35)
		_moon = OmniLight3D.new()
		_moon.light_color = Color(1.0, 0.35, 0.35)
		_moon.light_energy = 1.4
		_moon.omni_range = 16.0
		_moon.position.y = 6.0
		player.add_child(_moon)
	_night_t = NIGHT_TIME
	_night_tick = 0.0
	ring(feet(), NIGHT_RADIUS * 0.5, Color(0.9, 0.2, 0.25), 0.6)


func _tick_night(dt: float) -> void:
	if _night_t <= 0.0:
		return
	_night_t -= dt
	_night_tick -= dt
	if _night_tick <= 0.0:
		_night_tick = 0.25
		for i in near(feet(), NIGHT_RADIUS):
			enemies.slow(i, NIGHT_SLOW, 0.4)
		# A red mark over each hunted target
		if k.weapons:
			for i in k.weapons._top_hp(chest(), 30.0, RosterKit.HUNT_TARGETS):
				var top := enemies.pos[i] + Vector3(0, enemies.t_height[enemies.typ[i]] * enemies.sz[i] + 0.7, 0)
				mote(top, Vector3.ZERO, 0.3, Color(1.0, 0.2, 0.2), 0.3, false, 0.0)
	if _night_t <= 0.0:
		k._dim_world(false)
		if is_instance_valid(_moon):
			_moon.queue_free()
