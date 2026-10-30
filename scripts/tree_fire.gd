class_name TreeFire
extends Node3D
## A burning tree. Ignite a burnable prop (trees and fallen trees, in GROUP) and it burns for
## BURN_TIME seconds: flames over its whole shape, ember glow, flickering light, while the wood
## and foliage char patchily to black. When the fire dies the blackened tree crumbles into the
## ground (COLLAPSE seconds) and is gone, leaving a ScorchMark: a charred patch that smokes and
## sizzles for the rest of the match. Nothing burns twice.

const GROUP := "burnable"
const BURN_TIME := 15.0
const RAMP_UP := 1.5          # flames grow
const DIE_DOWN := 3.0         # flames shrink at the end
const COLLAPSE := 1.6         # the charred remains sink and crumble away

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


## The fire's out: leave the scorch mark, crumble the black remains away, then remove the prop
## (collision and all).
func _burnt_out() -> void:
	var body := get_parent() as Node3D
	body.set_meta("burn_state", "charred")
	body.remove_from_group(GROUP)
	var foot := Vector2(_aabb.size.x, _aabb.size.z) * Vector2(body.global_basis.get_scale().x, body.global_basis.get_scale().z)
	var r := clampf(maxf(foot.x, foot.y) * 0.32, 1.6, 4.5)
	var at := body.global_transform * Vector3(_aabb.get_center().x, 0.0, _aabb.get_center().z)
	at.y = SwampWater.height_at(at.x, at.z)
	ScorchMark.spawn(body.get_parent(), at, r)
	for c in body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
	var ash := Abilities._flame_particles(1.0, 1.2, 50)   # a last puff of ash and sparks
	var grad := Gradient.new()
	grad.set_color(0, Color(0.35, 0.33, 0.3, 0.8))
	grad.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	grad.add_point(0.1, Color(1.0, 0.45, 0.1, 0.9))
	ash.color_ramp = grad
	ash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ash.emission_box_extents = _aabb.size * 0.4
	ash.position = _aabb.get_center()
	ash.one_shot = true
	ash.explosiveness = 0.6
	add_child(ash)
	ash.emitting = true
	var tw := body.create_tween()
	var s0 := body.scale
	tw.tween_property(body, "scale", Vector3(s0.x * 1.05, s0.y * 0.02, s0.z * 1.05), COLLAPSE).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(body.queue_free)
