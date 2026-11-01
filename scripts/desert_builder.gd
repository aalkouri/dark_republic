class_name DesertBuilder
extends RefCounted
## The Desert: a sun-baked sea of dunes on the same 440 m footprint as the other outdoor maps,
## sharing their terrain generator (SwampWater: hills, level pads, chest sites, a 1 m height
## grid) with the hills re-shaped into wind-blown dunes (ridged crests, soft troughs).
##
##   - The Great Sphinx lies on a stone plinth north of the start, facing it (DesertSphinx). Its
##     tomb door is set in the plinth in front of its paws: the Pharaoh rises out of it at 8:00.
##   - PYRAMIDS stepped pyramids (one great, three smaller) stand around it. Their stepped shape is
##     baked into the height grid as an even 37-degree slope (half a step above the treads), so
##     the player, every walking enemy, pickups and ground markers all climb them for free;
##     the stone courses (DesertProps.pyramid) are drawn on top and the sand is cut away
##     wherever the stone shows (the ground shader knows each pyramid's courses).
##   - Two oases (pools from SwampWater) ringed with reeds, papyrus and date palms.
##   - 180 standing props (palms, acacias, dead trees, rock pillars, boulders), 72 lying ones
##     (fallen columns, half-buried colossal heads, camel skeletons, mud-brick walls,
##     sarcophagi), 24 landmarks (obelisks, colossi, temple pylons, colonnades) - the swamp's
##     counts. Ground scatter (dry grass, thorn scrub, pebbles, bleached bones, potsherds) in
##     40 m chunks drawn within 75 m, like the Forest.
##   - The edge: towering dunes all round, sandstone mesas on one side and the far pyramids of
##     another necropolis on the horizon (DesertEdge). Invisible walls keep you in.
## Time of day: blazing noon (most often), a red-gold dusk, or a cold moonlit night.

const TIMES := ["day", "day", "dusk", "night"]
static var force_time := ""     # tests / screenshots: --desert-time=day|dusk|night
static var time_of_day := ""
static var active := false      # the current world is the Desert (EnemyManager, main)

const STANDING := 180
const LYING := 72
const LANDMARKS := 24
const OASES := 2
const CHUNK := 40.0
const DRAW_DIST := 75.0

# Pyramid courses: each step is RISE tall and RUN deep (a 37.6-degree climb: under the player's
# 50-degree floor limit). The baked slope runs SLOPE_LIFT above the step edges.
const RUN := 0.65
const RISE := 0.5
const SLOPE_LIFT := 0.25
const PYRAMID_TOP := 3.0        # half-width of the flat summit
## The layout: centre (x, z) and base half-width of each pyramid; the sphinx's centre. The great
## pyramid stands behind the sphinx, like Giza.
const PYRAMID_LAYOUT := [[-72.0, -150.0, 34.0], [46.0, -160.0, 22.0], [-140.0, 62.0, 17.0], [130.0, 96.0, 13.0]]
const SPHINX_AT := Vector2(0.0, -80.0)
const PLINTH := Vector2(14.0, 27.0)    # the sphinx plinth's half extents (x, z)
const PLINTH_RUN := 1.0
const PLINTH_RISE := 0.6
const PLINTH_STEPS := 2

const DUNE_HEIGHT := 2.6
const CAUSEWAY_W := 6.0          # the processional way: half its width...
const CAUSEWAY_FROM := -54.0     # ...from the sphinx's plinth (z)...
const CAUSEWAY_TO := -9.0        # ...to the start
const DUNE_FREQ := 0.016
const WIND := Vector2(0.87, 0.5)        # prevailing wind (dune crests run across it)

## Built layout (read by gameplay and tests): pyramids [{c: Vector2, half, base, n, h}], the
## sphinx {at: Vector3, yaw, tomb: Vector3}, stone footprints for the ground shader.
static var pyramids: Array = []
static var sphinx := {}
static var footprints: Array = []    # [Vector4(cx, cz, hx, hz), Vector4(base, run, rise, steps)]
static var barriers: Array = []      # EnemyManager.barriers: the sphinx's body

const SKY := {
	"day": {"top": Color(0.13, 0.36, 0.82), "horizon": Color(0.96, 0.86, 0.68), "ground": Color(0.6, 0.48, 0.32),
		"cloud_dark": Color(0.86, 0.8, 0.72), "cloud_light": Color(1.0, 0.99, 0.96), "body": Color(1.0, 0.96, 0.82), "size": 0.045, "cover": 0.1},
	"dusk": {"top": Color(0.16, 0.16, 0.42), "horizon": Color(1.0, 0.52, 0.25), "ground": Color(0.4, 0.22, 0.14),
		"cloud_dark": Color(0.55, 0.28, 0.3), "cloud_light": Color(1.0, 0.72, 0.45), "body": Color(1.0, 0.62, 0.32), "size": 0.07, "cover": 0.28},
	"night": {"top": Color(0.012, 0.022, 0.07), "horizon": Color(0.08, 0.11, 0.2), "ground": Color(0.03, 0.03, 0.05),
		"cloud_dark": Color(0.04, 0.05, 0.09), "cloud_light": Color(0.2, 0.24, 0.34), "body": Color(0.95, 0.96, 1.0), "size": 0.065, "cover": 0.06},
}

