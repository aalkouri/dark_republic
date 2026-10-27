class_name SwampWater
extends RefCounted
## Recessed pools of swamp water.
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

# Per pool: center (Vector2), base radius, depth, water level, amplitudes[4], phases[4], bed seed
var pools: Array = []
# Flat arrays for fast "near a pool?" rejection in hot loops
var fast_x := PackedFloat32Array()
var fast_z := PackedFloat32Array()
var fast_r2 := PackedFloat32Array()
# 1 m grid over the arena: 1 where a pool might be (bounding circle). Read inline by hot loops.
const MASK_HALF := 128
const MASK_SIZE := MASK_HALF * 2
var mask := PackedByteArray()


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
		var c := Vector2(rng.randf_range(-half + 15.0, half - 15.0), rng.randf_range(-half + 15.0, half - 15.0))
		if c.length() < keep_out:
			continue
		var ok := true
		for p in sw.pools:
			if c.distance_to(p["center"]) < 25.0:
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
	sw.mask.resize(MASK_SIZE * MASK_SIZE)
	for zi in MASK_SIZE:
		for xi in MASK_SIZE:
			# Cell centre test with a 1 m margin so no edge cell is missed
			var x := xi - MASK_HALF + 0.5
			var z := zi - MASK_HALF + 0.5
			for k in sw.fast_x.size():
				var dx := x - sw.fast_x[k]
				var dz := z - sw.fast_z[k]
				var r := sqrt(sw.fast_r2[k]) + 1.0
				if dx * dx + dz * dz < r * r:
					sw.mask[zi * MASK_SIZE + xi] = 1
					break
	return sw


## Cheap check: could (x, z) be inside any pool?
func maybe_in_pool(x: float, z: float) -> bool:
	for k in fast_x.size():
		var dx := x - fast_x[k]
		var dz := z - fast_z[k]
		if dx * dx + dz * dz < fast_r2[k]:
			return true
	return false


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


## Ground height at a world XZ position (0 outside pools).
func ground_height(x: float, z: float) -> float:
	for p in pools:
		var c: Vector2 = p["center"]
		var dx := x - c.x
		var dz := z - c.y
		var d2 := dx * dx + dz * dz
		var mr := max_radius(p)
		if d2 > mr * mr:
			continue
		var th := atan2(dz, dx)
		var rr := outline_radius(p, th)
		var d := sqrt(d2)
		if d < rr:
			return bed_height(p, d / rr, th)
	return 0.0


## True if a body whose feet are at `pos` is standing in water.
func in_water(pos: Vector3) -> bool:
	for p in pools:
		var c: Vector2 = p["center"]
		var dx := pos.x - c.x
		var dz := pos.z - c.y
		var mr := max_radius(p)
		if dx * dx + dz * dz > mr * mr:
			continue
		if pos.y > float(p["water_y"]) + 0.05:
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
	var wy: float = p["water_y"]
	var grid := []
	for ri in RINGS + 1:
		var rho := float(ri) / RINGS
		var row := []
		for si in SEGMENTS:
			var th := TAU * si / SEGMENTS
			var rr := outline_radius(p, th) * (1.0 if is_bed else 0.995)
			var x := c.x + cos(th) * rr * rho
			var z := c.y + sin(th) * rr * rho
			var y := bed_height(p, rho, th) if is_bed else wy
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

## Heightmap collision for the whole ground (1 m cells), recessed where the pools are.
func heightmap_body(half: float) -> StaticBody3D:
	var size := int(ceil(half * 2.0 + 20.0)) + 1
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	var origin := -float(size - 1) * 0.5
	for zi in size:
		for xi in size:
			heights[zi * size + xi] = ground_height(origin + xi, origin + zi)
	var shape := HeightMapShape3D.new()
	shape.map_width = size
	shape.map_depth = size
	shape.map_data = heights
	var col := CollisionShape3D.new()
	col.shape = shape
	var body := StaticBody3D.new()
	body.add_child(col)
	return body


## Uniform arrays for the ground shader so it can cut holes exactly where the pools are.
func shader_params() -> Dictionary:
	var a := []   # center.x, center.z, R, unused
	var amps := []
	var phases := []
	for k in 4:
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
