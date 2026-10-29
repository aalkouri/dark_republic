extends Node3D
## Title screen: a living swamp diorama. The fire wizard stands on a mossy dais at night while
## the camera slowly orbits him; goblin silhouettes with glowing eyes lurk at the edge of his
## light, creep in and back off, and grunt now and then. "DARK REPUBLIC" burns over a menu of
## Play / Settings / Quit (mouse, keyboard or gamepad).

const GAME_SCENE := "res://scenes/main.tscn"
const CHARACTER_SCENE := "res://scenes/character_select.tscn"
const TAGLINES := "res://data/taglines.json"
const TAGLINE_TIME := 5.0   # seconds each pun stays up
const WORLD_SEED := 1            # a night-time swamp
const ORBIT_RADIUS := 7.5
const ORBIT_HEIGHT := 2.7
const ORBIT_PERIOD := 70.0       # seconds per full turn
const DAIS_HEIGHT := 1.0
const GOBLINS := 10
const TITLE_SHADER := """
shader_type canvas_item;
// Burning lettering: a flickering fire gradient (white-hot at the base, deep red at the top)
uniform vec4 rect;   // x, y, w, h of the label in screen UV
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 local = (SCREEN_UV - rect.xy) / rect.zw;
	float n = noise(vec2(local.x * 14.0, local.y * 5.0 + TIME * 2.4)) * 0.6 + noise(vec2(local.x * 37.0, local.y * 11.0 + TIME * 4.0)) * 0.4;
	float heat = clamp(local.y * 1.15 + (n - 0.5) * 0.55, 0.0, 1.0);
	vec3 col = mix(vec3(0.55, 0.04, 0.02), vec3(1.0, 0.42, 0.06), smoothstep(0.1, 0.6, heat));
	col = mix(col, vec3(1.0, 0.93, 0.62), smoothstep(0.72, 1.0, heat));
	col *= 0.9 + 0.2 * sin(TIME * 13.0 + local.x * 6.0) * sin(TIME * 7.0);
	COLOR = vec4(col, tex.a * COLOR.a);
}
"""

var _cam: Camera3D
var _t := 0.0
var _goblins: Array = []        # {node, a, r, phase, creep, creep_t, anim}
var _goblin_vat: VatCrowd
var _goblin_mm: MultiMesh
var _music: AudioStreamPlayer
var _tagline: Label
var _taglines: Array = []
var _tag_i := 0
var _tag_t := 0.0
var _tag_first := true
var _ui: CanvasLayer
var _title: Label
var _title_mat: ShaderMaterial
var _menu: VBoxContainer
var _settings: SettingsMenu
var _modes: ModeMenu
var _reveal_sfx: AudioStreamPlayer
var _fade: ColorRect
var _leaving := false
var _font: FontVariation
var _font_bold: FontVariation


func _ready() -> void:
	Wallet.set_shown(true)
	load("res://scripts/main.gd").setup_inputs()
	Settings.apply_bindings()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()
	_build_wizard()
	_build_goblins()
	_build_audio()
	_build_ui()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 300.0
	add_child(_cam)
	_cam.current = true
	_update_camera(0.0)
	_shot_setup()


# ------------------------------------------------------------------ world

func _build_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED
	WorldBuilder.build(self, rng, 110.0)
	for n in get_children():
		if n is WorldEnvironment:
			var env: Environment = (n as WorldEnvironment).environment
			env.fog_density = 0.03                       # thicker, moodier
			env.ambient_light_energy = 0.8
			env.glow_intensity = 1.1


