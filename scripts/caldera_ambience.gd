class_name CalderaAmbience
extends Node3D
## The air of the Ashen Caldera, and its lava's bite (its Butterflies / DesertWind):
##   - ash drifting down round the camera, embers rising off the ground, a bubbling lava sound
##     from the nearest lava;
##   - now and then a distant rumble, the camera trembling, the cinder cone flaring and puffing ash;
##   - LAVA BURNS: standing in it costs LAVA_DAMAGE every LAVA_TICK and sets you burning
##     (Player.ignite: a brief burn) - enemies wade through it unharmed;
##   - ERUPTIONS (erupt(), at the minute-swarm moments): a rumble, the cone erupts, and lava
##     bombs arc from it onto marked circles round the player. Each circle fills for at least
##     MIN_WARN seconds before its bomb lands; bombs only hurt the player.

const EXTENT := 22.0
const LAVA_TICK := 0.5
const LAVA_DAMAGE := 7.0
const MIN_WARN := 1.0
const BOMB_WARN := 1.8
const BOMB_RADIUS := 3.0
const BOMB_DAMAGE := 22.0
const RUMBLE_GAP := Vector2(22.0, 40.0)
const SOUNDS := {
	"bubble": "res://audio/caldera/lava_bubble.wav",
	"rumble": "res://audio/caldera/rumble.wav",
	"eruption": "res://audio/caldera/eruption.wav",
	"impact": "res://audio/caldera/bomb_impact.wav",
	"whistle": "res://audio/caldera/bomb_whistle.wav",
	"sizzle": "res://audio/caldera/sizzle.wav",
}

static var current: CalderaAmbience

var lava_hits := 0          # tests: lava burns dealt to the player
var bomb_hits := 0          # tests: lava bombs that hit the player
var bombs_landed := 0
var _player: Node3D
var _ash: CPUParticles3D
var _embers: CPUParticles3D
var _bubble: AudioStreamPlayer3D
var _sfx := {}
var _lava_t := 0.0
var _rumble_t := 20.0
var _bubble_t := 0.0
var _bubble_on := false
var _bombs: Array[Dictionary] = []   # {disc, t, time, at, node, from, trail}
var _volcano: Node3D
var _streams := {}


func _ready() -> void:
	name = "CalderaAmbience"   # no-i18n
	current = self
	_ash = _flakes(700, 0.07, Color(0.55, 0.52, 0.5, 0.75), Vector3(0.6, -1.0, 0.25), 1.2, 6.0, false)
	_embers = _flakes(260, 0.06, Color(1.0, 0.5, 0.12, 1.0), Vector3(0.2, 1.0, 0.1), 2.0, 3.5, true)
	_embers.emission_box_extents = Vector3(EXTENT, 0.5, EXTENT)
	for k in SOUNDS:
		if ResourceLoader.exists(SOUNDS[k]):
			_streams[k] = load(SOUNDS[k])
	_bubble = AudioStreamPlayer3D.new()
	_bubble.bus = Settings.SFX_BUS
	_bubble.unit_size = 10.0
	_bubble.max_distance = 40.0
	_bubble.volume_db = -6.0
	if _streams.has("bubble"):
		_bubble.stream = _streams["bubble"]
	_bubble.finished.connect(func() -> void:
		if _bubble_on:
			_bubble.play())
	add_child(_bubble)
	for k in ["rumble", "eruption", "sizzle"]:
		var a := AudioStreamPlayer.new()
		a.bus = Settings.SFX_BUS
		a.volume_db = -4.0 if k != "sizzle" else -8.0
		if _streams.has(k):
			a.stream = _streams[k]
		add_child(a)
		_sfx[k] = a
	_rumble_t = randf_range(RUMBLE_GAP.x, RUMBLE_GAP.y)


func _exit_tree() -> void:
	if current == self:
		current = null


