class_name GraveyardProps
extends RefCounted
## Procedural props for the Haunted Graveyard (GraveyardBuilder). Origin at the base, front
## toward +Z (a headstone's inscription faces +Z and its grave lies in front of it, on +Z).
##
## Three looks, as separate surfaces:
##   stone    (stone_material)    headstones and statues: weathered grain, streaks running down
##            the faces, grime near the ground, pale lichen blotches and moss on the tops, low
##            down and in the carved letters. Vertex alpha 1 = carved (letters, emblems).
##            MultiMesh custom data .x = how mossy this stone is (old plots are greener).
##   masonry  (masonry_material)  crypts, the chapel, the cemetery wall: coursed stone blocks
##            with joints, cracks, damp and ivy creeping up from the ground. Vertex alpha:
##            0 = coursed blocks, 0.5 = dressed stone (columns, mouldings), 1 = wrought iron.
##   prop     (MeshBuilder.prop_material) wood, cloth, plants, dirt, bones (alpha = wind sway),
##            and MeshBuilder.glow_material for flames, lantern glass and ghost-lights.
##
## Headstones (TOMB_KINDS, two shapes each): rounded, gothic pointed, shouldered tablet, Latin
## cross, Celtic cross, obelisk, angel, broken, child's stone with a lamb, ledger slab, chest
## tomb, draped urn. All carry carved names and dates (rows of little "words").
## Landmarks: four kinds of crypt / mausoleum and the ruined chapel with its bell tower.

const TOMB_KINDS := 12
const TOMB_SHAPES := 2
const DEAD_SHAPES := 6
const WILLOW_SHAPES := 2

const STONE := Color(0.68, 0.67, 0.64, 0.0)
const STONE_B := Color(0.6, 0.59, 0.57, 0.0)
const CARVE := Color(0.35, 0.34, 0.32, 1.0)
const MASON := Color(0.5, 0.49, 0.47, 0.0)
const DRESSED := Color(0.6, 0.59, 0.56, 0.5)
const IRON_M := Color(0.12, 0.12, 0.13, 1.0)
const IRON := Color(0.07, 0.07, 0.08, 0.0)
const RUST := Color(0.28, 0.15, 0.08, 0.0)
const WOOD := Color(0.3, 0.2, 0.12, 0.0)
const OLD_WOOD := Color(0.26, 0.22, 0.18, 0.0)
const DARK_WOOD := Color(0.14, 0.1, 0.07, 0.0)
const DIRT := Color(0.2, 0.145, 0.095, 0.0)
const DIRT_DARK := Color(0.11, 0.08, 0.055, 0.0)
const BONE := Color(0.8, 0.76, 0.66, 0.0)
const BARK := Color(0.2, 0.18, 0.16, 0.0)
const SLATE := Color(0.16, 0.17, 0.19, 0.0)
const BRONZE := Color(0.36, 0.27, 0.13, 0.0)
const FLAME := Color(1.0, 0.6, 0.22, 0.0)
const CANDLE := Color(0.85, 0.8, 0.68, 0.0)
const MOSS := Color(0.16, 0.24, 0.09, 0.0)
const HANGING_MOSS := Color(0.32, 0.35, 0.26, 0.6)

const STONE_SHADER := """
shader_type spatial;
varying vec3 wpos;
varying vec3 wnrm;
varying float ly;
varying float moss;
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float n3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x), mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x), mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm3(vec3 p) { return n3(p) * 0.5 + n3(p * 2.07) * 0.3 + n3(p * 4.3) * 0.2; }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ly = VERTEX.y;
	moss = INSTANCE_CUSTOM.x;
}
void fragment() {
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	vec3 base = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float carve = step(0.5, COLOR.a);
	float g = fbm3(wpos * 2.3);
	vec3 col = base * (0.72 + 0.5 * g) * (0.9 + 0.14 * n3(wpos * 26.0));
	// dark weathering streaks running down the faces
	float streak = smoothstep(0.55, 0.85, n3(vec3((wpos.x + wpos.z) * 7.0, wpos.y * 0.7, wpos.z * 3.0)));
	col *= 1.0 - streak * 0.35 * (1.0 - abs(wnrm.y));
	// grime creeping up from the ground
	col *= mix(0.55, 1.0, smoothstep(0.0, 0.5, ly + (g - 0.5) * 0.3));
	// carved letters and emblems: dark and dirty
	col = mix(col, col * 0.3, carve);
	// lichen: pale grey-green and rusty orange blotches
	float lich = smoothstep(0.64, 0.7, n3(wpos * 6.5 + 13.0)) * smoothstep(0.3, 0.6, n3(wpos * 1.3 + 3.0));
	vec3 lc = mix(vec3(0.56, 0.58, 0.46), vec3(0.55, 0.42, 0.26), step(0.6, n3(wpos * 2.0 + 40.0)));
	col = mix(col, lc * (0.7 + 0.3 * g) * base * 1.6, lich * (0.25 + 0.35 * moss));
	// moss: on the tops, low down and in the carving, in soft clumps
	float up = smoothstep(0.35, 0.9, wnrm.y);
	float low = 1.0 - smoothstep(0.05, 0.5 + moss * 0.5, ly);
	float m = max(up * (0.5 + 0.5 * moss), low * (0.45 + 0.5 * moss)) + carve * 0.35 * moss;
	m *= smoothstep(0.42, 0.72, fbm3(wpos * 6.0 + 7.0) * 0.7 + n3(wpos * 19.0) * 0.3 + moss * 0.12);
	vec3 mc = mix(vec3(0.05, 0.08, 0.03), vec3(0.13, 0.18, 0.06), n3(wpos * 23.0));
	col = mix(col, mc, clamp(m, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.84, 0.97, m);
	SPECULAR = 0.3;
}
"""

const MASONRY_SHADER := """
shader_type spatial;
uniform float ivy_amount = 1.0;
varying vec3 wpos;
varying vec3 wnrm;
varying float kind;
varying float ly;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.5 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.2; }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	kind = COLOR.a;
	ly = VERTEX.y;
}
void fragment() {
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	vec3 base = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	vec2 uv = abs(wnrm.x) > abs(wnrm.z) ? wpos.zy : wpos.xy;
	if (abs(wnrm.y) > 0.5) { uv = wpos.xz; }
	float n = fbm(uv * 3.0);
	vec3 col = base * (0.75 + 0.45 * n) * (0.9 + 0.14 * noise(uv * 28.0));
	float rough = 0.92;
	float metal = 0.0;
	if (kind > 0.75) {
		// wrought iron: near black, rust blooms
		float r = smoothstep(0.55, 0.8, fbm(uv * 9.0 + wpos.y * 3.0));
		col = mix(base, vec3(0.2, 0.09, 0.04), r);
		rough = mix(0.55, 0.95, r);
		metal = 0.5 * (1.0 - r);
	} else if (kind < 0.25 && abs(wnrm.y) < 0.5) {
		// coursed blocks
		vec2 p = uv / vec2(0.9, 0.42);
		float row = floor(p.y);
		p.x += 0.5 * mod(row, 2.0) + (hash(vec2(row, 3.0)) - 0.5) * 0.4;
		vec2 id = floor(p);
		vec2 f = fract(p);
		float h = hash(id);
		vec2 fw = f + (vec2(noise(uv * 6.0 + 3.0), noise(uv * 6.0 - 5.0)) - 0.5) * vec2(0.04, 0.08);
		float edge = min(min(fw.x, 1.0 - fw.x) * 0.9, min(fw.y, 1.0 - fw.y) * 0.42);
		float line = smoothstep(0.012, 0.03, edge);
		col *= 0.78 + 0.36 * h;
		col *= hash(id + 9.0) < 0.33 ? vec3(1.06, 1.0, 0.92) : vec3(0.96, 1.0, 1.04);
		col *= mix(0.75, 1.03, smoothstep(0.01, 0.1, edge));
		// cracks
		float ck = abs(fract(uv.x * 0.6 + noise(vec2(uv.y * 2.0, uv.x)) * 0.5) - 0.5);
		float crack = (1.0 - smoothstep(0.004, 0.012, ck)) * step(0.82, noise(vec2(floor(uv.x * 0.6), 7.0))) * smoothstep(0.3, 0.7, noise(uv * 0.9));
		col = mix(col, col * 0.3, crack);
		col = mix(vec3(0.05, 0.05, 0.045) + base * 0.15, col, line);
	}
	if (kind < 0.75) {
		// damp streaks down from the top, grime at the foot
		float streak = smoothstep(0.55, 0.85, noise(vec2(uv.x * 2.4, uv.y * 0.15)) * 0.7 + noise(vec2(uv.x * 8.0, uv.y * 0.4)) * 0.3);
		col *= 1.0 - streak * 0.35 * (1.0 - abs(wnrm.y));
		col *= mix(0.6, 1.0, smoothstep(0.0, 1.2, ly + (n - 0.5)));
		// moss on ledges and tops
		float top = smoothstep(0.5, 0.9, wnrm.y) * smoothstep(0.42, 0.6, fbm(wpos.xz * 2.0 + 5.0));
		col = mix(col, vec3(0.07, 0.11, 0.035) * (0.8 + 0.5 * n), top * 0.85);
		// ivy: patches climbing from the ground, made of little leaves
		float patch = fbm(uv * vec2(0.35, 0.2) + 13.0);
		float reach = mix(0.8, 4.5, smoothstep(0.45, 0.7, patch));
		float climb = smoothstep(reach, reach * 0.35, ly + (noise(uv * 1.3) - 0.5) * 1.2);
		float ivy = smoothstep(0.46, 0.56, patch) * climb * ivy_amount * (1.0 - abs(wnrm.y));
		if (ivy > 0.001) {
			vec2 g = uv * 6.0;
			vec2 gi = floor(g);
			float best = 8.0;
			float lh = 0.0;
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					vec2 o = vec2(float(x), float(y));
					vec2 c = o + vec2(hash(gi + o), hash(gi + o + 7.0)) - fract(g);
					c.y *= 1.25;
					float dd = length(c) + abs(c.x) * 0.35;
					if (dd < best) { best = dd; lh = hash(gi + o + 3.0); }
				}
			}
			float leaves = 1.0 - smoothstep(0.5, 0.58, best);
			vec3 leafcol = mix(vec3(0.05, 0.12, 0.04), vec3(0.16, 0.26, 0.08), lh) * (0.75 + 0.45 * smoothstep(0.5, 0.0, best));
			col *= 1.0 - ivy * 0.35;
			col = mix(col, leafcol, ivy * leaves);
			rough = mix(rough, 0.6, ivy * leaves);
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
}
"""

static var _stone_mat: ShaderMaterial
static var _mason_mat: ShaderMaterial
static var _cache := {}


static func stone_material() -> ShaderMaterial:
	if _stone_mat == null:
		var sh := Shader.new()
		sh.code = STONE_SHADER
		_stone_mat = ShaderMaterial.new()
		_stone_mat.shader = sh
	return _stone_mat


static func masonry_material() -> ShaderMaterial:
	if _mason_mat == null:
		var sh := Shader.new()
		sh.code = MASONRY_SHADER
		_mason_mat = ShaderMaterial.new()
		_mason_mat.shader = sh
	return _mason_mat


static func clear_cache() -> void:
	_cache.clear()


# ------------------------------------------------------------------ geometry helpers

## An extruded convex polygon: `pts` in the XY plane (any winding), `depth` along Z, centred.
## Flat normals; faces wound for Godot (clockwise seen from the front).
static func prism(pts: PackedVector2Array, depth: float) -> Array:
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var idx := PackedInt32Array()
	var hz := depth * 0.5
	var c := pts.size()
	var area := 0.0
	for k in c:
		var a := pts[k]
		var b := pts[(k + 1) % c]
		area += a.x * b.y - b.x * a.y
	var ccw := area > 0.0
	for face in [1.0, -1.0]:
		var base := v.size()
		for p in pts:
			v.append(Vector3(p.x, p.y, hz * face))
			nm.append(Vector3(0, 0, face))
		for k in range(1, c - 1):
			_tri(idx, v, base, base + k, base + k + 1, Vector3(0, 0, face))
	for k in c:
		var a := pts[k]
		var b := pts[(k + 1) % c]
		var e := b - a
		var n := Vector3(e.y, -e.x, 0.0).normalized() if ccw else Vector3(-e.y, e.x, 0.0).normalized()
		var base := v.size()
		v.append(Vector3(a.x, a.y, hz)); v.append(Vector3(b.x, b.y, hz))
		v.append(Vector3(b.x, b.y, -hz)); v.append(Vector3(a.x, a.y, -hz))
		for q in 4:
			nm.append(n)
		_tri(idx, v, base, base + 1, base + 2, n)
		_tri(idx, v, base, base + 2, base + 3, n)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Append a triangle wound so its front faces along `n`.
static func _tri(idx: PackedInt32Array, v: PackedVector3Array, a: int, b: int, c: int, n: Vector3) -> void:
	if (v[b] - v[a]).cross(v[c] - v[a]).dot(n) < 0.0:
		idx.append(a); idx.append(b); idx.append(c)
	else:
		idx.append(a); idx.append(c); idx.append(b)


## A triangular gable `w` wide, `h` high, `d` deep (base at y = 0).
static func gable(w: float, h: float, d: float) -> Array:
	return prism(PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), Vector2(0, h)]), d)


## Outline of a round-topped stone: straight sides up to `h - r`, then an arc of radius r
## (r >= w/2: a segmental arch, flatter than a semicircle).
static func _round_top(w: float, h: float, r: float, segs := 12) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0)])
	var half_ang := asin(clampf(w * 0.5 / r, 0.0, 1.0))
	var cy := h - r
	for k in segs + 1:
		var a := half_ang - 2.0 * half_ang * k / segs   # right side round to the left
		pts.append(Vector2(r * sin(a), cy + r * cos(a)))
	return pts


## Outline of a pointed (gothic) top: sides up to `spring`, then two arcs meeting at h.
static func _pointed_top(w: float, h: float, spring: float, segs := 7) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, spring)])
	var rise := h - spring
	# each arc is centred on the far spring line, radius R chosen to reach the apex
	var r := (w * w + rise * rise) / (2.0 * w) if rise < w else w
	r = maxf(r, w * 0.5 + 0.01)
	var cx := w * 0.5 - r
	for k in range(1, segs):
		var t := float(k) / segs
		var y := spring + rise * t
		var x := cx + sqrt(maxf(r * r - pow(y - spring, 2.0), 0.0))
		pts.append(Vector2(minf(x, w * 0.5), y))
	pts.append(Vector2(0, h))
	for k in range(segs - 1, 0, -1):
		var t := float(k) / segs
		var y := spring + rise * t
		var x := cx + sqrt(maxf(r * r - pow(y - spring, 2.0), 0.0))
		pts.append(Vector2(-minf(x, w * 0.5), y))
	pts.append(Vector2(-w * 0.5, spring))
	return pts


