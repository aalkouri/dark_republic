class_name BomberSkeletons
extends Node3D
## The Castle's bomber skeletons: in place of the goblin swarm rings on the other maps, the dead
## crawl up out of the floor all round you, each with a keg of black powder on its back, and
## shamble slowly at you.
##   - CONTACT: a bomber that reaches you blows up on the spot: CONTACT_DAMAGE (x the run's
##     enemy damage multiplier) to you, and it's gone (no XP, no barrel).
##   - KILLED: it drops its keg as it falls apart. The keg lies there with its fuse fizzing and a
##     red ring on the floor filling for FUSE seconds, then explodes: BARREL_DAMAGE to you if
##     you're inside the ring. Neither blast hurts other enemies.
## They are SKELETON rows in EnemyManager (bomber[i] = 1), drawn by SkeletonCrowd with the keg,
## that rise for RISE_TIME (sunk in the floor, harmless) before they run, at SPEED_MULT x.

const RISE_TIME := 1.3
const SPEED_MULT := 0.5        # a slow shamble (was a 1.9x sprint)
const HP_MULT := 0.3            # of a skeleton's health: they go down very fast (was 0.6)...
const CONTACT_DAMAGE := 40.0
const BARREL_DAMAGE := 32.0
const BLAST_RADIUS := 3.5
const FUSE := 1.6

var em: EnemyManager
var barrels: Array = []          # {node, ring, t, at}
var spawned := 0                 # counters for tests
var detonations := 0
var barrels_dropped := 0
var barrel_blasts := 0
var player_hits := 0
var _keg_mesh: Mesh
var _boom: Array[AudioStreamPlayer3D] = []
var _rise_sfx: AudioStreamPlayer3D


func _ready() -> void:
	for k in 3:
		_boom.append(_sfx("res://audio/castle/barrel_blast.wav", 26.0))
	_rise_sfx = _sfx("res://audio/castle/bomber_rise.wav", 10.0)


