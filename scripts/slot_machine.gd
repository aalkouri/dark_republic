class_name SlotMachine
extends Control
## The chest slot machine. Opening a chest pauses the game (like a level-up) and shows this:
## three reels whose symbols are your three abilities. Pull the handle (click it, or press
## Space / Enter) and the reels spin, then stop one after another, left to right.
##   three of the same ability -> that ability +3 levels (the jackpot)
##   otherwise                 -> +1 level to the ability that came up most (a pair); if all
##                                three differ, one of them, at random
## Like a real machine the result is decided the moment you pull (an RNG roll on the virtual
## reels), then the reels are stopped to show it. The chest's tier sets the odds of three of a
## kind: TRIPLE_ODDS. Abilities already at max level can show up on the reels but are never
## the one that's levelled.

signal finished(ability: int, levels: int)

const TRIPLE_ODDS := [0.08, 0.15, 0.30]   # bronze, silver, gold
const JACKPOT_LEVELS := 3
const STRIP := 12                 # symbols on each physical reel strip
const SYM := 112.0                # px per symbol on the reel
const WINDOW := Vector2(132, 200) # each reel window (1 symbol in the middle + bits of its neighbours)
const SPIN_SPEED := 2200.0        # px/s at full speed
const STOP_AFTER := [1.1, 1.75, 2.4]   # seconds after the pull each reel starts stopping
const STOP_TIME := 0.55           # deceleration onto the result
const SOUND_DIR := "res://audio/ui/"

var abilities: Abilities
var tier := 0
var rng: RandomNumberGenerator
var result := PackedInt32Array()  # the 3 symbols (ability slots) the reels stop on
var winner := -1
var levels := 0

var _strips: Array = []           # per reel: PackedInt32Array of ability slots
var _offset := PackedFloat32Array([0.0, 0.0, 0.0])   # px scrolled, per reel
var _state := "ready"             # ready -> spinning -> done
var _t := 0.0
var _stop_from := PackedFloat32Array([0.0, 0.0, 0.0])
var _stop_to := PackedFloat32Array([0.0, 0.0, 0.0])
var _stopped := [false, false, false]
var _handle_a := 0.0              # 0 up .. 1 pulled down
var _flash := 0.0
var _reel_nodes: Array = []       # per reel: Control (clip) holding AbilitySlot icons
var _icons: Array = []            # per reel: Array[AbilitySlot]
var _title: Label
var _sub: Label
var _odds: Label
var _result_label: Label
var _continue: Button
var _handle: Control
var _sounds := {}
var _tick_t := 0.0


## Decide the outcome of one pull: three reel symbols (ability slots 0-2). `eligible` are the
## abilities that can still level up (at least one). Returns the symbols; see `winner_of`.
static func roll(p_tier: int, eligible: Array, r: RandomNumberGenerator) -> PackedInt32Array:
	if r.randf() < TRIPLE_ODDS[p_tier]:
		var s: int = eligible[r.randi() % eligible.size()]
		return PackedInt32Array([s, s, s])
	for attempt in 100:
		var out := PackedInt32Array([r.randi() % 3, r.randi() % 3, r.randi() % 3])
		if out[0] == out[1] and out[1] == out[2]:
			continue   # not a jackpot this time
		var pair := _pair_of(out)
		if pair >= 0 and not eligible.has(pair):
			continue   # the pair would level a maxed ability: spin the virtual reels again
		return out
	return PackedInt32Array([eligible[0], eligible[0], (eligible[0] + 1) % 3])


## The symbol that appears at least twice, or -1.
static func _pair_of(s: PackedInt32Array) -> int:
	if s[0] == s[1] or s[0] == s[2]:
		return s[0]
	if s[1] == s[2]:
		return s[1]
	return -1


## Which ability levels up for symbols `s`, and by how much: [ability, levels].
static func winner_of(s: PackedInt32Array, eligible: Array, r: RandomNumberGenerator) -> Array:
	if s[0] == s[1] and s[1] == s[2]:
		return [s[0], JACKPOT_LEVELS]
	var pair := _pair_of(s)
	if pair >= 0:
		return [pair, 1]
	var pool := []
	for x in s:
		if eligible.has(x):
			pool.append(x)
	return [pool[r.randi() % pool.size()], 1]