const GROUND_SHADER := """
shader_type spatial;
uniform sampler2D patch_map : filter_linear, repeat_disable;
uniform float extent = 120.0;
uniform vec4 pools[16];
uniform vec4 pool_amps[16];
uniform vec4 pool_phases[16];
uniform vec4 foot_rect[8];      // stone footprints: cx, cz, half x, half z (w unused when 0 size)
uniform vec4 foot_step[8];      // base y, run, rise, steps
uniform int foot_count = 0;
uniform vec3 sand_col : source_color = vec3(0.8, 0.58, 0.36);
uniform vec3 red_col : source_color = vec3(0.74, 0.44, 0.26);
uniform vec3 pale_col : source_color = vec3(0.92, 0.78, 0.57);
uniform vec2 wind = vec2(0.87, 0.5);
uniform float night = 0.0;
uniform float quake = 0.0;        // (shared with the other maps' ground: Thog's quake)
uniform float quake_fill = 0.0;
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.5 + noise(p * 2.03 + 3.1) * 0.28 + noise(p * 4.1 + 7.7) * 0.14 + noise(p * 8.3) * 0.08; }

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

// Height of the ripple field (for the bump normal): crests across the wind, warped and broken up
float ripples(vec2 p) {
	vec2 w = wind;
	vec2 s = vec2(-w.y, w.x);
	float along = dot(p, w);
	float across = dot(p, s);
	float warp = noise(p * 0.21) * 5.0 + noise(p * 0.9) * 0.8;
	float r = sin(along * 5.2 + warp + sin(across * 0.35) * 1.4);
	r = r * 0.5 + 0.5;
	r = pow(r, 1.6);   // sharp crests, soft troughs
	return r * smoothstep(0.25, 0.6, noise(p * 0.07 + 11.0) + 0.25);
}

void fragment() {
	// Stone footprints (pyramid courses, the sphinx plinth): the sand is cut away wherever the
	// stone stands above it, so only drifts and sand caught in the corners of the steps show
	for (int i = 0; i < 8; i++) {
		if (i >= foot_count) { break; }
		vec4 fr = foot_rect[i];
		vec2 d = abs(wpos.xz - fr.xy);
		float e = min(fr.z - d.x, fr.w - d.y);
		if (e > 0.0) {
			vec4 st = foot_step[i];
			float k = min(floor(e / st.y) + 1.0, st.w);
			if (wpos.y < st.x + k * st.z + 0.2) { discard; }
		}
	}
	// Oasis pools: holes for the pool bed and water, wet banks round them
	float edge = 1e6;
	for (int i = 0; i < 16; i++) {
		vec4 p = pools[i];
		if (p.w < 0.5) { continue; }
		vec2 d = wpos.xz - p.xy;
		if (dot(d, d) > p.z * p.z * 4.0 + 200.0) { continue; }
		float th = atan(d.y, d.x);
		vec4 a = pool_amps[i];
		vec4 ph = pool_phases[i];
		float r = p.z * (1.0 + a.x * sin(2.0 * th + ph.x) + a.y * sin(3.0 * th + ph.y) + a.z * sin(4.0 * th + ph.z) + a.w * sin(5.0 * th + ph.w));
		float dist = length(d);
		if (dist < r * 0.985) { discard; }
		edge = min(edge, dist - r);
	}
	vec2 uv = (wpos.xz + extent) / (2.0 * extent);
	vec4 m = texture(patch_map, uv);
	float n = fbm(wpos.xz * 0.35);
	float fine = noise(wpos.xz * 9.0);
	// Sand: warm base, drifts of redder and paler sand, fine grain
	vec3 col = sand_col * (0.86 + 0.24 * n);
	col = mix(col, red_col * (0.85 + 0.3 * n), smoothstep(0.52, 0.7, m.r + (n - 0.5) * 0.15) * 0.75);
	col = mix(col, pale_col, smoothstep(0.55, 0.72, m.g + (n - 0.5) * 0.12) * 0.6);
	col *= 0.93 + 0.12 * fine;
	// Wind ripples: a bump normal plus lit crests / shaded troughs
	float rp = ripples(wpos.xz);
	float e = 0.06;
	float rx = ripples(wpos.xz + vec2(e, 0.0)) - rp;
	float rz = ripples(wpos.xz + vec2(0.0, e)) - rp;
	float far = smoothstep(18.0, 70.0, length(VERTEX));
	vec3 bump = normalize(vec3(-rx * 0.9, 1.0, -rz * 0.9));
	vec3 nb = normalize(mix(bump, vec3(0.0, 1.0, 0.0), far));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(nb.x, nb.y, nb.z, 0.0)).xyz, 0.6));
	col *= 0.95 + 0.1 * rp * (1.0 - far);
	// Wind streaks: long pale wisps of blowing sand sliding across the dunes
	vec2 s = vec2(-wind.y, wind.x);
	vec2 q = vec2(dot(wpos.xz, wind) * 0.05 - TIME * 0.35, dot(wpos.xz, s) * 0.9);
	float streak = smoothstep(0.62, 0.92, noise(q) * 0.75 + noise(q * 2.7 + 5.0) * 0.25);
	streak *= smoothstep(0.35, 0.7, noise(wpos.xz * 0.02 + vec2(TIME * 0.02, 0.0)));
	col = mix(col, pale_col * 1.05, streak * 0.12);
	// Darker, damp, packed patches (and near the oases, wet sand and a fringe of green)
	float damp = smoothstep(0.66, 0.78, fbm(wpos.xz * 0.045 + 31.0)) * 0.6;
	float bank = 1.0 - smoothstep(0.0, 9.0, edge + (noise(wpos.xz * 0.4) - 0.5) * 3.0);
	damp = max(damp, bank);
	col *= 1.0 - 0.32 * damp;
	float green = (1.0 - smoothstep(0.5, 5.0, edge + (noise(wpos.xz * 0.7) - 0.5) * 2.5)) * smoothstep(0.35, 0.6, noise(wpos.xz * 1.6));
	col = mix(col, vec3(0.26, 0.34, 0.1) * (0.8 + 0.4 * n), green * 0.8);
	// Gravel: scattered dark pebbles on the harder ground
	vec2 pg = wpos.xz * 3.1;
	vec2 pi = floor(pg);
	vec2 pf = fract(pg) - 0.5 - (vec2(hash(pi + 3.1), hash(pi + 9.7)) - 0.5) * 0.5;
	float gravel = smoothstep(0.5, 0.7, m.r) * step(0.8, hash(pi + 1.7));
	float peb = (1.0 - smoothstep(0.1, 0.17, length(pf * vec2(1.0, 1.0 + hash(pi + 5.5))))) * gravel;
	col = mix(col, vec3(0.42, 0.3, 0.2) * (0.6 + 0.7 * hash(pi + 2.2)), peb);
	// Steep dune faces (slip faces) are a touch darker and smoother
	float slope = 1.0 - clamp(dot(normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
	col *= 1.0 - smoothstep(0.15, 0.5, slope) * 0.12;
	if (night > 0.5) { col *= vec3(0.78, 0.86, 1.08); }
	if (quake > 0.0) {
		float pulse = 0.5 + 0.5 * sin(TIME * mix(5.0, 14.0, quake_fill));
		col = mix(col, vec3(1.0, 0.12, 0.04), quake * (0.45 + 0.25 * pulse));
		EMISSION = vec3(1.0, 0.12, 0.04) * quake * (0.25 + 0.6 * quake_fill * pulse);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.97, 0.6, damp);
	SPECULAR = mix(0.25, 0.45, damp) + streak * 0.1;
}
"""


