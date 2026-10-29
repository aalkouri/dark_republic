class_name SkeletonCrowd
extends Node3D
## Skeletons (EnemyManager.SKELETON) and their epic version, the Armored Skeleton. They live in
## EnemyManager's arrays like every goblin; this draws them and gives them their extras:
##   - models built in code (bones are simple shapes) with the walk, claw and throw animated in
##     the vertex shader per instance (COLOR.r = animation, COLOR.g = phase; INSTANCE_CUSTOM =
##     the same tint / burn / flash / epic / frozen / chill / shadow codes as the goblins)
##   - bone throwing: from THROW_MIN to THROW_MAX metres away, with a clear line (indoors),
##     every THROW_EVERY seconds a skeleton stops, winds up and lobs a bone at you on a real
##     ballistic arc, leading your movement. Bones break on walls and the floor.
##   - death: the skeleton clatters apart into bones that bounce and fade, instead of a corpse.

const HEIGHT := 1.75
const THROW_MIN := 3.0
const THROW_MAX := 17.0
const THROW_EVERY := Vector2(2.4, 3.6)   # random gap between throws (s)
const THROW_WINDUP := 0.45               # stands still this long; the bone leaves halfway
const BONE_DAMAGE := 0.7                 # x the skeleton's contact damage (armoured: x1.4 more)
const GRAVITY := 14.0
const BONES_MAX := 160
const DEBRIS_MAX := 500
const STRIDE := 20
const ANIM_RUN := 0.0
const ANIM_ATTACK := 0.5
const ANIM_THROW := 1.0

const BONE := Color(0.86, 0.83, 0.74, 0.0)
const BONE_DARK := Color(0.6, 0.57, 0.5, 0.0)
const STEEL := Color(0.36, 0.37, 0.42, 0.0)
const RUST := Color(0.4, 0.22, 0.12, 0.0)

