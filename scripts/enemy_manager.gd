class_name EnemyManager
extends Node3D
## Data-oriented crowd: enemies are rows in packed arrays, not nodes.
## - Rendering: one MultiMesh, whole instance buffer uploaded once per tick.
## - Spatial queries: a player-centred uniform grid rebuilt every tick with a counting sort
##   (no per-cell allocations), used for separation, weapon hits and contact damage.
## - Removal: kills are flagged and swap-removed at the start of the next tick, so indices
##   stay stable for the rest of the frame.
## - Status effects live in the same rows: burn (DoT; dying while burning explodes) and
##   knockback (a fixed displacement over a short time that overrides steering).

signal exploded(pos: Vector3, radius: float)
signal epic_killed(pos: Vector3)

const MAX := 1500
const CELL := 2.0
const GRID_N := 64                      # 64 * 2m = 128m window around the player
const HALF := CELL * GRID_N * 0.5
const RELOCATE_DIST := 58.0             # stragglers further than this teleport back near the player
const STRIDE := 20                      # 12 floats transform + 4 color + 4 custom (tint, fx)
const ACCEL := 25.0
const SEPARATION_NEIGHBOURS := 8
const BURN_COLOR := Color(1.0, 0.42, 0.08)
const MAX_EXPLOSIONS_PER_TICK := 60
const BOSS_KNOCKBACK_SCALE := 0.25
const EPIC_SIZE := 1.5
const EPIC_HP := 4.0
const EPIC_TINT := Color(0.72, 0.25, 1.0)

# Burn tuning (set by the ultimate; % of max HP)
var burn_dps_frac := 0.05
var burn_explode_frac := 0.5
var burn_explode_radius := 1.83     # 2 yards

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
var hp_max := PackedFloat32Array()
var typ := PackedInt32Array()
var flash := PackedFloat32Array()
var uid := PackedInt32Array()
var dead := PackedByteArray()
var epic := PackedByteArray()
var sz := PackedFloat32Array()          # per-enemy size multiplier (epic = 1.5)
var sep_x := PackedFloat32Array()
var sep_z := PackedFloat32Array()
var burn_t := PackedFloat32Array()      # seconds of burn left
var kb_vel := PackedVector3Array()      # knockback velocity while kb_t > 0
var kb_t := PackedFloat32Array()
var _explosions := PackedVector3Array() # queued burn explosions: x, z, damage packed in a Vector3
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
	hp_max.resize(MAX)
	burn_t.resize(MAX)
	kb_vel.resize(MAX)
	kb_t.resize(MAX)
	typ.resize(MAX)
	flash.resize(MAX)
	uid.resize(MAX)
	dead.resize(MAX)
	epic.resize(MAX)
	sz.resize(MAX)
	sep_x.resize(MAX)
	sep_z.resize(MAX)
	cell_of.resize(MAX)
	sorted.resize(MAX)
	cell_count.resize(GRID_N * GRID_N)
	cell_start.resize(GRID_N * GRID_N)
	cell_fill.resize(GRID_N * GRID_N)
	buf.resize(MAX * STRIDE)
	for i in MAX:   # instance color stays white; per-instance look lives in custom data
		for k in 4:
			buf[i * STRIDE + 12 + k] = 1.0

	# Goblins. The color is the clothing; scale 1 is about half the wizard's height.
	_add_type("Goblin", 10.0, 4.2, 0.45, 1.0, 8.0, 1.0, Color(0.5, 0.32, 0.17))
	_add_type("Goblin Scamp", 6.0, 6.8, 0.36, 0.8, 6.0, 1.0, Color(0.9, 0.68, 0.18))
	_add_type("Goblin Brute", 55.0, 3.0, 0.85, 1.8, 16.0, 5.0, Color(0.38, 0.4, 0.46))
	_add_type("Big Bonker", 2500.0, 3.6, 2.0, 4.5, 35.0, 120.0, Color(0.55, 0.08, 0.1))

	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = GoblinMesh.build()
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
	t_height.append(GoblinMesh.HEIGHT * scale)
	t_damage.append(damage)
	t_xp.append(xp)
	t_color.append(color)


