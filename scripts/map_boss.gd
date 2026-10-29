class_name MapBoss
extends Node3D
## Shared machinery for the map bosses after Thog (the Forest's Toadstool Knight, the Castle's
## Arachnid). A boss is a crowd row in EnemyManager (type TROLL, with this boss's numbers from
## stats()), so every weapon, ability, burn and freeze hits it; this node draws it, decides its
## attacks and keeps the HUD health bar.
##
## Fair warning, always: every attack that lands somewhere is announced on the ground first
## (warn_circle / warn_wedge / warn_lane / warn_ring). The marker fills up red until the hit
## lands, and never in less than MIN_WARN seconds, enraged or not, so there's always time to
## step out of it. Lobbed projectiles fly in an arc that lands exactly when their marker fills.
## Lingering zones (spore clouds, webs) stay drawn on the ground for as long as they last.
##
## Subclasses override: stats(), display_name(), bar_color(), sounds(), _build_model(),
## _think(dt, row) (walk / pick attacks), _tick_attack(dt), _on_enrage(), _tick_death(dt).

signal defeated
signal enraged

const ENRAGE_AFTER := 120.0       # seconds after arriving
const ENRAGE_SPEED := 1.6         # enraged: wind-ups and gaps this much faster (markers never below MIN_WARN)
const MIN_WARN := 1.0             # every telegraphed hit gives at least this long to get out of the way
const WARN_COLOR := Color(1.0, 0.12, 0.05)
const HAZARD_TICK := 0.5          # lingering zones hurt every this many seconds

var main: Node
var em: EnemyManager
var player: Player
var fx: FxManager
var uid := -1
var idx := -1
var state := "walk"               # walk | attack | dying | dead (subclasses add their own)
var attack := ""
var is_enraged := false
var alive_time := 0.0
var counts := {"hits": 0, "warned": 0}   # for tests
var _warns: Array[Dictionary] = []      # {disc, t, time, land}
var _hazards: Array[Dictionary] = []    # {disc, at, r, t, life, dps, slow, tick}
var _lobs: Array[Dictionary] = []       # {node, from, to, t, time, peak}
var _sfx := {}
var _bar_root: Control
var _bar: ProgressBar
var _bar_label: Label
var _last_hp := 0.0
var _die_t := 0.0


# ------------------------------------------------------------------ to override

## {name, hp, speed, radius, height, damage, xp} for the TROLL row.
func stats() -> Dictionary:
	return {}


func display_name() -> String:
	return "BOSS"


func bar_color() -> Color:
	return Color(0.8, 0.3, 0.3)


func sounds() -> Dictionary:
	return {}


func _build_model() -> void:
	pass


func _think(_dt: float, _i: int) -> void:
	pass


func _tick_attack(_dt: float) -> void:
	pass


func _on_enrage() -> void:
	pass


func _on_hurt() -> void:
	pass


func _on_die() -> void:
	pass


## Return true once the death animation is over.
func _tick_death(_dt: float) -> bool:
	return _die_t > 5.0


# ------------------------------------------------------------------ setup

## Spawn at `at` with `hp_mult` x the base health.
func setup(p_main: Node, at: Vector3, hp_mult: float) -> void:
	main = p_main
	em = main.enemies
	player = main.player
	fx = main.fx
	em.set_boss_stats(stats())
	em.boss_contact = true
	idx = em.spawn(EnemyManager.TROLL, at, hp_mult)
	uid = em.uid[idx]
	_last_hp = em.hp[idx]


func _ready() -> void:
	var snd := sounds()
	for k in snd:
		var a := AudioStreamPlayer3D.new()
		a.bus = Settings.SFX_BUS
		a.unit_size = 30.0
		a.max_distance = 140.0
		if ResourceLoader.exists(snd[k]):
			a.stream = load(snd[k])
		add_child(a)
		_sfx[k] = a
	_build_model()
	_make_bar()


## Current crowd row (rows move when others die), or -1 once gone.
func row() -> int:
	if em == null:
		return -1
	if idx >= 0 and idx < em.count and em.uid[idx] == uid:
		return idx
	idx = -1
	for i in em.count:
		if em.uid[i] == uid:
			idx = i
			break
	return idx


func hp_fraction() -> float:
	var i := row()
	return clampf(em.hp[i] / em.hp_max[i], 0.0, 1.0) if i >= 0 and not em.dead[i] else 0.0


func speed_k() -> float:
	return ENRAGE_SPEED if is_enraged else 1.0


# ------------------------------------------------------------------ loop

func _physics_process(dt: float) -> void:
	if state == "dead":
		return
	if state == "dying":
		_die_t += dt
		_tick_lobs(dt)
		if _tick_death(dt):
			state = "dead"
		return
	var i := row()
	if i < 0 or em.dead[i]:
		_die()
		return
	if main.state != "playing":
		return
	alive_time += dt
	if not is_enraged and alive_time >= ENRAGE_AFTER:
		_enrage()
	if em.hp[i] < _last_hp - 0.01:
		_on_hurt()
	_last_hp = em.hp[i]
	_tick_warns(dt)
	_tick_lobs(dt)
	_tick_hazards(dt)
	if state == "walk":
		_think(dt, i)
	else:
		_tick_attack(dt)
	_update_bar()