func _flakes(n: int, size: float, col: Color, vel: Vector3, speed: float, life: float, additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(EXTENT, 7.0, EXTENT)
	p.direction = vel.normalized()
	p.spread = 25.0
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed * 1.3
	p.gravity = Vector3(0, 0.25 if additive else -0.15, 0)
	p.tangential_accel_min = -0.6
	p.tangential_accel_max = 0.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.disable_fog = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Abilities._soft_dot()
	q.material = m
	p.mesh = q
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.0))
	ramp.add_point(0.15, col)
	ramp.add_point(0.75, col)
	ramp.set_color(ramp.get_point_count() - 1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = ramp
	add_child(p)
	return p


func _get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		var main := get_parent()
		if main != null and "player" in main and main.player is Node3D:
			_player = main.player
	return _player


func _volcano_node() -> Node3D:
	if _volcano == null or not is_instance_valid(_volcano):
		_volcano = get_parent().get_node_or_null("CinderCone") as Node3D if get_parent() != null else null
	return _volcano


func _physics_process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var c := cam.global_position
		_ash.global_position = Vector3(c.x, c.y + 2.0, c.z)
		_embers.global_position = Vector3(c.x, SwampWater.height_at(c.x, c.z) + 0.3, c.z)
	var pl := _get_player()
	if pl == null:
		return
	var main := get_parent()
	var playing: bool = main == null or not ("state" in main) or main.state == "playing"
	_tick_bombs(dt, pl)
	if not playing:
		return
	_lava_burn(dt, pl)
	_bubble_t -= dt
	if _bubble_t <= 0.0:   # the bubbling comes from the nearest lava
		_bubble_t = 0.5
		var near := _nearest_lava(pl.global_position, 32.0)
		_bubble_on = near != Vector3.INF
		if _bubble_on:
			_bubble.global_position = near
			if not _bubble.playing and _bubble.stream != null:
				_bubble.play()
		elif _bubble.playing:
			_bubble.stop()
	_rumble_t -= dt
	if _rumble_t <= 0.0:
		_rumble_t = randf_range(RUMBLE_GAP.x, RUMBLE_GAP.y)
		rumble(0.25)


## A distant rumble: the ground trembles and the cinder cone flares.
func rumble(shake: float) -> void:
	_play("rumble")
	var pl := _get_player()
	if pl != null and pl.has_method("add_shake"):
		pl.add_shake(shake)
	var v := _volcano_node()
	if v != null and v.has_method("erupt"):
		v.erupt(0.4)


func _nearest_lava(p: Vector3, reach: float) -> Vector3:
	var best := Vector3.INF
	var bd := reach * reach
	for rv in CalderaBuilder.rivers:
		var pts: PackedVector2Array = rv["pts"]
		var lv: PackedFloat32Array = rv["lv"]
		for k in range(0, pts.size(), 3):
			var d := Vector2(pts[k].x - p.x, pts[k].y - p.z).length_squared()
			if d < bd:
				bd = d
				best = Vector3(pts[k].x, lv[k], pts[k].y)
	for pool in CalderaBuilder.pools:
		var c: Vector2 = pool["c"]
		var to := Vector2(p.x - c.x, p.z - c.y)
		var d := maxf(0.0, to.length() - float(pool["r"]))
		if d * d < bd:
			bd = d * d
			var at := c + to.normalized() * minf(to.length(), float(pool["r"]))
			best = Vector3(at.x, float(pool["lv"]), at.y)
	return best


## Standing in lava burns: damage every LAVA_TICK (whatever grazed you a moment ago) and a burn.
func _lava_burn(dt: float, pl: Node3D) -> void:
	if not CalderaBuilder.in_lava(pl.global_position):
		_lava_t = 0.0
		return
	_lava_t -= dt
	if _lava_t > 0.0:
		return
	_lava_t = LAVA_TICK
	if "invuln" in pl:
		pl.invuln = 0.0
	var hit := false
	if pl.has_method("hurt"):
		hit = pl.hurt(LAVA_DAMAGE)
	if pl.has_method("ignite"):
		pl.ignite()
	if hit:
		lava_hits += 1
	var main := get_parent()
	if main != null and "fx" in main and main.fx is FxManager:
		(main.fx as FxManager).burst(pl.global_position + Vector3(0, 0.3, 0), 0.9, Color(1.0, 0.45, 0.1), 0.3)
	var s: AudioStreamPlayer = _sfx.get("sizzle")
	if s != null and s.stream != null and not s.playing:
		s.pitch_scale = randf_range(0.9, 1.1)
		s.play()


# ------------------------------------------------------------------ eruptions

## The volcano erupts: a rumble and a flare, and `n` lava bombs arc from the cinder cone onto
## marked circles round `center` (one where the player is heading). Returns the bombs thrown.
func erupt(center: Vector3, n: int, rng: RandomNumberGenerator = null) -> int:
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	_play("eruption")
	var pl := _get_player()
	if pl != null and pl.has_method("add_shake"):
		pl.add_shake(0.55)
	var v := _volcano_node()
	if v != null and v.has_method("erupt"):
		v.erupt(1.0)
	var lead := center
	if pl != null and "velocity" in pl:
		var vel: Vector3 = pl.velocity
		lead = center + Vector3(vel.x, 0, vel.z) * 1.2
	for k in n:
		var at := lead if k == 0 else center + Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized() * r.randf_range(3.5, 15.0)
		at.y = SwampWater.height_at(at.x, at.z)
		throw_bomb(at, BOMB_WARN + r.randf_range(0.0, 1.4) + k * 0.06)
	return n


## One lava bomb: a circle on the ground fills for `secs` (never under MIN_WARN) while the bomb
## arcs down onto it from the cinder cone.
func throw_bomb(at: Vector3, secs: float) -> void:
	secs = maxf(secs, MIN_WARN)
	var d := GroundDisc.create(1.0, Color(1.0, 0.35, 0.05), false)
	d.alpha = 0.55
	d.set_lift(0.15)
	d.set_fill(0.0)
	add_child(d)
	d.global_position = at
	d.scale = Vector3(BOMB_RADIUS, 1, BOMB_RADIUS)
	var from := at + Vector3(0, 60.0, 0)
	var cone: Dictionary = CalderaBuilder.cone
	if not cone.is_empty():
		var top: Vector3 = cone["top"]
		var dir := Vector3(top.x - at.x, 0, top.z - at.z)
		from = at + dir.normalized() * minf(dir.length(), 90.0) + Vector3(0, 70.0, 0)
	var bomb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.7
	sm.height = 1.4
	sm.radial_segments = 10
	sm.rings = 6
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.08, 0.04)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.42, 0.08)
	m.emission_energy_multiplier = 3.0
	sm.material = m
	bomb.mesh = sm
	bomb.top_level = true
	add_child(bomb)
	bomb.global_position = from
	var trail := CalderaProps.embers(Vector3.ZERO, 0.4, 24)
	trail.lifetime = 0.8
	trail.preprocess = 0.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 1.0
	bomb.add_child(trail)
	_bombs.append({"disc": d, "t": 0.0, "time": secs, "at": at, "node": bomb, "from": from})