static func build(parent: Node3D, rng: RandomNumberGenerator, half: float) -> SwampWater:
	active = true
	var pick: String = TIMES[rng.randi() % TIMES.size()]
	time_of_day = force_time if SKY.has(force_time) else pick
	_environment(parent, rng, time_of_day)

	# Pools: a couple of oases, well clear of the pyramids and the sphinx
	var water := SwampWater.generate(rng, 12, half, 40.0)
	_layout(rng)
	_keep_oases(water)
	var extra: Array = []
	for p in pyramids:
		extra.append([p["c"], float(p["half"]) * 1.42 + 6.0])
	extra.append([SPHINX_AT, Vector2(PLINTH.x, PLINTH.y).length() + 6.0])
	water.build_terrain(rng, half, WorldBuilder.CHEST_SITES, ChestManager.SITE_RADIUS, extra)
	_shape_terrain(water, rng, half)
	var patches := WorldBuilder._patch_map(rng, half + 10.0)
	_ground(parent, half, water, patches)
	water.build_meshes(parent, {"deep": Color(0.02, 0.2, 0.26), "shallow": Color(0.1, 0.42, 0.42), "scum": Color(0.3, 0.5, 0.18), "bed": Color(0.55, 0.45, 0.3)})
	var night := time_of_day == "night"
	DesertEdge.build(parent, half, night)

	# The sphinx and the pyramids
	var sp := DesertSphinx.build(night)
	var body := StaticBody3D.new()
	body.name = "Sphinx"   # no-i18n
	body.position = sphinx["at"]
	body.rotation.y = float(sphinx["yaw"])
	var mi := MeshInstance3D.new()
	mi.mesh = sp["mesh"]
	body.add_child(mi)
	for c in sp["colliders"]:
		var cs := CollisionShape3D.new()
		cs.shape = c[0]
		cs.transform = c[1]
		body.add_child(cs)
	body.add_to_group("sphinx")
	body.set_meta("eyes", sp["eyes"])
	parent.add_child(body)
	var eyes: Array = sp["eyes"]
	var eye_mat: StandardMaterial3D = sp["eye_material"]
	body.set_meta("eye_material", eye_mat)
	body.set_meta("eye_points", eyes)
	parent.add_child(DesertSphinx.plinth_mesh(sphinx["at"], PLINTH, PLINTH_RUN, PLINTH_RISE, PLINTH_STEPS, float(sphinx["base"]), night))
	parent.add_child(DesertSphinx.tomb_door(sphinx["tomb"]))
	_causeway(parent, water, rng)
	for k in pyramids.size():
		var p: Dictionary = pyramids[k]
		var pm := DesertProps.pyramid(p, rng, k == 1, night)
		pm.name = "Pyramid%d" % k   # no-i18n
		pm.add_to_group("pyramid")
		parent.add_child(pm)

	_grass_and_scrub(parent, rng, half, water, patches)
	WorldBuilder._reeds(parent, rng, water)
	_papyrus(parent, rng, water)

	var placed: Array[Vector3] = []
	# Date palms round the oases first, then the rest of the standing props over the sand
	var n_standing := 0
	for pool in water.pools:
		var c: Vector2 = pool["center"]
		for k in 9:
			var a := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
			var r := water.max_radius(pool) + rng.randf_range(2.5, 7.0)
			var p := Vector3(c.x + cos(a) * r, 0, c.y + sin(a) * r)
			if not _clear(p, water, placed, 3.5):
				continue
			p.y = WorldBuilder._low_point(water, p, 0.8) - 0.15
			_standing(parent, DesertProps.palm(rng, 0), p, rng)
			placed.append(p)
			n_standing += 1
	while n_standing < STANDING:
		var p := _free_point(rng, half - 8.0, 14.0, water, placed, 5.0)
		var kind := n_standing % 10
		var data: Dictionary
		var burn := true
		if kind <= 1:
			data = DesertProps.palm(rng, 1 + kind)
		elif kind <= 4:
			data = DesertProps.acacia(rng)
		elif kind <= 6:
			data = DesertProps.dead_tree(rng)
		elif kind <= 8:
			data = DesertProps.boulders(rng)
			burn = false
		else:
			data = DesertProps.rock_pillar(rng)
			burn = false
		p.y = WorldBuilder._low_point(water, p, 1.0) - (0.15 if burn else 0.4)
		if burn:
			_standing(parent, data, p, rng)
		else:
			WorldBuilder._prop(parent, data, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		placed.append(p)
		n_standing += 1

	for i in LYING:
		var data: Dictionary
		match i % 6:
			0: data = DesertProps.fallen_column(rng)
			1: data = DesertProps.buried_head(rng)
			2: data = DesertProps.camel_skeleton(rng)
			3: data = DesertProps.mud_wall(rng)
			4: data = DesertProps.sarcophagus(rng)
			_: data = DesertProps.fallen_obelisk(rng)
		var length: float = data.get("length", 3.0)
		var p := _free_point(rng, half - length * 0.5 - 6.0, 14.0, water, placed, length * 0.5 + 2.0)
		p.y = WorldBuilder._low_point(water, p, length * 0.35) - float(data.get("sink", 0.15))
		WorldBuilder._prop(parent, data, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		placed.append(p)

	for i in LANDMARKS:
		var p := _free_point(rng, half - 16.0, 26.0, water, placed, 8.0)
		p.y = WorldBuilder._low_point(water, p, 2.5) - 0.3
		var lm := DesertProps.landmark(rng, i)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		WorldBuilder._prop(parent, lm, xf)
		var lb := parent.get_child(parent.get_child_count() - 1)
		lb.add_to_group("obstacle")
		lb.set_meta("reach", 3.0)
		if night and i % 3 == 0:   # braziers burn by the landmarks at night
			_brazier_light(parent, xf * Vector3(2.4, 0, 2.4))
		placed.append(p)
	parent.add_child(DesertWind.new())
	return water


## The processional way: worn flagstones from the start up to the sphinx's plinth, following the
## ground, with ram-headed sphinxes on plinths along both sides.
static func _causeway(parent: Node3D, water: SwampWater, rng: RandomNumberGenerator) -> void:
	var q := DesertProps._Quads.new()
	var z := CAUSEWAY_TO
	var row := 0
	while z > CAUSEWAY_FROM:
		var z1 := maxf(z - 1.8, CAUSEWAY_FROM)
		var x := -CAUSEWAY_W + (0.9 if row % 2 else 0.0)
		var first := true
		while x < CAUSEWAY_W - 0.01:
			var x0 := -CAUSEWAY_W if first else x
			var x1 := minf(x + rng.randf_range(1.4, 2.2), CAUSEWAY_W)
			first = false
			if rng.randf() < 0.07 and absf(x0) > 2.0:   # a missing stone, sand in its place
				x = x1
				continue
			var c := DesertProps._shade(DesertProps.LIMESTONE.darkened(0.12), rng, 0.08)
			var h := func(px: float, pz: float) -> float: return water.ground_height(px, pz) + 0.07
			q.quad(Vector3(x0, h.call(x0, z1), z1), Vector3(x1, h.call(x1, z1), z1), Vector3(x1, h.call(x1, z), z), Vector3(x0, h.call(x0, z), z), Vector3.UP, c, Vector2(x1 - x0, z - z1))
			x = x1
		z = z1
		row += 1
	var mi := MeshInstance3D.new()
	mi.mesh = q.commit(DesertProps.stone_material())
	mi.name = "Causeway"   # no-i18n
	parent.add_child(mi)
	var ram := DesertProps.ram_statue()
	var zz := CAUSEWAY_TO - 6.0
	while zz > CAUSEWAY_FROM + 4.0:
		for sd in [-1.0, 1.0]:
			var p := Vector3(sd * (CAUSEWAY_W + 1.8), 0, zz)
			p.y = WorldBuilder._low_point(water, p, 1.2) - 0.05
			WorldBuilder._prop(parent, ram, Transform3D(Basis(Vector3.UP, -sd * PI * 0.5).scaled(Vector3.ONE * 0.85), p))
		zz -= 9.0


static func _standing(parent: Node3D, data: Dictionary, p: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.85, 1.2)
	WorldBuilder._prop(parent, data, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.12), s)), p), true)


