extends Node3D
## Opening cinematic, "The Sock Incident" (~31 s, plays after the studio logo). Built in code
## from the game's own models, goblins, swamp and effects so it matches the game exactly.
## Click, any key or any gamepad button skips to the title.
##
##   0.0  Night in the swamp. The Fire Wizard dozes by his campfire, socks drying on a rack.
##   3.2  A goblin creeps out of the reeds, nicks a sock and legs it.
##   8.0  He wakes with a start, looks at the rack... then straight at the camera.
##  11.0  A war horn. Hundreds of goblin eyes light up in the reeds.
##  14.0  The heroes answer: Ogre bursts up, Vicki drops from the sky, Gaiden from a tree,
##        the Ghast drifts through a wall, Dr. Croc blows himself up a bit.
##  24.0  Everyone charges the horde pouring out of the reeds; the wizard becomes the Meteor.
##  28.2  Impact. White-out. DARK REPUBLIC burns in, and the goblin runs past wearing the sock.

const NEXT_SCENE := "res://scenes/title.tscn"
const LENGTH := 31.5
const WORLD_SEED := 1          # the title screen's night swamp
const HORDE := 180

const FIRE := Vector2(0.0, 0.0)
const WIZ := Vector2(-1.4, 0.7)
const RACK := Vector2(1.6, 0.9)
const SNEAK_FROM := Vector2(5.5, -4.2)
const SNEAK_EXIT := Vector2(11.0, 6.5)
const IMPACT := Vector2(0.0, -15.0)

# Heroes in the roll call: id, spot (x, z), shot start
const CALL := [
	["ogre", Vector2(-3.6, -3.0), 14.0],
	["vicki", Vector2(3.4, -2.2), 16.0],
	["gaiden", Vector2(-1.2, -4.6), 18.0],
	["ghast", Vector2(5.2, -4.4), 20.0],
	["dr_croc", Vector2(1.6, -4.2), 22.0],
]
const EXTRAS := [   # join for the charge
	["ice_wizard", Vector2(-6.0, -2.0)], ["thunder_wizard", Vector2(6.8, -2.6)],
	["dark_wizard", Vector2(-7.6, -3.6)], ["merlin", Vector2(-4.8, -0.8)],
	["vampire_hunter", Vector2(8.6, -1.4)], ["rogue", Vector2(-9.2, -2.2)],
]

var water: SwampWater
var _t := 0.0
var _leaving := false
var _cam: Camera3D
var _wizard: HeroModel
var _heroes := {}            # id -> RosterModel
var _hero_home := {}         # id -> Vector3 (spot)
var _goblin_vat: VatCrowd
var _mm: MultiMesh           # sock thief (instance 0) + the horde
var _thief: Node3D
var _sock_taken: Node3D
var _sock_left: Node3D
var _horde: Array = []       # {pos, speed, phase, dead, dead_t, vel}
var _eyes: Array = []        # [Node3D, pop time]
var _head: Node3D
var _fire_light: OmniLight3D
var _zz: Array = []          # floating Z's
var _zz_next := 0.4
var _cues: Array = []        # [time, Callable] fired once
var _sfx := {}
var _ui: CanvasLayer
var _flash: ColorRect
var _fade: ColorRect
var _card: Control
var _card_name: Label
var _card_weapon: Label
var _card_t := -1.0
var _title: Label
var _skip_hint: Label
var _font: FontVariation
var _font_bold: FontVariation
var _wiz_dir := 0.0          # wizard yaw override (0 = face the fire)
var _bang: Label3D
var _shot_path := ""
var _shot_at := 0.0
var _frames_dir := ""
var _frames_left := 0
var _frames_n := 0
var _frames_fps := 24.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.split("=")[1]
		elif a.begins_with("--shot-at="):
			_shot_at = float(a.split("=")[1])
		elif a.begins_with("--frames="):   # DIR:START:COUNT[:FPS] debug dump
			var fp := a.split("=")[1].split(":")
			_frames_dir = fp[0]
			if fp.size() > 3:
				_frames_fps = float(fp[3])
			_t = -0.001
			_shot_at = float(fp[1])
			_frames_left = int(fp[2])
			RenderingServer.frame_post_draw.connect(_dump_frame)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Wallet.set_shown(false)
	_fonts()
	_build_world()
	_build_camp()
	_build_cast()
	_build_horde()
	_build_eyes()
	_build_sounds()
	_build_ui()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 260.0
	add_child(_cam)
	_cam.current = true
	_schedule()
	MenuMusic.play(1.5)
	if _shot_at > 0.0 and _frames_dir == "":   # screenshot: jump to the moment
		_advance(_shot_at)


