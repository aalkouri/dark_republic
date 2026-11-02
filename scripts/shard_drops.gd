class_name ShardDrops
extends Node3D
## The elemental shards a fallen boss drops: one faceted 3D crystal per shard (the map's kinds,
## Wallet.roll_boss_shards), bursting out of the corpse and scattering onto the ground round it,
## where they hover, bob, spin and glow in their element's colours (ShardIcon.COLORS). Walk over
## one (PICKUP_DIST) and it's yours: within your pickup range they drift to you. BossAftermath
## banks each one (Wallet.add_shards) as it's picked up.

signal collected(kind: String, at: Vector3)

const PICKUP_DIST := 1.5
const HOVER := 0.75          # metres above the ground they float at
const FLY_TIME := Vector2(0.75, 1.05)
const SCATTER := Vector2(2.6, 5.0)   # how far from the corpse they land
const MAGNET_SPEED := 9.0

var drops: Array = []        # {node, spin, kind, from, to, t, time, peak, landed, pulled}
var _mats := {}
var _halo_mats := {}
var _mesh: ArrayMesh
var _chime: AudioStreamPlayer
var _burst: AudioStreamPlayer3D
var _t := 0.0
var origin := Vector3.INF    # where the last drop burst out (the corpse, or the nearest good ground)


func _ready() -> void:
	_mesh = crystal_mesh()
	_chime = AudioStreamPlayer.new()
	_chime.bus = Settings.SFX_BUS
	_chime.max_polyphony = 4
	_chime.volume_db = -3.0
	if ResourceLoader.exists("res://audio/portal/shard_chime.wav"):
		_chime.stream = load("res://audio/portal/shard_chime.wav")
	add_child(_chime)
	_burst = AudioStreamPlayer3D.new()
	_burst.bus = Settings.SFX_BUS
	_burst.unit_size = 20.0
	_burst.max_distance = 100.0
	if ResourceLoader.exists("res://audio/portal/shard_burst.wav"):
		_burst.stream = load("res://audio/portal/shard_burst.wav")
	add_child(_burst)


## Burst `won` ({kind: count}) out of the corpse at `at`, scattering them round it. `ok` says
## whether a landing spot is fine (walkable, dry); `toward` is where to fall back to (the player).
func drop(won: Dictionary, at: Vector3, rng: RandomNumberGenerator, ok: Callable, toward: Vector3) -> void:
	var kinds: Array = []
	for kind in Wallet.SHARDS:   # a stable order: kinds grouped
		for k in int(won.get(kind, 0)):
			kinds.append(kind)
	if kinds.is_empty():
		return
	# start from the nearest good ground between the corpse and the player
	var from := at
	var to_p := Vector3(toward.x - at.x, 0, toward.z - at.z)
	var steps := int(to_p.length())
	for s in steps + 1:
		var q := at + to_p.normalized() * float(s) if steps > 0 else at
		if ok.call(q):
			from = q
			break
		from = toward
	from.y = SwampWater.height_at(from.x, from.z)
	origin = from
	var a0 := rng.randf() * TAU
	for k in kinds.size():
		var to := from
		for tries in 12:   # an even spread round the corpse, jittered, on good ground
			var a := a0 + TAU * (float(k) + 0.5) / float(kinds.size()) + rng.randf_range(-0.35, 0.35) + tries * 0.9
			var r := rng.randf_range(SCATTER.x, SCATTER.y) * (1.0 - tries * 0.06)
			var q := from + Vector3(cos(a), 0, sin(a)) * r
			if ok.call(q):
				to = q
				break
		to.y = SwampWater.height_at(to.x, to.z)
		_spawn(kinds[k], from + Vector3(0, 2.2, 0), to, rng)
	if _burst.stream:
		_burst.global_position = from + Vector3(0, 1.5, 0)
		_burst.play()


