class_name CalderaBuilder
extends RefCounted
## The Ashen Caldera: a volcanic crater floor under a smouldering red-orange sky, on the same
## 440 m footprint as the other outdoor maps and sharing their terrain generator (SwampWater:
## hills, level pads, chest sites, a 1 m height grid), with:
##
##   - LAVA instead of water. Three rivers of lava wind across the caldera (one pouring from the
##     lava falls on the northern ridge into the great lava pool north of the start, where Singe
##     sleeps), and a few side pools; the smith-god's broken colossus sinks in the biggest. Lava
##     is carved into the height grid (a channel 0.35 m deep with banks and levees), its glowing
##     surface drawn on top (LAVA_SHADER: crust plates drifting on the flow, molten seams).
##     Standing in it BURNS you (damage over time and a brief burn, CalderaAmbience); enemies
##     wade through unharmed. No swamp water anywhere: the ground is lifted well above 0 and the
##     SwampWater keeps no pools, so nothing is ever slowed by "water".
##   - Crossings: natural rock bridges (the channel is left uncut, the ground humped over it and a
##     rock arch drawn under it, the lava flowing through) and lines of basalt stepping stones.
##   - The ground (GROUND_SHADER): black basalt and grey ash, cooled pahoehoe ropes, glowing lava
##     cracks that pulse (hotter near the lava), sulphur-yellow crusts round the vents, scorched
##     patches. Thog-style map-wide effects: `flood_warn` (cracks spreading, pulsing) and `flood`
##     (the whole floor turns to molten lava) for Singe's Caldera Eruption.
##   - Set pieces: a ruined dwarven forge-temple with a giant anvil, the lava falls, the sunk
##     colossus. 180 standing props (charred and petrified trees, basalt columns, obsidian shards,
##     scoria boulders, sulphur vents, hornitos), 72 lying ones, 24 landmarks (basalt column
##     fields you can climb, obsidian spires, chained braziers, fumarole fields, sulphur crystal
##     clusters, the bones of some huge beast) - the swamp's counts - plus ground scatter (pumice,
##     ash drifts, embers, glowing cracks, scoria) in 40 m chunks drawn within 75 m.
##   - The edge: towering crater cliffs (CalderaEdge) with invisible walls; a great active
##     volcano on the horizon and a smaller one smoking in the cliffs.
## Time of day: a smouldering ember-lit haze (most often) or a black night lit by the lava.

const TIMES := ["ember", "ember", "night"]
static var force_time := ""     # tests / screenshots: --caldera-time=ember|night
static var time_of_day := ""
static var active := false      # the current world is the Caldera (EnemyManager, main)

const STANDING := 180
const LYING := 72
const LANDMARKS := 24
const CHUNK := 40.0
const DRAW_DIST := 75.0
const LAVA_NONE := -1000.0
const LAVA_BELOW := 0.3          # the lava surface sits this far below the banks...
const LAVA_DEPTH := 0.35         # ...over a bed this much deeper
const BANK := 3.2                # metres from the lava's edge to the top of the bank
const LEVEE := 4.0               # ...and a levee beyond, where the ground was lower than the lava
const BRIDGE_HALF := 3.0         # half the length (along the river) of a rock bridge
const STONE_STEP := 1.22         # stepping stones: spacing...
const STONE_R := 0.64            # ...and radius
const POOL_AT := Vector2(0.0, -78.0)   # the great lava pool, in view from the start
const POOL_R := 19.0
const ROAD_W := 3.6               # half the width of the dwarves' road down to the great pool
const FORGE_AT := Vector2(-64.0, -24.0)
const FORGE_HALF := Vector2(13.0, 11.0)
const LAVA_GLOW := Color(1.0, 0.36, 0.06)
const CONE_R := 36.0             # the cinder cone: base radius...
const CONE_H := 34.0             # ...height...
const CONE_CRATER := 7.5         # ...and its crater's radius

## Built layout (gameplay and tests read these)
static var rivers: Array = []        # {pts: PackedVector2Array (1 m apart), lv: PackedFloat32Array (lava height), w (half width), bridges: [s], stones: [s]}
static var pools: Array = []         # {c: Vector2, r, lv (lava height), amps, phases, kind}
static var stones: Array = []        # [Vector3 top centre] of every stepping stone
static var bridges: Array = []       # [{at: Vector3, dir: Vector2}]
static var forge := {}               # {at: Vector3, yaw}
static var statue := {}              # {at: Vector3}
static var falls := {}               # {at: Vector3, dir: Vector2}
static var cone := {}                # the cinder cone: {at: base centre, top: crater, r, crater, h}; eruptions come from it
static var lava_mats: Array = []     # every lava surface material (Singe's death dims them)
static var ground_mat: ShaderMaterial
# 1 m grids over the height grid (same origin and size): metres from the lava's edge (negative
# inside), the lava's surface height near it, and how much of a bridge stands here
static var ldist := PackedFloat32Array()
static var llev := PackedFloat32Array()
static var lbridge := PackedFloat32Array()
static var _hs := 0
static var _ho := 0.0

const SKY := {
	"ember": {"top": Color(0.1, 0.06, 0.055), "horizon": Color(0.72, 0.3, 0.12), "ground": Color(0.12, 0.06, 0.04),
		"cloud_dark": Color(0.1, 0.075, 0.07), "cloud_light": Color(0.5, 0.24, 0.13), "body": Color(1.0, 0.45, 0.2), "size": 0.06, "cover": 0.78},
	"night": {"top": Color(0.02, 0.012, 0.012), "horizon": Color(0.32, 0.09, 0.04), "ground": Color(0.05, 0.02, 0.015),
		"cloud_dark": Color(0.05, 0.03, 0.03), "cloud_light": Color(0.36, 0.12, 0.06), "body": Color(1.0, 0.55, 0.35), "size": 0.05, "cover": 0.6},
}

