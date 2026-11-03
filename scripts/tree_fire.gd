class_name TreeFire
extends Node3D
## A burning tree. Ignite a burnable prop (trees and fallen trees, in GROUP) and it burns for
## BURN_TIME seconds (then it drops loot: Events.prop_burnt -> ItemDrops): flames over its whole shape, ember glow, flickering light, while the wood
## and foliage char patchily to black. When the fire dies the blackened tree crumbles into the
## ground (COLLAPSE seconds) and is gone, leaving the ground clean (it used to leave a glowing
## sizzles for the rest of the match. Nothing burns twice.

const GROUP := "burnable"
const BURN_TIME := 3.0        # was 15 s: a quick, fierce blaze, then the tree drops its loot
const RAMP_UP := 0.35         # flames grow
const DIE_DOWN := 0.8         # flames shrink at the end
const COLLAPSE := 1.4         # the charred remains crumble to dust (then its item is left there)

var _mat: ShaderMaterial
var _flames: CPUParticles3D
var _light: OmniLight3D
var _t := 0.0
var _aabb: AABB


## Set a burnable prop on fire. Returns false if it's already burning or burnt.
static func ignite(body: Node3D) -> bool:
	if body.has_meta("burn_state"):
		return false
	var fire := TreeFire.new()
	fire.process_mode = Node.PROCESS_MODE_PAUSABLE
	body.add_child(fire)
	body.set_meta("burn_state", "burning")
	return true


static func state_of(body: Node3D) -> String:
	return body.get_meta("burn_state", "")


func _ready() -> void:
	var mi: MeshInstance3D = get_parent().get_meta("mesh_instance")
	_mat = (MeshBuilder.prop_material().duplicate() as ShaderMaterial)
	mi.material_override = _mat
	var aabb := mi.mesh.get_aabb()
	_aabb = aabb

	_flames = Abilities._flame_particles(1.3, 0.9, 120)
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_flames.emission_box_extents = aabb.size * Vector3(0.42, 0.42, 0.42)
	_flames.position = aabb.get_center()
	_flames.initial_velocity_min = 1.0
	_flames.initial_velocity_max = 3.0
	add_child(_flames)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.45, 0.1)
	_light.omni_range = maxf(aabb.size.length() * 0.9, 8.0)
	_light.position = aabb.get_center()
	add_child(_light)


func _process(dt: float) -> void:
	_t += dt
	var intensity := clampf(_t / RAMP_UP, 0.0, 1.0) * clampf((BURN_TIME - _t) / DIE_DOWN, 0.0, 1.0)
	_mat.set_shader_parameter("char_amount", clampf(_t / BURN_TIME, 0.0, 1.0))
	_mat.set_shader_parameter("burning", intensity)
	_light.light_energy = intensity * (2.4 + 0.9 * sin(_t * 19.0) * sin(_t * 7.0))
	_flames.emitting = intensity > 0.05
	_flames.scale_amount_max = 1.3 * maxf(intensity, 0.2)
	if _t >= BURN_TIME and get_parent().get_meta("burn_state", "") == "burning":
		_mat.set_shader_parameter("char_amount", 1.0)
		_mat.set_shader_parameter("burning", 0.0)
		_burnt_out()


## The fire's out: the black remains crumble to dust, the prop goes (collision and all), and
## its item is left where it stood.
func _burnt_out() -> void:
	var body := get_parent() as Node3D
	body.set_meta("burn_state", "charred")
	body.remove_from_group(GROUP)
	var at := body.global_transform * Vector3(_aabb.get_center().x, 0.0, _aabb.get_center().z)
	at.y = SwampWater.height_at(at.x, at.z)
	for c in body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
	# The charred tree crumbles to dust: a cloud of ash and cinders pours off it as it sinks in on
	# itself, then (no scorch mark: the ground is left clean) the item it hid is left in the ash
	var sc := body.global_basis.get_scale()
	var dust := CPUParticles3D.new()
	dust.top_level = true
	dust.amount = 110
	dust.lifetime = 1.6
	dust.one_shot = true
	dust.explosiveness = 0.15
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = _aabb.size * sc * 0.45
	dust.direction = Vector3(0, -1, 0)
	dust.spread = 70.0
	dust.initial_velocity_min = 0.3
	dust.initial_velocity_max = 1.4
	dust.gravity = Vector3(0, -3.5, 0)
	dust.damping_min = 0.5
	dust.damping_max = 1.5
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.45, 0.1, 0.9))   # a last few cinders...
	ramp.add_point(0.15, Color(0.3, 0.28, 0.26, 0.85))   # ...then grey-black ash
	ramp.set_color(1, Color(0.18, 0.17, 0.16, 0.0))
	dust.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	q.material = dm
	dust.mesh = q
	body.get_parent().add_child(dust)
	dust.global_position = body.global_transform * _aabb.get_center()
	dust.emitting = true
	dust.get_tree().create_timer(COLLAPSE + 2.0, false).timeout.connect(dust.queue_free)
	var tw := body.create_tween()
	var s0 := body.scale
	tw.tween_property(body, "scale", Vector3(s0.x * 0.85, s0.y * 0.02, s0.z * 0.85), COLLAPSE).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): Events.prop_burnt.emit(at))   # the item it hid, left in the ash where it stood
	tw.tween_callback(body.queue_free)