func _fonts() -> void:
	var base := load("res://fonts/Cinzel.ttf") as FontFile
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	_font = FontVariation.new()
	_font.base_font = base
	_font.variation_opentype = {wght: 600}
	_font_bold = FontVariation.new()
	_font_bold.base_font = base
	_font_bold.variation_opentype = {wght: 900}


func _g(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, water.ground_height(p.x, p.y) + lift, p.y)


# ------------------------------------------------------------------ set

func _build_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED
	water = WorldBuilder.build(self, rng, 110.0)
	for n in get_children():
		if n is WorldEnvironment:
			var env: Environment = (n as WorldEnvironment).environment
			env.fog_density = 0.028
			env.ambient_light_energy = 1.25   # a touch brighter than the title, so the action reads
			env.glow_intensity = 0.55   # softer bloom: flame sprites read as flames, not orbs
			env.glow_bloom = 0.0


func _build_camp() -> void:
	# Campfire: crossed logs, ring of stones, flames, a flickering warm light
	var mb := MeshBuilder.new()
	var wood := Color(0.28, 0.17, 0.09, 0.0)
	var stone := Color(0.32, 0.32, 0.3, 0.0)
	for k in 4:
		var a := TAU * k / 4.0 + 0.3
		mb.add(MeshBuilder.cyl(0.07, 0.09, 1.0, 6), Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 1.25), Vector3(cos(a) * 0.15, 0.18, sin(a) * 0.15)), wood)
	for k in 9:
		var a := TAU * k / 9.0
		mb.add(MeshBuilder.sphere(0.16, 6, 4), Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 1.0)), Vector3(cos(a) * 0.62, 0.06, sin(a) * 0.62)), stone)
	var fire_mi := MeshInstance3D.new()
	fire_mi.mesh = mb.commit()
	fire_mi.position = _g(FIRE)
	add_child(fire_mi)
	var flames := Abilities._flame_particles(0.4, 0.55, 80)   # small and short-lived: they stay in the fire
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.25
	flames.gravity = Vector3(0, 1.6, 0)
	flames.position = _g(FIRE, 0.25)
	add_child(flames)
	var embers := Abilities._flame_particles(0.08, 2.4, 30)
	embers.emission_sphere_radius = 0.3
	embers.scale_amount_min = 0.05
	embers.scale_amount_max = 0.12
	embers.gravity = Vector3(0, 1.0, 0)
	embers.position = _g(FIRE, 0.6)
	add_child(embers)
	# Flame/ember sprites that drift near the lens become huge soft orbs: fade them out
	# within a few metres of the camera
	for ps in [flames, embers]:
		var mat := (ps as CPUParticles3D).mesh.surface_get_material(0) as StandardMaterial3D
		if mat == null:
			mat = ((ps as CPUParticles3D).mesh as PrimitiveMesh).material as StandardMaterial3D
		if mat:
			mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
			mat.distance_fade_min_distance = 2.0
			mat.distance_fade_max_distance = 4.5
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.55, 0.2)
	_fire_light.light_energy = 2.4
	_fire_light.omni_range = 12.0
	_fire_light.shadow_enabled = true
	_fire_light.position = _g(FIRE, 1.0)
	add_child(_fire_light)

	# Sock rack: two forked sticks and a crossbar, two striped socks hanging off it
	var rb := MeshBuilder.new()
	for sx in [-0.5, 0.5]:
		rb.add(MeshBuilder.cyl(0.03, 0.035, 1.15, 5), Transform3D(Basis(Vector3(0, 0, 1), 0.06 * sx), Vector3(sx, 0.57, 0)), wood)
	rb.add(MeshBuilder.cyl(0.025, 0.025, 1.2, 5), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 1.1, 0)), wood)
	var rack := MeshInstance3D.new()
	rack.mesh = rb.commit()
	rack.position = _g(RACK)
	rack.rotation.y = 0.5
	add_child(rack)
	_sock_taken = _sock(Color(0.75, 0.1, 0.08))
	_sock_taken.position = Vector3(-0.22, 1.08, 0)
	rack.add_child(_sock_taken)
	_sock_left = _sock(Color(0.75, 0.1, 0.08))
	_sock_left.position = Vector3(0.24, 1.08, 0)
	rack.add_child(_sock_left)

	# A crumbling stone wall for the Ghast to drift through
	var wb := MeshBuilder.new()
	var ws := Color(0.3, 0.31, 0.28, 0.0)
	for k in 7:
		wb.add(MeshBuilder.box(Vector3(0.9, 0.5, 0.45)), Transform3D(Basis(Vector3.UP, 0.05 * (k % 3)), Vector3(-1.5 + (k % 4) * 0.95, 0.25 + (k / 4) * 0.5, 0)), ws)
	wb.add(MeshBuilder.box(Vector3(0.9, 0.5, 0.45)), Transform3D(Basis(), Vector3(-1.0, 1.25, 0)), ws)
	var wall := MeshInstance3D.new()
	wall.mesh = wb.commit()
	var wp: Vector2 = CALL[3][1]
	wall.position = _g(wp + Vector2(0.0, -1.2))
	add_child(wall)


