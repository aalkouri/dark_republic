class_name GoblinAudio
extends Node3D
## Goblin voices.
##  - Ambient: every so often a random goblin near the player grunts. Each clip has its own
##    5 s cooldown, so the same sound never plays twice within 5 s.
##  - Collision: whenever a goblin runs into the player, play the grunt clip.
## Clips live in res://audio/goblin/. Missing files are skipped, so the game runs without them.

const AMBIENT_CLIPS := [
	"res://audio/goblin/grunt.wav",        # "Grrrrr... hnnngh! Grraaah!"
	"res://audio/goblin/laugh.wav",        # "Heh heh heh... kekeke!"
	"res://audio/goblin/battle_cry.wav",   # "Yaaargh! Get 'em! Kill kill kill!"
	"res://audio/goblin/ow_ack.wav",       # "Ow! Ack! Eeyah!"
	"res://audio/goblin/nooo.wav",         # "Nooo... eeeeeaaagh... urk."
]
signal played(clip: int, at: float)   # clip -1 = collision

const COLLISION_CLIP := "res://audio/goblin/hit_grunt.wav"   # grunt when a goblin runs into you

const CLIP_COOLDOWN := 5.0          # per clip
const AMBIENT_GAP := Vector2(0.8, 2.2)   # seconds between ambient attempts
const HEAR_RADIUS := 25.0
const VOICES := 6                   # simultaneous positional voices
const COLLISION_DEBOUNCE := 0.12

var enemies: EnemyManager
var player: Node3D
var rng: RandomNumberGenerator

var _ambient: Array[AudioStream] = []
var _last_played := PackedFloat32Array()
var _collision: AudioStream
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _hit_player: AudioStreamPlayer
var _gap := 1.0
var _time := 0.0
var _last_hit := -10.0


func setup(p_enemies: EnemyManager, p_player: Node3D, p_rng: RandomNumberGenerator) -> void:
	enemies = p_enemies
	player = p_player
	rng = p_rng


func _ready() -> void:
	for path in AMBIENT_CLIPS:
		var s := _try_load(path)
		if s != null:
			_ambient.append(s)
	_last_played.resize(_ambient.size())
	_last_played.fill(-CLIP_COOLDOWN)
	_collision = _try_load(COLLISION_CLIP)
	if _ambient.size() < AMBIENT_CLIPS.size() or _collision == null:
		print("GoblinAudio: %d/%d ambient clips, collision clip %s (add files to res://audio/goblin/)" % [
			_ambient.size(), AMBIENT_CLIPS.size(), "ok" if _collision else "missing"])

	for k in VOICES:
		var v := AudioStreamPlayer3D.new()
		v.unit_size = 6.0
		v.max_distance = HEAR_RADIUS * 1.6
		v.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		v.volume_db = -2.0
		v.bus = Settings.SFX_BUS
		add_child(v)
		_voices.append(v)
	_hit_player = AudioStreamPlayer.new()
	_hit_player.volume_db = 0.0
	_hit_player.bus = Settings.SFX_BUS
	add_child(_hit_player)


static func _try_load(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


func tick(dt: float) -> void:
	_time += dt
	_gap -= dt
	if _gap > 0.0:
		return
	_gap = rng.randf_range(AMBIENT_GAP.x, AMBIENT_GAP.y)
	var clip := _pick_clip()
	if clip < 0:
		return
	var near := enemies.query_radius(player.global_position, HEAR_RADIUS, false)
	if near.is_empty():
		return
	var who := near[rng.randi() % near.size()]
	_last_played[clip] = _time
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	v.stream = _ambient[clip]
	v.pitch_scale = rng.randf_range(0.93, 1.08) / sqrt(enemies.t_scale[enemies.typ[who]])   # big goblins sound deeper
	v.global_position = enemies.center_of(who)
	v.play()
	played.emit(clip, _time)


## A random ambient clip that's off its 5 s cooldown, or -1.
func _pick_clip() -> int:
	var ready := PackedInt32Array()
	for k in _ambient.size():
		if _time - _last_played[k] >= CLIP_COOLDOWN:
			ready.append(k)
	if ready.is_empty():
		return -1
	return ready[rng.randi() % ready.size()]


func play_collision() -> void:
	if _collision == null or _time - _last_hit < COLLISION_DEBOUNCE:
		return
	_last_hit = _time
	_hit_player.stream = _collision
	_hit_player.pitch_scale = rng.randf_range(0.95, 1.06)
	_hit_player.play()
	played.emit(-1, _time)


## For tests: seconds since a clip last played.
func since_played(clip: int) -> float:
	return _time - _last_played[clip]


func ambient_count() -> int:
	return _ambient.size()