# ---------------------------------------------------------------- spawning / damage

func spawn(t: int, p: Vector3, hp_mult := 1.0, is_epic := false) -> int:
	if count >= MAX:
		return -1
	var i := count
	count += 1
	pos[i] = Vector3(clampf(p.x, -arena_half, arena_half), 0.0, clampf(p.z, -arena_half, arena_half))
	vel[i] = Vector3.ZERO
	hp[i] = t_hp[t] * hp_mult * (EPIC_HP if is_epic else 1.0)
	epic[i] = 1 if is_epic else 0
	sz[i] = EPIC_SIZE if is_epic else 1.0
	hp_max[i] = hp[i]
	burn_t[i] = 0.0
	kb_t[i] = 0.0
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
		vel[i] += knockback / (t_scale[typ[i]] * sz[i])
	if hp[i] <= 0.0:
		_kill(i)
		return true
	return false


func _kill(i: int) -> void:
	dead[i] = 1
	_dead_count += 1
	if epic[i]:
		epic_killed.emit(pos[i])
	if burn_t[i] > 0.0:
		_explosions.append(Vector3(pos[i].x, pos[i].z, hp_max[i] * burn_explode_frac))
	Events.enemy_killed.emit(pos[i], typ[i])


## Push an enemy a fixed distance away over `duration` seconds (overrides steering).
func knock(i: int, dir: Vector3, distance: float, duration := 0.25) -> void:
	if dead[i]:
		return
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5)
	if typ[i] == BOSS:
		distance *= BOSS_KNOCKBACK_SCALE
	kb_vel[i] = dir.normalized() * (distance / duration)
	kb_t[i] = duration
	vel[i] = Vector3.ZERO


## Direction the enemy is currently heading (velocity, or knockback while being knocked).
func heading(i: int) -> Vector3:
	var v := kb_vel[i] if kb_t[i] > 0.0 else vel[i]
	v.y = 0.0
	return v


## Set every live enemy on fire.
func ignite_all(duration: float) -> int:
	var n := 0
	for i in count:
		if not dead[i]:
			burn_t[i] = duration
			n += 1
	return n


func center_of(i: int) -> Vector3:
	return pos[i] + Vector3(0.0, 0.5 * t_scale[typ[i]] * sz[i], 0.0)


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
				var rr := r + t_radius[t] * sz[i]
				var dx := p.x - c.x
				var dz := p.z - c.z
				if dx * dx + dz * dz > rr * rr:
					continue
				if vertical and (c.y < p.y - 0.5 or c.y > p.y + t_height[t] * sz[i] + 0.5):
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
	_resolve_explosions()

	var n := count
	var parity := _frame & 1
	var corr := minf(1.0, 10.0 * dt)
	var max_dv := ACCEL * dt
	var lim := arena_half
	var reloc2 := RELOCATE_DIST * RELOCATE_DIST
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

		var sc := t_scale[t] * sz[i]
		var b := i * STRIDE

		# Burn DoT (% of max HP per second)
		var burning := burn_t[i] > 0.0
		if burning and not dead[i]:
			burn_t[i] -= dt
			hp[i] -= hp_max[i] * burn_dps_frac * dt
			if hp[i] <= 0.0:
				_kill(i)

		# Knockback: fixed displacement, no steering or separation
		if kb_t[i] > 0.0:
			kb_t[i] -= dt
			var kv := kb_vel[i]
			p.x = clampf(p.x + kv.x * dt, -lim, lim)
			p.z = clampf(p.z + kv.z * dt, -lim, lim)
			pos[i] = p
			_write_xform(b, p, -kv.x, -kv.z, sc, sc)
			if flash[i] > 0.0:
				flash[i] -= dt
			_write_color(i, b, t, burning)
			continue

		# Separation is expensive, so each enemy recomputes it every other frame (cached between).
		if (i & 1) == parity:
			var ax := 0.0
			var az := 0.0
			var c := cell_of[i]
			if c >= 0:
				var cx := c % GRID_N
				var cz := c / GRID_N
				var ri := t_radius[t] * sz[i]
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
							var minr := ri + t_radius[typ[j]] * sz[j]
							if dd < minr * minr and dd > 0.000001:
								var dist := sqrt(dd)
								var push := (minr - dist) / dist
								ax += dx * push
								az += dz * push
							checked += 1
							if checked >= SEPARATION_NEIGHBOURS:
								break
			sep_x[i] = ax
			sep_z[i] = az

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

		# Short-legged waddle: side-to-side roll and a little hop, faster when running
		var spd := sqrt(vl)
		var phase := _time * (6.0 + spd * 2.2) + float(uid[i]) * 1.37
		_write_xform(b, p, fx, fz, sc, sc, 0.16 * sin(phase) * minf(spd * 0.4, 1.0), absf(sin(phase)) * 0.09 * sc * minf(spd * 0.3, 1.0))
		if flash[i] > 0.0:
			flash[i] -= dt
		_write_color(i, b, t, burning)

	mm.buffer = buf
	mm.visible_instance_count = n


