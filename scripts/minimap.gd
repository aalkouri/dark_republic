class_name Minimap
extends Control
## The minimap in the HUD's top-right corner (under the coin and shard counters), drawn in code.
## A round, semi-transparent dark map with a gold rim, RANGE metres across its radius, that turns
## with the camera: you're the white arrow in the middle, always pointing up (the way the camera
## looks), and a little N on the rim shows north.
##   - Enemies: not shown, except the boss as a big red
##     skull diamond.
##   - Unopened chests (tier colour), power-ups (their own icons), keys and potions.
##   - Map context: the arena edge, swamp pools, the Caldera's lava, the castle's walls.
##   - BOSS ULTIMATES: while one is coming, the places to stand pulse bright green (Thog's quake
##     ponds, the Pharaoh's golden safe spots, the Necromancer's consecrated ground, Singe's basalt
##     islands); ground to keep off (the Arachnid's web swath) is tinted red. Bosses report these
##     through map_safe_zones() / map_danger_zones() (MapBoss, ThogBoss).
##   - A boss past the edge: a big pulsing red double arrow on the rim pointing his way (the
##     blip itself once he's in range).
##   - Important things past the edge (safe zones, power-ups, chests you hold the key
##     for) sit on the rim as small arrows pointing their way.
## The map content redraws REDRAW_HZ times a second; between redraws the layer is only turned and
## slid (cheap), so it stays smooth without redrawing every frame. Hidden during the entrance and
## when Settings.show_minimap is off.

const SIZE := 216.0
const RANGE := 65.0             # metres from the centre to the rim
const REDRAW_HZ := 20.0
const MAX_DOTS := 300
const MAX_ELITES := 60
const MAX_RIM_SAFE := 4         # off-map safe zones shown as rim arrows (the nearest)
const MARGIN := 18.0            # from the screen's right edge
const TOP := 68.0               # below the coin / shard pills (Wallet, offset_top 14)
const BG := Color(0.05, 0.035, 0.02, 0.72)
const GOLD := Color(0.85, 0.62, 0.18, 0.92)
const ENEMY := Color(0.9, 0.22, 0.16, 0.7)
const ELITE := Color(0.75, 0.35, 1.0, 0.95)
const BOSS := Color(1.0, 0.12, 0.08)
const SAFE := Color(0.24, 1.0, 0.4)
# Every kind of blip has its own colour on the map (none shared): chests and keys per tier,
# each potion and each power-up. Shapes differ too (boxes, keys, dots, ringed icons).
const CHEST_COLS := [Color("c8742f"), Color("eef2fa"), Color("ffd21f")]      # copper, silver-white, gold
const KEY_COLS := [Color("ff8f70"), Color("5fd8ff"), Color("ff3ddb")]        # salmon, sky blue, magenta
const POTION_COLS := [Color("8a3dff"), Color("ff5c8a"), Color("2f6bff")]     # purple, rose, royal blue
const POWERUP_COLS := [Color("ff6a00"), Color("19d6b0"), Color("ffb000"), Color("00ff9c"), Color("b8ff2e")]   # magnet, fear, damage, speed, nuke
const DANGER := Color(1.0, 0.12, 0.08)
const WATER := Color(0.25, 0.5, 0.6, 0.55)
const LAVA := Color(1.0, 0.42, 0.08, 0.6)
const WALL := Color(0.75, 0.68, 0.55, 0.55)

var main                         # main.gd (untyped: no cyclic class reference)
var _bg: Control
var _layer: Control              # world content, north-up, turned with the camera
var _overlay: Control            # rim, N, player arrow
var _redraw_t := 0.0
var _p0 := Vector3.ZERO          # player position at the last content redraw
var _time := 0.0
var _k := 1.0                    # pixels per metre
var last_draw_ms := 0.0          # how long the last content redraw took (tests, perf)
# what the last redraw showed (tests)
var shown := {"enemies": 0, "elites": 0, "bosses": [], "chests": [], "powerups": [], "keys": 0, "potions": 0,
	"safe": [], "danger": 0, "rim": 0, "boss_arrows": []}


func _init() -> void:
	name = "Minimap"   # no-i18n
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -MARGIN - SIZE
	offset_right = -MARGIN
	offset_top = TOP
	offset_bottom = TOP + SIZE
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY   # everything inside is cut to the disc
	_k = (SIZE * 0.5 - 4.0) / RANGE
	_bg = _child()
	_bg.draw.connect(_draw_bg)
	_layer = _child()
	_layer.pivot_offset = Vector2(SIZE, SIZE) * 0.5
	_layer.draw.connect(_draw_layer)
	_overlay = _child()
	_overlay.draw.connect(_draw_overlay)


