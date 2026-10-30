class_name KitMerlin
extends KitPart
## Merlin
##   1  Time Warp   35 s  enemies within 20 m are 70% slower for 5 s; +50% attack speed meanwhile
##   2  Polymorph   50 s  up to 40 enemies within 20 m become frogs for 8 s (not the boss): harmless,
##                        double damage taken, 2x XP
##   3  Rewind     150 s  HP and shield back to what they were 8 s ago (never lower), the other two
##                        cooldowns reset, every enemy within 25 m flung back 10 yd and stunned 2 s

const WARP_TIME := 5.0
const WARP_RADIUS := 20.0
const WARP_SLOW := 0.3
const WARP_HASTE := 1.5
const POLY_MAX := 40
const POLY_RADIUS := 20.0
const POLY_TIME := 8.0
const REWIND_BACK := 8.0
const REWIND_RADIUS := 25.0
const REWIND_FLING := 10.0 * YARD
const REWIND_STUN := 2.0
const HISTORY_STEP := 0.25

var _warp_t := 0.0
var _warp_tick := 0.0
var _warp_root: Node3D
var _hands: Array[Node3D] = []
var _history: Array = []        # [hp, shield] every HISTORY_STEP s, newest last
var _hist_t := 0.0
var _frogs: MultiMesh
var _frog_t := 0.0
var _rewound := 0.0             # seconds of the rewind effect left (visual)


func _ready() -> void:
	_frogs = MultiMesh.new()
	_frogs.transform_format = MultiMesh.TRANSFORM_3D
	_frogs.use_colors = true
	_frogs.mesh = _frog_mesh()
	_frogs.instance_count = int(POLY_MAX * Abilities.LEVEL_POWER_MAX) * 2
	_frogs.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _frogs
	mmi.top_level = true
	mmi.custom_aabb = AABB(Vector3(-500, -100, -500), Vector3(1000, 300, 1000))
	add_child(mmi)


func cast(i: int) -> void:
	match i:
		0: _time_warp()
		1: _polymorph()
		2: _rewind()


func active(name: String) -> bool:
	match name:
		"warp": return _warp_t > 0.0
		"polymorph": return enemies.frog_count > 0
	return false


func adjust_cooldown(i: int, cd: float) -> float:
	if i == 2:   # Rewind resets the other two (after its own cooldown starts)
		var c := k.hub.cooldown
		c[0] = 0.0
		c[1] = 0.0
		k.hub.cooldown = c
	return cd


func tick(dt: float) -> void:
	# What HP and shield were, for Rewind
	_hist_t -= dt
	if _hist_t <= 0.0:
		_hist_t = HISTORY_STEP
		_history.append([player.hp, player.shield])
		var keep := int(REWIND_BACK / HISTORY_STEP) + 1
		if _history.size() > keep:
			_history = _history.slice(_history.size() - keep)
	_tick_warp(dt)
	_tick_frogs(dt)


# ------------------------------------------------------------------ Time Warp

func _time_warp() -> void:
	play("time_warp")
	if _warp_t <= 0.0:
		stats.apply("attack_speed", "mult", WARP_HASTE)
		_build_warp()
	_warp_t = WARP_TIME * pw(0)
	_warp_tick = 0.0
	ring(feet(), WARP_RADIUS, k._light, 0.5)
	fx.burst(chest(), 4.0, k._main, 0.4)


