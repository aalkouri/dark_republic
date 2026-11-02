class_name HeroEntrances
extends Node3D
## Run-start entrances for the roster characters: each one arrives in its own way (no two
## alike, and no glowing ball falling from the sky). The Fire Wizard keeps his giant flaming
## head and the Thunder Wizard (and any character without an entry here) keeps the comet; both
## of those live in Abilities. A kit can also bring its own (RosterKit.entrance: An Argyle
## Sock's washing machine), which comes first.
##
## Abilities.entrance_meteor() makes one of these, calls start(), ticks it from its own tick()
## while the world holds still, and passes `landed` on as entrance_landed. One function per
## character (named after its id) builds its props on the first tick and animates everything
## from the elapsed time `t`. At `hit_at` the arrival hurts and knocks back the enemies within
## METEOR_RADIUS like the old comet did; at `dur` the hero is standing on the target, the player
## leaves the entrance form and `landed` fires once. Leftover debris fades for LINGER seconds,
## then the node frees itself.
##
## Sounds: audio/entrances/<id>.wav (tools/gen_entrance_sounds.py), timed to each timeline.

signal landed

const RADIUS := Abilities.METEOR_RADIUS
const LINGER := 3.0
const SOUND_DIR := "res://audio/entrances/"
const TENDRIL_BEADS := 22   # beads per Dark Wizard shadow tendril (overlapping, so they read as one)

## id -> [kind, duration s, impact at s, shake, camera distance from -> to, pitch from -> to]
const SPECS := {
	"ice_wizard":       ["frost_spire",      3.2, 2.3,  0.6, 9.0, 7.0, -0.24, -0.3],
	"dark_wizard":      ["shadow_rise",      3.3, 2.5,  0.45, 8.5, 6.8, -0.3, -0.3],
	"merlin":           ["rewind",           3.2, 2.6,  0.3, 9.0, 7.0, -0.2, -0.3],
	"ogre":             ["bog_geyser",       3.3, 1.6,  0.75, 9.0, 7.0, -0.2, -0.3],
	"ghast":            ["fog_wail",         3.3, 2.5,  0.4, 9.0, 6.8, -0.24, -0.3],
	"vampire_hunter":   ["bat_whirlwind",    3.2, 2.0,  0.4, 9.0, 7.0, -0.2, -0.3],
	"vicki":            ["valkyrie_descent", 3.4, 2.6,  0.55, 9.5, 7.5, -0.05, -0.3],
	"rogue":            ["smoke_bomb",       3.1, 1.0,  0.3, 8.5, 7.0, -0.3, -0.3],
	"gaiden":           ["leaf_slash",       3.0, 2.0,  0.4, 8.5, 7.0, -0.26, -0.3],
	"dr_croc":          ["chemical_lurk",    3.3, 1.9,  0.4, 8.0, 6.8, -0.3, -0.3],
	"blob":             ["ooze_seep",        3.2, 2.5,  0.3, 8.5, 7.0, -0.4, -0.3],
	"arachnid":         ["silk_drop",        3.2, 2.6,  0.4, 6.5, 6.5, -0.1, -0.3],
	"loco_robotico":    ["pinata_party",     3.4, 1.5,  0.3, 10.0, 7.5, -0.12, -0.3],
	"toadstool_knight": ["fairy_ring",       3.2, 2.5,  0.4, 11.0, 7.5, -0.16, -0.3],
	"thog":             ["troll_leap",       3.2, 2.45, 1.0, 10.0, 8.0, 0.12, -0.3],
	"pharaoh":          ["sarcophagus_rise", 3.3, 2.2,  0.45, 9.0, 7.0, -0.2, -0.3],
	"necromancer":      ["grave_rise",       3.3, 1.95, 0.45, 8.5, 7.0, -0.24, -0.3],
	"singe":            ["fuse_flare",       3.0, 1.9,  0.5, 9.5, 7.0, -0.32, -0.3],
}

## The kind of the latest run-start entrance (tests): one of the SPECS kinds, "comet" /
## "giant_head" (the Thunder and Fire Wizards) or "kit" (a kit's own, e.g. the Sock's).
static var last_kind := ""

var ab: Abilities
var player: Player
var hero: RosterHero
var kit := ""
var target := Vector3.ZERO
var t := 0.0
var dt := 0.0
var dur := 3.0
var hit_at := 2.0
var shake := 0.4
var hits := 0               # enemies the arrival hurt (tests)
var is_landed := false
var _hit := false
var _fwd := Vector3.FORWARD   # flat, from the camera toward the target
var _right := Vector3.RIGHT
var _to_cam := Vector3.BACK
var _yaw := 0.0               # the hero's facing during the entrance (3/4 toward the camera)
var _pitch0 := -0.3
var s := {}                   # this entrance's props and numbers
var _restore: Array[Callable] = []   # undone when the hero lands
var _sfx: AudioStreamPlayer


static func has_entrance(id: String) -> bool:
	return SPECS.has(id)


static func kind_of(id: String) -> String:
	return str(SPECS[id][0]) if SPECS.has(id) else "comet"


func start(p_ab: Abilities, id: String, at: Vector3) -> void:
	ab = p_ab
	player = ab.player
	kit = id
	target = at
	top_level = true
	global_transform = Transform3D.IDENTITY   # children are placed in world space
	var spec: Array = SPECS[id]
	last_kind = spec[0]
	dur = spec[1]
	hit_at = spec[2]
	shake = spec[3]
	hero = player.model as RosterHero
	var yaw := player.cam_yaw
	_fwd = Vector3(-sin(yaw), 0.0, -cos(yaw))
	_right = Vector3(cos(yaw), 0.0, -sin(yaw))
	_to_cam = -_fwd
	_yaw = yaw + PI - 0.45
	_pitch0 = player.cam_pitch
	player.enter_meteor_form()
	player.model.hide_now()
	player.global_position = target
	player.rig.global_position = target + Vector3(0, 1.6, 0)   # the camera starts on the spot
	hero.position = Vector3.ZERO
	hero.rotation = Vector3(0, _yaw, 0)
	# The weapon's projectile batch idles at the world origin (the spot) until weapons first
	# tick, after the landing: keep it out of the shot meanwhile
	var weapons: Node3D = ab.roster.weapons if ab.roster != null else null
	if weapons != null and weapons.visible:
		weapons.visible = false
		_restore.append(func() -> void:
			if is_instance_valid(weapons):
				weapons.visible = true)
	var path := SOUND_DIR + id + ".wav"
	if ResourceLoader.exists(path):
		_sfx = AudioStreamPlayer.new()
		_sfx.bus = Settings.SFX_BUS
		_sfx.stream = load(path)
		add_child(_sfx)
		_sfx.play()
	tick(0.0)


func tick(delta: float) -> void:
	dt = delta
	t += delta
	if not is_landed:
		var spec: Array = SPECS[kit]
		var kc := _eio(clampf(t / dur, 0.0, 1.0))
		player.spring.spring_length = lerpf(spec[4], spec[5], kc)
		player.cam_pitch = lerpf(spec[6], spec[7], kc)
	call("_" + kit)
	if not _hit and t >= hit_at:
		_hit = true
		_impact()
	if not is_landed and t >= dur:
		_land()
	if t >= dur + LINGER:
		queue_free()


## The arrival hurts: like the comet, METEOR_DAMAGE within METEOR_RADIUS, with knockback.
func _impact() -> void:
	var dmg := Abilities.METEOR_DAMAGE * ab.stats.value("damage") * ab.power(Abilities.METEOR)
	var em := ab.enemies
	# A straight scan, not query_radius: the enemy grid isn't rebuilt while the world holds still
	for i in em.count:
		if em.dead[i] or Vector2(em.pos[i].x - target.x, em.pos[i].z - target.z).length() > RADIUS:
			continue
		hits += 1
		if not em.damage(i, dmg):
			em.knock(i, em.pos[i] - target, Abilities.METEOR_KNOCKBACK, 0.2)
	if ab.fx:
		ab.fx.burst_fired.emit(target + Vector3(0, 0.5, 0), RADIUS * 0.6)   # shoves loose props
	player.add_shake(shake)


func _land() -> void:
	is_landed = true
	for f in _restore:
		f.call()
	_restore.clear()
	hero.transform = Transform3D(Basis(Vector3.UP, _yaw).scaled(Vector3.ONE * player.size_mult), Vector3.ZERO)
	hero.set_flash(0.0)
	hero.set_motion(0.0, false)
	player.cam_pitch = _pitch0
	player.exit_meteor_form(target)
	landed.emit()


# ------------------------------------------------------------------ helpers

## 0..1 as t goes from a to b.
func _k(a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


## True on the one tick that t passes `time`.
func _at(time: float) -> bool:
	return t >= time and t - dt < time


static func _eo(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _ei(x: float) -> float:
	return x * x * x


static func _eio(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Overshoots a little past 1, then settles.
static func _back(x: float) -> float:
	var c := 2.0
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)


static func _gy(x: float, z: float) -> float:
	return SwampWater.height_at(x, z)


static func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, _gy(p.x, p.z), p.z)


## Thrown debris: drag slows it sideways, gravity pulls it down, the ground stops it.
static func _fly(p0: Vector3, v: Vector3, tau: float, grav: float, drag := 1.2, rest := 0.05) -> Vector3:
	var h := Vector3(v.x, 0.0, v.z) * ((1.0 - exp(-drag * tau)) / drag)
	var p := Vector3(p0.x + h.x, p0.y + v.y * tau - 0.5 * grav * tau * tau, p0.z + h.z)
	var gy := _gy(p.x, p.z) + rest
	if p.y < gy:
		p.y = gy
	return p


func _add(n: Node3D, at := Vector3.ZERO, parent: Node3D = null) -> Node3D:
	(parent if parent != null else self).add_child(n)
	n.position = at
	return n


func _mesh(m: Mesh, mat: Material, at := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	_add(mi, at, parent)
	return mi


static func _lit(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _glow(c: Color, additive := true) -> StandardMaterial3D:
	return KitPart.glow_mat(c, additive)


## A material that takes its colour from the vertex / multimesh instance colour.
static func _vc(unshaded := false, additive := false, billboard := false, soft := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.disable_fog = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	if soft:
		m.albedo_texture = Abilities._soft_dot()
	return m


func _light(at: Vector3, c: Color, energy: float, r: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = r
	l.shadow_enabled = false
	_add(l, at)
	return l


func _flash(at: Vector3, c: Color, energy: float, r: float, secs: float) -> void:
	var l := _light(at, c, energy, r)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, secs)
	tw.tween_callback(l.queue_free)


## A flash: a quick light and a pop of glowing motes (not FxManager's sphere, which reads as
## a glass dome this close to the camera); the ground rings show the reach.
func _burst(at: Vector3, r: float, c: Color, life := 0.4) -> void:
	_flash(at, c, 5.0, clampf(r * 2.0, 4.0, 16.0), life + 0.15)
	var n := clampi(int(r * 6.0), 10, 50)
	var glows := c.get_luminance() > 0.45   # earthy colours (mud, rock) are motes, not glows
	_pop(at, n, clampf(r * 0.12, 0.25, 0.7), life + 0.3, Color(c.lightened(0.4 if glows else 0.1), 0.9), Color(c, 0.0), clampf(r * 1.5, 3.0, 10.0), 1.0, glows)


## A ring sweeping out over the ground to `radius` in `secs`, fading as it goes.
func _ring(at: Vector3, radius: float, c: Color, secs: float, additive := true) -> void:
	var g := GroundDisc.create(1.0, c, additive)
	add_child(g)
	g.global_position = at
	g.set_ring(0.86)
	g.set_lift(0.12)
	g.scale = Vector3(0.4, 1.0, 0.4)
	var tw := g.create_tween().set_parallel(true)
	tw.tween_property(g, "scale", Vector3(radius, 1.0, radius), secs).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(g, "alpha", 0.0, secs).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(g.queue_free)


## Particles: `amount` motes of `size` m living `life` s, coloured c0 -> c1.
func _emitter(size: float, life: float, amount: int, c0: Color, c1: Color, additive := true, at := Vector3.ZERO) -> CPUParticles3D:
	var p := Abilities._flame_particles(size, life, amount)
	var grad := Gradient.new()
	grad.set_color(0, c0)
	grad.set_color(1, c1)
	p.color_ramp = grad
	if not additive:
		var m := (p.mesh as QuadMesh).material as StandardMaterial3D
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		# Particle billboards draw the unused (not yet born / dead) slots as a dark disc at the
		# emitter in the Compatibility renderer (additive hides it, normal blending doesn't);
		# a plain billboard that keeps the instance's (zero) scale doesn't
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	add_child(p)
	p.position = at
	return p


## One explosive puff of particles.
func _pop(at: Vector3, amount: int, size: float, life: float, c0: Color, c1: Color, speed: float, grav: float, additive := true) -> CPUParticles3D:
	# A burst from a normal emitter switched off after a moment, not a one_shot: one-shot
	# normal-blend puffs draw as a dark clump in the Compatibility renderer
	var p := _emitter(size, life, amount, c0, c1, additive, at)
	p.explosiveness = 0.85
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -grav, 0)
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(minf(0.12, life * 0.3))
	tw.tween_callback(func() -> void: p.emitting = false)
	tw.tween_interval(life + 0.2)
	tw.tween_callback(p.queue_free)
	return p


## Grow-then-fade curve for smoke and mist puffs (instead of the flames' shrink).
static func _grow_curve(a := 0.4, b := 1.0) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	return c


class Swarm:
	extends RefCounted
	## Many small moving things in one MultiMesh (shards, crows, bats, leaves, confetti...);
	## the entrance places every instance each tick. Spare per-instance slots: p, q, v, f, g.
	var mm: MultiMesh
	var node: MultiMeshInstance3D
	var n := 0
	var p := PackedVector3Array()
	var q := PackedVector3Array()
	var v := PackedVector3Array()
	var f := PackedFloat32Array()
	var g := PackedFloat32Array()
	var c := PackedColorArray()

	func put(i: int, b: Basis, o: Vector3, col: Color) -> void:
		mm.set_instance_transform(i, Transform3D(b, o))
		mm.set_instance_color(i, col)

	func hide(i: int) -> void:
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -500, 0)))
		mm.set_instance_color(i, Color(0, 0, 0, 0))


func _swarm(mesh: Mesh, n: int, mat: Material) -> Swarm:
	var sw := Swarm.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(target - Vector3(90, 40, 90), Vector3(180, 120, 180))
	add_child(mi)
	sw.mm = mm
	sw.node = mi
	sw.n = n
	sw.p.resize(n)
	sw.q.resize(n)
	sw.v.resize(n)
	sw.f.resize(n)
	sw.g.resize(n)
	sw.c.resize(n)
	for i in n:
		sw.hide(i)
	return sw


## Flat triangle(s) as mesh arrays MeshBuilder.add() takes (both faces).
static func _tris(pts: PackedVector3Array) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in range(0, pts.size(), 3):
		var a := pts[k]
		var b := pts[k + 1]
		var c := pts[k + 2]
		var nrm := (b - a).cross(c - a).normalized()
		if not nrm.is_finite() or nrm.length_squared() < 0.5:
			nrm = Vector3.UP
		var base := verts.size()
		verts.append_array(PackedVector3Array([a, b, c, a, c, b]))
		norms.append_array(PackedVector3Array([nrm, nrm, nrm, -nrm, -nrm, -nrm]))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base + 3, base + 4, base + 5]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## A bird or a bat, wings spread along X, facing -Z, about 1 m across. Flap it by scaling Y.
static func _flyer_mesh(bat: bool) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var w := Color(1, 1, 1, 1)
	mb.add(MeshBuilder.sphere(0.07, 8, 5), Transform3D(Basis().scaled(Vector3(0.8, 0.8, 2.2)), Vector3.ZERO), w)
	mb.add(MeshBuilder.sphere(0.055, 8, 5), Transform3D(Basis(), Vector3(0, 0.02, -0.17)), w)
	for sx in [-1.0, 1.0]:
		if bat:   # scalloped membrane in three fingers
			mb.add(_tris(PackedVector3Array([
				Vector3(0, 0, -0.08), Vector3(sx * 0.5, 0.3, -0.05), Vector3(sx * 0.22, 0.12, 0.12),
				Vector3(0, 0, -0.08), Vector3(sx * 0.22, 0.12, 0.12), Vector3(0, 0, 0.1),
				Vector3(sx * 0.5, 0.3, -0.05), Vector3(sx * 0.42, 0.2, 0.16), Vector3(sx * 0.22, 0.12, 0.12),
			])), Transform3D(), w)
			mb.add(MeshBuilder.cone(0.025, 0.07, 4), Transform3D(Basis(), Vector3(sx * 0.03, 0.08, -0.18)), w)   # ears
		else:     # a crow's long fingered wing and a fan tail
			mb.add(_tris(PackedVector3Array([
				Vector3(0, 0, -0.1), Vector3(sx * 0.55, 0.28, 0.0), Vector3(0, 0, 0.1),
				Vector3(sx * 0.55, 0.28, 0.0), Vector3(sx * 0.3, 0.15, 0.14), Vector3(0, 0, 0.1),
			])), Transform3D(), w)
	if not bat:
		mb.add(_tris(PackedVector3Array([Vector3(0, 0, 0.1), Vector3(-0.1, 0, 0.32), Vector3(0.1, 0, 0.32)])), Transform3D(), w)
		mb.add(MeshBuilder.cone(0.03, 0.1, 4), Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 0.02, -0.25)), w)   # beak
	return mb.commit()


