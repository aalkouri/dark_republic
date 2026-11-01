class_name NecromancerBoss
extends MapBoss
## The Necromancer, the Haunted Graveyard's boss: a tall robed sorcerer with a skull staff who
## steps out of the fog at 8:00 and enrages at 10:00. Killing him wins the run.
##
## Attacks (every one marked on the ground first, see MapBoss):
##   STAFF SLAM     close: a circle round him fills, then the staff comes down and bone spikes
##                  burst out of the ground all round him.
##   BONE LINES     three lanes fanned out toward you; bone spikes erupt along each, one after
##                  another, from his feet outward.
##   BONE RING      a band round you; a ring of spikes bursts up in it: step into the middle or out.
##   RAISE THE DEAD green circles over graves round you (the ground, if there are none): when
##                  each fills, the dead claw their way out of it (skeletons and ghouls), and
##                  hands grab whoever stands there (hurt and rooted a moment).
##   SOUL DRAIN     a lane toward you marks where the beam will start; then for a few seconds a
##                  green beam pours from his staff, swinging after you (slowly enough to outrun);
##                  standing in it drains you and heals him.
##   CURSED CIRCLE  a big circle at where you're going; it becomes a ring of curse runes for a
##                  while that hurts and slows you while you stand in it.
##   THE GRAVES OPEN  his ultimate, at 75%, 50% and 10% health: he rises into the air and the
##                  whole graveyard glows a sickly green, cracks crawling over it, for ULT_WARN
##                  seconds. Only consecrated ground is safe: the chapel's churchyard and a few
##                  circles of holy light (each marked by a pillar of light) that appear round you.
##                  Anyone anywhere else when it lands loses ULT_FRAC of their max HP, straight
##                  through shields; then the dead rise from the graves all round.

const SCALE := 1.6                 # x NecromancerModel's 2.7 m: about 4.3 m tall
const TURN_RATE := 3.5
const GAP := Vector2(1.1, 1.9)
const MELEE_RANGE := 9.0
const SLAM_WARN := 1.4
const SLAM_RADIUS := 7.5
const SLAM_DAMAGE := 36.0
const LINES_WARN := 1.4
const LINE_LEN := 24.0
const LINE_WIDTH := 2.6
const LINE_SPREAD := 0.38          # radians between lanes
const LINE_DAMAGE := 30.0
const RING_WARN := 1.5
const RING_INNER := 3.5
const RING_OUTER := 7.5
const RING_DAMAGE := 30.0
const RAISE_WARN := 1.8
const RAISE_RADIUS := 1.8
const RAISE_COUNT := 5
const RAISE_DAMAGE := 16.0
const RAISE_COOLDOWN := 14.0
const RAISE_FIRST := 6.0
const DRAIN_WARN := 1.2
const DRAIN_LEN := 26.0
const DRAIN_WIDTH := 2.2
const DRAIN_TIME := 2.8
const DRAIN_TURN := 0.42           # radians per second the beam can swing (enraged x1.6)
const DRAIN_DPS := 22.0
const DRAIN_HEAL := 2.0            # he heals this many HP per HP drained
const DRAIN_COOLDOWN := 11.0
const CURSE_WARN := 1.5
const CURSE_RADIUS := 5.5
const CURSE_LIFE := 6.0
const CURSE_DPS := 9.0
const CURSE_SLOW := 0.6
const CURSE_COOLDOWN := 8.0
const ULT_AT := [0.75, 0.5, 0.1]   # health fractions that open the graves
const ULT_WARN := 9.0
const ULT_FRAC := 0.4              # of max HP, through shields
const ULT_RISE := 3.0              # metres he floats up meanwhile
const HOLY_CIRCLES := 4
const HOLY_RADIUS := 4.5
const ULT_RAISE := 10
const GREEN := Color(0.35, 1.0, 0.45)
const CURSE := Color(0.62, 0.2, 0.95)

