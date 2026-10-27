class_name CharacterIcon
extends Control
## Procedurally drawn character portrait. Composed from the "icon" traits in
## data/characters.json: background gradient, body shape, head, hat/headgear, beard/hair,
## eyes, signature item and a particle motif. Drawn in a 128x128 design space and scaled.

var data := {}          # the character's "icon" dictionary
var animate := true
var locked := false     # darken and draw a padlock badge
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_icon(d: Dictionary) -> void:
	data = d
	queue_redraw()


func _process(dt: float) -> void:
	if animate and is_visible_in_tree():
		_t += dt
		queue_redraw()


func _c(key: String, fallback := "#ffffff") -> Color:
	return Color.html(str(data.get(key, fallback)))


func _draw() -> void:
	if data.is_empty():
		return
	var s := minf(size.x, size.y) / 128.0
	draw_set_transform(Vector2((size.x - 128.0 * s) * 0.5, (size.y - 128.0 * s) * 0.5), 0.0, Vector2(s, s))
	var bg: Array = data.get("bg", ["#222222", "#000000"])
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(128, 0), Vector2(128, 128), Vector2(0, 128)]),
		PackedColorArray([Color.html(bg[0]), Color.html(bg[0]), Color.html(bg[1]), Color.html(bg[1])]))
	var fx: String = data.get("fx", "none")
	if fx in ["shadow", "wisps"]:
		_fx(fx)
	var item: String = data.get("item", "none")
	if item in ["web", "katana", "scythe"]:
		_item(item)          # behind the body
	var hat: String = data.get("hat", "none")
	_body(data.get("body", "robe"))
	if hat == "hood":
		_hat(hat)            # hood frames the face, so it goes behind the head
	_hair_back()
	_head(data.get("head", "round"))
	_beard()
	if hat != "hood":
		_hat(hat)
	_eyes()
	_extras()
	if item not in ["web", "katana", "scythe", "none"]:
		_item(item)
	if fx not in ["shadow", "wisps", "none"]:
		_fx(fx)
	if locked:
		_padlock()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ parts