# ------------------------------------------------------------------ telegraphs

## A filled red circle on the ground at `at`; `land` is called when it fills (after `secs`,
## sped up when enraged but never under MIN_WARN). Returns the warning (to cancel it).
func warn_circle(at: Vector3, radius: float, secs: float, land: Callable, color := WARN_COLOR) -> Dictionary:
	var d := _disc(at, Vector3(radius, 1, radius), color)
	return _add_warn(d, secs, land)


## A wedge `half_angle` either side of `aim`, `radius` long, from `origin`.
func warn_wedge(origin: Vector3, aim: Vector3, radius: float, half_angle: float, secs: float, land: Callable) -> Dictionary:
	var d := _disc(origin, Vector3(radius, 1, radius), WARN_COLOR)
	d.set_arc(half_angle)
	d.rotation.y = atan2(-aim.x, -aim.z)
	return _add_warn(d, secs, land)


## A lane `length` long and `width` wide from `from` along `dir` (a stretched oval).
func warn_lane(from: Vector3, dir: Vector3, length: float, width: float, secs: float, land: Callable) -> Dictionary:
	dir.y = 0.0
	dir = dir.normalized()
	var c := from + dir * (length * 0.5)
	c.y = SwampWater.height_at(c.x, c.z)
	var d := _disc(c, Vector3(width * 0.5, 1, length * 0.5), WARN_COLOR)
	d.rotation.y = atan2(-dir.x, -dir.z)
	return _add_warn(d, secs, land)


## A band from `inner` to `outer` metres around `at`.
func warn_ring(at: Vector3, inner: float, outer: float, secs: float, land: Callable) -> Dictionary:
	var d := _disc(at, Vector3(outer, 1, outer), WARN_COLOR)
	d.set_ring(inner / outer)
	return _add_warn(d, secs, land)


func warn_time(secs: float) -> float:
	return maxf(secs / speed_k(), MIN_WARN)


func _disc(at: Vector3, scl: Vector3, color: Color) -> GroundDisc:
	var d := GroundDisc.create(1.0, color, false)
	d.alpha = 0.55
	d.set_lift(0.15)
	d.set_fill(0.0)
	add_child(d)
	d.global_position = Vector3(at.x, SwampWater.height_at(at.x, at.z), at.z)
	d.scale = scl
	return d


func _add_warn(d: GroundDisc, secs: float, land: Callable) -> Dictionary:
	var w := {"disc": d, "t": 0.0, "time": warn_time(secs), "land": land}
	_warns.append(w)
	counts["warned"] += 1
	return w


func cancel_warn(w: Dictionary) -> void:
	if _warns.has(w):
		_warns.erase(w)
		(w["disc"] as Node).queue_free()


func clear_warns() -> void:
	for w in _warns:
		(w["disc"] as Node).queue_free()
	_warns.clear()


func _tick_warns(dt: float) -> void:
	for k in range(_warns.size() - 1, -1, -1):
		var w: Dictionary = _warns[k]
		w["t"] += dt
		var d: GroundDisc = w["disc"]
		d.set_fill(clampf(w["t"] / w["time"], 0.0, 1.0))
		if w["t"] >= w["time"]:
			_warns.remove_at(k)
			d.queue_free()
			(w["land"] as Callable).call()


# ------------------------------------------------------------------ lobbed projectiles

## A projectile mesh flying from `from` to `to` in an arc, arriving after `secs` (use the same
## time as its ground marker: warn_time()).
func lob(from: Vector3, to: Vector3, secs: float, color: Color, size := 0.6, peak := 6.0) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.5
	sm.material = m
	mi.mesh = sm
	mi.top_level = true
	add_child(mi)
	mi.global_position = from
	_lobs.append({"node": mi, "from": from, "to": to, "t": 0.0, "time": secs, "peak": peak})


func _tick_lobs(dt: float) -> void:
	for k in range(_lobs.size() - 1, -1, -1):
		var l: Dictionary = _lobs[k]
		l["t"] += dt
		var f: float = clampf(l["t"] / l["time"], 0.0, 1.0)
		var p: Vector3 = (l["from"] as Vector3).lerp(l["to"], f)
		p.y += 4.0 * l["peak"] * f * (1.0 - f)
		(l["node"] as Node3D).global_position = p
		if f >= 1.0:
			(l["node"] as Node).queue_free()
			_lobs.remove_at(k)


# ------------------------------------------------------------------ lingering zones

