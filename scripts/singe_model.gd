class_name SingeModel
extends Node3D
## Singe, the Living Cinder, swollen into a giant (the Ashen Caldera's boss), built in code:
## about 6 m from his clawed toes to the crown of his head, with his flame hair roaring above.
##   - BODY: a pot-bellied heap of cracked black coals (SHADER: glossy anthracite facets split by
##     glowing orange seams that pulse), lumps of hotter coal stuck all over him.
##   - HEAD: big and round, long pointed ears, heavy brows over glowing yellow eyes with slit
##     pupils, a snub nose and a WIDE IMPISH GRIN full of jagged, charred teeth; a hinged jaw that
##     cackles. A crown of roaring flame hair (FLAME_SHADER cones licking upward + fire particles).
##   - Spindly arms with long three-clawed hands, spindly backward-kneed legs, a long pointy tail
##     with a spade tip that never stops swishing. Embers stream off him; his belly lights the ground.
## The Magma Imps are his minions: they're a sixth his size, rocky, dark and horned; he has no
## horns, a flaming crown and a glowing grin, so he's never mistaken for one.
##
## The boss drives him with `pose` ("walk", "rise", "swipe", "breath", "dive", "juggle", "summon",
## "raise", "scamper", "cackle", "die") and `act` (0..1 through the move); `rise` lifts him out of
## the lava, `sink` lowers him into it (the lava dive), `curl` tucks him into a cannonball, `heat`
## (enrage) and `cool` (death) tint him; on death he fizzles down into a little heap of coals.

