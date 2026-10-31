class_name ThogBoss
extends Node3D
## Thog the Troll, the Swamp's boss. He arrives with 2 minutes of the run left (8:00). If he's
## still standing 2 minutes later he ENRAGES: his attacks come twice as fast. The run is only
## won by killing him. Beating him also unlocks the next map and Thog as a playable character.
##
## Body: ThogModel (the Ogre model re-tinted blue for now), about 10 m tall. Health, damage
## taken and walking are a crowd row in EnemyManager (type TROLL), so every weapon, ability,
## burn and freeze works on him. This node draws him, picks his attacks and holds him still
## (EnemyManager.troll_busy) while he swings.
##
## Three attacks, each telegraphed on the ground in red before it lands:
##   SLAM    both fists into the ground in front of him: a heavy hit in the marked circle, then
##           a shockwave ring rolls outward (jump over it).
##   SWEEP   a wide swing across a 130-degree wedge in front of him: big damage and knockback.
##   BELLOW  a roar that calls a ring of goblins (and a brute) around you.
## And at 75%, 50% and 10% health, the QUAKE: he stomps the ground over and over (your camera
## shakes the whole time) while the entire map lights up red - everything but the swamp pools.
## You have QUAKE_WARN seconds to get into a pool (a glowing arrow floats down over each one); if you're anywhere else when it lands, it
## takes QUAKE_FRAC of your max HP straight through your shield, and wipes the shield out.

signal defeated
signal enraged

const SCALE := 4.4                  # x ThogModel's 2.3 m: about 10 m tall
const ENRAGE_AFTER := 120.0         # seconds after he arrives
const ENRAGE_SPEED := 2.0           # enraged: attack animations, wind-ups and gaps all x2 faster
const TURN_RATE := 2.2              # radians per second while walking
# Attack tuning (unenraged)
const GAP := Vector2(1.6, 2.4)      # pause between attacks
const SLAM_SPEED := 0.55            # animation speed: the wind-up is about 1.7 s
const SLAM_AT := 0.75               # fraction of the slam segment when the fists land
const SLAM_REACH := 6.0             # impact centre this far in front of him
const SLAM_RADIUS := 7.0
const SLAM_DAMAGE := 40.0
const WAVE_RADIUS := 20.0           # the shockwave ring rolls out this far...
const WAVE_TIME := 0.8              # ...over this long
const WAVE_BAND := 1.6
const WAVE_DAMAGE := 22.0
const SWEEP_SPEED := 0.75           # wind-up about 1.7 s
const SWEEP_AT := 0.83
const SWEEP_RADIUS := 14.0
const SWEEP_HALF_ANGLE := deg_to_rad(65.0)
const SWEEP_DAMAGE := 32.0
const BELLOW_SPEED := 0.5
const BELLOW_AT := 0.4
const BELLOW_COOLDOWN := 14.0
const BELLOW_GOBLINS := 14
const QUAKE_AT := [0.75, 0.5, 0.1]  # health fractions that set off a quake
const QUAKE_WARN := 10.0            # seconds to get into a pool (arrows float over every pool)
const QUAKE_FRAC := 0.5             # of max HP, through shields
const QUAKE_STOMP := 0.6            # seconds between stomps
const MELEE_RANGE := 12.0           # closer than this he slams or sweeps; further, he walks / roars
const SOUNDS := {
	"roar": "res://audio/thog/roar.wav",
	"slam": "res://audio/thog/slam.wav",
	"sweep": "res://audio/thog/sweep.wav",
	"step": "res://audio/thog/step.wav",
	"fall": "res://audio/thog/fall.wav",
}

