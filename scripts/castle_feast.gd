class_name CastleFeast
extends Node3D
## The dining hall's very long table, laid with a feast. Every plate, goblet, roast, loaf,
## fruit, jug and candlestick is a real rigid body under normal gravity, asleep until disturbed:
##   - walking (or landing) on the table kicks whatever you step into along your motion
##   - any blast nearby (FxManager.burst: explosions, Fire Nova, Meteor, shatters...) flings
##     the food outward from it
## Food sits on its own physics layer, so it never blocks you or the goblins, but it does hit
## the table, the floor, the walls and the rest of the food.

const LAYER_FOOD := 1 << 3        # physics layer 4
const KICK_RADIUS := 1.2          # metres around your feet that you kick (generous: it's a stampede)
const KICK_COOLDOWN := 0.25
const SPACING := 1.0              # metres between place settings along each side
const BENCH_GAP := 1.15           # benches this far out from the table's edges
# Loitering on the table brings a chandelier down on you
const STAND_TIME := 2.0           # seconds on the table top before one drops
const DROP_WARN := 1.0            # its marker shows this long before it hits
const DROP_RADIUS := 2.4
const DROP_DAMAGE := 0.15         # of the player's max HP
const DROP_LINGER := 5.0          # the wreck lies on the table this long

var rect := []                    # table top x0, z0, x1, z1
var top_y := 0.95
var items: Array[RigidBody3D] = []
var _kicked := {}                 # item -> time it was last kicked
var _time := 0.0
var kicks := 0                    # counters for tests
var blasts := 0
var player: Node3D
var _meshes := {}
var stand_t := 0.0                # seconds the player has been standing on the table
var drops := 0                    # counters for tests
var drop_hits := 0
var _falling: Array = []          # {at, t, node, marker}
var _rng := RandomNumberGenerator.new()
var _snap_sfx: AudioStreamPlayer3D
var _crash_sfx: AudioStreamPlayer3D


func build(rng: RandomNumberGenerator, table_rect: Array, height: float) -> void:
	add_to_group("castle_feast")
	rect = table_rect
	_rng.seed = rng.randi()
	_snap_sfx = _sfx("res://audio/castle/chandelier_snap.wav")
	_crash_sfx = _sfx("res://audio/castle/chandelier_crash.wav")
	top_y = height
	_furniture()
	var x0: float = rect[0]
	var x1: float = rect[2]
	var z: float = rect[1] + 0.6
	var k := 0
	while z < float(rect[3]) - 0.6:
		for side in [-1.0, 1.0]:   # a place setting at each side
			var x: float = (x0 + 0.45) if side < 0 else (x1 - 0.45)
			_add("plate", Vector3(x, 0, z), rng)
			var kind: String = ["chicken_leg", "bread", "apple", "cheese", "none"][rng.randi() % 5]
			if kind != "none":
				_add(kind, Vector3(x, 0.05, z + rng.randf_range(-0.05, 0.05)), rng)
			if rng.randf() < 0.45:
				_add("goblet", Vector3(x + side * -0.35, 0, z + 0.22), rng)
		if k % 2 == 0:   # down the middle: roasts, pies, fruit bowls, jugs, candlesticks
			var mid: String = ["roast", "pie", "grapes", "jug", "candlestick", "roast_pig", "apple", "bread"][rng.randi() % 8]
			_add(mid, Vector3(rng.randf_range(-0.25, 0.25), 0, z), rng)
		z += SPACING
		k += 1


func _furniture() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.27, 0.16, 0.08)
	wood.roughness = 0.75
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.42, 0.38, 0.3)
	cloth.roughness = 1.0
	var x0: float = rect[0]
	var z0: float = rect[1]
	var x1: float = rect[2]
	var z1: float = rect[3]
	var w := x1 - x0
	var l := z1 - z0
	var c := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	var table := StaticBody3D.new()
	add_child(table)
	_solid(table, Vector3(w, 0.12, l), c + Vector3(0, top_y - 0.06, 0), wood)
	_visual(table, Vector3(w * 0.92, 0.02, l), c + Vector3(0, top_y + 0.005, 0), cloth)   # table runner
	var z := z0 + 2.0
	while z < z1 - 1.0:
		for side in [-1.0, 1.0]:
			_visual(table, Vector3(0.14, top_y - 0.12, 0.14), Vector3(c.x + side * (w * 0.5 - 0.25), (top_y - 0.12) * 0.5, z), wood)
		z += 8.0
	for side in [-1.0, 1.0]:   # long benches either side
		var bench := StaticBody3D.new()
		add_child(bench)
		var bx: float = c.x + side * (w * 0.5 + BENCH_GAP)
		_solid(bench, Vector3(0.7, 0.1, l - 1.0), Vector3(bx, 0.5, c.z), wood)
		var bz := z0 + 2.0
		while bz < z1 - 1.0:
			_visual(bench, Vector3(0.6, 0.45, 0.12), Vector3(bx, 0.22, bz), wood)
			bz += 6.0


