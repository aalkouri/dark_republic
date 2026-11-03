class_name KitBulldog
extends KitPart
## Billy Bulldog
##   1  Fetch!            25 s  throws his bone up to 25 m; enemies within 15 m of it rush to it
##                              and squabble (harmless) for 4 s, then it explodes: 100 in 5 m
##   2  Zoomies           45 s  +100% move speed for 6 s; his dust trail deals 30/s and knocks back
##   3  Who's a Good Boy 120 s  every enemy within 20 m stops to pet him for 4 s (he can't be
##                              hurt), then a bark: 250 within 12 m and a big knockback

const FETCH_RANGE := 25.0
const FETCH_FLIGHT := 0.6
const FETCH_LURE := 15.0
const FETCH_TIME := 4.0
const FETCH_PULL := 7.0
const FETCH_RADIUS := 5.0
const FETCH_DAMAGE := 100.0
const ZOOM_TIME := 6.0
const ZOOM_SPEED := 2.0
const ZOOM_DPS := 30.0
const ZOOM_RADIUS := 2.5
const PET_RADIUS := 20.0
const PET_TIME := 4.0
const BARK_RADIUS := 12.0
const BARK_DAMAGE := 250.0

var _bone: Node3D
var _bone_from := Vector3.ZERO
var _bone_to := Vector3.ZERO
var _bone_t := -1.0              # flying 0..1, then the lure
var _lure_t := 0.0
var _lured: Array = []           # uids
var _zoom_t := 0.0
var _zoom_tick := 0.0
var _pet_t := 0.0
var _pet: Array = []


func cast(i: int) -> void:
	src(i)
	match i:
		0: _fetch()
		1: _zoomies()
		2: _good_boy()


func active(name: String) -> bool:
	match name:
		"fetch": return _bone_t >= 0.0 or _lure_t > 0.0
		"zoomies": return _zoom_t > 0.0
		"good_boy": return _pet_t > 0.0
	return false


func tick(dt: float) -> void:
	src(0)
	_tick_fetch(dt)
	src(1)
	if _zoom_t > 0.0:
		_zoom_t -= dt
		_zoom_tick -= dt
		if _zoom_tick <= 0.0:
			_zoom_tick = 0.25
			for i in near(feet(), ZOOM_RADIUS):
				enemies.damage(i, ZOOM_DPS * 0.25 * dmg() * pw(1))
				enemies.knock(i, enemies.pos[i] - feet(), 2.0, 0.2)
			fx.burst(feet() + Vector3(0, 0.2, 0), 1.2, Color(0.75, 0.62, 0.42, 0.5), 0.3)
		if _zoom_t <= 0.0:
			stats.apply("move_speed", "mult", 1.0 / ZOOM_SPEED)
	src(2)
	if _pet_t > 0.0:
		_pet_t -= dt
		for u in _pet:
			var i := enemies.index_of(int(u))
			if i >= 0:
				var to := feet() - enemies.pos[i]
				to.y = 0.0
				if to.length() > 1.6:
					enemies.pos[i] += to.normalized() * minf(5.0 * dt, to.length() - 1.6)
		if _pet_t <= 0.0:
			_bark()


# ------------------------------------------------------------------ Fetch!

func _fetch() -> void:
	play("fetch")
	_bone_from = chest() + Vector3(0, 0.5, 0)
	_bone_to = aim_point(FETCH_RANGE)
	_bone_t = 0.0
	_bone = Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.93, 0.85)
	var shaft := MeshInstance3D.new()
	shaft.mesh = HeroBody._cap(0.06, 0.6)
	shaft.material_override = mat
	shaft.rotation.z = PI / 2
	_bone.add_child(shaft)
	for sd in [-1.0, 1.0]:
		for up in [-1.0, 1.0]:
			var knob := MeshInstance3D.new()
			knob.mesh = HeroBody._sph(0.08)
			knob.material_override = mat
			knob.position = Vector3(sd * 0.3, up * 0.05, 0)
			_bone.add_child(knob)
	spawn(_bone, _bone_from)


func _tick_fetch(dt: float) -> void:
	if _bone_t >= 0.0:
		_bone_t += dt / FETCH_FLIGHT
		var t := minf(_bone_t, 1.0)
		_bone.global_position = _bone_from.lerp(_bone_to + Vector3(0, 0.2, 0), t) + Vector3(0, 4.0 * t * (1.0 - t) * 4.0, 0)
		_bone.rotation.z += dt * 14.0
		if _bone_t >= 1.0:
			_bone_t = -1.0
			_bone.rotation.z = 0.0
			_lure_t = FETCH_TIME
			_lured.clear()
			for i in near(_bone_to, FETCH_LURE, true):
				enemies.confuse(i, FETCH_TIME)
				_lured.append(enemies.uid[i])
			ring(_bone_to, FETCH_LURE, Color(1.0, 0.95, 0.8, 0.4), 0.6)
	if _lure_t > 0.0:
		_lure_t -= dt
		for u in _lured:   # they scramble for it and squabble over it
			var i := enemies.index_of(int(u))
			if i >= 0:
				var to := _bone_to - enemies.pos[i]
				to.y = 0.0
				if to.length() > 1.2:
					enemies.pos[i] += to.normalized() * minf(FETCH_PULL * dt, to.length() - 1.2)
		if _lure_t <= 0.0:
			var d := FETCH_DAMAGE * dmg() * pw(0)
			for i in near(_bone_to, FETCH_RADIUS):
				enemies.damage(i, d)
				enemies.knock(i, enemies.pos[i] - _bone_to, 3.0, 0.25)
			fx.burst(_bone_to + Vector3(0, 0.6, 0), FETCH_RADIUS, Color(1.0, 0.7, 0.3), 0.45)
			ring(_bone_to, FETCH_RADIUS, Color(1.0, 0.85, 0.5), 0.4)
			play("boom", -2.0)
			if is_instance_valid(_bone):
				_bone.queue_free()


# ------------------------------------------------------------------ Zoomies

func _zoomies() -> void:
	play("zoomies")
	if _zoom_t <= 0.0:
		stats.apply("move_speed", "mult", ZOOM_SPEED)
	_zoom_t = ZOOM_TIME


# ------------------------------------------------------------------ Who's a Good Boy

func _good_boy() -> void:
	play("good_boy")
	_pet.clear()
	for i in near(feet(), PET_RADIUS):
		enemies.stun(i, PET_TIME)
		_pet.append(enemies.uid[i])
	_pet_t = PET_TIME
	player.invuln = maxf(player.invuln, PET_TIME + 0.2)
	for h in 12:   # little hearts drifting up
		mote(chest() + Vector3(randf_range(-1, 1), 0.8, randf_range(-1, 1)), Vector3(0, 1.5, 0), 1.6, Color(1.0, 0.45, 0.6), 0.25, false, 1.0)


func _bark() -> void:
	play("bark", 2.0)
	var d := BARK_DAMAGE * dmg() * pw(2)
	for i in near(feet(), BARK_RADIUS):
		enemies.damage(i, d)
		enemies.knock(i, enemies.pos[i] - feet(), 7.0, 0.35)
	for r in 3:
		after(r * 0.1, func(): ring(feet(), BARK_RADIUS * (0.5 + 0.25 * r), Color(1.0, 0.9, 0.6, 0.7), 0.4))
	player.add_shake(0.6)