func _child() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = Vector2(SIZE, SIZE)
	add_child(c)
	return c


func _draw() -> void:
	draw_circle(Vector2(SIZE, SIZE) * 0.5, SIZE * 0.5, Color.WHITE)   # the clip mask (not shown itself)


func _process(dt: float) -> void:
	var on: bool = Settings.show_minimap and main != null and main.player != null and not main.intro
	visible = on
	if not on:
		return
	_time += dt
	var p: Vector3 = main.player.global_position
	var yaw: float = main.player.cam_yaw
	_redraw_t -= dt
	if _redraw_t <= 0.0:
		_redraw_t = 1.0 / REDRAW_HZ
		_p0 = p
		_layer.queue_redraw()
	_layer.rotation = yaw
	_layer.position = (-Vector2(p.x - _p0.x, p.z - _p0.z) * _k).rotated(yaw)
	_overlay.queue_redraw()


## Force a full redraw now (tests).
func refresh() -> void:
	_redraw_t = 0.0
	_process(0.0)


## Where world point `w` lands on the minimap (control coordinates), for tests.
func to_map(w: Vector3) -> Vector2:
	var p: Vector3 = main.player.global_position
	var d := Vector2(w.x - p.x, w.z - p.z) * _k
	return Vector2(SIZE, SIZE) * 0.5 + d.rotated(main.player.cam_yaw)


# ------------------------------------------------------------------ drawing

func _draw_bg() -> void:
	var c := Vector2(SIZE, SIZE) * 0.5
	_bg.draw_circle(c, SIZE * 0.5, BG)
	_bg.draw_arc(c, SIZE * 0.25, 0.0, TAU, 48, Color(GOLD, 0.12), 1.0, true)


func _draw_overlay() -> void:
	var c := Vector2(SIZE, SIZE) * 0.5
	var r := SIZE * 0.5
	_overlay.draw_arc(c, r - 2.0, 0.0, TAU, 72, GOLD, 3.0, true)
	_overlay.draw_arc(c, r - 5.5, 0.0, TAU, 72, Color(0.0, 0.0, 0.0, 0.45), 1.5, true)
	# N on the rim
	var yaw: float = main.player.cam_yaw if main != null and main.player != null else 0.0
	var npos := c + Vector2(sin(yaw), -cos(yaw)) * (r - 13.0)
	_overlay.draw_circle(npos, 8.5, Color(0.08, 0.05, 0.02, 0.9))
	_overlay.draw_arc(npos, 8.5, 0.0, TAU, 20, GOLD, 1.5, true)
	var font := get_theme_default_font()
	_overlay.draw_string(font, npos + Vector2(-5.5, 5.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.86, 0.4))   # no-i18n
	# you: an arrow pointing up (where the camera looks)
	var tip := c + Vector2(0, -9)
	var pts := PackedVector2Array([tip, c + Vector2(6.5, 7), c + Vector2(0, 3.5), c + Vector2(-6.5, 7)])
	_overlay.draw_colored_polygon(pts, Color.WHITE)
	pts.append(tip)
	_overlay.draw_polyline(pts, Color(0.1, 0.06, 0.02), 1.5, true)


## Map position (layer coordinates, north-up, centred on _p0) of a world point.
func _at(w: Vector3) -> Vector2:
	return Vector2(SIZE, SIZE) * 0.5 + Vector2(w.x - _p0.x, w.z - _p0.z) * _k


func _in_range(w: Vector3, extra := 0.0) -> bool:
	return Vector2(w.x - _p0.x, w.z - _p0.z).length() <= RANGE + extra


func _draw_layer() -> void:
	if main == null or main.player == null:
		return
	var t0 := Time.get_ticks_usec()
	shown = {"enemies": 0, "elites": 0, "bosses": [], "chests": [], "powerups": [], "keys": 0, "potions": 0,
		"safe": [], "danger": 0, "rim": 0, "boss_arrows": []}
	_draw_terrain()
	var boss = _boss()
	if boss != null and boss.has_method("map_danger_zones"):
		for z in boss.map_danger_zones():
			_draw_danger(z)
	_draw_enemies()
	_draw_pickups()
	_draw_portal()
	if boss != null and boss.has_method("map_safe_zones"):
		_draw_safe(boss.map_safe_zones())
	last_draw_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _boss():
	if main.thog != null and is_instance_valid(main.thog):
		return main.thog
	if main.map_boss != null and is_instance_valid(main.map_boss):
		return main.map_boss
	return null


# --- static context