func _solid(body: StaticBody3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var s := BoxShape3D.new()
	s.size = size
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position = at
	body.add_child(cs)
	_visual(body, size, at, mat)


func _visual(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = at
	parent.add_child(mi)


# ------------------------------------------------------------------ food

## [mesh builder, collision shape, mass kg, centre height] per kind (meshes built once, shared)
func _kind(kind: String) -> Array:
	if _meshes.has(kind):
		return _meshes[kind]
	var mb := MeshBuilder.new()
	var gb := MeshBuilder.new()
	var shape: Shape3D
	var mass := 0.3
	var h := 0.05
	match kind:
		"plate":
			mb.add(MeshBuilder.cyl(0.17, 0.12, 0.025, 14), Transform3D(), Color(0.7, 0.7, 0.72, 0))
			mb.add(MeshBuilder.cyl(0.12, 0.12, 0.028, 14), Transform3D(), Color(0.85, 0.83, 0.78, 0))
			shape = _cyl(0.17, 0.03)
			mass = 0.4
			h = 0.015
		"goblet":
			mb.add(MeshBuilder.cyl(0.05, 0.05, 0.015, 10), Transform3D(Basis(), Vector3(0, -0.085, 0)), Color(0.75, 0.57, 0.2, 0))
			mb.add(MeshBuilder.cyl(0.012, 0.012, 0.09, 6), Transform3D(Basis(), Vector3(0, -0.04, 0)), Color(0.75, 0.57, 0.2, 0))
			mb.add(MeshBuilder.cyl(0.06, 0.035, 0.09, 10), Transform3D(Basis(), Vector3(0, 0.045, 0)), Color(0.8, 0.6, 0.22, 0))
			mb.add(MeshBuilder.cyl(0.052, 0.052, 0.01, 10), Transform3D(Basis(), Vector3(0, 0.085, 0)), Color(0.35, 0.03, 0.06, 0))   # wine
			shape = _cyl(0.05, 0.19)
			mass = 0.25
			h = 0.095
		"chicken_leg":
			mb.add(MeshBuilder.sphere(0.06, 8, 5), Transform3D(Basis.from_scale(Vector3(1.4, 1, 1)), Vector3(0.03, 0, 0)), Color(0.55, 0.3, 0.1, 0))
			mb.limb(Vector3(-0.03, 0, 0), Vector3(-0.12, 0.02, 0), 0.015, 0.015, Color(0.9, 0.87, 0.78, 0))
			shape = _sphere(0.06)
			mass = 0.15
			h = 0.06
		"bread":
			mb.add(MeshBuilder.sphere(0.1, 10, 6), Transform3D(Basis.from_scale(Vector3(1.6, 0.7, 1.0)), Vector3.ZERO), Color(0.72, 0.48, 0.2, 0))
			shape = _box(Vector3(0.3, 0.13, 0.19))
			mass = 0.3
			h = 0.07
		"apple":
			var red := Color(0.65, 0.08, 0.06, 0) if randf() < 0.6 else Color(0.45, 0.6, 0.12, 0)
			mb.add(MeshBuilder.sphere(0.045, 8, 6), Transform3D(), red)
			mb.limb(Vector3(0, 0.04, 0), Vector3(0.005, 0.07, 0), 0.006, 0.004, Color(0.25, 0.15, 0.05, 0))
			shape = _sphere(0.045)
			mass = 0.15
			h = 0.045
		"cheese":
			mb.add(MeshBuilder.cyl(0.0, 0.11, 0.08, 3), Transform3D(Basis(Vector3(1, 0, 0), PI / 2), Vector3.ZERO), Color(0.9, 0.75, 0.3, 0))
			shape = _box(Vector3(0.18, 0.08, 0.16))
			mass = 0.2
			h = 0.04
		"roast":
			mb.add(MeshBuilder.cyl(0.28, 0.24, 0.03, 16), Transform3D(Basis(), Vector3(0, -0.06, 0)), Color(0.75, 0.75, 0.78, 0))
			mb.add(MeshBuilder.sphere(0.15, 10, 6), Transform3D(Basis.from_scale(Vector3(1.3, 0.85, 1.0)), Vector3(0, 0.05, 0)), Color(0.55, 0.28, 0.08, 0))
			for s in [-1.0, 1.0]:
				mb.add(MeshBuilder.sphere(0.06, 8, 5), Transform3D(Basis.from_scale(Vector3(1.5, 1, 1)), Vector3(0.17, 0.05, s * 0.09)), Color(0.5, 0.25, 0.07, 0))
			shape = _cyl(0.28, 0.25)
			mass = 1.5
			h = 0.075
		"roast_pig":
			mb.add(MeshBuilder.box(Vector3(0.75, 0.04, 0.42)), Transform3D(Basis(), Vector3(0, -0.12, 0)), Color(0.7, 0.68, 0.7, 0))
			mb.add(MeshBuilder.sphere(0.18, 12, 6), Transform3D(Basis.from_scale(Vector3(1.8, 0.85, 1.0)), Vector3(0, 0.04, 0)), Color(0.6, 0.3, 0.12, 0))
			mb.add(MeshBuilder.sphere(0.1, 10, 6), Transform3D(Basis(), Vector3(0.33, 0.06, 0)), Color(0.58, 0.29, 0.11, 0))
			mb.add(MeshBuilder.sphere(0.04, 8, 5), Transform3D(Basis(), Vector3(0.43, 0.05, 0)), Color(0.75, 0.1, 0.08, 0))   # apple in its mouth
			shape = _box(Vector3(0.75, 0.32, 0.42))
			mass = 4.0
			h = 0.14
		"pie":
			mb.add(MeshBuilder.cyl(0.16, 0.13, 0.06, 14), Transform3D(), Color(0.78, 0.55, 0.25, 0))
			mb.add(MeshBuilder.sphere(0.15, 12, 4), Transform3D(Basis.from_scale(Vector3(1, 0.25, 1)), Vector3(0, 0.03, 0)), Color(0.82, 0.6, 0.3, 0))
			shape = _cyl(0.16, 0.08)
			mass = 0.6
			h = 0.04
		"grapes":
			mb.add(MeshBuilder.cyl(0.16, 0.1, 0.06, 12), Transform3D(Basis(), Vector3(0, -0.03, 0)), Color(0.75, 0.57, 0.2, 0))
			for g in 14:
				var a := g * 2.4
				var r := 0.03 + (g % 5) * 0.018
				mb.add(MeshBuilder.sphere(0.028, 6, 4), Transform3D(Basis(), Vector3(cos(a) * r, 0.02 + (g / 5) * 0.03, sin(a) * r)), Color(0.3, 0.08, 0.35, 0))
			shape = _cyl(0.16, 0.12)
			mass = 0.5
			h = 0.05
		"jug":
			mb.add(MeshBuilder.cyl(0.06, 0.1, 0.3, 12), Transform3D(), Color(0.5, 0.3, 0.18, 0))
			mb.add(MeshBuilder.sphere(0.1, 10, 6), Transform3D(Basis.from_scale(Vector3(1, 0.6, 1)), Vector3(0, -0.06, 0)), Color(0.5, 0.3, 0.18, 0))
			shape = _cyl(0.1, 0.32)
			mass = 1.0
			h = 0.16
		"candlestick":
			mb.add(MeshBuilder.cyl(0.08, 0.1, 0.03, 10), Transform3D(Basis(), Vector3(0, -0.2, 0)), Color(0.75, 0.57, 0.2, 0))
			mb.add(MeshBuilder.cyl(0.02, 0.025, 0.25, 8), Transform3D(Basis(), Vector3(0, -0.07, 0)), Color(0.75, 0.57, 0.2, 0))
			mb.add(MeshBuilder.cyl(0.025, 0.025, 0.16, 8), Transform3D(Basis(), Vector3(0, 0.13, 0)), Color(0.92, 0.87, 0.72, 0))
			gb.add(MeshBuilder.sphere(0.025, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 1.8, 1)), Vector3(0, 0.25, 0)), Color(1.0, 0.62, 0.22, 0))
			shape = _cyl(0.09, 0.45)
			mass = 0.6
			h = 0.215
	var mesh := mb.commit()
	gb.commit_into(mesh, MeshBuilder.glow_material())
	_meshes[kind] = [mesh, shape, mass, h]
	return _meshes[kind]


