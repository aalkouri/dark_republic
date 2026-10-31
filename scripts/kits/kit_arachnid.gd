class_name KitArachnid
extends KitPart
## The Arachnid (built in code: ArachnidBody, the Castle boss's spider at player size)
##   1  Web Trap   25 s  shoots a 10 m web where you aim (up to 25 m): for 4 s everything in it
##                       is stuck fast (the boss only slowed by half), and stuck enemies take
##                       +30% damage from poison
##   2  Brood      50 s  an egg sac hatches 12 spiderlings that leap onto enemies for 15 s
##                       (bosses in range first); each deals 20 damage per second and keeps
##                       poisoning what it clings to (the Venom Spit poison, stacking)
##   3  Cocoon    120 s  every enemy within 25 m is wrapped in silk for 5 s (can't move or
##                       attack) and takes 25% of its max HP; you heal 1% of max HP per cocoon.
##                       The boss is only slowed.
## Levels scale: Web Trap's poison bonus, the spiderlings' damage, Cocoon's damage.

const WEB_RANGE := 25.0
const WEB_RADIUS := 10.0
const WEB_TIME := 4.0
const WEB_BONUS := 0.3               # +30% poison damage to stuck enemies
const WEB_FLIGHT := 0.35
const BROOD_COUNT := 12
const BROOD_TIME := 15.0
const BROOD_DPS := 20.0
const BROOD_HATCH := 0.5
const BROOD_SEEK := 14.0             # they leap onto enemies this close...
const BROOD_LEASH := 22.0            # ...not too far from you
const BROOD_LEAP := 0.35             # seconds in the air
const BROOD_RUN := 9.0               # scuttling speed with nothing to jump on
const BROOD_POISON_EVERY := 1.0
const COCOON_RADIUS := 25.0
const COCOON_TIME := 5.0
const COCOON_FRAC := 0.25            # of max HP, over the 5 s
const COCOON_HEAL := 0.01            # of your max HP per cocoon
const COCOON_BOSS_SLOW := 0.4
const SILK := Color(0.95, 0.94, 0.9)

const WEB_SHADER := """
shader_type spatial;
render_mode unshaded, world_vertex_coords, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float h_origin = 0.0;
uniform float h_size = 1.0;
uniform float has_height = 0.0;
uniform float lift = 0.1;
uniform float spokes = 14.0;
uniform float turns = 10.0;
varying vec2 local_uv;

void vertex() {
	local_uv = UV;
	if (has_height > 0.5) {
		vec2 uv = (VERTEX.xz - h_origin + 0.5) / h_size;
		VERTEX.y = texture(height_tex, uv).r + lift;
	}
}

void fragment() {
	vec2 q = (local_uv - 0.5) * 2.0;
	float d = length(q);
	if (d > 1.0) { discard; }
	float a = atan(q.y, q.x);
	float seg = a / 6.28318 * spokes;
	float f = fract(seg) - 0.5;
	float w = 0.0055 + 0.0035 * d;
	// Radial threads
	float spoke = 1.0 - smoothstep(w * 0.5, w, abs(f) * 6.28318 / spokes * d);
	// The sticky spiral, sagging toward the middle between threads
	float sag = d * (1.0 + 0.05 * (1.0 - 4.0 * f * f));
	float r = sag * turns - seg / spokes;
	float ring = (1.0 - smoothstep(w * 0.5, w, abs(fract(r) - 0.5) / turns)) * step(0.07, d);
	float hub = 1.0 - smoothstep(0.03, 0.05, d);
	float line = max(max(spoke, ring), hub);
	float alpha = color.a * line * (1.0 - smoothstep(0.96, 1.0, d));
	if (alpha < 0.01) { discard; }
	ALBEDO = color.rgb;
	ALPHA = alpha;
}
"""

const COCOON_SHADER := """
shader_type spatial;
uniform vec4 tint : source_color = vec4(0.95, 0.94, 0.9, 1.0);
void fragment() {
	// Silk wound round and round: criss-crossing grooves
	float b1 = abs(sin((UV.y * 28.0 + UV.x * 9.0) * 3.14159));
	float b2 = abs(sin((UV.y * 24.0 - UV.x * 7.0) * 3.14159));
	float g = smoothstep(0.0, 0.35, min(b1, b2));
	ALBEDO = tint.rgb * (0.62 + 0.38 * g);
	ROUGHNESS = 0.7;
	EMISSION = tint.rgb * 0.12;
}
"""

