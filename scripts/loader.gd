extends CanvasLayer
## Loading screen (autoload "Loader"). Every scene change in the game goes through
## Loader.go(path): it loads the scene on a background thread (ResourceLoader.load_threaded_*)
## while a full-screen loading overlay shows, swaps scenes, waits until the new scene has built
## and drawn its first frames, then fades the overlay out.
##
## When it shows: straight away for transitions known to be slow (into a run, which builds the
## whole map in Main._ready; into the title, which builds its swamp diorama; leaving a run, which
## frees a whole world; any scene that took over SLOW_AFTER seconds last time). Otherwise only if
## the background load is still going after DELAY seconds, so quick changes never flash it.
##
## What it shows: the destination map's preview picture (blurred and dimmed) with its name and
## your character when loading into a run, a spinning rune circle, drifting embers and a TIP box
## with tips from data/tips.json that rotate every TIP_TIME seconds (shuffled, never the same twice
## in a row; any key, click or pad button skips to the next one). Tips are translated with tr().
##
## The world builders run synchronously in _ready, so the overlay freezes (but stays up) while
## the map is built; it's drawn first, so you're never left looking at a black screen.
##
## Tests/screenshots: Loader.hold = true keeps the overlay up after the scene is ready (or
## `-- --loader-hold`), until hold is set back to false.

signal finished(path: String)

const TIPS := "res://data/tips.json"
const MAIN_SCENE := "res://scenes/main.tscn"
const SLOW_SCENES := ["res://scenes/main.tscn", "res://scenes/title.tscn"]
const TIP_TIME := 4.5        # seconds each tip stays up
const TIP_FADE := 0.4        # crossfade between tips (out, then in)
const FADE_IN := 0.15
const FADE_OUT := 0.3
const DELAY := 0.25          # unknown transitions: show the overlay only if still loading by then
const MIN_SHOW := 0.8        # once shown, stay up at least this long (no flashes)
const SETTLE_FRAMES := 3     # frames the new scene draws under the overlay before it fades
const POLL_MAX := 3.0        # poll the background load this long (animating), then finish it blocking
const SLOW_AFTER := 1.0      # a scene that took longer than this last time shows the overlay next time

const GOLD := Color(1.0, 0.72, 0.35)
const PARCHMENT := Color(0.9, 0.84, 0.74)

var busy := false            # a transition is under way
var showing := false         # the overlay is up (fading in, shown or fading out)
var hold := false            # tests/screenshots: keep the overlay up after the scene is ready
var tips: Array = []
var tip_index := -1
var last_duration := 0.0     # seconds the last transition took (go() to scene ready)
var last_path := ""
var shown_count := 0         # how many transitions have shown the overlay (tests)

var _durations := {}         # path -> seconds it took last time
var _bag: Array = []
var _tip_t := 0.0
var _shown_t := 0.0
var _bg_cache := {}          # map id -> blurred ImageTexture
var _font: FontVariation
var _font_bold: FontVariation
var _root: Control
var _bg: TextureRect
var _heading_box: VBoxContainer
var _heading: Label
var _sub: Label
var _spinner: _RuneSpinner
var _loading_lbl: Label
var _tip_label: Label
var _tip_head: Label
var _hint: Label
var _fade_tw: Tween
var _tip_tw: Tween


func _ready() -> void:
	layer = 128   # above everything, the coin counter (90) included
	process_mode = Node.PROCESS_MODE_ALWAYS
	tips = load_tips()
	_build()
	_root.visible = false
	if "--loader-hold" in OS.get_cmdline_user_args():
		hold = true


