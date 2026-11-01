class_name GraveyardBuilder
extends RefCounted
## The Haunted Graveyard: a vast old cemetery at night, on the same 440 m footprint and terrain
## generator as the Swamp and the Forest (gentle hills, a few murky ponds, level chest pads).
##
## Layout, like a real cemetery: two wide gravel avenues cross at the start point (a round
## plaza), and narrower winding paths every BLOCK metres split the ground into plots.
##   - Most plots hold ROWS of headstones facing a path, each over its grave (some framed by a
##     stone kerb, a few under ledger slabs or chest tombs); some are OLD plots, irregular and
##     overgrown, the stones leaning, sunken and broken, mossier; some hold FAMILY plots ringed
##     by low iron railings round an obelisk, angel or urn.
##   - OPEN_GRAVES open graves (pit, spoil heap, shovel, a coffin below) and FRESH_GRAVES fresh
##     mounds with crude wooden crosses.
##   - LANDMARKS: the ruined chapel with its bell tower inside a railed churchyard (consecrated
##     ground: the Necromancer's ultimate can't touch it), and 23 crypts and mausoleums (four
##     kinds) fronting the paths, the ground levelled under each.
##   - DEAD_TREES gnarled dead trees and WILLOWS weeping willows (round the ponds), 72 lying
##     props (coffins, a coffin stack, dead logs, a gravedigger's wheelbarrow).
##   - Lantern posts along the avenues; candles, wreaths and withered flowers on graves; crows
##     perched on headstones; fallen leaves, dead grass, pebbles, toadstools and bones, drawn in
##     chunks only near the camera.
##   - A moonlit sky with clouds drifting across it, cold blue moonlight, ground fog that rolls
##     slowly over the hills (two draped layers plus height fog), will-o'-wisps (GraveyardAmbience).
##   - The edge: a high cemetery wall with iron railings and a great gate, dead woods beyond
##     (GraveyardEdge).
## Grave positions are kept (graves) so the dead can climb out of them (swarms, the Necromancer).

const PONDS := 3
const DEAD_TREES := 150
const WILLOWS := 18
const LYING := 72
const LANDMARKS := 24                # the chapel + 23 crypts, like the swamp's 24 ruins
const OPEN_GRAVES := 40
const FRESH_GRAVES := 60
const BLOCK := 40.0
const LINES := [-160.0, -120.0, -80.0, -40.0, 0.0, 40.0, 80.0, 120.0, 160.0]
const AVENUE_HW := 2.3               # half widths
const PATH_HW := 1.3
const PATH_END := 196.0
const PLAZA_R := 9.0
const CHUNK := 60.0                  # headstones and fences: chunk size and draw distance
const STONE_DRAW := 150.0
const DEBRIS_CHUNK := 40.0           # grass, leaves, flowers...: drawn within 75 m
const DEBRIS_DRAW := 75.0
const CRYPT_LIGHT_EVERY := 3
const CONSECRATED_R := 15.0

const TINTS := [Color(0.8, 0.8, 0.8), Color(0.92, 0.9, 0.86), Color(0.95, 0.85, 0.68), Color(0.5, 0.52, 0.55),
	Color(0.72, 0.78, 0.7), Color(1.0, 0.99, 0.97), Color(0.82, 0.66, 0.6), Color(0.66, 0.65, 0.62)]
# headstone kinds: rounded, gothic, shouldered, cross, celtic, obelisk, angel, broken, child, ledger, chest, urn
const ROW_WEIGHTS := [24.0, 14.0, 14.0, 9.0, 6.0, 2.0, 1.5, 5.0, 4.0, 5.0, 3.0, 2.5]
const OLD_WEIGHTS := [18.0, 12.0, 8.0, 10.0, 8.0, 2.0, 2.0, 14.0, 4.0, 6.0, 4.0, 2.0]

