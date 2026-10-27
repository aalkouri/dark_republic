extends CanvasLayer
## Coins (autoload "Wallet"): the player's persistent currency, and the coin counter that is
## always on screen in the top-right corner (title, character select, in-game, pause, end).
## Also stores each character's level ("lvl", shown on the character select tiles).
##
## Earning: 1 coin per second survived + 100 coins per 1,000 kills. A run's coins are only
## banked on the end-of-run summary, where payout() pours them out of the middle of the screen:
## each coin bursts out, then flies to the counter and disappears into it, the counter ticking
## up as they land, with a casino jingle playing until the last one lands (then a ka-ching).

signal changed(coins: int)
signal payout_finished

const PATH := "user://progress.cfg"
const COINS_PER_SECOND := 1
const KILL_BONUS := 100
const KILLS_PER_BONUS := 1000
const MAX_FLYING := 70                 # visual coins per payout (each carries a share)
const JINGLE := "res://audio/coins/jingle_loop.wav"
const DING := "res://audio/coins/coin_done.wav"

var coins := 0                         # banked total
var char_levels := {}                  # character id -> lvl (0 when missing)
var displayed := 0.0                   # what the counter shows (lags during a payout)
var persist := true                    # off for test/screenshot runs

var panel: Control
var icon: CoinIcon
var label: Label
var _flying: Array = []                # {node, value, t, start, vel, phase, dur, burst}
var _to_spawn: Array = []              # values still to launch
var _spawn_from := Vector2.ZERO
var _spawn_gap := 0.05
var _spawn_t := 0.0
var _pulse := 0.0
var _jingle: AudioStreamPlayer
var _ding: AudioStreamPlayer
var _paying := false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a == "--smoketest" or a.begins_with("--shot"):
			persist = false
	_load()
	displayed = coins
	_build()
	_build_audio()


## A character's level ("lvl"), 0 if it has none.
func char_level(id: String) -> int:
	return int(char_levels.get(id, 0))


func set_char_level(id: String, lvl: int) -> void:
	char_levels[id] = maxi(0, lvl)
	_save()


## Coins a run is worth: {time, bonus, total}.
static func run_reward(seconds: float, kills: int) -> Dictionary:
	var t := int(floor(seconds)) * COINS_PER_SECOND
	var b := (kills / KILLS_PER_BONUS) * KILL_BONUS
	return {"time": t, "bonus": b, "total": t + b}


## Add coins immediately (no animation).
func add(amount: int) -> void:
	coins += amount
	displayed = coins
	_save()
	changed.emit(coins)


## Bank `amount` and play the payout: coins pour out of `from` (screen position) and fly into
## the counter. The coins are saved at once; only the display catches up.
func payout(amount: int, from: Vector2) -> void:
	if amount <= 0:
		payout_finished.emit()
		return
	coins += amount
	_save()
	changed.emit(coins)
	var n := clampi(amount, 1, MAX_FLYING)
	var share := amount / n
	var extra := amount - share * n
	for k in n:
		_to_spawn.append(share + (1 if k < extra else 0))
	_spawn_from = from
	# Bigger payouts pour for longer, up to ~3.5 s
	_spawn_gap = clampf(lerpf(1.2, 3.5, clampf(amount / 1500.0, 0.0, 1.0)) / n, 0.02, 0.09)
	_spawn_t = 0.0
	_paying = true
	if not _jingle.playing:
		_jingle.play()


func is_paying() -> bool:
	return _paying


## Finish any payout instantly (e.g. leaving the screen).
func finish_now() -> void:
	for f in _flying:
		(f["node"] as Node).queue_free()
	_flying.clear()
	_to_spawn.clear()
	displayed = coins
	_end_payout()


func set_shown(v: bool) -> void:
	panel.visible = v


## Centre of the counter's coin, in screen space (where flying coins go).
func target() -> Vector2:
	return icon.get_global_rect().get_center()


# ------------------------------------------------------------------ build