## A striped sock hanging toe-down (pivot at the cuff).
func _sock(col: Color) -> Node3D:
	var mb := MeshBuilder.new()
	var white := Color(0.92, 0.9, 0.85, 0.0)
	var c := Color(col, 0.0)
	for k in 5:
		mb.add(MeshBuilder.cyl(0.07, 0.07, 0.08, 8), Transform3D(Basis(), Vector3(0, -0.04 - k * 0.08, 0)), c if k % 2 == 0 else white)
	mb.add(MeshBuilder.box(Vector3(0.13, 0.12, 0.22)), Transform3D(Basis(), Vector3(0, -0.42, 0.06)), c)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	return mi


func _build_cast() -> void:
	_wizard = HeroModel.new()
	_wizard.position = _g(WIZ)
	add_child(_wizard)
	_wizard.look_at(_g(FIRE), Vector3.UP)
	for c in CALL + EXTRAS:
		var id: String = c[0]
		if not RosterModel.has_model(id):
			continue
		var m := RosterModel.create(id)
		var spot: Vector2 = c[1]
		_hero_home[id] = _g(spot)
		m.position = _hero_home[id]
		m.visible = false
		add_child(m)
		m.look_at(_g(IMPACT), Vector3.UP)
		_heroes[id] = m
	_bang = Label3D.new()
	_bang.text = "!"
	_bang.font = _font_bold
	_bang.font_size = 120
	_bang.outline_size = 18
	_bang.modulate = Color(1.0, 0.85, 0.3)
	_bang.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bang.visible = false
	add_child(_bang)


func _build_horde() -> void:
	_goblin_vat = VatCrowd.load_bake(EnemyManager.GOBLIN_VAT)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _goblin_vat.mesh
	_mm.instance_count = HORDE + 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.custom_aabb = AABB(Vector3(-80, -20, -80), Vector3(160, 60, 160))
	add_child(mmi)
	_thief = Node3D.new()
	_thief.position = _g(SNEAK_FROM)
	add_child(_thief)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in HORDE:
		var p := Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-62.0, -36.0))
		_horde.append({"pos": p, "speed": rng.randf_range(7.0, 10.5), "phase": rng.randf(), "dead": false, "dead_t": 0.0,
			"fly": Vector2.ZERO, "scale": rng.randf_range(0.85, 1.35), "tint": Color(rng.randf_range(0.6, 1.0), rng.randf_range(0.6, 1.0), rng.randf_range(0.5, 0.9))})
	for k in HORDE + 1:
		_mm.set_instance_custom_data(k, Color(0.8, 0.75, 0.6, 0.0))


func _build_eyes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var eye := SphereMesh.new()
	eye.radius = 0.07
	eye.height = 0.1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.2)
	m.disable_fog = true
	eye.material = m
	for k in 70:
		var x := rng.randf_range(-20.0, 20.0)
		var z := rng.randf_range(-26.0, -16.0)
		var pair := Node3D.new()
		pair.position = _g(Vector2(x, z), rng.randf_range(0.5, 1.1))
		for sx in [-0.09, 0.09]:
			var e := MeshInstance3D.new()
			e.mesh = eye
			e.position = Vector3(sx, 0, 0)
			pair.add_child(e)
		pair.look_at(_g(FIRE, 1.0), Vector3.UP)
		pair.scale = Vector3(1, 0.01, 1)
		pair.visible = false
		add_child(pair)
		# Pop on in a wave from the centre outwards
		_eyes.append([pair, 11.4 + absf(x) / 20.0 * 1.6 + rng.randf_range(0.0, 0.5)])


func _build_sounds() -> void:
	for k in ["horn", "snore", "whoosh", "pop"]:
		_sfx[k] = _player("res://audio/intro/%s.wav" % k)
	_sfx["thud"] = _player("res://audio/ui/pick_slam.wav")
	_sfx["boom"] = _player("res://audio/abilities/meteor_impact.wav")
	_sfx["meteor"] = _player("res://audio/abilities/meteor.mp3")
	_sfx["title"] = _player("res://audio/ui/levelup_chime.wav")


func _player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = Settings.SFX_BUS
	p.max_polyphony = 3
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p