const GROUND_SHADER := """
shader_type spatial;
uniform sampler2D path_map : filter_linear, repeat_disable;     // gravel paths
uniform sampler2D dirt_map : filter_linear, repeat_disable;     // bare earth: graves, trodden ground
uniform sampler2D litter_map : filter_linear, repeat_disable;   // fallen leaves under the trees
uniform float extent = 230.0;
uniform vec4 pools[16];
uniform vec4 pool_amps[16];
uniform vec4 pool_phases[16];
uniform vec4 holes[48];            // open graves: centre x, z, cos(yaw), sin(yaw)
uniform int hole_count = 0;
uniform vec2 hole_half = vec2(0.5, 1.05);
uniform float curse = 0.0;         // the Necromancer's ultimate: the ground glows (0 off, 1 on)
uniform float curse_fill = 0.0;    // ...brighter and faster as it's about to land
uniform vec4 safe[8];              // consecrated ground meanwhile: x, z, radius, on
uniform float quake = 0.0;
uniform float quake_fill = 0.0;
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	// holes for the ponds (their beds fill them) and for the open graves (their pits do)
	float bank = 0.0;
	for (int i = 0; i < 16; i++) {
		vec4 p = pools[i];
		if (p.w < 0.5) { continue; }
		vec2 d = wpos.xz - p.xy;
		if (dot(d, d) > p.z * p.z * 2.6 + 30.0) { continue; }
		float th = atan(d.y, d.x);
		vec4 a = pool_amps[i];
		vec4 ph = pool_phases[i];
		float r = p.z * (1.0 + a.x * sin(2.0 * th + ph.x) + a.y * sin(3.0 * th + ph.y) + a.z * sin(4.0 * th + ph.z) + a.w * sin(5.0 * th + ph.w));
		float dist = length(d);
		if (dist < r * 0.985) { discard; }
		bank = max(bank, 1.0 - smoothstep(r, r + 3.5, dist));
	}
	for (int i = 0; i < 48; i++) {
		if (i >= hole_count) { break; }
		vec4 h = holes[i];
		vec2 d = wpos.xz - h.xy;
		if (dot(d, d) > 2.0) { continue; }
		vec2 l = vec2(d.x * h.z - d.y * h.w, d.x * h.w + d.y * h.z);
		if (abs(l.x) < hole_half.x && abs(l.y) < hole_half.y) { discard; }
	}
	vec2 uv = (wpos.xz + extent) / (2.0 * extent);
	float path = texture(path_map, uv).r;
	float dirt = texture(dirt_map, uv).r;
	float litter = texture(litter_map, uv).r;
	float n = noise(wpos.xz * 1.7) * 0.6 + noise(wpos.xz * 7.0) * 0.4;
	float big = noise(wpos.xz * 0.06) * 0.6 + noise(wpos.xz * 0.19) * 0.4;
	// dead and dying grass: straw, olive-brown and grey, in drifts
	vec3 straw = vec3(0.2, 0.165, 0.085);
	vec3 olive = vec3(0.075, 0.09, 0.04);
	vec3 grey = vec3(0.13, 0.125, 0.105);
	vec3 col = mix(olive, straw, smoothstep(0.32, 0.78, big + (n - 0.5) * 0.35));
	col = mix(col, grey, smoothstep(0.58, 0.8, noise(wpos.xz * 0.23 + 5.0)) * 0.6);
	col *= 0.7 + 0.5 * n;
	col *= mix(0.6, 1.0, smoothstep(0.25, 0.6, noise(wpos.xz * 0.45 + 9.0)));   // darker hollows of rank grass
	col *= 0.86 + 0.24 * noise(vec2(wpos.x * 16.0 + wpos.z * 3.0, wpos.z * 16.0 - wpos.x * 3.0));   // blades
	// bare earth: the graves, trodden ground; clods and stones in it
	float earth = smoothstep(0.3, 0.62, dirt + (n - 0.5) * 0.35);
	vec3 soil = mix(vec3(0.12, 0.088, 0.06), vec3(0.2, 0.15, 0.1), noise(wpos.xz * 3.3)) * (0.8 + 0.3 * noise(wpos.xz * 14.0));
	col = mix(col, soil, earth);
	float wet = earth * 0.25;
	// gravel paths: pebbles of many greys, a muddy fringe, puddles in the dips
	float pth = smoothstep(0.38, 0.62, path + (noise(wpos.xz * 2.1) - 0.5) * 0.35);
	if (pth > 0.001) {
		// fine gravel: two scales of small irregular stones in many greys, low contrast
		vec3 gc = vec3(0.11, 0.105, 0.095) * (0.8 + 0.4 * noise(wpos.xz * 3.0));
		for (int k = 0; k < 2; k++) {
			vec2 g = wpos.xz * (k == 0 ? 11.0 : 19.0) + vec2(float(k) * 31.0);
			vec2 gi = floor(g);
			vec2 gf = fract(g) - 0.5 - (vec2(hash(gi), hash(gi + 3.1)) - 0.5) * 0.5;
			float pd = length(gf * vec2(1.0, 1.0 + hash(gi + 7.0) * 0.8));
			float peb = (1.0 - smoothstep(0.16, 0.3, pd)) * step(0.35, hash(gi + 5.0));
			gc = mix(gc, vec3(0.23, 0.22, 0.2) * (0.55 + 0.6 * hash(gi + 2.0)), peb * 0.7);
		}
		float rut = smoothstep(0.6, 0.85, noise(wpos.xz * vec2(0.4, 3.0)));
		gc = mix(gc, soil * 0.9, rut * 0.3);
		gc = mix(gc, soil, smoothstep(0.55, 0.8, noise(wpos.xz * 0.9 + 4.0)) * 0.35);   // worn to earth in places
		col = mix(col, gc, pth);
		float fringe = pth * (1.0 - pth) * 4.0;
		col = mix(col, soil * 0.75, fringe * 0.55);
		float puddle = smoothstep(0.8, 0.84, noise(wpos.xz * 0.8 + 3.0)) * smoothstep(0.75, 0.95, pth);
		col = mix(col, vec3(0.06, 0.065, 0.075), puddle * 0.5);
		wet = max(wet, fringe * 0.2);
	}
	// fallen leaves: rust, brown, ochre and dark red, thickest under the trees
	float ld = 0.025 + litter * 0.4 + bank * 0.06;
	for (int k = 0; k < 2; k++) {
		vec2 q = wpos.xz * (k == 0 ? 4.3 : 6.9) + vec2(17.0 * float(k));
		vec2 qi = floor(q);
		vec2 qf = fract(q) - 0.5;
		if (hash(qi + 11.0) < ld) {
			float a = hash(qi + 5.0) * 6.2832;
			vec2 o = (vec2(hash(qi + 1.0), hash(qi + 2.0)) - 0.5) * 0.36;
			vec2 lp = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * (qf - o);
			float leaf = 1.0 - smoothstep(0.82, 1.0, length(lp * vec2(3.6, 6.2)));
			float hv = hash(qi + 9.0);
			vec3 lc = hv < 0.3 ? vec3(0.34, 0.15, 0.05) : (hv < 0.6 ? vec3(0.25, 0.16, 0.08) : (hv < 0.85 ? vec3(0.42, 0.3, 0.09) : vec3(0.3, 0.07, 0.05)));
			lc *= 1.0 - (1.0 - smoothstep(0.0, 0.015, abs(lp.y))) * 0.4;   // the midrib
			col = mix(col, lc * (0.55 + 0.25 * n), leaf * 0.85 * (1.0 - pth * 0.6));
		}
	}
	// damp, darker banks round the ponds
	col *= 1.0 - 0.35 * bank;
	wet = max(wet, bank * 0.6);
	if (curse > 0.0) {
		// the graves open: everything glows a sickly green, cracks crawling through it, but for
		// the consecrated ground, which shines warm and safe with a bright rim
		float sd = 1e6;
		for (int i = 0; i < 8; i++) {
			if (safe[i].w > 0.5) { sd = min(sd, length(wpos.xz - safe[i].xy) - safe[i].z); }
		}
		float inside = 1.0 - smoothstep(-0.25, 0.25, sd);
		float rim = 1.0 - smoothstep(0.0, 0.5, abs(sd));
		float pulse = 0.5 + 0.5 * sin(TIME * mix(4.0, 13.0, curse_fill));
		float ck = 1.0 - smoothstep(0.0, 0.035, abs(noise(wpos.xz * 0.5 + vec2(TIME * 0.15, 0.0)) - 0.5));
		ck = max(ck, 1.0 - smoothstep(0.0, 0.03, abs(noise(wpos.xz * 1.3 - vec2(0.0, TIME * 0.2)) - 0.5)));
		vec3 g = vec3(0.3, 1.0, 0.35);
		float out_a = curse * (1.0 - inside);
		col = mix(col, g * 0.25, out_a * (0.45 + 0.25 * pulse));
		col = mix(col, vec3(1.0, 0.92, 0.7), curse * inside * 0.35);
		EMISSION = g * out_a * (ck * (1.2 + 1.5 * curse_fill) + 0.18 + 0.55 * curse_fill * pulse) + vec3(1.0, 0.85, 0.5) * curse * (inside * 0.35 + rim * 1.6);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.45, wet);
	SPECULAR = mix(0.3, 0.5, wet);
}
"""

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, world_vertex_coords, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float h_origin = 0.0;
uniform float h_size = 1.0;
uniform float lift = 0.6;
uniform vec3 fog_col : source_color = vec3(0.45, 0.52, 0.56);
uniform float density = 0.35;
uniform vec2 drift = vec2(0.7, 0.25);
uniform float scale = 0.035;
uniform float seed = 0.0;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; } return v; }
void vertex() {
	vec2 uv = (VERTEX.xz - h_origin + 0.5) / h_size;
	VERTEX.y = texture(height_tex, uv).r + lift;
	wp = VERTEX;
}
void fragment() {
	vec2 p = wp.xz * scale + TIME * drift * scale + vec2(seed);
	float f = fbm(p) * 0.7 + fbm(p * 2.3 - TIME * 0.015) * 0.3;
	float a = smoothstep(0.4, 0.78, f) * density;
	float d = length(wp - CAMERA_POSITION_WORLD);
	a *= smoothstep(1.5, 9.0, d) * (1.0 - smoothstep(45.0, 110.0, d));
	ALBEDO = fog_col * (0.85 + 0.3 * f);
	ALPHA = a;
}
"""

const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 dark : source_color = vec3(0.07, 0.085, 0.11);
uniform vec3 lit : source_color = vec3(0.34, 0.38, 0.47);
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);
uniform float coverage = 0.55;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; } return v; }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * 0.0045 + TIME * vec2(0.004, 0.0015);
	float n = fbm(p);
	float a = smoothstep(1.0 - coverage, 1.0 - coverage + 0.3, n);
	float d = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	a *= 1.0 - smoothstep(200.0, 360.0, d);
	float n2 = fbm(p + moon_dir.xz * 0.03);
	float l = clamp(0.5 + (n - n2) * 7.0, 0.0, 1.0);
	// near the moon, a silver lining
	vec3 to = normalize(wp - CAMERA_POSITION_WORLD);
	float glow = pow(max(dot(to, moon_dir), 0.0), 24.0);
	ALBEDO = mix(dark, lit, l) + lit * glow * (1.0 - a) * 2.0 + vec3(0.6, 0.65, 0.75) * glow * 0.6;
	ALPHA = a * 0.88;
}
"""

# ------------------------------------------------------------------ what the last build made
static var active := false                      # the current run is on the Graveyard (EnemyManager reads it)
static var graves: Array[Vector3] = []          # centre of every grave (in front of its headstone)
static var grave_yaw := PackedFloat32Array()
static var open_graves: Array[Vector3] = []
static var chapel_at := Vector3.INF             # the churchyard (consecrated ground)
static var stats := {}                          # counts, for tests
static var wisp_homes: Array[Vector3] = []

# layout state (one build at a time)
static var _occ := PackedByteArray()            # 1 m occupancy grid: 0 free, 1 path, 2 grave, 3 building, 4 tree
static var _on := 0
static var _oo := 0.0
static var _wob := []                           # per line: [amp, phase]
static var _water: SwampWater
static var _half := 220.0


