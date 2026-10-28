class_name AbilityGlyphs
extends RefCounted
## Procedural ability icons for the roster kits in data/abilities.json ("icon": {"glyph", "color"}).
## Each glyph is a simple tinted shape drawn into a ~60 px square around `c` on any CanvasItem,
## in the same flat style as the Fire Wizard's hand-drawn slot icons.

const NAMES := ["snowflake", "dash", "cloud", "hourglass", "frog", "swirl", "bolt", "burst", "drop",
	"skull", "moon", "ring", "fist", "ghost", "eye", "arrow", "shield", "wing", "star", "blade",
	"flask", "web", "egg", "wave", "bone", "paw", "bomb", "note", "flame", "sun", "sock", "book",
	"cauldron", "mushroom", "crown", "chain"]


static func draw(ci: CanvasItem, glyph: String, c: Vector2, col: Color, t := 0.0) -> void:
	var dark := col.darkened(0.55)
	var light := col.lightened(0.45)
	# Soft glow behind every glyph so it reads on the dark slot
	ci.draw_circle(c, 27, Color(col.r, col.g, col.b, 0.10))
	match glyph:
		"snowflake":
			for k in 6:
				var d := Vector2.from_angle(TAU * k / 6.0 - PI / 2)
				var n := d.orthogonal()
				ci.draw_line(c, c + d * 25, col, 3.5)
				for f in [0.45, 0.72]:
					var p: Vector2 = c + d * 25 * f
					ci.draw_line(p, p + (d - n) * 6, light, 2.5)
					ci.draw_line(p, p + (d + n) * 6, light, 2.5)
			ci.draw_circle(c, 4, light)
		"dash":
			for k in 3:
				var y := -12.0 + k * 12.0
				ci.draw_line(c + Vector2(-26, y), c + Vector2(-4 - k * 4, y), Color(col.r, col.g, col.b, 0.45 + k * 0.15), 3.0)
			_poly(ci, [c + Vector2(-6, -16), c + Vector2(24, 0), c + Vector2(-6, 16), c + Vector2(2, 0)], col)
		"cloud":
			for p in [Vector2(-12, 2), Vector2(0, -6), Vector2(13, 1), Vector2(-3, 6), Vector2(8, 7)]:
				ci.draw_circle(c + p + Vector2(0, -6), 11, col)
			for k in 4:
				var x := -15.0 + k * 10.0
				ci.draw_line(c + Vector2(x, 14), c + Vector2(x - 4, 26), light, 2.5)
		"hourglass":
			ci.draw_line(c + Vector2(-17, -26), c + Vector2(17, -26), dark.lightened(0.3), 4.0)
			ci.draw_line(c + Vector2(-17, 26), c + Vector2(17, 26), dark.lightened(0.3), 4.0)
			_poly(ci, [c + Vector2(-14, -23), c + Vector2(14, -23), c + Vector2(2, 0), c + Vector2(14, 23), c + Vector2(-14, 23), c + Vector2(-2, 0)], Color(col.r, col.g, col.b, 0.35))
			var sand := 0.5 + 0.5 * sin(t * 1.5)
			_poly(ci, [c + Vector2(-10 * sand, -4 - 14 * sand), c + Vector2(10 * sand, -4 - 14 * sand), c + Vector2(0, -2)], light)
			_poly(ci, [c + Vector2(-13, 22), c + Vector2(13, 22), c + Vector2(0, 22 - 14 * (1.0 - sand) - 3)], light)
			ci.draw_line(c + Vector2(0, -2), c + Vector2(0, 20), light, 1.5)
		"frog":
			ci.draw_circle(c + Vector2(0, 8), 18, col)
			ci.draw_circle(c + Vector2(-10, -8), 8, col)
			ci.draw_circle(c + Vector2(10, -8), 8, col)
			ci.draw_circle(c + Vector2(-10, -9), 4.5, Color.WHITE)
			ci.draw_circle(c + Vector2(10, -9), 4.5, Color.WHITE)
			ci.draw_circle(c + Vector2(-10, -9), 2.2, Color.BLACK)
			ci.draw_circle(c + Vector2(10, -9), 2.2, Color.BLACK)
			ci.draw_arc(c + Vector2(0, 6), 10, 0.3, PI - 0.3, 12, dark, 2.5)
		"swirl":
			var pts := PackedVector2Array()
			for k in 60:
				var a := t * 2.0 + k * 0.2
				pts.append(c + Vector2.from_angle(a) * (2.0 + k * 0.42))
			ci.draw_polyline(pts, col, 4.0, true)
			ci.draw_circle(pts[pts.size() - 1], 4, light)
		"bolt":
			_poly(ci, [c + Vector2(4, -28), c + Vector2(-14, 4), c + Vector2(-1, 4), c + Vector2(-6, 28), c + Vector2(15, -6), c + Vector2(2, -6), c + Vector2(10, -28)], col)
			ci.draw_polyline(PackedVector2Array([c + Vector2(4, -24), c + Vector2(-8, 1)]), light, 2.0)
		"burst":
			var pts := PackedVector2Array()
			for k in 20:
				var r := 27.0 if k % 2 == 0 else 12.0
				pts.append(c + Vector2.from_angle(TAU * k / 20.0 + t * 0.4) * r)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, 9, light)
		"drop":
			var pts := PackedVector2Array()
			for k in 17:
				var a := PI * k / 16.0
				pts.append(c + Vector2(0, 8) + Vector2(cos(a) * 16, sin(a) * 16))
			pts.append(c + Vector2(-14, 0))
			pts.append(c + Vector2(0, -26))
			pts.append(c + Vector2(14, 0))
			ci.draw_colored_polygon(pts, col)
			ci.draw_arc(c + Vector2(0, 8), 9, PI * 0.95, PI * 1.45, 8, light, 3.0)
		"skull":
			ci.draw_circle(c + Vector2(0, -5), 19, col)
			ci.draw_rect(Rect2(c + Vector2(-11, 6), Vector2(22, 14)), col)
			ci.draw_circle(c + Vector2(-7, -4), 5.5, dark.darkened(0.6))
			ci.draw_circle(c + Vector2(7, -4), 5.5, dark.darkened(0.6))
			_poly(ci, [c + Vector2(-3, 7), c + Vector2(3, 7), c + Vector2(0, 2)], dark.darkened(0.6))
			for k in 4:
				ci.draw_line(c + Vector2(-7.5 + k * 5, 13), c + Vector2(-7.5 + k * 5, 20), dark.darkened(0.6), 1.5)
		"moon":
			ci.draw_circle(c, 24, col)
			ci.draw_circle(c + Vector2(10, -7), 21, Color(0.08, 0.05, 0.05))
			ci.draw_circle(c + Vector2(-12, 8), 2.5, light)
			ci.draw_circle(c + Vector2(-5, -12), 1.5, light)
		"ring":
			for k in 3:
				var rad := 8.0 + k * 9.0 + fmod(t * 6.0, 9.0)
				ci.draw_arc(c, rad, 0, TAU, 32, Color(col.r, col.g, col.b, 1.0 - (rad - 8.0) / 30.0), 3.5)
			ci.draw_circle(c, 5, light)
		"fist":
			ci.draw_rect(Rect2(c + Vector2(-16, -12), Vector2(30, 26)), col)
			for k in 4:
				ci.draw_circle(c + Vector2(-12 + k * 8, -12), 5, col)
				ci.draw_line(c + Vector2(-8 + k * 8, -14), c + Vector2(-8 + k * 8, -4), dark, 1.5)
			_poly(ci, [c + Vector2(-16, 2), c + Vector2(-22, -6), c + Vector2(-16, -10)], col)
			ci.draw_rect(Rect2(c + Vector2(-12, 14), Vector2(22, 12)), dark.lightened(0.2))
		"ghost":
			var pts := PackedVector2Array()
			for k in 13:
				var a := PI + PI * k / 12.0
				pts.append(c + Vector2(0, -6) + Vector2(cos(a) * 18, sin(a) * 18))
			for k in 7:
				pts.append(c + Vector2(18 - k * 6, 22 + (4 if k % 2 == 0 else -2) + sin(t * 4 + k) * 1.5))
			ci.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.9))
			ci.draw_circle(c + Vector2(-7, -6), 4, dark.darkened(0.6))
			ci.draw_circle(c + Vector2(7, -6), 4, dark.darkened(0.6))
			ci.draw_circle(c + Vector2(0, 6), 3.5, dark.darkened(0.6))
		"eye":
			var pts := PackedVector2Array()
			for k in 13:
				pts.append(c + Vector2(-26 + k * 52.0 / 12.0, -sin(PI * k / 12.0) * 16))
			for k in 13:
				pts.append(c + Vector2(26 - k * 52.0 / 12.0, sin(PI * k / 12.0) * 16))
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, 10, dark.darkened(0.4))
			ci.draw_circle(c, 4.5, light)
		"arrow":
			ci.draw_line(c + Vector2(-20, 20), c + Vector2(14, -14), col, 4.0)
			_poly(ci, [c + Vector2(22, -22), c + Vector2(6, -16), c + Vector2(16, -6)], light)
			ci.draw_line(c + Vector2(-20, 20), c + Vector2(-26, 12), col, 3.0)
			ci.draw_line(c + Vector2(-20, 20), c + Vector2(-12, 26), col, 3.0)
		"shield":
			_poly(ci, [c + Vector2(-20, -22), c + Vector2(20, -22), c + Vector2(20, 0), c + Vector2(0, 26), c + Vector2(-20, 0)], col)
			_poly(ci, [c + Vector2(-14, -16), c + Vector2(14, -16), c + Vector2(14, -1), c + Vector2(0, 18), c + Vector2(-14, -1)], dark)
			ci.draw_line(c + Vector2(0, -14), c + Vector2(0, 14), light, 3.0)
			ci.draw_line(c + Vector2(-10, -4), c + Vector2(10, -4), light, 3.0)
		"wing":
			# Feathers fanning back from the shoulder, longest on top
			var sh := c + Vector2(18, -16)
			for k in 5:
				var ang := PI - 0.1 - k * 0.3
				var len := 40.0 - k * 5.0
				var d := Vector2.from_angle(ang)
				var n := d.orthogonal() * (6.0 - k * 0.5)
				_poly(ci, [sh + n, sh + d * len, sh - n], col if k % 2 == 0 else light)
			ci.draw_circle(sh, 7, col)
		"star":
			var pts := PackedVector2Array()
			for k in 8:
				var r := 26.0 if k % 2 == 0 else 8.0
				pts.append(c + Vector2.from_angle(TAU * k / 8.0 + t * 1.2) * r)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, 4, dark)
		"blade":
			_poly(ci, [c + Vector2(-16, 16), c + Vector2(18, -22), c + Vector2(22, -26), c + Vector2(20, -18), c + Vector2(-12, 20)], col)
			ci.draw_line(c + Vector2(-14, 18), c + Vector2(18, -20), light, 1.5)
			ci.draw_line(c + Vector2(-22, 10), c + Vector2(-8, 24), dark.lightened(0.3), 4.0)
			ci.draw_line(c + Vector2(-15, 17), c + Vector2(-24, 26), dark.lightened(0.15), 4.0)
		"flask":
			ci.draw_rect(Rect2(c + Vector2(-5, -26), Vector2(10, 14)), Color(0.8, 0.85, 0.9, 0.7))
			_poly(ci, [c + Vector2(-5, -12), c + Vector2(5, -12), c + Vector2(20, 20), c + Vector2(-20, 20)], Color(0.8, 0.85, 0.9, 0.35))
			_poly(ci, [c + Vector2(-11, 2), c + Vector2(11, 2), c + Vector2(19, 19), c + Vector2(-19, 19)], col)
			for k in 3:
				ci.draw_circle(c + Vector2(-6 + k * 6, -2 - fmod(t * 12 + k * 7, 14)), 2.5, light)
		"web":
			for k in 8:
				ci.draw_line(c, c + Vector2.from_angle(TAU * k / 8.0) * 27, col, 1.8)
			for ring in [8.0, 15.0, 22.0]:
				var pts := PackedVector2Array()
				for k in 9:
					pts.append(c + Vector2.from_angle(TAU * k / 8.0) * ring)
				ci.draw_polyline(pts, col, 1.8)
		"egg":
			var pts := PackedVector2Array()
			for k in 32:
				var a := TAU * k / 32.0
				var s := sin(a)
				pts.append(c + Vector2(cos(a) * 15 * (1.0 - 0.15 * s), s * 21 + 2))
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c + Vector2(-5, -6), 3, Color.WHITE)
			ci.draw_circle(c + Vector2(6, 6), 2.5, dark)
			ci.draw_circle(c + Vector2(-3, 12), 2, dark)
		"wave":
			for k in 3:
				var pts := PackedVector2Array()
				for i in 25:
					var x := -26.0 + i * 52.0 / 24.0
					pts.append(c + Vector2(x, -12 + k * 12 + sin(x * 0.25 + t * 3 + k) * 4))
				ci.draw_polyline(pts, col if k != 1 else light, 4.0, true)
		"bone":
			ci.draw_line(c + Vector2(-16, 16), c + Vector2(16, -16), col, 8.0)
			for p in [Vector2(-18, 12), Vector2(-12, 18), Vector2(12, -18), Vector2(18, -12)]:
				ci.draw_circle(c + p, 6.5, col)
		"paw":
			ci.draw_circle(c + Vector2(0, 10), 13, col)
			for p in [Vector2(-16, -6), Vector2(-6, -16), Vector2(6, -16), Vector2(16, -6)]:
				ci.draw_circle(c + p, 6, col)
		"bomb":
			ci.draw_circle(c + Vector2(-2, 6), 18, col)
			ci.draw_circle(c + Vector2(-8, 0), 5, light)
			ci.draw_rect(Rect2(c + Vector2(4, -16), Vector2(8, 8)), dark)
			ci.draw_line(c + Vector2(8, -16), c + Vector2(16, -24), Color(0.85, 0.75, 0.55), 2.0)
			var sp := 4.0 + 2.0 * sin(t * 14.0)
			ci.draw_circle(c + Vector2(17, -25), sp, Color(1.0, 0.85, 0.3))
		"note":
			ci.draw_circle(c + Vector2(-12, 16), 7, col)
			ci.draw_circle(c + Vector2(12, 10), 7, col)
			ci.draw_line(c + Vector2(-6, 16), c + Vector2(-6, -18), col, 3.5)
			ci.draw_line(c + Vector2(18, 10), c + Vector2(18, -24), col, 3.5)
			_poly(ci, [c + Vector2(-7.5, -18), c + Vector2(19.5, -24), c + Vector2(19.5, -16), c + Vector2(-7.5, -10)], light)
		"flame":
			_flame(ci, c + Vector2(0, 10), 30, 16, col)
			_flame(ci, c + Vector2(0, 14), 17, 9, light)
		"sun":
			for k in 12:
				var d := Vector2.from_angle(TAU * k / 12.0 + t * 0.5)
				ci.draw_line(c + d * 16, c + d * 27, col, 3.0)
			ci.draw_circle(c, 13, col)
			ci.draw_circle(c, 8, light)
		"sock":
			_poly(ci, [c + Vector2(-6, -26), c + Vector2(10, -26), c + Vector2(10, 8), c + Vector2(4, 22), c + Vector2(-20, 22), c + Vector2(-22, 12), c + Vector2(-6, 6)], col)
			ci.draw_rect(Rect2(c + Vector2(-6, -26), Vector2(16, 6)), light)
			for p in [Vector2(2, -12), Vector2(2, 2), Vector2(-10, 14)]:
				_poly(ci, [c + p + Vector2(0, -5), c + p + Vector2(4, 0), c + p + Vector2(0, 5), c + p + Vector2(-4, 0)], dark)
		"book":
			_poly(ci, [c + Vector2(0, -14), c + Vector2(-24, -20), c + Vector2(-24, 18), c + Vector2(0, 24)], col)
			_poly(ci, [c + Vector2(0, -14), c + Vector2(24, -20), c + Vector2(24, 18), c + Vector2(0, 24)], col.darkened(0.15))
			for k in 3:
				ci.draw_line(c + Vector2(-19, -10 + k * 9), c + Vector2(-5, -6 + k * 9), dark, 1.5)
				ci.draw_line(c + Vector2(5, -6 + k * 9), c + Vector2(19, -10 + k * 9), dark, 1.5)
		"cauldron":
			ci.draw_circle(c + Vector2(0, 8), 18, Color(0.22, 0.22, 0.24))
			ci.draw_rect(Rect2(c + Vector2(-20, -6), Vector2(40, 6)), Color(0.3, 0.3, 0.32))
			ci.draw_rect(Rect2(c + Vector2(-17, -6), Vector2(34, 4)), col)
			for k in 3:
				ci.draw_circle(c + Vector2(-8 + k * 8, -10 - fmod(t * 10 + k * 6, 16)), 3.5, col)
		"mushroom":
			var pts := PackedVector2Array()
			for k in 17:
				var a := PI + PI * k / 16.0
				pts.append(c + Vector2(0, 2) + Vector2(cos(a) * 25, sin(a) * 20))
			ci.draw_colored_polygon(pts, col)
			ci.draw_rect(Rect2(c + Vector2(-7, 2), Vector2(14, 22)), Color(0.95, 0.9, 0.8))
			for p in [Vector2(-12, -7), Vector2(4, -13), Vector2(14, -4)]:
				ci.draw_circle(c + p, 3.5, Color.WHITE)
		"crown":
			_poly(ci, [c + Vector2(-24, 14), c + Vector2(-24, -12), c + Vector2(-12, 0), c + Vector2(0, -20), c + Vector2(12, 0), c + Vector2(24, -12), c + Vector2(24, 14)], col)
			ci.draw_rect(Rect2(c + Vector2(-24, 14), Vector2(48, 7)), dark.lightened(0.3))
			for p in [Vector2(-24, -14), Vector2(0, -22), Vector2(24, -14)]:
				ci.draw_circle(c + p, 3.5, light)
		"chain":
			for k in 4:
				var p := c + Vector2(-18 + k * 12, 14 - k * 10)
				if k % 2 == 0:
					ci.draw_arc(p, 8, 0, TAU, 16, col, 4.0)
				else:
					ci.draw_arc(p, 8, 0, TAU, 16, light, 4.0)
			ci.draw_line(c + Vector2(20, -22), c + Vector2(26, -28), light, 3.0)
			ci.draw_line(c + Vector2(18, -26), c + Vector2(24, -18), col, 3.0)
		_:
			ci.draw_circle(c, 18, col)


static func _poly(ci: CanvasItem, pts: Array, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array(pts), col)


static func _flame(ci: CanvasItem, base: Vector2, h: float, w: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 14
	for k in n + 1:
		var a := PI * float(k) / float(n)
		pts.append(base + Vector2(cos(a) * w, sin(a) * w * 0.8))
	pts.append(base + Vector2(-w * 0.9, -h * 0.35))
	pts.append(base + Vector2(-w * 0.2, -h * 0.75))
	pts.append(base + Vector2(0, -h * 1.15))
	pts.append(base + Vector2(w * 0.35, -h * 0.65))
	pts.append(base + Vector2(w * 0.95, -h * 0.3))
	ci.draw_colored_polygon(pts, col)