## A hexagonal ice crystal, 1 m across, its body 1 m tall with a pointed tip above.
static func _crystal_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var w := Color(1, 1, 1, 1)
	mb.add(MeshBuilder.cyl(0.5, 0.5, 1.0, 6), Transform3D(Basis(), Vector3(0, 0.5, 0)), w)
	mb.add(MeshBuilder.cone(0.5, 0.45, 6), Transform3D(Basis(), Vector3(0, 1.225, 0)), w)
	return mb.commit()


# ------------------------------------------------------------------ ground decals

const DECAL_HEAD := """
shader_type spatial;
render_mode world_vertex_coords, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled%s;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float h_origin = 0.0;
uniform float h_size = 1.0;
uniform float has_height = 0.0;
uniform float lift = 0.07;
uniform float prog = 0.0;
uniform float fade = 1.0;
uniform float seed = 0.0;
uniform vec4 col_a : source_color = vec4(1.0);
uniform vec4 col_b : source_color = vec4(1.0);
varying vec2 uv2;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	uv2 = UV * 2.0 - 1.0;
	if (has_height > 0.5) {
		vec2 uv = (VERTEX.xz - h_origin + 0.5) / h_size;
		VERTEX.y = texture(height_tex, uv).r + lift;
	}
	wpos = VERTEX;
}
void fragment() {
	float d = length(uv2);
	float ang = atan(uv2.y, uv2.x);
"""

## Each decal's fragment body (after d = distance from the centre 0..1, ang = angle).
const DECALS := {
	"frost": """
	float n = noise(wpos.xz * 1.6 + seed) * 0.6 + noise(wpos.xz * 4.5) * 0.4;
	float star = max(pow(abs(cos(ang * 3.0)), 8.0), pow(abs(cos(ang * 6.0 + 0.5236)), 14.0) * 0.55);
	float reach = prog * (0.2 + 0.8 * star) + (n - 0.5) * 0.1;
	float m = 1.0 - smoothstep(reach - 0.06, reach, d);
	float core = 1.0 - smoothstep(0.0, 0.35 * max(prog, 0.01), d);
	float glint = step(0.93, hash(floor(wpos.xz * 9.0))) * 0.6;
	ALBEDO = mix(col_b.rgb, col_a.rgb, clamp(n * 0.7 + core * 0.6 + glint, 0.0, 1.0));
	ALPHA = m * fade * clamp(0.5 + 0.35 * n + core * 0.3, 0.0, 0.95);
""",
	"shadow": """
	float sw = noise(vec2(ang * 1.5 + d * 4.0 - TIME * 1.2, d * 3.0 + seed));
	float edge = prog * (0.82 + 0.18 * noise(wpos.xz * 1.4 + TIME * 0.6));
	float m = 1.0 - smoothstep(edge - 0.1, edge, d);
	float rim = smoothstep(edge - 0.24, edge - 0.04, d) * m;
	ALBEDO = mix(col_b.rgb, col_a.rgb, smoothstep(0.55, 0.9, sw) * 0.6 + rim * 0.9);
	ALPHA = m * fade * 0.95;
""",
	"runes": """
	float fa = fract(-ang / 6.28318 + 0.25);
	float drawn = step(fa, prog);
	float ring = max(max(1.0 - smoothstep(0.0, 0.02, abs(d - 0.95)), 1.0 - smoothstep(0.0, 0.013, abs(d - 0.78))), 1.0 - smoothstep(0.0, 0.013, abs(d - 0.4)));
	float cell = floor(fa * 28.0);
	float gx = fract(fa * 28.0);
	float gy = (d - 0.8) / 0.13;
	float h = hash(vec2(cell, 3.0));
	float h2 = hash(vec2(cell, 7.0));
	float glyph = (1.0 - smoothstep(0.04, 0.1, abs(gx - 0.5))) * step(0.12, gy) * step(gy, 0.88);
	glyph = max(glyph, (1.0 - smoothstep(0.05, 0.12, abs(gy - 0.25 - 0.5 * h))) * step(0.22, gx) * step(gx, 0.78));
	glyph = max(glyph, (1.0 - smoothstep(0.05, 0.12, abs(gx - 0.2 - 0.6 * gy))) * step(0.5, h2) * step(0.12, gy) * step(gy, 0.88));
	glyph *= step(0.0, gy) * step(gy, 1.0);
	float seg = 2.0943951;
	float t1 = d * cos(mod(ang, seg) - seg * 0.5);
	float t2 = d * cos(mod(ang + seg * 0.5, seg) - seg * 0.5);
	float hexa = max(1.0 - smoothstep(0.0, 0.014, abs(t1 - 0.37)), 1.0 - smoothstep(0.0, 0.014, abs(t2 - 0.37))) * step(d, 0.78);
	float lines = max(max(ring, glyph), hexa);
	ALBEDO = mix(col_a.rgb, col_b.rgb, glyph) * (1.6 + 0.5 * sin(TIME * 7.0));
	ALPHA = clamp(lines * drawn * fade, 0.0, 1.0);
""",
	"mud": """
	float n = noise(wpos.xz * 1.3) * 0.6 + noise(wpos.xz * 4.0) * 0.4;
	float edge = prog * (0.75 + 0.3 * noise(wpos.xz * 2.2 + 3.0));
	float m = 1.0 - smoothstep(edge - 0.05, edge, d);
	float spots = step(0.78, noise(wpos.xz * 3.5 + 11.0)) * step(d, prog * 1.05);
	ALBEDO = mix(col_b.rgb, col_a.rgb, n);
	ROUGHNESS = mix(0.45, 0.85, n);
	SPECULAR = 0.3;
	ALPHA = max(m, spots) * fade * 0.96;
""",
	"fog": """
	float n = noise(wpos.xz * 0.45 + vec2(TIME * 0.3, 0.0)) * 0.6 + noise(wpos.xz * 1.2 - vec2(0.0, TIME * 0.4)) * 0.4;
	float m = 1.0 - smoothstep(prog * 0.45, max(prog, 0.01), d);
	ALBEDO = col_a.rgb;
	ALPHA = m * (0.3 + 0.7 * n) * 0.75 * fade;
""",
	"chem": """
	float n = noise(wpos.xz * 2.0 + vec2(TIME * 0.5, TIME * 0.3)) * 0.6 + noise(wpos.xz * 5.0 - TIME * 0.7) * 0.4;
	float edge = prog * (0.85 + 0.15 * noise(wpos.xz * 1.7 + TIME));
	float m = 1.0 - smoothstep(edge - 0.06, edge, d);
	float rim = smoothstep(edge - 0.2, edge - 0.03, d);
	float cells = smoothstep(0.66, 0.72, noise(wpos.xz * 6.0 + TIME * 1.5));
	ALBEDO = mix(col_b.rgb, col_a.rgb, clamp(n * 0.8 + cells * 0.7 + rim * 0.5, 0.0, 1.0));
	ALPHA = m * fade * 0.93;
""",
	"ooze": """
	float n = noise(wpos.xz * 1.5 + TIME * 0.2);
	float edge = prog * (0.8 + 0.2 * noise(wpos.xz * 2.5 + vec2(TIME * 0.8)));
	float m = 1.0 - smoothstep(edge - 0.04, edge, d);
	vec3 c = mix(col_b.rgb, col_a.rgb, smoothstep(0.0, max(edge, 0.01), d) * 0.6 + n * 0.4);
	ALBEDO = c;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	EMISSION = c * 0.3;
	ALPHA = m * fade * 0.92;
""",
	"web": """
	float spokes = 1.0 - smoothstep(0.0, 0.007 / max(d, 0.06), abs(sin(ang * 6.0)));
	float rr = d * 7.0 + 0.18 * abs(sin(ang * 6.0));
	float dl = min(fract(rr), 1.0 - fract(rr));
	float rings = (1.0 - smoothstep(0.012, 0.035, dl)) * step(0.1, d);
	float m = step(d, prog) * (1.0 - smoothstep(0.88, 1.0, d));
	ALBEDO = col_a.rgb;
	ALPHA = max(spokes, rings) * m * fade * 0.9;
""",
	"crater": """
	float cr = prog * 0.5;
	float bowl = 1.0 - smoothstep(cr * 0.6, cr, d);
	float c = abs(fract(ang / 6.28318 * 9.0 + seed + noise(vec2(d * 4.0, ang * 2.0)) * 0.35) - 0.5);
	float crk = (1.0 - smoothstep(0.0, 0.03 + 0.03 * (1.0 - d), c)) * step(d, prog) * (1.0 - smoothstep(0.55, 1.0, d / max(prog, 0.01)));
	float rim = smoothstep(cr * 0.75, cr, d) * (1.0 - smoothstep(cr, cr * 1.5, d));
	vec3 col = mix(col_a.rgb, col_b.rgb, clamp(bowl * 0.85 + crk, 0.0, 1.0));
	col = mix(col, col_a.rgb * 1.5, rim * 0.6);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	ALPHA = clamp(bowl * 0.95 + crk * 0.95 + rim * 0.6, 0.0, 1.0) * fade;
""",
	"slashes": """
	float a = 0.0;
	for (int k = 0; k < 3; k++) {
		float th = seed + float(k) * 1.05;
		vec2 dir = vec2(cos(th), sin(th));
		float off = (float(k) - 1.0) * 0.16;
		float dist = abs(dot(uv2, vec2(-dir.y, dir.x)) - off);
		float along = abs(dot(uv2, dir));
		a = max(a, (1.0 - smoothstep(0.0, 0.03 * (1.0 - along), dist)) * step(along, 0.95));
	}
	ALBEDO = mix(col_b.rgb, col_a.rgb, a);
	ALPHA = a * fade * prog;
""",
	"glow": """
	float g = pow(1.0 - clamp(d, 0.0, 1.0), 2.0) * prog;
	ALBEDO = col_a.rgb;
	ALPHA = g * fade;
""",
	"fairy": """
	float n = noise(wpos.xz * 3.0 + TIME * 0.5);
	float ring = exp(-pow((d - 0.78) / 0.1, 2.0)) * prog;
	float inner = (1.0 - smoothstep(0.0, 0.78, d)) * 0.25 * prog;
	ALBEDO = mix(col_a.rgb, col_b.rgb, n);
	ALPHA = clamp((ring * (0.6 + 0.6 * n) + inner) * fade, 0.0, 1.0);
""",
}

static var _decal_shaders := {}


