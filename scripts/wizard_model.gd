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
uniform float train = 0.0;   // 1 = back of the robe trails along the floor
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
	// Train: the back (+Z, the wizard faces -Z) is longer and drags along the floor behind him;
	// the front hem is a little shorter.
	float back = clamp(VERTEX.z / 0.55, -1.0, 1.0);
	float hem = pow(h, 4.0);
	VERTEX.z += max(back, 0.0) * max(back, 0.0) * hem * 0.75 * train;
	VERTEX.y += max(-back, 0.0) * hem * 0.12 * train;
	VERTEX.y = max(VERTEX.y, -height * 0.5 + 0.01);   // rests on the ground
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
const HAND := Vector3(0.36, 1.0, -0.34)     # staff pivot = right-hand grip, in front of the body
const TIP := Vector3(0.0, 1.07, 0.0)       # top of the orb, in pivot space
const GRIP_LOW := Vector3(0.0, 0.0, 0.0)     # right hand, in staff-pivot space
const GRIP_HIGH := Vector3(0.0, 0.3, 0.0)    # left hand, higher up the staff
const SHOULDER_R := Vector3(0.24, 1.3, -0.02)
const SHOULDER_L := Vector3(-0.24, 1.3, -0.02)
const SLEEVE_LEN := 0.7
const ATTACK_HOLD := 0.08
const ATTACK_RETURN := 0.22
var staff_pivot: Node3D
var _sleeves: Array[MeshInstance3D] = []
var _hands: Array[MeshInstance3D] = []
var _aim := Quaternion.IDENTITY
var _attack_t := 0.0
var _time := 0.0
var _dim := 1.0
var _std_mats: Array = []   # [material, albedo, emission energy]
var _particles: Array = []
var _dim_shaders: Array = []
var _light_base := 1.4


func _ready() -> void:
	_coat_mat = _make_coat_mat(1.3)
	_coat_mat.set_shader_parameter("train", 1.0)
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

	# Sleeves (posed every frame from shoulder to grip, so both hands stay on the staff)
	for k in 2:
		var sleeve := CylinderMesh.new()
		sleeve.top_radius = 0.085
		sleeve.bottom_radius = 0.15
		sleeve.height = SLEEVE_LEN
		sleeve.radial_segments = 12
		sleeve.rings = 4
		sleeve.cap_top = false
		sleeve.material = _sleeve_mat
		var mi := MeshInstance3D.new()
		mi.mesh = sleeve
		add_child(mi)
		_sleeves.append(mi)

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
	# Hands gripping the staff (children of the staff, so they follow every swing)
	var hand_mat := _mat(Color(0.93, 0.72, 0.58))
	for grip in [GRIP_LOW, GRIP_HIGH]:
		var hm := SphereMesh.new()
		hm.radius = 0.075
		hm.height = 0.13
		hm.material = hand_mat
		var h := MeshInstance3D.new()
		h.mesh = hm
		h.position = grip
		h.scale = Vector3(1.0, 1.15, 1.0)
		staff_pivot.add_child(h)
		_hands.append(h)
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

	# Hat: a sculpted, wrinkled, grimy felt cone whose tip bends over to the right,
	# on a wavy brim, with a tarnished gold band.
	var felt := _hat_material()
	var brim_mi := _put(parent, _brim_mesh(), Vector3(0, 1.655, 0))
	brim_mi.material_override = felt
	var band_mat := _smat(Color(0.62, 0.45, 0.16))
	band_mat.roughness = 0.6
	band_mat.metallic = 0.4
	band_mat.emission_enabled = true
	band_mat.emission = Color(0.8, 0.35, 0.05)
	band_mat.emission_energy_multiplier = 0.5
	var band := CylinderMesh.new()
	band.top_radius = 0.262
	band.bottom_radius = 0.285
	band.height = 0.085
	band.radial_segments = 24
	band.material = band_mat
	_put(parent, band, Vector3(0, 1.71, 0))
	var cone_mi := _put(parent, _hat_cone_mesh(), Vector3(0, 1.67, 0))
	cone_mi.material_override = felt


