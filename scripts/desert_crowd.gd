class_name DesertCrowd
extends Node3D
## The Desert's dead (EnemyManager.ZOMBIE .. VULTURE). They live in EnemyManager's rows like every
## goblin (no goblins come to the Desert: EnemyManager.type_remap turns every goblin spawn into
## its zombie counterpart); this draws them, gives them their extras and plays their deaths:
##
##   ZOMBIE         the common shambler: hunched, one leg dragging, arms out in front, a torn
##                  shirt, rotting grey-green skin, ribs showing, a dim glow in the eyes.
##   ZOMBIE_RUNNER  a fresh corpse that sprints (the scamps' place): lean, shirtless, arms pumping.
##   ZOMBIE_BRUTE   a bloated giant in torn overalls (the brutes' place), lumbering.
##   epic zombies   Plague Zombies: swollen, festering with glowing green boils.
##   MUMMY          slow and tanky, bound in bandages that trail and flutter, one eye burning
##                  through the wraps; it claws its way out of the sand when it spawns, and its
##                  touch CURSES you (slowed for a moment). Epic: a Mummy Priest in a gold nemes.
##   VULTURE        circles high on a thermal that keeps its distance from you, harmless and out
##                  of reach (EnemyManager.is_airborne: nothing can hit or target it up there).
##                  Come close and it glides down to land a few metres from you (on a pyramid's
##                  steps too), folds its wings and waddles after you on foot, slowly: now it can
##                  be hit. Within reach it rears back, a red wedge fills on the ground in front
##                  of it (PECK_WARN), and it lunges: a beak attack that hurts if you're still in
##                  the wedge. Run far away (or keep away long enough) and it takes off again.
## Walkers climb the pyramids by following the height grid (the steps are baked into it): on a
## steep stretch they slow down, lean into the slope and claw their way up, hand over hand.
##
## Models are built in code; walk, claw, climb, flap, glide, dive, strut, peck and death are
## animated in the vertex shader per instance (INSTANCE_CUSTOM: r = animation, g = phase, b = lean / fall / peck,
## a = the same burn / flash / epic / frozen / chill / shadow code as the goblins). The dead fall
## where they die (a vulture shot on the ground keels over; one caught in the air tumbles out
## of the sky) and sink into the sand.

const HEIGHT := 1.75
const STRIDE := 20
const CORPSE_MAX := 300
const CORPSE_LIFE := 3.2
const RISE_TIME := 1.4            # mummies clawing their way out of the sand
const CLIMB_SLOPE := 0.42         # steeper than this uphill: climbing (the pyramids are 0.77)
const CLIMB_SLOW := 0.45          # ...and they lose this share of their speed
const CURSE_SLOW := 0.55          # a mummy's touch: you move at this share of your speed...
const CURSE_TIME := 1.6           # ...for this long
const VULTURE_HIGH := 5.2         # metres above the ground (or you) while circling
const VULTURE_FLY_SPEED := 6.0    # m/s round its thermal
const VULTURE_RING := 4.5         # radius of the circle it flies round its thermal
const VULTURE_KEEP := 15.0        # its thermal hangs this far from you (+ 0..4.5 m per bird), so a
                                  # bird circling never comes nearer than VULTURE_LAND_RANGE by itself
const VULTURE_LAND_RANGE := 9.5   # you come this close (across the ground): it lands
const VULTURE_LAND_TIME := 1.2    # seconds gliding down and flaring
const VULTURE_LAND_DIST := 3.0    # it touches down this far from you
const VULTURE_STAND := 0.42       # standing: its body's centre this high over its feet (x scale)
const VULTURE_FLEE := 16.0        # on the ground: you get this far away and it takes off...
const VULTURE_GIVE_UP := 8.0      # ...or it's walked this long without pecking you
const VULTURE_CLIMB := 3.2        # m/s climbing back up
const VULTURE_RELAND := 4.0       # after taking off it won't land again for this long
const PECK_RANGE := 2.0           # within this it stops to peck
const PECK_REACH := 2.7           # the beak's wedge: this long...
const PECK_ARC := 0.55            # ...this many radians either side of its aim
const PECK_WARN := 0.8            # the wedge fills over this long before the beak strikes (>= 0.7 s)
const PECK_RECOVER := 0.3         # the lunge and pulling back
const PECK_CD := 1.5              # seconds between pecks
const PECK_DAMAGE := 1.5          # a peck hits this many zombie hits hard (x the run's enemy damage)
enum { V_CIRCLE, V_LAND, V_GROUND, V_PECK, V_TAKEOFF }
const A_WALK := 0.0
const A_CLAW := 0.25
const A_CLIMB := 0.5
const A_DIE := 0.75
# vulture animations
const A_FLAP := 0.0
const A_GLIDE := 0.25
const A_DIVE := 0.5
const A_STRUT := 1.0      # walking on the ground, wings folded
const A_PECK := 1.25      # rearing back and lunging (b = progress: 0..0.7 rear, the strike, 0.7..1 lunge)

enum { M_ZOMBIE, M_RUNNER, M_BRUTE, M_PLAGUE, M_MUMMY, M_PRIEST, M_VULTURE }

const SKIN := Color(0.46, 0.53, 0.4)
const ROT := Color(0.3, 0.28, 0.2)
const BONE := Color(0.86, 0.82, 0.7)
const SHIRT := Color(0.52, 0.47, 0.37)
const BLUE_SHIRT := Color(0.3, 0.36, 0.44)
const TROUSERS := Color(0.24, 0.2, 0.16)
const BLOOD := Color(0.3, 0.06, 0.05)
const WRAP := Color(0.78, 0.72, 0.58)
const WRAP_DARK := Color(0.55, 0.48, 0.36)
const GOLD := Color(0.92, 0.7, 0.25)
const LAPIS := Color(0.15, 0.25, 0.6)

const HUMAN_SHADER := """
shader_type spatial;
// COLOR.a of a vertex = its limb: 0 body, 1 L leg, 2 R leg, 3 L arm, 4 R arm, 5 head, 6 glow
// (eyes, boils), 7 loose cloth / bandage ends (flutter). INSTANCE_CUSTOM: r = animation (0 walk,
// .25 claw, .5 climb, .75 dying), g = phase, b = lean forward (climbing) / fall (dying, 0..1),
// a = burn + 2 flash + 4 epic + 8 frozen + 16 chill + 32 shadow.
uniform vec3 eye_color : source_color = vec3(0.75, 1.0, 0.3);
uniform float eye_power = 2.2;
uniform float hip_y = 0.92;
uniform float hip_x = 0.12;
uniform float sh_y = 1.42;
uniform float sh_x = 0.23;
uniform float head_y = 1.52;
uniform float gait = 0.0;        // 0 shamble, 1 sprint, 2 lumber, 3 mummy
varying float burn;
varying float flash;
varying float epic;
varying float frozen;
varying float chill;
varying float shadow;
varying float glow;
varying vec3 lpos;

mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_z(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	lpos = VERTEX;
	int limb = int(COLOR.a * 8.0 + 0.5);
	float anim = INSTANCE_CUSTOM.r;
	float ph = INSTANCE_CUSTOM.g * 6.2831853;
	float lean = INSTANCE_CUSTOM.b;
	float walk = 1.0 - step(0.125, anim);
	float claw = step(0.125, anim) * (1.0 - step(0.375, anim));
	float climb = step(0.375, anim) * (1.0 - step(0.625, anim));
	float die = step(0.625, anim);
	float sprint = step(0.5, gait) * (1.0 - step(1.5, gait));
	float lumber = step(1.5, gait) * (1.0 - step(2.5, gait));
	float mummy = step(2.5, gait);
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	vec3 hip_l = vec3(hip_x, hip_y, 0.0);
	vec3 hip_r = vec3(-hip_x, hip_y, 0.0);
	vec3 sh_l = vec3(sh_x, sh_y, 0.0);
	vec3 sh_r = vec3(-sh_x, sh_y, 0.0);
	float stride = mix(0.5, 0.95, sprint) * mix(1.0, 0.55, mummy) * mix(1.0, 0.7, lumber);
	float swing = sin(ph) * stride * (walk + climb * 0.7);
	mat3 R = mat3(1.0);
	vec3 piv = vec3(0.0);
	if (limb == 1) { piv = hip_l; R = rot_x(swing - die * 0.2); }
	if (limb == 2) { piv = hip_r; R = rot_x(-swing * mix(0.5, 1.0, max(max(sprint, mummy), lumber)) + die * 0.15); }   // the shambler drags his right leg
	if (limb == 3 || limb == 4) {
		float side = limb == 3 ? 1.0 : -1.0;
		// arms out in front (zombies, mummies straight and stiff), pumping (sprinters)
		float reach = mix(mix(mix(-1.2, -0.25, sprint), -1.5, mummy), -0.9, lumber);
		float a = reach + sin(ph * 0.5 + side) * 0.12 * (1.0 - mummy) - sprint * swing * 1.4 * side;
		a = mix(a, -1.7 + sin(ph + (side > 0.0 ? 0.0 : 3.14)) * 0.95, claw);                        // clawing at you
		a = mix(a, -2.7 + sin(ph + (side > 0.0 ? 0.0 : 3.14)) * 0.55, climb);                       // hand over hand up the steps
		a = mix(a, -2.9, die * clamp(lean * 1.5, 0.0, 1.0));                                         // flung out as it falls
		piv = side > 0.0 ? sh_l : sh_r;
		R = rot_z(side * (0.12 + claw * 0.15 + die * 0.4)) * rot_x(a);
	}
	if (limb == 5 || limb == 6) {
		piv = vec3(0.0, head_y, 0.0);
		float loll = (0.22 + sin(ph * 0.5) * 0.12) * (1.0 - mummy) * (1.0 - sprint * 0.6);
		R = rot_z(loll) * rot_x(0.12 - climb * 0.5);
	}
	v = piv + R * (v - piv);
	n = R * n;
	if (limb == 7) {   // rags and bandage ends flutter
		float w = clamp((sh_y - VERTEX.y) * 0.6, 0.0, 1.0) + 0.3;
		v.x += sin(TIME * 7.0 + VERTEX.y * 9.0 + ph) * 0.045 * w;
		v.z += -0.03 * w + cos(TIME * 6.0 + VERTEX.y * 7.0) * 0.04 * w;
	}
	// the whole body: a rolling shamble, a bob, a lean into the slope / the sprint, or the fall
	float sway = sin(ph) * mix(0.08, 0.03, sprint + mummy) * walk;
	float pitch = lean * (1.0 - die) + sprint * 0.28 * walk + lumber * 0.12;
	pitch = mix(pitch, lean * 1.5, die);
	mat3 G = rot_x(pitch) * rot_z(sway);
	v.y += abs(sin(ph)) * 0.045 * (walk + climb);
	v = G * v;
	n = G * n;
	VERTEX = v;
	NORMAL = normalize(n);
	glow = limb == 6 ? 1.0 : 0.0;
	float c = INSTANCE_CUSTOM.a;
	shadow = step(31.5, c); c -= shadow * 32.0;
	chill = step(15.5, c); c -= chill * 16.0;
	frozen = step(7.5, c); c -= frozen * 8.0;
	epic = step(3.5, c); c -= epic * 4.0;
	flash = step(1.5, c); c -= flash * 2.0;
	burn = clamp(c, 0.0, 1.0);
	flash *= smoothstep(18.0, 12.0, length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
}

void fragment() {
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	// grime and rot: blotches, fine dirt
	float g = noise(lpos * 11.0) * 0.6 + noise(lpos * 31.0) * 0.4;
	col *= 0.78 + 0.4 * g;
	col = mix(col, col * vec3(0.7, 0.62, 0.45), smoothstep(0.62, 0.8, noise(lpos * 5.0 + 3.0)) * 0.6);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	col = mix(col, col * vec3(0.92, 0.78, 1.12), epic * 0.5);
	col = mix(col, vec3(1.0, 0.42, 0.08), burn * 0.6);
	col = mix(col, col * vec3(0.55, 0.8, 1.25), chill * 0.55);
	col = mix(col, vec3(0.72, 0.9, 1.0), frozen * 0.78);
	col = mix(col, col * vec3(0.35, 0.22, 0.5), shadow * 0.7);
	ALBEDO = mix(col, col * vec3(1.45, 0.55, 0.45), flash * 0.6);
	ROUGHNESS = 0.85;
	EMISSION = glow * eye_color * eye_power + vec3(1.0, 0.32, 0.04) * burn * 0.9 + vec3(0.62, 0.18, 1.0) * epic * rim * 1.6
		+ vec3(0.45, 0.8, 1.0) * (frozen * (0.25 + rim * 1.4) + chill * rim * 0.6) + vec3(0.6, 0.2, 1.0) * shadow * rim * 1.8;
}
"""