var model: NecromancerModel
var _yaw := 0.0
var _aim := Vector3.FORWARD
var _gap := 2.0
var _raise_cd := RAISE_FIRST
var _drain_cd := 4.0
var _curse_cd := 2.0
var _t := 0.0
var _phase_t := 0.0
var _ults_done := 0
var _risen_uids: Array[int] = []
var _beam: MeshInstance3D
var _beam_dir := Vector3.FORWARD
var _beam_on := false
var _drain_tick := 0.0
var _safe: Array[Vector3] = []     # x, z, radius in a Vector3 (y = radius)
var _pillars: Array[Node3D] = []
var _landed := false


func stats() -> Dictionary:
	return {"name": "The Necromancer", "hp": 5400.0, "speed": 3.3, "radius": 1.5, "height": 4.6, "damage": 40.0, "xp": 400.0}


func display_name() -> String:
	return "THE NECROMANCER"


func bar_color() -> Color:
	return Color(0.3, 0.75, 0.4)


func sounds() -> Dictionary:
	return {
		"roar": "res://audio/graveyard/necro_laugh.wav",
		"laugh": "res://audio/graveyard/necro_laugh.wav",
		"spell": "res://audio/graveyard/necro_spell.wav",
		"spikes": "res://audio/graveyard/bone_spikes.wav",
		"drain": "res://audio/graveyard/soul_drain.wav",
		"graves": "res://audio/graveyard/graves_open.wav",
		"crumble": "res://audio/graveyard/grave_crumble.wav",
		"death": "res://audio/graveyard/necro_death.wav",
		"bell": "res://audio/graveyard/bell_toll.wav",
	}


func _build_model() -> void:
	model = NecromancerModel.new()
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	var i := row()
	if i >= 0:
		var to := player.global_position - em.pos[i]
		_yaw = atan2(to.x, to.z)
	_beam = _make_beam()
	add_child(_beam)
	_sync(0.0)
	play_sfx("laugh")
	play_sfx("bell", 0.8)
	if fx and i >= 0:   # he steps out of a swirl of grave-mist
		fx.burst(em.pos[i] + Vector3(0, 1.5, 0), 4.0, GREEN, 0.8)


func _physics_process(dt: float) -> void:
	super(dt)
	if state == "dead" or state == "dying":
		return
	if main.state != "playing":
		return
	_sync(dt)
	if state == "walk" and _ults_done < ULT_AT.size() and hp_fraction() <= ULT_AT[_ults_done]:
		while _ults_done < ULT_AT.size() and hp_fraction() <= ULT_AT[_ults_done]:
			_ults_done += 1
		_start("graves")


func _on_hurt() -> void:
	model.flash()


# ------------------------------------------------------------------ deciding

