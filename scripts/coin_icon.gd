class_name CoinIcon
extends Control
## A gold coin drawn in code: bevelled rim, embossed flame, a moving glint. `spin` turns it
## around its vertical axis (0..1 = a full turn) by squashing it horizontally, showing the
## darker edge as it turns side-on.

var spin := 0.0
var glint := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var sx := cos(spin * TAU)
	var w := maxf(absf(sx), 0.12)
	draw_set_transform(c, 0.0, Vector2(w, 1.0))
	# Edge thickness shows when turned
	var edge := (1.0 - absf(sx)) * r * 0.18 * signf(sx if sx != 0.0 else 1.0)
	draw_circle(Vector2(edge / w, 0), r, Color(0.55, 0.36, 0.06))
	draw_circle(Vector2.ZERO, r, Color(0.78, 0.55, 0.1))                 # rim
	draw_circle(Vector2.ZERO, r * 0.84, Color(1.0, 0.8, 0.22))            # face
	draw_circle(Vector2(-r * 0.12, -r * 0.14), r * 0.62, Color(1.0, 0.88, 0.4, 0.55))   # sheen
	draw_arc(Vector2.ZERO, r * 0.84, 0.0, TAU, 32, Color(0.62, 0.4, 0.06), maxf(1.0, r * 0.07))
	if absf(sx) > 0.25:
		# Embossed flame
		var fl := signf(sx)
		var outer := PackedVector2Array()
		for q in [Vector2(0, -0.58), Vector2(0.3, -0.08), Vector2(0.28, 0.28), Vector2(0, 0.46), Vector2(-0.28, 0.28), Vector2(-0.32, -0.02), Vector2(-0.12, -0.2)]:
			outer.append(Vector2(q.x * fl, q.y) * r)
		draw_colored_polygon(outer, Color(0.72, 0.46, 0.05))
		var inner := PackedVector2Array()
		for q in [Vector2(0, -0.16), Vector2(0.16, 0.2), Vector2(0, 0.36), Vector2(-0.16, 0.2)]:
			inner.append(Vector2(q.x * fl, q.y) * r)
		draw_colored_polygon(inner, Color(1.0, 0.86, 0.35))
	# Glint sweeping across
	var gx := (fmod(glint, 1.0) * 2.4 - 1.2) * r
	if absf(gx) < r * 0.8:
		draw_line(Vector2(gx - r * 0.25, r * 0.5), Vector2(gx + r * 0.25, -r * 0.5), Color(1, 1, 0.9, 0.7), maxf(1.0, r * 0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