static func build(parent: Node3D, rng: RandomNumberGenerator, half: float) -> SwampWater:
	active = true
	_half = half
	graves.clear()
	grave_yaw = PackedFloat32Array()
	open_graves.clear()
	wisp_homes.clear()
	stats = {"tombs": 0, "crypts": 0, "chapel": 0, "fence_panels": 0, "open_graves": 0, "fresh_graves": 0,
		"dead_trees": 0, "willows": 0, "lying": 0, "lanterns": 0, "crows": 0, "candles": 0, "wreaths": 0, "lights": 0}
	var moon_dir := _environment(parent, rng)

	var water := SwampWater.generate(rng, PONDS, half, 35.0)
	water.build_terrain(rng, half, WorldBuilder.CHEST_SITES, ChestManager.SITE_RADIUS)
	_water = water
	_on = water.hsize
	_oo = water.horigin
	_occ = PackedByteArray()
	_occ.resize(_on * _on)
	_wob.clear()
	for k in LINES.size() * 2:
		var avenue: bool = absf(float(LINES[k % LINES.size()])) < 0.1
		_wob.append([0.0 if avenue else rng.randf_range(0.5, 1.4), rng.randf() * TAU])
	_mark_paths()
	for s in water.chest_sites:   # chest pads stay clear
		_mark_circle(s.x, s.z, ChestManager.SITE_RADIUS + 3.0, 3)

	# The churchyard and the crypts first (the ground is levelled under them), then the graves
	var landmarks := _plan_landmarks(rng)
	for lm in landmarks:
		_flatten(water, lm["at"], lm["core"], lm["blend"])
	water.height_texture = ImageTexture.create_from_image(Image.create_from_data(water.hsize, water.hsize, false, Image.FORMAT_RF, water.hgrid.to_byte_array()))
	var tombs := {}            # "kind_shape" -> {chunk key -> [[xf, moss, tint], ...]}
	var extras := {}           # foliage on graves: kind -> chunk -> [xf]
	var fences: Array = []     # [Transform3D, height] panels
	var plots: Array = []      # [xf (headstone), kind, shape, open, fresh]
	_plan_graves(rng, landmarks, plots, fences)

	# Ground: paths, earth and leaf litter painted into masks for the shader
	var e := half + 10.0
	var path_img := Image.create(1024, 1024, false, Image.FORMAT_L8)
	var dirt_img := Image.create(1024, 1024, false, Image.FORMAT_L8)
	var litter_img := Image.create(1024, 1024, false, Image.FORMAT_L8)
	_paint_paths(path_img, e)
	var holes: Array = []
	for p in plots:
		var xf: Transform3D = p[0]
		var fwd := xf.basis.z.normalized()
		var c := xf.origin + fwd * 1.15
		_paint_rect(dirt_img, e, c, 0.5 if not p[4] else 0.65, 1.0 if not p[4] else 1.25, 200 if p[4] or p[3] else 110)
		if p[3]:
			var yaw := atan2(fwd.x, fwd.z)
			holes.append(Vector4(c.x, c.z, cos(yaw), sin(yaw)))
			_paint_rect(dirt_img, e, c + xf.basis.x.normalized() * 1.3, 1.1, 1.4, 230)
	for lm in landmarks:   # trodden earth in front of every door
		var door: Vector3 = lm["door_w"]
		_paint_rect(dirt_img, e, door, 2.5, 2.5, 150)

	var trees := _plan_trees(rng)
	for t in trees:
		_paint_rect(litter_img, e, t[0], 6.0, 6.0, 120)
		_paint_rect(litter_img, e, t[0], 3.0, 3.0, 230)
	_ground(parent, water, path_img, dirt_img, litter_img, e, holes)
	water.build_meshes(parent, {"deep": Color(0.02, 0.03, 0.03), "shallow": Color(0.06, 0.08, 0.06), "scum": Color(0.12, 0.15, 0.08), "bed": Color(0.08, 0.07, 0.05)})
	WorldBuilder._reeds(parent, rng, water)

	# Landmarks, headstones, fences, trees, lying props, lanterns
	var lights: Array[OmniLight3D] = []
	_build_landmarks(parent, rng, landmarks, lights)
	_build_graves(parent, rng, plots, tombs, extras)
	_chunked_tombs(parent, tombs)
	_build_fences(parent, fences)
	_build_trees(parent, rng, trees)
	_build_lying(parent, rng, plots)
	_build_lanterns(parent, rng, lights)
	_debris(parent, rng, half, path_img, e, extras, trees)
	_fog_layers(parent, water, rng)
	_clouds(parent, moon_dir)
	GraveyardEdge.build(parent, half, WorldBuilder.edge_haze)
	stats["lights"] = lights.size()

	var amb := GraveyardAmbience.new()
	amb.name = "GraveyardAmbience"   # no-i18n
	amb.setup(rng, wisp_homes, lights, chapel_at, half)
	parent.add_child(amb)
	_occ = PackedByteArray()
	var _cr := []   # TEMP-DEBUG
	for n in parent.get_children():   # TEMP-DEBUG
		if n.is_in_group("graveyard_crypt") and _cr.size() < 4:   # TEMP-DEBUG
			_cr.append([n.position, n.rotation.y])   # TEMP-DEBUG
	print("GRAVEYARD chapel %s yaw %s moon %s crypts %s" % [str(chapel_at), str(landmarks[0]["yaw"]), str(moon_dir), str(_cr)])   # TEMP-DEBUG
	return water


# ------------------------------------------------------------------ sky, moonlight, fog

static func _environment(parent: Node3D, rng: RandomNumberGenerator) -> Vector3:
	var sh := Shader.new()
	sh.code = WorldBuilder.SKY_SHADER
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("night", 1.0)
	sky_mat.set_shader_parameter("seed", rng.randf() * 50.0)
	sky_mat.set_shader_parameter("top_color", Color(0.01, 0.016, 0.04))
	sky_mat.set_shader_parameter("horizon_color", Color(0.06, 0.09, 0.11))
	sky_mat.set_shader_parameter("ground_color", Color(0.02, 0.025, 0.03))
	sky_mat.set_shader_parameter("cloud_dark", Color(0.03, 0.04, 0.06))
	sky_mat.set_shader_parameter("cloud_light", Color(0.2, 0.24, 0.3))
	sky_mat.set_shader_parameter("body_color", Color(0.9, 0.95, 1.0))
	sky_mat.set_shader_parameter("body_size", 0.065)
	sky_mat.set_shader_parameter("coverage", 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.85
	env.glow_hdr_luminance_cap = 4.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85   # drained of colour
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.28, 0.38)
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.13, 0.16)
	env.fog_density = 0.02
	env.fog_sky_affect = 0.1
	env.fog_height = 0.0
	env.fog_height_density = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	WorldBuilder._add_distant_castle(parent, env.fog_light_color, true)
	# the moon: low-ish, cold blue-white, long shadows
	var az := rng.randf() * TAU
	var el := deg_to_rad(rng.randf_range(30.0, 42.0))
	var to_light := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
	var light := DirectionalLight3D.new()
	light.basis = Basis.looking_at(-to_light, Vector3.UP)
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 80.0
	light.light_color = Color(0.62, 0.74, 1.0)
	light.light_energy = 0.9
	parent.add_child(light)
	# a faint cold fill from the far side of the sky, so shadowed faces keep their shape
	var fill := DirectionalLight3D.new()
	fill.basis = Basis.looking_at(Vector3(to_light.x, -0.6, to_light.z).normalized(), Vector3.UP)
	fill.light_color = Color(0.45, 0.55, 0.75)
	fill.light_energy = 0.18
	fill.shadow_enabled = false
	parent.add_child(fill)
	return to_light


static func _clouds(parent: Node3D, moon_dir: Vector3) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	var sh := Shader.new()
	sh.code = CLOUD_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("moon_dir", moon_dir)
	pm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.name = "Clouds"   # no-i18n
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 150, 0)
	mi.extra_cull_margin = 400.0
	parent.add_child(mi)


## Ground fog: two layers draped over the hills, drifting slowly the same way.
static func _fog_layers(parent: Node3D, water: SwampWater, rng: RandomNumberGenerator) -> void:
	var sh := Shader.new()
	sh.code = FOG_SHADER
	for k in 2:
		var pm := PlaneMesh.new()
		pm.size = Vector2(water.hsize - 2, water.hsize - 2)
		pm.subdivide_width = 150
		pm.subdivide_depth = 150
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = 1
		m.set_shader_parameter("height_tex", water.height_texture)
		m.set_shader_parameter("h_origin", water.horigin)
		m.set_shader_parameter("h_size", float(water.hsize))
		m.set_shader_parameter("lift", 0.35 if k == 0 else 1.1)
		m.set_shader_parameter("density", 0.65 if k == 0 else 0.4)
		m.set_shader_parameter("scale", 0.045 if k == 0 else 0.028)
		m.set_shader_parameter("drift", Vector2(0.8, 0.3) * (1.0 if k == 0 else 1.4))
		m.set_shader_parameter("seed", rng.randf() * 40.0)
		m.set_shader_parameter("fog_col", Color(0.4, 0.46, 0.52) if k == 0 else Color(0.34, 0.4, 0.46))
		pm.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.name = "GroundFog"   # no-i18n
		mi.add_to_group("ground_fog")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 30.0
		parent.add_child(mi)


# ------------------------------------------------------------------ occupancy and paths

static func _cell(x: float, z: float) -> int:
	var ix := int(floorf(x - _oo))
	var iz := int(floorf(z - _oo))
	if ix < 0 or iz < 0 or ix >= _on or iz >= _on:
		return -1
	return iz * _on + ix


static func _mark_circle(x: float, z: float, r: float, v: int) -> void:
	for iz in range(int(floorf(z - r - _oo)), int(ceilf(z + r - _oo)) + 1):
		for ix in range(int(floorf(x - r - _oo)), int(ceilf(x + r - _oo)) + 1):
			if ix < 0 or iz < 0 or ix >= _on or iz >= _on:
				continue
			if Vector2(_oo + ix + 0.5 - x, _oo + iz + 0.5 - z).length() <= r:
				_occ[iz * _on + ix] = maxi(_occ[iz * _on + ix], v)


