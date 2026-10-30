class_name BushField
extends Node3D
## Magical Forest bushes you can walk through. Drawn as one MultiMesh (a few bush shapes, each a
## clump of dark leaves with glowing berries); no collision. When the player moves through one
## it shakes (per-instance shake in the shader), rustles (one of 4 synthesised sounds, from the
## bush, rate-limited) and sometimes throws out a little burst of leaves.

const RADIUS := 1.3              # how close (metres, horizontally) counts as "in" a bush
const MIN_SPEED := 1.2           # standing still in a bush doesn't rustle it
const RUSTLE_GAP := 0.35         # a bush rustles again at most this often
const LEAF_CHANCE_ENTER := 0.45  # chance of leaves flying when you push into a bush...
const LEAF_RATE := 1.2           # ...and per second while you keep moving through it
const SHAKE_DECAY := 2.2
const CELL := 4.0
const SOUNDS := ["res://audio/forest/rustle_1.wav", "res://audio/forest/rustle_2.wav",
	"res://audio/forest/rustle_3.wav", "res://audio/forest/rustle_4.wav"]

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
varying float glow;
void vertex() {
	// INSTANCE_CUSTOM.r = shake (0..1), .g = phase. COLOR.a = 1 on berries.
	float sh = INSTANCE_CUSTOM.r;
	float h = clamp(VERTEX.y / 1.6, 0.0, 1.0);
	float t = TIME * 26.0 + INSTANCE_CUSTOM.g * 6.28;
	VERTEX.x += sin(t) * 0.12 * sh * h;
	VERTEX.z += cos(t * 1.3) * 0.12 * sh * h;
	// a slow idle breeze
	VERTEX.x += sin(TIME * 1.3 + INSTANCE_CUSTOM.g * 6.28) * 0.03 * h;
	glow = COLOR.a;
}
void fragment() {
	if (any(isnan(NORMAL)) || dot(NORMAL, NORMAL) < 1e-6) { NORMAL = vec3(0.0, 0.0, 1.0); }
	vec3 col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	ALBEDO = col;
	ROUGHNESS = 0.9;
	EMISSION = col * (glow * 2.6 + 0.6);   // leaves faintly luminous, berries bright
}
"""

const LEAF_A := Color(0.16, 0.5, 0.45, 0.0)
const LEAF_B := Color(0.3, 0.28, 0.65, 0.0)
const LEAF_C := Color(0.48, 0.22, 0.55, 0.0)
const BERRIES := [Color(0.25, 0.95, 1.0, 1.0), Color(1.0, 0.3, 0.85, 1.0), Color(1.0, 0.8, 0.3, 1.0), Color(0.5, 1.0, 0.35, 1.0)]

var pos := PackedVector3Array()
var size := PackedFloat32Array()
var shake := PackedFloat32Array()
var _last := PackedFloat32Array()     # time of the last rustle
var _inside := PackedByteArray()
var _grid := {}                       # Vector2i cell -> PackedInt32Array of bush indices
var _mms: Array[MultiMesh] = []
var _kind := PackedInt32Array()       # which shape (MultiMesh) each bush uses
var _slot := PackedInt32Array()       # its instance in that MultiMesh
var _players: Array[AudioStreamPlayer3D] = []
var _streams: Array[AudioStream] = []
var _leaves: Array[CPUParticles3D] = []
var _next_leaf := 0
var _time := 0.0
var rustles := 0                      # counters for tests
var leaf_bursts := 0
var player: Node3D                    # set at runtime (the Player); found automatically if unset


## Scatter `n` bushes: grassy patches first, away from pools, trees, shrine pads and the start.
func scatter(rng: RandomNumberGenerator, half: float, water: SwampWater, placed: Array[Vector3], patches: Image, n: int) -> void:
	var extent := half + 10.0
	var tries := 0
	while pos.size() < n and tries < n * 40:
		tries += 1
		var p := Vector3(rng.randf_range(-half + 8.0, half - 8.0), 0, rng.randf_range(-half + 8.0, half - 8.0))
		if Vector2(p.x, p.z).length() < 10.0 or water.near_pool(p.x, p.z, 1.5):
			continue
		var m := WorldBuilder._sample(patches, extent, p.x, p.z)
		if m.g < 0.48 and rng.randf() < 0.7:   # prefer the grassy patches
			continue
		var ok := true
		for site in water.shrine_sites:
			if Vector2(p.x - site.x, p.z - site.z).length() < Shrine.ZONE_RADIUS + 2.0:
				ok = false
				break
		if ok:
			for q in placed:
				if Vector2(p.x - q.x, p.z - q.z).length() < 2.6:
					ok = false
					break
		if not ok:
			continue
		p.y = WorldBuilder._low_point(water, p, 0.6) - 0.05   # on a slope, the downhill edge touches the ground
		pos.append(p)
		size.append(rng.randf_range(0.8, 1.35))
	_build(rng)


func _build(rng: RandomNumberGenerator) -> void:
	var n := pos.size()
	shake.resize(n)
	_last.resize(n)
	_last.fill(-10.0)
	_inside.resize(n)
	_kind.resize(n)
	_slot.resize(n)
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var shapes := 4
	var counts := PackedInt32Array()
	counts.resize(shapes)
	for i in n:
		_kind[i] = i % shapes
		_slot[i] = counts[_kind[i]]
		counts[_kind[i]] += 1
	for s in shapes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _bush_mesh(rng, s, mat)
		mm.instance_count = counts[s]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mms.append(mm)
	for i in n:
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size[i])
		_mms[_kind[i]].set_instance_transform(_slot[i], Transform3D(b, pos[i]))
		_mms[_kind[i]].set_instance_custom_data(_slot[i], Color(0.0, rng.randf(), 0, 0))
		var c := Vector2i(floori(pos[i].x / CELL), floori(pos[i].z / CELL))
		var cell: PackedInt32Array = _grid.get(c, PackedInt32Array())   # packed arrays are copied:
		cell.append(i)                                                 # write it back
		_grid[c] = cell


## A clump of leafy blobs (a few colours) with glowing berries tucked in.
static func _bush_mesh(rng: RandomNumberGenerator, shape: int, mat: Material) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var leaf: Color = [LEAF_A, LEAF_B, LEAF_C, LEAF_A][shape]
	var berry: Color = BERRIES[shape]
	for k in rng.randi_range(5, 8):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.75)
		var r := rng.randf_range(0.6, 0.95)
		mb.add(MeshBuilder.sphere(r, 8, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.75, 1.0)), Vector3(cos(a) * d, r * 0.65, sin(a) * d)), leaf.lerp(Color(0.02, 0.04, 0.05, 0.0), rng.randf() * 0.4))
	for k in rng.randi_range(10, 16):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.5, 1.05)
		mb.add(MeshBuilder.sphere(0.09, 5, 3), Transform3D(Basis(), Vector3(cos(a) * d, rng.randf_range(0.45, 1.4), sin(a) * d)), berry)
	return mb.commit(mat)


func _ready() -> void:
	for p in SOUNDS:
		if ResourceLoader.exists(p):
			_streams.append(load(p))
	for k in 4:
		var a := AudioStreamPlayer3D.new()
		a.bus = Settings.SFX_BUS
		a.unit_size = 6.0
		a.max_distance = 30.0
		a.volume_db = -4.0
		add_child(a)
		_players.append(a)
	for k in 6:
		var l := _leaf_emitter()
		add_child(l)
		_leaves.append(l)


func _leaf_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 10
	p.lifetime = 1.6
	p.explosiveness = 0.85
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -4.5, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(0.15, 0.5, 0.45))
	grad.set_color(1, Color(0.1, 0.25, 0.3, 0.0))
	grad.add_point(0.75, Color(0.2, 0.4, 0.55, 0.9))
	p.color_ramp = grad
	p.hue_variation_min = -0.08
	p.hue_variation_max = 0.12
	var quad := QuadMesh.new()
	quad.size = Vector2(0.13, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = m
	p.mesh = quad
	return p


func _find_player() -> Node3D:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
	return player


## Bushes within RADIUS of a point (horizontal).
func bushes_at(p: Vector3) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var list = _grid.get(c + Vector2i(dx, dz))
			if list == null:
				continue
			for i in list:
				var r := RADIUS * size[i]
				if Vector2(p.x - pos[i].x, p.z - pos[i].z).length_squared() < r * r:
					out.append(i)
	return out


func _physics_process(dt: float) -> void:
	_time += dt
	var pl := _find_player()
	if pl != null:
		var v: Vector3 = pl.get("velocity") if pl.get("velocity") != null else Vector3.ZERO
		var moving := Vector2(v.x, v.z).length() > MIN_SPEED
		var now_in := bushes_at(pl.global_position)
		for i in now_in:
			if not moving:
				continue
			var entering := _inside[i] == 0
			shake[i] = 1.0
			if _time - _last[i] >= RUSTLE_GAP:
				_last[i] = _time
				_rustle(pos[i])
			if (entering and randf() < LEAF_CHANCE_ENTER) or randf() < LEAF_RATE * dt:
				_leaf_burst(pos[i] + Vector3(0, 0.8 * size[i], 0))
		for i in _inside.size():
			if _inside[i] == 1 and not now_in.has(i):
				_inside[i] = 0
		for i in now_in:
			_inside[i] = 1
	_decay(dt)


## Ease shakes back to rest; only touched bushes are rewritten.
func _decay(dt: float) -> void:
	for i in shake.size():
		var s := shake[i]
		if s <= 0.0:
			continue
		s = maxf(0.0, s - dt * SHAKE_DECAY)
		shake[i] = s
		var mm := _mms[_kind[i]]
		var c := mm.get_instance_custom_data(_slot[i])
		c.r = s
		mm.set_instance_custom_data(_slot[i], c)


func _rustle(at: Vector3) -> void:
	rustles += 1
	if _streams.is_empty():
		return
	var p: AudioStreamPlayer3D = _players[rustles % _players.size()]
	p.stream = _streams[randi() % _streams.size()]
	p.pitch_scale = randf_range(0.9, 1.15)
	p.global_position = at + Vector3(0, 0.6, 0)
	p.play()


func _leaf_burst(at: Vector3) -> void:
	leaf_bursts += 1
	var l := _leaves[_next_leaf]
	_next_leaf = (_next_leaf + 1) % _leaves.size()
	l.global_position = at
	l.restart()