## A decal draped over the ground at `at` (see DECALS); drive it with prog / fade.
func _decal(kind: String, radius: float, a: Color, b: Color, at := Vector3.INF, mode := "unshaded") -> ShaderMaterial:
	var key := kind + mode
	if not _decal_shaders.has(key):
		var sh := Shader.new()
		var modes := ""
		if mode.contains("unshaded"):
			modes += ", unshaded"
		if mode.contains("add"):
			modes += ", blend_add"
		sh.code = DECAL_HEAD % modes + DECALS[kind] + "}\n"
		_decal_shaders[key] = sh
	var mat := ShaderMaterial.new()
	mat.shader = _decal_shaders[key]
	mat.render_priority = 1
	var ground := SwampWater.current
	if ground != null and ground.height_texture != null:
		mat.set_shader_parameter("height_tex", ground.height_texture)
		mat.set_shader_parameter("h_origin", ground.horigin)
		mat.set_shader_parameter("h_size", float(ground.hsize))
		mat.set_shader_parameter("has_height", 1.0)
	mat.set_shader_parameter("col_a", a)
	mat.set_shader_parameter("col_b", b)
	mat.set_shader_parameter("seed", randf() * 10.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16.0
	_add(mi, target if at == Vector3.INF else at)
	return mat


# ------------------------------------------------------------------ Ice Wizard
## Frost races out over the ground in a six-pointed star, ice spikes jut up along its rays,
## a crystal spire grows up around him (frozen inside, glowing), cracks, and shatters outward.

func _ice_wizard() -> void:
	if s.is_empty():
		s["frost"] = _decal("frost", 7.5, Color(0.92, 0.98, 1.0), Color(0.42, 0.7, 0.98))
		var imat := _lit(Color(0.72, 0.9, 1.0, 0.62), 0.05, 0.2)
		imat.emission_enabled = true
		imat.emission = Color(0.35, 0.65, 1.0)
		imat.emission_energy_multiplier = 0.35
		imat.rim_enabled = true
		imat.rim = 0.8
		s["imat"] = imat
		var cm := _crystal_mesh()
		var spikes: Array = []
		for k in 6:
			var a := float(k) * PI / 3.0
			var d := Vector3(cos(a), 0.0, sin(a))
			for j in 3:
				var r := 2.2 + j * 1.6 + randf_range(-0.3, 0.3)
				var p := _ground(target + d * r + Vector3(d.z, 0, -d.x) * randf_range(-0.3, 0.3))
				var mi := _mesh(cm, imat, p)
				mi.basis = Basis(Quaternion(Vector3.UP, (Vector3.UP + d * randf_range(0.3, 0.7)).normalized()))
				var w := randf_range(0.28, 0.45) * (1.0 - j * 0.2)
				spikes.append([mi, 0.12 + r / 7.5 * 0.65, Vector3(w, randf_range(0.6, 1.2) * (1.0 - j * 0.22), w), mi.basis])
		s["spikes"] = spikes
		var spire := Node3D.new()
		_add(spire, target)
		var clear := imat.duplicate() as StandardMaterial3D   # thin enough to see him frozen inside
		clear.albedo_color = Color(0.75, 0.92, 1.0, 0.3)
		clear.cull_mode = BaseMaterial3D.CULL_BACK
		s["clear"] = clear
		_mesh(cm, clear, Vector3.ZERO, spire).scale = Vector3(1.7, 2.5, 1.7)
		for k in 7:
			var a := TAU * k / 7.0 + 0.3
			var d := Vector3(cos(a), 0.0, sin(a))
			var mi := _mesh(cm, imat, d * 0.85, spire)
			mi.basis = Basis(Quaternion(Vector3.UP, (Vector3.UP + d * 0.5).normalized())) * Basis.from_scale(Vector3(0.6, randf_range(1.1, 1.9), 0.6))
		spire.scale = Vector3(0.6, 0.001, 0.6)
		s["spire"] = spire
		var smat := imat.duplicate() as StandardMaterial3D
		smat.vertex_color_use_as_albedo = true
		s["shards"] = _swarm(cm, 70, smat)
		var mist := _emitter(1.6, 1.6, 50, Color(0.9, 0.97, 1.0, 0.35), Color(0.7, 0.85, 1.0, 0.0), false, target + Vector3(0, 0.3, 0))
		mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		mist.emission_ring_axis = Vector3.UP
		mist.emission_ring_radius = 3.5
		mist.emission_ring_inner_radius = 0.5
		mist.emission_ring_height = 0.2
		mist.gravity = Vector3(0, 0.3, 0)
		mist.scale_amount_curve = _grow_curve()
		s["mist"] = mist
		s["light"] = _light(target + Vector3(0, 2.5, 0), Color(0.55, 0.85, 1.0), 0.0, 14.0)
	var frost: ShaderMaterial = s["frost"]
	frost.set_shader_parameter("prog", _eo(_k(0.0, 0.9)))
	frost.set_shader_parameter("fade", 1.0 - _k(3.6, 5.6))
	for sp in s["spikes"]:
		var mi: MeshInstance3D = sp[0]
		var g := _back(_k(sp[1], sp[1] + 0.28)) * (1.0 - _eio(_k(2.9, 3.8)))
		mi.basis = (sp[3] as Basis) * Basis.from_scale(sp[2] * maxf(g, 0.001))
	var imat: StandardMaterial3D = s["imat"]
	var spire: Node3D = s["spire"]
	(s["light"] as OmniLight3D).light_energy = 3.0 * _k(0.3, 1.2) * (1.0 - _k(2.6, 3.6)) + 4.0 * _k(1.5, hit_at) * (1.0 - _k(hit_at, hit_at + 0.4))
	(s["mist"] as CPUParticles3D).emitting = t < 2.8
	if t < hit_at:
		var g := _eo(_k(0.55, 1.35))
		spire.scale = Vector3(0.6 + 0.4 * g, maxf(g, 0.001), 0.6 + 0.4 * g)
		var j := _k(1.5, hit_at) * 0.06
		spire.position = target + Vector3(randf_range(-j, j), 0, randf_range(-j, j))
		imat.emission_energy_multiplier = 0.35 + 2.0 * _k(1.4, hit_at)
		(s["clear"] as StandardMaterial3D).emission_energy_multiplier = 0.2 + 1.5 * _k(1.4, hit_at)
		if _at(1.75) or _at(2.05):
			player.add_shake(0.12)
	elif spire.visible:
		spire.visible = false
		imat.emission_energy_multiplier = 0.5
	if not is_landed:
		hero.visible = t >= 0.6
		hero.set_flash(0.85 * (1.0 - _k(hit_at, hit_at + 0.8)))
	var sw: Swarm = s["shards"]
	if _at(hit_at):
		for i in sw.n:
			var a := randf() * TAU
			sw.p[i] = target + Vector3(cos(a) * randf_range(0.1, 0.8), randf_range(0.2, 3.6), sin(a) * randf_range(0.1, 0.8))
			sw.v[i] = Vector3(cos(a), 0, sin(a)) * randf_range(4.0, 12.0) + Vector3(0, randf_range(2.0, 9.0), 0)
			sw.q[i] = Vector3(randf_range(0.08, 0.2), randf_range(0.25, 0.6), randf_range(0.08, 0.2))
			sw.f[i] = randf() * TAU
			sw.g[i] = randf_range(5.0, 14.0)
		_burst(target + Vector3(0, 1.5, 0), 5.0, Color(0.85, 0.95, 1.0), 0.45)
		_burst(target + Vector3(0, 0.6, 0), RADIUS, Color(0.5, 0.8, 1.0), 0.6)
		_ring(target, RADIUS, Color(0.75, 0.92, 1.0, 0.8), 0.5)
		_pop(target + Vector3(0, 1.2, 0), 60, 1.6, 1.2, Color(0.95, 1.0, 1.0, 0.6), Color(0.7, 0.85, 1.0, 0.0), 7.0, -0.5, false)
		hero.play_ability(2)
	if t >= hit_at:
		var tau := t - hit_at
		var fade := 1.0 - clampf((tau - 1.4) / 1.2, 0.0, 1.0)
		for i in sw.n:
			var p := _fly(sw.p[i], sw.v[i], tau, 18.0, 1.4)
			var spin := sw.f[i] + sw.g[i] * minf(tau, 0.9)
			var b := Basis(Vector3(sin(sw.f[i]), 0.4, cos(sw.f[i])).normalized(), spin) * Basis.from_scale(sw.q[i])
			sw.put(i, b, p, Color(1, 1, 1, fade))


# ------------------------------------------------------------------ Dark Wizard
## A pool of living shadow spreads over the ground, tendrils curl up out of it, a murder of
## crows bursts out and scatters, and he rises slowly out of the dark; a pulse of shadow.

func _dark_wizard() -> void:
	var purple := RosterHero.color(kit, "main")
	if s.is_empty():
		s["pool"] = _decal("shadow", 4.2, Color(0.55, 0.18, 0.95), Color(0.015, 0.0, 0.03))
		var tmat := _vc()
		tmat.emission_enabled = true
		tmat.emission = Color(0.16, 0.02, 0.3)
		tmat.roughness = 0.25
		tmat.rim_enabled = true
		tmat.rim = 1.0
		tmat.rim_tint = 0.0
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 10
		sm.rings = 6
		var tw := _swarm(sm, 8 * TENDRIL_BEADS, tmat)
		for k in 8:
			var a := TAU * k / 8.0 + randf_range(-0.25, 0.25)
			tw.p[k] = Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 3.1)   # root offset
			tw.f[k] = randf_range(2.0, 3.4)    # height
			tw.g[k] = randf() * TAU           # phase
		s["tendrils"] = tw
		var cmat := _vc()
		cmat.albedo_color = Color(0.06, 0.05, 0.08)
		cmat.roughness = 0.6
		var crows := _swarm(_flyer_mesh(false), 38, cmat)
		for i in crows.n:
			var a := randf() * TAU
			crows.p[i] = target + Vector3(cos(a), 0, sin(a)) * randf_range(0.2, 2.2) + Vector3(0, 0.3, 0)
			crows.v[i] = Vector3(cos(a), 0, sin(a)) * randf_range(4.0, 9.0) + Vector3(0, randf_range(5.0, 10.0), 0)
			crows.f[i] = randf() * TAU
			crows.g[i] = randf_range(0.85, 1.25)   # size
			crows.q[i] = Vector3(randf_range(0.9, 1.25), 0, 0)   # launch delay offset
		s["crows"] = crows
		var smoke := _emitter(1.3, 1.6, 40, Color(0.08, 0.0, 0.12, 0.65), Color(0.25, 0.05, 0.4, 0.0), false, target + Vector3(0, 0.1, 0))
		smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		smoke.emission_ring_axis = Vector3.UP
		smoke.emission_ring_radius = 2.6
		smoke.emission_ring_inner_radius = 0.0
		smoke.emission_ring_height = 0.1
		smoke.gravity = Vector3(0, 1.2, 0)
		smoke.scale_amount_curve = _grow_curve()
		s["smoke"] = smoke
		s["light"] = _light(target + Vector3(0, 0.8, 0), purple, 0.0, 9.0)
	var pool: ShaderMaterial = s["pool"]
	pool.set_shader_parameter("prog", _eo(_k(0.0, 0.8)) * (1.0 - 0.6 * _eio(_k(2.6, 3.6))))
	pool.set_shader_parameter("fade", 1.0 - _k(3.4, 4.2))
	(s["smoke"] as CPUParticles3D).emitting = t > 0.3 and t < 2.7
	(s["light"] as OmniLight3D).light_energy = 2.5 * _k(0.2, 1.0) * (1.0 - _k(2.8, 3.8)) + 3.0 * (1.0 - _k(hit_at, hit_at + 0.4)) * _k(hit_at - 0.1, hit_at)
	# Tendrils: chains of shrinking beads curling up out of the pool and back down
	var tw: Swarm = s["tendrils"]
	var grow := _eo(_k(0.25, 1.3)) * (1.0 - _eio(_k(2.3, 3.4)))
	for k in 8:
		var root: Vector3 = target + tw.p[k]
		var inward := (-tw.p[k]).normalized()
		for j in TENDRIL_BEADS:
			var u := float(j) / float(TENDRIL_BEADS - 1)
			var idx := k * TENDRIL_BEADS + j
			if grow < 0.02:
				tw.hide(idx)
				continue
			var h := tw.f[k] * grow
			var curl := sin(u * PI * 0.9) * 0.9 * u
			var sway := sin(t * 3.0 + tw.g[k] + u * 4.0) * 0.35 * u
			var side := Vector3(-inward.z, 0, inward.x)
			var p := root + Vector3(0, u * h, 0) + inward * (curl * h * 0.45) + side * sway * grow
			p.y += _gy(root.x, root.z) - target.y
			var r := 0.3 * (1.0 - u * 0.88) * (0.4 + 0.6 * grow)
			tw.put(idx, Basis().scaled(Vector3.ONE * r * 2.0), p, Color(0.04, 0.0, 0.06, 1.0))
	# Crows burst out at ~1 s and scatter
	var crows: Swarm = s["crows"]
	for i in crows.n:
		var tau := t - crows.q[i].x
		if tau < 0.0 or tau > 4.0:
			crows.hide(i)
			continue
		var v := crows.v[i]
		var p := crows.p[i] + v * tau * 0.8 + Vector3(0, 1.2 * tau * tau, 0)
		var dir := (v + Vector3(0, 2.4 * tau, 0)).normalized()
		var flap := sin(t * 26.0 + crows.f[i])
		var b := Basis.looking_at(dir, Vector3.UP) * Basis.from_scale(Vector3(1.0, flap, 1.0) * crows.g[i])
		crows.put(i, b, p, Color(1, 1, 1, 1.0 - clampf((tau - 3.0), 0.0, 1.0)))
	if _at(0.9):
		_pop(target + Vector3(0, 0.6, 0), 24, 0.9, 0.9, Color(0.1, 0.0, 0.15, 0.8), Color(0.3, 0.1, 0.45, 0.0), 6.0, -1.0, false)
	# He rises up out of the shadow
	if not is_landed:
		hero.visible = t >= 1.2
		hero.position = Vector3(0, lerpf(-2.2, 0.0, _eo(_k(1.2, 2.5))), 0)
	if _at(hit_at):
		_ring(target, RADIUS, Color(0.6, 0.2, 1.0, 0.8), 0.55)
		_burst(target + Vector3(0, 1.0, 0), RADIUS * 0.8, purple, 0.5)
		_burst(target + Vector3(0, 1.4, 0), 3.0, Color(0.15, 0.0, 0.25), 0.35)
		hero.play_ability(1)


# ------------------------------------------------------------------ Merlin
## Time runs backwards ("mostly in reverse"): a cloud of dust and sparkles rushes inward and
## reassembles into him while a rune circle draws itself backwards round the ground; he settles
## with a twinkle and an owl flaps off.

func _merlin() -> void:
	var blue := RosterHero.color(kit, "main")
	if s.is_empty():
		s["runes"] = _decal("runes", 3.4, Color(0.55, 0.75, 1.0), Color(1.0, 0.82, 0.4), Vector3.INF, "unshaded add")
		var quad := QuadMesh.new()
		quad.size = Vector2(0.22, 0.22)
		var sp := _swarm(quad, 170, _vc(true, true, true, true))
		var palette: Array[Color] = [Color(0.6, 0.8, 1.0), Color(1.0, 1.0, 1.0), Color(1.0, 0.85, 0.4), Color(0.7, 0.6, 1.0)]
		for i in sp.n:
			var dir := Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0), randf_range(-1, 1)).normalized()
			sp.p[i] = target + dir * randf_range(4.0, 9.0) + Vector3(0, randf_range(0.5, 4.0), 0)
			sp.q[i] = target + Vector3(randf_range(-0.35, 0.35), randf_range(0.1, 2.0), randf_range(-0.3, 0.3))
			sp.f[i] = randf_range(0.0, 0.5)       # start delay
			sp.g[i] = randf_range(0.6, 1.4)       # size
			sp.c[i] = palette[i % palette.size()]
		s["sparks"] = sp
		var pquad := QuadMesh.new()
		pquad.size = Vector2(1.0, 1.0)
		var dust := _swarm(pquad, 46, _vc(false, false, true, true))
		for i in dust.n:
			var a := randf() * TAU
			dust.p[i] = target + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 6.0) + Vector3(0, randf_range(0.3, 2.2), 0)
			dust.f[i] = randf_range(0.0, 0.4)
			dust.g[i] = randf_range(0.9, 1.7)
		s["dust"] = dust
		s["light"] = _light(target + Vector3(0, 1.5, 0), blue, 0.0, 10.0)
		var star := Node3D.new()
		_add(star, target + Vector3(0, 2.35, 0))
		var smat := _glow(Color(1.0, 0.95, 0.75, 1.0))
		smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		smat.billboard_keep_scale = true
		smat.albedo_texture = _streak_tex()
		for k in 2:
			var q := QuadMesh.new()
			q.size = Vector2(2.4, 0.16) if k == 0 else Vector2(0.16, 2.4)
			_mesh(q, smat, Vector3.ZERO, star)
		star.scale = Vector3.ONE * 0.001
		s["star"] = star
		s["owl"] = _make_owl()
	var runes: ShaderMaterial = s["runes"]
	runes.set_shader_parameter("prog", _eio(_k(0.2, 2.1)))
	runes.set_shader_parameter("fade", (0.75 + 0.6 * (1.0 - _k(hit_at, hit_at + 0.5)) * _k(hit_at - 0.2, hit_at)) * (1.0 - _k(3.2, 4.4)))
	(s["light"] as OmniLight3D).light_energy = 3.5 * _ei(_k(0.0, 2.4)) * (1.0 - _k(2.8, 3.8))
	# Sparkles rush in from all around, accelerating (an explosion run backwards), spiralling
	var sp: Swarm = s["sparks"]
	for i in sp.n:
		var k := clampf((t - sp.f[i]) / (2.45 - sp.f[i]), 0.0, 1.0)
		if k >= 1.0:
			sp.hide(i)
			continue
		var e := pow(k, 2.3)
		var off := (sp.p[i] - sp.q[i]) * (1.0 - e)
		off = off.rotated(Vector3.UP, (1.0 - e) * 2.4)
		var tw := 0.6 + 0.4 * sin(t * 18.0 + float(i))
		sp.put(i, Basis().scaled(Vector3.ONE * sp.g[i] * (0.6 + 0.6 * e)), sp.q[i] + off, Color(sp.c[i], tw))
	var dust: Swarm = s["dust"]
	for i in dust.n:
		var k := clampf((t - dust.f[i]) / 1.9, 0.0, 1.0)
		var e := pow(k, 1.8)
		var p := dust.p[i].lerp(target + Vector3(0, 1.0, 0), e)
		var a := 0.45 * (1.0 - pow(k, 3.0)) * _k(0.0, 0.25)
		dust.put(i, Basis().scaled(Vector3.ONE * dust.g[i] * (1.0 - 0.7 * e)), p, Color(0.62, 0.56, 0.5, a))
	# He gathers out of the light, then settles
	if not is_landed:
		hero.visible = t >= 1.6
		hero.position = Vector3(0, 0.35 * (1.0 - _eo(_k(1.6, 2.6))), 0)
		hero.set_flash(1.0 - _k(1.8, 2.8))
	var star: Node3D = s["star"]
	var ts := _k(hit_at - 0.05, hit_at + 0.45)
	star.scale = Vector3.ONE * maxf(sin(ts * PI) * 1.2, 0.001)
	star.rotation = Vector3(0, 0, t * 3.0)
	if _at(hit_at):
		_ring(target, RADIUS * 0.8, Color(0.6, 0.8, 1.0, 0.7), 0.5)
		_burst(target + Vector3(0, 1.2, 0), 2.6, Color(0.85, 0.92, 1.0), 0.35)
		_pop(target + Vector3(0, 2.3, 0), 30, 0.25, 0.8, Color(1.0, 0.95, 0.7, 1.0), Color(0.5, 0.7, 1.0, 0.0), 3.0, 1.0)
		hero.play_ability(1)
	_tick_owl()


## Merlin's owl: a round body, a pale face disc, big eyes, ear tufts and two wings.
func _make_owl() -> Node3D:
	var owl := Node3D.new()
	_add(owl, target + _right * 0.5 + Vector3(0, 1.7, 0))
	var brown := _lit(Color(0.45, 0.32, 0.2), 0.9)
	var pale := _lit(Color(0.85, 0.75, 0.6), 0.9)
	var body := SphereMesh.new()
	body.radius = 0.16
	body.height = 0.4
	_mesh(body, brown, Vector3.ZERO, owl)
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.24
	_mesh(head, brown, Vector3(0, 0.24, 0), owl)
	var face := CylinderMesh.new()
	face.top_radius = 0.1
	face.bottom_radius = 0.1
	face.height = 0.02
	var fm := _mesh(face, pale, Vector3(0, 0.24, -0.1), owl)
	fm.rotation.x = PI / 2
	var eye := SphereMesh.new()
	eye.radius = 0.035
	eye.height = 0.07
	var emat := _glow(Color(1.0, 0.8, 0.2), false)
	for sx in [-1.0, 1.0]:
		_mesh(eye, emat, Vector3(sx * 0.045, 0.26, -0.115), owl)
		var tuft := CylinderMesh.new()
		tuft.top_radius = 0.0
		tuft.bottom_radius = 0.03
		tuft.height = 0.09
		_mesh(tuft, brown, Vector3(sx * 0.07, 0.37, 0), owl).rotation.z = -sx * 0.4
		var pivot := Node3D.new()
		pivot.name = "L" if sx < 0.0 else "R"
		_add(pivot, Vector3(sx * 0.12, 0.08, 0), owl)
		var wing := BoxMesh.new()
		wing.size = Vector3(0.42, 0.02, 0.22)
		_mesh(wing, brown, Vector3(sx * 0.21, 0, 0.02), pivot)
	owl.scale = Vector3.ONE * 0.001
	return owl


func _tick_owl() -> void:
	var owl: Node3D = s["owl"]
	if t < hit_at - 0.1:
		return
	var tau := t - (hit_at - 0.1)
	var pop := _back(clampf(tau / 0.25, 0.0, 1.0))
	var fly := clampf((tau - 0.35) / 2.6, 0.0, 1.0)
	var sc := maxf(pop * (1.0 - clampf((tau - 2.6) / 0.4, 0.0, 1.0)), 0.001)
	var start := target + _right * 0.5 + Vector3(0, 1.75, 0)
	var dest := target + _right * 9.0 + _fwd * 10.0 + Vector3(0, 9.0, 0)
	var e := fly * fly
	owl.position = start.lerp(dest, e) + Vector3(0, sin(fly * PI) * 1.2, 0)
	var head := (dest - start).normalized()
	var look := head.lerp(_to_cam, 1.0 - minf(fly * 4.0, 1.0)).normalized()
	owl.basis = Basis.looking_at(look, Vector3.UP) * Basis.from_scale(Vector3.ONE * sc)
	var flap := sin(tau * 22.0) * (0.9 if fly > 0.0 else 0.15)
	(owl.get_node("L") as Node3D).rotation.z = flap
	(owl.get_node("R") as Node3D).rotation.z = -flap


# ------------------------------------------------------------------ Ogre
## The ground bulges and trembles, then bursts: he erupts out of a geyser of bog mud that
## splatters everywhere, lands with a thud and shakes himself off like a wet dog.