static func load_tips() -> Array:
	var f := FileAccess.open(TIPS, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	return (d as Array).filter(func(s): return s is String and (s as String).strip_edges() != "") if d is Array else []


## Is this transition slow enough to show the loading screen straight away?
func is_slow(path: String) -> bool:
	if path in SLOW_SCENES:
		return true
	var cur := get_tree().current_scene
	if cur != null and cur.scene_file_path == MAIN_SCENE:   # leaving a run frees a whole world
		return true
	return float(_durations.get(path, 0.0)) > SLOW_AFTER


## Change to the scene at `path` behind the loading screen. `slow` forces the overlay on (true)
## or leaves it to the DELAY rule (false); by default is_slow() decides.
func go(path: String, slow = null) -> void:
	if busy:
		return
	busy = true
	last_path = path
	var t0 := Time.get_ticks_msec()
	_prepare(path)
	if (slow if slow != null else is_slow(path)):
		_show()
	var ok := ResourceLoader.load_threaded_request(path) == OK
	while ok and _loading(path) and Time.get_ticks_msec() - t0 < POLL_MAX * 1000.0:
		await get_tree().process_frame   # the overlay keeps animating while the scene loads
		if not showing and Time.get_ticks_msec() - t0 > DELAY * 1000.0:   # wall clock: what you'd notice
			_show()
	if ok and _loading(path):
		_show()
	if showing:
		# Make sure the overlay is fully drawn before a scene that may freeze the game while it builds
		while _root.modulate.a < 1.0 and showing:
			await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
	var ps: PackedScene = null
	if ok and ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_FAILED:
		# Blocks if it's still loading after POLL_MAX: finishing on the main thread beats waiting
		# a frame for each resource the loader thread hands to the renderer
		ps = ResourceLoader.load_threaded_get(path) as PackedScene
	get_tree().paused = false
	if ps != null:
		get_tree().change_scene_to_packed(ps)
	else:
		get_tree().change_scene_to_file(path)
	await get_tree().scene_changed
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	last_duration = (Time.get_ticks_msec() - t0) / 1000.0
	_durations[path] = last_duration
	if showing:
		while _shown_t < MIN_SHOW or hold:
			await get_tree().process_frame
		_hide()
		while showing:
			await get_tree().process_frame
	busy = false
	finished.emit(path)


func _loading(path: String) -> bool:
	return ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS


## The tip on screen now (translated).
func current_tip() -> String:
	return tr(tips[tip_index]) if tip_index >= 0 and tip_index < tips.size() else ""


## Crossfade to another tip (random, never the one showing).
func next_tip() -> void:
	tip_index = _pick_tip()
	_tip_t = 0.0
	var text := current_tip()
	if _tip_tw:
		_tip_tw.kill()
	if not showing or _tip_label.text == "":
		_tip_label.text = text
		_tip_label.modulate.a = 1.0
		return
	_tip_tw = create_tween()
	_tip_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tip_tw.tween_property(_tip_label, "modulate:a", 0.0, TIP_FADE * 0.5)
	_tip_tw.tween_callback(func(): _tip_label.text = text)
	_tip_tw.tween_property(_tip_label, "modulate:a", 1.0, TIP_FADE * 0.5)


func _pick_tip() -> int:
	if tips.is_empty():
		return -1
	if tips.size() == 1:
		return 0
	if _bag.is_empty():
		_bag = range(tips.size())
		_bag.shuffle()
		if _bag.back() == _last_pick:   # the next pick comes off the back: no repeat across bags
			_bag.push_front(_bag.pop_back())
	_last_pick = _bag.pop_back()
	return _last_pick


var _last_pick := -1


func _process(delta: float) -> void:
	if not _root.visible:
		return
	_shown_t += delta
	_tip_t += delta
	if _tip_t >= TIP_TIME:
		next_tip()
	_loading_lbl.modulate.a = 0.55 + 0.45 * sin(_shown_t * 3.0)
	_loading_lbl.text = tr("LOADING") + ".".repeat(int(_shown_t * 2.5) % 4)   # LOADING. .. ...
	_bg.scale = Vector2.ONE * (1.04 + 0.03 * sin(_shown_t * 0.15))   # a slow drift on the picture


var _pump_last := 0

## Keep the loading screen moving while a scene builds in one go (the maps are built in the new
## scene's _ready, which blocks the frame loop for several seconds): called from inside long
## builds (MeshBuilder.commit and the map builders), at most ~30 times a second it steps the
## animation (spinner, LOADING dots, tip timer) and draws a frame on the spot.
func pump() -> void:
	if _root == null or not _root.visible or DisplayServer.get_name() == "headless":
		return
	var now := Time.get_ticks_usec()
	if _pump_last != 0 and now - _pump_last < 33000:
		return
	var dt := 0.033 if _pump_last == 0 else clampf(float(now - _pump_last) / 1e6, 0.0, 0.1)
	_pump_last = now
	_process(dt)
	if _spinner != null:
		_spinner.t += dt
		_spinner.queue_redraw()
	RenderingServer.force_draw(true, 0.0)


func _input(event: InputEvent) -> void:
	if not showing:
		return
	var press: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if press:
		next_tip()
	if press or event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()   # nothing underneath reacts while loading


# ------------------------------------------------------------------ show / hide

func _show() -> void:
	if showing:
		return
	showing = true
	shown_count += 1
	_shown_t = 0.0
	_root.visible = true
	_root.modulate.a = 0.0
	_tip_label.text = ""
	_tip_head.text = tr("TIP")
	_hint.text = tr("Click or press any key for the next tip")
	_loading_lbl.text = tr("LOADING")
	next_tip()
	if _fade_tw:
		_fade_tw.kill()
	_fade_tw = create_tween()
	_fade_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tw.tween_property(_root, "modulate:a", 1.0, FADE_IN)


func _hide() -> void:
	if _fade_tw:
		_fade_tw.kill()
	_fade_tw = create_tween()
	_fade_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tw.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	_fade_tw.tween_callback(func():
		_root.visible = false
		showing = false)


## Heading and background for where we're going: a run shows its map and character.
func _prepare(path: String) -> void:
	if path != MAIN_SCENE:   # the menus: just the game's name
		_heading_box.visible = true
		_heading.text = "DARK REPUBLIC"   # the Label translates it
		_sub.visible = false
		_bg.texture = null
		return
	var map_id: String = Settings.selected_map
	var map_name := ""
	for m in MapPicker.MAPS:
		if m["id"] == map_id:
			map_name = m["name"]
	_heading_box.visible = map_name != ""
	_heading.text = tr(map_name).to_upper()
	_sub.text = tr(_character_name(Settings.selected_character))
	_sub.visible = _sub.text != ""
	_bg.texture = _map_picture(map_id)


static func _character_name(id: String) -> String:
	var f := FileAccess.open("res://data/characters.json", FileAccess.READ)
	if f == null:
		return ""
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for c in d.get("characters", []):
			if c.get("id", "") == id:
				return str(c.get("name", ""))
	return ""


## The map's preview picture, shrunk and blown back up so it's soft and blurred.
func _map_picture(map_id: String) -> Texture2D:
	if _bg_cache.has(map_id):
		return _bg_cache[map_id]
	var path := "res://images/maps/%s.png" % map_id
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	var img := tex.get_image() if tex else null
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var aspect := float(img.get_height()) / img.get_width()
	img.resize(40, int(40.0 * aspect), Image.INTERPOLATE_BILINEAR)
	for w in [80, 160, 320, 640]:   # blow it back up in steps so it stays smooth, no blocks
		img.resize(w, int(w * aspect), Image.INTERPOLATE_BILINEAR)
	var out := ImageTexture.create_from_image(img)
	_bg_cache[map_id] = out
	return out


# ------------------------------------------------------------------ building

func _build() -> void:
	var base := load("res://fonts/Cinzel.ttf") as FontFile
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	_font = FontVariation.new()
	_font.base_font = base
	_font.variation_opentype = {wght: 600}
	_font_bold = FontVariation.new()
	_font_bold.base_font = base
	_font_bold.variation_opentype = {wght: 900}

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var back := ColorRect.new()
	back.color = Color(0.035, 0.022, 0.015)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(back)
	_bg = TextureRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.modulate = Color(0.44, 0.38, 0.33)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.resized.connect(func(): _bg.pivot_offset = _bg.size * 0.5)
	_root.add_child(_bg)
	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
// Dark vignette with a faint ember glow rising from the bottom
uniform vec2 aspect = vec2(1.78, 1.0);
void fragment() {
	vec2 p = (UV - vec2(0.5, 0.45)) * aspect;
	float v = smoothstep(0.35, 1.25, length(p));
	float glow = smoothstep(0.55, 1.0, UV.y) * 0.18;
	vec3 col = mix(vec3(0.0), vec3(0.45, 0.12, 0.02), glow);
	COLOR = vec4(col, clamp(0.38 + 0.6 * v - glow, 0.0, 0.98));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	vignette.material = mat
	_root.add_child(vignette)
	var embers := _Embers.new()
	embers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	embers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(embers)

	# Middle: map name and character, the rune circle, LOADING
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -190
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 22)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_heading_box = VBoxContainer.new()
	_heading_box.add_theme_constant_override("separation", 6)
	_heading_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_heading_box)
	_heading = _label("", 64, GOLD, true)
	_heading.add_theme_color_override("font_shadow_color", Color(1.0, 0.35, 0.05, 0.45))
	_heading.add_theme_constant_override("shadow_outline_size", 18)
	_heading.add_theme_constant_override("shadow_offset_x", 0)
	_heading.add_theme_constant_override("shadow_offset_y", 0)
	_heading_box.add_child(_heading)
	var rule := _Rule.new()
	rule.custom_minimum_size = Vector2(0, 14)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading_box.add_child(rule)
	_sub = _label("", 26, PARCHMENT)
	_heading_box.add_child(_sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading_box.add_child(gap)
	_spinner = _RuneSpinner.new()
	_spinner.custom_minimum_size = Vector2(176, 176)
	_spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_spinner)
	_loading_lbl = _label("LOADING", 22, Color(0.85, 0.66, 0.42, 0.85))
	center.add_child(_loading_lbl)

	# Bottom: the tip box
	var bottom := VBoxContainer.new()
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -34
	bottom.add_theme_constant_override("separation", 10)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bottom)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1080, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.04, 0.025, 0.9)
	st.border_color = Color(0.72, 0.47, 0.2, 0.85)
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.content_margin_left = 26
	st.content_margin_right = 30
	st.content_margin_top = 18
	st.content_margin_bottom = 18
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 14
	panel.add_theme_stylebox_override("panel", st)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(panel)
	_root.resized.connect(func(): panel.custom_minimum_size.x = minf(1080.0, _root.size.x - 32.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	_tip_head = _label("TIP", 30, GOLD, true)
	_tip_head.custom_minimum_size = Vector2(84, 0)
	_tip_head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_tip_head)
	var sep := ColorRect.new()
	sep.color = Color(0.72, 0.47, 0.2, 0.6)
	sep.custom_minimum_size = Vector2(2, 58)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sep)
	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tip_label.custom_minimum_size = Vector2(0, 64)
	_tip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip_label.add_theme_font_size_override("font_size", 24)
	_tip_label.add_theme_color_override("font_color", PARCHMENT)
	_tip_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tip_label.add_theme_constant_override("outline_size", 3)
	row.add_child(_tip_label)
	_hint = _label("", 15, Color(0.8, 0.74, 0.64, 0.55))
	_hint.add_theme_font_override("font", ThemeDB.fallback_font)
	bottom.add_child(_hint)


