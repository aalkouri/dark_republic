class_name WorldBuilder
extends RefCounted
## Builds the dark swamp arena from a seed:
##   sky (50% sun behind dense clouds / 50% moon with few clouds), lighting and fog,
##   rolling ground (hills, dips, slopes; level pads for the start, pools and chests) with
##   random mud and swamp-grass patches, swaying grass tufts and reeds, 14 recessed pools of
##   swamp water, 180 swamp trees (4 variants), 72 fallen trees, 24 mossy ruins and a berm
##   with stone walls round the edge.
## Returns the SwampWater so gameplay can query water and ground height.

const TREES := 180
const FALLEN := 72
const RUINS := 24
const POOLS := 14
const CHEST_SITES := 28   # level pads reserved for chests (ChestManager uses some of them)

const SKY_SHADER := """
shader_type sky;
uniform vec3 top_color : source_color;
uniform vec3 horizon_color : source_color;
uniform vec3 ground_color : source_color;
uniform vec3 cloud_dark : source_color;
uniform vec3 cloud_light : source_color;
uniform vec3 body_color : source_color;
uniform float body_size = 0.045;       // angular radius of the sun/moon (radians)
uniform float coverage = 0.85;         // 0 = clear, 1 = overcast
uniform float night = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 6; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, h));
	if (h < 0.0) { col = mix(horizon_color, ground_color, smoothstep(0.0, -0.25, h)); }

	vec3 L = LIGHT0_DIRECTION;
	float cosang = dot(d, L);
	float ang = acos(clamp(cosang, -1.0, 1.0));
	float disc = 1.0 - smoothstep(body_size * 0.9, body_size, ang);
	float halo = exp(-(ang * ang) / (body_size * body_size * 18.0));
	float wide = pow(max(cosang, 0.0), 6.0);

	// Stars (night only)
	if (night > 0.5 && h > 0.0) {
		vec2 sp = vec2(atan(d.z, d.x), asin(h)) * 180.0;
		float s = hash(floor(sp));
		float star = step(0.9965, s) * smoothstep(0.0, 0.2, h);
		col += vec3(star) * (0.5 + 0.5 * hash(floor(sp) + 3.1));
	}

	// Sun / moon disc (the moon gets some mottling)
	vec3 body = body_color;
	if (night > 0.5) {
		vec3 t = d - L * cosang;
		body *= 0.82 + 0.18 * noise(t.xz * 260.0 + t.y * 90.0);
	}
	col = mix(col, body, disc);
	col += body_color * (halo * mix(0.55, 0.28, night) + wide * mix(0.12, 0.03, night));

	// Clouds on a virtual plane
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.1) * 0.55 + vec2(seed, seed * 0.37);
		float n = fbm(uv);
		float dens = smoothstep(1.0 - coverage - 0.08, 1.0 - coverage + 0.32, n);
		dens *= smoothstep(0.0, 0.12, h);
		float n2 = fbm(uv + L.xz * 0.06);
		float lit = clamp(0.55 + (n - n2) * 5.0, 0.0, 1.0);
		vec3 cc = mix(cloud_dark, cloud_light, lit);
		cc += body_color * (wide * mix(0.35, 0.08, night) + halo * mix(0.5, 0.2, night));  // silver lining
		col = mix(col, cc, dens);
		// The sun still glows through the overcast
		col += body_color * halo * dens * mix(0.35, 0.05, night);
	}
	COLOR = col;
}
"""