static func _brazier_light(parent: Node3D, at: Vector3) -> void:
	at.y = SwampWater.height_at(at.x, at.z)
	var b := DesertProps.brazier()
	WorldBuilder._prop(parent, b, Transform3D(Basis(), at))
	var fl := Abilities._flame_particles(0.5, 0.7, 26)
	fl.position = at + Vector3(0, 1.35, 0)
	parent.add_child(fl)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 2.2
	l.omni_range = 12.0
	l.shadow_enabled = false
	l.position = at + Vector3(0, 1.8, 0)
	parent.add_child(l)


# ------------------------------------------------------------------ layout

static func _layout(rng: RandomNumberGenerator) -> void:
	pyramids.clear()
	footprints.clear()
	for l in PYRAMID_LAYOUT:
		var c := Vector2(float(l[0]) + rng.randf_range(-4.0, 4.0), float(l[1]) + rng.randf_range(-4.0, 4.0))
		var hw: float = l[2]
		var n := int(round((hw - PYRAMID_TOP) / RUN))
		pyramids.append({"c": c, "half": hw, "n": n, "run": (hw - PYRAMID_TOP) / n, "rise": RISE, "h": n * RISE, "base": 0.0})
	sphinx = {"at": Vector3(SPHINX_AT.x, 0, SPHINX_AT.y), "yaw": 0.0, "base": 0.0}