const SHADER := """
shader_type spatial;
// COLOR.a of a vertex = its limb: 0 body, 1 L leg, 2 R leg, 3 L arm, 4 R arm, 5 head, 6 eyes (glow)
// INSTANCE_CUSTOM.r = animation (0 walk, 0.5 claw, 1 throw), .g = phase 0..1,
// .a = burn + 2 flash + 4 epic + 8 frozen + 16 chill + 32 shadow. (The instance colour is
// left white: Godot multiplies it into the vertex COLOR, whose alpha holds the limb id.)
uniform vec3 eye_color : source_color = vec3(0.3, 0.9, 1.0);
varying float burn;
varying float flash;
varying float epic;
varying float frozen;
varying float chill;
varying float shadow;
varying float eye;

mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_z(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }

void vertex() {
	int limb = int(COLOR.a * 8.0 + 0.5);
	float anim = INSTANCE_CUSTOM.r;
	float ph = INSTANCE_CUSTOM.g * 6.2831853;
	float walk = 1.0 - step(0.25, anim);
	float claw = step(0.25, anim) * (1.0 - step(0.75, anim));
	float throw_ = step(0.75, anim);
	vec3 v = VERTEX;
	vec3 hip_l = vec3(0.11, 0.95, 0.0);
	vec3 hip_r = vec3(-0.11, 0.95, 0.0);
	vec3 sh_l = vec3(0.22, 1.43, 0.0);
	vec3 sh_r = vec3(-0.22, 1.43, 0.0);
	float swing = sin(ph) * 0.65 * walk;
	if (limb == 1) { v = hip_l + rot_x(swing) * (v - hip_l); }
	if (limb == 2) { v = hip_r + rot_x(-swing) * (v - hip_r); }
	if (limb == 3) {
		float a = -swing * 0.8 + claw * (-1.6 + sin(ph) * 0.9) + throw_ * -0.3;
		v = sh_l + rot_x(a) * (v - sh_l);
	}
	if (limb == 4) {
		// throw: wind the arm back over the shoulder, then whip it forward
		float t = INSTANCE_CUSTOM.g;
		float th = throw_ * (t < 0.5 ? mix(0.0, 2.6, t * 2.0) : mix(2.6, -1.2, (t - 0.5) * 2.0));
		float a = swing * 0.8 + claw * (-1.6 + sin(ph + 3.14) * 0.9) + th;
		v = sh_r + rot_x(a) * (v - sh_r);
	}
	if (limb >= 5) { v.y += sin(ph * 2.0) * 0.02 * walk; v = vec3(0, 1.55, 0) + rot_z(sin(ph) * 0.06 * walk) * (v - vec3(0, 1.55, 0)); }
	// a little bob and sway of the whole body while walking
	v.y += abs(sin(ph)) * 0.04 * walk;
	VERTEX = v;
	eye = limb == 6 ? 1.0 : 0.0;
	float a = INSTANCE_CUSTOM.a;
	shadow = step(31.5, a); a -= shadow * 32.0;
	chill = step(15.5, a); a -= chill * 16.0;
	frozen = step(7.5, a); a -= frozen * 8.0;
	epic = step(3.5, a); a -= epic * 4.0;
	flash = step(1.5, a); a -= flash * 2.0;
	burn = clamp(a, 0.0, 1.0);
	flash *= smoothstep(18.0, 12.0, length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
}

void fragment() {
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	col = mix(col, col * vec3(0.92, 0.78, 1.12), epic * 0.5);
	col = mix(col, vec3(1.0, 0.42, 0.08), burn * 0.6);
	col = mix(col, col * vec3(0.55, 0.8, 1.25), chill * 0.55);
	col = mix(col, vec3(0.72, 0.9, 1.0), frozen * 0.78);
	col = mix(col, col * vec3(0.35, 0.22, 0.5), shadow * 0.7);
	ALBEDO = mix(col, col * vec3(1.45, 0.55, 0.45), flash * 0.6);
	ROUGHNESS = 0.75;
	EMISSION = eye * eye_color * 3.0 + vec3(1.0, 0.32, 0.04) * burn * 0.9 + vec3(0.62, 0.18, 1.0) * epic * rim * 1.6
		+ vec3(0.45, 0.8, 1.0) * (frozen * (0.25 + rim * 1.4) + chill * rim * 0.6) + vec3(0.6, 0.2, 1.0) * shadow * rim * 1.8;
}
"""

var em: EnemyManager
var _mm: MultiMesh                 # plain skeletons
var _mm_armored: MultiMesh         # armoured (epic) skeletons
var _buf := PackedFloat32Array()
var _buf_a := PackedFloat32Array()
# Bones in flight
var _b_pos := PackedVector3Array()
var _b_vel := PackedVector3Array()
var _b_dmg := PackedFloat32Array()
var _b_spin := PackedFloat32Array()
var _b_life := PackedFloat32Array()
var _b_n := 0
var _bones_mm: MultiMesh
# Bones scattered by a dead skeleton
var _d_pos := PackedVector3Array()
var _d_vel := PackedVector3Array()
var _d_rot := PackedVector3Array()
var _d_spin := PackedVector3Array()
var _d_age := PackedFloat32Array()
var _d_scale := PackedFloat32Array()
var _d_n := 0
var _debris_mm: MultiMesh
var thrown := 0                    # counters for tests
var bone_hits := 0
var _sfx: Array[AudioStreamPlayer3D] = []
var _clatter: AudioStream


