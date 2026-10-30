class_name ShardIcon
extends Control
## An elemental shard drawn in code: a faceted crystal (tall hexagonal gem with a pointed top
## and bottom) in its element's colours, light and dark facets, a bright edge, a small inner
## symbol and a slow glint. Kinds: Wallet.SHARDS ("fire", "ice", "lightning", "dark").

const COLORS := {
	"fire": [Color(1.0, 0.5, 0.12), Color(0.75, 0.18, 0.05), Color(1.0, 0.85, 0.45)],
	"ice": [Color(0.55, 0.85, 1.0), Color(0.2, 0.5, 0.85), Color(0.9, 0.98, 1.0)],
	"lightning": [Color(1.0, 0.92, 0.3), Color(0.8, 0.6, 0.05), Color(1.0, 1.0, 0.8)],
	"dark": [Color(0.62, 0.3, 0.95), Color(0.3, 0.1, 0.5), Color(0.85, 0.65, 1.0)],
}

var kind := "fire"
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _draw() -> void:
	draw_shard(self, size * 0.5, minf(size.x, size.y) * 0.5, kind, _t)


static func draw_shard(ci: CanvasItem, c: Vector2, r: float, p_kind: String, t := 0.0) -> void:
	var cols: Array = COLORS.get(p_kind, COLORS["fire"])
	var mid: Color = cols[0]
	var dark: Color = cols[1]
	var light: Color = cols[2]
	var w := r * 0.52
	var top := c + Vector2(0, -r)
	var bot := c + Vector2(0, r)
	var ul := c + Vector2(-w, -r * 0.42)
	var ur := c + Vector2(w, -r * 0.42)
	var ll := c + Vector2(-w, r * 0.42)
	var lr := c + Vector2(w, r * 0.42)
	var cm := c + Vector2(r * 0.08, 0)   # the front ridge, a little off centre
	# glow
	ci.draw_circle(c, r * 0.95, Color(mid.r, mid.g, mid.b, 0.16))
	# facets: left side darker, right side lit
	ci.draw_colored_polygon(PackedVector2Array([top, ul, ll, bot, cm]), dark)
	ci.draw_colored_polygon(PackedVector2Array([top, cm, bot, lr, ur]), mid)
	ci.draw_colored_polygon(PackedVector2Array([top, ur, cm]), light)
	ci.draw_colored_polygon(PackedVector2Array([ul, top, cm]), mid.lerp(dark, 0.4))
	# outline and ridge
	var edge := PackedVector2Array([top, ur, lr, bot, ll, ul, top])
	ci.draw_polyline(edge, light.lerp(Color.WHITE, 0.3), maxf(1.0, r * 0.07), true)
	ci.draw_line(top, cm, Color(light, 0.8), maxf(1.0, r * 0.05), true)
	ci.draw_line(cm, bot, Color(dark.darkened(0.3), 0.8), maxf(1.0, r * 0.04), true)
	# glint sweeping down the lit face now and then
	var g := fmod(t * 0.45 + (0.3 if p_kind == "ice" else 0.0) + (0.6 if p_kind == "dark" else 0.0), 1.6)
	if g < 1.0:
		var gy := lerpf(-r * 0.8, r * 0.7, g)
		ci.draw_line(c + Vector2(r * 0.12, gy - r * 0.12), c + Vector2(w * 0.85, gy + r * 0.06), Color(1, 1, 1, 0.65 * sin(g * PI)), maxf(1.0, r * 0.08), true)
