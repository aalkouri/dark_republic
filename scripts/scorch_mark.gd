class_name ScorchMark
extends Node3D
## What a burnt-out tree, log or bush leaves behind for the rest of the match: a black, charred
## patch on the ground (draped over the hills) ringed with ash, glowing embers, a thin column of
## smoke and a quiet sizzle you hear when you're close.

const GROUP := "scorch_marks"
const SIZZLE := "res://audio/forest/sizzle.wav"
const HEAR_DIST := 16.0              # the sizzle only plays this close (lots of patches stay quiet)

var radius := 2.5
var _embers: CPUParticles3D
var _sound: AudioStreamPlayer3D
var _check := 0.0
var _t := 0.0
var _glow: GroundDisc
static var _stream: AudioStream


## Leave a scorch mark of `r` metres at `at` (world) under `parent`.
static func spawn(parent: Node, at: Vector3, r: float) -> ScorchMark:
	var s := ScorchMark.new()
	s.radius = r
	s.top_level = true
	parent.add_child(s)
	s.global_position = at
	return s


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var ash := GroundDisc.create(radius * 1.25, Color(0.16, 0.14, 0.13, 0.55))
	ash.set_lift(0.05)
	add_child(ash)
	var black := GroundDisc.create(radius, Color(0.03, 0.025, 0.02, 0.92))
	black.set_lift(0.06)
	add_child(black)
	_glow = GroundDisc.create(radius * 0.55, Color(1.0, 0.32, 0.06, 0.25), true)   # embers in the middle
	_glow.set_lift(0.07)
	add_child(_glow)
	# Smoke: a slow grey column, wider for bigger patches
	var smoke := Abilities._flame_particles(1.0, 4.0, clampi(int(radius * 5.0), 6, 18))
	var puff := SphereMesh.new()   # soft round puffs (a sprite's dot texture draws black-centred here)
	puff.radius = 0.4
	puff.height = 0.8
	puff.radial_segments = 8
	puff.rings = 4
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.vertex_color_use_as_albedo = true
	pm.disable_fog = true
	pm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	puff.material = pm
	smoke.mesh = puff
	smoke.emission_sphere_radius = radius * 0.5
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 1.1
	smoke.gravity = Vector3(0.25, 0.25, 0.0)   # drifts a little
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.53, 0.5, 0.0))
	grad.set_color(1, Color(0.75, 0.75, 0.75, 0.0))
	grad.add_point(0.2, Color(0.5, 0.48, 0.46, 0.3))
	smoke.color_ramp = grad
	smoke.position.y = 0.3
	add_child(smoke)
	# Embers popping up now and then
	_embers = Abilities._flame_particles(0.12, 0.8, 6)
	_embers.emission_sphere_radius = radius * 0.6
	_embers.initial_velocity_min = 0.6
	_embers.initial_velocity_max = 1.8
	_embers.position.y = 0.15
	(_embers.mesh as QuadMesh).size = Vector2(0.08, 0.08)
	add_child(_embers)
	# The sizzle (only while you're close)
	if _stream == null and ResourceLoader.exists(SIZZLE):
		_stream = load(SIZZLE)
		if _stream is AudioStreamWAV:
			var w := (_stream as AudioStreamWAV).duplicate() as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_end = int(w.get_length() * w.mix_rate)
			_stream = w
	_sound = AudioStreamPlayer3D.new()
	_sound.bus = Settings.SFX_BUS
	_sound.stream = _stream
	_sound.unit_size = 3.0
	_sound.max_distance = HEAR_DIST
	_sound.volume_db = -8.0
	_sound.position.y = 0.4
	add_child(_sound)
	_check = randf() * 0.5


func _process(dt: float) -> void:
	_t += dt
	_glow.alpha = 0.16 + 0.1 * sin(_t * 2.3 + radius) * sin(_t * 5.1)
	_check -= dt
	if _check > 0.0:
		return
	_check = 0.5
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var near := pl != null and pl.global_position.distance_to(global_position) < HEAR_DIST
	if near and not _sound.playing and _sound.stream != null:
		_sound.play(randf() * 2.0)
	elif not near and _sound.playing:
		_sound.stop()
