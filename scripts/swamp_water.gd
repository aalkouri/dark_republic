class_name SwampWater
extends RefCounted
## The ground: rolling terrain (hills, dips and slopes) plus recessed pools of swamp water.
##  - Terrain: two layers of smooth noise (broad hills + smaller bumps), flattened into level
##    pads where pools, shrines and the start point sit, and rising into a berm at the arena
##    edge. Baked into a 1 m height grid that everything samples (ground_height).
##  - Outline: r(θ) = R * (1 + Σ a_k sin(kθ + φ_k)), k = 2..5, so every pool has a natural,
##    lumpy shape. Max diameter is capped at 10 yd (9.14 m).
##  - Bed: a bowl whose depth varies across the pool and per pool, always shallower than the
##    character (MAX_DEPTH). The water surface sits just below the surrounding ground.
##  - Gameplay: anything standing in the water moves at 50% speed.
## The same analytic outline drives the bowl mesh, the water mesh, the heightmap collision,
## the ground shader (which cuts holes for the pools) and the in-water checks, so they agree.

const YARD := 0.9144
const MAX_DIAMETER := 10.0 * YARD
const MAX_DEPTH := 1.65            # character capsule is 1.8 m tall
const MIN_DEPTH := 0.7
const SPEED_MULT := 0.5
const HARMONICS := 4               # k = 2..5

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform vec3 deep : source_color = vec3(0.05, 0.075, 0.045);
uniform vec3 shallow : source_color = vec3(0.16, 0.19, 0.09);
uniform vec3 scum : source_color = vec3(0.27, 0.33, 0.11);
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = wpos.xz;
	// Slow ripples
	float r1 = noise(p * 1.3 + vec2(TIME * 0.25, TIME * 0.18));
	float r2 = noise(p * 2.7 - vec2(TIME * 0.2, TIME * 0.31));
	NORMAL_MAP = normalize(vec3((r1 - 0.5) * 0.35, (r2 - 0.5) * 0.35, 1.0)) * 0.5 + 0.5;
	// Floating duckweed / algae scum, mostly near the edges (COLOR.r = 0 centre .. 1 edge)
	float edge = COLOR.r;
	float weed = smoothstep(0.55, 0.75, noise(p * 0.9) * 0.7 + noise(p * 4.0) * 0.3 + edge * 0.35);
	vec3 water = mix(deep, shallow, edge * 0.6);
	ALBEDO = mix(water, scum, weed);
	ROUGHNESS = mix(0.06, 0.8, weed);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(0.88, 1.0, weed);
}
"""

const BED_COLOR := Color(0.13, 0.1, 0.07)

# Terrain shape
const HILL_HEIGHT := 6.5        # broad hills: up to about +/- this many metres
const HILL_FREQ := 0.0105       # ~95 m between hill tops
const BUMP_HEIGHT := 0.7        # small rolls on top
const BUMP_FREQ := 0.045
const EDGE_RISE := 7.0          # the ground climbs this much into a berm at the arena edge
const EDGE_BAND := 32.0         # ...over the last this-many metres
const PAD_BLEND := 9.0          # how far a flattened pad blends back into the hills

## The ground of the current run, for anything that needs a height (pickups, drops, aim).
static var current: SwampWater

## Ground height at XZ in the current run (0 if no world is built).
static func height_at(x: float, z: float) -> float:
	return current.ground_height(x, z) if current != null else 0.0

# Per pool: center (Vector2), base radius, depth, water level, amplitudes[4], phases[4], bed seed
var pools: Array = []
# Flat arrays for fast "near a pool?" rejection in hot loops
var fast_x := PackedFloat32Array()
var fast_z := PackedFloat32Array()
var fast_r2 := PackedFloat32Array()
# Height grid (1 m cells) covering the arena + margin. Hot loops read it inline:
#   h = hgrid[iz * hsize + ix], with ix = x - horigin, iz = z - horigin.
var hgrid := PackedFloat32Array()
var hsize := 0
var horigin := 0.0
var half_extent := 0.0
# Level pads: [Vector2 centre, radius, height]
var pads: Array = []
var shrine_sites: Array[Vector3] = []
var height_texture: ImageTexture   # the height grid as a texture, for shaders (GroundDisc)
var _hills: FastNoiseLite
var _bumps: FastNoiseLite


static func generate(rng: RandomNumberGenerator, count: int, half: float, keep_out: float) -> SwampWater:
	var sw := SwampWater.new()
	var tries := 0
	while sw.pools.size() < count and tries < 500:
		tries += 1
		var amps := PackedFloat32Array()
		var phases := PackedFloat32Array()
		var amp_sum := 0.0
		for k in HARMONICS:
			var a := rng.randf_range(0.02, 0.11) / (1.0 + k * 0.5)
			amps.append(a)
			phases.append(rng.randf() * TAU)
			amp_sum += a
		# Largest possible radius is R * (1 + amp_sum); keep diameter <= 10 yd.
		var r_cap := (MAX_DIAMETER * 0.5 - 0.05) / (1.0 + amp_sum)
		var base_r := rng.randf_range(2.0, r_cap)
		var c := Vector2(rng.randf_range(-half + EDGE_BAND + 6.0, half - EDGE_BAND - 6.0), rng.randf_range(-half + EDGE_BAND + 6.0, half - EDGE_BAND - 6.0))
		if c.length() < keep_out:
			continue
		var ok := true
		for p in sw.pools:
			if c.distance_to(p["center"]) < 42.0:
				ok = false
		if not ok:
			continue
		sw.pools.append({
			"center": c, "r": base_r, "amps": amps, "phases": phases,
			"depth": rng.randf_range(MIN_DEPTH, MAX_DEPTH),
			"water_y": -rng.randf_range(0.12, 0.22),
			"seed": rng.randf() * 100.0,
		})
	for p in sw.pools:
		var c: Vector2 = p["center"]
		sw.fast_x.append(c.x)
		sw.fast_z.append(c.y)
		sw.fast_r2.append(pow(sw.max_radius(p), 2.0))
	return sw


## Cheap check: could (x, z) be inside any pool?
func maybe_in_pool(x: float, z: float) -> bool:
	for k in fast_x.size():
		var dx := x - fast_x[k]
		var dz := z - fast_z[k]
		if dx * dx + dz * dz < fast_r2[k]:
			return true
	return false


# ------------------------------------------------------------------ terrain

## Rolling hills, without pads, pools or the edge berm.
func raw_hills(x: float, z: float) -> float:
	return _hills.get_noise_2d(x, z) * HILL_HEIGHT + _bumps.get_noise_2d(x, z) * BUMP_HEIGHT


## Hills plus the edge berm (before pads and pools).
func base_terrain(x: float, z: float) -> float:
	var edge := smoothstep(0.0, EDGE_BAND, maxf(absf(x), absf(z)) - (half_extent - EDGE_BAND))
	# Hills calm down as the ground climbs into the berm, so the edge never gets too steep
	return raw_hills(x, z) * (1.0 - 0.6 * edge) + EDGE_RISE * edge


## Bakes the terrain into the height grid. `shrine_count` level pads are reserved for
## shrines (away from the start, the pools and each other); the start point and every pool
## sit on level ground too.
func build_terrain(rng: RandomNumberGenerator, half: float, shrine_count: int, shrine_radius: float) -> void:
	half_extent = half
	_hills = FastNoiseLite.new()
	_hills.seed = rng.randi()
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = HILL_FREQ
	_hills.fractal_octaves = 2
	_bumps = FastNoiseLite.new()
	_bumps.seed = rng.randi()
	_bumps.frequency = BUMP_FREQ
	_bumps.fractal_octaves = 2

	# Pads: start point, every pool, shrine sites
	pads.clear()
	pads.append([Vector2.ZERO, 10.0, base_terrain(0, 0)])
	for p in pools:
		var c: Vector2 = p["center"]
		p["base"] = base_terrain(c.x, c.y)
		pads.append([c, max_radius(p) + 2.5, p["base"]])
	shrine_sites.clear()
	var tries := 0
	while shrine_sites.size() < shrine_count and tries < 2000:
		tries += 1
		var c := Vector2(rng.randf_range(-half + EDGE_BAND + 8.0, half - EDGE_BAND - 8.0), rng.randf_range(-half + EDGE_BAND + 8.0, half - EDGE_BAND - 8.0))
		if c.length() < 40.0 or near_pool(c.x, c.y, shrine_radius + 14.0):
			continue
		var ok := true
		for q in shrine_sites:
			if c.distance_to(Vector2(q.x, q.z)) < 55.0:
				ok = false
				break
		if not ok:
			continue
		var h := base_terrain(c.x, c.y)
		pads.append([c, shrine_radius + 1.5, h])
		shrine_sites.append(Vector3(c.x, h, c.y))

	# Height grid: hills + edge berm, then flatten every pad, then carve the pools
	hsize = int(ceil(half * 2.0 + 20.0)) + 1
	horigin = -float(hsize - 1) * 0.5
	hgrid.resize(hsize * hsize)
	for zi in hsize:
		var z := horigin + zi
		for xi in hsize:
			var x := horigin + xi
			hgrid[zi * hsize + xi] = base_terrain(x, z)
	for pad in pads:
		var c: Vector2 = pad[0]
		var r: float = pad[1]
		var ph: float = pad[2]
		# Blend wider where the hills around the pad are far above/below it, so the ramp
		# down to (or up from) the pad stays a gentle slope
		var diff := 0.0
		for k in 16:
			var a := TAU * k / 16.0
			var ex := c.x + cos(a) * (r + PAD_BLEND)
			var ez := c.y + sin(a) * (r + PAD_BLEND)
			diff = maxf(diff, absf(hgrid[clampi(int(ez - horigin), 0, hsize - 1) * hsize + clampi(int(ex - horigin), 0, hsize - 1)] - ph))
		var reach := r + clampf(diff * 3.6, PAD_BLEND, 34.0)
		for other in pads:   # never ramp into another pad's level core
			if other != pad:
				reach = minf(reach, maxf(r + 4.0, c.distance_to(other[0]) - float(other[1]) - 1.0))
		for zi in range(maxi(0, int(c.y - reach - horigin)), mini(hsize, int(c.y + reach - horigin) + 2)):
			for xi in range(maxi(0, int(c.x - reach - horigin)), mini(hsize, int(c.x + reach - horigin) + 2)):
				var d := Vector2(horigin + xi, horigin + zi).distance_to(c)
				if d >= reach:
					continue
				var w := 1.0 - smoothstep(r, reach, d)
				var k := zi * hsize + xi
				hgrid[k] = lerpf(hgrid[k], ph, w)
	for p in pools:
		var c: Vector2 = p["center"]
		var mr := max_radius(p) + 1.0
		for zi in range(maxi(0, int(c.y - mr - horigin)), mini(hsize, int(c.y + mr - horigin) + 2)):
			for xi in range(maxi(0, int(c.x - mr - horigin)), mini(hsize, int(c.x + mr - horigin) + 2)):
				var x := horigin + xi
				var z := horigin + zi
				var b := _pool_bed_offset(p, x, z)
				if b < 0.0:
					hgrid[zi * hsize + xi] = float(p["base"]) + b
	var img := Image.create_from_data(hsize, hsize, false, Image.FORMAT_RF, hgrid.to_byte_array())
	height_texture = ImageTexture.create_from_image(img)
	current = self


## How far below the pool's base the bed is at XZ (0 outside the outline).
func _pool_bed_offset(p: Dictionary, x: float, z: float) -> float:
	var c: Vector2 = p["center"]
	var dx := x - c.x
	var dz := z - c.y
	var th := atan2(dz, dx)
	var rr := outline_radius(p, th)
	var d := sqrt(dx * dx + dz * dz)
	return bed_height(p, d / rr, th) if d < rr else 0.0


## Surface normal of the terrain at XZ (from the height grid).
func normal_at(x: float, z: float) -> Vector3:
	var hx := ground_height(x + 0.5, z) - ground_height(x - 0.5, z)
	var hz := ground_height(x, z + 0.5) - ground_height(x, z - 0.5)
	return Vector3(-hx, 1.0, -hz).normalized()


# ------------------------------------------------------------------ shape queries

func outline_radius(p: Dictionary, theta: float) -> float:
	var amps: PackedFloat32Array = p["amps"]
	var phases: PackedFloat32Array = p["phases"]
	var s := 1.0
	for k in HARMONICS:
		s += amps[k] * sin((k + 2) * theta + phases[k])
	return p["r"] * s


func max_radius(p: Dictionary) -> float:
	var amp_sum := 0.0
	for a in p["amps"]:
		amp_sum += a
	return p["r"] * (1.0 + amp_sum)


## Bed height (<= 0) at normalized radius rho (0 centre .. 1 rim) and angle theta.
func bed_height(p: Dictionary, rho: float, theta: float) -> float:
	if rho >= 1.0:
		return 0.0
	var profile := 1.0 - smoothstep(0.2, 1.0, rho)
	var sd: float = p["seed"]
	var bumps := 0.5 + 0.25 * sin(3.0 * theta + rho * 6.0 + sd) + 0.25 * sin(5.0 * theta - rho * 4.0 + sd * 1.7)
	var depth: float = p["depth"]
	return -depth * profile * (0.7 + 0.3 * bumps) - 0.01


## Ground height at a world XZ position (bilinear in the 1 m height grid).
func ground_height(x: float, z: float) -> float:
	if hsize == 0:
		return 0.0
	var gx := clampf(x - horigin, 0.0, hsize - 1.001)
	var gz := clampf(z - horigin, 0.0, hsize - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var k := iz * hsize + ix
	var a := lerpf(hgrid[k], hgrid[k + 1], fx)
	var b := lerpf(hgrid[k + hsize], hgrid[k + hsize + 1], fx)
	return lerpf(a, b, fz)


## True if a body whose feet are at `pos` is standing in water.
func in_water(pos: Vector3) -> bool:
	for p in pools:
		var c: Vector2 = p["center"]
		var dx := pos.x - c.x
		var dz := pos.z - c.y
		var mr := max_radius(p)
		if dx * dx + dz * dz > mr * mr:
			continue
		if pos.y > float(p.get("base", 0.0)) + float(p["water_y"]) + 0.05:
			continue
		if sqrt(dx * dx + dz * dz) < outline_radius(p, atan2(dz, dx)) * 0.97:
			return true
	return false


## Is XZ within `margin` metres of any pool's furthest edge? (for prop placement)
func near_pool(x: float, z: float, margin: float) -> bool:
	for p in pools:
		var c: Vector2 = p["center"]
		if Vector2(x, z).distance_to(c) < max_radius(p) + margin:
			return true
	return false


# ------------------------------------------------------------------ meshes

func build_meshes(parent: Node3D) -> void:
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = BED_COLOR
	bed_mat.roughness = 0.35
	var wsh := Shader.new()
	wsh.code = WATER_SHADER
	var water_mat := ShaderMaterial.new()
	water_mat.shader = wsh
	for p in pools:
		var bed := MeshInstance3D.new()
		bed.mesh = _polar_mesh(p, true)
		bed.material_override = bed_mat
		parent.add_child(bed)
		var water := MeshInstance3D.new()
		water.mesh = _polar_mesh(p, false)
		water.material_override = water_mat
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(water)


const RINGS := 16
const SEGMENTS := 96


func _polar_mesh(p: Dictionary, is_bed: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector2 = p["center"]
	var base: float = p.get("base", 0.0)
	var wy: float = base + float(p["water_y"])
	var grid := []
	for ri in RINGS + 1:
		var rho := float(ri) / RINGS
		var row := []
		for si in SEGMENTS:
			var th := TAU * si / SEGMENTS
			var rr := outline_radius(p, th) * (1.0 if is_bed else 0.995)
			var x := c.x + cos(th) * rr * rho
			var z := c.y + sin(th) * rr * rho
			var y := base + bed_height(p, rho, th) if is_bed else wy
			row.append(Vector3(x, y, z))
		grid.append(row)
	for ri in RINGS:
		for si in SEGMENTS:
			var sj := (si + 1) % SEGMENTS
			var a: Vector3 = grid[ri][si]
			var b: Vector3 = grid[ri][sj]
			var cc: Vector3 = grid[ri + 1][sj]
			var d: Vector3 = grid[ri + 1][si]
			for v in [a, cc, b, a, d, cc]:
				var rho := Vector2(v.x - c.x, v.z - c.y).length() / maxf(0.001, outline_radius(p, atan2(v.z - c.y, v.x - c.x)))
				st.set_color(Color(clampf(rho, 0.0, 1.0), 0, 0))
				st.set_uv(Vector2(v.x, v.z))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ collision + ground shader data

## Heightmap collision for the whole ground (1 m cells), straight from the height grid.
func heightmap_body() -> StaticBody3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = hsize
	shape.map_depth = hsize
	shape.map_data = hgrid
	var col := CollisionShape3D.new()
	col.shape = shape
	var body := StaticBody3D.new()
	body.add_child(col)
	return body


## Visible ground: a grid mesh following the height grid (every `step` metres).
func ground_mesh(step: int) -> ArrayMesh:
	var n := (hsize - 1) / step + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(n * n)
	normals.resize(n * n)
	for zi in n:
		for xi in n:
			var gx := mini(xi * step, hsize - 1)
			var gz := mini(zi * step, hsize - 1)
			var x := horigin + gx
			var z := horigin + gz
			verts[zi * n + xi] = Vector3(x, hgrid[gz * hsize + gx], z)
			normals[zi * n + xi] = normal_at(x, z)
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var w := 0
	for zi in n - 1:
		for xi in n - 1:
			var a := zi * n + xi
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx[w] = a; idx[w + 1] = b; idx[w + 2] = c
			idx[w + 3] = b; idx[w + 4] = d; idx[w + 5] = c
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


const MAX_SHADER_POOLS := 16

## Uniform arrays for the ground shader so it can cut holes exactly where the pools are.
func shader_params() -> Dictionary:
	var a := []   # center.x, center.z, R, unused
	var amps := []
	var phases := []
	for k in MAX_SHADER_POOLS:
		if k < pools.size():
			var p: Dictionary = pools[k]
			var c: Vector2 = p["center"]
			a.append(Vector4(c.x, c.y, p["r"], 1.0))
			var am: PackedFloat32Array = p["amps"]
			var ph: PackedFloat32Array = p["phases"]
			amps.append(Vector4(am[0], am[1], am[2], am[3]))
			phases.append(Vector4(ph[0], ph[1], ph[2], ph[3]))
		else:
			a.append(Vector4(0, 0, 0, 0))
			amps.append(Vector4.ZERO)
			phases.append(Vector4.ZERO)
	return {"pools": a, "pool_amps": amps, "pool_phases": phases}