## A zone on the ground that lasts `life` s: `dps` damage (every HAZARD_TICK) and/or a slow
## (`slow` < 1) while the player stands in it. Drawn for as long as it lasts.
func add_hazard(at: Vector3, radius: float, life: float, color: Color, dps: float, slow := 1.0) -> void:
	var d := GroundDisc.create(1.0, color, false)
	d.alpha = 0.45
	d.set_lift(0.12)
	add_child(d)
	d.global_position = Vector3(at.x, SwampWater.height_at(at.x, at.z), at.z)
	d.scale = Vector3(radius, 1, radius)
	_hazards.append({"disc": d, "at": at, "r": radius, "t": 0.0, "life": life, "dps": dps, "slow": slow, "tick": 0.0})


func _tick_hazards(dt: float) -> void:
	var pp := player.global_position
	for k in range(_hazards.size() - 1, -1, -1):
		var h: Dictionary = _hazards[k]
		h["t"] += dt
		var d: GroundDisc = h["disc"]
		var left: float = h["life"] - h["t"]
		d.alpha = 0.45 * clampf(left / 0.6, 0.0, 1.0)
		if left <= 0.0:
			d.queue_free()
			_hazards.remove_at(k)
			continue
		if flat_dist(pp, h["at"]) < h["r"] and not airborne():
			if h["slow"] < 1.0:
				player.apply_slow(h["slow"], 0.25)
			if h["dps"] > 0.0:
				h["tick"] -= dt
				if h["tick"] <= 0.0:
					h["tick"] = HAZARD_TICK
					player.invuln = 0.0
					player.hurt(h["dps"] * HAZARD_TICK)


func clear_hazards() -> void:
	for h in _hazards:
		(h["disc"] as Node).queue_free()
	_hazards.clear()


# ------------------------------------------------------------------ hitting the player

func hit_player(amount: float, push: Vector3) -> bool:
	player.invuln = 0.0   # telegraphed hits always land, whatever grazed you a moment ago
	if player.hurt(amount):
		counts["hits"] += 1
		player.knockback(push)
		shake(0.45)
		return true
	return false


func player_in_circle(c: Vector3, r: float) -> bool:
	return flat_dist(player.global_position, c) < r


func airborne() -> bool:
	var p := player.global_position
	return p.y - SwampWater.height_at(p.x, p.z) > 0.7


static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, SwampWater.height_at(p.x, p.z), p.z)


## The player's spot a moment from now (so markers lead a running target a little).
func player_ahead(secs: float) -> Vector3:
	var v := player.velocity
	return ground(player.global_position + Vector3(v.x, 0, v.z) * secs)


func shake(amount: float) -> void:
	var d := flat_dist(player.global_position, global_position)
	player.add_shake(amount * clampf(1.4 - d / 40.0, 0.2, 1.0))


func play_sfx(k: String, pitch := 1.0) -> void:
	var a: AudioStreamPlayer3D = _sfx.get(k)
	if a and a.stream:
		a.pitch_scale = pitch * randf_range(0.93, 1.05)
		a.play()


# ------------------------------------------------------------------ enrage, death

func _enrage() -> void:
	is_enraged = true
	play_sfx("roar")
	shake(0.7)
	main.hud.flash_message(tr("%s IS ENRAGED!") % tr(display_name()), 4.0)
	_on_enrage()
	enraged.emit()


func _die() -> void:
	state = "dying"
	em.troll_busy = false
	em.boss_contact = true
	clear_warns()
	clear_hazards()
	_die_t = 0.0
	if _bar_root:
		_bar_root.queue_free()
		_bar_root = null
	_on_die()
	defeated.emit()


# ------------------------------------------------------------------ HUD bar

func _make_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_bar_root = Control.new()
	_bar_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_bar_root.offset_left = -330
	_bar_root.offset_right = 330
	_bar_root.offset_top = 74
	_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_bar_root)
	_bar_label = Label.new()
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.size = Vector2(660, 28)
	_bar_label.add_theme_font_size_override("font_size", 22)
	_bar_label.add_theme_color_override("font_color", bar_color().lerp(Color.WHITE, 0.45))
	_bar_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_bar_label.add_theme_constant_override("outline_size", 5)
	_bar_root.add_child(_bar_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.position = Vector2(0, 30)
	_bar.size = Vector2(660, 18)
	_bar.max_value = 1.0
	_bar.step = 0.0001
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	bg.border_color = Color(0.0, 0.0, 0.0, 0.9)
	bg.set_border_width_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = bar_color()
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar_root.add_child(_bar)
	_update_bar()


func _update_bar() -> void:
	if _bar == null or _bar_root == null:
		return
	_bar.value = hp_fraction()
	var n := tr(display_name())
	if is_enraged:
		(_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.95, 0.2, 0.1).lerp(Color(1.0, 0.55, 0.1), 0.5 + 0.5 * sin(alive_time * 8.0))
		_bar_label.text = tr("%s  ·  ENRAGED") % n
		_bar_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
	else:
		var left := maxf(0.0, ENRAGE_AFTER - alive_time)
		_bar_label.text = tr("%s  ·  enrages in %d:%02d") % [n, int(left) / 60, int(left) % 60]
