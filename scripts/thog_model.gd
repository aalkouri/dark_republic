class_name ThogModel
extends Node3D
## Thog the Troll's body, for the Swamp boss. Stand-in: the rigged Ogre model (models/ogre/)
## with its skin re-tinted troll blue (models/ogre/thog_skin.jpg, made from the Ogre's texture),
## until Thog gets his own model. Faces -Z, origin at the feet, MODEL_HEIGHT tall at scale 1.
##
## Plays segments of the Ogre's Lean clip set: walk (run, slowed), slam, sweep and bellow
## (segments of the ability / attack clips), hit, and a death made from the hit clip.

const DIR := "res://models/ogre"
const MODEL_HEIGHT := 2.3
const SKIN := "res://models/ogre/thog_skin.jpg"
# Clip segments [clip, start, end]: picked from contact sheets of the Ogre's clips
const SEG := {
	"walk": ["run", 0.0, 0.8333],
	"idle": ["idle", 0.0, 4.0333],
	"slam": ["attack", 0.8, 1.8667],   # both arms up overhead, then smashed down into a crouch
	"sweep": ["ability", 0.4, 1.9],    # the club arm raised high, then swung down and across
	"bellow": ["hit", 0.1, 1.0],       # rears back, arms flung up: the roar
	"hit": ["hit", 0.1, 0.9],
	"death": ["hit", 0.0, 1.6667],
}

var player: AnimationPlayer
var _rig: Node3D
var _mats: Array[StandardMaterial3D] = []
var _seg := ""
var _end := 0.0
var _loop := false
var _enrage := 0.0
var _flash := 0.0


func _ready() -> void:
	_rig = (load(DIR.path_join("ogre.glb")) as PackedScene).instantiate()
	_rig.rotation.y = PI   # the GLB faces +Z; the game faces -Z
	add_child(_rig)
	var old := _rig.get_node_or_null("AnimationPlayer")
	if old:
		old.free()
	var skin: Texture2D = load(SKIN) if ResourceLoader.exists(SKIN) else null
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			if src is StandardMaterial3D:
				var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				if skin:
					mat.albedo_texture = skin
				mat.emission_enabled = true
				mat.emission = Color.BLACK
				m.set_surface_override_material(s, mat)
				_mats.append(mat)
	player = AnimationPlayer.new()
	_rig.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("c", load(DIR.path_join("anims.res")))
	play("idle", 1.0, true)


## Play a named segment at `speed` (looping for walk / idle).
func play(seg: String, speed := 1.0, loop := false) -> void:
	var s: Array = SEG[seg]
	if _seg == seg and _loop and loop:
		player.speed_scale = speed
		return
	_seg = seg
	_loop = loop
	_end = float(s[2])
	player.play("c/" + str(s[0]), 0.12, 1.0)
	player.seek(float(s[1]), true)
	player.speed_scale = speed


## Seconds a segment takes at `speed`.
static func seg_time(seg: String, speed := 1.0) -> float:
	var s: Array = SEG[seg]
	return (float(s[2]) - float(s[1])) / speed


func is_playing_seg(seg: String) -> bool:
	return _seg == seg


## Red-hot skin while enraged (0..1), a white flash when hit.
func set_enrage(k: float) -> void:
	_enrage = k


func flash() -> void:
	_flash = 0.1


func _process(dt: float) -> void:
	if player.current_animation != "" and player.current_animation_position >= _end - 0.001:
		var s: Array = SEG[_seg]
		if _loop:
			player.seek(float(s[1]), true)
		else:
			player.pause()   # hold the last pose until the next play()
	_flash = maxf(_flash - dt, 0.0)
	var glow := Color(1.0, 0.15, 0.04) * (_enrage * (0.16 + 0.08 * sin(Time.get_ticks_msec() * 0.012))) + Color(1, 1, 1) * (_flash * 4.0)
	for m in _mats:
		m.emission = glow
