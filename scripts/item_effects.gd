class_name ItemEffects
extends Node3D
## Behaviour for items that aren't plain stat modifiers. Each item listens on the event bus
## and reads its own stats (bomb_chance, fang_chance...), so levelling an item is still just data.
## Explosions are queued and resolved next tick (capped per tick) so chain reactions can't recurse.

const MAX_PER_TICK := 12
const MAX_QUEUED := 60

var stats: Stats
var enemies: EnemyManager
var player: Player
var rng: RandomNumberGenerator

var _bombs := PackedVector3Array()
var _blasts: Array = []   # [pos, damage, radius] (forged Fireballs)
var _fx: Array = []   # [MeshInstance3D, age, radius]
var _boom_mesh: SphereMesh


func setup(p_stats: Stats, p_enemies: EnemyManager, p_player: Player, p_rng: RandomNumberGenerator) -> void:
	stats = p_stats
	enemies = p_enemies
	player = p_player
	rng = p_rng


func _ready() -> void:
	Events.enemy_killed.connect(_on_enemy_killed)
	_boom_mesh = SphereMesh.new()
	_boom_mesh.radius = 1.0
	_boom_mesh.height = 2.0
	_boom_mesh.radial_segments = 12
	_boom_mesh.rings = 6


func _on_enemy_killed(p: Vector3, _type_id: int) -> void:
	var bomb := stats.value("bomb_chance")
	if bomb > 0.0 and _bombs.size() < MAX_QUEUED and rng.randf() < bomb:
		_bombs.append(p)
	var fang := stats.value("fang_chance")
	if fang > 0.0 and rng.randf() < fang:
		player.heal(2.0)


## A Blast-Bomb-style explosion at `at` for `dmg` within `r` (queued, resolved next tick).
func blast(at: Vector3, dmg: float, r: float) -> void:
	if _blasts.size() < MAX_QUEUED:
		_blasts.append([at, dmg, r])


func tick(dt: float) -> void:
	var nb := mini(_blasts.size(), MAX_PER_TICK)
	for k in nb:
		var b: Array = _blasts[k]
		var bp: Vector3 = b[0]
		var c := bp + Vector3(0.0, 0.6, 0.0)
		for e in enemies.query_radius(c, b[2]):
			var away := enemies.pos[e] - bp
			away.y = 0.0
			enemies.damage(e, b[1], away.normalized() * 8.0)
		_spawn_fx(c, b[2])
	if nb > 0:
		_blasts = _blasts.slice(nb)
	if not _bombs.is_empty():
		var n := mini(_bombs.size(), MAX_PER_TICK)
		var now := _bombs.slice(0, n)
		_bombs = _bombs.slice(n)
		var r := 3.0 * stats.value("area")
		var d := stats.value("bomb_damage") * stats.value("damage")
		for p in now:
			var c := p + Vector3(0.0, 0.6, 0.0)
			for e in enemies.query_radius(c, r):
				var away := enemies.pos[e] - p
				away.y = 0.0
				enemies.damage(e, d, away.normalized() * 8.0)
			_spawn_fx(c, r)
	_update_fx(dt)


func _spawn_fx(at: Vector3, r: float) -> void:
	if _fx.size() > 30:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _boom_mesh
	mi.material_override = WeaponSystem._fx_material(Color(1.0, 0.55, 0.15, 0.55))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	mi.global_position = at
	_fx.append([mi, 0.0, r])


func _update_fx(dt: float) -> void:
	for k in range(_fx.size() - 1, -1, -1):
		var fx: Array = _fx[k]
		var mi: MeshInstance3D = fx[0]
		fx[1] += dt
		var tt: float = fx[1] / 0.25
		if tt >= 1.0:
			mi.queue_free()
			_fx.remove_at(k)
			continue
		mi.scale = Vector3.ONE * fx[2] * (0.4 + 0.6 * tt)
		(mi.material_override as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - tt)