func _build_wizard() -> void:
	# Mossy stone dais
	var mb := MeshBuilder.new()
	var stone := Color(0.34, 0.35, 0.32, 0.0)
	var moss := Color(0.26, 0.34, 0.13, 0.0)
	mb.add(MeshBuilder.cyl(1.35, 1.6, DAIS_HEIGHT, 10), Transform3D(Basis(), Vector3(0, DAIS_HEIGHT * 0.5, 0)), stone)
	mb.add(MeshBuilder.cyl(1.45, 1.45, 0.12, 10), Transform3D(Basis(), Vector3(0, DAIS_HEIGHT, 0)), stone)
	mb.add(MeshBuilder.sphere(1.5, 12, 5), Transform3D(Basis.from_scale(Vector3(1.0, 0.12, 1.0)), Vector3(0.2, DAIS_HEIGHT + 0.05, -0.3)), moss)
	for k in 5:
		var a := TAU * k / 5.0 + 0.4
		var s := 0.35 + 0.15 * (k % 3)
		mb.add(MeshBuilder.box(Vector3(s, s * 0.6, s * 1.2)), Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 2.2, s * 0.25, sin(a) * 2.2)), stone)
	var dais := MeshInstance3D.new()
	dais.mesh = mb.commit()
	add_child(dais)

	var wizard := HeroModel.new()
	wizard.position = Vector3(0, DAIS_HEIGHT + 0.06, 0)
	add_child(wizard)
	wizard.rotation.y = PI * 0.15

	# Embers drifting up around him
	var embers := Abilities._flame_particles(0.12, 3.0, 60)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 2.2
	embers.position = Vector3(0, DAIS_HEIGHT + 0.8, 0)
	embers.gravity = Vector3(0, 0.6, 0)
	embers.initial_velocity_min = 0.1
	embers.initial_velocity_max = 0.5
	embers.amount = 40
	embers.scale_amount_min = 0.05
	embers.scale_amount_max = 0.12
	add_child(embers)
	var warm := OmniLight3D.new()
	warm.light_color = Color(1.0, 0.5, 0.18)
	warm.light_energy = 2.2
	warm.omni_range = 11.0
	warm.position = Vector3(0, DAIS_HEIGHT + 2.0, 0)
	add_child(warm)


