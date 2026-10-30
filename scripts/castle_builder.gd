class_name CastleBuilder
extends RefCounted
## The Castle: an enclosed, torch-lit keep on the same 440 m footprint as the outdoor maps.
## Mostly vast open halls joined by wide archways, with just two short, narrow corridors.
##
##   z = +220 (south)  great front doors (you walk in; they slam shut behind you)
##   Great Hall        x -100..100, z 60..220   two rows of columns, braziers, a long runner
##   Dining Hall       x -60..60,  z -110..60   a long table laid with a feast (CastleFeast)
##   Galleries         x +-(60..100), z -110..60 flanking the dining hall
##   Throne Room       x -100..100, z -220..-110 the throne on a dais
##   West wing         Barracks (z 20..220) and Armory (z -220..20)
##   East wing         Library (z 20..220) and Chapel (z -220..20)
##   Corridors         two 8 m wide, 30 m long passages: Armory <-> Throne Room <-> Chapel
##
## Same counts as the outdoor maps: 180 standing props (columns, knight statues, suits of
## armour, candelabras, weapon racks), 72 lying props (benches, toppled columns, crates,
## barrels, bookcases), 24 landmarks (the throne and braziers). No pools: the floor is flat.
## Goblins path around everything with CastleNav.

const CEILING := 24.0
const WALL_T := 2.0
const ARCH_H := 14.0            # doorway height; the wall continues above as a lintel
const DOOR_W := 12.0            # the front doorway (two 6 m leaves)
const PORCH := Vector3(0, 0, 232)   # where a run starts, outside the doors
const INSIDE := Vector3(0, 0, 204)  # where the walk-in ends
const STANDING := 180
const LYING := 72
const LANDMARKS := 24
const SHRINE_SITES := 14
const TORCH_STEP := 16.0        # metres between wall torches
const TORCH_LIGHT_EVERY := 2    # every 2nd torch has live flames and casts light

# Interior walls: [axis ("x" = runs along x at fixed z), fixed coordinate, from, to, openings [[centre, width]...]]
const WALLS := [
	["x", 60.0, -100.0, 100.0, [[0.0, 30.0], [-80.0, 20.0], [80.0, 20.0]]],      # Great Hall | Dining + galleries
	["x", -110.0, -100.0, 100.0, [[0.0, 24.0], [-80.0, 16.0], [80.0, 16.0]]],    # Dining + galleries | Throne Room
	["z", -60.0, -110.0, 60.0, [[-25.0, 24.0]]],                                 # west gallery | Dining
	["z", 60.0, -110.0, 60.0, [[-25.0, 24.0]]],                                  # Dining | east gallery
	["z", -100.0, -220.0, 220.0, [[150.0, 30.0], [-25.0, 20.0], [-165.0, 8.0]]], # centre | west wing
	["z", 100.0, -220.0, 220.0, [[150.0, 30.0], [-25.0, 20.0], [-165.0, 8.0]]],  # centre | east wing
	["x", 20.0, -220.0, -100.0, [[-160.0, 30.0]]],                               # Barracks | Armory
	["x", 20.0, 100.0, 220.0, [[160.0, 30.0]]],                                  # Library | Chapel
]
# Solid masonry leaving the two narrow corridors (z = -165, 8 m wide)
const BLOCKS := [
	[-130.0, -200.0, -100.0, -169.0], [-130.0, -161.0, -100.0, -130.0],
	[100.0, -200.0, 130.0, -169.0], [100.0, -161.0, 130.0, -130.0],
]
# Rooms, for placing props: [name, x0, z0, x1, z1]
const ROOMS := [
	["great_hall", -100.0, 60.0, 100.0, 220.0],
	["dining", -60.0, -110.0, 60.0, 60.0],
	["gallery_w", -100.0, -110.0, -60.0, 60.0],
	["gallery_e", 60.0, -110.0, 100.0, 60.0],
	["throne", -100.0, -220.0, 100.0, -110.0],
	["barracks", -220.0, 20.0, -100.0, 220.0],
	["armory", -220.0, -220.0, -100.0, 20.0],
	["library", 100.0, 20.0, 220.0, 220.0],
	["chapel", 100.0, -220.0, 220.0, 20.0],
]
const TABLE := [-1.8, -42.75, 1.8, -7.25]   # the dining table top (x0, z0, x1, z1): 35.5 m, mid-hall
const TABLE_H := 0.95

