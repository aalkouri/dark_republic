class_name PowerupIcon
extends Control
## Little 2D icons for the power-ups (the minimap's power-up blips, the HUD's active power-ups):
## a red horseshoe magnet, the stone Fear Idol, a burning 5x, a winged boot, and the NUKE: a fat
## olive bomb with a boxy tail, a red nose band and a yellow-and-black radiation trefoil.
## draw_kind() draws one onto any CanvasItem, so other UI can use them without a node.

var kind := 0
var dim := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_kind(self, kind, size * 0.5, minf(size.x, size.y) * 0.5, dim)


## Draw power-up `kind` centred on `c`, `r` pixels from the centre to the edge.
static func draw_kind(ci: CanvasItem, kind: int, c: Vector2, r: float, dim := 1.0) -> void:
	var k := clampf(dim, 0.0, 1.0)
	match kind:
		PowerupManager.MAGNET:
			var red := Color(0.95, 0.15, 0.12) * k
			ci.draw_arc(c + Vector2(0, -r * 0.1), r * 0.55, PI * 1.0, TAU, 14, Color(red, 1.0), r * 0.36, true)
			for s in [-1.0, 1.0]:
				ci.draw_rect(Rect2(c + Vector2(s * r * 0.55 - r * 0.18, -r * 0.1), Vector2(r * 0.36, r * 0.42)), Color(red, 1.0))
				ci.draw_rect(Rect2(c + Vector2(s * r * 0.55 - r * 0.18, r * 0.32), Vector2(r * 0.36, r * 0.3)), Color(0.85, 0.88, 0.95) * k)
		PowerupManager.FEAR:
			var stone := Color(0.55, 0.53, 0.5) * k
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.75), Vector2(r * 1.2, r * 1.5)), Color(stone, 1.0))
			ci.draw_rect(Rect2(c + Vector2(-r * 0.78, -r * 0.85), Vector2(r * 1.56, r * 0.25)), Color(stone.darkened(0.2), 1.0))
			for s in [-1.0, 1.0]:
				ci.draw_circle(c + Vector2(s * r * 0.27, -r * 0.2), r * 0.17, Color(0.8, 0.35, 1.0) * k)
		PowerupManager.DAMAGE:
			var pts := PackedVector2Array()
			for j in 16:
				var a := TAU * j / 16.0
				var rr := r * (0.95 if j % 2 == 0 else 0.6)
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, Color(1.0, 0.45, 0.08) * k)
			ci.draw_circle(c, r * 0.45, Color(1.0, 0.88, 0.45) * k)
		PowerupManager.SPEED:
			var green := Color(0.3, 0.9, 0.4) * k
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, -r * 0.8), c + Vector2(r * 0.15, -r * 0.8),
				c + Vector2(r * 0.15, r * 0.25), c + Vector2(r * 0.85, r * 0.35), c + Vector2(r * 0.85, r * 0.75),
				c + Vector2(-r * 0.3, r * 0.75)]), Color(green, 1.0))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, -r * 0.5), c + Vector2(-r * 0.95, -r * 0.85),
				c + Vector2(-r * 0.75, -r * 0.35), c + Vector2(-r * 0.95, -r * 0.1), c + Vector2(-r * 0.3, -r * 0.1)]), Color(0.95, 0.95, 1.0) * k)
		PowerupManager.NUKE:
			draw_nuke(ci, c, r, k)


## The NUKE's icon: a little bomb lying nose-right, fins left, with the trefoil on its side.
static func draw_nuke(ci: CanvasItem, c: Vector2, r: float, k := 1.0) -> void:
	var casing := Color(NukeModel.CASING.lightened(0.15) * k, 1.0)
	var tail := Color(NukeModel.TAIL.lightened(0.1) * k, 1.0)
	var outline := Color(0.05, 0.05, 0.03, 0.9)
	var body := c + Vector2(r * 0.12, 0)
	# the fin box behind the body
	var fx := c.x - r * 0.95
	ci.draw_rect(Rect2(Vector2(fx, c.y - r * 0.52), Vector2(r * 0.34, r * 1.04)), tail)
	ci.draw_rect(Rect2(Vector2(fx, c.y - r * 0.52), Vector2(r * 0.34, r * 1.04)), outline, false, maxf(1.0, r * 0.08))
	ci.draw_line(Vector2(fx, c.y), Vector2(fx + r * 0.5, c.y), outline, maxf(1.0, r * 0.08))
	# the fat egg-shaped casing
	var pts := PackedVector2Array()
	for j in 24:
		var a := TAU * j / 24.0
		pts.append(body + Vector2(cos(a) * r * 0.78, sin(a) * r * 0.6))
	ci.draw_colored_polygon(pts, casing)
	pts.append(pts[0])
	ci.draw_polyline(pts, outline, maxf(1.0, r * 0.08), true)
	# the red nose band
	var bx := body.x + r * 0.5
	ci.draw_line(Vector2(bx, body.y - r * 0.44), Vector2(bx, body.y + r * 0.44), Color(0.95, 0.12, 0.08) * k, maxf(1.5, r * 0.16))
	# the trefoil
	draw_trefoil(ci, body + Vector2(-r * 0.1, 0), r * 0.36, k)


## A yellow disc with the black three-bladed radiation sign.
static func draw_trefoil(ci: CanvasItem, c: Vector2, r: float, k := 1.0) -> void:
	var black := Color(0.06, 0.05, 0.02)
	ci.draw_circle(c, r, black)
	ci.draw_circle(c, r * 0.88, Color(NukeModel.TREFOIL_YELLOW * k, 1.0))
	for b in 3:
		var a0 := -PI * 0.5 + TAU * b / 3.0 - PI / 6.0   # one blade points up
		var pts := PackedVector2Array()
		var n := 6
		for j in n + 1:
			var a := a0 + (PI / 3.0) * j / n
			pts.append(c + Vector2(cos(a), sin(a)) * r * 0.78)
		for j in range(n, -1, -1):
			var a := a0 + (PI / 3.0) * j / n
			pts.append(c + Vector2(cos(a), sin(a)) * r * 0.27)
		ci.draw_colored_polygon(pts, black)
	ci.draw_circle(c, r * 0.17, black)
