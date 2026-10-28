class_name ShrineManager
extends Node3D
## Places 1-8 shrines on open ground each run (clear of pools, trees, logs, ruins and the
## spawn), ticks them, and spawns their chest when one is completed.

signal shrine_completed(shrine: Shrine, chest: Chest)

const MIN_SHRINES := 4
const MAX_SHRINES := 14   # the map is 440 m across
const PATTERNS := 2          # CHAINS, NOVA

var player: Player
var water: SwampWater
var rng: RandomNumberGenerator
var shrines: Array[Shrine] = []
var active: Shrine = null    # the shrine whose zone the player is in


func setup(p_player: Player, p_water: SwampWater, p_rng: RandomNumberGenerator) -> void:
	player = p_player
	water = p_water
	rng = p_rng


func spawn_all(half: float) -> void:
	var n := rng.randi_range(MIN_SHRINES, MAX_SHRINES)
	for k in n:
		var at := _free_spot(half)
		if at == Vector3.INF:
			break
		var s := Shrine.new()
		s.setup(rng.randi() % PATTERNS, rng.randi_range(1, 3))
		s.position = at
		s.process_mode = Node.PROCESS_MODE_INHERIT
		add_child(s)
		s.completed.connect(_on_completed)
		shrines.append(s)


func _free_spot(half: float) -> Vector3:
	# The world reserved level pads for shrines; use those first
	if water != null and not water.shrine_sites.is_empty():
		for site in water.shrine_sites:
			var taken := false
			for s in shrines:
				if Vector2(s.position.x - site.x, s.position.z - site.z).length() < 1.0:
					taken = true
					break
			if not taken:
				return site
		return Vector3.INF
	var need := Shrine.ZONE_RADIUS + 1.5
	for attempt in 400:
		var p := Vector3(rng.randf_range(-half + 12.0, half - 12.0), 0.0, rng.randf_range(-half + 12.0, half - 12.0))
		if p.length() < 22.0:
			continue
		if water != null and water.near_pool(p.x, p.z, need):
			continue
		var ok := true
		for s in shrines:
			if p.distance_to(s.position) < 30.0:
				ok = false
				break
		if ok:
			for b in get_tree().get_nodes_in_group(TreeFire.GROUP) + get_tree().get_nodes_in_group("obstacle"):
				var nb := b as Node3D
				var reach := float(nb.get_meta("reach", 2.0))
				if Vector2(nb.global_position.x - p.x, nb.global_position.z - p.z).length() < need + reach:
					ok = false
					break
		if ok:
			p.y = SwampWater.height_at(p.x, p.z)
			return p
	return Vector3.INF


func tick(dt: float) -> void:
	active = null
	for s in shrines:
		if s.tick(dt, player):
			active = s


func _on_completed(s: Shrine) -> void:
	var chest := Chest.new()
	chest.tier = s.difficulty - 1
	add_child(chest)
	var to_player := player.global_position - s.position
	to_player.y = 0.0
	var dir := to_player.normalized() if to_player.length() > 0.1 else Vector3.FORWARD
	chest.position = s.position + dir * 1.8
	chest.look_at(chest.position - dir, Vector3.UP)   # lock faces the player
	shrine_completed.emit(s, chest)