func _play(k: String, vol := 0.0) -> void:
	var p: AudioStreamPlayer = _sfx.get(k)
	if p and p.stream:
		p.volume_db = vol
		p.play()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	# Letterbox bars
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = 0 if top else -80
		bar.offset_bottom = 80 if top else 0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
	# Hero name card (slides in, fighting-game style)
	_card = Control.new()
	_card.position = Vector2(110, 640)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	root.add_child(_card)
	_card_name = _label(_font_bold, 72, Color(0.85, 0.06, 0.04), 14)
	_card.add_child(_card_name)
	_card_weapon = _label(_font, 30, Color(1.0, 0.85, 0.45), 8)
	_card_weapon.position = Vector2(8, 88)
	_card.add_child(_card_weapon)
	# Title
	_title = _label(_font_bold, 132, Color(1.0, 0.55, 0.12), 16)
	_title.text = "DARK REPUBLIC"
	_title.add_theme_color_override("font_outline_color", Color(0.2, 0.03, 0.0))
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.offset_left = -900
	_title.offset_right = 900
	_title.offset_top = -120
	_title.offset_bottom = 60
	_title.modulate.a = 0.0
	root.add_child(_title)
	_skip_hint = _label(_font, 18, Color(0.85, 0.8, 0.72), 4)
	_skip_hint.text = "Click or press any key to skip"
	_skip_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left = -420
	_skip_hint.offset_right = -30
	_skip_hint.offset_top = -56
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_skip_hint)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.97, 0.9, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 1.2)


func _label(font: Font, size: int, col: Color, outline: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------------ timeline

func _schedule() -> void:
	_cue(0.5, func(): _play("snore", -6.0))
	_cue(3.0, func(): _play("snore", -8.0))
	_cue(6.3, func(): _grab_sock())
	_cue(8.0, func():
		_wizard.play_hit()
		_bang.visible = true
		_bang.position = _wizard.position + Vector3(0, 2.6, 0))
	_cue(8.9, func(): _bang.visible = false)
	_cue(11.0, func(): _play("horn"))
	# Roll call
	_cue(14.0, func(): _hero_in("ogre", "OGRE", "Tree Trunk"))
	_cue(14.25, func():
		_play("thud")
		_dust(_hero_home["ogre"], 2.4)
		_heroes["ogre"].play("ability"))
	_cue(16.0, func(): _hero_in("vicki", "VICKI", "Valkyrie Spear"))
	_cue(16.15, func(): _play("whoosh"))
	_cue(16.6, func():
		_play("thud")
		_dust(_hero_home["vicki"], 2.0)
		_heroes["vicki"].play("ability"))
	_cue(18.0, func(): _hero_in("gaiden", "GAIDEN", "Katana"))
	_cue(18.35, func(): _play("whoosh", -4.0))
	_cue(18.75, func():
		_play("thud", -4.0)
		_dust(_hero_home["gaiden"], 1.2)
		_heroes["gaiden"].play("attack"))
	_cue(20.0, func(): _hero_in("ghast", "GHAST", "Wail"))
	_cue(22.0, func(): _hero_in("dr_croc", "DR. CROC", "Volatile Flasks"))
	_cue(22.2, func(): _heroes["dr_croc"].play("attack"))
	_cue(22.85, func():
		_play("pop")
		_splash(_hero_home["dr_croc"] + Vector3(0.6, 0.9, -0.5))
		_heroes["dr_croc"].play("hit"))
	# The charge
	_cue(24.0, func():
		_card_t = -1.0
		_card.modulate.a = 0.0
		for id in _heroes:
			var h: RosterModel = _heroes[id]
			h.visible = true
			h.position = _hero_home[id]
			h.look_at(_g(IMPACT), Vector3.UP)
			h.play("run")
		_wizard.position = _g(Vector2(0.0, -1.5))
		_wizard.look_at(_g(IMPACT), Vector3.UP)
		_wiz_dir = 0.0)
	_cue(25.3, func():
		_wizard.play_ability(2)
		_play("meteor"))
	_cue(25.85, func(): _wizard.hide_now() if _wizard.has_method("hide_now") else _wizard.set("visible", false))
	_cue(26.4, func(): _spawn_head())
	_cue(28.2, func(): _impact())
	_cue(28.9, func(): _play("title", -2.0))


func _cue(at: float, f: Callable) -> void:
	_cues.append([at, f])


func _hero_in(id: String, name: String, weapon: String) -> void:
	if not _heroes.has(id):
		return
	var h: RosterModel = _heroes[id]
	h.visible = true
	h.position = _hero_home[id]
	h.look_at(_g(FIRE) if id != "ghast" else _g(FIRE), Vector3.UP)
	h.play("idle")
	_card_name.text = name
	_card_weapon.text = weapon
	_card_t = 0.0


## The thief grabs the near sock: it jumps from the rack to his hand.
func _grab_sock() -> void:
	var at := _sock_taken.global_transform
	_sock_taken.get_parent().remove_child(_sock_taken)
	_thief.add_child(_sock_taken)
	_sock_taken.global_transform = at
	var tw := create_tween()
	tw.tween_property(_sock_taken, "position", Vector3(0.25, 0.75, 0.25), 0.15)


static var _dot_tex: GradientTexture2D

static func _soft_dot() -> GradientTexture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot_tex = GradientTexture2D.new()
		_dot_tex.gradient = g
		_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		_dot_tex.fill_from = Vector2(0.5, 0.5)
		_dot_tex.fill_to = Vector2(1.0, 0.5)
		_dot_tex.width = 64
		_dot_tex.height = 64
	return _dot_tex


func _dust(at: Vector3, r: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 40
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = r * 0.4
	p.emission_ring_inner_radius = 0.0
	p.emission_ring_height = 0.1
	p.direction = Vector3(0, 0.3, 0)
	p.spread = 80.0
	p.initial_velocity_min = r * 1.2
	p.initial_velocity_max = r * 2.2
	p.gravity = Vector3(0, -2.0, 0)
	p.damping_min = 3.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.45, 0.4, 0.32, 0.55)
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()   # round, soft puffs (not squares)
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.position = at + Vector3(0, 0.1, 0)
	add_child(p)
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


## Dr. Croc's flask goes off in his hand: a green puff and splatter.
func _splash(at: Vector3) -> void:
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.45, 1.0, 0.3, 0.7)
	m.disable_fog = true
	sm.material = m
	s.mesh = sm
	s.position = at
	s.scale = Vector3.ONE * 0.1
	add_child(s)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector3.ONE * 1.6, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(s.queue_free)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 1.0, 0.3)
	light.light_energy = 4.0
	light.omni_range = 6.0
	light.position = at
	add_child(light)
	create_tween().tween_property(light, "light_energy", 0.0, 0.6)


