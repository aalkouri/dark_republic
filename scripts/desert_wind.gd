class_name DesertWind
extends Node3D
## Blowing sand around the camera on the Desert (its Butterflies / Fireflies): a few hundred
## grains and pale wisps streaming low across the dunes on the prevailing wind, in a box that
## follows the camera. Much thicker while a sandstorm blows (the Pharaoh: storm = 0..1).

const EXTENT := 24.0
var storm := 0.0:
	set(v):
		storm = v
		if _storm:
			_storm.emitting = v > 0.05
			_storm_wisps.emitting = v > 0.05
var _grains: CPUParticles3D
var _wisps: CPUParticles3D
var _storm: CPUParticles3D
var _storm_wisps: CPUParticles3D


func _ready() -> void:
	name = "DesertWind"   # no-i18n
	var wind := Vector3(DesertBuilder.WIND.x, 0, DesertBuilder.WIND.y)
	_grains = _make(900, 0.05, Color(0.95, 0.82, 0.6, 0.7), wind * 9.0, 2.2)
	_wisps = _make(160, 1.4, Color(0.95, 0.85, 0.66, 0.12), wind * 6.0, 3.5)
	_storm = _make(2200, 0.07, Color(0.9, 0.72, 0.48, 0.85), wind * 16.0, 1.6)
	_storm_wisps = _make(420, 3.0, Color(0.88, 0.7, 0.48, 0.3), wind * 12.0, 2.2)
	for p in [_storm, _storm_wisps]:
		p.emission_box_extents = Vector3(EXTENT, 4.0, EXTENT)
	storm = 0.0


func _make(n: int, size: float, col: Color, vel: Vector3, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(EXTENT, 1.2, EXTENT)
	p.direction = vel.normalized()
	p.spread = 8.0
	p.initial_velocity_min = vel.length() * 0.7
	p.initial_velocity_max = vel.length() * 1.2
	p.gravity = Vector3(0, -0.3, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(size, size * 0.4)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Abilities._soft_dot()
	m.disable_receive_shadows = true
	q.material = m
	p.mesh = q
	p.color = col
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	add_child(p)
	return p


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	global_position = Vector3(c.x, SwampWater.height_at(c.x, c.z) + 0.8, c.z) - Vector3(DesertBuilder.WIND.x, 0, DesertBuilder.WIND.y) * EXTENT * 0.5
