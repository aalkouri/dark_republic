class_name KitPharaoh
extends KitPart
## The Pharaoh (PharaohBody: the Desert boss's body at player size)
##   1  Curse of the Sands  30 s  a beam of cursed green-gold light from his crook runs 22 m down
##                                where you aim: 60 damage; everything it touches is cursed (+25%
##                                damage taken) for 6 s, slowed 50% and withers for 3% of max HP a
##                                second for 4 s
##   2  Sandstorm           45 s  a storm whirls round him for 8 s out to 8 m: enemies in it are
##                                slowed 50% and take 20 a second, and it blinds them (they wander,
##                                harmless) for 2 s when it first catches them
##   3  Wrath of the Sands 120 s  a spectral Sphinx rises before him and its eyes blaze: a great
##                                storm tears through every enemy within 25 m for 300; up to 10 of
##                                the fallen rise as mummies that fight for him for 12 s (20 a hit)
## Levels: the curse beam's damage; the storm's damage; the Wrath's damage and the mummies' hits.

const CURSE_RANGE := 22.0
const CURSE_WIDTH := 3.0
const CURSE_WINDUP := 0.25          # the crook comes up, then the beam
const CURSE_DAMAGE := 60.0
const CURSE_TIME := 6.0
const CURSE_SLOW := 0.5
const CURSE_SLOW_TIME := 4.0
const CURSE_WITHER := 0.03           # of max HP per second...
const CURSE_WITHER_TIME := 4.0       # ...for 4 s
const STORM_TIME := 8.0
const STORM_RADIUS := 8.0
const STORM_DPS := 20.0
const STORM_TICK := 0.5
const STORM_SLOW := 0.5
const STORM_BLIND := 2.0
const WRATH_RADIUS := 25.0
const WRATH_DAMAGE := 300.0
const WRATH_STRIKE := 1.4            # seconds from the cast to the storm (the Sphinx rises, its eyes blaze)
const WRATH_SLOW := 0.4
const WRATH_MUMMIES := 10
const WRATH_MUMMY_TIME := 12.0
const WRATH_MUMMY_HIT := 20.0
const WRATH_TIME := 3.4              # the apparition's whole show
const WRATH_HEAD_DIST := 16.0        # the Sphinx's head rises this far ahead of him
const GOLD := Color(1.0, 0.8, 0.36)
const CURSE_GREEN := Color(0.7, 1.0, 0.35)
const SAND := Color(0.88, 0.72, 0.45)
const MUMMY_TINT := Color(0.62, 0.52, 0.3)

var _storm_t := 0.0
var _storm_tick := 0.0
var _storm_fx: Node3D
var _storm_bands: Array[MeshInstance3D] = []
var _blinded := {}                   # uid -> true (this storm)
var _wrath_t := -1.0
var _wrath_head: Node3D
var _wrath_mat: StandardMaterial3D
var _wrath_eye_mat: StandardMaterial3D
var _wrath_beams: Array[MeshInstance3D] = []
var _wrath_dead: Array[Vector3] = []  # where the storm's victims fell
var _wrath_from := Vector3.ZERO
var _wrath_fwd := Vector3.FORWARD
var _wrath_struck := false
var _wrath_raised := false
var mummies: AllyCrowd
var curse_hits := 0                  # tests
var storm_hits := 0
var blinded := 0
var wrath_hits := 0
var raised := 0


func _ready() -> void:
	mummies = AllyCrowd.new()
	mummies.enemies = enemies
	mummies.tint = MUMMY_TINT
	mummies.glow = Color(1.0, 0.75, 0.3)
	add_child(mummies)


func _exit_tree() -> void:
	for n in [_storm_fx, _wrath_head]:
		if is_instance_valid(n):
			(n as Node).queue_free()


func cast(i: int) -> void:
	src(i)
	match i:
		0: _curse()
		1: _sandstorm()
		2: _wrath()


