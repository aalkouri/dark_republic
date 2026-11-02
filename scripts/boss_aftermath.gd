class_name BossAftermath
extends Node3D
## What happens once a map's boss falls (main.gd calls `boss_down`). The run isn't over yet:
##   - his elemental shards burst out of the corpse and scatter round it as crystals
##     (ShardDrops); walk over them to bank them (Wallet.add_shards, main.shards_won);
##   - the monsters stop coming (main.boss_down; Classic only, Unrelenting keeps spawning);
##   - PORTAL_DELAY s later a portal (BossPortal) rises somewhere on the map; the clock gives
##     way to "PORTAL OPEN" and an arrow at the edge of the screen points to it;
##   - step into it: you're pulled through, any shards still lying about are banked for you, and
##     the run is won (main.complete_run: the usual end screen, coins, unlocks).
## Debug: `-- --portal-at=T` drops shards in front of you and opens the portal at T seconds
## without a boss (screenshots; nothing is banked).

const PORTAL_DELAY := 2.5      # seconds after the boss falls before the portal starts to rise
const PULL_TIME := 1.1         # stepping in: drawn into the vortex this long, then the win
const VIOLET := Color(0.78, 0.5, 1.0)

var main: Node
var drops: ShardDrops
var portal: BossPortal
var active := false            # the boss is down (or the debug portal is coming)
var entering := false          # being pulled through
var banked := {}               # shards banked by this aftermath (tests)
var _portal_t := -1.0
var _pull_t := 0.0
var _pull_from := Vector3.ZERO
var _debug_at := -1.0
var _debug := false
var _whoosh: AudioStreamPlayer
var _layer: CanvasLayer
var _label: Label
var _arrow: Control
var _flash: ColorRect
var _clock_hidden := false


func setup(p_main: Node) -> void:
	main = p_main
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--portal-at="):   # screenshots: shards and the portal without a boss
			_debug_at = float(a.split("=")[1])


func _ready() -> void:
	drops = ShardDrops.new()
	add_child(drops)
	drops.collected.connect(_on_collected)
	_whoosh = AudioStreamPlayer.new()
	_whoosh.bus = Settings.SFX_BUS
	_whoosh.process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists("res://audio/portal/portal_whoosh.wav"):
		_whoosh.stream = load("res://audio/portal/portal_whoosh.wav")
	add_child(_whoosh)
	_build_overlay()


## The boss fell at `at`: scatter `won` ({kind: count}) round him and open the portal soon.
func boss_down(at: Vector3, won: Dictionary) -> void:
	if active:
		return
	active = true
	drops.drop(won, at, main.rng, _good_ground, main.player.global_position)
	_portal_t = PORTAL_DELAY


## Where a shard may land: walkable floor indoors, dry ground (no pools, no lava) outdoors.
func _good_ground(q: Vector3) -> bool:
	var half: float = main.ARENA_HALF - 4.0
	if absf(q.x) > half or absf(q.z) > half:
		return false
	if CastleNav.current != null:
		var nav := CastleNav.current
		return not nav.is_blocked(q.x, q.z) and not nav.is_blocked(q.x + 1.0, q.z) and not nav.is_blocked(q.x - 1.0, q.z) \
			and not nav.is_blocked(q.x, q.z + 1.0) and not nav.is_blocked(q.x, q.z - 1.0)
	if CalderaBuilder.active:
		return not CalderaBuilder.near_lava(q.x, q.z, 1.0)
	return not main.water.in_pool_xz(q.x, q.z)


func _physics_process(dt: float) -> void:
	if main == null or main.state != "playing" or main.intro:
		return
	if _debug_at >= 0.0 and main.run_time >= _debug_at:
		_debug_at = -1.0
		_debug_open()
	if entering:
		_tick_pull(dt)
		return
	drops.tick(dt, main.player.global_position, main.stats.value("pickup_range"))
	if _portal_t >= 0.0:
		_portal_t -= dt
		if _portal_t < 0.0:
			_open_portal()
	if portal != null and portal.contains(main.player.global_position):
		_step_in()