func _cyl(r: float, h: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return s


func _sphere(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


func _box(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


## Put one item on the table top at `at` (x, extra lift, z).
func _add(kind: String, at: Vector3, rng: RandomNumberGenerator) -> void:
	var k := _kind(kind)
	var body := RigidBody3D.new()
	body.mass = k[2]
	body.collision_layer = LAYER_FOOD
	body.collision_mask = 1 | LAYER_FOOD
	body.can_sleep = true
	body.sleeping = true
	body.angular_damp = 0.6
	body.continuous_cd = false
	body.position = Vector3(at.x, top_y + float(k[3]) + at.y + 0.002, at.z)
	body.rotation.y = rng.randf() * TAU
	body.set_meta("kind", kind)
	var mi := MeshInstance3D.new()
	mi.mesh = k[0]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = k[1]
	body.add_child(cs)
	add_child(body)
	items.append(body)


# ------------------------------------------------------------------ interaction

var _hooked := false   # FxManager is created after the map: hook up on the first physics frame


func _physics_process(dt: float) -> void:
	_time += dt
	if not _hooked:
		_hook_bursts()
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
		if player == null:
			return
	var p := player.global_position
	_tick_chandeliers(dt, p)
	if p.x < float(rect[0]) - 1.5 or p.x > float(rect[2]) + 1.5 or p.z < float(rect[1]) - 1.5 or p.z > float(rect[3]) + 1.5:
		return
	if p.y < top_y - 0.6:
		return   # beside the table, not on it
	var v: Vector3 = player.get("velocity") if player.get("velocity") != null else Vector3.ZERO
	var hv := Vector3(v.x, 0, v.z)
	var speed := hv.length()
	var landing := v.y < -4.0
	if speed < 0.6 and not landing:
		return
	for it in items:
		var ip := it.global_position
		if absf(ip.z - p.z) > KICK_RADIUS or absf(ip.x - p.x) > KICK_RADIUS or ip.y > p.y + 1.2 or ip.y < p.y - 1.0:
			continue
		if _time - float(_kicked.get(it, -10.0)) < KICK_COOLDOWN:
			continue
		_kicked[it] = _time
		var away := Vector3(ip.x - p.x, 0, ip.z - p.z)
		var dir := (hv.normalized() * 0.75 + away.normalized() * 0.5).normalized() if speed > 0.6 else away.normalized()
		var push := clampf(2.2 + speed * 0.45, 2.0, 8.0) + (3.0 if landing else 0.0)
		it.apply_central_impulse((dir * push + Vector3(0, randf_range(2.5, 4.5), 0)) * it.mass)
		it.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * it.mass * 0.15)
		kicks += 1


# ------------------------------------------------------------------ falling chandeliers

## Standing on the table top for STAND_TIME s drops a chandelier where you were: a marker on
## the table fills for DROP_WARN s, then it crashes down for DROP_DAMAGE of your max HP if
## you're still under it. Keep standing there and another follows every STAND_TIME s.
func _tick_chandeliers(dt: float, p: Vector3) -> void:
	var on_table := p.x >= float(rect[0]) and p.x <= float(rect[2]) and p.z >= float(rect[1]) and p.z <= float(rect[3]) \
		and p.y > top_y - 0.25 and p.y < top_y + 0.4
	stand_t = stand_t + dt if on_table else 0.0
	if stand_t >= STAND_TIME:
		stand_t = 0.0
		_drop(Vector3(p.x, top_y, p.z))
	for k in range(_falling.size() - 1, -1, -1):
		var f: Dictionary = _falling[k]
		f["t"] += dt
		var t: float = f["t"]
		var at: Vector3 = f["at"]
		var node: Node3D = f["node"]
		if t < DROP_WARN:
			var marker: GroundDisc = f["marker"]
			marker.set_fill(t / DROP_WARN)
			marker.alpha = 0.45 + 0.2 * sin(t * 30.0)
			var fall := clampf((t - DROP_WARN * 0.35) / (DROP_WARN * 0.65), 0.0, 1.0)   # it gives, then plummets
			var shake := 0.08 * (1.0 - fall) * sin(t * 60.0)
			node.position = Vector3(at.x + shake, lerpf(float(f["top"]), at.y, fall * fall), at.z)
			continue
		if not f.get("landed", false):
			f["landed"] = true
			_crash(at, f)
		if t >= DROP_WARN + DROP_LINGER:
			node.queue_free()
			_falling.remove_at(k)


func _drop(at: Vector3) -> void:
	drops += 1
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = CastleProps.chandelier(_rng)["mesh"]
	node.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.42)
	light.light_energy = 2.0
	light.omni_range = 8.0
	light.position.y = 0.5
	node.add_child(light)
	add_child(node)
	var top := CastleBuilder.CEILING - 7.0
	node.position = Vector3(at.x, top, at.z)
	var marker := GroundDisc.create(DROP_RADIUS, Color(1.0, 0.25, 0.1, 0.5))
	marker.set_fill(0.0)
	marker.set_lift(0.04)
	add_child(marker)
	marker.global_position = at
	_falling.append({"at": at, "t": 0.0, "node": node, "marker": marker, "top": top})
	_play(_snap_sfx, at)


func _crash(at: Vector3, f: Dictionary) -> void:
	(f["marker"] as GroundDisc).queue_free()
	var node: Node3D = f["node"]
	node.position = at
	node.rotation = Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf() * TAU, _rng.randf_range(-0.25, 0.25))   # lands askew
	var light := node.get_child(1) as OmniLight3D
	node.create_tween().tween_property(light, "light_energy", 0.0, 1.2)   # candles snuffed
	blast(at + Vector3(0, 0.3, 0), DROP_RADIUS)
	_play(_crash_sfx, at)
	if player != null and is_instance_valid(player):
		var pp := player.global_position
		if Vector2(pp.x - at.x, pp.z - at.z).length() <= DROP_RADIUS and pp.y < at.y + 2.5:
			if player.has_method("hurt") and player.hurt(float(player.get("max_hp")) * DROP_DAMAGE):
				drop_hits += 1
		if player.has_method("add_shake"):
			player.add_shake(0.5 if Vector2(pp.x - at.x, pp.z - at.z).length() < 12.0 else 0.2)
	for fx in get_tree().root.find_children("*", "FxManager", true, false):
		(fx as FxManager).burst(at + Vector3(0, 0.6, 0), DROP_RADIUS, Color(1.0, 0.75, 0.4), 0.3)
		break


