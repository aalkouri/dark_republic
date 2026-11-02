class_name DesertProps
extends RefCounted
## Procedural Desert props. Builders return { "mesh": ArrayMesh, "colliders": [[Shape3D,
## Transform3D], ...] } with the origin at the base, like ForestProps / CastleProps.
##
## Stone is drawn with STONE_SHADER: sandstone weathered by fbm noise, bedding lines, pitting and
## dark streaks running down the faces, sand settled on every upward face, and carved
## hieroglyphs wherever a part's vertex alpha is 0.5 (columns of little signs: suns, eyes,
## birds, reeds, ankhs, water ripples, cut into whichever face they're on). Pyramid blocks also
## carry UVs and their size (UV2) so the shader cuts the joints between them and chips the
## corners. Trees, grass and scrub use MeshBuilder's prop material (they sway and burn).

const SAND := Color(0.84, 0.66, 0.44, 0.0)
const SANDSTONE := Color(0.8, 0.64, 0.45, 0.0)
const LIMESTONE := Color(0.88, 0.83, 0.72, 0.0)
const GRANITE := Color(0.56, 0.46, 0.44, 0.0)
const BASALT := Color(0.24, 0.23, 0.24, 0.0)
const BONE := Color(0.9, 0.86, 0.76, 0.0)
const GLYPH := 0.5               # vertex alpha: carve hieroglyphs here
const POLISHED := 1.0            # vertex alpha: smooth casing stone
const PALM_TRUNK := Color(0.45, 0.33, 0.22, 0.0)
const FROND := Color(0.36, 0.5, 0.2, 1.0)
const FROND_DRY := Color(0.62, 0.52, 0.28, 1.0)

const STONE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 sand_col : source_color = vec3(0.84, 0.66, 0.44);
uniform float sand_amount = 1.0;
varying vec3 lpos;
varying vec3 lnrm;
varying vec3 wpos;
varying vec3 wnrm;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { return noise(p) * 0.5 + noise(p * 2.1 + 3.3) * 0.27 + noise(p * 4.3 + 7.1) * 0.15 + noise(p * 8.7) * 0.08; }
float seg(vec2 p, vec2 a, vec2 b) { vec2 pa = p - a; vec2 ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h); }