func _ready() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var mat_a := ShaderMaterial.new()
	mat_a.shader = sh
	mat_a.set_shader_parameter("eye_color", Color(1.0, 0.25, 0.15))
	_mm = _crowd_mm(build_mesh(false, mat))
	_mm_armored = _crowd_mm(build_mesh(true, mat_a))
	_buf.resize(EnemyManager.MAX * STRIDE)
	_buf_a.resize(EnemyManager.MAX * STRIDE)
	for a in [_b_pos, _b_vel]:
		a.resize(BONES_MAX)
	for a in [_b_dmg, _b_spin, _b_life]:
		a.resize(BONES_MAX)
	for a in [_d_pos, _d_vel, _d_rot, _d_spin]:
		a.resize(DEBRIS_MAX)
	for a in [_d_age, _d_scale]:
		a.resize(DEBRIS_MAX)
	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.86, 0.83, 0.74)
	bone_mat.roughness = 0.8
	_bones_mm = _simple_mm(_bone_mesh(bone_mat), BONES_MAX)
	_debris_mm = _simple_mm(_bone_mesh(bone_mat), DEBRIS_MAX)
	for k in 3:
		var a := AudioStreamPlayer3D.new()
		a.bus = Settings.SFX_BUS
		a.unit_size = 8.0
		a.max_distance = 35.0
		add_child(a)
		_sfx.append(a)
	if ResourceLoader.exists("res://audio/castle/bone_clatter.wav"):
		_clatter = load("res://audio/castle/bone_clatter.wav")