## Keep at most OASES of the generated pools, clear of the pyramids, the sphinx and the start.
static func _keep_oases(water: SwampWater) -> void:
	var keep: Array = []
	for p in water.pools:
		var c: Vector2 = p["center"]
		var r := water.max_radius(p)
		var ok := c.length() > 45.0 + r and c.distance_to(SPHINX_AT) > 40.0 + r
		for py in pyramids:
			if c.distance_to(py["c"]) < float(py["half"]) * 1.42 + 14.0 + r:
				ok = false
		if ok and keep.size() < OASES:
			keep.append(p)
	water.pools = keep
	water.fast_x = PackedFloat32Array()
	water.fast_z = PackedFloat32Array()
	water.fast_r2 = PackedFloat32Array()
	for p in keep:
		var c: Vector2 = p["center"]
		water.fast_x.append(c.x)
		water.fast_z.append(c.y)
		water.fast_r2.append(pow(water.max_radius(p), 2.0))


## Height of a stone footprint's surface `e` metres in from its edge (the baked slope).
static func step_profile(e: float, run: float, rise: float, steps: int) -> float:
	if e < 0.0:
		return -INF
	return minf(e / run * rise + SLOPE_LIFT, steps * rise)


## Re-shape the hills into dunes, bake the pyramids and the sphinx plinth into the height grid,
## heap sand drifts against the pyramids, and lift everything so the ground never dips below 0.
static func _shape_terrain(water: SwampWater, rng: RandomNumberGenerator, half: float) -> void:
	var hs := water.hsize
	var ho := water.horigin
	var g := water.hgrid
	# Mask: 0 on level pads (start, oases, chest sites, pyramids, sphinx), 1 in the open dunes
	var mask := PackedFloat32Array()
	mask.resize(hs * hs)
	mask.fill(1.0)
	for pad in water.pads:
		var c: Vector2 = pad[0]
		var r: float = pad[1]
		var reach := r + 14.0
		for zi in range(maxi(0, int(c.y - reach - ho)), mini(hs, int(c.y + reach - ho) + 2)):
			for xi in range(maxi(0, int(c.x - reach - ho)), mini(hs, int(c.x + reach - ho) + 2)):
				var d := Vector2(ho + xi, ho + zi).distance_to(c)
				var k := zi * hs + xi
				mask[k] = minf(mask[k], smoothstep(r, reach, d))
	# The processional way from the start to the sphinx stays clear of dunes
	for zi in range(maxi(0, int(CAUSEWAY_FROM - ho)), mini(hs, int(CAUSEWAY_TO - ho) + 1)):
		for xi in range(maxi(0, int(-CAUSEWAY_W * 2.0 - ho)), mini(hs, int(CAUSEWAY_W * 2.0 - ho) + 1)):
			var k := zi * hs + xi
			mask[k] *= smoothstep(CAUSEWAY_W * 0.6, CAUSEWAY_W * 1.8, absf(ho + xi))
	# Dunes: ridged noise stretched along the wind, so crests run across it in long sinuous lines
	var dn := FastNoiseLite.new()
	dn.seed = rng.randi()
	dn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dn.frequency = DUNE_FREQ
	dn.fractal_octaves = 2
	var wx := WIND.x
	var wz := WIND.y
	for zi in hs:
		var z := ho + zi
		for xi in hs:
			var k := zi * hs + xi
			var mk := mask[k]
			if mk <= 0.001:
				continue
			var x := ho + xi
			var along := x * wx + z * wz
			var across := -x * wz + z * wx
			var nv := dn.get_noise_2d(along * 1.8, across * 0.55)
			var ridge := 1.0 - absf(nv)
			ridge = ridge * ridge
			var edge := smoothstep(0.0, SwampWater.EDGE_BAND, maxf(absf(x), absf(z)) - (half - SwampWater.EDGE_BAND))
			g[k] += (ridge - 0.35) * DUNE_HEIGHT * mk * (1.0 + edge * 1.5)
	# The causeway is graded into an even ramp from the start up to the plinth (cutting through
	# any hill in the way, banked up over any dip), so the sphinx is in view from the start
	var h_from := _grid_at(g, hs, ho, 0.0, CAUSEWAY_TO + 4.0)
	var h_to := _grid_at(g, hs, ho, SPHINX_AT.x, SPHINX_AT.y + PLINTH.y + 3.0)
	for zi in range(maxi(0, int(CAUSEWAY_FROM - 6.0 - ho)), mini(hs, int(CAUSEWAY_TO + 8.0 - ho) + 1)):
		var z := ho + zi
		var t := clampf((CAUSEWAY_TO + 4.0 - z) / (CAUSEWAY_TO + 4.0 - (SPHINX_AT.y + PLINTH.y + 3.0)), 0.0, 1.0)
		var target := lerpf(h_from, h_to, t)
		var fade_z := smoothstep(CAUSEWAY_TO + 8.0, CAUSEWAY_TO + 2.0, z) * smoothstep(CAUSEWAY_FROM - 6.0, CAUSEWAY_FROM - 1.0, z)
		for xi in range(maxi(0, int(-CAUSEWAY_W * 2.4 - ho)), mini(hs, int(CAUSEWAY_W * 2.4 - ho) + 1)):
			var x := ho + xi
			var w := (1.0 - smoothstep(CAUSEWAY_W * 1.4, CAUSEWAY_W * 2.4, absf(x))) * fade_z
			for site in water.chest_sites:   # never move a chest's pad
				if Vector2(x - site.x, z - site.z).length() < ChestManager.SITE_RADIUS + 6.0:
					w = 0.0
			var k := zi * hs + xi
			g[k] = lerpf(g[k], target, w)
	# Lift: the lowest ground (oasis beds) sits just above 0
	var lo := INF
	for k in g.size():
		lo = minf(lo, g[k])
	var off := 0.3 - lo
	for k in g.size():
		g[k] += off
	for k in water.pads.size():
		water.pads[k][2] = float(water.pads[k][2]) + off
	for k in water.chest_sites.size():
		var cs: Vector3 = water.chest_sites[k]
		cs.y += off
		water.chest_sites[k] = cs
	for p in water.pools:
		p["base"] = float(p["base"]) + off
	# Pyramids on their pads, with sand drifted against their feet
	var dr := FastNoiseLite.new()
	dr.seed = rng.randi()
	dr.frequency = 0.08
	for p in pyramids:
		var c: Vector2 = p["c"]
		var hw: float = p["half"]
		var base := _grid_at(g, hs, ho, c.x, c.y)
		p["base"] = base
		var run: float = p["run"]
		var n: int = p["n"]
		var reach := hw + 8.0
		for zi in range(maxi(0, int(c.y - reach - ho)), mini(hs, int(c.y + reach - ho) + 2)):
			for xi in range(maxi(0, int(c.x - reach - ho)), mini(hs, int(c.x + reach - ho) + 2)):
				var x := ho + xi
				var z := ho + zi
				var e := minf(hw - absf(x - c.x), hw - absf(z - c.y))   # metres in from the base edge
				var k := zi * hs + xi
				var h := g[k]
				if e >= 0.0:
					h = maxf(h, base + step_profile(e, run, RISE, n))
				# a drift: highest against the stone, fading 7 m out, patchy
				var drift := 1.7 * pow(clampf(1.0 - (-e) / 7.0, 0.0, 1.0), 2.0) * (0.35 + 0.65 * (dr.get_noise_2d(x, z) * 0.5 + 0.5))
				if e > 0.0:
					drift *= clampf(1.0 - e / 2.5, 0.0, 1.0)
				h = maxf(h, base + drift)
				g[k] = h
		footprints.append([Vector4(c.x, c.y, hw, hw), Vector4(base, run, RISE, n)])
	# The sphinx plinth: two broad steps up to a level stone floor
	var sc := SPHINX_AT
	var sbase := _grid_at(g, hs, ho, sc.x, sc.y)
	sphinx["base"] = sbase
	sphinx["at"] = Vector3(sc.x, sbase + PLINTH_STEPS * PLINTH_RISE, sc.y)
	sphinx["tomb"] = Vector3(sc.x, sbase + PLINTH_STEPS * PLINTH_RISE, sc.y + DesertSphinx.TOMB_Z)
	for zi in range(maxi(0, int(sc.y - PLINTH.y - ho) - 1), mini(hs, int(sc.y + PLINTH.y - ho) + 2)):
		for xi in range(maxi(0, int(sc.x - PLINTH.x - ho) - 1), mini(hs, int(sc.x + PLINTH.x - ho) + 2)):
			var x := ho + xi
			var z := ho + zi
			var e := minf(PLINTH.x - absf(x - sc.x), PLINTH.y - absf(z - sc.y))
			if e >= 0.0:
				var k := zi * hs + xi
				g[k] = maxf(g[k], sbase + step_profile(e, PLINTH_RUN, PLINTH_RISE, PLINTH_STEPS))
	footprints.append([Vector4(sc.x, sc.y, PLINTH.x, PLINTH.y), Vector4(sbase, PLINTH_RUN, PLINTH_RISE, PLINTH_STEPS)])
	# Enemies walk round the sphinx's body (paws to tail)
	barriers = [[Vector2(sc.x, sc.y - 19.0), Vector2(sc.x, sc.y + 14.5), 5.6]]
	water.hgrid = g
	var img := Image.create_from_data(hs, hs, false, Image.FORMAT_RF, g.to_byte_array())
	water.height_texture = ImageTexture.create_from_image(img)