func _think(dt: float, i: int) -> void:
	em.troll_busy = false
	var k := speed_k()
	_gap -= dt * k
	_raise_cd -= dt * k
	_drain_cd -= dt * k
	_curse_cd -= dt * k
	if em.is_held(i):
		return
	model.pose("walk" if em.vel[i].length() > 0.4 else "idle")
	if _gap > 0.0:
		return
	var d := flat_dist(player.global_position, em.pos[i])
	if _raise_cd <= 0.0:
		_start("raise")
	elif d < MELEE_RANGE:
		_start("slam")
	elif _drain_cd <= 0.0 and d < DRAIN_LEN - 2.0:
		_start("drain")
	elif _curse_cd <= 0.0:
		_start("curse")
	else:
		_start("lines" if randf() < 0.55 else "ring")


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
	_aim = to.normalized() if to.length() > 0.1 else Vector3(sin(_yaw), 0, cos(_yaw))
	var o := em.pos[i]
	match kind:
		"slam":
			model.pose("slam")
			play_sfx("spell", 0.8)
			_phase_t = warn_time(SLAM_WARN) + 0.4
			warn_circle(o, SLAM_RADIUS, SLAM_WARN, func(): _land_slam(o))
		"lines":
			model.pose("cast")
			play_sfx("spell")
			_phase_t = warn_time(LINES_WARN) + 0.6
			for k in 3:
				var dir := _aim.rotated(Vector3.UP, (k - 1) * LINE_SPREAD)
				warn_lane(o, dir, LINE_LEN, LINE_WIDTH, LINES_WARN, func(): _land_line(o, dir))
		"ring":
			model.pose("cast")
			play_sfx("spell", 1.1)
			var c := player_ahead(0.4)
			_phase_t = warn_time(RING_WARN) + 0.3
			warn_ring(c, RING_INNER, RING_OUTER, RING_WARN, func(): _land_ring(c))
		"raise":
			_raise_cd = RAISE_COOLDOWN
			model.pose("summon")
			play_sfx("laugh", 1.1)
			_phase_t = warn_time(RAISE_WARN) + 0.4
			for at in _raise_spots(RAISE_COUNT + (2 if is_enraged else 0)):
				var spot: Vector3 = at
				warn_circle(spot, RAISE_RADIUS, RAISE_WARN, func(): _land_raise(spot), GREEN)
			main.hud.flash_message("THE DEAD RISE!", 2.0)
		"drain":
			_drain_cd = DRAIN_COOLDOWN
			model.pose("channel")
			_beam_dir = _aim
			_phase_t = warn_time(DRAIN_WARN)
			warn_lane(o, _aim, DRAIN_LEN, DRAIN_WIDTH, DRAIN_WARN, _begin_drain)
		"curse":
			_curse_cd = CURSE_COOLDOWN
			model.pose("cast")
			play_sfx("spell", 0.7)
			var c := player_ahead(0.6)
			_phase_t = warn_time(CURSE_WARN) + 0.2
			lob(model.tip_position(), c + Vector3(0, 0.3, 0), warn_time(CURSE_WARN), CURSE, 0.4, 5.0)
			warn_circle(c, CURSE_RADIUS, CURSE_WARN, func(): _land_curse(c), CURSE)
		"graves":
			_begin_graves()


func _tick_attack(dt: float) -> void:
	_t += dt
	match attack:
		"drain":
			if _beam_on:
				_tick_drain(dt)
			elif _t > _phase_t + 0.2 and not _beam_on and _landed:
				_done(0.6)
		"graves":
			_tick_graves(dt)
		_:
			if _t >= _phase_t:
				_done(0.0)


func _done(extra_gap: float) -> void:
	state = "walk"
	attack = ""
	em.troll_busy = false
	em.boss_contact = true
	_gap = randf_range(GAP.x, GAP.y) / (1.0 + (0.3 if is_enraged else 0.0)) + extra_gap
	model.pose("idle")


# ------------------------------------------------------------------ attacks landing

func _land_slam(o: Vector3) -> void:
	play_sfx("spikes", 0.8)
	shake(0.7)
	for k in 16:
		var a := TAU * k / 16.0
		_spike(ground(o + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, SLAM_RADIUS - 0.5)), randf_range(1.2, 2.0), randf() * 0.15)
	if fx:
		fx.burst(o + Vector3(0, 0.6, 0), SLAM_RADIUS, Color(0.85, 0.82, 0.72), 0.45)
	if player_in_circle(o, SLAM_RADIUS) and not airborne():
		hit_player(SLAM_DAMAGE, player.global_position - o)


func _land_line(o: Vector3, dir: Vector3) -> void:
	play_sfx("spikes")
	shake(0.35)
	var n := 12
	for k in n:
		var t := (k + 0.5) / n
		var side := dir.cross(Vector3.UP).normalized() * randf_range(-0.6, 0.6)
		_spike(ground(o + dir * LINE_LEN * t + side), randf_range(1.0, 1.8), t * 0.3)
	# in the lane? (a stretched oval, as drawn)
	var rel := player.global_position - o
	rel.y = 0.0
	var along := rel.dot(dir)
	var across := (rel - dir * along).length()
	if along > 0.0 and along < LINE_LEN and across < LINE_WIDTH * 0.5 + 0.4 and not airborne():
		hit_player(LINE_DAMAGE, dir)