func setup(p_abilities: Abilities, p_tier: int, p_rng: RandomNumberGenerator) -> void:
	abilities = p_abilities
	tier = p_tier
	rng = p_rng


func eligible() -> Array:
	return abilities.levelable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for k in ["slot_pull", "slot_tick", "slot_stop", "slot_win", "slot_jackpot"]:
		var p := AudioStreamPlayer.new()
		p.bus = Settings.SFX_BUS
		p.max_polyphony = 4
		if ResourceLoader.exists(SOUND_DIR + k + ".wav"):
			p.stream = load(SOUND_DIR + k + ".wav")
		add_child(p)
		_sounds[k] = p
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	# Cabinet
	var cab := Panel.new()
	var cab_size := Vector2(620, 520)
	cab.anchor_left = 0.5
	cab.anchor_right = 0.5
	cab.anchor_top = 0.5
	cab.anchor_bottom = 0.5
	cab.offset_left = -cab_size.x * 0.5 - 40.0   # room for the handle on the right
	cab.offset_right = cab_size.x * 0.5 - 40.0
	cab.offset_top = -cab_size.y * 0.5
	cab.offset_bottom = cab_size.y * 0.5
	cab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var trim: Color = Chest.TIER_COLORS[tier]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.32, 0.05, 0.06)
	sb.border_color = trim
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(26)
	sb.shadow_color = Color(trim, 0.45)
	sb.shadow_size = 18
	cab.add_theme_stylebox_override("panel", sb)
	add_child(cab)
	_title = _lbl(tr("%s Chest") % tr(Chest.TIER_NAMES[tier]), 38, trim.lightened(0.2))
	_title.position = Vector2(0, 18)
	_title.size = Vector2(cab_size.x, 48)
	cab.add_child(_title)
	_sub = _lbl(tr("Pull the handle!"), 20, Color(1, 0.92, 0.8))
	_sub.position = Vector2(0, 66)
	_sub.size = Vector2(cab_size.x, 28)
	cab.add_child(_sub)
	# Reel bank
	var bank := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.06, 0.03, 0.03)
	bsb.border_color = Color(0.85, 0.7, 0.35)
	bsb.set_border_width_all(4)
	bsb.set_corner_radius_all(12)
	bank.add_theme_stylebox_override("panel", bsb)
	bank.position = Vector2(48, 108)
	bank.size = Vector2(WINDOW.x * 3 + 16 * 4, WINDOW.y + 24)
	bank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cab.add_child(bank)
	for r in 3:
		var strip := PackedInt32Array()
		for k in STRIP:
			strip.append(k % 3)
		for k in range(STRIP - 1, 0, -1):   # each reel's own symbol order
			var j := rng.randi_range(0, k)
			var tmp := strip[k]
			strip[k] = strip[j]
			strip[j] = tmp
		_strips.append(strip)
		_offset[r] = rng.randi_range(0, STRIP - 1) * SYM
		var win := Control.new()
		win.clip_contents = true
		win.position = Vector2(16 + r * (WINDOW.x + 16), 12)
		win.size = WINDOW
		win.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bank.add_child(win)
		var face := ColorRect.new()
		face.color = Color(0.96, 0.93, 0.86)
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(face)
		var icons: Array = []
		for k in 4:
			var ic := AbilitySlot.new()
			ic.icon_only = true
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			win.add_child(ic)
			icons.append(ic)
		var shade := _ReelShade.new()   # curved-glass shading top and bottom
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(shade)
		_reel_nodes.append(win)
		_icons.append(icons)
	var payline := ColorRect.new()   # the line the result is read on
	payline.color = Color(1.0, 0.25, 0.2, 0.75)
	payline.position = Vector2(8, 12 + WINDOW.y * 0.5 - 2)
	payline.size = Vector2(bank.size.x - 16, 4)
	payline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bank.add_child(payline)
	# Pay table / odds
	_odds = _lbl(tr("3 of a kind: +%d levels (%d%% chance)   ·   otherwise: +1 level") % [JACKPOT_LEVELS, roundi(TRIPLE_ODDS[tier] * 100.0)], 17, Color(1, 0.85, 0.55))
	_odds.position = Vector2(0, 344)
	_odds.size = Vector2(cab_size.x, 26)
	cab.add_child(_odds)
	_result_label = _lbl("", 28, Color.WHITE)
	_result_label.position = Vector2(0, 380)
	_result_label.size = Vector2(cab_size.x, 76)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cab.add_child(_result_label)
	_continue = Button.new()
	_continue.text = tr("Continue")
	_continue.add_theme_font_size_override("font_size", 22)
	_continue.size = Vector2(200, 46)
	_continue.position = Vector2((cab_size.x - 200) * 0.5, 456)
	_continue.visible = false
	_continue.pressed.connect(_finish)
	cab.add_child(_continue)
	# Handle on the right side of the cabinet
	_handle = _Handle.new()
	_handle.machine = self
	_handle.position = Vector2(cab_size.x - 4, 70)
	_handle.size = Vector2(90, 300)
	cab.add_child(_handle)
	_layout_reels()