static func _c(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## Carved lettering on a face at depth `z` (+Z facing): a name, dates and a short epitaph as
## rows of little word-blocks, centred, from `top` downward.
static func _inscribe(mb: MeshBuilder, w: float, top: float, z: float, rng: RandomNumberGenerator, lines := 4, scale := 1.0) -> float:
	var y := top
	for l in lines:
		var lh := (0.045 if l == 0 else 0.03) * scale
		var lw := w * (0.78 if l == 0 else (0.55 if l == 1 else rng.randf_range(0.35, 0.72)))
		var x := -lw * 0.5
		while x < lw * 0.5 - 0.02:
			var ww := minf(rng.randf_range(0.04, 0.15) * scale, lw * 0.5 - x)
			if ww > 0.015:
				mb.add(MeshBuilder.box(Vector3(ww, lh, 0.012)), Transform3D(Basis(), Vector3(x + ww * 0.5, y, z)), CARVE)
			x += ww + rng.randf_range(0.022, 0.04) * scale
		y -= lh + rng.randf_range(0.035, 0.055) * scale
	return y


## A small carved emblem: a cross, a ring, a star or praying hands (a round boss).
static func _emblem(mb: MeshBuilder, at: Vector3, s: float, kind: int) -> void:
	match kind % 4:
		0:
			mb.add(MeshBuilder.box(Vector3(0.025, 0.12, 0.012) * s), Transform3D(Basis(), at), CARVE)
			mb.add(MeshBuilder.box(Vector3(0.08, 0.025, 0.012) * s), Transform3D(Basis(), at + Vector3(0, 0.025 * s, 0)), CARVE)
		1:
			for k in 10:
				var a := TAU * k / 10.0
				mb.add(MeshBuilder.box(Vector3(0.026, 0.012, 0.012) * s), Transform3D(Basis(Vector3(0, 0, 1), a + PI * 0.5), at + Vector3(cos(a), sin(a), 0) * 0.045 * s), CARVE)
		2:
			for k in 3:
				mb.add(MeshBuilder.box(Vector3(0.1, 0.018, 0.012) * s), Transform3D(Basis(Vector3(0, 0, 1), PI * k / 3.0), at), CARVE)
		_:
			mb.add(MeshBuilder.sphere(0.05 * s, 8, 5), Transform3D(Basis.from_scale(Vector3(1, 1, 0.25)), at), CARVE)


# ------------------------------------------------------------------ headstones

## Headstone of `kind` (0..TOMB_KINDS-1), shape variant `shape`. Returns {mesh, aabb, top}.
static func tomb(kind: int, shape: int) -> Dictionary:
	var key := "tomb_%d_%d" % [kind, shape]   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9173 * (kind + 1) + 31 * (shape + 1)
	var mb := MeshBuilder.new()
	var top := 1.0
	match kind:
		0: top = _rounded(mb, rng, shape)
		1: top = _gothic(mb, rng, shape)
		2: top = _shouldered(mb, rng, shape)
		3: top = _latin_cross(mb, rng, shape)
		4: top = _celtic_cross(mb, rng, shape)
		5: top = _obelisk(mb, rng, shape)
		6: top = _angel(mb, rng, shape)
		7: top = _broken(mb, rng, shape)
		8: top = _child(mb, rng, shape)
		9: top = _ledger(mb, rng, shape)
		10: top = _chest_tomb(mb, rng, shape)
		_: top = _urn(mb, rng, shape)
	var mesh := mb.commit(stone_material())
	var d := {"mesh": mesh, "aabb": mesh.get_aabb(), "top": top}
	_cache[key] = d
	return d


static func _plinth(mb: MeshBuilder, w: float, d: float, h: float, col := STONE_B) -> void:
	mb.add(MeshBuilder.box(Vector3(w, h, d)), Transform3D(Basis(), Vector3(0, h * 0.5 - 0.06, 0)), col)


static func _rounded(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	var w := rng.randf_range(0.62, 0.82) if shape == 0 else rng.randf_range(0.75, 0.95)
	var h := rng.randf_range(0.85, 1.05) if shape == 0 else rng.randf_range(1.05, 1.3)
	var t := rng.randf_range(0.12, 0.16)
	var r := w * 0.5 if shape == 0 else w * 0.8
	_plinth(mb, w + 0.18, t + 0.22, 0.18)
	mb.add(prism(_round_top(w, h, r), t), Transform3D(Basis(), Vector3(0, 0.1, 0)), STONE)
	# a raised, polished panel with a carved border
	mb.add(prism(_round_top(w * 0.82, h * 0.88, r * 0.82), 0.012), Transform3D(Basis(), Vector3(0, 0.14, t * 0.5 + 0.004)), STONE.lightened(0.05))
	_emblem(mb, Vector3(0, 0.1 + h - r * 0.55, t * 0.5 + 0.012), 1.0, shape * 2 + rng.randi() % 2)
	_inscribe(mb, w * 0.8, 0.1 + h - r * 0.9, t * 0.5 + 0.012, rng, 4 + shape)
	return h + 0.1


static func _gothic(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	var w := rng.randf_range(0.6, 0.78)
	var h := rng.randf_range(1.0, 1.25) if shape == 0 else rng.randf_range(1.3, 1.55)
	var t := 0.15
	_plinth(mb, w + 0.24, t + 0.26, 0.22)
	mb.add(prism(_pointed_top(w, h, h - w * 0.75), t), Transform3D(Basis(), Vector3(0, 0.14, 0)), STONE)
	# a carved trefoil arch near the top and a sunken pointed panel
	mb.add(prism(_pointed_top(w * 0.7, h * 0.78, h * 0.78 - w * 0.55), 0.01), Transform3D(Basis(), Vector3(0, 0.22, t * 0.5 + 0.004)), STONE.darkened(0.06))
	for k in 3:
		var a := PI * 0.5 + (k - 1) * 0.9
		mb.add(MeshBuilder.cyl(0.045, 0.045, 0.012, 10), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(cos(a) * 0.06, 0.14 + h - w * 0.45 + sin(a) * 0.05, t * 0.5 + 0.012)), CARVE)
	_inscribe(mb, w * 0.65, 0.14 + h - w * 0.75, t * 0.5 + 0.012, rng, 5)
	if shape == 1:   # little crockets climbing the arch
		for k in 4:
			var y := 0.14 + h - w * 0.75 + k * w * 0.18
			for sd in [-1.0, 1.0]:
				mb.add(MeshBuilder.sphere(0.03, 6, 4), Transform3D(Basis(), Vector3(sd * (w * 0.5 - k * w * 0.11), y, 0)), STONE)
		mb.add(MeshBuilder.cone(0.05, 0.16, 6), Transform3D(Basis(), Vector3(0, 0.14 + h + 0.06, 0)), STONE)
	return h + 0.14


static func _shouldered(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	var w := rng.randf_range(0.8, 1.0)
	var h := rng.randf_range(0.8, 1.0)
	var t := 0.14
	_plinth(mb, w + 0.16, t + 0.2, 0.16)
	mb.add(MeshBuilder.box(Vector3(w, h, t)), Transform3D(Basis(), Vector3(0, 0.1 + h * 0.5, 0)), STONE)
	# central raised pediment (round or triangular) and two scrolls on the shoulders
	if shape == 0:
		mb.add(prism(_round_top(w * 0.6, 0.22, w * 0.42), t), Transform3D(Basis(), Vector3(0, 0.1 + h, 0)), STONE)
	else:
		mb.add(gable(w * 0.75, 0.22, t), Transform3D(Basis(), Vector3(0, 0.1 + h, 0)), STONE)
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.cyl(0.06, 0.06, t + 0.02, 10), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(sd * (w * 0.5 - 0.06), 0.1 + h + 0.02, 0)), STONE_B)
	# a moulded frame around the inscription
	for e in [[Vector3(w * 0.84, 0.02, 0.012), Vector3(0, 0.1 + h * 0.92, 0)], [Vector3(w * 0.84, 0.02, 0.012), Vector3(0, 0.1 + h * 0.08, 0)],
			[Vector3(0.02, h * 0.84, 0.012), Vector3(-w * 0.41, 0.1 + h * 0.5, 0)], [Vector3(0.02, h * 0.84, 0.012), Vector3(w * 0.41, 0.1 + h * 0.5, 0)]]:
		mb.add(MeshBuilder.box(e[0]), Transform3D(Basis(), e[1] + Vector3(0, 0, t * 0.5 + 0.004)), CARVE)
	_emblem(mb, Vector3(0, 0.1 + h + 0.08, t * 0.5 + 0.006), 0.9, rng.randi())
	_inscribe(mb, w * 0.72, 0.1 + h * 0.84, t * 0.5 + 0.008, rng, 6)
	return h + 0.32


static func _latin_cross(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	var h := rng.randf_range(1.3, 1.6) if shape == 0 else rng.randf_range(1.7, 2.1)
	var s := 0.13
	# two (or three) stepped base blocks with the name on the top step
	var steps := 2 if shape == 0 else 3
	var y := 0.0
	for k in steps:
		var bw := 0.75 - k * 0.18
		var bh := 0.2
		mb.add(MeshBuilder.box(Vector3(bw, bh, bw * 0.7)), Transform3D(Basis(), Vector3(0, y + bh * 0.5 - 0.05, 0)), STONE_B if k % 2 == 0 else STONE)
		y += bh
	_inscribe(mb, 0.5, y - 0.07, (0.75 - (steps - 1) * 0.18) * 0.35 + 0.005, rng, 2, 0.8)
	mb.add(MeshBuilder.box(Vector3(s, h, s)), Transform3D(Basis(), Vector3(0, y + h * 0.5 - 0.05, 0)), STONE)
	var arm := h * 0.45
	mb.add(MeshBuilder.box(Vector3(arm, s, s)), Transform3D(Basis(), Vector3(0, y + h * 0.72, 0)), STONE)
	if shape == 1:   # trefoil ends
		for p in [Vector3(-arm * 0.5, y + h * 0.72, 0), Vector3(arm * 0.5, y + h * 0.72, 0), Vector3(0, y + h - 0.05, 0)]:
			mb.add(MeshBuilder.sphere(0.085, 8, 5), Transform3D(Basis(), p), STONE)
	mb.add(MeshBuilder.box(Vector3(0.03, 0.03, 0.012)), Transform3D(Basis(), Vector3(0, y + h * 0.72, s * 0.5 + 0.004)), CARVE)
	return y + h


static func _celtic_cross(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	var h := rng.randf_range(1.6, 1.9) if shape == 0 else rng.randf_range(2.1, 2.5)
	mb.add(MeshBuilder.box(Vector3(0.7, 0.35, 0.45)), Transform3D(Basis(), Vector3(0, 0.12, 0)), STONE_B)
	mb.add(prism(PackedVector2Array([Vector2(-0.2, 0), Vector2(0.2, 0), Vector2(0.24, 0.35), Vector2(-0.24, 0.35)]), 0.32), Transform3D(Basis(), Vector3(0, 0.28, 0)), STONE)
	_inscribe(mb, 0.36, 0.53, 0.168, rng, 3, 0.8)
	var y := 0.63
	var sh := h - 0.63
	# tapering shaft
	mb.add(prism(PackedVector2Array([Vector2(-0.13, 0), Vector2(0.13, 0), Vector2(0.1, sh), Vector2(-0.1, sh)]), 0.14), Transform3D(Basis(), Vector3(0, y, 0)), STONE)
	var c := Vector3(0, y + sh * 0.78, 0)
	# flared arms and head
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		if is_equal_approx(a, PI * 1.5):
			continue
		var arm := prism(PackedVector2Array([Vector2(0, -0.07), Vector2(0.32, -0.11), Vector2(0.32, 0.11), Vector2(0, 0.07)]), 0.14)
		mb.add(arm, Transform3D(Basis(Vector3(0, 0, 1), a), c), STONE)
	# the ring
	var rr := 0.24
	for k in 16:
		var a := TAU * k / 16.0
		mb.add(MeshBuilder.box(Vector3(0.1, 0.05, 0.11)), Transform3D(Basis(Vector3(0, 0, 1), a + PI * 0.5), c + Vector3(cos(a), sin(a), 0) * rr), STONE)
	# knotwork bosses and interlace down the shaft
	mb.add(MeshBuilder.sphere(0.07, 10, 6), Transform3D(Basis.from_scale(Vector3(1, 1, 0.55)), c + Vector3(0, 0, 0.07)), STONE)
	for k in 5:
		var p := Vector3(0, y + 0.15 + k * sh * 0.11, 0.07)
		mb.add(MeshBuilder.box(Vector3(0.1, 0.018, 0.01)), Transform3D(Basis(Vector3(0, 0, 1), 0.6 if k % 2 == 0 else -0.6), p), CARVE)
	if shape == 1:
		for k in 4:
			var a := PI * 0.25 + k * PI * 0.5
			mb.add(MeshBuilder.sphere(0.035, 6, 4), Transform3D(Basis(), c + Vector3(cos(a), sin(a), 0) * 0.17 + Vector3(0, 0, 0.06)), STONE)
	return y + sh * 0.78 + 0.33


static func _obelisk(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	var h := rng.randf_range(2.4, 2.9) if shape == 0 else rng.randf_range(3.2, 3.8)
	mb.add(MeshBuilder.box(Vector3(1.2, 0.25, 1.2)), Transform3D(Basis(), Vector3(0, 0.08, 0)), STONE_B)
	mb.add(MeshBuilder.box(Vector3(1.0, 0.2, 1.0)), Transform3D(Basis(), Vector3(0, 0.3, 0)), STONE)
	mb.add(MeshBuilder.box(Vector3(0.78, 0.75, 0.78)), Transform3D(Basis(), Vector3(0, 0.77, 0)), STONE)
	mb.add(MeshBuilder.box(Vector3(0.9, 0.1, 0.9)), Transform3D(Basis(), Vector3(0, 1.18, 0)), STONE_B)
	for face in 4:
		var rot := Basis(Vector3.UP, face * PI * 0.5)
		var mb2 := MeshBuilder.new()
		_inscribe(mb2, 0.6, 1.0, 0.0, rng, 4 if face == 0 else 3, 0.9)
		var arr := mb2.commit().surface_get_arrays(0)
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		# re-add each word-block rotated onto this face
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for k in verts.size():
			verts[k] = rot * (verts[k] + Vector3(0, 0, 0.395))
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for k in norms.size():
			norms[k] = rot * norms[k]
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		if cols.size() > 0:
			mb.add(arr, Transform3D(), CARVE)
	var sh := h - 1.23 - 0.3
	mb.add(MeshBuilder.cyl(0.24, 0.34, sh, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 1.23 + sh * 0.5, 0)), STONE)
	mb.add(MeshBuilder.cone(0.24, 0.3, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 1.23 + sh + 0.15, 0)), STONE)
	_emblem(mb, Vector3(0, 1.23 + sh * 0.7, 0.215), 1.2, 1 + shape)
	if shape == 1:   # a draped urn carved in relief at the base of the shaft
		mb.add(MeshBuilder.sphere(0.12, 8, 5), Transform3D(Basis.from_scale(Vector3(1, 1.2, 0.4)), Vector3(0, 1.5, 0.23)), STONE.lightened(0.04))
	return h


static func _angel(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	var marble := Color(0.78, 0.77, 0.74, 0.0)
	mb.add(MeshBuilder.box(Vector3(0.9, 0.25, 0.9)), Transform3D(Basis(), Vector3(0, 0.08, 0)), STONE_B)
	mb.add(MeshBuilder.box(Vector3(0.7, 0.8, 0.7)), Transform3D(Basis(), Vector3(0, 0.6, 0)), STONE)
	mb.add(MeshBuilder.box(Vector3(0.82, 0.08, 0.82)), Transform3D(Basis(), Vector3(0, 1.03, 0)), STONE_B)
	_inscribe(mb, 0.5, 0.88, 0.355, rng, 4, 0.85)
	var y := 1.07
	# robe falling in folds, a cord at the waist
	mb.add(MeshBuilder.cyl(0.17, 0.3, 0.95, 12), Transform3D(Basis(), Vector3(0, y + 0.47, 0)), marble)
	for k in 6:
		var a := TAU * k / 6.0 + 0.3
		mb.limb(Vector3(cos(a) * 0.27, y + 0.02, sin(a) * 0.27), Vector3(cos(a) * 0.16, y + 0.9, sin(a) * 0.16), 0.045, 0.02, marble.darkened(0.05), 5)
	mb.add(MeshBuilder.cyl(0.2, 0.17, 0.45, 12), Transform3D(Basis(), Vector3(0, y + 1.15, 0)), marble)
	mb.add(MeshBuilder.cyl(0.18, 0.18, 0.04, 12), Transform3D(Basis(), Vector3(0, y + 0.95, 0)), marble.darkened(0.08))
	# head, bowed, with hair
	var head := Vector3(0, y + 1.52, 0.05)
	mb.add(MeshBuilder.sphere(0.11, 10, 7), Transform3D(Basis(Vector3(1, 0, 0), 0.35), head), marble)
	mb.add(MeshBuilder.sphere(0.125, 10, 7), Transform3D(Basis.from_scale(Vector3(1.0, 0.9, 1.05)), head + Vector3(0, 0.03, -0.03)), marble.darkened(0.04))
	mb.limb(Vector3(0, y + 1.37, 0), head, 0.05, 0.05, marble, 6)
	# wings: layered feathers sweeping back and up
	for sd in [-1.0, 1.0]:
		for f in 5:
			var t := float(f) / 4.0
			var root := Vector3(sd * 0.1, y + 1.3, -0.12)
			var tip := root + Vector3(sd * (0.25 + 0.15 * t), 0.35 - 0.75 * t, -0.25 - 0.12 * t)
			mb.add(MeshBuilder.sphere(0.5, 8, 5), Transform3D(Basis.looking_at(tip - root, Vector3(sd, 0, 0)).scaled(Vector3(0.12, 0.05, 0.5 + 0.3 * (1.0 - t)) * (1.0 - t * 0.25)), root.lerp(tip, 0.5)), marble.darkened(0.03 * f))
	if shape == 0:   # hands together in prayer
		for sd in [-1.0, 1.0]:
			mb.limb(Vector3(sd * 0.19, y + 1.32, 0), Vector3(sd * 0.12, y + 1.08, 0.12), 0.05, 0.045, marble, 6)
			mb.limb(Vector3(sd * 0.12, y + 1.08, 0.12), Vector3(sd * 0.02, y + 1.24, 0.2), 0.04, 0.035, marble, 6)
		mb.add(MeshBuilder.sphere(0.05, 8, 5), Transform3D(Basis.from_scale(Vector3(0.7, 1.4, 0.7)), Vector3(0, y + 1.28, 0.22)), marble)
	else:   # one arm raised to heaven, the other holding a wreath
		mb.limb(Vector3(0.19, y + 1.32, 0), Vector3(0.26, y + 1.62, 0.05), 0.05, 0.045, marble, 6)
		mb.limb(Vector3(0.26, y + 1.62, 0.05), Vector3(0.24, y + 1.95, 0.08), 0.04, 0.03, marble, 6)
		mb.add(MeshBuilder.sphere(0.04, 6, 4), Transform3D(Basis(), Vector3(0.24, y + 1.98, 0.08)), marble)
		mb.limb(Vector3(-0.19, y + 1.32, 0), Vector3(-0.22, y + 1.05, 0.12), 0.05, 0.045, marble, 6)
		for k in 10:
			var a := TAU * k / 10.0
			mb.add(MeshBuilder.sphere(0.035, 6, 4), Transform3D(Basis(), Vector3(-0.22, y + 0.95, 0.16) + Vector3(cos(a) * 0.1, sin(a) * 0.1, 0)), marble)
	return y + (2.0 if shape == 1 else 1.68)


static func _broken(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	var w := rng.randf_range(0.65, 0.85)
	var h := rng.randf_range(0.9, 1.15)
	var t := 0.15
	var cut := h * rng.randf_range(0.4, 0.55)
	_plinth(mb, w + 0.18, t + 0.22, 0.16)
	# the stump, with a jagged break along its top
	var pts := PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, cut + 0.06), Vector2(w * 0.15, cut - 0.03), Vector2(-w * 0.2, cut + 0.1), Vector2(-w * 0.5, cut - 0.02)])
	mb.add(prism(pts, t), Transform3D(Basis(), Vector3(0, 0.1, 0)), STONE)
	for k in 3:
		mb.add(MeshBuilder.box(Vector3(rng.randf_range(0.06, 0.14), 0.05, t * 0.9)), Transform3D(Basis(Vector3(0, 0, 1), rng.randf_range(-0.6, 0.6)), Vector3(rng.randf_range(-w * 0.4, w * 0.4), 0.1 + cut + 0.02, 0)), STONE)
	_inscribe(mb, w * 0.7, 0.1 + cut - 0.1, t * 0.5 + 0.005, rng, 2)
	# the top half lies face up on the grave in front (or face down, on the second shape)
	var top := _round_top(w, h - cut, w * 0.5)
	var lie := Basis(Vector3(1, 0, 0), -PI * 0.5 + rng.randf_range(-0.08, 0.08)) if shape == 0 else Basis(Vector3(1, 0, 0), PI * 0.5 - 0.15)
	var yaw := Basis(Vector3.UP, rng.randf_range(-0.6, 0.6))
	mb.add(prism(top, t), Transform3D(yaw * lie, Vector3(rng.randf_range(-0.15, 0.15), 0.06, 0.35)), STONE)
	if shape == 0:
		var mb2 := MeshBuilder.new()
		_inscribe(mb2, w * 0.7, h - cut - 0.25, 0.0, rng, 3)
		var arr := mb2.commit().surface_get_arrays(0)
		var xf := Transform3D(yaw * lie, Vector3(0, 0.06, 0.35) + (yaw * lie) * Vector3(0, 0, t * 0.5 + 0.004))
		mb.add(arr, xf, CARVE)
	for k in 4:   # chips
		mb.add(MeshBuilder.box(Vector3.ONE * rng.randf_range(0.04, 0.09)), Transform3D(Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU), Vector3(rng.randf_range(-0.5, 0.5), 0.03, rng.randf_range(0.1, 0.9))), STONE)
	return cut + 0.2