static var _web_sh: Shader
static var _ling_mesh: Mesh

# Web Trap
var _web: GroundDisc
var _web_at := Vector3.ZERO
var _web_t := 0.0
var _web_tick := 0.0
var _glob: Node3D
# Brood
var _sac: Node3D
var _hatch_t := -1.0
var _brood_t := 0.0
var _lings: Array = []               # {node, pos, state, uid, row, from, t, off, tick, ptick, yaw}
var _ling_mat: StandardMaterial3D
# Cocoon
var _cocoon_t := 0.0
var _cocoon_tick := 0.0
var _wrapped := {}                   # uid -> true
var _cocoons: MultiMeshInstance3D
# Tests
var stuck := 0
var hatched := 0
var leaps := 0
var ling_damage := 0.0
var wrapped := 0
var boss_slowed := 0


func _exit_tree() -> void:
	for l in _lings:
		if is_instance_valid(l["node"]):
			l["node"].queue_free()


func cast(i: int) -> void:
	match i:
		0: _web_trap()
		1: _brood()
		2: _cocoon()


func active(name: String) -> bool:
	match name:
		"web": return _web_t > 0.0 or is_instance_valid(_glob)
		"brood": return _brood_t > 0.0 or _hatch_t >= 0.0
		"cocoon": return _cocoon_t > 0.0
	return false


func tick(dt: float) -> void:
	_tick_web(dt)
	_tick_brood(dt)
	_tick_cocoon(dt)


## Live spiderlings: [node, position] (tests).
func lings() -> Array:
	var out := []
	for l in _lings:
		out.append([l["node"], l["pos"], l["state"], l["uid"]])
	return out


func _stacks() -> int:
	return k.weapons.venom_stacks() if k.weapons != null else WeaponSystem.VENOM_STACKS


## Row of the live enemy with uid `u`, trying the cached row first.
func _row(u: int, guess: int) -> int:
	if guess >= 0 and guess < enemies.count and enemies.uid[guess] == u and not enemies.dead[guess]:
		return guess
	return enemies.index_of(u)


# ------------------------------------------------------------------ Web Trap

func _web_trap() -> void:
	play("web_trap")
	var to := aim_point(WEB_RANGE)
	var from := player.model.staff_tip() if player.model != null else chest()
	# A ball of silk arcs out and bursts into the web
	if is_instance_valid(_glob):
		_glob.queue_free()
	var g := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	g.mesh = sm
	g.material_override = glow_mat(Color(SILK, 0.9), false)
	_glob = g
	spawn(g, from)
	var fly := func(f: float) -> void:
		g.global_position = from.lerp(to, f) + Vector3(0, sin(f * PI) * 2.5, 0)
		g.scale = Vector3.ONE * (1.0 + f)
	var land := func() -> void:
		g.queue_free()
		_land_web(to)
	var tw := g.create_tween()
	tw.tween_method(fly, 0.0, 1.0, WEB_FLIGHT)
	tw.tween_callback(land)