func _label(text: String, size: int, col: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", _font_bold if bold else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A gold rule with a diamond in the middle, under the map name.
class _Rule extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var col := Color(0.85, 0.6, 0.28, 0.8)
		for s in [-1.0, 1.0]:   # a line each side, fading out towards its end
			for i in 16:
				var a := Vector2(c.x + s * (14.0 + i * 15.0), c.y)
				var b := Vector2(c.x + s * (14.0 + (i + 1) * 15.0), c.y)
				draw_line(a, b, Color(col, col.a * clampf(1.6 - i / 10.0, 0.0, 1.0)), 2.0, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(7, 0), c + Vector2(0, 6), c + Vector2(-7, 0)]), Color(1.0, 0.72, 0.35))


## A circle of runes turning slowly round a sweeping ember arc, a light chasing round the runes.
class _RuneSpinner extends Control:
	const RUNES := [
		[Vector2(-0.3, -1), Vector2(-0.3, 1), Vector2(-0.3, -0.2), Vector2(0.35, -0.75), Vector2(-0.3, 0.25), Vector2(0.35, -0.3)],
		[Vector2(-0.35, 1), Vector2(-0.35, -1), Vector2(-0.35, -1), Vector2(0.35, -0.5), Vector2(0.35, -0.5), Vector2(0.35, 1)],
		[Vector2(-0.3, -1), Vector2(-0.3, 1), Vector2(-0.3, -0.5), Vector2(0.3, 0), Vector2(0.3, 0), Vector2(-0.3, 0.5)],
		[Vector2(-0.3, -1), Vector2(-0.3, 1), Vector2(-0.3, -1), Vector2(0.3, -0.5), Vector2(0.3, -0.5), Vector2(-0.3, 0), Vector2(-0.3, 0), Vector2(0.35, 1)],
		[Vector2(0.3, -0.8), Vector2(-0.3, 0), Vector2(-0.3, 0), Vector2(0.3, 0.8)],
		[Vector2(0, -1), Vector2(0, 1), Vector2(0, -0.1), Vector2(-0.45, -0.8), Vector2(0, -0.1), Vector2(0.45, -0.8)],
		[Vector2(0, -1), Vector2(0, 1), Vector2(0, -1), Vector2(-0.4, -0.45), Vector2(0, -1), Vector2(0.4, -0.45)],
		[Vector2(-0.35, -1), Vector2(-0.35, 1), Vector2(0.35, -1), Vector2(0.35, 1), Vector2(-0.35, -1), Vector2(0.35, -0.2), Vector2(0.35, -1), Vector2(-0.35, -0.2)],
	]
	const COUNT := 12
	var t := 0.0

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 6.0
		draw_circle(c, r + 4.0, Color(0.02, 0.01, 0.005, 0.5))   # a dark disc so it reads on any picture
		for i in 7:   # soft glow
			draw_circle(c, r * (0.25 + i * 0.12), Color(1.0, 0.42, 0.08, 0.03))
		var ring := Color(0.85, 0.6, 0.28, 0.6)
		draw_arc(c, r, 0.0, TAU, 96, ring, 2.0, true)
		draw_arc(c, r - 28.0, 0.0, TAU, 96, Color(ring, 0.4), 1.5, true)
		var rr := r - 14.0
		for k in COUNT:
			var a := t * 0.35 + k * TAU / COUNT
			var phase := fposmod(t * 0.9 - float(k) / COUNT, 1.0)
			var lit := exp(-phase * 7.0)
			var col := Color(0.55, 0.36, 0.18, 0.7).lerp(Color(1.0, 0.85, 0.5, 1.0), lit)
			var pos := c + Vector2(cos(a), sin(a)) * rr
			var xf := Transform2D(a + PI * 0.5, pos)
			var pts: Array = RUNES[k % RUNES.size()]
			for j in range(0, pts.size(), 2):
				draw_line(xf * (pts[j] * 8.0), xf * (pts[j + 1] * 8.0), col, 1.8 + lit, true)
			if lit > 0.3:
				draw_circle(pos, 9.0, Color(1.0, 0.55, 0.15, 0.12 * lit))
		# the sweeping ember arc inside, with a fading tail
		var a0 := -t * 3.4
		var ir := r - 44.0
		for j in 18:
			var s := a0 + j * 0.1
			draw_arc(c, ir, s, s + 0.12, 6, Color(1.0, 0.45 + j * 0.02, 0.1, pow((j + 1) / 18.0, 1.5)), 4.0, true)
		var head := c + Vector2(cos(a0 + 1.8), sin(a0 + 1.8)) * ir
		draw_circle(head, 6.0, Color(1.0, 0.6, 0.2, 0.35))
		draw_circle(head, 3.5, Color(1.0, 0.9, 0.6))
		# an ember at the heart
		var pulse := 0.5 + 0.5 * sin(t * 5.0)
		draw_circle(c, 11.0 + 2.0 * pulse, Color(1.0, 0.35, 0.05, 0.25))
		draw_circle(c, 6.0 + pulse, Color(1.0, 0.6, 0.2, 0.9))
		draw_circle(c, 2.5, Color(1.0, 0.95, 0.8))


