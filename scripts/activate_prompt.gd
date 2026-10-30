class_name ActivatePrompt
extends Label3D
## A "press the Activate key" prompt floating over something you can use (chests, power-ups): the key is whatever is
## bound to Activate (Settings > Controls). It gently grows and shrinks. Show/hide with `visible`.

var _t := 0.0


func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	render_priority = 10
	font_size = 44
	outline_size = 12
	pixel_size = 0.008
	modulate = Color(1.0, 0.95, 0.75)
	outline_modulate = Color(0.05, 0.03, 0.02)
	visible = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh_text()


## The prompt with the current Activate key (e.g. Press E).
func refresh_text() -> void:
	text = tr("Press %s") % Settings.key_text("activate")


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	var s := 1.0 + 0.08 * sin(_t * 4.0)
	scale = Vector3.ONE * s
	if fmod(_t, 1.0) < dt:   # keep up if the key was rebound
		refresh_text()
