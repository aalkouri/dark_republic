extends Control
## Character select: a 6-wide grid of 23 procedurally drawn portraits on the left and a preview
## panel on the right (live 3D model for playable characters, a large portrait for locked
## ones), with name, epithet, bio and kit. Only the Fire Wizard is unlocked for now.
## Keyboard, gamepad and mouse all work; Esc / Back returns to the title.

const DATA := "res://data/characters.json"
const TITLE_SCENE := "res://scenes/title.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const MUSIC := "res://audio/music/tension_drop.mp3"
const COLUMNS := 6
const TILE := 120.0

var characters: Array = []
var _tiles: Array[Button] = []
var _shown := -1
var _font: FontVariation
var _font_bold: FontVariation
var _name: Label
var _epithet: Label
var _bio: Label
var _kit: Label
var _status: Label
var _big_icon: CharacterIcon
var _view_box: SubViewportContainer
var _model_pivot: Node3D
var _play_btn: Button
var _back_btn: Button
var _music: AudioStreamPlayer
var _fade: ColorRect
var _leaving := false
var _t := 0.0


func _ready() -> void:
	characters = load_characters()
	_build_fonts()
	_build_background()
	_build_grid()
	_build_panel()
	_build_footer()
	_build_music()
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.5)
	var start := maxi(0, index_of(Settings.selected_character))
	_show(start)
	_tiles[start].grab_focus.call_deferred()
	_shot_setup()


static func load_characters() -> Array:
	var f := FileAccess.open(DATA, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed["characters"]


func index_of(id: String) -> int:
	for k in characters.size():
		if characters[k]["id"] == id:
			return k
	return -1


func is_unlocked(k: int) -> bool:
	return bool(characters[k].get("unlocked", false))


# ------------------------------------------------------------------ building

func _build_fonts() -> void:
	var base := load("res://fonts/Cinzel.ttf") as FontFile
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	_font = FontVariation.new()
	_font.base_font = base
	_font.variation_opentype = {wght: 600}
	_font_bold = FontVariation.new()
	_font_bold.base_font = base
	_font_bold.variation_opentype = {wght: 900}


func _label(text: String, size: int, col: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font_bold if bold else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _build_background() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float t;
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.05, 0.06, 0.05);
	vec3 bot = vec3(0.13, 0.05, 0.02);
	vec3 c = mix(top, bot, smoothstep(0.1, 1.0, uv.y));
	float glow = exp(-pow(distance(uv, vec2(0.74, 0.62)) * 2.6, 2.0));
	c += vec3(0.35, 0.12, 0.03) * glow * (0.85 + 0.15 * sin(t * 1.7));
	float vig = smoothstep(1.1, 0.35, distance(uv, vec2(0.5)));
	COLOR = vec4(c * vig, 1.0);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	bg.material = m
	add_child(bg)
	var embers := CPUParticles2D.new()
	embers.amount = 60
	embers.lifetime = 6.0
	embers.preprocess = 6.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(820, 10)
	embers.position = Vector2(800, 920)
	embers.direction = Vector2(0, -1)
	embers.spread = 15.0
	embers.gravity = Vector2(0, -8)
	embers.initial_velocity_min = 30.0
	embers.initial_velocity_max = 90.0
	embers.scale_amount_min = 1.5
	embers.scale_amount_max = 3.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.7, 0.3, 0.9))
	grad.set_color(1, Color(0.8, 0.15, 0.0, 0.0))
	embers.color_ramp = grad
	add_child(embers)

	var heading := _label("CHOOSE YOUR CHAMPION", 46, Color(1.0, 0.72, 0.35), true)
	heading.add_theme_color_override("font_shadow_color", Color(1.0, 0.35, 0.05, 0.45))
	heading.add_theme_constant_override("shadow_outline_size", 16)
	heading.add_theme_constant_override("shadow_offset_x", 0)
	heading.add_theme_constant_override("shadow_offset_y", 0)
	heading.position = Vector2(64, 36)
	add_child(heading)
	var count := 0
	for c in characters:
		if c.get("unlocked", false):
			count += 1
	var sub := _label("%d of %d unlocked" % [count, characters.size()], 20, Color(0.8, 0.74, 0.64, 0.8))
	sub.position = Vector2(68, 98)
	add_child(sub)