## A pale blue bubble of slow time, with a clock face on the ground whose hands crawl.
func _build_warp() -> void:
	_warp_root = Node3D.new()
	spawn(_warp_root, feet())
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = WARP_RADIUS
	sm.height = WARP_RADIUS * 1.2
	sm.radial_segments = 48
	sm.rings = 16
	var dm := glow_mat(Color(0.45, 0.6, 1.0, 0.07))
	dm.cull_mode = BaseMaterial3D.CULL_FRONT   # see the inside
	sm.material = dm
	dome.mesh = sm
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warp_root.add_child(dome)
	var face := GroundDisc.create(WARP_RADIUS, Color(0.55, 0.7, 1.0, 0.35), true)
	face.set_ring(0.96)
	_warp_root.add_child(face)
	var inner := GroundDisc.create(WARP_RADIUS * 0.35, Color(0.55, 0.7, 1.0, 0.25), true)
	inner.set_ring(0.9)
	_warp_root.add_child(inner)
	var mat := glow_mat(Color(0.75, 0.85, 1.0, 0.55))
	for h in 12:   # hour marks
		var mark := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 0.05, 2.0 if h % 3 == 0 else 1.0)
		bm.material = mat
		mark.mesh = bm
		var a := TAU * h / 12.0
		mark.position = Vector3(sin(a), 0.15, -cos(a)) * (WARP_RADIUS - 2.0) + Vector3(0, 0.15, 0)
		mark.rotation.y = -a
		_warp_root.add_child(mark)
	_hands.clear()
	for h in 2:   # hour and minute hands
		var pivot := Node3D.new()
		pivot.position.y = 0.2
		var hand := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var length := WARP_RADIUS * (0.55 if h == 0 else 0.85)
		bm.size = Vector3(0.5 if h == 0 else 0.3, 0.05, length)
		bm.material = mat
		hand.mesh = bm
		hand.position.z = -length * 0.5
		pivot.add_child(hand)
		_warp_root.add_child(pivot)
		_hands.append(pivot)
	_warp_root.scale = Vector3.ONE * 0.05
	_warp_root.create_tween().tween_property(_warp_root, "scale", Vector3.ONE, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _tick_warp(dt: float) -> void:
	if _warp_t <= 0.0:
		return
	_warp_t -= dt
	if is_instance_valid(_warp_root):
		_warp_root.global_position = feet()
		_hands[0].rotation.y -= dt * 0.25
		_hands[1].rotation.y -= dt * 2.0
	_warp_tick -= dt
	if _warp_tick <= 0.0:
		_warp_tick = 0.2
		for i in near(feet(), WARP_RADIUS):
			enemies.slow(i, WARP_SLOW, 0.45)
		if randf() < 0.8:   # sand of time drifting upward
			var a := randf() * TAU
			var r := randf() * WARP_RADIUS
			mote(feet() + Vector3(cos(a) * r, 0.3, sin(a) * r), Vector3(0, 1.2, 0), 1.5, k._light, 0.12, false, 0.0)
	if _warp_t <= 0.0:
		stats.apply("attack_speed", "mult", 1.0 / WARP_HASTE)
		if is_instance_valid(_warp_root):
			var root := _warp_root
			var tw := root.create_tween()
			tw.tween_property(root, "scale", Vector3.ONE * 0.02, 0.3).set_ease(Tween.EASE_IN)
			tw.tween_callback(root.queue_free)
		_warp_root = null


# ------------------------------------------------------------------ Polymorph

func _polymorph() -> void:
	play("polymorph")
	var n := 0
	var most := int(round(POLY_MAX * pw(1)))
	for i in enemies.nearest_k(feet(), POLY_RADIUS, most * 2):
		if n >= most:
			break
		if enemies.is_boss(i):
			continue
		enemies.frog(i, POLY_TIME)
		n += 1
		var c := enemies.center_of(i)
		fx.burst(c, 1.0, Color(0.55, 1.0, 0.4), 0.3)
		for m in 3:
			mote(c, Vector3(randf_range(-2, 2), randf_range(1, 3), randf_range(-2, 2)), 0.7, Color(1.0, 0.85, 0.4) if m == 0 else k._main, 0.14, false, 4.0)
	ring(feet(), POLY_RADIUS, Color(0.6, 1.0, 0.45), 0.45)
	print_verbose("Polymorph: %d frogs" % n)


## A frog: squat green body, pale belly, two bulging eyes. Faces -Z, sits on y = 0.
func _frog_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [
		[Vector3(0, 0.28, 0), Vector3(0.42, 0.26, 0.5), Color(0.3, 0.7, 0.2)],      # body
		[Vector3(0, 0.22, -0.12), Vector3(0.34, 0.18, 0.36), Color(0.85, 0.9, 0.55)],  # belly
		[Vector3(-0.2, 0.5, -0.22), Vector3(0.13, 0.13, 0.13), Color(0.3, 0.7, 0.2)],  # eye bumps
		[Vector3(0.2, 0.5, -0.22), Vector3(0.13, 0.13, 0.13), Color(0.3, 0.7, 0.2)],
		[Vector3(-0.22, 0.53, -0.3), Vector3(0.07, 0.07, 0.07), Color(0.05, 0.05, 0.05)],  # pupils
		[Vector3(0.22, 0.53, -0.3), Vector3(0.07, 0.07, 0.07), Color(0.05, 0.05, 0.05)],
		[Vector3(-0.38, 0.1, 0.25), Vector3(0.16, 0.1, 0.28), Color(0.25, 0.6, 0.15)],  # hind legs
		[Vector3(0.38, 0.1, 0.25), Vector3(0.16, 0.1, 0.28), Color(0.25, 0.6, 0.15)],
	]
	var sm := SphereMesh.new()
	sm.radial_segments = 12
	sm.rings = 6
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for p in parts:
		var at: Vector3 = p[0]
		var sc: Vector3 = p[1] * 2.0
		for t in idx:
			st.set_color(p[2])
			st.set_normal((norms[t] / sc).normalized())
			st.add_vertex(at + verts[t] * sc)
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.35
	mesh.surface_set_material(0, m)
	return mesh


func _tick_frogs(dt: float) -> void:
	_frog_t += dt
	if enemies.frog_count == 0 and _frogs.visible_instance_count == 0:
		return
	var buf := PackedFloat32Array()
	buf.resize(_frogs.instance_count * 16)
	var n := 0
	for i in enemies.count:
		if n >= _frogs.instance_count:
			break
		if enemies.dead[i] or enemies.frog_t[i] <= 0.0:
			continue
		var p := enemies.pos[i]
		var v := enemies.heading(i)
		var yaw := atan2(-v.x, -v.z) if v.length_squared() > 0.01 else 0.0
		var hop := absf(sin(_frog_t * 7.0 + float(enemies.uid[i]))) * 0.45
		var s := 1.1 * enemies.sz[i]
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s * (1.0 - hop * 0.3), s))
		var o := n * 16
		buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = p.x
		buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = p.y + hop
		buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = p.z
		var fl := 1.0 + 3.0 * enemies.flash[i] / 0.08 if enemies.flash[i] > 0.0 else 1.0
		buf[o + 12] = fl; buf[o + 13] = fl; buf[o + 14] = fl; buf[o + 15] = 1.0
		n += 1
	_frogs.buffer = buf
	_frogs.visible_instance_count = n