func _spawn_head() -> void:
	_head = Node3D.new()
	add_child(_head)
	var scaled := Node3D.new()
	scaled.scale = Vector3.ONE * Abilities.HEAD_SCALE
	_head.add_child(scaled)
	var parts := Node3D.new()
	parts.position = Vector3(0, -1.5, 0)
	scaled.add_child(parts)
	WizardModel.build_head(parts)
	var blaze := Abilities._flame_particles(3.2, 0.7, 160)
	blaze.emission_sphere_radius = 2.2
	_head.add_child(blaze)
	var trail := Abilities._flame_particles(3.6, 1.6, 220)
	trail.emission_sphere_radius = 1.6
	trail.gravity = Vector3(0, 6.0, 0)
	_head.add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 6.0
	light.omni_range = 30.0
	_head.add_child(light)


func _head_pos(t: float) -> Vector3:
	var start := _g(IMPACT) + Vector3(-10.0, 70.0, -30.0)
	var end := _g(IMPACT, 2.0)
	var k := clampf((t - 26.4) / 1.8, 0.0, 1.0)
	return start.lerp(end, k * k)


func _impact() -> void:
	_play("boom", 2.0)
	if _head:
		_head.queue_free()
		_head = null
	_flash.color.a = 1.0
	create_tween().tween_property(_flash, "color:a", 0.0, 1.1).set_delay(0.15)
	for g in _horde:
		var d: Vector2 = g["pos"] - IMPACT
		if d.length() < 11.0:
			g["dead"] = true
			g["fly"] = d.normalized() * (14.0 - d.length())
		else:
			g["speed"] = -absf(g["speed"]) * 1.3   # the rest turn tail
	_wizard.position = _g(IMPACT)
	_wizard.visible = true
	if _wizard.has_method("reappear"):
		_wizard.reappear()
	_wizard.look_at(_g(Vector2(0.0, 6.0)), Vector3.UP)
	for id in _heroes:
		(_heroes[id] as RosterModel).play("idle")


# ------------------------------------------------------------------ per frame

func _process(dt: float) -> void:
	if _frames_dir != "":
		dt = 1.0 / _frames_fps
	_advance(dt)


func _advance(dt: float) -> void:
	var steps := maxi(1, int(ceil(dt / 0.05)))
	for s in steps:
		_step(dt / steps)
	if _shot_path != "" and _t >= _shot_at and _frames_dir == "":
		var p := _shot_path
		_shot_path = ""
		_save_shot(p)


