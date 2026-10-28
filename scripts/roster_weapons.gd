class_name RosterWeapons
extends RefCounted
## Hand-held weapons for roster characters, built from primitives and attached to the hand
## bones (like the Fire Wizard's staff), so they follow every animation without being baked
## into the body mesh. Each weapon is modelled along its local +Y (grip at the origin) and
## pointed in the rest pose: staffs and spears straight up, blades forward.

const SKIN_UP := Vector3.UP
const FORWARD := Vector3(0, 0, 1)   # GLB characters face +Z in skeleton space


static func attach(id: String, skeleton: Skeleton3D) -> void:
	match id:
		"ice_wizard":
			_hold(skeleton, "RightHand", _staff(Color(0.55, 0.6, 0.68), _crystal(Color(0.6, 0.9, 1.0))), SKIN_UP)
		"merlin":
			_hold(skeleton, "RightHand", _staff(Color(0.3, 0.2, 0.12), _orb(Color(0.45, 0.65, 1.0))), SKIN_UP)
		"thunder_wizard":
			_hold(skeleton, "RightHand", _staff(Color(0.4, 0.38, 0.42), _orb(Color(1.0, 0.92, 0.35))), SKIN_UP)
		"dark_wizard":
			_hold(skeleton, "RightHand", _staff(Color(0.08, 0.06, 0.1), _skull()), SKIN_UP)
		"ogre":
			_hold(skeleton, "RightHand", _club(), (FORWARD + Vector3.DOWN * 0.6).normalized())
		"vampire_hunter":
			_hold(skeleton, "RightHand", _crossbow(), (Vector3.DOWN + FORWARD * 0.35).normalized())
		"vicki":
			_hold(skeleton, "RightHand", _spear(), SKIN_UP)
		"rogue":
			_hold(skeleton, "RightHand", _blade(0.32, 0.035, Color(0.8, 0.82, 0.86)), FORWARD)
			_hold(skeleton, "LeftHand", _blade(0.32, 0.035, Color(0.8, 0.82, 0.86)), FORWARD)
		"gaiden":
			_hold(skeleton, "RightHand", _blade(0.85, 0.03, Color(0.86, 0.88, 0.92), true), (Vector3.DOWN + FORWARD * 0.5).normalized())
		"dr_croc":
			_hold(skeleton, "RightHand", _flask(), SKIN_UP)


## Attach `weapon` to `bone`, gripped in the palm, its +Y pointing along `dir` (skeleton space)
## in the rest pose. Skeleton space is in centimetres (the Armature is scaled 0.01).
static func _hold(sk: Skeleton3D, bone: String, weapon: Node3D, dir: Vector3) -> void:
	var b := sk.find_bone(bone)
	if b < 0:
		return
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