func _spawn(kind: String, from: Vector3, to: Vector3, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	root.global_position = from
	var spin := Node3D.new()
	spin.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
	root.add_child(spin)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.scale = Vector3.ONE * 1.45
	mi.material_override = _mat(kind)
	spin.add_child(mi)
	var cols: Array = ShardIcon.COLORS.get(kind, ShardIcon.COLORS["fire"])
	var halo := MeshInstance3D.new()   # a soft glow round the crystal
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	halo.mesh = q
	halo.material_override = _halo(kind)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	var light := OmniLight3D.new()
	light.light_color = cols[0]
	light.light_energy = 1.6
	light.omni_range = 4.0
	root.add_child(light)
	var ring := GroundDisc.create(0.8, Color(cols[0], 0.3), true)
	ring.top_level = true
	ring.visible = false
	add_child(ring)
	drops.append({"node": root, "spin": spin, "ring": ring, "kind": kind, "from": from, "to": to, "t": 0.0,
		"time": rng.randf_range(FLY_TIME.x, FLY_TIME.y), "peak": rng.randf_range(2.5, 4.0), "landed": false, "pulled": false,
		"age": rng.randf() * 3.0})


## Move them; pick up any the player (feet at `feet`) walks over. Returns how many were picked up.
func tick(dt: float, feet: Vector3, pickup_range: float) -> int:
	_t += dt
	var got := 0
	var target := feet + Vector3(0, 0.9, 0)
	for k in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[k]
		var root: Node3D = d["node"]
		var spin: Node3D = d["spin"]
		d["age"] = float(d["age"]) + dt
		spin.rotation.y += dt * 1.8
		if not d["landed"]:
			d["t"] = float(d["t"]) + dt
			var f := clampf(float(d["t"]) / float(d["time"]), 0.0, 1.0)
			var from: Vector3 = d["from"]
			var to: Vector3 = d["to"] + Vector3(0, HOVER, 0)
			var p := from.lerp(to, f)
			p.y += float(d["peak"]) * 4.0 * f * (1.0 - f)
			root.global_position = p
			spin.rotation.x += dt * 9.0 * (1.0 - f)   # tumbling through the air
			if f >= 1.0:
				d["landed"] = true
				spin.rotation.x = 0.0
				var ring: GroundDisc = d["ring"]
				ring.global_position = d["to"]
				ring.visible = true
			continue
		var to2: Vector3 = d["to"]
		var bob := sin(float(d["age"]) * 2.6) * 0.12
		var dist := root.global_position.distance_to(target)
		if dist < pickup_range:
			d["pulled"] = true
		if d["pulled"]:   # drift to you, gently, then faster
			root.global_position += (target - root.global_position).normalized() * minf(dist, (MAGNET_SPEED + float(d["age"])) * dt)
			(d["ring"] as Node3D).visible = false
		else:
			root.global_position = to2 + Vector3(0, HOVER + bob, 0)
		var flat := Vector2(root.global_position.x - feet.x, root.global_position.z - feet.z).length()
		if flat < PICKUP_DIST and absf(root.global_position.y - target.y) < 2.2:
			_take(k)
			got += 1
	return got


## Pick them all up at once (stepping into the portal). Returns {kind: count}.
func collect_all() -> Dictionary:
	var out := {}
	for k in range(drops.size() - 1, -1, -1):
		var kind: String = drops[k]["kind"]
		out[kind] = int(out.get(kind, 0)) + 1
		_take(k, false, false)
	return out


func count() -> int:
	return drops.size()


## {kind: count} still on the ground (or in the air).
func remaining() -> Dictionary:
	var out := {}
	for d in drops:
		out[d["kind"]] = int(out.get(d["kind"], 0)) + 1
	return out


## Landed crystals' positions (tests, the bot).
func positions() -> Array:
	var out := []
	for d in drops:
		out.append((d["node"] as Node3D).global_position)
	return out


func _take(k: int, chime := true, emit := true) -> void:
	var d: Dictionary = drops[k]
	var at: Vector3 = (d["node"] as Node3D).global_position
	(d["node"] as Node).queue_free()
	(d["ring"] as Node).queue_free()
	drops.remove_at(k)
	if chime and _chime.stream:
		_chime.pitch_scale = {"fire": 0.94, "ice": 1.12, "lightning": 1.06, "dark": 0.84, "light": 1.26}.get(d["kind"], 1.0)
		_chime.play()
	if emit:
		collected.emit(d["kind"], at)


func _mat(kind: String) -> StandardMaterial3D:
	if not _mats.has(kind):
		var cols: Array = ShardIcon.COLORS.get(kind, ShardIcon.COLORS["fire"])
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[0]
		m.emission_enabled = true
		m.emission = cols[0]
		m.emission_energy_multiplier = 1.1
		m.metallic = 0.3
		m.roughness = 0.12
		m.rim_enabled = true
		m.rim = 0.8
		m.rim_tint = 0.2
		m.vertex_color_use_as_albedo = true
		_mats[kind] = m
	return _mats[kind]


func _halo(kind: String) -> ShaderMaterial:
	if not _halo_mats.has(kind):
		var cols: Array = ShardIcon.COLORS.get(kind, ShardIcon.COLORS["fire"])
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 col : source_color;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float g = pow(clamp(1.0 - r, 0.0, 1.0), 2.2) * (0.85 + 0.15 * sin(TIME * 4.0));
	ALBEDO = col * g * 1.4;
	ALPHA = g;
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("col", cols[0])
		_halo_mats[kind] = m
	return _halo_mats[kind]


## A faceted crystal: a hexagonal prism with a tall pointed top and a short pointed bottom,
## flat-shaded, the facets alternating light and dark (vertex colours), about 0.75 m tall.
static func crystal_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var sides := 6
	var r := 0.17
	var y0 := -0.12
	var y1 := 0.14
	var top := Vector3(0.02, 0.48, 0.0)
	var bot := Vector3(0.0, -0.3, 0.01)
	var ring0 := []
	var ring1 := []
	for k in sides:
		var a := TAU * k / sides
		var rr := r * (1.0 if k % 2 == 0 else 0.86)   # a little irregular
		ring0.append(Vector3(cos(a) * rr, y0, sin(a) * rr))
		ring1.append(Vector3(cos(a) * rr * 0.96, y1, sin(a) * rr * 0.96))
	var tris := []
	for k in sides:
		var j := (k + 1) % sides
		var shade := 1.0 if k % 2 == 0 else 0.72
		tris.append([ring0[k], ring1[k], ring1[j], shade])
		tris.append([ring0[k], ring1[j], ring0[j], shade])
		tris.append([ring1[k], top, ring1[j], shade * 1.12])
		tris.append([ring0[j], bot, ring0[k], shade * 0.8])
	for t in tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var d: Vector3 = t[2]
		var nn := (d - a).cross(b - a).normalized()
		if nn.dot((a + b + d) / 3.0) < 0.0:   # make every facet face outward (and wind clockwise)
			nn = -nn
			var tmp := b
			b = d
			d = tmp
		for p in [a, b, d]:
			v.append(p)
			n.append(nn)
			var s: float = t[3]
			c.append(Color(s, s, s))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