func _tile_style(border: Color, width: int, fill: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	return s


func _build_grid() -> void:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.position = Vector2(64, 146)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	add_child(grid)
	for k in characters.size():
		var c: Dictionary = characters[k]
		var b := Button.new()
		b.custom_minimum_size = Vector2(TILE, TILE)
		b.focus_mode = Control.FOCUS_ALL
		b.tooltip_text = ""
		var unlocked := is_unlocked(k)
		var rim := Color(0.95, 0.6, 0.2) if unlocked else Color(0.3, 0.28, 0.26)
		b.add_theme_stylebox_override("normal", _tile_style(rim.darkened(0.2), 2, Color(0, 0, 0, 0.5)))
		b.add_theme_stylebox_override("hover", _tile_style(Color(1.0, 0.75, 0.35), 3, Color(0, 0, 0, 0.5)))
		b.add_theme_stylebox_override("focus", _tile_style(Color(1.0, 0.8, 0.4), 4, Color(0, 0, 0, 0)))
		b.add_theme_stylebox_override("pressed", _tile_style(Color(1.0, 0.9, 0.6), 4, Color(0, 0, 0, 0.5)))
		var icon := CharacterIcon.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 4
		icon.offset_top = 4
		icon.offset_right = -4
		icon.offset_bottom = -4
		icon.locked = not unlocked
		icon.animate = false
		icon.set_icon(c["icon"])
		icon.clip_contents = true
		b.add_child(icon)
		b.set_meta("icon", icon)
		b.focus_entered.connect(_show.bind(k))
		b.mouse_entered.connect(func(): b.grab_focus())
		b.pressed.connect(_choose.bind(k))
		grid.add_child(b)
		_tiles.append(b)


func _build_panel() -> void:
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.03, 0.025, 0.02, 0.72)
	ps.border_color = Color(0.55, 0.3, 0.12, 0.8)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(10)
	ps.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", ps)
	panel.position = Vector2(860, 40)
	panel.custom_minimum_size = Vector2(690, 740)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	# Preview area: 3D model or a large portrait, same footprint
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(640, 360)
	v.add_child(stage)
	_view_box = SubViewportContainer.new()
	_view_box.stretch = true
	_view_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_view_box)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	_view_box.add_child(vp)
	_build_model_stage(vp)
	_big_icon = CharacterIcon.new()
	_big_icon.custom_minimum_size = Vector2(340, 340)
	_big_icon.size = Vector2(340, 340)
	_big_icon.position = Vector2((640 - 340) * 0.5, 10)
	stage.add_child(_big_icon)

	_name = _label("", 44, Color(1.0, 0.86, 0.6), true)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_name)
	_epithet = _label("", 22, Color(1.0, 0.55, 0.2))
	_epithet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_epithet)
	_bio = _label("", 19, Color(0.86, 0.8, 0.7))
	_bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bio.custom_minimum_size = Vector2(640, 0)
	v.add_child(_bio)
	_kit = _label("", 18, Color(0.95, 0.75, 0.45))
	_kit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_kit.custom_minimum_size = Vector2(640, 0)
	v.add_child(_kit)
	_status = _label("", 20, Color(0.7, 0.68, 0.64))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)


func _build_model_stage(vp: SubViewport) -> void:
	var root := Node3D.new()
	vp.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.4, 0.38)
	env.environment.ambient_light_energy = 0.8
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.1
	root.add_child(sun)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.5, 0.18)
	warm.light_energy = 2.0
	warm.omni_range = 6.0
	warm.position = Vector3(0.8, 1.6, 1.5)
	root.add_child(warm)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.6, 7.4)
	cam.look_at_from_position(cam.position, Vector3(0, 1.3, 0))
	root.add_child(cam)
	cam.current = true
	_model_pivot = Node3D.new()
	root.add_child(_model_pivot)
	var mb := MeshBuilder.new()
	var stone := Color(0.3, 0.3, 0.28, 0.0)
	mb.add(MeshBuilder.cyl(0.95, 1.05, 0.18, 12), Transform3D(Basis(), Vector3(0, -0.09, 0)), stone)
	var disc := MeshInstance3D.new()
	disc.mesh = mb.commit()
	_model_pivot.add_child(disc)
	_model_pivot.add_child(WizardModel.new())


func _build_footer() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(860, 800)
	row.custom_minimum_size = Vector2(690, 70)
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	_back_btn = _footer_button("Back", _back)
	row.add_child(_back_btn)
	_play_btn = _footer_button("Play", _play)
	row.add_child(_play_btn)
	var hint := _label("Enter: choose   ·   Esc: back", 16, Color(0.75, 0.7, 0.62, 0.6))
	hint.position = Vector2(66, 690)
	add_child(hint)


