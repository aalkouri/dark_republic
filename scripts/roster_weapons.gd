class_name RosterWeapons
extends RefCounted
## Hand-held weapons for roster characters, built from primitives and attached to the hand
## bones (like the Fire Wizard's staff), so they follow every animation without being baked
## into the body mesh. Each weapon is modelled along its local +Y (grip at the origin) and
## pointed in the rest pose: staffs and spears straight up, blades forward.

const SKIN_UP := Vector3.UP
const FORWARD := Vector3(0, 0, 1)   # GLB characters face +Z in skeleton space


## Returns the right-hand weapon (staffs have their head 0.9 m up their local +Y).
static func attach(id: String, skeleton: Skeleton3D) -> Node3D:
	var all := attach_all(id, skeleton)
	return all[0] if not all.is_empty() else null


## Every weapon the character holds (the Rogue has a dagger in each hand), right hand first.
static func attach_all(id: String, skeleton: Skeleton3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for k in count(id):
		var spec: Array = _grip(id, k)
		var w := _hold(skeleton, spec[0], make(id, k), spec[1])
		if w:
			out.append(w)
	return out


## How many weapons the character holds (0 for the ones without a weapon model here).
static func count(id: String) -> int:
	if id == "rogue":
		return 2
	return 1 if id in ["ice_wizard", "merlin", "thunder_wizard", "dark_wizard", "ogre", "vampire_hunter", "vicki", "gaiden", "dr_croc"] else 0


## Builds weapon `k` of character `id` (a fresh instance each call), grip at the origin.
static func make(id: String, _k := 0) -> Node3D:
	match id:
		"ice_wizard":
			return _staff(Color(0.55, 0.6, 0.68), _crystal(Color(0.6, 0.9, 1.0)))
		"merlin":
			return _staff(Color(0.3, 0.2, 0.12), _orb(Color(0.45, 0.65, 1.0)))
		"thunder_wizard":
			return _staff(Color(0.4, 0.38, 0.42), _orb(Color(1.0, 0.92, 0.35)))
		"dark_wizard":
			return _staff(Color(0.08, 0.06, 0.1), _skull())
		"ogre":
			return _club()
		"vampire_hunter":
			return _crossbow()
		"vicki":
			return _spear()
		"rogue":
			return _blade(0.32, 0.035, Color(0.8, 0.82, 0.86))
		"gaiden", "toadstool_knight":   # (the Knight's sword is Gaiden's katana, re-coloured)
			return _blade(0.85, 0.03, Color(0.86, 0.88, 0.92), true)
		"dr_croc":
			return _flask()
	return null


## [hand bone, the weapon's +Y in the rest pose (skeleton space)] for weapon `k`.
static func _grip(id: String, k: int) -> Array:
	match id:
		"ogre":
			return ["RightHand", (FORWARD + Vector3.DOWN * 0.6).normalized()]
		"vampire_hunter":
			return ["RightHand", (Vector3.DOWN + FORWARD * 0.35).normalized()]
		"rogue":
			return ["RightHand" if k == 0 else "LeftHand", FORWARD]
		"gaiden":
			return ["RightHand", (Vector3.DOWN + FORWARD * 0.5).normalized()]
	return ["RightHand", SKIN_UP]


# ------------------------------------------------------------------ put away
# Where each weapon goes when the character isn't fighting (RosterHero / RosterModel draw it
# into the hand to attack and put it back after a moment). One entry per held weapon, in
# attach_all()'s order: [body bone it rides on, grip position in metres (character space: +X
# their left, +Y up, +Z forward, from the feet, before the rig's scale), the weapon's +Y, the
# way its local +Z faces, sheath ("" none, "katana", "dagger")].
const STOW := {
	# Staffs slung diagonally across the back, the head up over the right shoulder
	"ice_wizard": [["Spine01", Vector3(0.07, 1.12, -0.25), Vector3(-0.58, 1, 0), Vector3(0, 0, -1), ""]],
	"thunder_wizard": [["Spine01", Vector3(0.07, 1.12, -0.19), Vector3(-0.58, 1, 0), Vector3(0, 0, -1), ""]],
	"dark_wizard": [["Spine01", Vector3(0.07, 1.12, -0.22), Vector3(-0.58, 1, 0), Vector3(0, 0, -1), ""]],
	"merlin": [["Spine01", Vector3(0.07, 1.12, -0.23), Vector3(-0.58, 1, 0), Vector3(0, 0, -1), ""]],
	# The spear the same way, longer, so it rides lower
	"vicki": [["Spine01", Vector3(0.1, 1.0, -0.22), Vector3(-0.55, 1, 0), Vector3(0, 0, -1), ""]],
	# The tree-trunk club across the Ogre's back, the heavy end over his right shoulder
	"ogre": [["Spine01", Vector3(0.28, 1.3, -0.43), Vector3(-0.55, 1, 0), Vector3(0, 0, -1), ""]],
	# The crossbow on the back, stock up, the bow across the shoulder blades
	"vampire_hunter": [["Spine01", Vector3(0.06, 0.98, -0.21), Vector3(-0.22, 1, 0), Vector3(0, 0, -1), ""]],
	# Daggers in sheaths on both hips, hilts up
	"rogue": [
		["Hips", Vector3(-0.2, 0.97, 0.04), Vector3(-0.12, -1, -0.28), Vector3(-1, 0, 0), "dagger"],
		["Hips", Vector3(0.2, 0.97, 0.04), Vector3(0.12, -1, -0.28), Vector3(1, 0, 0), "dagger"],
	],
	# The katana in its scabbard on the back, the hilt up over the right shoulder
	"gaiden": [["Spine01", Vector3(-0.13, 1.42, -0.17), Vector3(0.62, -1, 0), Vector3(0, 0, -1), "katana"]],
	# The Toadstool Knight (on Gaiden's rig, ToadstoolBody): his sword sheathed at the left hip,
	# hilt forward, the scabbard hanging back
	"toadstool_knight": [["Hips", Vector3(0.21, 1.0, 0.12), Vector3(0.14, -0.5, -0.86), Vector3(1, 0, 0), "katana"]],
	# A flask hooked on the belt at the right hip
	"dr_croc": [["Hips", Vector3(-0.27, 0.86, 0.1), Vector3(0, 1, 0), Vector3(0, 0, 1), ""]],
}


## The put-away copies of the character's weapons on their back or belt (scaled by `scale`), in
## attach_all()'s order. Sheaths are added beside them and stay on when the weapon is drawn.
static func stow(id: String, skeleton: Skeleton3D, scale := 1.0) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not STOW.has(id) or skeleton == null:
		return out
	var specs: Array = STOW[id]
	for k in specs.size():
		var s: Array = specs[k]
		var w := _stow(skeleton, s[0], make(id, k), s[1], s[2], s[3])
		if w == null:
			continue
		w.scale *= scale
		out.append(w)
		if str(s[4]) != "":
			var sheath := _sheath(str(s[4]))
			sheath.transform = w.transform
			w.get_parent().add_child(sheath)
	return out


## Attach `weapon` to `bone`, its grip at `pos` (metres, character space) with its +Y along
## `ydir` and its +Z toward `zdir`, in the rest pose.
static func _stow(sk: Skeleton3D, bone: String, weapon: Node3D, pos: Vector3, ydir: Vector3, zdir: Vector3) -> Node3D:
	var b := sk.find_bone(bone)
	if b < 0 or weapon == null:
		return null
	var rest := sk.get_bone_global_rest(b)
	var y := ydir.normalized()
	var z := (zdir - y * zdir.dot(y)).normalized()
	var x := y.cross(z)
	var want := Transform3D(Basis(x, y, z).scaled(Vector3.ONE * 100.0), pos * 100.0)
	var attach := BoneAttachment3D.new()
	attach.bone_name = bone
	sk.add_child(attach)
	weapon.transform = rest.affine_inverse() * want
	attach.add_child(weapon)
	return weapon


## A scabbard around a put-away blade (weapon space: the blade runs up +Y from the guard).
static func _sheath(kind: String) -> Node3D:
	var n := Node3D.new()
	var box := BoxMesh.new()
	if kind == "katana":   # black lacquer with a gold collar and tip
		box.size = Vector3(0.05, 0.88, 0.026)
		box.material = _mat(Color(0.07, 0.05, 0.06), 0.0, 0.3)
		n.add_child(_part(box, Vector3(0.0, 0.56, 0.0), Vector3(0, 0, 0.06)))   # follows the blade's curve
		var collar := BoxMesh.new()
		collar.size = Vector3(0.056, 0.03, 0.032)
		collar.material = _mat(Color(0.6, 0.45, 0.18), 0.0, 0.8)
		n.add_child(_part(collar, Vector3(0.0, 0.135, 0.0)))
		n.add_child(_part(collar, Vector3(-0.026, 0.995, 0.0), Vector3(0, 0, 0.06)))
	else:   # a leather dagger sheath
		box.size = Vector3(0.052, 0.34, 0.026)
		box.material = _mat(Color(0.26, 0.16, 0.09))
		n.add_child(_part(box, Vector3(0.0, 0.225, 0.0)))
	return n


## Attach `weapon` to `bone`, gripped in the palm, its +Y pointing along `dir` (skeleton space)
## in the rest pose. Skeleton space is in centimetres (the Armature is scaled 0.01).
static func _hold(sk: Skeleton3D, bone: String, weapon: Node3D, dir: Vector3) -> Node3D:
	var b := sk.find_bone(bone)
	if b < 0:
		return null
	var parent := sk.get_bone_parent(b)
	var rest := sk.get_bone_global_rest(b)
	var along := (rest.origin - sk.get_bone_global_rest(parent).origin).normalized() if parent >= 0 else Vector3.DOWN
	var palm := rest.origin + along * 7.0
	var y := dir.normalized()
	var x := y.cross(FORWARD if absf(y.dot(FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var want := Transform3D(Basis(x, y, z).scaled(Vector3.ONE * 100.0), palm)
	var attach := BoneAttachment3D.new()
	attach.bone_name = bone
	sk.add_child(attach)
	weapon.transform = rest.affine_inverse() * want
	attach.add_child(weapon)
	return weapon


static func _mat(c: Color, emit := 0.0, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6 if metal > 0.0 else 0.85
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


static func _part(mesh: Mesh, at: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.rotation = rot
	return mi


static func _cyl(top: float, bottom: float, h: float, c: StandardMaterial3D, seg := 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.material = c
	return m


# ------------------------------------------------------------------ weapons

static func _staff(wood: Color, head: Node3D) -> Node3D:
	var n := Node3D.new()
	n.add_child(_part(_cyl(0.022, 0.03, 1.6, _mat(wood)), Vector3(0, 0.05, 0)))
	head.position = Vector3(0, 0.9, 0)
	n.add_child(head)
	return n


static func _orb(c: Color) -> Node3D:
	var n := Node3D.new()
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	s.material = _mat(c, 1.4)
	n.add_child(_part(s, Vector3.ZERO))
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 1.2
	light.omni_range = 4.0
	n.add_child(light)
	return n


static func _crystal(c: Color) -> Node3D:
	var n := Node3D.new()
	var p := PrismMesh.new()
	p.size = Vector3(0.1, 0.24, 0.1)
	p.material = _mat(c, 1.1)
	n.add_child(_part(p, Vector3(0, 0.06, 0)))
	n.add_child(_part(p, Vector3(0, -0.08, 0), Vector3(PI, 0, 0)))
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 1.0
	light.omni_range = 4.0
	n.add_child(light)
	return n


static func _skull() -> Node3D:
	var n := Node3D.new()
	var s := SphereMesh.new()
	s.radius = 0.075
	s.height = 0.14
	s.material = _mat(Color(0.85, 0.82, 0.74))
	n.add_child(_part(s, Vector3.ZERO))
	var jaw := BoxMesh.new()
	jaw.size = Vector3(0.09, 0.04, 0.07)
	jaw.material = s.material
	n.add_child(_part(jaw, Vector3(0, -0.07, 0.02)))
	var eye := SphereMesh.new()
	eye.radius = 0.016
	eye.height = 0.032
	eye.material = _mat(Color(0.7, 0.3, 1.0), 4.0)
	n.add_child(_part(eye, Vector3(-0.026, 0.005, 0.062)))
	n.add_child(_part(eye, Vector3(0.026, 0.005, 0.062)))
	return n


static func _club() -> Node3D:
	var n := Node3D.new()
	var wood := _mat(Color(0.36, 0.24, 0.13))
	n.add_child(_part(_cyl(0.11, 0.045, 1.1, wood, 10), Vector3(0, 0.45, 0)))
	var stud := SphereMesh.new()
	stud.radius = 0.025
	stud.height = 0.05
	stud.material = _mat(Color(0.5, 0.48, 0.45), 0.0, 0.6)
	for k in 6:
		var a := TAU * k / 6.0
		n.add_child(_part(stud, Vector3(cos(a) * 0.1, 0.8 + (k % 2) * 0.12, sin(a) * 0.1)))
	return n


static func _crossbow() -> Node3D:
	var n := Node3D.new()
	var wood := _mat(Color(0.28, 0.18, 0.1))
	var stock := BoxMesh.new()
	stock.size = Vector3(0.05, 0.6, 0.06)
	stock.material = wood
	n.add_child(_part(stock, Vector3(0, 0.2, 0)))
	var limb := _cyl(0.012, 0.012, 0.6, _mat(Color(0.35, 0.33, 0.32), 0.0, 0.7))
	n.add_child(_part(limb, Vector3(0, 0.44, 0), Vector3(0, 0, PI * 0.5)))
	var bolt := _cyl(0.006, 0.006, 0.4, _mat(Color(0.82, 0.84, 0.88), 0.0, 0.8))
	n.add_child(_part(bolt, Vector3(0, 0.4, 0.035)))
	return n


static func _spear() -> Node3D:
	var n := Node3D.new()
	n.add_child(_part(_cyl(0.016, 0.02, 1.9, _mat(Color(0.4, 0.27, 0.15))), Vector3(0, 0.25, 0)))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.07, 0.24, 0.02)
	tip.material = _mat(Color(0.82, 0.84, 0.88), 0.0, 0.85)
	n.add_child(_part(tip, Vector3(0, 1.32, 0)))
	return n


static func _blade(length: float, width: float, steel: Color, curved := false) -> Node3D:
	var n := Node3D.new()
	var grip := _cyl(0.018, 0.018, 0.12 if length < 0.5 else 0.26, _mat(Color(0.12, 0.08, 0.06)))
	n.add_child(_part(grip, Vector3(0, -0.02, 0)))
	var guard := BoxMesh.new()
	guard.size = Vector3(0.08 if length < 0.5 else 0.06, 0.015, 0.05)
	guard.material = _mat(Color(0.55, 0.45, 0.2), 0.0, 0.8)
	n.add_child(_part(guard, Vector3(0, 0.05 if length < 0.5 else 0.11, 0)))
	var blade := BoxMesh.new()
	blade.size = Vector3(width, length, 0.008)
	blade.material = _mat(steel, 0.0, 0.9)
	var base_y := 0.06 if length < 0.5 else 0.12
	n.add_child(_part(blade, Vector3(0.0, base_y + length * 0.5, 0.0), Vector3(0, 0, 0.06 if curved else 0.0)))
	return n


static func _flask() -> Node3D:
	var n := Node3D.new()
	var glass := _mat(Color(0.75, 0.9, 0.9, 0.55))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var body := SphereMesh.new()
	body.radius = 0.07
	body.height = 0.14
	body.material = glass
	n.add_child(_part(body, Vector3(0, 0.1, 0)))
	var potion := SphereMesh.new()
	potion.radius = 0.058
	potion.height = 0.09
	potion.material = _mat(Color(0.35, 1.0, 0.3), 2.0)
	n.add_child(_part(potion, Vector3(0, 0.085, 0)))
	n.add_child(_part(_cyl(0.022, 0.025, 0.08, glass), Vector3(0, 0.2, 0)))
	return n
