class_name RosterModel
extends Node3D
## A roster character's rigged 3D model (from Higgsfield/Meshy) for previews: loads
## models/<id>/<id>.glb plus models/<id>/anims.res (made by tools/import_character.gd), faces
## -Z, plays its idle loop, and holds its weapon (built in code, like the wizard's staff).
## Characters without a skeleton (Ghast) float and sway procedurally instead.

const DIR := "res://models/%s"

var char_id := ""
var player: AnimationPlayer
var skeleton: Skeleton3D
var _rig: Node3D
var _t := 0.0
var _floaty := false


static func has_model(id: String) -> bool:
	var m := RosterHero.model_of(id)
	return ResourceLoader.exists((DIR % m).path_join(m + ".glb"))


static func create(id: String) -> RosterModel:
	var m := RosterModel.new()
	m.char_id = id
	return m


func _ready() -> void:
	# Thog borrows the Ogre's model (re-skinned, a size up) until he has his own
	var cfg: Dictionary = RosterHero.CFG.get(char_id, {})
	var mid := RosterHero.model_of(char_id)
	var dir := DIR % mid
	_rig = (load(dir.path_join(mid + ".glb")) as PackedScene).instantiate()
	_rig.rotation.y = PI          # GLBs face +Z; the game faces -Z
	_rig.scale = Vector3.ONE * float(cfg.get("scale", 1.0))
	add_child(_rig)
	if cfg.has("skin") and ResourceLoader.exists(cfg["skin"]):
		var skin: Texture2D = load(cfg["skin"])
		for mi in _rig.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for k in m.mesh.get_surface_count():
				var src := m.get_active_material(k)
				if src is StandardMaterial3D:
					var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					mat.albedo_texture = skin
					m.set_surface_override_material(k, mat)
	var sks := _rig.find_children("*", "Skeleton3D", true, false)
	skeleton = sks[0] if not sks.is_empty() else null
	var aps := _rig.find_children("*", "AnimationPlayer", true, false)
	player = aps[0] if not aps.is_empty() else null
	var lib_path := dir.path_join("anims.res")
	if player and ResourceLoader.exists(lib_path):
		player.add_animation_library("c", load(lib_path))
		if player.has_animation("c/idle"):
			player.play("c/idle")
		elif player.has_animation("c/attack"):   # no idle clip yet: hold the attack stance
			player.play("c/attack")
			player.seek(0.0, true)
			player.pause()
	_floaty = skeleton == null
	if skeleton:
		var w := RosterWeapons.attach(mid, skeleton)
		if w:
			w.scale *= float(cfg.get("weapon_scale", 1.0))


func play(clip: String) -> void:
	if player and player.has_animation("c/" + clip):
		player.play("c/" + clip, 0.15)


func _process(dt: float) -> void:
	_t += dt
	if _floaty:   # no skeleton: hover and sway
		_rig.position.y = 0.35 + 0.08 * sin(_t * 1.8)
		_rig.rotation.z = 0.05 * sin(_t * 1.1)
		_rig.rotation.y = PI + 0.08 * sin(_t * 0.7)