const GROUND_SHADER := """
shader_type spatial;
uniform sampler2D patch_map : filter_linear, repeat_disable;
uniform float extent = 120.0;
uniform sampler2D lava_tex : filter_linear, repeat_disable;   // r: metres from the lava (-4..16)
uniform float h_origin = 0.0;
uniform float h_size = 1.0;
uniform float night = 0.0;
uniform float dim = 1.0;          // the lava's glow (Singe's death dims it)
uniform float flood_warn = 0.0;   // the Caldera Eruption coming: cracks spread and pulse (0..1)
uniform float flood = 0.0;        // ...the floor is molten lava (0 / 1)
uniform float quake = 0.0;        // (shared with the other maps' ground: Thog's quake)
uniform float quake_fill = 0.0;
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.5 + noise(p * 2.03 + 3.1) * 0.28 + noise(p * 4.1 + 7.7) * 0.14 + noise(p * 8.3) * 0.08; }
// distance to the nearest cell edge (cracks between plates), and the cell's id
vec3 cells(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float d1 = 8.0; float d2 = 8.0; vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + vec2(hash(i + o), hash(i + o + 17.3)) - f;
			float dd = dot(r, r);
			if (dd < d1) { d2 = d1; d1 = dd; id = i + o; } else if (dd < d2) { d2 = dd; }
		}
	}
	return vec3(sqrt(d2) - sqrt(d1), id);
}
vec3 molten(vec2 p, float t) {
	vec3 c = cells(p * 0.45 + vec2(t * 0.05, t * 0.03));
	float seam = 1.0 - smoothstep(0.0, 0.22, c.x);
	float crust = step(0.35, hash(c.yz));
	vec3 hot = mix(vec3(1.0, 0.3, 0.04), vec3(1.0, 0.75, 0.25), noise(p * 0.8 + t * 0.4));
	return mix(hot * (1.0 - crust * 0.85), hot * 1.6, seam);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

// The height of the pahoehoe ropes (for their bump): bands bent into lobes
float ropes(vec2 p) {
	vec2 w = p + vec2(noise(p * 0.11) * 9.0, noise(p * 0.13 + 5.0) * 9.0);
	float lobe = length(fract(w * 0.06) - 0.5) * 16.0;
	return sin(lobe * 3.4 + noise(p * 1.4) * 2.0) * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = (wpos.xz + extent) / (2.0 * extent);
	vec4 m = texture(patch_map, uv);
	float ld = texture(lava_tex, (wpos.xz - h_origin + 0.5) / h_size).r * 20.0 - 4.0;
	float heat = 1.0 - smoothstep(0.0, 9.0, ld);
	float n = fbm(wpos.xz * 0.3);
	float fine = noise(wpos.xz * 8.0);
	// Black basalt and grey ash in drifts; the ash settles in the hollows
	vec3 basalt = vec3(0.052, 0.048, 0.048) * (0.7 + 0.6 * n);
	vec3 ash = vec3(0.25, 0.235, 0.225) * (0.8 + 0.4 * fbm(wpos.xz * 1.3));
	float ashk = smoothstep(0.5, 0.74, m.g + (n - 0.5) * 0.35 + (fine - 0.5) * 0.1) * (1.0 - heat * 0.8);
	vec3 col = mix(basalt, ash, ashk);
	col *= 0.94 + 0.09 * fine;
	// Cooled pahoehoe: ropy folds in the bare basalt, with a bump normal and lit crests
	float pah = smoothstep(0.5, 0.66, m.r + (n - 0.5) * 0.2) * (1.0 - ashk);
	float far = smoothstep(16.0, 60.0, length(VERTEX));
	if (pah > 0.01) {
		float rp = ropes(wpos.xz);
		float e = 0.05;
		float rx = ropes(wpos.xz + vec2(e, 0.0)) - rp;
		float rz = ropes(wpos.xz + vec2(0.0, e)) - rp;
		vec3 bump = normalize(vec3(-rx * 1.6, 1.0, -rz * 1.6));
		vec3 nb = normalize(mix(vec3(0.0, 1.0, 0.0), bump, pah * (1.0 - far)));
		NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(nb, 0.0)).xyz, 0.7));
		col = mix(col, col * (0.75 + 0.6 * rp) + vec3(0.02, 0.018, 0.02) * rp, pah);
	}
	// Scorched patches (sooty black) and rusty, oxidised ground
	float scorch = smoothstep(0.62, 0.78, fbm(wpos.xz * 0.05 + 21.0));
	col = mix(col, vec3(0.025, 0.02, 0.02), scorch * 0.75);
	float rust = smoothstep(0.6, 0.8, fbm(wpos.xz * 0.07 + 41.0)) * (1.0 - ashk);
	col = mix(col, vec3(0.22, 0.09, 0.05) * (0.7 + 0.5 * n), rust * 0.6);
	// Sulphur: yellow crusts in blotches (round the vents and here and there)
	float sul = smoothstep(0.76, 0.86, fbm(wpos.xz * 0.06 + 77.0) + fine * 0.06) * (1.0 - heat);
	col = mix(col, vec3(0.58, 0.48, 0.12) * (0.7 + 0.45 * fine), sul * 0.75);
	// Banks of the lava: dark glassy crust going orange-hot right at the edge
	col = mix(col, vec3(0.04, 0.03, 0.03), smoothstep(5.0, 1.0, ld) * 0.6);
	// Glowing cracks: a warped network of plates whose seams glow and pulse, patchy, tapering and
	// broken; wider and hotter near the lava
	vec2 wq = wpos.xz * 0.62 + vec2(noise(wpos.xz * 0.21), noise(wpos.xz * 0.19 + 7.0)) * 2.2 + vec2(noise(wpos.xz * 1.7), noise(wpos.xz * 1.6 + 5.0)) * 0.35;
	vec3 c1 = cells(wq);
	vec3 c2 = cells(wpos.xz * 1.2 + vec2(noise(wpos.xz * 0.9), noise(wpos.xz * 0.8 + 3.0)) * 0.8 + 9.0);
	float taper = smoothstep(0.25, 0.75, noise(wpos.xz * 0.9 + c1.yz * 3.0));
	float wide = (mix(0.012, 0.04, heat) + flood_warn * 0.16) * (0.35 + 0.9 * taper);
	float patchy = smoothstep(0.6, 0.82, fbm(wpos.xz * 0.035 + 13.0) + heat * 0.55 + flood_warn);
	float brk = smoothstep(0.32, 0.6, noise(wpos.xz * 2.3) + heat * 0.3 + flood_warn);   // the lines break up
	float crack = (1.0 - smoothstep(0.0, wide, c1.x)) * patchy * brk;
	float crack2 = (1.0 - smoothstep(0.0, 0.015 + heat * 0.02, c2.x)) * heat * heat * smoothstep(0.4, 0.75, noise(wpos.xz * 0.6));
	float cr = max(crack * (1.0 - ashk * 0.8), crack2 * 0.8);
	float pulse = 0.65 + 0.35 * sin(TIME * 1.6 + hash(c1.yz) * 6.28);
	col = mix(col, vec3(0.03, 0.012, 0.008), smoothstep(0.0, 0.5, cr) * 0.85);
	col = mix(col, vec3(0.02, 0.015, 0.015), (1.0 - smoothstep(0.0, wide * 3.0, c1.x)) * patchy * brk * 0.3);   // scorched rims
	vec3 glow = mix(vec3(1.0, 0.22, 0.03), vec3(1.0, 0.45, 0.08), heat) * cr * pulse * (0.9 + heat * 0.9) * dim;
	glow += vec3(1.0, 0.3, 0.05) * smoothstep(1.2, -0.2, ld) * 1.5 * dim;   // right at the lava's edge
	if (night > 0.5) { col *= vec3(0.75, 0.72, 0.8); glow *= 1.3; }
	// The Caldera Eruption coming: the cracks race open and pulse red, faster as it nears
	if (flood_warn > 0.0) {
		float fp = 0.5 + 0.5 * sin(TIME * mix(4.0, 13.0, flood_warn));
		glow += vec3(1.0, 0.12, 0.02) * (cr * 2.5 + 0.18) * flood_warn * fp;
		col = mix(col, vec3(0.3, 0.04, 0.02), flood_warn * 0.35 * fp);
	}
	float rough = mix(0.95, 0.8, pah);
	// ...and when it lands, the floor is molten
	if (flood > 0.0) {
		vec3 mo = molten(wpos.xz, TIME);
		col = mix(col, vec3(0.08, 0.03, 0.02), flood);
		glow = mix(glow, mo * 1.8, flood);
		rough = mix(rough, 0.4, flood);
	}
	if (quake > 0.0) {
		float qp = 0.5 + 0.5 * sin(TIME * mix(5.0, 14.0, quake_fill));
		col = mix(col, vec3(1.0, 0.12, 0.04), quake * (0.45 + 0.25 * qp));
		glow += vec3(1.0, 0.12, 0.04) * quake * (0.25 + 0.6 * quake_fill * qp);
	}
	ALBEDO = col;
	EMISSION = glow;
	ROUGHNESS = rough;
	SPECULAR = 0.3 + smoothstep(4.0, 0.0, ld) * 0.25;
}
"""

