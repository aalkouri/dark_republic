class_name ForgeMenu
extends Control
## The Forge (from the character select: click a weapon that's ready to forge). Shows the weapon
## big on the left, the shards the next level costs (lit when you have enough of that kind), and
## on the right what the forge will do: its stats now and after. "Forge Weapon" spends the
## shards and raises it a level (up to Forge.MAX_LEVEL), with a hammer clang and sparks.

signal forged(style: String, level: int)
signal closed

const SOUND := "res://audio/ui/forge_hammer.wav"

var style := "fire"
var weapon: Dictionary = {}          # KitDB weapon: name, icon...
var _icon: UpgradeIcon
var _level: Label
var _cost_row: HBoxContainer
var _now: Label
var _next: Label
var _btn: Button
var _buy: Button                     # buy the shards you're missing with coins
var _buy_label: Label
var _sparks: Array = []              # [pos, vel, life]
var _flash := 0.0
var _sfx: AudioStreamPlayer
var _spark_layer: Control
var _panel: Control


func setup(p_style: String, p_weapon: Dictionary) -> void:
	style = p_style
	weapon = p_weapon


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := Panel.new()
	var size_p := Vector2(860, 470)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -size_p.x * 0.5
	panel.offset_right = size_p.x * 0.5
	panel.offset_top = -size_p.y * 0.5
	panel.offset_bottom = size_p.y * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.06, 0.05, 0.98)
	sb.border_color = Color(1.0, 0.55, 0.2)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(1.0, 0.45, 0.1, 0.35)
	sb.shadow_size = 16
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var title := _lbl(tr("THE FORGE"), 36, Color(1.0, 0.7, 0.3))
	title.position = Vector2(0, 16)
	title.size = Vector2(size_p.x, 46)
	panel.add_child(title)
	# Left: the weapon
	var ic: Dictionary = weapon.get("icon", {})
	_icon = UpgradeIcon.create(ic, "weapon")
	_icon.position = Vector2(70, 92)
	_icon.size = Vector2(170, 170)
	_icon.custom_minimum_size = Vector2(170, 170)
	_icon.pivot_offset = Vector2(85, 85)
	panel.add_child(_icon)
	var name := _lbl(str(weapon.get("name", "")), 26, Color.html(str(ic.get("tint", "#ffb020"))).lerp(Color.WHITE, 0.35))
	name.position = Vector2(20, 272)
	name.size = Vector2(270, 34)
	panel.add_child(name)
	_level = _lbl("", 20, Color(1.0, 0.85, 0.5))
	_level.position = Vector2(20, 306)
	_level.size = Vector2(270, 28)
	panel.add_child(_level)
	# Cost under the weapon
	_cost_row = HBoxContainer.new()
	_cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cost_row.add_theme_constant_override("separation", 6)
	_cost_row.position = Vector2(20, 342)
	_cost_row.size = Vector2(270, 36)
	panel.add_child(_cost_row)
	# Right: what the forge does
	var head_now := _lbl(tr("Now"), 20, Color(0.75, 0.7, 0.65))
	head_now.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head_now.position = Vector2(330, 90)
	head_now.size = Vector2(240, 28)
	panel.add_child(head_now)
	_now = _lbl("", 19, Color(0.85, 0.8, 0.75))
	_now.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_now.position = Vector2(330, 122)
	_now.size = Vector2(240, 200)
	_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_now)
	var arrow := _lbl(">", 34, Color(1.0, 0.6, 0.25))
	arrow.position = Vector2(560, 150)
	arrow.size = Vector2(40, 40)
	panel.add_child(arrow)
	var head_next := _lbl(tr("After forging"), 20, Color(0.55, 1.0, 0.55))
	head_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head_next.position = Vector2(610, 90)
	head_next.size = Vector2(240, 28)
	panel.add_child(head_next)
	_next = _lbl("", 19, Color(0.7, 1.0, 0.7))
	_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_next.position = Vector2(610, 122)
	_next.size = Vector2(230, 200)
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_next)
	# Short on shards? Buy the missing ones with coins
	_buy = Button.new()
	_buy.text = ""
	_buy.position = Vector2(30, 386)
	_buy.size = Vector2(250, 50)
	_buy.pressed.connect(buy_missing)
	panel.add_child(_buy)
	var buy_row := HBoxContainer.new()
	buy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	buy_row.add_theme_constant_override("separation", 6)
	buy_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	buy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buy.add_child(buy_row)
	_buy_label = _lbl("", 17, Color(1.0, 0.88, 0.5))
	buy_row.add_child(_buy_label)
	var coin := CoinIcon.new()
	coin.custom_minimum_size = Vector2(22, 22)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy_row.add_child(coin)
	_btn = Button.new()
	_btn.text = tr("Forge Weapon")
	_btn.add_theme_font_size_override("font_size", 26)
	_btn.position = Vector2(440, 384)
	_btn.size = Vector2(260, 58)
	_btn.pressed.connect(do_forge)
	panel.add_child(_btn)
	var close := Button.new()
	close.text = tr("Close")
	close.add_theme_font_size_override("font_size", 20)
	close.position = Vector2(720, 392)
	close.size = Vector2(110, 44)
	close.pressed.connect(func(): closed.emit())
	panel.add_child(close)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = Settings.SFX_BUS
	if ResourceLoader.exists(SOUND):
		_sfx.stream = load(SOUND)
	add_child(_sfx)
	_spark_layer = _Sparks.new()
	_spark_layer.menu = self
	_spark_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_spark_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_spark_layer)
	_panel = panel
	_refresh()
	_btn.grab_focus()


