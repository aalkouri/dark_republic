class_name WizardModel
extends Node3D
## Procedural fire wizard: a coat made of flames (animated shader + rising flame particles),
## a tall crimson pointy hat with a gold band, ember eyes, a charcoal beard and a fire staff.
## Faces -Z. Origin at the feet.

const COAT_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform float hurt = 0.0;
uniform float dim = 1.0;
uniform float height = 1.3;
varying float h;      // 0 at the collar, 1 at the hem
varying float ang;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	h = clamp((height * 0.5 - VERTEX.y) / height, 0.0, 1.0);
	ang = atan(VERTEX.z, VERTEX.x);
	// Hem licks outward and flickers like flame
	float w = sin(ang * 7.0 + TIME * 9.0) * 0.5 + sin(ang * 13.0 - TIME * 13.0) * 0.5;
	float k = h * h * h;
	VERTEX.xz *= 1.0 + k * (0.10 + 0.08 * w);
	VERTEX.y -= k * 0.05 * w;
}

void fragment() {
	// Flame tongues scroll upward
	vec2 q = vec2(ang * 1.6, h * 3.5 + TIME * 2.2);
	float n = noise(q * vec2(3.0, 1.0)) * 0.6 + noise(q * vec2(7.0, 2.3) + 4.0) * 0.4;
	float fire = smoothstep(0.45, 1.05, h * 1.2 + (n - 0.5) * 1.0);
	// Ragged burning hem
	if (h > 0.8 && n < (h - 0.8) * 4.5) {
		discard;
	}
	vec3 robe = vec3(0.40, 0.03, 0.02) * (0.8 + 0.4 * n);
	vec3 hot = mix(vec3(0.95, 0.16, 0.01), vec3(1.0, 0.6, 0.12), fire * fire);
	ALBEDO = mix(robe, hot, fire);
	EMISSION = hot * fire * 1.4 + vec3(0.5, 0.03, 0.0) * (1.0 - fire) * 0.2 + vec3(hurt * 2.0);
	ROUGHNESS = 0.75;
	ALBEDO *= dim;
	EMISSION *= dim;
}
"""

var _coat_mat: ShaderMaterial
var _sleeve_mat: ShaderMaterial
var _staff_light: OmniLight3D
var _orb: MeshInstance3D

# Staff attack: the staff pivots at the hand, swings down to point at the target,
# holds briefly, then eases back upright.
const HAND := Vector3(0.52, 1.0, -0.2)
const TIP := Vector3(0.0, 1.07, 0.0)       # top of the orb, in pivot space
const ATTACK_HOLD := 0.08
const ATTACK_RETURN := 0.22
var staff_pivot: Node3D
var _aim := Quaternion.IDENTITY
var _attack_t := 0.0
var _time := 0.0
var _dim := 1.0
var _std_mats: Array = []   # [material, albedo, emission energy]
var _particles: Array = []
var _light_base := 1.4


func _ready() -> void:
	_coat_mat = _make_coat_mat(1.3)
	_sleeve_mat = _make_coat_mat(0.7)

	# Coat: flared cone from shoulders to the floor
	var coat := CylinderMesh.new()
	coat.top_radius = 0.22
	coat.bottom_radius = 0.58
	coat.height = 1.3
	coat.radial_segments = 32
	coat.rings = 10
	coat.cap_top = false
	coat.cap_bottom = false
	coat.material = _coat_mat
	_add(coat, Vector3(0, 0.65, 0))

	# Sleeves
	for side in [-1.0, 1.0]:
		var sleeve := CylinderMesh.new()
		sleeve.top_radius = 0.09
		sleeve.bottom_radius = 0.16
		sleeve.height = 0.7
		sleeve.radial_segments = 12
		sleeve.rings = 4
		sleeve.cap_top = false
		sleeve.material = _sleeve_mat
		var mi := _add(sleeve, Vector3(0.3 * side, 1.02, -0.05))
		mi.rotation = Vector3(deg_to_rad(-25.0), 0, deg_to_rad(28.0 * side))

	build_head(self)

	# Fire staff in the right hand
	var staff := CylinderMesh.new()
	staff.top_radius = 0.035
	staff.bottom_radius = 0.045
	staff.height = 1.9
	staff.radial_segments = 8
	staff.material = _mat(Color(0.25, 0.14, 0.08))
	staff_pivot = Node3D.new()
	staff_pivot.position = HAND
	add_child(staff_pivot)
	var staff_mi := MeshInstance3D.new()
	staff_mi.mesh = staff
	staff_mi.position = Vector3(0, -0.05, 0)
	staff_pivot.add_child(staff_mi)
	var orb_mat := _mat(Color(1.0, 0.6, 0.15))
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(1.0, 0.4, 0.05)
	orb_mat.emission_energy_multiplier = 5.0
	var orb := SphereMesh.new()
	orb.radius = 0.12
	orb.height = 0.24
	orb.material = orb_mat
	_orb = MeshInstance3D.new()
	_orb.mesh = orb
	_orb.position = Vector3(0, 0.95, 0)
	staff_pivot.add_child(_orb)
	var orb_fire := Abilities._flame_particles(0.35, 0.6, 24)
	orb_fire.emission_sphere_radius = 0.08
	_orb.add_child(orb_fire)
	_staff_light = OmniLight3D.new()
	_staff_light.light_color = Color(1.0, 0.5, 0.15)
	_staff_light.light_energy = 1.6
	_staff_light.omni_range = 6.0
	_orb.add_child(_staff_light)

	# Flames licking up off the coat hem
	var hem_fire := Abilities._flame_particles(0.35, 0.5, 28)
	hem_fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	hem_fire.emission_ring_axis = Vector3.UP
	hem_fire.emission_ring_radius = 0.55
	hem_fire.emission_ring_inner_radius = 0.3
	hem_fire.emission_ring_height = 0.1
	hem_fire.position.y = 0.15
	add_child(hem_fire)


## Head, ember eyes, beard and hat, at the same coordinates as on the full model
## (head centre at y = 1.5). Also used for the giant flaming meteor head.
static func build_head(parent: Node3D) -> void:
	# Head
	var skin := _smat(Color(0.93, 0.72, 0.58))
	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	head.material = skin
	_put(parent, head, Vector3(0, 1.5, 0))

	# Ember eyes
	var eye_mat := _smat(Color(1.0, 0.6, 0.1))
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.45, 0.05)
	eye_mat.emission_energy_multiplier = 4.0
	for side in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.035
		eye.height = 0.07
		eye.material = eye_mat
		_put(parent, eye, Vector3(0.075 * side, 1.53, -0.18))

	# Charcoal beard
	var beard := CylinderMesh.new()
	beard.top_radius = 0.17
	beard.bottom_radius = 0.0
	beard.height = 0.42
	beard.radial_segments = 10
	beard.material = _smat(Color(0.2, 0.18, 0.18))
	var bmi := _put(parent, beard, Vector3(0, 1.28, -0.12))
	bmi.rotation.x = deg_to_rad(12.0)

	# Hat: wide brim, gold band, cone in two segments with a tip bent backwards
	var hat_mat := _smat(Color(0.5, 0.03, 0.03))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.5
	brim.bottom_radius = 0.52
	brim.height = 0.04
	brim.radial_segments = 28
	brim.material = hat_mat
	_put(parent, brim, Vector3(0, 1.66, 0))
	var band_mat := _smat(Color(1.0, 0.7, 0.2))
	band_mat.emission_enabled = true
	band_mat.emission = Color(1.0, 0.45, 0.05)
	band_mat.emission_energy_multiplier = 1.5
	var band := CylinderMesh.new()
	band.top_radius = 0.255
	band.bottom_radius = 0.275
	band.height = 0.08
	band.radial_segments = 24
	band.material = band_mat
	_put(parent, band, Vector3(0, 1.72, 0))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = 0.27
	cone.height = 0.55
	cone.radial_segments = 20
	cone.material = hat_mat
	_put(parent, cone, Vector3(0, 1.955, 0))
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.12
	tip.height = 0.5
	tip.radial_segments = 16
	tip.material = hat_mat
	var tip_pivot := Node3D.new()
	tip_pivot.position = Vector3(0, 2.23, 0)
	tip_pivot.rotation.x = deg_to_rad(28.0)   # bends backwards (+Z)
	parent.add_child(tip_pivot)
	var tmi := MeshInstance3D.new()
	tmi.mesh = tip
	tmi.position.y = 0.25
	tip_pivot.add_child(tmi)


static func _put(parent: Node3D, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	parent.add_child(mi)
	return mi


static func _smat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _make_coat_mat(height: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = COAT_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("height", height)
	return m


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _add(mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	add_child(mi)
	return mi


## Scale the whole character's brightness (1 = normal, 0.5 = immune).
func set_dim(f: float) -> void:
	if is_equal_approx(f, _dim):
		return
	_dim = f
	if _std_mats.is_empty():
		_collect(self)
	_coat_mat.set_shader_parameter("dim", f)
	_sleeve_mat.set_shader_parameter("dim", f)
	for e in _std_mats:
		var m: StandardMaterial3D = e[0]
		var c: Color = e[1]
		m.albedo_color = Color(c.r * f, c.g * f, c.b * f, c.a)
		m.emission_energy_multiplier = e[2] * f
	for p in _particles:
		(p as CPUParticles3D).color = Color(f, f, f, 1.0)


func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		var mesh := (n as MeshInstance3D).mesh
		if mesh is PrimitiveMesh and (mesh as PrimitiveMesh).material is StandardMaterial3D:
			var m: StandardMaterial3D = (mesh as PrimitiveMesh).material
			for e in _std_mats:
				if e[0] == m:
					m = null
					break
			if m != null:
				_std_mats.append([m, m.albedo_color, m.emission_energy_multiplier])
	elif n is CPUParticles3D:
		_particles.append(n)
	for c in n.get_children():
		_collect(c)


## Swing the staff down to point at `target` (world space) and return the world position
## of the staff tip, where projectiles should spawn.
func attack(target: Vector3) -> Vector3:
	var hand_world := global_transform * HAND
	var dir := target - hand_world
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	var local_dir := (global_transform.basis.orthonormalized().inverse() * dir).normalized()
	_aim = Quaternion(Vector3.UP, local_dir)
	staff_pivot.quaternion = _aim
	_attack_t = ATTACK_HOLD + ATTACK_RETURN
	return staff_pivot.global_transform * TIP


func staff_tip() -> Vector3:
	return staff_pivot.global_transform * TIP


func set_hurt(amount: float) -> void:
	_coat_mat.set_shader_parameter("hurt", amount)
	_sleeve_mat.set_shader_parameter("hurt", amount)


func _process(dt: float) -> void:
	_time += dt
	if _attack_t > 0.0:
		_attack_t = maxf(0.0, _attack_t - dt)
		var w := clampf(_attack_t / ATTACK_RETURN, 0.0, 1.0)   # 1 while holding, eases to 0
		staff_pivot.quaternion = Quaternion.IDENTITY.slerp(_aim, w * w * (3.0 - 2.0 * w))
	_staff_light.light_energy = (_light_base + 0.4 * sin(_time * 17.0) * sin(_time * 7.3)) * _dim