func _draw_terrain() -> void:
	var L := _layer
	var view := RANGE * 1.6
	if CastleNav.current != null:   # the castle: its walls (with the doorways left open)
		for w in CastleBuilder.WALLS:
			var gaps: Array = w[4]
			var cuts: Array[float] = [float(w[2])]
			var sorted_gaps := gaps.duplicate()
			sorted_gaps.sort_custom(func(a, b): return a[0] < b[0])
			for g in sorted_gaps:
				cuts.append(float(g[0]) - float(g[1]) * 0.5)
				cuts.append(float(g[0]) + float(g[1]) * 0.5)
			cuts.append(float(w[3]))
			for k in range(0, cuts.size(), 2):
				var a: Vector3
				var b: Vector3
				if w[0] == "x":
					a = Vector3(float(w[1]), 0, cuts[k])
					b = Vector3(float(w[1]), 0, cuts[k + 1])
				else:
					a = Vector3(cuts[k], 0, float(w[1]))
					b = Vector3(cuts[k + 1], 0, float(w[1]))
				L.draw_line(_at(a), _at(b), WALL, 2.5)
		for bl in CastleBuilder.BLOCKS:
			var r0 := _at(Vector3(bl[0], 0, bl[1]))
			var r1 := _at(Vector3(bl[2], 0, bl[3]))
			L.draw_rect(Rect2(r0, r1 - r0), Color(WALL, 0.3))
	# the arena edge
	var half: float = main.enemies.arena_half if main.enemies != null else 220.0
	var c0 := _at(Vector3(-half, 0, -half))
	var c1 := _at(Vector3(half, 0, half))
	L.draw_rect(Rect2(c0, c1 - c0), Color(GOLD, 0.45), false, 2.0)
	# water pools
	var w = main.water
	if w != null and "pools" in w:
		for p in w.pools:
			var pc: Vector2 = p["center"]
			var pr: float = float(p["r"])
			var at := Vector3(pc.x, 0, pc.y)
			if _in_range(at, pr + view - RANGE):
				L.draw_circle(_at(at), pr * _k, WATER)
	# the Caldera's lava
	if CalderaBuilder.active:
		for p in CalderaBuilder.pools:
			var pc: Vector2 = p["c"]
			var at := Vector3(pc.x, 0, pc.y)
			if _in_range(at, float(p["r"]) + view - RANGE):
				L.draw_circle(_at(at), float(p["r"]) * _k, LAVA)
		for rv in CalderaBuilder.rivers:
			var pts: PackedVector2Array = rv["pts"]
			var line := PackedVector2Array()
			for k in range(0, pts.size(), 4):
				var q := pts[k]
				if Vector2(q.x - _p0.x, q.y - _p0.z).length() < view:
					line.append(_at(Vector3(q.x, 0, q.y)))
				elif line.size() > 1:
					L.draw_polyline(line, LAVA, maxf(2.0, float(rv["w"]) * 2.0 * _k))
					line = PackedVector2Array()
				else:
					line.clear()
			if line.size() > 1:
				L.draw_polyline(line, LAVA, maxf(2.0, float(rv["w"]) * 2.0 * _k))


# --- enemies

## Only the boss is shown (a skull blip, or the red rim arrow when he's out of range): no dots
## for the rest of the crowd, so the map stays readable.
func _draw_enemies() -> void:
	var em: EnemyManager = main.enemies
	if em == null:
		return
	for i in em.count:
		if not em.dead[i] and em.is_boss(i):
			_draw_boss(em.pos[i])
	shown["enemies"] = 0
	shown["elites"] = 0


func _draw_boss(p: Vector3) -> void:
	var L := _layer
	shown["bosses"].append(p)
	if not _in_range(p):
		_boss_arrow(p)
		return
	var c := _at(p)
	var s := 10.0
	var dia := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)])
	L.draw_colored_polygon(dia, Color(BOSS, 0.95))
	dia.append(dia[0])
	L.draw_polyline(dia, Color(0.1, 0.0, 0.0), 1.5, true)
	# a little skull: counter-rotated so it stays upright on screen
	L.draw_set_transform(c, -_layer.rotation)
	L.draw_circle(Vector2(0, -1.0), 4.4, Color(0.98, 0.95, 0.88))
	L.draw_rect(Rect2(Vector2(-2.6, 2.0), Vector2(5.2, 3.0)), Color(0.98, 0.95, 0.88))
	L.draw_circle(Vector2(-1.7, -1.2), 1.25, Color(0.15, 0.0, 0.0))
	L.draw_circle(Vector2(1.7, -1.2), 1.25, Color(0.15, 0.0, 0.0))
	L.draw_set_transform(Vector2.ZERO)