func _land_ring(c: Vector3) -> void:
	play_sfx("spikes", 1.1)
	shake(0.5)
	for k in 20:
		var a := TAU * k / 20.0
		_spike(ground(c + Vector3(cos(a), 0, sin(a)) * randf_range(RING_INNER + 0.4, RING_OUTER - 0.4)), randf_range(1.2, 2.1), randf() * 0.12)
	var d := flat_dist(player.global_position, c)
	if d >= RING_INNER and d <= RING_OUTER and not airborne():
		hit_player(RING_DAMAGE, player.global_position - c)


## Graves 5-16 m round the player (or bare ground in a ring if there are too few).
func _raise_spots(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var pp := player.global_position
	var cand: Array[Vector3] = []
	for g in GraveyardBuilder.graves:
		var d := Vector2(g.x - pp.x, g.z - pp.z).length()
		if d > 4.5 and d < 16.0:
			cand.append(g)
	cand.shuffle()
	for g in cand:
		if out.size() >= n:
			break
		var spaced := true
		for o in out:
			if o.distance_to(g) < 3.0:
				spaced = false
				break
		if spaced:
			out.append(g)
	var a0 := randf() * TAU
	while out.size() < n:
		var a := a0 + TAU * out.size() / float(n)
		out.append(ground(pp + Vector3(cos(a), 0, sin(a)) * randf_range(6.0, 11.0)))
	return out


func _land_raise(at: Vector3) -> void:
	play_sfx("crumble", randf_range(0.85, 1.15))
	if player_in_circle(at, RAISE_RADIUS) and not airborne():   # hands burst out and grab
		if hit_player(RAISE_DAMAGE, Vector3.ZERO):
			player.root(0.6)
	var undead: UndeadCrowd = em.undead
	var t := EnemyManager.SKELETON if randf() < 0.6 else EnemyManager.GHOUL
	var r := -1
	if undead != null:
		r = undead.raise(t, at, main.hp_mult() * 0.8, 0.0)
	else:
		r = em.spawn(t, at, main.hp_mult() * 0.8)
	if r >= 0:
		_risen_uids.append(em.uid[r])
		counts["risen"] = int(counts.get("risen", 0)) + 1


func _land_curse(c: Vector3) -> void:
	play_sfx("spell", 0.6)
	add_hazard(c, CURSE_RADIUS, CURSE_LIFE, CURSE, CURSE_DPS, CURSE_SLOW)
	if fx:
		fx.burst(c + Vector3(0, 0.4, 0), CURSE_RADIUS, CURSE, 0.5)
	# a slowly turning ring of curse runes floats over it while it lasts
	var ring := Node3D.new()
	ring.top_level = true
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.8, 0.4, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.7, 0.3, 1.0)
	for k in 12:
		var a := TAU * k / 12.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 0.05, 0.6) if k % 2 else Vector3(0.6, 0.05, 0.2)
		bm.material = m
		mi.mesh = bm
		mi.position = Vector3(cos(a), 0, sin(a)) * (CURSE_RADIUS - 0.6)
		mi.rotation.y = -a
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.add_child(mi)
	add_child(ring)
	ring.global_position = c + Vector3(0, 0.35, 0)
	var tw := create_tween()
	tw.tween_property(ring, "rotation:y", PI, CURSE_LIFE)
	tw.tween_callback(ring.queue_free)


# ------------------------------------------------------------------ bone spikes