static func _child(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	var w := rng.randf_range(0.4, 0.5)
	var h := rng.randf_range(0.45, 0.6)
	var t := 0.12
	_plinth(mb, w + 0.12, t + 0.16, 0.12)
	mb.add(prism(_round_top(w, h, w * 0.5), t), Transform3D(Basis(), Vector3(0, 0.07, 0)), STONE.lightened(0.06))
	_inscribe(mb, w * 0.75, 0.07 + h * 0.52, t * 0.5 + 0.005, rng, 3, 0.75)
	if shape == 0:   # a little lamb resting on top
		var y := 0.07 + h
		mb.add(MeshBuilder.sphere(0.11, 8, 6), Transform3D(Basis.from_scale(Vector3(0.75, 0.6, 1.0)), Vector3(0, y + 0.05, 0)), STONE.lightened(0.08))
		mb.add(MeshBuilder.sphere(0.055, 8, 6), Transform3D(Basis.from_scale(Vector3(0.8, 0.85, 1.1)), Vector3(0, y + 0.11, 0.09)), STONE.lightened(0.08))
	else:   # a carved heart and a rosebud
		mb.add(MeshBuilder.sphere(0.035, 8, 5), Transform3D(Basis.from_scale(Vector3(1, 1, 0.3)), Vector3(-0.025, 0.07 + h * 0.75, t * 0.5 + 0.004)), CARVE)
		mb.add(MeshBuilder.sphere(0.035, 8, 5), Transform3D(Basis.from_scale(Vector3(1, 1, 0.3)), Vector3(0.025, 0.07 + h * 0.75, t * 0.5 + 0.004)), CARVE)
		mb.add(MeshBuilder.cone(0.045, 0.06, 6), Transform3D(Basis(Vector3(1, 0, 0), PI), Vector3(0, 0.07 + h * 0.75 - 0.04, t * 0.5 + 0.004)), CARVE)
	return h + 0.12


static func _ledger(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	var w := 0.95
	var l := 2.0
	# a flat slab over the grave (in front of the origin), bevelled, with a raised cross
	mb.add(MeshBuilder.box(Vector3(w + 0.1, 0.12, l + 0.1)), Transform3D(Basis(), Vector3(0, 0.03, l * 0.5)), STONE_B)
	mb.add(MeshBuilder.box(Vector3(w, 0.1, l)), Transform3D(Basis(), Vector3(0, 0.12, l * 0.5)), STONE)
	mb.add(MeshBuilder.box(Vector3(0.07, 0.03, l * 0.7)), Transform3D(Basis(), Vector3(0, 0.18, l * 0.5)), STONE.lightened(0.04))
	mb.add(MeshBuilder.box(Vector3(w * 0.6, 0.03, 0.07)), Transform3D(Basis(), Vector3(0, 0.18, l * 0.28)), STONE.lightened(0.04))
	# lettering on the top face, read from the foot
	var mb2 := MeshBuilder.new()
	_inscribe(mb2, w * 0.7, 0.0, 0.0, rng, 4, 0.9)
	var arr := mb2.commit().surface_get_arrays(0)
	for side in [-1.0, 1.0]:
		mb.add(arr, Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5) * Basis(Vector3.UP, 0.0), Vector3(side * 0.25, 0.172, l * 0.62)).scaled_local(Vector3(0.5, 1.0, 1.0)), CARVE)
	if shape == 1:   # a cracked corner sunk into the ground, and a small headstone
		mb.add(MeshBuilder.box(Vector3(0.6, 0.3, 0.1)), Transform3D(Basis(), Vector3(0, 0.15, -0.02)), STONE)
		_inscribe(mb, 0.5, 0.24, 0.055, rng, 2, 0.7)
		return 0.35
	return 0.2


static func _chest_tomb(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	var w := 1.0
	var l := 2.1
	var h := 0.85
	mb.add(MeshBuilder.box(Vector3(w + 0.2, 0.15, l + 0.2)), Transform3D(Basis(), Vector3(0, 0.03, l * 0.5)), STONE_B)
	mb.add(MeshBuilder.box(Vector3(w, h, l)), Transform3D(Basis(), Vector3(0, h * 0.5 + 0.08, l * 0.5)), STONE)
	# corner pilasters and recessed side panels with carved wreaths
	for sx in [-1.0, 1.0]:
		for sz in [0.0, 1.0]:
			mb.add(MeshBuilder.box(Vector3(0.14, h, 0.14)), Transform3D(Basis(), Vector3(sx * w * 0.5, h * 0.5 + 0.08, sz * l)), STONE_B)
		for p in 2:
			var z := l * (0.27 + 0.46 * p)
			mb.add(MeshBuilder.box(Vector3(0.012, h * 0.62, l * 0.36)), Transform3D(Basis(), Vector3(sx * (w * 0.5 + 0.004), h * 0.5 + 0.08, z)), STONE.darkened(0.08))
			for k in 8:
				var a := TAU * k / 8.0
				mb.add(MeshBuilder.box(Vector3(0.012, 0.03, 0.06)), Transform3D(Basis(Vector3(1, 0, 0), a), Vector3(sx * (w * 0.5 + 0.01), h * 0.5 + 0.08 + sin(a) * 0.12, z + cos(a) * 0.12)), CARVE)
	_inscribe(mb, w * 0.7, h * 0.7 + 0.08, l + 0.005, rng, 3, 0.85)
	_inscribe(mb, w * 0.7, h * 0.7 + 0.08, -0.005, rng, 2, 0.85)
	# the lid: a heavy overhanging slab (on the second shape, cracked and shoved askew)
	var lid := Transform3D(Basis(), Vector3(0, h + 0.14, l * 0.5))
	if shape == 1:
		lid = Transform3D(Basis(Vector3.UP, 0.18) * Basis(Vector3(0, 0, 1), 0.06), Vector3(0.18, h + 0.16, l * 0.55))
		mb.add(MeshBuilder.box(Vector3(w * 0.8, 0.05, l * 0.8)), Transform3D(Basis(), Vector3(0, h + 0.07, l * 0.5)), Color(0.05, 0.05, 0.05, 1.0))
	mb.add(MeshBuilder.box(Vector3(w + 0.16, 0.12, l + 0.16)), lid, STONE.lightened(0.03))
	mb.add(MeshBuilder.box(Vector3(w * 0.4, 0.04, 0.06)), lid * Transform3D(Basis(), Vector3(0, 0.075, -l * 0.15)), STONE)
	mb.add(MeshBuilder.box(Vector3(0.06, 0.04, l * 0.6)), lid * Transform3D(Basis(), Vector3(0, 0.075, 0)), STONE)
	return h + 0.22


static func _urn(mb: MeshBuilder, rng: RandomNumberGenerator, shape: int) -> float:
	mb.add(MeshBuilder.box(Vector3(0.75, 0.2, 0.75)), Transform3D(Basis(), Vector3(0, 0.06, 0)), STONE_B)
	var ph := 1.0 if shape == 0 else 1.35
	mb.add(MeshBuilder.box(Vector3(0.55, ph, 0.55)), Transform3D(Basis(), Vector3(0, 0.15 + ph * 0.5, 0)), STONE)
	mb.add(MeshBuilder.box(Vector3(0.66, 0.08, 0.66)), Transform3D(Basis(), Vector3(0, 0.15 + ph + 0.04, 0)), STONE_B)
	_inscribe(mb, 0.42, 0.15 + ph * 0.8, 0.28, rng, 5, 0.75)
	var y := 0.15 + ph + 0.08
	# the urn: foot, swelling body, neck, lid and knop, with a cloth draped over one side
	mb.add(MeshBuilder.cyl(0.1, 0.14, 0.1, 12), Transform3D(Basis(), Vector3(0, y + 0.05, 0)), STONE)
	mb.add(MeshBuilder.sphere(0.2, 12, 7), Transform3D(Basis.from_scale(Vector3(1, 1.15, 1)), Vector3(0, y + 0.3, 0)), STONE.lightened(0.04))
	mb.add(MeshBuilder.cyl(0.1, 0.12, 0.12, 12), Transform3D(Basis(), Vector3(0, y + 0.55, 0)), STONE)
	mb.add(MeshBuilder.cyl(0.14, 0.14, 0.04, 12), Transform3D(Basis(), Vector3(0, y + 0.62, 0)), STONE)
	mb.add(MeshBuilder.sphere(0.04, 6, 4), Transform3D(Basis(), Vector3(0, y + 0.67, 0)), STONE)
	mb.add(MeshBuilder.sphere(0.22, 10, 6), Transform3D(Basis(Vector3(0, 0, 1), 0.5).scaled(Vector3(0.6, 1.2, 1.05)), Vector3(0.08, y + 0.32, 0)), STONE.darkened(0.05))
	for k in 3:
		mb.limb(Vector3(0.1 + k * 0.03, y + 0.55, -0.12 + k * 0.12), Vector3(0.22, y + 0.08, -0.15 + k * 0.15), 0.025, 0.04, STONE.darkened(0.05), 5)
	return y + 0.7


# ------------------------------------------------------------------ grave furniture

## A low stone kerb framing a grave plot (in front of the headstone), filled with dark chippings.
static func kerb() -> ArrayMesh:
	if _cache.has("kerb"):
		return _cache["kerb"]
	var mb := MeshBuilder.new()
	var w := 1.0
	var l := 2.05
	for sx in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(0.1, 0.16, l)), Transform3D(Basis(), Vector3(sx * w * 0.5, 0.05, l * 0.5 + 0.1)), STONE_B)
	mb.add(MeshBuilder.box(Vector3(w + 0.1, 0.16, 0.1)), Transform3D(Basis(), Vector3(0, 0.05, l + 0.1)), STONE_B)
	for sx in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(0.14, 0.24, 0.14)), Transform3D(Basis(), Vector3(sx * w * 0.5, 0.08, l + 0.1)), STONE)
	mb.add(MeshBuilder.box(Vector3(w - 0.1, 0.06, l - 0.1)), Transform3D(Basis(), Vector3(0, 0.04, l * 0.5 + 0.1)), Color(0.3, 0.3, 0.32, 1.0))
	var m := mb.commit(stone_material())
	_cache["kerb"] = m
	return m


## A crude wooden cross for a fresh grave, with a painted name board.
static func wooden_cross(shape: int) -> ArrayMesh:
	var key := "wcross_%d" % shape   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 555 + shape
	var mb := MeshBuilder.new()
	var h := 1.1 + shape * 0.25
	var lean := Basis(Vector3(0, 0, 1), (shape - 0.5) * 0.12)
	mb.add(MeshBuilder.box(Vector3(0.08, h, 0.06)), Transform3D(lean, Vector3(0, h * 0.5 - 0.2, 0)), OLD_WOOD)
	mb.add(MeshBuilder.box(Vector3(0.55, 0.07, 0.06)), Transform3D(lean, lean * Vector3(0, h * 0.62, 0.0)), OLD_WOOD)
	mb.add(MeshBuilder.box(Vector3(0.3, 0.12, 0.015)), Transform3D(lean, lean * Vector3(0, h * 0.45, 0.04)), WOOD.lightened(0.1))
	for k in 2:
		mb.add(MeshBuilder.box(Vector3(0.18 - k * 0.06, 0.018, 0.005)), Transform3D(lean, lean * Vector3(0, h * 0.47 - k * 0.04, 0.05)), Color(0.08, 0.06, 0.05, 0.0))
	mb.add(MeshBuilder.sphere(0.02, 4, 3), Transform3D(Basis(), lean * Vector3(0, h * 0.62, 0.035)), IRON)
	var m := mb.commit()
	_cache[key] = m
	return m


## A freshly filled grave: a long heaped mound of loose earth with clods and a few stones.
static func dirt_mound(shape: int) -> ArrayMesh:
	var key := "mound_%d" % shape   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + shape * 13
	var mb := MeshBuilder.new()
	mb.add(ForestProps._lumpy(1.0, rng), Transform3D(Basis.from_scale(Vector3(0.62, 0.32, 1.15)), Vector3(0, -0.06, 1.15)), DIRT)
	for k in 10:
		var p := Vector3(rng.randf_range(-0.55, 0.55), 0.02, rng.randf_range(0.1, 2.2))
		mb.add(MeshBuilder.sphere(rng.randf_range(0.05, 0.1), 6, 4), Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), p + Vector3(0, 0.12 * (1.0 - absf(p.x)), 0)), DIRT_DARK if k % 3 else DIRT.lightened(0.1))
	var m := mb.commit()
	_cache[key] = m
	return m


## An open grave: the pit (walls and floor; the ground shader cuts the hole), a heap of dug
## earth beside it, a shovel stood in the heap, sometimes a coffin waiting below.
## Pit: 1.0 x 2.1 m centred on the origin, 1.4 m deep.
static func open_grave(shape: int) -> Dictionary:
	var key := "open_%d" % shape   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 919 + shape * 7
	var mb := MeshBuilder.new()
	var hx := 0.5
	var hz := 1.05
	var d := 1.4
	var wall := DIRT_DARK
	for sx in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(0.05, d + 0.1, hz * 2.0)), Transform3D(Basis(), Vector3(sx * (hx + 0.02), -d * 0.5 + 0.02, 0)), wall)
	for sz in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(hx * 2.0, d + 0.1, 0.05)), Transform3D(Basis(), Vector3(0, -d * 0.5 + 0.02, sz * (hz + 0.02))), wall)
	mb.add(MeshBuilder.box(Vector3(hx * 2.0, 0.05, hz * 2.0)), Transform3D(Basis(), Vector3(0, -d, 0)), Color(0.06, 0.045, 0.03, 0.0))
	# spade marks: darker gouges down the walls, roots poking out
	for k in 6:
		var sx := 1.0 if k % 2 == 0 else -1.0
		mb.add(MeshBuilder.box(Vector3(0.01, 0.35, 0.18)), Transform3D(Basis(), Vector3(sx * (hx - 0.005), -rng.randf_range(0.3, 1.1), rng.randf_range(-0.8, 0.8))), Color(0.07, 0.05, 0.035, 0.0))
		mb.limb(Vector3(sx * hx, -rng.randf_range(0.1, 0.6), rng.randf_range(-0.9, 0.9)), Vector3(sx * (hx - 0.18), -rng.randf_range(0.3, 0.9), rng.randf_range(-0.9, 0.9)), 0.012, 0.004, BARK, 4)
	if shape != 1:   # a coffin at the bottom, lid ajar
		mb.add(prism(_coffin_outline(0.36, 0.26, 1.85), 0.3), Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, -d + 0.18, 0)), DARK_WOOD)
		mb.add(prism(_coffin_outline(0.37, 0.27, 1.87), 0.04), Transform3D(Basis(Vector3.UP, 0.12) * Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0.1, -d + 0.36, 0.15)), WOOD)
	# rim lip: loose earth all round the edge
	for k in 14:
		var a := TAU * k / 14.0
		var p := Vector3(cos(a) * (hx + 0.14), 0.0, sin(a) * (hz + 0.14))
		mb.add(MeshBuilder.sphere(rng.randf_range(0.12, 0.2), 6, 4), Transform3D(Basis.from_scale(Vector3(1, 0.35, 1)), p), DIRT)
	# the spoil heap beside it and the shovel in it
	var heap := Vector3(hx + 0.95, 0.0, rng.randf_range(-0.3, 0.3))
	mb.add(ForestProps._lumpy(1.0, rng), Transform3D(Basis.from_scale(Vector3(0.75, 0.55, 1.05)), heap), DIRT.lightened(0.05))
	for k in 8:
		mb.add(MeshBuilder.sphere(rng.randf_range(0.06, 0.12), 6, 4), Transform3D(Basis(), heap + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.0, 0.4), rng.randf_range(-1.0, 1.0))), DIRT_DARK)
	_shovel(mb, heap + Vector3(0.1, 0.35, 0.2), Basis(Vector3(0, 0, 1), 0.25) * Basis(Vector3.UP, 0.6))
	var gb := MeshBuilder.new()
	if shape == 2:   # a lantern left on the heap
		_lantern(mb, gb, heap + Vector3(-0.2, 0.52, -0.6), 0.7)
	var m := mb.commit()
	gb.commit_into(m, MeshBuilder.glow_material())
	var dd := {"mesh": m, "half": Vector2(hx, hz)}
	_cache[key] = dd
	return dd


