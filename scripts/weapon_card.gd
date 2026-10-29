class_name WeaponCard
extends Control
## A collectible-style game card for a character's weapon: gold frame, the character's name
## on a banner, the weapon's art in a glowing window, its name, what it does, and a ribbon.
## Used by UnlockReveal when you buy a character.

const SIZE := Vector2(330, 470)
const GOLD := Color(0.95, 0.75, 0.3)

var _font: Font
var _font_bold: Font


static func create(char_name: String, weapon: Dictionary, ribbon: String, font: Font, font_bold: Font) -> WeaponCard:
	var c := WeaponCard.new()
	c._font = font
	c._font_bold = font_bold
	c._build(char_name, weapon, ribbon)
	return c


func _box(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	return sb


func _label(text: String, size: int, col: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	if bold and _font_bold:
		l.add_theme_font_override("font", _font_bold)
	elif _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build(char_name: String, weapon: Dictionary, ribbon: String) -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon: Dictionary = weapon.get("icon", {})
	var accent := Color.html(str(icon.get("tint", "#ffb020")))
	var cover := Color.html(str(icon.get("cover", "#3a2010")))

	# Frame: dark outer edge, gold border, an inner gold hairline
	var outer := Panel.new()
	outer.add_theme_stylebox_override("panel", _box(Color(0.06, 0.04, 0.03), GOLD, 6, 18))
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(outer)
	var inner := Panel.new()
	var ib := _box(Color(0.12, 0.08, 0.05), Color(GOLD, 0.45), 2, 12)
	inner.add_theme_stylebox_override("panel", ib)
	inner.position = Vector2(14, 14)
	inner.size = SIZE - Vector2(28, 28)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inner)

	var v := VBoxContainer.new()
	v.position = Vector2(24, 22)
	v.size = SIZE - Vector2(48, 44)
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	# Character banner
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", _box(cover.darkened(0.2), GOLD, 2, 8))
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(_label(char_name.to_upper(), 16, Color(1.0, 0.92, 0.75), true))
	v.add_child(banner)
	# Art window: the weapon's emblem on a glowing field in its colours
	var art := Panel.new()
	var ab := _box(cover.darkened(0.45), Color(GOLD, 0.8), 3, 10)
	art.add_theme_stylebox_override("panel", ab)
	art.custom_minimum_size = Vector2(0, 200)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	var glow := _Glow.new()
	glow.color = accent
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.add_child(glow)
	var emblem := UpgradeIcon.create(icon, "weapon")
	emblem.custom_minimum_size = Vector2(170, 170)
	emblem.set_anchors_preset(Control.PRESET_CENTER)
	emblem.size = Vector2(170, 170)
	emblem.position = Vector2(-85, -85)
	art.add_child(emblem)
	# Name, text, ribbon
	v.add_child(_label(str(weapon.get("name", "")), 28, accent.lerp(Color.WHITE, 0.35), true))
	var desc := _label(str(weapon.get("desc", "")), 15, Color(0.9, 0.85, 0.76))
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)
	var rib := PanelContainer.new()
	rib.add_theme_stylebox_override("panel", _box(Color(0.35, 0.22, 0.05), GOLD, 2, 6))
	rib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rib.add_child(_label(ribbon, 14, Color(1.0, 0.86, 0.45), true))
	v.add_child(rib)


## Soft radial glow + slowly turning light rays behind the emblem.
class _Glow extends Control:
	var color := Color.WHITE
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.62
		for k in 12:
			var a := TAU * k / 12.0 + _t * 0.4
			var p := PackedVector2Array([c, c + Vector2(cos(a - 0.09), sin(a - 0.09)) * r * 1.4, c + Vector2(cos(a + 0.09), sin(a + 0.09)) * r * 1.4])
			draw_colored_polygon(p, Color(color, 0.10))
		for i in 6:
			draw_circle(c, r * (1.0 - i * 0.15), Color(color, 0.07))
