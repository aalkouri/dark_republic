class_name KeyManager
extends Node3D
## Chest keys: Bronze, Silver and Gold. Elites sometimes drop one when they die (bronze
## usually, silver sometimes, gold rarely); keys spin on the ground until picked up (pulled in
## by the pickup range like potions) and open a chest of the same tier. Keys only last the run.

signal collected(tier: int)

const DROP_CHANCE := 0.12            # per elite killed
const DROP_WEIGHTS := [65.0, 27.0, 8.0]   # bronze, silver, gold
const NAMES := ["Bronze Key", "Silver Key", "Gold Key"]
const PICKUP_DIST := 1.2
const SPIN_SPEED := 1.6

var player: Player
var rng: RandomNumberGenerator
var keys := PackedInt32Array([0, 0, 0])   # held, per tier
var _drops: Array = []                     # {node, spinner, tier, age, pulled}
var _mats: Array = []


func setup(p_player: Player, p_rng: RandomNumberGenerator) -> void:
	player = p_player
	rng = p_rng


func _ready() -> void:
	for t in 3:
		var m := PowerupManager._glow(Chest.TIER_COLORS[t], 0.9)
		m.metallic = 0.9
		m.roughness = 0.25
		_mats.append(m)


func roll_tier() -> int:
	var total := 0.0
	for w in DROP_WEIGHTS:
		total += w
	var r := rng.randf() * total
	for t in DROP_WEIGHTS.size():
		r -= DROP_WEIGHTS[t]
		if r <= 0.0:
			return t
	return 0


## An elite died at `at`: maybe drop a key. Returns true if one dropped.
func on_elite_killed(at: Vector3) -> bool:
	if rng.randf() >= DROP_CHANCE:
		return false
	drop(at)
	return true


func has_key(tier: int) -> bool:
	return keys[tier] > 0


func use_key(tier: int) -> bool:
	if keys[tier] <= 0:
		return false
	keys[tier] -= 1
	return true


func drop(at: Vector3, tier := -1) -> void:
	if tier < 0:
		tier = roll_tier()
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	root.global_position = Vector3(at.x, SwampWater.height_at(at.x, at.z), at.z)
	var spinner := Node3D.new()
	spinner.position.y = 0.6
	spinner.rotation.y = rng.randf() * TAU
	root.add_child(spinner)
	build_key(spinner, _mats[tier])
	var light := OmniLight3D.new()
	light.light_color = Chest.TIER_COLORS[tier]
	light.light_energy = 1.3
	light.omni_range = 3.0
	light.position.y = 0.7
	root.add_child(light)
	var ring := GroundDisc.create(0.6, Color(Chest.TIER_COLORS[tier], 0.4), true)
	ring.set_lift(0.04)
	root.add_child(ring)
	_drops.append({"node": root, "spinner": spinner, "tier": tier, "age": 0.0, "pulled": false})


## A chunky old-fashioned key (ring bow, shaft, two teeth), standing up, ~0.7 m tall.
static func build_key(parent: Node3D, mat: Material) -> void:
	var bow := TorusMesh.new()
	bow.inner_radius = 0.1
	bow.outer_radius = 0.17
	bow.rings = 16
	bow.ring_segments = 8
	bow.material = mat
	var bmi := MeshInstance3D.new()
	bmi.mesh = bow
	bmi.rotation.x = PI * 0.5
	bmi.position.y = 0.22
	parent.add_child(bmi)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.035
	shaft.bottom_radius = 0.035
	shaft.height = 0.42
	shaft.radial_segments = 8
	shaft.material = mat
	var smi := MeshInstance3D.new()
	smi.mesh = shaft
	smi.position.y = -0.14
	parent.add_child(smi)
	for k in 2:
		var tooth := BoxMesh.new()
		tooth.size = Vector3(0.1, 0.05, 0.04)
		tooth.material = mat
		var tmi := MeshInstance3D.new()
		tmi.mesh = tooth
		tmi.position = Vector3(0.06, -0.3 + k * 0.08, 0)
		parent.add_child(tmi)


func tick(dt: float, pickup_range: float) -> void:
	var target := player.global_position + Vector3(0, 0.6, 0)
	for k in range(_drops.size() - 1, -1, -1):
		var d: Dictionary = _drops[k]
		var root: Node3D = d["node"]
		var spinner: Node3D = d["spinner"]
		d["age"] += dt
		var age: float = d["age"]
		spinner.position.y = 0.6 + 0.1 * sin(age * 2.4)
		spinner.rotation.y += SPIN_SPEED * dt
		var to := target - (root.global_position + Vector3(0, 0.6, 0))
		var dist := to.length()
		if dist < pickup_range:
			d["pulled"] = true
		if d["pulled"]:
			root.global_position += to.normalized() * minf(dist, (10.0 + age) * dt * 2.0)
		if dist < PICKUP_DIST:
			keys[d["tier"]] += 1
			collected.emit(d["tier"])
			root.queue_free()
			_drops.remove_at(k)


func count() -> int:
	return _drops.size()
