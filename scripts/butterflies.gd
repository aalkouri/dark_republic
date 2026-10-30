class_name Butterflies
extends Node3D
## Magical Forest butterflies (daytime; Fireflies come out at night). COUNT of them flutter about
## in a box that follows the camera, so there are always some around you without filling the
## whole arena: each wanders on its own meandering path a metre or two above the grass, bobbing
## with every wingbeat, and now and then settles on the ground with its wings slowly opening and
## closing before flying off again. One MultiMesh; the wings flap in the vertex shader.

const COUNT := 70
const EXTENT := 22.0          # half-size of the box around the camera
const SPEED := 2.2
const SIZE := 0.22            # one wing's span (m)
const COLORS := [Color(1.0, 0.55, 0.1), Color(0.25, 0.55, 1.0), Color(1.0, 0.92, 0.25), Color(1.0, 0.4, 0.75),
	Color(0.95, 0.95, 1.0), Color(0.55, 0.35, 1.0), Color(0.3, 0.85, 0.95)]

const SHADER := """
shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_opaque;
// COLOR.rgb = wing colour (per butterfly), COLOR.a = wingbeat phase; UV.x: 0 at the body, 1 at
// the wing tip; UV.y along the wing. INSTANCE_CUSTOM is avoided on purpose (see BushField).
varying vec3 wing_col;
varying float side;
void vertex() {
	wing_col = COLOR.rgb;
	float phase = COLOR.a * 6.2832;
	// flap: rotate each wing about the body (Z axis); slower and lazier when settled (the
	// instance's Y axis is squashed a little to say so)
	float ratio = length(MODEL_MATRIX[1].xyz) / max(length(MODEL_MATRIX[0].xyz), 0.0001);
	float settled = 1.0 - smoothstep(0.92, 0.98, ratio);
	float speed = mix(18.0, 2.0, settled);
	float a = mix(0.15, 1.15, 0.5 + 0.5 * sin(TIME * speed + phase));
	side = sign(VERTEX.x);
	float r = abs(VERTEX.x);
	VERTEX = vec3(side * r * cos(a), r * sin(a), VERTEX.z);
}
void fragment() {
	// a rounded forewing and hindwing, dark edges, a pale spot
	vec2 uv = UV;
	float fore = length((uv - vec2(0.45, 0.32)) * vec2(1.0, 1.25));
	float hind = length((uv - vec2(0.35, 0.75)) * vec2(1.2, 1.4));
	float shape = min(fore, hind);
	if (shape > 0.5) { discard; }
	vec3 col = wing_col;
	col = mix(col, vec3(0.05, 0.04, 0.04), smoothstep(0.38, 0.47, shape));   // dark border
	col = mix(col, vec3(1.0), (1.0 - smoothstep(0.05, 0.1, length(uv - vec2(0.65, 0.3)))) * 0.85);   // spot
	col = mix(vec3(0.05), col, smoothstep(0.0, 0.06, uv.x));   // body
	ALBEDO = col;
}
"""

var _mm: MultiMesh
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _turn := PackedFloat32Array()     # current turning rate
var _rest := PackedFloat32Array()     # > 0: settled on the ground for this long
var _phase := PackedFloat32Array()
var _col: Array[Color] = []
var _center := Vector3.ZERO
var _t := 0.0


func _ready() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = _wing_mesh(mat)
	_mm.instance_count = COUNT
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-500, -100, -500), Vector3(1000, 300, 1000))
	add_child(mmi)
	for i in COUNT:
		_pos.append(Vector3.INF)
		_vel.append(Vector3.ZERO)
		_turn.append(0.0)
		_rest.append(0.0)
		_phase.append(randf())
		_col.append(COLORS[i % COLORS.size()].lerp(Color.WHITE, randf() * 0.15))


## Two wings (left and right of the body along Z), each a quad from the body out to x = +-1.
func _wing_mesh(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sgn in [-1.0, 1.0]:
		var quad := [Vector3(0.0, 0, -0.5), Vector3(sgn, 0, -0.5), Vector3(sgn, 0, 0.5), Vector3(0.0, 0, 0.5)]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[k])
			st.set_color(Color.WHITE)
			st.add_vertex(quad[k])
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


func _ground(x: float, z: float) -> float:
	return SwampWater.height_at(x, z)


func _respawn(i: int) -> void:
	var a := randf() * TAU
	var r := EXTENT * sqrt(randf_range(0.02, 1.0))   # spread evenly over the area, some close by
	var x := _center.x + cos(a) * r
	var z := _center.z + sin(a) * r
	_pos[i] = Vector3(x, _ground(x, z) + randf_range(0.6, 2.4), z)
	var h := randf() * TAU
	_vel[i] = Vector3(cos(h), 0, sin(h)) * SPEED
	_rest[i] = 0.0


func _process(dt: float) -> void:
	_t += dt
	var cam := get_viewport().get_camera_3d()
	if cam:
		_center = cam.global_position
	var buf := PackedFloat32Array()
	buf.resize(COUNT * 16)
	for i in COUNT:
		var p := _pos[i]
		if p == Vector3.INF or Vector2(p.x - _center.x, p.z - _center.z).length() > EXTENT * 1.3:
			_respawn(i)
			p = _pos[i]
		var v := _vel[i]
		var g := _ground(p.x, p.z)
		var scale_y := SIZE
		if _rest[i] > 0.0:   # settled on the grass, wings slowly opening and closing
			_rest[i] -= dt
			p.y = g + 0.35
			scale_y = SIZE * 0.9
			if _rest[i] <= 0.0:
				v = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * SPEED
		else:
			# meander: a turning rate that drifts, a gentle pull back toward a comfortable height
			_turn[i] = clampf(_turn[i] + randf_range(-6.0, 6.0) * dt, -2.2, 2.2)
			v = v.rotated(Vector3.UP, _turn[i] * dt)
			var want_h := g + 1.0 + 0.8 * sin(_t * 0.7 + _phase[i] * 9.0)
			v.y = clampf((want_h - p.y) * 1.5, -1.5, 1.5)
			p += v * dt
			p.y += sin(_t * 18.0 + _phase[i] * TAU) * 0.012   # bobbing with each wingbeat
			if p.y < g + 0.4:
				p.y = g + 0.4
			if randf() < dt * 0.05:   # now and then, settle for a while
				_rest[i] = randf_range(2.0, 5.0)
		_pos[i] = p
		_vel[i] = v
		var fwd := Vector3(v.x, 0, v.z)
		if fwd.length() < 0.01:
			fwd = Vector3.FORWARD
		var b := Basis.looking_at(fwd.normalized(), Vector3.UP) * Basis.from_scale(Vector3(SIZE, scale_y, SIZE))
		var o := i * 16
		buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = p.x
		buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = p.y
		buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = p.z
		var c: Color = _col[i]
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = _phase[i]
	_mm.buffer = buf


func count() -> int:
	return COUNT