static func _shovel(mb: MeshBuilder, at: Vector3, basis: Basis) -> void:
	mb.add(MeshBuilder.cyl(0.02, 0.02, 1.1, 6), Transform3D(basis, at + basis * Vector3(0, 0.55, 0)), WOOD)
	mb.add(MeshBuilder.box(Vector3(0.16, 0.035, 0.035)), Transform3D(basis, at + basis * Vector3(0, 1.1, 0)), WOOD)
	mb.add(MeshBuilder.box(Vector3(0.22, 0.28, 0.02)), Transform3D(basis, at + basis * Vector3(0, -0.12, 0)), Color(0.32, 0.31, 0.3, 0.0))


## A small iron lantern (cage, glass and flame) at `at`, scale `s`.
static func _lantern(mb: MeshBuilder, gb: MeshBuilder, at: Vector3, s: float) -> void:
	mb.add(MeshBuilder.box(Vector3(0.2, 0.03, 0.2) * s), Transform3D(Basis(), at), IRON)
	mb.add(MeshBuilder.cone(0.15 * s, 0.12 * s, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), at + Vector3(0, 0.34 * s, 0)), IRON)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add(MeshBuilder.box(Vector3(0.02, 0.28, 0.02) * s), Transform3D(Basis(), at + Vector3(sx * 0.09, 0.15, sz * 0.09) * s), IRON)
	mb.limb(at + Vector3(0, 0.4, 0) * s, at + Vector3(0, 0.5, 0) * s, 0.012 * s, 0.012 * s, IRON, 4)
	gb.add(MeshBuilder.box(Vector3(0.15, 0.24, 0.15) * s), Transform3D(Basis(), at + Vector3(0, 0.15, 0) * s), Color(0.9, 0.6, 0.25, 0.0))
	gb.add(MeshBuilder.sphere(0.04 * s, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 1.8, 1)), at + Vector3(0, 0.14, 0) * s), FLAME)


## A coffin's six-sided outline in the XY plane (head at +Y): shoulder width, foot width, length.
static func _coffin_outline(shoulder: float, foot: float, length: float) -> PackedVector2Array:
	var head := shoulder * 0.7
	return PackedVector2Array([Vector2(-foot, -length * 0.5), Vector2(foot, -length * 0.5), Vector2(shoulder, length * 0.22),
		Vector2(head, length * 0.5), Vector2(-head, length * 0.5), Vector2(-shoulder, length * 0.22)])


## A lantern on an iron post (the avenues), lit.
static func lantern_post() -> ArrayMesh:
	if _cache.has("lantern_post"):
		return _cache["lantern_post"]
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	mb.add(MeshBuilder.box(Vector3(0.35, 0.3, 0.35)), Transform3D(Basis(), Vector3(0, 0.1, 0)), Color(0.4, 0.39, 0.37, 0.0))
	mb.limb(Vector3(0, 0.2, 0), Vector3(0, 2.6, 0), 0.05, 0.035, IRON, 8)
	for k in 4:   # scrollwork brackets under the lantern
		var a := TAU * k / 4.0
		mb.limb(Vector3(0, 2.35, 0), Vector3(cos(a) * 0.14, 2.6, sin(a) * 0.14), 0.012, 0.012, IRON, 4)
	_lantern(mb, gb, Vector3(0, 2.6, 0), 1.6)
	var m := mb.commit()
	gb.commit_into(m, MeshBuilder.glow_material())
	_cache["lantern_post"] = m
	return m


## A cluster of candles on a grave (wax stubs of different heights with glowing flames).
static func candles(shape: int) -> ArrayMesh:
	var key := "candles_%d" % shape   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 404 + shape
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	for k in 3 + shape:
		var p := Vector3(rng.randf_range(-0.18, 0.18), 0, rng.randf_range(-0.12, 0.12))
		var h := rng.randf_range(0.08, 0.26)
		mb.add(MeshBuilder.cyl(0.028, 0.032, h, 7), Transform3D(Basis(), p + Vector3(0, h * 0.5, 0)), CANDLE if k % 2 else Color(0.8, 0.12, 0.1, 0.0))
		mb.add(MeshBuilder.sphere(0.035, 6, 3), Transform3D(Basis.from_scale(Vector3(1.3, 0.35, 1.3)), p + Vector3(0, 0.005, 0)), CANDLE)
		gb.add(MeshBuilder.sphere(0.022, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 2.0, 1)), p + Vector3(0, h + 0.035, 0)), FLAME)
	var m := mb.commit(MeshBuilder.foliage_material())
	gb.commit_into(m, MeshBuilder.glow_material())
	_cache[key] = m
	return m


## A funeral wreath leant against the foot of a headstone: evergreen ring, berries, a ribbon.
static func wreath(shape: int) -> ArrayMesh:
	var key := "wreath_%d" % shape   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 808 + shape
	var mb := MeshBuilder.new()
	var tilt := Basis(Vector3(1, 0, 0), -0.25)
	var c := Vector3(0, 0.26, 0)
	var green := Color(0.12, 0.2, 0.1, 0.1) if shape == 0 else Color(0.22, 0.2, 0.12, 0.1)   # the second has withered
	for k in 16:
		var a := TAU * k / 16.0
		mb.add(MeshBuilder.sphere(0.06, 6, 4), Transform3D(tilt * Basis.from_scale(Vector3(1, 1, 0.6)), c + tilt * Vector3(cos(a), sin(a), 0) * 0.2), green.lightened(rng.randf() * 0.1))
		if k % 3 == 0:
			mb.add(MeshBuilder.sphere(0.022, 5, 3), Transform3D(Basis(), c + tilt * (Vector3(cos(a), sin(a), 0) * 0.2 + Vector3(0, 0, 0.05))), Color(0.55, 0.06, 0.06, 0.1) if shape == 0 else Color(0.85, 0.82, 0.75, 0.1))
	var rib := Color(0.45, 0.05, 0.08, 0.3) if shape == 0 else Color(0.12, 0.1, 0.18, 0.3)
	mb.add(MeshBuilder.box(Vector3(0.12, 0.08, 0.02)), Transform3D(tilt, c + tilt * Vector3(0, -0.2, 0.05)), rib)
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(0.04, 0.2, 0.01)), Transform3D(tilt * Basis(Vector3(0, 0, 1), sd * 0.3), c + tilt * Vector3(sd * 0.04, -0.3, 0.05)), Color(rib, 0.6))
	var m := mb.commit()
	_cache[key] = m
	return m


## Withered flowers in a little stone vase (or lying loose): drooping stems and dead heads.
static func withered_flowers(shape: int) -> ArrayMesh:
	var key := "flowers_%d" % shape   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1201 + shape
	var mb := MeshBuilder.new()
	var heads := [Color(0.32, 0.12, 0.14, 0.6), Color(0.36, 0.26, 0.16, 0.6), Color(0.26, 0.14, 0.28, 0.6), Color(0.55, 0.5, 0.36, 0.6)]
	var base := Vector3.ZERO
	if shape == 0:
		mb.add(MeshBuilder.cyl(0.07, 0.05, 0.18, 8), Transform3D(Basis(), Vector3(0, 0.09, 0)), Color(0.5, 0.49, 0.46, 0.0))
		base = Vector3(0, 0.16, 0)
	for k in 7:
		var a := rng.randf() * TAU
		var top := base + Vector3(cos(a) * 0.12, rng.randf_range(0.2, 0.36), sin(a) * 0.12)
		var droop := top + Vector3(cos(a) * 0.08, -rng.randf_range(0.04, 0.12), sin(a) * 0.08)
		if shape == 1:   # a bunch lying on the grave
			top = Vector3(rng.randf_range(-0.05, 0.05), 0.02, 0.32 + rng.randf_range(-0.05, 0.05))
			droop = top + Vector3(rng.randf_range(-0.1, 0.1), 0.0, 0.08)
		mb.limb(base, top, 0.008, 0.006, Color(0.28, 0.27, 0.14, 0.4), 3)
		mb.limb(top, droop, 0.006, 0.005, Color(0.28, 0.27, 0.14, 0.6), 3)
		mb.add(MeshBuilder.sphere(0.035, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), droop), heads[k % heads.size()])
	var m := mb.commit()
	_cache[key] = m
	return m


## A crow (perched: feet at the origin, facing +Z). Vertex alpha: 1 = head (pecks in the crow
## shader), 0.5 = tail, 0 = body. Wings spread when `flying`.
static func crow(flying: bool) -> ArrayMesh:
	var key := "crow_%s" % str(flying)   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	var black := Color(0.035, 0.035, 0.045, 0.0)
	var sheen := Color(0.08, 0.08, 0.12, 0.0)
	mb.add(MeshBuilder.sphere(0.1, 8, 6), Transform3D(Basis(Vector3(1, 0, 0), -0.4 if not flying else -1.3).scaled(Vector3(0.75, 0.75, 1.4)), Vector3(0, 0.15, 0)), black)
	mb.add(MeshBuilder.sphere(0.055, 8, 6), Transform3D(Basis(), Vector3(0, 0.25 if not flying else 0.18, 0.11)), _c(sheen, 1.0))
	mb.add(MeshBuilder.cone(0.022, 0.08, 5), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.245 if not flying else 0.175, 0.19)), Color(0.02, 0.02, 0.02, 1.0))
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.sphere(0.012, 4, 3), Transform3D(Basis(), Vector3(sd * 0.03, 0.26 if not flying else 0.19, 0.145)), Color(0.5, 0.45, 0.2, 1.0))
	mb.add(MeshBuilder.box(Vector3(0.08, 0.015, 0.16)), Transform3D(Basis(Vector3(1, 0, 0), 0.5 if not flying else 0.0), Vector3(0, 0.1 if not flying else 0.15, -0.16)), _c(black, 0.5))
	if flying:
		for sd in [-1.0, 1.0]:
			mb.add(MeshBuilder.box(Vector3(0.32, 0.012, 0.13)), Transform3D(Basis(), Vector3(sd * 0.2, 0.16, 0.0)), _c(sheen, 0.75))
			mb.add(MeshBuilder.box(Vector3(0.16, 0.01, 0.09)), Transform3D(Basis(Vector3.UP, sd * 0.3), Vector3(sd * 0.42, 0.16, -0.03)), _c(black, 0.75))
	else:
		for sd in [-1.0, 1.0]:
			mb.add(MeshBuilder.sphere(0.07, 6, 4), Transform3D(Basis.from_scale(Vector3(0.35, 0.7, 1.5)), Vector3(sd * 0.065, 0.16, -0.02)), sheen)
			mb.limb(Vector3(sd * 0.025, 0.08, 0.0), Vector3(sd * 0.03, 0.0, 0.02), 0.008, 0.006, Color(0.05, 0.05, 0.05, 0.0), 3)
	var m := mb.commit(crow_material())
	_cache[key] = m
	return m


const CROW_SHADER := """
shader_type spatial;
uniform float flying = 0.0;
varying float part;
void vertex() {
	part = COLOR.a;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = fract(sin(dot(wp.xz, vec2(12.9898, 78.233))) * 43758.5453) * 40.0;
	if (flying > 0.5) {
		// wings flap (the wing parts are tagged 0.75)
		if (part > 0.6 && part < 0.9) {
			float a = sin(TIME * 9.0 + ph) * 0.7;
			float s = sign(VERTEX.x);
			float r = abs(VERTEX.x);
			VERTEX.y += r * sin(a) * 1.2;
			VERTEX.x = s * r * cos(a);
		}
	} else if (part > 0.9) {
		// now and then the head dips to peck, or turns to look about
		float t = TIME * 0.6 + ph;
		float peck = smoothstep(0.85, 0.95, fract(t)) * (1.0 - smoothstep(0.95, 1.0, fract(t)));
		float look = sin(floor(t) * 3.7) * 0.6;
		vec3 pivot = vec3(0.0, 0.2, 0.07);
		vec3 v = VERTEX - pivot;
		float c = cos(look); float s = sin(look);
		v = vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
		float pa = peck * 1.1;
		v = vec3(v.x, cos(pa) * v.y - sin(pa) * v.z, sin(pa) * v.y + cos(pa) * v.z);
		VERTEX = pivot + v;
	}
}
void fragment() {
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	ALBEDO = col;
	ROUGHNESS = 0.45;
	SPECULAR = 0.6;
}
"""

static var _crow_mat: ShaderMaterial
static var _crow_fly_mat: ShaderMaterial


static func crow_material(flying := false) -> ShaderMaterial:
	if _crow_mat == null:
		var sh := Shader.new()
		sh.code = CROW_SHADER
		_crow_mat = ShaderMaterial.new()
		_crow_mat.shader = sh
		_crow_fly_mat = ShaderMaterial.new()
		_crow_fly_mat.shader = sh
		_crow_fly_mat.set_shader_parameter("flying", 1.0)
	return _crow_fly_mat if flying else _crow_mat


## A skull with a few loose bones (scattered where the ground has given up its dead).
static func bones(shape: int) -> ArrayMesh:
	var key := "bones_%d" % shape   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3131 + shape
	var mb := MeshBuilder.new()
	var skull := Vector3(0, 0.09, 0)
	mb.add(MeshBuilder.sphere(0.1, 8, 6), Transform3D(Basis(Vector3(1, 0, 0), 0.3).scaled(Vector3(0.9, 0.9, 1.1)), skull), BONE)
	mb.add(MeshBuilder.box(Vector3(0.1, 0.04, 0.06)), Transform3D(Basis(), skull + Vector3(0, -0.07, 0.06)), BONE.darkened(0.15))
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.sphere(0.028, 5, 4), Transform3D(Basis(), skull + Vector3(sd * 0.035, 0.0, 0.09)), Color(0.05, 0.04, 0.03, 0.0))
	for k in 3 + shape:
		var a := rng.randf() * TAU
		var c := Vector3(rng.randf_range(-0.4, 0.4), 0.025, rng.randf_range(-0.4, 0.4))
		var d := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.12, 0.22)
		mb.limb(c - d, c + d, 0.018, 0.016, BONE.darkened(rng.randf() * 0.15), 5)
		mb.add(MeshBuilder.sphere(0.028, 5, 3), Transform3D(Basis(), c - d), BONE)
		mb.add(MeshBuilder.sphere(0.028, 5, 3), Transform3D(Basis(), c + d), BONE)
	var m := mb.commit()
	_cache[key] = m
	return m


# ------------------------------------------------------------------ iron fences

## A wrought-iron railing panel `length` long and `h` tall along +X from the origin: rails,
## balusters with spear tips, a stouter post with a ball finial at the start. Self-coloured
## near-black iron (the prop material).
static func fence_panel(h: float, length := 2.4) -> ArrayMesh:
	var key := "fence_%.2f_%.2f" % [h, length]   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	mb.add(MeshBuilder.box(Vector3(0.09, h + 0.12, 0.09)), Transform3D(Basis(), Vector3(0, (h + 0.12) * 0.5 - 0.1, 0)), IRON)
	mb.add(MeshBuilder.sphere(0.06, 8, 5), Transform3D(Basis(), Vector3(0, h + 0.08, 0)), IRON)
	for y in [0.1, h * 0.82, h * 0.9 if h > 1.2 else -1.0]:
		if y > 0.0:
			mb.add(MeshBuilder.box(Vector3(length, 0.035, 0.03)), Transform3D(Basis(), Vector3(length * 0.5, y, 0)), IRON)
	var n := int(length / 0.16)
	for k in range(1, n):
		var x := k * length / n
		mb.add(MeshBuilder.box(Vector3(0.018, h - 0.05, 0.018)), Transform3D(Basis(), Vector3(x, (h - 0.05) * 0.5 + 0.03, 0)), IRON)
		mb.add(MeshBuilder.cone(0.03, 0.1, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(x, h + 0.02, 0)), IRON)
		if k % 2 == 0 and h > 1.2:   # little scrolls between the rails
			mb.add(MeshBuilder.cyl(0.05, 0.05, 0.012, 8, 1), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(x - length / n * 0.5, h * 0.86, 0)), IRON)
	for k in range(2, n, 5):   # rust streaks
		mb.add(MeshBuilder.box(Vector3(0.022, h * 0.3, 0.022)), Transform3D(Basis(), Vector3(k * length / n, h * 0.2, 0)), RUST)
	var m := mb.commit()
	_cache[key] = m
	return m