const GROUND_SHADER := """
shader_type spatial;
uniform sampler2D patch_map : filter_linear, repeat_disable;
uniform float extent = 120.0;
uniform vec4 pools[16];
uniform vec4 pool_amps[16];
uniform vec4 pool_phases[16];
uniform vec3 base_col : source_color = vec3(0.17, 0.16, 0.1);
uniform vec3 grass_col : source_color = vec3(0.15, 0.21, 0.08);
uniform vec3 mud_col : source_color = vec3(0.12, 0.085, 0.055);
uniform float wet_amount = 1.0;   // how wet and dark the mud patches look (0 = dry meadow)
uniform float quake = 0.0;        // Thog's quake: the whole ground glows red (0 = off, 1 = on)
uniform float quake_fill = 0.0;   // ...brighter and faster as it's about to land (0..1)
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	// Cut holes where the pools are (the pool bed mesh fills them) and darken their wet banks
	float bank = 0.0;
	float edge = 1e6;   // distance outside the nearest pool's shore
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
		bank = max(bank, 1.0 - smoothstep(r, r + 2.5, dist));
		edge = min(edge, dist - r);
	}
	vec2 uv = (wpos.xz + extent) / (2.0 * extent);
	vec4 m = texture(patch_map, uv);
	float n = noise(wpos.xz * 1.7) * 0.6 + noise(wpos.xz * 7.0) * 0.4;
	float mud = smoothstep(0.57, 0.64, m.r + (n - 0.5) * 0.06);
	float grass = smoothstep(0.55, 0.63, m.g + (n - 0.5) * 0.06) * (1.0 - mud);
	vec3 col = base_col * (0.8 + 0.4 * n);
	col = mix(col, grass_col * (0.75 + 0.5 * n), grass);
	col = mix(col, mud_col * (0.85 + 0.3 * n), mud);
	float wet = max(mud * (0.6 + 0.4 * n) * wet_amount, bank * max(wet_amount, 0.35));
	col *= 1.0 - 0.35 * wet;
	if (quake > 0.0) {
		// Danger everywhere but the pools: pulsing red with stripes crawling toward the water,
		// and a bright safe rim round every pool's shore
		float pulse = 0.5 + 0.5 * sin(TIME * mix(5.0, 14.0, quake_fill));
		float stripe = smoothstep(0.4, 0.6, fract((wpos.x + wpos.z) * 0.18 - TIME * 1.2));
		vec3 red = vec3(1.0, 0.12, 0.04);
		float a = quake * (0.45 + 0.25 * pulse + 0.12 * stripe);
		float safe = 1.0 - smoothstep(0.0, 1.6, edge);
		col = mix(col, red, a * (1.0 - safe));
		col = mix(col, vec3(0.4, 1.0, 0.85), safe * quake * 0.6);
		EMISSION = red * quake * (1.0 - safe) * (0.25 + 0.6 * quake_fill * pulse) + vec3(0.2, 0.9, 0.7) * safe * quake * 0.8;
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.28, wet);
	SPECULAR = mix(0.3, 0.6, wet);
}
"""


const MAPS := ["swamp", "forest", "castle"]


