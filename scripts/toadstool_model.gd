class_name ToadstoolModel
extends Node3D
## The Toadstool Knight's body, for the Forest boss. Stand-in until he gets his own model:
## Gaiden's rigged swordsman (models/gaiden/) polished up into silver plate, wearing a huge
## glossy red toadstool cap with white spots (built in code on the Head bone), with a blade
## that glows violet with spores. Faces -Z, origin at the feet, MODEL_HEIGHT tall at scale 1.
##
## Plays segments of Gaiden's clips: walk (run, slowed), idle, slash (the overhead cut from the
## attack clip), cast (the forward thrust from the ability clip), hit and a death.
## The playable knight (ToadstoolBody) sets `animated = false` before adding it and drives the
## rig with its own AnimationTree instead (legs keep running while he slashes).

const DIR := "res://models/gaiden"
const MODEL_HEIGHT := 1.8
const CAP_RED := Color(0.78, 0.09, 0.06)
const SPOT := Color(0.97, 0.94, 0.86)
const GILL := Color(0.93, 0.86, 0.72)
const SPORE := Color(0.75, 0.45, 1.0)
const CAP_R := 0.44          # the cap's radius (metres, at scale 1)
const CAP_SQUASH := 0.62     # how flat the dome is
# Clip segments [clip, start, end] (picked from contact sheets: tools/render_clips.tscn)
const SEG := {
	"walk": ["run", 0.0, 0.5],
	"idle": ["idle", 0.0, 4.0333],
	"slash": ["attack", 0.55, 2.2],   # sword raised overhead, then cut down in front of him
	"cast": ["ability", 0.2, 1.7],    # blade swept low, then thrust forward: summons, spores
	"hit": ["hit", 0.1, 0.9],
	"death": ["hit", 0.0, 1.6667],
}
const SLASH_AT := 0.73   # fraction of "slash" when the blade comes down
const CAST_AT := 0.67    # fraction of "cast" at the thrust

var player: AnimationPlayer
var _rig: Node3D
var _mats: Array[StandardMaterial3D] = []
var _seg := ""
var _end := 0.0
var _loop := false
var _enrage := 0.0
var _flash := 0.0
var _blade_mats: Array[StandardMaterial3D] = []
var _cap_mats: Array[StandardMaterial3D] = []
var animated := true     # false: no AnimationPlayer (ToadstoolBody drives the rig)
var blade: Node3D        # the sword (its tip is BLADE_TIP up its local +Y)
var hurt := 0.0          # 0..1: flashes white-hot when hit (the playable knight)
var dim := 1.0           # brightness (the playable knight while immune)
const BLADE_TIP := 0.85


func _ready() -> void:
	_rig = (load(DIR.path_join("gaiden.glb")) as PackedScene).instantiate()
	_rig.rotation.y = PI   # the GLB faces +Z; the game faces -Z
	add_child(_rig)
	var old := _rig.get_node_or_null("AnimationPlayer")
	if old:
		old.free()
	# Polished silver plate over the dark cloth
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			if src is StandardMaterial3D:
				var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				mat.albedo_color = Color(2.0, 2.05, 2.2)
				mat.metallic = 0.6
				mat.roughness = 0.42
				mat.emission_enabled = true
				mat.emission = Color.BLACK
				m.set_surface_override_material(s, mat)
				_mats.append(mat)
	var sk := _skeleton()
	if sk:
		_add_cap(sk)
		blade = RosterWeapons.attach("gaiden", sk)
		if blade:
			blade.scale *= 1.25
			for mi in blade.find_children("*", "MeshInstance3D", true, false):
				var bm := (mi as MeshInstance3D).mesh
				if bm is BoxMesh and (bm as BoxMesh).size.y > 0.5:   # the blade itself
					var g := StandardMaterial3D.new()
					g.albedo_color = Color(0.85, 0.75, 1.0)
					g.metallic = 0.8
					g.emission_enabled = true
					g.emission = SPORE
					g.emission_energy_multiplier = 1.6
					(bm as BoxMesh).material = g
					_blade_mats.append(g)
	if not animated:
		return
	player = AnimationPlayer.new()
	_rig.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("c", load(DIR.path_join("anims.res")))
	play("idle", 1.0, true)


func _skeleton() -> Skeleton3D:
	var sks := _rig.find_children("*", "Skeleton3D", true, false)
	return sks[0] if not sks.is_empty() else null


