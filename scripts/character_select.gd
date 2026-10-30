extends Control
## Character select: a 6-wide grid of 23 procedurally drawn portraits on the left and a preview
## panel on the right (live 3D model for playable characters, a large portrait for locked
## ones), with name, epithet, bio and kit. Only the Fire Wizard is unlocked for now.
## Keyboard, gamepad and mouse all work; Esc / Back returns to the title.

const DATA := "res://data/characters.json"
const TITLE_SCENE := "res://scenes/title.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
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
var _ability_bar: HBoxContainer
var _ability_slots: Array = []     # AbilitySlot, one per Abilities.DEFS entry
var _ability_names: Array = []     # Label under each slot
var _kit_char := "fire_wizard"     # whose abilities the bar and tooltips show
var _tooltip: PanelContainer
var _tooltip_text: RichTextLabel
var _hover_slot := -1
var _status: Label             # locked characters only: "Unlock Requirements:" / "Ready to unlock"
var _level_box: VBoxContainer   # top left of the preview: level, EXP and a bar
var _level_label: Label
var _exp_label: Label
var _exp_bar: ProgressBar
var _req_box: PanelContainer
var _req_rows: HBoxContainer
var _big_icon: CharacterIcon
var _view_box: SubViewportContainer
var _weapon_box: VBoxContainer     # top right of the preview: weapon icon, name, short text
var _weapon_icon: UpgradeIcon
var _weapon_name: Label
var _weapon_short: Label
var _model_pivot: Node3D
var _hero_preview: Node3D
var _previews := {}          # character id -> RosterModel (built on first view)
var _play_btn: Button
var _back_btn: Button
var _skills_btn: Button
var skills: SkillScreen
var _count_label: Label
var _music: AudioStreamPlayer
var _fade: ColorRect
var _leaving := false
var _t := 0.0


func _ready() -> void:
	Wallet.set_shown(true)
	characters = load_characters()
	_build_fonts()
	_build_background()
	_build_grid()
	_build_panel()
	_build_footer()
	_build_music()
	skills = SkillScreen.new()
	skills.setup(_font, _font_bold)
	skills.visible = false
	skills.closed.connect(func():
		refresh_levels()
		_skills_btn.grab_focus())
	add_child(skills)
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
	return bool(characters[k].get("unlocked", false)) or Wallet.is_char_unlocked(characters[k]["id"])


func is_mystery(k: int) -> bool:
	return bool(characters[k].get("mystery", false))


## Has a model and abilities, so it can actually be played: the Fire Wizard, plus the roster
## characters RosterHero can run (Ice, Thunder and Dark Wizards so far).
func is_ready(k: int) -> bool:
	return characters[k].has("kit") or RosterHero.is_playable(characters[k]["id"])


func price_of(k: int) -> int:
	return int(characters[k].get("price", 0))


const BOSS_NAMES := {"thog": "Defeat Thog the Troll in the Swamp", "toadstool_knight": "Defeat the Toadstool Knight in the Magical Forest", "arachnid": "Defeat the Arachnid in the Castle"}
const FEAT_NAMES := {"unrelenting_swamp_15": "Survive 15:00 in the Swamp on Unrelenting"}


## What a locked character needs: [{text, met}], coins first, then any boss to beat.
func requirements(k: int) -> Array:
	var c: Dictionary = characters[k]
	var out := []
	if price_of(k) > 0:
		out.append({"text": tr("%s coins") % Wallet.fmt(price_of(k)), "met": Wallet.coins >= price_of(k)})
	var boss := str(c.get("requires_boss", ""))
	if boss != "":
		out.append({"text": BOSS_NAMES.get(boss, "Defeat " + boss), "met": Wallet.has_defeated(boss)})
	var feat := str(c.get("requires_feat", ""))
	if feat != "":
		out.append({"text": FEAT_NAMES.get(feat, feat), "met": Wallet.has_feat(feat)})
	return out


