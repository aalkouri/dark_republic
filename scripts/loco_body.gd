class_name LocoBody
extends Node3D
## Loco Robotico, built entirely in code (he has no 3D model): a boxy retro party robot about
## 1.9 m to the top of his sombrero. Two little wheels on stubby accordion legs, a riveted tin
## torso with a speaker grille, party lights and big buttons, a TV-screen head whose pixel face
## the shader draws (happy, party and DESTROY faces; it blinks, and shows X eyes when hit), a
## sombrero with a pom-pom fringe, and a maraca in each claw. Faces -Z, origin at the feet.
##
## The parts are separate pivots (wheels, torso, head, shoulders, forearms) so animate() can
## roll, lean, dance, shake a maraca per attack (alternating hands), throw both arms up when he
## casts, flinch when hit, and spin the torso like a turret with both arms out (DESTROY Mode).
## RosterHero drives it for the playable robot; RosterModel shows him dancing on character select.

const SHOULDER_X := 0.42
const WAIST_Y := 0.5
const SHOULDER_Y := 0.55      # above the waist
const WHEEL_R := 0.11
const UPPER := 0.26           # upper arm length
const FORE := 0.27            # forearm length

const BODY_SHADER := """
shader_type spatial;
render_mode cull_disabled;
// Vertex colours are sRGB; vertex alpha tags the surface:
//   0 = painted tin   0.25 = matte (straw hat, rubber)   0.5 = steady glow   1 = disco light
uniform float dim = 1.0;
uniform float hurt = 0.0;
uniform float rage = 0.0;     // DESTROY Mode: a red-hot rim
uniform float party = 0.0;    // Party Mode: the disco lights go wild
varying vec3 lpos;
void vertex() { lpos = VERTEX; }
vec3 hue(float h) { return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); }
void fragment() {
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float tag = COLOR.a;
	vec3 e = vec3(0.0);
	if (tag > 0.75) {
		vec3 h = hue(fract(TIME * (0.35 + party * 1.2) + (lpos.x + lpos.y) * 1.7));
		col = mix(col, h, 0.85);
		e = h * (1.2 + party * 1.6) * (0.75 + 0.25 * sin(TIME * (6.0 + party * 10.0) + lpos.x * 20.0));
	} else if (tag > 0.4) {
		e = col * 1.6;
	}
	ALBEDO = col * dim;
	METALLIC = tag < 0.1 ? 0.35 : 0.0;
	ROUGHNESS = tag < 0.1 ? 0.42 : 0.9;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = e * dim + vec3(1.0, 0.85, 0.75) * hurt + vec3(1.0, 0.12, 0.05) * rage * (rim * 1.4 + 0.08);
}
"""

