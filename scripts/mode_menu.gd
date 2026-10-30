class_name ModeMenu
extends Control
## The title's Play submenu: three mode cards that burst out of the Play button.
##
## Reveal: a burning fuse races right from Play, and each card drops in behind it with a flip,
## a flash and a puff of embers (staggered). Hover lifts a card and lights its border.
## Classic - survive 10 minutes. Quickplay - random character, random unlocked map, straight in.
## Unrelenting - no time limit; the clock counts up and it keeps getting harder.

signal chosen(mode: String)
signal cancelled

const MODES := [
	{"id": "classic", "name": "Classic", "desc": "Choose your champion and map. Survive 10 minutes.", "glyph": "hourglass", "color": Color(1.0, 0.5, 0.18)},
	{"id": "quickplay", "name": "Quickplay", "desc": "Random character, random unlocked map. Straight into the fight.", "glyph": "bolt", "color": Color(1.0, 0.78, 0.25)},
	{"id": "unrelenting", "name": "Unrelenting", "desc": "No time limit. Endless enemies that keep getting deadlier. No upgrade caps.", "glyph": "skull", "color": Color(0.85, 0.22, 0.2)},
]
const CARD := Vector2(264, 350)
const GAP := 22.0

var cards: Array[Button] = []
var _font: Font
var _font_bold: Font
var _fuse: Line2D
var _fuse_head: CPUParticles2D
var _origin := Vector2.ZERO      # where the fuse starts (right edge of the Play button)
var _hint: Label
var _open := false


static func create(font: Font, font_bold: Font) -> ModeMenu:
	var m := ModeMenu.new()
	m._font = font
	m._font_bold = font_bold
	return m


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuse = Line2D.new()
	_fuse.width = 4.0
	_fuse.default_color = Color(1.0, 0.6, 0.2)
	_fuse.gradient = Gradient.new()
	_fuse.gradient.set_color(0, Color(1.0, 0.3, 0.05, 0.0))
	_fuse.gradient.set_color(1, Color(1.0, 0.85, 0.45, 1.0))
	_fuse.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_fuse.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_fuse)
	_fuse_head = _embers(26, 0.5)
	add_child(_fuse_head)
	for i in MODES.size():
		cards.append(_card(MODES[i]))
	for i in cards.size():
		var b := cards[i]
		b.focus_neighbor_left = cards[maxi(0, i - 1)].get_path() if i > 0 else NodePath()
	_hint = Label.new()
	_hint.text = "Esc: back"
	_hint.add_theme_font_override("font", _font)
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.85, 0.78, 0.68, 0.6))
	_hint.modulate.a = 0.0
	add_child(_hint)
	visible = false


func is_open() -> bool:
	return _open