func active(name: String) -> bool:
	match name:
		"storm": return _storm_t > 0.0
		"wrath": return _wrath_t >= 0.0
		"mummies": return mummies != null and mummies.count() > 0
	return false


func tick(dt: float) -> void:
	src(1)
	_tick_storm(dt)
	src(2)
	_tick_wrath(dt)
	if mummies:
		mummies.tick(dt, dmg() * pw(2) * WRATH_MUMMY_HIT / RosterKit.RAISE_HIT)


func on_kill(at: Vector3, _type_id: int) -> void:
	if _wrath_t >= WRATH_STRIKE and not _wrath_raised and _wrath_dead.size() < WRATH_MUMMIES:
		_wrath_dead.append(at)


# ------------------------------------------------------------------ Curse of the Sands

func _curse() -> void:
	play("curse_sands")
	var from := feet()
	var aim := aim_point(CURSE_RANGE)
	var dir := aim - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 2.0 else aim_dir()
	after(CURSE_WINDUP, func() -> void: _curse_beam(from, dir))


func _curse_beam(from: Vector3, dir: Vector3) -> void:
	var d := CURSE_DAMAGE * dmg() * pw(0)
	for i in near(from + dir * CURSE_RANGE * 0.5, CURSE_RANGE * 0.5 + 2.0):
		var off := enemies.pos[i] - from
		off.y = 0.0
		var along := off.dot(dir)
		var side := (off - dir * along).length()
		if along < -0.5 or along > CURSE_RANGE or side > CURSE_WIDTH * 0.5 + enemies.t_radius[enemies.typ[i]] * enemies.sz[i]:
			continue
		enemies.damage(i, d)
		enemies.curse(i, CURSE_TIME)
		enemies.slow(i, CURSE_SLOW, CURSE_SLOW_TIME)
		enemies.afflict(i, CURSE_WITHER, CURSE_WITHER_TIME)
		curse_hits += 1
		mote(enemies.center_of(i), Vector3(0, 2.5, 0), 0.8, CURSE_GREEN, 0.3)
	# The beam: a shaft of green-gold light from the crook down the lane, and a scorched,
	# glowing strip of sand under it
	var start := player.model.staff_tip() if player.model != null else chest() + Vector3(0, 0.6, 0)
	var end := from + dir * CURSE_RANGE + Vector3(0, 0.6, 0)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 1.0
	cyl.radial_segments = 10
	var mat := glow_mat(Color(0.75, 1.0, 0.4, 0.85))
	cyl.material = mat
	beam.mesh = cyl
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spawn(beam, (start + end) * 0.5)
	var len := start.distance_to(end)
	beam.look_at(end, Vector3.UP if absf((end - start).normalized().y) < 0.95 else Vector3.RIGHT)
	beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	beam.scale = Vector3(1.0, len, 1.0)
	var tw := beam.create_tween()
	tw.tween_property(beam, "scale", Vector3(0.15, len, 0.15), 0.5).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(beam.queue_free)
	var core := MeshInstance3D.new()
	var cm := cyl.duplicate() as CylinderMesh
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	var cmat := glow_mat(Color(1.0, 1.0, 0.85, 1.0))
	cm.material = cmat
	core.mesh = cm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spawn(core, (start + end) * 0.5)
	core.transform = beam.global_transform
	core.scale = Vector3(1.0, len, 1.0)
	fade_out(core, cmat, 0.35)
	var strip := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(CURSE_WIDTH, CURSE_RANGE)
	var smat := glow_mat(Color(0.65, 0.9, 0.3, 0.45))
	plane.material = smat
	strip.mesh = plane
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := from + dir * CURSE_RANGE * 0.5
	spawn(strip, Vector3(mid.x, ground(mid).y + 0.08, mid.z))
	strip.basis = Basis(Vector3.UP, atan2(dir.x, dir.z))
	fade_out(strip, smat, 1.4)
	for n in 30:   # sand and curse motes boiling up along the lane
		var p := from + dir * randf_range(1.0, CURSE_RANGE) + dir.cross(Vector3.UP) * randf_range(-1.2, 1.2)
		mote(Vector3(p.x, ground(p).y + 0.3, p.z), Vector3(0, randf_range(1.5, 4.0), 0), 0.9, CURSE_GREEN if n % 2 else SAND, 0.25)
	flash_light(start, CURSE_GREEN, 4.0, 8.0, 0.4)
	player.add_shake(0.25)