## A bone spike bursting out of the ground at `at` after `delay` s, then sinking back.
func _spike(at: Vector3, h: float, delay := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _spike_mesh()
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	mi.rotation = Vector3(randf_range(-0.25, 0.25), randf() * TAU, randf_range(-0.25, 0.25))
	mi.scale = Vector3(1, 0.01, 1) * h
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(mi, "scale", Vector3.ONE * h, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.55)
	tw.tween_property(mi, "scale", Vector3(h, 0.01, h), 0.35)
	tw.tween_callback(mi.queue_free)
	counts["spikes"] = int(counts.get("spikes", 0)) + 1


static var _spike_cache: Mesh

static func _spike_mesh() -> Mesh:
	if _spike_cache == null:
		var mb := MeshBuilder.new()
		var bone := Color(0.84, 0.8, 0.68, 0.0)
		mb.add(MeshBuilder.cone(0.16, 1.0, 6), Transform3D(Basis(), Vector3(0, 0.5, 0)), bone)
		mb.add(MeshBuilder.cone(0.08, 0.5, 5), Transform3D(Basis(Vector3(0, 0, 1), 0.5), Vector3(0.12, 0.3, 0)), bone.darkened(0.1))
		mb.add(MeshBuilder.cone(0.07, 0.4, 5), Transform3D(Basis(Vector3(1, 0, 0), -0.5), Vector3(0, 0.25, 0.1)), bone.darkened(0.15))
		mb.add(MeshBuilder.sphere(0.2, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 0.3, 1)), Vector3.ZERO), Color(0.2, 0.15, 0.1, 0.0))
		_spike_cache = mb.commit()
	return _spike_cache


# ------------------------------------------------------------------ the soul drain

func _make_beam() -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.35
	cm.height = 1.0
	cm.radial_segments = 10
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
	float band = 0.5 + 0.5 * sin(UV.y * 40.0 - TIME * 30.0);
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALBEDO = vec3(0.35, 1.0, 0.5) * (0.6 + 0.8 * band) * 1.4;
	ALPHA = 0.8;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	cm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.top_level = true
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _begin_drain() -> void:
	_landed = true
	_beam_on = true
	_t = 0.0
	_phase_t = DRAIN_TIME
	_drain_tick = 0.0
	_beam.visible = true
	play_sfx("drain")


func _tick_drain(dt: float) -> void:
	var i := row()
	if i < 0:
		return
	var o := em.pos[i]
	# the beam swings after you, but only so fast
	var to := player.global_position - o
	to.y = 0.0
	if to.length() > 0.1:
		var want := atan2(to.x, to.z)
		var cur := atan2(_beam_dir.x, _beam_dir.z)
		var nxt := rotate_toward(cur, want, DRAIN_TURN * speed_k() * dt)
		_beam_dir = Vector3(sin(nxt), 0, cos(nxt))
		_aim = _beam_dir
	var from := model.tip_position()
	var end := ground(o + _beam_dir * DRAIN_LEN) + Vector3(0, 0.9, 0)
	var mid := (from + end) * 0.5
	var len := from.distance_to(end)
	_beam.global_transform = Transform3D(Basis.looking_at(end - from, Vector3.UP) * Basis(Vector3(1, 0, 0), PI * 0.5), mid).scaled_local(Vector3(1, len, 1))
	# in the beam: drained
	var rel := player.global_position - o
	rel.y = 0.0
	var along := rel.dot(_beam_dir)
	var across := (rel - _beam_dir * along).length()
	_drain_tick -= dt
	if along > 0.0 and along < DRAIN_LEN and across < DRAIN_WIDTH * 0.5 + 0.3 and _drain_tick <= 0.0:
		_drain_tick = 0.25
		player.invuln = 0.0
		var dmg := DRAIN_DPS * 0.25 * EnemyManager.BOSS_DAMAGE_MULT
		if player.hurt(dmg):
			counts["drain_hits"] = int(counts.get("drain_hits", 0)) + 1
			em.hp[i] = minf(em.hp_max[i], em.hp[i] + dmg * DRAIN_HEAL)
			if fx:
				fx.burst(player.global_position + Vector3(0, 1.0, 0), 0.8, GREEN, 0.3)
	_phase_t -= dt
	if _phase_t <= 0.0:
		_beam_on = false
		_beam.visible = false
		_done(0.4)