## Burst the cards out from `from` (the right-middle of the Play button, in this control's space).
func open(from: Vector2) -> void:
	_open = true
	visible = true
	_origin = from
	var base := Vector2(from.x + 60.0, from.y - CARD.y * 0.5 + 40.0)
	var end_x := base.x + (CARD.x + GAP) * cards.size() - GAP
	# The fuse: a burning line racing right, embers at its head
	_fuse.clear_points()
	_fuse.add_point(from)
	_fuse.add_point(from)
	_fuse.modulate.a = 1.0
	_fuse_head.position = from
	_fuse_head.emitting = true
	var tw := create_tween()
	tw.tween_method(func(x: float):
		_fuse.set_point_position(1, Vector2(x, from.y))
		_fuse_head.position = Vector2(x, from.y), from.x, end_x, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(func(): _fuse_head.emitting = false)
	tw.tween_property(_fuse, "modulate:a", 0.25, 0.5)
	for i in cards.size():
		var b := cards[i]
		var at := base + Vector2((CARD.x + GAP) * i, 0)
		b.position = at + Vector2(0, -60)
		b.pivot_offset = CARD * 0.5
		b.scale = Vector2(0.0, 1.15)
		b.rotation = deg_to_rad(-8.0 + 8.0 * i)
		b.modulate = Color(3.0, 2.2, 1.4, 0.0)
		b.disabled = true
		var delay := 0.08 + 0.11 * i
		var ct := create_tween().set_parallel(true)
		ct.tween_property(b, "position", at, 0.42).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ct.tween_property(b, "scale", Vector2.ONE, 0.36).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ct.tween_property(b, "rotation", 0.0, 0.4).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ct.tween_property(b, "modulate", Color.WHITE, 0.5).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ct.chain().tween_callback(func(): b.disabled = false)
		get_tree().create_timer(delay + 0.12, true).timeout.connect(func(): _burst(at + CARD * 0.5, (MODES[i]["color"] as Color)))
	_hint.position = Vector2(base.x, base.y + CARD.y + 18)
	create_tween().tween_property(_hint, "modulate:a", 1.0, 0.4).set_delay(0.5)
	get_tree().create_timer(0.5, true).timeout.connect(func(): if _open: cards[0].grab_focus())   # Classic


## Fold the cards back toward the Play button.
func close() -> void:
	if not _open:
		return
	_open = false
	var tw := create_tween().set_parallel(true)
	for i in cards.size():
		var b := cards[i]
		b.disabled = true
		var d := 0.04 * (cards.size() - 1 - i)
		tw.tween_property(b, "scale", Vector2(0.0, 1.1), 0.18).set_delay(d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(b, "modulate:a", 0.0, 0.18).set_delay(d)
	tw.tween_property(_fuse, "modulate:a", 0.0, 0.2)
	tw.tween_property(_hint, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(func(): if not _open: visible = false)
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()


# ------------------------------------------------------------------ building

func _card(m: Dictionary) -> Button:
	var col: Color = m["color"]
	var b := Button.new()
	b.custom_minimum_size = CARD
	b.size = CARD
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("mode", m["id"])
	b.add_theme_stylebox_override("normal", _style(col.darkened(0.35), 2, 0.0))
	b.add_theme_stylebox_override("disabled", _style(col.darkened(0.35), 2, 0.0))
	b.add_theme_stylebox_override("hover", _style(col, 4, 0.5))
	b.add_theme_stylebox_override("focus", _style(col.lightened(0.15), 4, 0.6))
	b.add_theme_stylebox_override("pressed", _style(Color(1, 0.95, 0.8), 5, 0.8))
	add_child(b)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 18
	v.offset_right = -18
	v.offset_top = 22
	v.offset_bottom = -18
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var em := _Emblem.new()
	em.glyph = m["glyph"]
	em.color = col
	em.custom_minimum_size = Vector2(0, 130)
	v.add_child(em)
	var title := _text(str(m["name"]), 30, col.lerp(Color.WHITE, 0.35), true)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_fit(title, CARD.x - 40.0)
	v.add_child(title)
	var line := ColorRect.new()
	line.color = Color(col, 0.55)
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	var desc := _text(m["desc"], 16, Color(0.9, 0.85, 0.78))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)
	b.mouse_entered.connect(func():
		if not b.disabled:
			b.grab_focus())
	b.focus_entered.connect(func(): _lift(b, true))
	b.focus_exited.connect(func(): _lift(b, false))
	b.pressed.connect(func():
		var tw := create_tween()
		tw.tween_property(b, "scale", Vector2.ONE * 1.08, 0.07)
		tw.tween_property(b, "scale", Vector2.ONE, 0.12)
		chosen.emit(str(b.get_meta("mode"))))
	return b


func _text(t: String, size: int, col: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = t if not bold else tr(t)
	if bold:
		l.text = l.text.to_upper()
	l.add_theme_font_override("font", _font_bold if bold and _font_bold else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Shrink a one-line label's font until it fits `width` (long names, other languages).
func _fit(l: Label, width: float) -> void:
	var f: Font = l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	while fs > 14 and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	l.add_theme_font_size_override("font_size", fs)


func _style(border: Color, width: int, glow: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.035, 0.025, 0.93).lerp(border.darkened(0.7), glow * 0.35)
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(border, 0.45 * glow)
	sb.shadow_size = int(18 * glow)
	return sb


func _lift(b: Button, up: bool) -> void:
	if b.disabled and up:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(b, "scale", Vector2.ONE * (1.05 if up else 1.0), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	b.z_index = 1 if up else 0


func _embers(n: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = n
	p.lifetime = life
	p.emitting = false
	p.spread = 180.0
	p.gravity = Vector2(0, -60)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 110.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 4.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	g.set_color(1, Color(0.9, 0.2, 0.0, 0.0))
	p.color_ramp = g
	return p


## A flash ring and a spray of embers where a card lands.
func _burst(at: Vector2, col: Color) -> void:
	var p := _embers(40, 0.8)
	p.one_shot = true
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = CARD * 0.45
	p.position = at
	p.color = col.lerp(Color.WHITE, 0.3)
	add_child(p)
	move_child(p, 0)
	p.emitting = true
	get_tree().create_timer(1.2, true).timeout.connect(p.queue_free)
	var ring := _Ring.new()
	ring.color = col
	ring.position = at
	add_child(ring)
	move_child(ring, 0)


class _Ring extends Node2D:
	var color := Color.WHITE
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		if _t > 0.45:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := _t / 0.45
		draw_arc(Vector2.ZERO, 40.0 + 190.0 * k, 0.0, TAU, 48, Color(color, 0.7 * (1.0 - k)), 6.0 * (1.0 - k) + 1.0)


## The mode's emblem, drawn: a lightning bolt, an hourglass or a horned skull, on a slow glow.
class _Emblem extends Control:
	var glyph := ""
	var color := Color.WHITE
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		var pulse := 0.5 + 0.5 * sin(_t * 2.2)
		for i in 5:
			draw_circle(c, r * (1.0 - i * 0.16), Color(color, 0.05 + 0.03 * pulse))
		draw_arc(c, r * 0.92, 0.0, TAU, 48, Color(color, 0.7), 2.5)
		var s := r * 0.62
		var dark := Color(0.08, 0.04, 0.02)
		match glyph:
			"bolt":
				var pts := PackedVector2Array([Vector2(0.15, -1.0), Vector2(-0.55, 0.12), Vector2(-0.05, 0.12),
					Vector2(-0.25, 1.0), Vector2(0.6, -0.22), Vector2(0.08, -0.22), Vector2(0.4, -1.0)])
				for k in pts.size():
					pts[k] = c + pts[k] * s
				draw_colored_polygon(pts, color.lerp(Color.WHITE, 0.25 * pulse))
				draw_polyline(pts + PackedVector2Array([pts[0]]), dark, 2.0)
			"hourglass":
				var top := PackedVector2Array([c + Vector2(-0.6, -0.9) * s, c + Vector2(0.6, -0.9) * s, c + Vector2(0.06, 0.0) * s, c + Vector2(-0.06, 0.0) * s])
				var bot := PackedVector2Array([c + Vector2(-0.06, 0.0) * s, c + Vector2(0.06, 0.0) * s, c + Vector2(0.6, 0.9) * s, c + Vector2(-0.6, 0.9) * s])
				draw_colored_polygon(top, Color(color, 0.35))
				draw_colored_polygon(bot, Color(color, 0.35))
				var sand := 0.55 + 0.25 * sin(_t * 0.9)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-0.6 * sand, 0.9 - 0.7 * sand) * s, c + Vector2(0.6 * sand, 0.9 - 0.7 * sand) * s, c + Vector2(0.6, 0.9) * s, c + Vector2(-0.6, 0.9) * s]), color)
				draw_line(c + Vector2(0, -0.1) * s, c + Vector2(0, 0.5) * s, Color(color, 0.8), 2.0)
				draw_polyline(top + PackedVector2Array([top[0]]), color.lerp(Color.WHITE, 0.3), 2.5)
				draw_polyline(bot + PackedVector2Array([bot[0]]), color.lerp(Color.WHITE, 0.3), 2.5)
				draw_line(c + Vector2(-0.75, -0.95) * s, c + Vector2(0.75, -0.95) * s, color.lerp(Color.WHITE, 0.3), 5.0)
				draw_line(c + Vector2(-0.75, 0.95) * s, c + Vector2(0.75, 0.95) * s, color.lerp(Color.WHITE, 0.3), 5.0)
			"skull":
				var bone := Color(0.93, 0.88, 0.8)
				# horns
				for side in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([c + Vector2(0.45 * side, -0.45) * s, c + Vector2(0.95 * side, -1.05) * s, c + Vector2(0.75 * side, -0.25) * s]), color)
				draw_circle(c + Vector2(0, -0.15) * s, s * 0.62, bone)
				draw_rect(Rect2(c + Vector2(-0.38, 0.2) * s, Vector2(0.76, 0.5) * s), bone)
				for side in [-1.0, 1.0]:
					draw_circle(c + Vector2(0.24 * side, -0.12) * s, s * 0.17, dark)
					draw_circle(c + Vector2(0.24 * side, -0.12) * s, s * 0.06, Color(color.lerp(Color.WHITE, 0.4), 0.6 + 0.4 * pulse))
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.08) * s, c + Vector2(-0.08, 0.24) * s, c + Vector2(0.08, 0.24) * s]), dark)
				for k in 4:
					var x := -0.27 + 0.18 * k
					draw_line(c + Vector2(x + 0.09, 0.42) * s, c + Vector2(x + 0.09, 0.7) * s, dark, 2.0)
