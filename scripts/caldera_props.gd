class_name CalderaProps
extends RefCounted
## Procedural Ashen Caldera props. Builders return { "mesh": ArrayMesh, "colliders": [[Shape3D,
## Transform3D], ...] } with the origin at the base, like DesertProps.
##
## Rock is drawn with ROCK_SHADER; a part's vertex alpha says what it's made of:
##   ROCK (0)      basalt / scoria: grainy, pitted with gas vesicles, ash dusted on the tops
##   HOT (0.12)    rock with a network of glowing lava cracks that pulse
##   GLOW (0.28)   molten / burning (coals, embers, lava dribbles): emissive in its own colour
##   GLASS (0.5)   obsidian: black volcanic glass, mirror-glossy with an oily iridescent sheen
##   SULPHUR (0.75) waxy yellow crystal, faintly lit
##   IRON (1.0)    the dwarves' iron: dark, rusty, half metallic
## Charred trees and logs use MeshBuilder's prop material (they burn, sway a little).

const BASALT := Color(0.14, 0.13, 0.13)
const SCORIA := Color(0.24, 0.12, 0.09)
const ASHEN := Color(0.4, 0.38, 0.36)
const BONE := Color(0.82, 0.78, 0.68)
const CHAR := Color(0.07, 0.06, 0.055)
const SULPHUR_YELLOW := Color(0.92, 0.8, 0.2)
const IRON_COL := Color(0.24, 0.22, 0.21)
const DWARF_STONE := Color(0.32, 0.29, 0.27)
const ROCK := 0.0
const HOT := 0.12
const GLOW := 0.28
const GLASS := 0.5
const SULPHUR := 0.75
const IRON := 1.0