func _build_goblins() -> void:
	# Same baked goblins as the game, in one MultiMesh; each entry keeps a Node3D that is moved
	# around and copied into the MultiMesh every frame.
	_goblin_vat = VatCrowd.load_bake(EnemyManager.GOBLIN_VAT)
	_goblin_mm = MultiMesh.new()
	_goblin_mm.transform_format = MultiMesh.TRANSFORM_3D
	_goblin_mm.use_colors = true
	_goblin_mm.use_custom_data = true
	_goblin_mm.mesh = _goblin_vat.mesh
	_goblin_mm.instance_count = GOBLINS
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _goblin_mm
	mmi.custom_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 15, 60))
	add_child(mmi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for k in GOBLINS:
		var g := Node3D.new()
		var s := rng.randf_range(0.85, 1.6)
		g.scale = Vector3.ONE * s
		add_child(g)
		_goblin_mm.set_instance_custom_data(k, Color(0.25, 0.22, 0.2, 0.0))   # dim, unlit-looking
		_goblins.append({"node": g, "a": TAU * k / GOBLINS + rng.randf_range(-0.25, 0.25), "r": rng.randf_range(10.5, 15.0),
			"phase": rng.randf() * TAU, "creep": 0.0, "creep_t": rng.randf_range(2.0, 9.0), "anim": rng.randf()})


func _build_audio() -> void:
	_music = MenuMusic.player   # shared with character select so the song never restarts
	MenuMusic.play()


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var base := load("res://fonts/Cinzel.ttf") as FontFile
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	_font = FontVariation.new()
	_font.base_font = base
	_font.variation_opentype = {wght: 600}
	_font_bold = FontVariation.new()
	_font_bold.base_font = base
	_font_bold.variation_opentype = {wght: 900}

	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	# Vignette on the left so the menu reads over the scene
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = "shader_type canvas_item;\nvoid fragment() { float a = smoothstep(0.62, 0.0, UV.x) * 0.72 + smoothstep(0.55, 1.0, UV.y) * 0.25; COLOR = vec4(0.0, 0.0, 0.02, a); }"
	var vm := ShaderMaterial.new()
	vm.shader = vs
	shade.material = vm
	root.add_child(shade)

	# Burning title
	_title = Label.new()
	_title.text = "DARK REPUBLIC"
	_title.add_theme_font_override("font", _font_bold)
	_title.add_theme_font_size_override("font_size", 104)
	_title.add_theme_color_override("font_shadow_color", Color(1.0, 0.35, 0.05, 0.55))
	_title.add_theme_constant_override("shadow_outline_size", 26)
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 0)
	_title.add_theme_color_override("font_outline_color", Color(0.18, 0.02, 0.0))
	_title.add_theme_constant_override("outline_size", 6)
	_title.position = Vector2(80, 110)
	var ts := Shader.new()
	ts.code = TITLE_SHADER
	_title_mat = ShaderMaterial.new()
	_title_mat.shader = ts
	_title.material = _title_mat
	root.add_child(_title)

	# Tagline: rotating Dungeons & Dragons puns (data/taglines.json), shuffled, crossfading
	_tagline = Label.new()
	_tagline.add_theme_font_override("font", _font)
	_tagline.add_theme_font_size_override("font_size", 26)
	_tagline.add_theme_color_override("font_color", Color(0.86, 0.78, 0.66, 0.85))
	_tagline.position = Vector2(88, 238)
	root.add_child(_tagline)
	_taglines = load_taglines()
	_taglines.shuffle()
	_tagline.text = _taglines[0] if not _taglines.is_empty() else ""

	# Embers rising off the lettering
	var sparks := CPUParticles2D.new()
	sparks.amount = 70
	sparks.lifetime = 2.4
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sparks.emission_rect_extents = Vector2(420, 12)
	sparks.position = Vector2(80 + 430, 200)
	sparks.direction = Vector2(0, -1)
	sparks.spread = 25.0
	sparks.gravity = Vector2(0, -25)
	sparks.initial_velocity_min = 20.0
	sparks.initial_velocity_max = 60.0
	sparks.scale_amount_min = 1.5
	sparks.scale_amount_max = 3.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	grad.set_color(1, Color(0.8, 0.15, 0.0, 0.0))
	sparks.color_ramp = grad
	root.add_child(sparks)

	# Menu
	_menu = VBoxContainer.new()
	_menu.position = Vector2(92, 340)
	_menu.add_theme_constant_override("separation", 10)
	root.add_child(_menu)
	var play := _menu_button("Play", _play)   # -> the mode cards (ModeMenu) -> character select...
	_menu_button("Settings", _open_settings)
	_menu_button("Quit", func(): get_tree().quit())
	play.grab_focus.call_deferred()

	var credit := Label.new()
	credit.text = "v0.1  ·  AtomAI"
	credit.add_theme_font_override("font", _font)
	credit.add_theme_font_size_override("font_size", 16)
	credit.add_theme_color_override("font_color", Color(0.8, 0.75, 0.68, 0.55))
	credit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	credit.offset_left = -220
	credit.offset_top = -40
	credit.offset_right = -24
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(credit)

	_modes = ModeMenu.create(_font, _font)
	_modes.chosen.connect(_on_mode)
	_modes.cancelled.connect(_on_modes_closed)
	root.add_child(_modes)
	_reveal_sfx = AudioStreamPlayer.new()
	_reveal_sfx.bus = Settings.SFX_BUS
	_reveal_sfx.stream = load("res://audio/ui/menu_reveal.wav")
	add_child(_reveal_sfx)

	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.closed.connect(func(): _menu.visible = true; (_menu.get_child(1) as Button).grab_focus())
	root.add_child(_settings)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 1.2)   # fade in from the splash


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "  " + tr(text).to_upper()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(340, 58)
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_color_override("font_color", Color(0.88, 0.82, 0.72))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.62, 0.2))
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.62, 0.2))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.5))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 4)
	var empty := StyleBoxEmpty.new()
	var glow := StyleBoxFlat.new()
	glow.bg_color = Color(1.0, 0.4, 0.08, 0.0)
	glow.border_color = Color(1.0, 0.5, 0.15, 0.9)
	glow.border_width_left = 4
	glow.content_margin_left = 0
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	for st in ["hover", "focus", "pressed"]:
		b.add_theme_stylebox_override(st, glow)
	b.mouse_entered.connect(func(): b.grab_focus())
	b.pressed.connect(cb)
	_menu.add_child(b)
	return b