func _crowd_mm(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = EnemyManager.MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(mmi)
	return mm


func _simple_mm(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.top_level = true
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(mmi)
	return mm


## A thrown / scattered bone: a shaft with two knobs at each end, along X.
static func _bone_mesh(mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	mb.limb(Vector3(-0.17, 0, 0), Vector3(0.17, 0, 0), 0.03, 0.03, Color.WHITE, 6)
	for x in [-0.18, 0.18]:
		for z in [-0.03, 0.03]:
			mb.add(MeshBuilder.sphere(0.04, 6, 4), Transform3D(Basis(), Vector3(x, 0, z)), Color.WHITE)
	return mb.commit(mat)


## The skeleton (facing +Z, feet at the origin, HEIGHT tall). Vertex alpha = limb id / 8.
static func build_mesh(armored: bool, mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var body := 0.0
	var ll := 1.0 / 8.0
	var rl := 2.0 / 8.0
	var la := 3.0 / 8.0
	var ra := 4.0 / 8.0
	var hd := 5.0 / 8.0
	var ey := 6.0 / 8.0
	var b := func(c: Color, limb: float) -> Color: return Color(c.r, c.g, c.b, limb)
	# Legs: thigh, shin, foot
	for side in [1.0, -1.0]:
		var limb := ll if side > 0 else rl
		mb.limb(Vector3(side * 0.11, 0.95, 0), Vector3(side * 0.12, 0.52, 0.02), 0.04, 0.035, b.call(BONE, limb), 6)
		mb.add(MeshBuilder.sphere(0.055, 6, 4), Transform3D(Basis(), Vector3(side * 0.12, 0.5, 0.02)), b.call(BONE, limb))
		mb.limb(Vector3(side * 0.12, 0.5, 0.02), Vector3(side * 0.12, 0.07, 0.0), 0.033, 0.03, b.call(BONE, limb), 6)
		mb.add(MeshBuilder.box(Vector3(0.09, 0.05, 0.22)), Transform3D(Basis(), Vector3(side * 0.12, 0.03, 0.06)), b.call(BONE_DARK, limb))
	# Pelvis and spine
	mb.add(MeshBuilder.sphere(0.16, 8, 5), Transform3D(Basis.from_scale(Vector3(1.3, 0.55, 0.8)), Vector3(0, 0.98, 0)), b.call(BONE_DARK, body))
	for k in 6:
		mb.add(MeshBuilder.sphere(0.045, 6, 4), Transform3D(Basis(), Vector3(0, 1.04 + k * 0.07, -0.05)), b.call(BONE, body))
	# Ribcage: curved ribs
	for k in 5:
		var y := 1.18 + k * 0.055
		var w := 0.17 - absf(k - 2) * 0.012
		mb.add(MeshBuilder.cyl(w, w, 0.025, 12), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.72)), Vector3(0, y, 0.01)), b.call(BONE, body))
	mb.limb(Vector3(0, 1.17, 0.12), Vector3(0, 1.42, 0.11), 0.025, 0.025, b.call(BONE, body), 5)   # sternum
	mb.limb(Vector3(-0.22, 1.43, 0), Vector3(0.22, 1.43, 0), 0.025, 0.025, b.call(BONE, body), 5)  # collarbones
	# Arms: upper, forearm, hand; the right hand holds a bone ready to throw
	for side in [1.0, -1.0]:
		var limb := la if side > 0 else ra
		mb.add(MeshBuilder.sphere(0.05, 6, 4), Transform3D(Basis(), Vector3(side * 0.22, 1.43, 0)), b.call(BONE, limb))
		mb.limb(Vector3(side * 0.22, 1.43, 0), Vector3(side * 0.25, 1.12, 0.02), 0.03, 0.028, b.call(BONE, limb), 6)
		mb.limb(Vector3(side * 0.25, 1.12, 0.02), Vector3(side * 0.25, 0.86, 0.1), 0.026, 0.022, b.call(BONE, limb), 6)
		for f in 3:
			mb.limb(Vector3(side * 0.25, 0.86, 0.1), Vector3(side * (0.23 + f * 0.02), 0.77, 0.14), 0.01, 0.006, b.call(BONE, limb), 4)
	mb.limb(Vector3(-0.25, 0.86, 0.02), Vector3(-0.25, 0.86, 0.32), 0.022, 0.022, b.call(BONE, ra), 5)   # the bone in hand
	# Skull, jaw, glowing eyes
	mb.add(MeshBuilder.sphere(0.12, 10, 7), Transform3D(Basis.from_scale(Vector3(1.0, 1.05, 1.1)), Vector3(0, 1.6, 0.01)), b.call(BONE, hd))
	mb.add(MeshBuilder.box(Vector3(0.14, 0.05, 0.1)), Transform3D(Basis(), Vector3(0, 1.5, 0.07)), b.call(BONE_DARK, hd))
	for side in [1.0, -1.0]:
		mb.add(MeshBuilder.sphere(0.03, 6, 4), Transform3D(Basis(), Vector3(side * 0.045, 1.62, 0.115)), Color(0.9, 0.95, 1.0, ey))
	if armored:
		# Helmet with a crest, breastplate, pauldrons, greaves, a round shield on the left arm
		mb.add(MeshBuilder.sphere(0.145, 10, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.85, 1.1)), Vector3(0, 1.66, 0)), b.call(STEEL, hd))
		mb.add(MeshBuilder.box(Vector3(0.03, 0.1, 0.28)), Transform3D(Basis(), Vector3(0, 1.8, -0.01)), b.call(RUST, hd))
		mb.add(MeshBuilder.box(Vector3(0.24, 0.035, 0.03)), Transform3D(Basis(), Vector3(0, 1.58, 0.15)), b.call(STEEL, hd))   # visor bar
		mb.add(MeshBuilder.cyl(0.2, 0.17, 0.36, 12), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.75)), Vector3(0, 1.26, 0.01)), b.call(STEEL, body))
		mb.add(MeshBuilder.cyl(0.19, 0.2, 0.12, 12), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.75)), Vector3(0, 1.02, 0)), b.call(STEEL.darkened(0.2), body))
		for side in [1.0, -1.0]:
			var arm := la if side > 0 else ra
			mb.add(MeshBuilder.sphere(0.11, 8, 5), Transform3D(Basis.from_scale(Vector3(1.1, 0.7, 1.0)), Vector3(side * 0.25, 1.46, 0)), b.call(STEEL, arm))
			var leg := ll if side > 0 else rl
			mb.add(MeshBuilder.cyl(0.055, 0.05, 0.3, 8), Transform3D(Basis(), Vector3(side * 0.12, 0.28, 0.02)), b.call(STEEL, leg))
		mb.add(MeshBuilder.cyl(0.24, 0.24, 0.04, 16), Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(0.31, 1.05, 0.06)), b.call(RUST.lerp(STEEL, 0.4), la))
		mb.add(MeshBuilder.sphere(0.05, 6, 4), Transform3D(Basis(), Vector3(0.34, 1.05, 0.06)), b.call(STEEL, la))
	return mb.commit(mat)