# --- pickups

## The way out once the boss is down (BossPortal, "portal" group): a pulsing violet ring with a
## swirl, or a violet arrow on the rim while it's out of range. shown["portal"] (tests).
func _draw_portal() -> void:
	var pt := get_tree().get_first_node_in_group("portal") as Node3D
	if pt == null:
		return
	var at := pt.global_position
	var col := Color(0.78, 0.5, 1.0)
	shown["portal"] = at
	if not _in_range(at):
		_rim_arrow(at, col, 9.0)
		return
	var c := _at(at)
	var pulse := 1.0 + 0.15 * sin(_time * 5.0)
	_layer.draw_circle(c, 9.0 * pulse, Color(0.05, 0.0, 0.1, 0.9))
	_layer.draw_arc(c, 9.0 * pulse, 0.0, TAU, 24, col, 2.2, true)
	for k in 3:   # a little swirl
		var a0 := _time * 3.0 + TAU * k / 3.0
		_layer.draw_arc(c, 5.0, a0, a0 + 1.6, 8, col.lerp(Color.WHITE, 0.4), 1.6, true)
	_layer.draw_circle(c, 2.0, Color(0.95, 0.9, 1.0))


func _draw_pickups() -> void:
	var L := _layer
	# potions
	if main.potions != null:
		for p in main.potions._potions:
			var node: Node3D = p["node"]
			if is_instance_valid(node) and _in_range(node.global_position):
				var c := _at(node.global_position)
				L.draw_circle(c, 3.6, Color(0.05, 0.03, 0.02, 0.85))
				L.draw_circle(c, 2.6, POTION_COLS[int(p["kind"])])
				shown["potions"] += 1
	# keys
	if main.keys != null:
		for d in main.keys._drops:
			var node: Node3D = d["node"]
			if is_instance_valid(node) and _in_range(node.global_position):
				var c := _at(node.global_position)
				var col: Color = KEY_COLS[int(d["tier"])]
				L.draw_set_transform(c, -_layer.rotation)
				L.draw_line(Vector2(-1.0, 0.0), Vector2(5.0, 0.0), Color(0.05, 0.03, 0.02), 4.0)
				L.draw_circle(Vector2(-2.5, 0.0), 3.6, Color(0.05, 0.03, 0.02))
				L.draw_line(Vector2(-1.0, 0.0), Vector2(5.0, 0.0), col, 2.0)
				L.draw_line(Vector2(4.0, 0.0), Vector2(4.0, 2.5), col, 1.6)
				L.draw_arc(Vector2(-2.5, 0.0), 2.4, 0.0, TAU, 12, col, 1.6)
				L.draw_set_transform(Vector2.ZERO)
				shown["keys"] += 1
	# chests (unopened)
	if main.chests != null:
		for ch in main.chests.chests:
			if not is_instance_valid(ch) or ch.is_open or ch.gone:
				continue
			var at: Vector3 = ch.global_position
			var col: Color = CHEST_COLS[ch.tier]
			if not _in_range(at):
				if main.keys != null and main.keys.has_key(ch.tier):
					_rim_arrow(at, col, 6.0)   # you could open this one: point the way
				continue
			var c := _at(at)
			L.draw_set_transform(c, -_layer.rotation)
			L.draw_rect(Rect2(Vector2(-5.5, -4.5), Vector2(11, 9)), Color(0.06, 0.04, 0.02, 0.95))
			L.draw_rect(Rect2(Vector2(-4.2, -3.2), Vector2(8.4, 6.4)), col)
			L.draw_line(Vector2(-4.2, -0.6), Vector2(4.2, -0.6), Color(0.06, 0.04, 0.02), 1.2)
			L.draw_set_transform(Vector2.ZERO)
			shown["chests"].append(at)
	# power-ups
	if main.powerups != null:
		for p in main.powerups._pickups:
			var node: Node3D = p["node"]
			if not is_instance_valid(node) or not node.visible:
				continue
			var at := node.global_position
			var kind: int = p["kind"]
			var col: Color = POWERUP_COLS[kind] if kind < POWERUP_COLS.size() else PowerupManager.COLORS[kind]
			shown["powerups"].append(at)
			if not _in_range(at):
				_rim_arrow(at, col, 7.0)
				continue
			var c := _at(at)
			var pulse := 1.0 + 0.12 * sin(_time * 6.0)
			L.draw_circle(c, 8.5 * pulse, Color(0.05, 0.03, 0.02, 0.9))
			L.draw_arc(c, 8.5 * pulse, 0.0, TAU, 20, col, 1.6, true)
			L.draw_set_transform(c, -_layer.rotation)
			PowerupIcon.draw_kind(L, kind, Vector2.ZERO, 6.0)
			L.draw_set_transform(Vector2.ZERO)