const STONE := Color(0.36, 0.33, 0.31, 0.0)
const DARK_STONE := Color(0.22, 0.2, 0.19, 0.0)
const WOOD := Color(0.3, 0.19, 0.1, 0.0)
const DARK_WOOD := Color(0.19, 0.12, 0.07, 0.0)
const IRON := Color(0.2, 0.2, 0.22, 0.0)
const STEEL := Color(0.55, 0.56, 0.6, 0.0)
const GOLD := Color(0.75, 0.56, 0.2, 0.0)
const RED_CLOTH := Color(0.42, 0.06, 0.07, 0.6)
const FLAME := Color(1.0, 0.55, 0.15, 0.0)

const FLOOR_SHADER := """
shader_type spatial;
uniform vec3 stone_a : source_color = vec3(0.3, 0.28, 0.26);
uniform vec3 stone_b : source_color = vec3(0.22, 0.2, 0.19);
uniform vec3 mortar : source_color = vec3(0.09, 0.08, 0.08);
uniform float tile = 3.0;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// Running-bond flagstones (each row offset by half a stone), worn and stained
	vec2 p = wpos.xz / tile;
	p.x += 0.5 * mod(floor(p.y), 2.0);
	vec2 id = floor(p);
	vec2 f = fract(p);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float line = smoothstep(0.015, 0.045, edge);
	float h = hash(id);
	vec3 col = mix(stone_a, stone_b, h);
	float n = noise(wpos.xz * 1.3) * 0.6 + noise(wpos.xz * 6.0) * 0.4;
	col *= 0.78 + 0.35 * n;
	col = mix(mortar, col, line);
	ALBEDO = col;
	ROUGHNESS = mix(0.6, 0.95, n);
	SPECULAR = 0.35;
}
"""

const WALL_SHADER := """
shader_type spatial;
uniform vec3 stone_a : source_color = vec3(0.34, 0.31, 0.29);
uniform vec3 stone_b : source_color = vec3(0.25, 0.23, 0.22);
uniform vec3 mortar : source_color = vec3(0.1, 0.09, 0.09);
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	// Ashlar blocks 2.4 x 1.2 m on vertical faces; plain stone on tops and bottoms
	vec2 uv = abs(wnrm.x) > abs(wnrm.z) ? wpos.zy : wpos.xy;
	vec2 p = uv / vec2(2.4, 1.2);
	p.x += 0.5 * mod(floor(p.y), 2.0);
	vec2 id = floor(p);
	vec2 f = fract(p);
	float edge = min(min(f.x, 1.0 - f.x) * 2.4, min(f.y, 1.0 - f.y) * 1.2);
	float line = smoothstep(0.03, 0.07, edge);
	vec3 col = mix(stone_a, stone_b, hash(id));
	col *= 0.85 + 0.25 * hash(id * 3.7 + 1.3);
	if (abs(wnrm.y) > 0.5) { line = 1.0; }
	ALBEDO = mix(mortar, col, line);
	ROUGHNESS = 0.92;
}
"""


static func build(parent: Node3D, rng: RandomNumberGenerator, half: float) -> SwampWater:
	var nav := CastleNav.new(half)
	CastleNav.current = nav
	_environment(parent)
	var mats := _materials()
	_floor_and_roof(parent, half, mats)
	_walls(parent, half, nav, mats)
	var doors := CastleDoors.new()
	doors.position = Vector3(0, 0, half)
	parent.add_child(doors)
	_porch(parent, half, mats)
	_rugs(parent)

	# The dining table and its feast
	var feast := CastleFeast.new()
	feast.build(rng, TABLE, TABLE_H)
	parent.add_child(feast)
	nav.block_rect(TABLE[0] - 1.6, TABLE[1] - 0.4, TABLE[2] + 1.6, TABLE[3] + 0.4)   # table + benches

	var placed: Array[Vector3] = []
	_structured(parent, rng, nav, placed)
	var sites := _shrine_sites(rng, nav, placed)
	_scatter(parent, rng, nav, placed, sites)
	_wall_decor(parent, rng, half)

	var ground := SwampWater.new()
	ground.build_flat(half, sites)
	return ground


# ------------------------------------------------------------------ look