func _write_xform(b: int, p: Vector3, fx: float, fz: float, s: float, sy: float, roll := 0.0, bob := 0.0) -> void:
	var l := fx * fx + fz * fz
	if l > 0.000001 and absf(l - 1.0) > 0.001:
		l = 1.0 / sqrt(l)
		fx *= l
		fz *= l
	elif l <= 0.000001:
		fx = 0.0
		fz = 1.0
	# Columns: X = right rolled, Y = up rolled, Z = forward. Rows are written out.
	var c := cos(roll)
	var sn := sin(roll)
	buf[b] = fz * c * s
	buf[b + 1] = -fz * sn * sy
	buf[b + 2] = fx * s
	buf[b + 3] = p.x
	buf[b + 4] = sn * s
	buf[b + 5] = c * sy
	buf[b + 6] = 0.0
	buf[b + 7] = p.y + bob
	buf[b + 8] = -fx * c * s
	buf[b + 9] = fx * sn * sy
	buf[b + 10] = fz * s
	buf[b + 11] = p.z


## Per-instance look goes into custom data: rgb = clothing tint, a = burn + 2*flash + 4*epic.
func _write_color(i: int, b: int, t: int, burning: bool) -> void:
	var col: Color = t_color[t]
	var fx := 0.0
	if burning:
		fx += 0.55 + 0.45 * sin(_time * 22.0 + float(uid[i]) * 1.7)
	if flash[i] > 0.0:
		fx += 2.0
	if epic[i]:
		fx += 4.0
		col = col.lerp(EPIC_TINT, 0.7)
	buf[b + 16] = col.r
	buf[b + 17] = col.g
	buf[b + 18] = col.b
	buf[b + 19] = fx


## Burn explosions are queued on death and resolved here (capped per tick), so chain
## reactions spread over frames instead of recursing.
func _resolve_explosions() -> void:
	if _explosions.is_empty():
		return
	var n := mini(_explosions.size(), MAX_EXPLOSIONS_PER_TICK)
	var now := _explosions.slice(0, n)
	_explosions = _explosions.slice(n)
	for e in now:
		var c := Vector3(e.x, 0.8, e.y)
		for j in query_radius(c, burn_explode_radius, false):
			damage(j, e.z)
		exploded.emit(Vector3(e.x, 0.6, e.y), burn_explode_radius)


func burning_count() -> int:
	var n := 0
	for i in count:
		if burn_t[i] > 0.0 and not dead[i]:
			n += 1
	return n


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
			hp_max[i] = hp_max[last]
			burn_t[i] = burn_t[last]
			kb_vel[i] = kb_vel[last]
			kb_t[i] = kb_t[last]
			typ[i] = typ[last]
			flash[i] = flash[last]
			uid[i] = uid[last]
			dead[i] = dead[last]
			epic[i] = epic[last]
			sz[i] = sz[last]
			sep_x[i] = sep_x[last]
			sep_z[i] = sep_z[last]
			count -= 1
		else:
			i += 1
	_dead_count = 0