## Mark a rotated rectangle (centre, half extents along the basis' local x and z).
static func _mark_rect(c: Vector3, ax: Vector3, az: Vector3, hx: float, hz: float, v: int) -> void:
	var r := sqrt(hx * hx + hz * hz)
	for iz in range(int(floorf(c.z - r - _oo)), int(ceilf(c.z + r - _oo)) + 1):
		for ix in range(int(floorf(c.x - r - _oo)), int(ceilf(c.x + r - _oo)) + 1):
			if ix < 0 or iz < 0 or ix >= _on or iz >= _on:
				continue
			var d := Vector3(_oo + ix + 0.5 - c.x, 0, _oo + iz + 0.5 - c.z)
			if absf(d.dot(ax)) <= hx + 0.3 and absf(d.dot(az)) <= hz + 0.3:
				_occ[iz * _on + ix] = maxi(_occ[iz * _on + ix], v)


## Is every cell within r of (x, z) free (or at most `allow`)?
static func _free(x: float, z: float, r: float, allow := 0) -> bool:
	for iz in range(int(floorf(z - r - _oo)), int(ceilf(z + r - _oo)) + 1):
		for ix in range(int(floorf(x - r - _oo)), int(ceilf(x + r - _oo)) + 1):
			if ix < 0 or iz < 0 or ix >= _on or iz >= _on:
				return false
			if _occ[iz * _on + ix] > allow:
				return false
	return true


static func _wobble(k: int, t: float) -> float:
	var w: Array = _wob[k]
	return float(w[0]) * (sin(t * 0.045 + float(w[1])) + 0.5 * sin(t * 0.11 + float(w[1]) * 2.0))


## Distance from (x, z) to the edge of the nearest path (negative = on it).
static func path_dist(x: float, z: float) -> float:
	var best := Vector2(x, z).length() - PLAZA_R
	var n := LINES.size()
	if absf(z) < PATH_END:
		for k in n:
			var lx: float = float(LINES[k]) + _wobble(k, z)
			best = minf(best, absf(x - lx) - (AVENUE_HW if absf(float(LINES[k])) < 0.1 else PATH_HW))
	if absf(x) < PATH_END:
		for k in n:
			var lz: float = float(LINES[k]) + _wobble(k + n, x)
			best = minf(best, absf(z - lz) - (AVENUE_HW if absf(float(LINES[k])) < 0.1 else PATH_HW))
	return best


static func _mark_paths() -> void:
	for iz in _on:
		var z := _oo + iz + 0.5
		for ix in _on:
			var x := _oo + ix + 0.5
			if absf(x) > PATH_END + 3.0 and absf(z) > PATH_END + 3.0:
				continue
			if path_dist(x, z) < 0.9:
				_occ[iz * _on + ix] = 1


static func _paint_paths(img: Image, e: float) -> void:
	var n := LINES.size()
	var s := img.get_width() / (2.0 * e)
	for k in n:
		var hw: float = AVENUE_HW if absf(float(LINES[k])) < 0.1 else PATH_HW
		var t := -PATH_END
		while t < PATH_END:
			var x: float = float(LINES[k]) + _wobble(k, t)
			if not _water.near_pool(x, t, 0.5):
				_fill(img, e, s, x, t, hw, hw, 255)
			var z: float = float(LINES[k]) + _wobble(k + n, t)
			if not _water.near_pool(t, z, 0.5):
				_fill(img, e, s, t, z, hw, hw, 255)
			t += 0.35
	# the plaza where the avenues cross: a round of gravel
	var r := PLAZA_R
	var y := -r
	while y <= r:
		var w := sqrt(maxf(r * r - y * y, 0.0))
		_fill(img, e, s, 0.0, y, w, 0.3, 255)
		y += 0.4


static func _fill(img: Image, e: float, s: float, x: float, z: float, hx: float, hz: float, v: int) -> void:
	var x0 := int((x - hx + e) * s)
	var z0 := int((z - hz + e) * s)
	var x1 := int(ceilf((x + hx + e) * s))
	var z1 := int(ceilf((z + hz + e) * s))
	var w := img.get_width()
	x0 = clampi(x0, 0, w - 1)
	z0 = clampi(z0, 0, w - 1)
	x1 = clampi(x1, 0, w)
	z1 = clampi(z1, 0, w)
	if x1 > x0 and z1 > z0:
		img.fill_rect(Rect2i(x0, z0, x1 - x0, z1 - z0), Color8(v, v, v))


static func _paint_rect(img: Image, e: float, c: Vector3, hx: float, hz: float, v: int) -> void:
	var s := img.get_width() / (2.0 * e)
	var r := maxf(hx, hz) * 0.85
	_fill(img, e, s, c.x, c.z, r, r, v)


# ------------------------------------------------------------------ levelling

## Level the ground at `at` (its own height) within `core` metres, blending out over `blend`.
static func _flatten(water: SwampWater, at: Vector3, core: float, blend: float) -> void:
	var h := water.ground_height(at.x, at.z)
	var reach := core + blend
	for zi in range(maxi(0, int(at.z - reach - water.horigin)), mini(water.hsize, int(at.z + reach - water.horigin) + 2)):
		for xi in range(maxi(0, int(at.x - reach - water.horigin)), mini(water.hsize, int(at.x + reach - water.horigin) + 2)):
			var d := Vector2(water.horigin + xi - at.x, water.horigin + zi - at.z).length()
			if d >= reach:
				continue
			var w := 1.0 - smoothstep(core, reach, d)
			var k := zi * water.hsize + xi
			water.hgrid[k] = lerpf(water.hgrid[k], h, w)


# ------------------------------------------------------------------ planning

## Block centres (40 m plots between the paths).
static func _blocks() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var c := -180.0
	while c <= 180.0:
		var d := -180.0
		while d <= 180.0:
			out.append(Vector2(c, d))
			d += BLOCK
		c += BLOCK
	return out


## The chapel in one of the four plots beside the plaza, and 23 crypts fronting the paths.
## Each: {kind, at, yaw, core, blend, door_w}
static func _plan_landmarks(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	# prefer the four plots beside the plaza, then any plot within 140 m, nearest first
	var cands: Array[Vector2] = []
	var start := rng.randi() % 4
	var near := [Vector2(60, -60), Vector2(-60, -60), Vector2(60, 60), Vector2(-60, 60)]
	for k in 4:
		cands.append(near[(start + k) % 4])
	var rest: Array[Vector2] = []
	for b in _blocks():
		if b.length() < 140.0 and b.length() > 50.0 and not cands.has(b):
			rest.append(b)
	rest.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	cands.append_array(rest)
	var best := Vector2.INF
	for pass_n in 2:
		for c in cands:
			if _water.near_pool(c.x, c.y, 30.0 if pass_n == 0 else 22.0):
				continue
			var ok := true
			for s in _water.chest_sites:
				if Vector2(s.x - c.x, s.z - c.y).length() < (28.0 if pass_n == 0 else 20.0):
					ok = false
			if ok:
				best = c
				break
		if best != Vector2.INF:
			break
	if best == Vector2.INF:
		best = cands[0]
	var cdir := Vector3(-signf(best.x), 0, 0) if rng.randf() < 0.5 else Vector3(0, 0, -signf(best.y))
	if absf(best.x) < 1.0:
		cdir = Vector3(0, 0, -signf(best.y))
	elif absf(best.y) < 1.0:
		cdir = Vector3(-signf(best.x), 0, 0)
	var cyaw := atan2(cdir.x, cdir.z)
	var cat := Vector3(best.x, 0, best.y)
	out.append({"kind": "chapel", "at": cat, "yaw": cyaw, "core": 17.0, "blend": 9.0, "door_w": cat + cdir * 15.0})
	chapel_at = cat
	_mark_rect(cat, Basis(Vector3.UP, cyaw).x, Basis(Vector3.UP, cyaw).z, 12.5, 17.0, 3)
	# crypts: on the edges of plots, facing the path that bounds them
	var blocks := _blocks()
	var tries := 0
	while out.size() < LANDMARKS and tries < 4000:
		tries += 1
		var b: Vector2 = blocks[rng.randi() % blocks.size()]
		if absf(b.x) > 150.0 or absf(b.y) > 150.0:
			continue
		var side := rng.randi() % 4
		var dir: Vector3 = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][side]
		var along := Vector3(dir.z, 0, -dir.x)
		var at := Vector3(b.x, 0, b.y) + dir * (BLOCK * 0.5 - 8.5) + along * rng.randf_range(-9.0, 9.0)
		if _water.near_pool(at.x, at.z, 14.0) or not _free(at.x, at.z, 4.2):
			continue
		var spaced := true
		for o in out:
			if (o["at"] as Vector3).distance_to(at) < 22.0:
				spaced = false
				break
		if not spaced:
			continue
		var yaw := atan2(dir.x, dir.z)
		out.append({"kind": "crypt", "at": at, "yaw": yaw, "core": 6.5, "blend": 7.0, "door_w": at + dir * 5.5})
		_mark_rect(at, Basis(Vector3.UP, yaw).x, Basis(Vector3.UP, yaw).z, 5.0, 6.0, 3)
	return out