func _process(_dt: float) -> void:
	var show: bool = portal != null and main != null and main.state == "playing" and not _hud_hidden()
	_label.visible = show
	_arrow.visible = show and not entering
	if show:
		var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
		_label.modulate = Color(1, 1, 1, 0.75 + 0.25 * k)
		_arrow.queue_redraw()


func _hud_hidden() -> bool:
	return main.hud == null or not main.hud.visible


func _open_portal() -> void:
	var spot := BossPortal.find_spot(main, Settings.selected_map)
	portal = BossPortal.new()
	portal.setup(Settings.selected_map, main.fx)
	add_child(portal)
	portal.global_position = spot["pos"]
	portal.rotation.y = float(spot["yaw"])
	portal.open()
	main.hud.flash_message(tr("THE PORTAL IS OPEN"), 4.0)
	if not main.endless:   # the countdown is over: "PORTAL OPEN" takes the clock's place
		main.hud.timer_label.visible = false
		_clock_hidden = true
		_label.offset_top = 16
	else:
		_label.offset_top = 64


## Debug (--portal-at): shards in front of you and the portal, opened at once.
func _debug_open() -> void:
	_debug = true
	if not main.endless:
		main.boss_down = true
		main._boss_down_at = main.run_time
	var p: Player = main.player
	var fwd := Vector3(-sin(p.cam_yaw), 0, -cos(p.cam_yaw))
	var won := {}
	for kind in Wallet.map_shards(Settings.selected_map):
		won[kind] = 2
	active = true
	drops.drop(won, p.global_position + fwd * 9.0, main.rng, _good_ground, p.global_position + fwd * 6.0)
	_open_portal()
	portal.open_now()


func _on_collected(kind: String, at: Vector3) -> void:
	_bank({kind: 1})
	var cols: Array = ShardIcon.COLORS.get(kind, ShardIcon.COLORS["fire"])
	if main.fx != null:
		main.fx.burst(at, 1.3, cols[0], 0.3)
	var l: Label = Wallet.shard_labels.get(kind)
	if l != null:   # the counter pops
		l.pivot_offset = l.size * 0.5
		var tw := l.create_tween()
		tw.tween_property(l, "scale", Vector2.ONE * 1.7, 0.08)
		tw.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _bank(won: Dictionary) -> void:
	if won.is_empty():
		return
	for kind in won:
		banked[kind] = int(banked.get(kind, 0)) + int(won[kind])
	if _debug:
		return   # screenshot shards aren't real
	for kind in won:
		main.shards_won[kind] = int(main.shards_won.get(kind, 0)) + int(won[kind])
	Wallet.add_shards(won)


# ------------------------------------------------------------------ stepping through

func _step_in() -> void:
	entering = true
	_pull_t = 0.0
	var p: Player = main.player
	_pull_from = p.global_position
	p.scripted = true      # no input or physics while the portal has you
	p.untouchable = true
	p.velocity = Vector3.ZERO
	if _whoosh.stream:
		_whoosh.play()
	if main.fx != null:
		main.fx.burst(portal.centre(), 3.0, BossPortal.VIOLET, 0.4)


func _tick_pull(dt: float) -> void:
	_pull_t += dt
	var k := clampf(_pull_t / PULL_TIME, 0.0, 1.0)
	var p: Player = main.player
	var e := k * k * (3.0 - 2.0 * k)
	var c := portal.centre() - Vector3(0, 0.9, 0)
	p.global_position = _pull_from.lerp(c, e)
	if p.model != null:
		var s := maxf(0.05, 1.0 - e * 0.95)
		p.model.scale = Vector3.ONE * s
		p.model.rotation.y += dt * (4.0 + 18.0 * e)
	_flash.color = Color(0.92, 0.85, 1.0, clampf((k - 0.55) / 0.45, 0.0, 1.0))
	if k >= 1.0:
		entering = false
		_bank(drops.collect_all())   # nothing left behind
		if p.model != null:
			p.model.visible = false
		main.complete_run()
		var tw := _flash.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(_flash, "color:a", 0.0, 0.7)