## Every requirement met: Unlock can be pressed.
func can_unlock(k: int) -> bool:
	if is_unlocked(k) or is_mystery(k):
		return false
	for r in requirements(k):
		if not r["met"]:
			return false
	return true


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
	var sub := _label("", 20, Color(0.8, 0.74, 0.64, 0.8))
	_count_label = sub
	sub.position = Vector2(68, 98)
	add_child(sub)
	if Settings.game_mode == "unrelenting":   # chosen from the title's Play cards
		var tag := _label("UNRELENTING", 20, Color(1.0, 0.35, 0.28), true)
		tag.text = tr("UNRELENTING")
		tag.position = Vector2(560, 100)
		add_child(tag)


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
		b.add_theme_stylebox_override("hover", _tile_style(Color(1.0, 0.75, 0.35), 3, Color(0, 0, 0, 0.5)))
		b.add_theme_stylebox_override("focus", _tile_style(Color(1.0, 0.8, 0.4), 4, Color(0, 0, 0, 0)))
		b.add_theme_stylebox_override("pressed", _tile_style(Color(1.0, 0.9, 0.6), 4, Color(0, 0, 0, 0.5)))
		var icon := CharacterIcon.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 4
		icon.offset_top = 4
		icon.offset_right = -4
		icon.offset_bottom = -4
		icon.animate = false
		icon.set_icon(c["icon"])
		icon.clip_contents = true
		b.add_child(icon)
		b.set_meta("icon", icon)
		# Character level, bottom-left of the tile; hidden at 0
		var lvl := _label("", 17, Color(1.0, 0.9, 0.6), true)
		lvl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		lvl.offset_left = 7
		lvl.offset_top = -26
		lvl.offset_bottom = -3
		lvl.add_theme_constant_override("outline_size", 5)
		lvl.add_theme_font_override("font", ThemeDB.fallback_font)   # plain lowercase "lvl"
		lvl.add_theme_font_size_override("font_size", 18)
		b.add_child(lvl)
		b.set_meta("lvl", lvl)
		# Unlock price, bottom-left of locked tiles (coin + amount)
		var price := HBoxContainer.new()
		price.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		price.offset_left = 6
		price.offset_top = -27
		price.offset_bottom = -4
		price.add_theme_constant_override("separation", 3)
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var coin := CoinIcon.new()
		coin.custom_minimum_size = Vector2(18, 18)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		price.add_child(coin)
		var amount := Label.new()
		amount.text = Wallet.fmt(price_of(k))
		amount.add_theme_font_override("font", ThemeDB.fallback_font)
		amount.add_theme_font_size_override("font_size", 16)
		amount.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
		amount.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		amount.add_theme_constant_override("outline_size", 5)
		price.add_child(amount)
		b.add_child(price)
		b.set_meta("price", price)
		b.focus_entered.connect(_show.bind(k))   # keyboard/gamepad navigation; hovering does nothing
		b.pressed.connect(_choose.bind(k))
		grid.add_child(b)
		_tiles.append(b)
	refresh_levels()


## Refresh every tile: rim, padlock, unlock price (locked) or "lvl N" (unlocked, 1+).
func refresh_levels() -> void:
	var count := 0
	for k in _tiles.size():
		var b := _tiles[k]
		var unlocked := is_unlocked(k)
		var mystery := is_mystery(k)
		if unlocked:
			count += 1
		var rim := Color(0.95, 0.6, 0.2) if unlocked else Color(0.3, 0.28, 0.26)
		b.add_theme_stylebox_override("normal", _tile_style(rim.darkened(0.2), 2, Color(0, 0, 0, 0.5)))
		(b.get_meta("icon") as CharacterIcon).locked = not unlocked and not mystery
		var lvl := Wallet.char_level(characters[k]["id"])
		var l := b.get_meta("lvl") as Label
		l.text = tr("lvl %d") % lvl
		l.visible = unlocked and lvl > 0
		(b.get_meta("price") as Control).visible = not unlocked and not mystery and price_of(k) > 0
	if _count_label:
		_count_label.text = tr("%d of %d unlocked") % [count, characters.size()]