func _lbl(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE):
		if _state == "ready":
			pull()
		elif _state == "done":
			_finish()
		get_viewport().set_input_as_handled()


## Pull the handle: decide the outcome now, then spin.
func pull() -> void:
	if _state != "ready":
		return
	var el := eligible()
	result = roll(tier, el, rng)
	var w := winner_of(result, el, rng)
	winner = w[0]
	levels = w[1]
	_state = "spinning"
	_t = 0.0
	_sub.text = tr("Spinning...")
	_play("slot_pull")
	for r in 3:
		_stopped[r] = false


func is_done() -> bool:
	return _state == "done"


func _process(dt: float) -> void:
	_flash = maxf(0.0, _flash - dt * 1.5)
	match _state:
		"spinning":
			_t += dt
			_handle_a = clampf(1.0 - absf(_t - 0.18) / 0.18, 0.0, 1.0) if _t < 0.36 else 0.0
			_tick_t -= dt
			for r in 3:
				if _stopped[r]:
					continue
				var start: float = STOP_AFTER[r]
				if _t < start:
					_offset[r] += SPIN_SPEED * minf(1.0, _t * 4.0) * dt
				else:
					if _stop_to[r] == 0.0 and _stop_from[r] == 0.0:
						_plan_stop(r)
					var k := clampf((_t - start) / STOP_TIME, 0.0, 1.0)
					var ease := 1.0 - pow(1.0 - k, 3.0)   # fast, then settles
					_offset[r] = lerpf(_stop_from[r], _stop_to[r], ease)
					if k >= 1.0:
						_stopped[r] = true
						_play("slot_stop")
			if _tick_t <= 0.0 and not (_stopped[0] and _stopped[1] and _stopped[2]):
				_tick_t = 0.07
				_play("slot_tick", -8.0)
			if _stopped[0] and _stopped[1] and _stopped[2]:
				_reveal()
		"done":
			pass
	_layout_reels()
	_handle.queue_redraw()


## Work out where reel `r` lands: a few more turns, then the result symbol on the payline.
func _plan_stop(r: int) -> void:
	var strip: PackedInt32Array = _strips[r]
	var cur := _offset[r]
	var cur_idx := int(floor(cur / SYM))
	var want := result[r]
	var target := -1
	for k in range(cur_idx + 3, cur_idx + 3 + STRIP):   # at least ~3 symbols further
		if strip[posmod(k, STRIP)] == want:
			target = k
			break
	_stop_from[r] = cur
	_stop_to[r] = target * SYM


func _reveal() -> void:
	_state = "done"
	var name := tr(str(abilities.defs()[winner]["name"]))
	var before := abilities.ab_level[winner]
	var gained := abilities.level_up(winner, levels)
	var now := abilities.ab_level[winner]
	if levels >= JACKPOT_LEVELS:
		_sub.text = tr("JACKPOT!")
		_result_label.text = tr("%s  +%d levels  (Lv %d -> %d)") % [name, gained, before, now]
		_result_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		_play("slot_jackpot")
	else:
		_sub.text = tr("Winner!")
		_result_label.text = tr("%s  +%d level  (Lv %d -> %d)") % [name, gained, before, now]
		_play("slot_win")
	_flash = 1.0
	_continue.visible = true
	_continue.grab_focus()


func _finish() -> void:
	if _state != "done":
		return
	_state = "closed"
	finished.emit(winner, levels)