# ------------------------------------------------------------------ the graves open

func _begin_graves() -> void:
	counts["graves_open"] = int(counts.get("graves_open", 0)) + 1
	_t = 0.0
	_landed = false
	em.troll_busy = true
	em.boss_contact = false
	clear_warns()
	_beam_on = false
	_beam.visible = false
	model.pose("rise")
	play_sfx("laugh", 0.8)
	play_sfx("graves")
	main.hud.flash_message("THE GRAVES OPEN!  STAND ON CONSECRATED GROUND!", ULT_WARN - 1.0)
	# consecrated ground: the churchyard, and circles of holy light round the player
	_safe.clear()
	if GraveyardBuilder.chapel_at != Vector3.INF:
		var c := GraveyardBuilder.chapel_at
		_safe.append(Vector3(c.x, GraveyardBuilder.CONSECRATED_R, c.z))
	var pp := player.global_position
	var a0 := randf() * TAU
	for k in HOLY_CIRCLES:
		var a := a0 + TAU * k / HOLY_CIRCLES + randf_range(-0.3, 0.3)
		var p := pp + Vector3(cos(a), 0, sin(a)) * randf_range(10.0, 18.0)
		p.x = clampf(p.x, -190.0, 190.0)
		p.z = clampf(p.z, -190.0, 190.0)
		_safe.append(Vector3(p.x, HOLY_RADIUS, p.z))
		_pillar(ground(p))
	_curse_ground(1.0, 0.0)


func _tick_graves(dt: float) -> void:
	var f := clampf(_t / ULT_WARN, 0.0, 1.0)
	model.lift = lerpf(model.lift, ULT_RISE / SCALE if not _landed else 0.0, clampf(dt * 2.0, 0.0, 1.0))
	if not _landed:
		_curse_ground(1.0, f)
		player.add_shake(lerpf(0.1, 0.45, f))
		if randf() < dt * 3.0 and fx:   # the earth heaves here and there
			var p := player.global_position + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
			fx.burst(ground(p) + Vector3(0, 0.3, 0), 1.2, Color(0.3, 0.9, 0.35), 0.4)
		for p in _pillars:   # the holy light pulses brighter as it lands
			if is_instance_valid(p):
				p.scale = Vector3(1.0, 1.0 + 0.1 * sin(_t * 6.0), 1.0)
	if not _landed and _t >= ULT_WARN:
		_landed = true
		play_sfx("spikes", 0.7)
		player.add_shake(1.4)
		if not in_consecrated(player.global_position):
			if player.hurt_true(ULT_FRAC):
				counts["ult_hits"] = int(counts.get("ult_hits", 0)) + 1
				counts["hits"] += 1
		# bone spikes everywhere but the holy ground, and the dead rise
		var pp := player.global_position
		for k in 40:
			var p := ground(pp + Vector3(randf_range(-16, 16), 0, randf_range(-16, 16)))
			if not in_consecrated(p):
				_spike(p, randf_range(1.0, 2.2), randf() * 0.4)
		var undead: UndeadCrowd = em.undead
		if undead != null:
			undead.grave_swarm(pp, ULT_RAISE + (4 if is_enraged else 0), main.hp_mult() * 0.7, main.rng, 0.0)
		_curse_ground(0.0, 0.0)
		for p in _pillars:
			if is_instance_valid(p):
				var tw := create_tween()
				tw.tween_property(p, "scale", Vector3(0.01, 1.0, 0.01), 0.6)
				tw.tween_callback(p.queue_free)
		_pillars.clear()
	if _landed and _t >= ULT_WARN + 1.2:
		model.lift = 0.0
		_safe.clear()
		_done(0.8)


