class_name Fireflies
extends Node3D
## Magical Forest fireflies: soft glowing motes drifting and blinking in a box that follows the
## camera, so there are always some around you without filling the whole 440 m arena.

const EXTENT := Vector3(28.0, 3.5, 28.0)

var _p: CPUParticles3D


func _ready() -> void:
	_p = CPUParticles3D.new()
	_p.amount = 260
	_p.lifetime = 6.0
	_p.preprocess = 6.0
	_p.local_coords = false
	_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_p.emission_box_extents = EXTENT
	_p.direction = Vector3.UP
	_p.spread = 180.0
	_p.initial_velocity_min = 0.1
	_p.initial_velocity_max = 0.5
	_p.gravity = Vector3.ZERO
	var curve := Curve.new()   # fade in, blink, fade out
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(0.4, 0.3))
	curve.add_point(Vector2(0.6, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.7, 1.0, 0.45))
	grad.set_color(1, Color(0.35, 0.95, 1.0))
	_p.color_initial_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_fog = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Abilities._soft_dot()
	quad.material = m
	_p.mesh = quad
	add_child(_p)


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		var c := cam.global_position
		_p.global_position = Vector3(c.x, c.y - 1.0, c.z)
