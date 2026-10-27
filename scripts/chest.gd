class_name Chest
extends Node3D
## Reward chest (placeholder): Bronze, Silver or Gold. Spawned by completed shrines.
## Opening and rewards are not implemented yet - see `open()`.

signal opened(chest: Chest)

const TIER_NAMES := ["Bronze", "Silver", "Gold"]
const TIER_COLORS := [Color(0.8, 0.48, 0.22), Color(0.82, 0.86, 0.95), Color(1.0, 0.8, 0.18)]

var tier := 0   # 0 bronze, 1 silver, 2 gold
var is_open := false
var _t := 0.0
var _lid: Node3D


func _ready() -> void:
	add_to_group("chests")
	var trim: Color = TIER_COLORS[tier]
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.33, 0.2, 0.11)
	wood.roughness = 0.85
	var metal := PowerupManager._glow(trim, 0.6)
	metal.metallic = 0.8
	metal.roughness = 0.35
	_box(self, Vector3(1.0, 0.55, 0.65), Vector3(0, 0.3, 0), wood)
	for x in [-0.42, 0.0, 0.42]:
		_box(self, Vector3(0.08, 0.57, 0.67), Vector3(x, 0.3, 0), metal)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.58, -0.33)   # hinge at the back
	add_child(_lid)
	var lid := CylinderMesh.new()
	lid.top_radius = 0.33
	lid.bottom_radius = 0.33
	lid.height = 1.0
	lid.radial_segments = 12
	lid.material = wood
	var lmi := MeshInstance3D.new()
	lmi.mesh = lid
	lmi.rotation.z = PI * 0.5
	lmi.scale = Vector3(1.0, 1.0, 0.6)
	lmi.position = Vector3(0, 0.0, 0.33)
	_lid.add_child(lmi)
	_box(_lid, Vector3(0.14, 0.2, 0.06), Vector3(0, 0.0, 0.66), metal)   # lock
	var light := OmniLight3D.new()
	light.light_color = trim
	light.light_energy = 1.5
	light.omni_range = 4.0
	light.position.y = 1.0
	add_child(light)
	var label := Label3D.new()
	label.text = "%s Chest" % TIER_NAMES[tier]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 10
	label.pixel_size = 0.008
	label.modulate = trim
	label.position.y = 1.5
	add_child(label)


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.position = at
	parent.add_child(mi)


func _process(dt: float) -> void:
	_t += dt
	if is_open:
		_lid.rotation.x = lerpf(_lid.rotation.x, -1.9, 1.0 - exp(-8.0 * dt))


## TODO: rewards. For now opening just swings the lid and emits `opened`.
func open() -> void:
	if is_open:
		return
	is_open = true
	opened.emit(self)