static func _environment(parent: Node3D) -> void:
	# Night sky: only ever seen through the open front doors
	var sh := Shader.new()
	sh.code = WorldBuilder.SKY_SHADER
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("night", 1.0)
	sky_mat.set_shader_parameter("top_color", Color(0.012, 0.018, 0.045))
	sky_mat.set_shader_parameter("horizon_color", Color(0.05, 0.075, 0.11))
	sky_mat.set_shader_parameter("ground_color", Color(0.02, 0.025, 0.03))
	sky_mat.set_shader_parameter("cloud_dark", Color(0.04, 0.05, 0.08))
	sky_mat.set_shader_parameter("cloud_light", Color(0.22, 0.26, 0.34))
	sky_mat.set_shader_parameter("body_color", Color(0.86, 0.9, 1.0))
	sky_mat.set_shader_parameter("coverage", 0.25)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_hdr_luminance_cap = 4.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.43, 0.34)
	env.ambient_light_energy = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.14, 0.1, 0.07)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	# Moonlight on the porch outside (a directional light would light the whole keep through
	# the roof beyond its shadow distance, so it's a wide spot instead)
	var moon := SpotLight3D.new()
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 3.0
	moon.spot_range = 60.0
	moon.spot_angle = 35.0
	moon.position = Vector3(10, 40, 250)
	moon.basis = Basis.looking_at(Vector3(0, 0, 228) - moon.position, Vector3.UP)
	parent.add_child(moon)


static func _materials() -> Dictionary:
	var fsh := Shader.new()
	fsh.code = FLOOR_SHADER
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = fsh
	var wsh := Shader.new()
	wsh.code = WALL_SHADER
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = wsh
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.08, 0.065, 0.055)
	roof_mat.roughness = 1.0
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(0.17, 0.11, 0.06)
	beam_mat.roughness = 0.9
	return {"floor": floor_mat, "wall": wall_mat, "roof": roof_mat, "beam": beam_mat}


static func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material, solid := true) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if not solid:
		mi.position = center
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.position = center
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.add_child(mi)
	parent.add_child(body)
	return body


static func _floor_and_roof(parent: Node3D, half: float, mats: Dictionary) -> void:
	_box(parent, Vector3(0, -1.0, 0), Vector3(half * 2.0 + 8.0, 2.0, half * 2.0 + 8.0), mats["floor"])
	_box(parent, Vector3(0, CEILING + 1.0, 0), Vector3(half * 2.0 + 8.0, 2.0, half * 2.0 + 8.0), mats["roof"])
	# Heavy roof beams every 20 m, both ways
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var beam := BoxMesh.new()
	beam.size = Vector3(1.4, 1.8, half * 2.0)
	beam.material = mats["beam"]
	mm.mesh = beam
	var xforms: Array[Transform3D] = []
	var k := -half + 10.0
	while k < half:
		xforms.append(Transform3D(Basis(), Vector3(k, CEILING - 0.9, 0)))
		xforms.append(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, CEILING - 2.4, k)))
		k += 20.0
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


static func _walls(parent: Node3D, half: float, nav: CastleNav, mats: Dictionary) -> void:
	var wall: Material = mats["wall"]
	var t := WALL_T
	# Outer walls (the south one has the front doorway)
	_wall_run(parent, nav, wall, "x", -half - t * 0.5, -half - t, half + t, [])
	_wall_run(parent, nav, wall, "x", half + t * 0.5, -half - t, half + t, [[0.0, DOOR_W]])
	_wall_run(parent, nav, wall, "z", -half - t * 0.5, -half - t, half + t, [])
	_wall_run(parent, nav, wall, "z", half + t * 0.5, -half - t, half + t, [])
	nav.block_rect(-DOOR_W * 0.5, half - 1.0, DOOR_W * 0.5, half + 4.0)   # the doors close; nothing walks out
	for w in WALLS:
		_wall_run(parent, nav, wall, w[0], w[1], w[2], w[3], w[4])
	for b in BLOCKS:
		var size := Vector3(b[2] - b[0], CEILING, b[3] - b[1])
		_box(parent, Vector3((b[0] + b[2]) * 0.5, CEILING * 0.5, (b[1] + b[3]) * 0.5), size, wall)
		nav.block_rect(b[0], b[1], b[2], b[3], 0.6)