func _step(dt: float) -> void:
	_t += dt
	while not _cues.is_empty() and _t >= float(_cues[0][0]):
		var c: Array = _cues.pop_front()
		(c[1] as Callable).call()
	_update_wizard(dt)
	_update_zz(dt)
	_update_thief(dt)
	_update_heroes(dt)
	_update_horde(dt)
	_update_eyes()
	_update_ui(dt)
	_update_camera()
	if _head:
		_head.position = _head_pos(_t)
		_head.look_at(_g(IMPACT, 2.0) + Vector3(0, -50, 0), Vector3.FORWARD)
	_fire_light.light_energy = 2.2 + 0.35 * sin(_t * 13.0) + 0.2 * sin(_t * 31.0)
	if _t >= LENGTH:
		_finish()


func _update_wizard(_dt: float) -> void:
	if _t < 8.0:
		_wizard.set_motion(0.0, false)
	elif _t < 24.0:
		# Startle, look at the rack, then turn to the camera for a long, flat stare
		var to_rack := (_g(RACK) - _wizard.position)
		var to_cam := (_cam.global_position - _wizard.position)
		var base := atan2(-(_g(FIRE) - _wizard.position).x, -(_g(FIRE) - _wizard.position).z)
		var rack_y := atan2(-to_rack.x, -to_rack.z)
		var cam_y := atan2(-to_cam.x, -to_cam.z)
		var target := base
		if _t > 8.5:
			target = rack_y
		if _t > 9.7:
			target = cam_y
		_wizard.rotation.y = lerp_angle(_wizard.rotation.y, target, 0.12)
	elif _t < 25.3:
		_wizard.set_motion(6.0, false)
		_wizard.position = _wizard.position.move_toward(_g(Vector2(0.0, -4.0)), 6.0 * _dt)


func _update_zz(dt: float) -> void:
	if _t < 7.8:
		_zz_next -= dt
		if _zz_next <= 0.0:
			_zz_next = 0.75
			var z := Label3D.new()
			z.text = "z" if _zz.size() % 2 == 0 else "Z"
			z.font = _font_bold
			z.font_size = 64
			z.outline_size = 10
			z.modulate = Color(0.85, 0.9, 1.0)
			z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			z.position = _wizard.position + Vector3(0.2, 2.2, 0)
			add_child(z)
			_zz.append([z, 0.0])
	for e in _zz.duplicate():
		var z: Label3D = e[0]
		e[1] += dt
		z.position += Vector3(0.25, 0.6, 0.0) * dt
		z.modulate.a = 1.0 - e[1] / 2.2
		if e[1] > 2.2 or _t > 8.0:
			z.queue_free()
			_zz.erase(e)


func _update_thief(dt: float) -> void:
	var p := _thief.position
	var target := p
	var speed := 0.0
	var phase_rate := 0.0
	if _t >= 3.2 and _t < 6.3:      # creep in
		target = _g(RACK + Vector2(0.55, -0.45))
		speed = 2.4
		phase_rate = 0.9
	elif _t >= 6.6 and _t < 9.0:    # leg it
		target = _g(SNEAK_EXIT)
		speed = 11.0
		phase_rate = 2.8
	elif _t >= 29.0:                 # the closing gag: runs past wearing the sock
		if _t - dt < 29.0:
			_thief.position = _g(Vector2(-9.0, 2.5))
			_sock_taken.position = Vector3(0, 1.0, 0)
			_sock_taken.rotation = Vector3(PI, 0, 0.3)
		target = _g(Vector2(12.0, 1.0))
		speed = 7.0
		phase_rate = 2.4
	if speed > 0.0:
		var flat := target - _thief.position
		_thief.position = _thief.position.move_toward(target, speed * dt)
		_thief.position.y = water.ground_height(_thief.position.x, _thief.position.z)
		if Vector2(flat.x, flat.z).length() > 0.05:
			_thief.look_at(_thief.position + Vector3(flat.x, 0, flat.z), Vector3.UP, true)
	var vis := _t >= 3.2 and (_t < 9.0 or _t >= 29.0)
	var ph := fmod(_t * phase_rate, 1.0)
	var clip := "run" if speed > 0.0 else "attack"
	if _t >= 6.3 and _t < 6.6:
		clip = "attack"
		ph = (_t - 6.3) / 2.5 + 0.2
	var xf := _thief.transform if vis else Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -50, 0))
	_mm.set_instance_transform(0, xf)
	_mm.set_instance_color(0, _goblin_vat.anim_color(clip, ph))
	_sock_taken.visible = _sock_taken.get_parent() != _thief or vis


