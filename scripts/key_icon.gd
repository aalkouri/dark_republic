class_name KeyIcon
extends Control
## A chest key drawn in code, in its tier's metal (Bronze, Silver, Gold): a round bow with a
## hole, a shaft and two teeth, lying diagonally, with a shine. Used on the key counter, the
## level-up Convert button and the key pop-up.

var tier := 0
var dim := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_key(self, size * 0.5, minf(size.x, size.y) * 0.5, tier, dim)


static func draw_key(ci: CanvasItem, c: Vector2, r: float, p_tier: int, p_dim := false) -> void:
	var metal: Color = Chest.TIER_COLORS[clampi(p_tier, 0, 2)]
	if p_dim:
		metal = metal.darkened(0.55)
	var dark := metal.darkened(0.45)
	var light := metal.lightened(0.45)
	var d := Vector2(1, 1).normalized()          # along the shaft (bow top-left, teeth bottom-right)
	var n := d.orthogonal()
	var bow := c - d * r * 0.42
	var tip := c + d * r * 0.85
	var w := maxf(1.5, r * 0.17)
	# shadow
	ci.draw_line(bow + Vector2(1.5, 2), tip + Vector2(1.5, 2), Color(0, 0, 0, 0.35), w)
	# shaft
	ci.draw_line(bow, tip, dark, w + 2.0)
	ci.draw_line(bow, tip, metal, w)
	# teeth
	for k in 2:
		var at := tip - d * r * (0.12 + k * 0.28)
		var pts := PackedVector2Array([at - d * r * 0.08, at + d * r * 0.08, at + d * r * 0.08 + n * r * 0.3, at - d * r * 0.08 + n * r * 0.3])
		ci.draw_colored_polygon(pts, metal)
		ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), dark, 1.0)
	# bow: a ring with a hole
	ci.draw_circle(bow, r * 0.42, dark)
	ci.draw_circle(bow, r * 0.36, metal)
	ci.draw_circle(bow, r * 0.16, Color(0.06, 0.05, 0.05, 0.9))
	ci.draw_arc(bow, r * 0.27, PI * 1.05, PI * 1.6, 10, light, maxf(1.0, r * 0.07))
	# shine along the shaft
	ci.draw_line(bow + d * r * 0.4 - n * w * 0.25, tip - d * r * 0.2 - n * w * 0.25, Color(light, 0.7), maxf(1.0, w * 0.3))
