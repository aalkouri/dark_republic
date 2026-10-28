class_name StaffFlame
extends Node3D
## The fire on top of the wizard's staff: a burning coal plus a shader-drawn flame.
##
## The flame is a camera-facing quad that stays upright in world space (fire rises no matter
## how the staff is tilted). Layered fbm noise scrolls upward to make licking tongues, with a
## white-yellow core, orange body and dark red tips that break up into wisps. The top of the
## flame trails behind when the staff moves (fed from the staff's velocity), and a few sparks
## spit off. A flickering light is driven by the same noise.

const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec2 size = vec2(0.22, 0.42);   // width, height in metres
uniform vec3 drag = vec3(0.0);           // world-space offset of the flame tip (motion trail)
uniform float intensity = 1.0;
uniform float seed = 0.0;
varying float h;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	to_cam.y = 0.0;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), normalize(to_cam + vec3(0.0001))));
	h = VERTEX.y + 0.5;                        // 0 at the base, 1 at the tip
	vec3 world = center + right * VERTEX.x * size.x + vec3(0.0, h * size.y, 0.0) + drag * h * h;
	world.y -= size.y * 0.08;                 // base sits a little into the coal
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 uv = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);   // x -1..1, y 0 (base) .. 1 (tip)
	float t = TIME * 1.0 + seed * 13.0;
	// Turbulence grows with height; the whole flame sways a little
	float sway = (fbm(vec2(t * 0.8, seed)) - 0.5) * 0.5 * uv.y;
	float n1 = fbm(vec2(uv.x * 2.2, uv.y * 2.6 - t * 2.4));
	float n2 = fbm(vec2(uv.x * 4.5 + 3.0, uv.y * 5.0 - t * 3.6));
	float n3 = fbm(vec2(uv.x * 9.0 - 2.0, uv.y * 9.0 - t * 5.5));
	float x = uv.x + sway + (n1 - 0.5) * 1.25 * uv.y + (n3 - 0.5) * 0.25 * uv.y;
	// Teardrop silhouette: round base, narrowing, ragged tip
	float width = mix(0.72, 0.08, pow(uv.y, 0.7)) * smoothstep(0.0, 0.12, uv.y + 0.03);
	width *= 0.8 + 0.45 * n2;
	float body = 1.0 - smoothstep(0.0, width, abs(x));
	float heat = body * (1.0 - uv.y * 0.85);
	heat *= 0.55 + 0.6 * n2 + 0.35 * n3;                  // licking tongues
	heat -= smoothstep(0.35, 1.0, uv.y) * (1.0 - n1) * 1.0; // tips tear into wisps
	heat = clamp(heat * 1.6, 0.0, 1.0);
	// Colour ramp: deep red -> orange -> yellow -> white-hot core
	vec3 col = mix(vec3(0.45, 0.04, 0.0), vec3(1.0, 0.32, 0.03), smoothstep(0.05, 0.4, heat));
	col = mix(col, vec3(1.0, 0.72, 0.22), smoothstep(0.4, 0.75, heat));
	col = mix(col, vec3(1.0, 0.96, 0.82), smoothstep(0.86, 1.0, heat));
	// A faint blue base where the fuel meets the air
	float blue = (1.0 - smoothstep(0.0, 0.14, uv.y)) * body * 0.55;
	col += vec3(0.05, 0.15, 0.6) * blue;
	float a = smoothstep(0.02, 0.25, heat) * smoothstep(0.0, 0.05, uv.y) * (1.0 - smoothstep(0.9, 1.0, abs(uv.x)));
	ALBEDO = col * intensity * 2.2;
	ALPHA = a;   // additive: only the flame adds light (also keeps transparent viewports clear)
}
"""

const COAL_SHADER := """
shader_type spatial;

