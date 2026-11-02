class_name SubBosses
extends Node3D
## Sub-bosses and their waygates, per map (data: MAPS; only the Swamp for now).
##   - At each of the map's times (the Swamp: 2:00 and 4:00) a sub-boss (SubBoss) arrives 25-35 m
##     from you on dry ground. Spawns aren't reduced for it (main.boss_up() is the real boss only).
##   - When one dies it drops a Waygate where it fell (snapped to the nearest flat, dry, open
##     ground), plus elite-ish rewards (its XP gems, an elite's chance at a chest key).
##   - The first gate is inactive ("Needs another portal to activate" when you're near). When its
##     partner drops, both light up; press E (Activate) at one and you're thrown to the other,
##     landing in front of it facing away (enemies right there are shoved back). Then both
##     recharge for COOLDOWN s (E does nothing; the text counts down).
##   - The gates stay until the map is done: when the map boss dies (main._on_boss_defeated) or
##     the run ends they fade away. A sub-boss still alive then stays; it no longer drops a gate.
## Debug: `-- --subboss-at=T[,T2...]` replaces the map's times (and enables them on any map);
## `-- --waygates-at=T` drops two active gates near you at T s, and `-- --shot-subboss` keeps
## the camera on the sub-boss (screenshots).

const MAPS := {
	"swamp": {"times": [120.0, 240.0], "kind": "bog_shaman"},
}
const SPAWN_MIN := 25.0
const SPAWN_MAX := 35.0
const COOLDOWN := 90.0
const SHOVE_R := 5.0

var main: Node
var times: Array[float] = []
var kind := ""
var next := 0                       # index into times
var bosses: Array[SubBoss] = []     # alive (or dying) sub-bosses
var gates: Array[Waygate] = []
var done := false                   # the map is done: no more gates
var teleports := 0                  # (tests)
var spawned := 0
var _debug_gates := -1.0
var _shot_face := false
var _whoosh: AudioStreamPlayer
var _layer: CanvasLayer
var _flash: ColorRect
var _flash_t := 0.0


func setup(p_main: Node) -> void:
	main = p_main
	var m: Dictionary = MAPS.get(Settings.selected_map, {})
	for t in m.get("times", []):
		times.append(float(t))
	kind = m.get("kind", "bog_shaman")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--subboss-at="):
			times.clear()
			for v in a.split("=")[1].split(","):
				times.append(float(v))
		elif a.begins_with("--waygates-at="):
			_debug_gates = float(a.split("=")[1])
		elif a == "--shot-subboss":
			_shot_face = true


func _ready() -> void:
	_whoosh = AudioStreamPlayer.new()
	_whoosh.bus = Settings.SFX_BUS
	if ResourceLoader.exists("res://audio/subboss/gate_teleport.wav"):
		_whoosh.stream = load("res://audio/subboss/gate_teleport.wav")
	add_child(_whoosh)
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	_flash = ColorRect.new()
	_flash.color = Color(0.55, 1.0, 0.92, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_flash)


func enabled() -> bool:
	return not times.is_empty()