## Lava: dark crust plates drifting on the flow over molten rock, glowing seams between them,
## bright upwellings, a heat shimmer. UV = (metres across, metres along) on rivers and falls;
## pools use the world position and swirl slowly.
const LAVA_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float flow = 0.5;        // metres a second along UV.y
uniform float pool = 0.0;        // 1: a pool (world-space, slow swirl)
uniform float fall = 0.0;        // 1: a falling sheet (fast, streaky)
uniform float dim = 1.0;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
vec3 cells(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float d1 = 8.0; float d2 = 8.0; vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + vec2(hash(i + o), hash(i + o + 17.3)) - f;
			float dd = dot(r, r);
			if (dd < d1) { d2 = d1; d1 = dd; id = i + o; } else if (dd < d2) { d2 = dd; }
		}
	}
	return vec3(sqrt(d2) - sqrt(d1), id);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p;
	if (pool > 0.5) {
		float a = TIME * 0.02;
		p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * wpos.xz * 0.75;
	} else {
		p = vec2(UV.x * 0.7, UV.y * 0.7 - TIME * flow * 0.7 * (1.0 + fall * 4.0));
		if (fall > 0.5) { p.x *= 2.5; }
	}
	vec2 warp = vec2(noise(p * 0.7 + TIME * 0.1), noise(p * 0.7 - TIME * 0.08)) - 0.5;
	vec3 c = cells(p + warp * 1.3);
	vec3 cf = cells(p * 2.6 + warp * 0.8 + 3.0);   // finer cracks breaking up the plates
	float h = hash(c.yz);
	float seam = 1.0 - smoothstep(0.0, 0.05 + 0.05 * noise(p * 2.0), c.x);
	float fine_seam = (1.0 - smoothstep(0.0, 0.05, cf.x)) * 0.6;
	float crusted = smoothstep(0.15, 0.32, h) * (1.0 - fall * 0.7);
	vec3 hot = mix(vec3(1.0, 0.24, 0.03), vec3(1.0, 0.55, 0.12), noise(p * 1.3 + TIME * 0.3));
	float bub = smoothstep(0.86, 0.97, noise(p * 3.0 + vec2(0.0, TIME * 0.5))) * (1.0 - crusted);   // bright upwellings
	vec3 crust = vec3(0.06, 0.03, 0.022) * (0.6 + 0.7 * noise(p * 4.0));
	float lit = mix(0.85 + 0.3 * noise(p * 0.8 - TIME * 0.2), 0.04, crusted * (1.0 - max(seam, fine_seam)));
	vec3 em = hot * lit * 1.7 + hot * max(seam, fine_seam) * crusted * 0.9 + vec3(1.0, 0.7, 0.35) * bub * 1.2;
	em *= 0.85 + 0.15 * sin(TIME * 2.0 + h * 6.28);
	if (fall > 0.5) {   // the falling sheet: streaks racing down it, darker crusted ribbons
		float streak = noise(vec2(UV.x * 2.2, UV.y * 0.35 - TIME * 2.6)) * 0.6 + noise(vec2(UV.x * 5.0, UV.y * 0.9 - TIME * 3.4)) * 0.4;
		em *= 0.25 + 1.3 * streak * streak;
		crusted = max(crusted, smoothstep(0.62, 0.8, 1.0 - streak) * 0.8);
	}
	ALBEDO = mix(hot * 0.3, crust, crusted * (1.0 - seam));
	EMISSION = em * dim;
	ROUGHNESS = mix(0.35, 0.95, crusted);
	SPECULAR = 0.4;
}
"""


static func build(parent: Node3D, rng: RandomNumberGenerator, half: float) -> SwampWater:
	active = true
	var pick: String = TIMES[rng.randi() % TIMES.size()]
	time_of_day = force_time if SKY.has(force_time) else pick
	lava_mats.clear()
	_environment(parent, rng, time_of_day)
	var night := time_of_day == "night"

	var water := SwampWater.generate(rng, 0, half, 40.0)   # no swamp pools: the lava is ours
	_layout(rng, half)
	var extra: Array = []
	for p in pools:
		extra.append([p["c"], float(p["r"]) * 1.25 + BANK + 2.0])
	extra.append([FORGE_AT, FORGE_HALF.length() + 4.0])
	water.build_terrain(rng, half, WorldBuilder.CHEST_SITES + 16, ChestManager.SITE_RADIUS, extra)
	_lift(water)
	_sightline(water)
	_river_levels(water, rng)
	_lava_field(water)
	_dry_sites(water)
	_carve(water)
	_bake_cone(water)
	var img := Image.create_from_data(water.hsize, water.hsize, false, Image.FORMAT_RF, water.hgrid.to_byte_array())
	water.height_texture = ImageTexture.create_from_image(img)
	var patches := WorldBuilder._patch_map(rng, half + 10.0)
	_ground(parent, half, water, patches)
	_lava_meshes(parent)
	CalderaEdge.build(parent, half, night, rng)

	# Set pieces: the forge-temple, the lava falls, the sunken colossus, crossings
	var fy := water.ground_height(FORGE_AT.x, FORGE_AT.y)
	forge = {"at": Vector3(FORGE_AT.x, fy, FORGE_AT.y), "yaw": atan2(-FORGE_AT.x, -FORGE_AT.y)}   # its door faces the start
	var ft := CalderaProps.forge_temple(rng, night)
	ft.name = "ForgeTemple"   # no-i18n
	ft.position = forge["at"]
	ft.rotation.y = float(forge["yaw"])
	parent.add_child(ft)
	for p in pools:
		if p["kind"] == "statue":
			var c: Vector2 = p["c"]
			statue = {"at": Vector3(c.x, float(p["lv"]), c.y)}
			var st := CalderaProps.smith_statue(rng)
			var body := StaticBody3D.new()
			body.name = "SmithGod"   # no-i18n
			body.position = statue["at"] + Vector3(0, -1.6, 0)
			body.rotation.y = atan2(-c.x, -c.y) + rng.randf_range(-0.5, 0.5)
			var mi := MeshInstance3D.new()
			mi.mesh = st["mesh"]
			body.add_child(mi)
			for col in st["colliders"]:
				body.add_child(DesertProps._shape_node(col))
			parent.add_child(body)
	var fr := CalderaProps.falls_ridge(rng, falls)
	fr.name = "LavaFalls"   # no-i18n
	parent.add_child(fr)
	_crossings(parent, water, rng)
	_lair_road(parent, water, rng, night)

	_scatter(parent, rng, half, water, patches)
	var placed: Array[Vector3] = []
	var n_standing := 0
	while n_standing < STANDING:
		var p := _free_point(rng, half - 8.0, 16.0, water, placed, 5.0)
		var kind := n_standing % 10
		var data: Dictionary
		var burn := false
		match kind:
			0, 1, 9:
				data = CalderaProps.charred_tree(rng)
				burn = true
			2: data = CalderaProps.petrified_tree(rng)
			3: data = CalderaProps.column_cluster(rng)
			4: data = CalderaProps.obsidian_shard(rng)
			5, 6: data = CalderaProps.scoria_boulders(rng)
			7: data = CalderaProps.sulphur_vent(rng)
			_: data = CalderaProps.hornito(rng)
		p.y = WorldBuilder._low_point(water, p, 1.0) - (0.15 if burn else 0.3)
		var s := rng.randf_range(0.85, 1.2) if burn else 1.0   # (Jolt can't scale stone props' sphere shapes)
		WorldBuilder._prop(parent, data, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * (rng.randf_range(0.9, 1.12) if burn else 1.0), s)), p), burn)
		if kind == 7:   # the vent steams
			parent.add_child(CalderaProps.steam(p + Vector3(0, 0.6 * s, 0), 0.6, 14, night))
		elif kind == 8 and n_standing % 20 == 8:
			parent.add_child(CalderaProps.embers(p + Vector3(0, 2.4 * s, 0), 0.4, 10))
		placed.append(p)
		n_standing += 1

	for i in LYING:
		var data: Dictionary
		var burn := false
		match i % 6:
			0: data = CalderaProps.fallen_columns(rng)
			1:
				data = CalderaProps.charred_log(rng)
				burn = true
			2: data = CalderaProps.lava_lobe(rng)
			3: data = CalderaProps.beast_bones(rng)
			4: data = CalderaProps.forge_debris(rng)
			_: data = CalderaProps.lava_bomb_rock(rng)
		var length: float = data.get("length", 3.0)
		var p := _free_point(rng, half - length * 0.5 - 6.0, 14.0, water, placed, length * 0.5 + 2.0)
		p.y = WorldBuilder._low_point(water, p, length * 0.35) - float(data.get("sink", 0.15))
		WorldBuilder._prop(parent, data, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), burn)
		placed.append(p)

	for i in LANDMARKS:
		var p := _free_point(rng, half - 16.0, 26.0, water, placed, 9.0)
		p.y = WorldBuilder._low_point(water, p, 2.5) - 0.2
		var lm := CalderaProps.landmark(rng, i, night)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		WorldBuilder._prop(parent, lm, xf)
		var lb := parent.get_child(parent.get_child_count() - 1)
		lb.add_to_group("obstacle")
		lb.set_meta("reach", 3.0)
		lb.set_meta("kind", lm.get("kind", ""))
		for fx in lm.get("fx", []):   # flames over braziers, steam over fumaroles (local -> world)
			var node: Node3D = fx
			node.position = xf * node.position
			parent.add_child(node)
		placed.append(p)
	parent.add_child(CalderaAmbience.new())
	return water


# ------------------------------------------------------------------ layout

## Pools (the great pool, the falls' plunge pool, a few side pools, the biggest holding the
## colossus), the falls on the northern ridge, and three rivers: falls -> great pool, the great
## pool -> the eastern cliffs, and one winding west to east across the south.
static func _layout(rng: RandomNumberGenerator, half: float) -> void:
	pools.clear()
	rivers.clear()
	stones.clear()
	bridges.clear()
	var pc := POOL_AT + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 4))
	pools.append(_pool(rng, pc, POOL_R, "great"))
	var fx := rng.randf_range(-70.0, 30.0)
	var fdir := Vector2(0, 1)
	falls = {"at": Vector3(fx, 0, -half + 30.0), "dir": fdir}
	var plunge := Vector2(fx, -half + 44.0)
	pools.append(_pool(rng, plunge, 7.0, "plunge"))
	var side_kind := ["statue", "side", "side"]
	var tries := 0
	while pools.size() < 5 and tries < 400:
		tries += 1
		var c := Vector2(rng.randf_range(-half + 50, half - 50), rng.randf_range(-half + 70, half - 50))
		if c.length() < 62.0 or c.distance_to(FORGE_AT) < 40.0:
			continue
		var ok := true
		for p in pools:
			if c.distance_to(p["c"]) < 75.0:
				ok = false
		if not ok:
			continue
		var big: bool = side_kind[pools.size() - 2] == "statue"
		pools.append(_pool(rng, c, rng.randf_range(12.0, 14.0) if big else rng.randf_range(7.5, 10.5), side_kind[pools.size() - 2]))
	# River A: the falls' plunge pool down to the great pool, meandering
	var a_pts: Array[Vector2] = [plunge + Vector2(0, 5.0)]
	var steps := 4
	for k in range(1, steps):
		var t := float(k) / steps
		var m := plunge.lerp(pc, t)
		a_pts.append(m + Vector2(rng.randf_range(-16.0, 16.0), 0))
	a_pts.append(pc + (plunge - pc).normalized() * (POOL_R - 2.0))
	_add_river(a_pts, rng.randf_range(2.6, 3.1), "a")
	# River B: west to east across the south, keeping well clear of the start
	var zb := rng.randf_range(58.0, 92.0)
	var b_pts: Array[Vector2] = []
	for k in 7:
		var x := -half - 4.0 + (half * 2.0 + 8.0) * k / 6.0
		var z := zb + rng.randf_range(-22.0, 22.0) * (1.0 if k > 0 and k < 6 else 0.4)
		b_pts.append(Vector2(x, z))
	_add_river(b_pts, rng.randf_range(2.8, 3.5), "b")
	# River C: out of the great pool's east side to the eastern cliffs
	var c_pts: Array[Vector2] = [pc + Vector2(POOL_R - 2.0, 2.0)]
	var cz := pc.y + rng.randf_range(-30.0, 10.0)
	for k in range(1, 5):
		var x := pc.x + POOL_R + (half + 6.0 - pc.x - POOL_R) * k / 4.0
		c_pts.append(Vector2(x, lerpf(pc.y, cz, float(k) / 4.0) + rng.randf_range(-14.0, 14.0)))
	_add_river(c_pts, rng.randf_range(2.4, 3.0), "c")
	# the cinder cone stands in whichever corner is furthest from the rivers, the falls and the forge
	var best := -1.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector2(sx * 150.0, sz * 150.0) + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
			var dmin := c.distance_to(FORGE_AT)
			dmin = minf(dmin, c.distance_to(Vector2(fx, -half + 30.0)))
			for rv in rivers:
				for q in rv["pts"]:
					dmin = minf(dmin, c.distance_to(q))
			if dmin > best:
				best = dmin
				cone = {"c": c, "r": CONE_R, "crater": CONE_CRATER, "h": CONE_H}
	# keep rivers out of other pools' way, the forge and the cone
	for rv in rivers:
		var pts: PackedVector2Array = rv["pts"]
		var keep_out: Array = []
		for p in pools:
			if p["kind"] != "great" and p["kind"] != "plunge":
				keep_out.append([p["c"], float(p["r"]) + 12.0])
		keep_out.append([FORGE_AT, FORGE_HALF.length() + 10.0])
		keep_out.append([Vector2.ZERO, 30.0])
		keep_out.append([cone["c"], CONE_R + 10.0])
		for k in pts.size():
			var q := pts[k]
			for ko in keep_out:
				var kc: Vector2 = ko[0]
				var kr: float = ko[1]
				var d := q.distance_to(kc)
				if d < kr:
					q = kc + (q - kc).normalized() * kr
			pts[k] = q
		rv["pts"] = _resample(_smooth_pts(pts, 6), 1.0)


static func _pool(rng: RandomNumberGenerator, c: Vector2, r: float, kind: String) -> Dictionary:
	var amps := PackedFloat32Array()
	var phases := PackedFloat32Array()
	for k in 4:
		amps.append(rng.randf_range(0.02, 0.09) / (1.0 + k * 0.5))
		phases.append(rng.randf() * TAU)
	return {"c": c, "r": r, "amps": amps, "phases": phases, "kind": kind, "lv": 0.0}


static func outline_radius(p: Dictionary, th: float) -> float:
	var amps: PackedFloat32Array = p["amps"]
	var phases: PackedFloat32Array = p["phases"]
	var s := 1.0
	for k in 4:
		s += amps[k] * sin((k + 2) * th + phases[k])
	return float(p["r"]) * s


static func _add_river(ctrl: Array[Vector2], w: float, id: String) -> void:
	# Catmull-Rom through the control points, then even 1 m samples
	var dense := PackedVector2Array()
	for k in ctrl.size() - 1:
		var p0: Vector2 = ctrl[maxi(k - 1, 0)]
		var p1: Vector2 = ctrl[k]
		var p2: Vector2 = ctrl[k + 1]
		var p3: Vector2 = ctrl[mini(k + 2, ctrl.size() - 1)]
		var seg := int(maxf(4.0, p1.distance_to(p2) / 2.0))
		for s in seg:
			var t := float(s) / seg
			var t2 := t * t
			var t3 := t2 * t
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	dense.append(ctrl[ctrl.size() - 1])
	rivers.append({"id": id, "pts": dense, "w": w, "bridges": [], "stones": []})


static func _smooth_pts(pts: PackedVector2Array, passes: int) -> PackedVector2Array:
	var out := pts.duplicate()
	for p in passes:
		var nx := out.duplicate()
		for k in range(1, out.size() - 1):
			nx[k] = (out[k - 1] + out[k] * 2.0 + out[k + 1]) * 0.25
		out = nx
	return out


static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	var acc := 0.0
	for k in range(1, pts.size()):
		var a := pts[k - 1]
		var b := pts[k]
		var d := a.distance_to(b)
		var t := step - acc
		while t <= d:
			out.append(a.lerp(b, t / d))
			t += step
		acc = d - (t - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > 0.3:
		out.append(pts[pts.size() - 1])
	return out


# ------------------------------------------------------------------ terrain

## The great pool sits in a basin below the start and the ground between is graded into an even
## slope, so Singe's lair (and the falls beyond it) is in view as you land.
static func _sightline(water: SwampWater) -> void:
	var g := water.hgrid
	var hs := water.hsize
	var ho := water.horigin
	var great: Dictionary = pools[0]
	var pc: Vector2 = great["c"]
	var start_h := water.ground_height(0.0, 0.0)
	var pool_h := water.ground_height(pc.x, pc.y)
	var drop := maxf(0.0, pool_h - (start_h - 3.0))
	var r0 := float(great["r"]) * 1.25 + BANK
	if drop > 0.0:
		var reach := r0 + 22.0
		for zi in range(maxi(0, int(pc.y - reach - ho)), mini(hs, int(pc.y + reach - ho) + 2)):
			for xi in range(maxi(0, int(pc.x - reach - ho)), mini(hs, int(pc.x + reach - ho) + 2)):
				var d := Vector2(ho + xi, ho + zi).distance_to(pc)
				g[zi * hs + xi] -= drop * (1.0 - smoothstep(r0, reach, d))
	pool_h -= drop
	var z_from := -10.0
	var z_to := pc.y + r0
	for zi in range(maxi(0, int(z_to - 4.0 - ho)), mini(hs, int(z_from + 6.0 - ho) + 1)):
		var z := ho + zi
		var t := clampf((z_from - z) / (z_from - z_to), 0.0, 1.0)
		var target := lerpf(start_h, pool_h + 0.2, t)
		var fade := smoothstep(z_from + 6.0, z_from, z) * smoothstep(z_to - 4.0, z_to, z)
		for xi in range(maxi(0, int(-18.0 - ho)), mini(hs, int(18.0 - ho) + 1)):
			var x := ho + xi
			var w := (1.0 - smoothstep(8.0, 18.0, absf(x - pc.x * t))) * fade
			for site in water.chest_sites:
				if Vector2(x - site.x, z - site.z).length() < ChestManager.SITE_RADIUS + 6.0:
					w = 0.0
			var k := zi * hs + xi
			g[k] = lerpf(g[k], target, w)
	water.hgrid = g

## Lift the whole ground so even the deepest lava bed stays well above 0 (no swamp water).
static func _lift(water: SwampWater) -> void:
	var g := water.hgrid
	var lo := INF
	for k in g.size():
		lo = minf(lo, g[k])
	var off := 2.2 - lo
	for k in g.size():
		g[k] += off
	water.hgrid = g
	for k in water.pads.size():
		water.pads[k][2] = float(water.pads[k][2]) + off
	for k in water.chest_sites.size():
		var cs: Vector3 = water.chest_sites[k]
		cs.y += off
		water.chest_sites[k] = cs


static func _gh(water: SwampWater, x: float, z: float) -> float:
	return water.ground_height(x, z)


## The lava's surface height along each river: the ground along it, smoothed (and blended into
## the pools it joins), less LAVA_BELOW. Pools sit LAVA_BELOW under their level pads.
static func _river_levels(water: SwampWater, rng: RandomNumberGenerator) -> void:
	for p in pools:
		var c: Vector2 = p["c"]
		p["lv"] = _gh(water, c.x, c.y) - LAVA_BELOW
	for rv in rivers:
		var pts: PackedVector2Array = rv["pts"]
		var raw := PackedFloat32Array()
		for q in pts:
			raw.append(_gh(water, q.x, q.y))
		var sm := raw
		for pass_k in 3:
			var nx := PackedFloat32Array()
			nx.resize(sm.size())
			for k in sm.size():
				var acc := 0.0
				var n := 0
				for j in range(maxi(0, k - 8), mini(sm.size(), k + 9)):
					acc += sm[j]
					n += 1
				nx[k] = acc / n
			sm = nx
		var lv := PackedFloat32Array()
		lv.resize(sm.size())
		for k in sm.size():
			lv[k] = sm[k] - LAVA_BELOW
		# blend into any pool the river starts or ends in
		for p in pools:
			var c: Vector2 = p["c"]
			var reach := float(p["r"]) + 26.0
			for k in pts.size():
				var d := pts[k].distance_to(c)
				if d < reach:
					var w := 1.0 - smoothstep(float(p["r"]), reach, d)
					lv[k] = lerpf(lv[k], float(p["lv"]), w)
		rv["lv"] = lv
		# crossings: two rock bridges and two lines of stepping stones, spread along it
		var n_pts := pts.size()
		var spots: Array = []
		for k in 4:
			spots.append(int(n_pts * (0.16 + 0.22 * k)) + rng.randi_range(-6, 6))
		var br: Array = []
		var st: Array = []
		for k in spots.size():
			var s: int = clampi(spots[k], 12, n_pts - 13)
			# never on the edge berm or in a pool
			var q := pts[s]
			if absf(q.x) > 190.0 or absf(q.y) > 190.0:
				continue
			var in_pool := false
			for p in pools:
				if q.distance_to(p["c"]) < float(p["r"]) + 8.0:
					in_pool = true
			if in_pool:
				continue
			if k % 2 == 0:
				br.append(s)
			else:
				st.append(s)
		rv["bridges"] = br
		rv["stones"] = st


## Stamp the lava's distance field, surface level and bridges into 1 m grids.
static func _lava_field(water: SwampWater) -> void:
	_hs = water.hsize
	_ho = water.horigin
	var n := _hs * _hs
	ldist.resize(n)
	ldist.fill(99.0)
	llev.resize(n)
	llev.fill(LAVA_NONE)
	lbridge.resize(n)
	lbridge.fill(0.0)
	var reach := BANK + LEVEE + 1.0
	for rv in rivers:
		var pts: PackedVector2Array = rv["pts"]
		var lv: PackedFloat32Array = rv["lv"]
		var w: float = rv["w"]
		var br: Array = rv["bridges"]
		for k in pts.size():
			var q := pts[k]
			var bw := 0.0
			for s in br:
				bw = maxf(bw, 1.0 - smoothstep(BRIDGE_HALF - 0.5, BRIDGE_HALF + 1.5, absf(float(k - int(s)))))
			var r := w + reach
			for zi in range(maxi(0, int(q.y - r - _ho)), mini(_hs, int(q.y + r - _ho) + 2)):
				for xi in range(maxi(0, int(q.x - r - _ho)), mini(_hs, int(q.x + r - _ho) + 2)):
					var dx := _ho + xi - q.x
					var dz := _ho + zi - q.y
					var dd := sqrt(dx * dx + dz * dz) - w
					var c := zi * _hs + xi
					if dd < ldist[c]:
						ldist[c] = dd
						llev[c] = lv[k]
					if bw > 0.0 and dd < BANK + 1.0:
						lbridge[c] = maxf(lbridge[c], bw)
	for p in pools:
		var pc: Vector2 = p["c"]
		var r := float(p["r"]) * 1.3 + reach
		for zi in range(maxi(0, int(pc.y - r - _ho)), mini(_hs, int(pc.y + r - _ho) + 2)):
			for xi in range(maxi(0, int(pc.x - r - _ho)), mini(_hs, int(pc.x + r - _ho) + 2)):
				var dx := _ho + xi - pc.x
				var dz := _ho + zi - pc.y
				var dd := sqrt(dx * dx + dz * dz) - outline_radius(p, atan2(dz, dx))
				var c := zi * _hs + xi
				if dd < ldist[c]:
					ldist[c] = dd
					llev[c] = float(p["lv"])
					lbridge[c] = 0.0


static func _cell(x: float, z: float) -> int:
	if _hs == 0:
		return -1
	var xi := int(round(x - _ho))
	var zi := int(round(z - _ho))
	if xi < 0 or zi < 0 or xi >= _hs or zi >= _hs:
		return -1
	return zi * _hs + xi


## Metres from the lava's edge at XZ (negative inside; 99 far away).
static func lava_dist(x: float, z: float) -> float:
	var c := _cell(x, z)
	return ldist[c] if c >= 0 else 99.0


## The lava's surface height at XZ if this spot is in (or at the edge of) the lava, else LAVA_NONE.
static func lava_level(x: float, z: float) -> float:
	var c := _cell(x, z)
	if c < 0 or ldist[c] > BANK or lbridge[c] > 0.5:
		return LAVA_NONE
	return llev[c]


## Are feet at `p` in the lava (below its surface where the ground dips under it)?
static func in_lava(p: Vector3) -> bool:
	if not active:
		return false
	var lv := lava_level(p.x, p.z)
	if lv <= LAVA_NONE + 1.0:
		return false
	return p.y < lv + 0.22 and SwampWater.height_at(p.x, p.z) < lv + 0.02


static func near_lava(x: float, z: float, margin: float) -> bool:
	return lava_dist(x, z) < margin


## Chest sites well clear of the lava (and not on the forge), back to the usual count.
static func _dry_sites(water: SwampWater) -> void:
	var keep: Array[Vector3] = []
	for s in water.chest_sites:
		if lava_dist(s.x, s.z) < ChestManager.SITE_RADIUS + BANK + LEVEE + 4.0:
			continue
		if absf(s.x - FORGE_AT.x) < FORGE_HALF.x + 8.0 and absf(s.z - FORGE_AT.y) < FORGE_HALF.y + 8.0:
			continue
		if on_cone(s.x, s.z, 10.0):
			continue
		if keep.size() < WorldBuilder.CHEST_SITES:
			keep.append(s)
	water.chest_sites = keep


## Cut the channels and pool bowls into the height grid: a bed LAVA_DEPTH under the lava, banks
## up to just over its surface, levees where the ground was lower than the lava; then ease any
## bank too steep to walk, and hump the ground over the rock bridges.
static func _carve(water: SwampWater) -> void:
	var g := water.hgrid
	var orig := g.duplicate()
	for c in g.size():
		var dd := ldist[c]
		if dd > BANK + LEVEE:
			continue
		var lv := llev[c]
		var top := lv + LAVA_BELOW
		var bed := lv - LAVA_DEPTH
		var h := g[c]
		if dd < 0.0:
			var deep := 0.0
			if dd < -2.0:   # pools get deeper toward the middle
				deep = clampf((-dd - 2.0) * 0.06, 0.0, 0.6)
			h = bed - deep
		elif dd < BANK:
			var t := smoothstep(0.0, BANK, dd)
			h = lerpf(bed, maxf(h, top + 0.12), t)
		else:
			var t := smoothstep(BANK, BANK + LEVEE, dd)
			h = maxf(h, lerpf(top + 0.12, h, t))
		g[c] = h
	# ease the banks: nothing outside the lava stands more than 0.85 m over a neighbour
	var hs := water.hsize
	for it in 8:
		for zi in range(1, hs - 1):
			for xi in range(1, hs - 1):
				var c := zi * hs + xi
				if ldist[c] < 0.3 or ldist[c] > BANK + LEVEE + 6.0:
					continue
				var lo := minf(minf(g[c - 1], g[c + 1]), minf(g[c - hs], g[c + hs]))
				if g[c] > lo + 0.85:
					g[c] = lo + 0.85
	# rock bridges: the channel left uncut, the ground humped a little over it
	for c in g.size():
		var bw := lbridge[c]
		if bw > 0.0:
			var lv := llev[c]
			g[c] = lerpf(g[c], maxf(orig[c], lv + 0.95), bw)
	water.hgrid = g


## Is XZ on (or within `margin` of) the cinder cone?
static func on_cone(x: float, z: float, margin: float) -> bool:
	if cone.is_empty():
		return false
	var c: Vector2 = cone["c"]
	return Vector2(x, z).distance_to(c) < float(cone["r"]) + margin


## Bake the cinder cone into the height grid: concave flanks steepening to a jagged rim round a
## crater bowl. The ground shader textures it like the rest of the floor (ash, glowing cracks).
static func _bake_cone(water: SwampWater) -> void:
	var g := water.hgrid
	var hs := water.hsize
	var ho := water.horigin
	var c: Vector2 = cone["c"]
	var base := water.ground_height(c.x, c.y)
	var rr := CONE_R + 2.0
	for zi in range(maxi(0, int(c.y - rr - ho)), mini(hs, int(c.y + rr - ho) + 2)):
		for xi in range(maxi(0, int(c.x - rr - ho)), mini(hs, int(c.x + rr - ho) + 2)):
			var d := Vector2(ho + xi, ho + zi).distance_to(c)
			if d >= CONE_R:
				continue
			var h := 0.0
			if d > CONE_CRATER:
				var t := (d - CONE_CRATER) / (CONE_R - CONE_CRATER)
				h = CONE_H * pow(1.0 - t, 1.6)
			else:
				h = CONE_H - 4.0 * (1.0 - pow(d / CONE_CRATER, 2.0))
			var k := zi * hs + xi
			g[k] = maxf(g[k], base + h)
	water.hgrid = g
	cone["at"] = Vector3(c.x, base, c.y)
	cone["top"] = Vector3(c.x, base + CONE_H, c.y)


# ------------------------------------------------------------------ lava surfaces

static func lava_material(kind: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = LAVA_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("pool", 1.0 if kind == "pool" else 0.0)
	m.set_shader_parameter("fall", 1.0 if kind == "fall" else 0.0)
	m.set_shader_parameter("dim", 1.0)
	lava_mats.append(m)
	return m


static func _lava_meshes(parent: Node3D) -> void:
	var river_mat := lava_material("river")
	var pool_mat := lava_material("pool")
	for rv in rivers:
		var pts: PackedVector2Array = rv["pts"]
		var lv: PackedFloat32Array = rv["lv"]
		var w: float = rv["w"]
		var br: Array = rv["bridges"]
		var span := w + BANK * 0.65
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var prev_ok := false
		var pa := Vector3.ZERO
		var pb := Vector3.ZERO
		for k in pts.size():
			var under := false
			for s in br:
				if absf(float(k - int(s))) < BRIDGE_HALF - 0.4:
					under = true
			var fwd := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
			var side := Vector2(-fwd.y, fwd.x)
			var y := lv[k]
			var a := Vector3(pts[k].x - side.x * span, y, pts[k].y - side.y * span)
			var b := Vector3(pts[k].x + side.x * span, y, pts[k].y + side.y * span)
			if prev_ok and not under:
				var v0 := float(k - 1)
				var v1 := float(k)
				for tri in [[pa, Vector2(0, v0)], [pb, Vector2(span * 2.0, v0)], [b, Vector2(span * 2.0, v1)], [pa, Vector2(0, v0)], [b, Vector2(span * 2.0, v1)], [a, Vector2(0, v1)]]:
					st.set_normal(Vector3.UP)
					st.set_uv(tri[1])
					st.add_vertex(tri[0])
			prev_ok = not under
			pa = a
			pb = b
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = river_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "LavaRiver_%s" % rv["id"]   # no-i18n
		mi.add_to_group("lava")
		parent.add_child(mi)
	for p in pools:
		var c: Vector2 = p["c"]
		var y: float = p["lv"]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var seg := 72
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var r0 := outline_radius(p, t0) + BANK * 0.65
			var r1 := outline_radius(p, t1) + BANK * 0.65
			for v in [Vector3(c.x, y, c.y), Vector3(c.x + cos(t1) * r1, y, c.y + sin(t1) * r1), Vector3(c.x + cos(t0) * r0, y, c.y + sin(t0) * r0)]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v.x, v.z))
				st.add_vertex(v)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = pool_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "LavaPool_%s" % p["kind"]   # no-i18n
		mi.add_to_group("lava")
		parent.add_child(mi)
		# the pool lights its surroundings
		if p["kind"] != "plunge":
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.42, 0.12)
			l.light_energy = 2.4 if p["kind"] == "great" else 1.6
			l.omni_range = float(p["r"]) * 2.2
			l.shadow_enabled = false
			l.position = Vector3(c.x, y + 3.0, c.y)
			l.add_to_group("lava_light")
			parent.add_child(l)


## Dim every lava surface and the ground's glow to `k` over `secs` (Singe's death).
static func dim_lava(tree_node: Node, k: float, secs: float) -> void:
	var tw := tree_node.create_tween().set_parallel(true)
	var mats: Array = lava_mats.duplicate()
	if ground_mat != null:
		mats.append(ground_mat)
	for m in mats:
		var sm: ShaderMaterial = m
		tw.tween_method(func(v: float) -> void: sm.set_shader_parameter("dim", v), 1.0, k, secs)
	for l in tree_node.get_tree().get_nodes_in_group("lava_light"):
		tw.tween_property(l, "light_energy", (l as OmniLight3D).light_energy * k, secs)


# ------------------------------------------------------------------ crossings

## Rock bridges (an arch of rock under the humped ground, the lava pouring through) and lines of
## basalt stepping stones (solid hexagonal columns, tops just over the lava).
static func _crossings(parent: Node3D, water: SwampWater, rng: RandomNumberGenerator) -> void:
	for rv in rivers:
		var pts: PackedVector2Array = rv["pts"]
		var lv: PackedFloat32Array = rv["lv"]
		var w: float = rv["w"]
		for s in rv["bridges"]:
			var k: int = s
			var fwd := (pts[mini(k + 2, pts.size() - 1)] - pts[maxi(k - 2, 0)]).normalized()
			var at := Vector3(pts[k].x, lv[k], pts[k].y)
			var arch := CalderaProps.rock_arch(rng, w + BANK, BRIDGE_HALF)
			var body := StaticBody3D.new()
			body.name = "RockBridge"   # no-i18n
			body.position = at
			body.rotation.y = atan2(fwd.x, fwd.y)
			var mi := MeshInstance3D.new()
			mi.mesh = arch["mesh"]
			body.add_child(mi)
			body.add_to_group("rock_bridge")
			parent.add_child(body)
			var deck := Vector3(at.x, water.ground_height(at.x, at.z), at.z)
			bridges.append({"at": deck, "dir": fwd})
		for s in rv["stones"]:
			var k: int = s
			var fwd := (pts[mini(k + 2, pts.size() - 1)] - pts[maxi(k - 2, 0)]).normalized()
			var side := Vector2(-fwd.y, fwd.x)
			var top := lv[k] + LAVA_BELOW + 0.1
			var reach := w + BANK * 0.55 + 0.6
			var n := int(ceil(reach * 2.0 / STONE_STEP)) + 1
			var mb := MeshBuilder.new()
			var body := StaticBody3D.new()
			body.name = "SteppingStones"   # no-i18n
			body.add_to_group("stepping_stones")
			for j in n:
				var off := -reach + j * (reach * 2.0 / (n - 1))
				var c := pts[k] + side * off + fwd * rng.randf_range(-0.12, 0.12)
				var ty := top + rng.randf_range(-0.04, 0.05)
				var r := STONE_R * rng.randf_range(0.95, 1.08)
				var bottom := lv[k] - LAVA_DEPTH - 0.8
				var p := Vector3(c.x, (ty + bottom) * 0.5, c.y)
				CalderaProps.hex_column(mb, Vector3(c.x, bottom, c.y), r, ty - bottom, rng.randf() * TAU, rng, true)
				var cs := CollisionShape3D.new()
				var shape := CylinderShape3D.new()
				shape.radius = r
				shape.height = ty - bottom
				cs.shape = shape
				cs.position = p
				body.add_child(cs)
				stones.append(Vector3(c.x, ty, c.y))
			var mi := MeshInstance3D.new()
			mi.mesh = mb.commit(CalderaProps.rock_material())
			body.add_child(mi)
			parent.add_child(body)


## The dwarves' old road down to the great pool: hexagonal basalt paving following the graded
## slope (worn, a few flags missing, some cracked with lava glowing through), lined with stone
## posts bearing burning iron braziers, and a broken dwarf statue here and there.
static func _lair_road(parent: Node3D, water: SwampWater, rng: RandomNumberGenerator, night: bool) -> void:
	var great: Dictionary = pools[0]
	var pc: Vector2 = great["c"]
	var z_from := -11.0
	var z_to := pc.y + float(great["r"]) * 1.25 + BANK + 2.0
	var mb := MeshBuilder.new()
	var hr := 0.6
	var dz := hr * 1.5
	var dx := hr * 1.732
	var row := 0
	var z := z_from
	while z > z_to:
		var t := clampf((z_from - z) / (z_from - z_to), 0.0, 1.0)
		var cx := pc.x * t
		var x := -ROAD_W + (dx * 0.5 if row % 2 else 0.0)
		while x < ROAD_W:
			var px := cx + x
			var edge := absf(x) / ROAD_W
			if rng.randf() > 0.06 + edge * edge * 0.5:   # ragged edges, the odd flag gone
				var h := water.ground_height(px, z) + 0.05 - rng.randf_range(0.0, 0.05) - edge * 0.06
				var c := CalderaProps._shade(Color(0.17, 0.16, 0.16), rng, 0.2)
				c.a = CalderaProps.HOT if rng.randf() < 0.07 else CalderaProps.ROCK
				mb.add(MeshBuilder.cyl(hr * 0.94, hr * 0.97, 0.2, 6), Transform3D(Basis(Vector3.UP, PI / 6), Vector3(px, h, z)), c)
			x += dx
		z -= dz
		row += 1
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(CalderaProps.rock_material())
	mi.name = "LairRoad"   # no-i18n
	parent.add_child(mi)
	var k := 0
	z = z_from - 6.0
	while z > z_to + 3.0:
		var t := clampf((z_from - z) / (z_from - z_to), 0.0, 1.0)
		var cx := pc.x * t
		for sd in [-1.0, 1.0]:
			var p := Vector3(cx + sd * (ROAD_W + 1.4), 0, z)
			p.y = WorldBuilder._low_point(water, p, 0.6) - 0.1
			var post := CalderaProps.brazier_post(rng, k % 3 == 2)
			WorldBuilder._prop(parent, post, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
			if not post.get("broken", false):
				var fl := Abilities._flame_particles(0.6, 0.75, 22)
				fl.position = p + Vector3(0, 2.75, 0)
				parent.add_child(fl)
				if k % 2 == 0 and sd > 0.0:
					var l := OmniLight3D.new()
					l.light_color = Color(1.0, 0.55, 0.22)
					l.light_energy = 2.4 if night else 1.6
					l.omni_range = 11.0
					l.shadow_enabled = false
					l.position = Vector3(cx, p.y + 3.0, z)
					parent.add_child(l)
		k += 1
		z -= 9.0


## Is XZ on the lair road (plus `margin`)?
static func on_road(x: float, z: float, margin: float) -> bool:
	if pools.is_empty():
		return false
	var great: Dictionary = pools[0]
	var pc: Vector2 = great["c"]
	var z_from := -11.0
	var z_to := pc.y + float(great["r"]) * 1.25 + BANK + 2.0
	if z > z_from + margin or z < z_to - margin:
		return false
	var t := clampf((z_from - z) / (z_from - z_to), 0.0, 1.0)
	return absf(x - pc.x * t) < ROAD_W + 2.0 + margin


# ------------------------------------------------------------------ placement

static func _clear(p: Vector3, water: SwampWater, placed: Array[Vector3], spacing: float) -> bool:
	if Vector2(p.x, p.z).length() < 14.0 or lava_dist(p.x, p.z) < BANK + 1.5 + spacing * 0.3:
		return false
	if absf(p.x - FORGE_AT.x) < FORGE_HALF.x + 4.0 and absf(p.z - FORGE_AT.y) < FORGE_HALF.y + 4.0:
		return false
	if on_cone(p.x, p.z, 4.0) or on_road(p.x, p.z, 3.0):
		return false
	var fa: Vector3 = falls.get("at", Vector3(0, 0, -999))
	if Vector2(p.x - fa.x, p.z - fa.z).length() < 26.0:
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
	for attempt in 400:   # crowded: anywhere off the lava
		var q := Vector3(rng.randf_range(-extent, extent), 0.0, rng.randf_range(-extent, extent))
		if lava_dist(q.x, q.z) > BANK + 1.0 and q.length() > keep_out:
			q.y = water.ground_height(q.x, q.z)
			return q
	var r := Vector3(rng.randf_range(-extent, extent), 0.0, rng.randf_range(-extent, extent))
	r.y = water.ground_height(r.x, r.z)
	return r


# ------------------------------------------------------------------ sky, light, haze

static func _environment(parent: Node3D, rng: RandomNumberGenerator, time: String) -> void:
	var night := time == "night"
	var s: Dictionary = SKY[time]
	var sh := Shader.new()
	sh.code = WorldBuilder.SKY_SHADER
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("night", 0.0)
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
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_luminance_cap = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	env.fog_enabled = true
	env.fog_sky_affect = 0.35
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if night:
		env.ambient_light_color = Color(0.42, 0.24, 0.2)
		env.ambient_light_energy = 0.75
		env.fog_light_color = Color(0.2, 0.07, 0.04)
		env.fog_density = 0.008
		env.glow_intensity = 0.95
	else:
		env.ambient_light_color = Color(0.56, 0.44, 0.4)
		env.ambient_light_energy = 0.62
		env.fog_light_color = Color(0.3, 0.16, 0.11)
		env.fog_density = 0.0032
	var we := WorldEnvironment.new()
	we.environment = env
	we.name = "CalderaEnvironment"   # no-i18n
	parent.add_child(we)
	WorldBuilder._add_distant_castle(parent, env.fog_light_color, night)
	var az := deg_to_rad(200.0) + rng.randf_range(-0.4, 0.4)
	var el := deg_to_rad(rng.randf_range(24.0, 34.0) if not night else rng.randf_range(40.0, 50.0))
	var to_light := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
	var light := DirectionalLight3D.new()
	light.basis = Basis.looking_at(-to_light, Vector3.UP)
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 90.0
	light.light_color = Color(1.0, 0.78, 0.62)
	light.light_energy = 0.85
	if night:
		light.light_color = Color(0.8, 0.45, 0.4)
		light.light_energy = 0.35
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
	# the lava distance field as a texture (metres -4..16 in a byte)
	var bytes := PackedByteArray()
	bytes.resize(_hs * _hs)
	for c in _hs * _hs:
		bytes[c] = clampi(int((clampf(ldist[c], -4.0, 16.0) + 4.0) / 20.0 * 255.0), 0, 255)
	var limg := Image.create_from_data(_hs, _hs, false, Image.FORMAT_R8, bytes)
	sm.set_shader_parameter("lava_tex", ImageTexture.create_from_image(limg))
	sm.set_shader_parameter("h_origin", water.horigin)
	sm.set_shader_parameter("h_size", float(water.hsize))
	sm.set_shader_parameter("night", 1.0 if time_of_day == "night" else 0.0)
	for k in ["dim"]:
		sm.set_shader_parameter(k, 1.0)
	for k in ["flood", "flood_warn", "quake", "quake_fill"]:
		sm.set_shader_parameter(k, 0.0)
	mesh.surface_set_material(0, sm)
	water.ground_mat = sm
	ground_mat = sm
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	body.name = "CalderaGround"   # no-i18n
	parent.add_child(body)


# ------------------------------------------------------------------ ground scatter

## Pumice, ash drifts, scoria, singed tufts, embers and little glowing cracks, in chunks drawn
## only near the camera; denser glowing bits by the lava.
static func _scatter(parent: Node3D, rng: RandomNumberGenerator, half: float, water: SwampWater, patches: Image) -> void:
	var scatter := [["pumice", 2600, 0.6, 1.5], ["scoria", 4200, 0.6, 1.6], ["ash", 900, 0.8, 1.6], ["tuft", 1500, 0.7, 1.3],
		["ember", 2200, 0.7, 1.3], ["crack", 1100, 0.8, 1.5], ["sulphur", 500, 0.7, 1.3], ["stones", 900, 0.6, 1.4]]
	for sc in scatter:
		var chunks := {}
		var kind: String = sc[0]
		for k in int(sc[1]):
			var p := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
			var ld := lava_dist(p.x, p.y)
			if ld < 1.2 or p.length() < 4.0:
				continue
			if kind == "ember" or kind == "crack":   # mostly near the lava
				if ld > 14.0 and rng.randf() < 0.75:
					continue
			if kind == "tuft" and ld < 8.0:
				continue
			var s := rng.randf_range(float(sc[2]), float(sc[3]))
			var h := water.ground_height(p.x, p.y)
			var nrm := water.normal_at(p.x, p.y)
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			if kind != "tuft":
				basis = Basis(Quaternion(Vector3.UP, nrm)) * basis
			ForestBuilder._chunk_add(chunks, Transform3D(basis.scaled(Vector3.ONE * s), Vector3(p.x, h - 0.03, p.y)))
		ForestBuilder._chunk_meshes(parent, chunks, CalderaProps.scatter_mesh(kind, rng))