func _build_panel() -> void:
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.03, 0.025, 0.02, 0.72)
	ps.border_color = Color(0.55, 0.3, 0.12, 0.8)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(10)
	ps.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", ps)
	panel.position = Vector2(860, 74)
	panel.custom_minimum_size = Vector2(690, 712)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	# Preview area: 3D model or a large portrait, same footprint
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(640, 262)
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
	_big_icon.custom_minimum_size = Vector2(280, 280)
	_big_icon.size = Vector2(280, 280)
	_big_icon.position = Vector2((640 - 280) * 0.5, 5)
	stage.add_child(_big_icon)
	_build_weapon_box(stage)
	_build_level_box(stage)

	_name = _label("", 54, Color(1.0, 0.86, 0.6), true)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_name)
	_epithet = _label("", 27, Color(1.0, 0.55, 0.2))
	_epithet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_epithet)
	_bio = _label("", 21, Color(0.86, 0.8, 0.7))
	_bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bio.custom_minimum_size = Vector2(640, 0)
	v.add_child(_bio)
	var gap := Control.new()   # breathing room between the tagline and the abilities
	gap.custom_minimum_size = Vector2(0, 22)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gap)
	_build_ability_bar(v)
	_kit = _label("", 17, Color(0.95, 0.75, 0.45))
	_kit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_kit.custom_minimum_size = Vector2(640, 0)
	v.add_child(_kit)
	_status = _label("", 24, Color(0.7, 0.68, 0.64))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)
	_build_requirements(v)


## Top-left corner of the preview: "LVL 3", the EXP towards the next level, and a thin bar.
func _build_level_box(stage: Control) -> void:
	_level_box = VBoxContainer.new()
	_level_box.position = Vector2(4, 0)
	_level_box.add_theme_constant_override("separation", 2)
	_level_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_level_box)
	_level_label = _label("", 34, Color(1.0, 0.82, 0.4), true)
	_level_box.add_child(_level_label)
	_exp_label = _label("", 18, Color(0.9, 0.84, 0.74))
	_level_box.add_child(_exp_label)
	_exp_bar = ProgressBar.new()
	_exp_bar.show_percentage = false
	_exp_bar.custom_minimum_size = Vector2(170, 8)
	_exp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.07, 0.05, 0.9)
	bg.border_color = Color(0.55, 0.35, 0.15, 0.8)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.65, 0.2)
	fill.set_corner_radius_all(4)
	_exp_bar.add_theme_stylebox_override("background", bg)
	_exp_bar.add_theme_stylebox_override("fill", fill)
	_exp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_box.add_child(_exp_bar)


