class_name ToadstoolBoss
extends MapBoss
## The Toadstool Knight, the Magical Forest's boss: a 6 m mushroom-capped knight who arrives at
## 8:00 and enrages at 10:00. Beating him unlocks the Castle and makes him playable.
##
## Attacks (every one marked on the ground first, see MapBoss):
##   SPORE SLASH   close: an overhead cut across a 120-degree wedge in front of him; leaves a
##                 lingering violet spore cloud where it lands.
##   FAIRY RING    a ring of mushrooms bursts out of the ground around you: the red band shows
##                 where; step into the middle or out past it.
##   SPORE MORTAR  at range: he lobs spore pods (5, enraged 7) at and around you; each lands where
##                 its circle fills and leaves a small poison puddle.
##   FUNGUS COURT  three giant toadstool guardians rise at marked spots around you for 12 s, each
##                 slamming the ground around itself (marked) every few seconds.

const SCALE := 3.4                 # x ToadstoolModel's 1.8 m: about 6 m tall
const TURN_RATE := 3.0
const GAP := Vector2(1.2, 2.0)
const MELEE_RANGE := 11.0
const SLASH_WARN := 1.5            # seconds of warning (enraged: / 1.6, never under 1 s)
const SLASH_RADIUS := 11.0
const SLASH_HALF := deg_to_rad(60.0)
const SLASH_DAMAGE := 34.0
const CLOUD_RADIUS := 4.0
const CLOUD_LIFE := 4.0
const CLOUD_DPS := 6.0
const RING_WARN := 1.6
const RING_INNER := 3.5
const RING_OUTER := 8.0
const RING_DAMAGE := 30.0
const RING_COOLDOWN := 11.0
const MORTAR_WARN := 1.5
const MORTAR_PODS := 5
const MORTAR_RADIUS := 2.8
const MORTAR_DAMAGE := 20.0
const MORTAR_COOLDOWN := 6.0
const COURT_WARN := 1.5
const COURT_COOLDOWN := 24.0
const COURT_FIRST := 25.0          # seconds after he arrives before the first summons
const GUARDIANS := 3
const GUARDIAN_LIFE := 12.0
const GUARDIAN_SLAM_EVERY := 3.0
const GUARDIAN_SLAM_WARN := 1.2
const GUARDIAN_SLAM_RADIUS := 4.5
const GUARDIAN_DAMAGE := 22.0
const SPORE := Color(0.62, 0.3, 0.95)

var model: ToadstoolModel
var _yaw := 0.0
var _aim := Vector3.FORWARD
var _gap := 2.0
var _ring_cd := 6.0
var _mortar_cd := 2.0
var _court_cd := COURT_FIRST
var _t := 0.0
var _total := 0.0
var _windup := 0.0
var _landed := false
var _step_t := 0.0
var _guardians: Array[Dictionary] = []   # {node, at, t, slam_t}


func stats() -> Dictionary:
	return {"name": "Toadstool Knight", "hp": 5000.0, "speed": 3.8, "radius": 1.8, "height": 6.2, "damage": 40.0, "xp": 400.0}


func display_name() -> String:
	return "THE TOADSTOOL KNIGHT"


func bar_color() -> Color:
	return Color(0.78, 0.18, 0.12)


func sounds() -> Dictionary:
	return {
		"roar": "res://audio/bosses/knight_roar.wav",
		"slash": "res://audio/bosses/knight_slash.wav",
		"burst": "res://audio/bosses/mushroom_burst.wav",
		"lob": "res://audio/bosses/spore_lob.wav",
		"splat": "res://audio/bosses/spore_splat.wav",
		"summon": "res://audio/bosses/court_summon.wav",
		"step": "res://audio/bosses/armor_step.wav",
		"fall": "res://audio/thog/fall.wav",
	}


func _build_model() -> void:
	model = ToadstoolModel.new()
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	var i := row()
	if i >= 0:
		var to := player.global_position - em.pos[i]
		_yaw = atan2(-to.x, -to.z)
	# A soft violet glow so he reads among the neon trees
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.6, 1.0)
	fill.light_energy = 1.5
	fill.omni_range = 14.0
	fill.position = Vector3(0, 6.5, -4.0)
	add_child(fill)
	_sync(0.0)
	play_sfx("roar")


