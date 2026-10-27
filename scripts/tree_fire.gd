class_name TreeFire
extends Node3D
## A burning tree. Ignite a burnable prop (trees and fallen trees, in GROUP) and it burns for
## BURN_TIME seconds: flames over its whole shape, ember glow, flickering light, while the wood
## and foliage char patchily to black. When the fire dies the tree stays charred, and a charred
## tree can't catch fire again.

const GROUP := "burnable"
const BURN_TIME := 15.0
const RAMP_UP := 1.5          # flames grow
const DIE_DOWN := 3.0         # flames shrink at the end

var _mat: ShaderMaterial
var _flames: CPUParticles3D
var _light: OmniLight3D
var _t := 0.0


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
	if _t >= BURN_TIME:
		_mat.set_shader_parameter("char_amount", 1.0)
		_mat.set_shader_parameter("burning", 0.0)
		get_parent().set_meta("burn_state", "charred")
		queue_free()