func _physics_process(dt: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= dt
		_flash.color.a = clampf(_flash_t / 0.4, 0.0, 1.0) * 0.75
	if main.state != "playing" or main.intro:
		return
	if not done and not main.boss_down and next < times.size() and main.run_time >= times[next]:
		next += 1
		spawn()
	if _debug_gates >= 0.0 and main.run_time >= _debug_gates:
		_debug_gates = -1.0
		var p: Vector3 = main.player.global_position
		var fwd := Vector3(-sin(main.player.cam_yaw), 0, -cos(main.player.cam_yaw))
		drop_gate(p + fwd * 9.0)
		drop_gate(p + fwd * 9.0 + Vector3(fwd.z, 0, -fwd.x) * 30.0)
	for k in range(bosses.size() - 1, -1, -1):
		if not is_instance_valid(bosses[k]):
			bosses.remove_at(k)
	if _shot_face and not bosses.is_empty() and bosses[0].row() >= 0:   # screenshots: look at it
		var to: Vector3 = main.enemies.pos[bosses[0].row()] - main.player.global_position
		main.player.cam_yaw = atan2(-to.x, -to.z) + 0.35
	_tick_gates()


## A sub-boss arrives 25-35 m away, on dry ground.
func spawn() -> SubBoss:
	var at: Vector3 = main._spawn_point(SPAWN_MIN, SPAWN_MAX)
	for k in 24:
		if not main.water.in_pool_xz(at.x, at.z) and not main.water.near_pool(at.x, at.z, 2.0):
			break
		at = main._spawn_point(SPAWN_MIN, SPAWN_MAX)
	var b := SubBoss.new()
	b.setup(main, at, main.hp_mult(), kind)
	if b.uid < 0:
		b.free()
		return null
	add_child(b)
	b.died.connect(_on_died.bind(b))
	bosses.append(b)
	spawned += 1
	return b


func _on_died(at: Vector3, _b: SubBoss) -> void:
	main.elites_killed += 1
	if main.keys != null:
		main.keys.on_elite_killed(at + Vector3(1.2, 0, 0))   # an elite's chance at a chest key
	if not done:
		drop_gate(at)


## Drop a gate at (the nearest good ground to) `at`; the second one lights up both.
func drop_gate(at: Vector3) -> Waygate:
	var avoid: Array = []
	for g in gates:
		avoid.append(g.global_position)
	var pos := Waygate.find_spot(main, at, avoid)
	var g := Waygate.new()
	g.setup(main.fx)
	add_child(g)
	g.global_position = pos
	var to: Vector3 = main.player.global_position - pos   # its front faces where you are
	g.rotation.y = atan2(to.x, to.z) if Vector2(to.x, to.z).length() > 0.5 else 0.0
	gates.append(g)
	var n := gates.size()
	if n % 2 == 0:   # gates pair up in the order they drop
		var a := gates[n - 2]
		a.partner = g
		g.partner = a
		a.activate()
		g.activate()
	return g


## The gate near the player (within USE_DIST) that E would use, or null.
func usable_gate() -> Waygate:
	var p: Vector3 = main.player.global_position
	var best: Waygate = null
	var bd := INF
	for g in gates:
		if not is_instance_valid(g) or g.state == "closing":
			continue
		var d := MapBoss.flat_dist(p, g.global_position)
		if d < bd and absf(p.y - g.global_position.y) < 3.5:
			bd = d
			best = g
	return best if best != null and bd < Waygate.USE_DIST else null


func _tick_gates() -> void:
	var p: Vector3 = main.player.global_position
	for k in range(gates.size() - 1, -1, -1):
		if not is_instance_valid(gates[k]):
			gates.remove_at(k)
	for g in gates:
		g.show_for(MapBoss.flat_dist(p, g.global_position))
	var g := usable_gate()
	if g != null and g.is_active() and g.partner != null and is_instance_valid(g.partner) and g.partner.is_active():
		if main.player.take_activate():   # one teleport per press
			teleport(g)


## Through `from` to its partner: land in front of it facing away, shove whatever's there, and
## both gates recharge.
func teleport(from: Waygate) -> void:
	var to := from.partner
	var pl: Player = main.player
	main.fx.burst(from.global_position + Vector3(0, Waygate.OPEN_C, 0), 3.0, Waygate.RUNE, 0.45)
	var land := to.arrival()
	land.y = main.water.ground_height(land.x, land.z) + 0.3
	pl.global_position = land
	pl.velocity = Vector3.ZERO
	var f := to.front()
	pl.cam_yaw = atan2(-f.x, -f.z)   # looking away from the gate
	if pl.has_method("reset_physics_interpolation"):
		pl.reset_physics_interpolation()
	main.fx.burst(to.global_position + Vector3(0, Waygate.OPEN_C, 0), 3.5, Waygate.RUNE, 0.5)
	var em: EnemyManager = main.enemies
	for i in em.query_radius(land, SHOVE_R, false):   # don't land in a crowd
		if not em.is_boss(i):
			var away := em.pos[i] - land
			away.y = 0.0
			em.knock(i, away if away.length() > 0.05 else f, 6.0, 0.3)
	if _whoosh.stream:
		_whoosh.play()
	_flash_t = 0.4
	from.start_cooldown(COOLDOWN)
	to.start_cooldown(COOLDOWN)
	teleports += 1


## The map is done (its boss fell): the gates fade away and no more drop.
func on_map_boss_defeated() -> void:
	done = true
	clear_gates()


func clear_gates() -> void:
	for g in gates:
		if is_instance_valid(g):
			g.close()
	gates.clear()