static func _grid_at(g: PackedFloat32Array, hs: int, ho: float, x: float, z: float) -> float:
	return g[clampi(int(round(z - ho)), 0, hs - 1) * hs + clampi(int(round(x - ho)), 0, hs - 1)]


## Is this XZ on (or within `margin` of) the causeway or any stone footprint?
static func on_paved(x: float, z: float, margin: float) -> bool:
	if absf(x) < CAUSEWAY_W + margin and z > CAUSEWAY_FROM - margin and z < CAUSEWAY_TO + margin:
		return true
	return on_stone(x, z, margin)


## Is this XZ on (or within `margin` of) a pyramid or the sphinx plinth?
static func on_stone(x: float, z: float, margin: float) -> bool:
	for f in footprints:
		var r: Vector4 = f[0]
		if absf(x - r.x) < r.z + margin and absf(z - r.y) < r.w + margin:
			return true
	return false


## The pyramid whose footprint holds XZ, or {} (tests, the zombies' climbing).
static func pyramid_at(x: float, z: float) -> Dictionary:
	for p in pyramids:
		var c: Vector2 = p["c"]
		var hw: float = p["half"]
		if absf(x - c.x) < hw and absf(z - c.y) < hw:
			return p
	return {}


static func _clear(p: Vector3, water: SwampWater, placed: Array[Vector3], spacing: float) -> bool:
	if water.near_pool(p.x, p.z, 1.5) or on_paved(p.x, p.z, 6.0) or Vector2(p.x, p.z).length() < 12.0:
		return false
	if absf(p.x) < CAUSEWAY_W + 6.0 and p.z > CAUSEWAY_FROM - 2.0 and p.z < CAUSEWAY_TO + 2.0:
		return false
	for site in water.chest_sites:
		if Vector2(p.x - site.x, p.z - site.z).length() < ChestManager.SITE_RADIUS + 3.0 + spacing * 0.5:
			return false
	for q in placed:
		if p.distance_to(q) < spacing:
			return false
	return true


