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
varying vec2 local_uv;

void vertex() {
	local_uv = UV;
	if (has_height > 0.5) {
		vec2 uv = (VERTEX.xz - h_origin + 0.5) / h_size;
		VERTEX.y = texture(height_tex, uv).r + lift;
	}
}

void fragment() {
	float d = length(local_uv - 0.5) * 2.0;
	float a = color.a * (1.0 - smoothstep(0.96, 1.0, d));
	if (inner > 0.0) { a *= smoothstep(inner - 0.04, inner, d); }
	if (a <= 0.001) { discard; }
	ALBEDO = color.rgb;
	ALPHA = a;
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


func set_lift(metres: float) -> void:
	_mat.set_shader_parameter("lift", metres)


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