## A pair of iron gates between two stone piers (front +Z), `w` wide.
static func gate(w: float, h: float, open := 0.0) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	for sd in [-1.0, 1.0]:
		var px: float = sd * (w * 0.5 + 0.3)
		mb.add(MeshBuilder.box(Vector3(0.6, h + 0.6, 0.6)), Transform3D(Basis(), Vector3(px, (h + 0.6) * 0.5 - 0.3, 0)), MASON)
		mb.add(MeshBuilder.box(Vector3(0.75, 0.15, 0.75)), Transform3D(Basis(), Vector3(px, h + 0.35, 0)), DRESSED)
		mb.add(MeshBuilder.sphere(0.22, 10, 6), Transform3D(Basis(), Vector3(px, h + 0.62, 0)), DRESSED)
		_lantern(mb, gb, Vector3(px, h - 0.6, 0.38), 1.1)
		# a gate leaf: frame, bars with spear tips, a scroll arch
		var hinge := Vector3(sd * w * 0.5, 0, 0)
		var basis := Basis(Vector3.UP, sd * open)
		var lw := w * 0.5 - 0.03
		for y in [0.15, h * 0.45, h - 0.15]:
			mb.add(MeshBuilder.box(Vector3(lw, 0.05, 0.04)), Transform3D(basis, hinge + basis * Vector3(-sd * lw * 0.5, y, 0)), IRON_M)
		var nb := int(lw / 0.14)
		for k in nb + 1:
			var x: float = -sd * k * lw / nb
			var bh := h + 0.25 * sin(PI * float(k) / nb) * (1.0 if sd < 0 else 1.0)
			mb.add(MeshBuilder.box(Vector3(0.025, bh, 0.025)), Transform3D(basis, hinge + basis * Vector3(x, bh * 0.5, 0)), IRON_M)
			mb.add(MeshBuilder.cone(0.035, 0.12, 4), Transform3D(basis * Basis(Vector3.UP, PI * 0.25), hinge + basis * Vector3(x, bh + 0.05, 0)), IRON_M)
	# the arch over the gate with a cross at its crown
	for k in 12:
		var a := PI * k / 11.0
		mb.add(MeshBuilder.box(Vector3(0.05, 0.05, 0.05)), Transform3D(Basis(), Vector3(cos(a) * w * 0.5, h + 0.5 + sin(a) * 0.9, 0)), IRON_M)
	mb.add(MeshBuilder.box(Vector3(0.04, 0.5, 0.04)), Transform3D(Basis(), Vector3(0, h + 1.65, 0)), IRON_M)
	mb.add(MeshBuilder.box(Vector3(0.3, 0.04, 0.04)), Transform3D(Basis(), Vector3(0, h + 1.72, 0)), IRON_M)
	var m := mb.commit(masonry_material())
	gb.commit_into(m, MeshBuilder.glow_material())
	return {"mesh": m}


# ------------------------------------------------------------------ crypts and mausoleums

## Crypt `kind` (0 classical mausoleum, 1 gothic crypt, 2 domed tomb, 3 barrow vault).
## Returns {mesh, colliders, door (local, front centre), light (Color), light_at, half (footprint)}.
static func crypt(kind: int, rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()   # masonry surface
	var pb := MeshBuilder.new()   # prop surface (wood, wreaths, dirt)
	var gb := MeshBuilder.new()   # glow surface (candles, lanterns)
	var d := {}
	match kind % 4:
		0: d = _mausoleum(mb, pb, gb, rng)
		1: d = _gothic_crypt(mb, pb, gb, rng)
		2: d = _domed_tomb(mb, pb, gb, rng)
		_: d = _barrow(mb, pb, gb, rng)
	var mesh := mb.commit(masonry_material())
	pb.commit_into(mesh, MeshBuilder.prop_material())
	gb.commit_into(mesh, MeshBuilder.glow_material())
	d["mesh"] = mesh
	return d


static func _box_col(size: Vector3, at: Vector3) -> Array:
	var s := BoxShape3D.new()
	s.size = size
	return [s, Transform3D(Basis(), at)]


## Carved lettering in iron-dark (masonry flag 1 reads as dark recess) across a frieze.
static func _frieze_letters(mb: MeshBuilder, w: float, y: float, z: float, rng: RandomNumberGenerator, scale := 1.0) -> void:
	var x := -w * 0.5
	while x < w * 0.5 - 0.05:
		var lw := minf(rng.randf_range(0.07, 0.12) * scale, w * 0.5 - x)
		mb.add(MeshBuilder.box(Vector3(lw * 0.75, 0.16 * scale, 0.02)), Transform3D(Basis(), Vector3(x + lw * 0.5, y, z)), IRON_M)
		x += lw + (0.14 * scale if rng.randf() < 0.2 else 0.0)


## An iron grille gate in a doorway `w` x `h` at depth z (front), bars and cross-braces.
static func _grille(mb: MeshBuilder, w: float, h: float, z: float, arch := false) -> void:
	var n := int(w / 0.13)
	for k in n + 1:
		var x := -w * 0.5 + k * w / n
		var bh := h
		if arch:
			bh = h + sqrt(maxf(0.0, pow(w * 0.5, 2.0) - x * x)) * 0.8
		mb.add(MeshBuilder.box(Vector3(0.03, bh, 0.03)), Transform3D(Basis(), Vector3(x, bh * 0.5, z)), IRON_M)
	for y in [0.2, h * 0.5, h - 0.1]:
		mb.add(MeshBuilder.box(Vector3(w, 0.05, 0.04)), Transform3D(Basis(), Vector3(0, y, z)), IRON_M)
	mb.add(MeshBuilder.cyl(0.08, 0.08, 0.02, 10), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, h * 0.5, z + 0.03)), IRON_M)


static func _mausoleum(mb: MeshBuilder, pb: MeshBuilder, gb: MeshBuilder, rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randf_range(5.0, 6.0)
	var dpt := rng.randf_range(6.5, 7.5)
	var h := rng.randf_range(3.8, 4.4)
	var porch := 2.0
	var y0 := 0.0
	# three broad steps up to the platform (sunk deep so slopes never show a gap)
	for k in 3:
		var sw := w + 1.8 - k * 0.5
		var sd := dpt + porch + 1.6 - k * 0.5
		mb.add(MeshBuilder.box(Vector3(sw, 0.28 + (2.0 if k == 0 else 0.0), sd)), Transform3D(Basis(), Vector3(0, y0 + 0.14 - (1.0 if k == 0 else 0.0), porch * 0.5 - (k * 0.25) + 0.3)), DRESSED if k % 2 else MASON)
		y0 += 0.28
	var cz := -porch * 0.5
	# the cella: coursed walls, a dressed plinth course and cornice
	mb.add(MeshBuilder.box(Vector3(w, h, dpt)), Transform3D(Basis(), Vector3(0, y0 + h * 0.5, cz)), MASON)
	mb.add(MeshBuilder.box(Vector3(w + 0.14, 0.4, dpt + 0.14)), Transform3D(Basis(), Vector3(0, y0 + 0.2, cz)), DRESSED)
	# pilasters down the sides
	for sx in [-1.0, 1.0]:
		for k in 3:
			mb.add(MeshBuilder.box(Vector3(0.12, h, 0.45)), Transform3D(Basis(), Vector3(sx * (w * 0.5 + 0.06), y0 + h * 0.5, cz - dpt * 0.35 + k * dpt * 0.35)), DRESSED)
	var front := cz + dpt * 0.5
	# the portico: four columns with bases and capitals
	var col_z := front + porch - 0.35
	for k in 4:
		var x := -w * 0.36 + k * w * 0.24
		mb.add(MeshBuilder.box(Vector3(0.62, 0.22, 0.62)), Transform3D(Basis(), Vector3(x, y0 + 0.11, col_z)), DRESSED)
		mb.add(MeshBuilder.cyl(0.22, 0.26, h - 0.5, 14), Transform3D(Basis(), Vector3(x, y0 + 0.22 + (h - 0.5) * 0.5, col_z)), DRESSED)
		for f in 8:   # flutes
			var a := TAU * f / 8.0
			mb.add(MeshBuilder.box(Vector3(0.04, h - 0.7, 0.04)), Transform3D(Basis(), Vector3(x + cos(a) * 0.235, y0 + 0.32 + (h - 0.7) * 0.5, col_z + sin(a) * 0.235)), Color(DRESSED.darkened(0.12), 0.5))
		mb.add(MeshBuilder.cyl(0.36, 0.24, 0.22, 14), Transform3D(Basis(), Vector3(x, y0 + h - 0.17, col_z)), DRESSED)
		mb.add(MeshBuilder.box(Vector3(0.66, 0.12, 0.66)), Transform3D(Basis(), Vector3(x, y0 + h - 0.0, col_z)), DRESSED)
	# entablature with a lettered frieze, the pediment and the roof
	var ent_y := y0 + h + 0.3
	mb.add(MeshBuilder.box(Vector3(w + 0.5, 0.6, dpt + porch + 0.4)), Transform3D(Basis(), Vector3(0, ent_y, cz + porch * 0.5)), DRESSED)
	mb.add(MeshBuilder.box(Vector3(w + 0.7, 0.14, dpt + porch + 0.6)), Transform3D(Basis(), Vector3(0, ent_y + 0.37, cz + porch * 0.5)), DRESSED)
	_frieze_letters(mb, w * 0.7, ent_y, front + porch + 0.21, rng, 1.6)
	var ped_h := w * 0.22
	mb.add(gable(w + 0.7, ped_h, dpt + porch + 0.6), Transform3D(Basis(), Vector3(0, ent_y + 0.44, cz + porch * 0.5)), MASON)
	mb.add(gable(w * 0.75, ped_h * 0.7, 0.05), Transform3D(Basis(), Vector3(0, ent_y + 0.55, front + porch + 0.31)), DRESSED.darkened(0.08))
	mb.add(MeshBuilder.sphere(0.3, 10, 6), Transform3D(Basis.from_scale(Vector3(1, 1, 0.3)), Vector3(0, ent_y + 0.44 + ped_h * 0.35, front + porch + 0.36)), IRON_M)
	# acroteria: urns at the corners of the pediment and an urn on the apex
	for p in [Vector3(-(w + 0.5) * 0.5, ent_y + 0.6, front + porch + 0.1), Vector3((w + 0.5) * 0.5, ent_y + 0.6, front + porch + 0.1), Vector3(0, ent_y + 0.5 + ped_h, front + porch + 0.1)]:
		mb.add(MeshBuilder.cyl(0.12, 0.16, 0.12, 10), Transform3D(Basis(), p), DRESSED)
		mb.add(MeshBuilder.sphere(0.2, 10, 6), Transform3D(Basis.from_scale(Vector3(1, 1.2, 1)), p + Vector3(0, 0.26, 0)), DRESSED)
		mb.add(MeshBuilder.cone(0.08, 0.2, 8), Transform3D(Basis(), p + Vector3(0, 0.56, 0)), DRESSED)
	# the door: a dark recess behind an iron gate, a bronze ring, a wreath hung on the gate
	mb.add(MeshBuilder.box(Vector3(1.9, 3.0, 0.3)), Transform3D(Basis(), Vector3(0, y0 + 1.5, front + 0.02)), Color(0.04, 0.035, 0.03, 1.0))
	mb.add(MeshBuilder.box(Vector3(2.3, 0.3, 0.4)), Transform3D(Basis(), Vector3(0, y0 + 3.15, front + 0.1)), DRESSED)
	for sx in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(0.22, 3.0, 0.4)), Transform3D(Basis(), Vector3(sx * 1.06, y0 + 1.5, front + 0.1)), DRESSED)
	var gm := MeshBuilder.new()
	_grille(gm, 1.8, 2.9, 0.0)
	mb.add(gm.commit().surface_get_arrays(0), Transform3D(Basis(), Vector3(0, y0, front + 0.25)), IRON_M)
	_wreath_on(pb, Vector3(0, y0 + 1.9, front + 0.32))
	# two urns of dead flowers and candles either side of the door
	for sx in [-1.0, 1.0]:
		var at := Vector3(sx * 1.6, y0, front + 0.8)
		mb.add(MeshBuilder.cyl(0.22, 0.16, 0.5, 10), Transform3D(Basis(), at + Vector3(0, 0.25, 0)), DRESSED)
		for k in 5:
			var a := TAU * k / 5.0
			pb.limb(at + Vector3(0, 0.5, 0), at + Vector3(cos(a) * 0.2, 0.75, sin(a) * 0.2), 0.012, 0.01, Color(0.3, 0.26, 0.14, 0.3), 3)
			pb.add(MeshBuilder.sphere(0.05, 5, 4), Transform3D(Basis(), at + Vector3(cos(a) * 0.22, 0.72, sin(a) * 0.22)), Color(0.32, 0.1, 0.12, 0.4))
		_candle_pair(pb, gb, Vector3(sx * 0.7, y0, front + 0.6))
	var depth_total := dpt + porch + 1.6
	return {"colliders": [_box_col(Vector3(w + 1.8, h + 4.0, depth_total), Vector3(0, (h + 4.0) * 0.5 - 1.0, porch * 0.5 + 0.3 - 0.5))],
		"door": Vector3(0, y0, front + porch), "light": Color(1.0, 0.62, 0.3), "light_at": Vector3(0, y0 + 1.2, front + 1.4),
		"half": Vector2((w + 1.8) * 0.5, depth_total * 0.5 + 0.3)}


static func _wreath_on(pb: MeshBuilder, at: Vector3) -> void:
	for k in 14:
		var a := TAU * k / 14.0
		pb.add(MeshBuilder.sphere(0.08, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 1, 0.6)), at + Vector3(cos(a), sin(a), 0) * 0.28), Color(0.1, 0.16, 0.08, 0.05))
	pb.add(MeshBuilder.box(Vector3(0.16, 0.1, 0.03)), Transform3D(Basis(), at + Vector3(0, -0.28, 0.06)), Color(0.4, 0.04, 0.06, 0.1))
	for sd in [-1.0, 1.0]:
		pb.add(MeshBuilder.box(Vector3(0.05, 0.3, 0.015)), Transform3D(Basis(Vector3(0, 0, 1), sd * 0.25), at + Vector3(sd * 0.05, -0.45, 0.06)), Color(0.4, 0.04, 0.06, 0.5))


static func _candle_pair(pb: MeshBuilder, gb: MeshBuilder, at: Vector3) -> void:
	for k in 2:
		var p := at + Vector3(k * 0.16 - 0.08, 0, (k % 2) * 0.1)
		var h := 0.25 + k * 0.12
		pb.add(MeshBuilder.cyl(0.04, 0.045, h, 8), Transform3D(Basis(), p + Vector3(0, h * 0.5, 0)), CANDLE)
		pb.add(MeshBuilder.sphere(0.05, 6, 3), Transform3D(Basis.from_scale(Vector3(1.3, 0.3, 1.3)), p), CANDLE)
		gb.add(MeshBuilder.sphere(0.03, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 2.0, 1)), p + Vector3(0, h + 0.05, 0)), FLAME)


