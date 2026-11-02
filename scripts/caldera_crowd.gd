class_name CalderaCrowd
extends Node3D
## The Ashen Caldera's creatures (EnemyManager.MAGMA_IMP .. LAVA_SLUG). They live in EnemyManager's
## rows like every goblin (no goblins come to the Caldera: EnemyManager.type_remap turns every
## goblin spawn into its counterpart here); this draws them, gives them their extras and plays
## their deaths:
##
##   MAGMA_IMP       (the goblins' place) a small hunched imp of cracked black rock with lava
##                   glowing in its seams, curling horns, ember eyes and a spade tail; it scuttles
##                   fast, in packs (imps spawned close together join up). Dies bursting into a
##                   puff of embers and a scatter of rock chunks that cool from orange to black.
##     epic          the EMBER FIEND: bigger, seams blazing, a mane of flame down its back.
##   CINDER_BAT      (the scamps' place) a bat of smouldering cinders with glowing wing veins and
##                   a tail of flame: it flies loose figure-eights above you, then dives at you and
##                   climbs away again, leaving a trail of embers. Near you it flies at YOUR
##                   height (so it reaches you on top of a column); its crowd row is at its real
##                   height, so every weapon hits it. Dies tumbling out of the air in a burst of
##                   sparks.
##   OBSIDIAN_GOLEM  (the brutes' place) slow and huge, a body of glassy black obsidian with a
##                   lava core showing through the cracks; every heavy step shakes the ground near
##                   you. Dies SHATTERING into a spray of glass shards.
##     epic          the MOLTEN GOLEM: glowing white-hot through and through.
##   LAVA_SLUG       slow and soft, crusted on top, glowing underneath, eye stalks waving; it
##                   leaves a TRAIL of burning lava that hurts you for TRAIL_LIFE seconds (enemies
##                   don't mind it). Dies melting into a cooling puddle.
##
## Models are built in code and animated in the vertex shader per instance, like the Desert's
## (INSTANCE_CUSTOM: r = animation, g = phase, b = lean / fall / melt, a = the goblins' burn /
## flash / epic / frozen / chill / shadow code).

const STRIDE := 20
const CORPSE_MAX := 300
const CAP := EnemyManager.MAX + CORPSE_MAX
const IMP_HEIGHT := 0.95
const GOLEM_HEIGHT := 1.65          # at scale 1 (the golem's type scale makes it ~2.6 m)
const SLUG_HEIGHT := 0.55
const BAT_HEIGHT := 0.6
const PACK_TIME := 1.6              # imps spawned within this long of each other join one pack...
const PACK_SIZE := 5                # ...of up to this many
const RISE_TIME := 0.9              # imps clawing up out of a crack (eruption swarms, summons)
const BAT_CYCLE := 6.0              # seconds: figure-eights, then a dive
const BAT_LOOP := 0.62              # share of the cycle spent looping above
const BAT_HIGH := 4.6
const BAT_LOW := 0.55
const BAT_LOOP_R := 9.0
const TRAIL_EVERY := 0.45           # slugs drop a blob of lava every this many seconds (about a metre)...
const TRAIL_LIFE := 4.0             # ...that burns for this long
const TRAIL_RADIUS := 0.85
const TRAIL_TICK := 0.5
const TRAIL_DAMAGE := 5.0
const TRAIL_MAX := 320
const EMBER_MAX := 400
const DEBRIS_MAX := 420
const A_WALK := 0.0
const A_CLAW := 0.25
const A_DIE := 0.75
const A_FLAP := 0.0
const A_GLIDE := 0.25
const A_DIVE := 0.5

enum { M_IMP, M_FIEND, M_BAT, M_GOLEM, M_MOLTEN, M_SLUG }

const ROCK := Color(0.085, 0.075, 0.075)
const ROCK2 := Color(0.13, 0.1, 0.09)
const HORN := Color(0.58, 0.52, 0.44)
const OBSIDIAN := Color(0.06, 0.055, 0.075)
const CRUST := Color(0.14, 0.08, 0.06)

const CREATURE_SHADER := """
shader_type spatial;
// COLOR.a of a vertex = its limb: 0 body, 1 L leg, 2 R leg, 3 L arm, 4 R arm, 5 head, 6 glow
// (eyes, the lava core, flames), 7 tail / mane (sways, flickers). INSTANCE_CUSTOM: r = animation
// (0 walk, .25 claw / slam, .75 dying), g = phase, b = lean / fall (dying), a = status code.
uniform vec3 eye_color : source_color = vec3(1.0, 0.6, 0.15);
uniform float eye_power = 3.0;
uniform float hip_y = 0.42;
uniform float hip_x = 0.1;
uniform float sh_y = 0.7;
uniform float sh_x = 0.2;
uniform float head_y = 0.8;
uniform float gait = 0.0;        // 0 imp scuttle, 1 golem lumber
uniform float seam = 1.0;        // how brightly the lava glows in the cracks
uniform float glass = 0.0;       // 1: obsidian (glossy, iridescent)
uniform float hot = 0.0;         // 1: molten through and through
uniform float crack_scale = 9.0;
varying float burn;
varying float flash;
varying float epic;
varying float frozen;
varying float chill;
varying float shadow;
varying float glow;
varying float flame;
varying vec3 lpos;

mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_z(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }
mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float cracks(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	float d1 = 8.0; float d2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 r = o + vec3(hash(i + o), hash(i + o + 11.1), hash(i + o + 23.7)) - f;
				float dd = dot(r, r);
				if (dd < d1) { d2 = d1; d1 = dd; } else if (dd < d2) { d2 = dd; }
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void vertex() {
	lpos = VERTEX;
	int limb = int(COLOR.a * 8.0 + 0.5);
	float anim = INSTANCE_CUSTOM.r;
	float ph = INSTANCE_CUSTOM.g * 6.2831853;
	float lean = INSTANCE_CUSTOM.b;
	float walk = 1.0 - step(0.125, anim);
	float claw = step(0.125, anim) * (1.0 - step(0.625, anim));
	float die = step(0.625, anim);
	float golem = step(0.5, gait);
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	vec3 hip_l = vec3(hip_x, hip_y, 0.0);
	vec3 hip_r = vec3(-hip_x, hip_y, 0.0);
	vec3 sh_l = vec3(sh_x, sh_y, 0.0);
	vec3 sh_r = vec3(-sh_x, sh_y, 0.0);
	float stride = mix(0.85, 0.42, golem);
	float swing = sin(ph) * stride * walk;
	mat3 R = mat3(1.0);
	vec3 piv = vec3(0.0);
	if (limb == 1) { piv = hip_l; R = rot_x(swing - die * 0.6); }
	if (limb == 2) { piv = hip_r; R = rot_x(-swing - die * 0.3); }
	if (limb == 3 || limb == 4) {
		float side = limb == 3 ? 1.0 : -1.0;
		// imps: arms low and swinging as they scuttle, raking at you; golems: a heavy swing and
		// a two-fisted overhead slam
		float a = mix(-0.35 - side * swing * 0.9, -side * swing * 0.5 - 0.1, golem);
		float rake = -1.6 + sin(ph + (side > 0.0 ? 0.0 : 3.14)) * 1.0;
		float slam = -2.9 + (sin(ph) * 0.5 + 0.5) * 2.5;
		a = mix(a, mix(rake, slam, golem), claw);
		a = mix(a, -2.6, die * clamp(lean * 1.5, 0.0, 1.0));
		piv = side > 0.0 ? sh_l : sh_r;
		R = rot_z(side * (0.15 + claw * 0.2 * (1.0 - golem) + die * 0.5)) * rot_x(a);
	}
	if (limb == 5) {
		piv = vec3(0.0, head_y, 0.0);
		R = rot_x(-0.2 * (1.0 - golem) + sin(ph * 2.0) * 0.06 * walk) * rot_y(sin(ph * 0.5) * 0.2 * (1.0 - golem));
	}
	if (limb == 6 && VERTEX.y > head_y - 0.05 && gait < 0.5) {   // the head's eyes follow it
		piv = vec3(0.0, head_y, 0.0);
		R = rot_x(-0.2 + sin(ph * 2.0) * 0.06 * walk) * rot_y(sin(ph * 0.5) * 0.2);
	}
	v = piv + R * (v - piv);
	n = R * n;
	flame = 0.0;
	if (limb == 7) {   // the tail lashes; flames (epic manes) flicker upward
		float w = clamp(-VERTEX.z * 2.0, 0.0, 1.5) + clamp((VERTEX.y - sh_y) * 2.0, 0.0, 1.0);
		v.x += sin(TIME * 7.0 + VERTEX.z * 6.0 + ph) * 0.07 * w;
		v.y += sin(TIME * 5.0 + VERTEX.z * 4.0) * 0.03 * w;
	}
	// the whole body: imps hunch forward and bob as they scuttle; golems rock side to side
	float sway = sin(ph) * mix(0.05, 0.09, golem) * walk;
	float pitch = mix(0.32, 0.06, golem) * walk + claw * mix(0.15, -0.1, golem);
	pitch = mix(pitch, lean * 1.5, die);
	mat3 G = rot_x(pitch) * rot_z(sway);
	v.y += abs(sin(ph)) * mix(0.05, 0.03, golem) * walk;
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
	float g = noise(lpos * 13.0) * 0.6 + noise(lpos * 37.0) * 0.4;
	col *= 0.75 + 0.45 * g;
	// lava in the cracks of the dark rock (horns, claws and bone stay plain)
	float dark = 1.0 - smoothstep(0.03, 0.08, max(max(col.r, col.g), col.b));
	float cr = cracks(lpos * crack_scale);
	float mask = smoothstep(0.3, 0.7, noise(lpos * crack_scale * 0.4 + 5.0));
	float seam_l = (1.0 - smoothstep(0.0, mix(0.03, 0.08, hot) * (0.4 + 0.8 * mask), cr)) * dark * (1.0 - glow) * mix(0.15, 1.0, mask);
	float pulse = 0.75 + 0.25 * sin(TIME * 3.0 + lpos.y * 9.0);
	vec3 lava = mix(vec3(1.0, 0.3, 0.04), vec3(1.0, 0.65, 0.2), pulse * 0.5);
	col = mix(col, vec3(0.03, 0.01, 0.0), seam_l * 0.8);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 em = lava * seam_l * seam * 2.4 * pulse;
	float rough = 0.85;
	float spec = 0.3;
	if (glass > 0.5) {
		vec3 irid = 0.5 + 0.5 * cos(6.2831 * (rim * 1.2 + g * 0.3 + vec3(0.0, 0.33, 0.67)));
		col = mix(col, vec3(0.01, 0.01, 0.015), dark);
		em += irid * rim * 0.25 * dark;
		rough = mix(0.85, 0.07, dark);
		spec = mix(0.3, 0.95, dark);
	}
	if (hot > 0.0) {   // molten: glowing through and through, a thin dark crust breaking up
		float crust = smoothstep(0.08, 0.2, cr) * smoothstep(0.35, 0.6, noise(lpos * 6.0 + TIME * 0.3));
		vec3 molten = mix(vec3(1.0, 0.3, 0.04), vec3(1.0, 0.6, 0.16), noise(lpos * 4.0 - TIME * 0.5));
		em = mix(em, molten * 1.25 * (1.0 - crust * 0.8), hot * dark);
		col = mix(col, vec3(0.08, 0.03, 0.02), hot * dark);
	}
	col = mix(col, col * vec3(0.92, 0.78, 1.12), epic * 0.4);
	col = mix(col, vec3(1.0, 0.42, 0.08), burn * 0.5);
	col = mix(col, col * vec3(0.55, 0.8, 1.25), chill * 0.55);
	col = mix(col, vec3(0.72, 0.9, 1.0), frozen * 0.78);
	col = mix(col, col * vec3(0.35, 0.22, 0.5), shadow * 0.7);
	ALBEDO = mix(col, col * vec3(1.45, 0.55, 0.45) + vec3(0.15, 0.05, 0.03), flash * 0.6);
	ROUGHNESS = rough;
	SPECULAR = spec;
	float fl = 0.8 + 0.2 * sin(TIME * 13.0 + lpos.y * 20.0);
	EMISSION = em * (1.0 - frozen) + glow * eye_color * eye_power * fl + vec3(1.0, 0.32, 0.04) * burn * 0.9 + vec3(0.62, 0.18, 1.0) * epic * rim * 1.2
		+ vec3(0.45, 0.8, 1.0) * (frozen * (0.25 + rim * 1.4) + chill * rim * 0.6) + vec3(0.6, 0.2, 1.0) * shadow * rim * 1.8 + vec3(1.0, 0.4, 0.3) * flash * 0.6;
}
"""