## Top-right corner of the preview: the signature weapon's icon, its name and a few words.
func _build_weapon_box(stage: Control) -> void:
	_weapon_box = VBoxContainer.new()
	_weapon_box.add_theme_constant_override("separation", 2)
	_weapon_box.position = Vector2(640 - 176, 0)
	_weapon_box.size = Vector2(176, 0)
	_weapon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_weapon_box)
	var head := _label("SIGNATURE WEAPON", 13, Color(0.8, 0.68, 0.5, 0.8), true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_box.add_child(head)
	_weapon_icon = UpgradeIcon.create({}, "weapon")
	_weapon_icon.custom_minimum_size = Vector2(76, 76)
	_weapon_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	_weapon_icon.mouse_entered.connect(func(): _on_slot_hover(WEAPON_HOVER, true))
	_weapon_icon.mouse_exited.connect(func(): _on_slot_hover(WEAPON_HOVER, false))
	_weapon_box.add_child(_weapon_icon)
	_weapon_name = _label("", 19, Color(1.0, 0.85, 0.5), true)
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weapon_name.custom_minimum_size.x = 176
	_weapon_box.add_child(_weapon_name)
	_weapon_short = _label("", 13, Color(0.85, 0.8, 0.72))
	_weapon_short.visible = false   # the details are in the hover tooltip
	_weapon_short.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_short.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weapon_short.custom_minimum_size.x = 150
	_weapon_box.add_child(_weapon_short)
	for l in [head, _weapon_name, _weapon_short]:
		(l as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE


## Under "Unlock Requirements:": one chip per requirement with a tick or a cross (coins, and for
## Thog, beating him in the Swamp), side by side.
func _build_requirements(parent: Control) -> void:
	_req_box = PanelContainer.new()
	_req_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_req_box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(_req_box)
	_req_rows = HBoxContainer.new()
	_req_rows.add_theme_constant_override("separation", 14)
	_req_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_req_box.add_child(_req_rows)


## The character's three abilities, drawn exactly like the in-run ability bar (square, key,
## name underneath). Hovering one shows the same tooltip as in a run: what it does + cooldown.
const ABILITY_COL := 136.0   # width of each ability column (square + wrapped name)


func _build_ability_bar(parent: Control) -> void:
	_ability_bar = HBoxContainer.new()
	_ability_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_ability_bar.add_theme_constant_override("separation", 22)
	parent.add_child(_ability_bar)
	var icons := [AbilitySlot.Icon.INFERNO, AbilitySlot.Icon.SHOCKWAVE, AbilitySlot.Icon.METEOR]
	for i in Abilities.DEFS.size():
		var d: Dictionary = Abilities.DEFS[i]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ability_bar.add_child(col)
		var slot := AbilitySlot.new()
		slot.icon = icons[i]
		slot.key_text = d["key"]
		slot.is_ult = d["ult"]
		slot.unlock_level = d["unlock_level"]
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.hovered.connect(func(on: bool): _on_slot_hover(i, on))
		col.add_child(slot)
		var name := _label(d["name"], 14, Color(1.0, 0.85, 0.3) if d["ult"] else Color(1, 1, 1, 0.85))
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Fixed-width columns: long names wrap onto a second line instead of pushing the
		# squares apart, so the three abilities always sit evenly spaced
		name.custom_minimum_size = Vector2(ABILITY_COL, 0)
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		name.visible = false   # names live in the hover tooltip only
		col.add_child(name)
		_ability_slots.append(slot)
		_ability_names.append(name)

	_tooltip = PanelContainer.new()
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 10
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.045, 0.04, 0.96)
	sb.border_color = Color(1.0, 0.5, 0.18, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	_tooltip.add_theme_stylebox_override("panel", sb)
	_tooltip_text = RichTextLabel.new()
	_tooltip_text.bbcode_enabled = true
	_tooltip_text.fit_content = true
	_tooltip_text.scroll_active = false
	_tooltip_text.custom_minimum_size = Vector2(460, 0)
	_tooltip_text.add_theme_font_size_override("normal_font_size", 18)
	_tooltip_text.add_theme_font_size_override("bold_font_size", 18)
	_tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(_tooltip_text)
	add_child.call_deferred(_tooltip)   # on top of the panel


const WEAPON_HOVER := 99   # _hover_slot value while the weapon icon is hovered


## Tooltip for a character's signature weapon: name, damage and rate, and what it does.
static func weapon_tooltip(char_id: String) -> String:
	var w: Dictionary = KitDB.kit(char_id).get("weapon", {})
	if w.is_empty():
		return ""
	var lines: Array[String] = []
	lines.append("[font_size=22][b]%s[/b][/font_size]  [color=#ffd23f][%s][/color]" % [I18n.t(w["name"]), I18n.t("SIGNATURE WEAPON")])
	var dmg := I18n.f("Damage: %s", "[color=#ffb347]%s[/color]" % str(w.get("damage", "?")))
	if w.has("every"):
		dmg += "   ·   " + I18n.f("One attack every %s", "[color=#ffb347]%s[/color]" % I18n.f("%s s", str(w["every"])))
	lines.append(dmg)
	lines.append("")
	lines.append(I18n.t(w.get("desc", "")))
	return "\n".join(lines)


## Tooltip text for ability i outside a run: what it does, cooldown, and when it unlocks.
## Characters other than the Fire Wizard show their designed kit from data/abilities.json.
static func ability_tooltip(i: int, char_id := "fire_wizard") -> String:
	var lines := Abilities.describe_lines(i) if char_id == "fire_wizard" else KitDB.describe_lines(char_id, i)
	var lvl := int(Abilities.DEFS[i]["unlock_level"])
	lines.append("")
	if lvl <= 1:
		lines.append("[color=#7dff7d]%s[/color]" % I18n.t("Available from the start of every run"))
	else:
		lines.append("[color=#ffb347]%s[/color]" % I18n.f("Unlocks at level %d during a run", lvl))
	return "\n".join(lines)


## Point the ability bar at a character's kit: the Fire Wizard keeps his hand-drawn icons,
## everyone else gets AbilityGlyphs icons and names from data/abilities.json.
func _set_kit(id: String) -> void:
	_kit_char = id
	for i in _ability_slots.size():
		var slot: AbilitySlot = _ability_slots[i]
		var a := KitDB.ability(id, i)
		var ic: Dictionary = a.get("icon", {})
		slot.glyph = "" if id == "fire_wizard" else str(ic.get("glyph", ""))
		slot.glyph_color = Color(str(ic.get("color", "#ffffff")))
		(_ability_names[i] as Label).text = str(a.get("name", Abilities.DEFS[i]["name"])) if id != "fire_wizard" else Abilities.DEFS[i]["name"]
		slot.queue_redraw()


func _on_slot_hover(i: int, on: bool) -> void:
	if on:
		_hover_slot = i
	elif _hover_slot == i:
		_hover_slot = -1
	_update_tooltip()


func _update_tooltip() -> void:
	if _hover_slot == WEAPON_HOVER:
		if not _weapon_box.is_visible_in_tree() or _shown < 0:
			_tooltip.visible = false
			return
		_tooltip_text.text = weapon_tooltip(characters[_shown]["id"])
	elif _hover_slot < 0 or not _ability_bar.is_visible_in_tree():
		_tooltip.visible = false
		return
	else:
		_tooltip_text.text = ability_tooltip(_hover_slot, _kit_char)
	_tooltip.visible = true
	_tooltip.reset_size()
	var anchor: Control = _weapon_icon if _hover_slot == WEAPON_HOVER else _ability_slots[_hover_slot]
	var r: Rect2 = anchor.get_global_rect()
	var vp := get_viewport().get_visible_rect().size
	var pos := Vector2(r.position.x + r.size.x * 0.5 - _tooltip.size.x * 0.5, r.position.y - _tooltip.size.y - 12)
	if _hover_slot == WEAPON_HOVER:
		pos.y = r.end.y + 12   # the weapon sits at the top of the panel: open downward
	pos.x = clampf(pos.x, 10, vp.x - _tooltip.size.x - 10)
	pos.y = maxf(pos.y, 10)
	_tooltip.position = pos


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
	cam.position = Vector3(0, 1.3, 5.6)
	cam.look_at_from_position(cam.position, Vector3(0, 1.05, 0))
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
	_hero_preview = HeroModel.new()
	_model_pivot.add_child(_hero_preview)


func _build_footer() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(860, 816)
	row.custom_minimum_size = Vector2(690, 70)
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	_back_btn = _footer_button("Back", _back)
	row.add_child(_back_btn)
	_skills_btn = _footer_button("Skills", _open_skills)
	row.add_child(_skills_btn)
	_play_btn = _footer_button("Play", _play)
	row.add_child(_play_btn)


func _footer_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = tr(text).to_upper()
	b.custom_minimum_size = Vector2(210, 60)
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
	_music = MenuMusic.player   # same song as the title screen, carries on without restarting
	MenuMusic.play()


# ------------------------------------------------------------------ behaviour

func _show(k: int) -> void:
	if k == _shown:
		return
	_shown = k
	var c: Dictionary = characters[k]
	var unlocked := is_unlocked(k)
	var mystery := is_mystery(k)
	var ready := unlocked and is_ready(k)
	_name.text = c["name"]
	_epithet.text = c.get("epithet", "")
	_bio.text = c.get("bio", "")
	var kit: Array = c.get("kit", [])
	var has_abilities: bool = KitDB.has_kit(c["id"]) and not mystery
	_set_kit(c["id"] if has_abilities else "fire_wizard")
	_ability_bar.visible = has_abilities
	_hover_slot = -1
	_update_tooltip()
	var weapon := ""
	for item in kit:
		if str(item).ends_with("(weapon)"):
			weapon = "Weapon: " + str(item).trim_suffix(" (weapon)")
	if c["id"] != "fire_wizard" and has_abilities:
		weapon = KitDB.weapon_line(c["id"])
	_kit.text = weapon if has_abilities else ("  ·  ".join(kit) if ready else "")
	# The weapon corner (icon, name, a few words) replaces the "Weapon: ..." line
	var w: Dictionary = KitDB.kit(c["id"]).get("weapon", {})
	_weapon_box.visible = not mystery and not w.is_empty()
	if _weapon_box.visible:
		var ic: Dictionary = w.get("icon", {})
		_weapon_icon.set_icon(ic, "weapon")
		_weapon_name.text = str(w.get("name", ""))
		_weapon_name.add_theme_color_override("font_color", Color.html(str(ic.get("tint", "#ffb020"))).lerp(Color.WHITE, 0.35))
		_weapon_short.text = str(w.get("short", ""))
		if has_abilities:
			_kit.text = ""
	_kit.visible = _kit.text != ""
	_play_btn.text = "PLAY"
	# Level and EXP sit in the preview's top-left corner (unlocked characters); the only text
	# under the abilities is for locked ones: what it takes to unlock them
	_status.visible = not mystery and not unlocked
	_level_box.visible = unlocked and not mystery
	if mystery:
		_status.text = ""
	elif unlocked:
		var cid: String = c["id"]
		var next := Wallet.next_level_exp(cid)
		var ex := Wallet.char_exp_of(cid)
		_level_label.text = tr("LVL %d") % Wallet.char_level(cid)
		_exp_label.text = (tr("%s / %s EXP") % [Wallet.fmt(ex), Wallet.fmt(next)]) if next >= 0 else tr("max level")
		_exp_bar.max_value = maxf(1.0, float(next)) if next >= 0 else 1.0
		_exp_bar.value = float(ex) if next >= 0 else 1.0
		_status.text = ""
	else:
		var ok := can_unlock(k)
		_status.text = "Ready to unlock" if ok else "Unlock Requirements:"
		_status.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45) if ok else Color(0.85, 0.5, 0.45))
		_play_btn.text = "UNLOCK"
	# Playable characters get the live model; everyone else a big portrait
	# 3D preview: the Fire Wizard's playable model, or a roster model if one has been made
	var cid3: String = c["id"]
	var model_3d := ready or RosterModel.has_model(cid3)
	_hero_preview.visible = cid3 == "fire_wizard"
	for pid in _previews:
		(_previews[pid] as Node3D).visible = pid == cid3
	if model_3d and cid3 != "fire_wizard" and not _previews.has(cid3):
		var rm := RosterModel.create(cid3)
		_model_pivot.add_child(rm)
		_previews[cid3] = rm
	_view_box.visible = model_3d
	_big_icon.visible = not model_3d
	_big_icon.locked = not unlocked and not mystery
	_big_icon.set_icon(c["icon"])
	for j in _tiles.size():
		(_tiles[j].get_meta("icon") as CharacterIcon).animate = j == k
	_req_box.visible = not unlocked and not mystery
	for r in _req_rows.get_children():
		r.queue_free()
	if _req_box.visible:
		for req in requirements(k):
			var chip := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.06, 0.04, 0.03, 0.85)
			sb.border_color = Color(0.35, 0.6, 0.3, 0.9) if req["met"] else Color(0.6, 0.25, 0.18, 0.9)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(8)
			sb.content_margin_left = 10
			sb.content_margin_right = 14
			sb.content_margin_top = 5
			sb.content_margin_bottom = 5
			chip.add_theme_stylebox_override("panel", sb)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			chip.add_child(row)
			var mark := ReqMark.new()
			mark.met = req["met"]
			row.add_child(mark)
			row.add_child(_label(req["text"], 19, Color(0.75, 0.95, 0.7) if req["met"] else Color(0.95, 0.85, 0.76)))
			_req_rows.add_child(chip)
	if mystery:
		_play_btn.disabled = true
	elif not unlocked:
		_play_btn.disabled = not can_unlock(k)
	else:
		_play_btn.disabled = not ready
	_skills_btn.disabled = not unlocked or mystery