# ------------------------------------------------------------------ Sandstorm

func _sandstorm() -> void:
	play("sandstorm")
	_storm_t = STORM_TIME
	_storm_tick = 0.0
	_blinded.clear()
	if not is_instance_valid(_storm_fx):
		_storm_fx = Node3D.new()
		player.add_child(_storm_fx)
		_storm_bands.clear()
		for k in 3:   # whirling walls of sand, one inside the other
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			var r := STORM_RADIUS * (0.45 + 0.27 * k)
			cyl.top_radius = r * 1.15
			cyl.bottom_radius = r
			cyl.height = 3.2 + k * 0.8
			cyl.cap_top = false
			cyl.cap_bottom = false
			cyl.radial_segments = 28
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.albedo_texture = _sand_streaks()
			m.uv1_scale = Vector3(3.0 + k, 1.0, 1.0)
			m.albedo_color = Color(SAND, 0.0)
			m.disable_fog = true
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			cyl.material = m
			mi.mesh = cyl
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position.y = cyl.height * 0.5 - 0.2
			_storm_fx.add_child(mi)
			_storm_bands.append(mi)
		var dust := particles(0.6, 1.4, 70, Color(SAND, 0.55), Color(SAND.darkened(0.2), 0.0))
		((dust.mesh as QuadMesh).material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		dust.emission_ring_axis = Vector3.UP
		dust.emission_ring_radius = STORM_RADIUS
		dust.emission_ring_inner_radius = STORM_RADIUS * 0.3
		dust.emission_ring_height = 0.5
		dust.tangential_accel_min = 14.0
		dust.tangential_accel_max = 22.0
		dust.radial_accel_min = -4.0
		dust.radial_accel_max = -2.0
		dust.gravity = Vector3(0, 1.2, 0)
		dust.position.y = 0.4
		_storm_fx.add_child(dust)
		var ground_glow := GroundDisc.create(STORM_RADIUS, Color(SAND, 0.18))
		_storm_fx.add_child(ground_glow)
	ring(feet(), STORM_RADIUS, Color(SAND, 0.8), 0.45)


## A strip of streaky sand: a little noise texture stretched round the storm walls.
static var _streaks: Texture2D
static func _sand_streaks() -> Texture2D:
	if _streaks == null:
		var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for y in 32:
			var band := rng.randf()
			for x in 64:
				var v := clampf(0.55 + 0.45 * sin(float(x) * 0.3 + band * 9.0 + float(y) * 0.15) * band, 0.0, 1.0)
				var a := v * (1.0 - absf(float(y) - 16.0) / 16.0) * (0.6 + 0.4 * rng.randf())
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_streaks = ImageTexture.create_from_image(img)
	return _streaks


func _tick_storm(dt: float) -> void:
	if _storm_t <= 0.0:
		return
	_storm_t -= dt
	var t := STORM_TIME - _storm_t
	var fade := clampf(t / 0.5, 0.0, 1.0) * clampf(_storm_t / 0.6, 0.0, 1.0)
	for k in _storm_bands.size():
		var b := _storm_bands[k]
		b.rotation.y += dt * (3.2 - k * 0.7)
		((b.mesh as CylinderMesh).material as StandardMaterial3D).albedo_color.a = (0.5 - k * 0.12) * fade
	if is_instance_valid(_storm_fx):
		_storm_fx.global_rotation = Vector3.ZERO
	_storm_tick -= dt
	if _storm_tick <= 0.0:
		_storm_tick = STORM_TICK
		var d := STORM_DPS * STORM_TICK * dmg() * pw(1)
		for i in near(feet(), STORM_RADIUS):
			enemies.damage(i, d)
			enemies.slow(i, STORM_SLOW, STORM_TICK + 0.2)
			storm_hits += 1
			var u: int = enemies.uid[i]
			if not _blinded.has(u):
				_blinded[u] = true
				enemies.confuse(i, STORM_BLIND)
				blinded += 1
	if _storm_t <= 0.0 and is_instance_valid(_storm_fx):
		_storm_fx.queue_free()
		_storm_bands.clear()


# ------------------------------------------------------------------ Wrath of the Sands

func _wrath() -> void:
	play("wrath_sands")
	if is_instance_valid(_wrath_head):
		_wrath_head.queue_free()
	_wrath_t = 0.0
	_wrath_struck = false
	_wrath_raised = false
	_wrath_dead.clear()
	_wrath_from = feet()
	_wrath_fwd = aim_dir()
	# The Sphinx's head rises out of the sand across the field from him, ghostly gold, looking
	# back over him (so the camera, behind him, sees its face)
	var mb := MeshBuilder.new()
	var eyes := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	DesertSphinx.head(mb, Transform3D(Basis.from_scale(Vector3.ONE * 2.6), Vector3.ZERO), GOLD, rng, false, true, eyes, GOLD, PharaohModel.LAPIS)
	_wrath_mat = glow_mat(Color(1.0, 0.78, 0.35, 0.0))
	_wrath_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_wrath_eye_mat = glow_mat(Color(0.75, 1.0, 0.4, 0.0))
	var head := mb.commit(_wrath_mat)
	eyes.commit_into(head, _wrath_eye_mat)
	_wrath_head = Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = head
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wrath_head.add_child(mi)
	spawn(_wrath_head, _wrath_from + _wrath_fwd * WRATH_HEAD_DIST + Vector3(0, -6.0, 0))
	_wrath_head.basis = Basis(Vector3.UP, atan2(-_wrath_fwd.x, -_wrath_fwd.z))   # its face (+Z) looks back at him
	_wrath_beams.clear()
	for sd in [-1.0, 1.0]:   # the two beams of light its eyes will pour down
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.25
		cyl.bottom_radius = 0.6
		cyl.height = 1.0
		cyl.material = glow_mat(Color(1.0, 0.95, 0.6, 0.0))
		beam.mesh = cyl
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.visible = false
		spawn(beam, _wrath_from)
		_wrath_beams.append(beam)
	player.add_shake(0.3)


func _tick_wrath(dt: float) -> void:
	if _wrath_t < 0.0:
		return
	_wrath_t += dt
	var t := _wrath_t
	if is_instance_valid(_wrath_head):
		var rise := clampf(t / 0.9, 0.0, 1.0)
		var base := _wrath_from + _wrath_fwd * WRATH_HEAD_DIST
		_wrath_head.global_position = base + Vector3(0, lerpf(-6.0, 6.5, 1.0 - pow(1.0 - rise, 3.0)) + 0.2 * sin(t * 2.0), 0)
		var fade := clampf(t / 0.6, 0.0, 1.0) * (1.0 - clampf((t - 2.6) / 0.8, 0.0, 1.0))
		_wrath_mat.albedo_color.a = 0.32 * fade
		var blaze := clampf((t - 0.8) / 0.4, 0.0, 1.0) * fade
		_wrath_eye_mat.albedo_color = Color(0.85, 1.0, 0.5, blaze)
		# The eyes' beams sweep out across the field to its far edge
		var sweep := clampf((t - 0.9) / 0.9, 0.0, 1.0)
		for k in _wrath_beams.size():
			var beam := _wrath_beams[k]
			var sd := -1.0 if k == 0 else 1.0
			var eye := _wrath_head.global_transform * Vector3(sd * 0.34 * 2.6, 0.12 * 2.6, 0.9 * 2.6)
			var side := _wrath_fwd.cross(Vector3.UP)
			var reach := lerpf(4.0, WRATH_RADIUS, sweep)
			var hit := _wrath_from + _wrath_fwd * lerpf(WRATH_HEAD_DIST - 4.0, -6.0, sweep) + side * sd * reach * 0.6 * sin(sweep * PI * 0.8 + 0.3)
			hit.y = ground(hit).y
			beam.visible = blaze > 0.05
			if beam.visible:
				var len := eye.distance_to(hit)
				beam.global_position = (eye + hit) * 0.5
				beam.look_at(hit, Vector3.UP if absf((hit - eye).normalized().y) < 0.95 else Vector3.RIGHT)
				beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)   # narrow end (+Y) at the eye
				beam.scale = Vector3(1.0, len, 1.0)
				((beam.mesh as CylinderMesh).material as StandardMaterial3D).albedo_color.a = 0.35 * blaze
				if randf() < dt * 30.0:
					mote(hit + Vector3(0, 0.3, 0), Vector3(randf_range(-2, 2), randf_range(3, 6), randf_range(-2, 2)), 0.7, SAND, 0.35)
	if not _wrath_struck and t >= WRATH_STRIKE:
		_wrath_struck = true
		_wrath_strike()
	if not _wrath_raised and t >= WRATH_STRIKE + 0.45:
		_wrath_raised = true
		_raise_mummies()
	if t >= WRATH_TIME:
		_wrath_t = -1.0
		if is_instance_valid(_wrath_head):
			_wrath_head.queue_free()
		for b in _wrath_beams:
			if is_instance_valid(b):
				b.queue_free()
		_wrath_beams.clear()