const BAT_SHADER := """
shader_type spatial;
render_mode cull_disabled;
// COLOR.a = limb: 0 body, 1 L inner wing, 2 R inner wing, 3 L outer wing, 4 R outer wing,
// 5 head, 6 glow (eyes, belly, veins), 7 tail flames. INSTANCE_CUSTOM: r = animation (0 flap,
// .25 glide, .5 dive, .75 dead), g = phase, a = status code.
varying float burn;
varying float flash;
varying float epic;
varying float frozen;
varying float chill;
varying float shadow;
varying float glow;
varying float wing;
varying vec3 lpos;
mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }
mat3 rot_z(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	lpos = VERTEX;
	int limb = int(COLOR.a * 8.0 + 0.5);
	float anim = INSTANCE_CUSTOM.r;
	float ph = INSTANCE_CUSTOM.g * 6.2831853;
	float flap = 1.0 - step(0.125, anim);
	float glide = step(0.125, anim) * (1.0 - step(0.375, anim));
	float dive = step(0.375, anim) * (1.0 - step(0.625, anim));
	float dead = step(0.625, anim);
	float a1 = sin(ph) * 1.0 * flap + (0.15 + sin(TIME * 2.2 + ph) * 0.06) * glide - 0.6 * dead + 0.4 * dive;
	float a2 = sin(ph - 0.9) * 0.7 * flap + (0.05 + sin(TIME * 2.7 + ph) * 0.08) * glide - 0.9 * dead - 0.5 * dive;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	wing = 0.0;
	if (limb >= 1 && limb <= 4) {
		wing = 1.0;
		float side = (limb == 1 || limb == 3) ? 1.0 : -1.0;
		vec3 sh = vec3(side * 0.1, 0.05, 0.05);
		vec3 el = vec3(side * 0.55, 0.05, 0.0);
		mat3 r1 = rot_y(-side * 0.9 * dive) * rot_z(side * a1);
		if (limb >= 3) {
			mat3 r2 = rot_y(-side * 0.5 * dive) * rot_z(side * a2);
			v = el + r2 * (v - el);
			n = r2 * n;
		}
		v = sh + r1 * (v - sh);
		n = r1 * n;
	}
	if (limb == 5 || (limb == 6 && VERTEX.z > 0.12)) {
		vec3 nk = vec3(0.0, 0.05, 0.14);
		mat3 r = rot_x(0.15 + dive * 0.35 + sin(ph * 2.0) * 0.06 * flap);
		v = nk + r * (v - nk);
		n = r * n;
	}
	if (limb == 7) {   // the tail of flame streams and flickers
		float w = clamp(-VERTEX.z * 2.5, 0.0, 2.0);
		v.x += sin(TIME * 14.0 + VERTEX.z * 12.0) * 0.05 * w;
		v.y += sin(TIME * 11.0 + VERTEX.z * 9.0) * 0.04 * w;
	}
	v.y -= sin(ph) * 0.06 * flap;
	VERTEX = v;
	NORMAL = normalize(n);
	glow = (limb == 6 || limb == 7) ? 1.0 : 0.0;
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
	// glowing veins across the wing membranes, cinders smouldering on the body
	float vein = 0.0;
	if (wing > 0.5) {
		float a = atan(lpos.z + 0.05, abs(lpos.x) - 0.5);
		vein = smoothstep(0.86, 0.97, abs(fract(a * 1.6) - 0.5) * 2.0) * 0.8 * smoothstep(0.1, 0.4, abs(lpos.x));
		vein += smoothstep(0.82, 0.92, noise(lpos.xz * 14.0)) * 0.4;
		vein += smoothstep(0.06, 0.0, abs(lpos.z + 0.33 + 0.15 * sin(lpos.x * 9.0))) * 0.4;   // the ragged trailing edge glows
	}
	float ember = smoothstep(0.7, 0.85, noise(lpos.xy * 25.0 + lpos.z * 9.0)) * (1.0 - wing);
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	col = mix(col, col * vec3(0.92, 0.78, 1.12), epic * 0.5);
	col = mix(col, vec3(0.72, 0.9, 1.0), frozen * 0.78);
	col = mix(col, col * vec3(0.35, 0.22, 0.5), shadow * 0.7);
	ALBEDO = mix(col, col * vec3(1.45, 0.55, 0.45), flash * 0.6);
	ROUGHNESS = 0.9;
	float fl = 0.8 + 0.2 * sin(TIME * 17.0 + lpos.z * 30.0);
	vec3 hot = vec3(1.0, 0.42, 0.08);
	EMISSION = (glow * col * 3.2 * fl + hot * (vein + ember) * 1.6) * (1.0 - frozen) + vec3(0.62, 0.18, 1.0) * epic * rim * 1.2
		+ vec3(0.45, 0.8, 1.0) * (frozen * (0.25 + rim * 1.4) + chill * rim * 0.6) + vec3(0.6, 0.2, 1.0) * shadow * rim * 1.8 + vec3(1.0, 0.4, 0.3) * flash * 0.5;
}
"""

const SLUG_SHADER := """
shader_type spatial;
// COLOR.a = part: 0 body, 5 eye stalks, 6 glow (eyes, the molten underside, the seams' light),
// 7 crust plates (ride the body's waves). INSTANCE_CUSTOM: r = animation (0 crawl, .25 rear up,
// .75 melting), g = phase, b = melt (0..1), a = status code.
varying float burn;
varying float flash;
varying float epic;
varying float frozen;
varying float chill;
varying float shadow;
varying float glow;
varying vec3 lpos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	lpos = VERTEX;
	int part = int(COLOR.a * 8.0 + 0.5);
	float anim = INSTANCE_CUSTOM.r;
	float ph = INSTANCE_CUSTOM.g * 6.2831853;
	float melt = INSTANCE_CUSTOM.b;
	float rear = step(0.125, anim) * (1.0 - step(0.625, anim));
	float dying = step(0.625, anim);
	vec3 v = VERTEX;
	// a wave of muscle running down the body as it creeps, a side-to-side slither
	float wave = sin(v.z * 5.5 - ph * 2.0);
	v.y *= 1.0 + 0.1 * wave * (1.0 - dying);
	v.x += sin(v.z * 2.2 - ph) * 0.06 * (1.0 - dying);
	v.z += wave * 0.025;
	// rearing up at you: the front half lifts
	v.y += rear * smoothstep(0.0, 0.8, v.z) * (0.25 + 0.1 * sin(ph * 3.0));
	if (part == 5 || (part == 6 && v.y > 0.45)) {   // the eye stalks wave about
		float w = clamp((VERTEX.y - 0.35) * 3.0, 0.0, 1.0);
		v.x += sin(TIME * 2.3 + VERTEX.x * 20.0) * 0.06 * w;
		v.z += cos(TIME * 1.9 + VERTEX.x * 15.0) * 0.04 * w;
	}
	// melting: slumps flat and spreads into a puddle
	v.y *= 1.0 - melt * 0.85;
	v.xz *= 1.0 + melt * 0.5;
	VERTEX = v;
	glow = part == 6 ? 1.0 : 0.0;
	float c = INSTANCE_CUSTOM.a;
	shadow = step(31.5, c); c -= shadow * 32.0;
	chill = step(15.5, c); c -= chill * 16.0;
	frozen = step(7.5, c); c -= frozen * 8.0;
	epic = step(3.5, c); c -= epic * 4.0;
	flash = step(1.5, c); c -= flash * 2.0;
	burn = clamp(c, 0.0, 1.0);
}
void fragment() {
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float g = noise(lpos * 16.0);
	col *= 0.75 + 0.45 * g;
	float slime = smoothstep(0.55, 0.75, noise(lpos * 7.0 + vec3(0.0, 0.0, TIME * 0.4)));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	col = mix(col, col * vec3(0.92, 0.78, 1.12), epic * 0.5);
	col = mix(col, vec3(0.72, 0.9, 1.0), frozen * 0.78);
	col = mix(col, col * vec3(0.35, 0.22, 0.5), shadow * 0.7);
	ALBEDO = mix(col, col * vec3(1.45, 0.55, 0.45), flash * 0.6);
	ROUGHNESS = mix(0.5, 0.2, slime);
	SPECULAR = 0.6;
	float fl = 0.8 + 0.2 * sin(TIME * 4.0 + lpos.z * 12.0);
	vec3 hot = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.7, 0.2), g);
	EMISSION = (glow * hot * 2.8 * fl + hot * rim * 0.35 * (1.0 - glow)) * (1.0 - frozen) + vec3(0.62, 0.18, 1.0) * epic * rim * 1.2
		+ vec3(0.45, 0.8, 1.0) * (frozen * (0.25 + rim * 1.4) + chill * rim * 0.6) + vec3(0.6, 0.2, 1.0) * shadow * rim * 1.8 + vec3(1.0, 0.4, 0.3) * flash * 0.5;
}
"""

