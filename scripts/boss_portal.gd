class_name BossPortal
extends Node3D
## The way out once a map's boss has fallen: a standing ring of carved stone about 4.3 m tall on
## a low round dais, a swirling violet vortex inside it, rune light, drifting motes and (on the
## outdoor maps) a pillar of light into the sky so it can be found from anywhere. It rises out of
## the ground (`open()`), then the vortex ignites; walking into it (`contains()`) completes the map
## (BossAftermath pulls the player in and runs the win).
##
## Placement (`find_spot`): each map has a preferred spot (the Desert: on the causeway in front of
## the Sphinx; the Castle: the middle of the keep, in the dining hall; the Caldera: at the foot of
## the dwarves' road, on the basalt beside the great lava pool; the Swamp, the Forest and the
## Graveyard: the clearing / glade / plaza where the run started). From there it spirals out to
## the nearest spot that is flat, dry (no water or lava), clear of props, walls and chests, and
## (indoors) open floor on the walk grid.
##
## The portal is in the "portal" group (the minimap draws it).

signal entered

const RING_C := 2.25        # height of the ring's centre above the dais' foot
const RING_RO := 2.05       # outer radius of the stone ring
const RING_RI := 1.55       # inner radius (the vortex fills it)
const RING_DEPTH := 0.7     # stone thickness, front to back
const STONES := 18
const DAIS_R := 3.3         # the dais: bottom radius...
const DAIS_TOP := 2.5       # ...top radius...
const DAIS_H := 0.28        # ...and height (a gentle ramp, walkable)
const ENTER_HALF := Vector3(1.3, 3.2, 0.9)   # local box (x across, y up, z through) that counts as stepping in
const RISE_TIME := 1.5      # the ring grinds up out of the ground...
const IGNITE_TIME := 1.0    # ...then the vortex blooms
const BEAM_H := 160.0
const CLEAR_R := 3.6        # the spot must be clear of props this far round
const VIOLET := Color(0.62, 0.3, 1.0)

