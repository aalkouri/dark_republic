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
const CHEST_SITES := 28
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
float fbm(vec2 p) { return noise(p) * 0.5 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.2; }
// distance to a crack: a wobbly line through `c` at angle `a`, fading out toward its ends
float crack(vec2 f, vec2 c, float a, float len, float seed) {
	vec2 d = vec2(cos(a), sin(a));
	vec2 q = f - c;
	float along = dot(q, d);
	float across = dot(q, vec2(-d.y, d.x)) + (noise(vec2(along * 9.0, seed)) - 0.5) * 0.09 + (noise(vec2(along * 30.0, seed + 3.0)) - 0.5) * 0.025;
	float ends = smoothstep(len, len * 0.6, abs(along));
	return abs(across) / max(ends, 0.001);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// Running-bond flagstones (rows offset by half a stone), every stone its own: some split
	// in two, each a different shade and tint, worn smooth in the middle and grimy at the
	// edges, chipped corners, cracks across many (some forking), the odd broken stone, dark
	// stains, and moss creeping along the mortar
	vec2 p = wpos.xz / tile;
	float row = floor(p.y);
	p.x += 0.5 * mod(row, 2.0) + (hash(vec2(row, 7.0)) - 0.5) * 0.3;
	vec2 id = floor(p);
	vec2 f = fract(p);
	float h = hash(id);
	// some stones are two half-stones
	if (hash(id + 11.0) > 0.62) {
		float cut = 0.5 + (hash(id + 4.0) - 0.5) * 0.3;
		id.x += f.x > cut ? 0.5 : 0.0;
		f.x = f.x > cut ? (f.x - cut) / (1.0 - cut) : f.x / cut;
		h = hash(id);
	}
	// wobbly, hand-cut edges
	vec2 fw = f + (vec2(noise(wpos.xz * 2.5 + 3.0), noise(wpos.xz * 2.5 - 5.0)) - 0.5) * 0.035;
	float edge = min(min(fw.x, 1.0 - fw.x), min(fw.y, 1.0 - fw.y));
	float line = smoothstep(0.012, 0.04, edge);
	// chipped corners
	float corner = length(min(fw, 1.0 - fw));
	line *= smoothstep(0.03, 0.07, corner + (hash(id + 2.0) > 0.6 ? 0.0 : 0.1) - noise(wpos.xz * 8.0) * 0.03);
	// the stone's own colour: shade, tint (warm, cool or greenish) and grain
	vec3 col = mix(stone_a, stone_b, h);
	float tint = hash(id + 9.0);
	col *= tint < 0.33 ? vec3(1.08, 1.0, 0.92) : (tint < 0.66 ? vec3(0.94, 0.98, 1.06) : vec3(0.96, 1.03, 0.94));
	col *= 0.8 + 0.4 * hash(id + 5.0);
	float grain = fbm(wpos.xz * 3.0 + h * 40.0);
	col *= 0.78 + 0.4 * grain;
	col *= 0.9 + 0.12 * noise(wpos.xz * 25.0);   // fine speckle
	// worn smooth in the middle, grime toward the edges
	float worn = smoothstep(0.02, 0.25, edge);
	col *= mix(0.72, 1.06, worn);
	// cracks
	float ck = 1e3;
	if (hash(id + 21.0) > 0.45) {
		vec2 c = vec2(hash(id + 31.0), hash(id + 41.0)) * 0.6 + 0.2;
		float a = hash(id + 51.0) * 3.1416;
		ck = crack(f, c, a, 0.5 + hash(id + 61.0) * 0.5, h * 10.0);
		if (hash(id + 71.0) > 0.5) {   // a fork
			ck = min(ck, crack(f, c + vec2(cos(a), sin(a)) * 0.15, a + 0.7, 0.3, h * 20.0));
		}
	}
	if (hash(id + 81.0) > 0.88) {   // a broken stone: shattered into pieces
		vec2 g = f * 3.0;
		vec2 gi = floor(g);
		float d1 = 8.0;
		float d2 = 8.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 o = vec2(float(x), float(y));
				vec2 r = o + vec2(hash(gi + o + id), hash(gi + o + id + 13.0)) - fract(g);
				float dd = dot(r, r);
				if (dd < d1) { d2 = d1; d1 = dd; } else if (dd < d2) { d2 = dd; }
			}
		}
		ck = min(ck, (sqrt(d2) - sqrt(d1)) * 0.3);
	}
	float crack_line = 1.0 - smoothstep(0.004, 0.012, ck);
	float crack_halo = 1.0 - smoothstep(0.012, 0.04, ck);
	col *= 1.0 - crack_halo * 0.25;
	col = mix(col, mortar * 0.6, crack_line);
	// stains
	float stain = smoothstep(0.62, 0.8, fbm(wpos.xz * 0.35 + 17.0));
	col *= 1.0 - stain * 0.35;
	// mortar, with moss creeping along it here and there
	vec3 m = mix(mortar, vec3(0.1, 0.14, 0.06), smoothstep(0.55, 0.75, noise(wpos.xz * 0.8)));
	col = mix(m, col, line);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, worn * line) + crack_line * 0.05;
	SPECULAR = 0.35;
}
"""

const CARPET_SHADER := """
shader_type spatial;
uniform vec2 size = vec2(8.0, 150.0);   // metres (width, length)
uniform float seed = 3.7;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.5 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.2; }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// Local metres: x across (0 at the middle), y along
	vec2 q = (UV - 0.5) * size;
	float ax = abs(q.x);
	float hw = size.x * 0.5;
	vec3 crimson = vec3(0.36, 0.05, 0.06);
	vec3 deep = vec3(0.2, 0.03, 0.05);
	vec3 navy = vec3(0.07, 0.09, 0.22);
	vec3 gold = vec3(0.62, 0.46, 0.16);
	vec3 cream = vec3(0.7, 0.62, 0.46);
	vec3 col = crimson;
	float edge_d = hw - ax;   // distance in from the long edge
	float end_d = size.y * 0.5 - abs(q.y);
	float bd = min(edge_d, end_d);
	// Border: gold rim, dark band, a navy band with a running zig-zag, a thin cream line
	if (bd < 0.12) { col = gold; }
	else if (bd < 0.3) { col = deep; }
	else if (bd < 0.95) {
		col = navy;
		float run = edge_d < end_d ? q.y : q.x;
		float zig = abs(fract(run * 0.9) - 0.5) * 0.65 + 0.37;   // a zig-zag vine
		if (abs(bd - zig) < 0.05) { col = gold; }
		vec2 dm = vec2(fract(run * 0.9 + 0.5) - 0.5, (bd - 0.62) * 1.6);
		if (abs(dm.x) + abs(dm.y) < 0.12) { col = crimson * 1.3; }   // little lozenges between
	}
	else if (bd < 1.05) { col = cream; }
	else if (bd < 1.2) { col = deep; }
	else {
		// The field: a lattice of small diamonds, with a big medallion every 9 m
		vec2 lat = vec2(q.x * 1.4, q.y * 1.4);
		vec2 lf = fract(lat) - 0.5;
		float dia = abs(lf.x) + abs(lf.y);
		if (dia < 0.12) { col = gold * 0.85; }
		else if (abs(dia - 0.42) < 0.035) { col = deep; }
		float my = mod(q.y + 4.5, 9.0) - 4.5;
		vec2 m = vec2(q.x / (hw - 1.4), my / 3.4);
		float md = abs(m.x) + abs(m.y);   // a lozenge medallion
		if (md < 1.0) {
			col = navy;
			float rings = fract(md * 3.0);
			if (rings < 0.12) { col = gold; }
			float r = length(vec2(q.x, my));
			if (r < 0.9) { col = mix(crimson, gold, step(0.55, r)); }
			if (abs(r - 0.35) < 0.05) { col = cream; }
			float petal = abs(sin(atan(my, q.x) * 4.0));
			if (r > 1.1 && r < 1.9 && petal > 0.8) { col = crimson * 1.2; }
		}
		if (abs(md - 1.08) < 0.05) { col = gold * 0.9; }
	}
	// The weave: fine warp and weft threads, a little uneven
	float warp = 0.85 + 0.15 * sin(q.x * 160.0 + noise(q * 3.0) * 2.0);
	float weft = 0.9 + 0.1 * sin(q.y * 140.0);
	col *= warp * weft;
	col *= 0.9 + 0.15 * noise(q * 18.0);
	// Age: faded patches, a threadbare path down the middle, dirt and stains
	float fade = smoothstep(0.45, 0.8, fbm(q * 0.35 + seed));
	col = mix(col, vec3(dot(col, vec3(0.33))) * vec3(1.15, 1.0, 0.85), fade * 0.45);
	float path = (1.0 - smoothstep(0.6, 2.2, ax)) * smoothstep(0.35, 0.65, fbm(vec2(q.x * 0.6, q.y * 0.08) + seed * 2.0));
	col = mix(col, vec3(0.32, 0.25, 0.2) * (0.8 + 0.4 * sin(q.x * 160.0)), path * 0.45);   // worn to the backing threads
	float dirt = fbm(q * 0.8 + seed * 3.0);
	col *= 0.72 + 0.4 * dirt;
	float stain = smoothstep(0.66, 0.78, fbm(q * 0.25 + seed * 5.0));
	col = mix(col, col * vec3(0.45, 0.38, 0.32), stain * 0.7);
	// A few holes and tears (about one every 28 m of runner)
	vec2 cell = vec2(0.0, floor(q.y / 7.0));
	float h = hash(cell + seed);
	float cut = 1e3;
	float fray = 0.0;
	if (h > 0.74) {
		vec2 c = vec2((hash(cell + seed + 1.0) - 0.5) * (size.x - 2.0), (cell.y + 0.2 + hash(cell + seed + 2.0) * 0.6) * 7.0);
		vec2 d = q - c;
		if (h > 0.88) {   // a tear: a long ragged slit
			float a = hash(cell + seed + 3.0) * 3.1416;
			vec2 dir = vec2(cos(a), sin(a));
			float along = dot(d, dir);
			float across = dot(d, vec2(-dir.y, dir.x)) + (noise(vec2(along * 6.0, seed)) - 0.5) * 0.12;
			float len = 0.5 + hash(cell + seed + 4.0) * 0.6;
			float w = 0.06 * smoothstep(len, 0.0, abs(along));
			cut = abs(across) - w;
			cut = max(cut, abs(along) - len);
		} else {   // a hole: ragged round, frayed
			float r = 0.18 + hash(cell + seed + 5.0) * 0.3;
			cut = length(d * vec2(1.0, 0.8)) - r * (0.75 + 0.5 * noise(normalize(d + 0.0001) * 3.0 + seed));
		}
	}
	if (cut < 0.0) { discard; }
	fray = 1.0 - smoothstep(0.0, 0.08, cut);
	col = mix(col, vec3(0.28, 0.2, 0.14), fray * 0.8);   // pale frayed threads round the edge
	col *= 1.0 - (1.0 - smoothstep(0.08, 0.25, cut)) * 0.25;   // grime gathers round the damage
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}
"""

const WALL_SHADER := """
shader_type spatial;
uniform vec3 stone_a : source_color = vec3(0.34, 0.31, 0.29);
uniform vec3 stone_b : source_color = vec3(0.25, 0.23, 0.22);
uniform vec3 mortar : source_color = vec3(0.1, 0.09, 0.09);
uniform float ivy_amount = 1.0;
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.5 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.2; }
float crack(vec2 f, vec2 c, float a, float len, float seed) {
	vec2 d = vec2(cos(a), sin(a));
	vec2 q = f - c;
	float along = dot(q, d);
	float across = dot(q, vec2(-d.y, d.x)) + (noise(vec2(along * 8.0, seed)) - 0.5) * 0.08 + (noise(vec2(along * 26.0, seed + 3.0)) - 0.5) * 0.02;
	float ends = smoothstep(len, len * 0.6, abs(along));
	return abs(across) / max(ends, 0.001);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	// Ashlar blocks about 2.4 x 1.2 m on vertical faces, every block its own: some halved,
	// varied shades and tints, uneven hand-cut edges, chipped corners, cracks (some running
	// on into the next block), water stains streaking down, soot and damp near the floor,
	// and patches of ivy climbing up from the ground. Plain stone on tops and bottoms.
	vec2 uv = abs(wnrm.x) > abs(wnrm.z) ? wpos.zy : wpos.xy;
	if (abs(wnrm.y) > 0.5) {
		float n0 = fbm(wpos.xz * 1.5);
		ALBEDO = mix(stone_a, stone_b, 0.5) * (0.8 + 0.35 * n0);
		ROUGHNESS = 0.92;
	} else {
		vec2 p = uv / vec2(2.4, 1.2);
		float row = floor(p.y);
		p.x += 0.5 * mod(row, 2.0) + (hash(vec2(row, 3.0)) - 0.5) * 0.4;
		vec2 id = floor(p);
		vec2 f = fract(p);
		if (hash(id + 11.0) > 0.7) {   // some blocks are two smaller ones
			float cut = 0.5 + (hash(id + 4.0) - 0.5) * 0.3;
			id.x += f.x > cut ? 0.5 : 0.0;
			f.x = f.x > cut ? (f.x - cut) / (1.0 - cut) : f.x / cut;
		}
		float h = hash(id);
		vec2 fw = f + (vec2(noise(uv * 3.0 + 3.0), noise(uv * 3.0 - 5.0)) - 0.5) * vec2(0.025, 0.05);
		float edge = min(min(fw.x, 1.0 - fw.x) * 2.4, min(fw.y, 1.0 - fw.y) * 1.2);
		float line = smoothstep(0.025, 0.06, edge);
		float corner = length(min(fw, 1.0 - fw) * vec2(2.4, 1.2));
		line *= smoothstep(0.05, 0.1, corner + (hash(id + 2.0) > 0.55 ? 0.0 : 0.12) - noise(uv * 9.0) * 0.04);
		vec3 col = mix(stone_a, stone_b, h);
		float tint = hash(id + 9.0);
		col *= tint < 0.33 ? vec3(1.07, 1.0, 0.92) : (tint < 0.66 ? vec3(0.94, 0.98, 1.05) : vec3(1.0, 1.0, 1.0));
		col *= 0.8 + 0.35 * hash(id + 5.0);
		col *= 0.8 + 0.35 * fbm(uv * 3.0 + h * 40.0);
		col *= 0.9 + 0.12 * noise(uv * 24.0);
		col *= mix(0.78, 1.04, smoothstep(0.02, 0.2, edge));   // grime toward the joints
		// cracks: across a block, sometimes forking
		float ck = 1e3;
		if (hash(id + 21.0) > 0.55) {
			vec2 c = vec2(hash(id + 31.0), hash(id + 41.0)) * 0.6 + 0.2;
			float a = hash(id + 51.0) * 3.1416;
			vec2 q = vec2(f.x * 2.0, f.y);   // blocks are twice as wide as tall
			ck = crack(q, c * vec2(2.0, 1.0), a, 0.6 + hash(id + 61.0) * 0.6, h * 10.0);
			if (hash(id + 71.0) > 0.5) {
				ck = min(ck, crack(q, c * vec2(2.0, 1.0) + vec2(cos(a), sin(a)) * 0.2, a + 0.8, 0.35, h * 20.0));
			}
		}
		// a long crack running down the wall through several courses
		float big = (noise(vec2(uv.x * 0.15, 9.0)) > 0.8) ? abs(fract(uv.x * 0.15) - 0.5 + (noise(vec2(uv.y * 1.5, uv.x)) - 0.5) * 0.12) * 8.0 : 1e3;
		big /= max(smoothstep(0.85, 0.95, noise(vec2(uv.x * 0.15, 9.0))) * smoothstep(9.0, 2.0, uv.y), 0.001);
		ck = min(ck, big * 0.1);
		float crack_line = 1.0 - smoothstep(0.006, 0.016, ck);
		float crack_halo = 1.0 - smoothstep(0.016, 0.05, ck);
		col *= 1.0 - crack_halo * 0.25;
		col = mix(col, mortar * 0.5, crack_line);
		// water stains streaking down from above, soot and damp low on the wall
		float streak = smoothstep(0.55, 0.85, noise(vec2(uv.x * 2.2, uv.y * 0.12)) * 0.7 + noise(vec2(uv.x * 7.0, uv.y * 0.3)) * 0.3);
		col *= 1.0 - streak * 0.3;
		col *= mix(0.75, 1.0, smoothstep(0.0, 1.6, uv.y + (noise(uv * 1.2) - 0.5)));
		vec3 m = mortar * (0.8 + 0.4 * noise(uv * 6.0));
		col = mix(m, col, line);
		// ivy: patches climbing from the floor, thinning upward, made of little leaves
		float patch = fbm(uv * vec2(0.22, 0.12) + 13.0);
		float reach = mix(2.0, 9.0, smoothstep(0.45, 0.7, patch));   // how high this patch climbs
		float climb = smoothstep(reach, reach * 0.4, uv.y + (noise(uv * 0.9) - 0.5) * 1.6);
		float ivy = smoothstep(0.43, 0.53, patch) * climb * ivy_amount;
		// tendrils reaching above the patch
		float tendril = (1.0 - smoothstep(0.0, 0.05, abs(fract(uv.x * 0.9 + noise(vec2(uv.y * 0.8, uv.x)) * 0.6) - 0.5))) * smoothstep(0.38, 0.45, patch) * smoothstep(reach * 1.5, reach, uv.y);
		ivy = max(ivy, tendril * 0.9 * ivy_amount);
		vec3 leafcol = vec3(0.0);
		float leaves = 0.0;
		if (ivy > 0.001) {
			vec2 g = uv * 4.5;
			vec2 gi = floor(g);
			float best = 8.0;
			float lh = 0.0;
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					vec2 o = vec2(float(x), float(y));
					vec2 cpt = o + vec2(hash(gi + o), hash(gi + o + 7.0)) - fract(g);
					cpt.y *= 1.25;   // leaves a little taller than wide
					float dd = length(cpt) + abs(cpt.x) * 0.35;   // a pointed, ivy-ish leaf
					if (dd < best) { best = dd; lh = hash(gi + o + 3.0); }
				}
			}
			leaves = 1.0 - smoothstep(0.5, 0.58, best);
			float vein = 1.0 - smoothstep(0.0, 0.05, abs(fract(g.x) - 0.5)) * 0.15;
			leafcol = mix(vec3(0.1, 0.24, 0.06), vec3(0.28, 0.46, 0.12), lh) * (0.75 + 0.45 * smoothstep(0.5, 0.0, best)) * vein;
			// a thin dark shadow behind the leaves on the stone
			col *= 1.0 - ivy * 0.4;
		}
		col = mix(col, leafcol, ivy * leaves);
		ALBEDO = col;
		ROUGHNESS = mix(0.92, 0.6, ivy * leaves);
	}
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
	var sites := _chest_sites(rng, nav, placed)
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