## The toadstool cap on the Head bone: a wide glossy red dome with white spots, cream gills under
## the rim. Built in metres and placed in skeleton space (centimetres).
func _add_cap(sk: Skeleton3D) -> void:
	var b := sk.find_bone("Head")
	if b < 0:
		return
	var cap := Node3D.new()
	var red := StandardMaterial3D.new()
	red.albedo_color = CAP_RED
	red.roughness = 0.28
	red.clearcoat_enabled = true
	red.clearcoat = 0.6
	_cap_mats.append(red)
	var dome := SphereMesh.new()
	dome.radius = CAP_R
	dome.height = CAP_R   # a hemisphere needs height == radius
	dome.is_hemisphere = true
	dome.material = red
	var dmi := MeshInstance3D.new()
	dmi.mesh = dome
	dmi.scale = Vector3(1.0, CAP_SQUASH, 1.0)
	dmi.position = Vector3(0, 0.0, 0)
	cap.add_child(dmi)
	var gill_mat := StandardMaterial3D.new()
	gill_mat.albedo_color = GILL
	gill_mat.roughness = 0.9
	_cap_mats.append(gill_mat)
	var gills := CylinderMesh.new()
	gills.top_radius = CAP_R * 0.98
	gills.bottom_radius = CAP_R * 0.3
	gills.height = 0.08
	gills.material = gill_mat
	var gmi := MeshInstance3D.new()
	gmi.mesh = gills
	gmi.position = Vector3(0, -0.04, 0)
	cap.add_child(gmi)
	var white := StandardMaterial3D.new()
	white.albedo_color = SPOT
	white.roughness = 0.6
	_cap_mats.append(white)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 13:
		var a := rng.randf() * TAU
		var e := rng.randf_range(0.12, 1.25)   # elevation on the dome
		var n := Vector3(cos(a) * cos(e), sin(e) * CAP_SQUASH, sin(a) * cos(e)).normalized()
		var spot := SphereMesh.new()
		var r := rng.randf_range(0.035, 0.07)
		spot.radius = r
		spot.height = r * 0.7
		spot.material = white
		var smi := MeshInstance3D.new()
		smi.mesh = spot
		var p := Vector3(cos(a) * cos(e) * CAP_R, sin(e) * CAP_R * CAP_SQUASH, sin(a) * cos(e) * CAP_R)
		smi.position = p
		smi.basis = Basis(Quaternion(Vector3.UP, n))
		cap.add_child(smi)
	# Into skeleton space, sitting on top of the head
	var rest := sk.get_bone_global_rest(b)
	var want := Transform3D(Basis().scaled(Vector3.ONE * 100.0), rest.origin + Vector3(0, 14.0, 0))
	var attach := BoneAttachment3D.new()
	attach.bone_name = "Head"
	sk.add_child(attach)
	cap.transform = rest.affine_inverse() * want
	attach.add_child(cap)


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


static func seg_time(seg: String, speed := 1.0) -> float:
	var s: Array = SEG[seg]
	return (float(s[2]) - float(s[1])) / speed


func set_enrage(k: float) -> void:
	_enrage = k


func flash() -> void:
	_flash = 0.1


## Brightness of the whole knight (1 = normal; the playable knight dims while immune).
func set_dim(f: float) -> void:
	dim = f
	for m in _mats:
		m.albedo_color = Color(2.0 * f, 2.05 * f, 2.2 * f)
	var bases: Array[Color] = [CAP_RED, GILL, SPOT]
	for k in mini(_cap_mats.size(), 3):
		var c: Color = bases[k]
		_cap_mats[k].albedo_color = Color(c.r * f, c.g * f, c.b * f)


func _process(dt: float) -> void:
	if player != null and player.current_animation != "" and player.current_animation_position >= _end - 0.001:
		var s: Array = SEG[_seg]
		if _loop:
			player.seek(float(s[1]), true)
		else:
			player.pause()
	_flash = maxf(_flash - dt, 0.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)
	var glow := Color(0.55, 0.15, 0.9) * (_enrage * (0.12 + 0.08 * pulse)) + Color(1, 1, 1) * (_flash * 4.0) + Color(1.0, 0.85, 0.75) * hurt
	for m in _mats:
		m.emission = glow
	for g in _blade_mats:
		g.emission_energy_multiplier = 1.4 + 1.2 * _enrage * pulse