const VULTURE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
// COLOR.a = limb: 0 body, 1 L inner wing, 2 R inner wing, 3 L outer wing, 4 R outer wing,
// 5 neck and head, 6 eyes, 7 tail and feet. INSTANCE_CUSTOM: r = animation (0 flap, .25 glide,
// .5 dive, .75 dead, 1 strut on the ground, 1.25 peck), g = phase, b = peck progress (0..0.7
// rearing back, 0.7..1 the lunge), a = status code (as the goblins).
varying float burn;
varying float flash;
varying float epic;
varying float frozen;
varying float chill;
varying float shadow;
varying float glow;
varying vec3 lpos;
mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }
mat3 rot_z(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }
void vertex() {
	lpos = VERTEX;
	int limb = int(COLOR.a * 8.0 + 0.5);
	float anim = INSTANCE_CUSTOM.r;
	float ph = INSTANCE_CUSTOM.g * 6.2831853;
	float pk = INSTANCE_CUSTOM.b;
	float flap = 1.0 - step(0.125, anim);
	float glide = step(0.125, anim) * (1.0 - step(0.375, anim));
	float dive = step(0.375, anim) * (1.0 - step(0.625, anim));
	float dead = step(0.625, anim) * (1.0 - step(0.875, anim));
	float walk = step(0.875, anim) * (1.0 - step(1.125, anim));
	float peck = step(1.125, anim);
	float ground = walk + peck;
	float rear = peck * smoothstep(0.0, 0.7, pk) * (1.0 - smoothstep(0.7, 0.75, pk));
	float lunge = peck * smoothstep(0.7, 0.77, pk) * (1.0 - smoothstep(0.86, 1.0, pk));
	float a1 = sin(ph) * 0.85 * flap + (0.1 + sin(TIME * 1.7 + ph) * 0.05) * glide - 0.55 * dead + 0.25 * dive;
	float a2 = sin(ph - 0.7) * 0.5 * flap + (-0.05 + sin(TIME * 2.1 + ph) * 0.06) * glide - 0.8 * dead - 0.2 * dive;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	bool leg = limb == 7 && VERTEX.z > -0.3 && VERTEX.y < -0.06;
	if (limb >= 1 && limb <= 4) {
		float side = (limb == 1 || limb == 3) ? 1.0 : -1.0;
		if (ground > 0.5) {
			// folded: the wing shortened, swept back along the body and draped over the flank,
			// the primaries crossing over the tail; mantled a little as it rears back
			vec3 sh = vec3(side * 0.13, 0.09, 0.1);
			v.x = sh.x + (v.x - sh.x) * 0.6;
			if (limb >= 3) {
				vec3 el = vec3(side * 0.53, 0.06, 0.0);
				mat3 r2 = rot_y(side * 0.3);
				v = el + r2 * (v - el);
				n = r2 * n;
			}
			mat3 r1 = rot_z(-side * (1.2 - rear * 0.45)) * rot_y(side * 1.48);
			v = sh + r1 * (v - sh);
			n = r1 * n;
		} else {
			vec3 sh = vec3(side * 0.16, 0.06, 0.08);
			vec3 el = vec3(side * 0.82, 0.06, 0.0);
			mat3 r1 = rot_y(-side * 1.1 * dive) * rot_z(side * a1);
			if (limb >= 3) {   // the outer wing bends again at the wrist
				mat3 r2 = rot_y(-side * 0.6 * dive) * rot_z(side * a2);
				v = el + r2 * (v - el);
				n = r2 * n;
			}
			v = sh + r1 * (v - sh);
			n = r1 * n;
		}
	}
	if (limb == 5 || limb == 6) {   // the head bobs and peers down; on foot it bobs as it walks, rears back, strikes
		vec3 nk = vec3(0.0, 0.08, 0.32);
		float hx = 0.25 + sin(ph * 2.0) * 0.08 * flap + dive * 0.4;
		hx = mix(hx, 0.45 + sin(ph * 2.0) * 0.14 * walk - rear * 1.15 + lunge * 1.0, ground);
		mat3 r = rot_x(hx);
		v = nk + r * (v - nk);
		n = r * n;
		v.z += (sin(ph * 2.0) * 0.05 * walk - rear * 0.12 + lunge * 0.2) * ground;
		v.y += (rear * 0.08 - lunge * 0.06) * ground;
	}
	if (limb == 7 && !leg) { v.y += sin(ph) * 0.02 * (1.0 - ground); }
	if (ground > 0.5) {
		if (leg) {
			// standing: the legs straighten down from the hips (and lengthen), stepping in turn
			float ls = VERTEX.x > 0.0 ? 1.0 : -1.0;
			vec3 hip = vec3(ls * 0.08, -0.12, 0.0);
			mat3 r = rot_x(-0.98 + ls * sin(ph) * 0.5 * walk);
			v = hip + r * ((v - hip) * 1.6);
			n = r * n;
			v.y += max(0.0, ls * cos(ph)) * 0.04 * walk;   // the foot coming forward lifts
		} else {
			// the body sits up, hunched, and pitches into the lunge
			mat3 bp = rot_x(-0.32 - rear * 0.25 + lunge * 0.8 + sin(ph * 2.0) * 0.05 * walk);
			vec3 hp = vec3(0.0, -0.12, 0.0);
			v = hp + bp * (v - hp);
			n = bp * n;
		}
		// a waddle: rolling over each foot in turn, bobbing
		mat3 wd = rot_z(sin(ph) * 0.12 * walk);
		vec3 ft = vec3(0.0, -0.42, 0.0);
		v = ft + wd * (v - ft);
		n = wd * n;
		v.y += abs(sin(ph)) * 0.03 * walk;
	}
	v.y -= sin(ph) * 0.08 * flap;   // the body heaves against each beat
	VERTEX = v;
	NORMAL = normalize(n);
	glow = limb == 6 ? 1.0 : 0.0;
	float c = INSTANCE_CUSTOM.a;
	shadow = step(31.5, c); c -= shadow * 32.0;
	chill = step(15.5, c); c -= chill * 16.0;
	frozen = step(7.5, c); c -= frozen * 8.0;
	epic = step(3.5, c); c -= epic * 4.0;
	flash = step(1.5, c); c -= flash * 2.0;
	burn = clamp(c, 0.0, 1.0);
}
void fragment() {
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	// feather barring on the wings
	col *= 0.85 + 0.25 * step(0.5, fract(lpos.x * 9.0 + lpos.z * 3.0));
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	col = mix(col, col * vec3(0.92, 0.78, 1.12), epic * 0.5);
	col = mix(col, vec3(1.0, 0.42, 0.08), burn * 0.6);
	col = mix(col, col * vec3(0.55, 0.8, 1.25), chill * 0.55);
	col = mix(col, vec3(0.72, 0.9, 1.0), frozen * 0.78);
	col = mix(col, col * vec3(0.35, 0.22, 0.5), shadow * 0.7);
	ALBEDO = mix(col, col * vec3(1.45, 0.55, 0.45), flash * 0.6);
	ROUGHNESS = 0.9;
	EMISSION = glow * vec3(1.0, 0.55, 0.1) * 1.5 + vec3(1.0, 0.32, 0.04) * burn * 0.9 + vec3(0.62, 0.18, 1.0) * epic * rim * 1.6
		+ vec3(0.45, 0.8, 1.0) * (frozen * (0.25 + rim * 1.4) + chill * rim * 0.6) + vec3(0.6, 0.2, 1.0) * shadow * rim * 1.8;
}
"""

const SOUNDS := {
	"groan": ["res://audio/desert/zombie_groan_1.wav", "res://audio/desert/zombie_groan_2.wav", "res://audio/desert/zombie_groan_3.wav"],
	"rasp": ["res://audio/desert/mummy_rasp_1.wav", "res://audio/desert/mummy_rasp_2.wav"],
	"screech": ["res://audio/desert/vulture_screech_1.wav", "res://audio/desert/vulture_screech_2.wav"],
	"flap": ["res://audio/desert/vulture_flap.wav"],
	"peck": ["res://audio/desert/vulture_peck.wav"],
	"curse": ["res://audio/desert/mummy_curse.wav"],
	"crumble": ["res://audio/desert/mummy_crumble.wav"],
}

var em: EnemyManager
var _mm: Array[MultiMesh] = []
var _buf := PackedFloat32Array()     # every kind's instances, CAP apiece, one after the other
var _counts := PackedInt32Array()
const CAP := EnemyManager.MAX + CORPSE_MAX
const STONE_N := 110                 # 4 m cells over the arena: is there stone (a pyramid, the plinth) here?
const KIND_OF := [0, 1, 2, 4, 6]     # ZOMBIE.. VULTURE -> M_ZOMBIE, M_RUNNER, M_BRUTE, M_MUMMY, M_VULTURE
var _stone_grid := PackedByteArray()
var _goblins_hidden := false
var _alt := {}                       # vulture uid -> height above its floor
var _v := {}                         # vulture uid -> its state (see _fly)
var _frame := 0
var _curse_cd := {}                  # mummy uid -> seconds until it can curse again
var _t := 0.0
# corpses: kind (mesh), position, yaw, scale, age, the height it fell from
var _c_kind := PackedInt32Array()
var _c_pos := PackedVector3Array()
var _c_yaw := PackedFloat32Array()
var _c_scale := PackedFloat32Array()
var _c_age := PackedFloat32Array()
var _c_from := PackedFloat32Array()
var _c_n := 0
var _sfx: Array[AudioStreamPlayer3D] = []
var _streams := {}
var _voice_t := 1.0
var _fx: FxManager
# counters for tests
var curses := 0
var climbing := 0                    # walkers climbing right now
var vultures_grounded := 0           # vultures on the ground right now
var pecks := 0                       # beak attacks started (telegraphed)...
var peck_hits := 0                   # ...and the ones that caught you in the wedge


func _ready() -> void:
	name = "DesertCrowd"   # no-i18n
	var meshes := build_meshes()
	for k in meshes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = meshes[k]
		mm.instance_count = CAP
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 200, 1000))
		add_child(mmi)
		_mm.append(mm)
	_buf.resize(meshes.size() * CAP * STRIDE)
	_counts.resize(meshes.size())
	_stone_grid.resize(STONE_N * STONE_N)
	for f in DesertBuilder.footprints:
		var r: Vector4 = f[0]
		for gz in range(maxi(0, int((r.y - r.w - 2.0 + 220.0) * 0.25)), mini(STONE_N, int((r.y + r.w + 2.0 + 220.0) * 0.25) + 1)):
			for gx in range(maxi(0, int((r.x - r.z - 2.0 + 220.0) * 0.25)), mini(STONE_N, int((r.x + r.z + 2.0 + 220.0) * 0.25) + 1)):
				_stone_grid[gz * STONE_N + gx] = 1
	for k in range(0, _buf.size(), STRIDE):   # instance colours stay white
		_buf[k + 12] = 1.0; _buf[k + 13] = 1.0; _buf[k + 14] = 1.0; _buf[k + 15] = 1.0
	_c_kind.resize(CORPSE_MAX)
	_c_pos.resize(CORPSE_MAX)
	for a in [_c_yaw, _c_scale, _c_age, _c_from]:
		a.resize(CORPSE_MAX)
	for k in SOUNDS:
		var list: Array = []
		for path in SOUNDS[k]:
			if ResourceLoader.exists(path):
				list.append(load(path))
		_streams[k] = list
	for k in 5:
		var a := AudioStreamPlayer3D.new()
		a.bus = Settings.SFX_BUS
		a.unit_size = 9.0
		a.max_distance = 45.0
		add_child(a)
		_sfx.append(a)


## Is `t` one of the Desert's types?
static func owns(t: int) -> bool:
	return t == EnemyManager.ZOMBIE or t == EnemyManager.ZOMBIE_RUNNER or t == EnemyManager.ZOMBIE_BRUTE or t == EnemyManager.MUMMY or t == EnemyManager.VULTURE


static func is_walker(t: int) -> bool:
	return t == EnemyManager.ZOMBIE or t == EnemyManager.ZOMBIE_RUNNER or t == EnemyManager.ZOMBIE_BRUTE or t == EnemyManager.MUMMY


## What spawns on the Desert this minute (the goblins' weights, plus mummies and vultures).
static func pick_type(rng: RandomNumberGenerator, m: float) -> int:
	var w_zombie := 10.0
	var w_runner := 4.0 * minf(m, 3.0) if m >= 1.0 else 0.0
	var w_brute := 1.5 * (m - 1.0) if m >= 2.0 else 0.0
	var w_mummy := 1.5 + 0.6 * minf(m, 6.0) if m >= 0.75 else 0.0
	var w_vulture := 2.0 + 0.4 * minf(m, 5.0) if m >= 0.4 else 0.0
	var r := rng.randf() * (w_zombie + w_runner + w_brute + w_mummy + w_vulture)
	if r < w_zombie:
		return EnemyManager.ZOMBIE
	r -= w_zombie
	if r < w_runner:
		return EnemyManager.ZOMBIE_RUNNER
	r -= w_runner
	if r < w_brute:
		return EnemyManager.ZOMBIE_BRUTE
	r -= w_brute
	if r < w_mummy:
		return EnemyManager.MUMMY
	return EnemyManager.VULTURE


func on_spawn(i: int) -> void:
	var t := em.typ[i]
	if t == EnemyManager.MUMMY:
		em.rise_t[i] = RISE_TIME
	elif t == EnemyManager.VULTURE:
		var alt := 9.0 + randf() * 3.0
		_alt[em.uid[i]] = alt
		var p := em.pos[i]
		p.y += alt
		em.pos[i] = p
		_v[em.uid[i]] = _new_state(p)


func _new_state(p: Vector3) -> Dictionary:
	return {"s": V_CIRCLE, "t": 0.0, "cd": 0.0, "pcd": 0.0, "p": p, "c": p, "a": randf() * TAU, "ph": 0.0,
		"from": p, "goal": p, "aim": Vector3.FORWARD, "disc": null, "struck": false, "f": _frame}


func on_kill(i: int) -> void:
	var t := em.typ[i]
	var kind := _mesh_of(i)
	var v := em.vel[i]
	var yaw := atan2(v.x, v.z) if Vector2(v.x, v.z).length() > 0.2 else randf() * TAU
	var k := _c_n
	if _c_n < CORPSE_MAX:
		_c_n += 1
	else:
		k = randi() % CORPSE_MAX
	_c_kind[k] = kind
	_c_pos[k] = em.pos[i]
	_c_yaw[k] = yaw
	_c_scale[k] = em.t_scale[t] * em.sz[i]
	_c_age[k] = 0.0
	_c_from[k] = em.pos[i].y - SwampWater.height_at(em.pos[i].x, em.pos[i].z)
	if t == EnemyManager.VULTURE:
		_alt.erase(em.uid[i])
		_drop_state(em.uid[i])
		_burst(em.pos[i] + Vector3(0, 0.4 if _c_from[k] < 0.6 else 0.0, 0), 1.4, Color(0.22, 0.18, 0.15))   # a puff of feathers
		_play("screech", em.pos[i], 0.6, 1.25)
	elif t == EnemyManager.MUMMY:
		_curse_cd.erase(em.uid[i])
		_burst(em.pos[i] + Vector3(0, 1.0, 0), 1.8, Color(0.8, 0.7, 0.5))   # crumbles to dust
		_play("crumble", em.pos[i], 0.8)


func _burst(at: Vector3, r: float, c: Color) -> void:
	if _fx == null:
		_fx = em.get_parent().get("fx") as FxManager if em.get_parent() != null else null
	if _fx != null:
		_fx.burst(at, r, c, 0.35)


func _mesh_of(i: int) -> int:
	var t := em.typ[i]
	var ep := em.epic[i] == 1
	match t:
		EnemyManager.ZOMBIE_RUNNER: return M_PLAGUE if ep else M_RUNNER
		EnemyManager.ZOMBIE_BRUTE: return M_PLAGUE if ep else M_BRUTE
		EnemyManager.MUMMY: return M_PRIEST if ep else M_MUMMY
		EnemyManager.VULTURE: return M_VULTURE
	return M_PLAGUE if ep else M_ZOMBIE


# ------------------------------------------------------------------ per frame

## Called by EnemyManager at the end of its tick (after the skeletons): moves the Desert's rows
## out of the goblin MultiMesh into their own, flies the vultures, slows the climbers, curses
## with the mummies' touch, and runs the corpses and the voices.
func sync(dt: float, buf: PackedFloat32Array, player: Node3D) -> PackedFloat32Array:
	_t += dt
	_frame += 1
	_counts.fill(0)
	climbing = 0
	vultures_grounded = 0
	var pp := player.global_position if player != null else Vector3.ZERO
	var p_ok := player != null
	for k in _curse_cd.keys():
		_curse_cd[k] = float(_curse_cd[k]) - dt
	# Nothing on the Desert is drawn by the goblin mesh (every spawn is one of these, the boss
	# draws himself): hide it once rather than blanking every row's transform every frame
	if not _goblins_hidden:
		for c in em.get_children():
			if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh == em.mm:
				(c as MultiMeshInstance3D).visible = false
				_goblins_hidden = true
	# Read-only views of the crowd's rows (writes go back through em.pos / em.vel)
	var typ := em.typ
	var pos := em.pos
	var vel := em.vel
	var sz := em.sz
	var tsc := em.t_scale
	var epic := em.epic
	var dead := em.dead
	var freeze := em.freeze_t
	var stun := em.stun_t
	var kbt := em.kb_t
	var rise := em.rise_t
	var clip_attack := em._clip_attack
	var z0 := EnemyManager.ZOMBIE
	var z1 := EnemyManager.VULTURE
	for i in em.count:
		var t := typ[i]
		if t < z0 or t > z1:
			continue
		var b := i * STRIDE
		var sc := tsc[t] * sz[i]
		var p := pos[i]
		var v := vel[i]
		var anim := A_CLAW if absf(buf[b + 12] - clip_attack) < 0.01 else A_WALK
		var phase := buf[b + 13]
		var lean := 0.0
		var held := freeze[i] > 0.0 or stun[i] > 0.0
		var kind: int = M_PLAGUE if epic[i] == 1 and t != EnemyManager.MUMMY and t != EnemyManager.VULTURE else KIND_OF[t - z0]
		if kind == M_MUMMY and epic[i] == 1:
			kind = M_PRIEST
		if t == EnemyManager.VULTURE:
			if dead[i] == 0:
				_fly(i, dt, pp, player, held, kind, sc, buf[b + 19])
		else:
			if dead[i] == 0:
				# walkers climbing the pyramids (or the plinth's steps) slow down and lean in
				var gx := int((p.x + 220.0) * 0.25)
				var gz := int((p.z + 220.0) * 0.25)
				if gx >= 0 and gz >= 0 and gx < STONE_N and gz < STONE_N and _stone_grid[gz * STONE_N + gx] != 0:
					var hv := Vector2(v.x, v.z)
					if hv.length() > 0.3 and not held and kbt[i] <= 0.0:
						var dir := hv.normalized()
						var h0 := SwampWater.height_at(p.x, p.z)
						var h1 := SwampWater.height_at(p.x + dir.x * 0.8, p.z + dir.y * 0.8)
						if (h1 - h0) / 0.8 > CLIMB_SLOPE:
							p.x -= v.x * dt * CLIMB_SLOW
							p.z -= v.z * dt * CLIMB_SLOW
							p.y = SwampWater.height_at(p.x, p.z)
							em.pos[i] = p
							climbing += 1
							if anim != A_CLAW:
								anim = A_CLIMB
							lean = 0.45
				if t == EnemyManager.MUMMY:
					if rise[i] > 0.0:   # clawing up out of the sand
						p.y -= HEIGHT * sc * 1.05 * clampf(rise[i] / RISE_TIME, 0.0, 1.0)
						anim = A_CLAW
					elif p_ok and not em.is_harmless(i):
						_try_curse(i, pp, player)
			# facing: the way it's going, or at the player when standing; the yaw basis is
			# written straight in (the hot path)
			var fx := v.x
			var fz := v.z
			if fx * fx + fz * fz < 0.04 and p_ok:
				fx = pp.x - p.x
				fz = pp.z - p.z
			var fl := sqrt(fx * fx + fz * fz)
			if fl > 0.001:
				fx /= fl
				fz /= fl
			else:
				fx = 0.0
				fz = 1.0
			var k := _counts[kind]
			if k < CAP:
				_counts[kind] = k + 1
				var o := (kind * CAP + k) * STRIDE
				_buf[o] = fz * sc; _buf[o + 1] = 0.0; _buf[o + 2] = fx * sc; _buf[o + 3] = p.x
				_buf[o + 4] = 0.0; _buf[o + 5] = sc; _buf[o + 6] = 0.0; _buf[o + 7] = p.y
				_buf[o + 8] = -fx * sc; _buf[o + 9] = 0.0; _buf[o + 10] = fz * sc; _buf[o + 11] = p.z
				_buf[o + 16] = anim; _buf[o + 17] = phase; _buf[o + 18] = lean; _buf[o + 19] = buf[b + 19]
	if not _v.is_empty():   # rows gone without a death (cleared, despawned): drop their state
		for u in _v.keys():
			if int((_v[u] as Dictionary)["f"]) != _frame:
				_drop_state(u)
				_alt.erase(u)
	_tick_corpses(dt)
	_voices(dt, pp, p_ok)
	for k in _mm.size():
		if _counts[k] > 0 or _mm[k].visible_instance_count > 0:
			_mm[k].buffer = _buf.slice(k * CAP * STRIDE, (k + 1) * CAP * STRIDE)
		_mm[k].visible_instance_count = _counts[k]
	return buf


func _put(kind: int, xf: Transform3D, anim: float, phase: float, lean: float, code: float) -> void:
	var k := _counts[kind]
	if k >= CAP:
		return
	_counts[kind] = k + 1
	var o := (kind * CAP + k) * STRIDE
	var bs := xf.basis
	_buf[o] = bs.x.x; _buf[o + 1] = bs.y.x; _buf[o + 2] = bs.z.x; _buf[o + 3] = xf.origin.x
	_buf[o + 4] = bs.x.y; _buf[o + 5] = bs.y.y; _buf[o + 6] = bs.z.y; _buf[o + 7] = xf.origin.y
	_buf[o + 8] = bs.x.z; _buf[o + 9] = bs.y.z; _buf[o + 10] = bs.z.z; _buf[o + 11] = xf.origin.z
	_buf[o + 12] = 1.0; _buf[o + 13] = 1.0; _buf[o + 14] = 1.0; _buf[o + 15] = 1.0
	_buf[o + 16] = anim; _buf[o + 17] = phase; _buf[o + 18] = lean; _buf[o + 19] = code


## How high a vulture is flying above its floor (metres); 0 for anything that isn't one.
func altitude(u: int) -> float:
	return float(_alt.get(u, 0.0))


## Is this vulture up in the air, out of reach (circling, gliding down to land, or climbing
## away above EnemyManager.VULTURE_HITTABLE_ALT)? Only once it's on the ground can it be hit.
func airborne(u: int) -> bool:
	var s: Dictionary = _v.get(u, {})
	if s.is_empty():
		return false
	var st: int = s["s"]
	if st == V_CIRCLE or st == V_LAND:
		return true
	return st == V_TAKEOFF and float(_alt.get(u, 0.0)) > EnemyManager.VULTURE_HITTABLE_ALT


## The vulture's state (V_CIRCLE ..), -1 for anything that isn't one.
func vulture_state(u: int) -> int:
	var s: Dictionary = _v.get(u, {})
	return -1 if s.is_empty() else int(s["s"])


## Its beak's warning wedge on the ground right now (null when it isn't pecking).
func peck_disc(u: int) -> GroundDisc:
	var s: Dictionary = _v.get(u, {})
	return null if s.is_empty() else s["disc"] as GroundDisc


## Put a vulture straight down on the ground where it is (tests).
func land_now(i: int) -> void:
	var u := em.uid[i]
	if not _v.has(u):
		_v[u] = _new_state(em.pos[i])
	var p := em.pos[i]
	p.y = SwampWater.height_at(p.x, p.z)
	em.pos[i] = p
	_touch_down(_v[u], u, p, em.t_scale[EnemyManager.VULTURE] * em.sz[i])


func _drop_state(u: int) -> void:
	var s: Dictionary = _v.get(u, {})
	if not s.is_empty():
		_free_disc(s)
		_v.erase(u)


func _free_disc(s: Dictionary) -> void:
	var d := s["disc"] as GroundDisc
	if d != null and is_instance_valid(d):
		d.queue_free()
	s["disc"] = null


func _touch_down(s: Dictionary, u: int, p: Vector3, sc: float) -> void:
	s["s"] = V_GROUND
	s["t"] = 0.0
	s["pcd"] = maxf(float(s["pcd"]), 0.3)
	s["p"] = p
	_alt[u] = VULTURE_STAND * sc


func _take_off(s: Dictionary, p: Vector3, sc: float) -> void:
	_free_disc(s)
	s["s"] = V_TAKEOFF
	s["t"] = 0.0
	s["cd"] = VULTURE_RELAND
	s["from"] = p
	s["p"] = Vector3(p.x, p.y + VULTURE_STAND * sc, p.z)
	s["c"] = p
	_play("flap", p, 0.8)


## Where the ground under a flying vulture counts from: near you it's your level (so it circles
## above you up a pyramid), away from you the ground.
func _floor_y(g: float, pp: Vector3, d: float, p_ok: bool) -> float:
	return maxf(g, lerpf(pp.y, g, smoothstep(8.0, 30.0, d))) if p_ok else g


## A vulture's life this frame (see VULTURE in the header): circling high on its thermal,
## gliding down to land, walking on the ground (the hot loop walked its row at the player:
## EnemyManager.t_speed), pecking, climbing away. Draws it.
func _fly(i: int, dt: float, pp: Vector3, player: Node3D, held: bool, kind: int, sc: float, code: float) -> void:
	var u := em.uid[i]
	var p_ok := player != null
	if not _v.has(u):
		_v[u] = _new_state(em.pos[i])
	var s: Dictionary = _v[u]
	s["f"] = _frame
	s["cd"] = float(s["cd"]) - dt
	s["pcd"] = float(s["pcd"]) - dt
	var st: int = s["s"]
	var row := em.pos[i]   # where the hot loop put it (at the ground, walked toward you)
	var alt: float = _alt.get(u, VULTURE_HIGH)
	var anim := A_GLIDE
	var roll := 0.0
	var pitch := 0.0
	var pk := 0.0
	var p := row
	var face := Vector2.ZERO
	var harmless := em.is_harmless(i)
	if st == V_CIRCLE or st == V_LAND or st == V_TAKEOFF:
		p = s["p"]
		if Vector2(row.x - p.x, row.z - p.z).length() > 6.0:   # the hot loop moved a straggler back near you
			p = Vector3(row.x, p.y, row.z)
			s["c"] = p
	if st == V_CIRCLE:
		var g := SwampWater.height_at(p.x, p.z)
		var d := Vector2(pp.x - p.x, pp.z - p.z).length()
		if not held:
			var c: Vector3 = s["c"]
			if p_ok:   # the thermal drifts after you, but keeps its distance
				var keep := VULTURE_KEEP + float(u % 4) * 1.5
				var tc := Vector2(c.x - pp.x, c.z - pp.z)
				var dc := tc.length()
				if dc > keep + 1.0:
					var mv := minf(dc - keep, (4.0 if dc < 32.0 else 10.0) * dt)
					c.x -= tc.x / dc * mv
					c.z -= tc.y / dc * mv
					s["c"] = c
			var dirn := 1.0 if u % 2 == 0 else -1.0
			var a: float = float(s["a"]) + dirn * VULTURE_FLY_SPEED / VULTURE_RING * dt
			s["a"] = a
			var target := Vector2(c.x + cos(a) * VULTURE_RING - p.x, c.z + sin(a) * VULTURE_RING - p.z)
			var mx := VULTURE_FLY_SPEED * 1.6 * dt
			if target.length() > mx:
				target = target.normalized() * mx
			p.x += target.x
			p.z += target.y
			if dt > 0.0:
				em.vel[i] = Vector3(target.x, 0, target.y) / dt
			var want := VULTURE_HIGH + 0.6 * sin(_t * 1.3 + float(u))
			anim = A_GLIDE if alt > want - 0.8 else A_FLAP
			alt = move_toward(alt, want, (4.0 if want < alt else 3.0) * dt)
			roll = -dirn * 0.45
			if p_ok and d < VULTURE_LAND_RANGE and float(s["cd"]) <= 0.0 and not harmless:
				# you've come close: glide down to land a few metres from you
				var away := Vector2(p.x - pp.x, p.z - pp.z)
				away = away.normalized() if away.length() > 0.01 else Vector2(1, 0)
				away = away.rotated(randf_range(-0.6, 0.6))
				var lim := em.arena_half - 1.0
				var goal := Vector3(clampf(pp.x + away.x * VULTURE_LAND_DIST, -lim, lim), 0, clampf(pp.z + away.y * VULTURE_LAND_DIST, -lim, lim))
				goal.y = SwampWater.height_at(goal.x, goal.z)
				s["s"] = V_LAND
				s["t"] = 0.0
				s["from"] = Vector3(p.x, maxf(_floor_y(g, pp, d, p_ok) + alt, g + 0.45), p.z)
				s["goal"] = goal
				_play("screech", p, 0.7)
		p.y = maxf(_floor_y(g, pp, d, p_ok) + alt, g + 0.45)
		s["p"] = p
		em.pos[i] = p
	elif st == V_LAND:
		if not held:
			s["t"] = float(s["t"]) + dt
		var f := clampf(float(s["t"]) / VULTURE_LAND_TIME, 0.0, 1.0)
		var from: Vector3 = s["from"]
		var goal: Vector3 = s["goal"]
		var e := f * f * (3.0 - 2.0 * f)
		var gy := goal.y + VULTURE_STAND * sc
		p = Vector3(lerpf(from.x, goal.x, e), lerpf(from.y, gy, 1.0 - (1.0 - f) * (1.0 - f)), lerpf(from.z, goal.z, e))
		face = Vector2(goal.x - from.x, goal.z - from.z)
		anim = A_GLIDE if f < 0.55 else A_FLAP   # glides down, then flares and beats to land
		pitch = 0.3 if f < 0.55 else -0.55
		alt = p.y - SwampWater.height_at(p.x, p.z)
		s["p"] = p
		em.pos[i] = p
		if f >= 1.0:
			_touch_down(s, u, goal, sc)
			alt = VULTURE_STAND * sc
			em.pos[i] = goal
			em.vel[i] = Vector3.ZERO
			_burst(goal + Vector3(0, 0.2, 0), 0.8, Color(0.78, 0.66, 0.45))   # a puff of sand
			_play("flap", goal, 0.6)
			p = goal
			anim = A_STRUT
			st = V_GROUND
	elif st == V_GROUND:
		var to := Vector2(pp.x - p.x, pp.z - p.z)
		var d := to.length()
		anim = A_STRUT
		alt = VULTURE_STAND * sc
		if not held:
			s["t"] = float(s["t"]) + dt
			var spd := Vector2(em.vel[i].x, em.vel[i].z).length()
			s["ph"] = fmod(float(s["ph"]) + dt * spd * 0.95, 1.0)
			if p_ok and (d > VULTURE_FLEE or float(s["t"]) > VULTURE_GIVE_UP):
				_take_off(s, p, sc)
				st = V_TAKEOFF
				p = s["p"]
				alt = VULTURE_STAND * sc
				anim = A_FLAP
			elif p_ok and d < PECK_RANGE and absf(pp.y - p.y) < 1.8 and float(s["pcd"]) <= 0.0 and not harmless:
				_start_peck(s, i, p, to)
				st = V_PECK
				anim = A_PECK
	if st == V_PECK:
		p = s["p"]
		anim = A_PECK
		var aim: Vector3 = s["aim"]
		face = Vector2(aim.x, aim.z)
		if held:   # frozen / stunned: the peck's off
			_free_disc(s)
			s["s"] = V_GROUND
			s["pcd"] = PECK_CD * 0.5
		else:
			s["t"] = float(s["t"]) + dt
			var tt: float = s["t"]
			var disc := s["disc"] as GroundDisc
			if tt < PECK_WARN:
				pk = 0.7 * tt / PECK_WARN
				if disc != null:
					disc.set_fill(tt / PECK_WARN)
			else:
				if not bool(s["struck"]):
					s["struck"] = true
					_free_disc(s)
					_strike(i, s, pp, player)
				pk = minf(0.7 + 0.3 * (tt - PECK_WARN) / PECK_RECOVER, 1.0)
				if tt >= PECK_WARN + PECK_RECOVER:
					s["s"] = V_GROUND
					s["t"] = 0.0
					s["pcd"] = PECK_CD
		em.pos[i] = p   # stands its ground while it pecks
		em.vel[i] = Vector3.ZERO
		alt = VULTURE_STAND * sc
	elif st == V_TAKEOFF:
		var from: Vector3 = s["from"]
		if not held:
			s["t"] = float(s["t"]) + dt
			alt += VULTURE_CLIMB * dt
			var aw := Vector2(p.x - pp.x, p.z - pp.z)
			aw = aw.normalized() * 3.0 * dt if aw.length() > 0.01 else Vector2.ZERO
			p.x += aw.x
			p.z += aw.y
			if dt > 0.0:
				em.vel[i] = Vector3(aw.x, 0, aw.y) / dt
		anim = A_FLAP
		pitch = -0.35
		p.y = from.y + alt
		s["p"] = p
		em.pos[i] = p
		if alt >= VULTURE_HIGH - 0.5:   # back up on a thermal
			var g := SwampWater.height_at(p.x, p.z)
			alt = p.y - _floor_y(g, pp, Vector2(pp.x - p.x, pp.z - p.z).length(), p_ok)
			s["s"] = V_CIRCLE
			s["c"] = p
	_alt[u] = alt
	# draw it
	var grounded := st == V_GROUND or st == V_PECK
	var phase: float
	if grounded:
		vultures_grounded += 1
		phase = float(s["ph"])
	else:
		phase = float(s["ph"])
		if not held:
			phase = fmod(phase + dt * (3.2 if anim == A_FLAP else 0.4), 1.0)
			s["ph"] = phase
	var fw := face
	if fw.length() < 0.01:
		var vv := em.vel[i]
		fw = Vector2(vv.x, vv.z)
		if fw.length() < 0.2 and p_ok:
			fw = Vector2(pp.x - p.x, pp.z - p.z)
	var yaw := atan2(fw.x, fw.y)
	var xf: Transform3D
	if grounded:
		xf = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, p.y + VULTURE_STAND * sc, p.z)).scaled_local(Vector3.ONE * sc)
	else:
		xf = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), pitch) * Basis(Vector3(0, 0, 1), roll), p).scaled_local(Vector3.ONE * sc)
	_put(kind, xf, anim, phase, pk, code)


## Within reach: it stops, rears back, and the wedge its beak will strike fills on the ground.
func _start_peck(s: Dictionary, i: int, p: Vector3, to: Vector2) -> void:
	var aim := Vector3(to.x, 0, to.y)
	if aim.length() < 0.05:
		var vv := em.vel[i]
		aim = Vector3(vv.x, 0, vv.z) if Vector2(vv.x, vv.z).length() > 0.05 else Vector3.FORWARD
	aim = aim.normalized()
	s["s"] = V_PECK
	s["t"] = 0.0
	s["p"] = p
	s["aim"] = aim
	s["struck"] = false
	_free_disc(s)
	var d := GroundDisc.create(PECK_REACH, Color(MapBoss.WARN_COLOR, 0.55), false)
	d.set_arc(PECK_ARC)
	d.set_lift(0.15)
	d.set_fill(0.0)
	add_child(d)
	d.global_position = Vector3(p.x, SwampWater.height_at(p.x, p.z), p.z)
	d.rotation.y = atan2(-aim.x, -aim.z)
	s["disc"] = d
	pecks += 1
	_play("screech", p, 0.5, 1.3)


## The beak strikes: it hurts you if you're still in the wedge.
func _strike(i: int, s: Dictionary, pp: Vector3, player: Node3D) -> void:
	var o: Vector3 = s["p"]
	var aim: Vector3 = s["aim"]
	_play("peck", o, 0.9)
	if player == null or not _in_wedge(o, aim, pp):
		return
	var phased: Variant = player.get("phase")
	if phased is bool and phased:
		return   # phased (Ghast): untouchable
	peck_hits += 1
	var mult := 1.0
	var m := em.get_parent()
	if m != null and m.has_method("enemy_damage_mult"):
		mult = float(m.call("enemy_damage_mult"))
	var dmg := em.t_damage[EnemyManager.ZOMBIE] * PECK_DAMAGE * mult * em.hit_mult(i)
	if player.has_method("hurt"):
		player.call("hurt", dmg, em.type_names[EnemyManager.VULTURE])
	_burst(pp + Vector3(0, 0.9, 0), 0.7, Color(0.6, 0.08, 0.06))


## Is `at` (your feet) inside the peck's wedge from `o` along `aim`?
static func _in_wedge(o: Vector3, aim: Vector3, at: Vector3) -> bool:
	if absf(at.y - o.y) > 1.8:
		return false
	var rel := Vector2(at.x - o.x, at.z - o.z)
	var d := rel.length()
	if d < 0.7:
		return true
	if d > PECK_REACH + 0.3:
		return false
	return absf(rel.angle_to(Vector2(aim.x, aim.z))) <= PECK_ARC + 0.3 / d


## A mummy touching you curses you: slowed for a moment (once a second per mummy).
func _try_curse(i: int, pp: Vector3, player: Node3D) -> void:
	var p := em.pos[i]
	var reach := em.t_radius[EnemyManager.MUMMY] * em.sz[i] + 0.75
	if Vector2(pp.x - p.x, pp.z - p.z).length() > reach or absf(pp.y - p.y) > 1.8:
		return
	var u := em.uid[i]
	if float(_curse_cd.get(u, 0.0)) > 0.0:
		return
	_curse_cd[u] = 1.0
	if player.has_method("apply_slow"):
		player.apply_slow(CURSE_SLOW, CURSE_TIME)
	curses += 1
	_burst(pp + Vector3(0, 1.0, 0), 1.2, Color(0.55, 0.25, 0.8))
	_play("curse", pp, 0.7)


func _tick_corpses(dt: float) -> void:
	var i := 0
	while i < _c_n:
		_c_age[i] += dt
		var age := _c_age[i]
		if age > CORPSE_LIFE:
			var last := _c_n - 1
			_c_kind[i] = _c_kind[last]
			_c_pos[i] = _c_pos[last]
			_c_yaw[i] = _c_yaw[last]
			_c_scale[i] = _c_scale[last]
			_c_age[i] = _c_age[last]
			_c_from[i] = _c_from[last]
			_c_n -= 1
			continue
		var p := _c_pos[i]
		var g := SwampWater.height_at(p.x, p.z)
		var kind := _c_kind[i]
		var sink := clampf((age - (CORPSE_LIFE - 1.0)) / 1.0, 0.0, 1.0)
		var xf: Transform3D
		if kind == M_VULTURE and _c_from[i] < 0.6:
			# shot on the ground: keels over onto its side, wings limp
			var f := clampf(age / 0.35, 0.0, 1.0)
			f = f * f
			var side := 1.0 if (int(_c_yaw[i] * 100.0) & 1) == 0 else -1.0
			xf = Transform3D(Basis(Vector3.UP, _c_yaw[i]) * Basis(Vector3(0, 0, 1), side * 1.4 * f), Vector3(p.x, g + (VULTURE_STAND - 0.2 * f) * _c_scale[i] - sink * 0.5, p.z)).scaled_local(Vector3.ONE * _c_scale[i])
			_put(kind, xf, 0.75, 0.0, 0.0, 0.0)
		elif kind == M_VULTURE:
			# tumbles out of the sky, wings limp, and lands on its back
			var fall_t := sqrt(2.0 * maxf(_c_from[i], 0.0) / 14.0) + 0.05
			var f := clampf(age / fall_t, 0.0, 1.0)
			var y := g + 0.15 + maxf(_c_from[i], 0.0) * (1.0 - f * f)
			var spin := age * 9.0 * (1.0 - f) + f * PI * 0.85
			xf = Transform3D(Basis(Vector3.UP, _c_yaw[i] + age * 2.0 * (1.0 - f)) * Basis(Vector3(0, 0, 1), spin), Vector3(p.x, y - sink * 0.5, p.z)).scaled_local(Vector3.ONE * _c_scale[i])
			_put(kind, xf, 0.75, 0.0, 0.0, 0.0)
		else:
			var fall := clampf(age / 0.55, 0.0, 1.0)
			fall = fall * fall
			var dust := 1.0 - sink * (0.6 if kind == M_MUMMY or kind == M_PRIEST else 0.0)   # mummies crumble away faster
			xf = Transform3D(Basis(Vector3.UP, _c_yaw[i]), Vector3(p.x, g - sink * 0.7 - (1.0 - dust) * 0.3, p.z)).scaled_local(Vector3(1, dust, 1) * _c_scale[i])
			_put(kind, xf, A_DIE, 0.0, fall, 0.0)
		i += 1


## Now and then a nearby zombie groans, a mummy rasps, a vulture screeches or beats its wings.
func _voices(dt: float, pp: Vector3, p_ok: bool) -> void:
	_voice_t -= dt
	if _voice_t > 0.0 or not p_ok or em.count == 0:
		return
	_voice_t = randf_range(0.7, 1.8)
	for tries in 6:
		var i := randi() % em.count
		var t := em.typ[i]
		if not owns(t) or em.dead[i] or em.pos[i].distance_to(pp) > 28.0:
			continue
		match t:
			EnemyManager.MUMMY: _play("rasp", em.pos[i], 0.8)
			EnemyManager.VULTURE: _play("screech" if randf() < 0.6 else "flap", em.pos[i], 0.7)
			EnemyManager.ZOMBIE_BRUTE: _play("groan", em.pos[i], 1.0, 0.7)
			_: _play("groan", em.pos[i], 0.8)
		return


func _play(kind: String, at: Vector3, volume: float, pitch := 1.0) -> void:
	var list: Array = _streams.get(kind, [])
	if list.is_empty():
		return
	var a := _sfx[randi() % _sfx.size()]
	if a.playing and randf() < 0.5:
		return
	a.stream = list[randi() % list.size()]
	a.volume_db = linear_to_db(volume) - 3.0
	a.pitch_scale = pitch * randf_range(0.88, 1.12)
	a.global_position = at
	a.play()


func corpse_count() -> int:
	return _c_n


func drawn(kind: int) -> int:
	return _counts[kind] if kind < _counts.size() else 0


# ------------------------------------------------------------------ models

static func _mat(gait: float, eye: Color, power: float, hip_y := 0.92, sh_y := 1.42, head_y := 1.52, sh_x := 0.23) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = HUMAN_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("gait", gait)
	m.set_shader_parameter("eye_color", eye)
	m.set_shader_parameter("eye_power", power)
	m.set_shader_parameter("hip_y", hip_y)
	m.set_shader_parameter("sh_y", sh_y)
	m.set_shader_parameter("head_y", head_y)
	m.set_shader_parameter("sh_x", sh_x)
	return m


static func build_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	out.append(_zombie(rng, "zombie", _mat(0.0, Color(0.85, 1.0, 0.35), 1.6)))
	out.append(_zombie(rng, "runner", _mat(1.0, Color(1.0, 0.85, 0.3), 1.6)))
	out.append(_zombie(rng, "brute", _mat(2.0, Color(1.0, 0.4, 0.2), 1.8, 0.95, 1.5, 1.66, 0.36)))
	out.append(_zombie(rng, "plague", _mat(0.0, Color(0.5, 1.0, 0.2), 2.6)))
	out.append(_mummy(rng, false, _mat(3.0, Color(1.0, 0.75, 0.2), 3.0)))
	out.append(_mummy(rng, true, _mat(3.0, Color(0.35, 0.65, 1.0), 3.5)))
	var vs := Shader.new()
	vs.code = VULTURE_SHADER
	var vm := ShaderMaterial.new()
	vm.shader = vs
	out.append(_vulture(rng, vm))
	return out


## For tools/render_desert.gd.
static func preview_meshes() -> Array[Mesh]:
	return build_meshes()


static func _l(c: Color, limb: int) -> Color:
	return Color(c.r, c.g, c.b, limb / 8.0)


## A zombie (facing +Z, feet at the origin, HEIGHT tall). `kind`: zombie, runner, brute, plague.
static func _zombie(rng: RandomNumberGenerator, kind: String, mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var brute := kind == "brute"
	var runner := kind == "runner"
	var plague := kind == "plague"
	var skin := SKIN.lerp(Color(0.62, 0.62, 0.52), 0.35) if runner else (SKIN.darkened(0.1) if brute else SKIN)
	if plague:
		skin = Color(0.5, 0.55, 0.32)
	var shirt := BLUE_SHIRT if runner else SHIRT
	var hip_y := 0.95 if brute else 0.92
	var sh_y := 1.5 if brute else 1.42
	var head_y := 1.66 if brute else 1.52
	var sh_x := 0.36 if brute else 0.23
	var hw := 0.2 if brute else 0.12           # hip half width
	var belly := 0.3 if brute else (0.2 if plague else 0.15)
	# legs: thigh, shin, foot (one bare, one in a rotten shoe); ragged trouser legs
	for side in [1.0, -1.0]:
		var limb := 1 if side > 0 else 2
		var lx: float = side * hw
		var knee := Vector3(lx * 1.05, hip_y * 0.52, 0.03)
		var foot := Vector3(lx * 1.08, 0.07, 0.0)
		var tr := 0.085 if brute else (0.055 if runner else 0.065)
		mb.limb(Vector3(lx, hip_y, 0), knee, tr * 1.25, tr, _l(TROUSERS if not runner else skin, limb), 7)
		mb.limb(knee, foot, tr, tr * 0.8, _l(skin.darkened(0.08), limb), 7)
		if not runner:   # trouser leg down to mid-shin, torn
			mb.limb(knee + Vector3(0, 0.02, 0), knee.lerp(foot, 0.45), tr * 1.25, tr * 1.3, _l(TROUSERS, limb), 7)
			for f in 3:
				mb.add(MeshBuilder.box(Vector3(0.05, 0.12, 0.02)), Transform3D(Basis(Vector3.UP, f * 2.1), knee.lerp(foot, 0.5) + Vector3(cos(f * 2.1) * tr * 1.2, -0.04, sin(f * 2.1) * tr * 1.2)), _l(TROUSERS.darkened(0.15), 7))
		mb.add(MeshBuilder.box(Vector3(tr * 1.6, 0.06, 0.24)), Transform3D(Basis(), foot + Vector3(0, -0.03, 0.06)), _l(skin.darkened(0.25) if side > 0 else Color(0.2, 0.15, 0.1), limb))
	# pelvis, belly, chest; a torn shirt (the runner is bare-chested, his ribs showing)
	mb.add(MeshBuilder.sphere(0.18 if not brute else 0.28, 8, 6), Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 0.85)), Vector3(0, hip_y + 0.02, 0)), _l(TROUSERS, 0))
	var chest_y := (hip_y + sh_y) * 0.5 + 0.05
	var torso_c := shirt if not runner else skin
	mb.add(MeshBuilder.sphere(belly, 10, 7), Transform3D(Basis.from_scale(Vector3(1.15, 1.0, 1.0)), Vector3(0, hip_y + 0.17, 0.05 + belly * 0.3)), _l(torso_c, 0))
	mb.add(MeshBuilder.cyl(sh_x * 0.85, sh_x * 0.72, sh_y - hip_y - 0.05, 10), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.7)), Vector3(0, chest_y, 0)), _l(torso_c, 0))
	if runner:
		for r in 5:   # ribs
			mb.add(MeshBuilder.cyl(0.155, 0.155, 0.02, 12), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.75)), Vector3(0, chest_y + 0.02 + r * 0.05, 0.01)), _l(BONE.darkened(0.1), 0))
		mb.add(MeshBuilder.box(Vector3(0.36, 0.22, 0.02)), Transform3D(Basis(), Vector3(0, hip_y + 0.12, 0.12)), _l(BLOOD, 0))
	else:
		# rents in the shirt: dark flaps and a hole with ribs behind it
		mb.add(MeshBuilder.box(Vector3(0.14, 0.12, 0.02)), Transform3D(Basis(Vector3(0, 0, 1), 0.3), Vector3(0.06, chest_y + 0.05, sh_x * 0.62)), _l(ROT, 0))
		for r in 3:
			mb.add(MeshBuilder.box(Vector3(0.11, 0.015, 0.015)), Transform3D(Basis(), Vector3(0.06, chest_y + 0.01 + r * 0.035, sh_x * 0.65)), _l(BONE, 0))
		for f in 4:   # tatters hanging from the hem
			mb.add(MeshBuilder.box(Vector3(0.07, 0.16, 0.02)), Transform3D(Basis(Vector3.UP, f * 1.6), Vector3(cos(f * 1.6) * sh_x * 0.8, hip_y + 0.04, sin(f * 1.6) * sh_x * 0.6)), _l(shirt.darkened(0.15), 7))
		mb.add(MeshBuilder.box(Vector3(0.1, 0.25, 0.02)), Transform3D(Basis(Vector3(0, 0, 1), -0.3), Vector3(-0.1, chest_y - 0.05, sh_x * 0.6)), _l(BLOOD, 0))
	if brute:   # overall straps and a bib
		for sd in [-1.0, 1.0]:
			mb.limb(Vector3(sd * 0.18, sh_y, 0.12), Vector3(sd * 0.15, chest_y - 0.1, 0.22), 0.025, 0.025, _l(Color(0.25, 0.3, 0.38), 0), 4)
		mb.add(MeshBuilder.box(Vector3(0.4, 0.3, 0.04)), Transform3D(Basis(), Vector3(0, chest_y - 0.12, 0.28)), _l(Color(0.25, 0.3, 0.38), 0))
	if plague:   # swollen, festering boils that glow
		for k in 9:
			var a := rng.randf() * TAU
			var y := rng.randf_range(hip_y + 0.05, sh_y)
			mb.add(MeshBuilder.sphere(rng.randf_range(0.03, 0.06), 6, 4), Transform3D(Basis(), Vector3(cos(a) * sh_x * 0.85, y, sin(a) * sh_x * 0.62 + 0.03)), _l(Color(0.7, 1.0, 0.3), 6))
		mb.add(MeshBuilder.sphere(0.2, 8, 6), Transform3D(Basis.from_scale(Vector3(1.2, 1.0, 1.1)), Vector3(0.05, chest_y, 0.1)), _l(skin.lerp(Color(0.6, 0.5, 0.2), 0.3), 0))
	# shoulders, arms, hands with long nails (left arm torn to the bone on the shambler)
	for side in [1.0, -1.0]:
		var limb := 3 if side > 0 else 4
		var sx: float = side * sh_x
		var ar := 0.075 if brute else (0.045 if runner else 0.05)
		var elbow := Vector3(sx * 1.08, sh_y - 0.3, 0.02)
		var hand := Vector3(sx * 1.05, sh_y - 0.58, 0.06)
		mb.add(MeshBuilder.sphere(ar * 1.5, 8, 5), Transform3D(Basis(), Vector3(sx, sh_y, 0)), _l(torso_c, limb))
		mb.limb(Vector3(sx, sh_y, 0), elbow, ar * 1.2, ar, _l(torso_c if not runner else skin, limb), 7)
		var bare: bool = kind == "zombie" and side > 0
		mb.limb(elbow, hand, ar, ar * 0.8, _l(BONE if bare else skin, limb), 7)
		if bare:
			mb.limb(elbow, elbow.lerp(hand, 0.4), ar * 1.1, ar * 0.95, _l(ROT, limb), 6)
		mb.add(MeshBuilder.sphere(ar * 1.15, 7, 5), Transform3D(Basis.from_scale(Vector3(0.9, 1.2, 0.7)), hand + Vector3(0, -0.04, 0)), _l(skin.darkened(0.1), limb))
		for f in 3:
			mb.limb(hand + Vector3(side * (f - 1) * 0.018, -0.07, 0.01), hand + Vector3(side * (f - 1) * 0.022, -0.15, 0.04), 0.01, 0.006, _l(skin.darkened(0.2), limb), 3)
	# neck and head: sunken cheeks, a slack jaw with teeth, wisps of hair, glowing eyes
	mb.limb(Vector3(0, sh_y - 0.02, 0), Vector3(0, head_y, 0.02), 0.05 if not brute else 0.09, 0.045, _l(skin, 5), 6)
	var hs := 0.85 if brute else 1.0
	var hc := Vector3(0, head_y + 0.11 * hs, 0.03)
	mb.add(MeshBuilder.sphere(0.115 * hs, 10, 7), Transform3D(Basis.from_scale(Vector3(0.92, 1.08, 1.0)), hc), _l(skin, 5))
	mb.add(MeshBuilder.sphere(0.07 * hs, 8, 5), Transform3D(Basis.from_scale(Vector3(1.1, 0.7, 1.0)), hc + Vector3(0, -0.1 * hs, 0.05)), _l(skin.darkened(0.12), 5))   # slack jaw
	mb.add(MeshBuilder.box(Vector3(0.09, 0.02, 0.02) * hs), Transform3D(Basis(), hc + Vector3(0, -0.06 * hs, 0.105 * hs)), _l(BONE, 5))   # teeth
	mb.add(MeshBuilder.box(Vector3(0.07, 0.04, 0.02) * hs), Transform3D(Basis(), hc + Vector3(0, -0.085 * hs, 0.1 * hs)), _l(Color(0.12, 0.04, 0.04), 5))   # the gaping mouth
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.sphere(0.03 * hs, 6, 4), Transform3D(Basis(), hc + Vector3(sd * 0.042 * hs, 0.015, 0.098 * hs)), _l(Color(0.05, 0.05, 0.04), 5))   # sockets
		mb.add(MeshBuilder.sphere(0.017 * hs, 6, 4), Transform3D(Basis(), hc + Vector3(sd * 0.042 * hs, 0.015, 0.108 * hs)), _l(Color(0.9, 1.0, 0.6), 6))   # eyes
	mb.add(MeshBuilder.sphere(0.04 * hs, 6, 4), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.0)), hc + Vector3(0.05, 0.05, 0.08)), _l(ROT, 5))   # a rotten patch
	for k in 6:   # wisps of hair
		var a := rng.randf() * TAU
		mb.limb(hc + Vector3(cos(a) * 0.06, 0.09, sin(a) * 0.06 - 0.02), hc + Vector3(cos(a) * 0.1, 0.13, sin(a) * 0.1 - 0.05), 0.008, 0.003, _l(Color(0.15, 0.12, 0.08), 5), 3)
	return mb.commit(mat)


## A mummy, bound in bandages: every limb and the head are wound with tilted wraps of linen,
## loose ends trailing; one eye burns through a gap. The priest wears a gold nemes and collar.
static func _mummy(rng: RandomNumberGenerator, priest: bool, mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var hip_y := 0.92
	var sh_y := 1.42
	var head_y := 1.52
	var wrap := func(a: Vector3, b: Vector3, r: float, limb: int, n: int) -> void:
		mb.limb(a, b, r * 0.92, r * 0.88, _l(WRAP_DARK, limb), 7)
		for k in n:
			var t := (k + 0.5) / n
			var p := a.lerp(b, t)
			var axis := (b - a).normalized()
			var side := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
			var x := side.cross(axis).normalized()
			var basis := Basis(x, axis, x.cross(axis)) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.35, 0.35))
			var c := WRAP.darkened(rng.randf_range(0.0, 0.18)) if k % 3 else WRAP.lightened(0.05)
			mb.add(MeshBuilder.cyl(r * 1.02, r * 1.05, (b - a).length() / n * 1.15, 8), Transform3D(basis, p), _l(c, limb))
	for side in [1.0, -1.0]:
		var limb := 1 if side > 0 else 2
		var knee := Vector3(side * 0.12, 0.5, 0.02)
		wrap.call(Vector3(side * 0.12, hip_y, 0), knee, 0.07, limb, 5)
		wrap.call(knee, Vector3(side * 0.13, 0.08, 0.0), 0.06, limb, 5)
		mb.add(MeshBuilder.box(Vector3(0.1, 0.07, 0.24)), Transform3D(Basis(), Vector3(side * 0.13, 0.035, 0.06)), _l(WRAP_DARK, limb))
	wrap.call(Vector3(0, hip_y - 0.05, 0), Vector3(0, sh_y, 0), 0.19, 0, 9)
	mb.add(MeshBuilder.sphere(0.2, 10, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 0.75)), Vector3(0, hip_y, 0)), _l(WRAP_DARK, 0))
	for side in [1.0, -1.0]:
		var limb := 3 if side > 0 else 4
		var elbow := Vector3(side * 0.25, sh_y - 0.3, 0.02)
		var hand := Vector3(side * 0.25, sh_y - 0.58, 0.05)
		mb.add(MeshBuilder.sphere(0.08, 8, 5), Transform3D(Basis(), Vector3(side * 0.23, sh_y, 0)), _l(WRAP, limb))
		wrap.call(Vector3(side * 0.23, sh_y, 0), elbow, 0.055, limb, 4)
		wrap.call(elbow, hand, 0.048, limb, 4)
		mb.add(MeshBuilder.sphere(0.055, 7, 5), Transform3D(Basis.from_scale(Vector3(0.9, 1.2, 0.7)), hand + Vector3(0, -0.04, 0)), _l(WRAP_DARK, limb))
		for k in 2:   # loose bandage ends trailing from the arm
			var at := elbow.lerp(hand, 0.3 + k * 0.4)
			mb.add(MeshBuilder.box(Vector3(0.035, 0.32, 0.01)), Transform3D(Basis(Vector3(1, 0, 0), 0.2), at + Vector3(side * 0.05, -0.14, -0.03)), _l(WRAP.darkened(0.1), 7))
	for k in 5:   # strips hanging from the waist
		var a := TAU * k / 5.0 + 0.3
		mb.add(MeshBuilder.box(Vector3(0.05, 0.4, 0.012)), Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 0.2, hip_y - 0.2, sin(a) * 0.16)), _l(WRAP.darkened(0.08 * (k % 2)), 7))
	# head: wound round and round at different angles; a gap with one burning eye
	var hc := Vector3(0, head_y + 0.12, 0.03)
	mb.limb(Vector3(0, sh_y, 0), hc, 0.06, 0.06, _l(WRAP_DARK, 5), 6)
	mb.add(MeshBuilder.sphere(0.12, 10, 7), Transform3D(Basis.from_scale(Vector3(0.92, 1.1, 1.0)), hc), _l(WRAP_DARK, 5))
	for k in 6:
		var b := Basis(Vector3(1, 0, 0), rng.randf_range(-0.6, 0.6)) * Basis(Vector3(0, 0, 1), rng.randf_range(-0.4, 0.4))
		mb.add(MeshBuilder.cyl(0.125, 0.125, 0.045, 12), Transform3D(b.scaled(Vector3(0.95, 1.0, 1.05)), hc + Vector3(0, -0.08 + k * 0.035, 0)), _l(WRAP.darkened(rng.randf_range(0.0, 0.15)), 5))
	mb.add(MeshBuilder.box(Vector3(0.1, 0.03, 0.02)), Transform3D(Basis(Vector3(0, 0, 1), 0.15), hc + Vector3(0.0, 0.015, 0.118)), _l(Color(0.05, 0.04, 0.03), 5))   # the gap
	mb.add(MeshBuilder.sphere(0.02, 6, 4), Transform3D(Basis(), hc + Vector3(0.035, 0.018, 0.122)), _l(Color(1, 0.8, 0.3), 6))   # one eye...
	mb.add(MeshBuilder.sphere(0.014, 6, 4), Transform3D(Basis(), hc + Vector3(-0.04, 0.012, 0.12)), _l(Color(1, 0.8, 0.3), 6))   # ...and the other, half hidden
	if priest:
		# gold-and-lapis nemes, a broad collar, a crook in the left hand
		mb.add(MeshBuilder.sphere(0.15, 12, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 1.05)), hc + Vector3(0, 0.1, -0.02)), _l(GOLD, 5))   # the crown of the headcloth
		for k in 7:   # striped bands round the sides and back, open at the face
			var y := hc.y + 0.08 - k * 0.045
			var r := 0.14 + k * 0.012
			var gap := 0.0 if k < 2 else 0.95
			for q in 10:
				var th := gap + (TAU - 2.0 * gap) * (q + 0.5) / 10.0
				var seg := 2.0 * r * sin((TAU - 2.0 * gap) / 20.0) + 0.01
				mb.add(MeshBuilder.box(Vector3(seg, 0.045, 0.02)), Transform3D(Basis(Vector3.UP, th), Vector3(sin(th) * r, y, hc.z - 0.02 + cos(th) * r)), _l(GOLD if k % 2 == 0 else LAPIS, 5))
		for sd in [-1.0, 1.0]:
			mb.add(MeshBuilder.box(Vector3(0.09, 0.3, 0.04)), Transform3D(Basis(), Vector3(sd * 0.14, sh_y - 0.06, 0.1)), _l(GOLD, 0))
		for r in 3:
			mb.add(MeshBuilder.cyl(0.26 - r * 0.02, 0.27 - r * 0.02, 0.04, 16), Transform3D(Basis(Vector3(1, 0, 0), 0.2), Vector3(0, sh_y - 0.03 - r * 0.045, 0.02)), _l(GOLD if r % 2 == 0 else LAPIS, 0))
		var hand := Vector3(0.25, sh_y - 0.58, 0.05)
		mb.limb(hand + Vector3(0, -0.25, 0.02), hand + Vector3(0, 0.45, 0.02), 0.015, 0.015, _l(GOLD, 3), 5)
		for k in 4:
			var a := k * 0.7
			mb.add(MeshBuilder.sphere(0.022, 6, 4), Transform3D(Basis(), hand + Vector3(0, 0.45 + sin(a) * 0.07, 0.02 + (1.0 - cos(a)) * 0.07)), _l(GOLD, 3))
	return mb.commit(mat)


## A vulture: dark wings 2.6 m across with fingered primaries, a white ruff, a bald pink head
## and hooked beak, a short tail fan, talons. Faces +Z, origin at the body's centre.
static func _vulture(rng: RandomNumberGenerator, mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var dark := Color(0.17, 0.13, 0.11)
	var brown := Color(0.32, 0.24, 0.17)
	mb.add(MeshBuilder.sphere(0.24, 12, 8), Transform3D(Basis.from_scale(Vector3(0.9, 0.75, 1.7)), Vector3.ZERO), _l(brown, 0))
	mb.add(MeshBuilder.sphere(0.16, 10, 6), Transform3D(Basis.from_scale(Vector3(1.2, 0.8, 1.0)), Vector3(0, 0.07, 0.3)), _l(Color(0.92, 0.9, 0.85), 0))   # the ruff
	# neck, bald head, beak
	mb.limb(Vector3(0, 0.08, 0.32), Vector3(0, 0.12, 0.55), 0.05, 0.04, _l(Color(0.85, 0.55, 0.5), 5), 6)
	mb.add(MeshBuilder.sphere(0.075, 8, 6), Transform3D(Basis.from_scale(Vector3(0.9, 0.9, 1.2)), Vector3(0, 0.13, 0.6)), _l(Color(0.9, 0.5, 0.45), 5))
	mb.add(MeshBuilder.cone(0.035, 0.12, 6), Transform3D(Basis(Vector3(1, 0, 0), PI / 2 + 0.35), Vector3(0, 0.11, 0.71)), _l(Color(0.85, 0.82, 0.7), 5))
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.sphere(0.014, 5, 4), Transform3D(Basis(), Vector3(sd * 0.04, 0.15, 0.64)), _l(Color(1, 0.6, 0.1), 6))
	# wings: inner panel (shoulder to wrist) and outer panel with five fingered primaries
	for sd in [-1.0, 1.0]:
		var inner := 1 if sd > 0 else 2
		var outer := 3 if sd > 0 else 4
		mb.add(MeshBuilder.box(Vector3(0.7, 0.03, 0.42)), Transform3D(Basis(), Vector3(sd * 0.5, 0.06, 0.02)), _l(dark, inner))
		mb.add(MeshBuilder.box(Vector3(0.7, 0.035, 0.18)), Transform3D(Basis(), Vector3(sd * 0.5, 0.075, 0.12)), _l(brown, inner))   # coverts
		mb.add(MeshBuilder.box(Vector3(0.36, 0.03, 0.34)), Transform3D(Basis(), Vector3(sd * 1.0, 0.06, -0.01)), _l(dark, outer))
		for f in 5:
			var z := 0.1 - f * 0.07
			mb.add(MeshBuilder.box(Vector3(0.32, 0.015, 0.05)), Transform3D(Basis(Vector3.UP, sd * (0.15 - f * 0.12)), Vector3(sd * (1.3 + f * 0.01), 0.06, z)), _l(dark.darkened(0.2), outer))
	# tail fan and tucked legs with talons
	for f in 5:
		mb.add(MeshBuilder.box(Vector3(0.06, 0.015, 0.3)), Transform3D(Basis(Vector3.UP, (f - 2) * 0.18), Vector3((f - 2) * 0.04, 0.0, -0.45)), _l(dark, 7))
	for sd in [-1.0, 1.0]:
		mb.limb(Vector3(sd * 0.08, -0.12, 0.0), Vector3(sd * 0.09, -0.22, -0.15), 0.025, 0.02, _l(Color(0.7, 0.6, 0.5), 7), 4)
		for t in 3:
			mb.limb(Vector3(sd * 0.09, -0.22, -0.15), Vector3(sd * (0.06 + t * 0.03), -0.26, -0.08), 0.01, 0.004, _l(Color(0.15, 0.12, 0.1), 7), 3)
	return mb.commit(mat)