func _footer_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.custom_minimum_size = Vector2(240, 60)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", _font_bold)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.9, 0.84, 0.74))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.7, 0.3))
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.7, 0.3))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.42, 0.4))
	b.add_theme_stylebox_override("normal", _tile_style(Color(0.55, 0.3, 0.12), 2, Color(0.08, 0.04, 0.02, 0.85)))
	b.add_theme_stylebox_override("hover", _tile_style(Color(1.0, 0.6, 0.2), 3, Color(0.2, 0.07, 0.02, 0.9)))
	b.add_theme_stylebox_override("focus", _tile_style(Color(1.0, 0.7, 0.3), 3, Color(0.2, 0.07, 0.02, 0.9)))
	b.add_theme_stylebox_override("pressed", _tile_style(Color(1.0, 0.85, 0.5), 3, Color(0.3, 0.1, 0.02, 0.9)))
	b.add_theme_stylebox_override("disabled", _tile_style(Color(0.25, 0.22, 0.2), 2, Color(0.05, 0.05, 0.05, 0.8)))
	b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
	b.pressed.connect(cb)
	return b


func _build_music() -> void:
	_music = AudioStreamPlayer.new()
	var stream := load(MUSIC) as AudioStreamMP3
	if stream:
		stream = stream.duplicate()
		stream.loop = true
		_music.stream = stream
	_music.bus = Settings.MUSIC_BUS
	add_child(_music)
	_music.play()


# ------------------------------------------------------------------ behaviour

func _show(k: int) -> void:
	if k == _shown:
		return
	_shown = k
	var c: Dictionary = characters[k]
	var unlocked := is_unlocked(k)
	_name.text = c["name"]
	_epithet.text = c.get("epithet", "")
	_bio.text = c.get("bio", "")
	var kit: Array = c.get("kit", [])
	_kit.text = "  ·  ".join(kit) if unlocked else ""
	_kit.visible = unlocked
	if unlocked:
		_status.text = "SELECTED" if Settings.selected_character == c["id"] else "Press Enter to choose"
		_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	else:
		_status.text = "LOCKED  -  coming soon"
		_status.add_theme_color_override("font_color", Color(0.65, 0.62, 0.58))
	# Playable characters get the live model; locked ones a big portrait
	_view_box.visible = unlocked
	_big_icon.visible = not unlocked
	_big_icon.locked = not unlocked
	_big_icon.set_icon(c["icon"])
	for j in _tiles.size():
		(_tiles[j].get_meta("icon") as CharacterIcon).animate = j == k
	_play_btn.disabled = not unlocked


func _choose(k: int) -> void:
	_show(k)
	if not is_unlocked(k):
		var tile := _tiles[k]
		var tw := create_tween()   # "nope" shake
		var x := tile.position.x
		for d in [-6.0, 6.0, -4.0, 4.0, 0.0]:
			tw.tween_property(tile, "position:x", x + d, 0.04)
		return
	Settings.selected_character = characters[k]["id"]
	_shown = -1
	_show(k)
	_play_btn.grab_focus()


func _play() -> void:
	if _leaving or _shown < 0 or not is_unlocked(_shown):
		return
	Settings.selected_character = characters[_shown]["id"]
	_leave(GAME_SCENE)


func _back() -> void:
	_leave(TITLE_SCENE)


func _leave(scene: String) -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	tw.tween_property(_music, "volume_db", -40.0, 0.45)
	tw.chain().tween_callback(func(): get_tree().change_scene_to_file(scene))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	_t += dt
	_model_pivot.rotation.y = PI - 0.55 + sin(_t * 0.5) * 0.35   # face the camera, sway to show the train
	_shot_tick()


# ------------------------------------------------------------------ screenshots
# -- --shot=/path.png --shot-at=SECONDS [--shot-char=id]

var _shot_path := ""
var _shot_at := 2.0


func _shot_setup() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.split("=")[1]
		elif a.begins_with("--shot-at="):
			_shot_at = float(a.split("=")[1])
		elif a.begins_with("--shot-char="):
			var k := index_of(a.split("=")[1])
			if k >= 0:
				_tiles[k].grab_focus.call_deferred()


func _shot_tick() -> void:
	if _shot_path == "" or _t < _shot_at:
		return
	var path := _shot_path
	_shot_path = ""
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT saved ", path)
	get_tree().quit()