var main: Node
var em: EnemyManager
var player: Player
var fx: FxManager
var model: ThogModel
var uid := -1
var idx := -1
var state := "walk"                 # walk | attack | dying | dead
var attack := ""                    # slam | sweep | bellow
var is_enraged := false
var alive_time := 0.0
var counts := {"slam": 0, "sweep": 0, "bellow": 0, "hits": 0, "quake": 0, "quake_hits": 0}   # for tests
var _arrows: Node3D                 # the quake's arrows over the pools (get in here!)
var _quakes_done := 0               # QUAKE_AT thresholds already used
var _stomp_t := 0.0
var _t := 0.0                       # time into the current attack
var _windup := 0.0                  # seconds from the start of the attack to its impact
var _total := 0.0                   # seconds the attack's animation takes
var _landed := false
var _gap := 1.5
var _bellow_cd := 4.0
var _yaw := 0.0
var _aim := Vector3.FORWARD         # attack direction, locked when the wind-up starts
var _tele: GroundDisc               # the red telegraph
var _waves: Array[Dictionary] = []  # slam shockwaves rolling out
var _last_hp := 0.0
var _step_t := 0.0
var _die_t := 0.0
var _sfx := {}
var _bar_root: Control
var _bar: ProgressBar
var _bar_label: Label


## Spawn Thog at `at` with `hp_mult` x his base health; he faces the player.
func setup(p_main: Node, at: Vector3, hp_mult: float) -> void:
	main = p_main
	em = main.enemies
	player = main.player
	fx = main.fx
	idx = em.spawn(EnemyManager.TROLL, at, hp_mult)
	uid = em.uid[idx]
	_last_hp = em.hp[idx]
	var to := player.global_position - at
	_yaw = atan2(-to.x, -to.z)


func _ready() -> void:
	model = ThogModel.new()
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	var club := RosterWeapons.attach("ogre", _skeleton())
	if club:
		club.scale *= 1.5   # a bigger club than the Ogre's
	for k in SOUNDS:
		var a := AudioStreamPlayer3D.new()
		a.bus = Settings.SFX_BUS
		a.unit_size = 30.0
		a.max_distance = 140.0
		if ResourceLoader.exists(SOUNDS[k]):
			a.stream = load(SOUNDS[k])
		add_child(a)
		_sfx[k] = a
	# A cold moonlit fill so he reads against the night swamp
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.light_energy = 1.8
	fill.omni_range = 18.0
	fill.position = Vector3(0, 7.0, -6.0)
	fill.shadow_enabled = false
	add_child(fill)
	_make_bar()
	_sync_model(0.0)
	_play_sfx("roar")


func _skeleton() -> Skeleton3D:
	return model.find_children("*", "Skeleton3D", true, false)[0]


## Current crowd row of Thog (rows move when others die), or -1 once he's gone.
func row() -> int:
	if idx >= 0 and idx < em.count and em.uid[idx] == uid:
		return idx
	idx = -1
	for i in em.count:
		if em.uid[i] == uid:
			idx = i
			break
	return idx


func hp_fraction() -> float:
	var i := row()
	return clampf(em.hp[i] / em.hp_max[i], 0.0, 1.0) if i >= 0 and not em.dead[i] else 0.0


func _physics_process(dt: float) -> void:
	if state == "dead":
		return
	if state == "dying":
		_tick_death(dt)
		return
	var i := row()
	if i < 0 or em.dead[i]:
		_die()
		return
	if main.state != "playing":
		return
	alive_time += dt
	if not is_enraged and alive_time >= ENRAGE_AFTER:
		_enrage()
	if em.hp[i] < _last_hp - 0.01:
		model.flash()
	_last_hp = em.hp[i]
	_bellow_cd -= dt * (ENRAGE_SPEED if is_enraged else 1.0)
	_tick_waves(dt)
	var held := em.is_held(i)
	if state != "attack" and _quakes_done < QUAKE_AT.size() and hp_fraction() <= QUAKE_AT[_quakes_done]:
		_start_quake()
	if state == "attack" and attack == "quake":
		_tick_quake(dt)
	elif state == "attack":
		_tick_attack(dt)
	elif not held:
		_think(dt, i)
	if held and state != "attack":
		em.troll_busy = false
		model.player.speed_scale = 0.0   # frozen / stunned: the pose holds
	_sync_model(dt)
	_update_bar()


# ------------------------------------------------------------------ deciding