## One straight wall with archways cut in it: solid pieces between the openings, and a lintel
## over each opening from ARCH_H up to the ceiling.
static func _wall_run(parent: Node3D, nav: CastleNav, mat: Material, axis: String, fixed: float, from: float, to: float, openings: Array) -> void:
	var cuts := []
	for o in openings:
		cuts.append([o[0] - o[1] * 0.5, o[0] + o[1] * 0.5])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var pieces := []
	var at := from
	for c in cuts:
		if c[0] > at:
			pieces.append([at, c[0]])
		at = maxf(at, c[1])
	if at < to:
		pieces.append([at, to])
	for p in pieces:
		var len: float = p[1] - p[0]
		var mid: float = (p[0] + p[1]) * 0.5
		if axis == "x":
			_box(parent, Vector3(mid, CEILING * 0.5, fixed), Vector3(len, CEILING, WALL_T), mat)
			nav.block_rect(p[0], fixed - WALL_T * 0.5, p[1], fixed + WALL_T * 0.5, 0.6)
		else:
			_box(parent, Vector3(fixed, CEILING * 0.5, mid), Vector3(WALL_T, CEILING, len), mat)
			nav.block_rect(fixed - WALL_T * 0.5, p[0], fixed + WALL_T * 0.5, p[1], 0.6)
	for c in cuts:
		var len: float = c[1] - c[0]
		var mid: float = (c[0] + c[1]) * 0.5
		var h := CEILING - ARCH_H
		if axis == "x":
			_box(parent, Vector3(mid, ARCH_H + h * 0.5, fixed), Vector3(len, h, WALL_T * 1.4), mat, false)
		else:
			_box(parent, Vector3(fixed, ARCH_H + h * 0.5, mid), Vector3(WALL_T * 1.4, h, len), mat, false)


## Outside the front doors: stone steps, a pair of torches and the night (the run starts here).
static func _porch(parent: Node3D, half: float, mats: Dictionary) -> void:
	_box(parent, Vector3(0, -0.5, half + 12.0), Vector3(30.0, 1.0, 22.0), mats["floor"])
	for side in [-1.0, 1.0]:   # low parapets so you can't wander off into the dark
		_box(parent, Vector3(side * 15.5, 1.5, half + 12.0), Vector3(1.0, 3.0, 22.0), mats["wall"])
	_box(parent, Vector3(0, 1.5, half + 23.5), Vector3(32.0, 3.0, 1.0), mats["wall"])
	for side in [-1.0, 1.0]:
		var p := Vector3(side * 9.0, 0, half + 2.5)
		_brazier(parent, p, 0.8)


static func _rugs(parent: Node3D) -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.32, 0.05, 0.06)
	red.roughness = 1.0
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.6, 0.45, 0.15)
	for r in [[0.0, 64.0, 216.0, 8.0], [0.0, -216.0, -114.0, 8.0]]:   # great hall and throne room runners
		var len: float = r[2] - r[1]
		_box(parent, Vector3(r[0], 0.015, (r[1] + r[2]) * 0.5), Vector3(r[3], 0.03, len), red, false)
		for side in [-1.0, 1.0]:
			_box(parent, Vector3(r[0] + side * (r[3] * 0.5 - 0.3), 0.02, (r[1] + r[2]) * 0.5), Vector3(0.25, 0.04, len), trim, false)


# ------------------------------------------------------------------ props

## Columns in rows down the great hall and throne room, the throne, the dining chandeliers.
static func _structured(parent: Node3D, rng: RandomNumberGenerator, nav: CastleNav, placed: Array[Vector3]) -> void:
	for z in range(80, 211, 26):   # great hall: two rows of columns
		for x in [-34.0, 34.0]:
			_place(parent, CastleProps.column(rng), Vector3(x, 0, z), 0.0, nav, placed, 1.6)
	for z in range(-200, -119, 22):
		for x in [-30.0, 30.0]:
			_place(parent, CastleProps.column(rng), Vector3(x, 0, z), 0.0, nav, placed, 1.6)
	# The throne on its dais, at the head of the throne room
	_place(parent, CastleProps.throne(rng), Vector3(0, 0, -206), 0.0, nav, placed, 6.0, true)
	# Chandeliers over the table
	for z in range(-86, 41, 21):
		var ch := CastleProps.chandelier(rng)
		var mi := MeshInstance3D.new()
		mi.mesh = ch["mesh"]
		mi.position = Vector3(0, CEILING - 7.0, z)
		parent.add_child(mi)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.42)
		l.light_energy = 3.0
		l.omni_range = 20.0
		l.position = Vector3(0, CEILING - 8.5, z)
		parent.add_child(l)