func _build() -> void:
	var font: Font = null
	if ResourceLoader.exists("res://fonts/Cinzel.ttf"):
		var fv := FontVariation.new()
		fv.base_font = load("res://fonts/Cinzel.ttf")
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
		font = fv
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.035, 0.02, 0.72)
	sb.border_color = Color(0.85, 0.62, 0.18, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 10
	sb.content_margin_right = 18
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -18
	panel.offset_top = 14
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	icon = CoinIcon.new()
	icon.custom_minimum_size = Vector2(34, 34)
	row.add_child(icon)
	label = Label.new()
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.0))
	label.add_theme_constant_override("outline_size", 5)
	label.custom_minimum_size = Vector2(70, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(label)
	_refresh()


func _build_audio() -> void:
	_jingle = AudioStreamPlayer.new()
	_jingle.bus = Settings.SFX_BUS
	_jingle.volume_db = -4.0
	if ResourceLoader.exists(JINGLE):
		var st := (load(JINGLE) as AudioStreamWAV).duplicate() as AudioStreamWAV
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
		_jingle.stream = st
	add_child(_jingle)
	_ding = AudioStreamPlayer.new()
	_ding.bus = Settings.SFX_BUS
	if ResourceLoader.exists(DING):
		_ding.stream = load(DING)
	add_child(_ding)


static func fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _refresh() -> void:
	label.text = fmt(int(round(displayed)))


# ------------------------------------------------------------------ animation

func _process(dt: float) -> void:
	icon.glint += dt * 0.35
	_pulse = maxf(0.0, _pulse - dt * 4.0)
	panel.pivot_offset = panel.size * Vector2(1.0, 0.5)
	panel.scale = Vector2.ONE * (1.0 + 0.12 * _pulse)
	icon.spin = fmod(icon.spin + dt * 2.5, 1.0) if _paying else 0.0

	# Launch queued coins from the middle of the screen
	if not _to_spawn.is_empty():
		_spawn_t -= dt
		while _spawn_t <= 0.0 and not _to_spawn.is_empty():
			_spawn_t += _spawn_gap
			_launch(_to_spawn.pop_front())

	var goal := target()
	for k in range(_flying.size() - 1, -1, -1):
		var f: Dictionary = _flying[k]
		var node: CoinIcon = f["node"]
		f["t"] += dt
		node.spin = fmod(node.spin + dt * f["spin"], 1.0)
		if f["t"] < f["burst"]:
			# Pour out: thrown up and out from the middle, falling back under gravity
			var v: Vector2 = f["vel"]
			v.y += 1500.0 * dt
			f["vel"] = v
			node.position += v * dt
			f["start"] = node.position + node.size * 0.5
		else:
			# Jump to the counter on an arc, speeding up
			var u := clampf((f["t"] - f["burst"]) / f["dur"], 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			var a: Vector2 = f["start"]
			var mid := a.lerp(goal, 0.5) + Vector2(0, -180.0)
			var p := a.lerp(mid, e).lerp(mid.lerp(goal, e), e)
			node.position = p - node.size * 0.5
			node.scale = Vector2.ONE * lerpf(1.0, 0.55, e)
			if u >= 1.0:
				displayed = minf(displayed + f["value"], coins)
				_pulse = 1.0
				node.queue_free()
				_flying.remove_at(k)
	if _paying and _to_spawn.is_empty() and _flying.is_empty():
		displayed = coins
		_end_payout()
		_ding.play()
	_refresh()


func _launch(value: int) -> void:
	var node := CoinIcon.new()
	var sz := randf_range(26.0, 40.0)
	node.size = Vector2(sz, sz)
	node.pivot_offset = node.size * 0.5
	node.position = _spawn_from - node.size * 0.5 + Vector2(randf_range(-30, 30), randf_range(-10, 10))
	node.spin = randf()
	add_child(node)
	var ang := randf_range(-PI * 0.85, -PI * 0.15)   # upward fan
	var speed := randf_range(380.0, 760.0)
	_flying.append({"node": node, "value": value, "t": 0.0, "start": _spawn_from,
		"vel": Vector2(cos(ang), sin(ang)) * speed, "spin": randf_range(1.5, 3.5),
		"burst": randf_range(0.35, 0.6), "dur": randf_range(0.45, 0.7)})


func _end_payout() -> void:
	_paying = false
	_jingle.stop()
	_refresh()
	payout_finished.emit()


# ------------------------------------------------------------------ save

func _load() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		coins = int(cfg.get_value("wallet", "coins", 0))
		char_levels = cfg.get_value("characters", "levels", {})


func _save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("wallet", "coins", coins)
	cfg.set_value("characters", "levels", char_levels)
	cfg.save(PATH)
