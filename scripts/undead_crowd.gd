class_name UndeadCrowd
extends Node3D
## The Haunted Graveyard's dead: GHOULS (EnemyManager.GHOUL) and GHOSTS (EnemyManager.GHOST).
## Like every goblin they are rows in EnemyManager's arrays (so every weapon, burn and freeze
## hits them); like the skeletons (SkeletonCrowd) they are drawn here, each as its own
## MultiMesh whose vertex shader animates them per instance, and moved out of the goblin buffer
## in sync().
##   GHOUL  the graveyard's common walker (in place of the goblin): a gaunt, hunched, grey-green
##          corpse-eater on all-but-fours, loping fast, raking with long black claws. Dies by
##          pitching forward into the dirt and sinking, in a spatter of dark ichor.
##   GHOST  a hooded, tattered wraith that floats GHOST_FLOAT above the ground with a wispy tail,
##          drawn see-through and flickering. It drifts through tombstones, railings and crypt
##          walls (nothing outdoors stops the dead), and its touch CHILLS you: CHILL_SLOW speed
##          for CHILL_SECS. Its hit box reaches up to its floating body, so every shot connects.
##          Dies by rising up, stretching thin and fading out with a wail.
## Both (and the skeletons) can RISE out of the ground: raise() plants one sunk below the
## surface, clawing its way out for RISE_TIME (harmless meanwhile) amid flying clods of earth.
## grave_swarm() is the graveyard's swarm: the dead climb out of the graves all round you.

const GHOUL_HEIGHT := 1.45
const GHOST_HEIGHT := 2.5          # the hit box (float + body)
const GHOST_FLOAT := 0.75
const CHILL_SLOW := 0.6
const CHILL_SECS := 1.6
const RISE_TIME := 1.3
const DYING_MAX := 300
const DIE_GHOUL := 1.2
const DIE_GHOST := 1.5
const CLODS_MAX := 400
const STRIDE := 20
const ANIM_WALK := 0.0
const ANIM_ATTACK := 0.5
const ANIM_DIE := 1.0

const GHOUL_SHADER := """
shader_type spatial;
// COLOR.a of a vertex = its part: 0 body, 1 L leg, 2 R leg, 3 L arm, 4 R arm, 5 head, 6 eyes (glow), 7 rags
// INSTANCE_CUSTOM.r = animation (0 lope, 0.5 rake, 1 die), .g = phase 0..1 (dying: 0..1 of the fall),
// .a = burn + 2 flash + 4 epic + 8 frozen + 16 chill + 32 shadow
varying float burn;
varying float flash;
varying float epic;
varying float frozen;
varying float chill;
varying float shadow;
varying float eye;
varying float dying;
mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_z(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }
void vertex() {
	int part = int(COLOR.a * 8.0 + 0.5);
	float anim = INSTANCE_CUSTOM.r;
	float t = INSTANCE_CUSTOM.g;
	float ph = t * 6.2831853;
	float walk = 1.0 - step(0.25, anim);
	float rake = step(0.25, anim) * (1.0 - step(0.75, anim));
	float die = step(0.75, anim);
	vec3 v = VERTEX;
	vec3 hip_l = vec3(0.12, 0.72, 0.0);
	vec3 hip_r = vec3(-0.12, 0.72, 0.0);
	vec3 sh_l = vec3(0.22, 1.12, 0.32);
	vec3 sh_r = vec3(-0.22, 1.12, 0.32);
	float swing = sin(ph) * 0.85 * walk;
	if (part == 1) { v = hip_l + rot_x(swing) * (v - hip_l); }
	if (part == 2) { v = hip_r + rot_x(-swing) * (v - hip_r); }
	if (part == 3) {
		float a = -swing * 0.7 + rake * (-2.0 + sin(ph) * 1.4) + die * -1.2 * t;
		v = sh_l + rot_x(a) * (v - sh_l);
	}
	if (part == 4) {
		float a = swing * 0.7 + rake * (-2.0 + sin(ph + 3.14) * 1.4) + die * -1.2 * t;
		v = sh_r + rot_x(a) * (v - sh_r);
	}
	if (part >= 5 && part <= 6) {
		vec3 nk = vec3(0.0, 1.18, 0.42);
		v = nk + rot_x(sin(ph * 2.0) * 0.12 * walk - rake * 0.35) * rot_z(sin(ph) * 0.1 * walk) * (v - nk);
	}
	if (part == 7) { v.x += sin(TIME * 4.0 + v.y * 6.0) * 0.03; v.z -= abs(sin(ph)) * 0.06 * walk; }
	// the lope: the whole body bobs and rocks
	v.y += abs(sin(ph)) * 0.08 * walk;
	v = vec3(0.0, 0.7, 0.0) + rot_z(sin(ph) * 0.06 * walk) * (v - vec3(0.0, 0.7, 0.0));
	// dying: pitch forward onto the face, then sink into the ground
	if (die > 0.5) {
		float f = clamp(t * 1.6, 0.0, 1.0);
		v = rot_x(f * f * 1.45) * v;
		v.y -= smoothstep(0.55, 1.0, t) * 0.9;
	}
	dying = die;
	VERTEX = v;
	eye = part == 6 ? 1.0 : 0.0;
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
	ROUGHNESS = 0.55;
	SPECULAR = 0.45;
	EMISSION = eye * vec3(0.85, 1.0, 0.25) * 3.5 * (1.0 - dying) + vec3(1.0, 0.32, 0.04) * burn * 0.9 + vec3(0.62, 0.18, 1.0) * epic * rim * 1.6
		+ vec3(0.45, 0.8, 1.0) * (frozen * (0.25 + rim * 1.4) + chill * rim * 0.6) + vec3(0.6, 0.2, 1.0) * shadow * rim * 1.8 + vec3(0.25, 0.35, 0.3) * rim * 0.25;
}
"""