func _ogre() -> void:
	var mud_c := Color(0.4, 0.29, 0.15)
	if s.is_empty():
		var mound := SphereMesh.new()
		mound.radius = 1.0
		mound.height = 2.0
		mound.radial_segments = 20
		mound.rings = 10
		var mm := _mesh(mound, _lit(Color(0.36, 0.27, 0.16), 0.95), target)
		mm.scale = Vector3(2.4, 0.001, 2.4)
		s["mound"] = mm
		s["mud"] = _decal("mud", 4.8, Color(0.34, 0.25, 0.13), Color(0.12, 0.08, 0.04), Vector3.INF, "")
		s["cracks"] = _decal("crater", 4.0, Color(0.36, 0.27, 0.16), Color(0.05, 0.04, 0.03), Vector3.INF, "")
		var gey := _emitter(1.5, 1.1, 160, Color(0.55, 0.41, 0.23, 1.0), Color(0.36, 0.26, 0.13, 0.85), false, target + Vector3(0, 0.3, 0))
		gey.emission_sphere_radius = 0.6
		gey.direction = Vector3.UP
		gey.spread = 13.0
		gey.initial_velocity_min = 9.0
		gey.initial_velocity_max = 15.0
		gey.gravity = Vector3(0, -20, 0)
		gey.scale_amount_curve = null
		gey.emitting = false
		s["geyser"] = gey
		var bmat := _vc()
		bmat.roughness = 0.55
		bmat.metallic_specular = 0.35
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 8
		sm.rings = 5
		s["blobs"] = _swarm(sm, 70, bmat)
		var dirt := _emitter(0.35, 0.8, 30, Color(0.35, 0.25, 0.14, 1.0), Color(0.3, 0.22, 0.12, 0.0), false, target + Vector3(0, 0.6, 0))
		dirt.emission_sphere_radius = 1.2
		dirt.spread = 60.0
		dirt.initial_velocity_min = 2.0
		dirt.initial_velocity_max = 4.0
		dirt.gravity = Vector3(0, -12, 0)
		dirt.scale_amount_curve = null
		s["dirt"] = dirt
	var mound: MeshInstance3D = s["mound"]
	var cracks: ShaderMaterial = s["cracks"]
	cracks.set_shader_parameter("prog", _eo(_k(0.2, 1.5)) * 0.9)
	cracks.set_shader_parameter("fade", 1.0 - _k(3.8, 5.0))
	(s["dirt"] as CPUParticles3D).emitting = t > 0.3 and t < 1.55
	if t < hit_at:
		var g := _eio(_k(0.0, 1.4))
		var j := 0.06 * g
		mound.scale = Vector3(2.4 + randf_range(-j, j), maxf(1.4 * g, 0.001), 2.4 + randf_range(-j, j))
		mound.position = target + Vector3(randf_range(-j, j), -0.35, randf_range(-j, j))
		if t > 0.2:
			player.add_shake(0.1 + 0.22 * _k(0.2, hit_at))
	else:
		mound.visible = false
	var mud: ShaderMaterial = s["mud"]
	mud.set_shader_parameter("prog", _eo(_k(hit_at, hit_at + 0.45)))
	mud.set_shader_parameter("fade", 1.0 - _k(4.0, 6.0))
	# The geyser: a fountain of mud for half a second
	var tg := t - hit_at
	(s["geyser"] as CPUParticles3D).emitting = tg >= 0.0 and tg < 0.45
	var sw: Swarm = s["blobs"]
	if _at(hit_at):
		for i in sw.n:
			var a := randf() * TAU
			sw.p[i] = target + Vector3(cos(a) * 0.5, randf_range(0.5, 4.5), sin(a) * 0.5)
			sw.v[i] = Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 10.0) + Vector3(0, randf_range(4.0, 12.0), 0)
			sw.f[i] = randf_range(0.18, 0.42)
			sw.c[i] = mud_c.lerp(Color(0.24, 0.16, 0.07), randf())
		_burst(target + Vector3(0, 1.5, 0), 4.5, Color(0.5, 0.36, 0.2), 0.5)
		_burst(target + Vector3(0, 0.5, 0), RADIUS, Color(0.4, 0.3, 0.16), 0.55)
		_pop(target + Vector3(0, 1.0, 0), 40, 1.4, 1.1, Color(0.4, 0.3, 0.18, 0.8), Color(0.35, 0.27, 0.16, 0.0), 8.0, 6.0, false)
	if tg >= 0.0:
		var fade := 1.0 - clampf((tg - 2.6) / 1.2, 0.0, 1.0)
		for i in sw.n:
			var p := _fly(sw.p[i], sw.v[i], tg, 20.0, 0.8, 0.03)
			var down := p.y <= _gy(p.x, p.z) + 0.04
			var r := sw.f[i]
			var sc := Vector3(r * 1.8, r * 0.3, r * 1.8) if down else Vector3(r, r * 1.3, r)
			sw.put(i, Basis().scaled(sc), p, Color(sw.c[i], fade))
	# He erupts with it, lands with a thud and shakes himself off
	if not is_landed:
		hero.visible = t >= hit_at
		var land := hit_at + 0.94
		if t < land:
			var tau := maxf(t - hit_at, 0.0)
			hero.position = Vector3(0, -1.6 + 13.0 * tau - 12.0 * tau * tau, 0)
			hero.rotation = Vector3(0, _yaw + tau * 3.0, 0)
		else:
			var tl := t - land
			hero.position = Vector3.ZERO
			var sq := 1.0 - clampf(tl / 0.3, 0.0, 1.0)
			hero.scale = Vector3(1.0 + 0.15 * sq, 1.0 - 0.15 * sq, 1.0 + 0.15 * sq)
			var shk := clampf((tl - 0.15) / 0.6, 0.0, 1.0)
			var w := sin(shk * 40.0) * 0.4 * (1.0 - shk) * float(shk > 0.0)
			hero.rotation = Vector3(0, _yaw + w, w * 0.4)
		if _at(land):
			player.add_shake(0.4)
			_pop(target + Vector3(0, 0.3, 0), 20, 1.2, 0.8, Color(0.45, 0.35, 0.22, 0.7), Color(0.4, 0.32, 0.2, 0.0), 3.0, 1.0, false)
			hero.play_ability(1)
		if _at(land + 0.2):
			var drops := _pop(target + Vector3(0, 1.3, 0), 36, 0.25, 0.9, Color(0.3, 0.22, 0.12, 1.0), Color(0.25, 0.18, 0.1, 0.0), 7.0, 14.0, false)
			drops.direction = Vector3.UP
			drops.spread = 80.0


# ------------------------------------------------------------------ Ghast
## Thick fog rolls in from every side, a wail rises, and it fades in out of the mist, see-
## through and glowing, chains rattling; the wail blasts the fog back out.

func _ghast() -> void:
	var pale := RosterHero.color(kit, "main")
	if s.is_empty():
		var fog := _emitter(5.5, 2.6, 230, Color(0.78, 0.86, 0.9, 0.0), Color(0.7, 0.8, 0.86, 0.0), false, target + Vector3(0, 0.6, 0))
		var grad := Gradient.new()
		grad.set_color(0, Color(0.86, 0.92, 0.96, 0.0))
		grad.add_point(0.3, Color(0.86, 0.92, 0.96, 0.6))
		grad.set_color(grad.get_point_count() - 1, Color(0.72, 0.82, 0.88, 0.0))
		fog.color_ramp = grad
		fog.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		fog.emission_ring_axis = Vector3.UP
		fog.emission_ring_radius = 14.0
		fog.emission_ring_inner_radius = 9.0
		fog.emission_ring_height = 0.6
		fog.spread = 180.0
		fog.initial_velocity_min = 0.0
		fog.initial_velocity_max = 0.5
		fog.gravity = Vector3.ZERO
		fog.radial_accel_min = -5.0
		fog.radial_accel_max = -3.0
		fog.scale_amount_curve = _grow_curve(0.6, 1.0)
		s["fog"] = fog
		s["mist"] = _decal("fog", 7.0, Color(0.82, 0.9, 0.95), Color(0.6, 0.7, 0.8))
		s["light"] = _light(target + Vector3(0, 2.0, 0), Color(0.6, 0.9, 1.0), 0.0, 12.0)
		# Its glow-in: the model's materials turn see-through while it fades in
		var mats: Array[StandardMaterial3D] = hero._mats
		var modes: Array[int] = []
		for m in mats:
			modes.append(m.transparency)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s["mats"] = mats
		_restore.append(func() -> void:
			for k in mats.size():
				mats[k].transparency = modes[k] as BaseMaterial3D.Transparency
				mats[k].albedo_color = hero._base_albedo[k])
		# Chains hanging off it, rattling
		var chains := Node3D.new()
		hero.add_child(chains)
		var torus := TorusMesh.new()
		torus.inner_radius = 0.05
		torus.outer_radius = 0.1
		torus.rings = 8
		torus.ring_segments = 6
		var iron := _lit(Color(0.48, 0.5, 0.53, 0.0), 0.35, 0.8)
		s["iron"] = iron
		var arms: Array[Node3D] = []
		for sx in [-1.0, 1.0]:
			var arm := Node3D.new()
			chains.add_child(arm)
			arm.position = Vector3(sx * 0.42, 1.35, -0.05)
			for k in 11:
				var link := MeshInstance3D.new()
				link.mesh = torus
				link.material_override = iron
				arm.add_child(link)
				link.position = Vector3(0, -0.15 * k, 0)
				link.rotation = Vector3(PI / 2, PI / 2 * float(k % 2), 0)
			arms.append(arm)
		s["arms"] = arms
		_restore.append(chains.queue_free)
	var fog: CPUParticles3D = s["fog"]
	fog.emitting = t < 1.9
	if _at(hit_at):   # the wail blows the fog back out
		fog.radial_accel_min = 10.0
		fog.radial_accel_max = 16.0
	var mist: ShaderMaterial = s["mist"]
	mist.set_shader_parameter("prog", _eo(_k(0.4, 2.0)))
	mist.set_shader_parameter("fade", 1.0 - _k(hit_at, hit_at + 1.5))
	(s["light"] as OmniLight3D).light_energy = (1.5 + 0.8 * sin(t * 13.0) * sin(t * 5.0)) * _k(0.8, 2.0) * (1.0 - _k(3.0, 4.0))
	var k := _eio(_k(1.1, 2.4))
	if not is_landed:
		hero.visible = t >= 1.1
		hero.position = Vector3(0, 0.7 * (1.0 - _eo(_k(1.1, 2.6))), 0)
		hero.set_flash(0.9 * k * (1.0 - _k(2.5, 3.3)))
		var mats: Array[StandardMaterial3D] = s["mats"]
		for j in mats.size():
			mats[j].albedo_color = Color(hero._base_albedo[j], hero._base_albedo[j].a * k * (0.85 + 0.15 * sin(t * 9.0)))
		(s["iron"] as StandardMaterial3D).albedo_color.a = k
		var whip := sin(_k(hit_at - 0.05, hit_at + 0.5) * PI) * 1.1
		var arms: Array[Node3D] = s["arms"]
		for j in arms.size():
			var side := -1.0 if j == 0 else 1.0
			arms[j].rotation = Vector3(0.25 * sin(t * 7.0 + j), 0, side * (0.2 * sin(t * 5.5 + j * 2.0) + whip))
	if _at(hit_at):
		_ring(target, RADIUS, Color(0.75, 0.95, 1.0, 0.7), 0.6)
		_burst(target + Vector3(0, 1.2, 0), RADIUS * 0.8, pale, 0.5)
		_pop(target + Vector3(0, 1.0, 0), 40, 3.0, 1.4, Color(0.85, 0.92, 0.95, 0.5), Color(0.8, 0.9, 0.95, 0.0), 11.0, 0.0, false)
		hero.play_ability(2)


# ------------------------------------------------------------------ Vampire Hunter
## A swarm of bats spirals down into a whirlwind over the spot; he bursts out of it, crossbow
## up, the bats scatter, and he puts a bolt into the ground with a thunk.

func _vampire_hunter() -> void:
	if s.is_empty():
		var bmat := _vc()
		bmat.albedo_color = Color(0.12, 0.06, 0.08)
		bmat.roughness = 0.6
		bmat.emission_enabled = true
		bmat.emission = Color(0.22, 0.02, 0.05)   # a red sheen so they read against a night sky
		bmat.rim_enabled = true
		bmat.rim = 1.0
		bmat.rim_tint = 0.6
		var bats := _swarm(_flyer_mesh(true), 96, bmat)
		for i in bats.n:
			var a := randf() * TAU
			bats.p[i] = target + Vector3(cos(a), 0, sin(a)) * randf_range(14.0, 24.0) + Vector3(0, randf_range(8.0, 16.0), 0)
			bats.f[i] = randf() * TAU                 # orbit phase
			bats.g[i] = randf_range(0.2, 3.4)         # orbit height
			bats.q[i] = Vector3(randf_range(0.0, 0.5), randf_range(0.75, 1.15), randf() * TAU)   # delay, size, flap phase
		s["bats"] = bats
		var dust := _emitter(1.0, 1.0, 70, Color(0.9, 0.15, 0.2, 0.5), Color(0.35, 0.02, 0.06, 0.0), true, target + Vector3(0, 0.2, 0))
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		dust.emission_ring_axis = Vector3.UP
		dust.emission_ring_radius = 2.5
		dust.emission_ring_inner_radius = 1.0
		dust.emission_ring_height = 0.1
		dust.gravity = Vector3(0, 2.5, 0)
		dust.tangential_accel_min = 8.0
		dust.tangential_accel_max = 12.0
		dust.scale_amount_curve = _grow_curve()
		s["dust"] = dust
		s["light"] = _light(target + Vector3(0, 1.6, 0), Color(0.9, 0.15, 0.2), 0.0, 9.0)
		var bolt := Node3D.new()
		_add(bolt, target)
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.018
		shaft.bottom_radius = 0.018
		shaft.height = 0.7
		_mesh(shaft, _lit(Color(0.4, 0.27, 0.15), 0.8), Vector3(0, 0, 0), bolt).rotation.x = PI / 2
		var tip := CylinderMesh.new()
		tip.top_radius = 0.0
		tip.bottom_radius = 0.035
		tip.height = 0.12
		_mesh(tip, _lit(Color(0.85, 0.87, 0.9), 0.25, 0.9), Vector3(0, 0, -0.41), bolt).rotation.x = -PI / 2
		for k in 2:
			var vane := BoxMesh.new()
			vane.size = Vector3(0.12, 0.005, 0.16) if k == 0 else Vector3(0.005, 0.12, 0.16)
			_mesh(vane, _lit(Color(0.6, 0.1, 0.12), 0.8), Vector3(0, 0, 0.27), bolt)
		bolt.visible = false
		s["bolt"] = bolt
	var bats: Swarm = s["bats"]
	var spin := _k(0.2, 1.9)
	var radius := lerpf(6.0, 1.15, _eio(spin))
	var burst := hit_at
	for i in bats.n:
		var dl := bats.q[i].x
		var flap := sin(t * 30.0 + bats.q[i].z)
		var sz := bats.q[i].y
		var ang := bats.f[i] + t * (3.0 + 5.0 * spin) + 0.6 * sin(t + bats.f[i])
		var orbit := target + Vector3(cos(ang) * radius, bats.g[i] + 0.3 * sin(t * 4.0 + bats.f[i]), sin(ang) * radius)
		var p: Vector3
		var dir: Vector3
		if t < burst:
			var e := _eo(clampf((t - dl) / 0.9, 0.0, 1.0))
			p = bats.p[i].lerp(orbit, e)
			dir = Vector3(-sin(ang), 0.05, cos(ang))
		else:
			if _at(burst):
				bats.v[i] = orbit   # where it broke away
			var out := (Vector3(bats.v[i].x, target.y, bats.v[i].z) - target).normalized()
			var tau := t - burst
			var vel := out * (8.0 + 3.0 * sin(bats.f[i] * 3.0)) + Vector3(0, 4.0 + 2.0 * sin(bats.f[i]), 0) + Vector3(-out.z, 0, out.x) * 2.0
			p = bats.v[i] + vel * tau + Vector3(0, 1.5 * tau * tau, 0)
			dir = vel.normalized()
			if tau > 3.5:
				bats.hide(i)
				continue
		var b := Basis.looking_at(dir, Vector3.UP) * Basis.from_scale(Vector3(1.0, flap, 1.0) * sz)
		bats.put(i, b, p, Color(1, 1, 1, 1))
	(s["dust"] as CPUParticles3D).emitting = t > 0.5 and t < burst
	(s["light"] as OmniLight3D).light_energy = 4.0 * _k(0.5, 1.5) * (1.0 - _k(burst, burst + 1.2))
	if not is_landed:
		hero.visible = t >= 1.3
	if _at(burst):
		_burst(target + Vector3(0, 1.2, 0), 4.0, Color(0.7, 0.1, 0.15), 0.4)
		_burst(target + Vector3(0, 0.5, 0), RADIUS, Color(0.55, 0.08, 0.12), 0.5)
		_ring(target, RADIUS, Color(0.85, 0.15, 0.2, 0.6), 0.5)
		hero.play_ability(1)
	# ...and a bolt into the ground in front of him
	var bolt: Node3D = s["bolt"]
	var fire := burst + 0.38
	var from := target + Vector3(0, 1.4, 0) + _to_cam * 0.4 + _right * 0.2
	var to := _ground(target + _to_cam * 2.4 + _right * 0.9) + Vector3(0, 0.12, 0)
	if t >= fire:
		bolt.visible = t < dur + LINGER - 0.5
		var u := clampf((t - fire) / 0.09, 0.0, 1.0)
		bolt.position = from.lerp(to, u)
		bolt.basis = Basis.looking_at((to - from).normalized(), Vector3.UP)
	if _at(fire + 0.09):
		player.add_shake(0.2)
		_pop(to, 18, 0.5, 0.6, Color(0.5, 0.42, 0.33, 0.8), Color(0.45, 0.4, 0.33, 0.0), 2.5, 4.0, false)