static func _gothic_crypt(mb: MeshBuilder, pb: MeshBuilder, gb: MeshBuilder, rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randf_range(4.2, 5.0)
	var dpt := rng.randf_range(5.5, 6.5)
	var h := rng.randf_range(3.6, 4.2)
	var y0 := 0.35
	mb.add(MeshBuilder.box(Vector3(w + 0.8, 2.35, dpt + 1.6)), Transform3D(Basis(), Vector3(0, y0 - 1.175, 0.4)), MASON)
	mb.add(MeshBuilder.box(Vector3(w, h, dpt)), Transform3D(Basis(), Vector3(0, y0 + h * 0.5, 0)), MASON)
	# buttresses at the corners, stepped
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * (w * 0.5 + 0.15), y0, sz * (dpt * 0.5 - 0.2))
			mb.add(MeshBuilder.box(Vector3(0.6, h * 0.7, 0.6)), Transform3D(Basis(), p + Vector3(0, h * 0.35, 0)), MASON)
			mb.add(MeshBuilder.box(Vector3(0.45, h * 0.35, 0.45)), Transform3D(Basis(), p + Vector3(0, h * 0.85, 0)), MASON)
			mb.add(MeshBuilder.cone(0.3, 0.9, 4), Transform3D(Basis(Vector3.UP, PI * 0.25), p + Vector3(0, h * 1.02 + 0.45, 0)), DRESSED)
	# a steep slate roof between stone gables, a ridge and a cross
	var roof_h := w * 0.75
	mb.add(gable(w + 0.2, roof_h, dpt + 0.1), Transform3D(Basis(), Vector3(0, y0 + h, 0)), MASON)
	var slope := atan2(roof_h, w * 0.5)
	var slab := sqrt(roof_h * roof_h + w * w * 0.25) + 0.3
	for sx in [-1.0, 1.0]:
		var mid := Vector3(sx * w * 0.25, y0 + h + roof_h * 0.5 + 0.1, 0)
		pb.add(MeshBuilder.box(Vector3(slab, 0.14, dpt + 0.5)), Transform3D(Basis(Vector3(0, 0, 1), -sx * slope), mid + Vector3(sx * 0.07, 0.0, 0)), SLATE)
		for k in 8:   # courses of slates
			var t := (k + 0.5) / 8.0
			var p := Vector3(sx * w * 0.5 * (1.0 - t), y0 + h + roof_h * t + 0.19, 0)
			pb.add(MeshBuilder.box(Vector3(0.05, 0.02, dpt + 0.5)), Transform3D(Basis(Vector3(0, 0, 1), -sx * slope), p), SLATE.darkened(0.3))
	pb.add(MeshBuilder.box(Vector3(0.22, 0.22, dpt + 0.6)), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.25), Vector3(0, y0 + h + roof_h + 0.12, 0)), SLATE.lightened(0.05))
	var front := dpt * 0.5
	mb.add(MeshBuilder.box(Vector3(0.14, 1.1, 0.14)), Transform3D(Basis(), Vector3(0, y0 + h + roof_h + 0.6, front)), DRESSED)
	mb.add(MeshBuilder.box(Vector3(0.6, 0.14, 0.14)), Transform3D(Basis(), Vector3(0, y0 + h + roof_h + 0.85, front)), DRESSED)
	# the pointed doorway with moulded jambs, an iron gate and a rose window above
	mb.add(prism(_pointed_top(1.7, 3.0, 2.0), 0.2), Transform3D(Basis(), Vector3(0, y0, front + 0.02)), Color(0.035, 0.03, 0.03, 1.0))
	for k in 3:
		var o := 0.12 * (k + 1)
		mb.add(prism(_pointed_top(1.7 + o * 2.0, 3.0 + o, 2.0), 0.1), Transform3D(Basis(), Vector3(0, y0, front - 0.03 + 0.04 * (3 - k))), DRESSED.darkened(0.04 * k))
	mb.add(prism(_pointed_top(1.7, 3.0, 2.0), 0.24), Transform3D(Basis(), Vector3(0, y0, front + 0.0)), Color(0.035, 0.03, 0.03, 1.0))
	var gm := MeshBuilder.new()
	_grille(gm, 1.6, 2.0, 0.0, true)
	mb.add(gm.commit().surface_get_arrays(0), Transform3D(Basis(), Vector3(0, y0, front + 0.17)), IRON_M)
	var rose := Vector3(0, y0 + h + roof_h * 0.35, front + 0.06)
	mb.add(MeshBuilder.cyl(0.55, 0.55, 0.12, 16), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), rose), DRESSED)
	gb.add(MeshBuilder.cyl(0.42, 0.42, 0.13, 16), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), rose + Vector3(0, 0, 0.01)), Color(0.25, 0.55, 0.45, 0.0))
	for k in 6:
		mb.add(MeshBuilder.box(Vector3(0.05, 0.84, 0.15)), Transform3D(Basis(Vector3(0, 0, 1), PI * k / 6.0), rose + Vector3(0, 0, 0.02)), DRESSED)
	# a carved name over the door, side lancet windows (dark), steps and a candle
	_frieze_letters(mb, 1.4, y0 + 3.45, front + 0.13, rng, 0.9)
	for sx in [-1.0, 1.0]:
		for k in 2:
			mb.add(prism(_pointed_top(0.36, 1.4, 1.1), 0.08), Transform3D(Basis(Vector3.UP, sx * PI * 0.5), Vector3(sx * (w * 0.5 + 0.02), y0 + 1.3, -dpt * 0.2 + k * dpt * 0.35)), Color(0.04, 0.035, 0.03, 1.0))
	for k in 2:
		mb.add(MeshBuilder.box(Vector3(2.4 - k * 0.4, 0.18, 0.5)), Transform3D(Basis(), Vector3(0, y0 - 0.09 - k * 0.18, front + 0.45 + k * 0.4)), DRESSED)
	_candle_pair(pb, gb, Vector3(1.05, y0, front + 0.35))
	_wreath_on(pb, Vector3(0, y0 + 1.6, front + 0.25))
	return {"colliders": [_box_col(Vector3(w + 0.8, h + roof_h + 2.5, dpt + 1.2), Vector3(0, (h + roof_h + 2.5) * 0.5 - 1.0, 0.2))],
		"door": Vector3(0, y0, front + 0.5), "light": Color(0.5, 1.0, 0.75), "light_at": Vector3(0, y0 + 1.4, front + 1.4),
		"half": Vector2(w * 0.5 + 0.6, dpt * 0.5 + 1.3)}


static func _domed_tomb(mb: MeshBuilder, pb: MeshBuilder, gb: MeshBuilder, rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf_range(2.6, 3.1)
	var h := rng.randf_range(3.2, 3.8)
	var y0 := 0.45
	mb.add(MeshBuilder.cyl(r + 0.9, r + 1.1, 2.45, 8), Transform3D(Basis(Vector3.UP, PI / 8.0), Vector3(0, y0 - 1.22, 0)), DRESSED)
	mb.add(MeshBuilder.cyl(r, r, h, 8), Transform3D(Basis(Vector3.UP, PI / 8.0), Vector3(0, y0 + h * 0.5, 0)), MASON)
	# pilasters on every corner of the octagon, a cornice and the dome with ribs
	for k in 8:
		var a := TAU * k / 8.0
		mb.add(MeshBuilder.box(Vector3(0.35, h, 0.35)), Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * r * 0.95, y0 + h * 0.5, sin(a) * r * 0.95)), DRESSED)
	mb.add(MeshBuilder.cyl(r + 0.3, r + 0.2, 0.4, 16), Transform3D(Basis(), Vector3(0, y0 + h + 0.2, 0)), DRESSED)
	mb.add(MeshBuilder.sphere(r, 16, 8), Transform3D(Basis.from_scale(Vector3(1, 0.85, 1)), Vector3(0, y0 + h + 0.3, 0)), Color(0.3, 0.36, 0.32, 0.5))   # verdigris copper
	for k in 8:
		var a := TAU * k / 8.0
		for s in 5:
			var t0 := float(s) / 5.0 * PI * 0.5
			var t1 := float(s + 1) / 5.0 * PI * 0.5
			var p0 := Vector3(cos(a) * cos(t0) * r, sin(t0) * r * 0.85, sin(a) * cos(t0) * r) + Vector3(0, y0 + h + 0.3, 0)
			var p1 := Vector3(cos(a) * cos(t1) * r, sin(t1) * r * 0.85, sin(a) * cos(t1) * r) + Vector3(0, y0 + h + 0.3, 0)
			mb.limb(p0 * Vector3(1.02, 1.0, 1.02), p1 * Vector3(1.02, 1.0, 1.02), 0.07, 0.07, Color(0.24, 0.3, 0.27, 0.5), 5)
	var top := Vector3(0, y0 + h + 0.3 + r * 0.85, 0)
	mb.add(MeshBuilder.cyl(0.35, 0.4, 0.7, 8), Transform3D(Basis(), top + Vector3(0, 0.3, 0)), DRESSED)
	mb.add(MeshBuilder.cone(0.45, 0.7, 8), Transform3D(Basis(), top + Vector3(0, 0.95, 0)), Color(0.24, 0.3, 0.27, 0.5))
	mb.add(MeshBuilder.box(Vector3(0.08, 0.7, 0.08)), Transform3D(Basis(), top + Vector3(0, 1.6, 0)), IRON_M)
	mb.add(MeshBuilder.box(Vector3(0.36, 0.08, 0.08)), Transform3D(Basis(), top + Vector3(0, 1.75, 0)), IRON_M)
	# the door on the front face
	var front := r * cos(PI / 8.0)
	mb.add(prism(_round_top(1.5, 2.7, 0.75), 0.25), Transform3D(Basis(), Vector3(0, y0, front)), Color(0.035, 0.03, 0.03, 1.0))
	mb.add(prism(_round_top(1.9, 3.0, 0.95), 0.12), Transform3D(Basis(), Vector3(0, y0, front - 0.03)), DRESSED)
	mb.add(prism(_round_top(1.5, 2.7, 0.75), 0.27), Transform3D(Basis(), Vector3(0, y0, front)), Color(0.035, 0.03, 0.03, 1.0))
	var gm := MeshBuilder.new()
	_grille(gm, 1.45, 1.95, 0.0, true)
	mb.add(gm.commit().surface_get_arrays(0), Transform3D(Basis(), Vector3(0, y0, front + 0.16)), IRON_M)
	_frieze_letters(mb, 1.6, y0 + h - 0.35, front + 0.03, rng, 0.9)
	for k in 2:
		mb.add(MeshBuilder.box(Vector3(2.2, 0.2, 0.5)), Transform3D(Basis(), Vector3(0, y0 - 0.1 - k * 0.2, front + 0.5 + k * 0.45)), DRESSED)
	# a lantern hanging by the door, an angel-less empty plinth with flowers
	_lantern(pb, gb, Vector3(1.15, y0 + 2.2, front + 0.35), 1.0)
	_candle_pair(pb, gb, Vector3(-0.95, y0, front + 0.4))
	return {"colliders": [_box_col(Vector3(r * 2.0 + 1.0, h + r + 3.0, r * 2.0 + 1.0), Vector3(0, (h + r + 3.0) * 0.5 - 1.0, 0))],
		"door": Vector3(0, y0, front + 0.4), "light": Color(1.0, 0.7, 0.35), "light_at": Vector3(0, y0 + 1.5, front + 1.6),
		"half": Vector2(r + 1.0, r + 1.4)}