## Fill every plot with graves: rows, old irregular plots and railed family plots; pick the open
## and fresh ones. plots: [headstone xf, kind, shape, open, fresh]; fences: [xf, height].
static func _plan_graves(rng: RandomNumberGenerator, landmarks: Array, plots: Array, fences: Array) -> void:
	for b in _blocks():
		if absf(b.x) > 185.0 or absf(b.y) > 185.0:
			continue
		var x0 := b.x - BLOCK * 0.5
		var z0 := b.y - BLOCK * 0.5
		var roll := rng.randf()
		var outer := absf(b.x) > 170.0 or absf(b.y) > 170.0
		if roll < 0.22 or outer:
			_old_plot(rng, b, plots, 0.55 if outer else 1.0)
		elif roll < 0.4:
			_family_plots(rng, b, plots, fences)
		else:
			_row_plot(rng, b, plots)
	# open and fresh graves among the rows near the middle (someone's been busy)
	var idx: Array[int] = []
	for k in plots.size():
		var xf: Transform3D = plots[k][0]
		if xf.origin.length() < 160.0 and xf.origin.length() > 18.0 and int(plots[k][1]) in [0, 1, 2, 3, 8]:
			idx.append(k)
	for k in range(idx.size() - 1, 0, -1):
		var j := rng.randi() % (k + 1)
		var t := idx[k]
		idx[k] = idx[j]
		idx[j] = t
	var n_open := 0
	var n_fresh := 0
	for k in idx:
		var xf: Transform3D = plots[k][0]
		var c := xf.origin + xf.basis.z.normalized() * 1.15
		var side := c + xf.basis.x.normalized() * 1.4
		if n_open < OPEN_GRAVES and _free_side(side):
			plots[k][3] = true
			n_open += 1
			open_graves.append(c)
			_mark_circle(side.x, side.z, 1.0, 2)
		elif n_fresh < FRESH_GRAVES:
			plots[k][4] = true
			n_fresh += 1
		if n_open >= OPEN_GRAVES and n_fresh >= FRESH_GRAVES:
			break
	stats["open_graves"] = n_open
	stats["fresh_graves"] = n_fresh


static func _free_side(p: Vector3) -> bool:
	var c := _cell(p.x, p.z)
	return c >= 0 and _occ[c] == 0


static func _pick(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := rng.randf() * total
	for k in weights.size():
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return 0


## Try to put a grave with its headstone at `p` facing `yaw`; returns false if it doesn't fit.
static func _try_grave(rng: RandomNumberGenerator, plots: Array, p: Vector3, yaw: float, kind: int, lean: float, sink: float) -> bool:
	var basis := Basis(Vector3.UP, yaw)
	var fwd := basis.z
	var side := basis.x
	var hw := 0.65 if kind != 5 and kind != 10 else 0.9
	var c := p + fwd * 1.0
	# the stone and its grave must sit clear of paths, buildings, ponds and other graves
	for q in [p, c, c + fwd * 0.9, p + side * hw, p - side * hw]:
		var cell := _cell(q.x, q.z)
		if cell < 0 or _occ[cell] != 0:
			return false
	if _water.near_pool(p.x, p.z, 2.0) or _water.near_pool(c.x, c.z, 2.0):
		return false
	_mark_rect(p + fwd * 0.9, side, fwd, hw - 0.1, 1.4, 2)
	var shape := rng.randi() % GraveyardProps.TOMB_SHAPES
	var tilt := Basis(Vector3(1, 0, 0), lean) * Basis(Vector3(0, 0, 1), rng.randf_range(-0.5, 0.5) * absf(lean) * 0.6)
	var h := minf(_water.ground_height(p.x, p.z), minf(_water.ground_height(p.x + side.x * 0.4, p.z + side.z * 0.4), _water.ground_height(p.x - side.x * 0.4, p.z - side.z * 0.4)))
	var xf := Transform3D(basis * tilt, Vector3(p.x, h - 0.04 - sink, p.z))
	plots.append([xf, kind, shape, false, false])
	return true


static func _row_plot(rng: RandomNumberGenerator, b: Vector2, plots: Array) -> void:
	var face := rng.randi() % 4
	var fwd: Vector3 = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][face]
	var along := Vector3(fwd.z, 0, -fwd.x)
	var yaw := atan2(fwd.x, fwd.z)
	var pitch := rng.randf_range(4.0, 4.8)
	var c := Vector3(b.x, 0, b.y)
	var r := -BLOCK * 0.5 + 2.5
	while r < BLOCK * 0.5 - 3.0:
		if rng.randf() < 0.14:   # a grassy aisle left between the rows
			r += pitch
			continue
		var s := -BLOCK * 0.5 + rng.randf_range(1.5, 2.5)
		var step := rng.randf_range(2.1, 2.9)
		while s < BLOCK * 0.5 - 1.5:
			if rng.randf() > 0.18:   # the odd gap
				var p := c - fwd * r + along * (s + rng.randf_range(-0.12, 0.12))
				var lean := 0.0
				var sink := rng.randf_range(0.0, 0.06)
				if rng.randf() < 0.12:
					lean = rng.randf_range(0.08, 0.26) * (1.0 if rng.randf() < 0.7 else -1.0)
				if rng.randf() < 0.05:
					sink = rng.randf_range(0.15, 0.35)
				_try_grave(rng, plots, p, yaw + rng.randf_range(-0.04, 0.04), _pick(rng, ROW_WEIGHTS), lean, sink)
			s += step
		r += pitch


static func _old_plot(rng: RandomNumberGenerator, b: Vector2, plots: Array, density: float) -> void:
	var c := Vector3(b.x, 0, b.y)
	var base_yaw := rng.randi() % 4 * PI * 0.5
	var n := int(rng.randf_range(32.0, 50.0) * density)
	for k in n * 3:
		if n <= 0:
			break
		var p := c + Vector3(rng.randf_range(-17.0, 17.0), 0, rng.randf_range(-17.0, 17.0))
		var lean := 0.0
		if rng.randf() < 0.35:
			lean = rng.randf_range(0.1, 0.4) * (1.0 if rng.randf() < 0.75 else -1.0)
		var sink := rng.randf_range(0.0, 0.1) if rng.randf() > 0.2 else rng.randf_range(0.2, 0.45)
		if _try_grave(rng, plots, p, base_yaw + rng.randf_range(-0.35, 0.35), _pick(rng, OLD_WEIGHTS), lean, sink):
			plots[-1].append(true)   # old: mossier
			n -= 1


## Two or three railed family plots round a central monument, and rows in the rest.
static func _family_plots(rng: RandomNumberGenerator, b: Vector2, plots: Array, fences: Array) -> void:
	var c := Vector3(b.x, 0, b.y)
	var spots := [Vector3(-9, 0, -9), Vector3(9, 0, -9), Vector3(-9, 0, 9), Vector3(9, 0, 9)]
	var k0 := rng.randi() % 4
	var count := rng.randi_range(2, 3)
	for k in count:
		var at: Vector3 = c + spots[(k0 + k) % 4]
		var hx := 3.4
		var hz := 4.0
		if not _free(at.x, at.z, 4.6):
			continue
		var yaw := rng.randi() % 4 * PI * 0.5
		var basis := Basis(Vector3.UP, yaw)
		# the monument in the middle
		var mono: int = [5, 6, 11, 5, 4][rng.randi() % 5]
		var mp := at - basis.z * 0.6
		var h := _water.ground_height(mp.x, mp.z)
		plots.append([Transform3D(basis, Vector3(mp.x, h - 0.05, mp.z)), mono, rng.randi() % 2, false, false])
		_mark_circle(mp.x, mp.z, 1.2, 2)
		# graves either side of it, facing in
		for sd in [-1.0, 1.0]:
			for q in 2:
				var p: Vector3 = at + basis.x * sd * 2.2 + basis.z * (-2.2 + q * 2.6)
				var gyaw := yaw + (PI * 0.5 if sd < 0.0 else -PI * 0.5)
				var gb := Basis(Vector3.UP, gyaw)
				var gh := _water.ground_height(p.x, p.z)
				plots.append([Transform3D(gb, Vector3(p.x, gh - 0.05, p.z)), [0, 1, 2, 8][rng.randi() % 4], rng.randi() % 2, false, false])
		# low railings round it, a gap for the gate on the front
		var corners := [at + basis * Vector3(-hx, 0, -hz), at + basis * Vector3(hx, 0, -hz), at + basis * Vector3(hx, 0, hz), at + basis * Vector3(-hx, 0, hz)]
		for e in 4:
			var a: Vector3 = corners[e]
			var bb: Vector3 = corners[(e + 1) % 4]
			_fence_run(fences, a, bb, 1.0, 2 if e == 2 else -1)
		_mark_rect(at, basis.x, basis.z, hx + 0.3, hz + 0.3, 2)