func _think(dt: float, i: int) -> void:
	em.troll_busy = false
	var pp := player.global_position
	var d := Vector2(pp.x - em.pos[i].x, pp.z - em.pos[i].z).length()
	var speed_k := ENRAGE_SPEED if is_enraged else 1.0
	_gap -= dt * speed_k
	model.play("walk", clampf(em.vel[i].length() / 3.4, 0.4, 1.4) * 0.8, true)
	_step_t -= dt
	if _step_t <= 0.0 and em.vel[i].length() > 0.5:
		_step_t = 0.55
		_play_sfx("step")
		_shake(0.12)
	if _gap > 0.0:
		return
	if d < MELEE_RANGE:
		# Mostly alternate, so it isn't the same swing three times running
		var other := "sweep" if attack == "slam" else "slam"
		_start(other if randf() < 0.7 else ("slam" if other == "sweep" else "sweep"))
	elif _bellow_cd <= 0.0:
		_start("bellow")


func _start(kind: String) -> void:
	state = "attack"
	attack = kind
	counts[kind] += 1
	_t = 0.0
	_landed = false
	em.troll_busy = true
	var k := ENRAGE_SPEED if is_enraged else 1.0
	var speed: float = {"slam": SLAM_SPEED, "sweep": SWEEP_SPEED, "bellow": BELLOW_SPEED}[kind] * k
	var at: float = {"slam": SLAM_AT, "sweep": SWEEP_AT, "bellow": BELLOW_AT}[kind]
	_total = ThogModel.seg_time(kind, speed)
	_windup = _total * at
	if kind != "bellow" and _windup < MapBoss.MIN_WARN:   # enraged or not, always time to get out
		speed *= _windup / MapBoss.MIN_WARN
		_total = ThogModel.seg_time(kind, speed)
		_windup = _total * at
	model.play(kind, speed)
	# Face the player now and lock the aim for this attack
	var i := row()
	var to := player.global_position - em.pos[i]
	to.y = 0.0
	_aim = to.normalized() if to.length() > 0.1 else Vector3(-sin(_yaw), 0, -cos(_yaw))
	_yaw = atan2(-_aim.x, -_aim.z)
	match kind:
		"slam":
			_telegraph(_slam_centre(), SLAM_RADIUS, PI)
		"sweep":
			_telegraph(em.pos[i], SWEEP_RADIUS, SWEEP_HALF_ANGLE)
		"bellow":
			_play_sfx("roar")


func _slam_centre() -> Vector3:
	var i := row()
	var c := em.pos[i] + _aim * SLAM_REACH
	c.y = SwampWater.height_at(c.x, c.z)
	return c


func _telegraph(at: Vector3, radius: float, half_angle: float) -> void:
	_clear_tele()
	_tele = GroundDisc.create(1.0, Color(1.0, 0.12, 0.05), false)
	_tele.alpha = 0.55
	_tele.set_lift(0.15)
	_tele.set_arc(half_angle)
	_tele.set_fill(0.0)
	_tele.top_level = true
	add_child(_tele)
	_tele.global_position = at
	_tele.scale = Vector3(radius, 1, radius)
	_tele.rotation.y = _yaw


func _clear_tele() -> void:
	if _tele:
		_tele.queue_free()
		_tele = null


# ------------------------------------------------------------------ attacking

func _tick_attack(dt: float) -> void:
	_t += dt
	if _tele:
		_tele.set_fill(clampf(_t / _windup, 0.0, 1.0))
	if not _landed and _t >= _windup:
		_landed = true
		_clear_tele()
		match attack:
			"slam":
				_land_slam()
			"sweep":
				_land_sweep()
			"bellow":
				_land_bellow()
	if _t >= _total + 0.15:
		state = "walk"
		em.troll_busy = false
		_gap = randf_range(GAP.x, GAP.y)


func _land_slam() -> void:
	var c := _slam_centre()
	_play_sfx("slam")
	_shake(0.9)
	if fx:
		fx.burst(c + Vector3(0, 0.8, 0), SLAM_RADIUS * 0.8, Color(0.55, 0.45, 0.3), 0.6)
		fx.burst(c + Vector3(0, 0.3, 0), SLAM_RADIUS * 0.45, Color(0.85, 0.75, 0.5), 0.4)
	if _flat_dist(player.global_position, c) < SLAM_RADIUS:
		_hit(SLAM_DAMAGE, player.global_position - c)
	# The shockwave ring rolls out from the impact
	var ring := GroundDisc.create(1.0, Color(1.0, 0.55, 0.2), true)
	ring.set_lift(0.25)
	ring.set_ring(0.9)
	ring.top_level = true
	add_child(ring)
	ring.global_position = c
	_waves.append({"c": c, "t": 0.0, "ring": ring, "hit": false})


