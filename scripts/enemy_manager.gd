class_name EnemyManager
extends Node3D
## Data-oriented crowd: enemies are rows in packed arrays, not nodes.
## - Rendering: one MultiMesh, whole instance buffer uploaded once per tick.
## - Spatial queries: a player-centred uniform grid rebuilt every tick with a counting sort
##   (no per-cell allocations), used for separation, weapon hits and contact damage.
## - Removal: kills are flagged and swap-removed at the start of the next tick, so indices
##   stay stable for the rest of the frame.

const MAX := 1500
const CELL := 2.0
const GRID_N := 64                      # 64 * 2m = 128m window around the player
const HALF := CELL * GRID_N * 0.5
const RELOCATE_DIST := 58.0             # stragglers further than this teleport back near the player
const STRIDE := 16                      # 12 floats transform + 4 floats color
const ACCEL := 25.0
const SEPARATION_NEIGHBOURS := 8

var arena_half := 110.0
var rng: RandomNumberGenerator

# Type table (index = type id)
var type_names := PackedStringArray()
var t_hp := PackedFloat32Array()
var t_speed := PackedFloat32Array()
var t_radius := PackedFloat32Array()
var t_scale := PackedFloat32Array()
var t_height := PackedFloat32Array()
var t_damage := PackedFloat32Array()
var t_xp := PackedFloat32Array()
var t_color: Array[Color] = []

# Per-enemy rows
var count := 0
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var hp := PackedFloat32Array()
var typ := PackedInt32Array()
var flash := PackedFloat32Array()
var uid := PackedInt32Array()
var dead := PackedByteArray()
var sep_x := PackedFloat32Array()
var sep_z := PackedFloat32Array()
var _next_uid := 1
var _dead_count := 0
var _time := 0.0
var _frame := 0

# Grid
var cell_of := PackedInt32Array()
var cell_count := PackedInt32Array()
var cell_start := PackedInt32Array()
var cell_fill := PackedInt32Array()
var sorted := PackedInt32Array()
var gx0 := 0.0
var gz0 := 0.0

var mm: MultiMesh
var buf := PackedFloat32Array()

enum { GRUNT, RUNNER, TANK, BOSS }


func _ready() -> void:
	pos.resize(MAX)
	vel.resize(MAX)
	hp.resize(MAX)
	typ.resize(MAX)
	flash.resize(MAX)
	uid.resize(MAX)
	dead.resize(MAX)
	sep_x.resize(MAX)
	sep_z.resize(MAX)
	cell_of.resize(MAX)
	sorted.resize(MAX)
	cell_count.resize(GRID_N * GRID_N)
	cell_start.resize(GRID_N * GRID_N)
	cell_fill.resize(GRID_N * GRID_N)
	buf.resize(MAX * STRIDE)
	for i in MAX:   # constant entries: zero basis terms and alpha
		buf[i * STRIDE + 15] = 1.0

	_add_type("Grunt", 10.0, 4.2, 0.5, 1.0, 8.0, 1.0, Color(0.86, 0.32, 0.30))
	_add_type("Runner", 6.0, 6.8, 0.4, 0.8, 6.0, 1.0, Color(0.95, 0.76, 0.25))
	_add_type("Tank", 55.0, 3.0, 0.9, 1.8, 16.0, 5.0, Color(0.52, 0.32, 0.82))
	_add_type("Big Bonker", 2500.0, 3.6, 2.2, 4.5, 35.0, 120.0, Color(0.18, 0.18, 0.24))

	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _make_mesh()
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(mmi)


func _add_type(n: String, p_hp: float, speed: float, radius: float, scale: float, damage: float, xp: float, color: Color) -> void:
	type_names.append(n)
	t_hp.append(p_hp)
	t_speed.append(speed)
	t_radius.append(radius)
	t_scale.append(scale)
	t_height.append(1.6 * scale)
	t_damage.append(damage)
	t_xp.append(xp)
	t_color.append(color)


func _make_mesh() -> Mesh:
	var body := CapsuleMesh.new()
	body.radius = 0.45
	body.height = 1.6
	body.radial_segments = 10
	body.rings = 3
	var snout := BoxMesh.new()
	snout.size = Vector3(0.35, 0.25, 0.3)
	var st := SurfaceTool.new()
	st.append_from(body, 0, Transform3D.IDENTITY)
	st.append_from(snout, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0.45)))
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	mesh.surface_set_material(0, mat)
	return mesh


# ---------------------------------------------------------------- spawning / damage