# ------------------------------------------------------------------ Rewind

func _rewind() -> void:
	play("rewind")
	var then: Array = _history[0] if not _history.is_empty() else [player.hp, player.shield]
	var hp_was: float = then[0]
	var sh_was: float = then[1]
	if hp_was > player.hp:
		var gain := hp_was - player.hp
		player.hp = minf(hp_was, player.max_hp)
		k.healed.emit(gain)
	player.shield = maxf(player.shield, sh_was)
	var at := feet()
	for i in near(at, REWIND_RADIUS * pw(2)):
		var away := enemies.pos[i] - at
		enemies.knock(i, away, REWIND_FLING, 0.45)
		enemies.stun(i, REWIND_STUN + 0.45)
	# The clock spins backwards: a ring sweeping inward, motes rushing back to him
	var g := GroundDisc.create(1.0, k._light, true)
	g.set_ring(0.9)
	spawn(g, at)
	g.scale = Vector3(REWIND_RADIUS * pw(2), 1, REWIND_RADIUS * pw(2))
	var tw := g.create_tween()
	tw.set_parallel(true)
	tw.tween_property(g, "scale", Vector3(0.5, 1, 0.5), 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(g, "alpha", 0.0, 0.6)
	tw.chain().tween_callback(g.queue_free)
	after(0.45, func(): ring(feet(), REWIND_RADIUS * pw(2), k._main, 0.5))
	for m in 40:
		var a := randf() * TAU
		var r := randf_range(4.0, REWIND_RADIUS * pw(2))
		mote(at + Vector3(cos(a) * r, randf_range(0.3, 3.0), sin(a) * r), Vector3.ZERO, 1.2, k._light if m % 2 else k._main, 0.2, true)
	fx.burst(chest(), 5.0, k._light, 0.5)
	flash_light(chest() + Vector3(0, 2, 0), Color(0.6, 0.75, 1.0), 6.0, 30.0, 0.8)
	player.add_shake(0.5)