func _tick_waves(dt: float) -> void:
	for k in range(_waves.size() - 1, -1, -1):
		var w: Dictionary = _waves[k]
		w["t"] += dt
		var f: float = w["t"] / WAVE_TIME
		var r := lerpf(SLAM_RADIUS, WAVE_RADIUS, minf(f, 1.0))
		var ring: GroundDisc = w["ring"]
		ring.scale = Vector3(r, 1, r)
		ring.set_ring(clampf(1.0 - WAVE_BAND / r, 0.0, 0.95))
		ring.alpha = 0.85 * clampf(1.0 - (f - 0.8) / 0.4, 0.0, 1.0)
		var c: Vector3 = w["c"]
		var d := _flat_dist(player.global_position, c)
		if not w["hit"] and f <= 1.0 and absf(d - r) < WAVE_BAND * 0.75 and not _airborne():
			w["hit"] = true
			_hit(WAVE_DAMAGE, player.global_position - c)
		if f > 1.2:
			ring.queue_free()
			_waves.remove_at(k)


func _land_sweep() -> void:
	var i := row()
	var o := em.pos[i]
	_play_sfx("sweep")
	_shake(0.5)
	# Dust kicked up along the arc
	if fx:
		for k in 7:
			var a := _yaw + lerpf(-SWEEP_HALF_ANGLE, SWEEP_HALF_ANGLE, k / 6.0)
			var p := o + Vector3(-sin(a), 0, -cos(a)) * SWEEP_RADIUS * 0.7
			p.y = SwampWater.height_at(p.x, p.z) + 0.8
			fx.burst(p, 2.2, Color(0.6, 0.5, 0.35), 0.45)
	var to := player.global_position - o
	to.y = 0.0
	if to.length() < SWEEP_RADIUS and to.length() > 0.01 and _aim.angle_to(to.normalized()) <= SWEEP_HALF_ANGLE:
		# knocked sideways, the way the swing travels, and away from him
		var side := _aim.cross(Vector3.UP).normalized()
		_hit(SWEEP_DAMAGE, to.normalized() + side * 0.8)


func _land_bellow() -> void:
	_shake(0.6)
	_bellow_cd = BELLOW_COOLDOWN
	var i := row()
	var ring := GroundDisc.create(1.0, Color(0.6, 0.85, 1.0), true)
	ring.set_ring(0.92)
	ring.top_level = true
	add_child(ring)
	ring.global_position = em.pos[i]
	var tw := create_tween()
	tw.tween_method(func(r: float):
		ring.scale = Vector3(r, 1, r)
		ring.alpha = 0.7 * (1.0 - r / 30.0), 3.0, 30.0, 0.7)
	tw.tween_callback(ring.queue_free)
	# A ring of goblins around the player, and a brute
	var pp := player.global_position
	var hpm: float = main.hp_mult()
	for k in BELLOW_GOBLINS:
		var a := TAU * k / BELLOW_GOBLINS
		var p := pp + Vector3(cos(a), 0, sin(a)) * 12.0
		p.y = SwampWater.height_at(p.x, p.z)
		main._spawn_enemy(EnemyManager.GRUNT if k % 3 else EnemyManager.RUNNER, p, hpm)
	main._spawn_enemy(EnemyManager.TANK, pp + _aim * -14.0, hpm)
	main.hud.flash_message("THOG CALLS HIS GOBLINS!", 2.0)


# ------------------------------------------------------------------ quake