## Is `p` on consecrated ground right now (the churchyard or a circle of holy light)?
func in_consecrated(p: Vector3) -> bool:
	for s in _safe:
		if Vector2(p.x - s.x, p.z - s.z).length() < s.y:
			return true
	return false


func safe_zones() -> Array[Vector3]:
	return _safe


func _pillar(at: Vector3) -> void:
	var n := Node3D.new()
	n.top_level = true
	var cm := CylinderMesh.new()
	cm.top_radius = HOLY_RADIUS * 0.75
	cm.bottom_radius = HOLY_RADIUS
	cm.height = 30.0
	cm.cap_top = false
	cm.cap_bottom = false
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
	float fade = 1.0 - UV.y;
	float shimmer = 0.75 + 0.25 * sin(UV.x * 40.0 + TIME * 3.0);
	ALBEDO = vec3(1.0, 0.85, 0.5) * pow(fade, 3.0) * 0.6 * shimmer;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	cm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.position = Vector3(0, 15.0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.55)
	l.light_energy = 1.5
	l.omni_range = 8.0
	l.position = Vector3(0, 2.0, 0)
	n.add_child(l)
	add_child(n)
	n.global_position = at
	_pillars.append(n)


## Light up (or clear) the graveyard ground, all but the consecrated circles.
func _curse_ground(on: float, fill: float) -> void:
	var w = main.water if main != null else null
	if w == null or w.ground_mat == null:
		return
	var sm: ShaderMaterial = w.ground_mat
	sm.set_shader_parameter("curse", on)
	sm.set_shader_parameter("curse_fill", fill)
	var arr: Array[Vector4] = []
	for k in 8:
		if k < _safe.size() and on > 0.0:
			arr.append(Vector4(_safe[k].x, _safe[k].z, _safe[k].y, 1.0))
		else:
			arr.append(Vector4.ZERO)
	sm.set_shader_parameter("safe", arr)


# ------------------------------------------------------------------ enrage, death, drawing

func _on_enrage() -> void:
	model.set_enrage(true)
	play_sfx("laugh", 0.75)


func _on_die() -> void:
	play_sfx("death")
	model.pose("die")
	_beam.visible = false
	_beam_on = false
	_curse_ground(0.0, 0.0)
	for p in _pillars:
		if is_instance_valid(p):
			p.queue_free()
	_pillars.clear()
	# the dead he raised fall back into their graves
	for u in _risen_uids:
		var r := em.index_of(u)
		if r >= 0:
			em.damage(r, 1e9)
	_risen_uids.clear()


func _tick_death(dt: float) -> bool:
	# he shrieks, the soul-flame gutters out, and the robe collapses empty into the dirt in a
	# burst of escaping souls
	model.lift = maxf(0.0, model.lift - dt * 2.0)
	model.crumble = clampf((_die_t - 0.8) / 1.6, 0.0, 1.0)
	if _die_t > 0.8 and not has_meta("burst"):
		set_meta("burst", true)
		shake(0.8)
		if fx:
			for k in 8:
				fx.burst(global_position + Vector3(randf_range(-1.5, 1.5), 1.0 + k * 0.6, randf_range(-1.5, 1.5)), 2.0, GREEN, 0.9)
	if _die_t > 5.0:
		model.position.y -= dt * 0.6
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
			want = atan2(v.x, v.z)
		elif to.length() > 0.1:
			want = atan2(to.x, to.z)
		_yaw = rotate_toward(_yaw, want, TURN_RATE * dt)
	else:
		_yaw = rotate_toward(_yaw, atan2(_aim.x, _aim.z), 6.0 * dt)
	rotation.y = _yaw
	# floating up for his ultimate: his row stays below him, tall enough that shots still reach
	em.set_boss_stats({"height": stats()["height"] + model.lift * SCALE})
