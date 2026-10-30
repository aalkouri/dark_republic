class_name AcidPuddle
extends Node3D
## The acid puddle a Volatile Flask leaves: an irregular, lobed splash (never a perfect disc)
## with a few stray droplets round its edge, a bright meniscus, porous foam pits that swell and
## pop in the shader, and real little bubbles welling up out of it and bursting into specks.
## Drapes over the hills the same way GroundDisc does. Fades out through `alpha` (0..1).

const SHADER := """
shader_type spatial;
render_mode unshaded, world_vertex_coords, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 body : source_color = vec4(0.36, 0.86, 0.12, 1.0);
uniform vec4 deep : source_color = vec4(0.14, 0.42, 0.04, 1.0);
uniform vec4 glow : source_color = vec4(0.82, 1.0, 0.45, 1.0);
uniform float alpha = 1.0;
uniform float shrink = 0.0;          // 0..1 the puddle evaporating inwards as it fades
uniform vec4 lobes = vec4(0.07, 0.06, 0.04, 0.02);
uniform vec4 phase = vec4(0.0);
uniform float base_r = 0.78;
uniform vec3 drops[4];               // stray droplets: xy (local, -1..1), z radius
uniform float seed = 0.0;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float h_origin = 0.0;
uniform float h_size = 1.0;
uniform float has_height = 0.0;
uniform float lift = 0.08;
varying vec2 local_uv;

void vertex() {
	local_uv = UV;
	if (has_height > 0.5) {
		vec2 uv = (VERTEX.xz - h_origin + 0.5) / h_size;
		VERTEX.y = texture(height_tex, uv).r + lift;
	}
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p + seed) * 43758.5453);
}

// Foam pits: cells that each hold a bubble swelling then popping on its own clock.
// Returns (dark pit, bright rim).
vec2 pores(vec2 p, float speed) {
	vec2 c = floor(p);
	vec2 f = fract(p);
	vec2 res = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 h = hash2(c + g);
			if (h.x < 0.35) { continue; }
			vec2 o = 0.2 + 0.6 * hash2(c + g + 17.0);
			float life = fract(TIME * speed * (0.6 + h.y) + h.x * 7.0);
			float r = mix(0.06, 0.3, h.y) * smoothstep(0.0, 0.85, life) * (1.0 - smoothstep(0.92, 1.0, life));
			float d = length(g + o - f);
			res.x = max(res.x, 1.0 - smoothstep(r * 0.55, r * 0.8, d));
			res.y = max(res.y, smoothstep(r * 0.6, r * 0.85, d) * (1.0 - smoothstep(r * 0.9, r * 1.05, d)) * step(0.01, r));
		}
	}
	return res;
}

void fragment() {
	vec2 p = (local_uv - 0.5) * 2.0;
	float d = length(p);
	float a = atan(p.y, p.x);
	float edge = base_r + lobes.x * sin(2.0 * a + phase.x) + lobes.y * sin(3.0 * a + phase.y)
		+ lobes.z * sin(5.0 * a + phase.z) + lobes.w * sin(8.0 * a + phase.w)
		+ 0.015 * sin(13.0 * a + phase.x * 2.3) + 0.01 * sin(21.0 * a + phase.y * 3.1);
	// a slow wobble, as if the surface were seething
	edge += 0.012 * sin(TIME * 2.1 + a * 4.0 + phase.z);
	edge *= 1.0 - 0.35 * shrink;
	float sdf = d - edge;
	for (int i = 0; i < 4; i++) {
		if (drops[i].z > 0.0) {
			sdf = smin(sdf, length(p - drops[i].xy) - drops[i].z * (1.0 - shrink), 0.09);
		}
	}
	float inside = 1.0 - smoothstep(-0.02, 0.008, sdf);
	if (inside <= 0.001) { discard; }
	float depth = smoothstep(-0.02, -0.45, sdf);         // 0 at the shore, 1 deep inside
	float rim = 1.0 - smoothstep(0.0, 0.07, -sdf);        // the bright meniscus
	vec3 col = mix(body.rgb, deep.rgb, depth * 0.75);
	vec2 big = pores(p * 6.0, 0.9);
	vec2 small = pores(p * 13.0 + 3.7, 1.4);
	float pit = max(big.x, small.x * 0.8);
	float ring = max(big.y, small.y * 0.7);
	col = mix(col, deep.rgb * 0.45, pit * 0.75);
	col = mix(col, glow.rgb, max(ring * 0.85, rim * 0.8));
	// a little sheen sliding across
	float sheen = pow(max(0.0, sin(p.x * 3.0 + p.y * 2.0 + TIME * 0.8 + seed)), 12.0) * 0.25;
	col += glow.rgb * sheen * depth;
	ALBEDO = col;
	ALPHA = inside * alpha * (0.62 + 0.25 * depth + 0.2 * rim);
}
"""