func _physics_process(dt: float) -> void:
	super(dt)
	if state == "dead" or state == "dying":
		return
	if main.state != "playing":
		return
	_tick_guardians(dt)
	_sync(dt)


func _on_hurt() -> void:
	model.flash()


# ------------------------------------------------------------------ deciding

func _think(dt: float, i: int) -> void:
	em.troll_busy = false
	var k := speed_k()
	_gap -= dt * k
	_ring_cd -= dt * k
	_mortar_cd -= dt * k
	_court_cd -= dt * k
	var held := em.is_held(i)
	model.player.speed_scale = 0.0 if held else model.player.speed_scale
	if held:
		return
	model.play("walk", clampf(em.vel[i].length() / 3.8, 0.4, 1.4) * 0.75, true)
	_step_t -= dt
	if _step_t <= 0.0 and em.vel[i].length() > 0.5:
		_step_t = 0.6
		play_sfx("step")
		shake(0.06)
	if _gap > 0.0:
		return
	var d := flat_dist(player.global_position, em.pos[i])
	if _court_cd <= 0.0 and _guardians.is_empty():
		_start("court")
	elif d < MELEE_RANGE:
		_start("ring" if _ring_cd <= 0.0 and randf() < 0.35 else "slash")
	elif _ring_cd <= 0.0 and d < 26.0:
		_start("ring")
	elif _mortar_cd <= 0.0:
		_start("mortar")


func _start(kind: String) -> void:
	state = "attack"
	attack = kind
	counts[kind] = int(counts.get(kind, 0)) + 1
	_t = 0.0
	_landed = false
	em.troll_busy = true
	var i := row()
	var to := player.global_position - em.pos[i]
	to.y = 0.0
	_aim = to.normalized() if to.length() > 0.1 else Vector3(-sin(_yaw), 0, -cos(_yaw))
	match kind:
		"slash":
			# The blade comes down exactly when the wedge fills
			_windup = warn_time(SLASH_WARN)
			var speed := ToadstoolModel.seg_time("slash") * ToadstoolModel.SLASH_AT / _windup
			model.play("slash", speed)
			_total = ToadstoolModel.seg_time("slash", speed)
			warn_wedge(em.pos[i], _aim, SLASH_RADIUS, SLASH_HALF, SLASH_WARN, _land_slash)
		"ring":
			_ring_cd = RING_COOLDOWN
			_windup = warn_time(RING_WARN)
			_cast_anim(_windup)
			var c := player_ahead(0.4)
			warn_ring(c, RING_INNER, RING_OUTER, RING_WARN, func(): _land_ring(c))
		"mortar":
			_mortar_cd = MORTAR_COOLDOWN
			_windup = 0.5
			_cast_anim(_windup)
		"court":
			_court_cd = COURT_COOLDOWN
			_windup = warn_time(COURT_WARN)
			_cast_anim(_windup)
			play_sfx("summon")
			var pp := player.global_position
			var a0 := randf() * TAU
			for g in GUARDIANS:
				var a := a0 + TAU * g / GUARDIANS
				var at := ground(pp + Vector3(cos(a), 0, sin(a)) * 7.5)
				warn_circle(at, 3.0, COURT_WARN, func(): _raise_guardian(at), Color(0.8, 0.3, 1.0))
			main.hud.flash_message("THE FUNGUS COURT RISES!", 2.5)


## The ability clip's thrust lands at `windup` seconds.
func _cast_anim(windup: float) -> void:
	var speed := ToadstoolModel.seg_time("cast") * ToadstoolModel.CAST_AT / windup
	model.play("cast", speed)
	_total = ToadstoolModel.seg_time("cast", speed)


func _tick_attack(dt: float) -> void:
	_t += dt
	if not _landed and _t >= _windup:
		_landed = true
		if attack == "mortar":
			_fire_mortar()
	if _t >= maxf(_total, _windup) + 0.15:
		state = "walk"
		em.troll_busy = false
		_gap = randf_range(GAP.x, GAP.y)


