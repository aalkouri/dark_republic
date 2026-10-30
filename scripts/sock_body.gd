class_name SockBody
extends Node3D
## An Argyle Sock, built entirely in code (it has no 3D model): a knitted tube bent into a sock -
## ribbed cuff, leg, heel, foot and toe - about 1.5 m tall, with big googly eyes near the top.
## The argyle diamonds and the yarn lines are drawn by the shader from the UVs (crisp at any
## size); the shader also bends the sock (lean, lunges, flinches) and squashes it as it hops.
## Faces -Z, origin at the bottom of the heel.
##
## RosterHero drives it for the playable sock (animate() every frame); Lost Pair spawns a second
## one in other colours; RosterModel shows one idling on character select.

const HEIGHT := 1.45
const LEG_R := 0.24
const RINGS := 64
const SIDES := 32

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 col_a : source_color = vec3(0.48, 0.24, 0.62);
uniform vec3 col_b : source_color = vec3(0.23, 0.6, 0.56);
uniform vec3 col_line : source_color = vec3(0.95, 0.82, 0.29);
uniform vec3 col_cuff : source_color = vec3(0.93, 0.89, 0.8);
uniform vec3 col_toe : source_color = vec3(0.3, 0.14, 0.4);
uniform float total_len = 2.0;
uniform float heel_at = 1.2;
uniform float bend_x = 0.0;
uniform float bend_z = 0.0;
uniform float squash = 1.0;
uniform float dim = 1.0;
uniform float hurt = 0.0;
uniform float charge = 0.0;   // static build-up: crackling purple glow

void vertex() {
	float h = clamp((VERTEX.y - 0.35) / 1.1, 0.0, 1.0);
	VERTEX.x += bend_x * h * h;
	VERTEX.z += bend_z * h * h;
	VERTEX.y *= squash;
}