uniform float intensity = 1.0;
uniform float dim = 1.0;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void fragment() {
	// Charred crust with glowing cracks that pulse
	float n = noise(lp * 26.0) * 0.6 + noise(lp * 61.0) * 0.4;
	float crack = 1.0 - smoothstep(0.03, 0.12, abs(n - 0.5));
	float pulse = 0.75 + 0.25 * sin(TIME * 3.1 + n * 9.0);
	ALBEDO = vec3(0.06, 0.035, 0.03) * dim;
	ROUGHNESS = 0.95;
	EMISSION = mix(vec3(0.9, 0.18, 0.02), vec3(1.0, 0.65, 0.2), crack) * (0.35 + crack * 2.8) * pulse * intensity * dim;
}
"""

const TRAIL := 0.12          # how far (s of velocity) the tip lags behind motion
const MAX_DRAG := 0.18

var light: OmniLight3D
var _flame_mat: ShaderMaterial
var _coal_mat: ShaderMaterial
var _sparks: CPUParticles3D
var _last := Vector3.ZERO
var _drag := Vector3.ZERO
var _time := 0.0
var _dim := 1.0
var _seed := 0.0


func _ready() -> void:
	_seed = randf() * 10.0
	# Burning coal cradled in the staff's crown
	var coal := SphereMesh.new()
	coal.radius = 0.045
	coal.height = 0.08
	coal.radial_segments = 16
	coal.rings = 8
	_coal_mat = ShaderMaterial.new()
	_coal_mat.shader = Shader.new()
	_coal_mat.shader.code = COAL_SHADER
	var coal_mi := MeshInstance3D.new()
	coal_mi.mesh = coal
	coal_mi.material_override = _coal_mat
	add_child(coal_mi)

	# Two flame layers: a big outer flame and a smaller, brighter inner one
	_flame_mat = _make_flame(Vector2(0.26, 0.46), 1.0, _seed)
	var inner := _make_flame(Vector2(0.13, 0.24), 0.7, _seed + 4.2)
	for m in [_flame_mat, inner]:
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 1.0
		add_child(mi)
	set_meta("inner", inner)

	# Sparks spitting upward
	_sparks = CPUParticles3D.new()
	_sparks.amount = 10
	_sparks.lifetime = 0.9
	_sparks.local_coords = false
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 0.04
	_sparks.direction = Vector3.UP
	_sparks.spread = 25.0
	_sparks.gravity = Vector3(0, 0.6, 0)
	_sparks.initial_velocity_min = 0.4
	_sparks.initial_velocity_max = 1.1
	_sparks.damping_min = 0.5
	_sparks.damping_max = 1.0
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.0
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.006
	spark_mesh.height = 0.012
	spark_mesh.radial_segments = 4
	spark_mesh.rings = 2
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.disable_fog = true   # additive + fog = pale grey halos
	spark_mesh.material = spark_mat
	_sparks.mesh = spark_mesh
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.5))
	grad.set_color(1, Color(0.9, 0.2, 0.0, 0.0))
	_sparks.color_ramp = grad
	add_child(_sparks)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position = Vector3(0, 0.12, 0)
	add_child(light)
	_last = global_position


func _make_flame(sz: Vector2, power: float, sd: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = FLAME_SHADER
	m.set_shader_parameter("size", sz)
	m.set_shader_parameter("intensity", power)
	m.set_shader_parameter("seed", sd)
	return m


func set_dim(f: float) -> void:
	_dim = f
	_coal_mat.set_shader_parameter("dim", f)
	_flame_mat.set_shader_parameter("intensity", f)
	(get_meta("inner") as ShaderMaterial).set_shader_parameter("intensity", 0.8 * f)
	_sparks.color = Color(f, f, f, 1.0)


func _process(dt: float) -> void:
	if dt <= 0.0:
		return
	_time += dt
	# Tip trails behind the motion of the staff head (world space)
	var p := global_position
	var vel := (p - _last) / dt
	_last = p
	var want := (-vel * TRAIL).limit_length(MAX_DRAG)
	want.y = minf(want.y, 0.02)   # moving down doesn't stretch the flame upward much
	_drag = _drag.lerp(want, 1.0 - exp(-10.0 * dt))
	_flame_mat.set_shader_parameter("drag", _drag)
	(get_meta("inner") as ShaderMaterial).set_shader_parameter("drag", _drag * 0.7)
	# Flicker
	var f := 0.82 + 0.12 * sin(_time * 17.0 + _seed) * sin(_time * 7.3) + 0.06 * sin(_time * 31.0)
	light.light_energy = 1.6 * f * _dim
