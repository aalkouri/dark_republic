class_name CastleNav
extends RefCounted
## Walkable-floor grid for indoor maps (the castle), 2 m cells over the arena.
##   - blocked cells: walls, pillars, the dining table, solid furniture
##   - a flow field around the player, rebuilt a few times a second: a breadth-first search
##     outward from the player's cell over a WINDOW-cell square, storing for every reachable
##     cell the direction to step toward the player. Goblins follow it through doorways
##     instead of piling up against walls. (Goblins further than the window are relocated
##     near the player by EnemyManager anyway.)
##   - line_clear() for skeletons deciding whether they can throw a bone at you
## Outdoor maps have no CastleNav (current == null) and keep the straight-line steering.

const CELL := 2.0
const WINDOW := 64                 # flow field covers 128 m around the player
const REFRESH := 0.3               # seconds between flow-field rebuilds

static var current: CastleNav

var n := 0                         # cells per side
var origin := 0.0                  # world coordinate of cell 0's corner
var blocked := PackedByteArray()
# Flow field (window around the player)
var win_x0 := 0                    # window corner, in cells
var win_z0 := 0
var dist := PackedInt32Array()     # steps to the player's cell, -1 = unreachable
var dir_x := PackedFloat32Array()  # unit step direction toward the player
var dir_z := PackedFloat32Array()
var _queue := PackedInt32Array()
var _t := 0.0
var _player_cell := Vector2i(-1, -1)


func _init(half: float) -> void:
	n = int(ceil(half * 2.0 / CELL))
	origin = -half
	blocked.resize(n * n)
	dist.resize(WINDOW * WINDOW)
	dist.fill(-1)
	dir_x.resize(WINDOW * WINDOW)
	dir_z.resize(WINDOW * WINDOW)
	_queue.resize(WINDOW * WINDOW)


func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int((x - origin) / CELL), 0, n - 1), clampi(int((z - origin) / CELL), 0, n - 1))


func cell_center(c: Vector2i) -> Vector3:
	return Vector3(origin + (c.x + 0.5) * CELL, 0.0, origin + (c.y + 0.5) * CELL)


func is_blocked(x: float, z: float) -> bool:
	var cx := int(floorf((x - origin) / CELL))
	var cz := int(floorf((z - origin) / CELL))
	if cx < 0 or cz < 0 or cx >= n or cz >= n:
		return true
	return blocked[cz * n + cx] != 0


## Mark an axis-aligned rectangle (world metres) as solid. `pad` grows it (goblin radius).
func block_rect(x0: float, z0: float, x1: float, z1: float, pad := 0.0) -> void:
	var a := cell_of(minf(x0, x1) - pad, minf(z0, z1) - pad)
	var b := cell_of(maxf(x0, x1) + pad - 0.001, maxf(z0, z1) + pad - 0.001)
	for cz in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			blocked[cz * n + cx] = 1


func block_circle(x: float, z: float, r: float) -> void:
	block_rect(x - r, z - r, x + r, z + r)


func clear_rect(x0: float, z0: float, x1: float, z1: float) -> void:
	var a := cell_of(minf(x0, x1), minf(z0, z1))
	var b := cell_of(maxf(x0, x1) - 0.001, maxf(z0, z1) - 0.001)
	for cz in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			blocked[cz * n + cx] = 0


func walkable_count() -> int:
	return blocked.count(0)


## Rebuild the flow field if it's stale or the player moved to another cell.
func update(dt: float, player_pos: Vector3) -> void:
	_t -= dt
	var pc := cell_of(player_pos.x, player_pos.z)
	if _t > 0.0 and absi(pc.x - _player_cell.x) + absi(pc.y - _player_cell.y) < 6:
		return   # rebuilt on a timer, or at once if the player moved far
	_t = REFRESH
	_player_cell = pc
	_rebuild(pc)