func _land_web(at: Vector3) -> void:
	_web_at = at
	_web_t = WEB_TIME
	_web_tick = 0.0
	enemies.web_poison_bonus = WEB_BONUS * pw(0)
	if is_instance_valid(_web):
		_web.queue_free()
	_web = GroundDisc.create(WEB_RADIUS, Color(SILK, 0.7))
	if _web_sh == null:
		_web_sh = Shader.new()
		_web_sh.code = WEB_SHADER
	var m: ShaderMaterial = _web._mat
	m.shader = _web_sh
	var gnd := SwampWater.current
	if gnd != null and gnd.height_texture != null:
		m.set_shader_parameter("height_tex", gnd.height_texture)
		m.set_shader_parameter("h_origin", gnd.horigin)
		m.set_shader_parameter("h_size", float(gnd.hsize))
		m.set_shader_parameter("has_height", 1.0)
	m.set_shader_parameter("color", Color(SILK, 0.7))
	m.set_shader_parameter("lift", 0.12)
	spawn(_web, at)
	_web.rotation.y = randf() * TAU
	_web.scale = Vector3(WEB_RADIUS * 0.2, 1.0, WEB_RADIUS * 0.2)
	_web.create_tween().tween_property(_web, "scale", Vector3(WEB_RADIUS, 1.0, WEB_RADIUS), 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	ring(at, WEB_RADIUS, Color(SILK, 0.6), 0.3)
	if fx:
		fx.burst(at + Vector3(0, 0.4, 0), 1.2, SILK, 0.3)
	_stick()


func _stick() -> void:
	for i in near(_web_at, WEB_RADIUS):
		if enemies.web_t[i] <= 0.0:
			stuck += 1
		enemies.web(i, _web_t)


func _tick_web(dt: float) -> void:
	if _web_t <= 0.0:
		return
	_web_t -= dt
	_web_tick -= dt
	if _web_tick <= 0.0 and _web_t > 0.0:   # anything that wanders in sticks too
		_web_tick = 0.1
		_stick()
	if _web_t <= 0.0 and is_instance_valid(_web):
		var w := _web
		_web = null
		var tw := w.create_tween()
		tw.tween_property(w, "alpha", 0.0, 0.4)
		tw.tween_callback(w.queue_free)


# ------------------------------------------------------------------ Brood

func _brood() -> void:
	play("brood")
	_clear_lings()
	var at := ground(feet() + aim_dir() * 1.6)
	if is_instance_valid(_sac):
		_sac.queue_free()
	_sac = Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.82, 0.7)
	mat.roughness = 0.45
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.32, 0.18)
	for e in [[Vector3(0, 0.32, 0), 0.34], [Vector3(0.18, 0.22, 0.1), 0.24], [Vector3(-0.16, 0.24, -0.08), 0.26], [Vector3(0.02, 0.55, 0.05), 0.2]]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r: float = e[1]
		sm.radius = r
		sm.height = r * 2.0
		sm.material = mat
		mi.mesh = sm
		mi.position = e[0]
		_sac.add_child(mi)
	spawn(_sac, at)
	_sac.scale = Vector3.ONE * 0.2
	var tw := _sac.create_tween()
	tw.tween_property(_sac, "scale", Vector3.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_sac, "scale", Vector3(1.15, 0.9, 1.15), 0.12)
	tw.tween_property(_sac, "scale", Vector3(0.95, 1.12, 0.95), 0.12)
	_hatch_t = BROOD_HATCH
	_brood_t = 0.0


func _hatch() -> void:
	_hatch_t = -1.0
	var at := _sac.global_position if is_instance_valid(_sac) else feet()
	if is_instance_valid(_sac):
		_sac.queue_free()
	if fx:
		fx.burst(at + Vector3(0, 0.4, 0), 1.4, Color(0.85, 0.82, 0.7), 0.3)
	if _ling_mesh == null:
		_ling_mesh = _make_ling_mesh()
	if _ling_mat == null:
		_ling_mat = StandardMaterial3D.new()
		_ling_mat.albedo_color = Color(0.14, 0.1, 0.17)
		_ling_mat.metallic = 0.3
		_ling_mat.roughness = 0.35
		_ling_mat.emission_enabled = true
		_ling_mat.emission = Color(0.2, 0.45, 0.06)
		_ling_mat.emission_energy_multiplier = 0.6
	for n in BROOD_COUNT:
		var mi := MeshInstance3D.new()
		mi.mesh = _ling_mesh
		mi.material_override = _ling_mat
		var a := TAU * n / BROOD_COUNT
		var p := at + Vector3(cos(a), 0, sin(a)) * 0.6
		spawn(mi, p)
		_lings.append({"node": mi, "pos": p, "state": "seek", "uid": 0, "row": -1, "from": p, "t": 0.0,
			"off": Vector3.ZERO, "tick": randf() * 0.25, "ptick": 0.0, "yaw": a, "phase": randf() * TAU})
		hatched += 1
	_brood_t = BROOD_TIME


func _clear_lings() -> void:
	for l in _lings:
		var nd: Node3D = l["node"]
		if is_instance_valid(nd):
			if fx:
				fx.burst(nd.global_position, 0.4, Color(0.4, 0.8, 0.2), 0.25)
			nd.queue_free()
	_lings.clear()