func _sfx(path: String, unit: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.bus = Settings.SFX_BUS
	a.unit_size = unit
	a.max_polyphony = 4
	if ResourceLoader.exists(path):
		a.stream = load(path)
	add_child(a)
	return a


## Raise a bomber at `p` (it crawls out of the floor first). Returns its row, or -1.
func spawn(p: Vector3, hp_mult: float, delay := 0.0) -> int:
	var i := em.spawn(EnemyManager.SKELETON, p, hp_mult * HP_MULT)
	if i < 0:
		return -1
	em.bomber[i] = 1
	em.rise_t[i] = RISE_TIME + delay
	em.throw_t[i] = 1e9
	spawned += 1
	var fx := _fx()
	if fx:   # dust and grit bursting up where it claws out
		fx.burst(em.pos[i] + Vector3(0, 0.2, 0), 0.9, Color(0.35, 0.3, 0.25), 0.4)
	if _rise_sfx and _rise_sfx.stream and spawned % 4 == 1:
		_rise_sfx.global_position = em.pos[i]
		_rise_sfx.play()
	return i


## A bomber touched the player: it blows up where it stands.
func detonate(i: int, player: Node3D, dmg_mult: float) -> void:
	if em.dead[i] or em.bomber[i] != 1:
		return
	em.bomber[i] = 2   # no barrel when it's removed
	var at := em.pos[i]
	detonations += 1
	_explode(at, player, CONTACT_DAMAGE * dmg_mult)
	em._kill(i)


## A killed bomber's keg: lies on the floor, fizzing, then goes off.
func drop_barrel(at: Vector3) -> void:
	barrels_dropped += 1
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _keg()
	node.add_child(mi)
	var spark := OmniLight3D.new()
	spark.light_color = Color(1.0, 0.6, 0.2)
	spark.light_energy = 1.2
	spark.omni_range = 2.5
	spark.position = Vector3(0.0, 0.25, 0.32)
	node.add_child(spark)
	add_child(node)
	node.global_position = at + Vector3(0, 0.16, 0)
	node.rotation = Vector3(PI * 0.5, randf() * TAU, 0)   # on its side
	var ring := GroundDisc.create(BLAST_RADIUS, Color(1.0, 0.25, 0.08, 0.5))
	ring.set_fill(0.0)
	ring.set_lift(0.03)
	add_child(ring)
	ring.global_position = Vector3(at.x, 0.0, at.z)
	barrels.append({"node": node, "ring": ring, "t": 0.0, "at": at, "spark": spark})


func _physics_process(dt: float) -> void:
	if barrels.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for k in range(barrels.size() - 1, -1, -1):
		var b: Dictionary = barrels[k]
		b["t"] += dt
		var t: float = b["t"]
		var ring: GroundDisc = b["ring"]
		ring.set_fill(clampf(t / FUSE, 0.0, 1.0))
		ring.alpha = 0.45 + 0.2 * sin(t * (12.0 + t * 20.0))
		(b["spark"] as OmniLight3D).light_energy = 0.8 + randf() * 1.2
		var node: Node3D = b["node"]
		node.position.x += sin(t * 70.0) * 0.004 * t   # rattles as the fuse burns down
		if t >= FUSE:
			barrel_blasts += 1
			var mult := 1.0
			var main := get_tree().current_scene
			if main != null and main.has_method("enemy_damage_mult"):
				mult = main.enemy_damage_mult()
			_explode(b["at"], player, BARREL_DAMAGE * mult)
			node.queue_free()
			ring.queue_free()
			barrels.remove_at(k)


## The blast: fire, smoke and a bang; hurts the player within BLAST_RADIUS, never the enemies.
func _explode(at: Vector3, player: Node3D, dmg: float) -> void:
	var fx := _fx()
	if fx:
		fx.burst(at + Vector3(0, 0.6, 0), BLAST_RADIUS, Color(1.0, 0.5, 0.12), 0.45)
	for a in _boom:
		if a.stream and not a.playing:
			a.global_position = at
			a.play()
			break
	if player != null and is_instance_valid(player):
		var pp := player.global_position
		var d := Vector2(pp.x - at.x, pp.z - at.z).length()
		if d <= BLAST_RADIUS and absf(pp.y - at.y) < 3.0:
			if player.has_method("hurt") and player.hurt(dmg, "Bomber Skeleton"):
				player_hits += 1
			if player.has_method("knockback"):
				var away := Vector3(pp.x - at.x, 0, pp.z - at.z)
				player.knockback(away.normalized() * 1.5 if away.length() > 0.01 else Vector3.ZERO)
		if player.has_method("add_shake"):
			player.add_shake(0.6 if d < 14.0 else 0.2)


func _fx() -> FxManager:
	for f in get_tree().root.find_children("*", "FxManager", true, false):
		return f as FxManager
	return null


## The keg alone (for dropped barrels): staves, hoops and a fizzing fuse.
func _keg() -> Mesh:
	if _keg_mesh == null:
		var mb := MeshBuilder.new()
		mb.add(MeshBuilder.cyl(0.16, 0.16, 0.44, 12), Transform3D(), SkeletonCrowd.KEG)
		mb.add(MeshBuilder.sphere(0.175, 12, 6), Transform3D(Basis.from_scale(Vector3(1.0, 1.25, 1.0)), Vector3.ZERO), SkeletonCrowd.KEG.darkened(0.1))
		for y in [-0.17, 0.0, 0.17]:
			mb.add(MeshBuilder.cyl(0.18, 0.18, 0.03, 12), Transform3D(Basis(), Vector3(0, y, 0)), SkeletonCrowd.HOOP)
		mb.limb(Vector3(0, 0.24, 0), Vector3(0.03, 0.34, 0.0), 0.01, 0.008, SkeletonCrowd.ROPE.darkened(0.4), 4)
		var gb := MeshBuilder.new()
		gb.add(MeshBuilder.sphere(0.035, 6, 4), Transform3D(Basis(), Vector3(0.035, 0.36, 0)), Color(1.0, 0.65, 0.2, 0.0))
		var m := mb.commit()
		gb.commit_into(m, MeshBuilder.glow_material())
		_keg_mesh = m
	return _keg_mesh
