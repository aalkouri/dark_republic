class_name SpiderWebs
extends Node3D
## The Arachnid's webs on the floor, and what they do to you:
##   - THE WEB SWATH (her ultimate, at 75%, 50% and 10% health): one half of the keep (west,
##     east, north or south, picked at random) is covered in webs, spreading out from her over
##     SPREAD seconds. They last SWATH_LIFE (a minute), then fade.
##   - THE TRAIL: wherever she walks on the floor she leaves webs behind her that fade after
##     TRAIL_LIFE (about 3 s).
## Standing in any web (on the ground) webs you: SLOW (half speed) and no jumping, lasting
## LINGER seconds after you leave the last web.

const SLOW := 0.5
const LINGER := 4.0
const SWATH_LIFE := 60.0
const SPREAD := 2.5
const FADE := 1.5
const TRAIL_LIFE := 3.0
const TRAIL_RADIUS := 2.8
const TRAIL_STEP := 1.6          # metres she walks between trail webs
const TRAIL_MAX := 48
const HALF := 220.0              # the keep's half-size
const HALVES := ["west", "east", "north", "south"]

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float cell = 6.0;          // metres per web (the swath); single = 1 draws one web over the quad
uniform float single = 0.0;
uniform vec2 origin = vec2(0.0);   // the swath spreads out from here...
uniform float reveal = 1e6;        // ...this far so far
uniform float alpha = 1.0;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float web(vec2 p, float rot, float spokes) {
	// p in -0.5..0.5: radial spokes and polygonal rings, sagging a little between spokes
	float r = length(p) * 2.0;
	if (r > 1.0) { return 0.0; }
	float a = atan(p.y, p.x) + rot;
	float seg = 6.2832 / spokes;
	float m = mod(a, seg);
	float spoke = 1.0 - smoothstep(0.0, 0.012 / max(r, 0.08), min(m, seg - m));
	float poly = r * cos(seg * 0.5) / cos(m - seg * 0.5);
	poly += 0.03 * sin(m / seg * 3.1416);   // sag
	float fr = fract(poly * 7.0);
	float rings = 1.0 - smoothstep(0.0, 0.07, min(fr, 1.0 - fr));
	rings *= step(0.12, poly);
	return max(spoke, rings * 0.85) * (1.0 - smoothstep(0.85, 1.0, r));
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float w;
	if (single > 0.5) {
		w = web(UV - 0.5, 0.0, 9.0);
	} else {
		vec2 g = wpos.xz / cell;
		vec2 id = floor(g);
		vec2 f = fract(g) - 0.5 + (vec2(hash(id), hash(id + 3.0)) - 0.5) * 0.2;
		w = web(f * 1.05, hash(id + 7.0) * 6.2832, 7.0 + floor(hash(id + 9.0) * 4.0));
		// strands joining neighbouring webs
		w = max(w, (1.0 - smoothstep(0.0, 0.012, abs(fract(g.x + g.y * 0.37) - 0.5))) * 0.35);
		float d = length(wpos.xz - origin);
		w *= 1.0 - smoothstep(reveal - 4.0, reveal, d);
	}
	if (w < 0.02) { discard; }
	ALBEDO = vec3(0.86, 0.88, 0.92);
	EMISSION = vec3(0.25, 0.27, 0.3) * w;
	ALPHA = w * 0.7 * alpha;
}
"""

var boss: Node3D
var player: Node3D
var swaths: Array = []           # {half, node, mat, t, origin}
var trail: Array = []            # {node, mat, at, t}
var webbed_t := 0.0              # tests: seconds the player has spent webbed
var swath_count := 0
var _shader: Shader
var _last_drop := Vector3.INF
var _quad: QuadMesh


func _ready() -> void:
	_shader = Shader.new()
	_shader.code = SHADER
	_quad = QuadMesh.new()
	_quad.size = Vector2(TRAIL_RADIUS * 2.0, TRAIL_RADIUS * 2.0)
	_quad.orientation = PlaneMesh.FACE_Y


## Cover one half of the keep in webs, spreading out from `from`. Returns the half's name.
func swath(from: Vector3, half := "") -> String:
	if half == "":
		half = HALVES[randi() % HALVES.size()]
	swath_count += 1
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("origin", Vector2(from.x, from.z))
	mat.set_shader_parameter("reveal", 0.0)
	var pm := PlaneMesh.new()
	var size := Vector2(HALF * 2.0, HALF) if half in ["north", "south"] else Vector2(HALF, HALF * 2.0)
	pm.size = size
	pm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	var c := Vector3.ZERO
	match half:
		"west": c = Vector3(-HALF * 0.5, 0, 0)
		"east": c = Vector3(HALF * 0.5, 0, 0)
		"north": c = Vector3(0, 0, -HALF * 0.5)
		_: c = Vector3(0, 0, HALF * 0.5)
	mi.global_position = c + Vector3(0, 0.05, 0)
	swaths.append({"half": half, "node": mi, "mat": mat, "t": 0.0, "origin": Vector2(from.x, from.z)})
	return half


## Leave trail webs as she walks along the floor (call every frame with her feet).
func trail_at(feet: Vector3) -> void:
	if _last_drop != Vector3.INF and Vector2(feet.x - _last_drop.x, feet.z - _last_drop.z).length() < TRAIL_STEP:
		return
	_last_drop = feet
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("single", 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	mi.global_position = Vector3(feet.x, maxf(feet.y, 0.0) + 0.06 + 0.002 * (trail.size() % 5), feet.z)
	mi.rotation.y = randf() * TAU
	trail.append({"node": mi, "mat": mat, "at": feet, "t": 0.0})
	if trail.size() > TRAIL_MAX:
		(trail.pop_front()["node"] as Node).queue_free()


func in_web(p: Vector3) -> bool:
	for s in swaths:
		if _in_half(p, s["half"]) and Vector2(p.x, p.z).distance_to(s["origin"]) < _reveal(s) and float(s["t"]) < SWATH_LIFE + FADE * 0.5:
			return true
	for w in trail:
		var at: Vector3 = w["at"]
		if Vector2(p.x - at.x, p.z - at.z).length() < TRAIL_RADIUS * 0.85:
			return true
	return false


static func _in_half(p: Vector3, half: String) -> bool:
	match half:
		"west": return p.x < 0.0
		"east": return p.x >= 0.0
		"north": return p.z < 0.0
		_: return p.z >= 0.0


func _reveal(s: Dictionary) -> float:
	return 600.0 * clampf(float(s["t"]) / SPREAD, 0.0, 1.0)


func clear() -> void:
	for s in swaths:
		(s["node"] as Node).queue_free()
	swaths.clear()
	for w in trail:
		(w["node"] as Node).queue_free()
	trail.clear()


func _physics_process(dt: float) -> void:
	for k in range(swaths.size() - 1, -1, -1):
		var s: Dictionary = swaths[k]
		s["t"] += dt
		var t: float = s["t"]
		var mat: ShaderMaterial = s["mat"]
		mat.set_shader_parameter("reveal", _reveal(s))
		mat.set_shader_parameter("alpha", clampf((SWATH_LIFE + FADE - t) / FADE, 0.0, 1.0))
		if t >= SWATH_LIFE + FADE:
			(s["node"] as Node).queue_free()
			swaths.remove_at(k)
	for k in range(trail.size() - 1, -1, -1):
		var w: Dictionary = trail[k]
		w["t"] += dt
		var t: float = w["t"]
		(w["mat"] as ShaderMaterial).set_shader_parameter("alpha", clampf((TRAIL_LIFE - t) / 0.8, 0.0, 1.0))
		if t >= TRAIL_LIFE:
			(w["node"] as Node).queue_free()
			trail.remove_at(k)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var grounded: bool = player.is_on_floor() if player.has_method("is_on_floor") else true
	if grounded and in_web(player.global_position) and player.has_method("web"):
		player.web(LINGER, SLOW)
		webbed_t += dt