# ------------------------------------------------------------------ Vicki
## A shaft of golden light parts the sky; she glides down it on great wings of light, plants
## her spear and a golden ring of force rolls out.

func _vicki() -> void:
	var gold := RosterHero.color(kit, "main")
	if s.is_empty():
		var beam := CylinderMesh.new()
		beam.top_radius = 2.6
		beam.bottom_radius = 1.5
		beam.height = 70.0
		beam.radial_segments = 24
		beam.cap_top = false
		beam.cap_bottom = false
		var sh := Shader.new()
		sh.code = BEAM_SHADER
		var bm := ShaderMaterial.new()
		bm.shader = sh
		bm.set_shader_parameter("col", Color(1.0, 0.85, 0.45))
		bm.set_shader_parameter("fade", 0.0)
		var mi := _mesh(beam, bm, target + Vector3(0, 35.0, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s["beam"] = bm
		s["glow"] = _decal("glow", 4.0, Color(1.0, 0.85, 0.45), Color(1, 1, 1), Vector3.INF, "unshaded add")
		s["light"] = _light(target + Vector3(0, 3.0, 0), Color(1.0, 0.86, 0.5), 0.0, 16.0)
		# Wings of light: two fans of long feathers on her back
		var wings := Node3D.new()
		hero.add_child(wings)
		wings.position = Vector3(0, 1.4, 0.15)
		var fmat := _glow(Color(1.0, 0.82, 0.4, 0.5))
		fmat.albedo_texture = _streak_tex()
		for sx in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.name = "L" if sx < 0.0 else "R"
			wings.add_child(pivot)
			var bone := Vector3(sx * cos(0.55), sin(0.55), 0.0)
			for k in 9:
				var u := float(k) / 8.0
				var len := 0.7 + 1.3 * u
				var fq := QuadMesh.new()
				fq.size = Vector2(len, 0.34)
				var feather := MeshInstance3D.new()
				feather.mesh = fq
				feather.material_override = fmat
				feather.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var arm := Node3D.new()
				pivot.add_child(arm)
				arm.position = bone * (0.15 + 1.5 * u) + Vector3(0, 0, 0.01 * k)
				var a := -1.5 + 0.95 * u   # inner feathers hang down, the tips sweep out
				arm.rotation.z = a if sx > 0.0 else PI - a
				arm.add_child(feather)
				feather.position = Vector3(len * 0.5, 0, 0)
		s["wings"] = wings
		s["fmat"] = fmat
		_restore.append(wings.queue_free)
		var feathers := _emitter(0.18, 1.6, 40, Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.8, 0.4, 0.0), true, target)
		feathers.emission_sphere_radius = 1.4
		feathers.gravity = Vector3(0, -1.2, 0)
		feathers.initial_velocity_min = 0.1
		feathers.initial_velocity_max = 0.6
		s["feathers"] = feathers
	var bm: ShaderMaterial = s["beam"]
	bm.set_shader_parameter("fade", _eio(_k(0.0, 0.5)) * (1.0 - _k(2.7, 3.7)))
	var glow: ShaderMaterial = s["glow"]
	glow.set_shader_parameter("prog", 0.8 * _k(0.2, 1.0) + 0.6 * sin(_k(hit_at, hit_at + 0.6) * PI))
	glow.set_shader_parameter("fade", 1.0 - _k(3.0, 4.0))
	(s["light"] as OmniLight3D).light_energy = 2.5 * _k(0.0, 0.6) * (1.0 - _k(2.9, 3.8)) + 5.0 * sin(_k(hit_at, hit_at + 0.5) * PI)
	var land := hit_at
	var h := 17.0 * (1.0 - _eio(_k(0.35, land)))
	var feathers: CPUParticles3D = s["feathers"]
	if not is_landed:
		hero.visible = t >= 0.35
		player.global_position = target + Vector3(0, h, 0)   # the camera glides down with her
		hero.rotation = Vector3(0.12 * sin(t * 1.7) * (1.0 - _k(2.0, land)), _yaw, 0.08 * sin(t * 2.3) * (1.0 - _k(2.0, land)))
		var wings: Node3D = s["wings"]
		var open := _eo(_k(0.35, 0.9)) * (1.0 - _eio(_k(land + 0.1, dur)))
		wings.scale = Vector3.ONE * maxf(open, 0.001)
		var flap := sin(t * 4.5) * 0.35 * (1.0 - _k(land - 0.4, land))
		(wings.get_node("L") as Node3D).rotation = Vector3(0, 0.35, -flap)
		(wings.get_node("R") as Node3D).rotation = Vector3(0, -0.35, flap)
		feathers.position = target + Vector3(0, h + 1.6, 0)
	feathers.emitting = t > 0.4 and t < land
	if _at(land - 0.2):
		hero.play_ability(1)
	if _at(land):
		_ring(target, RADIUS, Color(1.0, 0.85, 0.4, 0.9), 0.45)
		_ring(target, RADIUS * 0.6, Color(1.0, 0.95, 0.75, 0.9), 0.3)
		_burst(target + Vector3(0, 0.8, 0), RADIUS, gold, 0.5)
		_burst(target + Vector3(0, 1.5, 0), 3.0, Color(1.0, 0.97, 0.85), 0.3)
		_pop(target + Vector3(0, 0.3, 0), 50, 0.3, 1.0, Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.8, 0.4, 0.0), 7.0, 2.0)