# ------------------------------------------------------------------ per frame

## Called by EnemyManager at the end of its tick, before it uploads the goblin buffer: moves the
## skeleton rows out of the goblin MultiMesh into the skeleton ones, runs the throwing and the
## bones in flight. `buf` is the goblin instance buffer.
func sync(dt: float, buf: PackedFloat32Array, player: Node3D) -> PackedFloat32Array:
	var n := 0
	var na := 0
	var pp := player.global_position if player != null else Vector3.INF
	var nav := CastleNav.current
	for i in em.count:
		if em.typ[i] != EnemyManager.SKELETON:
			continue
		var b := i * STRIDE
		var anim := ANIM_ATTACK if absf(buf[b + 12] - em._clip_attack) < 0.01 else ANIM_RUN
		var phase := buf[b + 13]
		if not em.dead[i]:
			if em.throw_anim[i] > 0.0:
				var before := em.throw_anim[i]
				em.throw_anim[i] -= dt
				anim = ANIM_THROW
				phase = 1.0 - em.throw_anim[i] / THROW_WINDUP
				if before > THROW_WINDUP * 0.5 and em.throw_anim[i] <= THROW_WINDUP * 0.5 and pp != Vector3.INF:
					_throw(i, pp, player)
			elif not em.is_held(i) and pp != Vector3.INF:
				em.throw_t[i] -= dt
				if em.throw_t[i] <= 0.0:
					var d := Vector2(pp.x - em.pos[i].x, pp.z - em.pos[i].z).length()
					em.throw_t[i] = randf_range(THROW_EVERY.x, THROW_EVERY.y) * 0.5
					if d >= THROW_MIN and d <= THROW_MAX and not em.fear and not em.lost and (nav == null or nav.line_clear(em.pos[i], pp)):
						em.throw_anim[i] = THROW_WINDUP
						em.throw_t[i] = randf_range(THROW_EVERY.x, THROW_EVERY.y)
		var dst: PackedFloat32Array
		var o: int
		if em.epic[i]:
			o = na * STRIDE
			na += 1
		else:
			o = n * STRIDE
			n += 1
		for k in 12:
			var val := buf[b + k]
			if em.epic[i]:
				_buf_a[o + k] = val
			else:
				_buf[o + k] = val
			buf[b + k] = 0.0   # hide it in the goblin MultiMesh
		var code := buf[b + 19]
		if em.epic[i]:   # colour (white) then custom (anim, phase, -, status code)
			_buf_a[o + 12] = 1.0; _buf_a[o + 13] = 1.0; _buf_a[o + 14] = 1.0; _buf_a[o + 15] = 1.0
			_buf_a[o + 16] = anim; _buf_a[o + 17] = phase; _buf_a[o + 18] = 0.0; _buf_a[o + 19] = code
		else:
			_buf[o + 12] = 1.0; _buf[o + 13] = 1.0; _buf[o + 14] = 1.0; _buf[o + 15] = 1.0
			_buf[o + 16] = anim; _buf[o + 17] = phase; _buf[o + 18] = 0.0; _buf[o + 19] = code
	_mm.buffer = _buf
	_mm.visible_instance_count = n
	_mm_armored.buffer = _buf_a
	_mm_armored.visible_instance_count = na
	_tick_bones(dt, player)
	_tick_debris(dt)
	return buf