func _open_settings() -> void:
	_menu.visible = false
	_settings.open()


## Play: the mode cards burst out of the button (Quickplay / Classic / Unrelenting).
func _play() -> void:
	if _modes.is_open() or _leaving:
		return
	var play := _menu.get_child(0) as Button
	for i in range(1, _menu.get_child_count()):
		var b := _menu.get_child(i) as Button
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
		create_tween().tween_property(b, "modulate:a", 0.25, 0.2)
	play.add_theme_color_override("font_color", Color(1.0, 0.62, 0.2))
	var r := play.get_global_rect()
	_modes.open(Vector2(r.position.x + 300.0, r.get_center().y))
	_reveal_sfx.play()


func _on_modes_closed() -> void:
	var play := _menu.get_child(0) as Button
	play.remove_theme_color_override("font_color")
	play.add_theme_color_override("font_color", Color(0.88, 0.82, 0.72))
	for i in range(1, _menu.get_child_count()):
		var b := _menu.get_child(i) as Button
		b.disabled = false
		b.focus_mode = Control.FOCUS_ALL
		create_tween().tween_property(b, "modulate:a", 1.0, 0.2)
	play.grab_focus()


## Classic and Unrelenting go to character select (which then asks for the map); Quickplay
## picks a random playable character and a random map open to them and starts the run.
func _on_mode(mode: String) -> void:
	if mode == "quickplay":
		var pick := quickplay_pick(rng_seed())
		Settings.game_mode = "classic"
		Settings.selected_character = pick["character"]
		Settings.selected_map = pick["map"]
		_leave(GAME_SCENE, 0.6)
	else:
		Settings.game_mode = mode
		_leave(CHARACTER_SCENE, 0.45)


func rng_seed() -> int:
	return int(Time.get_ticks_usec())


## Quickplay's choice: {character, map} - an unlocked, playable character and a random map
## that's unlocked and open to them. (There are no difficulty settings yet; when there are,
## Quickplay should pick the hardest one unlocked.)
static func quickplay_pick(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var chars := []
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
	for c in (data["characters"] if data is Dictionary else []):
		var id: String = c["id"]
		if c.get("mystery", false):
			continue
		var unlocked: bool = bool(c.get("unlocked", false)) or Wallet.is_char_unlocked(id)
		if unlocked and (c.has("kit") or RosterHero.is_playable(id)):
			chars.append(id)
	if chars.is_empty():
		chars = ["fire_wizard"]
	var who: String = chars[rng.randi() % chars.size()]
	var maps := []
	for m in MapPicker.MAPS:
		if MapPicker.lock_reason(m["id"], who) == "":
			maps.append(m["id"])
	if maps.is_empty():
		maps = ["swamp"]
	return {"character": who, "map": maps[rng.randi() % maps.size()]}


func _leave(scene: String, fade: float) -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_fade, "color:a", 1.0, fade)
	if scene == GAME_SCENE:
		MenuMusic.fade_out(fade)
	tw.chain().tween_callback(func(): get_tree().change_scene_to_file(scene))


func _unhandled_input(event: InputEvent) -> void:
	if _modes.is_open():
		return   # ModeMenu handles its own Esc
	if event.is_action_pressed("pause") and _settings.visible:
		_settings.handle_escape()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ screenshots
# -- --shot=/path.png --shot-at=SECONDS [--shot-settings=TAB]

var _shot_path := ""
var _shot_at := 3.0
var _shot_tab := -1