// One hieroglyph in a cell (c in 0..1): returns 1 inside the carved strokes
float glyph(vec2 c, float h) {
	float w = 0.07;
	float d = 1.0;
	if (h < 0.12) { d = abs(length(c - 0.5) - 0.28); }                                   // sun disc
	else if (h < 0.24) { d = min(seg(c, vec2(0.15, 0.5), vec2(0.85, 0.5)), length((c - vec2(0.5, 0.5)) * vec2(1.0, 2.0)) - 0.02); d = min(d, abs(length((c - 0.5) * vec2(0.8, 1.8)) - 0.3)); }   // eye
	else if (h < 0.36) { d = min(seg(c, vec2(0.5, 0.1), vec2(0.5, 0.9)), seg(c, vec2(0.5, 0.75), vec2(0.72, 0.9))); }   // reed
	else if (h < 0.48) { d = min(min(abs(length((c - vec2(0.5, 0.72)) * vec2(1.0, 1.3)) - 0.15), seg(c, vec2(0.5, 0.58), vec2(0.5, 0.08))), seg(c, vec2(0.25, 0.48), vec2(0.75, 0.48))); }   // ankh
	else if (h < 0.6) { float y = 0.5 + sin(c.x * 18.0) * 0.08; d = abs(c.y - y); d = max(d, abs(c.x - 0.5) - 0.38); }   // water
	else if (h < 0.72) { d = min(length((c - vec2(0.45, 0.42)) * vec2(1.0, 1.6)) - 0.2, seg(c, vec2(0.6, 0.55), vec2(0.78, 0.8))); d = min(d, seg(c, vec2(0.4, 0.25), vec2(0.35, 0.08))); }   // bird
	else if (h < 0.84) { d = abs(max(abs(c.x - 0.5), abs(c.y - 0.5)) - 0.3); }                   // house
	else { d = min(seg(c, vec2(0.2, 0.2), vec2(0.8, 0.8)), seg(c, vec2(0.2, 0.8), vec2(0.5, 0.5))); }   // staff
	return 1.0 - smoothstep(w * 0.6, w, d);
}

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float tag = COLOR.a;
	float polished = step(0.9, tag);
	float n = fbm(wpos * 0.8);
	float fine = noise(wpos * 9.0);
	col *= mix(0.78 + 0.34 * n, 0.92 + 0.12 * n, polished);
	col *= mix(0.9 + 0.16 * fine, 0.97 + 0.05 * fine, polished);
	// bedding: thin horizontal layers in the sandstone
	float bed = noise(vec3(wpos.y * 6.0, wpos.x * 0.05, wpos.z * 0.05));
	col *= mix(0.92 + 0.12 * bed, 1.0, polished);
	// pits and pocks
	float pit = smoothstep(0.78, 0.86, noise(wpos * 6.5 + 2.0)) * (1.0 - polished * 0.7);
	col *= 1.0 - pit * 0.35;
	// streaks of grime running down the vertical faces
	float vert = 1.0 - abs(wnrm.y);
	float streak = smoothstep(0.55, 0.8, noise(vec3(wpos.x * 3.0, wpos.y * 0.25, wpos.z * 3.0))) * vert;
	col *= 1.0 - streak * 0.18;
	// block joints and chipped edges (pyramid blocks: UV across the face, UV2 = its size in m)
	float joint = 0.0;
	if (UV2.x > 0.0) {
		vec2 m = UV * UV2;
		vec2 mm = (1.0 - UV) * UV2;
		float e = min(min(m.x, mm.x), min(m.y, mm.y));
		float wob = (noise(wpos * 3.0) - 0.5) * 0.05;
		joint = 1.0 - smoothstep(0.015, 0.06, e + wob);
		float corner = length(min(m, mm));
		float chip = (1.0 - smoothstep(0.05, 0.2, corner - noise(wpos * 2.0) * 0.12)) * step(0.45, hash(floor(wpos * 0.7)));
		joint = max(joint, chip * 0.8);
		col *= 1.0 - joint * 0.5;
		col *= 0.9 + 0.2 * smoothstep(0.0, 0.3, e);   // worn, rounded block faces catch more light
	}
	// hieroglyphs carved into the face
	float carve = 0.0;
	if (tag > 0.4 && tag < 0.6) {
		vec3 an = abs(lnrm);
		vec2 p = an.x > an.z ? lpos.zy : lpos.xy;
		if (an.y > max(an.x, an.z)) { p = lpos.xz; }
		float cell = 0.26;
		vec2 g = p / cell;
		float colw = 4.0;
		float rule = 1.0 - smoothstep(0.02, 0.06, abs(fract(g.x / colw + 0.5) - 0.5) * colw);
		vec2 id = floor(g);
		vec2 f = fract(g);
		float h = hash2(id + 17.0);
		float pres = step(0.18, hash2(id + 3.0));
		carve = max(glyph(f, h) * pres, rule * 0.8);
		carve *= smoothstep(0.1, 0.5, noise(wpos * 1.3) + 0.3);   // eroded in places
		col *= 1.0 - carve * 0.5;
	}
	// sand settled on the upward faces and in the carvings
	float up = smoothstep(0.5, 0.9, wnrm.y);
	float sand = up * smoothstep(0.3, 0.65, noise(wpos * 1.2) * 0.8 + fine * 0.2 + 0.15) * sand_amount;
	col = mix(col, sand_col * (0.85 + 0.2 * fine), sand * 0.85);
	col = mix(col, sand_col * 0.8, carve * 0.25);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.55, polished) + carve * 0.05;
	SPECULAR = mix(0.3, 0.5, polished);
}
"""

static var _stone_mat: ShaderMaterial
static var _gold_mat: StandardMaterial3D
static var _void_mat: StandardMaterial3D
static var _cache := {}


static func stone_material() -> ShaderMaterial:
	if _stone_mat == null:
		var sh := Shader.new()
		sh.code = STONE_SHADER
		_stone_mat = ShaderMaterial.new()
		_stone_mat.shader = sh
	return _stone_mat


static func gold_material() -> StandardMaterial3D:
	if _gold_mat == null:
		_gold_mat = StandardMaterial3D.new()
		_gold_mat.albedo_color = Color(0.95, 0.72, 0.28)
		_gold_mat.metallic = 0.85
		_gold_mat.roughness = 0.28
		_gold_mat.vertex_color_use_as_albedo = true
	return _gold_mat


static func void_material() -> StandardMaterial3D:
	if _void_mat == null:
		_void_mat = StandardMaterial3D.new()
		_void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_void_mat.albedo_color = Color(0.015, 0.01, 0.01)
	return _void_mat


static func _c(c: Color, a := 0.0) -> Color:
	return Color(c.r, c.g, c.b, a)


static func _shade(c: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	var f := 1.0 + rng.randf_range(-amount, amount)
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), c.a)


static func _box_col(size: Vector3, at: Vector3, basis := Basis()) -> Array:
	var s := BoxShape3D.new()
	s.size = size
	return [s, Transform3D(basis, at)]


static func _cyl_col(r: float, h: float, at := Vector3.ZERO) -> Array:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return [s, Transform3D(Basis(), at + Vector3(0, h * 0.5, 0))]


## A finished stone prop: the stone parts, plus an optional gold surface.
static func _stone(mb: MeshBuilder, colliders: Array, extra := {}, gold: MeshBuilder = null) -> Dictionary:
	var mesh := mb.commit(stone_material())
	if gold != null:
		gold.commit_into(mesh, gold_material())
	var d := {"mesh": mesh, "colliders": colliders}
	d.merge(extra)
	return d


# ------------------------------------------------------------------ pyramids

## A stepped pyramid built course by course, block by block, on the baked slope of pyramid `p`
## (DesertBuilder.pyramids). Every course is a ring of blocks in running bond, each a little
## proud of or sunk into the face, a shade of its own, now and then a block missing; corners
## are worn back. `cased`: the top third keeps its smooth white limestone casing and a gilded
## capstone. One face (toward the middle of the map) has a gabled entrance.
static func pyramid(p: Dictionary, rng: RandomNumberGenerator, cased: bool, night: bool) -> Node3D:
	var root := Node3D.new()
	var c: Vector2 = p["c"]
	var hw: float = p["half"]
	var n: int = p["n"]
	var run: float = p["run"]
	var rise: float = p["rise"]
	var base: float = p["base"]
	root.position = Vector3(c.x, base, c.y)
	var st := _Quads.new()
	var tint := [Color(0.82, 0.66, 0.46), Color(0.86, 0.72, 0.52), Color(0.78, 0.6, 0.44), Color(0.8, 0.68, 0.5), Color(0.74, 0.6, 0.46)]
	# the entrance: which face (toward the map's middle) and which courses
	var to_mid := Vector2(-c.x, -c.y).normalized()
	var face := 0   # 0 +x, 1 -x, 2 +z, 3 -z
	var best := -2.0
	for f in 4:
		var dirs := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
		var dd: float = (dirs[f] as Vector2).dot(to_mid)
		if dd > best:
			best = dd
			face = f
	var door_k0 := maxi(3, int(n * 0.14))
	var door_k1 := door_k0 + 5
	var case_from := int(n * 0.68) if cased else n + 10
	for k in n:
		var w := hw - k * run
		var y0 := k * rise
		var y1 := y0 + rise
		var blen := 1.35 + 0.35 * sin(k * 1.7)
		for side in 4:
			var along_half := w if side < 2 else w - run
			var a := -along_half
			var first := true
			while a < along_half - 0.01:
				var b := minf(a + blen * (0.5 if first and k % 2 == 1 else 1.0) * rng.randf_range(0.8, 1.2), along_half)
				if along_half - b < 0.5:
					b = along_half
				first = false
				var dd := rng.randf_range(-0.07, 0.03)
				var corner := minf(a + along_half, along_half - b) < 1.2
				if k > 2 and k < n - 1 and rng.randf() < (0.12 if corner else 0.04):
					dd = -rng.randf_range(0.25, 0.45)   # a missing / broken block
				var in_door := side == face and k >= door_k0 and k < door_k1 and absf((a + b) * 0.5) < 1.6
				if in_door:
					dd = -1.2
				if k >= case_from:
					dd = -0.02
				var col: Color = tint[rng.randi() % tint.size()]
				col = col * rng.randf_range(0.86, 1.1)
				if rng.randf() < 0.06:
					col = col.darkened(0.25)
				col.a = 0.0
				var chip := rng.randf_range(0.0, 0.06) if k < case_from else 0.0
				st.block(side, w + dd, w - run, a, b, y0, y1 - chip, col)
				a = b
	# summit
	var wt := hw - (n - 1) * run - run
	st.quad(Vector3(-wt, n * rise, -wt), Vector3(wt, n * rise, -wt), Vector3(wt, n * rise, wt), Vector3(-wt, n * rise, wt), Vector3.UP, _c(tint[0]), Vector2(wt * 2.0, wt * 2.0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit(stone_material())
	root.add_child(mi)
	if cased:
		var cs := _Quads.new()
		for side in 4:
			var a := -hw
			while a < hw:
				var b := a + rng.randf_range(1.6, 2.6)
				var k0 := case_from + rng.randi_range(0, 3)
				for k in range(k0, n):
					var w0 := hw - k * run + 0.04
					var w1 := w0 - run
					var y0 := (k + 1) * rise
					var y1 := y0 + rise
					var lo0 := maxf(a, -w0)
					var hi0 := minf(b, w0)
					var lo1 := maxf(a, -w1)
					var hi1 := minf(b, w1)
					if hi0 <= lo0 or hi1 <= lo1:
						continue
					var col := _shade(LIMESTONE, rng, 0.04)
					col.a = POLISHED
					cs.slant(side, w0, w1, lo0, hi0, lo1, hi1, y0, y1, rise, run, col)
				a = b
		var cmi := MeshInstance3D.new()
		cmi.mesh = cs.commit(stone_material())
		root.add_child(cmi)
		# a gilded capstone on the summit (you can walk round it)
		var gb := MeshBuilder.new()
		gb.add(MeshBuilder.cone(1.1, 1.5, 4), Transform3D(Basis(Vector3.UP, PI / 4), Vector3(0, n * rise + 0.75, 0)), Color(1, 0.9, 0.6))
		var gm := MeshInstance3D.new()
		gm.mesh = gb.commit(gold_material())
		root.add_child(gm)
		var cap := StaticBody3D.new()
		cap.add_child(_shape_node(_cyl_col(0.6, 1.4, Vector3(0, n * rise, 0))))
		root.add_child(cap)
	else:
		# a broken-off top: a few blocks of the next course still sitting on the summit
		var mb := MeshBuilder.new()
		var body := StaticBody3D.new()
		for k in rng.randi_range(3, 5):
			var at := Vector3(rng.randf_range(-wt * 0.6, wt * 0.6), n * rise + 0.25, rng.randf_range(-wt * 0.6, wt * 0.6))
			var sz := Vector3(rng.randf_range(0.8, 1.3), 0.5, rng.randf_range(0.7, 1.1))
			var bs := Basis(Vector3.UP, rng.randf_range(-0.2, 0.2))
			mb.add(MeshBuilder.box(sz), Transform3D(bs, at), _shade(SANDSTONE, rng, 0.08))
			body.add_child(_shape_node(_box_col(sz, at, bs)))
		var bm := MeshInstance3D.new()
		bm.mesh = mb.commit(stone_material())
		root.add_child(bm)
		root.add_child(body)
	_pyramid_door(root, hw, run, rise, door_k0, face)
	# a few fallen blocks lie about its feet
	var fb := MeshBuilder.new()
	var fbody := StaticBody3D.new()
	for k in int(hw * 0.5):
		var f := rng.randi() % 4
		var along := rng.randf_range(-hw, hw)
		var out := hw + rng.randf_range(0.8, 5.0)
		var lp := Vector3(out, 0, along) if f == 0 else (Vector3(-out, 0, along) if f == 1 else (Vector3(along, 0, out) if f == 2 else Vector3(along, 0, -out)))
		var gy := SwampWater.height_at(c.x + lp.x, c.y + lp.z) - base
		var sz := Vector3(rng.randf_range(0.9, 1.5), rng.randf_range(0.45, 0.6), rng.randf_range(0.7, 1.1))
		var bs := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.25, 0.25))
		lp.y = gy + sz.y * 0.3
		fb.add(MeshBuilder.box(sz), Transform3D(bs, lp), _shade(SANDSTONE, rng, 0.1))
		if k % 2 == 0:
			fbody.add_child(_shape_node(_box_col(sz, lp, bs)))
	var fmi := MeshInstance3D.new()
	fmi.mesh = fb.commit(stone_material())
	root.add_child(fmi)
	root.add_child(fbody)
	root.set_meta("summit", Vector3(c.x, base + n * rise, c.y))
	return root


static func _shape_node(c: Array) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = c[0]
	cs.transform = c[1]
	return cs


## The gabled entrance on face `face`, at course `k0`: a dark passage framed by jambs, a carved
## lintel and two great leaning slabs.
static func _pyramid_door(root: Node3D, hw: float, run: float, rise: float, k0: int, face: int) -> void:
	var w := hw - k0 * run   # the face's distance out at the door's foot
	var y := k0 * rise
	var out := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][face] as Vector3
	var basis := Basis.looking_at(-out, Vector3.UP)   # local -Z = into the pyramid... so +Z = out
	var o := out * (w + 0.1) + Vector3(0, y, 0)
	var mb := MeshBuilder.new()
	var stone := _c(LIMESTONE.darkened(0.08))
	var xf := func(p: Vector3, b: Basis) -> Transform3D: return Transform3D(basis * b, o + basis * p)
	for s in [-1.0, 1.0]:   # jambs
		mb.add(MeshBuilder.box(Vector3(0.7, 2.9, 1.2)), xf.call(Vector3(s * 1.45, 1.45, 0.2), Basis()), stone)
	mb.add(MeshBuilder.box(Vector3(3.8, 0.8, 1.3)), xf.call(Vector3(0, 3.3, 0.25), Basis()), _c(LIMESTONE, GLYPH))   # lintel
	for s in [-1.0, 1.0]:   # the gable: two slabs leaning together
		mb.add(MeshBuilder.box(Vector3(2.6, 0.7, 1.4)), xf.call(Vector3(s * 0.95, 4.35, 0.15), Basis(Vector3(0, 0, 1), -s * 0.62)), stone)
	mb.add(MeshBuilder.box(Vector3(1.0, 0.25, 1.0)), xf.call(Vector3(0, 0.12, 0.6), Basis()), stone)   # threshold
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(stone_material())
	root.add_child(mi)
	var dark := MeshInstance3D.new()
	var q := BoxMesh.new()
	q.size = Vector3(2.2, 2.7, 1.6)
	q.material = void_material()
	dark.mesh = q
	dark.transform = xf.call(Vector3(0, 1.4, -0.35), Basis())
	root.add_child(dark)


## Quads with UVs and their size (UV2) for the stone shader's joints.
class _Quads:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color, size: Vector2) -> void:
		var s := v.size()
		for p in [a, b, c, d]:
			v.append(p)
			nrm.append(n)
			col.append(color)
			uv2.append(size)
		uv.append(Vector2(0, 1)); uv.append(Vector2(1, 1)); uv.append(Vector2(1, 0)); uv.append(Vector2(0, 0))
		idx.append(s); idx.append(s + 1); idx.append(s + 2)
		idx.append(s); idx.append(s + 2); idx.append(s + 3)

	## Map (out, along, y) on side `side` (0 +x, 1 -x, 2 +z, 3 -z) to a local point.
	static func pt(side: int, out: float, along: float, y: float) -> Vector3:
		match side:
			0: return Vector3(out, y, along)
			1: return Vector3(-out, y, -along)
			2: return Vector3(-along, y, out)
		return Vector3(along, y, -out)

	static func outward(side: int) -> Vector3:
		return [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][side]

	## One block of a course: its face (out at `o`), its tread (from `o` back to `inner`) and
	## both ends, spanning [a, b] along the side and [y0, y1] up.
	func block(side: int, o: float, inner: float, a: float, b: float, y0: float, y1: float, color: Color) -> void:
		var n := outward(side)
		var lw := b - a
		quad(pt(side, o, a, y0), pt(side, o, b, y0), pt(side, o, b, y1), pt(side, o, a, y1), n, color, Vector2(lw, y1 - y0))
		quad(pt(side, o, a, y1), pt(side, o, b, y1), pt(side, inner, b, y1), pt(side, inner, a, y1), Vector3.UP, color, Vector2(lw, o - inner))
		var t := (pt(side, 0, 1, 0) - pt(side, 0, 0, 0)).normalized()
		quad(pt(side, inner, a, y0), pt(side, o, a, y0), pt(side, o, a, y1), pt(side, inner, a, y1), -t, color, Vector2(o - inner, y1 - y0))
		quad(pt(side, o, b, y0), pt(side, inner, b, y0), pt(side, inner, b, y1), pt(side, o, b, y1), t, color, Vector2(o - inner, y1 - y0))

	## A slanted casing stone from (w0 at y0) up to (w1 at y1).
	func slant(side: int, w0: float, w1: float, lo0: float, hi0: float, lo1: float, hi1: float, y0: float, y1: float, rise: float, run: float, color: Color) -> void:
		var n := (outward(side) * rise + Vector3.UP * run).normalized()
		quad(pt(side, w0, lo0, y0), pt(side, w0, hi0, y0), pt(side, w1, hi1, y1), pt(side, w1, lo1, y1), n, color, Vector2(hi0 - lo0, 1.2))

	func commit(mat: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mat)
		return mesh


# ------------------------------------------------------------------ trees

static func _cached(key: String, rng: RandomNumberGenerator, shapes: int, make: Callable) -> Dictionary:
	var k := "%s_%d" % [key, rng.randi() % shapes]
	if not _cache.has(k):
		var r2 := RandomNumberGenerator.new()
		r2.seed = hash(k)
		_cache[k] = make.call(r2)
	return _cache[k]


static func clear_cache() -> void:
	_cache.clear()


## A ribbon of quads along `pts` (a palm frond's blade, a leaf): `widths` either side of the
## spine across `side`, with a saw-tooth edge for leaflets when `teeth`.
static func _ribbon(mb: MeshBuilder, pts: Array, widths: Array, side: Vector3, color: Color, color_tip: Color, teeth := true) -> void:
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var idx := PackedInt32Array()
	var cols: Array[Color] = []
	for k in pts.size():
		var p: Vector3 = pts[k]
		var w: float = widths[k] * (1.0 if not teeth or k % 2 == 0 else 0.55)
		var fwd: Vector3 = ((pts[mini(k + 1, pts.size() - 1)] as Vector3) - (pts[maxi(k - 1, 0)] as Vector3)).normalized()
		var up := fwd.cross(side).normalized()
		var droop := up * w * 0.35   # the leaflets fold down a little either side
		v.append(p - side * w - droop)
		v.append(p)
		v.append(p + side * w - droop)
		for q in 3:
			nm.append(up)
		var t := float(k) / maxf(1.0, pts.size() - 1)
		cols.append(color.lerp(color_tip, t))
	for k in pts.size() - 1:
		var a := k * 3
		var b := a + 3
		for tri in [[a, a + 1, b + 1], [a, b + 1, b], [a + 1, a + 2, b + 2], [a + 1, b + 2, b + 1]]:
			for q in tri:
				idx.append(q)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nm
	arrays[Mesh.ARRAY_INDEX] = idx
	# MeshBuilder.add colours a part with one colour; colour each slice of the ribbon instead
	var base := mb._verts.size()
	mb.add(arrays, Transform3D(), color)
	for k in pts.size():
		for q in 3:
			mb._cols[base + k * 3 + q] = cols[k]


## Palms: 0 a tall date palm at an oasis (with clusters of dates), 1 a leaning date palm, 2 a
## forked doum palm with fan-shaped crowns.
static func palm(rng: RandomNumberGenerator, variant: int) -> Dictionary:
	return _cached("palm%d" % variant, rng, 3, func(r: RandomNumberGenerator) -> Dictionary: return _grow_palm(r, variant))   # no-i18n


static func _grow_palm(rng: RandomNumberGenerator, variant: int) -> Dictionary:
	var mb := MeshBuilder.new()
	var h := rng.randf_range(9.0, 13.0) if variant == 0 else rng.randf_range(7.0, 10.0)
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * (rng.randf_range(0.6, 1.4) if variant == 0 else rng.randf_range(2.0, 3.5))
	var tops: Array[Vector3] = []
	if variant == 2:   # doum: a short trunk forking into two or three
		var fork := Vector3(lean.x * 0.2, h * 0.4, lean.z * 0.2)
		_palm_trunk(mb, rng, Vector3.ZERO, fork, 0.32)
		for k in rng.randi_range(2, 3):
			var a := rng.randf() * TAU
			var top := fork + Vector3(cos(a) * 2.2, h * 0.45, sin(a) * 2.2)
			_palm_trunk(mb, rng, fork, top, 0.24)
			tops.append(top)
	else:
		var top := Vector3(lean.x, h, lean.z)
		_palm_trunk(mb, rng, Vector3.ZERO, top, 0.34)
		tops.append(top)
	for top in tops:
		var nf := rng.randi_range(14, 18) if variant != 2 else 12
		for k in nf:
			var a := TAU * k / nf + rng.randf_range(-0.15, 0.15)
			var lift := rng.randf_range(-0.1, 0.9) if k % 3 else rng.randf_range(-0.9, -0.3)   # some fronds hang dead
			var dead := lift < -0.2
			var length := rng.randf_range(3.2, 4.6) if variant != 2 else rng.randf_range(2.2, 3.0)
			var dir := Vector3(cos(a), 0, sin(a))
			var side := Vector3(-dir.z, 0, dir.x)
			var pts: Array = []
			var wd: Array = []
			for s in 9:
				var t := s / 8.0
				pts.append(top + dir * length * t + Vector3(0, lift * length * t - length * 0.55 * t * t, 0))
				wd.append((0.08 + 0.5 * sin(t * PI * 0.92)) * (1.4 if variant == 2 else 1.0))
			_ribbon(mb, pts, wd, side, _c(FROND_DRY if dead else FROND, 0.3 if dead else 0.5), _c((FROND_DRY if dead else FROND).lightened(0.15), 1.0), variant != 2)
		# leaf bases and a crown knob, dates hanging below the fronds
		mb.add(MeshBuilder.sphere(0.5, 8, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.0)), top), _c(PALM_TRUNK.darkened(0.2)))
		if variant == 0:
			for k in 4:
				var a := rng.randf() * TAU
				var at := top + Vector3(cos(a) * 0.5, -0.6, sin(a) * 0.5)
				mb.add(MeshBuilder.sphere(0.28, 6, 4), Transform3D(Basis.from_scale(Vector3(1.0, 1.5, 1.0)), at), _c(Color(0.75, 0.42, 0.12), 0.2))
	return {"mesh": mb.commit(), "colliders": [_cyl_col(0.38, h * 0.8)], "length": 2.0}


static func _palm_trunk(mb: MeshBuilder, rng: RandomNumberGenerator, a: Vector3, b: Vector3, r: float) -> void:
	# A slightly curving trunk made of stacked leaf-base rings (the diamond-scarred bark)
	var segs := int((b - a).length() / 0.42)
	var bend := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
	var prev := a
	for s in segs:
		var t := float(s + 1) / segs
		var p := a.lerp(b, t) + bend * sin(t * PI)
		var rr := r * (1.15 - 0.3 * t)
		var col := PALM_TRUNK.lightened(0.08) if s % 2 == 0 else PALM_TRUNK.darkened(0.1)
		mb.limb(prev, p, rr * 1.06, rr, _c(col), 8)
		mb.add(MeshBuilder.cyl(rr * 1.18, rr * 1.04, 0.1, 8), Transform3D(Basis(), prev + (p - prev) * 0.15), _c(PALM_TRUNK.darkened(0.25)))
		prev = p


## An umbrella-thorn acacia: a forked, twisting trunk and a broad, flat-topped crown.
static func acacia(rng: RandomNumberGenerator) -> Dictionary:
	return _cached("acacia", rng, 4, func(r: RandomNumberGenerator) -> Dictionary: return _grow_acacia(r))


static func _grow_acacia(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var bark := Color(0.32, 0.26, 0.2, 0.0)
	var h := rng.randf_range(5.0, 7.0)
	var fork := Vector3(rng.randf_range(-0.4, 0.4), h * 0.4, rng.randf_range(-0.4, 0.4))
	mb.limb(Vector3.ZERO, fork, 0.32, 0.24, bark, 8)
	var crown_y := h
	var spread := rng.randf_range(4.0, 5.5)
	for k in rng.randi_range(3, 4):
		var a := TAU * k / 3.5 + rng.randf_range(-0.4, 0.4)
		var mid := fork + Vector3(cos(a) * spread * 0.4, h * 0.3, sin(a) * spread * 0.4)
		var tip := Vector3(cos(a) * spread * 0.8, crown_y - 0.2, sin(a) * spread * 0.8)
		mb.limb(fork, mid, 0.2, 0.14, bark, 6)
		mb.limb(mid, tip, 0.14, 0.06, bark, 5)
		for t in 3:
			var ta := a + rng.randf_range(-1.0, 1.0)
			mb.limb(mid, mid + Vector3(cos(ta) * 1.6, rng.randf_range(0.6, 1.2), sin(ta) * 1.6), 0.08, 0.03, bark, 4)
	# the flat crown: overlapping squashed clumps, darker underneath
	for k in 16:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * spread
		var rr := rng.randf_range(1.2, 2.0)
		var y := crown_y + rng.randf_range(-0.2, 0.35)
		mb.add(ForestProps._lumpy(rr, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.28, 1.0)), Vector3(cos(a) * d, y, sin(a) * d)), _shade(Color(0.36, 0.42, 0.16, 0.45), rng, 0.12))
		mb.add(ForestProps._lumpy(rr * 0.9, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.18, 1.0)), Vector3(cos(a) * d, y - 0.22, sin(a) * d)), _shade(Color(0.22, 0.26, 0.1, 0.4), rng, 0.1))
	return {"mesh": mb.commit(), "colliders": [_cyl_col(0.32, h * 0.6)], "length": 2.0}


## A dead tree bleached silver by the sun: a split trunk and bare, twisting branches.
static func dead_tree(rng: RandomNumberGenerator) -> Dictionary:
	return _cached("dead", rng, 4, func(r: RandomNumberGenerator) -> Dictionary: return _grow_dead(r))


static func _grow_dead(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var wood := Color(0.72, 0.68, 0.6, 0.0)
	var h := rng.randf_range(3.5, 6.0)
	var top := Vector3(rng.randf_range(-0.6, 0.6), h, rng.randf_range(-0.6, 0.6))
	mb.limb(Vector3.ZERO, top * 0.5, 0.3, 0.22, wood.darkened(0.1), 7)
	TreeDetail.bark(mb, rng, Vector3.ZERO, top * 0.5, 0.3, 0.22, wood.darkened(0.1), 5, false)
	mb.limb(top * 0.5, top, 0.22, 0.08, wood, 6)
	for k in rng.randi_range(4, 7):
		var from := top * rng.randf_range(0.35, 0.9)
		var a := rng.randf() * TAU
		var to := from + Vector3(cos(a) * rng.randf_range(1.2, 2.6), rng.randf_range(0.5, 1.8), sin(a) * rng.randf_range(1.2, 2.6))
		mb.limb(from, to, 0.1, 0.03, wood, 5)
		mb.limb(to, to + Vector3(cos(a + 0.8) * 0.8, 0.6, sin(a + 0.8) * 0.8), 0.04, 0.01, wood, 4)
	for k in 4:   # roots clawing out of the sand
		var a := TAU * k / 4.0 + rng.randf()
		mb.limb(Vector3(0, 0.2, 0), Vector3(cos(a) * 1.4, -0.15, sin(a) * 1.4), 0.14, 0.04, wood.darkened(0.15), 5)
	return {"mesh": mb.commit(), "colliders": [_cyl_col(0.28, h * 0.7)], "length": 2.0}


# ------------------------------------------------------------------ rocks

## A heap of wind-rounded boulders.
static func boulders(rng: RandomNumberGenerator) -> Dictionary:
	return _cached("boulders", rng, 5, func(r: RandomNumberGenerator) -> Dictionary:
		var mb := MeshBuilder.new()
		var big := r.randf_range(1.2, 2.2)
		var cols: Array = []
		for k in r.randi_range(3, 6):
			var rr := big * (1.0 if k == 0 else r.randf_range(0.35, 0.75))
			var a := r.randf() * TAU
			var d := 0.0 if k == 0 else big * r.randf_range(0.8, 1.4)
			var at := Vector3(cos(a) * d, rr * 0.55, sin(a) * d)
			mb.add(ForestProps._lumpy(rr, r), Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1.0, r.randf_range(0.6, 0.85), r.randf_range(0.8, 1.1))), at), _shade(Color(0.66, 0.5, 0.38, 0.0), r, 0.12))
			if k < 2:
				var s := SphereShape3D.new()
				s.radius = rr * 0.8
				cols.append([s, Transform3D(Basis(), at)])
		return _stone(mb, cols, {"length": big * 2.0}))


## A wind-carved rock pillar: layers of red and buff sandstone, narrower at the waist.
static func rock_pillar(rng: RandomNumberGenerator) -> Dictionary:
	return _cached("pillar", rng, 4, func(r: RandomNumberGenerator) -> Dictionary:
		var mb := MeshBuilder.new()
		var y := 0.0
		var h := r.randf_range(5.0, 9.0)
		var layers := r.randi_range(6, 9)
		for k in layers:
			var t := float(k) / layers
			var lh := h / layers
			var rr := 1.6 * (1.0 - 0.45 * sin(t * PI * 0.9)) + (0.5 if k == layers - 1 else 0.0)
			var col := Color(0.72, 0.46, 0.32, 0.0) if k % 2 == 0 else Color(0.82, 0.64, 0.46, 0.0)
			mb.add(ForestProps._lumpy(rr, r), Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1.0, lh / (rr * 1.6), 1.0)), Vector3(r.randf_range(-0.15, 0.15), y + lh * 0.5, r.randf_range(-0.15, 0.15))), _shade(col, r, 0.08))
			y += lh * 0.92
		return _stone(mb, [_cyl_col(1.2, h)], {"length": 3.0}))


# ------------------------------------------------------------------ lying props

## A toppled column: fluted drums rolled apart in a line, a papyrus-bundle capital at the end.
static func fallen_column(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var r := rng.randf_range(0.65, 0.9)
	var x := 0.0
	var cols: Array = []
	var drums := rng.randi_range(3, 5)
	for k in drums:
		var dl := rng.randf_range(1.0, 1.6)
		var basis := Basis(Vector3(0, 0, 1), PI / 2) * Basis(Vector3.UP, rng.randf())
		var at := Vector3(x + dl * 0.5, r * 0.85, rng.randf_range(-0.3, 0.3))
		mb.add(MeshBuilder.cyl(r, r, dl, 16), Transform3D(basis, at), _c(_shade(SANDSTONE, rng, 0.06), GLYPH if k % 2 == 0 else 0.0))
		for f in 8:   # flutes
			var a := TAU * f / 8.0
			mb.add(MeshBuilder.box(Vector3(dl * 0.98, 0.06, 0.06)), Transform3D(Basis(Vector3(1, 0, 0), a), at + Vector3(0, cos(a), sin(a)) * r * 0.98), _c(SANDSTONE.darkened(0.25)))
		x += dl + rng.randf_range(0.05, 0.5)
	# the capital: a flared bundle
	var cap := Vector3(x + 0.6, r * 1.1, 0)
	mb.add(MeshBuilder.cyl(r * 1.6, r, 1.2, 16), Transform3D(Basis(Vector3(0, 0, 1), PI / 2), cap), _c(_shade(SANDSTONE, rng, 0.05)))
	mb.add(MeshBuilder.box(Vector3(0.3, r * 3.4, r * 3.4)), Transform3D(Basis(), cap + Vector3(0.7, 0, 0)), _c(SANDSTONE.darkened(0.05)))
	var length := x + 1.4
	cols.append(_box_col(Vector3(length, r * 1.6, r * 1.8), Vector3(length * 0.5, r * 0.8, 0)))
	var data := _stone(mb, cols, {"length": length, "sink": 0.35})
	# re-centre on the middle
	return _recentre(data, Vector3(-length * 0.5, 0, 0))


static func _recentre(data: Dictionary, off: Vector3) -> Dictionary:
	var mesh: ArrayMesh = data["mesh"]
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for k in v.size():
			v[k] += off
		arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, mesh.surface_get_material(s))
	data["mesh"] = out
	for c in data["colliders"]:
		var t: Transform3D = c[1]
		t.origin += off
		c[1] = t
	return data


## A colossal stone head in a nemes headdress, half swallowed by the sand and tipped on its side.
static func buried_head(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var s := rng.randf_range(0.7, 1.0)
	var tilt := Basis(Vector3(0, 0, 1), rng.randf_range(-0.5, 0.5)) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.25, 0.1))
	DesertSphinx.head(mb, Transform3D(tilt.scaled(Vector3.ONE * s * 1.5), Vector3(0, 1.3 * s, 0)), _shade(SANDSTONE.lightened(0.05), rng, 0.08), rng, rng.randf() < 0.6)
	return _stone(mb, [_box_col(Vector3(4.6, 3.6, 4.0) * s, Vector3(0, 1.8 * s, 0))], {"length": 4.6 * s, "sink": 1.1})


## The bleached skeleton of a camel: skull, spine, ribs, legs scattered, half in the sand.
static func camel_skeleton(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var b := _c(BONE)
	var spine: Array[Vector3] = []
	for k in 16:
		var t := k / 15.0
		spine.append(Vector3(-1.4 + t * 2.8, 0.25 + sin(t * PI) * 0.35, sin(t * 3.0) * 0.12))
	for k in spine.size():
		mb.add(MeshBuilder.sphere(0.07, 6, 4), Transform3D(Basis(), spine[k]), b)
		if k > 0:
			mb.limb(spine[k - 1], spine[k], 0.035, 0.035, b, 4)
	# neck and skull
	var neck := spine[15]
	var head := neck + Vector3(0.9, -0.15, 0.3)
	mb.limb(neck, head, 0.05, 0.04, b, 5)
	mb.add(MeshBuilder.sphere(0.18, 8, 5), Transform3D(Basis.from_scale(Vector3(1.9, 0.75, 0.8)), head + Vector3(0.18, 0, 0)), b)
	mb.add(MeshBuilder.sphere(0.05, 6, 4), Transform3D(Basis(), head + Vector3(0.12, 0.08, 0.1)), _c(Color(0.15, 0.12, 0.1)))
	# ribs: curved arcs either side
	for k in range(3, 12):
		for sd in [-1.0, 1.0]:
			var p0 := spine[k]
			var p1 := p0 + Vector3(0, -0.18, sd * 0.32)
			var p2 := p0 + Vector3(0.05, -0.42, sd * 0.38)
			mb.limb(p0, p1, 0.02, 0.018, b, 4)
			mb.limb(p1, p2, 0.018, 0.012, b, 4)
	# legs flung out
	for k in 4:
		var hip := spine[2 if k < 2 else 12]
		var a := rng.randf_range(-0.6, 0.6) + (0.0 if k % 2 == 0 else PI)
		var knee := hip + Vector3(rng.randf_range(-0.4, 0.4), -0.2, cos(a) * 0.9)
		mb.limb(hip, knee, 0.04, 0.035, b, 5)
		mb.limb(knee, knee + Vector3(rng.randf_range(-0.6, 0.6), -0.05, cos(a) * 0.8), 0.035, 0.03, b, 5)
	return _stone(mb, [], {"length": 3.4, "sink": 0.12})


## A crumbling run of mud-brick wall, its top eaten away, sand banked against one side.
static func mud_wall(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var length := rng.randf_range(4.0, 8.0)
	var brick := Vector3(0.42, 0.16, 0.3)
	var rows := rng.randi_range(8, 14)
	for row in rows:
		var x := -length * 0.5 + (brick.x * 0.5 if row % 2 else 0.0)
		while x < length * 0.5:
			# the top is ragged: higher rows lose bricks toward a broken edge
			var keep := 1.0 - float(row) / rows * (0.6 + 0.4 * absf(sin(x * 0.7 + row)))
			if rng.randf() < keep:
				for t in 2:
					mb.add(MeshBuilder.box(brick * Vector3(0.96, 0.92, 0.96)), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.04, 0.04)), Vector3(x, row * brick.y + brick.y * 0.5, (t - 0.5) * brick.z)), _shade(Color(0.6, 0.45, 0.32, 0.0), rng, 0.1))
			x += brick.x
	var h := rows * brick.y
	return _stone(mb, [_box_col(Vector3(length, h, brick.z * 2.0), Vector3(0, h * 0.5, 0))], {"length": length, "sink": 0.3})


## A granite sarcophagus, its lid slid askew, carved all over.
static func sarcophagus(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var col := _c(_shade(GRANITE, rng, 0.08), GLYPH)
	mb.add(MeshBuilder.box(Vector3(2.6, 1.1, 1.2)), Transform3D(Basis(), Vector3(0, 0.55, 0)), col)
	mb.add(MeshBuilder.box(Vector3(2.4, 0.2, 1.0)), Transform3D(Basis(), Vector3(0, 1.08, 0)), _c(Color(0.05, 0.04, 0.04)))   # dark inside
	var lid := Transform3D(Basis(Vector3.UP, rng.randf_range(0.2, 0.5)) * Basis(Vector3(1, 0, 0), rng.randf_range(0.05, 0.2)), Vector3(rng.randf_range(0.3, 0.8), 1.25, rng.randf_range(0.3, 0.6)))
	mb.add(MeshBuilder.box(Vector3(2.7, 0.25, 1.3)), lid, col)
	# the lid's carved face and a gilded mask
	mb.add(MeshBuilder.sphere(0.32, 8, 5), lid * Transform3D(Basis.from_scale(Vector3(0.8, 0.5, 1.0)), Vector3(1.0, 0.18, 0)), _c(GRANITE.lightened(0.2)))
	gb.add(MeshBuilder.sphere(0.22, 8, 5), lid * Transform3D(Basis.from_scale(Vector3(0.7, 0.5, 0.9)), Vector3(1.05, 0.27, 0)), Color(1, 0.85, 0.5))
	return _stone(mb, [_box_col(Vector3(2.6, 1.3, 1.2), Vector3(0, 0.65, 0))], {"length": 2.8, "sink": 0.2}, gb)


## A fallen obelisk snapped in two, its pyramidion tip half buried.
static func fallen_obelisk(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var w := rng.randf_range(0.9, 1.2)
	var l1 := rng.randf_range(4.0, 6.0)
	var l2 := rng.randf_range(2.5, 4.0)
	var col := _c(_shade(GRANITE.lightened(0.15), rng, 0.06), GLYPH)
	mb.add(MeshBuilder.box(Vector3(l1, w, w)), Transform3D(Basis(Vector3.UP, 0.05), Vector3(-l1 * 0.5, w * 0.5, 0)), col)
	var b2 := Basis(Vector3.UP, rng.randf_range(0.15, 0.4)) * Basis(Vector3(0, 0, 1), 0.08)
	mb.add(MeshBuilder.box(Vector3(l2, w * 0.85, w * 0.85)), Transform3D(b2, Vector3(l2 * 0.5 + 0.4, w * 0.45, 0.3)), col)
	gb.add(MeshBuilder.cone(w * 0.6, w, 4), Transform3D(b2 * Basis(Vector3(0, 0, 1), -PI / 2) * Basis(Vector3.UP, PI / 4), b2 * Vector3(l2 + 0.5, 0, 0) + Vector3(0.4, w * 0.4, 0.3)), Color(1, 0.88, 0.55))
	return _stone(mb, [_box_col(Vector3(l1 + l2, w, w * 1.6), Vector3(0, w * 0.5, 0))], {"length": l1 + l2, "sink": 0.25}, gb)


# ------------------------------------------------------------------ landmarks

## Landmarks, in turn: a standing obelisk, a seated colossus, a temple pylon, a broken
## colonnade, and an avenue of ram-headed sphinxes.
static func landmark(rng: RandomNumberGenerator, kind: int) -> Dictionary:
	match kind % 5:
		0: return _obelisk(rng)
		1: return _colossus(rng)
		2: return _pylon(rng)
		3: return _colonnade(rng)
	return _ram_avenue(rng)


static func _obelisk(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var h := rng.randf_range(11.0, 15.0)
	var w := rng.randf_range(1.3, 1.6)
	mb.add(MeshBuilder.box(Vector3(w * 2.4, 0.8, w * 2.4)), Transform3D(Basis(), Vector3(0, 0.4, 0)), _c(SANDSTONE))
	mb.add(MeshBuilder.box(Vector3(w * 1.8, 0.6, w * 1.8)), Transform3D(Basis(), Vector3(0, 1.1, 0)), _c(SANDSTONE.lightened(0.05), GLYPH))
	# the shaft tapers: stacked frusta (square cylinders)
	var segs := 6
	for k in segs:
		var t0 := float(k) / segs
		var t1 := float(k + 1) / segs
		var r0 := w * (1.0 - 0.3 * t0) * 0.7071
		var r1 := w * (1.0 - 0.3 * t1) * 0.7071
		mb.add(MeshBuilder.cyl(r1, r0, h / segs, 4), Transform3D(Basis(Vector3.UP, PI / 4), Vector3(0, 1.4 + h * (t0 + t1) * 0.5, 0)), _c(_shade(GRANITE.lightened(0.2), rng, 0.03), GLYPH))
	gb.add(MeshBuilder.cone(w * 0.7 * 0.7071 * 1.0, w * 0.8, 4), Transform3D(Basis(Vector3.UP, PI / 4), Vector3(0, 1.4 + h + w * 0.4, 0)), Color(1, 0.88, 0.55))
	return _stone(mb, [_box_col(Vector3(w * 2.4, 1.4, w * 2.4), Vector3(0, 0.7, 0)), _box_col(Vector3(w, h, w), Vector3(0, 1.4 + h * 0.5, 0))], {}, gb)


## A pharaoh enthroned, hands on knees, gazing over the sand; one is missing its face.
static func _colossus(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var st := _c(_shade(SANDSTONE.darkened(0.05), rng, 0.05))
	var gl := _c(st, GLYPH)
	mb.add(MeshBuilder.box(Vector3(4.0, 1.0, 5.0)), Transform3D(Basis(), Vector3(0, 0.5, 0)), gl)   # base
	mb.add(MeshBuilder.box(Vector3(3.4, 3.0, 3.2)), Transform3D(Basis(), Vector3(0, 2.5, -0.6)), gl)   # throne
	mb.add(MeshBuilder.box(Vector3(3.4, 4.2, 0.8)), Transform3D(Basis(), Vector3(0, 4.6, -1.9)), gl)   # back pillar
	# legs: thighs forward, shins down, feet
	for sd in [-0.7, 0.7]:
		mb.add(MeshBuilder.box(Vector3(1.1, 1.0, 2.6)), Transform3D(Basis(), Vector3(sd, 4.4, 0.2)), st)
		mb.add(MeshBuilder.box(Vector3(1.0, 3.2, 1.0)), Transform3D(Basis(), Vector3(sd, 2.6, 1.3)), st)
		mb.add(MeshBuilder.box(Vector3(1.0, 0.5, 1.6)), Transform3D(Basis(), Vector3(sd, 1.25, 1.6)), st)
		# arm resting on the knee
		mb.add(MeshBuilder.box(Vector3(0.75, 2.2, 0.8)), Transform3D(Basis(), Vector3(sd * 2.0, 5.8, -0.6)), st)
		mb.add(MeshBuilder.box(Vector3(0.7, 0.6, 2.2)), Transform3D(Basis(), Vector3(sd * 1.9, 4.95, 0.4)), st)
	mb.add(MeshBuilder.box(Vector3(3.0, 3.0, 1.6)), Transform3D(Basis(), Vector3(0, 6.3, -0.8)), st)   # torso
	mb.add(MeshBuilder.box(Vector3(2.4, 1.4, 1.8)), Transform3D(Basis(), Vector3(0, 4.9, -0.4)), st)   # kilt
	DesertSphinx.head(mb, Transform3D(Basis.from_scale(Vector3.ONE * 0.42), Vector3(0, 8.6, -0.7)), st, rng, rng.randf() < 0.5)
	return _stone(mb, [_box_col(Vector3(4.0, 7.5, 5.0), Vector3(0, 3.75, 0))])


## A temple gateway: two battered towers carved with reliefs, a lintel over the gap.
static func _pylon(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var st := _c(_shade(SANDSTONE, rng, 0.05), GLYPH)
	var h := rng.randf_range(8.0, 10.0)
	var cols: Array = []
	for sd in [-1.0, 1.0]:
		var at := Vector3(sd * 4.2, h * 0.5, 0)
		# battered (sloping) walls: a 4-sided frustum
		mb.add(MeshBuilder.cyl(2.6, 3.6, h, 4), Transform3D(Basis(Vector3.UP, PI / 4).scaled(Vector3(1.25, 1.0, 0.55)), at), st)
		mb.add(MeshBuilder.box(Vector3(4.7, 0.5, 2.3)), Transform3D(Basis(), Vector3(sd * 4.2, h + 0.25, 0)), _c(SANDSTONE.darkened(0.08)))   # cornice
		var broken: bool = rng.randf() < 0.5 and sd > 0
		if broken:   # a chunk of the cornice fallen at its foot
			mb.add(MeshBuilder.box(Vector3(1.6, 0.6, 1.2)), Transform3D(Basis(Vector3.UP, 0.6), Vector3(sd * 5.5, 0.3, 2.2)), _c(SANDSTONE))
		cols.append(_box_col(Vector3(4.6, h, 2.6), at))
	mb.add(MeshBuilder.box(Vector3(3.0, h * 0.7, 1.6)), Transform3D(Basis(), Vector3(0, h * 0.35, -0.4)), _c(SANDSTONE.darkened(0.04), GLYPH))   # gate jambs (back)
	mb.add(MeshBuilder.box(Vector3(2.0, h * 0.62, 1.7)), Transform3D(Basis(), Vector3(0, h * 0.31, -0.35)), _c(Color(0.06, 0.05, 0.04)))   # the dark gateway
	mb.add(MeshBuilder.box(Vector3(4.2, 1.0, 2.0)), Transform3D(Basis(), Vector3(0, h * 0.68, 0)), st)   # lintel
	mb.add(MeshBuilder.sphere(0.7, 10, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 0.25)), Vector3(0, h * 0.68, 1.0)), _c(Color(0.75, 0.55, 0.25)))   # winged sun disc
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.box(Vector3(1.4, 0.3, 0.1)), Transform3D(Basis(Vector3(0, 0, 1), sd * 0.15), Vector3(sd * 1.2, h * 0.68 + 0.1, 1.0)), _c(Color(0.3, 0.42, 0.6)))
	return _stone(mb, cols)


## A broken colonnade: two rows of papyrus columns, an architrave across some, others fallen.
static func _colonnade(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var cols: Array = []
	var h := rng.randf_range(6.0, 7.5)
	mb.add(MeshBuilder.box(Vector3(9.0, 0.5, 6.0)), Transform3D(Basis(), Vector3(0, 0.25, 0)), _c(SANDSTONE.darkened(0.08)))
	for row in [-1.0, 1.0]:
		for k in 4:
			var at := Vector3(-3.6 + k * 2.4, 0.5, row * 2.2)
			var standing := rng.randf() < 0.75
			var ch := h * (1.0 if standing else rng.randf_range(0.3, 0.6))
			mb.add(MeshBuilder.cyl(0.55, 0.65, ch, 14), Transform3D(Basis(), at + Vector3(0, ch * 0.5, 0)), _c(_shade(SANDSTONE, rng, 0.05), GLYPH))
			for b in 3:   # binding bands
				mb.add(MeshBuilder.cyl(0.6, 0.6, 0.12, 14), Transform3D(Basis(), at + Vector3(0, ch * (0.65 + b * 0.05), 0)), _c(Color(0.42, 0.5, 0.6)))
			if standing:
				mb.add(MeshBuilder.cyl(0.95, 0.55, 0.9, 14), Transform3D(Basis(), at + Vector3(0, ch + 0.45, 0)), _c(SANDSTONE))   # open papyrus capital
				mb.add(MeshBuilder.box(Vector3(1.3, 0.35, 1.3)), Transform3D(Basis(), at + Vector3(0, ch + 1.05, 0)), _c(SANDSTONE.darkened(0.05)))
			cols.append(_cyl_col(0.62, ch, at))
		mb.add(MeshBuilder.box(Vector3(5.6, 0.8, 1.2)), Transform3D(Basis(), Vector3(-1.2, 0.5 + h + 1.6, row * 2.2)), _c(SANDSTONE, GLYPH))   # architrave
	return _stone(mb, cols)


## An avenue of ram-headed sphinxes on plinths.
static func _ram_avenue(rng: RandomNumberGenerator) -> Dictionary:
	var mb := MeshBuilder.new()
	var cols: Array = []
	for k in 3:
		var at := Vector3(0, 0, -4.0 + k * 4.0)
		mb.add(MeshBuilder.box(Vector3(1.8, 1.0, 3.4)), Transform3D(Basis(), at + Vector3(0, 0.5, 0)), _c(SANDSTONE, GLYPH))
		var s := _c(_shade(SANDSTONE.darkened(0.04), rng, 0.05))
		mb.add(MeshBuilder.sphere(0.8, 10, 6), Transform3D(Basis.from_scale(Vector3(0.8, 0.7, 1.7)), at + Vector3(0, 1.6, -0.2)), s)   # body
		mb.add(MeshBuilder.sphere(0.6, 8, 5), Transform3D(Basis(), at + Vector3(0, 1.6, -1.2)), s)   # haunch
		for sd in [-0.4, 0.4]:
			mb.add(MeshBuilder.box(Vector3(0.35, 0.3, 1.4)), Transform3D(Basis(), at + Vector3(sd, 1.15, 1.0)), s)   # paws
		mb.add(MeshBuilder.sphere(0.45, 8, 5), Transform3D(Basis.from_scale(Vector3(0.8, 0.9, 1.3)), at + Vector3(0, 2.5, 1.1)), s)   # ram head
		for sd in [-1.0, 1.0]:   # curled horns
			for t in 5:
				var a := t * 1.1
				mb.add(MeshBuilder.sphere(0.13 - t * 0.015, 6, 4), Transform3D(Basis(), at + Vector3(sd * (0.35 + sin(a) * 0.15), 2.6 + cos(a) * 0.15, 1.0 - t * 0.04)), _c(SANDSTONE.darkened(0.15)))
		cols.append(_box_col(Vector3(1.8, 2.5, 3.4), at + Vector3(0, 1.25, 0)))
	return _stone(mb, cols)


## One ram-headed sphinx (a criosphinx) on its plinth, the causeway's guardians, facing +Z: a
## lion lying down with its forelegs stretched out, a ram's head with curled, ridged horns under a
## striped nemes, and a small pharaoh standing between its paws against its chest.
static func ram_statue() -> Dictionary:
	if _cache.has("ram"):
		return _cache["ram"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var mb := MeshBuilder.new()
	# the plinth (as before): carved sides and a cap
	mb.add(MeshBuilder.box(Vector3(1.8, 1.0, 3.4)), Transform3D(Basis(), Vector3(0, 0.5, 0)), _c(SANDSTONE, GLYPH))
	mb.add(MeshBuilder.box(Vector3(2.0, 0.15, 3.6)), Transform3D(Basis(), Vector3(0, 1.05, 0)), _c(SANDSTONE.darkened(0.1)))
	var y0 := 1.125
	var st := _c(_shade(SANDSTONE.lightened(0.04), rng, 0.04))
	var dk := _c(st.darkened(0.12))
	var sph := func(r: float, sc: Vector3, at: Vector3, c: Color, seg := 16) -> void:
		mb.add(MeshBuilder.sphere(r, seg, int(seg * 0.6)), Transform3D(Basis.from_scale(sc), at + Vector3(0, y0, 0)), c)
	var lim := func(a: Vector3, b: Vector3, ra: float, rb: float, c: Color) -> void:
		mb.limb(a + Vector3(0, y0, 0), b + Vector3(0, y0, 0), ra, rb, c, 12)
	# the lion's body lying down: torso, haunch, chest, the spine
	sph.call(1.0, Vector3(0.5, 0.42, 1.05), Vector3(0, 0.46, -0.35), st, 24)
	sph.call(1.0, Vector3(0.56, 0.5, 0.55), Vector3(0, 0.5, -1.1), st, 20)
	sph.call(1.0, Vector3(0.46, 0.56, 0.42), Vector3(0, 0.62, 0.55), st, 20)
	sph.call(1.0, Vector3(0.12, 0.08, 0.95), Vector3(0, 0.9, -0.45), dk, 12)
	# hind legs folded beside it, paws tucked forward; the tail curled along the right flank
	for sd in [-1.0, 1.0]:
		sph.call(1.0, Vector3(0.17, 0.22, 0.55), Vector3(sd * 0.46, 0.24, -0.95), st, 14)
		sph.call(1.0, Vector3(0.15, 0.1, 0.24), Vector3(sd * 0.5, 0.1, -0.38), st, 12)
		for t in 3:
			sph.call(0.055, Vector3.ONE, Vector3(sd * (0.44 + t * 0.06), 0.06, -0.16), dk, 8)
	var tail: Array[Vector3] = []
	for k in 8:
		var a := k / 7.0
		tail.append(Vector3(0.2 + sin(a * 2.6) * 0.42, 0.14 + 0.25 * (1.0 - a), -1.55 + a * 1.25))
	for k in tail.size() - 1:
		lim.call(tail[k], tail[k + 1], 0.07, 0.06, st)
	sph.call(0.1, Vector3(1.0, 0.8, 1.4), tail[-1] + Vector3(0, 0, 0.08), dk, 10)
	# forelegs stretched out in front, big paws with toes
	for sd in [-1.0, 1.0]:
		sph.call(1.0, Vector3(0.2, 0.28, 0.28), Vector3(sd * 0.34, 0.36, 0.62), st, 14)   # elbow
		lim.call(Vector3(sd * 0.34, 0.24, 0.65), Vector3(sd * 0.34, 0.15, 1.42), 0.16, 0.13, st)
		sph.call(1.0, Vector3(0.17, 0.12, 0.22), Vector3(sd * 0.34, 0.11, 1.52), st, 14)
		for t in 4:
			sph.call(0.055, Vector3(1.0, 0.9, 1.2), Vector3(sd * 0.34 + (t - 1.5) * 0.075, 0.07, 1.7), dk, 8)
	# the neck and the ram's head: a long skull, a heavy muzzle, eyes, nostrils
	lim.call(Vector3(0, 0.82, 0.5), Vector3(0, 1.2, 0.86), 0.3, 0.24, st)
	sph.call(1.0, Vector3(0.27, 0.3, 0.36), Vector3(0, 1.42, 0.98), st, 18)
	sph.call(1.0, Vector3(0.18, 0.2, 0.3), Vector3(0, 1.27, 1.28), st, 16)
	sph.call(1.0, Vector3(0.14, 0.1, 0.12), Vector3(0, 1.18, 1.48), st, 12)   # the nose
	for sd in [-1.0, 1.0]:
		sph.call(0.035, Vector3.ONE, Vector3(sd * 0.06, 1.18, 1.58), _c(Color(0.25, 0.18, 0.12)), 8)   # nostrils
		sph.call(0.06, Vector3(1.3, 0.8, 0.8), Vector3(sd * 0.18, 1.45, 1.17), dk, 10)                  # brow
		sph.call(0.04, Vector3(1.2, 0.8, 0.6), Vector3(sd * 0.19, 1.42, 1.2), _c(Color(0.22, 0.16, 0.1)), 8)   # eye
		sph.call(1.0, Vector3(0.06, 0.12, 0.05), Vector3(sd * 0.27, 1.36, 0.95), st, 10)              # ear
		# the horn: a ridged spiral curling back, down and forward round the ear
		var c := Vector3(sd * 0.36, 1.38, 0.9)
		var n := 22
		for k in n:
			var a := TAU * 1.05 * k / (n - 1)
			var r := 0.3 * (1.0 - 0.5 * a / TAU)
			var at := c + Vector3(sd * (0.0 + 0.12 * a / TAU), cos(a) * r, -sin(a) * r)
			sph.call(0.12 - 0.065 * k / n, Vector3.ONE, at, _c(Color(0.78, 0.66, 0.5).darkened(0.18 if k % 2 else 0.0)), 10)
	# a striped nemes over the skull, lappets falling either side of the neck onto the chest
	sph.call(1.0, Vector3(0.31, 0.26, 0.34), Vector3(0, 1.52, 0.9), _c(DesertSphinx.STRIPE_A), 16)
	for k in 5:
		var y := 1.5 - k * 0.07
		var c := DesertSphinx.STRIPE_A if k % 2 == 0 else DesertSphinx.STRIPE_B
		mb.add(MeshBuilder.cyl(0.3 + k * 0.012, 0.31 + k * 0.012, 0.07, 16), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.9)), Vector3(0, y0 + y, 0.82)), _c(c))
	for sd in [-1.0, 1.0]:
		for k in 7:
			var t := k / 6.0
			var c := DesertSphinx.STRIPE_A if k % 2 == 0 else DesertSphinx.STRIPE_B
			mb.add(MeshBuilder.box(Vector3(0.2, 0.09, 0.08)), Transform3D(Basis(Vector3(1, 0, 0), -0.25), Vector3(sd * (0.25 + t * 0.03), y0 + 1.25 - t * 0.5, 0.98 + t * 0.06)), _c(c))
	# a small pharaoh standing between the paws, against the chest, arms crossed
	var f := Vector3(0, 0, 1.12)
	mb.add(MeshBuilder.box(Vector3(0.24, 0.4, 0.16)), Transform3D(Basis(), f + Vector3(0, y0 + 0.2, 0)), dk)       # legs and kilt
	mb.add(MeshBuilder.cyl(0.13, 0.12, 0.34, 10), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.7)), f + Vector3(0, y0 + 0.57, 0)), st)   # torso
	mb.add(MeshBuilder.box(Vector3(0.26, 0.07, 0.06)), Transform3D(Basis(Vector3(0, 0, 1), 0.35), f + Vector3(0, y0 + 0.6, 0.1)), dk)   # crossed arms
	mb.add(MeshBuilder.box(Vector3(0.26, 0.07, 0.06)), Transform3D(Basis(Vector3(0, 0, 1), -0.35), f + Vector3(0, y0 + 0.62, 0.11)), dk)
	DesertSphinx.head(mb, Transform3D(Basis.from_scale(Vector3.ONE * 0.085), f + Vector3(0, y0 + 0.86, 0.02)), st, rng, false, true)
	var d := _stone(mb, [_box_col(Vector3(1.8, 2.9, 3.4), Vector3(0, 1.45, 0))])
	_cache["ram"] = d
	return d


static func brazier() -> Dictionary:
	var mb := MeshBuilder.new()
	for k in 3:
		var a := TAU * k / 3.0
		mb.limb(Vector3(cos(a) * 0.45, 0, sin(a) * 0.45), Vector3(cos(a) * 0.22, 1.05, sin(a) * 0.22), 0.04, 0.03, Color(0.3, 0.22, 0.12), 5)
	mb.add(MeshBuilder.cyl(0.5, 0.3, 0.35, 12), Transform3D(Basis(), Vector3(0, 1.15, 0)), Color(0.55, 0.38, 0.16))
	mb.add(MeshBuilder.sphere(0.3, 8, 4), Transform3D(Basis.from_scale(Vector3(1.4, 0.4, 1.4)), Vector3(0, 1.3, 0)), Color(1.0, 0.45, 0.1))
	return {"mesh": mb.commit(), "colliders": [_cyl_col(0.4, 1.3)]}


# ------------------------------------------------------------------ ground scatter

static func dry_grass_mesh(rng: RandomNumberGenerator, lush: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 11:
		var a := TAU * k / 11.0 + rng.randf() * 0.5
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var h := rng.randf_range(0.25, 0.6) * (1.3 if lush else 1.0)
		var base := out * rng.randf_range(0.0, 0.12)
		var tip := base + out * rng.randf_range(0.15, 0.4) + Vector3(0, h, 0)
		var bc := Color(0.5, 0.42, 0.24, 0.0) if not lush else Color(0.2, 0.32, 0.1, 0.0)
		var tc: Color = ([Color(0.9, 0.78, 0.46, 1.0), Color(0.82, 0.68, 0.38, 1.0), Color(0.95, 0.86, 0.6, 1.0)] if not lush else [Color(0.45, 0.62, 0.2, 1.0), Color(0.55, 0.7, 0.25, 1.0), Color(0.62, 0.66, 0.3, 1.0)])[k % 3]
		st.set_normal(Vector3.UP)
		st.set_color(bc)
		st.add_vertex(base - side * 0.03)
		st.set_color(bc)
		st.add_vertex(base + side * 0.03)
		st.set_color(tc)
		st.add_vertex(tip)
	var mesh := st.commit()
	mesh.surface_set_material(0, MeshBuilder.foliage_material())
	return mesh


static func scatter_mesh(kind: String, rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	match kind:
		"scrub":   # a low, twiggy grey-green desert bush (saltbush)
			for k in 9:
				var a := rng.randf() * TAU
				var e := rng.randf_range(0.25, 0.5)
				var tip := Vector3(cos(a) * 0.38, e, sin(a) * 0.38)
				mb.limb(Vector3.ZERO, tip, 0.02, 0.008, Color(0.42, 0.34, 0.24, 0.0), 3)
				for t in 2:
					var at := tip * rng.randf_range(0.55, 1.0) + Vector3(rng.randf_range(-0.06, 0.06), 0.02, rng.randf_range(-0.06, 0.06))
					mb.add(ForestProps._lumpy(rng.randf_range(0.08, 0.15), rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.0)), at), _shade(Color(0.52, 0.55, 0.4, 0.4) if (k + t) % 3 else Color(0.62, 0.6, 0.44, 0.4), rng, 0.12))
		"thorn":   # a dead camel-thorn tangle
			for k in 10:
				var a := rng.randf() * TAU
				var e := rng.randf_range(0.2, 0.8)
				var to := Vector3(cos(a) * 0.55, e * 0.6, sin(a) * 0.55)
				mb.limb(Vector3.ZERO, to, 0.022, 0.006, Color(0.55, 0.45, 0.32, 0.2), 3)
				mb.limb(to * 0.6, to * 0.6 + Vector3(cos(a + 1.2) * 0.25, 0.15, sin(a + 1.2) * 0.25), 0.012, 0.004, Color(0.6, 0.5, 0.35, 0.3), 3)
		"pebbles":
			for k in 5:
				var a := rng.randf() * TAU
				var d := rng.randf_range(0.0, 0.3)
				mb.add(MeshBuilder.sphere(rng.randf_range(0.04, 0.09), 6, 4), Transform3D(Basis.from_scale(Vector3(1.0, 0.55, rng.randf_range(0.7, 1.2))), Vector3(cos(a) * d, 0.02, sin(a) * d)), _shade(Color(0.5, 0.38, 0.28, 0.0), rng, 0.25))
		"stones":
			mb.add(ForestProps._lumpy(rng.randf_range(0.2, 0.4), rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 0.8)), Vector3(0, 0.06, 0)), _shade(Color(0.58, 0.44, 0.32, 0.0), rng, 0.12))
		"bones":   # a horned skull and a couple of bones
			var b := _c(BONE)
			mb.add(MeshBuilder.sphere(0.13, 8, 5), Transform3D(Basis.from_scale(Vector3(0.8, 0.7, 1.4)), Vector3(0, 0.07, 0)), b)
			for sd in [-1.0, 1.0]:
				mb.limb(Vector3(sd * 0.08, 0.1, -0.06), Vector3(sd * 0.3, 0.2, -0.16), 0.03, 0.008, b, 4)
			mb.limb(Vector3(0.3, 0.02, 0.1), Vector3(0.75, 0.02, 0.25), 0.025, 0.025, b, 4)
			mb.add(MeshBuilder.sphere(0.04, 6, 4), Transform3D(Basis(), Vector3(0.75, 0.03, 0.25)), b)
			mb.limb(Vector3(-0.3, 0.02, 0.3), Vector3(-0.5, 0.02, 0.62), 0.02, 0.02, b, 4)
		"shards":   # broken pottery
			for k in 4:
				var a := rng.randf() * TAU
				var d := rng.randf_range(0.0, 0.4)
				mb.add(MeshBuilder.cyl(0.12, 0.14, 0.02, 6), Transform3D(Basis(Vector3(1, 0, 0), rng.randf_range(-0.3, 0.3)).scaled(Vector3(1.0, 1.0, rng.randf_range(0.4, 0.8))), Vector3(cos(a) * d, 0.02, sin(a) * d)), _shade(Color(0.66, 0.36, 0.22, 0.0), rng, 0.15))
			mb.add(MeshBuilder.cyl(0.1, 0.16, 0.18, 10), Transform3D(Basis(Vector3(0, 0, 1), 1.3), Vector3(0.1, 0.08, -0.2)), Color(0.62, 0.34, 0.2, 0.0))   # a jar's broken neck
	return mb.commit(MeshBuilder.prop_material())


static func papyrus_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf()
		var top := Vector3(cos(a) * 0.3, rng.randf_range(1.5, 2.3), sin(a) * 0.3)
		mb.limb(Vector3.ZERO, top, 0.025, 0.012, Color(0.32, 0.48, 0.16, 0.6), 4)
		for r in 10:   # the umbel: a starburst of thin rays
			var ra := TAU * r / 10.0
			mb.limb(top, top + Vector3(cos(ra) * 0.28, 0.12 + rng.randf() * 0.08, sin(ra) * 0.28), 0.008, 0.004, Color(0.48, 0.62, 0.22, 1.0), 3)
	return mb.commit(MeshBuilder.foliage_material())