## The slugs' lava trail: blobs of molten rock on the ground, crusting over and fading
## (INSTANCE_CUSTOM.r = age 0..1).
const TRAIL_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;
varying float age;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	age = INSTANCE_CUSTOM.r;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 q = UV - 0.5;
	float n = noise(wpos.xz * 3.0) * 0.5 + noise(wpos.xz * 9.0) * 0.25;
	float d = length(q) * 2.0 + (n - 0.35) * 0.5;
	float a = 1.0 - smoothstep(0.55, 0.8, d);
	if (a < 0.02) { discard; }
	float crust = smoothstep(0.25, 0.9, age) * smoothstep(0.35, 0.6, n + age * 0.4);
	vec3 hot = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.75, 0.25), n);
	ALBEDO = mix(hot * 0.3, vec3(0.06, 0.03, 0.02), crust);
	EMISSION = hot * (1.0 - crust) * 2.6 * (1.0 - smoothstep(0.7, 1.0, age));
	ALPHA = a * (1.0 - smoothstep(0.8, 1.0, age));
	ROUGHNESS = 0.5;
}
"""

## Flying chunks of rock (cooling from orange) and obsidian shards (INSTANCE_CUSTOM.r = heat).
const DEBRIS_SHADER := """
shader_type spatial;
uniform float glass = 0.0;
varying float heat;
void vertex() { heat = INSTANCE_CUSTOM.r; }
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(vec3(0.07, 0.06, 0.06), vec3(0.015, 0.012, 0.02), glass);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.06, glass);
	SPECULAR = mix(0.3, 0.95, glass);
	vec3 irid = 0.5 + 0.5 * cos(6.2831 * (rim + vec3(0.0, 0.33, 0.67)));
	EMISSION = vec3(1.0, 0.4, 0.08) * heat * heat * 3.0 + irid * rim * 0.3 * glass;
}
"""

## Embers drifting off the cinder bats (INSTANCE_CUSTOM.r = age 0..1).
const EMBER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_disabled, fog_disabled;
varying float age;
void vertex() {
	age = INSTANCE_CUSTOM.r;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= (1.0 - age * 0.7) * length(MODEL_MATRIX[0].xyz);
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.2, 1.0, d)) * (1.0 - age);
	ALBEDO = mix(vec3(1.0, 0.75, 0.3), vec3(1.0, 0.25, 0.03), age) * 2.0 * a;
}
"""

const SOUNDS := {
	"imp_death": ["res://audio/caldera/imp_death_1.wav", "res://audio/caldera/imp_death_2.wav"],
	"imp_chitter": ["res://audio/caldera/imp_chitter_1.wav", "res://audio/caldera/imp_chitter_2.wav"],
	"screech": ["res://audio/caldera/bat_screech_1.wav", "res://audio/caldera/bat_screech_2.wav"],
	"flap": ["res://audio/caldera/bat_flap.wav"],
	"step": ["res://audio/caldera/golem_step.wav"],
	"shatter": ["res://audio/caldera/golem_shatter.wav"],
	"squelch": ["res://audio/caldera/slug_squelch.wav"],
	"melt": ["res://audio/caldera/slug_death.wav"],
	"crack": ["res://audio/caldera/crack_open.wav"],
}

var em: EnemyManager
var _mm: Array[MultiMesh] = []
var _buf := PackedFloat32Array()
var _counts := PackedInt32Array()
var _goblins_hidden := false
var _pack_at := Vector3.INF
var _pack_t := -99.0
var _pack_n := 0
var _t := 0.0
# corpses: kind, position, yaw, scale, age, the height it fell from
var _c_kind := PackedInt32Array()
var _c_pos := PackedVector3Array()
var _c_yaw := PackedFloat32Array()
var _c_scale := PackedFloat32Array()
var _c_age := PackedFloat32Array()
var _c_from := PackedFloat32Array()
var _c_n := 0
# the slugs' lava trail
var trail_pos := PackedVector3Array()
var trail_age := PackedFloat32Array()
var _trail_mm: MultiMesh
var _trail_buf := PackedFloat32Array()
var _trail_tick := 0.0
# embers off the bats
var _e_pos := PackedVector3Array()
var _e_vel := PackedVector3Array()
var _e_age := PackedFloat32Array()
var _e_n := 0
var _e_next := 0
var _ember_mm: MultiMesh
var _ember_buf := PackedFloat32Array()
# debris: rock chunks (0) and obsidian shards (1)
var _d_kind := PackedInt32Array()
var _d_pos := PackedVector3Array()
var _d_vel := PackedVector3Array()
var _d_rot := PackedVector3Array()   # axis * spin
var _d_ang := PackedFloat32Array()
var _d_age := PackedFloat32Array()
var _d_life := PackedFloat32Array()
var _d_heat := PackedFloat32Array()
var _d_size := PackedFloat32Array()
var _d_n := 0
var _debris_mm: Array[MultiMesh] = []
var _debris_bufs: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _sfx: Array[AudioStreamPlayer3D] = []
var _streams := {}
var _voice_t := 1.0
var _death_tokens := 6.0
var _step_cd := 0.0
var _fx: FxManager
# counters for tests
var trail_hits := 0
var stomps := 0
var shatters := 0
var bats_low := 0
var deaths := {}


func _ready() -> void:
	name = "CalderaCrowd"   # no-i18n
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
	for k in range(0, _buf.size(), STRIDE):
		_buf[k + 12] = 1.0; _buf[k + 13] = 1.0; _buf[k + 14] = 1.0; _buf[k + 15] = 1.0
	_c_kind.resize(CORPSE_MAX)
	_c_pos.resize(CORPSE_MAX)
	for a in [_c_yaw, _c_scale, _c_age, _c_from]:
		a.resize(CORPSE_MAX)
	_trail_mm = _make_mm(_trail_mesh(), TRAIL_MAX, TRAIL_SHADER)
	_trail_buf.resize(TRAIL_MAX * 16)
	_e_pos.resize(EMBER_MAX)
	_e_vel.resize(EMBER_MAX)
	_e_age.resize(EMBER_MAX)
	var eq := QuadMesh.new()
	eq.size = Vector2(0.16, 0.16)
	_ember_mm = _make_mm(eq, EMBER_MAX, EMBER_SHADER)
	_ember_buf.resize(EMBER_MAX * 16)
	for a in [_d_ang, _d_age, _d_life, _d_heat, _d_size]:
		a.resize(DEBRIS_MAX)
	_d_kind.resize(DEBRIS_MAX)
	_d_pos.resize(DEBRIS_MAX)
	_d_vel.resize(DEBRIS_MAX)
	_d_rot.resize(DEBRIS_MAX)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var chunk := MeshBuilder.new()
	chunk.add(ForestProps._lumpy(0.13, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.75, 0.85)), Vector3.ZERO), Color.WHITE)
	var shard := MeshBuilder.new()
	shard.add(MeshBuilder.cyl(0.0, 0.09, 0.32, 4), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.35)), Vector3.ZERO), Color.WHITE)
	for k in 2:
		var sh := Shader.new()
		sh.code = DEBRIS_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("glass", float(k))
		var mesh := (chunk if k == 0 else shard).commit(m)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = DEBRIS_MAX
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 200, 1000))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_debris_mm.append(mm)
	for k in SOUNDS:
		var list: Array = []
		for path in SOUNDS[k]:
			if ResourceLoader.exists(path):
				list.append(load(path))
		_streams[k] = list
	for k in 6:
		var a := AudioStreamPlayer3D.new()
		a.bus = Settings.SFX_BUS
		a.unit_size = 9.0
		a.max_distance = 45.0
		add_child(a)
		_sfx.append(a)


func _make_mm(mesh: Mesh, n: int, code: String) -> MultiMesh:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	mesh.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 200, 1000))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


static func _trail_mesh() -> Mesh:
	var p := PlaneMesh.new()
	p.size = Vector2(TRAIL_RADIUS * 2.4, TRAIL_RADIUS * 2.4)
	return p


## Is `t` one of the Caldera's types?
static func owns(t: int) -> bool:
	return t >= EnemyManager.MAGMA_IMP and t <= EnemyManager.LAVA_SLUG


## What spawns on the Caldera this minute: imps in the goblins' place, bats in the scamps',
## golems in the brutes', and slugs.
static func pick_type(rng: RandomNumberGenerator, m: float) -> int:
	var w_imp := 10.0
	var w_bat := (1.5 + 3.0 * minf(m, 3.0)) if m >= 0.4 else 0.0
	var w_golem := 1.5 * (m - 1.0) if m >= 2.0 else 0.0
	var w_slug := (1.4 + 0.5 * minf(m, 6.0)) if m >= 0.75 else 0.0
	var r := rng.randf() * (w_imp + w_bat + w_golem + w_slug)
	if r < w_imp:
		return EnemyManager.MAGMA_IMP
	r -= w_imp
	if r < w_bat:
		return EnemyManager.CINDER_BAT
	r -= w_bat
	if r < w_golem:
		return EnemyManager.OBSIDIAN_GOLEM
	return EnemyManager.LAVA_SLUG


