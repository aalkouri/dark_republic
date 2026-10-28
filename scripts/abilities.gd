class_name Abilities
extends Node3D
## The fire wizard's three active abilities (keys 1 / 2 / 3).
##   (unlock: Inferno from the start, Fire Nova at level 5, Meteor at level 10)
##   1  Inferno        30 s  Ignites every enemy: 5% max HP/s for 10 s. Burning enemies that
##                           die explode for 50% of their max HP within 2 yd (chains).
##   2  Fire Nova      45 s  Ring of fire expanding 18 m from the floor under you; knocks enemies back 5 yd.
##   3  Meteor (ult)  120 s  The wizard vanishes (invulnerable) and becomes a giant flaming copy of
##                           his own head, which crashes where you aim 3 s later; he reappears
##                           there. Big AoE damage, then the ground burns for 3 s (3% max HP/s).
## Slot order lives in DEFS; refer to slots by INFERNO / SHOCKWAVE / METEOR, never by number.
## Cooldowns tick in the physics step, so they pause with the game.

signal cast(index: int)

const YARD := 0.9144

# Ability slots (index into DEFS / cooldown; key = index + 1)
const INFERNO := 0
const SHOCKWAVE := 1
const METEOR := 2

const METEOR_COOLDOWN := 120.0       # ultimate
const METEOR_FALL_TIME := 3.0
const METEOR_RADIUS := 8.0
const METEOR_DAMAGE := 250.0
const METEOR_RANGE := 45.0
const METEOR_KNOCKBACK := 3.0
const HEAD_SCALE := 8.0              # giant head: ~3 m across, hat towering above
const SCORCH_RADIUS := 7.0
const SCORCH_TIME := 3.0
const SCORCH_DPS := 0.03             # of max HP per second while standing in the fire