func spawn(t: int, p: Vector3, hp_mult := 1.0) -> int:
	if count >= MAX:
		return -1
	var i := count
	count += 1
	pos[i] = Vector3(clampf(p.x, -arena_half, arena_half), 0.0, clampf(p.z, -arena_half, arena_half))
	vel[i] = Vector3.ZERO
	hp[i] = t_hp[t] * hp_mult
	typ[i] = t
	flash[i] = 0.0
	uid[i] = _next_uid
	_next_uid += 1
	dead[i] = 0
	sep_x[i] = 0.0
	sep_z[i] = 0.0
	return i


## Returns true if this hit killed the enemy. Kill events fire immediately;
## the row is removed at the start of the next tick.
func damage(i: int, amount: float, knockback := Vector3.ZERO) -> bool:
	if dead[i]:
		return false
	hp[i] -= amount
	flash[i] = 0.08
	if knockback != Vector3.ZERO:
		vel[i] += knockback / t_scale[typ[i]]
	if hp[i] <= 0.0:
		dead[i] = 1
		_dead_count += 1
		Events.enemy_killed.emit(pos[i], typ[i])
		return true
	return false


func center_of(i: int) -> Vector3:
	return pos[i] + Vector3(0.0, 0.8 * t_scale[typ[i]], 0.0)


func alive_count() -> int:
	return count - _dead_count


# ---------------------------------------------------------------- queries

## Indices of live enemies overlapping a sphere-ish volume (horizontal radius + vertical band).
func query_radius(c: Vector3, r: float, vertical := true) -> PackedInt32Array:
	var res := PackedInt32Array()
	var minx := maxi(floori((c.x - r - 2.5 - gx0) / CELL), 0)
	var maxx := mini(floori((c.x + r + 2.5 - gx0) / CELL), GRID_N - 1)
	var minz := maxi(floori((c.z - r - 2.5 - gz0) / CELL), 0)
	var maxz := mini(floori((c.z + r + 2.5 - gz0) / CELL), GRID_N - 1)
	if minx > maxx or minz > maxz:
		return res
	for cz in range(minz, maxz + 1):
		var row := cz * GRID_N
		for cx in range(minx, maxx + 1):
			var cell := row + cx
			var s := cell_start[cell]
			for k in range(s, s + cell_count[cell]):
				var i := sorted[k]
				if dead[i]:
					continue
				var p := pos[i]
				var t := typ[i]
				var rr := r + t_radius[t]
				var dx := p.x - c.x
				var dz := p.z - c.z
				if dx * dx + dz * dz > rr * rr:
					continue
				if vertical and (c.y < p.y - 0.5 or c.y > p.y + t_height[t] + 0.5):
					continue
				res.append(i)
	return res


## Up to k nearest live enemies within r (horizontal distance), nearest first.
func nearest_k(c: Vector3, r: float, k: int) -> PackedInt32Array:
	var best := PackedInt32Array()
	var best_d := PackedFloat32Array()
	if k <= 0:
		return best
	for i in query_radius(c, r, false):
		var p := pos[i]
		var d := (p.x - c.x) * (p.x - c.x) + (p.z - c.z) * (p.z - c.z)
		if best.size() == k and d >= best_d[k - 1]:
			continue
		var at := best.size()
		while at > 0 and best_d[at - 1] > d:
			at -= 1
		best.insert(at, i)
		best_d.insert(at, d)
		if best.size() > k:
			best.resize(k)
			best_d.resize(k)
	return best


# ---------------------------------------------------------------- simulation