func _tick_brood(dt: float) -> void:
	if _hatch_t >= 0.0:
		_hatch_t -= dt
		if _hatch_t < 0.0:
			_hatch()
		return
	if _brood_t <= 0.0:
		return
	_brood_t -= dt
	if _brood_t <= 0.0:
		_clear_lings()
		return
	var home := feet()
	var claimed := {}
	for l in _lings:
		if l["state"] == "cling" or l["state"] == "leap":
			claimed[l["uid"]] = int(claimed.get(l["uid"], 0)) + 1
	for n in _lings.size():
		var l: Dictionary = _lings[n]
		var p: Vector3 = l["pos"]
		var st: String = l["state"]
		if st == "leap" or st == "cling":
			var row := _row(l["uid"], l["row"])
			l["row"] = row
			if row < 0:
				st = "seek"
			else:
				var top: Vector3 = enemies.pos[row] + Vector3(0, EnemyManager.GOBLIN_HEIGHT * enemies.t_scale[enemies.typ[row]] * enemies.sz[row] * 0.8, 0) + l["off"]
				if st == "leap":
					l["t"] = float(l["t"]) + dt / BROOD_LEAP
					var f := minf(float(l["t"]), 1.0)
					p = (l["from"] as Vector3).lerp(top, f) + Vector3(0, sin(f * PI) * 1.4, 0)
					if f >= 1.0:
						st = "cling"
						l["ptick"] = 0.0
				else:
					p = top
					_bite(l, row, dt)
		if st == "seek":
			var prey := _pick(p, claimed)
			if prey >= 0:
				l["uid"] = enemies.uid[prey]
				l["row"] = prey
				l["from"] = p
				l["t"] = 0.0
				l["off"] = Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
				claimed[l["uid"]] = int(claimed.get(l["uid"], 0)) + 1
				st = "leap"
				leaps += 1
			else:   # nothing in reach: scuttle back to you
				var goal := home + Vector3(cos(l["yaw"]), 0, sin(l["yaw"])) * 1.8
				var to := goal - p
				to.y = 0.0
				if to.length() > 0.3:
					p += to.normalized() * minf(BROOD_RUN * dt, to.length())
				if Engine.get_physics_frames() % 6 == n % 6:
					p.y = ground(p).y
		l["state"] = st
		var moved: Vector3 = p - (l["pos"] as Vector3)
		moved.y = 0.0
		if moved.length() > 0.01:
			l["yaw"] = atan2(moved.x, moved.z)
		l["pos"] = p
		var nd: Node3D = l["node"]
		l["phase"] = float(l["phase"]) + dt * (22.0 if st != "cling" else 30.0)
		var wig := 0.12 * sin(float(l["phase"]))
		nd.global_position = p
		nd.rotation = Vector3(0.0, float(l["yaw"]) + PI + wig, wig * 0.5)


## The enemy this spiderling should jump on: the nearest (a boss in range first), preferring
## ones the others haven't already got.
func _pick(p: Vector3, claimed: Dictionary) -> int:
	var near_ := enemies.nearest_k(p + Vector3(0, 0.5, 0), BROOD_SEEK, 6)
	var best := -1
	for i in near_:
		if enemies.pos[i].distance_to(feet()) > BROOD_LEASH:
			continue
		if enemies.is_boss(i):
			return i
		if best < 0:
			best = i
		if int(claimed.get(enemies.uid[i], 0)) == 0:
			return i
	return best


## Chewing on its prey: 20 damage a second, and a fresh stack of poison every second.
func _bite(l: Dictionary, row: int, dt: float) -> void:
	l["tick"] = float(l["tick"]) - dt
	if l["tick"] <= 0.0:
		l["tick"] = 0.25
		var d := BROOD_DPS * 0.25 * pw(1) * dmg()
		ling_damage += d
		enemies.dot_damage(row, d)
	l["ptick"] = float(l["ptick"]) - dt
	if l["ptick"] <= 0.0 and not enemies.dead[row]:
		l["ptick"] = BROOD_POISON_EVERY
		enemies.poison(row, WeaponSystem.VENOM_FRAC, WeaponSystem.VENOM_TIME, _stacks())


## One spiderling: a little round body and head on eight bent legs, about 0.5 m across.
static func _make_ling_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ab := SphereMesh.new()
	ab.radius = 0.12
	ab.height = 0.24
	ab.radial_segments = 10
	ab.rings = 5
	st.append_from(ab, 0, Transform3D(Basis.from_scale(Vector3(1.0, 0.85, 1.2)), Vector3(0, 0.17, 0.13)))
	var hd := SphereMesh.new()
	hd.radius = 0.08
	hd.height = 0.16
	hd.radial_segments = 8
	hd.rings = 4
	st.append_from(hd, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.14, -0.06)))
	var seg := BoxMesh.new()
	seg.size = Vector3(0.022, 0.022, 1.0)
	for s in [-1.0, 1.0]:
		for k2 in 4:
			var z := -0.1 + 0.07 * k2
			var hip := Vector3(0.05 * s, 0.14, z)
			var knee := Vector3(0.17 * s, 0.26, z * 1.7)
			var foot := Vector3(0.27 * s, 0.0, z * 2.2)
			for pair in [[hip, knee], [knee, foot]]:
				var a: Vector3 = pair[0]
				var b: Vector3 = pair[1]
				var v := b - a
				var bs := Basis.looking_at(v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.95 else Vector3.FORWARD)
				bs = Basis(bs.x, bs.y, bs.z * v.length())
				st.append_from(seg, 0, Transform3D(bs, (a + b) * 0.5))
	return st.commit()