static func _barrow(mb: MeshBuilder, pb: MeshBuilder, gb: MeshBuilder, rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf_range(4.0, 4.8)
	# an earthen mound, grassed over, with a stone facade and a dark arched entrance
	pb.add(ForestProps._lumpy(1.0, rng), Transform3D(Basis.from_scale(Vector3(r, 2.6, r * 1.2)), Vector3(0, -0.4, -0.8)), Color(0.2, 0.19, 0.12, 0.0))
	pb.add(ForestProps._lumpy(1.0, rng), Transform3D(Basis.from_scale(Vector3(r * 0.8, 2.2, r)), Vector3(0.4, 0.2, -1.5)), Color(0.17, 0.17, 0.1, 0.0))
	var front := r * 0.95
	mb.add(MeshBuilder.box(Vector3(5.2, 3.6, 1.6)), Transform3D(Basis(), Vector3(0, 0.8, front - 0.6)), MASON)
	# retaining wings sloping down into the mound
	for sx in [-1.0, 1.0]:
		var wing := PackedVector2Array([Vector2(0, -1), Vector2(2.4 * sx, -1), Vector2(2.4 * sx, 0.4), Vector2(0, 2.4)])
		mb.add(prism(wing, 0.7), Transform3D(Basis(Vector3.UP, -sx * 0.35), Vector3(sx * 2.4, 0.0, front - 0.4)), MASON)
	mb.add(prism(_round_top(1.6, 2.4, 0.8), 0.3), Transform3D(Basis(), Vector3(0, 0.0, front + 0.21)), Color(0.035, 0.03, 0.03, 1.0))
	for k in 9:   # voussoirs round the arch
		var a := PI * k / 8.0
		mb.add(MeshBuilder.box(Vector3(0.42, 0.25, 0.3)), Transform3D(Basis(Vector3(0, 0, 1), a - PI * 0.5), Vector3(cos(a) * 1.0, 1.6 + sin(a) * 1.0, front + 0.24)), DRESSED)
	var gm := MeshBuilder.new()
	_grille(gm, 1.55, 1.6, 0.0, true)
	mb.add(gm.commit().surface_get_arrays(0), Transform3D(Basis(), Vector3(0, 0, front + 0.38)), IRON_M)
	# two squat pillars topped with carved skulls flank it
	for sx in [-1.0, 1.0]:
		var p := Vector3(sx * 1.9, 0, front + 0.6)
		mb.add(MeshBuilder.box(Vector3(0.6, 2.2, 0.6)), Transform3D(Basis(), p + Vector3(0, 0.6, 0)), DRESSED)
		mb.add(MeshBuilder.box(Vector3(0.75, 0.15, 0.75)), Transform3D(Basis(), p + Vector3(0, 1.75, 0)), DRESSED)
		mb.add(MeshBuilder.sphere(0.24, 10, 7), Transform3D(Basis.from_scale(Vector3(0.9, 1.0, 1.05)), p + Vector3(0, 2.05, 0)), DRESSED)
		mb.add(MeshBuilder.box(Vector3(0.26, 0.1, 0.12)), Transform3D(Basis(), p + Vector3(0, 1.88, 0.18)), DRESSED)
		for e in [-1.0, 1.0]:
			mb.add(MeshBuilder.sphere(0.06, 6, 4), Transform3D(Basis(), p + Vector3(e * 0.08, 2.07, 0.21)), IRON_M)
		gb.add(MeshBuilder.sphere(0.035, 6, 4), Transform3D(Basis(), p + Vector3(-0.08, 2.07, 0.24)), Color(0.4, 1.0, 0.6, 0.0))
		gb.add(MeshBuilder.sphere(0.035, 6, 4), Transform3D(Basis(), p + Vector3(0.08, 2.07, 0.24)), Color(0.4, 1.0, 0.6, 0.0))
	_frieze_letters(mb, 2.4, 2.35, front + 0.21, rng, 1.0)
	_candle_pair(pb, gb, Vector3(0.7, 0.0, front + 0.9))
	_candle_pair(pb, gb, Vector3(-0.6, 0.0, front + 1.0))
	for k in 4:   # bones scattered at the threshold
		var c := Vector3(rng.randf_range(-1.0, 1.0), 0.03, front + rng.randf_range(0.6, 1.6))
		var a := rng.randf() * TAU
		pb.limb(c - Vector3(cos(a), 0, sin(a)) * 0.15, c + Vector3(cos(a), 0, sin(a)) * 0.15, 0.02, 0.018, BONE, 5)
	return {"colliders": [_box_col(Vector3(r * 2.0, 4.0, r * 2.2), Vector3(0, 1.0, -0.8)), _box_col(Vector3(5.6, 4.0, 2.0), Vector3(0, 1.0, front - 0.4))],
		"door": Vector3(0, 0, front + 0.6), "light": Color(0.45, 1.0, 0.65), "light_at": Vector3(0, 1.2, front + 1.8),
		"half": Vector2(r + 0.6, r * 1.2 + 0.6)}


# ------------------------------------------------------------------ the ruined chapel

## The ruined chapel: a roofless nave with jagged broken walls and empty lancet windows, a
## gable front with a pointed doorway and an empty rose window, a broken apse, a tall bell tower
## with an open belfry, a bronze bell and a leaning spire, a few charred roof timbers, toppled
## pews, an altar with candles, and rubble. Front (door) toward +Z. Nave interior 9 x 20 m.
## Returns {mesh, colliders, light_at, door, belfry, half}.
static func chapel(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var pb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var cols := []
	var iw := 9.0
	var il := 20.0
	var t := 0.9
	var front := il * 0.5
	var back := -il * 0.5
	# foundations and a flagged floor
	mb.add(MeshBuilder.box(Vector3(iw + t * 2.0 + 1.0, 2.4, il + t * 2.0 + 1.0)), Transform3D(Basis(), Vector3(0, -1.05, 0)), DRESSED.darkened(0.05))
	# side walls: 1 m wide piers of rubble masonry, broken to ragged heights, with five lancet
	# windows each
	for sx in [-1.0, 1.0]:
		var x: float = sx * (iw * 0.5 + t * 0.5)
		var z := back
		var k := 0
		while z < front - 0.01:
			var seg := minf(1.0, front - z)
			var hgt := 7.5 - 4.2 * pow(absf(sin(z * 0.37 + sx * 1.3 + rng.randf() * 0.4)), 2.0) - rng.randf() * 0.8
			if sx > 0.0 and z > 2.0 and z < 7.0:
				hgt = minf(hgt, 2.0 + rng.randf() * 1.2)   # a great breach in the east wall
			var win := fmod(z - back, 4.0)
			var in_win := win > 1.4 and win < 2.6 and z < front - 1.5 and z > back + 1.0
			var cz := z + seg * 0.5
			if in_win:
				mb.add(MeshBuilder.box(Vector3(t, 1.9, seg)), Transform3D(Basis(), Vector3(x, 0.95, cz)), MASON)
				if hgt > 6.2:
					mb.add(MeshBuilder.box(Vector3(t, hgt - 6.2, seg)), Transform3D(Basis(), Vector3(x, 6.2 + (hgt - 6.2) * 0.5, cz)), MASON)
					mb.add(MeshBuilder.box(Vector3(t + 0.1, 0.22, seg)), Transform3D(Basis(), Vector3(x, 6.1, cz)), DRESSED)
				mb.add(MeshBuilder.box(Vector3(t + 0.16, 0.14, seg)), Transform3D(Basis(), Vector3(x, 1.95, cz)), DRESSED)
			else:
				mb.add(MeshBuilder.box(Vector3(t, hgt, seg)), Transform3D(Basis(), Vector3(x, hgt * 0.5, cz)), MASON)
				if absf(win) < 0.01 or absf(win - 4.0) < 0.01:   # buttress between windows
					mb.add(prism(PackedVector2Array([Vector2(0, 0), Vector2(1.2, 0), Vector2(0.5, minf(hgt, 5.0)), Vector2(0, minf(hgt, 5.0))]), 0.7), Transform3D(Basis(Vector3.UP, 0.0 if sx > 0.0 else PI), Vector3(x + sx * t * 0.5, 0, cz)), MASON)
			z += seg
			k += 1
		cols.append(_box_col(Vector3(t, 3.0, il), Vector3(x, 1.5, 0)))
	# the gable front: a pointed doorway, an empty rose window, the apex partly fallen
	for sx in [-1.0, 1.0]:
		var w2 := (iw + t * 2.0) * 0.5 - 1.3
		mb.add(MeshBuilder.box(Vector3(w2, 8.0, t)), Transform3D(Basis(), Vector3(sx * (1.3 + w2 * 0.5), 4.0, front + t * 0.5)), MASON)
		cols.append(_box_col(Vector3(w2, 3.0, t), Vector3(sx * (1.3 + w2 * 0.5), 1.5, front + t * 0.5)))
	mb.add(MeshBuilder.box(Vector3(2.6, 3.2, t)), Transform3D(Basis(), Vector3(0, 6.4, front + t * 0.5)), MASON)
	for k in 4:   # moulded arch orders round the door
		var o := 0.14 * k
		mb.add(prism(_pointed_top(2.6 + o * 2.0, 4.8 + o, 3.2), 0.12), Transform3D(Basis(), Vector3(0, 0, front + t + 0.05 + 0.02 * (4 - k))), DRESSED.darkened(0.04 * k))
	mb.add(prism(_pointed_top(2.4, 4.6, 3.0), t + 0.4), Transform3D(Basis(), Vector3(0, 0, front + t * 0.5)), Color(0.03, 0.025, 0.025, 1.0))
	var rose := Vector3(0, 9.1, front + t * 0.5)
	mb.add(gable(iw + t * 2.0, 4.0, t), Transform3D(Basis(), Vector3(0, 8.0, front + t * 0.5)), MASON)
	mb.add(MeshBuilder.cyl(1.35, 1.35, t + 0.2, 20), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), rose), DRESSED)
	mb.add(MeshBuilder.cyl(1.1, 1.1, t + 0.3, 20), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), rose), Color(0.03, 0.025, 0.025, 1.0))
	for k in 4:   # broken tracery spokes
		mb.add(MeshBuilder.box(Vector3(0.12, 2.1 - k * 0.3, t + 0.32)), Transform3D(Basis(Vector3(0, 0, 1), PI * k / 4.0 + 0.2), rose), DRESSED)
	# the apse: a broken half-round east end
	for k in 9:
		var a := PI + PI * k / 8.0
		var hgt := 6.5 - 3.5 * absf(sin(k * 1.7)) - rng.randf()
		var p := Vector3(cos(a) * (iw * 0.5 + t * 0.5), hgt * 0.5, back + sin(a) * (iw * 0.5 + t * 0.5) * 0.8)
		mb.add(MeshBuilder.box(Vector3(2.0, hgt, t)), Transform3D(Basis(Vector3.UP, -a - PI * 0.5), p), MASON)
	cols.append(_box_col(Vector3(iw + t * 2.0, 3.0, t), Vector3(0, 1.5, back - (iw * 0.5) * 0.8 + 0.3)))
	cols.append(_box_col(Vector3(t, 3.0, iw * 0.8), Vector3(-(iw * 0.5 + t * 0.4), 1.5, back - iw * 0.3)))
	cols.append(_box_col(Vector3(t, 3.0, iw * 0.8), Vector3(iw * 0.5 + t * 0.4, 1.5, back - iw * 0.3)))
	# the bell tower at the front left corner: tall, with a belfry, a bell and a leaning spire
	var tw := 4.4
	var th := 16.0
	var tp := Vector3(-(iw * 0.5 + tw * 0.5 - 0.4), 0, front + tw * 0.5 - 0.4)
	mb.add(MeshBuilder.box(Vector3(tw, th - 4.0, tw)), Transform3D(Basis(), tp + Vector3(0, (th - 4.0) * 0.5, 0)), MASON)
	for k in 3:   # string courses
		mb.add(MeshBuilder.box(Vector3(tw + 0.2, 0.25, tw + 0.2)), Transform3D(Basis(), tp + Vector3(0, 4.0 + k * 3.8, 0)), DRESSED)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.add(MeshBuilder.box(Vector3(0.9, 4.0, 0.9)), Transform3D(Basis(), tp + Vector3(sx * (tw * 0.5 - 0.45), th - 2.0, sz * (tw * 0.5 - 0.45))), MASON)
			mb.add(MeshBuilder.box(Vector3(0.7, th - 2.0, 0.7)), Transform3D(Basis(), tp + Vector3(sx * (tw * 0.5 + 0.15), (th - 2.0) * 0.5, sz * (tw * 0.5 + 0.15))), MASON)
	mb.add(MeshBuilder.box(Vector3(tw + 0.4, 0.5, tw + 0.4)), Transform3D(Basis(), tp + Vector3(0, th + 0.25, 0)), DRESSED)
	for face in 4:   # lancet slits up the shaft
		var rot := Basis(Vector3.UP, face * PI * 0.5)
		for k in 2:
			mb.add(prism(_pointed_top(0.3, 1.5, 1.2), 0.1), Transform3D(rot, tp + rot * Vector3(0, 5.0 + k * 3.6, tw * 0.5 + 0.02)), Color(0.03, 0.025, 0.025, 1.0))
	var bell := tp + Vector3(0, th - 2.4, 0)
	pb.add(MeshBuilder.box(Vector3(tw - 0.6, 0.3, 0.3)), Transform3D(Basis(), bell + Vector3(0, 1.4, 0)), DARK_WOOD)
	mb.add(MeshBuilder.cyl(0.35, 0.85, 1.3, 16), Transform3D(Basis(), bell + Vector3(0, 0.5, 0)), Color(0.3, 0.24, 0.12, 0.8))
	mb.add(MeshBuilder.sphere(0.36, 12, 6), Transform3D(Basis.from_scale(Vector3(1, 0.6, 1)), bell + Vector3(0, 1.15, 0)), Color(0.3, 0.24, 0.12, 0.8))
	mb.add(MeshBuilder.cyl(0.9, 0.9, 0.1, 16), Transform3D(Basis(), bell + Vector3(0, -0.15, 0)), Color(0.28, 0.22, 0.1, 0.8))
	# the spire: a tall pyramid, cracked and leaning, a bent iron cross on top
	var lean := Basis(Vector3(1, 0, 1).normalized(), 0.09)
	var sp := tp + Vector3(0, th + 0.5, 0)
	pb.add(MeshBuilder.cone(tw * 0.62, 7.5, 4), Transform3D(lean * Basis(Vector3.UP, PI * 0.25), sp + lean * Vector3(0, 3.75, 0)), SLATE)
	for k in 6:
		pb.add(MeshBuilder.cone(tw * 0.62 * (1.0 - k / 6.0) + 0.02, 0.06, 4), Transform3D(lean * Basis(Vector3.UP, PI * 0.25), sp + lean * Vector3(0, k * 1.2 + 0.2, 0)), SLATE.darkened(0.35))
	mb.add(MeshBuilder.box(Vector3(0.1, 1.2, 0.1)), Transform3D(lean * Basis(Vector3(0, 0, 1), 0.25), sp + lean * Vector3(0, 8.0, 0)), IRON_M)
	mb.add(MeshBuilder.box(Vector3(0.6, 0.08, 0.08)), Transform3D(lean * Basis(Vector3(0, 0, 1), 0.25), sp + lean * Vector3(0.08, 8.2, 0)), IRON_M)
	cols.append(_box_col(Vector3(tw + 1.4, th + 4.0, tw + 1.4), tp + Vector3(0, (th + 4.0) * 0.5 - 1.0, 0)))
	# charred roof timbers still spanning the nave, one end of slate roof left
	for k in 5:
		var z := back + 2.0 + k * 4.0
		if k == 2:
			continue
		var tilt := rng.randf_range(-0.05, 0.05)
		pb.add(MeshBuilder.box(Vector3(iw + t * 2.0, 0.35, 0.35)), Transform3D(Basis(Vector3(0, 0, 1), tilt), Vector3(0, 7.0, z)), DARK_WOOD)
		for sx in [-1.0, 1.0]:
			if k == 4 or (k == 0 and sx > 0):
				pb.add(MeshBuilder.box(Vector3(6.2, 0.3, 0.3)), Transform3D(Basis(Vector3(0, 0, 1), -sx * 0.62), Vector3(sx * 2.5, 8.8, z)), DARK_WOOD)
	for sx in [-1.0, 1.0]:
		pb.add(MeshBuilder.box(Vector3(6.6, 0.18, 4.5)), Transform3D(Basis(Vector3(0, 0, 1), -sx * 0.62), Vector3(sx * 2.6, 9.0, front - 2.3)), SLATE)
	# a beam fallen across the floor
	pb.add(MeshBuilder.box(Vector3(0.35, 0.35, 8.0)), Transform3D(Basis(Vector3(1, 0, 0), 0.4) * Basis(Vector3.UP, 0.5), Vector3(1.0, 1.4, 1.0)), DARK_WOOD)
	# inside: the altar on a step with candles and a cross, rows of pews (some toppled), rubble
	var alt := Vector3(0, 0, back - 1.0)
	mb.add(MeshBuilder.box(Vector3(5.0, 0.3, 3.0)), Transform3D(Basis(), alt + Vector3(0, 0.15, 0)), DRESSED)
	mb.add(MeshBuilder.box(Vector3(2.4, 1.0, 1.0)), Transform3D(Basis(), alt + Vector3(0, 0.8, 0)), DRESSED)
	mb.add(MeshBuilder.box(Vector3(2.6, 0.12, 1.15)), Transform3D(Basis(), alt + Vector3(0, 1.36, 0)), DRESSED)
	pb.add(MeshBuilder.box(Vector3(2.2, 0.02, 0.9)), Transform3D(Basis(), alt + Vector3(0, 1.43, 0)), Color(0.4, 0.06, 0.08, 0.2))
	mb.add(MeshBuilder.box(Vector3(0.1, 1.0, 0.1)), Transform3D(Basis(), alt + Vector3(0, 1.92, -0.2)), Color(0.4, 0.3, 0.12, 0.8))
	mb.add(MeshBuilder.box(Vector3(0.55, 0.1, 0.1)), Transform3D(Basis(), alt + Vector3(0, 2.15, -0.2)), Color(0.4, 0.3, 0.12, 0.8))
	for k in 7:
		var p := alt + Vector3(-1.0 + k * 0.33, 1.42, 0.25 * (k % 2))
		var h := 0.2 + 0.25 * fmod(k * 0.61, 1.0)
		pb.add(MeshBuilder.cyl(0.04, 0.045, h, 8), Transform3D(Basis(), p + Vector3(0, h * 0.5, 0)), CANDLE)
		gb.add(MeshBuilder.sphere(0.03, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 2.0, 1)), p + Vector3(0, h + 0.05, 0)), FLAME)
	cols.append(_box_col(Vector3(2.6, 1.4, 1.2), alt + Vector3(0, 0.7, 0)))
	for row in 6:
		for sx in [-1.0, 1.0]:
			var p := Vector3(sx * 2.3, 0, back + 4.0 + row * 2.2)
			if rng.randf() < 0.3:
				continue
			var toppled := rng.randf() < 0.35
			var b := Basis(Vector3.UP, rng.randf_range(-0.15, 0.15))
			if toppled:
				b = b * Basis(Vector3(1, 0, 0), PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0))
			var o := p + Vector3(0, 0.25 if toppled else 0.0, 0)
			pb.add(MeshBuilder.box(Vector3(3.2, 0.08, 0.45)), Transform3D(b, o + b * Vector3(0, 0.45, 0)), OLD_WOOD)
			pb.add(MeshBuilder.box(Vector3(3.2, 0.5, 0.06)), Transform3D(b, o + b * Vector3(0, 0.75, -0.22)), OLD_WOOD)
			for e in [-1.4, 1.4]:
				pb.add(MeshBuilder.box(Vector3(0.08, 0.95, 0.5)), Transform3D(b, o + b * Vector3(e, 0.47, 0)), DARK_WOOD)
	for k in 9:   # rubble heaps along the broken walls
		var sx := -1.0 if k % 2 == 0 else 1.0
		var p := Vector3(sx * rng.randf_range(2.8, 4.0), 0.0, rng.randf_range(back + 1.0, front - 2.0))
		if k >= 6:
			p = Vector3(sx * (iw * 0.5 + rng.randf_range(1.2, 3.0)), 0.0, rng.randf_range(back, front))
		mb.add(ForestProps._lumpy(1.0, rng), Transform3D(Basis.from_scale(Vector3(rng.randf_range(0.8, 1.6), rng.randf_range(0.3, 0.6), rng.randf_range(0.8, 1.6))), p), MASON)
		for q in 4:
			mb.add(MeshBuilder.box(Vector3(0.6, 0.35, 0.4)), Transform3D(Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU), p + Vector3(rng.randf_range(-1, 1), 0.25, rng.randf_range(-1, 1))), MASON)
	# lanterns either side of the door
	for sx in [-1.0, 1.0]:
		_lantern(pb, gb, Vector3(sx * 1.85, 2.6, front + t + 0.3), 1.3)
	var mesh := mb.commit(masonry_material())
	pb.commit_into(mesh, MeshBuilder.prop_material())
	gb.commit_into(mesh, MeshBuilder.glow_material())
	return {"mesh": mesh, "colliders": cols, "light_at": alt + Vector3(0, 2.4, 1.2), "door": Vector3(0, 0, front + t + 1.0),
		"belfry": bell, "half": Vector2(iw * 0.5 + t + tw, il * 0.5 + tw + 1.0), "tower": tp}


# ------------------------------------------------------------------ trees

## A dead, gnarled tree: a twisting trunk, crooked forking branches bare of leaves, broken stubs
## and hanging moss. Shared meshes (DEAD_SHAPES).
static func dead_tree(shape: int) -> Dictionary:
	var key := "dead_%d" % (shape % DEAD_SHAPES)   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6007 * (shape % DEAD_SHAPES + 1)
	var mb := MeshBuilder.new()
	var h := rng.randf_range(7.0, 12.0)
	var r := rng.randf_range(0.3, 0.5)
	var bark := BARK.lerp(Color(0.26, 0.25, 0.23, 0.0), rng.randf())
	var p := Vector3.ZERO
	var dir := Vector3(rng.randf_range(-0.15, 0.15), 1.0, rng.randf_range(-0.15, 0.15)).normalized()
	var segs := 6
	var rr := r
	var trunk: Array[Vector3] = [p]
	for k in segs:
		var q := p + dir * (h * 0.62 / segs)
		mb.limb(p, q, rr, rr * 0.88, ForestProps._shade(bark, rng, 0.08), 9)
		if rng.randf() < 0.4:   # knots and burls
			mb.add(MeshBuilder.sphere(rr * 0.5, 7, 5), Transform3D(Basis(), p.lerp(q, 0.5) + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rr * 0.75), bark.darkened(0.15))
		p = q
		rr *= 0.88
		dir = (dir + Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))).normalized()
		trunk.append(p)
	# root flare clawing into the ground
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf() * 0.5
		var mid := Vector3(cos(a) * r * 1.6, 0.15, sin(a) * r * 1.6)
		mb.limb(Vector3(0, 0.7, 0), mid, r * 0.5, r * 0.25, bark, 5)
		mb.limb(mid, mid + Vector3(cos(a) * r * 1.6, -0.35, sin(a) * r * 1.6), r * 0.25, r * 0.06, bark, 4)
	# branches from the upper trunk, crooked and forking
	var tips: Array[Vector3] = []
	var nb := rng.randi_range(4, 6)
	for k in nb:
		var at: Vector3 = trunk[rng.randi_range(2, trunk.size() - 1)]
		var a := TAU * k / nb + rng.randf_range(-0.5, 0.5)
		var bd := (Vector3(cos(a), rng.randf_range(0.25, 0.9), sin(a))).normalized()
		_dead_branch(mb, rng, at, bd, h * rng.randf_range(0.28, 0.42), r * 0.45, 3, bark, tips)
	_dead_branch(mb, rng, p, dir, h * 0.3, rr, 2, bark, tips)
	# a broken-off stub or two, and moss hanging in grey-green strands
	for k in 2:
		var at: Vector3 = trunk[rng.randi_range(1, 3)]
		var a := rng.randf() * TAU
		mb.limb(at, at + Vector3(cos(a), 0.3, sin(a)) * 0.6, r * 0.3, r * 0.22, bark.darkened(0.1), 6)
	for k in rng.randi_range(5, 10):
		if tips.is_empty():
			break
		var t: Vector3 = tips[rng.randi() % tips.size()]
		var top := t + Vector3(0, -0.1, 0)
		var l := rng.randf_range(0.7, 1.8)
		mb.add(MeshBuilder.box(Vector3(0.12, l * 0.5, 0.02)), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), top + Vector3(0, -l * 0.25, 0)), Color(HANGING_MOSS, 0.4))
		mb.add(MeshBuilder.box(Vector3(0.08, l * 0.5, 0.02)), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), top + Vector3(0, -l * 0.75, 0)), Color(HANGING_MOSS.darkened(0.1), 0.9))
	var mesh := mb.commit()
	var s := CylinderShape3D.new()
	s.radius = r * 0.9
	s.height = h * 0.55
	var d := {"mesh": mesh, "colliders": [[s, Transform3D(Basis(), Vector3(0, h * 0.275, 0))]], "length": 3.0}
	_cache[key] = d
	return d


static func _dead_branch(mb: MeshBuilder, rng: RandomNumberGenerator, p: Vector3, dir: Vector3, length: float, r: float, depth: int, bark: Color, tips: Array[Vector3]) -> void:
	var pts: Array[Vector3] = [p]
	var d := dir
	var q := p
	for k in 3:   # crooked: three kinked segments
		q += d * length / 3.0
		pts.append(q)
		d = (d + Vector3(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.25, 0.3), rng.randf_range(-0.45, 0.45))).normalized()
	var rr := r
	for k in 3:
		var sway := 0.05 * (4 - depth) + 0.04 * k
		mb.limb(pts[k], pts[k + 1], rr, rr * 0.75, Color(bark.r, bark.g, bark.b, sway), 5 if r > 0.05 else 4)
		rr *= 0.75
	if depth <= 1 or rr < 0.025:
		tips.append(q)
		# twiggy ends
		for k in 3:
			var td := (d + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.2, 0.6), rng.randf_range(-0.8, 0.8))).normalized()
			mb.limb(q, q + td * length * 0.3, rr, 0.006, Color(bark.r, bark.g, bark.b, 0.5), 3)
		return
	for k in rng.randi_range(2, 3):
		var at: Vector3 = pts[rng.randi_range(1, 3)]
		var nd := (d + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.1, 0.7), rng.randf_range(-0.9, 0.9))).normalized()
		_dead_branch(mb, rng, at, nd, length * rng.randf_range(0.55, 0.7), rr * 1.1, depth - 1, bark, tips)