func on_spawn(i: int) -> void:
	var t := em.typ[i]
	if t == EnemyManager.MAGMA_IMP:
		# imps run in packs: one spawned soon after another joins it
		if _t - _pack_t < PACK_TIME and _pack_n < PACK_SIZE and _pack_at != Vector3.INF and em.rise_t[i] <= 0.0:
			var p := _pack_at + Vector3(randf_range(-1.6, 1.6), 0, randf_range(-1.6, 1.6))
			p.y = SwampWater.height_at(p.x, p.z)
			em.pos[i] = p
			_pack_n += 1
		else:
			_pack_at = em.pos[i]
			_pack_n = 1
		_pack_t = _t
	elif t == EnemyManager.CINDER_BAT:
		var alt := 8.0 + randf() * 3.0
		em.throw_t[i] = alt   # (a bat's height above its floor lives in the row: skeletons' throw timer)
		var p := em.pos[i]
		p.y += alt
		em.pos[i] = p


func on_kill(i: int) -> void:
	var t := em.typ[i]
	var kind := _mesh_of(i)
	var p := em.pos[i]
	var u := em.uid[i]
	var sc := em.t_scale[t] * em.sz[i]
	deaths[t] = int(deaths.get(t, 0)) + 1
	var corpse := true
	match t:
		EnemyManager.MAGMA_IMP:   # bursts into a puff of embers and cooling rock chunks
			_burst(p + Vector3(0, 0.5 * sc, 0), 1.3 * sc, Color(1.0, 0.45, 0.08))
			_debris(0, p + Vector3(0, 0.45 * sc, 0), 5 if em.epic[i] == 0 else 9, 3.5, sc)
			for k in 6:
				_ember(p + Vector3(randf_range(-0.3, 0.3), 0.5 * sc, randf_range(-0.3, 0.3)), Vector3(randf_range(-1.5, 1.5), randf_range(1.5, 4.0), randf_range(-1.5, 1.5)))
			_death_sound("imp_death", p, 0.8, 1.0 / sqrt(sc))
		EnemyManager.CINDER_BAT:   # tumbles out of the air in a burst of sparks
			_burst(p, 1.2, Color(1.0, 0.55, 0.15))
			for k in 8:
				_ember(p, Vector3(randf_range(-2.5, 2.5), randf_range(-0.5, 3.0), randf_range(-2.5, 2.5)))
			_death_sound("screech", p, 0.6, 1.3)
		EnemyManager.OBSIDIAN_GOLEM:   # shatters into a spray of glass
			corpse = false
			shatters += 1
			_burst(p + Vector3(0, 1.3 * sc / 1.6, 0), 2.2 * sc / 1.6, Color(1.0, 0.5, 0.12) if em.epic[i] == 1 else Color(0.9, 0.35, 0.1))
			_debris(1, p + Vector3(0, 1.2 * sc / 1.6, 0), 22 if em.epic[i] == 0 else 30, 6.0, sc / 1.6)
			_debris(0, p + Vector3(0, 1.0, 0), 4, 3.0, 1.0)
			_death_sound("shatter", p, 1.0, 1.0)
		EnemyManager.LAVA_SLUG:   # melts into a cooling puddle
			_burst(p + Vector3(0, 0.3, 0), 1.0, Color(1.0, 0.4, 0.08))
			_death_sound("melt", p, 0.8, 1.0)
	if not corpse:
		return
	var v := em.vel[i]
	var yaw := atan2(v.x, v.z) if Vector2(v.x, v.z).length() > 0.2 else randf() * TAU
	var k := _c_n
	if _c_n < CORPSE_MAX:
		_c_n += 1
	else:
		k = randi() % CORPSE_MAX
	_c_kind[k] = kind
	_c_pos[k] = p
	_c_yaw[k] = yaw
	_c_scale[k] = sc
	_c_age[k] = 0.0
	_c_from[k] = p.y - SwampWater.height_at(p.x, p.z)


func _mesh_of(i: int) -> int:
	var ep := em.epic[i] == 1
	match em.typ[i]:
		EnemyManager.CINDER_BAT: return M_BAT
		EnemyManager.OBSIDIAN_GOLEM: return M_MOLTEN if ep else M_GOLEM
		EnemyManager.LAVA_SLUG: return M_SLUG
	return M_FIEND if ep else M_IMP


func _get_fx() -> FxManager:
	if _fx == null:
		var main := em.get_parent()
		_fx = main.get("fx") as FxManager if main != null else null
	return _fx


func _burst(at: Vector3, r: float, c: Color) -> void:
	var fx := _get_fx()
	if fx != null:
		fx.burst(at, r, c, 0.35)


# ------------------------------------------------------------------ the eruption swarm

## The minute's swarm on the Caldera: the volcano erupts (lava bombs on marked circles round the
## player, CalderaAmbience.erupt) and a ring of imps claws up out of the cracks round you, with
## cinder bats wheeling in. Returns how many came.
func eruption_swarm(pp: Vector3, n: int, hp_mult: float, rng: RandomNumberGenerator, epic_chance := 0.0, bombs := 8) -> int:
	if CalderaAmbience.current != null:
		CalderaAmbience.current.erupt(pp, bombs, rng)
	var came := 0
	for k in n:
		var a := TAU * float(k) / float(maxi(n, 1)) + rng.randf_range(-0.08, 0.08)
		var p := pp + Vector3(cos(a), 0, sin(a)) * rng.randf_range(18.0, 23.0)
		p.y = SwampWater.height_at(p.x, p.z)
		var t := EnemyManager.CINDER_BAT if k % 4 == 3 else EnemyManager.MAGMA_IMP
		if raise(t, p, hp_mult, rng.randf() < epic_chance) >= 0:
			came += 1
	return came


## An imp (or anything) climbing out of a glowing crack at `p`: harmless while it rises.
func raise(t: int, p: Vector3, hp_mult: float, epic := false) -> int:
	var i := em.spawn(t, p, hp_mult, epic)
	if i < 0:
		return -1
	if t == EnemyManager.MAGMA_IMP or t == EnemyManager.OBSIDIAN_GOLEM:
		em.rise_t[i] = RISE_TIME
		_burst(p + Vector3(0, 0.3, 0), 1.0, Color(1.0, 0.4, 0.08))
	return i


# ------------------------------------------------------------------ per frame

## Called by EnemyManager at the end of its tick: moves the Caldera's rows out of the goblin
## MultiMesh into their own, flies the bats, lays the slugs' trails (and burns the player on
## them), shakes the ground under the golems, and runs the corpses, debris and voices.
func sync(dt: float, buf: PackedFloat32Array, player: Node3D) -> PackedFloat32Array:
	_t += dt
	_counts.fill(0)
	bats_low = 0
	_death_tokens = minf(8.0, _death_tokens + dt * 14.0)
	_step_cd -= dt
	var pp := player.global_position if player != null else Vector3.ZERO
	var p_ok := player != null
	if not _goblins_hidden:
		for c in em.get_children():
			if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh == em.mm:
				(c as MultiMeshInstance3D).visible = false
				_goblins_hidden = true
	var typ := em.typ
	var pos := em.pos
	var vel := em.vel
	var sz := em.sz
	var tsc := em.t_scale
	var epic := em.epic
	var dead := em.dead
	var freeze := em.freeze_t
	var stun := em.stun_t
	var rise := em.rise_t
	var clip_attack := em._clip_attack
	var t0 := EnemyManager.MAGMA_IMP
	var t1 := EnemyManager.LAVA_SLUG
	for i in em.count:
		var t := typ[i]
		if t < t0 or t > t1:
			continue
		var b := i * STRIDE
		var sc := tsc[t] * sz[i]
		var p := pos[i]
		var v := vel[i]
		var anim := A_CLAW if absf(buf[b + 12] - clip_attack) < 0.01 else A_WALK
		var phase := buf[b + 13]
		var lean := 0.0
		var held := freeze[i] > 0.0 or stun[i] > 0.0
		var kind := M_IMP
		if t == EnemyManager.CINDER_BAT:
			var r := _fly(i, dt, pp, p_ok)
			p = em.pos[i]
			v = em.vel[i]
			if not held:
				phase = fmod(_t * (3.6 if r.x != A_GLIDE else 0.5) + float(em.uid[i]) * 0.37, 1.0)
			var fw := Vector2(v.x, v.z)
			if fw.length() < 0.2 and p_ok:
				fw = Vector2(pp.x - p.x, pp.z - p.z)
			var xf := Transform3D(Basis(Vector3.UP, atan2(fw.x, fw.y)) * Basis(Vector3(1, 0, 0), r.z) * Basis(Vector3(0, 0, 1), r.y), p).scaled_local(Vector3.ONE * sc)
			_put(M_BAT, xf, r.x, phase, 0.0, buf[b + 19])
			if dead[i] == 0 and not held and fmod(_t + float(em.uid[i]) * 0.037, 0.12) < dt and (pp - p).length_squared() < 2000.0:
				_ember(p + Vector3(randf_range(-0.15, 0.15), randf_range(-0.1, 0.1), randf_range(-0.15, 0.15)), Vector3(randf_range(-0.4, 0.4), randf_range(-0.6, 0.3), randf_range(-0.4, 0.4)))
			continue
		if t == EnemyManager.OBSIDIAN_GOLEM:
			kind = M_MOLTEN if epic[i] == 1 else M_GOLEM
			phase = fmod(phase * 1.0, 1.0)
			if dead[i] == 0 and not held and p_ok:
				# a footfall when the walk cycle passes a quarter or three quarters (the phase it had
				# a frame ago is worked back from the crowd's own stride rate)
				var spd := Vector2(v.x, v.z).length()
				var prev := phase - dt * maxf(spd, 0.8) / (EnemyManager.STRIDE_LEN * sc)
				var a0 := prev - floorf(prev)
				if (a0 < 0.25 and phase >= 0.25) or (a0 < 0.75 and phase >= 0.75) or (a0 > phase and phase >= 0.25):
					_golem_step(i, p, pp, player)
		elif t == EnemyManager.LAVA_SLUG:
			kind = M_SLUG
			if dead[i] == 0 and fmod(_t + float(em.uid[i]) * 0.13, TRAIL_EVERY) < dt and Vector2(v.x, v.z).length_squared() > 0.09:
				_slug_trail(p)
		else:
			kind = M_FIEND if epic[i] == 1 else M_IMP
			if rise[i] > 0.0:   # clawing up out of a crack
				p.y -= IMP_HEIGHT * sc * 1.05 * clampf(rise[i] / RISE_TIME, 0.0, 1.0)
				anim = A_CLAW
		if t == EnemyManager.OBSIDIAN_GOLEM and rise[i] > 0.0:
			p.y -= GOLEM_HEIGHT * sc * clampf(rise[i] / RISE_TIME, 0.0, 1.0)
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
	_tick_corpses(dt)
	_tick_trail(dt, pp, player)
	_tick_embers(dt)
	_tick_debris(dt)
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