## Panels along a->b; `gap` = index of a panel to leave out (the gate), -1 for none.
static func _fence_run(fences: Array, a: Vector3, b: Vector3, h: float, gap := -1) -> void:
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	var len := d.length()
	var n := maxi(1, int(round(len / 2.4)))
	var mid := n / 2
	for k in n:
		if gap >= 0 and k == mid:
			continue
		var p0 := a + d * (float(k) / n)
		var p1 := a + d * (float(k + 1) / n)
		var y0 := _water.ground_height(p0.x, p0.z)
		var y1 := _water.ground_height(p1.x, p1.z)
		var ax := Vector3(p1.x - p0.x, y1 - y0, p1.z - p0.z) / 2.4   # shear: balusters stay upright
		var az := Vector3(-d.z, 0, d.x).normalized()
		fences.append([Transform3D(Basis(ax, Vector3.UP, az), Vector3(p0.x, y0 - 0.06, p0.z)), h])


static func _plan_trees(rng: RandomNumberGenerator) -> Array:
	var out: Array = []   # [pos, kind (0 dead, 1 willow)]
	# willows lean over the ponds
	for p in _water.pools:
		var c: Vector2 = p["center"]
		for k in int(WILLOWS / float(PONDS)):
			for t in 40:
				var a := rng.randf() * TAU
				var r := _water.max_radius(p) + rng.randf_range(2.5, 7.0)
				var q := Vector3(c.x + cos(a) * r, 0, c.y + sin(a) * r)
				if _free(q.x, q.z, 2.0):
					out.append([q, 1])
					_mark_circle(q.x, q.z, 3.0, 4)
					break
	while out.size() < WILLOWS:   # if a pond had no room, elsewhere
		var q := Vector3(rng.randf_range(-180, 180), 0, rng.randf_range(-180, 180))
		if _free(q.x, q.z, 3.0):
			out.append([q, 1])
			_mark_circle(q.x, q.z, 3.0, 4)
	var tries := 0
	var dead := 0
	while dead < DEAD_TREES and tries < 20000:
		tries += 1
		var q := Vector3(rng.randf_range(-200, 200), 0, rng.randf_range(-200, 200))
		if q.length() < 16.0 or not _free(q.x, q.z, 1.6):
			continue
		var spaced := true
		for o in out:
			if (o[0] as Vector3).distance_to(q) < 7.0:
				spaced = false
				break
		if not spaced:
			continue
		out.append([q, 0])
		_mark_circle(q.x, q.z, 1.8, 4)
		dead += 1
	return out


# ------------------------------------------------------------------ building

static func _ground(parent: Node3D, water: SwampWater, path_img: Image, dirt_img: Image, litter_img: Image, e: float, holes: Array) -> void:
	var body := water.heightmap_body()
	var mesh := water.ground_mesh(1)
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("path_map", ImageTexture.create_from_image(path_img))
	sm.set_shader_parameter("dirt_map", ImageTexture.create_from_image(dirt_img))
	sm.set_shader_parameter("litter_map", ImageTexture.create_from_image(litter_img))
	sm.set_shader_parameter("extent", e)
	var sp := water.shader_params()
	for k in sp:
		sm.set_shader_parameter(k, sp[k])
	var hv: Array[Vector4] = []
	for h in holes:
		hv.append(h)
	while hv.size() < 48:
		hv.append(Vector4.ZERO)
	sm.set_shader_parameter("holes", hv)
	sm.set_shader_parameter("hole_count", mini(holes.size(), 48))
	var safe: Array[Vector4] = []
	for k in 8:
		safe.append(Vector4.ZERO)
	sm.set_shader_parameter("safe", safe)
	mesh.surface_set_material(0, sm)
	water.ground_mat = sm
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	body.name = "Ground"   # no-i18n
	parent.add_child(body)


static func _prop(parent: Node3D, data: Dictionary, xf: Transform3D, burnable := false) -> StaticBody3D:
	WorldBuilder._prop(parent, data, xf, burnable)
	return parent.get_child(parent.get_child_count() - 1) as StaticBody3D


static func _build_landmarks(parent: Node3D, rng: RandomNumberGenerator, landmarks: Array, lights: Array[OmniLight3D]) -> void:
	var ci := 0
	for lm in landmarks:
		var at: Vector3 = lm["at"]
		var yaw: float = lm["yaw"]
		var basis := Basis(Vector3.UP, yaw)
		var y := _water.ground_height(at.x, at.z)
		if lm["kind"] == "chapel":
			var d := GraveyardProps.chapel(rng)
			# shift so the churchyard's centre (between nave and tower) sits on the plot centre
			var xf := Transform3D(basis, Vector3(at.x, y - 0.05, at.z) + basis * Vector3(1.0, 0, 0))
			var body := _prop(parent, d, xf)
			body.add_to_group("obstacle")
			body.add_to_group("graveyard_chapel")
			body.set_meta("reach", 12.0)
			stats["chapel"] = 1
			lights.append(_light(parent, xf * (d["light_at"] as Vector3), Color(1.0, 0.68, 0.35), 1.6, 12.0))
			lights.append(_light(parent, xf * (d["door"] as Vector3) + Vector3(0, 2.4, 0), Color(1.0, 0.65, 0.3), 1.2, 9.0))
			chapel_at = Vector3(at.x, y, at.z)
			wisp_homes.append(chapel_at + basis * Vector3(0, 0, 17.0))
			# the churchyard: a tall railing all round with a gate in front
			var hx := 12.0
			var hz := 16.5
			var c := Vector3(at.x, 0, at.z)
			var corners := [c + basis * Vector3(-hx, 0, -hz), c + basis * Vector3(hx, 0, -hz), c + basis * Vector3(hx, 0, hz), c + basis * Vector3(-hx, 0, hz)]
			var fences: Array = []
			for e in 4:
				_fence_run(fences, corners[e], corners[(e + 1) % 4], 1.7, 2 if e == 2 else -1)
			_build_fences(parent, fences)
			var gate := GraveyardProps.gate(2.4, 2.2, 1.35)
			var gp := c + basis * Vector3(0, 0, hz)
			var g := StaticBody3D.new()
			var gmi := MeshInstance3D.new()
			gmi.mesh = gate["mesh"]
			g.add_child(gmi)
			for sd in [-1.0, 1.0]:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.7, 3.0, 0.7)
				cs.shape = bs
				cs.position = Vector3(sd * 1.5, 1.4, 0)
				g.add_child(cs)
			g.transform = Transform3D(basis, Vector3(gp.x, _water.ground_height(gp.x, gp.z) - 0.05, gp.z))
			parent.add_child(g)
			continue
		var d := GraveyardProps.crypt(ci, rng)
		var xf := Transform3D(basis, Vector3(at.x, y - 0.05, at.z))
		var body := _prop(parent, d, xf)
		body.add_to_group("obstacle")
		body.add_to_group("graveyard_crypt")
		body.set_meta("reach", 5.0)
		if ci % CRYPT_LIGHT_EVERY == 0:
			lights.append(_light(parent, xf * (d["light_at"] as Vector3), d["light"], 1.3, 8.0))
		wisp_homes.append(xf * (d["door"] as Vector3) + basis.z * 3.0)
		lm["door_w"] = xf * (d["door"] as Vector3)
		ci += 1
		stats["crypts"] = ci