func tick(dt: float, player_pos: Vector3) -> void:
	_time += dt
	_frame += 1
	_compact()
	_build_grid(player_pos)

	var n := count
	var parity := _frame & 1
	var corr := minf(1.0, 10.0 * dt)
	var max_dv := ACCEL * dt
	var lim := arena_half
	var reloc2 := RELOCATE_DIST * RELOCATE_DIST
	var wobble_t := _time * 11.0
	for i in n:
		var p := pos[i]
		var t := typ[i]
		var tx := player_pos.x - p.x
		var tz := player_pos.z - p.z
		var d2 := tx * tx + tz * tz

		if d2 > reloc2 and t != BOSS:
			var a := rng.randf() * TAU
			var r := rng.randf_range(28.0, 36.0)
			pos[i] = Vector3(player_pos.x + cos(a) * r, 0.0, player_pos.z + sin(a) * r)
			vel[i] = Vector3.ZERO
			continue

		# Separation is expensive, so each enemy recomputes it every other frame (cached between).
		if (i & 1) == parity:
			var sx := 0.0
			var sz := 0.0
			var c := cell_of[i]
			if c >= 0:
				var cx := c % GRID_N
				var cz := c / GRID_N
				var ri := t_radius[t]
				var checked := 0
				for oz in range(maxi(cz - 1, 0), mini(cz + 2, GRID_N)):
					if checked >= SEPARATION_NEIGHBOURS:
						break
					for ox in range(maxi(cx - 1, 0), mini(cx + 2, GRID_N)):
						if checked >= SEPARATION_NEIGHBOURS:
							break
						var cell := oz * GRID_N + ox
						var s := cell_start[cell]
						for k in range(s, s + cell_count[cell]):
							var j := sorted[k]
							if j == i:
								continue
							var q := pos[j]
							var dx := p.x - q.x
							var dz := p.z - q.z
							var dd := dx * dx + dz * dz
							var minr := ri + t_radius[typ[j]]
							if dd < minr * minr and dd > 0.000001:
								var dist := sqrt(dd)
								var push := (minr - dist) / dist
								sx += dx * push
								sz += dz * push
							checked += 1
							if checked >= SEPARATION_NEIGHBOURS:
								break
			sep_x[i] = sx
			sep_z[i] = sz

		# Steering: accelerate toward the player at the type's speed
		var v := vel[i]
		var dvx := -v.x
		var dvz := -v.z
		var fx := 0.0
		var fz := 1.0
		if d2 > 0.0001:
			var inv := 1.0 / sqrt(d2)
			fx = tx * inv
			fz = tz * inv
			var sp := t_speed[t]
			dvx += fx * sp
			dvz += fz * sp
		var dl := sqrt(dvx * dvx + dvz * dvz)
		if dl > max_dv:
			dvx *= max_dv / dl
			dvz *= max_dv / dl
		v.x += dvx
		v.z += dvz
		v.y = 0.0
		p.x = clampf(p.x + v.x * dt + sep_x[i] * corr, -lim, lim)
		p.z = clampf(p.z + v.z * dt + sep_z[i] * corr, -lim, lim)
		pos[i] = p
		vel[i] = v

		# Face movement direction (or the player when nearly stopped)
		var vl := v.x * v.x + v.z * v.z
		if vl > 0.04:
			var inv_v := 1.0 / sqrt(vl)
			fx = v.x * inv_v
			fz = v.z * inv_v

		var s := t_scale[t]
		var sy := s * (1.0 + 0.07 * sin(wobble_t + float(uid[i])))   # waddle
		var b := i * STRIDE
		buf[b] = fz * s
		buf[b + 2] = fx * s
		buf[b + 3] = p.x
		buf[b + 5] = sy
		buf[b + 7] = 0.8 * sy
		buf[b + 8] = -fx * s
		buf[b + 10] = fz * s
		buf[b + 11] = p.z
		var fl := flash[i]
		if fl > 0.0:
			flash[i] = fl - dt
			buf[b + 12] = 1.0
			buf[b + 13] = 1.0
			buf[b + 14] = 1.0
		else:
			var col: Color = t_color[t]
			buf[b + 12] = col.r
			buf[b + 13] = col.g
			buf[b + 14] = col.b

	mm.buffer = buf
	mm.visible_instance_count = n


func _build_grid(center: Vector3) -> void:
	gx0 = floorf(center.x / CELL) * CELL - HALF
	gz0 = floorf(center.z / CELL) * CELL - HALF
	cell_count.fill(0)
	for i in count:
		var p := pos[i]
		var cx := floori((p.x - gx0) / CELL)
		var cz := floori((p.z - gz0) / CELL)
		if cx < 0 or cz < 0 or cx >= GRID_N or cz >= GRID_N:
			cell_of[i] = -1
		else:
			var c := cz * GRID_N + cx
			cell_of[i] = c
			cell_count[c] += 1
	var acc := 0
	for c in GRID_N * GRID_N:
		cell_start[c] = acc
		cell_fill[c] = acc
		acc += cell_count[c]
	for i in count:
		var c := cell_of[i]
		if c >= 0:
			sorted[cell_fill[c]] = i
			cell_fill[c] += 1


func _compact() -> void:
	if _dead_count == 0:
		return
	var i := 0
	while i < count:
		if dead[i]:
			var last := count - 1
			pos[i] = pos[last]
			vel[i] = vel[last]
			hp[i] = hp[last]
			typ[i] = typ[last]
			flash[i] = flash[last]
			uid[i] = uid[last]
			dead[i] = dead[last]
			sep_x[i] = sep_x[last]
			sep_z[i] = sep_z[last]
			count -= 1
		else:
			i += 1
	_dead_count = 0