## Build the arena for `map` ("swamp", "forest" or "castle"). All share the 440 m footprint and
## the same prop counts; the outdoor two share the terrain generator, the castle is indoors.
static func build(parent: Node3D, rng: RandomNumberGenerator, half: float, map := "swamp") -> SwampWater:
	CastleNav.current = null
	if map == "forest":
		return ForestBuilder.build(parent, rng, half)
	if map == "castle":
		return CastleBuilder.build(parent, rng, half)
	var is_night := rng.randf() < 0.5
	_environment(parent, rng, is_night)

	var water := SwampWater.generate(rng, POOLS, half, 35.0)
	water.build_terrain(rng, half, CHEST_SITES, ChestManager.SITE_RADIUS)
	var patches := _patch_map(rng, half + 10.0)
	_ground(parent, half, water, patches)
	water.build_meshes(parent)
	_grass(parent, rng, half, water, patches)
	_reeds(parent, rng, water)
	_walls(parent, half)

	var placed: Array[Vector3] = []   # trunk positions, to keep trees apart
	for i in TREES:
		var p := _free_point(rng, half - 6.0, 12.0, water, 3.0, placed, 4.5)
		var t := SwampProps.tree(i % SwampProps.VARIANTS, rng)
		p.y = _low_point(water, p, 1.2) - 0.15   # on a slope, sit on the downhill side
		_prop(parent, t, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), true)
		placed.append(p)

	for i in FALLEN:
		var fallen := SwampProps.fallen_log(rng)
		var length: float = fallen["length"]
		var r: float = fallen["radius"]
		var p := _free_point(rng, half - length * 0.5 - 4.0, 14.0, water, length * 0.5 + 2.0, placed, length * 0.5 + 1.0)
		# Lie on the ground, partly sunk in the mud, root end lifted a little
		var tilt := deg_to_rad(rng.randf_range(2.0, 8.0))
		var yaw := rng.randf() * TAU
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), -tilt)
		# On a slope, sit at the lower end of the log so neither end floats
		var along := Basis(Vector3.UP, yaw) * Vector3(1, 0, 0) * length * 0.5
		var low := minf(water.ground_height(p.x + along.x, p.z + along.z), water.ground_height(p.x - along.x, p.z - along.z))
		var y := (low - p.y) + r * 0.8 + sin(tilt) * length * 0.5
		_prop(parent, fallen, Transform3D(basis, p + Vector3(0, y, 0)), true)
		placed.append(p)

	for i in RUINS:
		var p := _free_point(rng, half - 15.0, 25.0, water, 4.0, placed, 6.0)
		p.y = _low_point(water, p, 2.5) - 0.3
		_prop(parent, SwampProps.ruin(rng), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		var ruin_body := parent.get_child(parent.get_child_count() - 1)
		ruin_body.add_to_group("obstacle")
		ruin_body.set_meta("reach", 3.0)
		placed.append(p)
	return water


static func _free_point(rng: RandomNumberGenerator, extent: float, keep_out: float, water: SwampWater, pool_margin: float, placed: Array[Vector3], spacing: float) -> Vector3:
	for attempt in 300:
		var p := Vector3(rng.randf_range(-extent, extent), 0.0, rng.randf_range(-extent, extent))
		if p.length() < keep_out or water.near_pool(p.x, p.z, pool_margin):
			continue
		var ok := true
		for site in water.chest_sites:   # keep chest pads clear
			if Vector2(p.x - site.x, p.z - site.z).length() < ChestManager.SITE_RADIUS + 3.0 + spacing * 0.5:
				ok = false
				break
		for q in placed:
			if p.distance_to(q) < spacing:
				ok = false
				break
		if ok:
			p.y = water.ground_height(p.x, p.z)
			return p
	var q := Vector3(rng.randf_range(-extent, extent), 0.0, rng.randf_range(-extent, extent))
	q.y = water.ground_height(q.x, q.z)
	return q


## Lowest ground within radius r of p (centre + 8 points round it).
static func _low_point(water: SwampWater, p: Vector3, r: float) -> float:
	var h := water.ground_height(p.x, p.z)
	for k in 8:
		var a := TAU * k / 8.0
		h = minf(h, water.ground_height(p.x + cos(a) * r, p.z + sin(a) * r))
	return h


static func _prop(parent: Node3D, data: Dictionary, xf: Transform3D, burnable := false) -> void:
	var body := StaticBody3D.new()
	body.transform = xf
	var mi := MeshInstance3D.new()
	mi.mesh = data["mesh"]
	body.add_child(mi)
	if burnable:
		body.add_to_group(TreeFire.GROUP)
		body.set_meta("mesh_instance", mi)
		body.set_meta("reach", data.get("length", 3.0) * 0.5)   # how far from its origin the prop extends
	for c in data["colliders"]:
		var cs := CollisionShape3D.new()
		cs.shape = c[0]
		cs.transform = c[1]
		body.add_child(cs)
	parent.add_child(body)


# ------------------------------------------------------------------ sky, light, fog

static func _environment(parent: Node3D, rng: RandomNumberGenerator, night: bool) -> void:
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("night", 1.0 if night else 0.0)
	sky_mat.set_shader_parameter("seed", rng.randf() * 50.0)
	if night:
		# Moon, very few clouds
		sky_mat.set_shader_parameter("top_color", Color(0.012, 0.018, 0.045))
		sky_mat.set_shader_parameter("horizon_color", Color(0.05, 0.075, 0.11))
		sky_mat.set_shader_parameter("ground_color", Color(0.02, 0.025, 0.03))
		sky_mat.set_shader_parameter("cloud_dark", Color(0.04, 0.05, 0.08))
		sky_mat.set_shader_parameter("cloud_light", Color(0.22, 0.26, 0.34))
		sky_mat.set_shader_parameter("body_color", Color(0.86, 0.9, 1.0))
		sky_mat.set_shader_parameter("body_size", 0.04)
		sky_mat.set_shader_parameter("coverage", 0.14)
	else:
		# Sun hidden behind dense, gloomy clouds
		sky_mat.set_shader_parameter("top_color", Color(0.3, 0.33, 0.33))
		sky_mat.set_shader_parameter("horizon_color", Color(0.44, 0.47, 0.42))
		sky_mat.set_shader_parameter("ground_color", Color(0.15, 0.16, 0.13))
		sky_mat.set_shader_parameter("cloud_dark", Color(0.24, 0.26, 0.25))
		sky_mat.set_shader_parameter("cloud_light", Color(0.5, 0.51, 0.48))
		sky_mat.set_shader_parameter("body_color", Color(1.0, 0.9, 0.7))
		sky_mat.set_shader_parameter("body_size", 0.05)
		sky_mat.set_shader_parameter("coverage", 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_hdr_luminance_cap = 4.0   # one over-bright pixel can't bloom into a big white flash
	env.fog_enabled = true
	env.fog_sky_affect = 0.12
	if night:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.13, 0.17, 0.28)
		env.ambient_light_energy = 1.0
		env.fog_light_color = Color(0.05, 0.07, 0.11)
		env.fog_density = 0.014
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.75
		env.fog_light_color = Color(0.32, 0.36, 0.3)
		env.fog_density = 0.016
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	# Sun or moon: random direction, 28-50 degrees above the horizon
	var az := rng.randf() * TAU
	var el := deg_to_rad(rng.randf_range(28.0, 50.0))
	var to_light := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
	var light := DirectionalLight3D.new()
	light.basis = Basis.looking_at(-to_light, Vector3.UP)
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 80.0
	if night:
		light.light_color = Color(0.6, 0.7, 1.0)
		light.light_energy = 0.45
	else:
		light.light_color = Color(0.9, 0.86, 0.74)
		light.light_energy = 0.55   # dimmed by the overcast
		light.shadow_opacity = 0.6
	parent.add_child(light)


# ------------------------------------------------------------------ ground

## R = mud noise, G = swamp-grass noise, sampled over the whole ground.
static func _patch_map(rng: RandomNumberGenerator, extent: float) -> Image:
	var mud := FastNoiseLite.new()
	mud.seed = rng.randi()
	mud.frequency = 0.035
	mud.fractal_octaves = 3
	var grass := FastNoiseLite.new()
	grass.seed = rng.randi()
	grass.frequency = 0.045
	grass.fractal_octaves = 3
	var n := 384
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var wx := -extent + (x + 0.5) / n * extent * 2.0
			var wz := -extent + (y + 0.5) / n * extent * 2.0
			img.set_pixel(x, y, Color(mud.get_noise_2d(wx, wz) * 0.5 + 0.5, grass.get_noise_2d(wx, wz) * 0.5 + 0.5, 0.0))
	return img


static func _sample(img: Image, extent: float, x: float, z: float) -> Color:
	var n := img.get_width()
	var px := clampi(int((x + extent) / (extent * 2.0) * n), 0, n - 1)
	var py := clampi(int((z + extent) / (extent * 2.0) * n), 0, n - 1)
	return img.get_pixel(px, py)


static func _ground(parent: Node3D, half: float, water: SwampWater, patches: Image, colors := {}) -> void:
	var body := water.heightmap_body()
	var mesh := water.ground_mesh(1)   # same 1 m grid as collision + placement, so nothing floats
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("patch_map", ImageTexture.create_from_image(patches))
	sm.set_shader_parameter("extent", half + 10.0)
	var sp := water.shader_params()
	for k in sp:
		sm.set_shader_parameter(k, sp[k])
	for k in colors:   # base_col, grass_col, mud_col
		sm.set_shader_parameter(k, colors[k])
	mesh.surface_set_material(0, sm)
	water.ground_mat = sm
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	parent.add_child(body)


## Swaying swamp-grass tufts wherever the patch map says grass (not in mud or water).
static func _grass(parent: Node3D, rng: RandomNumberGenerator, half: float, water: SwampWater, patches: Image) -> void:
	var xforms: Array[Transform3D] = []
	var step := 1.35
	var extent := half + 10.0
	var z := -half
	while z < half:
		var x := -half
		while x < half:
			var px := x + rng.randf_range(-0.6, 0.6)
			var pz := z + rng.randf_range(-0.6, 0.6)
			var m := _sample(patches, extent, px, pz)
			if m.g > 0.6 and m.r < 0.57 and not water.near_pool(px, pz, 0.8) and Vector2(px, pz).length() > 3.0:
				var s := rng.randf_range(0.7, 1.35)
				xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(px, water.ground_height(px, pz) - 0.04, pz)))   # on the hills, not at y = 0
			x += step
		z += step
	_multimesh(parent, _tuft_mesh(rng), xforms)