## A cinder bat's flight this frame: loose figure-eights above you (a lemniscate round you, its
## own size and tilt), then a dive straight at you, down to your chest, and away. Near you it
## flies at your height (up a column), away from you it follows the ground. Returns
## (animation, bank roll, pitch).
func _fly(i: int, dt: float, pp: Vector3, p_ok: bool) -> Vector3:
	var u := em.uid[i]
	var alt: float = em.throw_t[i]
	var p := em.pos[i]
	var g := SwampWater.height_at(p.x, p.z)
	var to := Vector3(pp.x - p.x, 0, pp.z - p.z)
	var d := to.length()
	var cycle := fmod(_t / BAT_CYCLE + float(u) * 0.377, 1.0)
	var floor_y := maxf(g, lerpf(pp.y, g, smoothstep(8.0, 30.0, d))) if p_ok else g
	var want := BAT_HIGH
	var anim := A_FLAP
	var roll := 0.0
	var pitch := 0.0
	if em.is_held(i):
		want = alt
		anim = A_GLIDE
	elif p_ok and d < 22.0 and cycle < BAT_LOOP and not em.is_harmless(i) and em.kb_t[i] <= 0.0:
		var sp := em.t_speed[EnemyManager.CINDER_BAT]
		var rr := BAT_LOOP_R + float(u % 4)
		var th := _t * sp / (rr * 1.6) + float(u) * 1.7
		var tilt := float(u % 7) * 0.9
		var loc := Vector2(sin(th), sin(th) * cos(th)) * rr
		loc = loc.rotated(tilt)
		var target := Vector3(pp.x + loc.x, 0, pp.z + loc.y)
		var stp := Vector3(target.x - p.x, 0, target.z - p.z)
		var max_step := sp * 1.4 * dt
		if stp.length() > max_step:
			stp = stp.normalized() * max_step
		p.x += stp.x
		p.z += stp.z
		var tan := Vector2(cos(th), cos(2.0 * th)).rotated(tilt).normalized()
		em.vel[i] = Vector3(tan.x, 0, tan.y) * sp
		want = BAT_HIGH + 0.6 * sin(_t * 1.7 + float(u))
		anim = A_FLAP if sin(_t * 2.0 + u) > -0.3 else A_GLIDE
		roll = -sin(th * 2.0) * 0.5
	else:
		want = lerpf(BAT_LOW, BAT_HIGH + 1.0, smoothstep(2.0, 14.0, d))
		anim = A_DIVE if d > 3.5 else A_FLAP
		pitch = 0.4 if d > 3.5 else -0.2
	alt = move_toward(alt, want, (10.0 if want < alt else 6.0) * dt)
	em.throw_t[i] = alt
	p.y = maxf(floor_y + alt, g + 0.45)
	em.pos[i] = p
	if alt < 1.2:
		bats_low += 1
	return Vector3(anim, roll, pitch)


## A golem's footfall: near you it shakes the ground (and thuds).
func _golem_step(i: int, p: Vector3, pp: Vector3, player: Node3D) -> void:
	var d := Vector2(pp.x - p.x, pp.z - p.z).length()
	if d < 14.0:
		stomps += 1
		if player.has_method("add_shake"):
			player.add_shake(clampf(0.18 - d * 0.01, 0.03, 0.15))
		if _step_cd <= 0.0:
			_step_cd = 0.25
			_play("step", p, 0.9, randf_range(0.8, 1.0))
		var fx := _get_fx()
		if fx != null:
			fx.burst(p + Vector3(0, 0.15, 0), 0.9, Color(0.25, 0.22, 0.2), 0.3)


## A crawling slug lays a blob of lava every TRAIL_EVERY seconds (about a metre).
func _slug_trail(p: Vector3) -> void:
	if trail_pos.size() >= TRAIL_MAX:
		trail_pos.remove_at(0)
		trail_age.remove_at(0)
	trail_pos.append(Vector3(p.x, SwampWater.height_at(p.x, p.z) + 0.04, p.z))
	trail_age.append(0.0)
	if randf() < 0.08:
		_play("squelch", p, 0.5)


## The trail ages and fades; standing on it (on the ground) burns.
func _tick_trail(dt: float, pp: Vector3, player: Node3D) -> void:
	var n := trail_pos.size()
	if n == 0 and _trail_mm.visible_instance_count == 0:
		return
	var k := 0
	while k < n:
		trail_age[k] += dt
		if trail_age[k] >= TRAIL_LIFE:
			trail_pos.remove_at(k)
			trail_age.remove_at(k)
			n -= 1
			continue
		k += 1
	_trail_tick -= dt
	if player != null and n > 0:
		var on := false
		var g := SwampWater.height_at(pp.x, pp.z)
		if pp.y - g < 0.6:
			for j in n:
				var q := trail_pos[j]
				if (pp.x - q.x) * (pp.x - q.x) + (pp.z - q.z) * (pp.z - q.z) < TRAIL_RADIUS * TRAIL_RADIUS:
					on = true
					break
		if on and _trail_tick <= 0.0:
			_trail_tick = TRAIL_TICK
			if "invuln" in player:
				player.invuln = 0.0
			var main := em.get_parent()
			var mult: float = main.enemy_damage_mult() if main != null and main.has_method("enemy_damage_mult") else 1.0
			if player.has_method("hurt") and player.hurt(TRAIL_DAMAGE * mult):
				trail_hits += 1
	for j in n:
		var o := j * 16
		var q := trail_pos[j]
		var s := 1.0 + 0.15 * sin(float(j) * 2.3)
		_trail_buf[o] = s; _trail_buf[o + 1] = 0.0; _trail_buf[o + 2] = 0.0; _trail_buf[o + 3] = q.x
		_trail_buf[o + 4] = 0.0; _trail_buf[o + 5] = 1.0; _trail_buf[o + 6] = 0.0; _trail_buf[o + 7] = q.y
		_trail_buf[o + 8] = 0.0; _trail_buf[o + 9] = 0.0; _trail_buf[o + 10] = s; _trail_buf[o + 11] = q.z
		_trail_buf[o + 12] = trail_age[j] / TRAIL_LIFE; _trail_buf[o + 13] = 0.0; _trail_buf[o + 14] = 0.0; _trail_buf[o + 15] = 0.0
	if n > 0 or _trail_mm.visible_instance_count > 0:
		_trail_mm.buffer = _trail_buf
	_trail_mm.visible_instance_count = n


func _ember(at: Vector3, v: Vector3) -> void:
	var k := _e_next
	_e_next = (_e_next + 1) % EMBER_MAX
	_e_n = mini(_e_n + 1, EMBER_MAX)
	_e_pos[k] = at
	_e_vel[k] = v
	_e_age[k] = 0.0


func _tick_embers(dt: float) -> void:
	if _e_n == 0:
		return
	var shown := 0
	for k in _e_n:
		var a := _e_age[k] + dt / 0.7
		_e_age[k] = a
		if a >= 1.0:
			continue
		var v := _e_vel[k]
		v.y += 1.2 * dt
		v *= 1.0 - 1.5 * dt
		_e_vel[k] = v
		var p := _e_pos[k] + v * dt
		_e_pos[k] = p
		var o := shown * 16
		_ember_buf[o] = 1.0; _ember_buf[o + 1] = 0.0; _ember_buf[o + 2] = 0.0; _ember_buf[o + 3] = p.x
		_ember_buf[o + 4] = 0.0; _ember_buf[o + 5] = 1.0; _ember_buf[o + 6] = 0.0; _ember_buf[o + 7] = p.y
		_ember_buf[o + 8] = 0.0; _ember_buf[o + 9] = 0.0; _ember_buf[o + 10] = 1.0; _ember_buf[o + 11] = p.z
		_ember_buf[o + 12] = a; _ember_buf[o + 13] = 0.0; _ember_buf[o + 14] = 0.0; _ember_buf[o + 15] = 0.0
		shown += 1
	if shown > 0 or _ember_mm.visible_instance_count > 0:
		_ember_mm.buffer = _ember_buf
	_ember_mm.visible_instance_count = shown


## Fling `n` pieces of debris (0 rock chunks, cooling; 1 obsidian shards) out from `at`.
func _debris(kind: int, at: Vector3, n: int, speed: float, sc: float) -> void:
	for j in n:
		var k := _d_n
		if _d_n < DEBRIS_MAX:
			_d_n += 1
		else:
			k = randi() % DEBRIS_MAX
		_d_kind[k] = kind
		_d_pos[k] = at + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.4), randf_range(-0.3, 0.3)) * sc
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)).normalized()
		_d_vel[k] = dir * speed * randf_range(0.5, 1.2)
		_d_rot[k] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(4.0, 12.0)
		_d_ang[k] = randf() * TAU
		_d_age[k] = 0.0
		_d_life[k] = randf_range(1.6, 2.4)
		_d_heat[k] = 1.0 if kind == 0 else randf_range(0.0, 0.5)
		_d_size[k] = randf_range(0.7, 1.4) * sc