## A weeping willow: a stout leaning trunk splitting into limbs, with long curtains of thin
## drooping branchlets hanging almost to the ground (they sway).
static func willow(shape: int) -> Dictionary:
	var key := "willow_%d" % (shape % WILLOW_SHAPES)   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8111 * (shape % WILLOW_SHAPES + 1)
	var mb := MeshBuilder.new()
	var bark := Color(0.24, 0.21, 0.17, 0.0)
	var r := 0.6
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized()
	var top := lean * 3.2
	mb.limb(Vector3.ZERO, top, r, r * 0.75, bark, 10)
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf()
		mb.limb(Vector3(0, 0.6, 0), Vector3(cos(a) * r * 2.0, -0.1, sin(a) * r * 2.0), r * 0.4, r * 0.1, bark, 5)
	var leaves := [Color(0.24, 0.28, 0.15), Color(0.3, 0.32, 0.18), Color(0.2, 0.24, 0.13)]
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var mid := top + out * rng.randf_range(1.5, 2.5) + Vector3(0, rng.randf_range(1.5, 2.5), 0)
		var tip := mid + out * rng.randf_range(1.2, 2.2) + Vector3(0, rng.randf_range(0.0, 0.8), 0)
		mb.limb(top, mid, r * 0.45, r * 0.28, bark, 7)
		mb.limb(mid, tip, r * 0.28, r * 0.12, Color(bark, 0.05), 6)
		# curtains of thin branchlets hanging from along the arch, leafy, swaying more toward the tips
		for st in 22:
			var t := rng.randf_range(0.15, 1.0)
			var at := mid.lerp(tip, t) if rng.randf() < 0.65 else top.lerp(mid, t)
			at += Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.7, 0.7))
			var hang := minf(at.y - rng.randf_range(0.5, 1.8), 6.5)
			var c: Color = leaves[rng.randi() % leaves.size()]
			var drift := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
			var prev := at
			for q in 4:
				var nxt := at + drift * float(q + 1) / 4.0 - Vector3(0, hang * float(q + 1) / 4.0, 0)
				mb.limb(prev, nxt, 0.014, 0.01, Color(c.darkened(0.25), 0.2 + 0.2 * q), 3)
				for lf in 2:   # little leaf tufts along it
					var lp := prev.lerp(nxt, 0.3 + 0.4 * lf)
					mb.add(MeshBuilder.sphere(0.09, 4, 3), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.7, 1.6, 0.25)), lp), Color(c.lightened(rng.randf() * 0.1), 0.25 + 0.2 * q))
				prev = nxt
	var mesh := mb.commit()
	var s := CylinderShape3D.new()
	s.radius = r * 0.9
	s.height = 3.0
	var d := {"mesh": mesh, "colliders": [[s, Transform3D(Basis(), Vector3(0, 1.5, 0))]], "length": 3.0}
	_cache[key] = d
	return d


# ------------------------------------------------------------------ lying props

## The graveyard's lying props (in place of the swamp's fallen logs): a closed coffin, an open
## coffin with a skeleton, a fallen dead log, a stack of coffins, a gravedigger's wheelbarrow.
static func lying(rng: RandomNumberGenerator, i: int) -> Dictionary:
	match i % 5:
		0: return _coffin(rng, false)
		1: return _coffin(rng, true)
		2: return _fallen_log(rng)
		3: return _coffin_stack(rng)
		_: return _wheelbarrow(rng)


static func _coffin_mesh(mb: MeshBuilder, at: Transform3D, open: bool, rng: RandomNumberGenerator) -> void:
	var wood := WOOD.lerp(DARK_WOOD, rng.randf())
	var body := prism(_coffin_outline(0.36, 0.26, 1.9), 0.42)
	mb.add(body, at * Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0.21, 0)), wood)
	if open:
		mb.add(prism(_coffin_outline(0.3, 0.2, 1.75), 0.05), at * Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0.42, 0)), Color(0.05, 0.035, 0.03, 0.0))
		mb.add(prism(_coffin_outline(0.37, 0.27, 1.92), 0.05), at * Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3(0, 0, 1), 0.3) * Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0.75, 0.25, 0.2)), wood.lightened(0.05))
		# a skeleton lying in state: skull, ribs, crossed arms
		mb.add(MeshBuilder.sphere(0.1, 8, 6), Transform3D(Basis(), at * Vector3(0, 0.46, 0.7)), BONE)
		for k in 4:
			mb.add(MeshBuilder.cyl(0.12 - k * 0.01, 0.12 - k * 0.01, 0.02, 10), Transform3D(at.basis * Basis(Vector3(1, 0, 0), PI * 0.5).scaled(Vector3(1, 1, 0.5)), at * Vector3(0, 0.46, 0.4 - k * 0.07)), BONE)
		for sd in [-1.0, 1.0]:
			mb.limb(at * Vector3(sd * 0.08, 0.47, 0.0), at * Vector3(sd * 0.09, 0.47, -0.75), 0.022, 0.02, BONE, 5)
			mb.limb(at * Vector3(sd * 0.15, 0.47, 0.5), at * Vector3(-sd * 0.05, 0.5, 0.2), 0.02, 0.018, BONE, 5)
	else:
		mb.add(prism(_coffin_outline(0.38, 0.28, 1.94), 0.06), at * Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0.45, 0)), wood.lightened(0.04))
		mb.add(MeshBuilder.box(Vector3(0.05, 0.02, 0.7)), at * Transform3D(Basis(), Vector3(0, 0.49, 0.1)), BRONZE)
		mb.add(MeshBuilder.box(Vector3(0.3, 0.02, 0.05)), at * Transform3D(Basis(), Vector3(0, 0.49, 0.3)), BRONZE)
	for sd in [-1.0, 1.0]:   # brass handles
		for z in [-0.5, 0.2]:
			mb.add(MeshBuilder.box(Vector3(0.03, 0.04, 0.18)), at * Transform3D(Basis(), Vector3(sd * 0.36 * (0.75 + 0.25 * (z + 0.5)), 0.22, z)), BRONZE)


static func _coffin(rng: RandomNumberGenerator, open: bool) -> Dictionary:
	var mb := MeshBuilder.new()
	_coffin_mesh(mb, Transform3D(Basis(Vector3(0, 0, 1), rng.randf_range(-0.05, 0.05)), Vector3.ZERO), open, rng)
	var s := BoxShape3D.new()
	s.size = Vector3(0.8, 0.5, 2.0)
	return {"mesh": mb.commit(), "colliders": [[s, Transform3D(Basis(), Vector3(0, 0.25, 0))]], "radius": 0.3, "length": 2.0}


static func _coffin_stack(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	_coffin_mesh(mb, Transform3D(Basis(), Vector3(-0.42, 0, 0)), false, rng)
	_coffin_mesh(mb, Transform3D(Basis(Vector3.UP, 0.06), Vector3(0.42, 0, 0.05)), false, rng)
	_coffin_mesh(mb, Transform3D(Basis(Vector3.UP, -0.1), Vector3(0.0, 0.5, -0.05)), false, rng)
	# one stood on end against the stack
	_coffin_mesh(mb, Transform3D(Basis(Vector3(1, 0, 0), -1.35), Vector3(1.2, 0.0, 0.6)), false, rng)
	var s := BoxShape3D.new()
	s.size = Vector3(1.8, 1.0, 2.0)
	return {"mesh": mb.commit(), "colliders": [[s, Transform3D(Basis(), Vector3(0, 0.5, 0))]], "radius": 0.5, "length": 2.4}


static func _fallen_log(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var length := rng.randf_range(6.0, 10.0)
	var r := rng.randf_range(0.3, 0.5)
	var a := Vector3(-length * 0.5, 0, 0)
	var b := Vector3(length * 0.5, 0, 0)
	mb.limb(a, b, r, r * 0.55, BARK, 10)
	for k in 6:   # broken limbs sticking up and out
		var t := rng.randf_range(-0.4, 0.45) * length
		var dir := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.2, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var root := Vector3(t, 0, 0) + dir * r * 0.7
		mb.limb(root, root + dir * rng.randf_range(0.8, 2.0), r * 0.25, 0.02, Color(BARK, 0.05), 4)
	mb.add(MeshBuilder.cyl(r * 0.95, r * 0.95, 0.02, 10), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), b + Vector3(0.01, 0, 0)), Color(0.36, 0.3, 0.22, 0.0))
	for k in 4:   # pale fungus brackets
		var t := rng.randf_range(-0.4, 0.4) * length
		mb.add(MeshBuilder.sphere(0.14, 8, 4), Transform3D(Basis.from_scale(Vector3(1, 0.3, 0.8)), Vector3(t, rng.randf_range(-0.1, 0.2), r * 0.95)), Color(0.7, 0.66, 0.55, 0.0))
	var s := CylinderShape3D.new()
	s.radius = r * 0.85
	s.height = length
	return {"mesh": mb.commit(), "colliders": [[s, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO)]], "radius": r, "length": length}


static func _wheelbarrow(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var tilt := Basis(Vector3(1, 0, 0), 0.12)
	# tray of planks heaped with earth, a wheel at the front, handles at the back
	mb.add(MeshBuilder.box(Vector3(0.8, 0.06, 1.1)), Transform3D(tilt, Vector3(0, 0.5, 0)), OLD_WOOD)
	for sx in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(0.05, 0.35, 1.1)), Transform3D(tilt * Basis(Vector3(0, 0, 1), sx * 0.25), Vector3(sx * 0.42, 0.66, 0)), OLD_WOOD)
		mb.limb(Vector3(sx * 0.3, 0.45, 0.5), Vector3(sx * 0.32, 0.65, -1.2), 0.03, 0.025, WOOD, 5)
		mb.limb(Vector3(sx * 0.3, 0.45, -0.5), Vector3(sx * 0.3, 0.0, -0.55), 0.03, 0.03, WOOD, 5)
	mb.add(MeshBuilder.box(Vector3(0.8, 0.35, 0.05)), Transform3D(tilt * Basis(Vector3(1, 0, 0), -0.3), Vector3(0, 0.62, 0.58)), OLD_WOOD)
	mb.add(MeshBuilder.cyl(0.25, 0.25, 0.07, 14), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 0.25, 0.75)), DARK_WOOD)
	mb.add(MeshBuilder.cyl(0.27, 0.27, 0.05, 14), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 0.25, 0.75)), IRON)
	mb.add(ForestProps._lumpy(1.0, rng), Transform3D(Basis.from_scale(Vector3(0.36, 0.2, 0.5)), Vector3(0, 0.62, 0)), DIRT)
	_shovel(mb, Vector3(0.25, 0.7, -0.1), Basis(Vector3(1, 0, 0), 1.2) * Basis(Vector3.UP, 0.3))
	# a pick lying beside it
	mb.limb(Vector3(0.9, 0.04, -0.6), Vector3(0.7, 0.04, 0.4), 0.025, 0.025, WOOD, 5)
	mb.add(MeshBuilder.box(Vector3(0.6, 0.05, 0.05)), Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.72, 0.05, 0.42)), Color(0.3, 0.3, 0.3, 0.0))
	var s := BoxShape3D.new()
	s.size = Vector3(0.9, 0.9, 2.0)
	return {"mesh": mb.commit(), "colliders": [[s, Transform3D(Basis(), Vector3(0, 0.45, 0))]], "radius": 0.4, "length": 2.0}


# ------------------------------------------------------------------ ground debris

## A tuft of dead grass: straw and grey-brown blades, some bent over.
static func dead_grass(shape: int) -> ArrayMesh:
	var key := "grass_%d" % shape   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2221 + shape
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := [Color(0.55, 0.48, 0.3, 1.0), Color(0.45, 0.41, 0.28, 1.0), Color(0.36, 0.37, 0.22, 1.0), Color(0.6, 0.55, 0.4, 1.0)]
	for k in 16:
		var a := TAU * k / 16.0 + rng.randf() * 0.5
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var h := rng.randf_range(0.14, 0.38)
		var base := out * rng.randf_range(0.0, 0.14)
		var bend := rng.randf() < 0.3
		var tip := base + out * (rng.randf_range(0.25, 0.45) if bend else rng.randf_range(0.05, 0.2)) + Vector3(0, h * (0.45 if bend else 1.0), 0)
		var base_col := Color(0.24, 0.21, 0.13, 0.0)
		var tip_col: Color = cols[k % cols.size()]
		st.set_normal(Vector3.UP)
		st.set_color(base_col)
		st.add_vertex(base - side * 0.022)
		st.set_color(base_col)
		st.add_vertex(base + side * 0.022)
		st.set_color(tip_col)
		st.add_vertex(tip)
	var m := st.commit()
	m.surface_set_material(0, MeshBuilder.foliage_material())
	_cache[key] = m
	return m


## A scatter of fallen leaves lying flat (oak-brown, rust, ochre, a few dark red).
static func leaves(shape: int) -> ArrayMesh:
	var key := "leaves_%d" % shape   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3301 + shape
	var mb := MeshBuilder.new()
	var cols := [Color(0.36, 0.2, 0.08, 0.0), Color(0.42, 0.26, 0.08, 0.0), Color(0.3, 0.16, 0.08, 0.0), Color(0.4, 0.1, 0.06, 0.0), Color(0.45, 0.36, 0.14, 0.0)]
	for k in 14:
		var p := Vector3(rng.randf_range(-0.5, 0.5), 0.015 + k * 0.001, rng.randf_range(-0.5, 0.5))
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.25, 0.25))
		mb.add(MeshBuilder.sphere(0.05, 6, 3), Transform3D(b.scaled(Vector3(0.7, 0.08, 1.2)), p), cols[rng.randi() % cols.size()])
	var m := mb.commit(MeshBuilder.foliage_material())
	_cache[key] = m
	return m


## A few pebbles and a broken stone chip half sunk in the turf.
static func pebbles(shape: int) -> ArrayMesh:
	var key := "pebbles_%d" % shape   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4401 + shape
	var mb := MeshBuilder.new()
	for k in 5:
		var s := rng.randf_range(0.025, 0.06)
		mb.add(MeshBuilder.sphere(s, 6, 4), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.2, 0.6, 0.9)), Vector3(rng.randf_range(-0.4, 0.4), s * 0.2, rng.randf_range(-0.4, 0.4))), Color(0.42, 0.41, 0.38, 0.0).darkened(rng.randf() * 0.3))
	var m := mb.commit()
	_cache[key] = m
	return m


## Pale toadstools in a clump (they grow round the dead trees).
static func toadstools(shape: int) -> ArrayMesh:
	var key := "toads_%d" % shape   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5501 + shape
	var mb := MeshBuilder.new()
	for k in 5:
		var p := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var h := rng.randf_range(0.06, 0.18)
		mb.limb(p, p + Vector3(0, h, 0), 0.015, 0.012, Color(0.75, 0.72, 0.62, 0.0), 5)
		mb.add(MeshBuilder.sphere(rng.randf_range(0.04, 0.08), 8, 4), Transform3D(Basis.from_scale(Vector3(1, 0.45, 1)), p + Vector3(0, h, 0)), Color(0.62, 0.58, 0.48, 0.0) if shape == 0 else Color(0.45, 0.38, 0.3, 0.0))
	var m := mb.commit()
	_cache[key] = m
	return m


# ------------------------------------------------------------------ the cemetery wall

## A section of the boundary wall: a stone plinth wall with a coping, `len` long along +X.
static func wall_section(length: float, h: float) -> ArrayMesh:
	var key := "wall_%.1f_%.1f" % [length, h]   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	var deep := 6.0
	mb.add(MeshBuilder.box(Vector3(length, h + deep, 0.7)), Transform3D(Basis(), Vector3(length * 0.5, (h - deep) * 0.5, 0)), MASON)
	mb.add(MeshBuilder.box(Vector3(length, 0.16, 0.86)), Transform3D(Basis(), Vector3(length * 0.5, h + 0.08, 0)), DRESSED)
	var m := mb.commit(masonry_material())
	_cache[key] = m
	return m


## A stone pier for the boundary wall, capped with a ball finial (every few metres).
static func wall_pier(h: float, urn := false) -> ArrayMesh:
	var key := "pier_%.1f_%s" % [h, str(urn)]   # no-i18n
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	var deep := 6.0
	mb.add(MeshBuilder.box(Vector3(0.8, h + deep, 0.8)), Transform3D(Basis(), Vector3(0, (h - deep) * 0.5, 0)), MASON)
	mb.add(MeshBuilder.box(Vector3(0.95, 0.18, 0.95)), Transform3D(Basis(), Vector3(0, h + 0.09, 0)), DRESSED)
	if urn:
		mb.add(MeshBuilder.cyl(0.14, 0.2, 0.15, 10), Transform3D(Basis(), Vector3(0, h + 0.25, 0)), DRESSED)
		mb.add(MeshBuilder.sphere(0.25, 10, 6), Transform3D(Basis.from_scale(Vector3(1, 1.2, 1)), Vector3(0, h + 0.55, 0)), DRESSED)
		mb.add(MeshBuilder.cone(0.1, 0.25, 8), Transform3D(Basis(), Vector3(0, h + 0.92, 0)), DRESSED)
	else:
		mb.add(MeshBuilder.sphere(0.26, 10, 6), Transform3D(Basis(), Vector3(0, h + 0.42, 0)), DRESSED)
	var m := mb.commit(masonry_material())
	_cache[key] = m
	return m