static func _place(parent: Node3D, data: Dictionary, p: Vector3, yaw: float, nav: CastleNav, placed: Array[Vector3], radius: float, landmark := false) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), p)
	WorldBuilder._prop(parent, data, xf, data.get("burnable", false))
	var body := parent.get_child(parent.get_child_count() - 1)
	if landmark:
		body.add_to_group("obstacle")
		body.set_meta("reach", radius)
	if data.has("light"):
		var l := OmniLight3D.new()
		l.light_color = data["light"]
		l.light_energy = data.get("light_energy", 2.0)
		l.omni_range = data.get("light_range", 12.0)
		l.position = xf * (data.get("light_at", Vector3(0, 2, 0)) as Vector3)
		parent.add_child(l)
	if data.has("fire_at"):
		_flames(parent, xf * (data["fire_at"] as Vector3), data.get("fire_size", 0.6))
	var foot: Vector2 = data.get("footprint", Vector2(radius, radius))
	var ext := Basis(Vector3.UP, yaw) * Vector3(foot.x, 0, foot.y)
	nav.block_rect(p.x - absf(ext.x), p.z - absf(ext.z), p.x + absf(ext.x), p.z + absf(ext.z), 0.4)
	placed.append(p)


static func _flames(parent: Node3D, at: Vector3, size: float) -> void:
	var f := Abilities._flame_particles(size, 0.7, int(18 + size * 30))
	f.position = at
	parent.add_child(f)


static func _brazier(parent: Node3D, p: Vector3, scale: float) -> void:
	var data := CastleProps.brazier(RandomNumberGenerator.new(), scale)
	var mi := MeshInstance3D.new()
	mi.mesh = data["mesh"]
	mi.position = p
	parent.add_child(mi)
	_flames(parent, p + (data["fire_at"] as Vector3), data["fire_size"])
	var l := OmniLight3D.new()
	l.light_color = data["light"]
	l.light_energy = 2.0
	l.omni_range = 12.0
	l.position = p + data["light_at"]
	parent.add_child(l)


## Shrine pads: open floor (nothing solid within a shrine zone), spread across the rooms.
static func _shrine_sites(rng: RandomNumberGenerator, nav: CastleNav, placed: Array[Vector3]) -> Array[Vector3]:
	var sites: Array[Vector3] = []
	var tries := 0
	while sites.size() < SHRINE_SITES and tries < 3000:
		tries += 1
		var room: Array = ROOMS[rng.randi() % ROOMS.size()]
		var r := Shrine.ZONE_RADIUS + 2.0
		var x := rng.randf_range(room[1] + r, room[3] - r)
		var z := rng.randf_range(room[2] + r, room[4] - r)
		if Vector2(x, z - 205.0).length() < 30.0:   # not on the entrance
			continue
		var ok := true
		for k in 12:
			var a := TAU * k / 12.0
			for rr in [0.0, r * 0.5, r]:
				if nav.is_blocked(x + cos(a) * rr, z + sin(a) * rr):
					ok = false
		for q in sites:
			if Vector2(q.x - x, q.z - z).length() < 50.0:
				ok = false
		if ok:
			sites.append(Vector3(x, 0, z))
	return sites


## The remaining standing props, lying props and landmarks, room by room, keeping doorways,
## the entrance, the shrine pads and the table clear.
static func _scatter(parent: Node3D, rng: RandomNumberGenerator, nav: CastleNav, placed: Array[Vector3], sites: Array[Vector3]) -> void:
	var standing := placed.size() - 1          # columns already placed (the throne isn't one)
	var landmarks := 1                         # the throne
	var lying := 0
	var tries := 0
	while (standing < STANDING or lying < LYING or landmarks < LANDMARKS) and tries < 20000:
		tries += 1
		var room: Array = ROOMS[rng.randi() % ROOMS.size()]
		var kind := "landmark" if landmarks < LANDMARKS else ("standing" if standing < STANDING and (lying >= LYING or rng.randf() < 0.7) else "lying")
		var margin := 4.0 if kind != "landmark" else 8.0
		var p := Vector3(rng.randf_range(room[1] + margin, room[3] - margin), 0, rng.randf_range(room[2] + margin, room[4] - margin))
		if not _clear_spot(p, nav, placed, sites, 3.5 if kind == "lying" else 2.5):
			continue
		var yaw := rng.randf() * TAU
		match kind:
			"landmark":
				_place(parent, CastleProps.brazier(rng, 1.5), p, 0.0, nav, placed, 2.4, true)
				landmarks += 1
			"standing":
				_place(parent, CastleProps.standing(rng, room[0], standing), p, yaw, nav, placed, 1.2)
				standing += 1
			"lying":
				_place(parent, CastleProps.lying(rng, room[0], lying), p, yaw, nav, placed, 2.0)
				lying += 1