static func _light(parent: Node3D, at: Vector3, color: Color, energy: float, rng_m: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	l.position = at
	l.add_to_group("grave_light")
	l.set_meta("base", energy)
	parent.add_child(l)
	return l


## Headstones go into `tombs` (chunked MultiMesh data); grave dressing into `extras`.
static func _build_graves(parent: Node3D, rng: RandomNumberGenerator, plots: Array, tombs: Dictionary, extras: Dictionary) -> void:
	for p in plots:
		var xf: Transform3D = p[0]
		var kind: int = p[1]
		var shape: int = p[2]
		var is_open: bool = p[3]
		var fresh: bool = p[4]
		var old: bool = p.size() > 5
		var fwd := xf.basis.z.normalized()
		var side := xf.basis.x.normalized()
		var c := xf.origin + fwd * 1.15
		c.y = _water.ground_height(c.x, c.z)
		graves.append(c)
		grave_yaw.append(atan2(fwd.x, fwd.z))
		var upright := Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), c)
		if fresh:
			# a fresh mound with a wooden cross instead of a stone
			_add_extra(extras, "mound_%d" % (rng.randi() % 2), upright * Transform3D(Basis(), Vector3(0, -0.02, -1.15)))   # no-i18n
			var cp := xf.origin
			cp.y = _water.ground_height(cp.x, cp.z)
			_add_extra(extras, "wcross_%d" % (rng.randi() % 2), Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z) + rng.randf_range(-0.1, 0.1)), cp))   # no-i18n
			if rng.randf() < 0.5:
				_add_extra(extras, "flowers_1", upright * Transform3D(Basis(), Vector3(0, 0.25, -0.2)))
			continue
		var tint: Color = TINTS[rng.randi() % TINTS.size()]
		var moss := rng.randf_range(0.0, 0.45)
		if old:
			moss = rng.randf_range(0.55, 1.0)
			tint = tint.lerp(Color(0.62, 0.68, 0.58), 0.35)
		var key := "%d_%d" % [kind, shape]
		if not tombs.has(key):
			tombs[key] = {}
		_chunk_add(tombs[key], [xf, moss, tint], CHUNK)
		stats["tombs"] += 1
		if is_open:
			var og := GraveyardProps.open_grave(rng.randi() % 3)
			var mi := MeshInstance3D.new()
			mi.mesh = og["mesh"]
			var body := StaticBody3D.new()
			body.add_child(mi)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(1.1, 1.4, 2.2)
			cs.shape = bs
			cs.position = Vector3(0, 0.3, 0)
			body.add_child(cs)
			body.transform = Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), c + Vector3(0, -0.02, 0))
			body.add_to_group("open_grave")
			parent.add_child(body)
			continue
		# a stone kerb round many graves in the rows (not under ledgers and chest tombs)
		if kind in [0, 1, 2, 3, 4, 8, 11] and rng.randf() < (0.3 if not old else 0.12):
			_add_extra(extras, "kerb", Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), xf.origin + Vector3(0, 0.02, 0) + fwd * 0.05))
		# things left on the grave
		var r := rng.randf()
		var dress := c + fwd * -0.65
		dress.y = _water.ground_height(dress.x, dress.z)
		var yaw := atan2(fwd.x, fwd.z) + rng.randf_range(-0.3, 0.3)
		if kind in [9, 10]:
			pass
		elif r < 0.06:
			_add_extra(extras, "wreath_%d" % (rng.randi() % 2), Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), xf.origin + fwd * 0.2 + Vector3(0, _water.ground_height(xf.origin.x, xf.origin.z) - xf.origin.y, 0)))   # no-i18n
			stats["wreaths"] += 1
		elif r < 0.11:
			_add_extra(extras, "candles_%d" % (rng.randi() % 2), Transform3D(Basis(Vector3.UP, yaw), dress))   # no-i18n
			stats["candles"] += 1
			if rng.randf() < 0.12:
				wisp_homes.append(dress)
		elif r < 0.3:
			_add_extra(extras, "flowers_%d" % (rng.randi() % 2), Transform3D(Basis(Vector3.UP, yaw), dress))   # no-i18n
		# crows perched on the taller stones
		var top: float = GraveyardProps.tomb(kind, shape)["top"]
		if top > 0.7 and top < 2.6 and rng.randf() < 0.02 and kind != 6:
			var perch := xf * Vector3(0, top, 0)
			_add_extra(extras, "crow", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 1.3), perch))
			stats["crows"] += 1


static func _add_extra(extras: Dictionary, kind: String, xf: Transform3D) -> void:
	if not extras.has(kind):
		extras[kind] = {}
	_chunk_add(extras[kind], xf, DEBRIS_CHUNK)


static func _chunk_add(chunks: Dictionary, item, size: float) -> void:
	var o: Vector3 = (item[0] as Transform3D).origin if item is Array else (item as Transform3D).origin
	var key := Vector2i(floori(o.x / size), floori(o.z / size))
	if not chunks.has(key):
		chunks[key] = []
	(chunks[key] as Array).append(item)


## Headstones: one MultiMesh per kind per chunk, drawn within STONE_DRAW, with a StaticBody of
## box colliders per chunk for every stone big enough to bump into.
static func _chunked_tombs(parent: Node3D, tombs: Dictionary) -> void:
	var bodies := {}
	for key in tombs:
		var parts := (key as String).split("_")
		var info := GraveyardProps.tomb(int(parts[0]), int(parts[1]))
		var aabb: AABB = info["aabb"]
		for ck in tombs[key]:
			var items: Array = tombs[key][ck]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = info["mesh"]
			mm.instance_count = items.size()
			var origins := PackedVector3Array()
			for k in items.size():
				var xf: Transform3D = items[k][0]
				mm.set_instance_transform(k, xf)
				mm.set_instance_color(k, items[k][2])
				mm.set_instance_custom_data(k, Color(float(items[k][1]), 0, 0, 0))
				origins.append(xf.origin)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.name = "Tombs"   # no-i18n
			mmi.add_to_group("graveyard_tombs")
			mmi.visibility_range_end = STONE_DRAW
			mmi.visibility_range_end_margin = 12.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.set_meta("origins", origins)
			mmi.set_meta("kind", int(parts[0]))
			parent.add_child(mmi)
			if aabb.size.y < 0.4:
				continue
			if not bodies.has(ck):
				var b := StaticBody3D.new()
				b.name = "TombColliders"   # no-i18n
				b.add_to_group("graveyard_tomb_colliders")
				parent.add_child(b)
				bodies[ck] = b
			var body: StaticBody3D = bodies[ck]
			for k in items.size():
				var xf: Transform3D = items[k][0]
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(maxf(aabb.size.x, 0.2), aabb.size.y, maxf(aabb.size.z, 0.2))
				cs.shape = bs
				cs.transform = xf * Transform3D(Basis(), aabb.get_center())
				body.add_child(cs)


static func _build_fences(parent: Node3D, fences: Array) -> void:
	if fences.is_empty():
		return
	var by_h := {}
	for f in fences:
		var h: float = f[1]
		if not by_h.has(h):
			by_h[h] = {}
		_chunk_add(by_h[h], [f[0]], CHUNK)
	for h in by_h:
		var mesh := GraveyardProps.fence_panel(h)
		for ck in by_h[h]:
			var items: Array = by_h[h][ck]
			var xfs: Array[Transform3D] = []
			for it in items:
				xfs.append(it[0])
			WorldBuilder._multimesh(parent, mesh, xfs)
			var mmi := parent.get_child(parent.get_child_count() - 1) as MultiMeshInstance3D
			mmi.name = "Railings"   # no-i18n
			mmi.add_to_group("graveyard_fences")
			mmi.visibility_range_end = STONE_DRAW
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			var body := StaticBody3D.new()
			for xf in xfs:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(2.4, h + 0.2, 0.12)
				cs.shape = bs
				var mid := xf * Vector3(1.2, 0, 0)
				cs.transform = Transform3D(Basis(Vector3.UP, atan2(-xf.basis.x.z, xf.basis.x.x)), mid + Vector3(0, h * 0.5, 0))
				body.add_child(cs)
			parent.add_child(body)
			stats["fence_panels"] += xfs.size()


static func _build_trees(parent: Node3D, rng: RandomNumberGenerator, trees: Array) -> void:
	for t in trees:
		var p: Vector3 = t[0]
		var willow: bool = int(t[1]) == 1
		var d := GraveyardProps.willow(rng.randi()) if willow else GraveyardProps.dead_tree(rng.randi())
		p.y = WorldBuilder._low_point(_water, p, 0.8) - 0.15
		var s := rng.randf_range(0.85, 1.2)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), p)
		_prop(parent, d, xf, true)
		stats["willows" if willow else "dead_trees"] += 1
		if not willow and rng.randf() < 0.3:
			wisp_homes.append(p + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)))


static func _build_lying(parent: Node3D, rng: RandomNumberGenerator, plots: Array) -> void:
	var placed := 0
	var tries := 0
	while placed < LYING and tries < 8000:
		tries += 1
		var d := GraveyardProps.lying(rng, placed)
		var length: float = d["length"]
		var p := Vector3(rng.randf_range(-195, 195), 0, rng.randf_range(-195, 195))
		if placed < 30 and not open_graves.is_empty() and rng.randf() < 0.4:   # coffins and barrows by the open graves
			var og: Vector3 = open_graves[rng.randi() % open_graves.size()]
			p = og + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
		if p.length() < 14.0 or _water.near_pool(p.x, p.z, length * 0.5 + 1.0):
			continue
		var yaw := rng.randf() * TAU
		var basis := Basis(Vector3.UP, yaw)
		var axis := basis.x if placed % 5 == 2 else basis.z   # logs lie along x, coffins and barrows along z
		var clear := true
		for t in [-0.5, -0.25, 0.0, 0.25, 0.5]:
			var q: Vector3 = p + axis * length * float(t)
			if not _free(q.x, q.z, 0.9):
				clear = false
				break
		if not clear:
			continue
		var y := _water.ground_height(p.x, p.z)
		var off := 0.0
		if placed % 5 == 2:   # a log lies along the ground at its own lower end
			var along := basis * Vector3(1, 0, 0) * length * 0.5
			y = minf(_water.ground_height(p.x + along.x, p.z + along.z), _water.ground_height(p.x - along.x, p.z - along.z))
			off = float(d["radius"]) * 0.75
		else:
			y = WorldBuilder._low_point(_water, p, length * 0.4) - 0.04
		_prop(parent, d, Transform3D(basis, Vector3(p.x, y + off, p.z)), true)
		for t in [-0.5, 0.0, 0.5]:
			var q: Vector3 = p + axis * length * float(t)
			_mark_circle(q.x, q.z, 1.0, 4)
		placed += 1
	stats["lying"] = placed


