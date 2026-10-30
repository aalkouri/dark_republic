class_name ChestManager
extends Node3D
## Places the run's chests (MIN_CHESTS..MAX_CHESTS of them, on the level pads the world
## reserved) - Bronze most often, Gold rarely - and watches for the player walking up to one.
## With a key of that tier, press Activate (E) to open it (`open_requested`, main runs the
## slot machine); without
## one, the chest says which key it needs.

signal open_requested(chest: Chest)

const MIN_CHESTS := 8
const MAX_CHESTS := 28
const SITE_RADIUS := 3.0              # level pad kept clear around each chest site
const TIER_WEIGHTS := [60.0, 30.0, 10.0]   # bronze, silver, gold
const OPEN_DIST := 2.6                # this close, press Activate (E) to open it
const HINT_DIST := 3.5

var player: Player
var water: SwampWater
var keys: KeyManager
var rng: RandomNumberGenerator
var chests: Array[Chest] = []
var opened_count := 0


func setup(p_player: Player, p_water: SwampWater, p_keys: KeyManager, p_rng: RandomNumberGenerator) -> void:
	player = p_player
	water = p_water
	keys = p_keys
	rng = p_rng


func roll_tier() -> int:
	var total := 0.0
	for w in TIER_WEIGHTS:
		total += w
	var r := rng.randf() * total
	for t in TIER_WEIGHTS.size():
		r -= TIER_WEIGHTS[t]
		if r <= 0.0:
			return t
	return 0


func spawn_all() -> void:
	var sites: Array[Vector3] = water.chest_sites.duplicate() if water != null else []
	# shuffle with the run's rng so the same seed gives the same chests
	for k in range(sites.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp := sites[k]
		sites[k] = sites[j]
		sites[j] = tmp
	var n := mini(rng.randi_range(MIN_CHESTS, MAX_CHESTS), sites.size())
	for k in n:
		place(sites[k], roll_tier())


func place(at: Vector3, tier: int) -> Chest:
	var c := Chest.new()
	c.tier = tier
	add_child(c)
	c.global_position = at
	c.rotation.y = rng.randf() * TAU
	chests.append(c)
	return c


func tick(_dt: float) -> void:
	var p := player.global_position
	for c in chests:
		if c.is_open:
			continue
		var d := Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length()
		if absf(c.global_position.y - p.y) > 3.0:
			d = INF
		var has := keys.has_key(c.tier)
		c.show_hint(d < HINT_DIST and not has)
		c.prompt.visible = d < OPEN_DIST and has
		if d < OPEN_DIST and has and player.activate_pressed():   # press Activate (E) to open
			keys.use_key(c.tier)
			c.open()
			opened_count += 1
			open_requested.emit(c)
			return   # one at a time


## Unopened chests, for the minimap / tests.
func closed_count() -> int:
	var n := 0
	for c in chests:
		if not c.is_open:
			n += 1
	return n
