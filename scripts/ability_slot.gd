class_name AbilitySlot
extends Control
## One slot on the ability bar: procedural icon, key hint, draining cooldown shade + seconds,
## yellow outline for the ultimate, and a flash when the ability comes off cooldown.

signal activated

enum Icon { METEOR, SHOCKWAVE, INFERNO }

const SIZE := 78.0

var icon := Icon.METEOR
var key_text := "1"
var is_ult := false
var fraction := 0.0        # 0 = ready, 1 = just cast
var seconds_left := 0.0
var _ready_flash := 0.0
var _was_ready := true
var _time := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_cooldown(frac: float, secs: float) -> void:
	var ready := frac <= 0.0
	if ready and not _was_ready:
		_ready_flash = 1.0
	_was_ready = ready
	fraction = frac
	seconds_left = secs


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit()
		accept_event()


func _process(dt: float) -> void:
	_time += dt
	_ready_flash = maxf(0.0, _ready_flash - dt * 2.0)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var ready := fraction <= 0.0

	# Background
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.05, 0.05, 0.85)
	bg.set_corner_radius_all(10)
	draw_style_box(bg, r)

	# Icon
	var c := size * 0.5
	match icon:
		Icon.METEOR:
			_icon_meteor(c)
		Icon.SHOCKWAVE:
			_icon_shockwave(c)
		Icon.INFERNO:
			_icon_inferno(c)

	# Cooldown: dark fill that drains top-down, plus a radial "clock" edge and seconds
	if not ready:
		var h := size.y * fraction
		var shade := StyleBoxFlat.new()
		shade.bg_color = Color(0, 0, 0, 0.62)
		shade.set_corner_radius_all(10)
		draw_style_box(shade, Rect2(Vector2(0, size.y - h), Vector2(size.x, h)))
		var txt := str(ceili(seconds_left)) if seconds_left >= 1.0 else "%.1f" % seconds_left
		var font := get_theme_default_font()
		var fs := 26
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, Vector2(c.x - tw * 0.5, c.y + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color.BLACK)
		draw_string(font, Vector2(c.x - tw * 0.5, c.y + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

	# Border: yellow for the ultimate (pulses when ready), grey otherwise
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.set_corner_radius_all(10)
	if is_ult:
		var glow := 0.75 + 0.25 * sin(_time * 4.0) if ready else 0.55
		border.border_color = Color(1.0, 0.85, 0.15, glow)
		border.set_border_width_all(4)
		if ready:
			border.shadow_color = Color(1.0, 0.8, 0.1, 0.45)
			border.shadow_size = 8
	else:
		border.border_color = Color(1.0, 0.55, 0.2, 0.9) if ready else Color(0.45, 0.4, 0.4, 0.9)
		border.set_border_width_all(2)
	draw_style_box(border, r)

	# "Ready" flash
	if _ready_flash > 0.0:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(1.0, 0.9, 0.6, 0.45 * _ready_flash)
		f.set_corner_radius_all(10)
		draw_style_box(f, r)

	# Key hint
	var font := get_theme_default_font()
	draw_string_outline(font, Vector2(7, 19), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
	draw_string(font, Vector2(7, 19), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))


# ------------------------------------------------------------------ icons

func _icon_meteor(c: Vector2) -> void:
	var head := c + Vector2(8, 8)
	for k in 4:   # fiery trail streaks
		var off := Vector2(-6 + k * 4, 6 - k * 4)
		draw_line(head + off, head + off + Vector2(-26, -26), Color(1.0, 0.45 + k * 0.1, 0.1, 0.5 + k * 0.1), 5.0 - k)
	draw_circle(head, 14, Color(1.0, 0.4, 0.05))
	draw_circle(head + Vector2(-2, -2), 10, Color(1.0, 0.7, 0.2))
	draw_circle(head + Vector2(-4, -4), 5, Color(1.0, 0.95, 0.7))


func _icon_shockwave(c: Vector2) -> void:
	var base := c + Vector2(0, 18)
	for k in 3:
		var rad := 12.0 + k * 11.0
		var col := Color(1.0, 0.75 - k * 0.2, 0.15, 1.0 - k * 0.22)
		draw_arc(base, rad, PI + 0.15, TAU - 0.15, 24, col, 4.0 - k * 0.6)
	draw_line(base + Vector2(-32, 2), base + Vector2(32, 2), Color(0.6, 0.25, 0.1), 3.0)
	draw_circle(base, 5, Color(1.0, 0.9, 0.5))


func _icon_inferno(c: Vector2) -> void:
	var flick := sin(_time * 9.0) * 1.5
	_flame(c + Vector2(0, 6), 26 + flick, 17, Color(0.95, 0.2, 0.05))
	_flame(c + Vector2(-13, 14), 16, 10, Color(1.0, 0.35, 0.05))
	_flame(c + Vector2(13, 14), 16 - flick, 10, Color(1.0, 0.35, 0.05))
	_flame(c + Vector2(0, 12), 17, 10, Color(1.0, 0.65, 0.15))
	_flame(c + Vector2(0, 16), 9, 6, Color(1.0, 0.95, 0.6))


func _flame(base: Vector2, h: float, w: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 14
	for k in n + 1:   # teardrop: round bottom, pointed top
		var a := PI * float(k) / float(n)
		pts.append(base + Vector2(cos(a) * w, sin(a) * w * 0.8))
	pts.append(base + Vector2(-w * 0.9, -h * 0.35))
	pts.append(base + Vector2(-w * 0.2, -h * 0.75))
	pts.append(base + Vector2(0, -h * 1.15))
	pts.append(base + Vector2(w * 0.35, -h * 0.65))
	pts.append(base + Vector2(w * 0.95, -h * 0.3))
	draw_colored_polygon(pts, col)
