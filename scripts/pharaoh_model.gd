class_name PharaohModel
extends Node3D
## The Pharaoh's body (the Desert's boss): a mummified king, MODEL_HEIGHT tall at scale 1, facing
## -Z, origin at the feet. Built in code as a jointed rig (hips, torso, head, shoulders, elbows,
## hands, hips, knees) and posed in _process.
##
##   Head    a gold death mask in a gold-and-lapis striped nemes, kohl-lined eyes that burn
##           green-gold, the uraeus cobra and the long plaited beard (DesertSphinx.head).
##   Body    wound in yellowed bandages (a woven, grimy linen shader), a broad collar of gold,
##           lapis and carnelian rings, a gold belt and pleated kilt, gold bands on the arms and
##           ankles, a tattered royal-blue cloak, loose bandage ends trailing and swaying.
##   Hands   the crook (left) and the flail (right) in gold and lapis, the flail's three beaded
##           strands swinging.
## Poses: idle / walk (arms crossed on the chest, the Osiride pose; a stiff, dragging stride),
## slam (the flail raised over the head and brought down at `act` 0.75), beam (the crook thrust
## out), summon and raise (both arms up), rise (out of the tomb), die (buckles and crumbles).

const MODEL_HEIGHT := 1.9
const GOLD := Color(1.0, 0.8, 0.36)
const LAPIS := Color(0.14, 0.26, 0.66)
const CARNELIAN := Color(0.72, 0.22, 0.12)
const LINEN := Color(0.8, 0.72, 0.56)
const LINEN_DARK := Color(0.56, 0.48, 0.36)
const CLOAK := Color(0.1, 0.16, 0.36)