func _start_quake() -> void:
	# one quake per crossing, even if a big hit skipped past two thresholds
	while _quakes_done < QUAKE_AT.size() and hp_fraction() <= QUAKE_AT[_quakes_done]:
		_quakes_done += 1
	state = "attack"
	attack = "quake"
	counts["quake"] += 1
	_t = 0.0
	_stomp_t = 0.0
	_landed = false
	em.troll_busy = true
	_clear_tele()
	_play_sfx("roar")
	main.hud.flash_message(tr("THOG SHAKES THE SWAMP!  GET IN A PUDDLE!"), QUAKE_WARN - 0.5)
	_quake_ground(1.0, 0.0)
	_show_arrows()


func _tick_quake(dt: float) -> void:
	_t += dt
	var f := clampf(_t / QUAKE_WARN, 0.0, 1.0)
	if not _landed:
		_quake_ground(1.0, f)
	_stomp_t -= dt
	if _stomp_t <= 0.0 and not _landed:   # stomp, stomp, stomp - faster as it builds
		_stomp_t = QUAKE_STOMP * lerpf(1.0, 0.6, f)
		model.play("slam", 2.2)
		_play_sfx("step" if randi() % 2 else "slam")
		if fx:
			var i := row()
			fx.burst(em.pos[i] + _aim * 3.0 + Vector3(0, 0.4, 0), 4.0, Color(0.5, 0.42, 0.3), 0.35)
	player.add_shake(lerpf(0.35, 0.75, f))   # the whole map trembles
	if not _landed and _t >= QUAKE_WARN:
		_landed = true
		_play_sfx("slam")
		player.add_shake(1.6)
		var safe: bool = main.water != null and main.water.in_pool_xz(player.global_position.x, player.global_position.z)
		if not safe and player.hurt_true(QUAKE_FRAC):
			counts["quake_hits"] += 1
			counts["hits"] += 1
		_quake_ground(0.0, 0.0)
		_hide_arrows()
	if _arrows != null:   # bob and spin
		for a in _arrows.get_children():
			var base: float = a.get_meta("y")
			(a as Node3D).position.y = base + sin(_t * 4.0 + float(a.get_meta("ph"))) * 0.6
			(a as Node3D).rotation.y += dt * 2.0
	if _t >= QUAKE_WARN + 0.8:
		state = "walk"
		em.troll_busy = false
		_gap = randf_range(GAP.x, GAP.y)


## Light up (or clear) the ground everywhere but the pools.
func _quake_ground(on: float, fill: float) -> void:
	var w = main.water if main != null else null
	if w == null or w.ground_mat == null:
		return
	w.ground_mat.set_shader_parameter("quake", on)
	w.ground_mat.set_shader_parameter("quake_fill", fill)


## A big glowing arrow floating over every pool, pointing down: get in the water!
func _show_arrows() -> void:
	_hide_arrows()
	var w = main.water if main != null else null
	if w == null or w.pools.is_empty():
		return
	_arrows = Node3D.new()
	_arrows.name = "QuakeArrows"
	_arrows.top_level = true
	main.add_child(_arrows)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 0.7)
	mat.disable_fog = true
	mat.no_depth_test = false
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.9, 2.4, 0.9)
	var head := CylinderMesh.new()   # a cone pointing down
	head.top_radius = 1.7
	head.bottom_radius = 0.0
	head.height = 2.0
	head.radial_segments = 4   # a four-sided arrowhead
	for p in w.pools:
		var c: Vector2 = p["center"]
		var y: float = float(p.get("base", 0.0)) + float(p["water_y"]) + 6.0
		var a := Node3D.new()
		a.position = Vector3(c.x, y, c.y)
		a.set_meta("y", y)
		a.set_meta("ph", randf() * TAU)
		var s := MeshInstance3D.new()
		s.mesh = shaft
		s.material_override = mat
		s.position.y = 2.2
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.add_child(s)
		var h := MeshInstance3D.new()
		h.mesh = head
		h.material_override = mat
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.add_child(h)
		_arrows.add_child(a)


func _hide_arrows() -> void:
	if _arrows != null and is_instance_valid(_arrows):
		_arrows.queue_free()
	_arrows = null


func is_quaking() -> bool:
	return state == "attack" and attack == "quake" and not _landed