func _update_heroes(dt: float) -> void:
	# Roll-call entrances
	var vk: RosterModel = _heroes.get("vicki")
	if vk and _t >= 16.0 and _t < 16.6:
		vk.position = _hero_home["vicki"] + Vector3(0, 9.0 * (1.0 - (_t - 16.0) / 0.6), 0)
	var gd: RosterModel = _heroes.get("gaiden")
	if gd and _t >= 18.0 and _t < 18.75:
		var k := clampf((_t - 18.35) / 0.4, 0.0, 1.0)
		gd.position = _hero_home["gaiden"] + Vector3(0, 4.5 * (1.0 - k * k), 0)
	var og: RosterModel = _heroes.get("ogre")
	if og and _t >= 14.0 and _t < 14.5:
		var k := clampf((_t - 14.0) / 0.25, 0.0, 1.0)
		og.scale = Vector3(1.0, lerpf(0.15, 1.0, k), 1.0)
		og.position = _hero_home["ogre"] + Vector3(0, -0.6 * (1.0 - k), 0)
	var gh: RosterModel = _heroes.get("ghast")
	if gh and _t >= 20.0 and _t < 22.0:
		var k := clampf((_t - 20.2) / 1.5, 0.0, 1.0)
		gh.position = _hero_home["ghast"] + Vector3(0, 0, -2.6 * (1.0 - k))
	# The charge
	if _t >= 24.0 and _t < 28.2:
		for id in _heroes:
			var h: RosterModel = _heroes[id]
			h.position = h.position.move_toward(Vector3(h.position.x, h.position.y, -9.0), 6.5 * dt)
			h.position.y = water.ground_height(h.position.x, h.position.z)


func _update_horde(dt: float) -> void:
	for k in _horde.size():
		var g: Dictionary = _horde[k]
		var p: Vector2 = g["pos"]
		var clip := "run"
		var ph := 0.0
		var lift := 0.0
		var face := Vector2(0, 1)
		if g["dead"]:
			g["dead_t"] += dt
			var fly: Vector2 = g["fly"]
			p += fly * dt * maxf(0.0, 1.0 - g["dead_t"] * 1.5)
			lift = maxf(0.0, 3.0 * g["dead_t"] - 6.0 * g["dead_t"] * g["dead_t"])
			clip = "death"
			ph = clampf(g["dead_t"] / 1.6, 0.0, 1.0)
			face = -fly
		elif _t >= 23.6:
			var sp: float = g["speed"]
			if sp > 0.0 and p.y < IMPACT.y + 2.0:
				p.y = minf(p.y + sp * dt, IMPACT.y + 2.0 + float(k % 7))
			elif sp < 0.0:
				p.y += sp * dt
				face = Vector2(0, -1)
			g["phase"] = fmod(g["phase"] + dt * absf(sp) / 4.5, 1.0)
			ph = g["phase"]
		else:
			ph = g["phase"]
		g["pos"] = p
		var pos := _g(p, lift)
		var b := Basis.looking_at(Vector3(face.x, 0, face.y), Vector3.UP, true).scaled(Vector3.ONE * float(g["scale"]))
		var visible_now := _t >= 23.6
		_mm.set_instance_transform(k + 1, Transform3D(b, pos) if visible_now else Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -50, 0)))
		_mm.set_instance_color(k + 1, _goblin_vat.anim_color(clip, ph))


func _update_eyes() -> void:
	for e in _eyes:
		var pair: Node3D = e[0]
		var on := _t >= float(e[1]) and _t < 24.0
		pair.visible = on
		if on:
			var k := clampf((_t - float(e[1])) / 0.15, 0.0, 1.0)
			var blink := 0.08 if fmod(_t * 0.7 + float(e[1]) * 3.0, 3.0) < 0.12 else 1.0
			pair.scale = Vector3(1, k * blink, 1)


func _update_ui(dt: float) -> void:
	if _card_t >= 0.0:
		_card_t += dt
		var k := clampf(_card_t / 0.25, 0.0, 1.0)
		_card.position.x = lerpf(-500.0, 110.0, 1.0 - (1.0 - k) * (1.0 - k))
		_card.modulate.a = minf(1.0, _card_t / 0.15) * clampf((1.95 - _card_t) / 0.25, 0.0, 1.0)
	if _t >= 28.8:
		var k := clampf((_t - 28.8) / 0.6, 0.0, 1.0)
		_title.modulate.a = k * clampf((LENGTH - _t) / 0.6, 0.0, 1.0)
		_title.scale = Vector2.ONE * lerpf(1.25, 1.0, k)
		_title.pivot_offset = Vector2(900, 90)
	_skip_hint.modulate.a = clampf(1.0 - (_t - 4.0) / 1.0, 0.0, 0.8)


