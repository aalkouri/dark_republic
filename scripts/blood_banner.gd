class_name BloodBanner
extends Control
## Big blood-red title in the middle of the screen with a thick black outline and blood
## dripping off the letters (drawn in code, Cinzel Black). Slams in, the drips run down,
## then it fades away.  show_text("SURVIVE")

const FONT_SIZE := 96
const HOLD := 3.2          # seconds fully visible
const FADE := 0.9
const BLOOD := Color(0.62, 0.0, 0.02)
const BLOOD_HI := Color(0.85, 0.05, 0.06)
const OUTLINE := 16

var text := ""
var _t := -1.0
var _font: FontVariation
var _drips: Array = []   # [x offset (0..1 of text width), length px, width px, delay s]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var base := load("res://fonts/Cinzel.ttf") as FontFile
	_font = FontVariation.new()
	_font.base_font = base
	_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 900}


func show_text(t: String) -> void:
	text = tr(t)
	_t = 0.0
	visible = true
	_drips.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(t)
	for k in 14:
		_drips.append([rng.randf_range(0.03, 0.97), rng.randf_range(18.0, 70.0), rng.randf_range(5.0, 11.0), rng.randf_range(0.15, 1.1)])


func is_showing() -> bool:
	return visible and _t >= 0.0


func _process(dt: float) -> void:
	if _t < 0.0:
		return
	_t += dt
	if _t > HOLD + FADE:
		_t = -1.0
		visible = false
	queue_redraw()


func _draw() -> void:
	if _t < 0.0 or text == "":
		return
	var alpha := 1.0 - clampf((_t - HOLD) / FADE, 0.0, 1.0)
	# Slam in: starts big, settles to 1.0 in 0.25 s
	var k := clampf(_t / 0.25, 0.0, 1.0)
	var s := lerpf(1.35, 1.0, 1.0 - (1.0 - k) * (1.0 - k))
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var asc := _font.get_ascent(FONT_SIZE)
	var c := size * 0.5 + Vector2(0, -size.y * 0.08)
	draw_set_transform(c, 0.0, Vector2(s, s))
	var base := Vector2(-tw * 0.5, asc * 0.35)   # baseline, text centred on c
	# Drips run down from the bottom of the letters (behind the text so they hang off it)
	for d in _drips:
		var grow := clampf((_t - float(d[3])) / 1.4, 0.0, 1.0)
		if grow <= 0.0:
			continue
		var x: float = base.x + float(d[0]) * tw
		var top := base.y - 6.0
		var len: float = float(d[1]) * (1.0 - (1.0 - grow) * (1.0 - grow))
		var w: float = d[2]
		draw_rect(Rect2(x - w * 0.5 - 3.0, top, w + 6.0, len + 3.0), Color(0, 0, 0, alpha))
		draw_circle(Vector2(x, top + len), w * 0.5 + 4.0, Color(0, 0, 0, alpha))
		draw_rect(Rect2(x - w * 0.5, top, w, len), Color(BLOOD, alpha))
		draw_circle(Vector2(x, top + len), w * 0.5 + 1.0, Color(BLOOD, alpha))
		draw_circle(Vector2(x - w * 0.15, top + len - w * 0.2), w * 0.18, Color(1, 0.5, 0.5, 0.5 * alpha))
	# Black outline, a dark under-layer for depth, then the blood fill with a brighter top
	draw_string_outline(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, OUTLINE, Color(0, 0, 0, alpha))
	draw_string(_font, base + Vector2(0, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.3, 0.0, 0.0, alpha))
	draw_string(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(BLOOD, alpha))
	draw_string(_font, base + Vector2(0, -2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(BLOOD_HI, alpha * 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