func _throw(i: int, target: Vector3, player: Node3D) -> void:
	if _b_n >= BONES_MAX:
		return
	var s := em.t_scale[em.typ[i]] * em.sz[i]
	var from := em.pos[i] + Vector3(0, 1.55 * s, 0)
	var v: Vector3 = player.get("velocity") if player.get("velocity") != null else Vector3.ZERO
	var aim := target + Vector3(0, 1.0, 0)
	var d := Vector2(aim.x - from.x, aim.z - from.z).length()
	var t := clampf(d / 13.0, 0.45, 1.3)
	aim += Vector3(v.x, 0, v.z) * t * 0.6   # lead the target
	var vel := (aim - from) / t + Vector3(0, 0.5 * GRAVITY * t, 0)
	var k := _b_n
	_b_n += 1
	_b_pos[k] = from
	_b_vel[k] = vel
	_b_dmg[k] = em.t_damage[em.typ[i]] * BONE_DAMAGE * (1.4 if em.epic[i] else 1.0)
	_b_spin[k] = randf() * TAU
	_b_life[k] = 3.0
	thrown += 1


func _tick_bones(dt: float, player: Node3D) -> void:
	var nav := CastleNav.current
	var chest := player.global_position + Vector3(0, 0.95, 0) if player != null else Vector3.INF
	var buf := PackedFloat32Array()
	buf.resize(BONES_MAX * 12)
	var i := 0
	while i < _b_n:
		_b_life[i] -= dt
		_b_vel[i].y -= GRAVITY * dt
		var p := _b_pos[i] + _b_vel[i] * dt
		_b_pos[i] = p
		_b_spin[i] += dt * 18.0
		var gone := _b_life[i] <= 0.0
		if not gone and chest != Vector3.INF:
			var d := p - chest
			if absf(d.y) < 0.95 and Vector2(d.x, d.z).length() < 0.6:
				if player.has_method("hurt") and player.hurt(_b_dmg[i]):
					bone_hits += 1
					player.knockback(Vector3(_b_vel[i].x, 0, _b_vel[i].z))
				_shatter_bone(p, _b_vel[i] * 0.2)
				gone = true
		if not gone and p.y < SwampWater.height_at(p.x, p.z) + 0.05:
			_shatter_bone(p, Vector3(_b_vel[i].x, 0, _b_vel[i].z) * 0.15)
			gone = true
		if not gone and nav != null and p.y < Abilities.ceiling and nav.is_blocked(p.x, p.z) and _hits_wall(p):
			_shatter_bone(p, -_b_vel[i] * 0.1)
			gone = true
		if gone:
			var last := _b_n - 1
			_b_pos[i] = _b_pos[last]
			_b_vel[i] = _b_vel[last]
			_b_dmg[i] = _b_dmg[last]
			_b_spin[i] = _b_spin[last]
			_b_life[i] = _b_life[last]
			_b_n -= 1
			continue
		var fwd := _b_vel[i].normalized()
		var basis := Basis(Vector3.UP, atan2(fwd.x, fwd.z) + PI / 2) * Basis(Vector3(0, 0, 1), _b_spin[i])
		_put(buf, i, Transform3D(basis.scaled(Vector3.ONE * 1.3), p))
		i += 1
	_bones_mm.buffer = buf
	_bones_mm.visible_instance_count = _b_n


## Walls and solid furniture are only "solid" up to a height; the table and benches are low.
func _hits_wall(p: Vector3) -> bool:
	var feast := get_tree().get_first_node_in_group("castle_feast")
	if feast and p.y > 1.3:
		var r: Array = feast.rect
		if p.x > float(r[0]) - 2.0 and p.x < float(r[2]) + 2.0 and p.z > float(r[1]) - 1.0 and p.z < float(r[3]) + 1.0:
			return false   # flying over the table
	return true