static func _tuft_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf() * 0.5
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var h := rng.randf_range(0.35, 0.8)
		var base := out * rng.randf_range(0.0, 0.12)
		var tip := base + out * rng.randf_range(0.12, 0.35) + Vector3(0, h, 0)
		var w := 0.035
		var base_col := Color(0.12, 0.16, 0.06, 0.0)
		var tip_col := Color(0.38, 0.4, 0.17, 1.0) if k % 3 else Color(0.3, 0.36, 0.12, 1.0)
		st.set_normal(Vector3.UP)
		st.set_color(base_col)
		st.add_vertex(base - side * w)
		st.set_color(base_col)
		st.add_vertex(base + side * w)
		st.set_color(tip_col)
		st.add_vertex(tip)
	var mesh := st.commit()
	mesh.surface_set_material(0, MeshBuilder.prop_material())
	return mesh


## Reeds and cattails ringing the pools.
static func _reeds(parent: Node3D, rng: RandomNumberGenerator, water: SwampWater) -> void:
	var xforms: Array[Transform3D] = []
	for p in water.pools:
		var c: Vector2 = p["center"]
		for k in int(TAU * float(p["r"]) * rng.randf_range(1.2, 1.8)):   # reeds all round the shore
			var th := rng.randf() * TAU
			var r := water.outline_radius(p, th) * rng.randf_range(0.85, 1.15)
			var pos := Vector3(c.x + cos(th) * r, 0, c.y + sin(th) * r)
			pos.y = water.exact_height(pos.x, pos.z) - 0.05
			var s := rng.randf_range(0.8, 1.25)
			xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), pos))
	var mb := MeshBuilder.new()
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf()
		var top := Vector3(cos(a) * 0.15, rng.randf_range(1.1, 1.7), sin(a) * 0.15)
		mb.limb(Vector3.ZERO, top, 0.02, 0.008, Color(0.3, 0.36, 0.14, 0.0).lerp(Color(0.3, 0.36, 0.14, 1.0), 0.5), 4)
		if k % 2 == 0:
			mb.add(MeshBuilder.cyl(0.045, 0.045, 0.22, 6), Transform3D(Basis(), top + Vector3(0, -0.15, 0)), Color(0.3, 0.18, 0.09, 1.0))
	_multimesh(parent, mb.commit(), xforms)


static func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.set_meta("origins", PackedVector3Array(xforms.map(func(x: Transform3D): return x.origin)))   # tests (headless can't read instances back)
	parent.add_child(mmi)


static func _walls(parent: Node3D, half: float, c := Color(0.2, 0.21, 0.19)) -> void:
	# The ground rises into a berm at the edge; the walls stand on top of it, sunk deep
	# enough to cover every dip.
	var top := SwampWater.HILL_HEIGHT + SwampWater.BUMP_HEIGHT + SwampWater.EDGE_RISE + 5.0
	var bottom := -SwampWater.HILL_HEIGHT - SwampWater.BUMP_HEIGHT - 2.0
	var h := top - bottom
	var y := (top + bottom) * 0.5
	var t := 2.0
	var l := half * 2.0 + t * 2.0
	_box(parent, Vector3(0, y, -half - t * 0.5), Vector3(l, h, t), c)
	_box(parent, Vector3(0, y, half + t * 0.5), Vector3(l, h, t), c)
	_box(parent, Vector3(-half - t * 0.5, y, 0), Vector3(t, h, l), c)
	_box(parent, Vector3(half + t * 0.5, y, 0), Vector3(t, h, l), c)


static func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	body.position = at
	parent.add_child(body)
