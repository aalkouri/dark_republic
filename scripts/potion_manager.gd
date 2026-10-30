class_name PotionManager
extends Node3D
## Potions dropped by epic enemies: each one killed has a DROP_CHANCE of dropping a potion, and
## never while MAX_ON_MAP are already lying around (spawns climb to ~50 goblins a second, so
## without this the ground fills with them). Which potion:
##   30% purple  -> every ability's cooldown is reduced by 30% of its full duration
##   50% red     -> heal 10% of max HP
##   20% blue    -> shield worth 10% of max HP (absorbs damage first, stacks)
## Potions bob and spin, are pulled in by the player's pickup range, and expire after a while.

signal collected(kind: int)
signal healed(amount: float)                    # HP actually restored
signal cooldowns_cut(amounts: PackedFloat32Array)  # seconds removed per ability

enum { PURPLE, RED, BLUE }

const DROP_WEIGHTS := [30.0, 50.0, 20.0]   # purple, red, blue
const COLORS := [Color(0.72, 0.25, 1.0), Color(1.0, 0.15, 0.15), Color(0.2, 0.55, 1.0)]
const NAMES := ["Purple Potion: cooldowns -30%", "Red Potion: +10% health", "Blue Potion: +10% shield"]
const COOLDOWN_CUT := 0.30
const HEAL_FRAC := 0.10
const SHIELD_FRAC := 0.10
const DROP_CHANCE := 0.15
const MAX_ON_MAP := 3
const LIFETIME := 45.0
const BLINK_WINDOW := 5.0      # start blinking this many seconds before disappearing
const BLINK_PERIOD := 0.3      # one blink every 0.3 s
const BLINK_ON := 0.6          # visible for 60% of each blink period
const SPIN_SPEED := 0.9        # rad/s - a slow turn
const LEAN := deg_to_rad(22.0) # tilt so the spin is easy to see
const PICKUP_DIST := 1.2

var player: Player
var abilities: Abilities
var rng: RandomNumberGenerator
var _potions: Array = []   # {node, kind, age, pulled}
var _meshes: Array = []    # per kind: [glass Mesh, liquid Mesh]


func setup(p_player: Player, p_abilities: Abilities, p_rng: RandomNumberGenerator) -> void:
	player = p_player
	abilities = p_abilities
	rng = p_rng


func _ready() -> void:
	for kind in 3:
		var c: Color = COLORS[kind]
		var liquid := StandardMaterial3D.new()
		liquid.albedo_color = c
		liquid.emission_enabled = true
		liquid.emission = c
		liquid.emission_energy_multiplier = 1.6
		var body := SphereMesh.new()
		body.radius = 0.26
		body.height = 0.5
		body.radial_segments = 14
		body.rings = 7
		body.material = liquid
		_meshes.append(body)


func roll_kind() -> int:
	var total := 0.0
	for w in DROP_WEIGHTS:
		total += w
	var r := rng.randf() * total
	for k in DROP_WEIGHTS.size():
		r -= DROP_WEIGHTS[k]
		if r <= 0.0:
			return k
	return RED


## An epic died at `at`: maybe drop a potion there. Returns true if one dropped.
func on_elite_killed(at: Vector3) -> bool:
	if _potions.size() >= MAX_ON_MAP or rng.randf() >= DROP_CHANCE:
		return false
	drop(at)
	return true


func drop(at: Vector3, kind := -1) -> void:
	if kind < 0:
		kind = roll_kind()
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	root.global_position = Vector3(at.x, SwampWater.height_at(at.x, at.z), at.z)

	# spinner (turns around vertical, bobs) -> tilt (leans the bottle) -> bottle mesh
	var spinner := Node3D.new()
	spinner.position.y = 0.55
	spinner.rotation.y = rng.randf() * TAU
	root.add_child(spinner)
	var tilt := Node3D.new()
	tilt.rotation.z = LEAN
	spinner.add_child(tilt)
	var bottle := MeshInstance3D.new()
	bottle.mesh = _meshes[kind]
	tilt.add_child(bottle)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.9, 0.95, 1.0, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var neck := CylinderMesh.new()
	neck.top_radius = 0.08
	neck.bottom_radius = 0.1
	neck.height = 0.2
	neck.material = glass
	var neck_mi := MeshInstance3D.new()
	neck_mi.mesh = neck
	neck_mi.position.y = 0.3
	bottle.add_child(neck_mi)
	var cork := CylinderMesh.new()
	cork.top_radius = 0.085
	cork.bottom_radius = 0.075
	cork.height = 0.09
	var cork_mat := StandardMaterial3D.new()
	cork_mat.albedo_color = Color(0.55, 0.38, 0.22)
	cork.material = cork_mat
	var cork_mi := MeshInstance3D.new()
	cork_mi.mesh = cork
	cork_mi.position.y = 0.44
	bottle.add_child(cork_mi)

	var light := OmniLight3D.new()
	light.light_color = COLORS[kind]
	light.light_energy = 1.2
	light.omni_range = 3.0
	light.position.y = 0.6
	root.add_child(light)

	# Ground glow so potions are easy to spot in a crowd
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.02
	disc.radial_segments = 24
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(COLORS[kind], 0.35)
	disc.material = dm
	ring.mesh = disc
	ring.position.y = 0.04
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)

	_potions.append({"node": root, "bottle": spinner, "kind": kind, "age": 0.0, "pulled": false})


func tick(dt: float, pickup_range: float) -> void:
	var target := player.global_position + Vector3(0, 0.6, 0)
	for k in range(_potions.size() - 1, -1, -1):
		var p: Dictionary = _potions[k]
		var root: Node3D = p["node"]
		var bottle: Node3D = p["bottle"]
		p["age"] += dt
		var age: float = p["age"]
		bottle.position.y = 0.55 + 0.12 * sin(age * 2.2)
		bottle.rotation.y += SPIN_SPEED * dt
		var to := target - (root.global_position + Vector3(0, 0.6, 0))
		var d := to.length()
		if d < pickup_range:
			p["pulled"] = true
		if p["pulled"]:
			root.global_position += to.normalized() * minf(d, (10.0 + age) * dt * 2.0)
		if d < PICKUP_DIST:
			_apply(p["kind"])
			root.queue_free()
			_potions.remove_at(k)
			continue
		if age > LIFETIME:
			root.queue_free()
			_potions.remove_at(k)
		else:
			root.visible = is_visible_at(age)


## Blink in the last BLINK_WINDOW seconds: on for 60% of every BLINK_PERIOD.
static func is_visible_at(age: float) -> bool:
	if age < LIFETIME - BLINK_WINDOW:
		return true
	return fmod(age - (LIFETIME - BLINK_WINDOW), BLINK_PERIOD) < BLINK_PERIOD * BLINK_ON


func _apply(kind: int) -> void:
	match kind:
		PURPLE:
			var cut := PackedFloat32Array()
			for i in abilities.cooldown.size():
				var full: float = abilities.defs()[i]["cooldown"]
				var before := abilities.cooldown[i]
				abilities.cooldown[i] = maxf(0.0, before - full * COOLDOWN_CUT)
				cut.append(before - abilities.cooldown[i])
			cooldowns_cut.emit(cut)
		RED:
			var before := player.hp
			player.heal(player.max_hp * HEAL_FRAC)
			healed.emit(player.hp - before)
		BLUE:
			player.add_shield(player.max_hp * SHIELD_FRAC)
	collected.emit(kind)


func count() -> int:
	return _potions.size()