const HIP_Y := 2.0
const COAL := Color(0.09, 0.05, 0.045)
const COAL_HI := Color(0.16, 0.08, 0.06)
const EMBER := Color(1.0, 0.45, 0.1)
const EYE := Color(1.0, 0.88, 0.29)
const MOUTH := Color(1.0, 0.62, 0.15)
const CLAW := Color(0.05, 0.04, 0.05)
const TOOTH := Color(0.62, 0.55, 0.42)
const ROCK := 0.0
const HOT := 0.12
const GLOW := 0.28
const GLASS := 0.5
const BONE := 0.8

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float heat = 0.0;
uniform float cool = 0.0;
uniform float flash = 0.0;
varying vec3 lpos;
vec3 h3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}
// distance to the nearest cell border: the seams between the coals
float seam(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	float d1 = 8.0; float d2 = 8.0;
	for (int x = -1; x <= 1; x++) for (int y = -1; y <= 1; y++) for (int z = -1; z <= 1; z++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = g + h3(i + g) - f;
		float d = dot(o, o);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return sqrt(d2) - sqrt(d1);
}
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { lpos = VERTEX; }
void fragment() {
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float tag = COLOR.a;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float pulse = 0.72 + 0.28 * sin(TIME * 3.1 + lpos.y * 2.0 + lpos.x * 1.3);
	vec3 em = vec3(0.0);
	float rough = 0.4;
	float spec = 0.6;
	if (tag < 0.2) {   // coal: glossy black facets, glowing seams between them
		float e = seam(lpos * 2.3);
		float e2 = abs(vnoise(lpos * 5.0 + vec3(4.0)) - 0.5);   // finer hairline cracks (cheap)
		float w = 0.05 + tag * 0.5 + heat * 0.05;
		float s = 1.0 - smoothstep(0.0, w, e);
		float s2 = (1.0 - smoothstep(0.0, 0.025, e2)) * 0.4;
		col *= 0.75 + 0.6 * hash(floor(lpos * 2.3));
		vec3 hot = mix(vec3(1.0, 0.28, 0.04), vec3(1.0, 0.72, 0.22), s * pulse);
		em = hot * max(s, s2) * (1.4 + tag * 6.0 + heat * 2.2) * pulse;
		em += vec3(1.0, 0.3, 0.05) * rim * (0.08 + heat * 0.5);
		col *= 1.0 - s * 0.8;
		rough = 0.32 + 0.3 * hash(floor(lpos * 2.3) + 1.0);
	} else if (tag < 0.4) {   // eyes, the furnace in his mouth
		em = col * (3.2 + heat * 2.0) * (0.85 + 0.15 * pulse);
		col *= 0.25;
		rough = 0.5;
	} else if (tag < 0.62) {   // claws: black glass
		col = vec3(0.01) + col * 0.15;
		em = vec3(1.0, 0.35, 0.08) * rim * (0.15 + heat * 0.5);
		rough = 0.1;
		spec = 0.9;
	} else {   // charred teeth
		col *= 0.8 + 0.3 * hash(floor(lpos * 9.0));
		rough = 0.6;
	}
	col = mix(col, vec3(0.3, 0.29, 0.28) * (0.8 + 0.4 * hash(floor(lpos * 4.0))), cool * 0.85);
	em *= 1.0 - cool * 0.96;
	ALBEDO = mix(col, vec3(1.0, 0.7, 0.5), flash * 0.45);
	EMISSION = em + vec3(1.0, 0.55, 0.3) * flash * 0.9;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
"""

const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float power = 1.0;
varying float h;
void vertex() {
	h = clamp(VERTEX.y / 1.9, 0.0, 1.0);
	float w = sin(TIME * 9.0 + VERTEX.y * 3.0 + VERTEX.x * 5.0) * 0.16 * h + sin(TIME * 13.0 + VERTEX.z * 4.0) * 0.08 * h;
	VERTEX.x += w;
	VERTEX.z += w * 0.7;
	VERTEX.y *= (0.82 + 0.18 * sin(TIME * 11.0 + VERTEX.x * 7.0 + VERTEX.z * 3.0)) * (0.6 + 0.4 * power);
}
void fragment() {
	vec3 c = mix(vec3(1.0, 0.95, 0.62), vec3(1.0, 0.48, 0.06), smoothstep(0.0, 0.45, h));
	c = mix(c, vec3(0.85, 0.12, 0.02), smoothstep(0.45, 1.0, h));
	float a = (1.0 - smoothstep(0.5, 1.0, h)) * power;
	float face = abs(dot(NORMAL, VIEW));
	ALBEDO = c * (0.7 + power * 0.35) * a * (0.3 + 0.7 * face);
}
"""

var pose := "walk"
var act := 0.0
var rise := 1.0
var sink := 0.0
var curl := 0.0
var lift := 0.0                     # raised off the ground (his leap into the lava)
var die_t := 0.0
var walk_speed := 0.0
var preview := false
var mouth: Node3D                   # where the breath leaves
var head: Node3D
var hands: Array[Node3D] = []       # [left, right]; the right one swipes
var _root: Node3D
var _torso: Node3D
var _jaw: Node3D
var _hair: Node3D
var _hair_mi: MeshInstance3D
var _hair_fx: CPUParticles3D
var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _ankles: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _tail: Array[Node3D] = []
var _balls: Array[MeshInstance3D] = []   # the lava bombs he juggles
var _pile: Node3D
var _mat: ShaderMaterial
var _fmat: ShaderMaterial
var _light: OmniLight3D
var _embers: Array[CPUParticles3D] = []
var _flash := 0.0
var _heat := 0.0
var _cool := 0.0
var _t := 0.0
var _phase := 0.0
var _act_s := 0.0                   # act, smoothed
var _mix := {}                      # pose blend weights


func _ready() -> void:
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_fmat = ShaderMaterial.new()
	var fsh := Shader.new()
	fsh.code = FLAME_SHADER
	_fmat.shader = fsh
	_fmat.set_shader_parameter("power", 1.0)
	_root = Node3D.new()
	add_child(_root)
	var pelvis := Node3D.new()
	pelvis.position = Vector3(0, HIP_Y, 0)
	_root.add_child(pelvis)
	for sd in [-1.0, 1.0]:
		_build_leg(pelvis, sd)
	_torso = Node3D.new()
	pelvis.add_child(_torso)
	_mesh(_torso, _torso_mesh())
	for sd in [-1.0, 1.0]:
		_build_arm(_torso, sd)
	head = Node3D.new()
	head.position = Vector3(0, 2.35, -0.05)
	_torso.add_child(head)
	_mesh(head, _head_mesh())
	_jaw = Node3D.new()
	_jaw.position = Vector3(0, 0.22, -0.35)
	head.add_child(_jaw)
	_mesh(_jaw, _jaw_mesh())
	mouth = Node3D.new()
	mouth.position = Vector3(0, 0.05, -0.75)
	_jaw.add_child(mouth)
	_hair = Node3D.new()
	_hair.position = Vector3(0, 1.0, 0.1)
	head.add_child(_hair)
	_hair_mi = MeshInstance3D.new()
	_hair_mi.mesh = _hair_mesh()
	_hair_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hair.add_child(_hair_mi)
	_hair_fx = Abilities._flame_particles(1.5, 0.75, 70)
	_hair_fx.emission_sphere_radius = 0.75
	_hair_fx.position = Vector3(0, 0.35, 0)
	_hair_fx.initial_velocity_min = 2.0
	_hair_fx.initial_velocity_max = 4.0
	_hair.add_child(_hair_fx)
	_build_tail(pelvis)
	for k in 3:   # the lava bombs he juggles (only shown while he does)
		var b := MeshInstance3D.new()
		var mb := MeshBuilder.new()
		mb.add(ForestProps._lumpy(0.42, RandomNumberGenerator.new()), Transform3D(), _c(EMBER, GLOW))
		b.mesh = mb.commit(_mat)
		b.visible = false
		_root.add_child(b)
		_balls.append(b)
	_pile = Node3D.new()
	_mesh(_pile, _pile_mesh())
	_pile.visible = false
	add_child(_pile)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.18)
	_light.light_energy = 3.0
	_light.omni_range = 16.0
	_light.position = Vector3(0, 3.0, -1.6)
	_root.add_child(_light)
	var e1 := CalderaProps.embers(Vector3(0, 1.0, 0), 1.1, 34)
	_torso.add_child(e1)
	var e2 := CalderaProps.embers(Vector3(0, 0.6, 0), 0.6, 26)
	e2.initial_velocity_max = 6.0
	_hair.add_child(e2)
	_embers = [e1, e2]
	_animate(0.0)


func _mesh(parent: Node3D, m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	parent.add_child(mi)
	return mi


func flash() -> void:
	_flash = 0.15


func set_enrage(k: float) -> void:
	_heat = k


func set_cool(k: float) -> void:
	_cool = k


## tools/render_caldera: hold a pose for the contact sheet.
func pose_preview(p: String) -> void:
	preview = true
	pose = p
	act = 0.8 if p != "swipe" else 0.5
	curl = 1.0 if p == "dive" else 0.0
	die_t = 6.0 if p == "die" else 0.0
	_act_s = act
	_mix.clear()
	_t = 1.3
	_phase = 0.35
	_animate(0.0)


func _process(dt: float) -> void:
	_t += dt
	_flash = maxf(0.0, _flash - dt)
	_animate(dt)
	_mat.set_shader_parameter("flash", _flash / 0.15)
	_mat.set_shader_parameter("heat", _heat)
	_mat.set_shader_parameter("cool", _cool)
	var fire := (1.0 + _heat * 0.6) * (1.0 - clampf(die_t / 2.2, 0.0, 1.0) if pose == "die" else 1.0)
	_fmat.set_shader_parameter("power", fire)
	_hair_fx.emitting = fire > 0.2
	_light.light_energy = (3.0 + _heat * 2.0) * (1.0 - _cool)
	for e in _embers:
		e.emitting = _cool < 0.5 and pose != "die"


# ------------------------------------------------------------------ posing

## Blend weight of a pose, eased in and out so he never snaps.
func _w(p: String, dt: float) -> float:
	var target := 1.0 if pose == p else 0.0
	var cur: float = _mix.get(p, target if preview or dt == 0.0 else 0.0)
	cur = move_toward(cur, target, dt * 6.0) if dt > 0.0 else target
	_mix[p] = cur
	return cur


func _animate(dt: float) -> void:
	_act_s = lerpf(_act_s, act, clampf(dt * 14.0, 0.0, 1.0)) if dt > 0.0 else act
	var a := _act_s
	var spd := walk_speed if pose == "walk" else (9.0 if pose == "scamper" else 0.0)
	_phase += dt * (1.6 + spd * 0.55)
	var ph := _phase * TAU
	var t := _t
	# rest values
	var root_y := 0.0
	var root_rx := 0.0
	var root_rz := 0.0
	var squash := 1.0
	var lean := 0.0          # torso, + leans back
	var twist := 0.0
	var roll := 0.0
	var head_x := 0.0
	var head_z := 0.0
	var jaw := 0.08
	var sh := [Vector2(0.15, -0.35), Vector2(0.15, 0.35)]   # (forward swing, out) per arm, left/right
	var el := [0.5, 0.5]
	var hip := [0.0, 0.0]
	var knee := [0.0, 0.0]
	var tail_k := 1.0
	var balls := false
	# ---- walking / idling: he hops and capers
	var w_walk := _w("walk", dt)
	if w_walk > 0.0:
		var moving := clampf(spd / 3.0, 0.0, 1.0)
		var hop := absf(sin(ph * 0.5)) * (0.25 + 0.4 * moving)
		root_y += hop * w_walk
		squash = lerpf(squash, 1.0 - 0.06 * (1.0 - absf(sin(ph * 0.5))), w_walk)
		roll += sin(ph * 0.5) * 0.12 * w_walk
		lean += (-0.18 * moving + 0.04 * sin(ph)) * w_walk
		head_z += sin(ph * 0.5 + 0.6) * 0.18 * w_walk
		for s in 2:
			var sd := -1.0 if s == 0 else 1.0
			hip[s] += sin(ph * 0.5 + s * PI) * (0.25 + 0.5 * moving) * w_walk
			knee[s] += (0.25 + absf(sin(ph * 0.5 + s * PI)) * 0.6 * moving) * w_walk
			# arms: rubbing his hands with glee when still, flung about when he capers
			var rub := sin(t * 9.0 + s * PI) * 0.12
			sh[s] += Vector2(lerpf(0.9 + rub, -sin(ph * 0.5 + s * PI) * 0.8, moving), lerpf(0.05 * sd, 0.55 * sd, moving)) * w_walk - Vector2(0.15, 0.35 * sd) * w_walk
			el[s] += lerpf(0.9, 0.5, moving) * w_walk - 0.5 * w_walk
		jaw += (0.1 + 0.08 * absf(sin(t * 3.0))) * w_walk
	# ---- scampering: bent low, arms flung back, legs a blur
	var w_sc := _w("scamper", dt)
	if w_sc > 0.0:
		root_y += absf(sin(ph * 0.5)) * 0.35 * w_sc
		lean -= 0.55 * w_sc
		head_x += 0.35 * w_sc
		for s in 2:
			var sd := -1.0 if s == 0 else 1.0
			hip[s] += sin(ph * 0.5 + s * PI) * 0.9 * w_sc
			knee[s] += (0.3 + absf(sin(ph * 0.5 + s * PI)) * 1.0) * w_sc
			sh[s] += (Vector2(-1.1, 0.4 * sd) - Vector2(0.15, 0.35 * sd)) * w_sc
			el[s] += 0.3 * w_sc
		jaw += 0.35 * w_sc
		tail_k += 0.8 * w_sc
	# ---- claw swipe: the right arm cocks back and up, then rakes across in front
	var w_sw := _w("swipe", dt)
	if w_sw > 0.0:
		var wind := clampf(a / 0.7, 0.0, 1.0)
		var strike := clampf((a - 0.7) / 0.3, 0.0, 1.0)
		twist += (0.6 * wind - 1.3 * strike) * w_sw
		lean += (0.1 * wind - 0.25 * strike) * w_sw
		sh[1] += (Vector2(lerpf(2.2, 1.4, strike), lerpf(1.3, -0.6, strike)) - Vector2(0.15, 0.35)) * w_sw
		el[1] += (lerpf(0.9, 0.1, strike) - 0.5) * w_sw
		sh[0] += (Vector2(0.6, -0.7) - Vector2(0.15, -0.35)) * w_sw
		jaw += (0.25 + 0.3 * strike) * w_sw
		hip[0] += 0.3 * w_sw
		knee[0] += 0.4 * w_sw
		knee[1] += 0.3 * w_sw
	# ---- fire breath: rears back drawing breath, then thrusts his head forward, jaws wide
	var w_br := _w("breath", dt)
	if w_br > 0.0:
		var draw := clampf(a / 0.7, 0.0, 1.0)
		var blow := clampf((a - 0.7) / 0.3, 0.0, 1.0)
		lean += (0.3 * draw - 0.6 * blow) * w_br
		head_x += (0.45 * draw - 0.35 * blow) * w_br
		squash += 0.06 * draw * (1.0 - blow) * w_br
		jaw += (0.15 * draw + 0.75 * blow) * w_br
		for s in 2:
			var sd := -1.0 if s == 0 else 1.0
			sh[s] += (Vector2(lerpf(0.4, -0.5, blow), lerpf(0.9, 0.7, blow) * sd) - Vector2(0.15, 0.35 * sd)) * w_br
			el[s] += 0.4 * w_br
			knee[s] += 0.35 * blow * w_br
	# ---- juggling lava bombs, then flinging them skyward
	var w_jg := _w("juggle", dt)
	if w_jg > 0.0:
		var fling := clampf((a - 0.7) / 0.3, 0.0, 1.0)
		balls = w_jg > 0.5 and fling < 0.5
		head_x += 0.35 * w_jg
		jaw += 0.35 * w_jg
		for s in 2:
			var sd := -1.0 if s == 0 else 1.0
			var bob := sin(t * 10.0 + s * PI) * 0.35
			sh[s] += (Vector2(lerpf(1.25 + bob, 2.9, fling), lerpf(0.25, 0.5, fling) * sd) - Vector2(0.15, 0.35 * sd)) * w_jg
			el[s] += (lerpf(1.2, 0.1, fling) - 0.5) * w_jg
		root_y += absf(sin(t * 5.0)) * 0.15 * w_jg
	# ---- summoning / the eruption: arms flung high, cackling and bouncing
	for p in ["summon", "raise", "rise", "cackle"]:
		var wp := _w(p, dt)
		if wp <= 0.0:
			continue
		var cack := absf(sin(t * 14.0))
		var up := 2.7 if p != "cackle" else 0.6
		var out := 0.75 if p == "summon" else (0.35 if p != "cackle" else 0.55)
		head_x += (0.5 if p != "rise" else 0.3) * wp
		jaw += (0.3 + 0.45 * cack) * wp
		lean += (0.22 + 0.05 * cack) * wp
		root_y += (absf(sin(t * 6.0)) * (0.5 if p == "raise" else 0.2)) * wp
		for s in 2:
			var sd := -1.0 if s == 0 else 1.0
			var shake := sin(t * 18.0 + s) * 0.12
			sh[s] += (Vector2(up + shake, out * sd) - Vector2(0.15, 0.35 * sd)) * wp
			el[s] += ((0.3 if p != "cackle" else 1.6) - 0.5) * wp
			knee[s] += 0.3 * wp
		tail_k += 0.6 * wp
	# ---- cannonball: tucked into a spinning ball of coals
	var w_dv := maxf(_w("dive", dt), curl)
	if w_dv > 0.0:
		lean -= 0.7 * w_dv
		head_x -= 0.5 * w_dv
		for s in 2:
			var sd := -1.0 if s == 0 else 1.0
			hip[s] += 1.7 * w_dv
			knee[s] += 2.0 * w_dv
			sh[s] += (Vector2(1.0, 0.15 * sd) - Vector2(0.15, 0.35 * sd)) * w_dv
			el[s] += 1.3 * w_dv
		root_y += 1.0 * w_dv
	# ---- dying: he staggers, sputters and gutters out into a heap of coals
	var shrink := 1.0
	if pose == "die":
		var f := clampf((die_t - 0.8) / 2.2, 0.0, 1.0)
		root_rz += sin(die_t * 11.0) * 0.12 * (1.0 - f)
		lean -= 0.4 * f
		head_x -= 0.6 * f
		jaw = 0.5 * (1.0 - f)
		for s in 2:
			sh[s] = Vector2(0.2, 0.25 * (-1.0 if s == 0 else 1.0))
			knee[s] = 1.2 * f
		shrink = lerpf(1.0, 0.12, f * f)
		root_y = -0.6 * f
		_pile.visible = die_t > 2.2
		_pile.scale = Vector3.ONE * clampf((die_t - 2.2) / 0.8, 0.01, 1.0)
		_root.visible = die_t < 3.1
	else:
		_pile.visible = false
		_root.visible = true
	# ---- apply
	_root.position = Vector3(0, root_y + lift - sink - (1.0 - rise) * 7.5, 0)
	_root.rotation = Vector3(root_rx, 0, root_rz)
	_root.scale = Vector3(shrink * (2.0 - squash), shrink * squash, shrink * (2.0 - squash))
	_torso.rotation = Vector3(lean, twist, roll)
	head.rotation = Vector3(head_x, 0, head_z)
	_jaw.rotation.x = -clampf(jaw, 0.0, 1.0) * 0.75
	for s in 2:
		var sd := -1.0 if s == 0 else 1.0
		var v: Vector2 = sh[s]
		_shoulders[s].rotation = Vector3(v.x, 0, v.y)
		_elbows[s].rotation.x = el[s]
		_hips[s].rotation.x = hip[s]
		_knees[s].rotation.x = -knee[s]
		_ankles[s].rotation.x = knee[s] * 0.6 - hip[s] * 0.4
		_hips[s].rotation.z = 0.08 * sd
	for k in _tail.size():
		var seg := _tail[k]
		seg.rotation = Vector3(-0.16 - (0.1 if k > 4 else 0.0), sin(t * 3.2 * tail_k - k * 0.7) * 0.28, 0)
	for k in _balls.size():
		var b := _balls[k]
		b.visible = balls
		if balls:   # an arc over his head, from hand to hand
			var u := fmod(t * 1.4 + k / 3.0, 1.0)
			b.position = Vector3(lerpf(-1.4, 1.4, u if k % 2 == 0 else 1.0 - u), 5.6 + sin(u * PI) * 2.6, -1.6)
	_hair.scale = Vector3.ONE * 1.3 * (1.0 + _heat * 0.3)


# ------------------------------------------------------------------ building

static func _c(c: Color, tag: float) -> Color:
	return Color(c.r, c.g, c.b, tag)


## A basis whose local +Y points along `dir`.
static func _ybasis(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var side := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(side).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


## A cone with its base at `base`, pointing along `dir`.
static func _spike(mb: MeshBuilder, base: Vector3, dir: Vector3, r: float, h: float, col: Color, seg := 5) -> void:
	mb.add(MeshBuilder.cone(r, h, seg), Transform3D(_ybasis(dir), base + dir.normalized() * h * 0.5), col)


## A lump of coal: a faceted, squashed rock.
static func _coal(mb: MeshBuilder, at: Vector3, r: float, rng: RandomNumberGenerator, col: Color, scl := Vector3.ONE) -> void:
	var b := Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf() * TAU)
	mb.add(ForestProps._lumpy(r, rng), Transform3D(b.scaled(scl), at), col)


func _torso_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	_coal(mb, Vector3(0, 0.75, -0.1), 1.12, rng, _c(COAL, ROCK), Vector3(1.05, 0.95, 1.0))   # the pot belly
	_coal(mb, Vector3(0, 1.6, 0.05), 0.95, rng, _c(COAL, ROCK), Vector3(1.15, 0.85, 0.9))   # chest
	_coal(mb, Vector3(0, 2.05, 0.05), 0.55, rng, _c(COAL, ROCK))   # the neck's knot
	_coal(mb, Vector3(0, 0.15, 0.05), 0.8, rng, _c(COAL, ROCK), Vector3(1.1, 0.6, 0.95))   # hips
	for k in 26:   # hotter lumps of coal stuck all over him
		var a := rng.randf() * TAU
		var y := rng.randf_range(0.0, 2.0)
		var rad := 1.0 if y < 1.2 else 0.9
		var p := Vector3(cos(a) * rad, y, sin(a) * rad * 0.9 - 0.1)
		_coal(mb, p, rng.randf_range(0.2, 0.36), rng, _c(COAL_HI if rng.randf() < 0.5 else COAL, HOT if rng.randf() < 0.4 else ROCK))
	for sd in [-1.0, 1.0]:
		_coal(mb, Vector3(sd * 0.95, 2.0, 0.05), 0.42, rng, _c(COAL, HOT))   # shoulders
	return mb.commit(_mat)


func _head_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	_coal(mb, Vector3(0, 0.55, 0), 1.0, rng, _c(COAL, ROCK), Vector3(1.18, 0.95, 1.0))   # the big round head
	_coal(mb, Vector3(0, 0.12, -0.25), 0.75, rng, _c(COAL, ROCK), Vector3(1.25, 0.55, 1.0))   # cheeks
	for sd in [-1.0, 1.0]:
		# long pointed ears sweeping out and up
		var e0 := Vector3(sd * 1.0, 0.7, 0.05)
		var e1 := e0 + Vector3(sd * 0.6, 0.3, 0.1)
		mb.limb(e0, e1, 0.26, 0.17, _c(COAL, HOT), 7)
		_spike(mb, e1, Vector3(sd * 0.9, 0.5, 0.15), 0.17, 0.75, _c(COAL, HOT))
		# heavy brows slanting down to the middle: mischief
		mb.add(MeshBuilder.box(Vector3(0.52, 0.16, 0.28)), Transform3D(Basis(Vector3(0, 0, 1), sd * 0.38), Vector3(sd * 0.38, 0.98, -0.82)), _c(COAL_HI, ROCK))
		# glowing yellow eyes, slit pupils
		mb.add(MeshBuilder.sphere(0.21, 10, 7), Transform3D(Basis.from_scale(Vector3(1.15, 0.8, 0.6)), Vector3(sd * 0.38, 0.76, -0.86)), _c(EYE, GLOW))
		mb.add(MeshBuilder.box(Vector3(0.05, 0.26, 0.05)), Transform3D(Basis(), Vector3(sd * 0.38, 0.76, -0.985)), _c(Color(0.02, 0.01, 0.0), GLASS))
		# a tuft of little coal spikes on the cheeks
		_spike(mb, Vector3(sd * 0.95, 0.2, -0.2), Vector3(sd, -0.2, -0.3), 0.09, 0.35, _c(COAL, HOT))
	# snub nose
	_coal(mb, Vector3(0, 0.55, -1.02), 0.16, rng, _c(COAL_HI, ROCK), Vector3(1.2, 0.9, 1.0))
	# the grin: a wide glowing slot curving up at the corners, jagged upper teeth along it
	for k in 9:
		var u := (k - 4) / 4.0
		var p := Vector3(u * 0.78, 0.26 + u * u * 0.2, -0.9 + absf(u) * absf(u) * 0.3)
		mb.add(MeshBuilder.sphere(0.17, 8, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.65, 0.6)), p), _c(MOUTH, GLOW))
		_spike(mb, p + Vector3(0, 0.12, -0.04), Vector3(0, -1, -0.15), 0.07 + (0.02 if k % 2 == 0 else 0.0), 0.2 + (0.1 if k % 3 == 0 else 0.0), _c(TOOTH, BONE), 4)
	return mb.commit(_mat)