func _tick_debris(dt: float) -> void:
	if _d_n == 0 and _debris_mm[0].visible_instance_count == 0 and _debris_mm[1].visible_instance_count == 0:
		return
	var counts := [0, 0]
	var bufs := _debris_bufs
	if bufs[0].size() != DEBRIS_MAX * 16:
		bufs[0].resize(DEBRIS_MAX * 16)
		bufs[1].resize(DEBRIS_MAX * 16)
	var k := 0
	while k < _d_n:
		_d_age[k] += dt
		if _d_age[k] >= _d_life[k]:
			var last := _d_n - 1
			_d_kind[k] = _d_kind[last]; _d_pos[k] = _d_pos[last]; _d_vel[k] = _d_vel[last]; _d_rot[k] = _d_rot[last]
			_d_ang[k] = _d_ang[last]; _d_age[k] = _d_age[last]; _d_life[k] = _d_life[last]; _d_heat[k] = _d_heat[last]; _d_size[k] = _d_size[last]
			_d_n -= 1
			continue
		var v := _d_vel[k]
		var p := _d_pos[k]
		var g := SwampWater.height_at(p.x, p.z) + 0.05
		var resting := p.y <= g + 0.01 and absf(v.y) < 0.5
		if not resting:
			v.y -= 16.0 * dt
			p += v * dt
			if p.y < g:   # bounce once, then lie there
				p.y = g
				v = Vector3(v.x * 0.35, -v.y * 0.3, v.z * 0.35)
				_d_rot[k] *= 0.4
			_d_ang[k] += _d_rot[k].length() * dt
		var sink := clampf((_d_age[k] - (_d_life[k] - 0.5)) / 0.5, 0.0, 1.0)
		p.y = maxf(p.y, g) if not resting else g - sink * 0.15
		_d_pos[k] = p
		_d_vel[k] = v
		_d_heat[k] = maxf(0.0, _d_heat[k] - dt * 0.6)
		var kind := _d_kind[k]
		var c: int = counts[kind]
		var axis := _d_rot[k].normalized() if _d_rot[k].length() > 0.01 else Vector3.UP
		var bs := Basis(axis, _d_ang[k]).scaled(Vector3.ONE * _d_size[k] * (1.0 - sink * 0.6))
		var o := c * 16
		var bb: PackedFloat32Array = bufs[kind]
		bb[o] = bs.x.x; bb[o + 1] = bs.y.x; bb[o + 2] = bs.z.x; bb[o + 3] = p.x
		bb[o + 4] = bs.x.y; bb[o + 5] = bs.y.y; bb[o + 6] = bs.z.y; bb[o + 7] = p.y
		bb[o + 8] = bs.x.z; bb[o + 9] = bs.y.z; bb[o + 10] = bs.z.z; bb[o + 11] = p.z
		bb[o + 12] = _d_heat[k]; bb[o + 13] = 0.0; bb[o + 14] = 0.0; bb[o + 15] = 0.0
		bufs[kind] = bb
		counts[kind] = c + 1
		k += 1
	_debris_bufs = bufs
	for j in 2:
		if counts[j] > 0 or _debris_mm[j].visible_instance_count > 0:
			_debris_mm[j].buffer = bufs[j]
		_debris_mm[j].visible_instance_count = counts[j]


func _tick_corpses(dt: float) -> void:
	var i := 0
	while i < _c_n:
		_c_age[i] += dt
		var age := _c_age[i]
		var kind := _c_kind[i]
		var life := 2.6 if kind == M_SLUG else (2.4 if kind == M_BAT else 1.1)
		if age > life:
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
		var xf: Transform3D
		if kind == M_BAT:   # tumbles out of the air and lands on its back
			var fall_t := sqrt(2.0 * maxf(_c_from[i], 0.0) / 14.0) + 0.05
			var f := clampf(age / fall_t, 0.0, 1.0)
			var y := g + 0.12 + maxf(_c_from[i], 0.0) * (1.0 - f * f)
			var spin := age * 10.0 * (1.0 - f) + f * PI * 0.9
			var sink := clampf((age - (life - 0.8)) / 0.8, 0.0, 1.0)
			xf = Transform3D(Basis(Vector3.UP, _c_yaw[i] + age * 2.0 * (1.0 - f)) * Basis(Vector3(0, 0, 1), spin), Vector3(p.x, y - sink * 0.4, p.z)).scaled_local(Vector3.ONE * _c_scale[i])
			_put(kind, xf, 0.75, 0.0, 0.0, 0.0)
		elif kind == M_SLUG:   # melts flat into a cooling puddle and sinks
			var melt := clampf(age / 1.2, 0.0, 1.0)
			var sink := clampf((age - (life - 0.8)) / 0.8, 0.0, 1.0)
			xf = Transform3D(Basis(Vector3.UP, _c_yaw[i]), Vector3(p.x, g - sink * 0.2, p.z)).scaled_local(Vector3.ONE * _c_scale[i])
			_put(kind, xf, A_DIE, 0.0, melt, 0.0)
		else:   # imps: topple, then crumble away into the ash
			var fall := clampf(age / 0.3, 0.0, 1.0)
			fall = fall * fall
			var crumble := clampf((age - 0.3) / (life - 0.3), 0.0, 1.0)
			xf = Transform3D(Basis(Vector3.UP, _c_yaw[i]), Vector3(p.x, g - crumble * 0.5 * _c_scale[i], p.z)).scaled_local(Vector3(1.0 + crumble * 0.3, 1.0 - crumble * 0.85, 1.0 + crumble * 0.3) * _c_scale[i])
			_put(kind, xf, A_DIE, 0.0, fall, 0.0)
		i += 1


## Now and then a nearby imp chitters, a bat screeches or beats its wings, a slug squelches.
func _voices(dt: float, pp: Vector3, p_ok: bool) -> void:
	_voice_t -= dt
	if _voice_t > 0.0 or not p_ok or em.count == 0:
		return
	_voice_t = randf_range(0.8, 1.9)
	for tries in 6:
		var i := randi() % em.count
		var t := em.typ[i]
		if not owns(t) or em.dead[i] or em.pos[i].distance_to(pp) > 28.0:
			continue
		match t:
			EnemyManager.CINDER_BAT: _play("screech" if randf() < 0.55 else "flap", em.pos[i], 0.6)
			EnemyManager.LAVA_SLUG: _play("squelch", em.pos[i], 0.7)
			EnemyManager.OBSIDIAN_GOLEM: _play("step", em.pos[i], 0.7, 0.7)
			_: _play("imp_chitter", em.pos[i], 0.7)
		return


func _death_sound(kind: String, at: Vector3, volume: float, pitch: float) -> void:
	if _death_tokens < 1.0:
		return
	_death_tokens -= 1.0
	_play(kind, at, volume, pitch, true)


func _play(kind: String, at: Vector3, volume: float, pitch := 1.0, force := false) -> void:
	var list: Array = _streams.get(kind, [])
	if list.is_empty():
		return
	var a := _sfx[randi() % _sfx.size()]
	if a.playing and not force and randf() < 0.5:
		return
	a.stream = list[randi() % list.size()]
	a.volume_db = linear_to_db(volume) - 3.0
	a.pitch_scale = pitch * randf_range(0.88, 1.12)
	a.global_position = at
	a.play()


func corpse_count() -> int:
	return _c_n


func debris_count() -> int:
	return _d_n


func drawn(kind: int) -> int:
	return _counts[kind] if kind < _counts.size() else 0


# ------------------------------------------------------------------ models

static func _mat(gait: float, eye: Color, power: float, seam: float, glass: float, hot: float, pivots: Array, crack_scale := 9.0) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = CREATURE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("gait", gait)
	m.set_shader_parameter("eye_color", eye)
	m.set_shader_parameter("eye_power", power)
	m.set_shader_parameter("seam", seam)
	m.set_shader_parameter("glass", glass)
	m.set_shader_parameter("hot", hot)
	m.set_shader_parameter("hip_y", pivots[0])
	m.set_shader_parameter("hip_x", pivots[1])
	m.set_shader_parameter("sh_y", pivots[2])
	m.set_shader_parameter("sh_x", pivots[3])
	m.set_shader_parameter("head_y", pivots[4])
	m.set_shader_parameter("crack_scale", crack_scale)
	return m


static func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


static func build_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1313
	var imp_piv := [0.42, 0.1, 0.66, 0.2, 0.78]
	out.append(_imp(rng, false, _mat(0.0, Color(1.0, 0.62, 0.12), 3.0, 1.0, 0.0, 0.0, imp_piv)))
	out.append(_imp(rng, true, _mat(0.0, Color(1.0, 0.85, 0.3), 3.6, 1.7, 0.0, 0.0, imp_piv)))
	out.append(_bat(rng, _shader_mat(BAT_SHADER)))
	var golem_piv := [0.62, 0.22, 1.28, 0.5, 1.4]
	out.append(_golem(rng, false, _mat(1.0, Color(1.0, 0.5, 0.1), 3.2, 1.1, 1.0, 0.0, golem_piv, 5.0)))
	out.append(_golem(rng, true, _mat(1.0, Color(1.0, 0.95, 0.6), 3.6, 1.6, 0.0, 1.0, golem_piv, 5.0)))
	out.append(_slug(rng, _shader_mat(SLUG_SHADER)))
	return out


## For tools/render_caldera.gd.
static func preview_meshes() -> Array[Mesh]:
	return build_meshes()


static func _l(c: Color, limb: int) -> Color:
	return Color(c.r, c.g, c.b, limb / 8.0)