func _poly(pts: Array, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), col)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color, arc_from := 0.0, arc_to := TAU) -> void:
	var pts := PackedVector2Array()
	var n := 28
	for k in n + 1:
		var a := lerpf(arc_from, arc_to, float(k) / n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	if not is_equal_approx(arc_to - arc_from, TAU):
		pts.append(c)
	draw_colored_polygon(pts, col)


func _body(kind: String) -> void:
	var col := _c("body_col")
	var dark := col.darkened(0.35)
	match kind:
		"robe":
			_poly([Vector2(46, 72), Vector2(82, 72), Vector2(104, 128), Vector2(24, 128)], col)
			_poly([Vector2(62, 74), Vector2(66, 74), Vector2(70, 128), Vector2(58, 128)], dark)
		"coat":
			_poly([Vector2(44, 72), Vector2(84, 72), Vector2(98, 128), Vector2(30, 128)], col)
			_poly([Vector2(56, 72), Vector2(64, 96), Vector2(72, 72)], col.lightened(0.25))
			draw_line(Vector2(64, 96), Vector2(64, 128), dark, 2.0)
		"slim":
			_poly([Vector2(48, 74), Vector2(80, 74), Vector2(90, 128), Vector2(38, 128)], col)
			draw_line(Vector2(64, 76), Vector2(64, 128), dark, 2.0)
		"bulky":
			_poly([Vector2(30, 82), Vector2(98, 82), Vector2(112, 128), Vector2(16, 128)], col)
			_ellipse(Vector2(34, 88), 14, 12, col)
			_ellipse(Vector2(94, 88), 14, 12, col)
		"box":
			_poly([Vector2(36, 74), Vector2(92, 74), Vector2(92, 128), Vector2(36, 128)], col)
			_poly([Vector2(48, 86), Vector2(80, 86), Vector2(80, 108), Vector2(48, 108)], col.darkened(0.45))
			for p in [Vector2(40, 78), Vector2(88, 78), Vector2(40, 124), Vector2(88, 124)]:
				draw_circle(p, 2.0, col.lightened(0.4))
			draw_circle(Vector2(56, 97), 3.0, Color(1.0, 0.3, 0.3))
			draw_circle(Vector2(72, 97), 3.0, Color(0.3, 1.0, 0.5))
		"imp":
			_ellipse(Vector2(64, 102), 24, 26, col)
			for k in 7:
				var p := Vector2(48 + k * 5.0, 96 + float((k * 37) % 17))
				draw_circle(p, 2.0, Color(1.0, 0.45, 0.1, 0.8))   # glowing cracks
		"blob":
			_ellipse(Vector2(64, 88), 46, 40, col)
			_ellipse(Vector2(48, 74), 12, 8, col.lightened(0.35))
			for x in [36.0, 58.0, 84.0]:
				var drip := 8.0 + 5.0 * sin(_t * 2.0 + x)
				_ellipse(Vector2(x, 120 + drip * 0.3), 5, drip * 0.5 + 4, col)
		"ghost":
			var pts := []
			for k in 15:
				var a := PI + PI * k / 14.0
				pts.append(Vector2(64, 60) + Vector2(cos(a), sin(a)) * 34.0)
			for k in 7:
				var x := 98.0 - k * (68.0 / 6.0)
				pts.append(Vector2(x, 112 + (8.0 if k % 2 == 0 else 0.0) + 3.0 * sin(_t * 3.0 + k)))
			_poly(pts, Color(col, 0.92))
		"spider":
			var legc := col.lightened(0.2)
			for side in [-1.0, 1.0]:
				for k in 4:
					var y := 80.0 + k * 8.0
					var knee := Vector2(64 + side * (36 + k * 3.0), y - 22 + k * 4.0)
					var foot := Vector2(64 + side * (52 + k * 2.0), y + 26)
					draw_line(Vector2(64 + side * 14, y), knee, legc, 3.5)
					draw_line(knee, foot, legc, 3.0)
			_ellipse(Vector2(64, 98), 30, 24, col)
			_ellipse(Vector2(64, 98), 12, 9, Color(0.75, 0.1, 0.12))   # hourglass mark
			_ellipse(Vector2(64, 66), 18, 14, col.lightened(0.1))
		"sock":
			var sock := [Vector2(44, 18), Vector2(82, 18), Vector2(82, 92), Vector2(106, 102), Vector2(108, 122), Vector2(60, 122), Vector2(44, 104)]
			_poly(sock, col)
			for k in 4:
				_poly([Vector2(44, 18 + k * 4.0), Vector2(82, 18 + k * 4.0), Vector2(82, 20 + k * 4.0), Vector2(44, 20 + k * 4.0)], Color(0.95, 0.9, 0.85) if k % 2 == 0 else col)
			for row in 3:
				for colx in 2:
					var c := Vector2(54 + colx * 18 + (9 if row % 2 else 0), 46 + row * 18)
					if c.x < 82:
						_poly([c + Vector2(0, -8), c + Vector2(7, 0), c + Vector2(0, 8), c + Vector2(-7, 0)], Color(0.95, 0.75, 0.2))
			draw_line(Vector2(48, 40), Vector2(80, 100), Color(0.2, 0.9, 0.85, 0.7), 1.5)
			draw_line(Vector2(80, 40), Vector2(48, 100), Color(0.2, 0.9, 0.85, 0.7), 1.5)


func _head(kind: String) -> void:
	var skin := _c("skin")
	match kind:
		"round":
			_ellipse(Vector2(64, 56), 18, 19, skin)
		"hooded":
			_ellipse(Vector2(64, 60), 13, 15, skin)
		"ogre":
			_ellipse(Vector2(40, 56), 6, 8, skin)
			_ellipse(Vector2(88, 56), 6, 8, skin)
			_ellipse(Vector2(64, 58), 25, 23, skin)
			_poly([Vector2(54, 70), Vector2(58, 70), Vector2(55, 60)], Color(0.95, 0.92, 0.8))
			_poly([Vector2(70, 70), Vector2(74, 70), Vector2(73, 60)], Color(0.95, 0.92, 0.8))
			draw_line(Vector2(52, 47), Vector2(60, 50), skin.darkened(0.4), 3.0)
			draw_line(Vector2(76, 47), Vector2(68, 50), skin.darkened(0.4), 3.0)
		"skull":
			_ellipse(Vector2(64, 56), 17, 18, skin)
			_poly([Vector2(54, 66), Vector2(74, 66), Vector2(72, 76), Vector2(56, 76)], skin)
			for x in [58.0, 63.0, 68.0]:
				draw_line(Vector2(x, 68), Vector2(x, 75), Color(0.1, 0.1, 0.1), 1.2)
			_poly([Vector2(62, 62), Vector2(66, 62), Vector2(64, 66)], Color(0.05, 0.05, 0.05))
		"croc":
			_ellipse(Vector2(56, 56), 17, 17, skin)
			_poly([Vector2(60, 50), Vector2(104, 54), Vector2(106, 64), Vector2(60, 68)], skin)
			for k in 6:
				var x := 66.0 + k * 6.5
				_poly([Vector2(x, 61), Vector2(x + 3, 61), Vector2(x + 1.5, 65)], Color(0.97, 0.95, 0.88))
			draw_circle(Vector2(101, 55), 1.5, skin.darkened(0.6))
			for k in 5:
				draw_circle(Vector2(46 + k * 5.0, 44 + (k % 2) * 3.0), 2.0, skin.darkened(0.25))
		"dog":
			_poly([Vector2(42, 44), Vector2(34, 68), Vector2(48, 60)], skin.darkened(0.45))
			_poly([Vector2(86, 44), Vector2(94, 68), Vector2(80, 60)], skin.darkened(0.45))
			_ellipse(Vector2(64, 60), 23, 21, skin)
			_ellipse(Vector2(56, 70), 10, 8, skin.lightened(0.3))
			_ellipse(Vector2(72, 70), 10, 8, skin.lightened(0.3))
			_ellipse(Vector2(64, 64), 6, 4, Color(0.08, 0.06, 0.06))
			draw_line(Vector2(56, 78), Vector2(72, 78), Color(0.3, 0.12, 0.1), 2.0)
			_poly([Vector2(58, 77), Vector2(61, 77), Vector2(59, 72)], Color(0.97, 0.95, 0.88))
			_poly([Vector2(67, 77), Vector2(70, 77), Vector2(69, 72)], Color(0.97, 0.95, 0.88))
		"robot":
			_poly([Vector2(44, 36), Vector2(84, 36), Vector2(84, 72), Vector2(44, 72)], skin)
			_poly([Vector2(48, 42), Vector2(80, 42), Vector2(80, 66), Vector2(48, 66)], Color(0.05, 0.08, 0.1))
			draw_line(Vector2(64, 36), Vector2(64, 26), skin, 2.0)
			draw_circle(Vector2(64, 25), 3.0 + 0.8 * sin(_t * 6.0), Color(1.0, 0.25, 0.2))
		"platypus":
			_ellipse(Vector2(60, 56), 17, 17, skin)
			_poly([Vector2(66, 56), Vector2(104, 52), Vector2(108, 62), Vector2(102, 68), Vector2(66, 66)], Color(0.24, 0.27, 0.32))
			draw_circle(Vector2(96, 56), 1.4, Color(0.05, 0.05, 0.05))
			draw_circle(Vector2(100, 56), 1.4, Color(0.05, 0.05, 0.05))


func _hair_back() -> void:
	if not data.has("hair"):
		return
	var hair := _c("hair")
	if data.get("hat", "") == "winged_helm":
		_ellipse(Vector2(44, 70), 8, 16, hair)       # braid
		_ellipse(Vector2(84, 70), 8, 16, hair)
	else:
		for k in 6:
			var x := 46.0 + k * 7.0
			draw_line(Vector2(x, 44), Vector2(x - 4 + k, 80), hair, 3.0)


func _beard() -> void:
	if not data.has("beard"):
		return
	var long: bool = data.get("beard_long", false)
	var b := _c("beard")
	_poly([Vector2(48, 60), Vector2(80, 60), Vector2(72, 72), Vector2(64, 64.0 + (40.0 if long else 22.0)), Vector2(56, 72)], b)
	_ellipse(Vector2(64, 62), 9, 3, b)


func _hat(kind: String) -> void:
	var hc := _c("hat_col")
	match kind:
		"wizard", "wizard_stars", "wizard_bent":
			var tip := Vector2(66, 2) if kind != "wizard_bent" else Vector2(96, 10)
			_poly([Vector2(44, 42), Vector2(84, 42), Vector2(tip.x + 4, tip.y + 10), tip], hc)
			_ellipse(Vector2(64, 42), 31, 6, hc.darkened(0.15))
			draw_line(Vector2(47, 39), Vector2(81, 39), Color(0.95, 0.75, 0.25), 3.0)
			if kind == "wizard_stars":
				for p in [Vector2(60, 26), Vector2(70, 16), Vector2(56, 36), Vector2(74, 32)]:
					_star(p, 3.0, Color(1.0, 0.95, 0.6))
		"witch":
			_poly([Vector2(46, 40), Vector2(82, 40), Vector2(58, 14), Vector2(74, 4), Vector2(54, 10)], hc)
			_ellipse(Vector2(64, 41), 36, 5, hc)
			_poly([Vector2(58, 34), Vector2(70, 34), Vector2(70, 40), Vector2(58, 40)], Color(0.8, 0.7, 0.3))
		"hood":
			var pts := []
			for k in 17:
				var a := PI + PI * k / 16.0
				pts.append(Vector2(64, 58) + Vector2(cos(a) * 26.0, sin(a) * 28.0))
			pts.append(Vector2(92, 82))
			pts.append(Vector2(36, 82))
			_poly(pts, hc)
			_ellipse(Vector2(64, 60), 15, 18, Color(0.02, 0.02, 0.03))
		"cowboy":
			_ellipse(Vector2(64, 42), 36, 6, hc)
			_poly([Vector2(48, 42), Vector2(80, 42), Vector2(78, 24), Vector2(64, 28), Vector2(50, 24)], hc)
			draw_line(Vector2(49, 38), Vector2(79, 38), hc.darkened(0.5), 3.0)
		"tricorn":
			_poly([Vector2(34, 42), Vector2(94, 42), Vector2(80, 30), Vector2(64, 24), Vector2(48, 30)], hc)
			draw_line(Vector2(36, 42), Vector2(92, 42), Color(0.75, 0.6, 0.3), 2.0)
		"winged_helm":
			_ellipse(Vector2(64, 50), 20, 18, hc, PI, TAU)
			for side in [-1.0, 1.0]:
				for k in 3:
					var base := Vector2(64 + side * 18, 46 - k * 4.0)
					_poly([base, base + Vector2(side * (18 - k * 3.0), -14 + k * 2.0), base + Vector2(side * 4, 4)], Color(0.98, 0.98, 1.0))
		"headband":
			_poly([Vector2(45, 44), Vector2(83, 44), Vector2(83, 50), Vector2(45, 50)], hc)
			var wave := 3.0 * sin(_t * 5.0)
			_poly([Vector2(82, 46), Vector2(104, 52 + wave), Vector2(102, 56 + wave), Vector2(82, 50)], hc)
			_poly([Vector2(82, 48), Vector2(100, 60 + wave), Vector2(97, 63 + wave), Vector2(82, 50)], hc)
		"goggles":
			draw_line(Vector2(40, 42), Vector2(70, 40), Color(0.25, 0.2, 0.15), 4.0)
			draw_circle(Vector2(48, 41), 7.0, hc)
			draw_circle(Vector2(62, 40), 7.0, hc)
			draw_circle(Vector2(48, 41), 4.5, Color(0.55, 0.85, 0.95))
			draw_circle(Vector2(62, 40), 4.5, Color(0.55, 0.85, 0.95))
		"collar":
			_poly([Vector2(42, 78), Vector2(86, 78), Vector2(86, 86), Vector2(42, 86)], hc)
			for k in 6:
				var x := 46.0 + k * 7.0
				_poly([Vector2(x - 2, 78), Vector2(x + 2, 78), Vector2(x, 72)], Color(0.82, 0.84, 0.88))
		"sombrero":
			_ellipse(Vector2(64, 38), 46, 8, hc)
			_ellipse(Vector2(64, 34), 15, 16, hc, PI, TAU)
			for k in 8:
				var x := 26.0 + k * 10.0
				draw_line(Vector2(x, 40), Vector2(x + 5, 36), Color(0.85, 0.15, 0.2), 2.0)
		"flame_hair":
			for k in 5:
				var x := 50.0 + k * 7.0
				var h := 18.0 + 6.0 * sin(_t * 6.0 + k * 1.3)
				_poly([Vector2(x - 6, 44), Vector2(x + 6, 44), Vector2(x + 1, 44 - h)], hc)
				_poly([Vector2(x - 3, 44), Vector2(x + 3, 44), Vector2(x, 44 - h * 0.6)], Color(1.0, 0.85, 0.3))
		"top_hat":
			_ellipse(Vector2(60, 40), 22, 4, hc)
			_poly([Vector2(48, 40), Vector2(72, 40), Vector2(72, 12), Vector2(48, 12)], hc)
			_poly([Vector2(48, 32), Vector2(72, 32), Vector2(72, 36), Vector2(48, 36)], Color(0.55, 0.12, 0.15))
		"mushroom":
			_ellipse(Vector2(64, 46), 38, 26, hc, PI, TAU)
			_poly([Vector2(26, 46), Vector2(102, 46), Vector2(96, 50), Vector2(32, 50)], Color(0.92, 0.86, 0.72))
			for p in [Vector2(48, 32), Vector2(66, 26), Vector2(84, 36), Vector2(56, 42), Vector2(78, 24)]:
				draw_circle(p, 4.0, Color(0.98, 0.96, 0.9))


func _eyes() -> void:
	var col := _c("eyes", "#000000")
	var head: String = data.get("head", "round")
	var body: String = data.get("body", "robe")
	var glow: bool = data.get("eyes_glow", false)
	var pts := [Vector2(57, 56), Vector2(71, 56)]
	var r := 3.0
	match head:
		"ogre":
			pts = [Vector2(55, 54), Vector2(73, 54)]
			r = 3.5
		"hooded":
			pts = [Vector2(58, 60), Vector2(70, 60)]
			r = 2.5
		"skull":
			pts = [Vector2(57, 54), Vector2(71, 54)]
			for p in pts:
				draw_circle(p, 5.0, Color(0.03, 0.03, 0.03))
			r = 2.2
		"croc":
			pts = [Vector2(52, 48), Vector2(64, 46)]
		"dog":
			pts = [Vector2(55, 54), Vector2(73, 54)]
		"robot":
			for p in [Vector2(52, 50), Vector2(68, 50)]:
				var on := col if fmod(_t, 3.0) > 0.12 else col.darkened(0.8)   # blink
				_poly([p, p + Vector2(10, 0), p + Vector2(10, 6), p + Vector2(0, 6)], on)
			draw_line(Vector2(54, 61), Vector2(74, 61), col, 2.0)
			return
		"platypus":
			pts = [Vector2(54, 52), Vector2(65, 52)]
			r = 2.6
		"none":
			match body:
				"blob":
					pts = [Vector2(52, 76), Vector2(76, 76)]
					r = 7.0
				"ghost":
					for p in [Vector2(52, 62), Vector2(76, 62)]:
						_ellipse(p, 6, 9, Color(0.05, 0.12, 0.13))
					_ellipse(Vector2(64, 82), 5, 7, Color(0.05, 0.12, 0.13))
					return
				"spider":
					pts = []
					for k in 8:
						pts.append(Vector2(52 + (k % 4) * 8.0, 62 + (k / 4) * 6.0))
					r = 2.2
				"sock":
					pts = [Vector2(56, 46), Vector2(72, 46)]
					r = 8.0
	if data.get("eyes_googly", false) or body == "blob":
		for k in pts.size():
			var p: Vector2 = pts[k]
			draw_circle(p, r, Color(0.98, 0.98, 0.98))
			draw_circle(p + Vector2(cos(_t * 2.0 + k) * r * 0.4, sin(_t * 1.6 + k) * r * 0.35 + r * 0.2), r * 0.45, Color(0.05, 0.05, 0.05))
		return
	for p in pts:
		if glow:
			draw_circle(p, r * 2.2, Color(col, 0.25))
		draw_circle(p, r, col)


func _extras() -> void:
	if data.has("scarf"):
		var sc := _c("scarf")
		_poly([Vector2(48, 70), Vector2(80, 70), Vector2(80, 78), Vector2(48, 78)], sc)
		_poly([Vector2(72, 76), Vector2(80, 76), Vector2(84, 94), Vector2(76, 94)], sc)
	if data.has("mask"):
		_poly([Vector2(47, 60), Vector2(81, 60), Vector2(80, 73), Vector2(48, 73)], _c("mask"))
	if data.get("monocle", false):
		draw_arc(Vector2(65, 52), 5.0, 0.0, TAU, 20, Color(0.9, 0.78, 0.3), 1.5)
		draw_line(Vector2(69, 55), Vector2(74, 80), Color(0.9, 0.78, 0.3), 1.0)


func _item(kind: String) -> void:
	var wood := Color(0.36, 0.22, 0.12)
	match kind:
		"staff_fire", "staff_ice", "staff_wood", "staff_thunder", "staff_dark":
			draw_line(Vector2(104, 48), Vector2(100, 128), wood if kind != "staff_dark" else Color(0.12, 0.08, 0.14), 4.0)
			match kind:
				"staff_fire":
					var f := 4.0 * sin(_t * 8.0)
					draw_circle(Vector2(104, 44), 9.0, Color(1.0, 0.45, 0.1, 0.35))
					draw_circle(Vector2(104, 44), 6.0, Color(1.0, 0.65, 0.2))
					_poly([Vector2(99, 42), Vector2(109, 42), Vector2(104, 26 + f)], Color(1.0, 0.5, 0.1))
				"staff_ice":
					_poly([Vector2(104, 26), Vector2(111, 40), Vector2(104, 52), Vector2(97, 40)], Color(0.75, 0.95, 1.0))
					_poly([Vector2(104, 30), Vector2(107, 40), Vector2(104, 48), Vector2(101, 40)], Color(1, 1, 1))
				"staff_wood":
					draw_line(Vector2(104, 48), Vector2(110, 36), wood, 3.0)
					draw_line(Vector2(104, 48), Vector2(98, 36), wood, 3.0)
					draw_circle(Vector2(104, 38), 6.0, Color(0.4, 0.7, 1.0))
				"staff_thunder":
					_poly([Vector2(104, 18), Vector2(96, 36), Vector2(103, 36), Vector2(98, 52), Vector2(112, 30), Vector2(105, 30), Vector2(110, 18)], Color(1.0, 0.92, 0.3))
				"staff_dark":
					draw_circle(Vector2(104, 42), 8.0, Color(0.6, 0.25, 0.9, 0.35))
					draw_circle(Vector2(104, 42), 6.0, Color(0.85, 0.82, 0.78))
					draw_circle(Vector2(102, 41), 1.5, Color(0.6, 0.2, 1.0))
					draw_circle(Vector2(106, 41), 1.5, Color(0.6, 0.2, 1.0))
		"scythe":
			draw_line(Vector2(102, 14), Vector2(108, 128), Color(0.25, 0.2, 0.16), 4.0)
			_poly([Vector2(102, 14), Vector2(60, 8), Vector2(34, 22), Vector2(70, 16), Vector2(102, 22)], Color(0.82, 0.85, 0.9))
		"crossbow":
			draw_arc(Vector2(96, 96), 18.0, -PI * 0.85, -PI * 0.15, 16, wood, 4.0)
			draw_line(Vector2(80, 92), Vector2(112, 92), Color(0.85, 0.85, 0.85), 1.0)
			draw_line(Vector2(96, 80), Vector2(96, 120), wood, 5.0)
		"daggers":
			for side in [-1.0, 1.0]:
				var base := Vector2(64 + side * 30, 112)
				_poly([base, base + Vector2(side * 10, -26), base + Vector2(side * 4, 2)], Color(0.85, 0.88, 0.92))
				draw_line(base + Vector2(-6, 2), base + Vector2(6, 2), Color(0.3, 0.2, 0.1), 3.0)
		"club":
			_poly([Vector2(92, 128), Vector2(100, 128), Vector2(122, 70), Vector2(106, 62)], Color(0.45, 0.3, 0.16))
			for p in [Vector2(110, 70), Vector2(116, 82), Vector2(104, 78)]:
				draw_circle(p, 2.5, Color(0.75, 0.72, 0.65))
		"katana":
			draw_line(Vector2(96, 20), Vector2(36, 112), Color(0.9, 0.92, 0.95), 3.0)
			draw_line(Vector2(96, 20), Vector2(106, 6), Color(0.15, 0.12, 0.1), 5.0)
		"revolver":
			_poly([Vector2(90, 100), Vector2(114, 100), Vector2(114, 106), Vector2(98, 106), Vector2(96, 118), Vector2(90, 118)], Color(0.3, 0.3, 0.32))
			draw_circle(Vector2(98, 103), 4.0, Color(0.4, 0.4, 0.42))
		"spear":
			draw_line(Vector2(108, 18), Vector2(100, 128), wood, 3.0)
			_poly([Vector2(104, 6), Vector2(112, 22), Vector2(104, 20)], Color(0.85, 0.88, 0.92))
		"chains":
			for side in [-1.0, 1.0]:
				for k in 4:
					draw_arc(Vector2(64 + side * 34, 76 + k * 8.0), 3.5, 0, TAU, 10, Color(0.55, 0.6, 0.6), 1.5)
		"flask":
			_ellipse(Vector2(102, 108), 10, 10, Color(0.8, 0.9, 0.95, 0.7))
			_ellipse(Vector2(102, 111), 8, 6, Color(0.35, 0.95, 0.3))
			_poly([Vector2(99, 90), Vector2(105, 90), Vector2(105, 99), Vector2(99, 99)], Color(0.8, 0.9, 0.95, 0.7))
		"web":
			var c := Vector2(8, 8)
			for k in 6:
				var a := PI * 0.5 * k / 5.0
				draw_line(c, c + Vector2(cos(a), sin(a)) * 60.0, Color(0.9, 0.9, 0.95, 0.45), 1.0)
			for ring in [18.0, 32.0, 46.0]:
				draw_arc(c, ring, 0, PI * 0.5, 10, Color(0.9, 0.9, 0.95, 0.4), 1.0)
		"bone":
			draw_line(Vector2(92, 116), Vector2(118, 104), Color(0.95, 0.93, 0.85), 4.0)
			for p in [Vector2(90, 114), Vector2(93, 119), Vector2(117, 101), Vector2(120, 106)]:
				draw_circle(p, 3.0, Color(0.95, 0.93, 0.85))
		"maracas":
			for side in [-1.0, 1.0]:
				var base := Vector2(64 + side * 40, 100)
				var shake := 3.0 * sin(_t * 14.0 + side)
				draw_line(base, base + Vector2(0, 18), Color(0.4, 0.25, 0.12), 3.0)
				_ellipse(base + Vector2(shake, -6), 7, 9, Color(0.95, 0.3, 0.3) if side < 0 else Color(0.3, 0.75, 0.95))
		"ladle":
			draw_line(Vector2(110, 40), Vector2(98, 120), wood, 3.0)
			_ellipse(Vector2(111, 36), 8, 6, Color(0.5, 0.45, 0.4))
			draw_circle(Vector2(111, 34), 4.0, Color(0.45, 0.9, 0.3))
		"sword":
			_poly([Vector2(104, 20), Vector2(108, 20), Vector2(108, 100), Vector2(104, 100)], Color(0.85, 0.88, 0.92))
			_poly([Vector2(96, 100), Vector2(116, 100), Vector2(116, 104), Vector2(96, 104)], Color(0.6, 0.45, 0.15))
			draw_line(Vector2(106, 104), Vector2(106, 118), Color(0.35, 0.2, 0.1), 4.0)


func _fx(kind: String) -> void:
	for k in 14:
		var h := fmod(float(k) * 0.6180339 + 0.13, 1.0)
		var x := 8.0 + h * 112.0
		var speed := 10.0 + (k % 5) * 4.0
		var y := 128.0 - fmod(_t * speed + k * 37.0, 128.0)
		match kind:
			"embers":
				draw_circle(Vector2(x, y), 1.4 + (k % 3) * 0.6, Color(1.0, 0.55 + 0.1 * (k % 3), 0.15, 0.85))
			"snow":
				draw_circle(Vector2(x + 3.0 * sin(_t + k), 128.0 - y), 1.5 + (k % 2), Color(1, 1, 1, 0.85))
			"stars":
				if k % 2 == 0:
					_star(Vector2(x, fmod(h * 300.0, 60.0) + 4.0), 2.0 + (k % 3) * 0.6 * (0.6 + 0.4 * sin(_t * 3.0 + k)), Color(1.0, 0.95, 0.7))
			"sparks":
				if fmod(_t * 3.0 + k * 0.7, 2.0) < 0.6:
					var p := Vector2(x, fmod(h * 500.0, 110.0) + 8.0)
					draw_polyline(PackedVector2Array([p, p + Vector2(4, 5), p + Vector2(-1, 8), p + Vector2(5, 14)]), Color(1.0, 0.95, 0.4), 1.5)
			"shadow":
				_ellipse(Vector2(x, 120 + 4.0 * sin(_t + k)), 14, 6, Color(0.35, 0.1, 0.5, 0.18))
			"wisps":
				draw_circle(Vector2(x, y), 3.0 + (k % 3), Color(0.8, 0.95, 1.0, 0.12))
			"bubbles":
				if k % 2 == 0:
					draw_arc(Vector2(x, y), 2.0 + (k % 3), 0, TAU, 12, Color(0.6, 1.0, 0.5, 0.7), 1.0)
			"spores":
				draw_circle(Vector2(x + 2.0 * sin(_t * 2.0 + k), y), 1.2, Color(1.0, 0.95, 0.8, 0.6))


func _star(c: Vector2, r: float, col: Color) -> void:
	_poly([c + Vector2(0, -r * 2), c + Vector2(r * 0.5, -r * 0.5), c + Vector2(r * 2, 0), c + Vector2(r * 0.5, r * 0.5),
		c + Vector2(0, r * 2), c + Vector2(-r * 0.5, r * 0.5), c + Vector2(-r * 2, 0), c + Vector2(-r * 0.5, -r * 0.5)], col)


func _padlock() -> void:
	draw_rect(Rect2(0, 0, 128, 128), Color(0.0, 0.0, 0.02, 0.45))
	var c := Vector2(108, 108)
	draw_arc(c + Vector2(0, -6), 7.0, PI, TAU, 14, Color(0.8, 0.78, 0.72), 3.0)
	draw_rect(Rect2(c + Vector2(-10, -6), Vector2(20, 16)), Color(0.85, 0.7, 0.3))
	draw_rect(Rect2(c + Vector2(-10, -6), Vector2(20, 16)), Color(0.3, 0.2, 0.05), false, 1.5)
	draw_circle(c + Vector2(0, 1), 2.5, Color(0.2, 0.12, 0.03))