func _jaw_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 63
	_coal(mb, Vector3(0, -0.12, -0.35), 0.6, rng, _c(COAL, ROCK), Vector3(1.3, 0.45, 0.95))   # the chin
	mb.add(MeshBuilder.sphere(0.45, 10, 6), Transform3D(Basis.from_scale(Vector3(1.35, 0.25, 0.85)), Vector3(0, 0.04, -0.42)), _c(MOUTH, GLOW))   # the furnace inside
	_spike(mb, Vector3(0, -0.3, -0.55), Vector3(0, -1, -0.5), 0.12, 0.35, _c(COAL, HOT))   # a pointy chin
	for k in 8:   # jagged lower teeth
		var u := (k - 3.5) / 3.5
		var p := Vector3(u * 0.66, 0.0 + u * u * 0.18, -0.62 - (1.0 - absf(u)) * 0.18)
		_spike(mb, p, Vector3(0, 1, -0.1), 0.065, 0.16 + (0.1 if k % 3 == 1 else 0.0), _c(TOOTH, BONE), 4)
	return mb.commit(_mat)


## The flame hair: tongues of fire licking up and back off his crown.
func _hair_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 64
	for k in 13:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.7)
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r * 0.8)
		var h := rng.randf_range(1.0, 1.9) * (1.0 - r * 0.35)
		var dir := Vector3(base.x * 0.35, 1.0, base.z * 0.35 + 0.25).normalized()
		mb.add(MeshBuilder.cone(rng.randf_range(0.28, 0.45), h, 7), Transform3D(_ybasis(dir), base + dir * h * 0.5), Color.WHITE)
	return mb.commit(_fmat)