## Which symbol is on the payline of reel `r` right now.
func showing(r: int) -> int:
	var strip: PackedInt32Array = _strips[r]
	return strip[posmod(roundi(_offset[r] / SYM), STRIP)]


func _layout_reels() -> void:
	for r in 3:
		var strip: PackedInt32Array = _strips[r]
		var off := _offset[r]
		var base := int(floor(off / SYM))
		var frac := off - base * SYM
		var icons: Array = _icons[r]
		for k in 4:
			var ic: AbilitySlot = icons[k]
			var idx := base + k - 1
			var sym := strip[posmod(idx, STRIP)]
			_set_icon(ic, sym)
			# symbol idx sits on the payline when off == idx * SYM; later symbols wait above it
			# and the strip scrolls downward
			var cy := WINDOW.y * 0.5 - (k - 1) * SYM + frac
			ic.position = Vector2((WINDOW.x - AbilitySlot.SIZE) * 0.5, cy - AbilitySlot.SIZE * 0.5)
			var hit := _state == "done" and k == 1 and _flash > 0.0
			ic.modulate = Color(1, 1, 1) if not hit else Color(1.0 + _flash, 1.0 + _flash, 1.0 + _flash * 0.5)
			ic.queue_redraw()


func _set_icon(ic: AbilitySlot, sym: int) -> void:
	if ic.get_meta("sym", -1) == sym:
		return
	ic.set_meta("sym", sym)
	ic.icon = [AbilitySlot.Icon.INFERNO, AbilitySlot.Icon.SHOCKWAVE, AbilitySlot.Icon.METEOR][sym]
	if abilities.roster != null:
		var icd: Dictionary = KitDB.ability(abilities.kit, sym).get("icon", {})
		ic.glyph = str(icd.get("glyph", ""))
		ic.glyph_color = Color(str(icd.get("color", "#ffffff")))
	ic.is_ult = sym == 2


func _play(key: String, db := 0.0) -> void:
	var p: AudioStreamPlayer = _sounds.get(key)
	if p != null and p.stream != null:
		p.volume_db = db
		p.pitch_scale = randf_range(0.96, 1.04) if key == "slot_tick" else 1.0
		p.play()


## Curved-glass shading over a reel window: darker toward the top and bottom.
class _ReelShade extends Control:
	func _draw() -> void:
		var h := size.y
		for k in 10:
			var a := 0.5 * (1.0 - k / 10.0)
			draw_rect(Rect2(0, k * h * 0.03, size.x, h * 0.03), Color(0, 0, 0, a))
			draw_rect(Rect2(0, h - (k + 1) * h * 0.03, size.x, h * 0.03), Color(0, 0, 0, a))


## The lever: a chrome arm with a red ball that swings down when pulled. Click it to pull.
class _Handle extends Control:
	var machine: SlotMachine

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			machine.pull()
			accept_event()

	func _draw() -> void:
		var pivot := Vector2(18, size.y * 0.62)
		# mount
		draw_rect(Rect2(Vector2(0, pivot.y - 34), Vector2(26, 68)), Color(0.55, 0.55, 0.6))
		draw_rect(Rect2(Vector2(0, pivot.y - 34), Vector2(26, 68)), Color(0.2, 0.2, 0.22), false, 3.0)
		# arm: up (ready) swings down to below the pivot when pulled
		var ang := lerpf(-PI * 0.5 + 0.12, PI * 0.5 - 0.2, machine._handle_a)
		var tip := pivot + Vector2(cos(ang), sin(ang)) * 150.0 + Vector2(30, 0) * cos(ang)
		draw_line(pivot, tip, Color(0.82, 0.84, 0.9), 12.0)
		draw_line(pivot, tip, Color(1, 1, 1, 0.5), 4.0)
		var ready := machine._state == "ready"
		var glow := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008) if ready else 0.0
		if ready:
			draw_circle(tip, 34.0, Color(1.0, 0.3, 0.2, 0.25 * glow))
		draw_circle(tip, 24.0, Color(0.85, 0.08, 0.08))
		draw_circle(tip + Vector2(-7, -7), 8.0, Color(1, 0.6, 0.6, 0.8))
		draw_circle(pivot, 10.0, Color(0.3, 0.3, 0.32))