static var _shader: Shader
static var _bubble_mesh: SphereMesh
static var _speck_mesh: SphereMesh
static var _shard_mesh: BoxMesh

var radius := 3.0
var lobes := Vector4.ZERO
var phases := Vector4.ZERO
var base_r := 0.78
var drops: Array = []        # Vector3 (x, y, r) in local units
var alpha := 1.0:
	set(v):
		alpha = v
		if _mat:
			_mat.set_shader_parameter("alpha", v)
			_mat.set_shader_parameter("shrink", 1.0 - clampf(v, 0.0, 1.0))
		if v < 0.99:
			for e in [bubbles, specks]:
				if e != null:
					e.emitting = false
var mesh: MeshInstance3D
var bubbles: CPUParticles3D
var specks: CPUParticles3D
var shards: CPUParticles3D
var _mat: ShaderMaterial


## Puddle edge (in units of the puddle's scale) at `angle` radians, matching the shader's
## outline without the droplets and wobble. Used by the bubble emitter and the tests.
func edge_radius(angle: float) -> float:
	return base_r + lobes.x * sin(2.0 * angle + phases.x) + lobes.y * sin(3.0 * angle + phases.y) \
		+ lobes.z * sin(5.0 * angle + phases.z) + lobes.w * sin(8.0 * angle + phases.w) \
		+ 0.015 * sin(13.0 * angle + phases.x * 2.3) + 0.01 * sin(21.0 * angle + phases.y * 3.1)


## Shortest over longest edge radius: 1 for a circle.
func roundness() -> float:
	var lo := 9.0
	var hi := 0.0
	for k in 72:
		var r := edge_radius(k * TAU / 72.0)
		lo = minf(lo, r)
		hi = maxf(hi, r)
	return lo / hi


static func create(p_radius: float, at: Vector3, parent: Node) -> AcidPuddle:
	var pd := AcidPuddle.new()
	pd.radius = p_radius
	pd.top_level = true
	parent.add_child(pd)
	pd.global_position = at
	pd._build(at)
	return pd