## One flat triangle (drawn both sides by the bat's shader).
static func _tri(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([a, b, c])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([n, n, n])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mb.add(arrays, Transform3D(), col)


## A magma imp (facing +Z, feet at the origin, about 0.95 m to the horn tips): crooked digitigrade
## legs with clawed feet, a lumpy rock body with a ridge of spines, long arms ending in three
## talons, a jutting head with a fanged jaw, ember eyes, curling horns and pointed ears, a long
## tail with a spade tip. The fiend (epic) has a blazing mane of flame down its head and back.
static func _imp(rng: RandomNumberGenerator, fiend: bool, mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var rock := ROCK2 if fiend else ROCK
	var hip_y := 0.42
	var sh_y := 0.66
	var head_y := 0.78
	for side in [1.0, -1.0]:
		var limb := 1 if side > 0 else 2
		var hip := Vector3(side * 0.1, hip_y, 0)
		var knee := Vector3(side * 0.13, 0.27, 0.11)
		var ankle := Vector3(side * 0.12, 0.09, -0.06)
		var toe := Vector3(side * 0.13, 0.02, 0.1)
		mb.limb(hip, knee, 0.07, 0.05, _l(rock, limb), 7)
		mb.limb(knee, ankle, 0.05, 0.035, _l(rock, limb), 6)
		mb.limb(ankle, toe, 0.04, 0.03, _l(rock, limb), 5)
		mb.add(MeshBuilder.sphere(0.055, 7, 5), Transform3D(Basis(), knee), _l(rock.lightened(0.05), limb))   # knobbly knee
		for t in 3:
			mb.limb(toe + Vector3((t - 1) * 0.03, 0, 0), toe + Vector3((t - 1) * 0.045, -0.01, 0.07), 0.014, 0.004, _l(HORN.darkened(0.3), limb), 3)
	# pelvis, belly, chest: a lumpy body of rock
	mb.add(ForestProps._lumpy(0.13, rng), Transform3D(Basis.from_scale(Vector3(1.15, 0.8, 0.95)), Vector3(0, hip_y + 0.02, -0.01)), _l(rock, 0))
	mb.add(ForestProps._lumpy(0.17, rng), Transform3D(Basis.from_scale(Vector3(1.0, 1.05, 0.9)), Vector3(0, 0.58, 0.04)), _l(rock, 0))
	mb.add(MeshBuilder.sphere(0.1, 8, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.9, 0.6)), Vector3(0, 0.5, 0.12)), _l(rock.darkened(0.2), 0))   # belly plate
	for k in 5:   # a ridge of rock spines down the back
		var y := 0.72 - k * 0.07
		mb.add(MeshBuilder.cone(0.035, 0.12 - k * 0.012, 4), Transform3D(Basis(Vector3(1, 0, 0), -0.7), Vector3(0, y, -0.13 + k * 0.01)), _l(HORN.darkened(0.45), 0))
	# shoulders, long arms, three-talon hands
	for side in [1.0, -1.0]:
		var limb := 3 if side > 0 else 4
		var sh := Vector3(side * 0.2, sh_y, 0.02)
		var el := Vector3(side * 0.25, 0.44, 0.08)
		var hand := Vector3(side * 0.23, 0.25, 0.13)
		mb.add(ForestProps._lumpy(0.07, rng), Transform3D(Basis(), sh), _l(rock, limb))
		mb.limb(sh, el, 0.05, 0.04, _l(rock, limb), 6)
		mb.limb(el, hand, 0.04, 0.033, _l(rock, limb), 6)
		mb.add(MeshBuilder.sphere(0.045, 7, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.2)), hand), _l(rock, limb))
		for f in 3:
			var a := (f - 1) * 0.45
			mb.limb(hand + Vector3(sin(a) * 0.03, -0.02, 0.03), hand + Vector3(sin(a) * 0.06, -0.09, 0.08), 0.014, 0.003, _l(HORN.darkened(0.25), limb), 3)
	# the head: a jutting lumpy skull, brow ridge, fanged jaw, ember eyes, horns, ears
	var hc := Vector3(0, head_y + 0.02, 0.1)
	mb.limb(Vector3(0, sh_y, 0.02), hc + Vector3(0, -0.04, -0.03), 0.06, 0.05, _l(rock, 5), 6)
	mb.add(ForestProps._lumpy(0.095, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.85, 1.1)), hc), _l(rock, 5))
	mb.add(MeshBuilder.box(Vector3(0.15, 0.03, 0.05)), Transform3D(Basis(Vector3(1, 0, 0), 0.3), hc + Vector3(0, 0.035, 0.07)), _l(rock.darkened(0.3), 5))   # brow
	mb.add(MeshBuilder.sphere(0.06, 7, 5), Transform3D(Basis.from_scale(Vector3(1.1, 0.55, 1.2)), hc + Vector3(0, -0.06, 0.06)), _l(rock, 5))   # jaw
	mb.add(MeshBuilder.box(Vector3(0.08, 0.02, 0.03)), Transform3D(Basis(), hc + Vector3(0, -0.045, 0.11)), _l(Color(1.0, 0.45, 0.08), 6))   # the glowing maw
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.cone(0.01, 0.04, 4), Transform3D(Basis(Vector3(1, 0, 0), PI), hc + Vector3(sd * 0.03, -0.035, 0.115)), _l(HORN, 5))   # fangs
		mb.add(MeshBuilder.sphere(0.019, 6, 4), Transform3D(Basis(), hc + Vector3(sd * 0.04, 0.012, 0.085)), _l(Color(1.0, 0.7, 0.2), 6))   # eyes
		# horns curling back and out
		var hb := hc + Vector3(sd * 0.055, 0.06, 0.0)
		var h1 := hb + Vector3(sd * 0.06, 0.08, -0.04)
		var h2 := h1 + Vector3(sd * 0.05, 0.03, -0.07)
		var h3 := h2 + Vector3(sd * 0.0, -0.03, -0.04)
		mb.limb(hb, h1, 0.025, 0.018, _l(HORN, 5), 5)
		mb.limb(h1, h2, 0.018, 0.01, _l(HORN.darkened(0.1), 5), 5)
		mb.limb(h2, h3, 0.01, 0.002, _l(HORN.darkened(0.2), 5), 4)
		mb.add(MeshBuilder.cone(0.025, 0.07, 4), Transform3D(Basis(Vector3(0, 0, 1), -sd * 1.2), hc + Vector3(sd * 0.1, 0.0, -0.02)), _l(rock, 5))   # ears
	# the tail: a lashing chain of rock ending in a glowing spade
	var prev := Vector3(0, hip_y, -0.1)
	for k in 7:
		var t := (k + 1) / 7.0
		var p := Vector3(sin(t * 3.0) * 0.06, hip_y - 0.1 * t + sin(t * PI) * 0.1, -0.1 - t * 0.45)
		mb.limb(prev, p, 0.035 * (1.0 - t * 0.6), 0.03 * (1.0 - t * 0.6), _l(rock, 7), 5)
		prev = p
	mb.add(MeshBuilder.cone(0.05, 0.1, 4), Transform3D(Basis(Vector3(1, 0, 0), -PI / 2).scaled(Vector3(1.0, 1.0, 0.35)), prev + Vector3(0, 0, -0.04)), _l(Color(1.0, 0.4, 0.08), 7))
	if fiend:   # a mane of flame: tongues rising from the head and down the back
		for k in 9:
			var t := k / 8.0
			var at := Vector3(0, lerpf(head_y + 0.09, 0.55, t), lerpf(0.06, -0.14, t))
			var h := lerpf(0.2, 0.1, t) * rng.randf_range(0.8, 1.2)
			for sd in [-1.0, 0.0, 1.0]:
				mb.add(MeshBuilder.cone(0.035, h, 4), Transform3D(Basis(Vector3(1, 0, 0), -0.4 - t * 0.6) * Basis(Vector3(0, 0, 1), sd * 0.3), at + Vector3(sd * 0.03, h * 0.4, 0)), _l(Color(1.0, 0.5 + rng.randf() * 0.2, 0.1), 6))
		for sd in [-1.0, 1.0]:   # burning shoulder spikes
			mb.add(MeshBuilder.cone(0.04, 0.14, 4), Transform3D(Basis(Vector3(0, 0, 1), -sd * 0.5), Vector3(sd * 0.22, sh_y + 0.08, 0.0)), _l(Color(1.0, 0.55, 0.15), 6))
	return mb.commit(mat)


## A cinder bat (origin at its body's centre, facing +Z): a smouldering body with a glowing
## belly, a snub-nosed head with tall ears and ember eyes, wings of dark membrane on bony fingers
## (1.4 m across) with glowing veins, and a tail of flame.
static func _bat(rng: RandomNumberGenerator, mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var body := Color(0.16, 0.07, 0.05)
	var membrane := Color(0.22, 0.07, 0.04)
	var bone := Color(0.1, 0.05, 0.04)
	mb.add(MeshBuilder.sphere(0.13, 10, 7), Transform3D(Basis.from_scale(Vector3(0.9, 0.8, 1.5)), Vector3.ZERO), _l(body, 0))
	mb.add(MeshBuilder.sphere(0.09, 8, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.4)), Vector3(0, -0.04, 0.02)), _l(Color(1.0, 0.42, 0.08), 6))   # glowing belly
	# head: snub snout, tall ears, eyes, fangs
	mb.add(MeshBuilder.sphere(0.075, 8, 6), Transform3D(Basis(), Vector3(0, 0.05, 0.18)), _l(body, 5))
	mb.add(MeshBuilder.sphere(0.035, 6, 4), Transform3D(Basis(), Vector3(0, 0.03, 0.25)), _l(body.lightened(0.05), 5))
	for sd in [-1.0, 1.0]:
		mb.add(MeshBuilder.cone(0.035, 0.11, 4), Transform3D(Basis(Vector3(0, 0, 1), -sd * 0.35), Vector3(sd * 0.04, 0.14, 0.16)), _l(body, 5))
		mb.add(MeshBuilder.sphere(0.017, 6, 4), Transform3D(Basis(), Vector3(sd * 0.03, 0.07, 0.24)), _l(Color(1.0, 0.85, 0.3), 6))
		mb.add(MeshBuilder.cone(0.008, 0.03, 4), Transform3D(Basis(Vector3(1, 0, 0), PI), Vector3(sd * 0.015, 0.0, 0.26)), _l(Color(0.9, 0.85, 0.7), 5))
	# wings: an arm to the wrist (inner) with a membrane back to the body, four fingers fanning
	# out from the wrist (outer) with ragged membrane panels between them
	for sd in [-1.0, 1.0]:
		var inner := 1 if sd > 0 else 2
		var outer := 3 if sd > 0 else 4
		var sh := Vector3(sd * 0.1, 0.05, 0.05)
		var wr := Vector3(sd * 0.55, 0.05, 0.0)
		mb.limb(sh, wr, 0.022, 0.016, _l(bone, inner), 4)
		var tips := [Vector3(sd * 0.98, 0.08, 0.08), Vector3(sd * 1.0, 0.05, -0.16), Vector3(sd * 0.82, 0.04, -0.36), Vector3(sd * 0.56, 0.04, -0.42)]
		var body_back := Vector3(sd * 0.08, 0.02, -0.18)
		_tri(mb, sh, wr, Vector3(sd * 0.45, 0.04, -0.4), _l(membrane, inner))
		_tri(mb, sh, Vector3(sd * 0.45, 0.04, -0.4), body_back, _l(membrane, inner))
		for f in tips.size():
			var tip: Vector3 = tips[f]
			mb.limb(wr, tip, 0.012, 0.004, _l(bone, outer), 3)
			if f > 0:
				var prev: Vector3 = tips[f - 1]
				var notch := (prev + tip) * 0.5 + (wr - (prev + tip) * 0.5) * 0.22   # the scalloped edge
				_tri(mb, wr, prev, notch, _l(membrane, outer))
				_tri(mb, wr, notch, tip, _l(membrane, outer))
		_tri(mb, wr, tips[3], Vector3(sd * 0.45, 0.04, -0.4), _l(membrane, outer))
		mb.add(MeshBuilder.cone(0.012, 0.05, 4), Transform3D(Basis(Vector3(1, 0, 0), PI / 2), wr + Vector3(0, 0, 0.04)), _l(Color(0.85, 0.8, 0.7), outer))   # thumb claw
	# a tail of flame streaming behind
	for k in 5:
		var t := k / 4.0
		mb.add(MeshBuilder.cone(0.06 * (1.0 - t * 0.7), 0.18, 5), Transform3D(Basis(Vector3(1, 0, 0), -PI / 2), Vector3(0, -0.01, -0.2 - t * 0.14)), _l(Color(1.0, lerpf(0.65, 0.25, t), 0.08), 7))
	for sd in [-1.0, 1.0]:   # little hooked feet
		mb.limb(Vector3(sd * 0.05, -0.08, -0.08), Vector3(sd * 0.06, -0.14, -0.14), 0.012, 0.008, _l(bone, 0), 3)
	return mb.commit(mat)


