class_name UpgradeIcon
extends Control
## Level-up card centrepiece, drawn in code (64x64 design space, scaled). The frame depends on
## the upgrade kind, with a SkillIcon glyph as the emblem:
##   tome   - a closed leather book in the cover colour, gold emblem on the cover
##   weapon - a round bronze medallion, the emblem in its own tint
##   item   - a hexagonal charm, the emblem in its own tint
## Set per upgrade in data/upgrades.json: "icon": {"glyph", "cover", "tint"?}.

var frame := "tome"
var glyph := "book"
var cover := Color(0.45, 0.2, 0.12)
var _emblem: SkillIcon

const GOLD := Color(0.95, 0.75, 0.32)


static func create(icon: Dictionary, kind := "tome") -> UpgradeIcon:
	var t := UpgradeIcon.new()
	t.set_icon(icon, kind)
	return t


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem = SkillIcon.new()
	add_child(_emblem)
	resized.connect(_layout)


func set_icon(icon: Dictionary, kind := "tome") -> void:
	frame = kind if kind in ["tome", "weapon", "item"] else "tome"
	glyph = str(icon.get("glyph", "book"))
	cover = Color.html(str(icon.get("cover", "#73331f")))
	_emblem.kind = glyph
	_emblem.color = Color.html(str(icon["tint"])) if icon.has("tint") else Color(1.0, 0.82, 0.38)
	_layout()
	_emblem.queue_redraw()
	queue_redraw()


func _ready() -> void:
	_layout()   # sizes set before entering the tree don't emit `resized`


func _layout() -> void:
	_emblem.queue_redraw()
	var s := minf(size.x, size.y) / 64.0
	var o := (size - Vector2(64, 64) * s) * 0.5
	match frame:
		"tome":
			_emblem.position = o + Vector2(20.5, 15) * s
			_emblem.size = Vector2(28, 28) * s
		_:
			_emblem.position = o + Vector2(15, 15) * s
			_emblem.size = Vector2(34, 34) * s


func _draw() -> void:
	var s := minf(size.x, size.y) / 64.0
	draw_set_transform((size - Vector2(64, 64) * s) * 0.5, 0.0, Vector2(s, s))
	match frame:
		"tome":
			_draw_tome()
		"weapon":
			_draw_medallion()
		"item":
			_draw_charm()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_tome() -> void:
	var dark := cover.darkened(0.5)
	draw_rect(Rect2(12, 8, 46, 54), Color(0, 0, 0, 0.35))                 # shadow
	draw_rect(Rect2(14, 6, 42, 52), Color(0.9, 0.85, 0.72))                # pages
	for k in 4:
		draw_line(Vector2(16, 50 + k * 2), Vector2(55, 50 + k * 2), Color(0.7, 0.64, 0.52), 1)
	draw_rect(Rect2(10, 4, 42, 50), cover)                                 # cover
	draw_rect(Rect2(10, 4, 42, 50), dark, false, 2)
	draw_rect(Rect2(10, 4, 7, 50), dark)                                   # spine
	for y in [10.0, 46.0]:
		draw_line(Vector2(10, y), Vector2(17, y), GOLD, 2)
	draw_rect(Rect2(19, 9, 29, 40), Color(GOLD, 0.55), false, 1.5)         # gilt frame
	for c in [Vector2(52, 4), Vector2(52, 54)]:                            # corner guards
		var dy := 8.0 if c.y < 10 else -8.0
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(-8, 0), c + Vector2(0, dy)]), GOLD)
	draw_rect(Rect2(17, 5, 34, 3), Color(1, 1, 1, 0.12))


func _draw_medallion() -> void:
	var c := Vector2(32, 32)
	draw_circle(c + Vector2(2, 3), 30, Color(0, 0, 0, 0.35))              # shadow
	draw_circle(c, 30, Color(0.42, 0.27, 0.12))                            # bronze rim
	draw_circle(c, 28, Color(0.72, 0.5, 0.22))
	draw_arc(c, 28, PI * 1.05, PI * 1.6, 16, Color(1.0, 0.85, 0.5, 0.8), 2)  # rim highlight
	for k in 8:                                                             # rivets
		var a := TAU * k / 8.0 + PI / 8.0
		draw_circle(c + Vector2(cos(a), sin(a)) * 26.5, 1.6, Color(0.95, 0.78, 0.42))
	draw_circle(c, 23, cover.darkened(0.55))                                # inner disc
	draw_circle(c, 21, cover.darkened(0.2))
	draw_circle(c + Vector2(-5, -6), 12, Color(cover.lightened(0.25), 0.35))  # sheen
	draw_arc(c, 22, 0, TAU, 40, Color(0, 0, 0, 0.5), 2)


func _draw_charm() -> void:
	var pts := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in 6:
		var a := TAU * k / 6.0 - PI / 2.0
		pts.append(Vector2(32, 32) + Vector2(cos(a), sin(a)) * 30)
		inner.append(Vector2(32, 32) + Vector2(cos(a), sin(a)) * 24)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(2, 3))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	draw_colored_polygon(pts, Color(0.62, 0.62, 0.68))                      # silver frame
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.3, 0.3, 0.36), 2)
	draw_colored_polygon(inner, cover.darkened(0.15))
	draw_polyline(inner + PackedVector2Array([inner[0]]), Color(0.9, 0.9, 0.95, 0.7), 1.5)
	draw_colored_polygon(PackedVector2Array([inner[5], inner[0], inner[1], Vector2(32, 32)]), Color(1, 1, 1, 0.08))