void fragment() {
	float L = UV.y;
	float a = UV.x * 4.0;
	float b = L / 0.19;
	vec3 c;
	if (L < 0.2) {
		c = col_cuff * (0.82 + 0.18 * step(0.5, fract(UV.x * 30.0)));   // ribbed cuff
	} else if (L > total_len - 0.24) {
		c = col_toe;                                                      // the toe
	} else if (abs(L - heel_at) < 0.17 && abs(UV.x - 0.75) < 0.22) {
		c = col_toe;                                                      // the heel patch
	} else {
		float d = mod(floor(a + b) + floor(a - b), 2.0);
		c = mix(col_a, col_b, d);
		float la = 0.5 - abs(fract(a + b) - 0.5);
		float lb = 0.5 - abs(fract(a - b) - 0.5);
		if (min(la, lb) < 0.035) { c = col_line; }                        // the criss-cross yarn
	}
	// a soft knitted texture: fine horizontal rows
	c *= 0.9 + 0.1 * sin(L * 260.0);
	ALBEDO = c * dim;
	ROUGHNESS = 0.97;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float crackle = step(0.93, fract(sin(dot(floor(UV * vec2(40.0, 30.0)) + floor(TIME * 12.0), vec2(12.9898, 78.233))) * 43758.5453));
	EMISSION = vec3(0.72, 0.35, 1.0) * charge * (rim * 1.2 + crackle * 1.5) + vec3(1.0, 0.85, 0.75) * hurt;
}
"""

static var _shader: Shader

var mat: ShaderMaterial
var _eyes: Array[Node3D] = []
var _pupils: Array[Node3D] = []
var _pupil_vel: Array[Vector3] = []
var _pupil_off: Array[Vector3] = []
var _time := 0.0
var _hop := 0.0
var _last_pos := Vector3.INF
var _spin := 0.0
var spin_rate := 0.0                 # Spin Cycle: rad/s


## `colors` overrides the palette: {"a", "b", "line", "cuff", "toe"} (the Lost Pair is blue).
static func create(colors := {}) -> SockBody:
	var s := SockBody.new()
	s.set_meta("colors", colors)
	return s


func _ready() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = _shader
	var colors: Dictionary = get_meta("colors", {})
	for k in colors:
		mat.set_shader_parameter("col_" + str(k), colors[k])
	var built := _build_mesh()
	mat.set_shader_parameter("total_len", built[1])
	mat.set_shader_parameter("heel_at", built[2])
	var mi := MeshInstance3D.new()
	mi.mesh = built[0]
	mi.material_override = mat
	add_child(mi)
	_build_eyes()


## Centre line: down the leg, round the heel, forward along the foot (toward -Z).
static func _centre(s: float) -> Vector3:
	if s < 0.55:   # the leg
		return Vector3(0, lerpf(HEIGHT, 0.5, s / 0.55), 0)
	if s < 0.72:   # the heel: a quarter turn
		var a := (s - 0.55) / 0.17 * PI * 0.5
		return Vector3(0, 0.5 - sin(a) * 0.28, -(1.0 - cos(a)) * 0.28)
	return Vector3(0, 0.22, -0.28 - (s - 0.72) / 0.28 * 0.42)   # the foot


static func _radius(s: float) -> Vector2:   # (width, height) of the tube's cross-section
	var r := LEG_R
	if s < 0.04:
		r *= 1.08   # the cuff flares a touch
	if s > 0.72:
		var f := (s - 0.72) / 0.28
		var w := r * (1.0 + 0.05 * f)
		var h := r * (0.88 - 0.1 * f)
		if f > 0.82:   # round off the toe
			var k := sqrt(maxf(0.0, 1.0 - pow((f - 0.82) / 0.18, 2.0)))
			return Vector2(w, h) * maxf(k, 0.02)
		return Vector2(w, h)
	return Vector2(r, r)


func _build_mesh() -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 0.0
	var heel := 0.0
	var prev := _centre(0.0)
	var lens := PackedFloat32Array()
	for i in RINGS + 1:
		var s := float(i) / RINGS
		var c := _centre(s)
		length += c.distance_to(prev)
		prev = c
		lens.append(length)
		if heel == 0.0 and s >= 0.635:
			heel = length
	var verts: Array[PackedVector3Array] = []
	for i in RINGS + 1:
		var s := float(i) / RINGS
		var c := _centre(s)
		var t := (_centre(minf(s + 0.01, 1.0)) - _centre(maxf(s - 0.01, 0.0))).normalized()
		var side := Vector3.RIGHT
		var up := side.cross(t).normalized()   # in the plane of the bend
		var r := _radius(s)
		var ring := PackedVector3Array()
		for j in SIDES + 1:
			var a := TAU * j / SIDES
			ring.append(c + side * cos(a) * r.x + up * sin(a) * r.y)
		verts.append(ring)
	for i in RINGS:
		for j in SIDES:
			var q := [verts[i][j], verts[i][j + 1], verts[i + 1][j + 1], verts[i + 1][j]]
			var uv := [Vector2(float(j) / SIDES, lens[i]), Vector2(float(j + 1) / SIDES, lens[i]),
				Vector2(float(j + 1) / SIDES, lens[i + 1]), Vector2(float(j) / SIDES, lens[i + 1])]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uv[k])
				st.add_vertex(q[k])
	# Close the top of the cuff (dark inside)
	var top := _centre(0.0)
	for j in SIDES:
		st.set_uv(Vector2(0.5, 0.0))
		st.add_vertex(top + Vector3(0, -0.12, 0))
		st.set_uv(Vector2(float(j) / SIDES, 0.0))
		st.add_vertex(verts[0][j])
		st.set_uv(Vector2(float(j + 1) / SIDES, 0.0))
		st.add_vertex(verts[0][j + 1])
	st.generate_normals()
	return [st.commit(), length, heel]


func _build_eyes() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.98, 0.98, 0.96)
	white.roughness = 0.3
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.03, 0.03, 0.04)
	black.roughness = 0.2
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(side * 0.1, 1.3, -LEG_R + 0.02)
		add_child(eye)
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.095
		sm.height = 0.19
		sm.material = white
		ball.mesh = sm
		ball.scale = Vector3(1, 1, 0.55)
		eye.add_child(ball)
		var pupil := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.045
		pm.height = 0.09
		pm.material = black
		pupil.mesh = pm
		pupil.scale = Vector3(1, 1, 0.5)
		pupil.position = Vector3(0, -0.02, -0.045)
		eye.add_child(pupil)
		_eyes.append(eye)
		_pupils.append(pupil)
		_pupil_vel.append(Vector3.ZERO)
		_pupil_off.append(Vector3(0, -0.02, 0))


## Every frame: `speed` (m/s) makes it hop and lean; `lunge`, `swell`, `flinch` 0..1 pulses
## (attack, cast, hit).
func animate(dt: float, speed: float, airborne: bool, lunge := 0.0, swell := 0.0, flinch := 0.0) -> void:
	_time += dt
	var lean := clampf(speed / 7.0, 0.0, 1.0)
	if speed > 0.5 and not airborne:
		_hop += dt * (2.2 + speed * 0.35)
	else:
		_hop = move_toward(_hop, roundf(_hop), dt * 2.0)
	var bounce := absf(sin(_hop * PI))
	var l := sin(lunge * PI)
	var bz := -0.3 * lean - 0.55 * l + 0.35 * flinch
	var bx := 0.07 * sin(_time * 1.4) + 0.05 * sin(_hop * PI * 2.0) * lean
	var squash := 1.0 - 0.1 * (1.0 - bounce) * lean + 0.12 * sin(swell * PI)
	mat.set_shader_parameter("bend_x", bx)
	mat.set_shader_parameter("bend_z", bz)
	mat.set_shader_parameter("squash", squash)
	position.y = 0.22 * bounce * lean
	scale = Vector3.ONE * (1.0 + 0.15 * sin(swell * PI))
	_spin += spin_rate * dt
	rotation.y = _spin
	# Eyes ride the bend; pupils wobble about on a spring (googly)
	var h := clampf((1.3 - 0.35) / 1.1, 0.0, 1.0)
	var move := Vector3.ZERO
	if _last_pos != Vector3.INF:
		move = (global_position - _last_pos) / maxf(dt, 0.001)
	_last_pos = global_position
	for k in _eyes.size():
		var e := _eyes[k]
		e.position = Vector3((-0.1 if k == 0 else 0.1) + bx * h * h, 1.3 * squash, -LEG_R + 0.02 + bz * h * h)
		var local_move := global_transform.basis.inverse() * move
		var want := Vector3(-local_move.x, -local_move.y - 0.6, 0) * 0.02
		var off := _pupil_off[k]
		var v := _pupil_vel[k]
		v += ((want - off) * 140.0 - v * 6.0) * dt
		off += v * dt
		off = off.limit_length(0.045)
		_pupil_off[k] = off
		_pupil_vel[k] = v
		_pupils[k].position = Vector3(off.x, off.y, -0.045)


func set_dim(f: float) -> void:
	if mat:
		mat.set_shader_parameter("dim", f)


func set_hurt(f: float) -> void:
	if mat:
		mat.set_shader_parameter("hurt", f)


func set_charge(f: float) -> void:
	if mat:
		mat.set_shader_parameter("charge", f)


## Where its zaps leave from: the top of the cuff.
func tip() -> Vector3:
	return global_transform * Vector3(0, HEIGHT * 0.95, 0)
