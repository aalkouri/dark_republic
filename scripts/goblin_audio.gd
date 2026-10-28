class_name GoblinAudio
extends Node3D
## Goblin death sounds. Goblins make no other sounds (no voices, no grunts).
## Every kill near the player plays a short "splat-pop" (4 variants, slight random pitch; big
## goblins sound deeper), heard from where the goblin died. A burst of kills is rate-limited so
## a 50-goblin explosion sounds like a crunchy volley, not a wall of noise.
## Clips: res://audio/goblin/death_*.wav (tools/gen_goblin_death_sounds.py).

signal played(at: Vector3)

const DEATH_CLIPS := [
	"res://audio/goblin/death_1.wav",
	"res://audio/goblin/death_2.wav",
	"res://audio/goblin/death_3.wav",
	"res://audio/goblin/death_4.wav",
]
const HEAR_RADIUS := 30.0      # kills further away are silent
const MIN_GAP := 0.045         # seconds between death sounds
const VOICES := 8              # simultaneous positional voices
const VOLUME_DB := -4.0

var enemies: EnemyManager
var player: Node3D
var rng: RandomNumberGenerator

var _clips: Array[AudioStream] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _time := 0.0
var _last := -10.0


func setup(p_enemies: EnemyManager, p_player: Node3D, p_rng: RandomNumberGenerator) -> void:
	enemies = p_enemies
	player = p_player
	rng = p_rng


func _ready() -> void:
	for path in DEATH_CLIPS:
		if ResourceLoader.exists(path):
			_clips.append(load(path) as AudioStream)
	for k in VOICES:
		var v := AudioStreamPlayer3D.new()
		v.unit_size = 8.0
		v.max_distance = HEAR_RADIUS * 1.5
		v.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		v.volume_db = VOLUME_DB
		v.bus = Settings.SFX_BUS
		add_child(v)
		_voices.append(v)
	Events.enemy_killed.connect(_on_enemy_killed)


func tick(dt: float) -> void:
	_time += dt


func _on_enemy_killed(p: Vector3, type_id: int) -> void:
	if _clips.is_empty() or _time - _last < MIN_GAP:
		return
	if player != null and p.distance_to(player.global_position) > HEAR_RADIUS:
		return
	_last = _time
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	v.stream = _clips[rng.randi() % _clips.size() if rng else 0]
	var big := enemies.t_scale[type_id] if enemies != null and type_id >= 0 and type_id < enemies.t_scale.size() else 1.0
	v.pitch_scale = (rng.randf_range(0.9, 1.12) if rng else 1.0) / sqrt(big)
	v.global_position = p + Vector3(0, 0.5, 0)
	v.play()
	played.emit(p)
