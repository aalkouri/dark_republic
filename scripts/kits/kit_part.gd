class_name KitPart
extends Node3D
## One roster character's three abilities (RosterKit hands it casts, ticks and kills). The
## shared helpers - rings, motes, sounds, timers, damage scaling - live on RosterKit (`k`).
## Numbers match data/abilities.json; flat damage scales with the Damage stat.

const YARD := 0.9144

var k: RosterKit


func cast(_i: int) -> void:
	pass


func tick(_dt: float) -> void:
	pass


func active(_name: String) -> bool:
	return false


func on_kill(_at: Vector3, _type_id: int) -> void:
	pass


func weapon_mult() -> float:
	return 1.0


func weapon_fired() -> void:
	pass


func clone_list() -> Array:
	return []


func adjust_cooldown(_i: int, cd: float) -> float:
	return cd


# ------------------------------------------------------------------ shortcuts

var enemies: EnemyManager:
	get: return k.enemies
var player: Player:
	get: return k.player
var stats: Stats:
	get: return k.stats
var fx: FxManager:
	get: return k.fx


func dmg() -> float:
	return k.stats.value("damage")


func play(key: String, volume_db := 0.0) -> void:
	if not k._sounds.has(key):
		k._sounds[key] = k._sfx(RosterKit.SOUND_DIR + key + ".wav")
	k._play(key, volume_db)


func ring(at: Vector3, radius: float, color: Color, time: float) -> void:
	k._ring(at, radius, color, time)


func mote(at: Vector3, vel: Vector3, life: float, color: Color, size: float, home := false, drag := 3.0) -> void:
	k._mote(at, vel, life, color, size, home, drag)


func after(secs: float, f: Callable) -> void:
	k._after(secs, f)


func feet() -> Vector3:
	return player.global_position


func chest() -> Vector3:
	return player.global_position + Vector3(0, 0.9, 0)


## Ground height under `p` (floors indoors, hills outdoors).
func ground(p: Vector3) -> Vector3:
	var from := Vector3(p.x, maxf(p.y, player.global_position.y) + 2.5, p.z)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -12, 0))
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else Vector3(p.x, SwampWater.height_at(p.x, p.z), p.z)


## Flat direction the camera looks (where "aim" points when there's no target).
func aim_dir() -> Vector3:
	return Vector3(-sin(player.cam_yaw), 0.0, -cos(player.cam_yaw))


func aim_point(max_range: float) -> Vector3:
	return k.hub.aim_point(max_range)


## Enemies within `r` of `at`, the boss included unless `no_boss`.
func near(at: Vector3, r: float, no_boss := false) -> PackedInt32Array:
	var all := enemies.query_radius(at + Vector3(0, 0.8, 0), r, false)
	if not no_boss:
		return all
	var out := PackedInt32Array()
	for i in all:
		if not enemies.is_boss(i):
			out.append(i)
	return out


## A glowing unshaded material.
static func glow_mat(c: Color, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_fog = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


## A world-space node (not carried by the player) under this part.
func spawn(n: Node3D, at: Vector3) -> Node3D:
	n.top_level = true
	add_child(n)
	n.global_position = at
	return n


## Particles in the kit's colours: `amount` motes of `size` m living `life` s.
func particles(size: float, life: float, amount: int, c0: Color, c1: Color) -> CPUParticles3D:
	var p := Abilities._flame_particles(size, life, amount)
	var grad := Gradient.new()
	grad.set_color(0, c0)
	grad.set_color(1, c1)
	p.color_ramp = grad
	return p


## Fade a material's alpha to 0 over `secs`, then free `node`.
func fade_out(node: Node, mat: StandardMaterial3D, secs: float) -> void:
	var tw := node.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, secs)
	tw.tween_callback(node.queue_free)


## A temporary point light.
func flash_light(at: Vector3, c: Color, energy: float, r: float, secs: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = r
	spawn(l, at)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, secs)
	tw.tween_callback(l.queue_free)


## Moving the player along a path the kit controls (leaps, dashes, rolls): he can't steer,
## the camera follows.
func begin_scripted() -> void:
	player.scripted = true
	player.velocity = Vector3.ZERO


func end_scripted(at: Vector3) -> void:
	player.scripted = false
	player.global_position = at + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