func _build_leg(pelvis: Node3D, sd: float) -> void:
	var hip := Node3D.new()
	hip.position = Vector3(sd * 0.55, 0.1, 0.05)
	pelvis.add_child(hip)
	var knee_at := Vector3(0, -0.92, -0.32)
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 70 + int(sd)
	mb.limb(Vector3.ZERO, knee_at, 0.3, 0.17, _c(COAL, ROCK), 8)
	_coal(mb, Vector3(0, -0.15, 0), 0.34, rng, _c(COAL, ROCK))
	_coal(mb, knee_at, 0.2, rng, _c(COAL_HI, HOT))
	_mesh(hip, mb.commit(_mat))
	var knee := Node3D.new()
	knee.position = knee_at
	hip.add_child(knee)
	var ankle_at := Vector3(0, -0.88, 0.4)
	var mb2 := MeshBuilder.new()
	mb2.limb(Vector3.ZERO, ankle_at, 0.15, 0.1, _c(COAL, ROCK), 7)
	_mesh(knee, mb2.commit(_mat))
	var ankle := Node3D.new()
	ankle.position = ankle_at
	knee.add_child(ankle)
	var mb3 := MeshBuilder.new()
	mb3.limb(Vector3.ZERO, Vector3(0, -0.2, -0.45), 0.11, 0.13, _c(COAL, ROCK), 7)
	for k in 3:   # three clawed toes splayed forward
		var a := (k - 1) * 0.42
		var toe := Vector3(sin(a) * 0.12, -0.2, -0.45)
		var dir := Vector3(sin(a), -0.15, -cos(a))
		mb3.limb(toe, toe + dir * 0.32, 0.07, 0.05, _c(COAL, ROCK), 5)
		_spike(mb3, toe + dir * 0.3, dir + Vector3(0, -0.5, 0), 0.05, 0.26, _c(CLAW, GLASS), 4)
	_spike(mb3, Vector3(0, 0, 0.05), Vector3(0, -0.4, 1), 0.06, 0.3, _c(CLAW, GLASS), 4)   # a dewclaw at the heel
	_mesh(ankle, mb3.commit(_mat))
	_hips.append(hip)
	_knees.append(knee)
	_ankles.append(ankle)