const ROCK_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float dim = 1.0;
uniform vec3 ash_col : source_color = vec3(0.42, 0.4, 0.38);
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { return noise(p) * 0.5 + noise(p * 2.1 + 3.3) * 0.27 + noise(p * 4.3 + 7.1) * 0.15 + noise(p * 8.7) * 0.08; }
float cracks(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	float d1 = 8.0; float d2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 r = o + vec3(hash(i + o), hash(i + o + 11.1), hash(i + o + 23.7)) - f;
				float dd = dot(r, r);
				if (dd < d1) { d2 = d1; d1 = dd; } else if (dd < d2) { d2 = dd; }
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float tag = COLOR.a;
	float n = fbm(wpos * 0.9);
	float fine = noise(wpos * 7.0);
	float up = smoothstep(0.45, 0.9, wnrm.y);
	vec3 em = vec3(0.0);
	float rough = 0.92;
	float spec = 0.3;
	float metal = 0.0;
	if (tag < 0.2) {
		// basalt: grain, gas vesicles, streaks, ash dusting on the tops
		col *= 0.72 + 0.5 * n;
		col *= 0.88 + 0.2 * fine;
		float pore = smoothstep(0.78, 0.86, noise(wpos * 13.0));
		col *= 1.0 - pore * 0.55;
		float vert = 1.0 - abs(wnrm.y);
		col *= 1.0 - smoothstep(0.6, 0.85, noise(vec3(wpos.x * 3.0, wpos.y * 0.3, wpos.z * 3.0))) * vert * 0.25;
		float ash = up * smoothstep(0.35, 0.7, noise(wpos * 1.1) * 0.8 + fine * 0.25);
		col = mix(col, ash_col * (0.8 + 0.3 * fine), ash * 0.7);
		if (tag > 0.06) {   // hot rock: glowing cracks
			float c = cracks(wpos * 1.5);
			float crack = 1.0 - smoothstep(0.0, 0.07, c);
			float pulse = 0.7 + 0.3 * sin(TIME * 1.7 + n * 9.0);
			col = mix(col, vec3(0.03, 0.01, 0.0), crack * 0.9);
			em = vec3(1.0, 0.33, 0.05) * crack * 2.8 * pulse * dim * (1.0 - ash * 0.8);
			em += vec3(1.0, 0.3, 0.05) * (1.0 - smoothstep(0.0, 0.2, c)) * 0.25 * dim;
		}
	} else if (tag < 0.4) {
		// molten / burning: lit in its own colour, flickering
		float fl = 0.8 + 0.2 * sin(TIME * 5.0 + wpos.x * 3.0 + wpos.z * 2.0) * noise(wpos * 3.0 + TIME);
		em = col * 3.2 * fl * dim;
		col *= 0.35;
		rough = 0.6;
	} else if (tag < 0.62) {
		// obsidian: black glass, conchoidal ripples, oily sheen at grazing angles
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		float rip = sin(dot(wpos, vec3(3.1, 4.7, 2.3)) * 2.0 + n * 6.0) * 0.5 + 0.5;
		col = vec3(0.012, 0.01, 0.016) + col * 0.15 + vec3(0.02) * rip;
		vec3 irid = 0.5 + 0.5 * cos(6.2831 * (fres * 1.3 + n * 0.4 + vec3(0.0, 0.33, 0.67)));
		em = irid * fres * 0.22 + vec3(1.0, 0.35, 0.1) * fres * 0.15 * dim;
		rough = 0.06 + 0.1 * fine;
		spec = 0.9;
	} else if (tag < 0.88) {
		// sulphur crystal: waxy yellow, brighter on the faces' edges
		col *= 0.8 + 0.3 * n;
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		em = col * (0.12 + fres * 0.35);
		rough = 0.4;
		spec = 0.55;
	} else {
		// iron: dark, rust in patches
		col *= 0.75 + 0.4 * n;
		float rust = smoothstep(0.55, 0.75, noise(wpos * 2.3) * 0.7 + fine * 0.3);
		col = mix(col, vec3(0.34, 0.15, 0.06) * (0.7 + 0.5 * fine), rust * 0.75);
		metal = mix(0.65, 0.1, rust);
		rough = mix(0.45, 0.9, rust);
		spec = 0.5;
	}
	ALBEDO = col;
	EMISSION = em;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
}
"""

static var _rock_mat: ShaderMaterial
static var _cache := {}


static func rock_material() -> ShaderMaterial:
	if _rock_mat == null:
		var sh := Shader.new()
		sh.code = ROCK_SHADER
		_rock_mat = ShaderMaterial.new()
		_rock_mat.shader = sh
	return _rock_mat


static func _c(c: Color, tag := ROCK) -> Color:
	return Color(c.r, c.g, c.b, tag)


static func _shade(c: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	var f := 1.0 + rng.randf_range(-amount, amount)
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), c.a)


static func _done(mb: MeshBuilder, colliders: Array, extra := {}) -> Dictionary:
	var d := {"mesh": mb.commit(rock_material()), "colliders": colliders}
	d.merge(extra)
	return d


static func _cached(key: String, rng: RandomNumberGenerator, shapes: int, make: Callable) -> Dictionary:
	var k := "%s_%d" % [key, rng.randi() % shapes]
	if not _cache.has(k):
		var r2 := RandomNumberGenerator.new()
		r2.seed = hash(k)
		_cache[k] = make.call(r2)
	return _cache[k]


static func clear_cache() -> void:
	_cache.clear()


static func _lumpy(r: float, rng: RandomNumberGenerator) -> Array:
	return ForestProps._lumpy(r, rng)


## One hexagonal basalt column from `base` up `h` metres: six faces, a chamfered top, the odd
## band where it cracked as it cooled, a little ash on top.
static func hex_column(mb: MeshBuilder, base: Vector3, r: float, h: float, rot: float, rng: RandomNumberGenerator, cap := true, tag := ROCK) -> void:
	var col := _c(_shade(BASALT, rng, 0.18), tag)
	var b := Basis(Vector3.UP, rot)
	mb.add(MeshBuilder.cyl(r, r * 1.02, h - 0.08, 6), Transform3D(b, base + Vector3(0, (h - 0.08) * 0.5, 0)), col)
	if cap:
		mb.add(MeshBuilder.cyl(r * 0.86, r, 0.08, 6), Transform3D(b, base + Vector3(0, h - 0.04, 0)), _c(col.lightened(0.08), tag))
	if h > 1.6 and rng.randf() < 0.6:   # a cooling joint: a thin dark band across the column
		mb.add(MeshBuilder.cyl(r * 1.015, r * 1.015, 0.05, 6), Transform3D(b, base + Vector3(0, h * rng.randf_range(0.3, 0.7), 0)), _c(BASALT.darkened(0.6)))


# ------------------------------------------------------------------ standing props

## A tree burnt to charcoal: a twisted black trunk, snapped branches and stubs, grey ash flaking.
static func charred_tree(rng: RandomNumberGenerator) -> Dictionary:
	return _cached("charred", rng, 5, func(r: RandomNumberGenerator) -> Dictionary:
		var mb := MeshBuilder.new()
		var h := r.randf_range(6.0, 10.5)
		var lean := Vector3(r.randf_range(-0.6, 0.6), 0, r.randf_range(-0.6, 0.6))
		var pts: Array[Vector3] = []
		for k in 6:
			var t := k / 5.0
			pts.append(Vector3(sin(t * 3.0 + r.randf()) * 0.25, t * h, cos(t * 2.0) * 0.2) + lean * t * t)
		var rad := r.randf_range(0.36, 0.55)
		for k in pts.size() - 1:
			var t := float(k) / 5.0
			var c := _shade(CHAR, r, 0.2) if k % 2 == 0 else _shade(CHAR.lightened(0.08), r, 0.2)
			c.a = 0.08 * t
			mb.limb(pts[k], pts[k + 1], rad * (1.0 - t * 0.7), rad * (1.0 - (t + 0.2) * 0.7), c, 7)
		# bark split into charcoal blocks: grey ash in the cracks
		for k in 10:
			var t := r.randf_range(0.05, 0.6)
			var a := r.randf() * TAU
			var at: Vector3 = pts[0].lerp(pts[3], t / 0.6)
			mb.add(MeshBuilder.box(Vector3(0.05, 0.4, 0.04)), Transform3D(Basis(Vector3.UP, a), at + Vector3(cos(a), 0, sin(a)) * rad * (1.0 - t * 0.6)), Color(0.35, 0.33, 0.31, 0.0))
		# branches, broken off short, some forked
		for k in r.randi_range(4, 7):
			var t := r.randf_range(0.35, 0.92)
			var from: Vector3 = pts[int(t * 4.99)].lerp(pts[mini(int(t * 4.99) + 1, 5)], fmod(t * 4.99, 1.0))
			var a := r.randf() * TAU
			var len := r.randf_range(0.8, 2.4) * (1.0 - t * 0.4)
			var to := from + Vector3(cos(a) * len, r.randf_range(0.2, 0.9) * len, sin(a) * len)
			mb.limb(from, to, rad * 0.35, 0.03, Color(CHAR.r, CHAR.g, CHAR.b, 0.3), 5)
			if r.randf() < 0.5:
				mb.limb(to, to + Vector3(cos(a + 0.8) * 0.6, 0.5, sin(a + 0.8) * 0.6), 0.04, 0.015, Color(CHAR.r, CHAR.g, CHAR.b, 0.4), 4)
		# a jagged snapped top
		for k in 3:
			var a := TAU * k / 3.0 + r.randf()
			mb.add(MeshBuilder.cone(0.08, 0.5, 4), Transform3D(Basis(Vector3(cos(a), 0, sin(a)), 0.3), pts[5] + Vector3(cos(a) * 0.06, 0.2, sin(a) * 0.06)), Color(0.05, 0.045, 0.04, 0.3))
		# roots clawing the ash
		for k in 5:
			var a := TAU * k / 5.0 + r.randf()
			mb.limb(Vector3(0, 0.3, 0), Vector3(cos(a) * 1.3, -0.15, sin(a) * 1.3), rad * 0.6, 0.05, Color(0.06, 0.05, 0.05, 0.0), 5)
		return {"mesh": mb.commit(), "colliders": [DesertProps._cyl_col(rad, h * 0.8)], "length": 2.0})


## A tree turned to stone: grey-brown bark ridges, a broken top, crystals in the cracks.
static func petrified_tree(rng: RandomNumberGenerator) -> Dictionary:
	return _cached("petrified", rng, 3, func(r: RandomNumberGenerator) -> Dictionary:
		var mb := MeshBuilder.new()
		var h := r.randf_range(2.4, 4.5)
		var rad := r.randf_range(0.45, 0.7)
		var stone := Color(0.38, 0.32, 0.28)
		mb.add(MeshBuilder.cyl(rad * 0.85, rad * 1.15, h, 10), Transform3D(Basis(Vector3(1, 0, 0), r.randf_range(-0.08, 0.08)), Vector3(0, h * 0.5, 0)), _c(stone))
		for k in 14:   # bark ridges
			var a := TAU * k / 14.0
			mb.add(MeshBuilder.box(Vector3(0.09, h * r.randf_range(0.7, 0.98), 0.08)), Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * rad, h * 0.45, sin(a) * rad)), _c(_shade(stone.darkened(0.15), r, 0.15)))
		# the broken top: jagged stumps of stone, a ring of growth rings showing
		mb.add(MeshBuilder.cyl(rad * 0.8, rad * 0.86, 0.06, 12), Transform3D(Basis(), Vector3(0, h + 0.02, 0)), _c(Color(0.55, 0.42, 0.3)))
		for k in 4:
			var a := TAU * k / 4.0 + r.randf()
			mb.add(MeshBuilder.cone(rad * 0.35, r.randf_range(0.4, 1.0), 4), Transform3D(Basis(), Vector3(cos(a) * rad * 0.5, h + 0.3, sin(a) * rad * 0.5)), _c(stone))
		for k in 3:   # a few amber-yellow crystals in the splits
			var a := r.randf() * TAU
			mb.add(MeshBuilder.cone(0.06, 0.25, 5), Transform3D(Basis(Vector3(cos(a), 0, sin(a)), 1.2), Vector3(cos(a) * rad, r.randf_range(0.5, h - 0.5), sin(a) * rad)), _c(SULPHUR_YELLOW, SULPHUR))
		for k in 4:   # root buttresses turned to rock
			var a := TAU * k / 4.0 + r.randf()
			mb.limb(Vector3(cos(a) * rad * 0.6, 0.6, sin(a) * rad * 0.6), Vector3(cos(a) * rad * 2.2, -0.1, sin(a) * rad * 2.2), 0.22, 0.08, _c(stone.darkened(0.08)), 6)
		return _done(mb, [DesertProps._cyl_col(rad, h)], {"length": 2.0}))


## A small cluster of hexagonal basalt columns, broken off at different heights.
static func column_cluster(rng: RandomNumberGenerator) -> Dictionary:
	return _cached("colcluster", rng, 5, func(r: RandomNumberGenerator) -> Dictionary:
		var mb := MeshBuilder.new()
		var cols: Array = []
		var n := r.randi_range(4, 8)
		var cr := r.randf_range(0.42, 0.55)
		var pts := _hex_pack(n, cr * 1.74)
		for k in n:
			var p: Vector2 = pts[k]
			var h := r.randf_range(1.6, 5.2)
			hex_column(mb, Vector3(p.x, -0.3, p.y), cr, h + 0.3, 0.0, r)
			if k < 3:
				cols.append(DesertProps._cyl_col(cr, h, Vector3(p.x, 0, p.y)))
		# a broken drum lying at its foot
		var a := r.randf() * TAU
		var lie := Basis(Vector3(cos(a), 0, sin(a)), PI / 2)
		mb.add(MeshBuilder.cyl(cr, cr, r.randf_range(0.8, 1.5), 6), Transform3D(lie, Vector3(-sin(a), 0, cos(a)) * 2.2 + Vector3(0, cr * 0.8, 0)), _c(_shade(BASALT, r, 0.1)))
		return _done(mb, cols, {"length": 2.4}))


## Points in a hexagonal packing round the origin, `d` apart, nearest first.
static func _hex_pack(n: int, d: float) -> Array:
	var out: Array = [Vector2.ZERO]
	var ring := 1
	while out.size() < n:
		for side in 6:
			var a0 := TAU * side / 6.0
			var a1 := TAU * (side + 1) / 6.0
			for k in ring:
				var p := Vector2(cos(a0), sin(a0)).lerp(Vector2(cos(a1), sin(a1)), float(k) / ring) * d * ring
				out.append(p)
		ring += 1
	out.resize(n)
	return out


## Jagged blades of black obsidian glass, leaning out of a scree of glassy chips.
static func obsidian_shard(rng: RandomNumberGenerator) -> Dictionary:
	return _cached("shard", rng, 5, func(r: RandomNumberGenerator) -> Dictionary:
		var mb := MeshBuilder.new()
		var top := 0.0
		for k in r.randi_range(2, 4):
			var h := r.randf_range(2.6, 6.0) * (1.0 if k == 0 else 0.6)
			top = maxf(top, h)
			var a := r.randf() * TAU
			var tilt := Basis(Vector3(cos(a), 0, sin(a)), r.randf_range(0.05, 0.35)) * Basis(Vector3.UP, r.randf() * TAU)
			var w := r.randf_range(0.35, 0.6)
			mb.add(MeshBuilder.cyl(0.0, w, h, r.randi_range(4, 5)), Transform3D(tilt.scaled(Vector3(1.0, 1.0, r.randf_range(0.35, 0.6))), Vector3(cos(a) * 0.3 * k, h * 0.5 - 0.1, sin(a) * 0.3 * k)), _c(Color(0.05, 0.05, 0.07), GLASS))
		for k in 10:
			var a := r.randf() * TAU
			var d := r.randf_range(0.5, 1.6)
			mb.add(MeshBuilder.cone(r.randf_range(0.08, 0.18), r.randf_range(0.1, 0.3), 4), Transform3D(Basis(Vector3(cos(a), 0, sin(a)), r.randf_range(0.4, 1.4)), Vector3(cos(a) * d, 0.04, sin(a) * d)), _c(Color(0.05, 0.05, 0.07), GLASS))
		return _done(mb, [DesertProps._cyl_col(0.45, top)], {"length": 2.0}))


## A heap of scoria boulders: red-black and frothy, the biggest still cracked and glowing inside.
static func scoria_boulders(rng: RandomNumberGenerator) -> Dictionary:
	return _cached("scoria", rng, 6, func(r: RandomNumberGenerator) -> Dictionary:
		var mb := MeshBuilder.new()
		var big := r.randf_range(1.3, 2.4)
		var cols: Array = []
		for k in r.randi_range(3, 6):
			var rr := big * (1.0 if k == 0 else r.randf_range(0.3, 0.7))
			var a := r.randf() * TAU
			var d := 0.0 if k == 0 else big * r.randf_range(0.8, 1.4)
			var at := Vector3(cos(a) * d, rr * 0.5, sin(a) * d)
			var col := _shade(SCORIA if k % 2 == 0 else BASALT, r, 0.15)
			col.a = HOT if (k == 0 and r.randf() < 0.75) or r.randf() < 0.2 else ROCK
			mb.add(_lumpy(rr, r), Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1.0, r.randf_range(0.6, 0.85), r.randf_range(0.8, 1.1))), at), col)
			if k < 2:
				var s := SphereShape3D.new()
				s.radius = rr * 0.8
				cols.append([s, Transform3D(Basis(), at)])
		return _done(mb, cols, {"length": big * 2.0}))


## A sulphur vent: a low crusted mound, yellow round a dark throat, crystals growing on the rim.
static func sulphur_vent(rng: RandomNumberGenerator) -> Dictionary:
	return _cached("vent", rng, 4, func(r: RandomNumberGenerator) -> Dictionary:
		var mb := MeshBuilder.new()
		var rr := r.randf_range(1.0, 1.5)
		mb.add(_lumpy(rr * 1.4, r), Transform3D(Basis.from_scale(Vector3(1.0, 0.32, 1.0)), Vector3(0, 0.1, 0)), _c(Color(0.3, 0.26, 0.18)))
		mb.add(MeshBuilder.cyl(rr * 0.7, rr * 0.95, 0.35, 12), Transform3D(Basis(), Vector3(0, 0.4, 0)), _c(Color(0.75, 0.65, 0.2), SULPHUR))
		mb.add(MeshBuilder.cyl(rr * 0.35, rr * 0.45, 0.4, 10), Transform3D(Basis(), Vector3(0, 0.45, 0)), _c(Color(0.02, 0.015, 0.01)))
		for k in 12:
			var a := r.randf() * TAU
			var d := rr * r.randf_range(0.5, 0.95)
			mb.add(MeshBuilder.cyl(0.0, r.randf_range(0.05, 0.11), r.randf_range(0.18, 0.5), 5), Transform3D(Basis(Vector3(cos(a), 0, sin(a)), r.randf_range(-0.5, 0.5)), Vector3(cos(a) * d, 0.6, sin(a) * d)), _c(SULPHUR_YELLOW, SULPHUR))
		return _done(mb, [DesertProps._cyl_col(rr * 0.9, 0.6)], {"length": 2.0}))


## A hornito: a chimney of spattered lava, lumps stacked and welded, glowing at the mouth with
## dribbles of molten rock down its sides.
static func hornito(rng: RandomNumberGenerator) -> Dictionary:
	return _cached("hornito", rng, 4, func(r: RandomNumberGenerator) -> Dictionary:
		var mb := MeshBuilder.new()
		var h := r.randf_range(2.6, 4.4)
		var y := 0.0
		var n := 6
		for k in n:
			var t := float(k) / n
			var rr := lerpf(1.3, 0.55, t)
			var col := _shade(SCORIA if k % 2 else BASALT, r, 0.2)
			col.a = HOT if k > n - 3 else ROCK
			mb.add(_lumpy(rr, r), Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1.0, 0.55, 1.0)), Vector3(r.randf_range(-0.1, 0.1), y + rr * 0.3, r.randf_range(-0.1, 0.1))), col)
			y += h / n
		mb.add(MeshBuilder.cyl(0.42, 0.3, 0.2, 10), Transform3D(Basis(), Vector3(0, y + 0.15, 0)), _c(Color(1.0, 0.45, 0.1), GLOW))
		for k in 3:   # molten dribbles
			var a := r.randf() * TAU
			mb.limb(Vector3(cos(a) * 0.5, y, sin(a) * 0.5), Vector3(cos(a) * 0.9, y * 0.45, sin(a) * 0.9), 0.07, 0.03, _c(Color(1.0, 0.4, 0.08), GLOW), 4)
		return _done(mb, [DesertProps._cyl_col(0.9, h)], {"length": 2.4}))


# ------------------------------------------------------------------ lying props

## Basalt columns toppled in a fan, broken into drums.
static func fallen_columns(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var cr := rng.randf_range(0.45, 0.6)
	var length := 0.0
	var cols: Array = []
	for k in rng.randi_range(2, 4):
		var a := rng.randf_range(-0.35, 0.35)
		var x := 0.0
		var off := Vector3(0, cr * 0.85, (k - 1.5) * cr * 1.9)
		for d in rng.randi_range(2, 4):
			var dl := rng.randf_range(0.9, 1.8)
			var bs := Basis(Vector3.UP, a) * Basis(Vector3(0, 0, 1), PI / 2) * Basis(Vector3.UP, rng.randf() * 0.2)
			mb.add(MeshBuilder.cyl(cr, cr, dl, 6), Transform3D(bs, off + Basis(Vector3.UP, a) * Vector3(x + dl * 0.5, 0, 0)), _c(_shade(BASALT, rng, 0.15)))
			x += dl + rng.randf_range(0.05, 0.3)
		length = maxf(length, x)
	cols.append(DesertProps._box_col(Vector3(length, cr * 1.7, cr * 6.0), Vector3(length * 0.5, cr * 0.85, 0)))
	var data := _done(mb, cols, {"length": length, "sink": 0.25})
	return DesertProps._recentre(data, Vector3(-length * 0.5, 0, 0))


## A burnt-out log: charcoal split into blocks, ash grey in the cracks, broken branch stubs.
static func charred_log(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var length := rng.randf_range(4.0, 7.0)
	var r := rng.randf_range(0.3, 0.45)
	mb.add(MeshBuilder.cyl(r * 0.85, r, length, 10), Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(0, r * 0.8, 0)), Color(CHAR.r, CHAR.g, CHAR.b, 0.0))
	for k in 16:
		var x := rng.randf_range(-length * 0.45, length * 0.45)
		var a := rng.randf() * TAU
		mb.add(MeshBuilder.box(Vector3(0.35, 0.04, 0.05)), Transform3D(Basis(Vector3(1, 0, 0), a), Vector3(x, r * 0.8 + cos(a) * r, sin(a) * r)), Color(0.33, 0.31, 0.29, 0.0))
	for k in 3:
		var x := rng.randf_range(-length * 0.4, length * 0.4)
		var a := rng.randf_range(-1.2, 1.2)
		mb.limb(Vector3(x, r, 0), Vector3(x + 0.3, r + 0.9 * cos(a), sin(a) * 0.9), r * 0.3, 0.04, Color(0.06, 0.05, 0.05, 0.1), 5)
	return {"mesh": mb.commit(), "colliders": [DesertProps._box_col(Vector3(length, r * 1.6, r * 1.8), Vector3(0, r * 0.8, 0))], "length": length, "sink": 0.12}


## A lobe of cooled pahoehoe: a flattened blob with ropy folds and a crack still glowing.
static func lava_lobe(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var length := rng.randf_range(3.0, 5.0)
	mb.add(_lumpy(length * 0.5, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.18, 0.62)), Vector3(0, 0.15, 0)), _c(_shade(BASALT.lightened(0.05), rng, 0.1)))
	for k in 6:   # ropy folds: arcs across the lobe
		var x := -length * 0.35 + k * length * 0.12
		mb.add(MeshBuilder.cyl(length * 0.27 * (1.0 - absf(x) / length), length * 0.27 * (1.0 - absf(x) / length), 0.08, 14), Transform3D(Basis(Vector3(0, 0, 1), PI / 2).scaled(Vector3(1.0, 1.0, 0.45)), Vector3(x, 0.32, 0)), _c(BASALT.darkened(0.3)))
	mb.add(MeshBuilder.box(Vector3(length * 0.6, 0.05, 0.08)), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), Vector3(0, 0.43, 0)), _c(Color(1.0, 0.4, 0.08), GLOW))
	return _done(mb, [DesertProps._box_col(Vector3(length * 0.9, 0.6, length * 0.55), Vector3(0, 0.25, 0))], {"length": length, "sink": 0.1})


## Bones of something enormous: a great curved rib, a vertebra, a broken horn, ash drifted over.
static func beast_bones(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var b := _c(_shade(BONE, rng, 0.08))
	var pts: Array[Vector3] = []
	for k in 9:
		var t := k / 8.0
		pts.append(Vector3(-1.8 + t * 3.6, sin(t * PI) * 1.6, sin(t * 2.0) * 0.3))
	for k in pts.size() - 1:
		mb.limb(pts[k], pts[k + 1], 0.16 - k * 0.01, 0.15 - k * 0.01, b, 7)
	mb.add(_lumpy(0.45, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 0.8)), Vector3(2.2, 0.25, 0.8)), b)   # a vertebra
	for sd in [-1.0, 1.0]:
		mb.limb(Vector3(2.2, 0.3, 0.8), Vector3(2.2 + sd * 0.7, 0.5, 0.8), 0.1, 0.05, b, 5)
	mb.limb(Vector3(2.2, 0.4, 0.8), Vector3(2.3, 1.1, 0.8), 0.1, 0.04, b, 5)
	mb.limb(Vector3(-1.5, 0.15, -0.9), Vector3(-0.3, 0.5, -1.4), 0.2, 0.03, _c(Color(0.3, 0.27, 0.24)), 7)   # a horn
	return _done(mb, [], {"length": 4.4, "sink": 0.1})


## Wreckage of the dwarves' forges: a broken anvil, a great hammer head, a cog, chain.
static func forge_debris(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var iron := _c(IRON_COL, IRON)
	mb.add(MeshBuilder.box(Vector3(1.2, 0.5, 0.7)), Transform3D(Basis(Vector3(0, 0, 1), 0.35), Vector3(0, 0.3, 0)), iron)   # anvil body, tipped
	mb.add(MeshBuilder.cyl(0.0, 0.3, 0.8, 8), Transform3D(Basis(Vector3(0, 0, 1), PI / 2 + 0.35), Vector3(0.8, 0.55, 0)), iron)
	mb.add(MeshBuilder.box(Vector3(0.7, 0.45, 0.45)), Transform3D(Basis(Vector3.UP, 0.7), Vector3(-1.1, 0.22, 0.9)), iron)   # hammer head
	mb.limb(Vector3(-1.1, 0.22, 0.9), Vector3(-0.1, 0.1, 1.9), 0.06, 0.06, Color(0.12, 0.08, 0.05, ROCK), 6)   # its haft, charred
	var cog := Vector3(1.0, 0.12, -1.0)
	mb.add(MeshBuilder.cyl(0.6, 0.6, 0.15, 16), Transform3D(Basis(Vector3(1, 0, 0), 0.08), cog), iron)
	for k in 10:
		var a := TAU * k / 10.0
		mb.add(MeshBuilder.box(Vector3(0.18, 0.15, 0.2)), Transform3D(Basis(Vector3.UP, -a), cog + Vector3(cos(a) * 0.68, 0, sin(a) * 0.68)), iron)
	for k in 7:   # chain links in a curve
		var t := k / 6.0
		var at := Vector3(-0.5 + t * 1.8, 0.06, -1.6 + sin(t * 3.0) * 0.4)
		mb.add(MeshBuilder.cyl(0.1, 0.1, 0.04, 8), Transform3D(Basis(Vector3(1, 0, 0), PI / 2 * (k % 2)) * Basis(Vector3.UP, t), at), iron)
	return _done(mb, [DesertProps._box_col(Vector3(2.0, 0.8, 1.0), Vector3(0, 0.4, 0))], {"length": 3.4, "sink": 0.08})


## A volcanic bomb: a spindle of rock twisted as it flew, half buried, cracked and still warm.
static func lava_bomb_rock(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var s := rng.randf_range(0.9, 1.5)
	var col := _shade(SCORIA, rng, 0.15)
	col.a = HOT
	mb.add(_lumpy(1.0 * s, rng), Transform3D(Basis(Vector3(0, 0, 1), rng.randf_range(-0.2, 0.2)).scaled(Vector3(1.6, 0.8, 0.85)), Vector3(0, 0.45 * s, 0)), col)
	for sd in [-1.0, 1.0]:   # the twisted tails
		mb.add(MeshBuilder.cone(0.35 * s, 0.9 * s, 6), Transform3D(Basis(Vector3(0, 0, 1), -sd * PI / 2) * Basis(Vector3.UP, 0.8), Vector3(sd * 1.9 * s, 0.45 * s, 0)), _c(SCORIA.darkened(0.2)))
	# a crater of splashed ash round it
	mb.add(MeshBuilder.cyl(2.2 * s, 2.6 * s, 0.12, 14), Transform3D(Basis(), Vector3(0, 0.02, 0)), _c(ASHEN.darkened(0.3)))
	return _done(mb, [DesertProps._box_col(Vector3(3.0, 1.2, 1.5) * s, Vector3(0, 0.5 * s, 0))], {"length": 3.6 * s, "sink": 0.25})


# ------------------------------------------------------------------ landmarks

## Landmarks, in turn: a basalt column field (a staircase you can climb), obsidian spires,
## chained braziers, a fumarole field, a sulphur crystal cluster and the bones of a huge beast.
## Each returns its mesh, colliders, "kind", and "fx": particle / light nodes in local space.
static func landmark(rng: RandomNumberGenerator, i: int, night: bool) -> Dictionary:
	match i % 6:
		0: return column_field(rng)
		1: return obsidian_spires(rng)
		2: return brazier_shrine(rng, night)
		3: return fumarole_field(rng, night)
		4: return sulphur_crystals(rng)
	return beast_skeleton(rng)


## A field of hexagonal basalt columns, packed like a honeycomb, their tops climbing in steps
## (about 0.45 m each) from knee height to 5 m: jump from top to top up to the summit.
static func column_field(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var cols: Array = []
	var cr := 0.72
	var n := 37
	var pts := _hex_pack(n, cr * 1.73)
	var dir := Vector2(1, 0).rotated(rng.randf() * TAU)
	var tops: Array[Vector3] = []
	var hi := 0.0
	for k in n:
		var p: Vector2 = pts[k]
		var along := p.dot(dir) / (cr * 1.73 * 3.5)   # -1..1 across the field
		var h := clampf(snappedf(lerpf(0.45, 5.4, (along + 1.0) * 0.5) + rng.randf_range(-0.2, 0.2), 0.45), 0.45, 5.85)
		if rng.randf() < 0.1:
			h = maxf(0.45, h - 1.35)   # a broken one
		hex_column(mb, Vector3(p.x, -0.6, p.y), cr * 0.985, h + 0.6, 0.0, rng)
		cols.append(DesertProps._cyl_col(cr * 0.96, h, Vector3(p.x, 0, p.y)))
		tops.append(Vector3(p.x, h, p.y))
		hi = maxf(hi, h)
	# loose columns and drums round the field
	for k in 6:
		var a := rng.randf() * TAU
		var d := rng.randf_range(6.5, 8.5)
		var bs := Basis(Vector3(cos(a), 0, sin(a)), PI / 2 + rng.randf_range(-0.2, 0.2))
		mb.add(MeshBuilder.cyl(cr, cr, rng.randf_range(1.0, 2.6), 6), Transform3D(bs, Vector3(-sin(a) * d, cr * 0.85, cos(a) * d)), _c(_shade(BASALT, rng, 0.15)))
	return _done(mb, cols, {"kind": "columns", "tops": tops, "height": hi})


## Spires of obsidian: towering blades of black glass leaning out of a scree of glassy chips.
static func obsidian_spires(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var cols: Array = []
	var glass := _c(Color(0.05, 0.05, 0.07), GLASS)
	for k in rng.randi_range(4, 6):
		var h := rng.randf_range(6.0, 14.0) * (1.0 if k == 0 else 0.7)
		var a := TAU * k / 5.0 + rng.randf_range(-0.4, 0.4)
		var d := 0.0 if k == 0 else rng.randf_range(1.6, 3.2)
		var at := Vector3(cos(a) * d, 0, sin(a) * d)
		var w := rng.randf_range(0.9, 1.6) * (1.0 if k == 0 else 0.75)
		var tilt := Basis(Vector3(-sin(a), 0, cos(a)), rng.randf_range(0.04, 0.18) * (0.0 if k == 0 else 1.0)) * Basis(Vector3.UP, rng.randf() * TAU)
		# stacked tapering facets, slightly twisted: a fractured glass blade
		var segs := 4
		for s in segs:
			var t0 := float(s) / segs
			var t1 := float(s + 1) / segs
			var r0 := w * (1.0 - t0 * 0.85)
			var r1 := w * (1.0 - t1 * 0.85) if s < segs - 1 else 0.0
			mb.add(MeshBuilder.cyl(r1, r0, h / segs, 5), Transform3D(tilt * Basis(Vector3.UP, s * 0.22).scaled(Vector3(1.0, 1.0, 0.55)), at + tilt * Vector3(0, h * (t0 + t1) * 0.5, 0)), glass)
		cols.append(DesertProps._cyl_col(w * 0.7, h * 0.8, at))
	mb.add(_lumpy(4.0, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.2, 1.0)), Vector3(0, 0.1, 0)), _c(BASALT))
	for k in 30:
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.5, 5.0)
		mb.add(MeshBuilder.cone(rng.randf_range(0.1, 0.3), rng.randf_range(0.2, 0.6), 4), Transform3D(Basis(Vector3(cos(a), 0, sin(a)), rng.randf_range(0.3, 1.3)), Vector3(cos(a) * d, 0.2, sin(a) * d)), glass)
	return _done(mb, cols, {"kind": "spires"})


## Chained braziers: two basalt pillars carved with dwarven runes and an iron crossbeam, two
## iron braziers hanging from it on chains, burning, and a third standing between them.
static func brazier_shrine(rng: RandomNumberGenerator, night: bool) -> Dictionary:
	var mb := MeshBuilder.new()
	var cols: Array = []
	var iron := _c(IRON_COL, IRON)
	var h := 5.4
	var fx: Array = []
	for sd in [-1.0, 1.0]:
		var at := Vector3(sd * 3.0, 0, 0)
		mb.add(MeshBuilder.box(Vector3(1.4, 0.6, 1.4)), Transform3D(Basis(), at + Vector3(0, 0.3, 0)), _c(DWARF_STONE))
		mb.add(MeshBuilder.cyl(0.5, 0.55, h, 8), Transform3D(Basis(), at + Vector3(0, 0.6 + h * 0.5, 0)), _c(_shade(DWARF_STONE, rng, 0.06)))
		for k in 4:   # glowing runes up the pillar
			mb.add(MeshBuilder.box(Vector3(0.18, 0.28, 0.04)), Transform3D(Basis(), at + Vector3(0, 1.4 + k * 0.85, 0.53)), _c(Color(1.0, 0.5, 0.15), GLOW))
			mb.add(MeshBuilder.box(Vector3(0.04, 0.2, 0.18)), Transform3D(Basis(), at + Vector3(sd * 0.53, 1.6 + k * 0.85, 0)), _c(Color(1.0, 0.5, 0.15), GLOW))
		mb.add(MeshBuilder.box(Vector3(1.2, 0.5, 1.2)), Transform3D(Basis(), at + Vector3(0, h + 0.85, 0)), _c(DWARF_STONE.darkened(0.1)))
		cols.append(DesertProps._box_col(Vector3(1.3, h + 1.1, 1.3), at + Vector3(0, (h + 1.1) * 0.5, 0)))
	mb.add(MeshBuilder.box(Vector3(7.4, 0.35, 0.4)), Transform3D(Basis(), Vector3(0, h + 1.25, 0)), iron)   # the crossbeam
	for sd in [-1.0, 1.0]:
		var hang := Vector3(sd * 1.2, h + 1.05, 0)
		var bowl := hang + Vector3(0, -2.6, 0)
		for k in 9:   # the chain
			var at := hang.lerp(bowl + Vector3(0, 0.4, 0), (k + 0.5) / 9.0)
			mb.add(MeshBuilder.cyl(0.07, 0.07, 0.03, 8), Transform3D(Basis(Vector3(1, 0, 0), PI / 2) * Basis(Vector3(0, 0, 1), (k % 2) * PI / 2), at), iron)
		for k in 3:   # three short chains to the bowl's rim
			var a := TAU * k / 3.0
			mb.limb(bowl + Vector3(0, 0.45, 0), bowl + Vector3(cos(a) * 0.5, 0.05, sin(a) * 0.5), 0.02, 0.02, iron, 4)
		mb.add(MeshBuilder.cyl(0.55, 0.3, 0.45, 12), Transform3D(Basis(), bowl), iron)
		mb.add(MeshBuilder.sphere(0.45, 10, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.35, 1.0)), bowl + Vector3(0, 0.2, 0)), _c(Color(1.0, 0.45, 0.1), GLOW))
		var fl := Abilities._flame_particles(0.7, 0.8, 28)
		fl.position = bowl + Vector3(0, 0.45, 0)
		fx.append(fl)
	# the standing brazier on its tripod
	for k in 3:
		var a := TAU * k / 3.0
		mb.limb(Vector3(cos(a) * 0.55, 0, sin(a) * 0.55 + 1.5), Vector3(cos(a) * 0.25, 1.1, sin(a) * 0.25 + 1.5), 0.05, 0.04, iron, 5)
	mb.add(MeshBuilder.cyl(0.6, 0.35, 0.4, 12), Transform3D(Basis(), Vector3(0, 1.25, 1.5)), iron)
	mb.add(MeshBuilder.sphere(0.5, 10, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.35, 1.0)), Vector3(0, 1.42, 1.5)), _c(Color(1.0, 0.45, 0.1), GLOW))
	var fl2 := Abilities._flame_particles(0.8, 0.85, 30)
	fl2.position = Vector3(0, 1.7, 1.5)
	fx.append(fl2)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.22)
	l.light_energy = 2.6 if night else 1.8
	l.omni_range = 13.0
	l.shadow_enabled = false
	l.position = Vector3(0, 3.0, 0.6)
	fx.append(l)
	cols.append(DesertProps._cyl_col(0.5, 1.4, Vector3(0, 0, 1.5)))
	return _done(mb, cols, {"kind": "braziers", "fx": fx})


## A fumarole field: crusted vents in cracked ground, yellow with sulphur, steam pouring up.
static func fumarole_field(rng: RandomNumberGenerator, night: bool) -> Dictionary:
	var mb := MeshBuilder.new()
	var cols: Array = []
	var fx: Array = []
	mb.add(_lumpy(6.0, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.08, 0.9)), Vector3(0, -0.1, 0)), _c(Color(0.28, 0.24, 0.17)))
	for k in rng.randi_range(4, 6):
		var a := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
		var d := 0.0 if k == 0 else rng.randf_range(2.4, 4.8)
		var at := Vector3(cos(a) * d, 0, sin(a) * d)
		var rr := rng.randf_range(0.8, 1.4) * (1.3 if k == 0 else 1.0)
		var hh := rng.randf_range(0.6, 1.6) * (1.6 if k == 0 else 1.0)
		mb.add(MeshBuilder.cyl(rr * 0.45, rr * 1.2, hh, 10), Transform3D(Basis(Vector3.UP, rng.randf()), at + Vector3(0, hh * 0.5, 0)), _c(_shade(Color(0.36, 0.3, 0.2), rng, 0.1)))
		mb.add(MeshBuilder.cyl(rr * 0.5, rr * 0.55, 0.12, 10), Transform3D(Basis(), at + Vector3(0, hh, 0)), _c(Color(0.85, 0.72, 0.2), SULPHUR))
		mb.add(MeshBuilder.cyl(rr * 0.28, rr * 0.3, 0.14, 10), Transform3D(Basis(), at + Vector3(0, hh + 0.02, 0)), _c(Color(0.02, 0.015, 0.01)))
		for c in 8:
			var ca := rng.randf() * TAU
			mb.add(MeshBuilder.cyl(0.0, rng.randf_range(0.05, 0.1), rng.randf_range(0.2, 0.45), 5), Transform3D(Basis(Vector3(cos(ca), 0, sin(ca)), rng.randf_range(-0.6, 0.6)), at + Vector3(cos(ca) * rr * 0.6, hh, sin(ca) * rr * 0.6)), _c(SULPHUR_YELLOW, SULPHUR))
		fx.append(steam(at + Vector3(0, hh + 0.1, 0), rr * 0.7, 26 if k == 0 else 16, night))
		cols.append(DesertProps._cyl_col(rr * 0.8, hh, at))
	for k in 8:   # hot cracks between them
		var a := rng.randf() * TAU
		mb.add(MeshBuilder.box(Vector3(rng.randf_range(1.5, 3.5), 0.04, 0.1)), Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 2.5, 0.12, sin(a) * 2.5)), _c(Color(1.0, 0.4, 0.08), GLOW))
	return _done(mb, cols, {"kind": "fumaroles", "fx": fx})


## A cluster of great sulphur crystals bursting out of a cracked rock: yellow prisms 2-5 m long.
static func sulphur_crystals(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var cols: Array = []
	mb.add(_lumpy(2.6, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.45, 0.9)), Vector3(0, 0.4, 0)), _c(BASALT.lightened(0.05)))
	for k in rng.randi_range(9, 14):
		var a := rng.randf() * TAU
		var tilt := rng.randf_range(0.0, 0.9) if k > 0 else 0.05
		var len := rng.randf_range(1.6, 3.8) * (1.4 if k == 0 else 1.0)
		var w := rng.randf_range(0.25, 0.5) * (1.4 if k == 0 else 1.0)
		var bs := Basis(Vector3(-sin(a), 0, cos(a)), tilt) * Basis(Vector3.UP, rng.randf() * TAU)
		var base := Vector3(cos(a) * 0.6, 0.6, sin(a) * 0.6)
		var c := _shade(SULPHUR_YELLOW, rng, 0.12)
		c.a = SULPHUR
		mb.add(MeshBuilder.cyl(w, w, len, 6), Transform3D(bs, base + bs * Vector3(0, len * 0.5, 0)), c)
		mb.add(MeshBuilder.cyl(0.0, w, w * 1.4, 6), Transform3D(bs, base + bs * Vector3(0, len + w * 0.7, 0)), _c(c.lightened(0.12), SULPHUR))
		if k < 3:
			cols.append(DesertProps._cyl_col(w + 0.3, len * cos(tilt), base * Vector3(1, 0, 1)))
	cols.append(DesertProps._cyl_col(2.0, 1.0))
	return _done(mb, cols, {"kind": "sulphur"})


## The bones of some enormous beast: a ribcage arching 8 m high along a spine half sunk in the
## ash, a horned skull as big as a cart, a clawed foreleg.
static func beast_skeleton(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var cols: Array = []
	var b := _c(_shade(BONE, rng, 0.06))
	var spine: Array[Vector3] = []
	for k in 14:
		var t := k / 13.0
		spine.append(Vector3(0, 1.4 + sin(t * PI) * 1.6 - t * 0.8, -6.0 + t * 12.0))
	for k in spine.size():
		mb.add(_lumpy(0.45, rng), Transform3D(Basis.from_scale(Vector3(0.9, 0.8, 0.7)), spine[k]), b)
		mb.limb(spine[k], spine[k] + Vector3(0, 0.8, -0.2), 0.12, 0.04, b, 5)   # dorsal process
		if k > 0:
			mb.limb(spine[k - 1], spine[k], 0.22, 0.22, b, 6)
	# ribs: tall arches either side
	for k in range(2, 10):
		var sp := spine[k]
		var tall := 5.5 * sin(float(k - 1) / 9.0 * PI) + 1.0
		for sd in [-1.0, 1.0]:
			var prev := sp
			for s in 7:
				var t := (s + 1) / 7.0
				var p := sp + Vector3(sd * sin(t * PI * 0.75) * (2.2 + tall * 0.35), -sp.y * t * 1.02 + sin(t * PI) * tall * 0.25, t * 0.6)
				mb.limb(prev, p, 0.15 - t * 0.06, 0.15 - t * 0.07, b, 5)
				prev = p
		if k % 3 == 0:
			for sd in [-1.0, 1.0]:
				cols.append(DesertProps._cyl_col(0.35, 3.0, Vector3(sd * (2.2 + tall * 0.35), 0, sp.z)))
	# the skull: a long snout, brow ridges, empty orbits, swept-back horns, a dropped jaw
	var sk := spine[0] + Vector3(0, -0.6, -2.4)
	mb.add(_lumpy(1.2, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.7)), sk), b)
	mb.add(_lumpy(0.8, rng), Transform3D(Basis.from_scale(Vector3(0.8, 0.55, 1.6)), sk + Vector3(0, -0.2, -1.6)), b)
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.sphere(0.32, 8, 5), Transform3D(Basis(), sk + Vector3(sd * 0.7, 0.35, -0.6)), _c(Color(0.04, 0.03, 0.03)))
		var h0 := sk + Vector3(sd * 0.7, 0.6, 0.4)
		var h1 := h0 + Vector3(sd * 1.2, 1.4, 1.2)
		var h2 := h1 + Vector3(sd * 0.3, -0.2, 1.6)
		mb.limb(h0, h1, 0.32, 0.2, _c(Color(0.3, 0.26, 0.22)), 7)
		mb.limb(h1, h2, 0.2, 0.02, _c(Color(0.24, 0.2, 0.17)), 7)
		for t in 5:   # teeth
			mb.add(MeshBuilder.cone(0.07, 0.3, 4), Transform3D(Basis(Vector3(1, 0, 0), PI), sk + Vector3(sd * 0.45, -0.7, -1.2 - t * 0.35)), b)
	mb.add(_lumpy(0.6, rng), Transform3D(Basis(Vector3(1, 0, 0), 0.5).scaled(Vector3(0.9, 0.35, 2.4)), sk + Vector3(0.3, -1.2, -1.0)), b)   # the jaw
	cols.append(DesertProps._box_col(Vector3(2.4, 2.0, 4.0), sk))
	# a foreleg, claws dug into the ash
	var sh := spine[3] + Vector3(2.0, -1.0, 0)
	mb.limb(sh, sh + Vector3(1.4, -0.8, -1.0), 0.3, 0.22, b, 6)
	mb.limb(sh + Vector3(1.4, -0.8, -1.0), sh + Vector3(1.8, -1.0, -2.6), 0.22, 0.16, b, 6)
	for t in 4:
		mb.limb(sh + Vector3(1.8, -1.0, -2.6), sh + Vector3(1.4 + t * 0.3, -1.1, -3.4), 0.08, 0.02, b, 4)
	return _done(mb, cols, {"kind": "bones"})


## A dwarven brazier post: a squat stone pillar banded in bronze, runes glowing, an iron bowl of
## coals on top. Broken ones have lost their top.
static func brazier_post(rng: RandomNumberGenerator, broken: bool) -> Dictionary:
	var mb := MeshBuilder.new()
	var st := _shade(DWARF_STONE, rng, 0.08)
	mb.add(MeshBuilder.box(Vector3(1.0, 0.4, 1.0)), Transform3D(Basis(), Vector3(0, 0.2, 0)), _c(st.darkened(0.15)))
	var h := 1.1 if broken else 2.2
	mb.add(MeshBuilder.cyl(0.32, 0.38, h, 8), Transform3D(Basis(), Vector3(0, 0.4 + h * 0.5, 0)), _c(st))
	mb.add(MeshBuilder.cyl(0.42, 0.42, 0.12, 8), Transform3D(Basis(), Vector3(0, 0.9, 0)), _c(Color(0.5, 0.34, 0.16), IRON))
	mb.add(MeshBuilder.box(Vector3(0.14, 0.22, 0.04)), Transform3D(Basis(), Vector3(0, 1.3, 0.35)), _c(Color(1.0, 0.5, 0.15), GLOW))
	if broken:
		for k in 3:   # its top lies in pieces at its foot
			var a := rng.randf() * TAU
			mb.add(MeshBuilder.cyl(0.32, 0.34, rng.randf_range(0.3, 0.6), 8), Transform3D(Basis(Vector3(cos(a), 0, sin(a)), PI / 2), Vector3(cos(a) * 1.0, 0.3, sin(a) * 1.0)), _c(st))
	else:
		mb.add(MeshBuilder.cyl(0.5, 0.5, 0.15, 8), Transform3D(Basis(), Vector3(0, 2.65, 0)), _c(st.darkened(0.1)))
		var iron := _c(IRON_COL, IRON)
		mb.add(MeshBuilder.cyl(0.48, 0.28, 0.32, 12), Transform3D(Basis(), Vector3(0, 2.85, 0)), iron)
		mb.add(MeshBuilder.sphere(0.4, 10, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.35, 1.0)), Vector3(0, 2.98, 0)), _c(Color(1.0, 0.45, 0.1), GLOW))
	return {"mesh": mb.commit(rock_material()), "colliders": [DesertProps._cyl_col(0.45, h + 0.4)], "broken": broken}


# ------------------------------------------------------------------ set pieces

## The ruined forge-temple of the dwarves: a flagged floor, massive walls in squared basalt
## broken to jagged tops, squat octagonal columns (some fallen), glowing runes, a great hearth of
## glowing coals under a hood and chimney with bellows beside it, a quenching channel of lava,
## two hanging braziers, stout dwarf statues at the door, and in the middle the GIANT ANVIL with
## a hammer leaning on it. Local +Z faces the door. Returns a node with its own bodies and fx.
static func forge_temple(rng: RandomNumberGenerator, night: bool) -> Node3D:
	var root := Node3D.new()
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	body.name = "ForgeTempleBody"   # no-i18n
	root.add_child(body)
	var hx := CalderaBuilder.FORGE_HALF.x
	var hz := CalderaBuilder.FORGE_HALF.y
	var stone := DWARF_STONE
	var col := func(size: Vector3, at: Vector3, b := Basis()) -> void:
		body.add_child(DesertProps._shape_node(DesertProps._box_col(size, at, b)))
	# the floor: big square flags, every one its own shade, some cracked with glowing seams
	var fx := -hx
	while fx < hx - 0.01:
		var fz := -hz
		while fz < hz - 0.01:
			var c := _shade(stone.darkened(0.15), rng, 0.12)
			if rng.randf() < 0.12:
				c.a = HOT
			if rng.randf() > 0.05:
				mb.add(MeshBuilder.box(Vector3(1.95, 0.2, 1.95)), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)), Vector3(fx + 1.0, -0.06 + rng.randf_range(-0.03, 0.02), fz + 1.0)), c)
			fz += 2.0
		fx += 2.0
	# walls: courses of squared blocks, the tops broken away in jagged steps; a doorway in front
	var wall := func(a: Vector2, b: Vector2, h: float, door: bool) -> void:
		var len := a.distance_to(b)
		var dir := (b - a) / len
		var yaw := atan2(dir.y, dir.x)
		var course := 0
		var bh := 0.8
		var y := 0.0
		while y < h:
			var x := -0.6 if course % 2 else 0.0
			while x < len:
				var bl := rng.randf_range(1.2, 1.9)
				var x1 := minf(x + bl, len)
				var mid := (x + x1) * 0.5
				var broken_top := h * (0.45 + 0.55 * absf(sin(mid * 0.37 + a.x)))
				var in_door := door and absf(mid - len * 0.5) < 2.6 and y < 5.0
				if y < broken_top and not in_door and x1 > 0.0:
					var p := a + dir * maxf(mid, 0.3)
					var c := _shade(stone, rng, 0.1)
					mb.add(MeshBuilder.box(Vector3(maxf(x1 - maxf(x, 0.0), 0.3) - 0.06, bh - 0.06, 1.3 + rng.randf_range(-0.05, 0.05))), Transform3D(Basis(Vector3.UP, -yaw), Vector3(p.x, y + bh * 0.5, p.y)), c)
				x = x1
			y += bh
			course += 1
		var mid2 := (a + b) * 0.5
		if door:
			for sd in [-1.0, 1.0]:
				var seg_c: Vector2 = a + dir * (len * 0.5 + sd * (len * 0.25 + 1.3))
				col.call(Vector3(len * 0.5 - 2.6, h, 1.3), Vector3(seg_c.x, h * 0.5, seg_c.y), Basis(Vector3.UP, -yaw))
		else:
			col.call(Vector3(len, h * 0.7, 1.3), Vector3(mid2.x, h * 0.35, mid2.y), Basis(Vector3.UP, -yaw))
	wall.call(Vector2(-hx, -hz), Vector2(hx, -hz), 8.5, false)        # back
	wall.call(Vector2(-hx, -hz), Vector2(-hx, hz), 6.0, false)         # sides
	wall.call(Vector2(hx, -hz), Vector2(hx, hz * 0.2), 5.0, false)     # (a breach in the east wall)
	wall.call(Vector2(-hx, hz), Vector2(hx, hz), 6.5, true)            # front, with the door
	# the doorway: massive jambs carved with runes and a broken lintel slab
	for sd in [-1.0, 1.0]:
		var jx: float = sd * 2.9
		mb.add(MeshBuilder.box(Vector3(1.2, 6.0, 1.8)), Transform3D(Basis(), Vector3(jx, 3.0, hz)), _c(stone.darkened(0.08)))
		for k in 5:
			mb.add(MeshBuilder.box(Vector3(0.5, 0.34, 0.05)), Transform3D(Basis(), Vector3(jx, 1.0 + k * 0.95, hz + 0.92)), _c(Color(1.0, 0.5, 0.15), GLOW))
		col.call(Vector3(1.2, 6.0, 1.8), Vector3(jx, 3.0, hz))
	mb.add(MeshBuilder.box(Vector3(4.2, 1.0, 2.0)), Transform3D(Basis(Vector3(0, 0, 1), 0.12), Vector3(-0.4, 6.4, hz)), _c(stone))
	mb.add(MeshBuilder.box(Vector3(3.2, 0.9, 1.8)), Transform3D(Basis(Vector3(0, 0, 1), 0.5) * Basis(Vector3.UP, 0.4), Vector3(3.8, 0.45, hz + 2.6)), _c(stone))   # the other half, fallen
	# squat octagonal columns down both sides, some broken, one fallen across the floor
	for sd in [-1.0, 1.0]:
		for k in 3:
			var at := Vector3(sd * (hx - 3.5), 0, -hz + 4.0 + k * 6.0)
			var hh := 6.5 if rng.randf() < 0.6 else rng.randf_range(1.5, 3.5)
			mb.add(MeshBuilder.box(Vector3(1.6, 0.5, 1.6)), Transform3D(Basis(), at + Vector3(0, 0.25, 0)), _c(stone.darkened(0.1)))
			mb.add(MeshBuilder.cyl(0.6, 0.66, hh, 8), Transform3D(Basis(), at + Vector3(0, 0.5 + hh * 0.5, 0)), _c(_shade(stone, rng, 0.06)))
			for r in 2:
				mb.add(MeshBuilder.cyl(0.7, 0.7, 0.18, 8), Transform3D(Basis(), at + Vector3(0, 1.2 + r * (hh - 1.4), 0)), _c(Color(0.55, 0.38, 0.2), IRON))   # bronze bands
			if hh > 6.0:
				mb.add(MeshBuilder.box(Vector3(1.7, 0.6, 1.7)), Transform3D(Basis(), at + Vector3(0, hh + 0.8, 0)), _c(stone.darkened(0.1)))
			col.call(Vector3(1.3, hh + 0.5, 1.3), at + Vector3(0, (hh + 0.5) * 0.5, 0))
	mb.add(MeshBuilder.cyl(0.6, 0.66, 6.0, 8), Transform3D(Basis(Vector3(0, 0, 1), PI / 2) * Basis(Vector3.UP, 0.3), Vector3(hx - 6.0, 0.6, 3.0)), _c(stone))
	# the great hearth against the back wall: a stone bed of glowing coals, a hood and chimney
	var hz0 := -hz + 2.2
	mb.add(MeshBuilder.box(Vector3(7.0, 1.2, 3.2)), Transform3D(Basis(), Vector3(0, 0.6, hz0)), _c(stone.darkened(0.2), HOT))
	mb.add(MeshBuilder.box(Vector3(6.2, 0.3, 2.6)), Transform3D(Basis(), Vector3(0, 1.25, hz0)), _c(Color(1.0, 0.4, 0.08), GLOW))
	for k in 18:   # lumps of coal glowing on it
		mb.add(MeshBuilder.sphere(rng.randf_range(0.15, 0.3), 6, 4), Transform3D(Basis(), Vector3(rng.randf_range(-2.8, 2.8), 1.4, hz0 + rng.randf_range(-1.1, 1.1))), _c(Color(1.0, 0.3, 0.05) if k % 3 else Color(0.08, 0.05, 0.04), GLOW if k % 3 else ROCK))
	mb.add(MeshBuilder.cyl(1.6, 3.8, 2.6, 4), Transform3D(Basis(Vector3.UP, PI / 4).scaled(Vector3(1.3, 1.0, 0.7)), Vector3(0, 4.4, hz0 - 0.2)), _c(stone.darkened(0.12)))   # the hood
	mb.add(MeshBuilder.box(Vector3(2.4, 7.0, 2.0)), Transform3D(Basis(), Vector3(0, 9.0, hz0 - 0.6)), _c(stone.darkened(0.15)))      # the chimney
	col.call(Vector3(7.0, 1.4, 3.2), Vector3(0, 0.7, hz0))
	# bellows beside it: leather between two boards, an iron nozzle
	var bel := Vector3(4.6, 0.9, hz0 + 0.4)
	mb.add(MeshBuilder.box(Vector3(2.2, 0.12, 1.2)), Transform3D(Basis(Vector3(0, 0, 1), 0.15), bel + Vector3(0, 0.45, 0)), _c(Color(0.3, 0.2, 0.12)))
	mb.add(MeshBuilder.box(Vector3(2.2, 0.12, 1.2)), Transform3D(Basis(), bel), _c(Color(0.3, 0.2, 0.12)))
	mb.add(MeshBuilder.sphere(0.6, 10, 6), Transform3D(Basis.from_scale(Vector3(1.6, 0.4, 0.9)), bel + Vector3(0, 0.22, 0)), _c(Color(0.35, 0.22, 0.14)))
	mb.limb(bel + Vector3(-1.1, 0.2, 0), bel + Vector3(-1.9, 0.5, -0.2), 0.12, 0.06, _c(IRON_COL, IRON), 6)
	# the quenching channel: a stone-lined trough of lava along the west wall
	mb.add(MeshBuilder.box(Vector3(1.8, 0.5, hz * 1.4)), Transform3D(Basis(), Vector3(-hx + 1.8, 0.1, -1.0)), _c(stone.darkened(0.25)))
	mb.add(MeshBuilder.box(Vector3(1.1, 0.1, hz * 1.35)), Transform3D(Basis(), Vector3(-hx + 1.8, 0.33, -1.0)), _c(Color(1.0, 0.38, 0.06), GLOW))
	col.call(Vector3(1.8, 0.6, hz * 1.4), Vector3(-hx + 1.8, 0.3, -1.0))
	# THE GIANT ANVIL: a stepped plinth, a waisted body, the face, the horn, the heel; a great hammer
	var av := Vector3(0, 0, 1.5)
	var iron := _c(IRON_COL.darkened(0.1), IRON)
	mb.add(MeshBuilder.box(Vector3(5.2, 0.6, 3.4)), Transform3D(Basis(), av + Vector3(0, 0.3, 0)), _c(stone.darkened(0.1)))
	mb.add(MeshBuilder.box(Vector3(4.4, 0.5, 2.8)), Transform3D(Basis(), av + Vector3(0, 0.85, 0)), _c(stone.darkened(0.05)))
	mb.add(MeshBuilder.cyl(1.0, 1.5, 1.4, 4), Transform3D(Basis(Vector3.UP, PI / 4).scaled(Vector3(1.5, 1.0, 0.75)), av + Vector3(0, 1.8, 0)), iron)   # the waist
	mb.add(MeshBuilder.box(Vector3(4.2, 1.1, 1.6)), Transform3D(Basis(), av + Vector3(-0.2, 3.05, 0)), iron)         # the face
	mb.add(MeshBuilder.cyl(0.0, 0.8, 2.6, 12), Transform3D(Basis(Vector3(0, 0, 1), PI / 2).scaled(Vector3(1.0, 1.0, 0.75)), av + Vector3(3.2, 3.2, 0)), iron)   # the horn
	mb.add(MeshBuilder.box(Vector3(1.0, 0.9, 1.4)), Transform3D(Basis(), av + Vector3(-2.7, 3.1, 0)), iron)         # the heel
	mb.add(MeshBuilder.box(Vector3(1.2, 0.15, 0.6)), Transform3D(Basis(), av + Vector3(0.4, 3.65, 0.1)), _c(Color(1.0, 0.55, 0.15), GLOW))   # a glowing billet on it
	for k in 4:   # runes on the waist
		mb.add(MeshBuilder.box(Vector3(0.3, 0.4, 0.04)), Transform3D(Basis(), av + Vector3(-0.9 + k * 0.6, 1.8, 0.93)), _c(Color(1.0, 0.55, 0.2), GLOW))
	var hm := av + Vector3(-1.2, 0, 2.3)
	mb.limb(hm + Vector3(0, 0.1, 0.0), hm + Vector3(0.6, 3.2, -0.9), 0.14, 0.12, _c(Color(0.25, 0.16, 0.1)), 8)   # the haft leaning on the anvil
	mb.add(MeshBuilder.box(Vector3(1.6, 0.8, 0.9)), Transform3D(Basis(Vector3(1, 0, 0), -0.3), hm + Vector3(0.1, 0.4, 0.15)), iron)
	col.call(Vector3(5.2, 1.1, 3.4), av + Vector3(0, 0.55, 0))
	col.call(Vector3(5.6, 2.6, 1.6), av + Vector3(0.3, 2.4, 0))
	# hanging braziers from a beam across the hall, and stout dwarf statues at the door
	mb.add(MeshBuilder.box(Vector3(hx * 2.0 - 1.0, 0.5, 0.5)), Transform3D(Basis(), Vector3(0, 6.8, -2.0)), _c(Color(0.12, 0.08, 0.05)))
	var fxs: Array[Node3D] = []
	for sd in [-1.0, 1.0]:
		var bowl := Vector3(sd * 5.0, 3.6, -2.0)
		for k in 8:
			mb.add(MeshBuilder.cyl(0.07, 0.07, 0.03, 8), Transform3D(Basis(Vector3(1, 0, 0), PI / 2) * Basis(Vector3(0, 0, 1), (k % 2) * PI / 2), bowl.lerp(Vector3(sd * 5.0, 6.6, -2.0), (k + 0.5) / 8.0)), _c(IRON_COL, IRON))
		mb.add(MeshBuilder.cyl(0.6, 0.3, 0.45, 12), Transform3D(Basis(), bowl), _c(IRON_COL, IRON))
		mb.add(MeshBuilder.sphere(0.5, 10, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.35, 1.0)), bowl + Vector3(0, 0.2, 0)), _c(Color(1.0, 0.45, 0.1), GLOW))
		var fl := Abilities._flame_particles(0.7, 0.8, 26)
		fl.position = bowl + Vector3(0, 0.5, 0)
		fxs.append(fl)
		_dwarf_statue(mb, Vector3(sd * 4.6, 0, hz + 2.2), rng)
		col.call(Vector3(1.6, 4.6, 1.6), Vector3(sd * 4.6, 2.3, hz + 2.2))
	# rubble and charred roof timbers
	for k in 14:
		var at := Vector3(rng.randf_range(-hx + 1, hx - 1), 0.25, rng.randf_range(-hz + 4, hz - 1))
		if at.distance_to(av) < 4.0:
			continue
		mb.add(MeshBuilder.box(Vector3(rng.randf_range(0.6, 1.4), rng.randf_range(0.4, 0.7), rng.randf_range(0.5, 1.0))), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.3, 0.3)), at), _c(_shade(stone, rng, 0.12)))
	for k in 3:
		var at := Vector3(rng.randf_range(-hx + 3, hx - 3), 0.3, rng.randf_range(-2, hz - 3))
		mb.add(MeshBuilder.box(Vector3(7.0, 0.45, 0.45)), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(0, 0, 1), rng.randf_range(0.05, 0.25)), at), _c(Color(0.06, 0.05, 0.045)))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(rock_material())
	root.add_child(mi)
	for f in fxs:
		root.add_child(f)
	var hf := Abilities._flame_particles(1.2, 0.9, 50)
	hf.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	hf.emission_box_extents = Vector3(2.8, 0.2, 1.0)
	hf.position = Vector3(0, 1.6, hz0)
	root.add_child(hf)
	var smoke := steam(Vector3(0, 12.6, hz0 - 0.6), 0.9, 20, night, Color(0.15, 0.13, 0.12, 0.5))
	root.add_child(smoke)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.18)
	l.light_energy = 3.2
	l.omni_range = 18.0
	l.position = Vector3(0, 3.0, hz0 + 1.5)
	l.shadow_enabled = false
	root.add_child(l)
	root.set_meta("anvil", av + Vector3(0, 3.6, 0))
	return root


## A stout dwarf in stone on a plinth: a horned helm, a great braided beard, both hands on the
## haft of a hammer resting head-down before him.
static func _dwarf_statue(mb: MeshBuilder, at: Vector3, rng: RandomNumberGenerator) -> void:
	var st := _c(_shade(DWARF_STONE.lightened(0.08), rng, 0.05))
	var dk := _c(st.darkened(0.15))
	mb.add(MeshBuilder.box(Vector3(1.6, 0.8, 1.6)), Transform3D(Basis(), at + Vector3(0, 0.4, 0)), dk)
	var y := 0.8
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.cyl(0.28, 0.32, 0.9, 8), Transform3D(Basis(), at + Vector3(sd * 0.3, y + 0.45, 0)), st)   # legs
		mb.add(MeshBuilder.box(Vector3(0.42, 0.25, 0.6)), Transform3D(Basis(), at + Vector3(sd * 0.3, y + 0.1, 0.1)), dk)   # boots
	mb.add(MeshBuilder.cyl(0.62, 0.7, 1.3, 10), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.8)), at + Vector3(0, y + 1.5, 0)), st)   # barrel chest
	mb.add(MeshBuilder.cyl(0.72, 0.72, 0.18, 10), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.82)), at + Vector3(0, y + 0.95, 0)), dk)   # belt
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.sphere(0.32, 8, 5), Transform3D(Basis(), at + Vector3(sd * 0.72, y + 2.05, 0)), dk)   # pauldrons
		mb.limb(at + Vector3(sd * 0.75, y + 1.95, 0), at + Vector3(sd * 0.3, y + 1.15, 0.55), 0.2, 0.17, st, 8)
	var hd := at + Vector3(0, y + 2.6, 0.05)
	mb.add(MeshBuilder.sphere(0.36, 10, 6), Transform3D(Basis(), hd), st)
	mb.add(MeshBuilder.sphere(0.42, 10, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.0)), hd + Vector3(0, 0.18, 0)), dk)   # helm
	for sd in [-1.0, 1.0]:
		mb.limb(hd + Vector3(sd * 0.35, 0.25, 0), hd + Vector3(sd * 0.8, 0.75, -0.1), 0.1, 0.02, dk, 6)   # horns
	mb.add(MeshBuilder.box(Vector3(0.1, 0.3, 0.12)), Transform3D(Basis(), hd + Vector3(0, -0.02, 0.36)), dk)   # nasal guard
	# the beard: a broad fan and two braids down to the belt
	mb.add(MeshBuilder.cone(0.42, 0.9, 8), Transform3D(Basis(Vector3(1, 0, 0), PI).scaled(Vector3(1.0, 1.0, 0.5)), hd + Vector3(0, -0.6, 0.28)), st)
	for sd in [-1.0, 1.0]:
		for k in 4:
			mb.add(MeshBuilder.sphere(0.1, 6, 4), Transform3D(Basis(), hd + Vector3(sd * 0.16, -1.0 - k * 0.16, 0.38)), dk)
	# the hammer, head down between his feet
	mb.limb(at + Vector3(0, y + 0.3, 0.75), at + Vector3(0, y + 1.6, 0.62), 0.07, 0.07, dk, 6)
	mb.add(MeshBuilder.box(Vector3(0.9, 0.45, 0.45)), Transform3D(Basis(), at + Vector3(0, y + 0.22, 0.78)), dk)


## The smith-god's broken colossus, half sunk in a lava pool: a bearded head in a crested helm
## tipped back, one shoulder and a mighty arm thrust up out of the lava, the fist still gripping
## a hammer whose head has broken away; cracks glowing low down where the lava is eating it.
static func smith_statue(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var st := Color(0.36, 0.32, 0.29)
	var hot := _c(st.darkened(0.1), HOT)
	var s := 3.4
	var tilt := Basis(Vector3(1, 0, 0), -0.32) * Basis(Vector3(0, 0, 1), 0.12)
	var hd := Vector3(0, 2.2 * s, 0)
	var xf := func(p: Vector3) -> Vector3: return tilt * p
	# the head
	mb.add(MeshBuilder.sphere(1.0 * s, 18, 12), Transform3D(tilt.scaled(Vector3(0.88, 1.0, 0.95)), xf.call(hd)), _c(st))
	# the helm: a dome, a broad rim, a tall comb crest, cheek guards
	mb.add(MeshBuilder.sphere(1.08 * s, 18, 8), Transform3D(tilt.scaled(Vector3(0.95, 0.75, 1.0)), xf.call(hd + Vector3(0, 0.35 * s, -0.05 * s))), _c(st.darkened(0.12)))
	mb.add(MeshBuilder.cyl(1.12 * s, 1.12 * s, 0.18 * s, 20), Transform3D(tilt, xf.call(hd + Vector3(0, 0.25 * s, 0))), _c(st.darkened(0.2)))
	mb.add(MeshBuilder.box(Vector3(0.22, 0.75, 2.0) * s), Transform3D(tilt, xf.call(hd + Vector3(0, 1.2 * s, -0.1 * s))), _c(st.darkened(0.15)))
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(0.2, 0.9, 0.7) * s), Transform3D(tilt * Basis(Vector3.UP, sd * 0.3), xf.call(hd + Vector3(sd * 0.85 * s, -0.25 * s, 0.35 * s))), _c(st.darkened(0.12)))
	# the face: heavy brows, deep eyes, a broad nose, a stern mouth lost in the moustache
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(0.62, 0.2, 0.3) * s), Transform3D(tilt * Basis(Vector3(0, 0, 1), -sd * 0.18), xf.call(hd + Vector3(sd * 0.36 * s, 0.12 * s, 0.82 * s))), _c(st.darkened(0.05)))
		mb.add(MeshBuilder.sphere(0.15 * s, 8, 6), Transform3D(tilt, xf.call(hd + Vector3(sd * 0.34 * s, -0.08 * s, 0.82 * s))), _c(Color(1.0, 0.45, 0.1), GLOW))   # eyes glow with the lava's light
		mb.add(MeshBuilder.sphere(0.28 * s, 10, 6), Transform3D(tilt.scaled(Vector3(1.4, 0.6, 1.0)), xf.call(hd + Vector3(sd * 0.32 * s, -0.55 * s, 0.82 * s))), _c(st.lightened(0.04)))   # moustache
	mb.add(MeshBuilder.cyl(0.12 * s, 0.24 * s, 0.6 * s, 8), Transform3D(tilt * Basis(Vector3(1, 0, 0), 0.3), xf.call(hd + Vector3(0, -0.25 * s, 0.98 * s))), _c(st))   # nose
	# the beard: a great fan of braids pouring down into the lava
	for k in 9:
		var x := (k - 4) * 0.2 * s
		var top := hd + Vector3(x, -0.65 * s, 0.75 * s - absf(x) * 0.25)
		var bot := top + Vector3(x * 0.3, -2.1 * s, 0.25 * s)
		var c := _c(st.darkened(0.06 * (k % 2)), HOT if k % 3 == 0 else ROCK)
		mb.limb(xf.call(top), xf.call(bot), 0.18 * s, 0.12 * s, c, 8)
		for b in 4:   # the braid's knots
			mb.add(MeshBuilder.sphere(0.17 * s, 8, 5), Transform3D(tilt, xf.call(top.lerp(bot, (b + 0.5) / 4.0))), _c(st.darkened(0.12)))
	# the shoulder and the upraised arm with the hammer
	var sh := Vector3(1.9 * s, 1.1 * s, -0.2 * s)
	mb.add(MeshBuilder.sphere(0.95 * s, 14, 8), Transform3D(Basis.from_scale(Vector3(1.1, 0.8, 1.0)), sh), hot)
	mb.add(MeshBuilder.cyl(1.0 * s, 1.0 * s, 0.25 * s, 16), Transform3D(Basis(Vector3(0, 0, 1), -0.4), sh + Vector3(0, 0.35 * s, 0)), _c(Color(0.42, 0.3, 0.16), IRON))   # pauldron rim
	var el := sh + Vector3(0.7 * s, 1.9 * s, 0.4 * s)
	var fist := el + Vector3(-0.2 * s, 1.9 * s, 0.3 * s)
	mb.limb(sh, el, 0.6 * s, 0.48 * s, _c(st), 12)
	mb.limb(el, fist, 0.46 * s, 0.4 * s, _c(st), 12)
	mb.add(MeshBuilder.cyl(0.5 * s, 0.5 * s, 0.5 * s, 12), Transform3D(Basis(), el + Vector3(0, 0.9 * s, 0.1 * s)), _c(Color(0.42, 0.3, 0.16), IRON))   # bracer
	mb.add(MeshBuilder.sphere(0.5 * s, 12, 8), Transform3D(Basis.from_scale(Vector3(1.0, 0.9, 1.1)), fist), _c(st.lightened(0.03)))
	var haft_top := fist + Vector3(0.3 * s, 1.6 * s, -0.1 * s)
	mb.limb(fist + Vector3(-0.15 * s, -0.8 * s, 0.05 * s), haft_top, 0.16 * s, 0.15 * s, _c(st.darkened(0.2)), 10)
	mb.add(MeshBuilder.box(Vector3(1.6, 0.9, 0.95) * s), Transform3D(Basis(Vector3(0, 0, 1), 0.2), haft_top + Vector3(-0.3 * s, 0.25 * s, 0)), _c(st.darkened(0.1)))   # what's left of the hammer head
	mb.add(MeshBuilder.box(Vector3(0.5, 0.95, 1.0) * s), Transform3D(Basis(Vector3(0, 0, 1), 0.2), haft_top + Vector3(-1.15 * s, 0.1 * s, 0)), _c(st.darkened(0.25)))   # its broken face
	# the other hand, half sunk, fingers curled over the lava's surface
	var hand := Vector3(-2.6 * s, 0.3 * s, 1.2 * s)
	mb.add(MeshBuilder.sphere(0.6 * s, 10, 6), Transform3D(Basis.from_scale(Vector3(1.2, 0.6, 1.0)), hand), hot)
	for k in 4:
		var a := -0.6 + k * 0.4
		mb.limb(hand + Vector3(cos(a) * 0.5 * s, 0.1 * s, sin(a) * 0.5 * s + 0.3 * s), hand + Vector3(cos(a) * 1.1 * s, -0.25 * s, sin(a) * 1.1 * s + 0.4 * s), 0.17 * s, 0.13 * s, hot, 8)
	var cols := [DesertProps._box_col(Vector3(2.4, 4.0, 2.4) * s, Vector3(0, 2.0 * s, 0)), DesertProps._box_col(Vector3(1.6, 4.0, 1.6) * s, sh + Vector3(0.5 * s, 1.5 * s, 0.2 * s))]
	return _done(mb, cols)


## The lava falls: a ridge of black rock on the northern rim, lava pouring over its lip in two
## glowing cascades into the plunge pool that feeds river A, steam and embers boiling up.
static func falls_ridge(rng: RandomNumberGenerator, falls: Dictionary) -> Node3D:
	var root := Node3D.new()
	var at: Vector3 = falls["at"]
	var plunge_lv := 0.0
	for p in CalderaBuilder.pools:
		if p["kind"] == "plunge":
			plunge_lv = p["lv"]
	var base := SwampWater.height_at(at.x, at.z)
	root.position = Vector3(at.x, 0, at.z)
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	root.add_child(body)
	var top := plunge_lv + 19.0
	var lip_z := 6.0   # the front face, toward the arena (local +Z)
	# the ridge: great lumpy masses in layers, cracked hot near the falls
	for k in 34:
		var x := rng.randf_range(-28.0, 28.0)
		var r := rng.randf_range(4.5, 8.5)
		var y := rng.randf_range(plunge_lv - 2.0, top - r * 0.6)
		var near := absf(x) < 8.0
		var c := _shade(BASALT if k % 3 else SCORIA, rng, 0.15)
		c.a = HOT if near and rng.randf() < 0.5 else ROCK
		mb.add(_lumpy(r, rng), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.2, 0.75, 0.9)), Vector3(x, y, rng.randf_range(-6.0, lip_z - r * 0.5))), c)
	for sd in [-1.0, 1.0]:   # shoulders of the ridge sloping down either side
		for k in 5:
			var x: float = sd * (12.0 + k * 5.0)
			var r := 6.0 - k * 0.5
			mb.add(_lumpy(r, rng), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.3, 0.9, 1.0)), Vector3(x, base + r * 0.6 + (5 - k) * 1.6, rng.randf_range(-4.0, 2.0))), _c(_shade(BASALT, rng, 0.12)))
	# the summit channel feeding the falls
	mb.add(MeshBuilder.box(Vector3(9.0, 0.3, 10.0)), Transform3D(Basis(), Vector3(0, top - 0.6, 0)), _c(Color(1.0, 0.4, 0.07), GLOW))
	body.add_child(DesertProps._shape_node(DesertProps._box_col(Vector3(48.0, top - base + 4.0, 12.0), Vector3(0, (top + base) * 0.5 - 2.0, -1.0))))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(rock_material())
	root.add_child(mi)
	# the cascade: one broad curved sheet of lava pouring over the lip, splitting round a
	# jutting rock halfway down, rocks framing its edges; spray and steam where it lands
	var fall_mat := CalderaBuilder.lava_material("fall")
	var n := 28
	for part in 2:
		var cx := -2.4 + part * 4.8 + rng.randf_range(-0.3, 0.3)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rows: Array = []
		var dist := 0.0
		var prev_c := Vector3.ZERO
		for k in n + 1:
			var t := float(k) / n
			var z := lip_z - 1.5 + 4.5 * sqrt(t) + 0.5
			var y := top - 0.5 - (top - plunge_lv) * (t * t * 0.45 + t * 0.55)
			var wob := sin(t * 9.0 + part * 2.0) * 0.4
			var c := Vector3(cx + wob * 0.6 - (part * 2.0 - 1.0) * t * 1.2, y, z)
			if k > 0:
				dist += c.distance_to(prev_c)
			prev_c = c
			var ww := 4.2 * (1.0 + t * 0.5) + wob
			rows.append([c + Vector3(-ww * 0.5, 0, sin(t * 7.0) * 0.3), c + Vector3(ww * 0.5, 0, cos(t * 6.0) * 0.3), dist, ww])
		for k in n:
			var r0: Array = rows[k]
			var r1: Array = rows[k + 1]
			for tri in [[r0[0], Vector2(0, r0[2])], [r0[1], Vector2(r0[3], r0[2])], [r1[1], Vector2(r1[3], r1[2])], [r0[0], Vector2(0, r0[2])], [r1[1], Vector2(r1[3], r1[2])], [r1[0], Vector2(0, r1[2])]]:
				st.set_normal(Vector3(0, 0, 1))
				st.set_uv(tri[1])
				st.add_vertex(tri[0])
		var fm := MeshInstance3D.new()
		fm.mesh = st.commit()
		fm.material_override = fall_mat
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fm)
		root.add_child(embers(Vector3(cx, plunge_lv + 0.4, lip_z + 4.8), 2.4, 40))
		root.add_child(steam(Vector3(cx, plunge_lv + 0.5, lip_z + 4.8), 2.2, 28, false))
	# the lip's overhang, the jutting rock that splits the fall, rocks along its outer edges
	var mbk := MeshBuilder.new()
	mbk.add(_lumpy(3.0, rng), Transform3D(Basis.from_scale(Vector3(2.4, 0.5, 0.9)), Vector3(0, top - 0.2, lip_z - 2.2)), _c(BASALT.darkened(0.2), HOT))
	mbk.add(_lumpy(1.6, rng), Transform3D(Basis.from_scale(Vector3(0.8, 2.6, 0.9)), Vector3(0, (top + plunge_lv) * 0.5, lip_z + 1.2)), _c(BASALT, HOT))
	for sd in [-1.0, 1.0]:
		for j in 5:
			var y := lerpf(top - 0.5, plunge_lv + 0.8, j / 4.0)
			var rr := rng.randf_range(1.8, 2.8)
			var ck := _shade(BASALT, rng, 0.2)
			ck.a = HOT if rng.randf() < 0.4 else ROCK
			mbk.add(_lumpy(rr, rng), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.9, 1.1, 0.9)), Vector3(sd * (5.6 + j * 0.4 + rr * 0.4), y, lip_z - 1.0 + 3.8 * sqrt(float(j) / 4.0))), ck)
	var rk := MeshInstance3D.new()
	rk.mesh = mbk.commit(rock_material())
	root.add_child(rk)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.45, 0.12)
	l.light_energy = 4.0
	l.omni_range = 34.0
	l.position = Vector3(0, plunge_lv + 6.0, lip_z + 8.0)
	l.shadow_enabled = false
	l.add_to_group("lava_light")
	root.add_child(l)
	return root


## A natural rock bridge over a lava river: under the humped ground, an arch of black rock on
## either face with the lava pouring into its dark mouth, rough boulders along both edges of the
## deck. Local +Z runs along the river; `hw` is half the river's width plus banks.
static func rock_arch(rng: RandomNumberGenerator, hw: float, hl: float) -> Dictionary:
	var mb := MeshBuilder.new()
	for face in [-1.0, 1.0]:
		var z: float = face * (hl - 0.3)
		# boulders following an arch shape across the river
		var n := 9
		for k in n:
			var t := float(k) / (n - 1)
			var x := lerpf(-hw - 0.6, hw + 0.6, t)
			var lift := sin(t * PI) * 0.75
			var r := rng.randf_range(0.9, 1.4)
			var c := _shade(BASALT, rng, 0.15)
			c.a = HOT if rng.randf() < 0.3 else ROCK
			mb.add(_lumpy(r, rng), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, 0.75, 0.6)), Vector3(x, 0.55 + lift + r * 0.35, z)), c)
		# the arch's dark mouth, the lava glowing on its floor
		mb.add(MeshBuilder.box(Vector3(hw * 1.5, 0.65, 0.2)), Transform3D(Basis(), Vector3(0, 0.3, z - face * 0.3)), _c(Color(0.01, 0.006, 0.005)))
		mb.add(MeshBuilder.box(Vector3(hw * 1.5, 0.04, 0.8)), Transform3D(Basis(), Vector3(0, 0.02, z - face * 0.1)), _c(Color(1.0, 0.4, 0.07), GLOW))
	# boulders along the deck's edges
	for sd in [-1.0, 1.0]:
		for k in 3:
			var z := lerpf(-hl + 0.6, hl - 0.6, k / 2.0)
			mb.add(_lumpy(rng.randf_range(0.5, 0.8), rng), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, 0.7, 1.0)), Vector3(sd * (hw - 0.4), 1.25, z)), _c(_shade(BASALT, rng, 0.15)))
	return _done(mb, [])


# ------------------------------------------------------------------ effects

## Steam (or smoke) pouring up from a vent: soft puffs that swell and fade as they rise.
static func steam(at: Vector3, radius: float, amount: int, night: bool, col := Color(0.86, 0.82, 0.76, 0.32)) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 3.2
	p.preprocess = 3.0
	p.local_coords = false
	p.position = at
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0.25, 0.4, 0.1)
	p.damping_min = 0.2
	p.damping_max = 0.5
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.6))
	p.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Abilities._soft_dot()
	q.material = m
	p.mesh = q
	var c := col
	if night:
		c = Color(col.r * 0.5, col.g * 0.4, col.b * 0.38, col.a)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(c.r, c.g, c.b, 0.0))
	ramp.add_point(0.15, c)
	ramp.set_color(ramp.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = ramp
	return p


## Embers spiralling up from a hot spot.
static func embers(at: Vector3, radius: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.4
	p.preprocess = 2.0
	p.local_coords = false
	p.position = at
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, 0.6, 0)
	p.tangential_accel_min = -1.0
	p.tangential_accel_max = 1.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Abilities._soft_dot()
	m.disable_fog = true
	q.material = m
	p.mesh = q
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.35, 1.0))
	ramp.add_point(0.5, Color(1.0, 0.4, 0.08, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.1, 0.02, 0.0))
	p.color_ramp = ramp
	return p


# ------------------------------------------------------------------ ground scatter

static func scatter_mesh(kind: String, rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	match kind:
		"pumice":   # pale grey frothy lumps
			for k in 3:
				var a := rng.randf() * TAU
				var d := rng.randf_range(0.0, 0.35)
				mb.add(_lumpy(rng.randf_range(0.06, 0.16), rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 0.9)), Vector3(cos(a) * d, 0.04, sin(a) * d)), _c(_shade(Color(0.55, 0.52, 0.48), rng, 0.12)))
		"scoria":   # red-black cinders
			for k in 6:
				var a := rng.randf() * TAU
				var d := rng.randf_range(0.0, 0.4)
				mb.add(MeshBuilder.sphere(rng.randf_range(0.03, 0.08), 5, 3), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, rng.randf_range(0.7, 1.3))), Vector3(cos(a) * d, 0.02, sin(a) * d)), _c(_shade(SCORIA if k % 2 else BASALT, rng, 0.25)))
		"ash":   # a low drift of grey ash
			mb.add(MeshBuilder.sphere(0.9, 12, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.07, 0.6)), Vector3(0, -0.01, 0)), _c(Color(0.27, 0.26, 0.25)))
		"tuft":   # a singed clump of dead grass
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for k in 8:
				var a := TAU * k / 8.0 + rng.randf() * 0.5
				var out := Vector3(cos(a), 0, sin(a))
				var side := Vector3(-out.z, 0, out.x)
				var tip := out * rng.randf_range(0.12, 0.3) + Vector3(0, rng.randf_range(0.2, 0.4), 0)
				st.set_normal(Vector3.UP)
				st.set_color(Color(0.12, 0.1, 0.08, 0.0))
				st.add_vertex(-side * 0.025)
				st.set_color(Color(0.12, 0.1, 0.08, 0.0))
				st.add_vertex(side * 0.025)
				st.set_color(Color(0.45, 0.36, 0.22, 1.0) if k % 2 else Color(0.18, 0.14, 0.1, 1.0))
				st.add_vertex(tip)
			var tm := st.commit()
			tm.surface_set_material(0, MeshBuilder.foliage_material())
			return tm
		"ember":   # glowing bits of cinder
			for k in 4:
				var a := rng.randf() * TAU
				var d := rng.randf_range(0.0, 0.3)
				mb.add(MeshBuilder.sphere(rng.randf_range(0.025, 0.05), 5, 3), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.0)), Vector3(cos(a) * d, 0.02, sin(a) * d)), _c(Color(1.0, 0.38 + rng.randf() * 0.2, 0.06), GLOW))
			mb.add(MeshBuilder.sphere(0.08, 6, 4), Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), Vector3(0.1, 0.02, 0.0)), _c(BASALT.darkened(0.3)))
		"crack":   # a little glowing fissure in the ground
			var a := rng.randf() * TAU
			var l := rng.randf_range(0.6, 1.4)
			mb.add(MeshBuilder.box(Vector3(l, 0.04, 0.05)), Transform3D(Basis(Vector3.UP, a), Vector3(0, 0.02, 0)), _c(Color(1.0, 0.36, 0.06), GLOW))
			for b in 2:
				var a2 := a + rng.randf_range(0.5, 1.2) * (1.0 if b == 0 else -1.0)
				var at := Vector3(cos(a), 0, -sin(a)) * l * (0.15 + b * 0.25)
				mb.add(MeshBuilder.box(Vector3(l * 0.5, 0.04, 0.035)), Transform3D(Basis(Vector3.UP, a2), at + Vector3(cos(a2), 0, -sin(a2)) * l * 0.25 + Vector3(0, 0.02, 0)), _c(Color(1.0, 0.3, 0.05), GLOW))
		"sulphur":   # yellow crumbs and a crystal or two
			for k in 4:
				var a := rng.randf() * TAU
				var d := rng.randf_range(0.0, 0.3)
				mb.add(MeshBuilder.cyl(0.0, rng.randf_range(0.03, 0.06), rng.randf_range(0.08, 0.2), 5), Transform3D(Basis(Vector3(cos(a), 0, sin(a)), rng.randf_range(0.0, 0.8)), Vector3(cos(a) * d, 0.05, sin(a) * d)), _c(SULPHUR_YELLOW, SULPHUR))
		"stones":
			mb.add(_lumpy(rng.randf_range(0.2, 0.4), rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 0.8)), Vector3(0, 0.06, 0)), _c(_shade(BASALT, rng, 0.2), HOT if rng.randf() < 0.2 else ROCK))
	return mb.commit(rock_material())