func _sfx(path: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = Settings.SFX_BUS
	p.unit_size = 14.0
	p.max_polyphony = 3
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p


func _play(p: AudioStreamPlayer3D, at: Vector3) -> void:
	if p and p.stream:
		p.global_position = at
		p.play()


func _hook_bursts() -> void:
	for f in get_tree().root.find_children("*", "FxManager", true, false):
		var fx := f as FxManager
		if fx and not fx.burst_fired.is_connected(blast):
			fx.burst_fired.connect(blast)
			_hooked = true


## Fling food outward from an explosion at `at` with radius `radius` (any burst near the table).
func blast(at: Vector3, radius: float) -> void:
	var reach := radius * 1.3 + 0.5
	if at.x < float(rect[0]) - reach or at.x > float(rect[2]) + reach or at.z < float(rect[1]) - reach or at.z > float(rect[3]) + reach:
		return
	var hit := false
	for it in items:
		var d := it.global_position - at
		var dist := d.length()
		if dist > reach:
			continue
		var f := 1.0 - dist / reach
		var dir := (d + Vector3(0, 0.6, 0)).normalized() if dist > 0.01 else Vector3.UP
		it.apply_central_impulse(dir * (3.0 + radius * 1.6) * f * it.mass)
		it.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * it.mass * 0.2 * f)
		hit = true
	if hit:
		blasts += 1


func awake_count() -> int:
	var n := 0
	for it in items:
		if not it.sleeping:
			n += 1
	return n