# ------------------------------------------------------------------ Cocoon

func _cocoon() -> void:
	play("cocoon")
	var at := feet()
	var n := 0
	_wrapped.clear()
	for i in near(at, COCOON_RADIUS):
		if enemies.is_boss(i):   # too big to wrap: only slowed
			enemies.slow(i, COCOON_BOSS_SLOW, COCOON_TIME)
			boss_slowed += 1
			continue
		enemies.stun(i, COCOON_TIME)
		_wrapped[enemies.uid[i]] = true
		n += 1
		if n <= 40:   # silk lashing out to them
			var to := enemies.center_of(i) - chest()
			mote(chest(), to * 2.2, 0.45, SILK, 0.12)
	wrapped += n
	k.heal_pct(COCOON_HEAL * n)
	_cocoon_t = COCOON_TIME
	_cocoon_tick = 0.0
	ring(at, COCOON_RADIUS, Color(SILK, 0.7), 0.5)
	ring(at, COCOON_RADIUS * 0.5, Color(SILK, 0.5), 0.35)
	if not is_instance_valid(_cocoons):
		_cocoons = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var cm := SphereMesh.new()
		cm.radius = 0.5
		cm.height = 1.0
		cm.radial_segments = 12
		cm.rings = 8
		var sh := Shader.new()
		sh.code = COCOON_SHADER
		var sm := ShaderMaterial.new()
		sm.shader = sh
		cm.material = sm
		mm.mesh = cm
		_cocoons.multimesh = mm
		_cocoons.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 100, 400))
		spawn(_cocoons, Vector3.ZERO)
	_cocoons.multimesh.instance_count = maxi(1, n)
	_cocoons.multimesh.visible_instance_count = 0
	_cocoons.visible = true
	_place_cocoons(0.0)


## Wrapped enemies' rows, in one pass over the crowd: uid -> row.
func _wrapped_rows() -> Dictionary:
	var out := {}
	for i in enemies.count:
		if not enemies.dead[i] and _wrapped.has(enemies.uid[i]):
			out[enemies.uid[i]] = i
	return out


func _place_cocoons(t: float) -> void:
	var rows := _wrapped_rows()
	var mm := _cocoons.multimesh
	var grow := clampf(t / 0.25, 0.15, 1.0)
	var k2 := 0
	for u in rows:
		if k2 >= mm.instance_count:
			break
		var i: int = rows[u]
		var h := EnemyManager.GOBLIN_HEIGHT * enemies.t_scale[enemies.typ[i]] * enemies.sz[i] * 1.15
		var w := h * 0.55
		var b := Basis.from_scale(Vector3(w, h, w) * grow).rotated(Vector3.UP, float(u) * 1.7)
		mm.set_instance_transform(k2, Transform3D(b, enemies.pos[i] + Vector3(0, h * 0.5, 0)))
		k2 += 1
	mm.visible_instance_count = k2


func _tick_cocoon(dt: float) -> void:
	if _cocoon_t <= 0.0:
		return
	_cocoon_t -= dt
	_cocoon_tick -= dt
	if _cocoon_tick <= 0.0:
		_cocoon_tick = 0.25
		var rows := _wrapped_rows()
		for u in rows:
			var i: int = rows[u]
			enemies.stun(i, minf(0.3, maxf(_cocoon_t, 0.0)))
			enemies.dot_damage(i, enemies.hp_max[i] * COCOON_FRAC * pw(2) / COCOON_TIME * 0.25 * enemies.pct_scale(i))
	if is_instance_valid(_cocoons):
		_place_cocoons(COCOON_TIME - _cocoon_t)
	if _cocoon_t <= 0.0:
		# The silk splits and falls away
		var rows := _wrapped_rows()
		var shown := 0
		for u in rows:
			shown += 1
			if shown > 30:
				break
			var i: int = rows[u]
			mote(enemies.center_of(i), Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)), 0.5, SILK, 0.15)
		_wrapped.clear()
		if is_instance_valid(_cocoons):
			_cocoons.visible = false
