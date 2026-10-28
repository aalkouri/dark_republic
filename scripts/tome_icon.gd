class_name TomeIcon
extends Control
## A tome drawn in code: a closed leather book in the tome's cover colour, gilded corners, a
## page edge and its emblem (a SkillIcon glyph) stamped in gold on the cover. Each tome's glyph
## and cover colour live in data/upgrades.json ("icon": {"glyph", "cover"}).

var glyph := "book"
var cover := Color(0.45, 0.2, 0.12)
var _emblem: SkillIcon


static func create(icon: Dictionary) -> TomeIcon:
	var t := TomeIcon.new()
	t.set_icon(icon)
	return t


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem = SkillIcon.new()
	_emblem.color = Color(1.0, 0.82, 0.38)
	add_child(_emblem)
	resized.connect(_layout)


func set_icon(icon: Dictionary) -> void:
	glyph = str(icon.get("glyph", "book"))
	cover = Color.html(str(icon.get("cover", "#73331f")))
	_emblem.kind = glyph
	_emblem.queue_redraw()
	queue_redraw()


func _layout() -> void:
	var s := minf(size.x, size.y) / 64.0
	var o := (size - Vector2(64, 64) * s) * 0.5
	_emblem.position = o + Vector2(20.5, 15) * s
	_emblem.size = Vector2(28, 28) * s


func _draw() -> void:
	var s := minf(size.x, size.y) / 64.0
	draw_set_transform((size - Vector2(64, 64) * s) * 0.5, 0.0, Vector2(s, s))
	var gold := Color(0.95, 0.75, 0.32)
	var dark := cover.darkened(0.5)
	# shadow, pages (right + bottom edge), cover, spine
	draw_rect(Rect2(12, 8, 46, 54), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(14, 6, 42, 52), Color(0.9, 0.85, 0.72))
	for k in 4:
		draw_line(Vector2(16, 50 + k * 2), Vector2(55, 50 + k * 2), Color(0.7, 0.64, 0.52), 1)
	draw_rect(Rect2(10, 4, 42, 50), cover)
	draw_rect(Rect2(10, 4, 42, 50), dark, false, 2)
	draw_rect(Rect2(10, 4, 7, 50), dark)
	for y in [10.0, 46.0]:
		draw_line(Vector2(10, y), Vector2(17, y), gold, 2)
	# inner gilt frame + corner guards
	draw_rect(Rect2(19, 9, 29, 40), Color(gold, 0.55), false, 1.5)
	for c in [Vector2(52, 4), Vector2(52, 54)]:
		var dy := 8.0 if c.y < 10 else -8.0
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(-8, 0), c + Vector2(0, dy)]), gold)
	# soft highlight along the top
	draw_rect(Rect2(17, 5, 34, 3), Color(1, 1, 1, 0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
