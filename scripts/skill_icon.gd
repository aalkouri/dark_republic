class_name SkillIcon
extends Control
## Small vector glyphs for skill squares (drawn in a 64x64 design space and scaled).
## kinds: heart, shield, cross, bubble, blade, clock, orb, burst, arrow, boot, feather, coin,
## magnet, book, clover, flame, expand, eye, triple, fireball, stink, slam, bomb, fang.

var kind := "orb"
var color := Color.WHITE
var dim := 1.0
var locked := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _poly(pts: Array, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), c)


func _draw() -> void:
	var s := minf(size.x, size.y) / 64.0
	draw_set_transform((size - Vector2(64, 64) * s) * 0.5, 0.0, Vector2(s, s))
	var c := Color(color.r * dim, color.g * dim, color.b * dim, 1.0)
	var light := c.lightened(0.35)
	var dark := c.darkened(0.45)
	match kind:
		"heart":
			draw_circle(Vector2(22, 24), 12, c)
			draw_circle(Vector2(42, 24), 12, c)
			_poly([Vector2(11, 29), Vector2(53, 29), Vector2(32, 54)], c)
			draw_circle(Vector2(19, 20), 4, light)
		"shield":
			_poly([Vector2(32, 6), Vector2(54, 14), Vector2(50, 38), Vector2(32, 58), Vector2(14, 38), Vector2(10, 14)], c)
			_poly([Vector2(32, 12), Vector2(48, 18), Vector2(45, 37), Vector2(32, 51)], dark)
		"cross":
			_poly([Vector2(25, 8), Vector2(39, 8), Vector2(39, 25), Vector2(56, 25), Vector2(56, 39), Vector2(39, 39),
				Vector2(39, 56), Vector2(25, 56), Vector2(25, 39), Vector2(8, 39), Vector2(8, 25), Vector2(25, 25)], c)
		"bubble":
			draw_arc(Vector2(32, 32), 24, 0, TAU, 40, c, 5)
			draw_arc(Vector2(32, 32), 17, PI * 1.1, PI * 1.6, 12, light, 3)
			draw_circle(Vector2(32, 32), 9, Color(c, 0.5))
		"blade":
			_poly([Vector2(46, 6), Vector2(54, 10), Vector2(24, 44), Vector2(18, 40)], light)
			_poly([Vector2(12, 38), Vector2(26, 52), Vector2(22, 56), Vector2(8, 42)], c)
			draw_line(Vector2(17, 47), Vector2(8, 56), dark, 5)
		"clock":
			draw_circle(Vector2(32, 34), 22, c)
			draw_circle(Vector2(32, 34), 17, dark)
			draw_line(Vector2(32, 34), Vector2(32, 21), light, 4)
			draw_line(Vector2(32, 34), Vector2(42, 39), light, 4)
			_poly([Vector2(27, 6), Vector2(37, 6), Vector2(37, 12), Vector2(27, 12)], c)
		"orb":
			draw_circle(Vector2(32, 34), 18, c)
			draw_circle(Vector2(26, 28), 7, light)
			for k in 3:
				var a := -PI * 0.5 + (k - 1) * 0.6
				draw_line(Vector2(32, 34) + Vector2(cos(a), sin(a)) * 21, Vector2(32, 34) + Vector2(cos(a), sin(a)) * 29, c, 4)
		"burst":
			for k in 8:
				var a := TAU * k / 8.0
				_poly([Vector2(32, 32) + Vector2(cos(a - 0.2), sin(a - 0.2)) * 10, Vector2(32, 32) + Vector2(cos(a), sin(a)) * 28,
					Vector2(32, 32) + Vector2(cos(a + 0.2), sin(a + 0.2)) * 10], c)
			draw_circle(Vector2(32, 32), 10, light)
		"arrow":
			draw_line(Vector2(10, 54), Vector2(46, 18), c, 6)
			_poly([Vector2(54, 10), Vector2(50, 32), Vector2(32, 14)], light)
			_poly([Vector2(8, 46), Vector2(18, 56), Vector2(10, 58), Vector2(6, 54)], dark)
		"boot":
			_poly([Vector2(20, 8), Vector2(36, 8), Vector2(36, 36), Vector2(56, 42), Vector2(56, 54), Vector2(16, 54), Vector2(18, 30)], c)
			_poly([Vector2(16, 50), Vector2(56, 50), Vector2(56, 56), Vector2(16, 56)], dark)
			for k in 3:
				draw_line(Vector2(4 + k * 3, 20 + k * 10), Vector2(14, 20 + k * 10), light, 3)
		"feather":
			_poly([Vector2(48, 6), Vector2(56, 14), Vector2(34, 44), Vector2(18, 48), Vector2(22, 32)], c)
			draw_line(Vector2(50, 12), Vector2(10, 56), light, 3)
		"coin":
			draw_circle(Vector2(32, 32), 22, c.darkened(0.2))
			draw_circle(Vector2(32, 32), 18, c)
			draw_circle(Vector2(27, 26), 6, light)
			draw_arc(Vector2(32, 32), 18, 0, TAU, 32, dark, 2)
		"magnet":
			draw_arc(Vector2(32, 30), 17, PI, TAU, 20, c, 12)
			_poly([Vector2(9, 30), Vector2(21, 30), Vector2(21, 44), Vector2(9, 44)], c)
			_poly([Vector2(43, 30), Vector2(55, 30), Vector2(55, 44), Vector2(43, 44)], c)
			_poly([Vector2(9, 44), Vector2(21, 44), Vector2(21, 54), Vector2(9, 54)], light)
			_poly([Vector2(43, 44), Vector2(55, 44), Vector2(55, 54), Vector2(43, 54)], light)
		"book":
			_poly([Vector2(8, 14), Vector2(31, 18), Vector2(31, 54), Vector2(8, 50)], c)
			_poly([Vector2(33, 18), Vector2(56, 14), Vector2(56, 50), Vector2(33, 54)], c.darkened(0.15))
			for k in 3:
				draw_line(Vector2(13, 24 + k * 8), Vector2(27, 26 + k * 8), light, 2)
		"clover":
			for k in 4:
				var a := TAU * k / 4.0 + PI * 0.25
				draw_circle(Vector2(32, 30) + Vector2(cos(a), sin(a)) * 11, 10, c)
			draw_line(Vector2(32, 34), Vector2(40, 58), dark, 4)
		"expand":   # four arrows pushing outwards
			for k in 4:
				var a := TAU * k / 4.0 + PI * 0.25
				var dir := Vector2(cos(a), sin(a))
				var side := Vector2(-dir.y, dir.x)
				var o := Vector2(32, 32)
				draw_line(o + dir * 6, o + dir * 20, c, 5)
				_poly([o + dir * 27, o + dir * 16 + side * 8, o + dir * 16 - side * 8], light)
			draw_circle(Vector2(32, 32), 5, c)
		"eye":
			_poly([Vector2(6, 32), Vector2(20, 20), Vector2(32, 16), Vector2(44, 20), Vector2(58, 32),
				Vector2(44, 44), Vector2(32, 48), Vector2(20, 44)], c)
			draw_circle(Vector2(32, 32), 11, dark)
			draw_circle(Vector2(32, 32), 6, light)
			draw_circle(Vector2(29, 29), 2.5, Color(1, 1, 1, 0.9))
		"triple":   # three projectiles side by side
			for k in 3:
				var o := Vector2(16 + k * 16, 36 - (k % 2) * 8)
				draw_line(o + Vector2(0, 8), o + Vector2(0, 22), dark, 4)
				draw_circle(o, 7, c)
				draw_circle(o + Vector2(-2, -2), 2.5, light)
		"shard":   # an icicle flying down-right with frost trailing
			for k in 3:
				draw_line(Vector2(10 + k * 6, 14 + k * 2), Vector2(24 + k * 6, 28 + k * 2), Color(light, 0.5), 3)
			_poly([Vector2(20, 18), Vector2(28, 14), Vector2(56, 52), Vector2(14, 26)], c)
			_poly([Vector2(24, 18), Vector2(28, 16), Vector2(54, 50)], light)
		"chainbolt":   # a bolt that forks into a second goblin-seeking arc
			_poly([Vector2(30, 4), Vector2(14, 34), Vector2(26, 34), Vector2(20, 60), Vector2(42, 26), Vector2(30, 26), Vector2(40, 4)], c)
			draw_polyline(PackedVector2Array([Vector2(36, 30), Vector2(46, 36), Vector2(42, 44), Vector2(56, 52)]), light, 3)
			draw_circle(Vector2(56, 52), 4, light)
		"shadowbolt":   # a dark orb with a violet halo and a wisping tail
			for k in 4:
				draw_circle(Vector2(18 - k * 3, 46 + k * 3), 6 - k, Color(c, 0.5 - k * 0.1))
			draw_circle(Vector2(36, 28), 17, c)
			draw_circle(Vector2(36, 28), 11, Color(0.08, 0.02, 0.12))
			draw_arc(Vector2(36, 28), 17, PI * 1.1, PI * 1.7, 12, light, 3)
		"fireball":   # a blazing ball with its tail streaming behind (up-left)
			_poly([Vector2(40, 30), Vector2(8, 8), Vector2(22, 26), Vector2(4, 22), Vector2(26, 40), Vector2(30, 46)], dark)
			_poly([Vector2(40, 32), Vector2(14, 14), Vector2(26, 30), Vector2(12, 28), Vector2(32, 44)], c)
			draw_circle(Vector2(40, 40), 15, c)
			draw_circle(Vector2(40, 40), 10, light)
			draw_circle(Vector2(37, 37), 4, Color(1, 1, 0.9))
		"stink":   # wavy fumes rising from a puddle
			draw_circle(Vector2(32, 52), 20, Color(c, 0.35))
			for k in 3:
				var x := 18.0 + k * 14.0
				var pts := PackedVector2Array()
				for j in 9:
					var y := 48.0 - j * 4.6
					pts.append(Vector2(x + sin(j * 1.1 + k) * 4.0, y))
				draw_polyline(pts, c, 4)
			draw_circle(Vector2(46, 14), 3, light)
			draw_circle(Vector2(20, 12), 2.5, light)
		"slam":   # a fist hammering the ground, cracks and dust flying
			_poly([Vector2(20, 6), Vector2(44, 6), Vector2(46, 30), Vector2(18, 30)], c)
			for k in 4:
				draw_line(Vector2(22 + k * 6, 12), Vector2(22 + k * 6, 22), dark, 2)
			_poly([Vector2(16, 30), Vector2(48, 30), Vector2(46, 36), Vector2(18, 36)], light)
			draw_line(Vector2(6, 46), Vector2(58, 46), c, 3)
			for seg in [[Vector2(32, 46), Vector2(26, 54), Vector2(28, 60)], [Vector2(32, 46), Vector2(40, 53), Vector2(38, 60)]]:
				draw_polyline(PackedVector2Array(seg), dark, 2.5)
			for k in 3:
				var a := PI + 0.35 + k * 0.25
				draw_line(Vector2(14, 42) + Vector2(cos(a), sin(a)) * 3, Vector2(14, 42) + Vector2(cos(a), sin(a)) * 11, light, 2.5)
				var b := -0.35 - k * 0.25
				draw_line(Vector2(50, 42) + Vector2(cos(b), sin(b)) * 3, Vector2(50, 42) + Vector2(cos(b), sin(b)) * 11, light, 2.5)
		"bomb":
			draw_circle(Vector2(28, 38), 19, Color(0.12, 0.12, 0.14))
			draw_circle(Vector2(22, 32), 6, Color(0.45, 0.45, 0.5))
			_poly([Vector2(34, 16), Vector2(44, 16), Vector2(44, 24), Vector2(34, 24)], Color(0.3, 0.3, 0.34))
			draw_polyline(PackedVector2Array([Vector2(39, 16), Vector2(42, 10), Vector2(48, 8)]), Color(0.75, 0.6, 0.4), 2.5)
			for k in 6:
				var a := TAU * k / 6.0
				draw_line(Vector2(50, 8), Vector2(50, 8) + Vector2(cos(a), sin(a)) * 7, c, 2.5)
			draw_circle(Vector2(50, 8), 3, light)
		"fang":
			_poly([Vector2(10, 10), Vector2(54, 10), Vector2(54, 18), Vector2(10, 18)], Color(0.6, 0.15, 0.2))
			_poly([Vector2(14, 16), Vector2(28, 16), Vector2(21, 48)], Color(0.96, 0.94, 0.88))
			_poly([Vector2(36, 16), Vector2(50, 16), Vector2(43, 48)], Color(0.96, 0.94, 0.88))
			draw_circle(Vector2(21, 54), 4, c)
			_poly([Vector2(18, 53), Vector2(24, 53), Vector2(21, 46)], c)
		"flame":
			_poly([Vector2(32, 4), Vector2(48, 26), Vector2(50, 42), Vector2(32, 58), Vector2(14, 42), Vector2(18, 26), Vector2(26, 30)], c)
			_poly([Vector2(32, 24), Vector2(40, 40), Vector2(32, 52), Vector2(24, 40)], light)
	if locked:
		draw_rect(Rect2(20, 30, 24, 20), Color(0.75, 0.7, 0.6))
		draw_arc(Vector2(32, 30), 8, PI, TAU, 12, Color(0.75, 0.7, 0.6), 3)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