# ------------------------------------------------------------------ attacks landing

func _land_slash() -> void:
	var i := row()
	if i < 0:
		return
	var o := em.pos[i]
	play_sfx("slash")
	shake(0.5)
	var to := player.global_position - o
	to.y = 0.0
	if to.length() < SLASH_RADIUS and to.length() > 0.01 and _aim.angle_to(to.normalized()) <= SLASH_HALF:
		hit_player(SLASH_DAMAGE, to.normalized())
	var c := ground(o + _aim * SLASH_RADIUS * 0.6)
	add_hazard(c, CLOUD_RADIUS * (1.25 if is_enraged else 1.0), CLOUD_LIFE, SPORE, CLOUD_DPS)
	if fx:
		fx.burst(c + Vector3(0, 0.8, 0), CLOUD_RADIUS, SPORE, 0.6)


func _land_ring(c: Vector3) -> void:
	play_sfx("burst")
	shake(0.6)
	var d := flat_dist(player.global_position, c)
	if d >= RING_INNER and d <= RING_OUTER and not airborne():
		hit_player(RING_DAMAGE, player.global_position - c)
	# Mushrooms burst up all round the band, then wither
	for k in 14:
		var a := TAU * k / 14.0
		var p := ground(c + Vector3(cos(a), 0, sin(a)) * (RING_INNER + RING_OUTER) * 0.5)
		_pop_mushroom(p, 1.6, 2.5)
		if fx and k % 2 == 0:
			fx.burst(p + Vector3(0, 0.6, 0), 1.6, Color(0.95, 0.85, 0.7), 0.4)


func _fire_mortar() -> void:
	var i := row()
	if i < 0:
		return
	var from := em.pos[i] + Vector3(0, 5.0, 0)
	var n := MORTAR_PODS + (2 if is_enraged else 0)
	var secs := warn_time(MORTAR_WARN)
	play_sfx("lob")
	for k in n:
		var at := player_ahead(secs * 0.5) if k == 0 else ground(player.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(3.0, 8.0))
		lob(from, at + Vector3(0, 0.4, 0), secs, SPORE, 0.55, 7.0 + randf() * 3.0)
		warn_circle(at, MORTAR_RADIUS, MORTAR_WARN, func(): _land_pod(at))


func _land_pod(at: Vector3) -> void:
	play_sfx("splat")
	if player_in_circle(at, MORTAR_RADIUS) and not airborne():
		hit_player(MORTAR_DAMAGE, player.global_position - at)
	add_hazard(at, MORTAR_RADIUS, 3.0, Color(0.45, 0.85, 0.3), CLOUD_DPS)
	if fx:
		fx.burst(at + Vector3(0, 0.5, 0), MORTAR_RADIUS, SPORE, 0.4)


# ------------------------------------------------------------------ the Fungus Court

func _raise_guardian(at: Vector3) -> void:
	var g := _pop_mushroom(at, 4.5, GUARDIAN_LIFE)
	play_sfx("burst", 0.8)
	shake(0.4)
	if player_in_circle(at, 3.0):
		hit_player(GUARDIAN_DAMAGE, player.global_position - at)
	_guardians.append({"node": g, "at": at, "t": 0.0, "slam_t": 0.8 + _guardians.size() * 0.9})


func _tick_guardians(dt: float) -> void:
	for k in range(_guardians.size() - 1, -1, -1):
		var g: Dictionary = _guardians[k]
		g["t"] += dt
		# The mushroom can be freed early (e.g. the boss dies and clears its props) —
		# drop the entry before anything reads it as a typed Node3D.
		if g["t"] >= GUARDIAN_LIFE or not is_instance_valid(g["node"]):
			_guardians.remove_at(k)
			continue
		g["slam_t"] -= dt * speed_k()
		if g["slam_t"] <= 0.0 and g["t"] < GUARDIAN_LIFE - GUARDIAN_SLAM_WARN:
			g["slam_t"] = GUARDIAN_SLAM_EVERY
			var at: Vector3 = g["at"]
			var node: Node3D = g["node"]
			warn_circle(at, GUARDIAN_SLAM_RADIUS, GUARDIAN_SLAM_WARN, func():
				play_sfx("burst", 0.7)
				if is_instance_valid(node):
					var tw := create_tween()
					tw.tween_property(node, "scale:y", node.scale.y * 0.6, 0.06)
					tw.tween_property(node, "scale:y", node.scale.y, 0.25)
				if player_in_circle(at, GUARDIAN_SLAM_RADIUS) and not airborne():
					hit_player(GUARDIAN_DAMAGE, player.global_position - at)
				if fx:
					fx.burst(at + Vector3(0, 0.5, 0), GUARDIAN_SLAM_RADIUS, Color(0.9, 0.8, 0.65), 0.45))