static func _free_point(rng: RandomNumberGenerator, extent: float, keep_out: float, water: SwampWater, placed: Array[Vector3], spacing: float) -> Vector3:
	for attempt in 400:
		var p := Vector3(rng.randf_range(-extent, extent), 0.0, rng.randf_range(-extent, extent))
		if p.length() < keep_out:
			continue
		if _clear(p, water, placed, spacing):
			p.y = water.ground_height(p.x, p.z)
			return p
	var q := Vector3(rng.randf_range(-extent, extent), 0.0, rng.randf_range(-extent, extent))
	q.y = water.ground_height(q.x, q.z)
	return q


# ------------------------------------------------------------------ sky, light, haze

static func _environment(parent: Node3D, rng: RandomNumberGenerator, time: String) -> void:
	var night := time == "night"
	var dusk := time == "dusk"
	var s: Dictionary = SKY[time]
	var sh := Shader.new()
	sh.code = WorldBuilder.SKY_SHADER
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("night", 1.0 if night else 0.0)
	sky_mat.set_shader_parameter("seed", rng.randf() * 50.0)
	sky_mat.set_shader_parameter("top_color", s["top"])
	sky_mat.set_shader_parameter("horizon_color", s["horizon"])
	sky_mat.set_shader_parameter("ground_color", s["ground"])
	sky_mat.set_shader_parameter("cloud_dark", s["cloud_dark"])
	sky_mat.set_shader_parameter("cloud_light", s["cloud_light"])
	sky_mat.set_shader_parameter("body_color", s["body"])
	sky_mat.set_shader_parameter("body_size", s["size"])
	sky_mat.set_shader_parameter("coverage", s["cover"])
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_luminance_cap = 4.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.fog_enabled = true
	env.fog_sky_affect = 0.15
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	if night:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.3, 0.38, 0.6)
		env.ambient_light_energy = 0.9
		env.fog_light_color = Color(0.06, 0.08, 0.15)
		env.fog_density = 0.009
		env.glow_intensity = 0.8
		env.glow_hdr_threshold = 0.9
	elif dusk:
		env.fog_light_color = Color(0.85, 0.5, 0.32)
		env.fog_density = 0.008
		env.adjustment_saturation = 1.2
	else:   # heat haze
		env.fog_light_color = Color(0.9, 0.8, 0.64)
		env.fog_density = 0.0035
	var we := WorldEnvironment.new()
	we.environment = env
	we.name = "DesertEnvironment"   # no-i18n
	parent.add_child(we)
	WorldBuilder._add_distant_castle(parent, env.fog_light_color, night)
	var az := deg_to_rad(205.0) + rng.randf_range(-0.5, 0.5)   # behind the sphinx's shoulder, more or less
	var el := deg_to_rad(rng.randf_range(12.0, 18.0) if dusk else (rng.randf_range(38.0, 50.0) if night else rng.randf_range(52.0, 64.0)))
	var to_light := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
	var light := DirectionalLight3D.new()
	light.basis = Basis.looking_at(-to_light, Vector3.UP)
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 90.0
	light.light_color = Color(1.0, 0.95, 0.84)
	light.light_energy = 1.2
	if dusk:
		light.light_color = Color(1.0, 0.62, 0.36)
		light.light_energy = 1.25
	elif night:
		light.light_color = Color(0.62, 0.74, 1.0)
		light.light_energy = 0.55
	parent.add_child(light)