## Camera: one shot after another, each a move from one framing to the next.
func _update_camera() -> void:
	var t := _t
	var eye: Vector3
	var look: Vector3
	var fire := _g(FIRE, 0.8)
	if t < 3.2:
		var k := _ease(t / 3.2)
		eye = _g(FIRE).lerp(_g(FIRE), 0) + Vector3(6.5, 3.6, 7.5).lerp(Vector3(3.8, 2.3, 4.6), k)
		look = fire.lerp(_wizard.position + Vector3(0, 1.4, 0), k * 0.5)
	elif t < 8.0:
		var k := _ease((t - 3.2) / 4.8)
		eye = _g(RACK) + Vector3(2.6, 0.8, 1.6).lerp(Vector3(1.8, 1.0, 2.2), k)
		var thief := _thief.position + Vector3(0, 0.6, 0)
		look = (_g(RACK, 0.9)).lerp(thief, 0.8)
	elif t < 11.0:
		var face := _wizard.position + Vector3(0, 1.55, 0)
		var dir := (_g(RACK) - _wizard.position).normalized()
		# In front of him, on the far side from the campfire: the fire glows behind him instead of
		# filling the lens
		var away := Vector3(_wizard.position.x - _g(FIRE).x, 0, _wizard.position.z - _g(FIRE).z).normalized()
		var side := Vector3(-away.z, 0, away.x)
		var k := _ease((t - 8.0) / 3.0)
		eye = face + (away * 2.4 + side * 0.9 + Vector3(0, 0.1, 0)).lerp(away * 1.7 + side * 0.5 + dir * 0.3, k)
		look = face
	elif t < 14.0:
		var k := _ease((t - 11.0) / 3.0)
		eye = _g(FIRE, 0.0) + Vector3(2.8, 1.8, 2.6).lerp(Vector3(2.3, 2.1, 1.4), k)   # beside the fire, not through it
		look = _g(Vector2(0, -20), 1.0)
	elif t < 24.0:
		var i := clampi(int((t - 14.0) / 2.0), 0, CALL.size() - 1)
		var id: String = CALL[i][0]
		var home: Vector3 = _hero_home.get(id, Vector3.ZERO)
		var k := _ease(fmod(t - 14.0, 2.0) / 2.0)
		var toward := (fire - home)
		toward.y = 0.0
		toward = toward.normalized()
		var side := Vector3(toward.z, 0, -toward.x)
		var h := 1.2 if id != "ogre" else 1.6
		eye = home + toward * lerpf(4.2, 3.2, k) + side * lerpf(1.6, 0.8, k) + Vector3(0, lerpf(0.6, 1.0, k), 0)
		look = home + Vector3(0, h, 0)
		if id == "vicki" and t < 16.7:
			look = (_heroes["vicki"] as Node3D).position + Vector3(0, 1.2, 0) if _heroes.has("vicki") else look
		if id == "gaiden" and t < 18.8:
			look = (_heroes["gaiden"] as Node3D).position + Vector3(0, 1.0, 0) if _heroes.has("gaiden") else look
	elif t < 26.4:
		var k := _ease((t - 24.0) / 2.4)
		eye = _g(Vector2(0, 7.0)) + Vector3(0, 4.5, 0).lerp(Vector3(0, 6.5, -2.0), k)
		look = _g(Vector2(0, -14.0), 0.5)
	elif t < 28.2:
		eye = _g(Vector2(4.0, 1.0)) + Vector3(0, 2.2, 0)
		look = _head_pos(t) if _head else _g(IMPACT, 2.0)
	else:
		var k := _ease(clampf((t - 28.2) / 3.0, 0.0, 1.0))
		eye = _g(Vector2(0.0, 6.0)) + Vector3(0, 3.0, 0).lerp(Vector3(0, 2.0, -1.0), k)
		look = _g(Vector2(0.0, -6.0), 1.0)
	_cam.global_position = eye
	if eye.distance_to(look) > 0.01:
		_cam.look_at(look, Vector3.UP)


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# ------------------------------------------------------------------ skip / finish

func _input(event: InputEvent) -> void:
	if _leaving:
		return
	var skip: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if skip:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.5)
	tw.tween_callback(func(): get_tree().change_scene_to_file(NEXT_SCENE))


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT saved ", path)
	get_tree().quit()


func _dump_frame() -> void:
	if _frames_left <= 0 or _t < _shot_at:
		return
	get_viewport().get_texture().get_image().save_jpg("%s/f%04d.jpg" % [_frames_dir, _frames_n], 0.85)
	_frames_n += 1
	_frames_left -= 1
	if _frames_left == 0:
		print("FRAMES saved %d" % _frames_n)
		get_tree().quit()