func _tick_bombs(dt: float, pl: Node3D) -> void:
	for k in range(_bombs.size() - 1, -1, -1):
		var b: Dictionary = _bombs[k]
		b["t"] += dt
		var f: float = clampf(b["t"] / b["time"], 0.0, 1.0)
		var disc: GroundDisc = b["disc"]
		disc.set_fill(f)
		var from: Vector3 = b["from"]
		var to: Vector3 = b["at"]
		var p := from.lerp(to, f)
		p.y += 4.0 * 14.0 * f * (1.0 - f)
		(b["node"] as Node3D).global_position = p
		if f >= 1.0:
			_bombs.remove_at(k)
			disc.queue_free()
			(b["node"] as Node).queue_free()
			_land_bomb(to, pl)


func _land_bomb(at: Vector3, pl: Node3D) -> void:
	bombs_landed += 1
	_play3d("impact", at)
	var main := get_parent()
	if main != null and "fx" in main and main.fx is FxManager:
		var fx := main.fx as FxManager
		fx.burst(at + Vector3(0, 0.8, 0), BOMB_RADIUS, Color(1.0, 0.45, 0.1), 0.45)
		fx.burst(at + Vector3(0, 0.4, 0), BOMB_RADIUS * 0.7, Color(0.2, 0.16, 0.14), 0.6)
	var pp := pl.global_position
	var flat := Vector2(pp.x - at.x, pp.z - at.z).length()
	var airborne := pp.y - SwampWater.height_at(pp.x, pp.z) > 1.2
	if flat < BOMB_RADIUS and not airborne:
		if "invuln" in pl:
			pl.invuln = 0.0
		var mult := 1.0
		if main != null and "enemies" in main and main.enemies != null:
			mult = 1.0 + float(main.run_time) / 600.0
		if pl.has_method("hurt") and pl.hurt(BOMB_DAMAGE * mult):
			bomb_hits += 1
			if pl.has_method("ignite"):
				pl.ignite()
			if pl.has_method("knockback"):
				pl.knockback(pp - at)
	if pl.has_method("add_shake"):
		pl.add_shake(clampf(0.5 - flat / 60.0, 0.05, 0.5))


func pending_bombs() -> int:
	return _bombs.size()


## The shortest warning among the bombs in flight (tests: >= MIN_WARN).
func min_bomb_warning() -> float:
	var m := INF
	for b in _bombs:
		m = minf(m, float(b["time"]))
	return m


func _play(k: String) -> void:
	var a: AudioStreamPlayer = _sfx.get(k)
	if a != null and a.stream != null:
		a.pitch_scale = randf_range(0.92, 1.06)
		a.play()


func _play3d(k: String, at: Vector3) -> void:
	if not _streams.has(k):
		return
	var a := AudioStreamPlayer3D.new()
	a.bus = Settings.SFX_BUS
	a.stream = _streams[k]
	a.unit_size = 14.0
	a.max_distance = 80.0
	a.pitch_scale = randf_range(0.9, 1.1)
	add_child(a)
	a.global_position = at
	a.play()
	a.finished.connect(a.queue_free)