static func _clear_spot(p: Vector3, nav: CastleNav, placed: Array[Vector3], sites: Array[Vector3], spacing: float) -> bool:
	if Vector2(p.x, p.z - 205.0).length() < 26.0:   # the entrance stays open
		return false
	if absf(p.x) < 10.0 and p.z > 60.0:            # the great hall's runner aisle
		return false
	for k in 9:
		var a := TAU * k / 8.0
		var r := 0.0 if k == 8 else spacing
		if nav.is_blocked(p.x + cos(a) * r, p.z + sin(a) * r):
			return false
	for q in placed:
		if Vector2(p.x - q.x, p.z - q.z).length() < spacing + 2.5:
			return false
	for s in sites:
		if Vector2(p.x - s.x, p.z - s.z).length() < Shrine.ZONE_RADIUS + 4.0:
			return false
	return true


## Torches in iron sconces along every wall (a real light on every third), banners between,
## and tall stained-glass windows glowing with moonlight in the outer walls.
static func _wall_decor(parent: Node3D, rng: RandomNumberGenerator, half: float) -> void:
	var runs := []   # [start, end, normal into the room, openings, outer wall?] along wall faces
	for w in WALLS:
		for side in [-1.0, 1.0]:
			var off: float = w[1] + side * (WALL_T * 0.5 + 0.05)
			if w[0] == "x":
				runs.append([Vector3(w[2], 0, off), Vector3(w[3], 0, off), Vector3(0, 0, side), w[4], false])
			else:
				runs.append([Vector3(off, 0, w[2]), Vector3(off, 0, w[3]), Vector3(side, 0, 0), w[4], false])
	var inner := half - 0.05
	runs.append([Vector3(-half, 0, -inner), Vector3(half, 0, -inner), Vector3(0, 0, 1), [], true])
	runs.append([Vector3(-half, 0, inner), Vector3(half, 0, inner), Vector3(0, 0, -1), [[0.0, DOOR_W + 6.0]], true])
	runs.append([Vector3(-inner, 0, -half), Vector3(-inner, 0, half), Vector3(1, 0, 0), [], true])
	runs.append([Vector3(inner, 0, -half), Vector3(inner, 0, half), Vector3(-1, 0, 0), [], true])
	var sconce := CastleProps.sconce(rng)
	var banner := CastleProps.banner(rng)
	var window := CastleProps.stained_window(rng)
	var t_xf: Array[Transform3D] = []
	var b_xf: Array[Transform3D] = []
	var w_xf: Array[Transform3D] = []
	var lit := 0
	for r in runs:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var nrm: Vector3 = r[2]
		var openings: Array = r[3]
		var along := (b - a).normalized()
		var length := a.distance_to(b)
		var basis := Basis.looking_at(-nrm, Vector3.UP)   # -Z faces into the room
		var outer: bool = r[4]
		var d := TORCH_STEP
		var k := 0
		while d < length - 6.0:
			var p := a + along * d
			var coord := p.x if absf(along.x) > 0.5 else p.z
			var in_gap := false
			for o in openings:
				if absf(coord - o[0]) < o[1] * 0.5 + 5.0:
					in_gap = true
			if not in_gap and _room_at(p - nrm * 2.0) != "":
				t_xf.append(Transform3D(basis, p + Vector3(0, 4.2, 0)))
				if lit % TORCH_LIGHT_EVERY == 0:   # flickering fire + a real light on some; the rest glow
					_flames(parent, p + nrm * 0.45 + Vector3(0, 5.0, 0), 0.22)
					var l := OmniLight3D.new()
					l.light_color = Color(1.0, 0.6, 0.3)
					l.light_energy = 2.4
					l.omni_range = 15.0
					l.position = p + nrm * 1.2 + Vector3(0, 5.0, 0)
					parent.add_child(l)
				lit += 1
				if k % 2 == 1:
					if outer:
						w_xf.append(Transform3D(basis, p + nrm * 0.02 + Vector3(0, 11.0, 0)))
					else:
						b_xf.append(Transform3D(basis, p + nrm * 0.12 + Vector3(0, 11.0, 0)))
			k += 1
			d += TORCH_STEP
	WorldBuilder._multimesh(parent, sconce, t_xf)
	WorldBuilder._multimesh(parent, banner, b_xf)
	WorldBuilder._multimesh(parent, window, w_xf)


static func _room_at(p: Vector3) -> String:
	for r in ROOMS:
		if p.x >= r[1] and p.x <= r[3] and p.z >= r[2] and p.z <= r[4]:
			return r[0]
	return ""
