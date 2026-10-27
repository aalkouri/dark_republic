class_name WorldBuilder
extends RefCounted
## Builds the arena procedurally from a seed: lighting, ground, platforms, ramps, walls.

const GROUND_SHADER := """
shader_type spatial;
uniform vec3 col_a : source_color = vec3(0.30, 0.42, 0.26);
uniform vec3 col_b : source_color = vec3(0.26, 0.37, 0.23);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 c = floor(wpos.xz / 4.0);
	float k = mod(c.x + c.y, 2.0);
	ALBEDO = mix(col_a, col_b, k);
	ROUGHNESS = 0.95;
}
"""

const PALETTE := [
	Color(0.85, 0.78, 0.62), Color(0.62, 0.72, 0.85), Color(0.86, 0.62, 0.55),
	Color(0.66, 0.82, 0.62), Color(0.78, 0.66, 0.86), Color(0.9, 0.84, 0.5),
]


static func build(parent: Node3D, rng: RandomNumberGenerator, half: float) -> void:
	_environment(parent)
	_ground(parent, half)
	_walls(parent, half)

	# Platforms (avoid the spawn area)
	for i in 45:
		var p := _random_point(rng, half - 8.0, 12.0)
		var size := Vector3(rng.randf_range(3.0, 9.0), rng.randf_range(1.0, 4.5), rng.randf_range(3.0, 9.0))
		_box(parent, Vector3(p.x, size.y * 0.5, p.z), size, Vector3(0, rng.randf() * TAU, 0), PALETTE[rng.randi() % PALETTE.size()])

	# Ramps: great for slide-boosting and launching
	for i in 18:
		var p := _random_point(rng, half - 10.0, 14.0)
		var tilt := deg_to_rad(rng.randf_range(12.0, 22.0))
		var length := rng.randf_range(8.0, 14.0)
		var size := Vector3(rng.randf_range(4.0, 7.0), 0.6, length)
		var y := sin(tilt) * length * 0.5 - 0.3 * cos(tilt)
		_box(parent, Vector3(p.x, y, p.z), size, Vector3(tilt, rng.randf() * TAU, 0), Color(0.75, 0.75, 0.78))

	# A few tall pillars as landmarks
	for i in 6:
		var p := _random_point(rng, half - 15.0, 25.0)
		var h := rng.randf_range(10.0, 18.0)
		_box(parent, Vector3(p.x, h * 0.5, p.z), Vector3(3, h, 3), Vector3.ZERO, Color(0.5, 0.45, 0.55))


static func _random_point(rng: RandomNumberGenerator, extent: float, keep_out: float) -> Vector3:
	while true:
		var p := Vector3(rng.randf_range(-extent, extent), 0.0, rng.randf_range(-extent, extent))
		if p.length() > keep_out:
			return p
	return Vector3.ZERO


static func _environment(parent: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.5, 0.85)
	sky_mat.sky_horizon_color = Color(0.78, 0.84, 0.92)
	sky_mat.ground_horizon_color = Color(0.78, 0.84, 0.92)
	sky_mat.ground_bottom_color = Color(0.3, 0.35, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.82, 0.9)
	env.fog_density = 0.006
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	parent.add_child(sun)


static func _ground(parent: Node3D, half: float) -> void:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(half * 2.0 + 20.0, 1.0, half * 2.0 + 20.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = -0.5
	body.add_child(col)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(half * 2.0 + 20.0, half * 2.0 + 20.0)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	sm.shader = sh
	mesh.material = sm
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	parent.add_child(body)


static func _walls(parent: Node3D, half: float) -> void:
	var c := Color(0.4, 0.38, 0.45)
	var h := 6.0
	var t := 2.0
	var l := half * 2.0 + t * 2.0
	_box(parent, Vector3(0, h * 0.5, -half - t * 0.5), Vector3(l, h, t), Vector3.ZERO, c)
	_box(parent, Vector3(0, h * 0.5, half + t * 0.5), Vector3(l, h, t), Vector3.ZERO, c)
	_box(parent, Vector3(-half - t * 0.5, h * 0.5, 0), Vector3(t, h, l), Vector3.ZERO, c)
	_box(parent, Vector3(half + t * 0.5, h * 0.5, 0), Vector3(t, h, l), Vector3.ZERO, c)


static func _box(parent: Node3D, at: Vector3, size: Vector3, rot: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	body.position = at
	body.rotation = rot
	parent.add_child(body)