# ------------------------------------------------------------------ HUD: label and pointer

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 0   # under the HUD layer: pause, level-up and end screens cover it
	add_child(_layer)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_layer.add_child(_flash)
	_label = Label.new()
	_label.text = tr("PORTAL OPEN")
	_label.add_theme_font_size_override("font_size", 38)
	_label.add_theme_color_override("font_color", VIOLET)
	_label.add_theme_color_override("font_outline_color", Color(0.08, 0.0, 0.14))
	_label.add_theme_constant_override("outline_size", 8)
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.offset_left = -260
	_label.offset_right = 260
	_label.offset_top = 16
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	_layer.add_child(_label)
	_arrow = Control.new()
	_arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.visible = false
	_arrow.draw.connect(_draw_arrow)
	_layer.add_child(_arrow)


## Where the portal's marker sits on screen: {pos, on_screen, angle} (tests).
func marker() -> Dictionary:
	var cam: Camera3D = main.player.cam if main.player != null else null
	var vs := _arrow.get_viewport_rect().size
	if cam == null or portal == null:
		return {}
	var target := portal.global_position + Vector3(0, BossPortal.RING_C * 2.0 + 0.8, 0)
	var behind := cam.is_position_behind(target)
	var sp := cam.unproject_position(target)
	var c := vs * 0.5
	var margin := 70.0
	if not behind and sp.x > margin and sp.x < vs.x - margin and sp.y > margin and sp.y < vs.y - margin:
		return {"pos": sp, "on_screen": true, "angle": PI * 0.5}
	var d := sp - c
	if behind:
		d = -d
	if d.length_squared() < 1.0:
		d = Vector2(0, 1)
	var ang := d.angle()
	var half := c - Vector2(margin, margin)
	var t := minf(absf(half.x / cos(ang)) if absf(cos(ang)) > 0.001 else INF, absf(half.y / sin(ang)) if absf(sin(ang)) > 0.001 else INF)
	return {"pos": c + Vector2(cos(ang), sin(ang)) * t, "on_screen": false, "angle": ang}


func _draw_arrow() -> void:
	var m := marker()
	if m.is_empty():
		return
	var pos: Vector2 = m["pos"]
	var ang: float = m["angle"]
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	var s := 20.0 + 4.0 * pulse
	var dir := Vector2(cos(ang), sin(ang))
	var side := Vector2(-dir.y, dir.x)
	if m["on_screen"]:   # over the portal: a bobbing chevron pointing down at it
		pos += Vector2(0, -10.0 - 6.0 * pulse)
	_arrow.draw_circle(pos - dir * s * 0.2, s * 1.25, Color(0.6, 0.25, 1.0, 0.18 + 0.15 * pulse))
	var tip := pos + dir * s
	var pts := PackedVector2Array([tip, pos - dir * s * 0.6 + side * s * 0.85, pos - dir * s * 0.15, pos - dir * s * 0.6 - side * s * 0.85])
	_arrow.draw_colored_polygon(pts, Color(0.82, 0.55, 1.0).lerp(Color.WHITE, 0.3 * pulse))
	pts.append(pts[0])
	_arrow.draw_polyline(pts, Color(0.12, 0.0, 0.22), 2.5, true)
	var dist := int(round(Vector2(portal.global_position.x - main.player.global_position.x, portal.global_position.z - main.player.global_position.z).length()))
	var font := _arrow.get_theme_default_font()
	var txt := tr("%d m") % dist
	var tp := pos - dir * (s * 1.6) + Vector2(-20, 7)
	_arrow.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 18, 5, Color(0.08, 0.0, 0.14))
	_arrow.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 18, Color(0.92, 0.8, 1.0))
