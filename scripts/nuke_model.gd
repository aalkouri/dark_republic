class_name NukeModel
extends RefCounted
## The NUKE power-up's pickup: a classic cartoon atomic bomb, built in code. A fat rounded olive
## casing with a seam, a red band round the nose, a tapered tail ending in a boxy fin cage, and
## a yellow-and-black radiation trefoil on each side (a small texture drawn in code). It glows
## gently; PowerupManager makes it bob and spin like the others.

const CASING := Color(0.36, 0.39, 0.21)
const TAIL := Color(0.24, 0.25, 0.22)
const BAND := Color(0.9, 0.1, 0.07)
const TREFOIL_YELLOW := Color(1.0, 0.84, 0.1)
const LENGTH := 0.8            # nose to tail, metres

static var _trefoil: ImageTexture


## The bomb, its nose along +Z, tipped nose-down a little.
static func build() -> Node3D:
	var root := Node3D.new()
	var bomb := Node3D.new()
	bomb.rotation.x = deg_to_rad(16.0)   # nose dips
	bomb.position.z = 0.04
	root.add_child(bomb)
	var casing := _mat(CASING, 0.35, 0.45, 0.25)   # glows a little so it reads olive even at night
	var tail := _mat(TAIL, 0.05, 0.6, 0.5)
	# the fat egg-shaped body
	var body := SphereMesh.new()
	body.radius = 0.21
	body.height = 0.42
	body.radial_segments = 28
	body.rings = 16
	body.material = casing
	var b := MeshInstance3D.new()
	b.mesh = body
	b.scale = Vector3(1.0, 1.0, 1.3)
	bomb.add_child(b)
	# the casing seam and the red nose band
	bomb.add_child(_band(-0.118, -0.102, _mat(TAIL, 0.0, 0.6, 0.4)))   # the casing seam, behind the trefoils
	bomb.add_child(_band(0.125, 0.2, _mat(BAND, 0.9, 0.35, 0.2)))
	# a tapered neck into the tail
	var neck := CylinderMesh.new()
	neck.top_radius = 0.14
	neck.bottom_radius = 0.05
	neck.height = 0.16
	neck.radial_segments = 16
	neck.material = tail
	var n := MeshInstance3D.new()
	n.mesh = neck
	n.rotation.x = deg_to_rad(90.0)   # cylinder axis Y -> Z, wide end toward the body
	n.position.z = -0.29
	bomb.add_child(n)
	# the boxy fin cage: four outer plates and a cross of fins inside
	var zc := -0.39
	var w := 0.34
	var depth := 0.15
	var th := 0.014
	for side in 4:
		var p := BoxMesh.new()
		p.size = Vector3(w, th, depth) if side < 2 else Vector3(th, w, depth)
		p.material = tail
		var pm := MeshInstance3D.new()
		pm.mesh = p
		var off := (w - th) * 0.5 * (1.0 if side % 2 == 0 else -1.0)
		pm.position = Vector3(0.0, off, zc) if side < 2 else Vector3(off, 0.0, zc)
		bomb.add_child(pm)
	for k in 2:
		var f := BoxMesh.new()
		f.size = Vector3(w, th, depth) if k == 0 else Vector3(th, w, depth)
		f.material = tail
		var fm := MeshInstance3D.new()
		fm.mesh = f
		fm.position.z = zc
		fm.rotation.z = deg_to_rad(45.0)
		bomb.add_child(fm)
	# the radiation trefoil on each side
	var deco := StandardMaterial3D.new()
	deco.albedo_texture = trefoil_texture()
	deco.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	deco.alpha_scissor_threshold = 0.5
	deco.emission_enabled = true
	deco.emission_texture = trefoil_texture()
	deco.emission = Color(0.6, 0.5, 0.1)
	deco.emission_energy_multiplier = 0.9
	deco.cull_mode = BaseMaterial3D.CULL_BACK
	deco.roughness = 1.0
	deco.metallic_specular = 0.0
	for side in 3:   # both flanks and the top
		var q := QuadMesh.new()
		q.size = Vector2(0.2, 0.2)
		q.material = deco
		var qm := MeshInstance3D.new()
		qm.mesh = q
		if side < 2:
			var sx := -1.0 if side == 0 else 1.0
			qm.position = Vector3(0.214 * sx, 0.0, 0.0)
			qm.rotation.y = deg_to_rad(90.0 * sx)   # face outward (+X / -X)
		else:
			qm.position = Vector3(0.0, 0.214, 0.0)
			qm.rotation.x = deg_to_rad(-90.0)       # face up
		qm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bomb.add_child(qm)
	return root


static func _mat(c: Color, glow: float, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


## A painted band hugging the egg-shaped body from z0 to z1 (a frustum just over its surface).
static func _band(z0: float, z1: float, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = _body_r(z0) + 0.007
	c.top_radius = _body_r(z1) + 0.007
	c.height = maxf(z1 - z0, 0.012)
	c.radial_segments = 28
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	c.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.rotation.x = deg_to_rad(90.0)   # local +Y (top) -> +Z (the nose)
	mi.position.z = (z0 + z1) * 0.5
	return mi


## The body's radius at `z` along its axis (an ellipsoid 0.21 wide, 0.273 long each way).
static func _body_r(z: float) -> float:
	return 0.21 * sqrt(maxf(0.0, 1.0 - pow(z / 0.273, 2.0)))


## A thin ring round the body (axis Z) at `z`.
static func _ring(inner: float, outer: float, z: float, mat: Material) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 28
	t.ring_segments = 8
	t.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.rotation.x = deg_to_rad(90.0)
	mi.position.z = z
	mi.scale = Vector3(1.0, 1.0, 0.6)   # flattened into a band
	return mi


## The yellow disc with the black three-bladed radiation trefoil (128 px, made once).
static func trefoil_texture() -> ImageTexture:
	if _trefoil != null:
		return _trefoil
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var black := Color(0.05, 0.04, 0.02)
	for y in n:
		for x in n:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(n) * 2.0 - Vector2.ONE   # -1..1
			img.set_pixel(x, y, trefoil_color(p, TREFOIL_YELLOW, black))
	_trefoil = ImageTexture.create_from_image(img)
	return _trefoil


## Colour of the trefoil sign at `p` (-1..1 across the disc; transparent outside it).
static func trefoil_color(p: Vector2, yellow: Color, black: Color) -> Color:
	var r := p.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	if r > 0.9:
		return black   # the rim
	if r < 0.17:
		return black   # the hub
	if r > 0.27 and r < 0.8:
		var a := fposmod(rad_to_deg(atan2(-p.y, p.x)) - 90.0, 120.0)   # one blade points up
		if a < 30.0 or a > 90.0:   # within 30 degrees of a blade's centre line
			return black
	return yellow