const GHOST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
// COLOR.a = part: 0 shroud, 1 L arm, 2 R arm, 3 hood/face, 4 eyes, 5 tatters and tail (sway)
// INSTANCE_CUSTOM.r = animation (0 drift, 0.5 lunge, 1 die), .g = phase (dying: 0..1),
// .b = how far risen out of the ground (1 = fully), .a = status code as the goblins
varying float burn;
varying float flash;
varying float epic;
varying float frozen;
varying float chill;
varying float eye;
varying float fade;
varying float seed;
varying float face;
mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
void vertex() {
	int part = int(COLOR.a * 8.0 + 0.5);
	float anim = INSTANCE_CUSTOM.r;
	float t = INSTANCE_CUSTOM.g;
	float lunge = step(0.25, anim) * (1.0 - step(0.75, anim));
	float die = step(0.75, anim);
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	seed = fract(sin(dot(floor(wp.xz * 0.5), vec2(12.9898, 78.233))) * 43758.5453) * 50.0;
	vec3 v = VERTEX;
	float low = clamp((1.0 - v.y) / 1.0, 0.0, 1.0);
	// the shroud ripples and the tail streams out behind
	if (part == 0 || part == 5) {
		float w = part == 5 ? 1.0 : low * 0.6;
		v.x += sin(TIME * 3.1 + v.y * 5.0 + seed) * 0.07 * w;
		v.z += -low * low * 0.35 + sin(TIME * 2.3 + v.y * 4.0 + seed) * 0.06 * w;
	}
	vec3 sh_l = vec3(0.2, 1.42, 0.05);
	vec3 sh_r = vec3(-0.2, 1.42, 0.05);
	float reach = sin(TIME * 1.7 + seed) * 0.25;
	if (part == 1) { v = sh_l + rot_x(-0.4 + reach - lunge * (1.0 + sin(t * 6.28) * 0.3) - die * 1.6 * t) * (v - sh_l); }
	if (part == 2) { v = sh_r + rot_x(-0.4 - reach - lunge * (1.0 + sin(t * 6.28 + 2.0) * 0.3) - die * 1.6 * t) * (v - sh_r); }
	if (part == 3 || part == 4) {
		vec3 nk = vec3(0.0, 1.5, 0.0);
		v = nk + rot_x(-lunge * 0.35 + sin(TIME * 1.3 + seed) * 0.08) * (v - nk);
	}
	// floating: a slow bob; dying: rise and stretch thin
	v.y += sin(TIME * 2.0 + seed) * 0.12;
	if (die > 0.5) {
		v.xz *= 1.0 - t * 0.6;
		v.y = v.y * (1.0 + t * 1.2) + t * t * 2.5;
	}
	VERTEX = v;
	eye = part == 4 ? 1.0 : 0.0;
	face = part == 3 ? 1.0 : 0.0;
	fade = (1.0 - die * t) * clamp(INSTANCE_CUSTOM.b, 0.0, 1.0);
	float a = INSTANCE_CUSTOM.a;
	a -= step(31.5, a) * 32.0;
	chill = step(15.5, a); a -= chill * 16.0;
	frozen = step(7.5, a); a -= frozen * 8.0;
	epic = step(3.5, a); a -= epic * 4.0;
	flash = step(1.5, a); a -= flash * 2.0;
	burn = clamp(a, 0.0, 1.0);
}
void fragment() {
	vec3 base = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	// flicker: a shimmer, and now and then it nearly winks out
	float fl = 0.82 + 0.18 * sin(TIME * 23.0 + seed);
	float wink = step(0.94, fract(sin(floor(TIME * 7.0 + seed) * 12.9898) * 43758.5453));
	fl *= 1.0 - wink * 0.7;
	vec3 tint = mix(vec3(0.62, 0.95, 1.0), vec3(0.8, 0.55, 1.0), epic);
	tint = mix(tint, vec3(1.0, 0.5, 0.15), burn * 0.6);
	tint = mix(tint, vec3(0.8, 0.95, 1.0), frozen * 0.6);
	vec3 col = base * tint * 1.1 + tint * rim * 0.9;
	col = mix(col, vec3(1.0), flash * 0.6);
	ALBEDO = col + eye * vec3(0.4, 1.0, 1.0) * 3.0;
	ALPHA = clamp((0.22 + rim * 0.55 + face * 0.15 + eye) * fl * fade, 0.0, 1.0);
}
"""

var em: EnemyManager
var _mm_ghoul: MultiMesh
var _mm_ghost: MultiMesh
var _buf_g := PackedFloat32Array()
var _buf_h := PackedFloat32Array()
# the dying (drawn on after their rows are gone)
var _d_pos := PackedVector3Array()
var _d_face := PackedVector2Array()
var _d_scale := PackedFloat32Array()
var _d_t := PackedFloat32Array()
var _d_kind := PackedInt32Array()
var _d_code := PackedFloat32Array()
var _d_n := 0
# clods of earth thrown up by the risen
var _c_pos := PackedVector3Array()
var _c_vel := PackedVector3Array()
var _c_age := PackedFloat32Array()
var _c_n := 0
var _clods_mm: MultiMesh
# counters for tests
var ghouls_drawn := 0
var ghosts_drawn := 0
var chills := 0
var risen := 0
var deaths := 0
var _chill_cd := 0.0
var _voice_t := 3.0
var _sfx := {}
var _voices: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	var sh := Shader.new()
	sh.code = GHOUL_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_mm_ghoul = _crowd_mm(build_ghoul(mat), true)
	var sh2 := Shader.new()
	sh2.code = GHOST_SHADER
	var mat2 := ShaderMaterial.new()
	mat2.shader = sh2
	mat2.render_priority = 3
	_mm_ghost = _crowd_mm(build_ghost(mat2), false)
	_buf_g.resize((EnemyManager.MAX + DYING_MAX) * STRIDE)
	_buf_h.resize((EnemyManager.MAX + DYING_MAX) * STRIDE)
	for a in [_d_pos]:
		a.resize(DYING_MAX)
	_d_face.resize(DYING_MAX)
	for a in [_d_scale, _d_t, _d_code]:
		a.resize(DYING_MAX)
	_d_kind.resize(DYING_MAX)
	for a in [_c_pos, _c_vel]:
		a.resize(CLODS_MAX)
	_c_age.resize(CLODS_MAX)
	var cm := MeshBuilder.new()
	cm.add(MeshBuilder.sphere(0.07, 6, 4), Transform3D(Basis.from_scale(Vector3(1.2, 0.8, 1.0)), Vector3.ZERO), Color(0.17, 0.12, 0.08, 0.0))
	_clods_mm = MultiMesh.new()
	_clods_mm.transform_format = MultiMesh.TRANSFORM_3D
	_clods_mm.mesh = cm.commit()
	_clods_mm.instance_count = CLODS_MAX
	_clods_mm.visible_instance_count = 0
	var ci := MultiMeshInstance3D.new()
	ci.multimesh = _clods_mm
	ci.top_level = true
	ci.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(ci)
	for k in ["wail", "snarl", "grave_crumble", "ghost_death", "ghoul_death"]:
		var path := "res://audio/graveyard/%s.wav" % k
		_sfx[k] = load(path) if ResourceLoader.exists(path) else null
	for k in 4:
		var a := AudioStreamPlayer3D.new()
		a.bus = Settings.SFX_BUS
		a.unit_size = 9.0
		a.max_distance = 45.0
		a.max_polyphony = 2
		add_child(a)
		_voices.append(a)


func _crowd_mm(mesh: Mesh, shadows: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = EnemyManager.MAX + DYING_MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


# ------------------------------------------------------------------ models

## The ghoul (facing +Z, feet at the origin, about GHOUL_HEIGHT tall, hunched). Vertex alpha = part / 8.
static func build_ghoul(mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var skin := Color(0.44, 0.48, 0.39)
	var dark := Color(0.29, 0.32, 0.26)
	var rag := Color(0.17, 0.13, 0.1)
	var claw := Color(0.06, 0.05, 0.05)
	var c := func(col: Color, part: int) -> Color: return Color(col.r, col.g, col.b, part / 8.0)
	# legs: bent at the knee (always half crouched), long splayed feet with claws
	for sd in [1.0, -1.0]:
		var part := 1 if sd > 0.0 else 2
		var hip := Vector3(sd * 0.12, 0.72, 0.0)
		var knee := Vector3(sd * 0.15, 0.42, 0.16)
		var ankle := Vector3(sd * 0.14, 0.08, -0.04)
		mb.limb(hip, knee, 0.075, 0.05, c.call(skin, part), 7)
		mb.add(MeshBuilder.sphere(0.055, 6, 4), Transform3D(Basis(), knee), c.call(dark, part))
		mb.limb(knee, ankle, 0.045, 0.035, c.call(skin, part), 6)
		mb.add(MeshBuilder.box(Vector3(0.1, 0.05, 0.24)), Transform3D(Basis(), Vector3(sd * 0.14, 0.03, 0.06)), c.call(dark, part))
		for k in 3:
			mb.add(MeshBuilder.cone(0.012, 0.07, 4), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(sd * 0.14 + (k - 1) * 0.03, 0.02, 0.2)), c.call(claw, part))
	# pelvis, rags round the hips
	mb.add(MeshBuilder.sphere(0.15, 8, 5), Transform3D(Basis.from_scale(Vector3(1.25, 0.6, 0.9)), Vector3(0, 0.74, 0)), c.call(dark, 0))
	for k in 6:
		var a := TAU * k / 6.0
		mb.add(MeshBuilder.box(Vector3(0.1, 0.24, 0.015)), Transform3D(Basis(Vector3.UP, -a), Vector3(sin(a) * 0.17, 0.62, cos(a) * 0.12)), c.call(rag, 7))
	# a long curved back leaning far forward: spine knobs, ribs, sunken belly, shoulder blades
	var spine: Array[Vector3] = [Vector3(0, 0.76, -0.02), Vector3(0, 0.92, 0.06), Vector3(0, 1.05, 0.18), Vector3(0, 1.13, 0.32)]
	for k in 3:
		mb.limb(spine[k], spine[k + 1], 0.15 - k * 0.01, 0.16 - k * 0.01, c.call(skin, 0), 9)
	for k in 7:
		var p: Vector3 = spine[0].lerp(spine[3], float(k) / 6.0)
		mb.add(MeshBuilder.sphere(0.03, 6, 4), Transform3D(Basis(), p + Vector3(0, 0.15, -0.05)), c.call(dark, 0))
	for k in 4:
		var p: Vector3 = spine[1].lerp(spine[3], float(k) / 3.0)
		mb.add(MeshBuilder.cyl(0.16, 0.16, 0.022, 12), Transform3D(Basis(Vector3(1, 0, 0), 0.9).scaled(Vector3(1.0, 1.0, 0.75)), p + Vector3(0, -0.02, 0.02)), c.call(skin.lightened(0.08), 0))
	for sd in [1.0, -1.0]:
		mb.add(MeshBuilder.sphere(0.07, 6, 4), Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.2)), Vector3(sd * 0.1, 1.22, 0.24)), c.call(dark, 0))
	mb.add(MeshBuilder.box(Vector3(0.3, 0.12, 0.08)), Transform3D(Basis(Vector3(1, 0, 0), 0.6), Vector3(0, 1.17, 0.22)), c.call(rag, 7))
	# arms: long, hanging forward to the knees, big hands with long black claws
	for sd in [1.0, -1.0]:
		var part := 3 if sd > 0.0 else 4
		var sh := Vector3(sd * 0.22, 1.12, 0.32)
		var elbow := Vector3(sd * 0.27, 0.82, 0.42)
		var wrist := Vector3(sd * 0.24, 0.5, 0.5)
		mb.add(MeshBuilder.sphere(0.065, 6, 4), Transform3D(Basis(), sh), c.call(skin, part))
		mb.limb(sh, elbow, 0.055, 0.04, c.call(skin, part), 6)
		mb.add(MeshBuilder.sphere(0.045, 6, 4), Transform3D(Basis(), elbow), c.call(dark, part))
		mb.limb(elbow, wrist, 0.04, 0.03, c.call(skin, part), 6)
		mb.add(MeshBuilder.sphere(0.055, 6, 4), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.3)), wrist + Vector3(0, -0.03, 0.03)), c.call(skin, part))
		for f in 4:
			var tip := wrist + Vector3(sd * (f - 1.5) * 0.03, -0.17, 0.1 + absf(f - 1.5) * -0.02)
			mb.limb(wrist + Vector3(sd * (f - 1.5) * 0.025, -0.04, 0.06), tip, 0.012, 0.004, c.call(claw, part), 4)
	# head thrust forward and low: long skull, pointed ears, a gaping mouth of teeth, glowing eyes
	var hd := Vector3(0, 1.2, 0.52)
	mb.limb(Vector3(0, 1.15, 0.36), hd + Vector3(0, -0.02, -0.06), 0.06, 0.05, c.call(skin, 5), 6)
	mb.add(MeshBuilder.sphere(0.12, 10, 7), Transform3D(Basis.from_scale(Vector3(0.9, 0.85, 1.25)), hd), c.call(skin, 5))
	mb.add(MeshBuilder.sphere(0.08, 8, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.2)), hd + Vector3(0, -0.08, 0.08)), c.call(dark, 5))   # jaw
	mb.add(MeshBuilder.box(Vector3(0.12, 0.035, 0.08)), Transform3D(Basis(), hd + Vector3(0, -0.06, 0.12)), Color(0.08, 0.02, 0.02, 5 / 8.0))   # the gape
	for k in 6:
		var x := -0.05 + k * 0.02
		mb.add(MeshBuilder.cone(0.008, 0.03, 4), Transform3D(Basis(Vector3(1, 0, 0), PI), hd + Vector3(x, -0.04, 0.155)), Color(0.85, 0.82, 0.68, 5 / 8.0))
		mb.add(MeshBuilder.cone(0.008, 0.03, 4), Transform3D(Basis(), hd + Vector3(x, -0.08, 0.15)), Color(0.85, 0.82, 0.68, 5 / 8.0))
	for sd in [1.0, -1.0]:
		mb.add(MeshBuilder.cone(0.04, 0.14, 4), Transform3D(Basis(Vector3(0, 0, 1), -sd * 1.1) * Basis(Vector3(1, 0, 0), -0.4), hd + Vector3(sd * 0.11, 0.06, -0.04)), c.call(skin, 5))
		mb.add(MeshBuilder.sphere(0.024, 6, 4), Transform3D(Basis(), hd + Vector3(sd * 0.045, 0.03, 0.135)), Color(1.0, 1.0, 0.4, 6 / 8.0))
	mb.add(MeshBuilder.box(Vector3(0.14, 0.02, 0.05)), Transform3D(Basis(Vector3(1, 0, 0), 0.2), hd + Vector3(0, 0.07, 0.11)), c.call(dark, 5))   # brow
	return mb.commit(mat)


## The ghost (facing +Z, origin at the hem: drawn GHOST_FLOAT above the ground). Vertex alpha = part / 8.
static func build_ghost(mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var shroud := Color(0.72, 0.86, 0.9)
	var pale := Color(0.86, 0.92, 0.94)
	var hollow := Color(0.08, 0.14, 0.17)
	var c := func(col: Color, part: int) -> Color: return Color(col.r, col.g, col.b, part / 8.0)
	# the shroud: one smooth surface from the shoulders, swelling at the chest, narrowing into a
	# long streaming tail, its hem rippled
	var prof := [[1.48, 0.2], [1.36, 0.29], [1.15, 0.33], [0.9, 0.32], [0.65, 0.27], [0.42, 0.2], [0.22, 0.12], [0.06, 0.05], [-0.12, 0.012]]
	mb.add(_lathe(prof, 14, 0.04), Transform3D(), c.call(shroud, 0))
	mb.add(MeshBuilder.sphere(0.24, 10, 6), Transform3D(Basis.from_scale(Vector3(1.35, 0.5, 1.0)), Vector3(0, 1.45, 0)), c.call(shroud, 0))   # shoulders
	# ragged tatters trailing from the waist down, longer at the back
	for k in 12:
		var a := TAU * k / 12.0
		var back := 0.5 - 0.5 * cos(a)
		var l := 0.35 + 0.3 * fmod(k * 0.618, 1.0) + back * 0.25
		var top := Vector3(sin(a) * 0.3, 0.75, cos(a) * 0.3)
		var bot := Vector3(sin(a) * 0.36, 0.75 - l, cos(a) * 0.36 - back * 0.15)
		mb.add(MeshBuilder.box(Vector3(0.08, l, 0.012)), Transform3D(Basis.looking_at(Vector3(sin(a), 0, cos(a)), Vector3.UP) * Basis(Vector3(1, 0, 0), 0.12), (top + bot) * 0.5), c.call(shroud.darkened(0.06), 5))
	# a drape of the hood over the back
	mb.add(MeshBuilder.sphere(0.22, 10, 6), Transform3D(Basis.from_scale(Vector3(1.0, 1.4, 0.6)), Vector3(0, 1.45, -0.14)), c.call(shroud, 3))
	# the hood, deep, round a skull-like face with hollow eyes that glow
	var hd := Vector3(0, 1.66, 0.02)
	mb.add(MeshBuilder.sphere(0.21, 12, 8), Transform3D(Basis.from_scale(Vector3(1.0, 1.15, 1.05)), hd), c.call(shroud, 3))
	mb.add(MeshBuilder.sphere(0.15, 10, 7), Transform3D(Basis.from_scale(Vector3(0.9, 1.1, 0.6)), hd + Vector3(0, -0.02, 0.12)), c.call(hollow, 3))
	mb.add(MeshBuilder.sphere(0.11, 10, 7), Transform3D(Basis.from_scale(Vector3(0.85, 1.05, 0.7)), hd + Vector3(0, -0.03, 0.15)), c.call(pale, 3))
	mb.add(MeshBuilder.sphere(0.05, 8, 5), Transform3D(Basis.from_scale(Vector3(0.8, 1.4, 0.5)), hd + Vector3(0, -0.1, 0.22)), c.call(hollow, 3))   # the wailing mouth
	for sd in [1.0, -1.0]:
		mb.add(MeshBuilder.sphere(0.035, 6, 4), Transform3D(Basis(), hd + Vector3(sd * 0.045, 0.01, 0.23)), c.call(hollow, 3))
		mb.add(MeshBuilder.sphere(0.018, 6, 4), Transform3D(Basis(), hd + Vector3(sd * 0.045, 0.01, 0.25)), Color(0.6, 1.0, 1.0, 4 / 8.0))
	# arms: wide tattered sleeves reaching out, bony fingers
	for sd in [1.0, -1.0]:
		var part := 1 if sd > 0.0 else 2
		var sh := Vector3(sd * 0.2, 1.42, 0.05)
		var el := Vector3(sd * 0.3, 1.2, 0.3)
		var wr := Vector3(sd * 0.28, 1.1, 0.58)
		mb.limb(sh, el, 0.08, 0.1, c.call(shroud, part), 8)
		mb.limb(el, wr, 0.1, 0.13, c.call(shroud, part), 8)
		for k in 3:
			mb.add(MeshBuilder.box(Vector3(0.05, 0.22, 0.01)), Transform3D(Basis(Vector3(1, 0, 0), -0.6) * Basis(Vector3.UP, sd * (k - 1) * 0.6), wr + Vector3(sd * (k - 1) * 0.06, -0.12, -0.02)), c.call(shroud.darkened(0.08), part))
		for f in 4:
			mb.limb(wr + Vector3(sd * (f - 1.5) * 0.025, 0, 0.04), wr + Vector3(sd * (f - 1.5) * 0.045, -0.06, 0.2), 0.01, 0.005, c.call(pale, part), 4)
	return mb.commit(mat)


## A surface of revolution round Y: `prof` = [[y, radius], ...] from top to bottom, `seg` sides,
## the radius rippled by `ripple` (so a hem isn't a perfect circle).
static func _lathe(prof: Array, seg: int, ripple: float) -> Array:
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var idx := PackedInt32Array()
	var rows := prof.size()
	for r in rows:
		var y: float = prof[r][0]
		var rad: float = prof[r][1]
		var y0: float = prof[maxi(r - 1, 0)][0]
		var y1: float = prof[mini(r + 1, rows - 1)][0]
		var r0: float = prof[maxi(r - 1, 0)][1]
		var r1: float = prof[mini(r + 1, rows - 1)][1]
		var slope := (r1 - r0) / minf(y1 - y0, -0.001)
		for k in seg + 1:
			var a := TAU * k / seg
			var rr := rad * (1.0 + ripple * sin(a * 3.0 + r * 1.7) * float(r) / rows)
			v.append(Vector3(sin(a) * rr, y, cos(a) * rr))
			nm.append(Vector3(sin(a), slope, cos(a)).normalized())
	for r in rows - 1:
		for k in seg:
			var i0 := r * (seg + 1) + k
			var i1 := i0 + 1
			var i2 := i0 + seg + 1
			var i3 := i2 + 1
			for t in [[i0, i2, i1], [i1, i2, i3]]:
				var out := (v[t[0]] + v[t[1]] + v[t[2]]) / 3.0
				out.y = 0.0
				if (v[t[1]] - v[t[0]]).cross(v[t[2]] - v[t[0]]).dot(out) < 0.0:
					idx.append(t[0]); idx.append(t[1]); idx.append(t[2])
				else:
					idx.append(t[0]); idx.append(t[2]); idx.append(t[1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


# ------------------------------------------------------------------ per frame

## Called by EnemyManager at the end of its tick (after the skeletons): moves the ghoul and
## ghost rows out of the goblin buffer into theirs, sinks the ones still rising, chills the
## player at a ghost's touch, draws the dying. `buf` is the goblin instance buffer.
func sync(dt: float, buf: PackedFloat32Array, player: Node3D) -> PackedFloat32Array:
	var ng := 0
	var nh := 0
	var pp := player.global_position if player != null else Vector3.INF
	_chill_cd -= dt
	var near_ghost := -1
	var near_ghoul := -1
	var ngd := 625.0
	var nld := 625.0
	for i in em.count:
		var t := em.typ[i]
		if t != EnemyManager.GHOUL and t != EnemyManager.GHOST:
			continue
		var b := i * STRIDE
		if em.frog_t[i] > 0.0:   # polymorphed: RosterKit draws the frog
			continue
		var anim := ANIM_ATTACK if absf(buf[b + 12] - em._clip_attack) < 0.01 else ANIM_WALK
		var phase := buf[b + 13]
		var up := 1.0
		var ghost := t == EnemyManager.GHOST
		if em.rise_t[i] > 0.0:
			var f := clampf(em.rise_t[i] / RISE_TIME, 0.0, 1.0)
			buf[b + 7] -= (GHOUL_HEIGHT if not ghost else 1.0) * 1.05 * f
			anim = ANIM_ATTACK
			up = 1.0 - f
		if ghost:
			buf[b + 7] += GHOST_FLOAT
		var o: int
		if ghost:
			o = nh * STRIDE
			nh += 1
		else:
			o = ng * STRIDE
			ng += 1
		var code := buf[b + 19]
		if ghost:
			for k in 12:
				_buf_h[o + k] = buf[b + k]
				buf[b + k] = 0.0
			_buf_h[o + 12] = 1.0; _buf_h[o + 13] = 1.0; _buf_h[o + 14] = 1.0; _buf_h[o + 15] = 1.0
			_buf_h[o + 16] = anim; _buf_h[o + 17] = phase; _buf_h[o + 18] = up; _buf_h[o + 19] = code
		else:
			for k in 12:
				_buf_g[o + k] = buf[b + k]
				buf[b + k] = 0.0
			_buf_g[o + 12] = 1.0; _buf_g[o + 13] = 1.0; _buf_g[o + 14] = 1.0; _buf_g[o + 15] = 1.0
			_buf_g[o + 16] = anim; _buf_g[o + 17] = phase; _buf_g[o + 18] = up; _buf_g[o + 19] = code
		if pp != Vector3.INF and not em.dead[i]:
			var dx := em.pos[i].x - pp.x
			var dz := em.pos[i].z - pp.z
			var d2 := dx * dx + dz * dz
			if ghost:
				if d2 < ngd:
					ngd = d2
					near_ghost = i
				# a ghost's touch chills you to the bone
				var reach := em.t_radius[t] * em.sz[i] + 0.55
				if d2 < reach * reach and not em.is_harmless(i) and absf(pp.y - em.pos[i].y) < 2.5 and player.has_method("apply_slow"):
					player.apply_slow(CHILL_SLOW, CHILL_SECS)
					chills += 1
					if _chill_cd <= 0.0 and player is Node3D:   # a puff of frost (not every frame)
						_chill_cd = 0.5
						var fx := _fx()
						if fx:
							fx.burst((player as Node3D).global_position + Vector3(0, 1.0, 0), 0.7, Color(0.6, 0.9, 1.0), 0.3)
			elif d2 < nld:
				nld = d2
				near_ghoul = i
	ghosts_drawn = nh
	ghouls_drawn = ng
	# the dying, after the living
	var i := 0
	while i < _d_n:
		_d_t[i] += dt
		var ghost := _d_kind[i] == EnemyManager.GHOST
		var life := DIE_GHOST if ghost else DIE_GHOUL
		if _d_t[i] >= life:
			var last := _d_n - 1
			_d_pos[i] = _d_pos[last]; _d_face[i] = _d_face[last]; _d_scale[i] = _d_scale[last]
			_d_t[i] = _d_t[last]; _d_kind[i] = _d_kind[last]; _d_code[i] = _d_code[last]
			_d_n -= 1
			continue
		var p := _d_pos[i]
		var f := _d_face[i]
		var s := _d_scale[i]
		var o := (nh if ghost else ng) * STRIDE
		var row := PackedFloat32Array([f.y * s, 0.0, f.x * s, p.x, 0.0, s, 0.0, p.y + (GHOST_FLOAT if ghost else 0.0),
			-f.x * s, 0.0, f.y * s, p.z, 1.0, 1.0, 1.0, 1.0, ANIM_DIE, _d_t[i] / life, 1.0, _d_code[i]])
		if ghost:
			nh += 1
			for k in STRIDE:
				_buf_h[o + k] = row[k]
		else:
			ng += 1
			for k in STRIDE:
				_buf_g[o + k] = row[k]
		i += 1
	_mm_ghoul.buffer = _buf_g
	_mm_ghoul.visible_instance_count = ng
	_mm_ghost.buffer = _buf_h
	_mm_ghost.visible_instance_count = nh
	_tick_clods(dt)
	# now and then the nearest ghost wails, the nearest ghoul snarls
	_voice_t -= dt
	if _voice_t <= 0.0:
		_voice_t = randf_range(2.5, 5.5)
		if near_ghost >= 0 and (near_ghoul < 0 or randf() < 0.5):
			_say("wail", em.pos[near_ghost] + Vector3(0, 1.8, 0), randf_range(0.85, 1.15))
		elif near_ghoul >= 0:
			_say("snarl", em.pos[near_ghoul] + Vector3(0, 1.0, 0), randf_range(0.85, 1.2))
	return buf


func _say(k: String, at: Vector3, pitch := 1.0) -> void:
	var s: AudioStream = _sfx.get(k)
	if s == null:
		return
	for a in _voices:
		if not a.playing:
			a.stream = s
			a.pitch_scale = pitch
			a.global_position = at
			a.play()
			return


## A ghoul or ghost row has died: it plays its death here (EnemyManager._kill calls this).
func on_killed(i: int) -> void:
	deaths += 1
	var k := _d_n
	if _d_n < DYING_MAX:
		_d_n += 1
	else:
		k = randi() % DYING_MAX
	var v := em.heading(i)
	var f := Vector2(v.x, v.z)
	if f.length_squared() < 0.0001:
		f = Vector2(randf() - 0.5, randf() - 0.5)
	f = f.normalized()
	_d_pos[k] = em.pos[i]
	_d_face[k] = f
	_d_scale[k] = em.t_scale[em.typ[i]] * em.sz[i]
	_d_t[k] = 0.0
	_d_kind[k] = em.typ[i]
	_d_code[k] = 4.0 if em.epic[i] else 0.0
	var fx := _fx()
	if em.typ[i] == EnemyManager.GHOST:
		if fx:
			fx.burst(em.pos[i] + Vector3(0, GHOST_FLOAT + 1.1, 0), 1.3, Color(0.55, 0.95, 1.0), 0.5)
		if randf() < 0.5:
			_say("ghost_death", em.pos[i] + Vector3(0, 2.0, 0), randf_range(0.9, 1.2))
	else:
		if fx:
			fx.burst(em.pos[i] + Vector3(0, 0.6, 0), 1.1, Color(0.18, 0.24, 0.08), 0.4)
		if randf() < 0.35:
			_say("ghoul_death", em.pos[i] + Vector3(0, 0.8, 0), randf_range(0.85, 1.15))


func dying_count() -> int:
	return _d_n


# ------------------------------------------------------------------ rising from the grave

## Raise one of the dead (GHOUL, GHOST or SKELETON) at `at`: it starts sunk in the ground and
## claws its way out for RISE_TIME (+ `delay`), harmless, amid clods of earth. Returns its row.
func raise(type: int, at: Vector3, hp_mult: float, delay := 0.0, is_epic := false) -> int:
	var i := em.spawn(type, at, hp_mult, is_epic)
	if i < 0:
		return -1
	em.rise_t[i] = RISE_TIME + delay
	em.throw_t[i] = RISE_TIME + delay + randf_range(1.5, 4.0)
	risen += 1
	var p := em.pos[i]
	for k in 7:
		_clod(p + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3)), Vector3(randf_range(-1.6, 1.6), randf_range(2.5, 5.0), randf_range(-1.6, 1.6)))
	var fx := _fx()
	if fx:
		fx.burst(p + Vector3(0, 0.25, 0), 1.0, Color(0.3, 0.24, 0.17) if type != EnemyManager.GHOST else Color(0.5, 0.9, 1.0), 0.4)
	if risen % 3 == 1:
		_say("grave_crumble", p, randf_range(0.85, 1.15))
	return i


func _clod(at: Vector3, vel: Vector3) -> void:
	var k := _c_n
	if _c_n < CLODS_MAX:
		_c_n += 1
	else:
		k = randi() % CLODS_MAX
	_c_pos[k] = at
	_c_vel[k] = vel
	_c_age[k] = 0.0


func _tick_clods(dt: float) -> void:
	var buf := PackedFloat32Array()
	buf.resize(CLODS_MAX * 12)
	var i := 0
	while i < _c_n:
		_c_age[i] += dt
		if _c_age[i] > 2.0:
			var last := _c_n - 1
			_c_pos[i] = _c_pos[last]
			_c_vel[i] = _c_vel[last]
			_c_age[i] = _c_age[last]
			_c_n -= 1
			continue
		var v := _c_vel[i]
		v.y -= 14.0 * dt
		var p := _c_pos[i] + v * dt
		var g := SwampWater.height_at(p.x, p.z) + 0.04
		if p.y < g:
			p.y = g
			v = Vector3(v.x * 0.3, 0.0, v.z * 0.3)
		_c_pos[i] = p
		_c_vel[i] = v
		var s := clampf((2.0 - _c_age[i]) / 0.5, 0.0, 1.0)
		var b := i * 12
		buf[b] = s; buf[b + 3] = p.x
		buf[b + 5] = s; buf[b + 7] = p.y
		buf[b + 10] = s; buf[b + 11] = p.z
		i += 1
	_clods_mm.buffer = buf
	_clods_mm.visible_instance_count = _c_n


## The graveyard's swarm: `n` of the dead climb out of graves round the player (12-30 m away),
## skeletons mostly, with ghouls and ghosts among them; where there aren't graves enough, out of
## the bare ground in a ring. Returns how many rose.
func grave_swarm(player_pos: Vector3, n: int, hp_mult: float, rng: RandomNumberGenerator, epic_chance := 0.0) -> int:
	var spots: Array[Vector3] = []
	var graves := GraveyardBuilder.graves
	if not graves.is_empty():
		var cand: Array[Vector3] = []
		for g in graves:
			var d := Vector2(g.x - player_pos.x, g.z - player_pos.z).length()
			if d > 12.0 and d < 30.0:
				cand.append(g)
		for k in range(cand.size() - 1, 0, -1):
			var j := rng.randi() % (k + 1)
			var tmp := cand[k]
			cand[k] = cand[j]
			cand[j] = tmp
		for k in mini(n, cand.size()):
			spots.append(cand[k])
	var missing := n - spots.size()
	for k in missing:
		var a := TAU * float(k) / float(maxi(missing, 1)) + rng.randf_range(-0.1, 0.1)
		spots.append(player_pos + Vector3(cos(a), 0, sin(a)) * rng.randf_range(16.0, 24.0))
	var rose := 0
	for k in spots.size():
		var r := rng.randf()
		var t := EnemyManager.SKELETON if r < 0.6 else (EnemyManager.GHOUL if r < 0.85 else EnemyManager.GHOST)
		if raise(t, spots[k], hp_mult, rng.randf_range(0.0, 1.4), rng.randf() < epic_chance) >= 0:
			rose += 1
	return rose


func _fx() -> FxManager:
	var main := get_tree().current_scene if is_inside_tree() else null
	if main != null and "fx" in main and main.fx is FxManager:
		return main.fx
	return null