## Lantern posts along both avenues (a few cast real light near the plaza).
static func _build_lanterns(parent: Node3D, rng: RandomNumberGenerator, lights: Array[OmniLight3D]) -> void:
	var xfs: Array[Transform3D] = []
	var body := StaticBody3D.new()
	var lit := 0
	for axis in 2:
		var d := 16.0
		var side := 1.0
		while d < 186.0:
			for sgn in [-1.0, 1.0]:
				var along: float = d * sgn
				var p: Vector3 = Vector3(along, 0, side * (AVENUE_HW + 0.9)) if axis == 0 else Vector3(side * (AVENUE_HW + 0.9), 0, along)
				if _water.near_pool(p.x, p.z, 2.0) or not _free_or_path(p):
					continue
				p.y = _water.ground_height(p.x, p.z)
				xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
				var cs := CollisionShape3D.new()
				var sh := CylinderShape3D.new()
				sh.radius = 0.2
				sh.height = 2.6
				cs.shape = sh
				cs.position = p + Vector3(0, 1.3, 0)
				body.add_child(cs)
				if d < 30.0 and lit < 4:
					lights.append(_light(parent, p + Vector3(0, 3.0, 0), Color(1.0, 0.7, 0.38), 1.1, 9.0))
					lit += 1
				if rng.randf() < 0.08:
					wisp_homes.append(p)
			side = -side
			d += 24.0
	parent.add_child(body)
	WorldBuilder._multimesh(parent, GraveyardProps.lantern_post(), xfs)
	var mmi := parent.get_child(parent.get_child_count() - 1) as MultiMeshInstance3D
	mmi.name = "Lanterns"   # no-i18n
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	stats["lanterns"] = xfs.size()


static func _free_or_path(p: Vector3) -> bool:
	var c := _cell(p.x, p.z)
	return c >= 0 and _occ[c] <= 1


## Ground debris and grave dressing in chunks drawn only near the camera: dead grass, fallen
## leaves, pebbles on the paths, toadstools round the trees, bones; flowers, wreaths, candles,
## kerbs, fresh mounds and crows from the graves.
static func _debris(parent: Node3D, rng: RandomNumberGenerator, half: float, path_img: Image, e: float, extras: Dictionary, trees: Array) -> void:
	var grass := {}
	var leaf := {}
	var pebble := {}
	var w := path_img.get_width()
	var z := -half
	while z < half:
		var x := -half
		while x < half:
			var px := x + rng.randf_range(-0.6, 0.6)
			var pz := z + rng.randf_range(-0.6, 0.6)
			var ix := clampi(int((px + e) / (2.0 * e) * w), 0, w - 1)
			var iz := clampi(int((pz + e) / (2.0 * e) * w), 0, w - 1)
			var on_path := path_img.get_pixel(ix, iz).r > 0.5
			var near := _water.near_pool(px, pz, 0.6)
			if not near and Vector2(px, pz).length() > 3.0:
				var y := _water.ground_height(px, pz)
				var cell := _cell(px, pz)
				var occ := _occ[cell] if cell >= 0 else 0
				if on_path:
					if rng.randf() < 0.05:
						_chunk_add(pebble, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(px, y, pz)), DEBRIS_CHUNK)
				elif occ != 3 and rng.randf() < 0.62:
					var s := rng.randf_range(0.7, 1.4)
					_chunk_add(grass, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(px, y - 0.03, pz)), DEBRIS_CHUNK)
				if rng.randf() < (0.06 if not on_path else 0.02):
					_chunk_add(leaf, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(px, y, pz)), DEBRIS_CHUNK)
			x += 1.45
		z += 1.45
	_chunk_meshes(parent, grass, [GraveyardProps.dead_grass(0), GraveyardProps.dead_grass(1)], rng)
	_chunk_meshes(parent, leaf, [GraveyardProps.leaves(0), GraveyardProps.leaves(1)], rng)
	_chunk_meshes(parent, pebble, [GraveyardProps.pebbles(0), GraveyardProps.pebbles(1)], rng)
	# leaves heaped and toadstools growing round the trees
	var under := {}
	var toads := {}
	for t in trees:
		var c: Vector3 = t[0]
		for k in 9:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.8, 5.0)
			var p := Vector3(c.x + cos(a) * r, 0, c.z + sin(a) * r)
			p.y = _water.ground_height(p.x, p.z)
			_chunk_add(under, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.5)), p), DEBRIS_CHUNK)
		if rng.randf() < 0.45:
			var a := rng.randf() * TAU
			var p := Vector3(c.x + cos(a) * 1.0, 0, c.z + sin(a) * 1.0)
			p.y = _water.ground_height(p.x, p.z)
			_chunk_add(toads, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), DEBRIS_CHUNK)
	_chunk_meshes(parent, under, [GraveyardProps.leaves(0), GraveyardProps.leaves(1)], rng)
	_chunk_meshes(parent, toads, [GraveyardProps.toadstools(0), GraveyardProps.toadstools(1)], rng)
	# bones: by the open graves and here and there
	var bone := {}
	for og in open_graves:
		for k in 2:
			var p := og + Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))
			p.y = _water.ground_height(p.x, p.z)
			_chunk_add(bone, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), DEBRIS_CHUNK)
	for k in 90:
		var p := Vector3(rng.randf_range(-190, 190), 0, rng.randf_range(-190, 190))
		if _water.near_pool(p.x, p.z, 1.0) or not _free(p.x, p.z, 0.5, 2):
			continue
		p.y = _water.ground_height(p.x, p.z)
		_chunk_add(bone, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), DEBRIS_CHUNK)
	_chunk_meshes(parent, bone, [GraveyardProps.bones(0), GraveyardProps.bones(1)], rng)
	# grave dressing
	for kind in extras:
		var mesh: Mesh = null
		var k := kind as String
		if k == "kerb":
			mesh = GraveyardProps.kerb()
		elif k == "crow":
			mesh = GraveyardProps.crow(false)
		elif k.begins_with("mound_"):
			mesh = GraveyardProps.dirt_mound(int(k.split("_")[1]))
		elif k.begins_with("wcross_"):
			mesh = GraveyardProps.wooden_cross(int(k.split("_")[1]))
		elif k.begins_with("flowers_"):
			mesh = GraveyardProps.withered_flowers(int(k.split("_")[1]))
		elif k.begins_with("wreath_"):
			mesh = GraveyardProps.wreath(int(k.split("_")[1]))
		elif k.begins_with("candles_"):
			mesh = GraveyardProps.candles(int(k.split("_")[1]))
		if mesh == null:
			continue
		var big := k == "kerb" or k.begins_with("mound_") or k.begins_with("wcross_")
		for ck in extras[kind]:
			var xfs: Array[Transform3D] = []
			for it in extras[kind][ck]:
				xfs.append(it)
			WorldBuilder._multimesh(parent, mesh, xfs)
			var mmi := parent.get_child(parent.get_child_count() - 1) as MultiMeshInstance3D
			mmi.name = "GraveDressing"   # no-i18n
			mmi.set_meta("dressing", k)
			mmi.visibility_range_end = STONE_DRAW if big else DEBRIS_DRAW
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if big:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## One MultiMesh per chunk (meshes alternate per instance), faded out beyond DEBRIS_DRAW.
static func _chunk_meshes(parent: Node3D, chunks: Dictionary, meshes: Array, rng: RandomNumberGenerator) -> void:
	for key in chunks:
		var split: Array = []
		for m in meshes:
			split.append([] as Array[Transform3D])
		for it in chunks[key]:
			(split[rng.randi() % meshes.size()] as Array[Transform3D]).append(it)
		for k in meshes.size():
			var xfs: Array[Transform3D] = split[k]
			if xfs.is_empty():
				continue
			WorldBuilder._multimesh(parent, meshes[k], xfs)
			var mmi := parent.get_child(parent.get_child_count() - 1) as MultiMeshInstance3D
			mmi.visibility_range_end = DEBRIS_DRAW
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.set_meta("chunk", true)