const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
// The face: pixel art on a 24 x 16 grid. mode 0 = happy, 1 = party, 2 = DESTROY.
uniform float mode = 0.0;
uniform float blink = 0.0;
uniform float hurt = 0.0;
uniform float dim = 1.0;
vec3 hue(float h) { return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); }
float eye(vec2 q, vec2 c) {
	vec2 d = q - c;
	if (hurt > 0.3) {   // X eyes
		return step(abs(abs(d.x) - abs(d.y)), 0.6) * step(max(abs(d.x), abs(d.y)), 2.6);
	}
	if (mode > 1.5) {   // angry: a slab cut by a slant toward the nose
		float s = (c.x < 12.0) ? d.x : -d.x;
		return step(abs(d.x), 2.6) * step(d.y, 1.6) * step(-d.y + 0.6 * s, 1.2);
	}
	if (mode > 0.5) {   // party: ^ ^
		float r = length(d - vec2(0.0, 1.5));
		return step(abs(r - 2.3), 0.65) * step(d.y, 0.9);
	}
	float h = mix(2.3, 0.35, blink);
	return step(length(d / vec2(1.7, h)), 1.0);
}
void fragment() {
	vec2 q = floor(UV * vec2(24.0, 16.0)) + 0.5;
	float on = eye(q, vec2(7.0, 6.0)) + eye(q, vec2(17.0, 6.0));
	vec2 m = q - vec2(12.0, 9.5);
	if (mode > 1.5) {          // gritted zig-zag teeth
		on += step(abs(m.y - (mod(q.x, 2.0) - 0.5) * 1.2), 0.6) * step(abs(m.x), 6.0);
	} else if (mode > 0.5) {   // a big open grin
		on += step(length(m * vec2(1.0, 1.5)), 5.2) * step(0.0, m.y);
	} else if (hurt > 0.3) {   // an "o" of surprise
		on += step(abs(length(m) - 1.6), 0.6);
	} else {                   // a smile
		on += step(abs(length(m + vec2(0.0, 3.0)) - 5.0), 0.6) * step(1.0, m.y + 3.0 - 2.5);
	}
	on = clamp(on, 0.0, 1.0);
	vec3 c = vec3(0.24, 1.0, 0.54);
	if (mode > 1.5) { c = vec3(1.0, 0.12, 0.08); }
	else if (mode > 0.5) { c = hue(fract(TIME * 0.6 + q.x * 0.02)); }
	float scan = 0.72 + 0.28 * step(0.5, fract(UV.y * 32.0));
	vec2 gd = abs(fract(UV * vec2(24.0, 16.0)) - 0.5);
	float grid = 1.0 - 0.35 * step(0.42, max(gd.x, gd.y));
	vec3 bg = vec3(0.01, 0.05, 0.045) + c * 0.04;
	ALBEDO = (mix(bg, c * 2.2, on) * scan * grid + vec3(1.0, 0.85, 0.75) * hurt * 0.4) * dim;
}
"""

static var _body_shader: Shader
static var _screen_shader: Shader

var mat: ShaderMaterial
var screen_mat: ShaderMaterial
var _wheels: Array[Node3D] = []
var _torso: Node3D
var _head: Node3D
var _hat: Node3D
var _shoulders: Array[Node3D] = []
var _fores: Array[Node3D] = []
var _maracas: Array[Node3D] = []      # the bulbs (where his sonic pulses leave from)
var _shake: Array[float] = [0.0, 0.0]
var _side := 1                        # which hand shook last
var _time := 0.0
var _roll := 0.0
var _blink_t := 2.0
var _turret := 0.0                    # torso yaw relative to the root (DESTROY Mode)
var party := false                    # Party Mode: dance harder, disco lights, party face
var destroy := false                  # DESTROY Mode: red face, arms out, torso spins
var turret_yaw := 0.0                 # ...world yaw the arms point along (set by the kit)
var _destroy_f := 0.0
var _hurt := 0.0
var shakes := 0                       # maraca shakes (tests)


static func create() -> LocoBody:
	return LocoBody.new()


func _ready() -> void:
	if _body_shader == null:
		_body_shader = Shader.new()
		_body_shader.code = BODY_SHADER
		_screen_shader = Shader.new()
		_screen_shader.code = SCREEN_SHADER
	mat = ShaderMaterial.new()
	mat.shader = _body_shader
	screen_mat = ShaderMaterial.new()
	screen_mat.shader = _screen_shader
	_build()


# ------------------------------------------------------------------ building

const TIN := Color(0.6, 0.64, 0.68, 0.0)
const TIN_DARK := Color(0.36, 0.39, 0.43, 0.0)
const TIN_LIGHT := Color(0.78, 0.81, 0.84, 0.0)
const TEAL := Color(0.12, 0.42, 0.48, 0.0)
const RUBBER := Color(0.08, 0.08, 0.09, 0.25)
const STRAW := Color(0.88, 0.63, 0.17, 0.25)
const STRAW_DARK := Color(0.66, 0.42, 0.1, 0.25)
const RED := Color(0.86, 0.16, 0.14, 0.25)
const GREEN := Color(0.1, 0.6, 0.3, 0.25)


func _part(parent: Node3D, mb: MeshBuilder, at := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(mat)
	mi.position = at
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	parent.add_child(n)
	return n


static func _tf(at: Vector3, b := Basis()) -> Transform3D:
	return Transform3D(b, at)


static func _torus(r: float, t: float, seg := 28) -> Array:
	var m := TorusMesh.new()
	m.inner_radius = r - t
	m.outer_radius = r + t
	m.rings = seg
	m.ring_segments = 8
	return m.get_mesh_arrays()


func _build() -> void:
	var side_axis := Basis(Vector3.FORWARD, PI / 2)   # cylinders lying along X
	# --- Legs and wheels (fixed to the root; the wheels spin)
	var legs := MeshBuilder.new()
	legs.add(MeshBuilder.box(Vector3(0.5, 0.12, 0.32)), _tf(Vector3(0, 0.45, 0)), TIN_DARK)   # hips
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.19
		for k in 4:   # an accordion leg
			var y0 := 0.42 - k * 0.07
			legs.add(MeshBuilder.cyl(0.065 if k % 2 == 0 else 0.05, 0.065 if k % 2 == 0 else 0.05, 0.07, 12), _tf(Vector3(x, y0 - 0.035, 0)), TIN if k % 2 == 0 else TIN_DARK)
		legs.add(MeshBuilder.box(Vector3(0.05, 0.08, 0.16)), _tf(Vector3(x + sx * 0.07, WHEEL_R, 0)), TIN_DARK)   # the fork
		var w := _pivot(self, Vector3(x + sx * 0.02, WHEEL_R, 0))
		var wb := MeshBuilder.new()
		wb.add(MeshBuilder.cyl(WHEEL_R, WHEEL_R, 0.08, 18), _tf(Vector3.ZERO, side_axis), RUBBER)
		wb.add(MeshBuilder.cyl(0.06, 0.06, 0.09, 12), _tf(Vector3.ZERO, side_axis), TIN_LIGHT)
		wb.add(MeshBuilder.box(Vector3(0.1, 0.18, 0.03)), _tf(Vector3.ZERO), Color(0.95, 0.75, 0.15, 0.25))   # a spoke, so you see it roll
		_part(w, wb)
		_wheels.append(w)
	_part(self, legs)

	# --- Torso
	_torso = _pivot(self, Vector3(0, WAIST_Y, 0))
	var t := MeshBuilder.new()
	t.add(MeshBuilder.box(Vector3(0.72, 0.62, 0.46)), _tf(Vector3(0, 0.36, 0)), TIN)
	t.add(MeshBuilder.box(Vector3(0.76, 0.06, 0.5)), _tf(Vector3(0, 0.05, 0)), TIN_DARK)     # bottom trim
	t.add(MeshBuilder.box(Vector3(0.76, 0.05, 0.5)), _tf(Vector3(0, 0.66, 0)), TIN_DARK)     # top trim
	t.add(MeshBuilder.box(Vector3(0.6, 0.46, 0.02)), _tf(Vector3(0, 0.36, -0.235)), TEAL)    # chest panel
	# Speaker grille: a dark disc with rings
	var face := Basis(Vector3.RIGHT, PI / 2)
	t.add(MeshBuilder.cyl(0.13, 0.13, 0.03, 20), _tf(Vector3(0.13, 0.3, -0.245), face), Color(0.05, 0.05, 0.06, 0.25))
	for r in [0.1, 0.065, 0.03]:
		t.add(_torus(r, 0.008, 20), _tf(Vector3(0.13, 0.3, -0.262), face), TIN_DARK)
	# Big buttons and a row of party lights
	var btn := [Color(0.95, 0.2, 0.2, 0.5), Color(1.0, 0.82, 0.2, 0.5), Color(0.2, 0.9, 0.45, 0.5)]
	for k in 3:
		t.add(MeshBuilder.cyl(0.035, 0.035, 0.03, 12), _tf(Vector3(-0.18, 0.44 - k * 0.1, -0.25), face), btn[k])
	for k in 6:
		t.add(MeshBuilder.box(Vector3(0.07, 0.045, 0.03)), _tf(Vector3(-0.25 + k * 0.1, 0.56, -0.25)), Color(1, 1, 1, 1.0))
	# Rivets on the corners, a dial on the side
	for x in [-0.33, 0.33]:
		for y in [0.12, 0.6]:
			t.add(MeshBuilder.sphere(0.018, 6, 4), _tf(Vector3(x, y, -0.235)), TIN_LIGHT)
	t.add(MeshBuilder.cyl(0.05, 0.05, 0.03, 12), _tf(Vector3(0.37, 0.3, 0), side_axis), Color(1.0, 0.82, 0.2, 0.25))
	t.add(MeshBuilder.cyl(0.075, 0.07, 0.08, 12), _tf(Vector3(0, 0.71, 0)), TIN_DARK)        # neck
	_part(_torso, t)

	# --- Head: a TV with a pixel face, under a sombrero
	_head = _pivot(_torso, Vector3(0, 0.76, 0))
	var h := MeshBuilder.new()
	h.add(MeshBuilder.box(Vector3(0.56, 0.42, 0.44)), _tf(Vector3(0, 0.21, 0)), TIN_LIGHT)
	h.add(MeshBuilder.box(Vector3(0.5, 0.36, 0.02)), _tf(Vector3(0, 0.21, -0.222)), Color(0.15, 0.16, 0.18, 0.25))   # bezel
	for sx in [-1.0, 1.0]:   # ear bolts with glowing tips
		h.add(MeshBuilder.cyl(0.06, 0.06, 0.06, 12), _tf(Vector3(sx * 0.3, 0.22, 0), side_axis), TIN_DARK)
		h.add(MeshBuilder.cyl(0.012, 0.012, 0.16, 6), _tf(Vector3(sx * 0.36, 0.3, 0), Basis(Vector3.FORWARD, -sx * 0.6)), TIN_DARK)
		h.add(MeshBuilder.sphere(0.03, 8, 5), _tf(Vector3(sx * 0.41, 0.37, 0)), Color(1, 1, 1, 1.0))
	_part(_head, h)
	var scr := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.44, 0.3)
	scr.mesh = q
	scr.material_override = screen_mat
	scr.position = Vector3(0, 0.21, -0.234)
	scr.rotation.y = PI   # quads face +Z
	_head.add_child(scr)

	_hat = _pivot(_head, Vector3(0, 0.42, 0))
	_hat.rotation.z = 0.1   # worn at a jaunty angle
	var s := MeshBuilder.new()
	s.add(MeshBuilder.cyl(0.64, 0.66, 0.035, 36), _tf(Vector3(0, 0.03, 0)), STRAW)             # brim
	s.add(_torus(0.64, 0.035, 36), _tf(Vector3(0, 0.07, 0)), STRAW_DARK)                       # rolled-up rim
	s.add(MeshBuilder.cyl(0.15, 0.22, 0.3, 24), _tf(Vector3(0, 0.2, 0)), STRAW)                # crown
	s.add(MeshBuilder.sphere(0.15, 16, 6), Transform3D(Basis().scaled(Vector3(1, 0.45, 1)), Vector3(0, 0.35, 0)), STRAW)
	s.add(MeshBuilder.cyl(0.215, 0.222, 0.06, 24), _tf(Vector3(0, 0.085, 0)), RED)             # bands
	s.add(MeshBuilder.cyl(0.2, 0.207, 0.03, 24), _tf(Vector3(0, 0.13, 0)), GREEN)
	s.add(_torus(0.5, 0.012, 32), _tf(Vector3(0, 0.05, 0)), RED)                                # brim stitching
	for k in 16:   # pom-poms dangling round the brim
		var a := TAU * k / 16.0
		s.add(MeshBuilder.sphere(0.035, 6, 4), _tf(Vector3(cos(a) * 0.66, -0.03, sin(a) * 0.66)), RED if k % 2 == 0 else GREEN)
	_part(_hat, s)

	# --- Arms: shoulder -> upper arm -> elbow pivot -> forearm, claw and maraca
	for k in 2:
		var sx := -1.0 if k == 0 else 1.0
		var sh := _pivot(_torso, Vector3(sx * SHOULDER_X, SHOULDER_Y, 0))
		var a := MeshBuilder.new()
		a.add(MeshBuilder.sphere(0.085, 12, 8), _tf(Vector3.ZERO), TIN_DARK)
		for j in 3:
			a.add(MeshBuilder.cyl(0.048 if j % 2 == 0 else 0.04, 0.048 if j % 2 == 0 else 0.04, UPPER / 3.0, 10), _tf(Vector3(0, -UPPER / 6.0 - j * UPPER / 3.0, 0)), TIN if j % 2 == 0 else TIN_DARK)
		a.add(MeshBuilder.sphere(0.058, 10, 6), _tf(Vector3(0, -UPPER, 0)), TIN_DARK)
		_part(sh, a)
		var fo := _pivot(sh, Vector3(0, -UPPER, 0))
		var f := MeshBuilder.new()
		f.limb(Vector3.ZERO, Vector3(0, 0, -FORE), 0.045, 0.04, TIN, 10)
		# A two-fingered claw round the handle
		for cx in [-1.0, 1.0]:
			f.add(MeshBuilder.box(Vector3(0.025, 0.05, 0.07)), _tf(Vector3(cx * 0.035, 0, -FORE - 0.03)), TIN_DARK)
		# The maraca: handle up out of the claw, a striped bulb on top
		var bulb_col := RED if k == 0 else GREEN
		f.add(MeshBuilder.cyl(0.02, 0.024, 0.2, 8), _tf(Vector3(0, 0.06, -FORE - 0.03)), Color(0.55, 0.32, 0.14, 0.25))
		f.add(MeshBuilder.sphere(0.1, 14, 8), Transform3D(Basis().scaled(Vector3(1, 1.25, 1)), Vector3(0, 0.25, -FORE - 0.03)), bulb_col)
		f.add(MeshBuilder.cyl(0.098, 0.098, 0.04, 14), _tf(Vector3(0, 0.25, -FORE - 0.03)), Color(1.0, 0.82, 0.2, 0.25))
		f.add(MeshBuilder.cyl(0.08, 0.08, 0.025, 14), _tf(Vector3(0, 0.32, -FORE - 0.03)), Color(0.15, 0.45, 0.85, 0.25))
		_part(fo, f)
		var tipn := _pivot(fo, Vector3(0, 0.25, -FORE - 0.03))
		_shoulders.append(sh)
		_fores.append(fo)
		_maracas.append(tipn)


# ------------------------------------------------------------------ animation

## A maraca shake (one weapon pulse): alternates hands. Returns the hand that shook (0 left, 1 right).
func shake() -> int:
	_side = 1 - _side
	_shake[_side] = 1.0
	shakes += 1
	return _side


## Every frame: `speed` (m/s) rolls the wheels and leans him in; `swell` (cast) throws both
## arms up; `flinch` (hit) knocks him back.
func animate(dt: float, speed: float, airborne: bool, swell := 0.0, flinch := 0.0) -> void:
	_time += dt
	var lean := clampf(speed / 7.0, 0.0, 1.0)
	_roll += speed / WHEEL_R * dt
	for w in _wheels:
		w.rotation.x = -_roll
	for k in 2:
		_shake[k] = maxf(0.0, _shake[k] - dt * 3.2)
	_destroy_f = move_toward(_destroy_f, 1.0 if destroy else 0.0, dt * 3.0)
	var sw := sin(swell * PI)
	var groove := 1.0 if party else 0.35
	var beat := _time * (7.5 if party else 4.2)
	# Body: a bob as he rolls, a groove when he doesn't, a lean forward, a jolt back when hit
	var bump := 0.025 * absf(sin(_roll * 0.5)) * lean if not airborne else 0.0
	_torso.position = Vector3(0.04 * sin(beat * 0.5) * groove * (1.0 - lean), WAIST_Y + bump + 0.03 * absf(sin(beat * 0.5)) * groove * (1.0 - lean), 0.0)
	var twist := 0.18 * sin(beat * 0.5) * groove * (1.0 - lean)
	if _destroy_f > 0.0:   # the torso spins with the beams
		var want := wrapf(turret_yaw - PI / 2 - global_rotation.y, -PI, PI)
		_turret = lerp_angle(_turret, want, 1.0 - exp(-25.0 * dt)) if destroy else lerp_angle(_turret, 0.0, 1.0 - exp(-8.0 * dt))
	else:
		_turret = 0.0
	_torso.rotation = Vector3(-0.22 * lean + 0.45 * flinch - 0.1 * sw, _turret + twist * (1.0 - _destroy_f), 0.06 * sin(beat * 0.25) * groove * (1.0 - lean))
	_head.rotation = Vector3(0.12 * sin(beat) * groove * (1.0 - lean) * 0.5 - 0.2 * flinch, 0.15 * sin(beat * 0.25) * groove * (1.0 - _destroy_f), 0.1 * sin(beat * 0.5) * groove)
	_hat.rotation = Vector3(0.04 * sin(_time * 3.1) + 0.12 * flinch, 0.0, 0.1 + 0.05 * sin(_time * 2.3))
	# Arms
	for k in 2:
		var sx := -1.0 if k == 0 else 1.0
		var s := _shake[k]
		var pump := 0.45 * sin(_roll * 0.35 + (PI if k == 0 else 0.0)) * lean
		var dance := 0.35 * sin(beat + (PI if k == 0 else 0.0)) * groove * (1.0 - lean)
		var raise := 0.2 + pump + dance + 0.9 * sin(s * PI) + 2.2 * sw
		var out := 0.12 + 0.35 * sw
		var fore := 0.15 * sin(beat * 2.0) * groove + 0.6 * sin(s * PI) * sin(_time * 55.0) * s
		# DESTROY: arms straight out to the sides, along the beams
		_shoulders[k].rotation = Vector3(lerpf(raise, 0.0, _destroy_f), 0.0, lerpf(sx * out, sx * PI / 2, _destroy_f))
		_fores[k].rotation = Vector3(lerpf(fore, -PI / 2, _destroy_f), 0.0, 0.0)
	# Face
	_blink_t -= dt
	var blink := 0.0
	if _blink_t < 0.12:
		blink = 1.0 - absf(_blink_t / 0.06 - 1.0)
		if _blink_t <= 0.0:
			_blink_t = randf_range(2.0, 4.5)
	screen_mat.set_shader_parameter("blink", blink)
	screen_mat.set_shader_parameter("mode", 2.0 if destroy else (1.0 if party or swell > 0.0 else 0.0))
	screen_mat.set_shader_parameter("hurt", maxf(_hurt, flinch))
	mat.set_shader_parameter("rage", _destroy_f)
	mat.set_shader_parameter("party", 1.0 if party else 0.0)


func set_dim(f: float) -> void:
	if mat:
		mat.set_shader_parameter("dim", f)
		screen_mat.set_shader_parameter("dim", f)


func set_hurt(f: float) -> void:
	_hurt = f
	if mat:
		mat.set_shader_parameter("hurt", f)


## Where his sonic pulses leave from: the bulb of the maraca that shook last.
func tip(side := -1) -> Vector3:
	var k := _side if side < 0 else side
	if _maracas.size() <= k:
		return global_transform * Vector3(0, 1.2, -0.5)
	return _maracas[k].global_position


## Where a DESTROY beam leaves from: the claw at the end of an outstretched arm.
func hand(k: int) -> Vector3:
	if _fores.size() <= k:
		return global_position + Vector3(0, 1.05, 0)
	return _fores[k].global_transform * Vector3(0, 0, -FORE - 0.05)