func _shot_setup() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.split("=")[1]
		elif a.begins_with("--shot-at="):
			_shot_at = float(a.split("=")[1])
		elif a == "--shot-modes":   # the Play submenu (mode cards)
			get_tree().create_timer(1.3).timeout.connect(_play)
		elif a == "--shot-thog-beaten":   # as if Thog was just beaten (screenshot runs don't save)
			Wallet.bosses_defeated = ["thog"]
			Wallet.seen_unlocks = []
		elif a.begins_with("--shot-settings="):
			_shot_tab = int(a.split("=")[1])


func _shot_tick() -> void:
	if _shot_path == "" or _t < _shot_at:
		return
	var path := _shot_path
	_shot_path = ""
	if _shot_tab >= 0:
		_open_settings()
		_settings._tabs.current_tab = _shot_tab
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT saved ", path)
	get_tree().quit()


# ------------------------------------------------------------------ animation

## The 50 title-screen puns.
static func load_taglines() -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string(TAGLINES))
	return (d["taglines"] as Array).duplicate() if d is Dictionary and d.has("taglines") else []


## Every TAGLINE_TIME seconds the line fades out and the next pun fades in (shuffled; the
## whole list plays before any repeats).
func _update_tagline(dt: float) -> void:
	if _taglines.size() < 2:
		return
	_tag_t += dt
	var fade := 0.45
	if _tag_t >= TAGLINE_TIME:
		_tag_t = 0.0
		_tag_first = false
		_tag_i += 1
		if _tag_i >= _taglines.size():
			var last: String = _taglines[-1]
			_taglines.shuffle()
			if _taglines[0] == last:
				_taglines.reverse()
			_tag_i = 0
		_tagline.text = _taglines[_tag_i]
	var a_in := 1.0 if _tag_first else minf(1.0, _tag_t / fade)   # the first pun is just there
	var a_out := minf(1.0, (TAGLINE_TIME - _tag_t) / fade)
	_tagline.modulate.a = clampf(a_in * a_out, 0.0, 1.0)


func _process(dt: float) -> void:
	_t += dt
	_update_tagline(dt)
	_update_camera(dt)
	_update_goblins(dt)
	_shot_tick()
	if _title_mat:
		var vp := get_viewport().get_visible_rect().size
		var r := _title.get_global_rect()
		_title_mat.set_shader_parameter("rect", Vector4(r.position.x / vp.x, r.position.y / vp.y, r.size.x / vp.x, r.size.y / vp.y))


func _update_camera(_dt: float) -> void:
	var a := TAU * _t / ORBIT_PERIOD + 0.6
	var pos := Vector3(cos(a) * ORBIT_RADIUS, ORBIT_HEIGHT + 0.25 * sin(_t * 0.2), sin(a) * ORBIT_RADIUS)
	_cam.global_position = pos
	# Look slightly past the wizard so he sits in the right third, clear of the menu
	var side := Vector3(-sin(a), 0, cos(a))
	_cam.look_at(Vector3(0, DAIS_HEIGHT + 1.3, 0) + side * 2.6, Vector3.UP)


func _update_goblins(dt: float) -> void:
	for g in _goblins:
		var node: Node3D = g["node"]
		g["creep_t"] -= dt
		if g["creep_t"] <= 0.0:
			g["creep_t"] = randf_range(4.0, 10.0)
			g["target"] = randf_range(-3.5, -1.0) if g["creep"] > -0.5 else 0.0   # sneak in, then back off
		var target: float = g.get("target", 0.0)
		g["creep"] = move_toward(g["creep"], target, dt * 0.9)
		var r: float = g["r"] + g["creep"]
		var a: float = g["a"] + 0.05 * sin(_t * 0.3 + g["phase"])
		var moving := absf(g["creep"] - target) > 0.05
		node.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		node.look_at(Vector3(0, 0, 0), Vector3.UP, true)   # face the wizard (+Z)
		# Creeping: slow run cycle; lurking: barely moving
		g["anim"] = fmod(g["anim"] + dt * (0.9 if moving else 0.12), 1.0)
		var k := _goblins.find(g)
		_goblin_mm.set_instance_transform(k, node.transform)
		_goblin_mm.set_instance_color(k, _goblin_vat.anim_color("run", g["anim"]))


