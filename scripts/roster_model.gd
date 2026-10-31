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
	if RosterHero.CFG.get(id, {}).has("procedural"):
		return true
	var m := RosterHero.model_of(id)
	return ResourceLoader.exists((DIR % m).path_join(m + ".glb"))


static func create(id: String) -> RosterModel:
	var m := RosterModel.new()
	m.char_id = id
	return m


var _sock: SockBody
var _loco: LocoBody
var _knight: ToadstoolBody
var _blob: BlobBody
var _spider: ArachnidBody


func _ready() -> void:
	if RosterHero.CFG.get(char_id, {}).get("procedural", "") == "arachnid":   # built in code
		_spider = ArachnidBody.create()
		_rig = _spider
		add_child(_spider)
		return
	if RosterHero.CFG.get(char_id, {}).get("procedural", "") == "blob":   # built in code
		_blob = BlobBody.create()
		_rig = _blob
		add_child(_blob)
		return
	if RosterHero.CFG.get(char_id, {}).get("procedural", "") == "sock":   # built in code
		_sock = SockBody.create()
		_rig = _sock
		add_child(_sock)
		return
	if RosterHero.CFG.get(char_id, {}).get("procedural", "") == "toadstool":   # the boss's body, player size
		_knight = ToadstoolBody.create()
		_rig = _knight
		add_child(_knight)
		return
	if RosterHero.CFG.get(char_id, {}).get("procedural", "") == "loco":   # built in code
		_loco = LocoBody.create()
		_rig = _loco
		add_child(_loco)
		return
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
	if _spider:   # idles: breathes and sways, now and then rears up and spits
		var c := fmod(_t, 5.0)
		if c < dt * 1.01 and _t > 1.0:
			_spider.spit()
		_spider.animate(dt, 0.0, false, clampf((c - 2.5) / 1.2, 0.0, 1.0) if c > 2.5 and c < 3.7 else 0.0)
		return
	if _blob:   # idles: jiggles, now and then a little bounce (stretch, then splat)
		_blob.animate(dt, 0.0, fmod(_t, 3.0) < 0.22, 0.0, 0.0, 0.0)
		return
	if _sock:   # idles: sways, now and then a little hop
		_sock.animate(dt, 0.0, false, 0.0, 0.3 if fmod(_t, 4.0) < 0.3 else 0.0)
		return
	if _knight:   # stands guard, now and then a practice cut with his sword
		if fmod(_t, 4.0) < dt * 1.01 and _t > 1.0:
			_knight.slash()
		_knight.animate(dt, 0.0)
		return
	if _loco:   # dances on the spot, shaking a maraca now and then
		if fmod(_t, 0.9) < dt:
			_loco.shake()
		_loco.animate(dt, 0.0, false)
		return
	if _floaty:   # no skeleton: hover and sway
		_rig.position.y = 0.35 + 0.08 * sin(_t * 1.8)
		_rig.rotation.z = 0.05 * sin(_t * 1.1)
		_rig.rotation.y = PI + 0.08 * sin(_t * 0.7)