func _build_arm(torso: Node3D, sd: float) -> void:
	var sh := Node3D.new()
	sh.position = Vector3(sd * 1.05, 2.0, 0.05)
	torso.add_child(sh)
	var elbow_at := Vector3(sd * 0.12, -1.25, 0.08)
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 80 + int(sd)
	mb.limb(Vector3.ZERO, elbow_at, 0.19, 0.13, _c(COAL, ROCK), 7)   # spindly
	_coal(mb, elbow_at, 0.17, rng, _c(COAL_HI, HOT))
	_mesh(sh, mb.commit(_mat))
	var el := Node3D.new()
	el.position = elbow_at
	sh.add_child(el)
	var wrist := Vector3(0, -1.2, -0.05)
	var mb2 := MeshBuilder.new()
	mb2.limb(Vector3.ZERO, wrist, 0.13, 0.1, _c(COAL, ROCK), 7)
	var hand := Node3D.new()
	hand.position = wrist
	el.add_child(hand)
	_mesh(el, mb2.commit(_mat))
	var mb3 := MeshBuilder.new()
	_coal(mb3, Vector3(0, -0.12, 0), 0.22, rng, _c(COAL, ROCK), Vector3(1.0, 1.1, 0.7))
	for k in 3:   # three long clawed fingers, and a thumb
		var a := (k - 1) * 0.35
		var f0 := Vector3(sin(a) * 0.14, -0.25, -0.04)
		var f1 := f0 + Vector3(sin(a) * 0.15, -0.38, -0.12)
		var f2 := f1 + Vector3(sin(a) * 0.08, -0.26, -0.18)
		mb3.limb(f0, f1, 0.06, 0.05, _c(COAL, ROCK), 5)
		mb3.limb(f1, f2, 0.05, 0.04, _c(COAL, ROCK), 5)
		_spike(mb3, f2, (f2 - f1) + Vector3(0, 0, -0.1), 0.05, 0.34, _c(CLAW, GLASS), 4)
	_spike(mb3, Vector3(-sd * 0.15, -0.15, -0.12), Vector3(-sd * 0.4, -0.5, -0.8), 0.05, 0.3, _c(CLAW, GLASS), 4)
	_mesh(hand, mb3.commit(_mat))
	_shoulders.append(sh)
	_elbows.append(el)
	hands.append(hand)