const LINEN_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float flash = 0.0;
uniform float enrage = 0.0;
varying vec3 lpos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { lpos = VERTEX; }
void fragment() {
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	// the weave: fine threads one way, the edges of the wraps the other
	float weave = 0.5 + 0.5 * sin(lpos.y * 260.0 + lpos.x * 40.0) * sin(lpos.x * 240.0 - lpos.z * 220.0);
	float edge = smoothstep(0.75, 0.95, abs(sin(lpos.y * 38.0 + lpos.x * 9.0 + lpos.z * 7.0)));
	col *= 0.9 + 0.12 * weave;
	col *= 1.0 - edge * 0.28;
	// grime, resin stains and age
	float g = noise(lpos * 14.0) * 0.6 + noise(lpos * 41.0) * 0.4;
	col *= 0.75 + 0.4 * g;
	col = mix(col, col * vec3(0.55, 0.42, 0.28), smoothstep(0.6, 0.8, noise(lpos * 6.0 + 4.0)) * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	EMISSION = vec3(1.0, 0.85, 0.6) * flash * 1.6 + vec3(1.0, 0.55, 0.1) * enrage * 0.12 * (0.5 + 0.5 * sin(TIME * 6.0 + lpos.y * 8.0));
}
"""

var pose := "walk"
var act := 0.0               # progress through the current attack pose (0..1)
var walk_speed := 0.0        # m/s (at scale 1) for the stride
var rise := 0.0              # 0 = buried, 1 = standing (the tomb)
var die_t := 0.0
var _phase := 0.0
var _flash := 0.0
var _enrage := 0.0
var _linen: ShaderMaterial
var _gold: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var sh_l: Node3D
var sh_r: Node3D
var el_l: Node3D
var el_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var flail_strands: Array[Node3D] = []
var _ribbons: Array[Node3D] = []
var cloak: Node3D
var flail_head: Node3D       # where the flail's strands hang from (slam effects)
var crook_tip: Node3D        # the crook's hook (the curse beam leaves from here)
var _rng := RandomNumberGenerator.new()
# smoothed joint angles
var _ang := {}


func _ready() -> void:
	_rng.seed = 1212
	var sh := Shader.new()
	sh.code = LINEN_SHADER
	_linen = ShaderMaterial.new()
	_linen.shader = sh
	_gold = StandardMaterial3D.new()
	_gold.vertex_color_use_as_albedo = true
	_gold.metallic = 0.85
	_gold.roughness = 0.3
	_gold.emission_enabled = true
	_gold.emission = Color(0, 0, 0)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.2, 0.6, 0.2)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(0.7, 1.0, 0.35)
	_eye_mat.emission_energy_multiplier = 4.0
	_build()


func _part(parent: Node3D, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	parent.add_child(n)
	return n


func _mesh(parent: Node3D, cloth: MeshBuilder, gold: MeshBuilder, glow: MeshBuilder = null) -> void:
	var mesh: ArrayMesh
	if not cloth.is_empty():
		mesh = cloth.commit(_linen)
		if not gold.is_empty():
			gold.commit_into(mesh, _gold)
	elif not gold.is_empty():
		mesh = gold.commit(_gold)
	if glow != null and not glow.is_empty():
		if mesh == null:
			mesh = glow.commit(_eye_mat)
		else:
			glow.commit_into(mesh, _eye_mat)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)


## Bandage wraps round a bone from a to b: a core and tilted, overlapping turns of linen.
func _wrap(mb: MeshBuilder, a: Vector3, b: Vector3, r0: float, r1: float, turns: int) -> void:
	mb.limb(a, b, r0 * 0.94, r1 * 0.94, LINEN_DARK, 8)
	var axis := (b - a).normalized()
	var side := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := side.cross(axis).normalized()
	for k in turns:
		var t := (k + 0.5) / turns
		var r := lerpf(r0, r1, t)
		var basis := Basis(x, axis, x.cross(axis)) * Basis(Vector3(1, 0, 0), _rng.randf_range(-0.3, 0.3)) * Basis(Vector3(0, 0, 1), _rng.randf_range(-0.2, 0.2))
		var c := LINEN.darkened(_rng.randf_range(0.0, 0.2)) if k % 3 else LINEN.lightened(0.04)
		mb.add(MeshBuilder.cyl(r * 1.03, r * 1.06, (b - a).length() / turns * 1.2, 10), Transform3D(basis, a.lerp(b, t)), c)


func _build() -> void:
	# --- hips, legs
	hips = _part(self, Vector3(0, 0.95, 0))
	var pelvis := MeshBuilder.new()
	var pg := MeshBuilder.new()
	pelvis.add(MeshBuilder.sphere(0.17, 10, 6), Transform3D(Basis.from_scale(Vector3(1.25, 0.7, 0.85)), Vector3.ZERO), LINEN_DARK)
	# belt and pleated kilt (shendyt): gold pleats with a lapis-striped front apron
	pg.add(MeshBuilder.cyl(0.215, 0.215, 0.07, 18), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.8)), Vector3(0, 0.05, 0)), GOLD)
	for k in 18:
		var a := TAU * k / 18.0
		var c := GOLD if k % 2 == 0 else Color(0.95, 0.9, 0.78)
		pg.add(MeshBuilder.box(Vector3(0.075, 0.3, 0.02)), Transform3D(Basis(Vector3.UP, a) * Basis(Vector3(1, 0, 0), 0.12), Vector3(sin(a) * 0.22, -0.12, cos(a) * 0.18)), c)
	for k in 5:
		pg.add(MeshBuilder.box(Vector3(0.13 - k * 0.012, 0.06, 0.02)), Transform3D(Basis(), Vector3(0, -0.02 - k * 0.065, -0.2)), LAPIS if k % 2 == 0 else GOLD)
	_mesh(hips, pelvis, pg)
	for sd in [1.0, -1.0]:
		var hip := _part(hips, Vector3(sd * 0.11, -0.04, 0))
		var thigh := MeshBuilder.new()
		_wrap(thigh, Vector3.ZERO, Vector3(0, -0.44, 0), 0.085, 0.07, 5)
		_mesh(hip, thigh, MeshBuilder.new())
		var knee := _part(hip, Vector3(0, -0.44, 0))
		var shin := MeshBuilder.new()
		var sg := MeshBuilder.new()
		_wrap(shin, Vector3.ZERO, Vector3(0, -0.42, 0), 0.07, 0.055, 5)
		sg.add(MeshBuilder.cyl(0.066, 0.066, 0.05, 12), Transform3D(Basis(), Vector3(0, -0.38, 0)), GOLD)   # anklet
		shin.add(MeshBuilder.box(Vector3(0.11, 0.07, 0.26)), Transform3D(Basis(), Vector3(0, -0.47, -0.06)), LINEN_DARK)   # foot
		_mesh(knee, shin, sg)
		if sd > 0:
			hip_r = hip
			knee_r = knee
		else:
			hip_l = hip
			knee_l = knee
	# --- torso: wrapped chest, the broad collar, a tattered cloak
	torso = _part(hips, Vector3(0, 0.0, 0))
	var chest := MeshBuilder.new()
	var cg := MeshBuilder.new()
	_wrap(chest, Vector3(0, 0.05, 0), Vector3(0, 0.55, 0), 0.21, 0.26, 9)
	chest.add(MeshBuilder.sphere(0.25, 12, 8), Transform3D(Basis.from_scale(Vector3(1.25, 0.55, 0.82)), Vector3(0, 0.55, 0)), LINEN)
	for sd in [-1.0, 1.0]:   # broad shoulders
		chest.add(MeshBuilder.sphere(0.11, 10, 6), Transform3D(Basis.from_scale(Vector3(1.2, 0.9, 1.0)), Vector3(sd * 0.25, 0.53, 0)), LINEN.darkened(0.05))
	var rings := [GOLD, LAPIS, GOLD, CARNELIAN, GOLD, LAPIS]
	for r in rings.size():   # the usekh: concentric bands of gold, lapis and carnelian beads
		var rr := 0.1 + r * 0.026
		for q in 13:
			var a := PI * (0.06 + 0.88 * q / 12.0)
			cg.add(MeshBuilder.sphere(0.021, 6, 4), Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 0.6)), Vector3(cos(a) * rr * 1.15, 0.58 - sin(a) * rr * 0.8, -0.215 - sin(a) * 0.03)), rings[r])
	cg.add(MeshBuilder.sphere(0.05, 8, 5), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.4)), Vector3(0, 0.3, -0.21)), CARNELIAN)   # a scarab pectoral
	for sd in [-1.0, 1.0]:
		cg.add(MeshBuilder.box(Vector3(0.09, 0.03, 0.01)), Transform3D(Basis(Vector3(0, 0, 1), sd * 0.4), Vector3(sd * 0.07, 0.31, -0.215)), LAPIS)   # its wings
	_mesh(torso, chest, cg)
	cloak = _part(torso, Vector3(0, 0.56, 0.14))
	var cl := MeshBuilder.new()
	var cg2 := MeshBuilder.new()
	for k in 9:   # a curved, flaring royal cloak in strips, its hem in tatters
		var a := lerpf(-1.25, 1.25, k / 8.0)
		var top := Vector3(sin(a) * 0.3, 0.0, cos(a) * 0.12)
		var bot := Vector3(sin(a) * 0.5, -1.2 - (0.06 if k % 2 else 0.0), cos(a) * 0.3)
		var mid := (top + bot) * 0.5
		var dir := (bot - top).normalized()
		var side := Vector3(cos(a), 0, -sin(a))
		var basis := Basis(side, -dir, side.cross(-dir))
		cl.add(MeshBuilder.box(Vector3(0.17, (bot - top).length(), 0.025)), Transform3D(basis, mid), CLOAK.lerp(Color(0.2, 0.08, 0.1), 0.15 * (k % 3)))
		cl.add(MeshBuilder.box(Vector3(0.12, 0.14 + (k % 3) * 0.05, 0.025)), Transform3D(basis, bot + Vector3(0, -0.08, 0.02)), CLOAK.darkened(0.25))
	cg2.add(MeshBuilder.cyl(0.32, 0.32, 0.04, 16), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.5)), Vector3(0, 0.0, 0.02)), GOLD)   # a gold clasp-band
	_mesh(cloak, cl, cg2)
	# --- head: the gold death mask and nemes
	head = _part(torso, Vector3(0, 0.62, 0))
	var hg := MeshBuilder.new()
	var he := MeshBuilder.new()
	var neck := MeshBuilder.new()
	_wrap(neck, Vector3(0, -0.08, 0), Vector3(0, 0.06, 0), 0.07, 0.07, 3)
	DesertSphinx.head(hg, Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * 0.105), Vector3(0, 0.13, 0)), GOLD, _rng, false, true, he, GOLD, LAPIS)
	_mesh(head, neck, hg, he)
	# --- arms
	for sd in [1.0, -1.0]:
		var shoulder := _part(torso, Vector3(sd * 0.29, 0.5, 0))
		var up := MeshBuilder.new()
		var ug := MeshBuilder.new()
		up.add(MeshBuilder.sphere(0.085, 8, 6), Transform3D(), LINEN)
		_wrap(up, Vector3.ZERO, Vector3(0, -0.3, 0), 0.07, 0.06, 4)
		ug.add(MeshBuilder.cyl(0.072, 0.072, 0.05, 12), Transform3D(Basis(), Vector3(0, -0.1, 0)), GOLD)
		_mesh(shoulder, up, ug)
		var elbow := _part(shoulder, Vector3(0, -0.3, 0))
		var fore := MeshBuilder.new()
		var fg := MeshBuilder.new()
		_wrap(fore, Vector3.ZERO, Vector3(0, -0.27, 0), 0.058, 0.048, 4)
		fg.add(MeshBuilder.cyl(0.058, 0.058, 0.07, 12), Transform3D(Basis(), Vector3(0, -0.22, 0)), GOLD)   # bracelet
		fg.add(MeshBuilder.box(Vector3(0.02, 0.05, 0.02)), Transform3D(Basis(), Vector3(0, -0.22, -0.06)), LAPIS)
		fore.add(MeshBuilder.sphere(0.055, 8, 5), Transform3D(Basis.from_scale(Vector3(0.9, 1.1, 0.8)), Vector3(0, -0.31, 0)), LINEN_DARK)   # fist
		_mesh(elbow, fore, fg)
		var hand := _part(elbow, Vector3(0, -0.31, 0))
		if sd > 0:
			sh_r = shoulder
			el_r = elbow
			hand_r = hand
		else:
			sh_l = shoulder
			el_l = elbow
			hand_l = hand
		for k in 2:   # loose bandage ends trailing from the arm
			var rb := _part(shoulder if k == 0 else elbow, Vector3(sd * 0.05, -0.12, 0.03))
			var rm := MeshBuilder.new()
			rm.add(MeshBuilder.box(Vector3(0.04, 0.36, 0.01)), Transform3D(Basis(), Vector3(0, -0.18, 0)), LINEN.darkened(0.12))
			_mesh(rb, rm, MeshBuilder.new())
			_ribbons.append(rb)
	for k in 4:   # strips hanging from the belt
		var a := TAU * k / 4.0 + 0.4
		var rb := _part(hips, Vector3(sin(a) * 0.2, -0.05, cos(a) * 0.17))
		var rm := MeshBuilder.new()
		rm.add(MeshBuilder.box(Vector3(0.05, 0.5, 0.012)), Transform3D(Basis(Vector3.UP, a), Vector3(0, -0.25, 0)), LINEN.darkened(0.05 * k))
		_mesh(rb, rm, MeshBuilder.new())
		_ribbons.append(rb)
	# --- the crook (left hand) and the flail (right hand): gold and lapis
	var crook := MeshBuilder.new()
	for k in 10:
		crook.add(MeshBuilder.cyl(0.018, 0.018, 0.09, 8), Transform3D(Basis(), Vector3(0, -0.2 + k * 0.09, 0)), GOLD if k % 2 == 0 else LAPIS)
	for k in 7:   # the hook
		var a := k * 0.5
		crook.add(MeshBuilder.cyl(0.018, 0.018, 0.07, 8), Transform3D(Basis(Vector3(1, 0, 0), -a), Vector3(0, 0.7 + sin(a) * 0.1, -(1.0 - cos(a)) * 0.1)), GOLD if k % 2 == 0 else LAPIS)
	_mesh(hand_l, MeshBuilder.new(), crook)
	crook_tip = _part(hand_l, Vector3(0, 0.72, -0.2))
	var flail := MeshBuilder.new()
	for k in 5:
		flail.add(MeshBuilder.cyl(0.016, 0.016, 0.08, 8), Transform3D(Basis(), Vector3(0, -0.12 + k * 0.08, 0)), GOLD if k % 2 == 0 else LAPIS)
	flail.add(MeshBuilder.sphere(0.03, 8, 5), Transform3D(Basis(), Vector3(0, 0.29, 0)), GOLD)
	_mesh(hand_r, MeshBuilder.new(), flail)
	flail_head = _part(hand_r, Vector3(0, 0.3, 0))
	for k in 3:
		var strand := _part(flail_head, Vector3((k - 1) * 0.025, 0, 0))
		var sm := MeshBuilder.new()
		for b in 6:
			sm.add(MeshBuilder.sphere(0.022, 6, 4), Transform3D(Basis.from_scale(Vector3(1.0, 1.4, 1.0)), Vector3(0, -0.035 - b * 0.055, 0)), [GOLD, LAPIS, CARNELIAN][b % 3])
		_mesh(strand, MeshBuilder.new(), sm)
		flail_strands.append(strand)
	# a gold glow about him
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.35)
	l.light_energy = 0.8
	l.omni_range = 4.0
	l.position = Vector3(0, 1.4, -0.6)
	add_child(l)
	_update(0.0)


func flash() -> void:
	_flash = 0.15


func set_enrage(k: float) -> void:
	_enrage = k
	_linen.set_shader_parameter("enrage", k)
	_eye_mat.emission = Color(1.0, 0.45, 0.15) if k > 0.5 else Color(0.7, 1.0, 0.35)
	_eye_mat.emission_energy_multiplier = 7.0 if k > 0.5 else 4.0
	_gold.emission = Color(0.5, 0.3, 0.05) * k


## Instantly strike a pose (tools/render_desert.gd).
func pose_preview(p: String) -> void:
	pose = p
	act = 0.5 if p == "slam" else 1.0
	if p == "walk":
		walk_speed = 1.2
		_phase = 0.6
	_ang.clear()
	_update(0.0)


func _process(dt: float) -> void:
	_update(dt)


func _joint(n: Node3D, x: float, z := 0.0, y := 0.0, dt := 0.0) -> void:
	var key := n.get_instance_id()
	var want := Vector3(x, y, z)
	var cur: Vector3 = _ang.get(key, want)
	cur = cur.lerp(want, clampf(dt * 12.0, 0.0, 1.0)) if dt > 0.0 else want
	_ang[key] = cur
	n.rotation = cur


func _update(dt: float) -> void:
	_phase += dt * maxf(walk_speed, 0.3) * 2.2
	if _flash > 0.0:
		_flash -= dt
	_linen.set_shader_parameter("flash", clampf(_flash / 0.15, 0.0, 1.0))
	var t := Time.get_ticks_msec() / 1000.0
	var sw := sin(_phase) * clampf(walk_speed / 1.2, 0.0, 1.0)
	# defaults: the Osiride pose, crook and flail crossed on the chest, a stiff stride
	var hip_a := sw * 0.45
	var knee_a := -absf(sin(_phase)) * 0.35 * clampf(walk_speed / 1.2, 0.0, 1.0)
	var torso_x := -0.06
	var torso_z := sw * 0.05
	var head_x := 0.05
	var sr := [0.55, -0.55, 0.0]     # right shoulder: pitch, roll, yaw
	var sl := [0.55, 0.55, 0.0]
	var er := 2.15
	var e_l := 2.15
	var y_off := 0.0
	match pose:
		"slam":   # flail raised over the head, then down hard at act 0.75
			var up := clampf(act / 0.7, 0.0, 1.0)
			var down := clampf((act - 0.72) / 0.08, 0.0, 1.0)
			sr = [lerpf(0.55, 3.0, up) - down * 2.4, lerpf(-0.55, 0.1, up), 0.0]
			er = lerpf(2.15, 0.35, up) + down * 0.2
			torso_x = lerpf(-0.06, 0.18, up) - down * 0.45
			hip_a = 0.0
		"beam":   # the crook thrust out toward you
			var k := clampf(act * 3.0, 0.0, 1.0)
			sl = [lerpf(0.55, 1.6, k), lerpf(0.55, -0.05, k), 0.0]
			e_l = lerpf(2.15, 0.1, k)
			torso_x = -0.12 * k
			hip_a = 0.0
		"summon", "raise":   # both arms up: the dead rise / the sands answer
			var k := clampf(act * 2.5, 0.0, 1.0)
			sr = [lerpf(0.55, 2.7, k), lerpf(-0.55, 0.45, k), 0.0]
			sl = [lerpf(0.55, 2.7, k), lerpf(0.55, -0.45, k), 0.0]
			er = lerpf(2.15, 0.3, k)
			e_l = er
			torso_x = 0.15 * k
			head_x = -0.25 * k
			hip_a = 0.0
			knee_a = 0.0
			if pose == "raise":
				y_off = 0.35 + sin(t * 2.0) * 0.05
		"rise":
			torso_x = lerpf(0.4, -0.06, rise)
			head_x = lerpf(0.5, 0.05, rise)
			hip_a = 0.0
			knee_a = 0.0
		"die":   # knees buckle, he slumps, arms fall away
			var k := clampf(die_t / 1.2, 0.0, 1.0)
			knee_a = -1.3 * k
			hip_a = 0.9 * k
			torso_x = -0.6 * k
			head_x = 0.5 * k
			sr = [lerpf(0.55, -0.1, k), lerpf(-0.55, 0.5, k), 0.0]
			sl = [lerpf(0.55, -0.1, k), lerpf(0.55, -0.5, k), 0.0]
			er = lerpf(2.15, 0.2, k)
			e_l = er
			y_off = -0.45 * k
	hips.position = Vector3(0, 0.95 + y_off + absf(sin(_phase)) * 0.025 * clampf(walk_speed, 0.0, 1.0), 0)
	_joint(hip_r, hip_a, 0.0, 0.0, dt)
	_joint(hip_l, -hip_a if pose in ["walk", "idle"] else hip_a, 0.0, 0.0, dt)
	_joint(knee_r, knee_a if sw > 0.0 or pose == "die" else 0.0, 0.0, 0.0, dt)
	_joint(knee_l, knee_a if sw <= 0.0 or pose == "die" else 0.0, 0.0, 0.0, dt)
	_joint(torso, torso_x, torso_z, 0.0, dt)
	_joint(head, head_x, 0.0, 0.0, dt)
	_joint(sh_r, sr[0], sr[1], sr[2], dt)
	_joint(sh_l, sl[0], sl[1], sl[2], dt)
	_joint(el_r, er, 0.0, 0.0, dt)
	_joint(el_l, e_l, 0.0, 0.0, dt)
	# the cloak and the loose bandages sway; the flail's strands swing
	cloak.rotation = Vector3(0.12 + absf(sw) * 0.15 + sin(t * 1.7) * 0.04, 0, sin(t * 1.3) * 0.03)
	for k in _ribbons.size():
		_ribbons[k].rotation = Vector3(0.15 + sin(t * 3.0 + k) * 0.18, 0, sin(t * 2.3 + k * 1.7) * 0.15)
	for k in flail_strands.size():
		var s := flail_strands[k]
		# hang down in world space, swinging with the arm
		var up := s.get_parent_node_3d().global_transform.basis
		var inv := up.inverse()
		var down := (inv * Vector3.DOWN).normalized() if s.is_inside_tree() else Vector3.DOWN
		var tilt := Quaternion(Vector3.DOWN, down)
		s.quaternion = tilt * Quaternion(Vector3(1, 0, 0), sin(t * 5.0 + k) * 0.25)
	if die_t > 1.4:   # crumbling to dust
		var c := clampf((die_t - 1.4) / 2.5, 0.0, 1.0)
		scale.y = maxf(0.05, scale.x * (1.0 - c * 0.9))