## Buy a locked character with coins.
func unlock(k: int) -> bool:
	if not can_unlock(k) or not Wallet.spend(price_of(k)):
		return false
	Wallet.unlock_char(characters[k]["id"])
	refresh_levels()
	_shown = -1
	_show(k)
	var b := _tiles[k]
	b.pivot_offset = b.size * 0.5
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector2(1.12, 1.12), 0.1)
	tw.tween_property(b, "scale", Vector2.ONE, 0.18)
	_skills_btn.grab_focus()
	_reveal_weapon(k)
	return true


## "UNLOCKED <weapon>" with the character's weapon as a game card.
var reveal: UnlockReveal

func _reveal_weapon(k: int) -> void:
	var id: String = characters[k]["id"]
	var w: Dictionary = KitDB.kit(id).get("weapon", {})
	if w.is_empty():
		return
	var ribbon := "SIGNATURE WEAPON"
	if WeaponSystem.STYLE_CHAR.values().has(id):
		ribbon = "NEW LEGENDARY LEVEL-UP REWARD"
	reveal = UnlockReveal.show_for(self, str(characters[k]["name"]), w, ribbon, _font, _font_bold)


func _choose(k: int) -> void:
	_show(k)
	if can_unlock(k):
		_play_btn.grab_focus()   # "Unlock" is ready to press
		return
	if not is_unlocked(k) or not is_ready(k):
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
	if _leaving or _shown < 0:
		return
	if not is_unlocked(_shown):
		unlock(_shown)
		return
	if not is_ready(_shown):
		return
	Settings.selected_character = characters[_shown]["id"]
	if _picker != null:
		return
	_picker = MapPicker.create(_font)
	_fade.get_parent().add_child(_picker)
	_fade.get_parent().move_child(_picker, _fade.get_index())   # under the fade
	_picker.chosen.connect(func(_m: String): _leave(GAME_SCENE))
	_picker.cancelled.connect(func():
		_picker.queue_free()
		_picker = null
		_play_btn.grab_focus())