## The great hall and throne room runners: a woven carpet (CARPET_SHADER) with a border of
## bands and a running motif, medallions down a patterned field, a gold-fringed end at each end,
## and a few centuries of wear: dirt, faded patches, stains, a threadbare path down the middle,
## and here and there a hole or a tear (not too many).
static func _rugs(parent: Node3D) -> void:
	var sh := Shader.new()
	sh.code = CARPET_SHADER
	var k := 0
	for r in [[0.0, 64.0, 216.0, 8.0], [0.0, -216.0, -114.0, 8.0]]:   # great hall and throne room runners
		var len: float = r[2] - r[1]
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("size", Vector2(r[3], len))
		mat.set_shader_parameter("seed", 3.7 + k * 11.3)
		var pm := PlaneMesh.new()
		pm.size = Vector2(r[3], len)
		pm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.position = Vector3(r[0], 0.02, (r[1] + r[2]) * 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_to_group("castle_carpet")
		parent.add_child(mi)
		# Gold fringe (tassels) at both ends
		var mb := MeshBuilder.new()
		for end in [-1.0, 1.0]:
			var z: float = end * (len * 0.5 + 0.12)
			var x: float = -float(r[3]) * 0.5 + 0.1
			while x < r[3] * 0.5 - 0.05:
				mb.add(MeshBuilder.box(Vector3(0.05, 0.015, 0.26 + 0.06 * sin(x * 7.0))), Transform3D(Basis(), Vector3(x, 0.0, z)), Color(0.66, 0.5, 0.2, 0))
				x += 0.11
		var fr := MeshInstance3D.new()
		fr.mesh = mb.commit()
		fr.position = mi.position
		parent.add_child(fr)
		k += 1


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


## Chest pads: open floor (nothing solid around them), spread across the rooms.
static func _chest_sites(rng: RandomNumberGenerator, nav: CastleNav, placed: Array[Vector3]) -> Array[Vector3]:
	var sites: Array[Vector3] = []
	var tries := 0
	while sites.size() < CHEST_SITES and tries < 3000:
		tries += 1
		var room: Array = ROOMS[rng.randi() % ROOMS.size()]
		var r := ChestManager.SITE_RADIUS + 2.0
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
			if Vector2(q.x - x, q.z - z).length() < 30.0:
				ok = false
		if ok:
			sites.append(Vector3(x, 0, z))
	return sites


## The remaining standing props, lying props and landmarks, room by room, keeping doorways,
## the entrance, the chest pads and the table clear.
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
		if Vector2(p.x - s.x, p.z - s.z).length() < ChestManager.SITE_RADIUS + 4.0:
			return false
	return true


## Torches in iron sconces along every wall (a real light on every third), heraldic banners in
## four colour schemes high between them, tall stained-glass windows glowing with moonlight in
## the outer walls, and halfway between torches the memorabilia: painted shields over crossed
## swords, woven tapestries, a stag's antlers, a boar's head, crossed battle-axes.
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
	var banners: Array[ArrayMesh] = []
	for v in CastleProps.BANNERS.size():
		banners.append(CastleProps.banner_variant(rng, v))
	var window := CastleProps.stained_window(rng)
	# Memorabilia between the torches: [mesh, height, weight]
	var deco: Array = []
	for v in 4:
		deco.append([CastleProps.shield_and_swords(rng, v), 5.4, 2.0])
	for v in 3:
		deco.append([CastleProps.tapestry(rng, v), 6.6, 1.2])
	deco.append([CastleProps.antler_trophy(rng), 6.0, 1.2])
	deco.append([CastleProps.boar_trophy(rng), 5.8, 1.0])
	deco.append([CastleProps.crossed_axes(rng), 5.6, 1.2])
	var deco_total := 0.0
	for dd in deco:
		deco_total += float(dd[2])
	var deco_xf := {}   # deco index -> transforms
	var t_xf: Array[Transform3D] = []
	var b_xf := {}      # banner variant -> transforms
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
						var bv := rng.randi() % banners.size()
						if not b_xf.has(bv):
							b_xf[bv] = [] as Array[Transform3D]
						(b_xf[bv] as Array[Transform3D]).append(Transform3D(basis, p + nrm * 0.12 + Vector3(0, 11.0, 0)))
			# Halfway to the next torch: a shield, tapestry or trophy (most of the time)
			var mp := a + along * (d + TORCH_STEP * 0.5)
			var mcoord := mp.x if absf(along.x) > 0.5 else mp.z
			var m_gap := d + TORCH_STEP * 0.5 > length - 4.0
			for o in openings:
				if absf(mcoord - o[0]) < o[1] * 0.5 + 4.0:
					m_gap = true
			if not m_gap and _room_at(mp - nrm * 2.0) != "" and rng.randf() < 0.8:
				var roll := rng.randf() * deco_total
				var di := 0
				while di < deco.size() - 1 and roll > float(deco[di][2]):
					roll -= float(deco[di][2])
					di += 1
				if not deco_xf.has(di):
					deco_xf[di] = [] as Array[Transform3D]
				(deco_xf[di] as Array[Transform3D]).append(Transform3D(basis, mp + nrm * 0.06 + Vector3(0, float(deco[di][1]), 0)))
			k += 1
			d += TORCH_STEP
	WorldBuilder._multimesh(parent, sconce, t_xf)
	for bv in b_xf:
		WorldBuilder._multimesh(parent, banners[bv], b_xf[bv])
	for di in deco_xf:
		WorldBuilder._multimesh(parent, deco[di][0], deco_xf[di])
		(parent.get_child(parent.get_child_count() - 1) as Node).add_to_group("castle_wall_deco")
	WorldBuilder._multimesh(parent, window, w_xf)


static func _room_at(p: Vector3) -> String:
	for r in ROOMS:
		if p.x >= r[1] and p.x <= r[3] and p.z >= r[2] and p.z <= r[4]:
			return r[0]
	return ""