const VORTEX_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform float open = 1.0;
uniform vec3 col_a : source_color = vec3(0.22, 0.05, 0.5);
uniform vec3 col_b : source_color = vec3(0.85, 0.32, 1.0);
uniform vec3 col_c : source_color = vec3(0.45, 0.95, 1.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p) / max(open, 0.001);
	if (r > 1.0) { discard; }
	float a = atan(p.y, p.x);
	float t = TIME;
	float sw = a + 2.6 / (r + 0.22) - t * 1.7;
	float n = noise(vec2(cos(sw) * 2.5 + t * 0.4, sin(sw) * 2.5 + r * 6.0));
	float bands = sin(sw * 3.0 + n * 4.0) * 0.5 + 0.5;
	float fine = sin(sw * 9.0 - r * 10.0 + t * 3.0) * 0.5 + 0.5;
	vec3 c = mix(col_a, col_b, clamp(bands * 0.85 + n * 0.35, 0.0, 1.0));
	c = mix(c, col_c, smoothstep(0.6, 0.12, r) * bands * 0.75);
	c += col_b * fine * 0.25 * smoothstep(0.2, 0.7, r);
	c += vec3(1.0, 0.95, 1.0) * smoothstep(0.42, 0.0, r) * 1.4;   // the bright eye
	c += col_b * smoothstep(0.8, 1.0, r) * 1.6;                    // a hot rim
	ALBEDO = c * 1.5;
	ALPHA = clamp((1.0 - smoothstep(0.93, 1.0, r)) * (0.8 + 0.2 * bands), 0.0, 1.0);
}
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;
uniform float power = 1.0;
uniform float height = 160.0;
uniform vec3 col : source_color = vec3(0.7, 0.45, 1.0);
varying float ly;
void vertex() { ly = VERTEX.y / height + 0.5; }
void fragment() {
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.6);
	float rise = 1.0 - ly;
	float fade = smoothstep(0.0, 0.03, ly) * pow(rise, 1.4);
	float ripple = 0.8 + 0.2 * sin(ly * 60.0 - TIME * 6.0);
	ALBEDO = col * 2.2 * ripple;
	ALPHA = clamp(edge * fade * power * 0.85, 0.0, 1.0);
}
"""

var map := ""
var indoors := false
var opened := 0.0           # 0 -> 1 as it rises and ignites
var _t := -1.0              # time since open() (-1: not opening yet)
var _frame: Node3D          # the ring, the dais and the runes (rises out of the ground)
var _vortex_mat: ShaderMaterial
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _light: OmniLight3D
var _motes: GPUParticles3D
var _swirl: GPUParticles3D
var _hum: AudioStreamPlayer3D
var _sfx_open: AudioStreamPlayer3D
var _body: StaticBody3D
var _fx: FxManager
var _dist := PackedInt32Array()   # indoors: walk-grid steps to the portal (bots find their way)


func _init() -> void:
	add_to_group("portal")


## Build it closed (sunk in the ground); `fx` for the dust as it rises.
func setup(p_map: String, p_fx: FxManager) -> void:
	map = p_map
	indoors = CastleNav.current != null
	_fx = p_fx


func _ready() -> void:
	_frame = Node3D.new()
	add_child(_frame)
	_build_frame()
	_build_vortex()
	_light = OmniLight3D.new()
	_light.light_color = VIOLET
	_light.light_energy = 0.0
	_light.omni_range = 14.0
	_light.position = Vector3(0, RING_C, 1.4)
	add_child(_light)
	_build_particles()
	if not indoors:
		_build_beam()
	_body = StaticBody3D.new()
	for sx in [-1.0, 1.0]:   # the ring's flanks are solid: you go through the middle
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(RING_RO - RING_RI + 0.1, RING_C + 0.8, RING_DEPTH)
		cs.shape = bs
		cs.position = Vector3(sx * (RING_RI + RING_RO) * 0.5, (RING_C + 0.8) * 0.5, 0)
		_body.add_child(cs)
	_frame.add_child(_body)
	_sfx_open = _sound("res://audio/portal/portal_open.wav", 0.0)
	_hum = _sound("res://audio/portal/portal_hum.wav", -8.0)
	if _hum.stream is AudioStreamWAV:
		var w := (_hum.stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		_hum.stream = w
	_frame.position.y = -(RING_C + RING_RO + 0.4)
	_set_open(0.0)


func _sound(path: String, db: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.bus = Settings.SFX_BUS
	a.unit_size = 14.0
	a.max_distance = 90.0
	a.volume_db = db
	a.position.y = RING_C
	if ResourceLoader.exists(path):
		a.stream = load(path)
	add_child(a)
	return a


## Start the opening: the ring grinds up out of the ground, then the vortex ignites.
func open() -> void:
	if _t >= 0.0:
		return
	_t = 0.0
	if _sfx_open.stream:
		_sfx_open.play()


## Open at once (screenshots, tests that don't care about the animation).
func open_now() -> void:
	_t = RISE_TIME + IGNITE_TIME
	_frame.position.y = 0.0
	_set_open(1.0)
	_start_hum()


func is_open() -> bool:
	return opened >= 1.0


func _physics_process(dt: float) -> void:
	if _t < 0.0 or opened >= 1.0:
		return
	_t += dt
	var k := clampf(_t / RISE_TIME, 0.0, 1.0)
	_frame.position.y = -(RING_C + RING_RO + 0.4) * (1.0 - _ease_out(k))
	_frame.position.x = sin(_t * 47.0) * 0.04 * (1.0 - k)   # grinding judder
	if _fx != null and k < 1.0 and fmod(_t, 0.18) < dt:
		var a := randf() * TAU
		_fx.burst(global_position + Vector3(cos(a) * DAIS_R, 0.2, sin(a) * DAIS_R), 1.6, Color(0.55, 0.48, 0.42), 0.5)
	var ig := clampf((_t - RISE_TIME) / IGNITE_TIME, 0.0, 1.0)
	_set_open(ig)
	if ig >= 1.0:
		_frame.position = Vector3.ZERO
		if _fx != null:
			_fx.burst(global_position + Vector3(0, RING_C, 0), 4.0, VIOLET, 0.5)
		_start_hum()


func _process(_dt: float) -> void:
	if opened >= 1.0 and _light != null:   # a slow breathing glow
		_light.light_energy = 3.2 + 0.6 * sin(Time.get_ticks_msec() * 0.003)


static func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)


func _start_hum() -> void:
	if _hum.stream and not _hum.playing:
		_hum.play()


func _set_open(v: float) -> void:
	opened = v
	_vortex_mat.set_shader_parameter("open", maxf(v, 0.001))
	_light.light_energy = 0.4 + 4.0 * v + (3.0 * sin(v * PI) if v > 0.0 and v < 1.0 else 0.0)
	_swirl.emitting = v > 0.05
	_motes.emitting = _t >= 0.0
	if _beam_mat != null:
		_beam_mat.set_shader_parameter("power", v)
		_beam.visible = v > 0.0


## The middle of the vortex (where the player is pulled to), in world space.
func centre() -> Vector3:
	return global_transform * Vector3(0, RING_C, 0)


## Is world point `p` (the player's feet) stepping into the portal?
func contains(p: Vector3) -> bool:
	if not is_open():
		return false
	var l := global_transform.affine_inverse() * p
	return absf(l.x) < ENTER_HALF.x and absf(l.z) < ENTER_HALF.z and l.y > -1.0 and l.y < ENTER_HALF.y


## Which way to walk from `from` to reach the portal: straight at it outdoors, along the walk
## grid indoors (round walls and through doorways). Unit XZ vector.
func way_from(from: Vector3) -> Vector3:
	var direct := Vector3(global_position.x - from.x, 0, global_position.z - from.z)
	var nav := CastleNav.current
	if nav == null or direct.length() < 4.0:
		return direct.normalized()
	if _dist.is_empty():
		_build_dist(nav)
	var c := nav.cell_of(from.x, from.z)
	var best := _dist_at(nav, c)
	var best_c := c
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var q := Vector2i(c.x + dx, c.y + dz)
			var d := _dist_at(nav, q)
			if d >= 0 and (best < 0 or d < best):
				if dx != 0 and dz != 0 and (_dist_at(nav, Vector2i(c.x + dx, c.y)) < 0 or _dist_at(nav, Vector2i(c.x, c.y + dz)) < 0):
					continue   # don't cut a corner
				best = d
				best_c = q
	if best_c == c:
		return direct.normalized()
	var to := nav.cell_center(best_c) - Vector3(from.x, 0, from.z)
	to.y = 0.0
	return to.normalized() if to.length() > 0.01 else direct.normalized()


## Indoors: walk-grid steps from `p` to the portal (-1: cut off). Outdoors: 0.
func steps_from(p: Vector3) -> int:
	var nav := CastleNav.current
	if nav == null:
		return 0
	if _dist.is_empty():
		_build_dist(nav)
	return _dist_at(nav, nav.cell_of(p.x, p.z))


func _dist_at(nav: CastleNav, c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= nav.n or c.y >= nav.n:
		return -1
	return _dist[c.y * nav.n + c.x]


## Breadth-first steps from the portal over the whole walk grid (once; the portal never moves).
func _build_dist(nav: CastleNav) -> void:
	var n := nav.n
	_dist.resize(n * n)
	_dist.fill(-1)
	var start := nav.cell_of(global_position.x, global_position.z)
	var front := global_transform.basis.z
	var queue := PackedInt32Array()
	for k in 3:   # seed in front of and behind the ring (the ring's own cells may be blocked)
		for s in [1.0, -1.0, 0.0]:
			var q := nav.cell_of(global_position.x + front.x * s * (1.0 + k * 2.0), global_position.z + front.z * s * (1.0 + k * 2.0))
			if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and nav.blocked[q.y * n + q.x] == 0 and _dist[q.y * n + q.x] < 0:
				_dist[q.y * n + q.x] = 0
				queue.append(q.y * n + q.x)
	if queue.is_empty() and start.x >= 0 and start.y >= 0 and start.x < n and start.y < n:
		_dist[start.y * n + start.x] = 0
		queue.append(start.y * n + start.x)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % n
		var z := i / n
		var d := _dist[i] + 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var xx: int = x + o.x
			var zz: int = z + o.y
			if xx < 0 or zz < 0 or xx >= n or zz >= n:
				continue
			var j := zz * n + xx
			if _dist[j] < 0 and nav.blocked[j] == 0:
				_dist[j] = d
				queue.append(j)


# ------------------------------------------------------------------ placement

## The preferred spot and facing (yaw: the portal's front, +Z, turned toward where you'd come
## from) for each map, before the clearance search.
static func preferred(p_map: String) -> Dictionary:
	match p_map:
		"desert":   # on the causeway, a few paces in front of the Sphinx's plinth, facing the start
			return {"at": Vector2(DesertBuilder.SPHINX_AT.x, DesertBuilder.SPHINX_AT.y + DesertBuilder.PLINTH.y + 8.0), "yaw": 0.0}
		"castle":   # the middle of the keep (the dining hall), facing the front doors
			return {"at": Vector2(0.0, 0.0), "yaw": 0.0}
		"caldera":   # the foot of the dwarves' road, on the basalt beside the great lava pool
			for p in CalderaBuilder.pools:
				if p["kind"] == "great":
					var c: Vector2 = p["c"]
					return {"at": Vector2(c.x, c.y + float(p["r"]) * 1.25 + CalderaBuilder.BANK + 5.0), "yaw": 0.0}
			return {"at": Vector2(0.0, -12.0), "yaw": 0.0}
		_:   # the Swamp's clearing, the Forest's glade, the Graveyard's plaza: where the run began
			return {"at": Vector2(0.0, -6.0), "yaw": 0.0}


## Where the portal goes on this map: {pos: Vector3, yaw}. `main` gives the world (physics,
## ground, chests). Spirals out from the preferred spot to the first clear one.
static func find_spot(main: Node, p_map: String) -> Dictionary:
	var pref := preferred(p_map)
	var at: Vector2 = pref["at"]
	var yaw: float = pref["yaw"]
	for ring in 25:
		var r := ring * 2.0
		var n := 1 if ring == 0 else 8 + ring * 2
		for k in n:
			var a := TAU * float(k) / float(n) + ring * 0.37
			var q := at + Vector2(cos(a), sin(a)) * r
			if is_clear(main, q):
				return {"pos": Vector3(q.x, main.water.ground_height(q.x, q.y), q.y), "yaw": yaw}
	return {"pos": Vector3(at.x, main.water.ground_height(at.x, at.y), at.y), "yaw": yaw}


## Flat, dry, open ground with nothing standing within CLEAR_R (props, walls, chests, the
## sphinx), inside the arena and (indoors) on open walk-grid floor.
static func is_clear(main: Node, q: Vector2) -> bool:
	var half: float = main.ARENA_HALF - 14.0
	if absf(q.x) > half or absf(q.y) > half:
		return false
	var water: SwampWater = main.water
	if not CalderaBuilder.active and water.near_pool(q.x, q.y, CLEAR_R + 1.0):
		return false
	if CalderaBuilder.active and (CalderaBuilder.near_lava(q.x, q.y, CLEAR_R + 2.0) or CalderaBuilder.on_cone(q.x, q.y, 4.0)):
		return false
	var h0 := water.ground_height(q.x, q.y)
	for k in 8:   # flat enough that the dais sits on it
		var a := TAU * k / 8.0
		if absf(water.ground_height(q.x + cos(a) * DAIS_R, q.y + sin(a) * DAIS_R) - h0) > 0.6:
			return false
	var nav := CastleNav.current
	if nav != null:
		for dz in range(-4, 5, 2):
			for dx in range(-4, 5, 2):
				if nav.is_blocked(q.x + dx, q.y + dz):
					return false
	if main.chests != null:
		for c in main.chests.chests:
			if is_instance_valid(c) and Vector2(c.global_position.x - q.x, c.global_position.z - q.y).length() < CLEAR_R + 3.0:
				return false
	var space: PhysicsDirectSpaceState3D = (main as Node3D).get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CLEAR_R * 2.0, 3.6, CLEAR_R * 2.0)
	params.shape = box
	params.transform = Transform3D(Basis(), Vector3(q.x, h0 + 0.9 + 1.8, q.y))
	params.collide_with_areas = false
	if main.player != null:
		params.exclude = [main.player.get_rid()]
	return space.intersect_shape(params, 1).is_empty()


# ------------------------------------------------------------------ the look

func _build_frame() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7177
	var stone := MeshBuilder.new()
	var rune := MeshBuilder.new()
	var base_col := Color(0.58, 0.55, 0.62)
	# The dais: a low round ramp of stone with a ring of flagstones
	stone.add(MeshBuilder.cyl(DAIS_TOP, DAIS_R, DAIS_H, 28), Transform3D(Basis(), Vector3(0, DAIS_H * 0.5, 0)), base_col.darkened(0.15))
	stone.add(MeshBuilder.cyl(DAIS_TOP - 0.25, DAIS_TOP, 0.06, 28), Transform3D(Basis(), Vector3(0, DAIS_H + 0.03, 0)), base_col.darkened(0.05))
	for k in 12:   # a circle of runes inlaid in the dais
		var a := TAU * k / 12.0
		rune.add(MeshBuilder.box(Vector3(0.32, 0.03, 0.09)), Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0, sin(a)) * (DAIS_TOP - 0.55) + Vector3(0, DAIS_H + 0.05, 0)), VIOLET)
	# Two footing blocks the ring stands in
	for sx in [-1.0, 1.0]:
		stone.add(MeshBuilder.box(Vector3(1.0, 0.7, RING_DEPTH + 0.5)), Transform3D(Basis(), Vector3(sx * (RING_RI + RING_RO) * 0.5, DAIS_H + 0.2, 0)), base_col.darkened(0.25))
	# The ring: wedge-shaped voussoirs with a bigger keystone at the top, each carved with a glowing rune
	var cy := RING_C
	for k in STONES:
		var a0 := TAU * k / STONES + 0.006
		var a1 := TAU * (k + 1) / STONES - 0.006
		var mid := (a0 + a1) * 0.5
		var key := k == STONES / 4   # straight up (angle PI/2 lands on stone STONES/4)
		var ro := RING_RO + (0.22 if key else rng.randf_range(-0.03, 0.05))
		var col := base_col.lerp(Color(0.66, 0.6, 0.7), rng.randf()) * rng.randf_range(0.85, 1.08)
		col.a = 0.0
		stone.add(_wedge(a0, a1, RING_RI, ro, RING_DEPTH + (0.14 if key else 0.0)), Transform3D(Basis(), Vector3(0, cy, 0)), col)
		# runes on both faces
		var rp := Vector3(cos(mid), sin(mid), 0) * (RING_RI + RING_RO) * 0.5 + Vector3(0, cy, 0)
		var rb := Basis(Vector3.BACK, mid - PI * 0.5)
		for face in [1.0, -1.0]:
			var off := Vector3(0, 0, face * (RING_DEPTH * 0.5 + 0.01))
			rune.add(MeshBuilder.box(Vector3(0.07, 0.24, 0.02)), Transform3D(rb, rp + off), VIOLET)
			rune.add(MeshBuilder.box(Vector3(0.18, 0.05, 0.02)), Transform3D(rb, rp + off + rb * Vector3(0, 0.05 if k % 2 else -0.06, 0)), VIOLET)
	# a glowing inner lip round the vortex
	for k in 36:
		var a := TAU * k / 36.0
		rune.add(MeshBuilder.box(Vector3(0.05, TAU * RING_RI / 36.0 * 1.02, RING_DEPTH * 0.6)), Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a), sin(a), 0) * (RING_RI + 0.02) + Vector3(0, cy, 0)), VIOLET.lerp(Color.WHITE, 0.25))
	# two braziers of violet flame flanking the ring
	for sx in [-1.0, 1.0]:
		var bp := Vector3(sx * 2.95, DAIS_H, 0.6)
		stone.add(MeshBuilder.cyl(0.16, 0.22, 1.1, 8), Transform3D(Basis(), bp + Vector3(0, 0.55, 0)), base_col.darkened(0.3))
		stone.add(MeshBuilder.cyl(0.34, 0.18, 0.22, 10), Transform3D(Basis(), bp + Vector3(0, 1.2, 0)), Color(0.2, 0.18, 0.2))
		rune.add(MeshBuilder.sphere(0.2, 8, 5), Transform3D(Basis().scaled(Vector3(1, 0.5, 1)), bp + Vector3(0, 1.3, 0)), VIOLET.lerp(Color.WHITE, 0.4))
		var fl := Abilities._flame_particles(0.35, 0.7, 24)
		fl.position = bp + Vector3(0, 1.35, 0)
		_tint_flame(fl)
		_frame.add_child(fl)
	var mi := MeshInstance3D.new()
	mi.mesh = stone.commit(MeshBuilder.prop_material())
	rune.commit_into(mi.mesh as ArrayMesh, MeshBuilder.glow_material())
	_frame.add_child(mi)


func _tint_flame(p: CPUParticles3D) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.8, 1.0, 1.0))
	g.set_color(1, Color(0.4, 0.08, 0.85, 0.0))
	g.add_point(0.35, Color(0.75, 0.35, 1.0, 0.8))
	p.color_ramp = g


## One voussoir: the ring between angles a0..a1 and radii ri..ro, `depth` thick (flat faces).
static func _wedge(a0: float, a1: float, ri: float, ro: float, depth: float) -> Array:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	var hz := depth * 0.5
	var p := [Vector3(cos(a0) * ri, sin(a0) * ri, 0), Vector3(cos(a1) * ri, sin(a1) * ri, 0),
		Vector3(cos(a1) * ro, sin(a1) * ro, 0), Vector3(cos(a0) * ro, sin(a0) * ro, 0)]
	var quads := []
	quads.append([p[0] + Vector3(0, 0, hz), p[1] + Vector3(0, 0, hz), p[2] + Vector3(0, 0, hz), p[3] + Vector3(0, 0, hz)])   # front
	quads.append([p[3] - Vector3(0, 0, hz), p[2] - Vector3(0, 0, hz), p[1] - Vector3(0, 0, hz), p[0] - Vector3(0, 0, hz)])   # back
	for e in 4:
		var a: Vector3 = p[e]
		var b: Vector3 = p[(e + 1) % 4]
		quads.append([b + Vector3(0, 0, hz), a + Vector3(0, 0, hz), a - Vector3(0, 0, hz), b - Vector3(0, 0, hz)])
	for q in quads:
		var n := ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[2] as Vector3) - (q[0] as Vector3)).normalized()
		var base := v.size()
		for c in q:
			v.append(c)
			nrm.append(-n)
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


func _build_vortex() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(RING_RI * 2.0 + 0.1, RING_RI * 2.0 + 0.1)
	var sh := Shader.new()
	sh.code = VORTEX_SHADER
	_vortex_mat = ShaderMaterial.new()
	_vortex_mat.shader = sh
	q.material = _vortex_mat
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, RING_C, 0)
	_frame.add_child(mi)


func _build_particles() -> void:
	# sparks spiralling in to the vortex
	_swirl = GPUParticles3D.new()
	_swirl.amount = 70
	_swirl.lifetime = 1.4
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 0, 1)
	pm.emission_ring_radius = RING_RO + 0.6
	pm.emission_ring_inner_radius = RING_RI + 0.2
	pm.emission_ring_height = 0.3
	pm.gravity = Vector3.ZERO
	pm.radial_accel_min = -3.5
	pm.radial_accel_max = -2.0
	pm.tangential_accel_min = 2.0
	pm.tangential_accel_max = 3.5
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(0.9, 0.7, 1.0, 0.0))
	g.add_point(0.3, Color(0.85, 0.6, 1.0, 1.0))
	g.set_color(g.get_point_count() - 1, Color(0.5, 0.9, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_swirl.process_material = pm
	_swirl.draw_pass_1 = _spark_mesh(0.07)
	_swirl.position = Vector3(0, RING_C, 0)
	_swirl.emitting = false
	_frame.add_child(_swirl)
	# motes drifting up off the dais
	_motes = GPUParticles3D.new()
	_motes.amount = 40
	_motes.lifetime = 3.0
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm2.emission_ring_axis = Vector3(0, 1, 0)
	pm2.emission_ring_radius = DAIS_R
	pm2.emission_ring_inner_radius = 0.5
	pm2.emission_ring_height = 0.1
	pm2.direction = Vector3(0, 1, 0)
	pm2.spread = 15.0
	pm2.initial_velocity_min = 0.4
	pm2.initial_velocity_max = 1.1
	pm2.gravity = Vector3(0, 0.15, 0)
	pm2.color_ramp = gt
	_motes.process_material = pm2
	_motes.draw_pass_1 = _spark_mesh(0.05)
	_motes.position = Vector3(0, DAIS_H + 0.1, 0)
	_motes.emitting = false
	add_child(_motes)


static func _spark_mesh(s: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(s, s)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.6, 1.3, 2.0)
	q.material = m
	return q


func _build_beam() -> void:
	var c := CylinderMesh.new()
	c.top_radius = 1.1
	c.bottom_radius = 0.7
	c.height = BEAM_H
	c.radial_segments = 16
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = sh
	_beam_mat.set_shader_parameter("height", BEAM_H)
	c.material = _beam_mat
	_beam = MeshInstance3D.new()
	_beam.mesh = c
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3(0, RING_C + RING_RO + BEAM_H * 0.5 - 0.5, 0)
	_beam.visible = false
	add_child(_beam)
