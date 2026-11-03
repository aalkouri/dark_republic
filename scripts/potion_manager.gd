class_name PotionManager
extends Node3D
## Potions dropped by epic enemies: each one killed has a DROP_CHANCE of dropping a potion. They
## stay where they fell until picked up (no despawning, no limit on how many). Which potion:
##   20% yellow  (Liquid Soul-Amber)      -> 5x damage for 10 s (the 5x Damage power-up's effect)
##   55% red     (Vampiric Dew)           -> heal 10% of max HP
##   25% blue    (Bioluminescent Nectar)  -> shield worth 10% of max HP (absorbs damage first, stacks)
## The bottles are PotionModel (built from primitives).
## Potions bob and spin, are pulled in by the player's pickup range, and expire after a while.

signal collected(kind: int)
signal healed(amount: float)                    # HP actually restored

enum { YELLOW, RED, BLUE }

const DROP_WEIGHTS := [20.0, 55.0, 25.0]   # yellow, red, blue
const COLORS := [Color(1.0, 0.68, 0.12), Color(1.0, 0.1, 0.12), Color(0.2, 0.8, 1.0)]
const NAMES := ["Yellow Potion: 5x damage", "Red Potion: +10% health", "Blue Potion: +10% shield"]
const HEAL_FRAC := 0.10
const SHIELD_FRAC := 0.10
const DROP_CHANCE := 0.15
const SPIN_SPEED := 0.9        # rad/s - a slow turn
const LEAN := deg_to_rad(22.0) # tilt so the spin is easy to see
const PICKUP_DIST := 1.2

var player: Player
var abilities: Abilities
var powerups: PowerupManager   # the yellow potion borrows the 5x Damage power-up's effect
var rng: RandomNumberGenerator
var _potions: Array = []   # {node, kind, age, pulled}


func setup(p_player: Player, p_abilities: Abilities, p_rng: RandomNumberGenerator) -> void:
	player = p_player
	abilities = p_abilities
	rng = p_rng


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
	if rng.randf() >= DROP_CHANCE:
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
	spinner.position.y = 0.65
	spinner.rotation.y = rng.randf() * TAU
	root.add_child(spinner)
	var tilt := Node3D.new()
	tilt.rotation.z = LEAN
	spinner.add_child(tilt)
	tilt.add_child(PotionModel.build(kind))

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
		bottle.position.y = 0.65 + 0.12 * sin(age * 2.2)
		bottle.rotation.y += SPIN_SPEED * dt
		var to := target - (root.global_position + Vector3(0, 0.6, 0))
		var d := to.length()
		if d < pickup_range:
			p["pulled"] = true
		if p["pulled"]:
			root.global_position += to.normalized() * minf(d, (10.0 + age) * dt * 2.0)
		if d < PICKUP_DIST:
			_drink_sfx()
			_apply(p["kind"])
			root.queue_free()
			_potions.remove_at(k)
			continue


var _drink: AudioStreamPlayer

## The potion pickup sound (the same for all three potions).
func _drink_sfx() -> void:
	if _drink == null:
		_drink = AudioStreamPlayer.new()
		_drink.bus = Settings.SFX_BUS
		_drink.max_polyphony = 3
		if ResourceLoader.exists("res://audio/ui/potion.mp3"):
			_drink.stream = load("res://audio/ui/potion.mp3")
		add_child(_drink)
	if _drink.stream:
		_drink.play()


func _apply(kind: int) -> void:
	match kind:
		YELLOW:
			if powerups != null:
				powerups.activate(PowerupManager.DAMAGE)
		RED:
			var before := player.hp
			player.heal(player.max_hp * HEAL_FRAC)
			healed.emit(player.hp - before)
		BLUE:
			player.add_shield(player.max_hp * SHIELD_FRAC)
	collected.emit(kind)


func count() -> int:
	return _potions.size()