func _rebuild(pc: Vector2i) -> void:
	win_x0 = pc.x - WINDOW / 2
	win_z0 = pc.y - WINDOW / 2
	dist.fill(-1)
	var head := 0
	var tail := 0
	# Seed from the player's cell, or (standing on the table, say) the nearest open cells on
	# every side of it (a couple of rings past the first one found)
	var first := -1
	for r in 10:
		if first >= 0 and r > first + 2:
			break
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var gx := pc.x + dx
				var gz := pc.y + dz
				if gx < 0 or gz < 0 or gx >= n or gz >= n or blocked[gz * n + gx] != 0:
					continue
				var w0 := (gz - win_z0) * WINDOW + (gx - win_x0)
				dist[w0] = r
				_queue[tail] = w0
				tail += 1
		if tail > 0 and first < 0:
			first = r
	while head < tail:
		var w := _queue[head]
		head += 1
		var wx := w % WINDOW
		var wz := w / WINDOW
		var d := dist[w] + 1
		for k in 4:
			var nx := wx + (1 if k == 0 else (-1 if k == 1 else 0))
			var nz := wz + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or nz < 0 or nx >= WINDOW or nz >= WINDOW:
				continue
			var nw := nz * WINDOW + nx
			if dist[nw] >= 0:
				continue
			var gx := win_x0 + nx
			var gz := win_z0 + nz
			if gx < 0 or gz < 0 or gx >= n or gz >= n or blocked[gz * n + gx] != 0:
				continue
			dist[nw] = d
			_queue[tail] = nw
			tail += 1
	# Directions: toward the lowest neighbour (8-way, no cutting wall corners)
	for i in tail:
		var w := _queue[i]
		var wx := w % WINDOW
		var wz := w / WINDOW
		var best := dist[w]
		var bx := 0
		var bz := 0
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var nx := wx + dx
				var nz := wz + dz
				if nx < 0 or nz < 0 or nx >= WINDOW or nz >= WINDOW:
					continue
				var nd := dist[nz * WINDOW + nx]
				if nd < 0:
					continue
				if dx != 0 and dz != 0 and (dist[wz * WINDOW + nx] < 0 or dist[nz * WINDOW + wx] < 0):
					continue
				var cost := float(nd) + (0.42 if dx != 0 and dz != 0 else 0.0)
				if cost < best:
					best = cost
					bx = dx
					bz = dz
		var l := sqrt(float(bx * bx + bz * bz))
		dir_x[w] = bx / l if l > 0.0 else 0.0
		dir_z[w] = bz / l if l > 0.0 else 0.0


## Window index of the cell under (x, z), or -1 if it's outside the flow-field window.
func window_index(x: float, z: float) -> int:
	var wx := int(floorf((x - origin) / CELL)) - win_x0
	var wz := int(floorf((z - origin) / CELL)) - win_z0
	if wx < 0 or wz < 0 or wx >= WINDOW or wz >= WINDOW:
		return -1
	return wz * WINDOW + wx


## Steps from (x, z) to the player along the floor, or -1 if unknown / unreachable.
func steps_to_player(x: float, z: float) -> int:
	var w := window_index(x, z)
	return dist[w] if w >= 0 else -1


## True if nothing solid lies on the straight line between a and b (for throwing).
func line_clear(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var steps := int(d.length() / (CELL * 0.5)) + 1
	for k in range(1, steps):
		var t := float(k) / steps
		if is_blocked(a.x + d.x * t, a.z + d.y * t):
			return false
	return true


## A walkable cell the player can be reached from, between r0 and r1 metres from `around`.
## Falls back to any reachable cell in the window; INF if there's none.
func reachable_point(around: Vector3, r0: float, r1: float, rng: RandomNumberGenerator) -> Vector3:
	for attempt in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(r0, r1)
		var x := around.x + cos(a) * r
		var z := around.z + sin(a) * r
		var w := window_index(x, z)
		if w >= 0 and dist[w] > 0:
			return Vector3(x, 0.0, z)
	for attempt in 200:
		var w := rng.randi() % (WINDOW * WINDOW)
		if dist[w] > 2:
			return Vector3(origin + (win_x0 + w % WINDOW + 0.5) * CELL, 0.0, origin + (win_z0 + w / WINDOW + 0.5) * CELL)
	return Vector3.INF