## The great storm: everything within WRATH_RADIUS is torn through.
func _wrath_strike() -> void:
	var at := feet()
	var d := WRATH_DAMAGE * dmg() * pw(2)
	for i in near(at, WRATH_RADIUS):
		enemies.slow(i, WRATH_SLOW, 4.0)
		enemies.damage(i, d, (enemies.pos[i] - at).normalized() * 4.0)
		wrath_hits += 1
	ring(at, WRATH_RADIUS, Color(SAND, 0.85), 0.7)
	ring(at, WRATH_RADIUS * 0.6, Color(GOLD, 0.7), 0.5)
	var dust := particles(1.4, 2.0, 160, Color(SAND, 0.6), Color(SAND.darkened(0.3), 0.0))
	((dust.mesh as QuadMesh).material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	dust.one_shot = true
	dust.explosiveness = 0.85
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = WRATH_RADIUS * 0.8
	dust.emission_ring_inner_radius = 1.0
	dust.emission_ring_height = 1.0
	dust.tangential_accel_min = 20.0
	dust.tangential_accel_max = 30.0
	dust.gravity = Vector3(0, 2.0, 0)
	dust.emitting = true
	spawn(dust, at + Vector3(0, 1.0, 0))
	get_tree().create_timer(2.6).timeout.connect(dust.queue_free)
	flash_light(at + Vector3(0, 6, 0), GOLD, 5.0, WRATH_RADIUS * 1.3, 0.9)
	player.add_shake(0.8)
	play("wrath_storm", 2.0)


## The fallen rise as mummies (the storm's victims first, then the sand gives up older dead).
func _raise_mummies() -> void:
	var at := feet()
	var spots: Array[Vector3] = []
	for p in _wrath_dead:
		spots.append(p)
	while spots.size() < WRATH_MUMMIES:
		var a := randf() * TAU
		var r := randf_range(3.0, 10.0)
		spots.append(at + Vector3(cos(a) * r, 0, sin(a) * r))
	for k in WRATH_MUMMIES:
		var p := spots[k]
		p.y = SwampWater.height_at(p.x, p.z) if SwampWater.current != null else ground(p).y
		mummies.add(p, WRATH_MUMMY_TIME, k * 0.06)
		raised += 1
		if fx:
			fx.burst(p + Vector3(0, 0.4, 0), 1.0, SAND, 0.4)