## Embers drifting up the screen.
class _Embers extends Control:
	const N := 46
	var _p: Array = []   # [pos, vel, size, life, max]
	var _rng := RandomNumberGenerator.new()

	func _process(delta: float) -> void:
		if not is_visible_in_tree() or size.x < 2.0:
			return
		while _p.size() < N:
			_p.append(_spawn(true))
		for e in _p:
			e[3] -= delta
			e[0] += e[1] * delta
			e[1].x += sin(e[3] * 2.0 + e[2]) * 6.0 * delta
		for i in _p.size():
			if _p[i][3] <= 0.0 or _p[i][0].y < -10.0:
				_p[i] = _spawn(false)
		queue_redraw()

	func _spawn(anywhere: bool) -> Array:
		var y := _rng.randf_range(0.2, 1.0) * size.y if anywhere else size.y + 5.0
		var life := _rng.randf_range(4.0, 9.0)
		return [Vector2(_rng.randf() * size.x, y), Vector2(_rng.randf_range(-10, 10), -_rng.randf_range(25, 70)), _rng.randf_range(1.0, 2.6), life, life]

	func _draw() -> void:
		for e in _p:
			var f: float = clampf(e[3] / e[4], 0.0, 1.0)
			var a := sin(f * PI)
			draw_circle(e[0], e[2] * 2.6, Color(1.0, 0.4, 0.08, 0.12 * a))
			draw_circle(e[0], e[2], Color(1.0, 0.7, 0.3, 0.75 * a))