## An obsidian golem (facing +Z, feet at the origin, GOLEM_HEIGHT tall at scale 1): stumpy column
## legs, a massive faceted torso of black glass split open at the chest over a lava core, boulder
## shoulders, long arms with huge fists, a small head sunk between the shoulders with a glowing
## eye slit, shards of glass jutting from its back. The molten golem is the same, white-hot.
static func _golem(rng: RandomNumberGenerator, molten: bool, mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var ob := OBSIDIAN if not molten else Color(0.07, 0.04, 0.03)
	var hip_y := 0.62
	var sh_y := 1.28
	for side in [1.0, -1.0]:
		var limb := 1 if side > 0 else 2
		var hip := Vector3(side * 0.22, hip_y, 0)
		var knee := Vector3(side * 0.25, 0.34, 0.04)
		mb.add(MeshBuilder.cyl(0.13, 0.16, 0.36, 6), Transform3D(Basis(Vector3.UP, rng.randf()), hip.lerp(knee, 0.5)), _l(ob, limb))
		mb.add(MeshBuilder.cyl(0.15, 0.13, 0.32, 6), Transform3D(Basis(Vector3.UP, rng.randf()), knee.lerp(Vector3(side * 0.25, 0.08, 0.02), 0.5)), _l(ob, limb))
		mb.add(MeshBuilder.box(Vector3(0.3, 0.12, 0.38)), Transform3D(Basis(Vector3.UP, 0.1 * side), Vector3(side * 0.25, 0.06, 0.06)), _l(ob, limb))   # blocky foot
		mb.add(ForestProps._lumpy(0.12, rng), Transform3D(Basis(), knee), _l(ob, limb))
	# hips and the great torso: faceted blocks of glass, wider at the shoulders
	mb.add(MeshBuilder.cyl(0.3, 0.26, 0.26, 6), Transform3D(Basis(Vector3.UP, 0.3), Vector3(0, hip_y + 0.08, 0)), _l(ob, 0))
	mb.add(MeshBuilder.cyl(0.46, 0.32, 0.62, 7), Transform3D(Basis(Vector3.UP, 0.2).scaled(Vector3(1.0, 1.0, 0.72)), Vector3(0, 1.0, 0)), _l(ob, 0))
	for k in 6:   # angular plates over it
		var a := TAU * k / 6.0 + 0.4
		mb.add(MeshBuilder.box(Vector3(0.28, 0.32, 0.08)), Transform3D(Basis(Vector3.UP, -a + PI / 2) * Basis(Vector3(1, 0, 0), 0.2), Vector3(cos(a) * 0.36, 1.05 + 0.08 * sin(k * 2.0), sin(a) * 0.26)), _l(ob.lightened(0.04), 0))
	# the lava core glowing out of a split in the chest
	mb.add(MeshBuilder.sphere(0.17, 10, 7), Transform3D(Basis.from_scale(Vector3(1.0, 1.2, 0.8)), Vector3(0, 1.02, 0.12)), _l(Color(1.0, 0.5, 0.12), 6))
	for sd in [-1.0, 1.0]:   # the split's jagged lips
		mb.add(MeshBuilder.cone(0.07, 0.3, 4), Transform3D(Basis(Vector3(0, 0, 1), sd * 1.3), Vector3(sd * 0.1, 1.05, 0.2)), _l(ob, 0))
	# shoulders, arms, fists
	for side in [1.0, -1.0]:
		var limb := 3 if side > 0 else 4
		var sh := Vector3(side * 0.5, sh_y, 0)
		mb.add(ForestProps._lumpy(0.22, rng), Transform3D(Basis.from_scale(Vector3(1.1, 0.9, 1.0)), sh + Vector3(side * 0.02, 0.06, 0)), _l(ob, limb))
		var el := Vector3(side * 0.6, 0.86, 0.06)
		var fist := Vector3(side * 0.58, 0.46, 0.12)
		mb.add(MeshBuilder.cyl(0.12, 0.15, 0.42, 6), Transform3D(Basis(Vector3(0, 0, 1), side * 0.2), sh.lerp(el, 0.5)), _l(ob, limb))
		mb.add(MeshBuilder.cyl(0.14, 0.12, 0.4, 6), Transform3D(Basis(), el.lerp(fist, 0.5)), _l(ob, limb))
		mb.add(ForestProps._lumpy(0.2, rng), Transform3D(Basis.from_scale(Vector3(1.0, 0.95, 1.1)), fist + Vector3(0, -0.06, 0.02)), _l(ob, limb))
		mb.add(MeshBuilder.sphere(0.05, 6, 4), Transform3D(Basis(), el), _l(Color(1.0, 0.5, 0.1), 6))   # glowing elbow joint
		for k in 2:   # glass spikes on the shoulder
			mb.add(MeshBuilder.cone(0.06, 0.28, 4), Transform3D(Basis(Vector3(0, 0, 1), -side * (0.4 + k * 0.4)), sh + Vector3(side * 0.08, 0.2, -0.05 + k * 0.08)), _l(ob, limb))
	# the head: a small block sunk between the shoulders, a heavy brow, a glowing slit
	var hc := Vector3(0, 1.42, 0.08)
	mb.add(MeshBuilder.cyl(0.13, 0.17, 0.24, 6), Transform3D(Basis(Vector3.UP, 0.5), hc), _l(ob, 5))
	mb.add(MeshBuilder.box(Vector3(0.3, 0.06, 0.12)), Transform3D(Basis(), hc + Vector3(0, 0.06, 0.12)), _l(ob, 5))
	mb.add(MeshBuilder.box(Vector3(0.2, 0.025, 0.04)), Transform3D(Basis(), hc + Vector3(0, 0.01, 0.15)), _l(Color(1.0, 0.6, 0.15), 6))
	# glass shards jutting from its back
	for k in 5:
		var a := rng.randf_range(-0.8, 0.8)
		mb.add(MeshBuilder.cone(0.07, rng.randf_range(0.25, 0.45), 4), Transform3D(Basis(Vector3(1, 0, 0), -0.5 - rng.randf() * 0.4) * Basis(Vector3(0, 0, 1), a), Vector3(a * 0.2, 1.1 + rng.randf() * 0.2, -0.25)), _l(ob, 0))
	return mb.commit(mat)


## A lava slug (facing +Z, origin under its middle, about 1.7 m long and 0.55 m high): a soft
## body tapering to the tail, dark crust plates on its back with molten seams between, a glowing
## underside and foot fringe, two eye stalks with ember eyes, a round mouth.
static func _slug(rng: RandomNumberGenerator, mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var flesh := Color(0.35, 0.12, 0.06)
	for k in 9:
		var t := k / 8.0
		var z := lerpf(-0.85, 0.65, t)
		var r := 0.28 * sin(lerpf(0.35, 2.75, t)) + 0.04
		mb.add(MeshBuilder.sphere(r, 12, 7), Transform3D(Basis.from_scale(Vector3(1.15, 0.85, 1.2)), Vector3(0, r * 0.8, z)), _l(flesh.darkened(0.1 * (k % 2)), 0))
		# the molten foot fringe underneath
		mb.add(MeshBuilder.cyl(r * 1.25, r * 1.3, 0.05, 12), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.1)), Vector3(0, 0.03, z)), _l(Color(1.0, 0.42, 0.08), 6))
	# crust plates riding its back, molten seams showing between them
	for k in 8:
		var t := (k + 0.5) / 8.0
		var z := lerpf(-0.75, 0.5, t)
		var r := 0.28 * sin(lerpf(0.35, 2.75, t)) + 0.04
		var c := CRUST.darkened(rng.randf_range(0.0, 0.3))
		mb.add(MeshBuilder.box(Vector3(r * 1.7, 0.06, 0.16)), Transform3D(Basis(Vector3(1, 0, 0), rng.randf_range(-0.15, 0.15)) * Basis(Vector3(0, 0, 1), rng.randf_range(-0.1, 0.1)), Vector3(0, r * 1.55, z)), _l(c, 7))
		for sd in [-1.0, 1.0]:
			mb.add(MeshBuilder.box(Vector3(0.12, 0.05, 0.14)), Transform3D(Basis(Vector3(0, 0, 1), sd * 0.9), Vector3(sd * r * 0.95, r * 1.15, z)), _l(c.lightened(0.04), 7))
		mb.add(MeshBuilder.box(Vector3(r * 1.5, 0.02, 0.025)), Transform3D(Basis(), Vector3(0, r * 1.5, z + 0.085)), _l(Color(1.0, 0.5, 0.12), 6))   # the seam
	# the head: a round mouth, eye stalks
	mb.add(MeshBuilder.cyl(0.07, 0.08, 0.03, 10), Transform3D(Basis(Vector3(1, 0, 0), PI / 2), Vector3(0, 0.14, 0.86)), _l(Color(1.0, 0.45, 0.1), 6))
	for sd in [-1.0, 1.0]:
		var base := Vector3(sd * 0.09, 0.3, 0.6)
		var tip := Vector3(sd * 0.16, 0.6, 0.72)
		mb.limb(base, tip, 0.035, 0.02, _l(flesh, 5), 5)
		mb.add(MeshBuilder.sphere(0.04, 7, 5), Transform3D(Basis(), tip), _l(Color(1.0, 0.75, 0.25), 6))
		mb.limb(Vector3(sd * 0.12, 0.12, 0.8), Vector3(sd * 0.2, 0.08, 0.95), 0.02, 0.008, _l(flesh, 5), 4)   # feelers
	return mb.commit(mat)