# --- boss ultimates

func _draw_safe(zones: Array) -> void:
	if zones.is_empty():
		return
	var L := _layer
	var pulse := 0.5 + 0.5 * sin(_time * 7.0)
	var off: Array = []
	for z in zones:
		var at: Vector3 = z["pos"]
		var r: float = float(z["radius"])
		shown["safe"].append(at)
		var d := Vector2(at.x - _p0.x, at.z - _p0.z).length()
		if d - r > RANGE:
			off.append([d, at])
			continue
		var c := _at(at)
		var rp := maxf(r * _k, 5.0)
		L.draw_circle(c, rp + 3.0 * pulse, Color(SAFE, 0.18 + 0.12 * pulse))
		L.draw_circle(c, rp, Color(SAFE, 0.38 + 0.2 * pulse))
		L.draw_arc(c, rp + 1.0, 0.0, TAU, 28, Color(0.75, 1.0, 0.8, 0.95), 2.0, true)
	off.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(off.size(), MAX_RIM_SAFE):
		_rim_arrow(off[k][1], Color(SAFE.lerp(Color.WHITE, 0.4 * pulse), 1.0), 8.0 + 2.0 * pulse)


func _draw_danger(z: Dictionary) -> void:
	var L := _layer
	shown["danger"] += 1
	var col := Color(DANGER, 0.26 + 0.06 * sin(_time * 5.0))
	if z.has("rect"):
		var r: Rect2 = z["rect"]
		var a := _at(Vector3(r.position.x, 0, r.position.y))
		var b := _at(Vector3(r.end.x, 0, r.end.y))
		L.draw_rect(Rect2(a, b - a), col)
		L.draw_rect(Rect2(a, b - a), Color(DANGER, 0.7), false, 1.5)
	elif z.has("pos"):
		var at: Vector3 = z["pos"]
		var rp := float(z["radius"]) * _k
		L.draw_circle(_at(at), rp, col)
		L.draw_arc(_at(at), rp, 0.0, TAU, 28, Color(DANGER, 0.75), 1.5, true)


## The boss past the edge: a big, bright red, pulsing double arrow on the rim pointing his way
## (it turns with the map, so "lower left" on the map means behind you, to the left).
## shown["boss_arrows"] gets its tip in layer coordinates (tests).
func _boss_arrow(at: Vector3) -> void:
	var dir := Vector2(at.x - _p0.x, at.z - _p0.z)
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var pulse := 0.5 + 0.5 * sin(_time * 8.0)
	var s := 12.0 + 3.0 * pulse
	var c := Vector2(SIZE, SIZE) * 0.5 + dir * (SIZE * 0.5 - 10.0 - s * 0.55)
	var side := Vector2(-dir.y, dir.x)
	var tip := c + dir * s
	var L := _layer
	L.draw_circle(c, s * 1.15, Color(1.0, 0.1, 0.05, 0.22 + 0.25 * pulse))   # glow
	for k in 2:   # a double chevron: the front one bigger
		var o := -dir * (k * s * 0.55)
		var sc := 1.0 - 0.3 * k
		var pts := PackedVector2Array([tip + o, c + o - dir * s * 0.55 * sc + side * s * 0.85 * sc,
			c + o - dir * s * 0.15 * sc, c + o - dir * s * 0.55 * sc - side * s * 0.85 * sc])
		var col := Color(1.0, 0.12 + 0.25 * pulse, 0.08 + 0.15 * pulse) if k == 0 else Color(0.85, 0.05, 0.03, 0.9)
		L.draw_colored_polygon(pts, col)
		pts.append(pts[0])
		L.draw_polyline(pts, Color(1.0, 0.92, 0.85, 0.95) if k == 0 else Color(0.2, 0.0, 0.0, 0.9), 1.6, true)
	shown["boss_arrows"].append(tip)
	shown["rim"] += 1


## A small arrow on the rim pointing toward something past the edge.
func _rim_arrow(at: Vector3, col: Color, s: float) -> void:
	var dir := Vector2(at.x - _p0.x, at.z - _p0.z)
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var c := Vector2(SIZE, SIZE) * 0.5 + dir * (SIZE * 0.5 - 9.0 - s * 0.5)
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([c + dir * s, c - dir * s * 0.6 + side * s * 0.75, c - dir * s * 0.6 - side * s * 0.75])
	_layer.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	_layer.draw_polyline(pts, Color(0.05, 0.03, 0.02, 0.9), 1.2, true)
	shown["rim"] += 1