# ------------------------------------------------------------------ ground

static func _ground(parent: Node3D, half: float, water: SwampWater, patches: Image) -> void:
	var body := water.heightmap_body()
	var mesh := water.ground_mesh(1)
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("patch_map", ImageTexture.create_from_image(patches))
	sm.set_shader_parameter("extent", half + 10.0)
	var sp := water.shader_params()
	for k in sp:
		sm.set_shader_parameter(k, sp[k])
	var rects: Array[Vector4] = []
	var steps: Array[Vector4] = []
	for f in footprints:
		rects.append(f[0])
		steps.append(f[1])
	while rects.size() < 8:
		rects.append(Vector4.ZERO)
		steps.append(Vector4(0, 1, 1, 0))
	sm.set_shader_parameter("foot_rect", rects)
	sm.set_shader_parameter("foot_step", steps)
	sm.set_shader_parameter("foot_count", footprints.size())
	sm.set_shader_parameter("wind", WIND)
	sm.set_shader_parameter("night", 1.0 if time_of_day == "night" else 0.0)
	if time_of_day == "dusk":
		sm.set_shader_parameter("sand_col", Color(0.9, 0.6, 0.4))
	mesh.surface_set_material(0, sm)
	water.ground_mat = sm
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	body.name = "DesertGround"   # no-i18n
	parent.add_child(body)


# ------------------------------------------------------------------ ground scatter

## Sparse dry grass and thorn scrub on the firmer ground, pebbles, bleached bones and potsherds
## everywhere, lush grass round the oases; all in chunks drawn only near the camera.
static func _grass_and_scrub(parent: Node3D, rng: RandomNumberGenerator, half: float, water: SwampWater, patches: Image) -> void:
	var extent := half + 10.0
	var grass := {}
	var lush := {}
	var z := -half
	while z < half:
		var x := -half
		while x < half:
			var px := x + rng.randf_range(-1.2, 1.2)
			var pz := z + rng.randf_range(-1.2, 1.2)
			if not on_paved(px, pz, 0.5) and Vector2(px, pz).length() > 4.0 and not water.in_pool_xz(px, pz):
				var near := water.near_pool(px, pz, 9.0)
				var m := WorldBuilder._sample(patches, extent, px, pz)
				if near or m.r > 0.56 or (m.g < 0.42 and rng.randf() < 0.4):
					var s := rng.randf_range(0.7, 1.3)
					var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(px, water.ground_height(px, pz) - 0.04, pz))
					ForestBuilder._chunk_add(lush if near else grass, xf)
			x += 2.1
		z += 2.1
	_chunks(parent, grass, DesertProps.dry_grass_mesh(rng, false))
	_chunks(parent, lush, DesertProps.dry_grass_mesh(rng, true))
	var scatter := [["scrub", 1700, 0.8, 1.3], ["pebbles", 4200, 0.6, 1.6], ["stones", 900, 0.6, 1.4], ["bones", 260, 0.8, 1.2], ["shards", 320, 0.8, 1.2], ["thorn", 700, 0.7, 1.3]]
	for sc in scatter:
		var chunks := {}
		var kind: String = sc[0]
		for k in int(sc[1]):
			var p := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
			if water.near_pool(p.x, p.y, 0.5) or on_paved(p.x, p.y, 0.3) or p.length() < 4.0:
				continue
			var s := rng.randf_range(float(sc[2]), float(sc[3]))
			var h := water.ground_height(p.x, p.y)
			var nrm := water.normal_at(p.x, p.y)
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			if kind in ["pebbles", "stones", "bones", "shards"]:   # lie flat on the slope
				basis = Basis(Quaternion(Vector3.UP, nrm)) * basis
			ForestBuilder._chunk_add(chunks, Transform3D(basis.scaled(Vector3.ONE * s), Vector3(p.x, h - 0.03, p.y)))
		_chunks(parent, chunks, DesertProps.scatter_mesh(kind, rng))


static func _chunks(parent: Node3D, chunks: Dictionary, mesh: Mesh) -> void:
	ForestBuilder._chunk_meshes(parent, chunks, mesh)


## Papyrus clumps in the shallows of the oases.
static func _papyrus(parent: Node3D, rng: RandomNumberGenerator, water: SwampWater) -> void:
	var xforms: Array[Transform3D] = []
	for p in water.pools:
		var c: Vector2 = p["center"]
		for k in int(TAU * float(p["r"]) * 0.7):
			var th := rng.randf() * TAU
			var r := water.outline_radius(p, th) * rng.randf_range(0.78, 0.97)
			var pos := Vector3(c.x + cos(th) * r, 0, c.y + sin(th) * r)
			pos.y = water.exact_height(pos.x, pos.z) - 0.05
			var s := rng.randf_range(0.8, 1.3)
			xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), pos))
	if not xforms.is_empty():
		WorldBuilder._multimesh(parent, DesertProps.papyrus_mesh(rng), xforms)