## A long pointy tail: a chain of tapering coal links ending in a spade.
func _build_tail(pelvis: Node3D) -> void:
	var parent := pelvis
	var at := Vector3(0, 0.15, 0.7)
	for k in 8:
		var seg := Node3D.new()
		seg.position = at
		parent.add_child(seg)
		var r := lerpf(0.2, 0.06, k / 7.0)
		var mb := MeshBuilder.new()
		mb.limb(Vector3.ZERO, Vector3(0, 0, 0.5), r, r * 0.85, _c(COAL, HOT if k % 3 == 0 else ROCK), 6)
		if k == 7:   # the spade
			mb.add(MeshBuilder.cone(0.32, 0.6, 4), Transform3D(Basis(Vector3(1, 0, 0), PI / 2).scaled(Vector3(1.0, 1.0, 0.25)), Vector3(0, 0, 0.75)), _c(COAL_HI, HOT))
		_mesh(seg, mb.commit(_mat))
		_tail.append(seg)
		parent = seg
		at = Vector3(0, 0, 0.5)


## What's left of him: a small heap of coals and ash.
func _pile_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 65
	mb.add(MeshBuilder.sphere(1.5, 12, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.28, 1.0)), Vector3(0, 0.05, 0)), _c(Color(0.22, 0.2, 0.19), ROCK))   # ash
	for k in 24:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 1.3)
		var y := 0.25 + (1.3 - r) * 0.45 + rng.randf_range(0.0, 0.15)
		_coal(mb, Vector3(cos(a) * r, y, sin(a) * r), rng.randf_range(0.18, 0.38), rng, _c(COAL if rng.randf() < 0.6 else COAL_HI, HOT if rng.randf() < 0.5 else ROCK))
	_spike(mb, Vector3(0.1, 0.8, 0.0), Vector3(0.2, 1, 0.1), 0.12, 0.45, _c(COAL, HOT))   # the tip of his tail, poking out
	return mb.commit(_mat)
