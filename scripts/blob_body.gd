class_name BlobBody
extends Node3D
## The Blob, built entirely in code (it has no 3D model): a glossy, see-through green slime
## dome about 1.4 m tall with a little drip of a peak on top, two big eyes, and bubbles drifting
## up inside it. The shader wobbles the surface all the time (jelly), ripples it outward when it
## burns something (attack pulse), and the body squashes and stretches on a spring: it hops along
## when it moves, stretches tall in the air, splats flat on landing and when hit (spraying a few
## droplets), and swells when it casts. Enemies it swallows (Engulf) show through the jelly.
## Faces -Z, origin at the bottom centre.
##
## RosterHero drives it for the playable Blob (animate() every frame); Split spawns two half-size
## ones; RosterModel shows one idling on character select.

const RADIUS := 0.78
const CENTER := 0.58
const RY := 0.6
const PEAK := 0.2
const RINGS := 30
const SIDES := 40
const BUBBLES := 10
const EYE_Y := 0.84
const EYE_X := 0.21
const DROPS := 8

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, %s, specular_schlick_ggx;
uniform vec3 col_body : source_color = vec3(0.45, 0.86, 0.18);
uniform vec3 col_deep : source_color = vec3(0.1, 0.38, 0.05);
uniform vec3 col_rim : source_color = vec3(0.82, 1.0, 0.55);
uniform float opacity = 0.6;
uniform float inner = 0.0;          // 1: the inside (back faces) pass, darker
uniform vec2 squash = vec2(1.0);    // x: width, y: height
uniform vec2 lean = vec2(0.0);      // (x, z) shift of the top
uniform float wobble = 1.0;
uniform float pulse = 0.0;          // attack: a ripple pushed outward
uniform float ripple_t = 0.0;
uniform float dim = 1.0;
uniform float hurt = 0.0;
uniform float glow = 0.0;           // acid glow (grows with kills)
uniform float seed = 0.0;
varying float hgt;