const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform float fade = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float face = abs(dot(NORMAL, VIEW));
	float streak = noise(vec2(UV.x * 30.0, UV.y * 5.0 - TIME * 2.5)) * 0.6 + noise(vec2(UV.x * 70.0, UV.y * 12.0 - TIME * 4.0)) * 0.4;
	float ends = smoothstep(0.0, 0.5, UV.y) * smoothstep(1.0, 0.97, UV.y);
	ALBEDO = col.rgb * (1.2 + streak);
	ALPHA = clamp(fade * (0.12 + 0.35 * streak) * (0.25 + 0.75 * face) * ends, 0.0, 1.0);
}
"""


# ------------------------------------------------------------------ Rogue
## A smoke bomb lobbed in from the side bounces to a stop, fizzes and goes off in a thick grey
## cloud; as it thins he's crouched there, then stands, tossing a dagger and catching it.

func _rogue() -> void:
	if s.is_empty():
		var bomb := Node3D.new()
		_add(bomb, target)
		var ball := SphereMesh.new()
		ball.radius = 0.22
		ball.height = 0.44
		_mesh(ball, _lit(Color(0.07, 0.07, 0.08), 0.25, 0.6), Vector3.ZERO, bomb)
		var cap := CylinderMesh.new()
		cap.top_radius = 0.06
		cap.bottom_radius = 0.07
		cap.height = 0.08
		_mesh(cap, _lit(Color(0.4, 0.38, 0.3), 0.4, 0.8), Vector3(0, 0.23, 0), bomb)
		var fuse := CylinderMesh.new()
		fuse.top_radius = 0.012
		fuse.bottom_radius = 0.012
		fuse.height = 0.14
		_mesh(fuse, _lit(Color(0.75, 0.65, 0.45), 0.9), Vector3(0.02, 0.32, 0), bomb).rotation.z = -0.4
		s["bomb"] = bomb
		var spark := _emitter(0.12, 0.35, 30, Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.4, 0.1, 0.0), true, target)
		spark.emission_sphere_radius = 0.02
		spark.spread = 70.0
		spark.initial_velocity_min = 1.0
		spark.initial_velocity_max = 2.5
		spark.gravity = Vector3(0, -4, 0)
		s["spark"] = spark
		var dagger := Node3D.new()
		hero.add_child(dagger)
		var blade := PrismMesh.new()
		blade.size = Vector3(0.07, 0.3, 0.015)
		_mesh(blade, _lit(Color(0.88, 0.9, 0.95), 0.15, 0.95), Vector3(0, 0.2, 0), dagger)
		var guard := BoxMesh.new()
		guard.size = Vector3(0.14, 0.025, 0.03)
		_mesh(guard, _lit(Color(0.55, 0.45, 0.2), 0.4, 0.8), Vector3(0, 0.045, 0), dagger)
		var grip := CylinderMesh.new()
		grip.top_radius = 0.018
		grip.bottom_radius = 0.018
		grip.height = 0.1
		_mesh(grip, _lit(Color(0.2, 0.12, 0.08), 0.9), Vector3(0, -0.02, 0), dagger)
		dagger.visible = false
		s["dagger"] = dagger
		_restore.append(dagger.queue_free)
	var bomb: Node3D = s["bomb"]
	var spark: CPUParticles3D = s["spark"]
	var start := target + _right * 9.0 - _fwd * 1.5 + Vector3(0, 3.5, 0)
	var rest := _ground(target - _right * 0.5) + Vector3(0, 0.22, 0)
	var hit := _ground(target + _right * 0.4) + Vector3(0, 0.22, 0)
	if t < hit_at:
		var p: Vector3
		if t < 0.6:
			var u := t / 0.6
			p = start.lerp(hit, u) + Vector3(0, 2.6 * sin(u * PI), 0)
		else:
			var u := clampf((t - 0.6) / 0.3, 0.0, 1.0)
			p = hit.lerp(rest, _eo(u)) + Vector3(0, 0.5 * sin(u * PI), 0)
		bomb.position = p
		bomb.rotation = Vector3(0, 0, t * 9.0 * (1.0 - _k(0.6, 0.95)))
		spark.position = bomb.global_transform * Vector3(0.05, 0.4, 0)
		if _at(0.6):
			player.add_shake(0.08)
	else:
		bomb.visible = false
	spark.emitting = t < hit_at
	if _at(hit_at):
		var smoke := _pop(rest, 140, 5.0, 2.6, Color(0.4, 0.42, 0.45, 1.0), Color(0.62, 0.63, 0.66, 0.0), 5.0, -0.4, false)
		smoke.emission_sphere_radius = 0.6
		smoke.damping_min = 3.0
		smoke.damping_max = 5.0
		smoke.scale_amount_curve = _grow_curve(0.65, 1.1)
		_flash(rest + Vector3(0, 1, 0), Color(1.0, 0.95, 0.85), 6.0, 8.0, 0.25)
		_burst(rest + Vector3(0, 0.8, 0), 3.0, Color(0.85, 0.85, 0.85), 0.3)
		_burst(target + Vector3(0, 0.5, 0), RADIUS, Color(0.55, 0.6, 0.55), 0.45)
	if not is_landed:
		hero.visible = t >= hit_at + 0.1
		var up := _eio(_k(1.9, 2.3))
		hero.scale = Vector3(1.0 + 0.06 * (1.0 - up), 0.84 + 0.16 * up, 1.0 + 0.06 * (1.0 - up))
		hero.position = Vector3(0, 0, 0)
		var dagger: Node3D = s["dagger"]
		var toss := _k(2.3, 2.95)
		dagger.visible = toss > 0.0 and toss < 1.0
		dagger.position = Vector3(0.32, 1.1 + 1.3 * sin(toss * PI), -0.3)
		dagger.rotation = Vector3(toss * TAU * 2.0, 0, 0)
		if _at(2.3):
			hero.play_ability(0)
		if _at(2.62):
			_flash(hero.global_transform * Vector3(0.32, 2.4, -0.3), Color(1, 1, 1), 2.0, 3.0, 0.15)


# ------------------------------------------------------------------ Gaiden
## A whirl of leaves and reeds whips round the spot, three slashes cut across it in a blink,
## the leaves burst apart and he is simply there, kneeling; he rises and sheathes with a click.

func _gaiden() -> void:
	var red := RosterHero.color(kit, "main")
	if s.is_empty():
		var leaf := QuadMesh.new()
		leaf.size = Vector2(0.38, 0.19)
		var lmat := _vc()
		lmat.roughness = 0.8
		var lv := _swarm(leaf, 150, lmat)
		var greens: Array[Color] = [Color(0.36, 0.55, 0.18), Color(0.55, 0.62, 0.22), Color(0.45, 0.35, 0.15), Color(0.66, 0.6, 0.3), Color(0.25, 0.42, 0.14)]
		for i in lv.n:
			var a := randf() * TAU
			lv.p[i] = target + _fwd * randf_range(8.0, 14.0) + Vector3(cos(a) * 4.0, randf_range(0.5, 4.0), sin(a) * 4.0)
			lv.f[i] = randf() * TAU
			lv.g[i] = randf_range(0.2, 3.0)
			lv.q[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			lv.c[i] = greens[i % greens.size()]
		s["leaves"] = lv
		var smat := _glow(Color(1.0, 0.9, 0.9, 1.0))
		smat.albedo_texture = _streak_tex()
		var slashes: Array[MeshInstance3D] = []
		var angs := [-0.6, 0.55, 0.05]
		for k in 3:
			var q := QuadMesh.new()
			q.size = Vector2(5.0, 0.22)
			var m := smat.duplicate() as StandardMaterial3D
			m.albedo_color = Color(1.0, 0.85 - k * 0.2, 0.85 - k * 0.2, 0.0)
			var mi := _mesh(q, m, target + Vector3(0, 1.1 + (k - 1) * 0.25, 0))
			mi.basis = Basis.looking_at(_fwd, Vector3.UP) * Basis(Vector3.BACK, float(angs[k]))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			slashes.append(mi)
		s["slashes"] = slashes
		s["marks"] = _decal("slashes", 3.0, Color(0.35, 0.02, 0.04), Color(0.05, 0.0, 0.0), Vector3.INF, "")
	var lv: Swarm = s["leaves"]
	var swirl := _k(0.0, 1.6)
	var radius := lerpf(5.0, 1.3, _eio(swirl))
	var cut := 1.95
	for i in lv.n:
		var ang := lv.f[i] + t * (4.0 + 7.0 * swirl)
		var orbit := target + Vector3(cos(ang) * radius * (0.8 + 0.2 * sin(lv.f[i] * 3.0)), lv.g[i] + 0.4 * sin(t * 3.0 + lv.f[i]), sin(ang) * radius)
		var p: Vector3
		if t < cut:
			p = lv.p[i].lerp(orbit, _eo(clampf(t / 0.6, 0.0, 1.0)))
		else:
			if _at(cut):
				lv.v[i] = orbit
			var out := (Vector3(lv.v[i].x, target.y, lv.v[i].z) - target).normalized()
			p = _fly(lv.v[i], out * 8.0 + Vector3(0, 3.0, 0), t - cut, 3.0, 2.0, 0.03)
		var b := Basis(lv.q[i], t * 6.0 + lv.f[i])
		lv.put(i, b, p, Color(lv.c[i], 1.0 - clampf((t - cut - 1.6) / 0.8, 0.0, 1.0)))
	var slashes: Array[MeshInstance3D] = s["slashes"]
	for k in slashes.size():
		var t0 := 1.6 + k * 0.14
		var u := _k(t0, t0 + 0.06)
		var f := 1.0 - _k(t0 + 0.06, t0 + 0.4)
		var mi := slashes[k]
		mi.scale = Vector3(maxf(u, 0.001), 1.0, 1.0)
		(mi.material_override as StandardMaterial3D).albedo_color.a = u * f
		if _at(t0):
			player.add_shake(0.12)
	var marks: ShaderMaterial = s["marks"]
	marks.set_shader_parameter("prog", _k(1.6, 2.0))
	marks.set_shader_parameter("fade", 1.0 - _k(3.5, 5.0))
	if not is_landed:
		hero.visible = t >= cut + 0.05
		var rise := _eio(_k(2.35, 2.8))
		hero.position = Vector3(0, -0.32 * (1.0 - rise), 0)
		hero.rotation = Vector3(-0.25 * (1.0 - rise), _yaw, 0)
		if _at(cut + 0.05):
			hero.play_ability(0)
		if _at(2.78):
			_flash(target + Vector3(0, 1.0, 0) + _right * 0.3, Color(1.0, 0.9, 0.9), 2.5, 3.0, 0.15)
	if _at(hit_at):
		_ring(target, RADIUS * 0.85, Color(1.0, 0.3, 0.3, 0.6), 0.4)
		_burst(target + Vector3(0, 1.0, 0), 3.0, red, 0.3)
		_burst(target + Vector3(0, 0.5, 0), RADIUS, Color(0.85, 0.85, 0.9), 0.35)


static var _streak: Texture2D


## A long soft streak (bright core fading to the ends and edges) for blade trails.
static func _streak_tex() -> Texture2D:
	if _streak == null:
		var img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
		for x in 64:
			for y in 16:
				var u := float(x) / 63.0
				var v := absf(float(y) / 15.0 - 0.5) * 2.0
				var a := pow(sin(u * PI), 0.6) * pow(1.0 - v, 2.0) * (0.4 + 0.6 * u)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_streak = ImageTexture.create_from_image(img)
	return _streak


# ------------------------------------------------------------------ Dr. Croc
## The ground turns into a bubbling green chemical pool; his eyes and snout surface and glide
## across it like a lurking crocodile, then he surges up out of it in a green splash and
## adjusts his goggles.

func _dr_croc() -> void:
	var green := RosterHero.color(kit, "main")
	if s.is_empty():
		s["pool"] = _decal("chem", 4.0, Color(0.6, 1.0, 0.25), Color(0.08, 0.32, 0.06))
		var bubbles := _emitter(0.3, 0.9, 50, Color(0.75, 1.0, 0.45, 0.9), Color(0.5, 1.0, 0.2, 0.0), true, target + Vector3(0, 0.1, 0))
		bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		bubbles.emission_ring_axis = Vector3.UP
		bubbles.emission_ring_radius = 3.0
		bubbles.emission_ring_inner_radius = 0.0
		bubbles.emission_ring_height = 0.05
		bubbles.spread = 10.0
		bubbles.initial_velocity_min = 0.3
		bubbles.initial_velocity_max = 1.0
		bubbles.gravity = Vector3(0, 0.5, 0)
		s["bubbles"] = bubbles
		var fumes := _emitter(1.6, 2.0, 30, Color(0.4, 0.8, 0.2, 0.0), Color(0.35, 0.6, 0.2, 0.0), false, target + Vector3(0, 0.3, 0))
		var g := Gradient.new()
		g.set_color(0, Color(0.45, 0.85, 0.25, 0.0))
		g.add_point(0.3, Color(0.45, 0.8, 0.25, 0.3))
		g.set_color(g.get_point_count() - 1, Color(0.4, 0.6, 0.25, 0.0))
		fumes.color_ramp = g
		fumes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		fumes.emission_ring_axis = Vector3.UP
		fumes.emission_ring_radius = 3.0
		fumes.emission_ring_inner_radius = 0.0
		fumes.emission_ring_height = 0.1
		fumes.gravity = Vector3(0, 0.8, 0)
		fumes.scale_amount_curve = _grow_curve()
		s["fumes"] = fumes
		s["light"] = _light(target + Vector3(0, 0.8, 0), green, 0.0, 9.0)
		var wake := _emitter(0.25, 0.7, 30, Color(0.8, 1.0, 0.5, 1.0), Color(0.5, 1.0, 0.25, 0.0), true, target)
		wake.emission_sphere_radius = 0.3
		wake.spread = 30.0
		wake.initial_velocity_min = 0.5
		wake.initial_velocity_max = 1.5
		wake.gravity = Vector3(0, -2.0, 0)
		s["wake"] = wake
	var pool: ShaderMaterial = s["pool"]
	pool.set_shader_parameter("prog", _eo(_k(0.0, 0.8)) * (1.0 - 0.7 * _eio(_k(2.6, 3.8))))
	pool.set_shader_parameter("fade", 1.0 - _k(3.4, 4.4))
	(s["bubbles"] as CPUParticles3D).emitting = t > 0.2 and t < 2.9
	(s["fumes"] as CPUParticles3D).emitting = t > 0.3 and t < 2.6
	(s["light"] as OmniLight3D).light_energy = 2.2 * _k(0.1, 0.8) * (1.0 - _k(2.8, 3.8)) + 3.0 * sin(_k(hit_at, hit_at + 0.4) * PI)
	# Surface, glide in like a lurking croc, then surge up
	var lurk := _k(0.8, 1.75)
	var start := _to_cam * -2.6 + _right * 1.6
	var wake: CPUParticles3D = s["wake"]
	if not is_landed:
		hero.visible = t >= 0.8
		var y: float
		if t < 1.75:
			y = lerpf(-1.95, -1.25, _eo(_k(0.8, 1.15)))
		else:
			y = lerpf(-1.25, 0.0, _eo(_k(1.75, 2.15)))
		var flat := start.lerp(Vector3.ZERO, _eio(lurk))
		hero.position = Vector3(flat.x, y, flat.z)
		hero.rotation = Vector3(0, _yaw + 0.5 * (1.0 - lurk), 0)
		hero.set_flash(0.3 * (1.0 - _k(2.0, 2.8)))
		wake.position = target + flat + Vector3(0, 0.15, 0)
		if _at(2.6):
			hero.play_ability(0)
		if _at(2.85):
			_flash(target + Vector3(0, 1.75, 0) + _to_cam * 0.3, Color(1.0, 0.95, 0.6), 2.5, 3.0, 0.2)
	wake.emitting = t > 0.85 and t < 1.8
	if _at(hit_at):
		var spl := _pop(target + Vector3(0, 0.4, 0), 70, 0.35, 1.0, Color(0.75, 1.0, 0.4, 1.0), Color(0.4, 0.9, 0.2, 0.0), 8.0, 14.0)
		spl.direction = Vector3.UP
		spl.spread = 50.0
		_burst(target + Vector3(0, 1.0, 0), 3.5, green, 0.4)
		_burst(target + Vector3(0, 0.4, 0), RADIUS, Color(0.4, 0.9, 0.2), 0.5)
		_ring(target, RADIUS, Color(0.55, 1.0, 0.3, 0.7), 0.5)


# ------------------------------------------------------------------ Blob
## A little ooze puddle seeps up through the ground and spreads, bubbling and gurgling, then
## swells up into the full Blob, wobbles, and lands a wet splort.

func _blob() -> void:
	var green := RosterHero.color(kit, "main")
	if s.is_empty():
		s["ooze"] = _decal("ooze", 3.2, Color(0.55, 1.0, 0.3), Color(0.15, 0.45, 0.08), Vector3.INF, "")
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 10
		sm.rings = 6
		var bmat := _vc()
		bmat.roughness = 0.05
		bmat.metallic_specular = 1.0
		bmat.emission_enabled = true
		bmat.emission = Color(0.12, 0.3, 0.05)
		var bb := _swarm(sm, 22, bmat)
		for i in bb.n:
			var a := randf() * TAU
			bb.p[i] = Vector3(cos(a), 0, sin(a)) * randf_range(0.3, 2.5)
			bb.f[i] = randf() * 0.9         # phase
			bb.g[i] = randf_range(0.12, 0.3)
		s["bubbles"] = bb
		var goo := _emitter(0.2, 0.7, 24, Color(0.6, 1.0, 0.35, 1.0), Color(0.35, 0.8, 0.2, 0.0), false, target + Vector3(0, 0.1, 0))
		goo.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		goo.emission_ring_axis = Vector3.UP
		goo.emission_ring_radius = 2.0
		goo.emission_ring_inner_radius = 0.0
		goo.emission_ring_height = 0.05
		goo.spread = 25.0
		goo.initial_velocity_min = 1.0
		goo.initial_velocity_max = 2.5
		goo.gravity = Vector3(0, -9.0, 0)
		goo.scale_amount_curve = null
		s["goo"] = goo
		_restore.append(func() -> void:
			if hero.blob:
				hero.blob.puddle_target = 0.0)
	var ooze: ShaderMaterial = s["ooze"]
	ooze.set_shader_parameter("prog", _eo(_k(0.0, 1.0)) * (1.0 - 0.55 * _eio(_k(1.3, 2.4))))
	ooze.set_shader_parameter("fade", 1.0 - _k(3.3, 4.3))
	(s["goo"] as CPUParticles3D).emitting = t > 0.3 and t < 2.3
	var bb: Swarm = s["bubbles"]
	for i in bb.n:
		var cyc := fmod(t * 1.1 + bb.f[i], 1.0)
		var live := t > 0.2 and t < 2.6
		if not live:
			bb.hide(i)
			continue
		var r := bb.g[i] * sin(cyc * PI) * (1.0 + 0.3 * float(cyc > 0.9))
		var p: Vector3 = target + bb.p[i] * (0.6 + 0.4 * _k(0.0, 1.0))
		p.y = _gy(p.x, p.z) + r * 0.3
		bb.put(i, Basis().scaled(Vector3(r, r * 0.8, r)), p, Color(0.6, 1.0, 0.35, 0.75))
	if not is_landed:
		hero.visible = t >= 0.35
		var spread := 1.0 - _eio(_k(1.2, 2.3))
		if hero.blob:
			hero.blob.puddle = spread
			hero.blob.puddle_target = spread
		var grow := lerpf(0.3, 0.75, _eo(_k(0.35, 1.2)))
		var swell := _eo(_k(1.2, 2.4))
		var sc := lerpf(grow, 1.0, swell) + 0.14 * sin(_k(2.2, 3.0) * PI * 2.0) * (1.0 - _k(2.6, 3.1))
		hero.scale = Vector3.ONE * sc
		hero.position = Vector3.ZERO
	if _at(hit_at):
		var spl := _pop(target + Vector3(0, 0.6, 0), 50, 0.3, 0.9, Color(0.6, 1.0, 0.35, 1.0), Color(0.4, 0.9, 0.2, 0.0), 7.0, 14.0, false)
		spl.direction = Vector3.UP
		spl.spread = 75.0
		_burst(target + Vector3(0, 0.6, 0), RADIUS, green, 0.5)
		_ring(target, RADIUS, Color(0.55, 1.0, 0.3, 0.6), 0.5)
		hero.play_ability(1)


# ------------------------------------------------------------------ The Arachnid
## It lowers itself on a silk thread from high above, swinging gently, hangs a moment, then
## lets go and drops the last bit, legs splaying, and webs puff out across the ground.

func _arachnid() -> void:
	var venom := RosterHero.color(kit, "main")
	if s.is_empty():
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.02
		cyl.height = 1.0
		cyl.radial_segments = 6
		var silk := _mesh(cyl, _glow(Color(0.92, 0.95, 1.0, 0.75), false))
		silk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s["silk"] = silk
		s["anchor"] = target + _right * 1.0 + Vector3(0, 40.0, 0)
		s["web"] = _decal("web", 5.5, Color(0.93, 0.95, 1.0), Color(1, 1, 1))
	var anchor: Vector3 = s["anchor"]
	var silk: MeshInstance3D = s["silk"]
	var hang := 2.0
	var drop := 2.3
	var land := hit_at
	var h: float
	if t < hang:
		h = lerpf(20.0, 3.2, _eo(_k(0.0, hang)))
	elif t < drop:
		h = 3.2 + 0.12 * sin((t - hang) * 18.0) * (1.0 - _k(hang, drop))
	else:
		h = 3.2 * (1.0 - pow(_k(drop, land), 2.0))
	var swing := 1.3 * sin(t * 2.4) * (1.0 - _k(0.0, drop))
	var body := target + _right * swing + Vector3(0, h, 0)
	if not is_landed:
		hero.visible = true
		player.global_position = body   # the camera comes down with it
		hero.position = Vector3.ZERO
		hero.rotation = Vector3(0, _yaw, -swing * 0.12)
		hero.set_motion(0.0, t < land)
		if t >= land:
			var sq := 1.0 - clampf((t - land) / 0.3, 0.0, 1.0)
			hero.scale = Vector3(1.0 + 0.25 * sq, 1.0 - 0.3 * sq, 1.0 + 0.25 * sq)
	# The thread runs up from its back; when it lets go the cut end whips back up
	var end := body + Vector3(0, 0.75, 0)
	if t >= drop:
		end = (target + _right * swing + Vector3(0, 3.2 + 0.75, 0)).lerp(anchor, _eo(_k(drop, drop + 0.5)))
	var span := anchor - end
	silk.visible = span.length() > 0.2
	if silk.visible:
		silk.position = end + span * 0.5
		silk.basis = Basis(Quaternion(Vector3.UP, span.normalized())) * Basis.from_scale(Vector3(1.0, span.length(), 1.0))
	var web: ShaderMaterial = s["web"]
	web.set_shader_parameter("prog", _eo(_k(land, land + 0.3)))
	web.set_shader_parameter("fade", 1.0 - _k(4.5, 6.0))
	if _at(land):
		_pop(target + Vector3(0, 0.3, 0), 40, 0.9, 0.8, Color(0.95, 0.97, 1.0, 0.8), Color(0.9, 0.92, 1.0, 0.0), 5.0, 1.0, false)
		_burst(target + Vector3(0, 0.5, 0), RADIUS, venom, 0.45)
		_ring(target, RADIUS * 0.75, Color(0.9, 0.95, 1.0, 0.35), 0.35)
		hero.play_ability(2)


# ------------------------------------------------------------------ Loco Robotico
## A piñata swings in on a rope and bursts into confetti and streamers; a cardboard box drops
## out of it, its flaps pop open and the party robot springs up out of it, disco lights on.

func _loco_robotico() -> void:
	if s.is_empty():
		var rope := CylinderMesh.new()
		rope.top_radius = 0.03
		rope.bottom_radius = 0.03
		rope.height = 1.0
		rope.radial_segments = 6
		s["rope"] = _mesh(rope, _lit(Color(0.75, 0.62, 0.4), 0.9))
		s["pinata"] = _add(_make_pinata())
		var quad := QuadMesh.new()
		quad.size = Vector2(0.17, 0.1)
		var conf := _swarm(quad, 260, _vc(true))
		for i in conf.n:
			conf.v[i] = Vector3(randf_range(-1, 1), randf_range(-0.3, 1.0), randf_range(-1, 1)).normalized() * randf_range(3.0, 10.0)
			conf.q[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			conf.f[i] = randf() * TAU
			conf.c[i] = Color.from_hsv(randf(), 0.75, 1.0)
		s["confetti"] = conf
		var sq := QuadMesh.new()
		sq.size = Vector2(0.08, 0.75)
		var strs := _swarm(sq, 18, _vc(true))
		for i in strs.n:
			strs.v[i] = Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized() * randf_range(2.0, 6.0)
			strs.f[i] = randf() * TAU
			strs.q[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			strs.c[i] = Color.from_hsv(randf(), 0.8, 1.0)
		s["streamers"] = strs
		var box := Node3D.new()
		_add(box, target)
		var card := _lit(Color(0.68, 0.5, 0.3), 0.95)
		var tape := _lit(Color(0.85, 0.75, 0.5), 0.6)
		var size := 1.1
		var bottom := BoxMesh.new()
		bottom.size = Vector3(size, 0.04, size)
		_mesh(bottom, card, Vector3(0, 0.02, 0), box)
		for k in 4:   # the walls fold down flat when it falls apart
			var wall := Node3D.new()
			var a := k * PI / 2.0
			var dir := Vector3(sin(a), 0, cos(a))
			_add(wall, dir * size * 0.5, box)
			wall.basis = Basis(Vector3.UP, a)
			wall.name = "W%d" % k
			var w := BoxMesh.new()
			w.size = Vector3(size, size * 0.9, 0.04)
			_mesh(w, card, Vector3(0, size * 0.45, 0), wall)
			var flap := Node3D.new()
			flap.name = "F"
			_add(flap, Vector3(0, size * 0.9, 0), wall)
			var f := BoxMesh.new()
			f.size = Vector3(size, 0.03, size * 0.5)
			_mesh(f, card, Vector3(0, 0, -size * 0.25), flap)
			var strip := BoxMesh.new()
			strip.size = Vector3(0.16, 0.035, size * 0.5)
			_mesh(strip, tape, Vector3(0, 0.005, -size * 0.25), flap)
		box.visible = false
		s["box"] = box
		var lights: Array[OmniLight3D] = []
		for k in 3:
			var l := _light(target, Color.from_hsv(k / 3.0, 0.9, 1.0), 0.0, 6.0)
			lights.append(l)
		s["disco"] = lights
		_restore.append(func() -> void:
			if hero.loco:
				hero.loco.party = false)
	# The piñata swings in on its rope from the side
	var pivot := target + Vector3(0, 13.0, 0) + _fwd * 0.5
	var length := 10.8
	var th := 1.0 * cos(PI * t / 1.0) * exp(-0.15 * t) if t < hit_at else 0.0
	var pin := pivot + (_right * sin(th) - Vector3(0, cos(th), 0)) * length
	var pinata: Node3D = s["pinata"]
	var rope: MeshInstance3D = s["rope"]
	if t < hit_at:
		pinata.position = pin - Vector3(0, 1.2, 0)
		pinata.basis = Basis(Vector3.UP, _yaw - PI / 2) * Basis(Vector3.BACK, th * 0.3)
		var span := pivot - (pin + Vector3(0, 0.6, 0))
		rope.position = pin + Vector3(0, 0.6, 0) + span * 0.5
		rope.basis = Basis(Quaternion(Vector3.UP, span.normalized())) * Basis.from_scale(Vector3(1, span.length(), 1))
	else:
		pinata.visible = false
		var top := pivot - Vector3(0, length * (1.0 - _eo(_k(hit_at, hit_at + 0.6))), 0)
		var span2 := pivot - top
		rope.visible = span2.length() > 0.3
		if rope.visible:
			rope.position = top + span2 * 0.5
			rope.basis = Basis(Quaternion(Vector3.UP, span2.normalized())) * Basis.from_scale(Vector3(1, span2.length(), 1))
	var burst_at := target + Vector3(0, 2.2, 0)
	var conf: Swarm = s["confetti"]
	var strm: Swarm = s["streamers"]
	if t >= hit_at:
		var tau := t - hit_at
		var fade := 1.0 - clampf((tau - 3.5) / 1.0, 0.0, 1.0)
		for i in conf.n:
			var p := _fly(burst_at, conf.v[i], tau, 3.5, 2.4, 0.02)
			p += Vector3(sin(t * 5.0 + conf.f[i]), 0, cos(t * 4.0 + conf.f[i])) * 0.25 * minf(tau, 1.0) * float(p.y > _gy(p.x, p.z) + 0.05)
			conf.put(i, Basis(conf.q[i], t * 9.0 + conf.f[i]), p, Color(conf.c[i], fade))
		for i in strm.n:
			var p := _fly(burst_at, strm.v[i], tau, 2.0, 2.0, 0.1)
			var b := Basis(strm.q[i], strm.f[i] + t * 5.0) * Basis(Vector3.FORWARD, 0.8 * sin(t * 7.0 + strm.f[i]))
			strm.put(i, b, p + Vector3(0, 0.3, 0), Color(strm.c[i], fade))
	if _at(hit_at):
		_burst(burst_at, 3.0, Color(1.0, 0.5, 0.85), 0.35)
		_burst(target + Vector3(0, 0.5, 0), RADIUS, Color(0.5, 1.0, 0.8), 0.45)
		_ring(target, RADIUS, Color(1.0, 0.45, 0.85, 0.6), 0.5)
		_flash(burst_at, Color(1.0, 0.8, 0.9), 5.0, 8.0, 0.3)
	# The box falls out, pops open, and the robot springs up out of it
	var box: Node3D = s["box"]
	var fall := _k(hit_at, hit_at + 0.32)
	box.visible = t >= hit_at
	if box.visible:
		var by := 2.2 * (1.0 - fall * fall)
		box.position = target + Vector3(0, by + 0.12 * sin(_k(hit_at + 0.32, hit_at + 0.5) * PI), 0)
		box.basis = Basis(Vector3.UP, _yaw + PI * 0.25) * Basis(Vector3.RIGHT, 0.6 * (1.0 - fall))
		var open := _back(_k(1.95, 2.2))
		var flat := _eio(_k(2.9, 3.4))
		for k in 4:
			var wall := box.get_node("W%d" % k) as Node3D
			var a := k * PI / 2.0
			wall.basis = Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, flat * PI / 2.0)
			(wall.get_node("F") as Node3D).rotation.x = -open * 2.2
		var gone := _k(4.2, 5.0)
		box.scale = Vector3.ONE * maxf(1.0 - gone, 0.001)
	if _at(hit_at + 0.32):
		player.add_shake(0.15)
	var lights: Array[OmniLight3D] = s["disco"]
	for k in lights.size():
		var a := t * 4.0 + TAU * k / 3.0
		lights[k].position = target + Vector3(cos(a) * 2.2, 2.6, sin(a) * 2.2)
		lights[k].light_energy = 3.5 * _k(2.3, 2.5) * (1.0 - _k(3.4, 4.2))
	if not is_landed:
		hero.visible = t >= 2.05
		var up := _back(_k(2.1, 2.55))
		hero.position = Vector3(0, -0.7 * (1.0 - _k(2.1, 2.45)), 0)
		hero.scale = Vector3(1.0, maxf(0.25 + 0.75 * up, 0.01), 1.0)
		if hero.loco and t >= 2.4:
			hero.loco.party = true
		if _at(2.5):
			hero.play_ability(0)


## The piñata donkey: paper bands in party colours (like Loco's Piñata ability).
func _make_pinata() -> Node3D:
	var root := Node3D.new()
	var mb := MeshBuilder.new()
	var stripes: Array[Color] = [Color(1.0, 0.3, 0.6, 0), Color(1.0, 0.85, 0.2, 0), Color(0.3, 0.85, 1.0, 0), Color(0.5, 1.0, 0.35, 0), Color(0.75, 0.45, 1.0, 0)]
	var along := Basis(Vector3.RIGHT, PI / 2)
	for k in 7:
		mb.add(MeshBuilder.cyl(0.42, 0.42, 0.17, 16), Transform3D(along, Vector3(0, 1.0, -0.51 + k * 0.17)), stripes[k % 5])
	for k in 4:
		mb.add(MeshBuilder.cyl(0.2, 0.22, 0.16, 12), Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 1.35 + k * 0.13, -0.55 - k * 0.07)), stripes[(k + 2) % 5])
	mb.add(MeshBuilder.box(Vector3(0.32, 0.3, 0.55)), Transform3D(Basis(), Vector3(0, 1.85, -0.9)), stripes[1])
	mb.add(MeshBuilder.box(Vector3(0.28, 0.24, 0.2)), Transform3D(Basis(), Vector3(0, 1.8, -1.2)), stripes[0])
	for sx in [-1.0, 1.0]:
		mb.add(MeshBuilder.cyl(0.02, 0.07, 0.32, 6), Transform3D(Basis(Vector3.FORWARD, sx * 0.3), Vector3(sx * 0.12, 2.15, -0.8)), stripes[3])
		mb.add(MeshBuilder.sphere(0.04, 6, 4), Transform3D(Basis(), Vector3(sx * 0.12, 1.92, -1.15)), Color(0.05, 0.05, 0.05, 0))
		for z in [-0.4, 0.4]:
			mb.add(MeshBuilder.cyl(0.09, 0.09, 0.62, 8), Transform3D(Basis(), Vector3(sx * 0.22, 0.42, z)), stripes[(int(z * 10) + 5) % 5])
	mb.add(MeshBuilder.cyl(0.05, 0.02, 0.5, 6), Transform3D(Basis(Vector3.RIGHT, 0.9), Vector3(0, 1.05, 0.75)), stripes[4])
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(MeshBuilder.prop_material())
	root.add_child(mi)
	return root


# ------------------------------------------------------------------ Toadstool Knight
## A fairy ring of mushrooms pops up one by one, a giant toadstool grows in the middle with him
## riding up on its cap, and he leaps off it with a somersault, landing in a burst of spores.

func _toadstool_knight() -> void:
	var violet := RosterHero.color(kit, "main")
	if s.is_empty():
		var ring: Array = []
		var n := 13
		for k in n:
			var a := TAU * k / n
			var p := _ground(target + Vector3(cos(a), 0, sin(a)) * 3.8)
			var m := KitToadstool.make_toadstool(randf_range(0.5, 0.85), k * 7 + 3)
			_add(m, p)
			m.rotation.y = randf() * TAU
			m.scale = Vector3.ONE * 0.001
			ring.append([m, 0.05 + 0.9 * float(k) / n])
		s["ring"] = ring
		var big := KitToadstool.make_toadstool(4.2, 11, true)
		var bp := _ground(target + _fwd * 2.4)
		_add(big, bp)
		big.rotation.y = _yaw
		big.scale = Vector3.ONE * 0.001
		s["big"] = big
		s["bp"] = bp
		s["fairy"] = _decal("fairy", 4.8, Color(0.75, 0.5, 1.0), Color(0.4, 1.0, 0.6), Vector3.INF, "unshaded add")
		var spores := _emitter(0.16, 1.4, 50, Color(0.85, 0.7, 1.0, 1.0), Color(0.5, 1.0, 0.6, 0.0), true, target + Vector3(0, 0.3, 0))
		spores.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		spores.emission_ring_axis = Vector3.UP
		spores.emission_ring_radius = 3.8
		spores.emission_ring_inner_radius = 3.4
		spores.emission_ring_height = 0.1
		spores.gravity = Vector3(0, 0.8, 0)
		s["spores"] = spores
	var shrink := _eio(_k(2.9, 3.7))
	for r in s["ring"]:
		var m: Node3D = r[0]
		var g := _back(_k(r[1], r[1] + 0.2)) * (1.0 - shrink)
		m.scale = Vector3.ONE * maxf(g, 0.001)
		if _at(r[1]):
			_burst(m.position + Vector3(0, 0.4, 0), 0.8, Color(0.8, 0.6, 1.0), 0.25)
	(s["spores"] as CPUParticles3D).emitting = t > 0.2 and t < 2.8
	var fairy: ShaderMaterial = s["fairy"]
	fairy.set_shader_parameter("prog", _eo(_k(0.0, 1.0)))
	fairy.set_shader_parameter("fade", 1.0 - _k(3.0, 4.0))
	var big: Node3D = s["big"]
	var bp: Vector3 = s["bp"]
	var grow := _back(_k(0.6, 1.5))
	var bounce := sin(_k(2.0, 2.3) * PI) * 0.18
	var gone := _eio(_k(3.0, 3.8))
	big.scale = Vector3(1.0 + bounce * 0.6, maxf(grow * (1.0 - bounce) * (1.0 - gone), 0.001), 1.0 + bounce * 0.6) * maxf(grow, 0.001)
	var cap_top := 4.2 * (0.6 + 0.42 * 0.62) * big.scale.y
	var leap := 2.05
	var land := hit_at
	if not is_landed:
		hero.visible = t >= 0.6
		var top := bp - target + Vector3(0, cap_top, 0)
		if t < leap:
			hero.position = top
			hero.rotation = Vector3(0, _yaw, 0)
		elif t < land:
			var u := _k(leap, land)
			var from := bp - target + Vector3(0, 4.2 * (0.6 + 0.42 * 0.62), 0)
			hero.position = from.lerp(Vector3.ZERO, u) + Vector3(0, 2.0 * sin(u * PI), 0)
			hero.basis = Basis(_right, -u * TAU) * Basis(Vector3.UP, _yaw)
		else:
			var sq := 1.0 - clampf((t - land) / 0.3, 0.0, 1.0)
			hero.transform = Transform3D(Basis(Vector3.UP, _yaw).scaled(Vector3(1.0 + 0.15 * sq, 1.0 - 0.2 * sq, 1.0 + 0.15 * sq)), Vector3.ZERO)
		if _at(land):
			hero.play_ability(2)
	if _at(land):
		_pop(target + Vector3(0, 0.4, 0), 60, 0.5, 1.2, Color(0.85, 0.65, 1.0, 1.0), Color(0.4, 1.0, 0.6, 0.0), 6.0, 1.0)
		_burst(target + Vector3(0, 0.6, 0), RADIUS, violet, 0.5)
		_ring(target, RADIUS, Color(0.8, 0.55, 1.0, 0.7), 0.5)


# ------------------------------------------------------------------ Thog the Troll
## He jumps in from far across the field in one enormous leap, club raised over his head, and
## comes down club-first: the ground cracks into a crater and rocks fly.

func _thog() -> void:
	if s.is_empty():
		s["start"] = _ground(target + _fwd * 34.0)
		s["crater"] = _decal("crater", 5.0, Color(0.36, 0.3, 0.22), Color(0.05, 0.045, 0.04), Vector3.INF, "")
		var rm := SphereMesh.new()
		rm.radius = 0.5
		rm.height = 1.0
		rm.radial_segments = 5
		rm.rings = 3
		var rmat := _vc()
		rmat.roughness = 0.95
		var rocks := _swarm(rm, 50, rmat)
		for i in rocks.n:
			var a := randf() * TAU
			rocks.p[i] = target + Vector3(cos(a), 0, sin(a)) * randf_range(0.3, 1.8) + Vector3(0, 0.2, 0)
			rocks.v[i] = Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 9.0) + Vector3(0, randf_range(4.0, 11.0), 0)
			rocks.q[i] = Vector3(randf_range(0.15, 0.4), randf_range(0.12, 0.3), randf_range(0.15, 0.4))
			rocks.f[i] = randf() * TAU
			rocks.c[i] = Color(0.42, 0.38, 0.33).lerp(Color(0.3, 0.24, 0.17), randf())
		s["rocks"] = rocks
	var start: Vector3 = s["start"]
	var jump := 0.45
	var land := hit_at
	if _at(jump):
		_pop(start + Vector3(0, 0.4, 0), 30, 2.0, 1.2, Color(0.5, 0.42, 0.32, 0.7), Color(0.45, 0.4, 0.33, 0.0), 5.0, 1.0, false)
	if not is_landed:
		hero.visible = true
		var p: Vector3
		var lean := 0.0
		if t < jump:
			p = start - target
			var crouch := sin(_k(0.0, jump) * PI * 0.5)
			hero.scale = Vector3(1.0 + 0.1 * crouch, 1.0 - 0.15 * crouch, 1.0 + 0.1 * crouch)
		elif t < land:
			var u := _k(jump, land)
			p = (start - target).lerp(Vector3.ZERO, u) + Vector3(0, 15.0 * 4.0 * u * (1.0 - u), 0)
			lean = lerpf(-0.35, 0.55, u)
			hero.scale = Vector3.ONE
		else:
			p = Vector3.ZERO
			var sq := 1.0 - clampf((t - land) / 0.35, 0.0, 1.0)
			hero.scale = Vector3(1.0 + 0.18 * sq, 1.0 - 0.22 * sq, 1.0 + 0.18 * sq)
			lean = 0.55 * (1.0 - _eio(_k(land, land + 0.6)))
		hero.position = p
		hero.rotation = Vector3(-lean, player.cam_yaw + PI, 0)
		if _at(jump):
			hero.play_ability(0)
		if _at(land - 0.45):
			hero.play_ability(2)
	var crater: ShaderMaterial = s["crater"]
	crater.set_shader_parameter("prog", _eo(_k(land, land + 0.15)))
	crater.set_shader_parameter("fade", 1.0 - _k(4.6, 6.0))
	var rocks: Swarm = s["rocks"]
	if t >= land:
		var tau := t - land
		var fade := 1.0 - clampf((tau - 2.6) / 1.0, 0.0, 1.0)
		for i in rocks.n:
			var p := _fly(rocks.p[i], rocks.v[i], tau, 22.0, 1.0, rocks.q[i].y * 0.5)
			var spin := rocks.f[i] + 8.0 * minf(tau, 0.8)
			rocks.put(i, Basis(Vector3(cos(rocks.f[i]), 0.5, sin(rocks.f[i])).normalized(), spin) * Basis.from_scale(rocks.q[i]), p, Color(rocks.c[i], fade))
	if _at(land):
		_burst(target + Vector3(0, 0.8, 0), RADIUS, Color(0.5, 0.42, 0.32), 0.55)
		_burst(target + Vector3(0, 1.5, 0), 4.0, Color(0.85, 0.9, 1.0), 0.3)
		var dust := _pop(target + Vector3(0, 0.3, 0), 70, 2.6, 1.8, Color(0.5, 0.43, 0.34, 0.75), Color(0.48, 0.42, 0.35, 0.0), 11.0, -0.3, false)
		dust.damping_min = 4.0
		dust.damping_max = 6.0
		dust.scale_amount_curve = _grow_curve(0.4, 1.0)
		_ring(target, RADIUS, Color(0.65, 0.55, 0.42, 0.7), 0.5, false)


# ------------------------------------------------------------------ The Pharaoh
## The sand turns into a whirlpool and a gilded sarcophagus rises out of it, sand pouring off;
## its lid falls open with a thud, scarabs scatter, and he stands there as it sinks back down.

func _pharaoh() -> void:
	var gold := RosterHero.color(kit, "main")
	if s.is_empty():
		s["swirl"] = _decal("shadow", 3.6, Color(0.93, 0.8, 0.52), Color(0.6, 0.45, 0.25), Vector3.INF, "")
		var sand := _emitter(0.9, 1.1, 60, Color(0.9, 0.78, 0.5, 0.7), Color(0.85, 0.72, 0.45, 0.0), false, target + Vector3(0, 0.2, 0))
		sand.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		sand.emission_ring_axis = Vector3.UP
		sand.emission_ring_radius = 3.0
		sand.emission_ring_inner_radius = 1.0
		sand.emission_ring_height = 0.1
		sand.gravity = Vector3(0, 1.0, 0)
		sand.tangential_accel_min = 8.0
		sand.tangential_accel_max = 12.0
		sand.radial_accel_min = -3.0
		sand.radial_accel_max = -2.0
		s["sand"] = sand
		var coffin := Node3D.new()   # a shell (back, sides, top, base) so he can stand inside it
		_add(coffin, target)
		coffin.basis = Basis(Vector3.UP, player.cam_yaw)   # its open front (local +Z) faces the camera
		var gilt := _lit(Color(0.95, 0.72, 0.25), 0.3, 0.8)
		var lapis := _lit(Color(0.12, 0.22, 0.6), 0.4, 0.2)
		var parts := [[Vector3(1.1, 2.4, 0.1), Vector3(0, 1.2, -0.4), gilt], [Vector3(0.1, 2.4, 0.9), Vector3(-0.55, 1.2, 0.0), gilt],
			[Vector3(0.1, 2.4, 0.9), Vector3(0.55, 1.2, 0.0), gilt], [Vector3(1.2, 0.12, 1.0), Vector3(0, 2.42, 0.0), gilt],
			[Vector3(1.2, 0.12, 1.0), Vector3(0, 0.06, 0.0), gilt]]
		for k in 3:   # blue bands round the back and sides (the front is open once the lid falls)
			var y := 0.6 + k * 0.6
			parts.append([Vector3(1.22, 0.1, 0.12), Vector3(0, y, -0.41), lapis])
			parts.append([Vector3(0.12, 0.1, 0.95), Vector3(-0.56, y, 0.0), lapis])
			parts.append([Vector3(0.12, 0.1, 0.95), Vector3(0.56, y, 0.0), lapis])
		for pr in parts:
			var b := BoxMesh.new()
			b.size = pr[0]
			_mesh(b, pr[2], pr[1], coffin)
		var lid := Node3D.new()
		lid.name = "Lid"
		_add(lid, Vector3(0, 0.0, 0.48), coffin)   # hinged at its foot: it falls toward the camera
		var face := BoxMesh.new()
		face.size = Vector3(1.0, 2.35, 0.1)
		_mesh(face, gilt, Vector3(0, 1.2, 0), lid)
		var mask := BoxMesh.new()
		mask.size = Vector3(0.5, 0.6, 0.08)
		_mesh(mask, _lit(Color(1.0, 0.82, 0.35), 0.2, 0.9), Vector3(0, 1.9, 0.08), lid)
		for k in 4:
			var stripe := BoxMesh.new()
			stripe.size = Vector3(0.92, 0.07, 0.04)
			_mesh(stripe, lapis, Vector3(0, 0.4 + k * 0.32, 0.07), lid)
		var eye := SphereMesh.new()
		eye.radius = 0.04
		eye.height = 0.08
		for sx in [-0.1, 0.1]:
			_mesh(eye, _glow(Color(0.5, 1.0, 0.4), false), Vector3(sx, 1.98, 0.13), lid)
		s["coffin"] = coffin
		var pour := _emitter(0.35, 0.9, 50, Color(0.92, 0.8, 0.52, 1.0), Color(0.88, 0.75, 0.48, 0.0), false, target + Vector3(0, 2.4, 0))
		pour.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		pour.emission_box_extents = Vector3(0.55, 0.05, 0.45)
		pour.gravity = Vector3(0, -9.0, 0)
		pour.spread = 60.0
		pour.initial_velocity_min = 0.5
		pour.initial_velocity_max = 1.5
		pour.scale_amount_curve = null
		s["pour"] = pour
		var bm := _vc()
		bm.roughness = 0.3
		bm.metallic = 0.6
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 8
		sm.rings = 4
		var bugs := _swarm(sm, 40, bm)
		for i in bugs.n:
			bugs.f[i] = randf() * TAU
			bugs.g[i] = randf_range(2.5, 6.0)
		s["bugs"] = bugs
		s["light"] = _light(target + Vector3(0, 2.0, 0), gold, 0.0, 9.0)
	var swirl: ShaderMaterial = s["swirl"]
	swirl.set_shader_parameter("prog", _eo(_k(0.0, 0.7)) * (1.0 - 0.6 * _k(2.6, 3.4)))
	swirl.set_shader_parameter("fade", 0.85 * (1.0 - _k(3.0, 4.0)))
	(s["sand"] as CPUParticles3D).emitting = t > 0.1 and t < 2.0
	var coffin: Node3D = s["coffin"]
	var rise := _eo(_k(0.5, 1.6))
	var sink := _eio(_k(2.6, 3.3))
	coffin.position = target + Vector3(0, -2.6 * (1.0 - rise) - 2.7 * sink, 0)
	coffin.visible = sink < 0.999
	(s["pour"] as CPUParticles3D).position = coffin.position + Vector3(0, 2.4, 0)
	(s["pour"] as CPUParticles3D).emitting = t > 0.6 and t < 1.9
	var lid: Node3D = coffin.get_node("Lid")
	var fall := _k(1.85, hit_at)
	lid.rotation.x = PI / 2.0 * fall * fall   # it tips over toward the camera, faster as it goes
	(s["light"] as OmniLight3D).light_energy = 3.0 * _k(1.8, 2.2) * (1.0 - _k(2.8, 3.6))
	if not is_landed:
		hero.visible = t >= 1.6
		hero.rotation = Vector3(0, player.cam_yaw + PI, 0)
	var bugs: Swarm = s["bugs"]
	if t >= hit_at:   # scarabs scuttle out across the sand
		var tau := t - hit_at
		for i in bugs.n:
			var r := 0.6 + bugs.g[i] * minf(tau, 1.4) / 1.4
			var a := bugs.f[i] + 0.4 * sin(tau * 9.0 + float(i))
			var p := _ground(target + Vector3(cos(a), 0, sin(a)) * r) + Vector3(0, 0.05, 0)
			var b := Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(0.12, 0.06, 0.16))
			bugs.put(i, b, p, Color(0.1, 0.25, 0.55, 1.0 - clampf((tau - 1.6) / 0.6, 0.0, 1.0)))
	if _at(hit_at):
		_pop(target + _to_cam * 1.4 + Vector3(0, 0.3, 0), 50, 1.6, 1.2, Color(0.9, 0.78, 0.5, 0.8), Color(0.85, 0.72, 0.45, 0.0), 6.0, 2.0, false)
		_ring(target, RADIUS, Color(1.0, 0.8, 0.36, 0.7), 0.5)
		_flash(target + Vector3(0, 1.8, 0), Color(0.5, 1.0, 0.4), 4.0, 6.0, 0.4)
		hero.play_ability(2)


# ------------------------------------------------------------------ The Necromancer
## Green ghost-fire rings the spot, skeletal hands claw up out of the earth around it, a
## headstone heaves up, its cracks glow green, and it bursts apart: he's standing where it was.

func _necromancer() -> void:
	var green := RosterHero.color(kit, "main")
	if s.is_empty():
		s["ring"] = _decal("fairy", 4.2, Color(0.35, 1.0, 0.5), Color(0.6, 1.0, 0.7), Vector3.INF, "unshaded add")
		var fire := _emitter(0.6, 0.9, 110, Color(0.5, 1.0, 0.6, 0.9), Color(0.1, 0.5, 0.2, 0.0), true, target + Vector3(0, 0.1, 0))
		fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		fire.emission_ring_axis = Vector3.UP
		fire.emission_ring_radius = 3.3
		fire.emission_ring_inner_radius = 3.1
		fire.emission_ring_height = 0.05
		fire.gravity = Vector3(0, 3.0, 0)
		s["fire"] = fire
		var bone := Color(0.86, 0.83, 0.72)
		var hands: Array = []
		for k in 7:
			var a := TAU * k / 7.0 + 0.2
			var hand := Node3D.new()
			_add(hand, _ground(target + Vector3(cos(a), 0, sin(a)) * randf_range(1.6, 2.6)))
			hand.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
			var mb := MeshBuilder.new()
			var w := Color(bone, 1.0)
			mb.limb(Vector3(-0.03, -0.9, 0), Vector3(-0.03, 0.0, 0), 0.035, 0.03, w)
			mb.limb(Vector3(0.03, -0.9, 0), Vector3(0.03, 0.0, 0), 0.03, 0.03, w)
			mb.add(MeshBuilder.box(Vector3(0.16, 0.14, 0.05)), Transform3D(Basis(), Vector3(0, 0.07, 0)), w)
			for f in 4:
				var fx_ := -0.06 + f * 0.04
				mb.limb(Vector3(fx_, 0.14, 0), Vector3(fx_, 0.27, 0.04), 0.014, 0.012, w)
				mb.limb(Vector3(fx_, 0.27, 0.04), Vector3(fx_, 0.36, 0.1), 0.012, 0.009, w)
			mb.limb(Vector3(0.08, 0.06, 0), Vector3(0.15, 0.16, 0.05), 0.013, 0.01, w)
			var mi := MeshInstance3D.new()
			mi.mesh = mb.commit(_lit(bone, 0.8))
			mi.material_override = _lit(bone, 0.8)
			hand.add_child(mi)
			hands.append([hand, 0.35 + k * 0.1, hand.position])
		s["hands"] = hands
		var stone := Node3D.new()
		_add(stone, target)
		stone.basis = Basis(Vector3.UP, player.cam_yaw)
		var smat := _lit(Color(0.45, 0.46, 0.48), 0.95)
		smat.emission_enabled = true
		smat.emission = green
		smat.emission_energy_multiplier = 0.0
		s["smat"] = smat
		var slab := BoxMesh.new()
		slab.size = Vector3(1.1, 1.6, 0.3)
		_mesh(slab, smat, Vector3(0, 0.8, 0), stone)
		var top := CylinderMesh.new()
		top.top_radius = 0.55
		top.bottom_radius = 0.55
		top.height = 0.3
		_mesh(top, smat, Vector3(0, 1.6, 0), stone).rotation.x = PI / 2
		var cross := BoxMesh.new()
		cross.size = Vector3(0.08, 0.5, 0.04)
		var cmat := _glow(Color(0.4, 1.0, 0.55), false)
		_mesh(cross, cmat, Vector3(0, 1.15, 0.16), stone)
		cross = BoxMesh.new()
		cross.size = Vector3(0.32, 0.08, 0.04)
		_mesh(cross, cmat, Vector3(0, 1.25, 0.16), stone)
		s["stone"] = stone
		var rm := SphereMesh.new()
		rm.radius = 0.5
		rm.height = 1.0
		rm.radial_segments = 5
		rm.rings = 3
		var chunks := _swarm(rm, 36, _vc())
		for i in chunks.n:
			var a := randf() * TAU
			chunks.p[i] = target + Vector3(cos(a) * 0.3, randf_range(0.2, 1.7), sin(a) * 0.3)
			chunks.v[i] = Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 8.0) + Vector3(0, randf_range(2.0, 7.0), 0)
			chunks.q[i] = Vector3(randf_range(0.12, 0.3), randf_range(0.1, 0.25), randf_range(0.12, 0.3))
			chunks.f[i] = randf() * TAU
		s["chunks"] = chunks
		s["light"] = _light(target + Vector3(0, 1.2, 0), green, 0.0, 10.0)
	var ring: ShaderMaterial = s["ring"]
	ring.set_shader_parameter("prog", _eo(_k(0.0, 0.6)))
	ring.set_shader_parameter("fade", 1.0 - _k(2.8, 3.8))
	(s["fire"] as CPUParticles3D).emitting = t < 2.7
	(s["light"] as OmniLight3D).light_energy = 2.0 * _k(0.0, 0.8) * (1.0 - _k(2.8, 3.8)) + 4.0 * sin(_k(hit_at - 0.3, hit_at + 0.3) * PI)
	for h in s["hands"]:   # claw up out of the ground, grope, sink back
		var hand: Node3D = h[0]
		var base: Vector3 = h[2]
		var up := _eo(_k(h[1], h[1] + 0.5)) * (1.0 - _eio(_k(2.4, 3.2)))
		hand.position = base + Vector3(0, -1.0 + 1.25 * up, 0)
		hand.rotation.x = 0.3 * sin(t * 4.0 + float(h[1]) * 9.0)
	var stone: Node3D = s["stone"]
	var smat: StandardMaterial3D = s["smat"]
	if t < hit_at:
		var j := 0.04 * _k(1.3, hit_at)
		stone.position = target + Vector3(randf_range(-j, j), -1.9 * (1.0 - _eo(_k(0.3, 1.2))), randf_range(-j, j))
		smat.emission_energy_multiplier = 2.5 * _k(1.2, hit_at)
	else:
		stone.visible = false
	var chunks: Swarm = s["chunks"]
	if t >= hit_at:
		var tau := t - hit_at
		var fade := 1.0 - clampf((tau - 1.8) / 0.8, 0.0, 1.0)
		for i in chunks.n:
			var p := _fly(chunks.p[i], chunks.v[i], tau, 18.0, 1.2, chunks.q[i].y * 0.5)
			var b := Basis(Vector3(cos(chunks.f[i]), 0.6, sin(chunks.f[i])).normalized(), chunks.f[i] + 6.0 * minf(tau, 0.8)) * Basis.from_scale(chunks.q[i])
			chunks.put(i, b, p, Color(0.45, 0.46, 0.48, fade))
	if not is_landed:
		hero.visible = t >= hit_at
		hero.rotation = Vector3(0, player.cam_yaw + PI, 0)
	if _at(hit_at):
		_burst(target + Vector3(0, 1.2, 0), 3.0, green, 0.4)
		_ring(target, RADIUS, Color(0.4, 1.0, 0.55, 0.7), 0.5)
		_pop(target + Vector3(0, 0.6, 0), 40, 1.4, 1.2, Color(0.5, 0.52, 0.5, 0.7), Color(0.45, 0.47, 0.45, 0.0), 5.0, 0.5, false)
		hero.play_ability(2)


# ------------------------------------------------------------------ Singe
## A lit fuse burns its way in over the ground in a spiral, scorching a trail, the spot glows
## and cracks, then a pillar of flame erupts and the little imp hops out of it.

func _singe() -> void:
	var orange := RosterHero.color(kit, "main")
	if s.is_empty():
		var flame := _emitter(0.7, 0.45, 50, Color(1.0, 0.85, 0.4, 1.0), Color(0.8, 0.15, 0.02, 0.0), true, target)
		flame.emission_sphere_radius = 0.1
		flame.gravity = Vector3(0, 3.0, 0)
		s["flame"] = flame
		var disc := CylinderMesh.new()
		disc.top_radius = 0.5
		disc.bottom_radius = 0.5
		disc.height = 0.02
		disc.radial_segments = 10
		var scorch := _swarm(disc, 70, _vc(true))
		s["scorch"] = scorch
		s["glow"] = _decal("glow", 3.0, Color(1.0, 0.45, 0.1), Color(1, 1, 1), Vector3.INF, "unshaded add")
		s["crack"] = _decal("crater", 3.5, Color(0.25, 0.12, 0.06), Color(0.04, 0.02, 0.01), Vector3.INF, "")
		var pillar := _emitter(1.6, 0.8, 120, Color(1.0, 0.85, 0.45, 1.0), Color(0.7, 0.1, 0.0, 0.0), true, target + Vector3(0, 0.3, 0))
		pillar.emission_sphere_radius = 0.6
		pillar.direction = Vector3.UP
		pillar.spread = 8.0
		pillar.initial_velocity_min = 7.0
		pillar.initial_velocity_max = 11.0
		pillar.gravity = Vector3(0, 2.0, 0)
		pillar.emitting = false
		s["pillar"] = pillar
		s["light"] = _light(target + Vector3(0, 1.0, 0), orange, 0.0, 10.0)
	var reach := 1.6
	var flame: CPUParticles3D = s["flame"]
	var scorch: Swarm = s["scorch"]
	# The fuse: a spiral from 7 m out into the centre over `reach` seconds
	var u := _k(0.0, reach)
	var spiral := func(v: float) -> Vector3:
		var r := 7.0 * (1.0 - v)
		var a := player.cam_yaw + v * TAU * 1.25
		return _ground(target + Vector3(cos(a), 0, sin(a)) * r)
	flame.position = (spiral.call(u) as Vector3) + Vector3(0, 0.15, 0)
	flame.emitting = t < reach
	for i in scorch.n:
		var v := float(i) / float(scorch.n - 1)
		if v > u or t > dur + 1.5:
			scorch.hide(i)
			continue
		var p: Vector3 = spiral.call(v)
		var hot := 1.0 - clampf((u - v) * 3.0, 0.0, 1.0)   # embers glow, then cool to black
		var c := Color(0.08, 0.04, 0.02).lerp(Color(1.0, 0.45, 0.1), hot * 0.9)
		scorch.put(i, Basis().scaled(Vector3(0.55, 1.0, 0.55)), p + Vector3(0, 0.04, 0), Color(c, 0.85 * (1.0 - _k(dur, dur + 1.5))))
	var glow: ShaderMaterial = s["glow"]
	glow.set_shader_parameter("prog", _k(1.2, hit_at) + 0.8 * sin(_k(hit_at, hit_at + 0.6) * PI))
	glow.set_shader_parameter("fade", 1.0 - _k(2.8, 3.6))
	var crack: ShaderMaterial = s["crack"]
	crack.set_shader_parameter("prog", _eo(_k(1.5, hit_at)))
	crack.set_shader_parameter("fade", 1.0 - _k(4.0, 5.5))
	(s["pillar"] as CPUParticles3D).emitting = t >= hit_at and t < hit_at + 0.5
	(s["light"] as OmniLight3D).light_energy = 2.0 * _k(1.2, hit_at) + 5.0 * sin(_k(hit_at, hit_at + 0.7) * PI) * float(t < hit_at + 0.7)
	if not is_landed:   # he hops up out of the flames and lands
		hero.visible = t >= hit_at
		var hop := _k(hit_at, hit_at + 0.55)
		hero.position = Vector3(0, -0.6 + 0.6 * hop + 1.8 * sin(hop * PI), 0)
		hero.rotation = Vector3(0, player.cam_yaw + PI + hop * TAU, 0)
		if _at(hit_at + 0.55):
			player.add_shake(0.2)
			hero.play_ability(1)
	if _at(hit_at):
		_burst(target + Vector3(0, 1.5, 0), 3.0, orange, 0.4)
		_ring(target, RADIUS, Color(1.0, 0.5, 0.12, 0.7), 0.5)
		Abilities.ignite_area(get_tree(), target, 4.0)   # a little imp of hot coals: the bushes catch