func _lbl(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _refresh() -> void:
	var lvl := Forge.level_of(style)
	var maxed := lvl >= Forge.MAX_LEVEL
	_level.text = tr("Forge level %d / %d") % [lvl, Forge.MAX_LEVEL] if lvl > 0 else tr("Not forged yet")
	_now.text = "\n".join(Forge.describe(style, lvl))
	_next.text = tr("Max level") if maxed else "\n".join(Forge.describe(style, lvl + 1))
	for c in _cost_row.get_children():
		c.queue_free()
	if not maxed:
		var cost := Forge.next_cost(style)
		for kind in cost:
			var have := int(Wallet.shards.get(kind, 0))
			var need := int(cost[kind])
			var ic := ShardIcon.new()
			ic.kind = kind
			ic.custom_minimum_size = Vector2(24, 32)
			ic.modulate = Color.WHITE if have >= need else Color(0.45, 0.45, 0.45, 0.7)
			_cost_row.add_child(ic)
			var l := _lbl("%d/%d" % [have, need], 17, ShardIcon.COLORS[kind][2] if have >= need else Color(0.6, 0.55, 0.55))
			_cost_row.add_child(l)
	_btn.disabled = maxed or not Forge.can_afford(style)
	var short := missing()
	var n := 0
	for kind in short:
		n += int(short[kind])
	_buy.visible = n > 0
	_buy_label.text = tr("Buy %d missing shards: %s") % [n, Wallet.fmt(n * Wallet.SHARD_PRICE)] if n != 1 else tr("Buy 1 missing shard: %s") % Wallet.fmt(Wallet.SHARD_PRICE)
	_buy.disabled = Wallet.coins < n * Wallet.SHARD_PRICE
	_btn.text = tr("Max level") if maxed else tr("Forge Weapon")


## The shards the next level still needs that you don't have: {kind: count}.
func missing() -> Dictionary:
	var out := {}
	var cost := Forge.next_cost(style)
	for kind in cost:
		var short := int(cost[kind]) - int(Wallet.shards.get(kind, 0))
		if short > 0:
			out[kind] = short
	return out


## Buy every missing shard for the next level with coins (Wallet.SHARD_PRICE each).
func buy_missing() -> bool:
	var short := missing()
	var n := 0
	for kind in short:
		n += int(short[kind])
	if n <= 0 or Wallet.coins < n * Wallet.SHARD_PRICE:
		return false
	for kind in short:
		Wallet.buy_shards(kind, int(short[kind]))
	_refresh()
	forged.emit(style, Forge.level_of(style))   # the character select refreshes its shard row
	return true


## Spend the shards and raise the weapon a level.
func do_forge() -> bool:
	if not Forge.forge(style):
		return false
	_flash = 1.0
	if _sfx.stream != null:
		_sfx.play()
	var c := _icon.position + _icon.size * 0.5
	for k in 40:
		var a := randf() * TAU
		_sparks.append([c, Vector2(cos(a), sin(a)) * randf_range(120.0, 420.0), randf_range(0.4, 0.9)])
	_refresh()
	forged.emit(style, Forge.level_of(style))
	return true


func _process(dt: float) -> void:
	_flash = maxf(0.0, _flash - dt * 2.0)
	_icon.scale = Vector2.ONE * (1.0 + 0.18 * _flash)
	_icon.modulate = Color(1.0 + _flash, 1.0 + _flash * 0.7, 1.0 + _flash * 0.3)
	for k in range(_sparks.size() - 1, -1, -1):
		var s: Array = _sparks[k]
		s[0] += s[1] * dt
		s[1] = s[1] * (1.0 - 2.5 * dt) + Vector2(0, 500.0) * dt
		s[2] -= dt
		if s[2] <= 0.0:
			_sparks.remove_at(k)
	_spark_layer.queue_redraw()


class _Sparks extends Control:
	var menu: ForgeMenu

	func _draw() -> void:
		var origin := menu._panel.position
		for s in menu._sparks:
			var p: Vector2 = origin + s[0]
			draw_circle(p, 3.0, Color(1.0, 0.75, 0.3, clampf(s[2] * 1.5, 0.0, 1.0)))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