void vertex() {
	vec3 p = VERTEX;
	float h = clamp(p.y / 1.4, 0.0, 1.0);
	float t = TIME + seed;
	float n = sin(p.x * 6.0 + t * 3.1) * sin(p.z * 5.3 - t * 2.4) * 0.6 + sin(p.y * 7.0 - t * 4.2 + p.x * 3.0) * 0.4;
	float base = smoothstep(0.0, 0.2, p.y);
	float rip = sin(p.y * 12.0 - ripple_t * 26.0);
	p += NORMAL * (n * 0.035 * wobble + pulse * (0.07 + 0.035 * rip)) * base;
	p.xz *= squash.x;
	p.y *= squash.y;
	p.xz += lean * h * h;
	hgt = h;
	VERTEX = p;
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.4);
	vec3 c = mix(col_body, col_deep, inner * 0.55 + (1.0 - hgt) * 0.3);
	c = mix(c, col_rim, fres * 0.55 * (1.0 - inner));
	ALBEDO = c * dim;
	ALPHA = clamp(opacity + fres * 0.35 - inner * 0.15, 0.0, 0.96);
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	METALLIC = 0.0;
	EMISSION = (col_body * (0.14 + glow * 0.45) + col_rim * fres * 0.3 * (1.0 - inner) + vec3(0.6, 1.0, 0.3) * pulse * 0.35) * dim
		+ vec3(1.0, 0.85, 0.75) * hurt;
}
"""

static var _shaders := {}
static var _mesh: ArrayMesh

var mat: ShaderMaterial              # the outside
var mat_in: ShaderMaterial           # the inside (seen through it)
var size := 1.0                      # 0.5 for Split's mini-blobs
var growth := 0.0                    # Acid Body: 0..0.5 bigger with kills
var fullness := 0                    # enemies swallowed (Engulf): it bulges a little
var puddle_target := 0.0             # The Great Puddle: 1 = spread flat
var puddle := 0.0
var _eyes: Array[Node3D] = []
var _pupils: Array[Node3D] = []
var _pupil_off: Array[Vector3] = []
var _pupil_vel: Array[Vector3] = []
var _bubbles: Array[MeshInstance3D] = []
var _bub: Array[Vector4] = []        # x, z, y, speed
var _drops: Array = []               # {node, vel, life}
var _drop_mesh: SphereMesh
var _drop_mat: StandardMaterial3D
var _time := 0.0
var _hop := 0.0
var _sy := 1.0                       # height squash on a spring
var _sv := 0.0
var _was_air := false
var _last_flinch := 0.0
var _ripple := 0.0
var _last_pos := Vector3.INF
var _seed := 0.0
var splats := 0                      # hit splats (tests)


## `opts`: {"size": 0.5, "body": Color, "deep": Color, "rim": Color, "seed": float}
static func create(opts := {}) -> BlobBody:
	var b := BlobBody.new()
	b.set_meta("opts", opts)
	return b


func _ready() -> void:
	var opts: Dictionary = get_meta("opts", {})
	size = float(opts.get("size", 1.0))
	_seed = float(opts.get("seed", randf() * 10.0))
	if _mesh == null:
		_mesh = _build_mesh()
	mat_in = _material("cull_front", opts)
	mat_in.set_shader_parameter("inner", 1.0)
	mat_in.render_priority = -1
	mat = _material("cull_back", opts)
	var back := MeshInstance3D.new()
	back.mesh = _mesh
	back.material_override = mat_in
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.extra_cull_margin = 2.0
	add_child(back)
	var front := MeshInstance3D.new()
	front.mesh = _mesh
	front.material_override = mat
	front.extra_cull_margin = 2.0
	add_child(front)
	_build_eyes()
	_build_bubbles()
	_drop_mesh = SphereMesh.new()
	_drop_mesh.radius = 0.07
	_drop_mesh.height = 0.14
	_drop_mesh.radial_segments = 8
	_drop_mesh.rings = 4
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.albedo_color = (opts.get("body", Color(0.45, 0.86, 0.18)) as Color)
	_drop_mat.roughness = 0.08
	_drop_mat.emission_enabled = true
	_drop_mat.emission = _drop_mat.albedo_color * 0.25
	_drop_mesh.material = _drop_mat
	scale = Vector3.ONE * size


func _material(cull: String, opts: Dictionary) -> ShaderMaterial:
	if not _shaders.has(cull):
		var sh := Shader.new()
		sh.code = SHADER % cull
		_shaders[cull] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[cull]
	m.set_shader_parameter("seed", _seed)
	for k in ["body", "deep", "rim"]:
		if opts.has(k):
			m.set_shader_parameter("col_" + k, opts[k])
	return m


## Radius of the body's outline at height `y` (before squash): for the eyes and bubbles.
static func radius_at(y: float) -> float:
	var c := clampf((y - CENTER) / RY, -1.0, 1.0)
	var th := acos(c)
	return _ring_r(th)


static func _ring_r(th: float) -> float:
	var s := sin(th)
	var lower := th > PI * 0.5
	return RADIUS * pow(maxf(s, 0.0), 0.55 if lower else 1.0) * (1.0 + 0.08 * th / PI)


static func _ring_y(th: float) -> float:
	var y := CENTER + cos(th) * RY + PEAK * exp(-th * th / 0.06)
	if y < 0.04:   # sits flat on the ground
		y = 0.04 - (0.04 - y) * 0.1
	return y


## A drop of jelly: a dome with a flat base and a little curl of a peak on top.
static func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	# vertex 0: the top; rings 1..RINGS-1 of SIDES; last: the bottom
	st.add_vertex(Vector3(0, _ring_y(0.0), 0))
	for r in range(1, RINGS):
		var th := PI * float(r) / RINGS
		var rr := _ring_r(th)
		var y := _ring_y(th)
		var curl := 0.04 * exp(-th * th / 0.1)   # the peak leans back a touch
		for j in SIDES:
			var a := TAU * float(j) / SIDES
			st.add_vertex(Vector3(cos(a) * rr, y, sin(a) * rr + curl))
	st.add_vertex(Vector3(0, 0.0, 0))
	var bottom := 1 + (RINGS - 1) * SIDES
	for j in SIDES:
		var j1 := (j + 1) % SIDES
		st.add_index(0); st.add_index(1 + j1); st.add_index(1 + j)
	for r in RINGS - 2:
		var a0 := 1 + r * SIDES
		var b0 := a0 + SIDES
		for j in SIDES:
			var j1 := (j + 1) % SIDES
			st.add_index(a0 + j); st.add_index(a0 + j1); st.add_index(b0 + j)
			st.add_index(a0 + j1); st.add_index(b0 + j1); st.add_index(b0 + j)
	var last := 1 + (RINGS - 2) * SIDES
	for j in SIDES:
		var j1 := (j + 1) % SIDES
		st.add_index(last + j); st.add_index(last + j1); st.add_index(bottom)
	st.generate_normals()
	return st.commit()


func _build_eyes() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.98, 0.99, 0.95)
	white.roughness = 0.15
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.02, 0.04, 0.02)
	black.roughness = 0.1
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.albedo_color = Color.WHITE
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		add_child(eye)
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.28
		sm.radial_segments = 16
		sm.rings = 8
		sm.material = white
		ball.mesh = sm
		ball.scale = Vector3(1.0, 1.15, 0.7)
		eye.add_child(ball)
		var pupil := Node3D.new()
		eye.add_child(pupil)
		var pm := MeshInstance3D.new()
		var ps := SphereMesh.new()
		ps.radius = 0.075
		ps.height = 0.15
		ps.radial_segments = 12
		ps.rings = 6
		ps.material = black
		pm.mesh = ps
		pm.scale = Vector3(1.0, 1.2, 0.45)
		pupil.add_child(pm)
		var glint := MeshInstance3D.new()
		var gs := SphereMesh.new()
		gs.radius = 0.022
		gs.height = 0.044
		gs.radial_segments = 6
		gs.rings = 3
		gs.material = shine
		glint.mesh = gs
		glint.position = Vector3(0.025, 0.035, -0.035)
		pupil.add_child(glint)
		_eyes.append(eye)
		_pupils.append(pupil)
		_pupil_off.append(Vector3.ZERO)
		_pupil_vel.append(Vector3.ZERO)


func _build_bubbles() -> void:
	var bm := StandardMaterial3D.new()
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(0.85, 1.0, 0.7, 0.42)
	bm.roughness = 0.05
	bm.emission_enabled = true
	bm.emission = Color(0.4, 0.8, 0.2)
	bm.emission_energy_multiplier = 0.4
	bm.render_priority = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_seed * 1000.0)
	for k in BUBBLES:
		var b := MeshInstance3D.new()
		var s := SphereMesh.new()
		var r := rng.randf_range(0.03, 0.075)
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 8
		s.rings = 4
		s.material = bm
		b.mesh = s
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		_bubbles.append(b)
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 0.45
		_bub.append(Vector4(cos(a) * d, sin(a) * d, rng.randf_range(0.1, 1.0), rng.randf_range(0.12, 0.3)))


## Squash-and-stretch of a point in the body's rest shape.
func _deform(p: Vector3, sx: float, sy: float, lean: Vector2) -> Vector3:
	var h := clampf(p.y / 1.4, 0.0, 1.0)
	return Vector3(p.x * sx + lean.x * h * h, p.y * sy, p.z * sx + lean.y * h * h)


## Every frame: `speed` (m/s) makes it hop and lean; `lunge`, `swell`, `flinch` 0..1 pulses
## (attack, cast, hit).
func animate(dt: float, speed: float, airborne: bool, lunge := 0.0, swell := 0.0, flinch := 0.0) -> void:
	if mat == null:
		return
	_time += dt
	var lean_f := clampf(speed / 7.0, 0.0, 1.0)
	if speed > 0.5 and not airborne:
		_hop += dt * (2.0 + speed * 0.3)
	else:
		_hop = move_toward(_hop, roundf(_hop), dt * 2.0)
	var bounce := absf(sin(_hop * PI))
	puddle = move_toward(puddle, puddle_target, dt * (3.0 if puddle_target > puddle else 2.0))
	# Height squash on a spring: hops, stretched tall in the air, splat on landing and when hit
	var want := 1.0 + 0.14 * (bounce - 0.55) * lean_f
	if airborne:
		want = 1.2
	want -= 0.4 * flinch
	want = lerpf(want, 0.12, puddle)
	if _was_air and not airborne:
		_sv -= 4.0   # landing: splat
	_was_air = airborne
	if flinch > _last_flinch + 0.5:
		_splat()
	_last_flinch = flinch
	_sv += ((want - _sy) * 170.0 - _sv * 10.0) * dt
	_sy = clampf(_sy + _sv * dt, 0.08, 1.6)
	var sx := 1.0 / sqrt(maxf(_sy, 0.3)) * lerpf(1.0, 1.9, puddle)
	var l := sin(lunge * PI)
	var lean := Vector2(0.06 * sin(_time * 1.3 + _seed), 0.12 * lean_f - 0.18 * l + 0.1 * flinch) * (1.0 - puddle)
	_ripple += dt * (1.0 + 3.0 * lunge)
	mat.set_shader_parameter("squash", Vector2(sx, _sy))
	mat.set_shader_parameter("lean", lean)
	mat.set_shader_parameter("pulse", l)
	mat.set_shader_parameter("ripple_t", _ripple)
	mat.set_shader_parameter("wobble", 1.0 + 1.5 * lean_f + 2.0 * flinch + puddle)
	mat.set_shader_parameter("glow", growth * 2.0)
	for k in ["squash", "lean", "pulse", "ripple_t"]:
		mat_in.set_shader_parameter(k, mat.get_shader_parameter(k))
	position.y = 0.2 * bounce * lean_f * size * (1.0 - puddle)
	scale = Vector3.ONE * size * (1.0 + growth) * (1.0 + 0.25 * sin(swell * PI)) * (1.0 + 0.012 * mini(fullness, 20))
	# Eyes ride the surface; pupils wobble on a spring and look where it's going
	var move := Vector3.ZERO
	if _last_pos != Vector3.INF:
		move = (global_position - _last_pos) / maxf(dt, 0.001)
	_last_pos = global_position
	var local_move := global_transform.basis.orthonormalized().inverse() * move
	var ey := lerpf(EYE_Y, 0.95, puddle)   # spread flat, the eyes poke up out of the puddle
	var ez := -sqrt(maxf(0.0, pow(radius_at(EYE_Y), 2.0) - EYE_X * EYE_X)) + 0.07
	for k in _eyes.size():
		var side := -1.0 if k == 0 else 1.0
		var p := _deform(Vector3(side * EYE_X, ey, ez), sx if puddle < 0.5 else 1.0, _sy if puddle < 0.5 else 0.13, lean)
		_eyes[k].position = p
		_eyes[k].scale = Vector3(1.0, clampf(0.6 + 0.4 * _sy, 0.6, 1.2), 1.0)
		var aim := Vector3(-local_move.x, -local_move.y * 0.5 - 0.5, 0) * 0.015
		var off := _pupil_off[k]
		var v := _pupil_vel[k]
		v += ((aim - off) * 120.0 - v * 5.0) * dt
		off = (off + v * dt).limit_length(0.05)
		_pupil_off[k] = off
		_pupil_vel[k] = v
		_pupils[k].position = Vector3(off.x, off.y, -0.085)
	# Bubbles drift up through the jelly and start again at the bottom
	for k in _bubbles.size():
		var b := _bub[k]
		b.z += b.w * dt * (1.0 + lean_f)
		var top := 1.05
		if b.z > top:
			b.z = 0.08
		_bub[k] = b
		var rmax := radius_at(b.z) * 0.8
		var x := b.x + 0.04 * sin(_time * 2.0 + k)
		var z := b.y
		var d := Vector2(x, z).length()
		if d > rmax and d > 0.0:
			x *= rmax / d
			z *= rmax / d
		_bubbles[k].position = _deform(Vector3(x, b.z, z), sx, _sy, lean)
		_bubbles[k].visible = puddle < 0.6
	_tick_drops(dt)


## Hit: a splash of droplets flies off and falls.
func _splat() -> void:
	splats += 1
	if not is_inside_tree():
		return
	for k in 6:
		var a := randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		var n := MeshInstance3D.new()
		n.mesh = _drop_mesh
		n.top_level = true
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
		n.global_position = global_transform * (dir * RADIUS * 0.9 + Vector3(0, 0.5, 0))
		n.scale = Vector3.ONE * size * randf_range(0.6, 1.3)
		_drops.append({"node": n, "vel": dir * randf_range(2.0, 3.5) * size + Vector3(0, randf_range(2.5, 4.0), 0), "life": 0.7})
		if _drops.size() > DROPS * 2:
			var old: Dictionary = _drops.pop_front()
			(old["node"] as Node).queue_free()


func _tick_drops(dt: float) -> void:
	for k in range(_drops.size() - 1, -1, -1):
		var d: Dictionary = _drops[k]
		d["life"] -= dt
		var n: MeshInstance3D = d["node"]
		if d["life"] <= 0.0:
			n.queue_free()
			_drops.remove_at(k)
			continue
		d["vel"] += Vector3(0, -12.0, 0) * dt
		n.global_position += d["vel"] * dt
		var s: float = clampf(d["life"] / 0.25, 0.0, 1.0)
		n.scale = Vector3(1.0, 1.0 + 0.6 * (1.0 - s), 1.0) * size * s


func set_dim(f: float) -> void:
	if mat:
		mat.set_shader_parameter("dim", f)
		mat_in.set_shader_parameter("dim", f)


func set_hurt(f: float) -> void:
	if mat:
		mat.set_shader_parameter("hurt", f)


func set_growth(g: float) -> void:
	growth = clampf(g, 0.0, 0.5)


## Where its burns and casts come from: the middle of the jelly.
func tip() -> Vector3:
	return global_transform * Vector3(0, 0.7, -0.3)