func _hit(amount: float, push: Vector3) -> void:
	player.invuln = 0.0   # the big swings always land, whatever grazed you a moment ago
	if player.hurt(amount * EnemyManager.BOSS_DAMAGE_MULT):
		counts["hits"] += 1
		player.knockback(push)
		_shake(0.5)


func _airborne() -> bool:
	var p := player.global_position
	return p.y - SwampWater.height_at(p.x, p.z) > 0.7


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ------------------------------------------------------------------ enrage, death

func _enrage() -> void:
	is_enraged = true
	model.set_enrage(1.0)
	_play_sfx("roar")
	_shake(0.7)
	main.hud.flash_message("THOG IS ENRAGED!", 4.0)
	var fire := Abilities._flame_particles(0.9, 1.0, 40)
	fire.position = Vector3(0, 1.4, 0)
	fire.emission_sphere_radius = 0.6
	model.add_child(fire)
	enraged.emit()


func _die() -> void:
	state = "dying"
	em.troll_busy = false
	_clear_tele()
	_quake_ground(0.0, 0.0)
	_hide_arrows()
	for w in _waves:
		(w["ring"] as Node).queue_free()
	_waves.clear()
	_die_t = 0.0
	model.play("death", 0.7)
	_play_sfx("roar")
	if _bar_root:
		_bar_root.queue_free()
		_bar_root = null
	defeated.emit()


func _tick_death(dt: float) -> void:
	_die_t += dt
	# Topple backwards, then crash down and sink into the bog
	var f := clampf((_die_t - 0.6) / 1.4, 0.0, 1.0)
	model.rotation = Vector3(-f * f * PI * 0.47, 0, 0)
	if f >= 1.0 and not has_meta("crashed"):
		set_meta("crashed", true)
		_play_sfx("fall")
		_shake(1.0)
		if fx:
			fx.burst(global_position + Vector3(0, 1, 0) - Vector3(-sin(_yaw), 0, -cos(_yaw)) * 4.0, 9.0, Color(0.45, 0.4, 0.3), 0.8)
	if _die_t > 4.0:
		model.position.y -= dt * 0.8
	if _die_t > 7.0:
		state = "dead"
		model.visible = false


# ------------------------------------------------------------------ drawing

func _sync_model(dt: float) -> void:
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


func _make_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_bar_root = Control.new()
	_bar_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_bar_root.offset_left = -330
	_bar_root.offset_right = 330
	_bar_root.offset_top = 74
	_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_bar_root)
	_bar_label = Label.new()
	_bar_label.text = "THOG THE TROLL"
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.size = Vector2(660, 28)
	_bar_label.add_theme_font_size_override("font_size", 22)
	_bar_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	_bar_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_bar_label.add_theme_constant_override("outline_size", 5)
	_bar_root.add_child(_bar_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.position = Vector2(0, 30)
	_bar.size = Vector2(660, 18)
	_bar.max_value = 1.0
	_bar.step = 0.0001
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	bg.border_color = Color(0.0, 0.0, 0.0, 0.9)
	bg.set_border_width_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.55, 0.95)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar_root.add_child(_bar)


func _update_bar() -> void:
	if _bar == null or _bar_root == null:
		return
	_bar.value = hp_fraction()
	if is_enraged:
		(_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.95, 0.2, 0.1).lerp(Color(1.0, 0.55, 0.1), 0.5 + 0.5 * sin(alive_time * 8.0))
		_bar_label.text = "THOG THE TROLL  ·  ENRAGED"
		_bar_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
	else:
		var left := ENRAGE_AFTER - alive_time
		_bar_label.text = tr("THOG THE TROLL  ·  enrages in %d:%02d") % [int(left) / 60, int(left) % 60]


func _shake(amount: float) -> void:
	var i := row()
	var d := _flat_dist(player.global_position, global_position) if i >= 0 else 0.0
	player.add_shake(amount * clampf(1.4 - d / 40.0, 0.2, 1.0))


func _play_sfx(k: String) -> void:
	var a: AudioStreamPlayer3D = _sfx.get(k)
	if a and a.stream:
		a.pitch_scale = randf_range(0.93, 1.05)
		a.play()