## A toadstool `height` tall that grows out of the ground, stands for `life` s and sinks back.
func _pop_mushroom(at: Vector3, height: float, life: float) -> Node3D:
	var n := Node3D.new()
	n.top_level = true
	var stem := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18 * height
	cm.bottom_radius = 0.24 * height
	cm.height = height * 0.7
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.93, 0.88, 0.76)
	cm.material = sm
	stem.mesh = cm
	stem.position = Vector3(0, height * 0.35, 0)
	n.add_child(stem)
	var cap := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.55 * height
	dm.height = 0.55 * height
	dm.is_hemisphere = true
	var capm := StandardMaterial3D.new()
	capm.albedo_color = Color(0.8, 0.1, 0.07) if height > 3.0 else Color(0.75, 0.45, 1.0)
	capm.emission_enabled = height <= 3.0
	capm.emission = Color(0.6, 0.3, 1.0)
	capm.roughness = 0.3
	dm.material = capm
	cap.mesh = dm
	cap.scale = Vector3(1, 0.6, 1)
	cap.position = Vector3(0, height * 0.66, 0)
	n.add_child(cap)
	add_child(n)
	n.global_position = at
	n.scale = Vector3(1, 0.05, 1)
	n.rotation.y = randf() * TAU
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(life - 0.6, 0.1))
	tw.tween_property(n, "scale", Vector3(1, 0.02, 1), 0.4)
	tw.tween_callback(n.queue_free)
	return n


# ------------------------------------------------------------------ enrage, death, drawing

func _on_enrage() -> void:
	model.set_enrage(1.0)
	var spores := Abilities._flame_particles(0.7, 1.2, 40)
	spores.position = Vector3(0, 1.6, 0)
	spores.emission_sphere_radius = 0.5
	spores.color = SPORE
	model.add_child(spores)


func _on_die() -> void:
	model.play("death", 0.7)
	play_sfx("roar", 0.8)
	for g in _guardians:
		if is_instance_valid(g["node"]):
			(g["node"] as Node).queue_free()
	_guardians.clear()


func _tick_death(dt: float) -> bool:
	# Topples forward onto his cap, then sinks into the moss
	var f := clampf((_die_t - 0.5) / 1.3, 0.0, 1.0)
	model.rotation = Vector3(f * f * PI * 0.47, 0, 0)
	if f >= 1.0 and not has_meta("crashed"):
		set_meta("crashed", true)
		play_sfx("fall")
		shake(0.8)
		if fx:
			fx.burst(global_position + Vector3(0, 1, 0) + Vector3(-sin(_yaw), 0, -cos(_yaw)) * 3.5, 7.0, SPORE, 0.8)
	if _die_t > 4.0:
		model.position.y -= dt * 0.8
	if _die_t > 7.0:
		model.visible = false
		return true
	return false


func _sync(dt: float) -> void:
	var i := row()
	if i < 0:
		return
	global_position = em.pos[i]
	if state == "walk":
		var v := em.vel[i]
		var want := _yaw
		var to := player.global_position - em.pos[i]
		if Vector2(v.x, v.z).length() > 0.4:
			want = atan2(-v.x, -v.z)
		elif to.length() > 0.1:
			want = atan2(-to.x, -to.z)
		_yaw = rotate_toward(_yaw, want, TURN_RATE * dt)
	else:
		_yaw = rotate_toward(_yaw, atan2(-_aim.x, -_aim.z), 6.0 * dt)
	rotation.y = _yaw
