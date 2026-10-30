class_name DistantCastle
extends Node3D
## A great castle far off on the horizon of the outdoor maps (the Swamp and the Magical Forest):
## the same castle on both, never reachable, standing in a different direction every time a map
## loads. Like the sky it keeps its distance (it follows the camera across the arena), so it's
## always there on the skyline: a hazy silhouette in the colour of the distant air, base lost
## in the mist, with a few lit windows at night.
##
## Built from simple shapes: a tall central keep with a spire, four round corner towers with
## conical roofs, curtain walls with battlements, a gatehouse and banners.

const DISTANCE := 330.0      # metres from the camera (inside its 400 m far plane)
const SCALE := 1.0
const SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back, depth_draw_opaque;
uniform vec3 haze : source_color = vec3(0.4, 0.45, 0.5);   // the air colour it melts into
uniform vec3 body : source_color = vec3(0.25, 0.28, 0.32);  // the stone, seen through the haze
uniform float mist_top = 40.0;     // below this height the base melts into the haze
uniform float rim = 0.0;           // a touch of light along the top edges (day)
varying float h;
varying vec3 n;
void vertex() {
	h = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - MODEL_MATRIX[3].y;
	n = NORMAL;
}
void fragment() {
	vec3 col = body;
	col = mix(col, col * 1.18, clamp(n.x * 0.5 + 0.5, 0.0, 1.0) * 0.6);   // one side a little lighter
	col += vec3(rim) * smoothstep(0.6, 1.0, n.y);
	col = mix(haze, col, smoothstep(0.0, mist_top, h));                // base lost in the mist
	ALBEDO = col;
}
"""

var bearing := 0.0
var _mat: ShaderMaterial
var _windows: StandardMaterial3D


## Add the castle under `parent`, in a random direction from `rng`. `haze` is the colour of
## the distant air (the fog colour), `night` lights its windows.
static func add(parent: Node3D, rng: RandomNumberGenerator, haze: Color, night: bool) -> DistantCastle:
	var c := DistantCastle.new()
	c.bearing = rng.randf() * TAU
	c.name = "DistantCastle"
	parent.add_child(c)
	c.build(haze, night, rng)
	return c


func build(haze: Color, night: bool, rng: RandomNumberGenerator) -> void:
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("haze", haze)
	var body := haze.darkened(0.42 if night else 0.3).lerp(Color(0.2, 0.22, 0.27), 0.25)
	_mat.set_shader_parameter("body", body)
	_mat.set_shader_parameter("rim", 0.0 if night else 0.05)
	_windows = StandardMaterial3D.new()
	_windows.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_windows.disable_fog = true
	_windows.albedo_color = Color(1.0, 0.75, 0.35) if night else body.darkened(0.35)
	var root := Node3D.new()
	root.scale = Vector3.ONE * SCALE
	add_child(root)
	# Curtain walls round a square bailey, with battlements
	var half := 46.0
	var wall_h := 34.0
	for side in 4:
		var a := side * PI * 0.5
		var along := Vector3(cos(a), 0, sin(a))
		var out := Vector3(-sin(a), 0, cos(a))
		var mid := out * half
		_box(root, mid + Vector3(0, wall_h * 0.5, 0), Vector3(half * 2.0, wall_h, 6.0), a)
		for k in 15:   # merlons
			var x := -half + 4.0 + k * (half * 2.0 - 8.0) / 14.0
			_box(root, mid + along * x + Vector3(0, wall_h + 2.0, 0), Vector3(3.0, 4.0, 6.4), a)
	# Corner towers with pointed roofs
	for k in 4:
		var p := Vector3((1 if k % 2 else -1) * half, 0, (1 if k / 2 else -1) * half)
		var th := rng.randf_range(58.0, 70.0)
		_tower(root, p, 9.5, th, 22.0)
	# Gatehouse on the front wall
	_box(root, Vector3(0, 24.0, half + 2.0), Vector3(26.0, 48.0, 12.0), 0.0)
	for k in 2:
		_tower(root, Vector3((k * 2 - 1) * 15.0, 0, half + 3.0), 6.5, 54.0, 14.0)
	# The keep: a great block with its own turrets, and a tall spire tower
	_box(root, Vector3(0, 44.0, -6.0), Vector3(44.0, 88.0, 38.0), 0.0)
	for k in 4:
		var p := Vector3((1 if k % 2 else -1) * 22.0, 0, -6.0 + (1 if k / 2 else -1) * 19.0)
		_tower(root, p, 5.0, 104.0, 16.0)
	_tower(root, Vector3(8.0, 0, -10.0), 8.0, 138.0, 34.0)
	# Banners on the spires
	for p in [Vector3(8.0, 172.0, -10.0), Vector3(-22.0, 120.0, -25.0), Vector3(22.0, 120.0, 13.0)]:
		_box(root, p + Vector3(0, 5.0, 0), Vector3(0.8, 10.0, 0.8), 0.0)
		_box(root, p + Vector3(3.5, 8.0, 0), Vector3(7.0, 4.0, 0.4), 0.0)
	# Windows: a few lit (night) or dark slits up the keep and towers
	for k in 26:
		var p := Vector3(rng.randf_range(-18.0, 18.0), rng.randf_range(30.0, 80.0), 13.2)
		var win := _box(root, p, Vector3(2.0, 4.0, 0.6), 0.0)
		win.material_override = _windows
	for k in 10:
		var a := rng.randf() * TAU
		var p := Vector3(8.0 + cos(a) * 8.2, rng.randf_range(60.0, 125.0), -10.0 + sin(a) * 8.2)
		var win := _box(root, p, Vector3(1.6, 3.4, 1.6), 0.0)
		win.material_override = _windows


func _box(parent: Node3D, at: Vector3, size: Vector3, yaw: float) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = _mat
	mi.position = at
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _tower(parent: Node3D, at: Vector3, r: float, h: float, roof: float) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r * 1.06
	cyl.height = h
	cyl.radial_segments = 14
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = _mat
	mi.position = at + Vector3(0, h * 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = r * 1.3
	cone.height = roof
	cone.radial_segments = 14
	var ci := MeshInstance3D.new()
	ci.mesh = cone
	ci.material_override = _mat
	ci.position = at + Vector3(0, h + roof * 0.5, 0)
	ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ci)


func _process(_dt: float) -> void:
	# Keep its distance, like the sky: always DISTANCE away in its direction, facing you
	var cam := get_viewport().get_camera_3d()
	var from := cam.global_position if cam != null else Vector3.ZERO
	var dir := Vector3(cos(bearing), 0.0, sin(bearing))
	global_position = Vector3(from.x, -14.0, from.z) + dir * DISTANCE
	rotation.y = atan2(-dir.x, -dir.z)   # the gatehouse faces the arena