var _picker: MapPicker


func _back() -> void:
	_leave(TITLE_SCENE)


func _leave(scene: String) -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	if scene == GAME_SCENE:
		MenuMusic.fade_out(0.45)
	tw.chain().tween_callback(func(): get_tree().change_scene_to_file(scene))


func _open_skills() -> void:
	if _shown < 0 or not is_unlocked(_shown):
		return
	skills.open(characters[_shown]["id"], characters[_shown]["name"])


func _unhandled_input(event: InputEvent) -> void:
	if skills.visible or is_instance_valid(reveal):
		return   # the skill screen / unlock reveal handle their own input
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
		elif a == "--shot-levels":   # demo levels (screenshot runs don't save)
			for id in ["fire_wizard", "kong", "thog", "merlin"]:
				Wallet.set_char_exp(id, {"fire_wizard": 62000000, "kong": 12500, "thog": 1000000000, "merlin": 2500}[id])
			refresh_levels()
		elif a == "--shot-skills":   # demo tree: lvl 3 (Special still locked), 2 skills learned (not saved)
			Wallet.set_char_exp("fire_wizard", 61234)
			for sk in ["kindling", "ember_hide"]:
				SkillTree.learn("fire_wizard", sk)
			refresh_levels()
			_open_skills.call_deferred()
		elif a == "--shot-skills-5":   # demo tree at lvl 6 with Special open
			Wallet.set_char_exp("fire_wizard", 5600000)
			for sk in ["kindling", "wildfire", "ember_hide", "fleet"]:
				SkillTree.learn("fire_wizard", sk)
			refresh_levels()
			_open_skills.call_deferred()
		elif a.begins_with("--shot-coins="):
			Wallet.coins = int(a.split("=")[1])
			Wallet.displayed = Wallet.coins
		elif a.begins_with("--shot-ability="):   # show ability i's hover tooltip
			var i := int(a.split("=")[1])
			(func(): _on_slot_hover(i, true)).call_deferred()
		elif a.begins_with("--shot-unlock="):   # buy this character (not saved) to show the weapon reveal
			var k := index_of(a.split("=")[1])
			if k >= 0:
				Wallet.coins = maxi(Wallet.coins, price_of(k))
				(func():
					_show(k)
					unlock(k)).call_deferred()
		elif a.begins_with("--shot-char="):
			var k := index_of(a.split("=")[1])
			if k >= 0:
				_tiles[k].grab_focus.call_deferred()


func _shot_tick() -> void:
	if _shot_path == "" or _t < _shot_at:
		return
	var path := _shot_path
	_shot_path = ""
	_update_tooltip()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT saved ", path)
	get_tree().quit()


## A tick (met) or a cross (not yet) in front of an unlock requirement.
class ReqMark extends Control:
	var met := false

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(11, 11)
		draw_circle(c, 10.5, Color(0.25, 0.55, 0.22) if met else Color(0.45, 0.14, 0.1))
		draw_arc(c, 10.5, 0, TAU, 24, Color(0.75, 0.95, 0.65) if met else Color(0.95, 0.45, 0.35), 1.5, true)
		if met:
			draw_polyline(PackedVector2Array([Vector2(6, 11.5), Vector2(9.5, 15), Vector2(16, 7.5)]), Color.WHITE, 2.5, true)
		else:
			draw_line(Vector2(7, 7), Vector2(15, 15), Color.WHITE, 2.5, true)
			draw_line(Vector2(15, 7), Vector2(7, 15), Color.WHITE, 2.5, true)
