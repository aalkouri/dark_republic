class_name UnlockReveal
extends Control
## Full-screen reveal when you buy a character: "UNLOCKED <weapon>" over their weapon's game
## card, which flips in with a fanfare. Click or press any key to continue.

signal closed

const SOUND := "res://audio/ui/levelup_fanfare.wav"

var card: WeaponCard
var title: Label
var _t := 0.0
var _player: AudioStreamPlayer


static func show_for(parent: Node, char_name: String, weapon: Dictionary, ribbon: String, font: Font, font_bold: Font) -> UnlockReveal:
	var r := UnlockReveal.new()
	r._build(char_name, weapon, ribbon, font, font_bold)
	parent.add_child(r)
	return r


func _build(char_name: String, weapon: Dictionary, ribbon: String, font: Font, font_bold: Font) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	title = Label.new()
	title.text = tr("UNLOCKED %s") % tr(str(weapon.get("name", ""))).to_upper()
	title.add_theme_font_override("font", font_bold)
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.38))
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.04, 0.0))
	title.add_theme_constant_override("outline_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -800
	title.offset_right = 800
	title.offset_top = 70
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	card = WeaponCard.create(char_name, weapon, ribbon, font, font_bold)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.position = -WeaponCard.SIZE * 0.5 + Vector2(0, 40)
	card.scale = Vector2(0.05, 0.6)
	add_child(card)
	var hint := Label.new()
	hint.text = "Click to continue"
	hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.8, 0.75, 0.68, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -300
	hint.offset_right = 300
	hint.offset_top = -60
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	_player = AudioStreamPlayer.new()
	_player.bus = Settings.SFX_BUS
	if ResourceLoader.exists(SOUND):
		_player.stream = load(SOUND)
	add_child(_player)


func _ready() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	# The card flips in (thin -> full width), overshoots a little, settles
	var ct := create_tween()
	ct.tween_interval(0.15)
	ct.tween_property(card, "scale", Vector2(1.08, 1.08), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ct.tween_property(card, "scale", Vector2.ONE, 0.15)
	title.scale = Vector2(1.4, 1.4)
	title.pivot_offset = Vector2(800, 30)
	var tt := create_tween()
	tt.tween_interval(0.25)
	tt.tween_property(title, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _player.stream:
		_player.play()


func _process(dt: float) -> void:
	_t += dt
	card.rotation = sin(_t * 1.3) * 0.015


func _gui_input(event: InputEvent) -> void:
	if _t > 0.5 and event is InputEventMouseButton and event.pressed:
		close()
	accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		get_viewport().set_input_as_handled()
		if _t > 0.5:
			close()


func close() -> void:
	if is_queued_for_deletion():
		return
	set_process_unhandled_input(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		closed.emit()
		queue_free())