func _put(buf: PackedFloat32Array, i: int, xf: Transform3D) -> void:
	var b := i * 12
	var bs := xf.basis
	buf[b] = bs.x.x; buf[b + 1] = bs.y.x; buf[b + 2] = bs.z.x; buf[b + 3] = xf.origin.x
	buf[b + 4] = bs.x.y; buf[b + 5] = bs.y.y; buf[b + 6] = bs.z.y; buf[b + 7] = xf.origin.y
	buf[b + 8] = bs.x.z; buf[b + 9] = bs.y.z; buf[b + 10] = bs.z.z; buf[b + 11] = xf.origin.z


func _shatter_bone(at: Vector3, vel: Vector3) -> void:
	for k in 2:
		_debris(at, vel + Vector3(randf_range(-2, 2), randf_range(1.5, 3.5), randf_range(-2, 2)), 0.5)
	_play(at, 0.7)


## A dead skeleton falls apart: a skull and a handful of bones scatter and bounce.
func scatter(at: Vector3, scale: float, armored: bool) -> void:
	for k in 9:
		var v := Vector3(randf_range(-2.5, 2.5), randf_range(2.0, 5.0), randf_range(-2.5, 2.5))
		_debris(at + Vector3(randf_range(-0.2, 0.2), randf_range(0.4, 1.5) * scale, randf_range(-0.2, 0.2)), v, scale * (1.4 if k == 0 else 1.0))
	_play(at, 1.0)


func _debris(at: Vector3, vel: Vector3, scale: float) -> void:
	var k := _d_n
	if _d_n < DEBRIS_MAX:
		_d_n += 1
	else:
		k = randi() % DEBRIS_MAX
	_d_pos[k] = at
	_d_vel[k] = vel
	_d_rot[k] = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_d_spin[k] = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
	_d_age[k] = 0.0
	_d_scale[k] = scale


func _tick_debris(dt: float) -> void:
	var buf := PackedFloat32Array()
	buf.resize(DEBRIS_MAX * 12)
	var i := 0
	while i < _d_n:
		_d_age[i] += dt
		if _d_age[i] > 3.0:
			var last := _d_n - 1
			_d_pos[i] = _d_pos[last]
			_d_vel[i] = _d_vel[last]
			_d_rot[i] = _d_rot[last]
			_d_spin[i] = _d_spin[last]
			_d_age[i] = _d_age[last]
			_d_scale[i] = _d_scale[last]
			_d_n -= 1
			continue
		var v := _d_vel[i]
		v.y -= GRAVITY * dt
		var p := _d_pos[i] + v * dt
		var g := SwampWater.height_at(p.x, p.z) + 0.04
		if p.y < g:   # bounce, losing most of the energy, then rest
			p.y = g
			v = Vector3(v.x * 0.5, -v.y * 0.3, v.z * 0.5)
			_d_spin[i] *= 0.5
			if absf(v.y) < 0.6:
				v.y = 0.0
		_d_pos[i] = p
		_d_vel[i] = v
		_d_rot[i] += _d_spin[i] * dt
		var fade := clampf((3.0 - _d_age[i]) / 0.6, 0.0, 1.0)
		var r := _d_rot[i]
		_put(buf, i, Transform3D(Basis.from_euler(r).scaled(Vector3.ONE * _d_scale[i] * fade), p - Vector3(0, (1.0 - fade) * 0.2, 0)))
		i += 1
	_debris_mm.buffer = buf
	_debris_mm.visible_instance_count = _d_n


func _play(at: Vector3, volume: float) -> void:
	if _clatter == null:
		return
	var a := _sfx[randi() % _sfx.size()]
	if a.playing and randf() < 0.6:
		return
	a.stream = _clatter
	a.volume_db = linear_to_db(volume) - 4.0
	a.pitch_scale = randf_range(0.85, 1.2)
	a.global_position = at
	a.play()


func bones_in_flight() -> int:
	return _b_n


func debris_count() -> int:
	return _d_n