const HAT_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 felt : source_color = vec3(0.47, 0.06, 0.045);
uniform float dim = 1.0;
varying vec3 lp;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { lp = VERTEX; }
void fragment() {
	float fibre = noise(lp * 60.0) * 0.5 + noise(lp * 23.0) * 0.5;          // felt texture
	float grime = smoothstep(0.42, 0.78, noise(lp * 6.0 + 3.0));            // dirt patches
	float stain = smoothstep(0.6, 0.9, noise(lp * 13.0 - 7.0));
	vec3 col = felt * (0.72 + 0.4 * fibre);
	col = mix(col, vec3(0.13, 0.09, 0.06), grime * 0.55);
	col = mix(col, vec3(0.22, 0.17, 0.1), stain * 0.35);
	col *= 1.0 - COLOR.r * 0.55;                                            // dark creases
	col = mix(col, col * 1.35 + vec3(0.04, 0.02, 0.0), COLOR.g * 0.6);      // worn ridges
	ALBEDO = col * dim;
	ROUGHNESS = 0.96;
	SPECULAR = 0.2;
}
"""


static func _hat_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = HAT_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## Wrinkled cone on a curved spine. Base at origin (radius ~0.27); the upper half bends to the
## right (+X) and droops at the tip. COLOR.r = crease darkness, COLOR.g = ridge highlight.
static func _hat_cone_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 30
	var segs := 28
	var h := 1.0
	var folds := [0.3, 0.47, 0.62, 0.76]
	var pts := []
	var cols := []
	for ri in rings + 1:
		var t := float(ri) / rings
		# Spine: straight at first, then leaning over to the right and drooping at the end
		var bend := pow(t, 2.4)
		var center := Vector3(0.42 * bend, h * t - 0.22 * pow(t, 4.0), 0.06 * bend)
		var t2 := minf(t + 0.01, 1.0)
		var b2 := pow(t2, 2.4)
		var tangent := (Vector3(0.42 * b2, h * t2 - 0.22 * pow(t2, 4.0), 0.06 * b2) - center).normalized()
		var n := tangent.cross(Vector3.FORWARD).normalized()
		var bn := n.cross(tangent).normalized()
		var r := 0.27 * pow(1.0 - t, 0.85)
		var fold := 0.0
		for f in folds:
			fold += exp(-pow((t - f) / 0.03, 2.0))
		var row := []
		var crow := []
		for si in segs:
			var a := TAU * si / segs
			var w := smoothstep(0.06, 0.35, t)
			var wrinkle := 0.075 * sin(5.0 * a + t * 9.0) + 0.04 * sin(11.0 * a - t * 17.0) + 0.025 * sin(17.0 * a + t * 31.0)
			var rr := r * (1.0 + w * wrinkle) * (1.0 - 0.1 * fold)
			row.append(center + (n * cos(a) + bn * sin(a)) * rr)
			var ridge := clampf(wrinkle * 8.0 * w, 0.0, 1.0)
			crow.append(Color(clampf(fold * 0.8 + maxf(-wrinkle * 6.0 * w, 0.0), 0.0, 1.0), ridge, 0.0))
		pts.append(row)
		cols.append(crow)
	for ri in rings:
		for si in segs:
			var sj := (si + 1) % segs
			var quad := [[ri, si], [ri, sj], [ri + 1, sj], [ri, si], [ri + 1, sj], [ri + 1, si]]
			for q in quad:
				st.set_color(cols[q[0]][q[1]])
				st.add_vertex(pts[q[0]][q[1]])
	st.generate_normals()
	return st.commit()


## Wavy, slightly uneven brim (annulus), drooping a little toward the edge.
static func _brim_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 64
	var rings := 6
	var pts := []
	var cols := []
	for ri in rings + 1:
		var u := float(ri) / rings
		var row := []
		var crow := []
		for si in segs:
			var a := TAU * si / segs
			var outer := 0.53 + 0.035 * sin(3.0 * a + 1.3) + 0.02 * sin(7.0 * a)
			var r := lerpf(0.24, outer, u)
			var wave := (0.045 * sin(5.0 * a + 0.7) + 0.022 * sin(9.0 * a + 2.1)) * u * u
			var droop := -0.03 * u * u
			row.append(Vector3(cos(a) * r, wave + droop, sin(a) * r))
			crow.append(Color(clampf(-wave * 12.0, 0.0, 0.6), clampf(wave * 12.0, 0.0, 0.6), 0.0))
		pts.append(row)
		cols.append(crow)
	for ri in rings:
		for si in segs:
			var sj := (si + 1) % segs
			for q in [[ri, si], [ri + 1, sj], [ri, sj], [ri, si], [ri + 1, si], [ri + 1, sj]]:
				st.set_color(cols[q[0]][q[1]])
				st.add_vertex(pts[q[0]][q[1]])
	st.generate_normals()
	return st.commit()


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
	for sm in _dim_shaders:
		(sm as ShaderMaterial).set_shader_parameter("dim", f)


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
	if n is GeometryInstance3D and (n as GeometryInstance3D).material_override is ShaderMaterial:
		var sm := (n as GeometryInstance3D).material_override as ShaderMaterial
		if not _dim_shaders.has(sm):
			_dim_shaders.append(sm)
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


## Stretch each sleeve from its shoulder to its grip on the staff (cuff end at the hand).
func _pose_arms() -> void:
	var grips := [staff_pivot.transform * GRIP_LOW, staff_pivot.transform * GRIP_HIGH]
	var shoulders := [SHOULDER_R, SHOULDER_L]
	for k in 2:
		var sh: Vector3 = shoulders[k]
		var hand: Vector3 = grips[k]
		var d := sh - hand                  # +Y of the sleeve points back to the shoulder
		var length := maxf(d.length(), 0.05)
		var up := d / length
		var side := up.cross(Vector3.FORWARD)
		if side.length_squared() < 0.001:
			side = up.cross(Vector3.RIGHT)
		side = side.normalized()
		var fwd := side.cross(up)
		var basis := Basis(side, up * (length / SLEEVE_LEN), fwd)
		_sleeves[k].transform = Transform3D(basis, (sh + hand) * 0.5)


func _process(dt: float) -> void:
	_pose_arms()
	_time += dt
	if _attack_t > 0.0:
		_attack_t = maxf(0.0, _attack_t - dt)
		var w := clampf(_attack_t / ATTACK_RETURN, 0.0, 1.0)   # 1 while holding, eases to 0
		staff_pivot.quaternion = Quaternion.IDENTITY.slerp(_aim, w * w * (3.0 - 2.0 * w))
	_staff_light.light_energy = (_light_base + 0.4 * sin(_time * 17.0) * sin(_time * 7.3)) * _dim