func _build(at: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	lobes = Vector4(rng.randf_range(0.05, 0.08), rng.randf_range(0.04, 0.07), rng.randf_range(0.025, 0.045), rng.randf_range(0.012, 0.025))
	phases = Vector4(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	base_r = 0.78
	for i in rng.randi_range(2, 4):   # stray splashes past the shore
		var ang := rng.randf() * TAU
		for _try in 6:
			if edge_radius(ang) < 0.82:
				break
			ang = rng.randf() * TAU
		var r := minf(edge_radius(ang) + rng.randf_range(0.05, 0.11), 0.9)
		drops.append(Vector3(cos(ang) * r, sin(ang) * r, rng.randf_range(0.035, 0.07)))
	_build_mesh(rng)
	_build_particles(at, rng)
	# Splashes out from where the vial broke
	mesh.scale = Vector3(radius * 1.12 * 0.35, 1.0, radius * 1.12 * 0.35)
	mesh.create_tween().tween_property(mesh, "scale", Vector3(radius * 1.12, 1.0, radius * 1.12), 0.28) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _build_mesh(rng: RandomNumberGenerator) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.render_priority = 2
	_mat.set_shader_parameter("lobes", lobes)
	_mat.set_shader_parameter("phase", phases)
	_mat.set_shader_parameter("base_r", base_r)
	_mat.set_shader_parameter("seed", rng.randf() * 100.0)
	var arr := PackedVector3Array()
	for i in 4:
		arr.append(drops[i] if i < drops.size() else Vector3.ZERO)
	_mat.set_shader_parameter("drops", arr)
	var ground := SwampWater.current
	if ground != null and ground.height_texture != null:
		_mat.set_shader_parameter("height_tex", ground.height_texture)
		_mat.set_shader_parameter("h_origin", ground.horigin)
		_mat.set_shader_parameter("h_size", float(ground.hsize))
		_mat.set_shader_parameter("has_height", 1.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.subdivide_width = 20
	plane.subdivide_depth = 20
	plane.material = _mat
	mesh = MeshInstance3D.new()
	mesh.mesh = plane
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.extra_cull_margin = 16.0
	add_child(mesh)


## Points scattered over the puddle's surface (world offsets from its centre, on the ground).
func _surface_points(at: Vector3, n: int, rng: RandomNumberGenerator, lift: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var s := radius * 1.12
	for i in n:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * edge_radius(ang) * 0.85 * s
		var x := cos(ang) * r
		var z := sin(ang) * r
		var y := SwampWater.height_at(at.x + x, at.z + z) - at.y if SwampWater.current != null else 0.0
		pts.append(Vector3(x, y + lift, z))
	return pts


static func _unlit(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.disable_fog = true
	return m


func _build_particles(at: Vector3, rng: RandomNumberGenerator) -> void:
	if _bubble_mesh == null:
		_bubble_mesh = SphereMesh.new()
		_bubble_mesh.radius = 0.07
		_bubble_mesh.height = 0.12   # a little squashed, sitting on the surface
		_bubble_mesh.radial_segments = 8
		_bubble_mesh.rings = 4
		_bubble_mesh.material = _unlit(Color(1, 1, 1, 1))
		_speck_mesh = SphereMesh.new()
		_speck_mesh.radius = 0.025
		_speck_mesh.height = 0.05
		_speck_mesh.radial_segments = 6
		_speck_mesh.rings = 3
		_speck_mesh.material = _unlit(Color(1, 1, 1, 1))
		_shard_mesh = BoxMesh.new()
		_shard_mesh.size = Vector3(0.09, 0.015, 0.05)
		_shard_mesh.material = _unlit(Color(1, 1, 1, 1))
	var area := radius / 3.0
	# Bubbles: well up, swell, and pop
	bubbles = CPUParticles3D.new()
	bubbles.mesh = _bubble_mesh
	bubbles.amount = int(clampf(16.0 * area, 8, 40))
	bubbles.lifetime = 0.8
	bubbles.randomness = 0.6
	bubbles.lifetime_randomness = 0.4
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	bubbles.emission_points = _surface_points(at, 40, rng, 0.04)
	bubbles.direction = Vector3.UP
	bubbles.spread = 12.0
	bubbles.initial_velocity_min = 0.05
	bubbles.initial_velocity_max = 0.35
	bubbles.gravity = Vector3(0, 0.5, 0)
	bubbles.scale_amount_min = 0.5
	bubbles.scale_amount_max = 1.7
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.1))
	sc.add_point(Vector2(0.7, 0.85))
	sc.add_point(Vector2(0.86, 1.2))
	sc.add_point(Vector2(0.9, 0.0))   # pop
	sc.add_point(Vector2(1.0, 0.0))
	bubbles.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.95, 0.2, 0.75))
	g.set_color(1, Color(0.85, 1.0, 0.55, 0.9))
	bubbles.color_ramp = g
	bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bubbles)
	# Specks flicked up as bubbles burst
	specks = CPUParticles3D.new()
	specks.mesh = _speck_mesh
	specks.amount = int(clampf(10.0 * area, 6, 24))
	specks.lifetime = 0.4
	specks.randomness = 0.8
	specks.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	specks.emission_points = _surface_points(at, 30, rng, 0.12)
	specks.direction = Vector3.UP
	specks.spread = 55.0
	specks.initial_velocity_min = 0.8
	specks.initial_velocity_max = 2.0
	specks.gravity = Vector3(0, -9.8, 0)
	specks.color = Color(0.75, 1.0, 0.4, 0.85)
	specks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(specks)
	# The vial's glass flying apart, and a splash of acid with it
	shards = CPUParticles3D.new()
	shards.mesh = _shard_mesh
	shards.amount = 14
	shards.one_shot = true
	shards.explosiveness = 1.0
	shards.lifetime = 0.55
	shards.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	shards.emission_sphere_radius = 0.15
	shards.position.y = 0.3
	shards.direction = Vector3.UP
	shards.spread = 75.0
	shards.initial_velocity_min = 2.5
	shards.initial_velocity_max = 5.0
	shards.gravity = Vector3(0, -14.0, 0)
	shards.angular_velocity_min = -720.0
	shards.angular_velocity_max = 720.0
	shards.particle_flag_rotate_y = true
	var sg := Gradient.new()
	sg.set_color(0, Color(0.85, 1.0, 0.92, 0.9))
	sg.set_color(1, Color(0.6, 0.9, 0.7, 0.0))
	shards.color_ramp = sg
	shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shards)
	shards.emitting = true