const SCORCH_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float fade = 1.0;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float d = length(c);
	float n = noise(wpos.xz * 1.1 + vec2(0.0, TIME * 1.6)) * 0.6 + noise(wpos.xz * 3.1 - vec2(TIME * 2.2, 0.0)) * 0.4;
	float edge = smoothstep(1.0, 0.72, d + (n - 0.5) * 0.45);
	float hot = smoothstep(0.35, 0.85, n);
	vec3 col = mix(vec3(0.55, 0.06, 0.0), vec3(1.0, 0.5, 0.08), hot);
	col = mix(col, vec3(1.0, 0.88, 0.45), smoothstep(0.78, 0.95, n));
	ALBEDO = col;
	ALPHA = edge * (0.3 + 0.7 * hot) * fade;
}
"""

const SHOCK_COOLDOWN := 45.0
const SHOCK_RADIUS := 18.0           # Fire Nova reach (doubled from 9 m)
const SHOCK_EXPAND_TIME := 0.7      # same feel: the ring still sweeps out at ~26 m/s
const SHOCK_DAMAGE := 80.0
const SHOCK_KNOCKBACK := 5.0 * YARD

const INFERNO_COOLDOWN := 30.0
const INFERNO_BURN_TIME := 10.0
const INFERNO_BURN_DPS := 0.05          # of max HP per second
const INFERNO_EXPLODE_FRAC := 0.5       # of the dying enemy's max HP
const INFERNO_EXPLODE_RADIUS := 2.0 * YARD

const INFERNO_SOUND := "res://audio/abilities/inferno.mp3"
const INFERNO_DELAY := 1.0   # the sound plays on the key press; the fire erupts this much later
const NOVA_SOUND := "res://audio/abilities/fire_nova.mp3"
const METEOR_SOUND := "res://audio/abilities/meteor.mp3"
const METEOR_IMPACT_SOUND := "res://audio/abilities/meteor_impact.wav"   # tools/gen_explosion_sound.py
const NOVA_DELAY := 1.0      # same wind-up for Fire Nova: sound first, the ring bursts out 1 s later

const DEFS := [
	{"name": "Inferno", "key": "1", "cooldown": INFERNO_COOLDOWN, "ult": false, "unlock_level": 1},
	{"name": "Fire Nova", "key": "2", "cooldown": SHOCK_COOLDOWN, "ult": false, "unlock_level": 5},
	{"name": "Meteor", "key": "3", "cooldown": METEOR_COOLDOWN, "ult": true, "unlock_level": 10},
]

var stats: Stats
var enemies: EnemyManager
var player: Player
var fx: FxManager

var cooldown := PackedFloat32Array([0.0, 0.0, 0.0])

var _meteors: Array = []   # {target, t, head, marker, fill, start}
var _scorches: Array = []  # {center, t, node, mat, light}
var _scorch_shader: Shader
var _shocks: Array = []    # {center, t, hit: Dictionary, ring, disc}
var _fire_mat: StandardMaterial3D


func setup(p_stats: Stats, p_enemies: EnemyManager, p_player: Player, p_fx: FxManager) -> void:
	stats = p_stats
	enemies = p_enemies
	player = p_player
	fx = p_fx
	enemies.burn_dps_frac = INFERNO_BURN_DPS
	enemies.burn_explode_frac = INFERNO_EXPLODE_FRAC
	enemies.burn_explode_radius = INFERNO_EXPLODE_RADIUS


var inferno_sfx: AudioStreamPlayer
var _inferno_wait := -1.0   # >= 0 while an Inferno cast is winding up
var nova_sfx: AudioStreamPlayer
var meteor_sfx: AudioStreamPlayer
var impact_sfx: AudioStreamPlayer
var _nova_wait := -1.0


func _ready() -> void:
	inferno_sfx = AudioStreamPlayer.new()   # 2D: the caster always hears it at full volume
	inferno_sfx.bus = Settings.SFX_BUS
	inferno_sfx.max_polyphony = 2
	if ResourceLoader.exists(INFERNO_SOUND):
		inferno_sfx.stream = load(INFERNO_SOUND)
	add_child(inferno_sfx)
	nova_sfx = AudioStreamPlayer.new()
	nova_sfx.bus = Settings.SFX_BUS
	nova_sfx.max_polyphony = 2
	if ResourceLoader.exists(NOVA_SOUND):
		nova_sfx.stream = load(NOVA_SOUND)
	add_child(nova_sfx)
	meteor_sfx = _sfx(METEOR_SOUND, 0.0)
	impact_sfx = _sfx(METEOR_IMPACT_SOUND, 2.0)
	_fire_mat = StandardMaterial3D.new()
	_fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fire_mat.disable_fog = true   # additive + fog = pale grey halos
	_fire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fire_mat.albedo_color = Color(1.0, 0.45, 0.1, 0.9)



## Player level, kept up to date by main; abilities unlock at DEFS[i].unlock_level.
var level := 1


## Tooltip text (BBCode) with the current numbers, including the Damage stat.
func describe(i: int) -> String:
	var lines := describe_lines(i, stats.value("damage") if stats != null else 1.0)
	lines.append("")
	if not is_unlocked(i):
		lines.append("[color=#ff7060]Locked: unlocks at level %d[/color]" % int(DEFS[i]["unlock_level"]))
	elif cooldown[i] > 0.0:
		lines.append("[color=#cccccc]Ready in %s[/color]" % _fmt_cd(cooldown[i]))
	else:
		lines.append("[color=#7dff7d]Ready[/color]")
	return "\n".join(lines)


## Title, key/cooldown and what the ability does (BBCode lines), without the live status, so
## the character select screen can show the same text outside a run.
static func describe_lines(i: int, dmg_mult := 1.0) -> Array[String]:
	var d: Dictionary = DEFS[i]
	var bonus := "" if is_equal_approx(dmg_mult, 1.0) else "  [color=#9be37a](+%d%% from Damage)[/color]" % roundi((dmg_mult - 1.0) * 100.0)
	var hot := "[color=#ffb347]%s[/color]"
	var lines: Array[String] = []
	var title := "[font_size=22][b]%s[/b][/font_size]" % d["name"]
	if d["ult"]:
		title += "  [color=#ffd23f][ULTIMATE][/color]"
	lines.append(title)
	lines.append("[color=#aaaaaa]Key %s  ·  Cooldown %s[/color]" % [d["key"], _fmt_cd(float(d["cooldown"]))])
	lines.append("")
	match i:
		INFERNO:
			lines.append("Sets [b]every goblin[/b] on fire.")
			lines.append("• Burn: %s of max HP per second for %s (%s total)" % [hot % ("%d%%" % roundi(INFERNO_BURN_DPS * 100.0)), hot % ("%d s" % roundi(INFERNO_BURN_TIME)), hot % ("%d%%" % roundi(INFERNO_BURN_DPS * INFERNO_BURN_TIME * 100.0))])
			lines.append("• Burning goblins that die explode for %s of their max HP to goblins within %s; explosions chain" % [hot % ("%d%%" % roundi(INFERNO_EXPLODE_FRAC * 100.0)), hot % "2 yd"])
		SHOCKWAVE:
			lines.append("A ring of fire bursts out from the ground under you.")
			lines.append("• %s damage to every goblin within %s%s" % [hot % str(roundi(SHOCK_DAMAGE * dmg_mult)), hot % ("%d m" % roundi(SHOCK_RADIUS)), bonus])
			lines.append("• Knocks them back %s" % (hot % "5 yd"))
		METEOR:
			lines.append("You vanish and become a giant flaming copy of your own head. [b]Invulnerable[/b] while falling.")
			lines.append("• Crashes where you aim after %s: %s damage within %s%s, plus knockback" % [hot % ("%d s" % roundi(METEOR_FALL_TIME)), hot % str(roundi(METEOR_DAMAGE * dmg_mult)), hot % ("%d m" % roundi(METEOR_RADIUS)), bonus])
			lines.append("• You reappear at the crash site")
			lines.append("• The ground burns for %s: %s of max HP per second within %s" % [hot % ("%d s" % roundi(SCORCH_TIME)), hot % ("%d%%" % roundi(SCORCH_DPS * 100.0)), hot % ("%d m" % roundi(SCORCH_RADIUS))])
	return lines


static func _fmt_cd(secs: float) -> String:
	if secs >= 60.0:
		var m := int(secs) / 60
		var s := int(ceil(secs)) % 60
		return "%d min" % m if s == 0 else "%d:%02d" % [m, s]
	return "%d s" % ceili(secs)


func is_unlocked(i: int) -> bool:
	return level >= int(DEFS[i]["unlock_level"])


func is_ready(i: int) -> bool:
	return is_unlocked(i) and cooldown[i] <= 0.0


func fraction_remaining(i: int) -> float:
	return clampf(cooldown[i] / float(DEFS[i]["cooldown"]), 0.0, 1.0)


func reset_cooldowns() -> void:
	cooldown = PackedFloat32Array([0.0, 0.0, 0.0])


func try_cast(i: int) -> bool:
	if i < 0 or i >= DEFS.size() or not is_ready(i):
		return false
	match i:
		INFERNO:
			_cast_inferno()
		SHOCKWAVE:
			_cast_shockwave()
		METEOR:
			_cast_meteor()
	cooldown[i] = DEFS[i]["cooldown"] * (stats.value("ability_cdr") if stats.has_stat("ability_cdr") else 1.0)
	cast.emit(i)
	return true


func tick(dt: float) -> void:
	for i in cooldown.size():
		cooldown[i] = maxf(0.0, cooldown[i] - dt)
	if _inferno_wait >= 0.0:
		_inferno_wait -= dt
		if _inferno_wait < 0.0:
			_erupt_inferno()
	if _nova_wait >= 0.0:
		_nova_wait -= dt
		if _nova_wait < 0.0:
			_erupt_shockwave()
	_update_meteors(dt)
	_update_scorches(dt)
	_update_shocks(dt)


# ------------------------------------------------------------------ 1: Meteor

## A 2D sound player on the SFX bus (the caster always hears it at full volume).
func _sfx(path: String, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = Settings.SFX_BUS
	p.volume_db = volume_db
	p.max_polyphony = 2
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p


func _cast_meteor() -> void:
	meteor_sfx.play()
	var target := _aim_point()
	var marker := _ground_disc(METEOR_RADIUS, Color(1.0, 0.15, 0.05, 0.22))
	marker.global_position = target + Vector3(0, 0.05, 0)
	var fill := _ground_disc(METEOR_RADIUS, Color(1.0, 0.4, 0.05, 0.35))
	fill.global_position = target + Vector3(0, 0.07, 0)
	fill.scale = Vector3(0.01 * METEOR_RADIUS, 1, 0.01 * METEOR_RADIUS)

	# Comes in at an angle, from behind the caster.
	var back := (target - player.global_position)
	back.y = 0.0
	back = back.normalized() if back.length() > 0.5 else Vector3(0, 0, 1)
	var start := target - back * 35.0 + Vector3(0, 75.0, 0)

	var head := _make_giant_head()
	head.global_position = start
	_face(head, target)
	player.enter_meteor_form()
	player.global_position = start - Vector3(0, 1.6, 0)
	_meteors.append({"target": target, "t": 0.0, "head": head, "marker": marker, "fill": fill, "start": start})


## A giant copy of the wizard's own head and hat, wreathed in fire.
func _make_giant_head() -> Node3D:
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	var scaled := Node3D.new()
	scaled.scale = Vector3.ONE * HEAD_SCALE
	root.add_child(scaled)
	var parts := Node3D.new()
	parts.position = Vector3(0, -1.5, 0)   # head centre at the root's origin
	scaled.add_child(parts)
	WizardModel.build_head(parts)
	# Fire: an engulfing blaze around the head plus a long trail behind it
	var blaze := _flame_particles(3.2, 0.7, 160)
	blaze.emission_sphere_radius = 2.2
	root.add_child(blaze)
	var trail := _flame_particles(3.6, 1.6, 220)
	trail.emission_sphere_radius = 1.6
	trail.gravity = Vector3(0, 6.0, 0)
	root.add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 5.0
	light.omni_range = 22.0
	root.add_child(light)
	return root


## Point the face (-Z) at the target.
func _face(n: Node3D, target: Vector3) -> void:
	var d := target - n.global_position
	if d.length_squared() > 0.01:
		n.basis = Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.FORWARD)


func _aim_point() -> Vector3:
	var cam := player.cam
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var p: Vector3
	if hit.is_empty():
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		p = player.global_position + flat * 20.0
		p.y = SwampWater.height_at(p.x, p.z)
	else:
		p = hit["position"]
	var off := p - player.global_position
	off.y = 0.0
	if off.length() > METEOR_RANGE:
		p = player.global_position + off.normalized() * METEOR_RANGE
	p.y = SwampWater.height_at(p.x, p.z)
	return _floor_below(p + Vector3(0, 0.5, 0))


func _update_meteors(dt: float) -> void:
	for k in range(_meteors.size() - 1, -1, -1):
		var m: Dictionary = _meteors[k]
		m["t"] += dt
		var tt: float = m["t"] / METEOR_FALL_TIME
		var target: Vector3 = m["target"]
		var marker: GroundDisc = m["marker"]
		var fill: GroundDisc = m["fill"]
		var head: Node3D = m["head"]
		if tt < 1.0:
			var e := tt * tt   # accelerates as it falls
			head.global_position = (m["start"] as Vector3).lerp(target + Vector3(0, 1.5, 0), e)
			player.global_position = head.global_position - Vector3(0, 1.6, 0)   # camera rides along
			fill.scale = Vector3(tt * METEOR_RADIUS, 1, tt * METEOR_RADIUS)
			marker.alpha = 0.18 + 0.12 * sin(m["t"] * 12.0)
			continue
		player.exit_meteor_form(target)
		_meteor_impact(target)
		_start_scorch(target)
		marker.queue_free()
		fill.queue_free()
		head.queue_free()
		_meteors.remove_at(k)


## Trees (and fallen trees) caught in the blast catch fire and char over 15 s.
func _ignite_trees(at: Vector3) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group(TreeFire.GROUP):
		var body := b as Node3D
		var d := Vector2(body.global_position.x - at.x, body.global_position.z - at.z).length()
		if d <= METEOR_RADIUS + float(body.get_meta("reach", 1.5)) and TreeFire.ignite(body):
			n += 1
	return n


func _meteor_impact(at: Vector3) -> void:
	impact_sfx.play()
	_ignite_trees(at)
	var dmg := METEOR_DAMAGE * stats.value("damage")
	for i in enemies.query_radius(Vector3(at.x, 0.8, at.z), METEOR_RADIUS, false):
		var away := enemies.pos[i] - at
		if not enemies.damage(i, dmg):
			enemies.knock(i, away, METEOR_KNOCKBACK, 0.2)
	fx.burst(at + Vector3(0, 1.0, 0), METEOR_RADIUS * 1.1, Color(1.0, 0.4, 0.08), 0.6)
	fx.burst(at + Vector3(0, 2.5, 0), METEOR_RADIUS * 0.6, Color(1.0, 0.8, 0.3), 0.4)
	for n in 10:
		var a := randf() * TAU
		var r := randf_range(1.0, METEOR_RADIUS * 0.9)
		fx.burst(at + Vector3(cos(a) * r, randf_range(0.3, 2.0), sin(a) * r), randf_range(1.0, 2.2), Color(1.0, 0.35, 0.05), randf_range(0.4, 0.8))
	var d := player.global_position.distance_to(at)
	player.add_shake(clampf(1.2 - d / 40.0, 0.15, 1.0))


## Burning ground left by the crash: SCORCH_DPS of max HP per second for SCORCH_TIME.
func _start_scorch(at: Vector3) -> void:
	if _scorch_shader == null:
		_scorch_shader = Shader.new()
		_scorch_shader.code = SCORCH_SHADER
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	root.global_position = at + Vector3(0, 0.06, 0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(SCORCH_RADIUS * 2.0, SCORCH_RADIUS * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = _scorch_shader
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var flames := _flame_particles(1.4, 0.8, 140)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	flames.emission_ring_axis = Vector3.UP
	flames.emission_ring_radius = SCORCH_RADIUS * 0.85
	flames.emission_ring_inner_radius = 0.0
	flames.emission_ring_height = 0.1
	flames.initial_velocity_min = 1.0
	flames.initial_velocity_max = 2.5
	root.add_child(flames)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.1)
	light.light_energy = 3.0
	light.omni_range = SCORCH_RADIUS * 2.2
	light.position.y = 1.5
	root.add_child(light)
	_scorches.append({"center": at, "t": 0.0, "node": root, "mat": mat, "light": light, "flames": flames})


func _update_scorches(dt: float) -> void:
	for k in range(_scorches.size() - 1, -1, -1):
		var z: Dictionary = _scorches[k]
		z["t"] += dt
		var t: float = z["t"]
		if t >= SCORCH_TIME + 0.6:   # fire is out; let the last flames die down
			(z["node"] as Node3D).queue_free()
			_scorches.remove_at(k)
			continue
		var fade := clampf((SCORCH_TIME - t) / 0.5, 0.0, 1.0)
		(z["mat"] as ShaderMaterial).set_shader_parameter("fade", fade)
		(z["light"] as OmniLight3D).light_energy = (2.6 + 0.8 * sin(t * 23.0) * sin(t * 9.0)) * fade
		(z["flames"] as CPUParticles3D).emitting = t < SCORCH_TIME
		if t <= SCORCH_TIME:
			var c: Vector3 = z["center"]
			for i in enemies.query_radius(Vector3(c.x, 0.8, c.z), SCORCH_RADIUS, false):
				enemies.dot_damage(i, enemies.hp_max[i] * SCORCH_DPS * dt)


func scorch_count() -> int:
	return _scorches.size()


# ------------------------------------------------------------------ 2: Fire Nova

func _cast_shockwave() -> void:
	nova_sfx.play()
	_nova_wait = NOVA_DELAY


## The ring bursts out from wherever the wizard is standing when the wind-up ends.
func _erupt_shockwave() -> void:
	var center := _floor_below(player.global_position + Vector3(0, 0.5, 0))
	# The fire ring is drawn on the ground so it rolls over the hills
	var ring := _ground_disc(1.0, Color(1.0, 0.45, 0.1, 0.75), true)
	ring.set_ring(0.9)
	ring.set_lift(0.2)
	ring.global_position = center
	var disc := _ground_disc(1.0, Color(1.0, 0.3, 0.04, 0.12), true)
	disc.global_position = center + Vector3(0, 0.06, 0)
	_shocks.append({"center": center, "t": 0.0, "hit": {}, "ring": ring, "disc": disc})
	player.add_shake(0.35)


func _update_shocks(dt: float) -> void:
	var dmg := SHOCK_DAMAGE * stats.value("damage")
	for k in range(_shocks.size() - 1, -1, -1):
		var s: Dictionary = _shocks[k]
		s["t"] += dt
		var tt: float = s["t"] / SHOCK_EXPAND_TIME
		var center: Vector3 = s["center"]
		var ring: GroundDisc = s["ring"]
		var disc: GroundDisc = s["disc"]
		var r := SHOCK_RADIUS * minf(tt, 1.0)
		if tt <= 1.0:
			var hit: Dictionary = s["hit"]
			for i in enemies.query_radius(Vector3(center.x, 0.8, center.z), r, false):
				var u := enemies.uid[i]
				if hit.has(u):
					continue
				hit[u] = true
				var away := enemies.pos[i] - center
				if not enemies.damage(i, dmg):
					enemies.knock(i, away, SHOCK_KNOCKBACK, 0.3)
		# Visual: ring rides the front, then fades out
		var fade := clampf(1.0 - (tt - 1.0) / 0.5, 0.0, 1.0)
		var vr := maxf(r, 0.3)
		ring.scale = Vector3(vr, 1, vr)
		ring.set_ring(clampf(1.0 - 1.4 / vr, 0.0, 0.92))   # a band ~1.4 m wide
		disc.scale = Vector3(vr, 1, vr)
		ring.alpha = 0.75 * fade
		disc.alpha = 0.12 * fade
		if tt > 1.0 and fade <= 0.0:
			ring.queue_free()
			disc.queue_free()
			_shocks.remove_at(k)
		elif tt <= 1.0 and Engine.get_physics_frames() % 3 == 0:
			var a := randf() * TAU
			var bx := center.x + cos(a) * r
			var bz := center.z + sin(a) * r
			if fx: fx.burst(Vector3(bx, SwampWater.height_at(bx, bz) + 0.6, bz), 1.1, Color(1.0, 0.4, 0.08), 0.3)


# ------------------------------------------------------------------ 3: Inferno (ultimate)

func _cast_inferno() -> void:
	inferno_sfx.play()
	_inferno_wait = INFERNO_DELAY


func _erupt_inferno() -> void:
	var n := enemies.ignite_all(INFERNO_BURN_TIME)
	var at := player.global_position + Vector3(0, 1.0, 0)
	if fx:
		fx.burst(at, 6.0, Color(1.0, 0.75, 0.25), 0.5)
		fx.burst(at, 14.0, Color(1.0, 0.3, 0.05), 0.8)
	player.add_shake(0.6)
	print_verbose("Inferno ignited %d enemies" % n)


# ------------------------------------------------------------------ helpers

func _floor_below(from: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -200, 0))
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector3(from.x, SwampWater.height_at(from.x, from.z), from.z)
	return hit["position"]


func _ground_disc(radius: float, color: Color, additive := false) -> GroundDisc:
	var g := GroundDisc.create(radius, color, additive)
	add_child(g)
	return g


## Shared fire particle emitter (meteor trail, wizard flames).
static func _flame_particles(size: float, lifetime: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.6
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 2.0, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.35, 1.0))
	grad.set_color(1, Color(0.6, 0.05, 0.0, 0.0))
	grad.add_point(0.35, Color(1.0, 0.35, 0.05, 0.8))
	p.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_fog = true   # additive + fog = pale grey halos
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	p.mesh = quad
	return p


static var _dot_tex: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 32
		t.height = 32
		_dot_tex = t
	return _dot_tex
