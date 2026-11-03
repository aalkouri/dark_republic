class_name GroundDisc
extends MeshInstance3D
## A flat coloured disc that drapes over the hills: a subdivided plane whose vertices are
## pushed onto the terrain in the vertex shader (sampling the ground's height texture), so
## markers like the Meteor target, Fire Nova's glow and the Stink Aura hug slopes instead of
## cutting into them. Radius 1 at scale 1; scale X/Z to resize. Move it freely.

const SHADER := """
shader_type spatial;
render_mode unshaded, world_vertex_coords, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled%s;
uniform vec4 color : source_color = vec4(1.0);
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float h_origin = 0.0;
uniform float h_size = 1.0;
uniform float has_height = 0.0;
uniform float lift = 0.1;
uniform float inner = 0.0;   // > 0: a ring (band from inner to 1)
uniform float arc = 4.0;     // < PI: only a wedge this many radians either side of local -Z
uniform float fill = 1.0;    // < 1: a telegraph, solid out to `fill` of the radius, faint beyond
uniform vec4 clip_rect = vec4(-1e9, -1e9, 1e9, 1e9);   // world x/z min, x/z max: only drawn inside
uniform float pattern = 0.0;   // 1: Stink Aura (drifting, swirling blotches of fumes, a brighter rim)
varying vec2 local_uv;
varying vec2 wxz;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1.0, 0.0)), f.x), mix(h2(i + vec2(0.0, 1.0)), h2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	local_uv = UV;
	wxz = VERTEX.xz;
	if (has_height > 0.5) {
		vec2 uv = (VERTEX.xz - h_origin + 0.5) / h_size;
		VERTEX.y = texture(height_tex, uv).r + lift;
	}
}

void fragment() {
	if (wxz.x < clip_rect.x || wxz.y < clip_rect.y || wxz.x > clip_rect.z || wxz.y > clip_rect.w) { discard; }
	float d = length(local_uv - 0.5) * 2.0;
	float a = color.a * (1.0 - smoothstep(0.96, 1.0, d));
	if (inner > 0.0) { a *= smoothstep(inner - 0.04, inner, d); }
	if (arc < 3.14) {
		vec2 q = local_uv - 0.5;
		float ang = acos(clamp(dot(normalize(q + vec2(0.00001)), vec2(0.0, -1.0)), -1.0, 1.0));
		a *= 1.0 - smoothstep(arc - 0.03, arc, ang);
	}
	if (fill < 1.0) { a *= d < fill ? 1.0 : (d > 0.93 ? 0.9 : 0.28); }
	vec3 col = color.rgb;
	if (pattern > 0.5) {
		vec2 q = (local_uv - 0.5) * 2.0;
		float t = TIME * 0.25;
		mat2 rot = mat2(vec2(cos(t), sin(t)), vec2(-sin(t), cos(t)));
		vec2 w = rot * q;
		float n = vn(w * 3.2 + vec2(TIME * 0.35, -TIME * 0.2)) * 0.6 + vn(q * 7.5 - vec2(TIME * 0.5, TIME * 0.3)) * 0.4;
		float blot = smoothstep(0.35, 0.75, n);
		col = mix(vec3(0.22, 0.32, 0.08), vec3(0.72, 0.95, 0.25), blot);
		float rim = smoothstep(0.82, 0.97, d);
		col = mix(col, vec3(0.8, 1.0, 0.4), rim * 0.6);
		a *= 0.45 + 1.1 * blot + rim * 1.4;
	}
	if (a <= 0.001) { discard; }
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

static var _shaders := {}

var alpha := 1.0:
	set(v):
		alpha = v
		if _mat:
			_mat.set_shader_parameter("color", Color(color, alpha))
var color := Color.WHITE:
	set(v):
		color = v
		if _mat:
			_mat.set_shader_parameter("color", Color(color, alpha))
var _mat: ShaderMaterial


## Make it a ring: only the band from `fraction` of the radius out to the edge is drawn.
func set_ring(fraction: float) -> void:
	_mat.set_shader_parameter("inner", fraction)


## Only draw a wedge `half_angle` radians either side of the disc's forward (-Z).
func set_arc(half_angle: float) -> void:
	_mat.set_shader_parameter("arc", half_angle)


## Telegraph fill: solid out to `f` of the radius, a faint area with a bright rim beyond it.
func set_fill(f: float) -> void:
	_mat.set_shader_parameter("fill", f)


## A pattern instead of a flat colour (1: the Stink Aura's swirling fumes).
func set_pattern(p: int) -> void:
	_mat.set_shader_parameter("pattern", float(p))


func set_lift(metres: float) -> void:
	_mat.set_shader_parameter("lift", metres)


## Lie flat at the disc's own height instead of draping over the ground (e.g. on a table top).
func set_flat() -> void:
	_mat.set_shader_parameter("has_height", 0.0)


## Only draw the part inside this world-space rectangle (x0, z0, x1, z1).
func set_clip(x0: float, z0: float, x1: float, z1: float) -> void:
	_mat.set_shader_parameter("clip_rect", Vector4(x0, z0, x1, z1))


static func create(radius: float, c: Color, additive := false) -> GroundDisc:
	var g := GroundDisc.new()
	var key := "add" if additive else "mix"
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = SHADER % (", blend_add" if additive else "")
		_shaders[key] = sh
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.subdivide_width = 24
	plane.subdivide_depth = 24
	g._mat = ShaderMaterial.new()
	g._mat.shader = _shaders[key]
	g._mat.render_priority = 2
	var ground := SwampWater.current
	if ground != null and ground.height_texture != null:
		g._mat.set_shader_parameter("height_tex", ground.height_texture)
		g._mat.set_shader_parameter("h_origin", ground.horigin)
		g._mat.set_shader_parameter("h_size", float(ground.hsize))
		g._mat.set_shader_parameter("has_height", 1.0)
	plane.material = g._mat
	g.mesh = plane
	g.top_level = true
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.extra_cull_margin = 16.0   # the shader moves vertices up/down
	g.color = Color(c.r, c.g, c.b)
	g.alpha = c.a
	g.scale = Vector3(radius, 1.0, radius)
	return g
