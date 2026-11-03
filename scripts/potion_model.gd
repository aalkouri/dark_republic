class_name PotionModel
extends RefCounted
## The three potion bottles, built from primitives (no imported art), ~0.8 m tall, centred on
## the origin so they bob and spin round their middle:
##   YELLOW  Liquid Soul-Amber: a squat glass jar of glowing amber in a dark iron frame (bands top
##           and bottom, four straps, a heavy lid) with glowing runes down the straps.
##   RED     Vampiric Dew: a tall teardrop vial of deep red in an ornate silver cage (ribs, a
##           spiked foot, shoulder spikes, a collar and a horn-tipped stopper).
##   BLUE    Bioluminescent Nectar: a round flask of glowing cyan wrapped in a lattice of luminous
##           veins, with a glowing ball stopper and drifting sparkles.

const AMBER := Color(1.0, 0.5, 0.04)
const BLOOD := Color(0.5, 0.0, 0.04)
const NECTAR := Color(0.04, 0.5, 1.0)

static var _mats := {}


static func build(kind: int) -> Node3D:
	var root := Node3D.new()
	match kind:
		PotionManager.YELLOW: _amber(root)
		PotionManager.RED: _vampiric(root)
		_: _nectar(root)
	return root


# ------------------------------------------------------------------ the bottles

static func _amber(root: Node3D) -> void:
	_part(root, _cyl(0.19, 0.19, 0.4), _liquid(AMBER, 1.3), Vector3(0, -0.02, 0))
	_part(root, _cyl(0.215, 0.215, 0.46), _glass(), Vector3(0, -0.02, 0))
	for y in [-0.24, 0.2]:   # iron bands
		_part(root, _cyl(0.235, 0.235, 0.06), _iron(), Vector3(0, y, 0))
	_part(root, _cyl(0.2, 0.22, 0.08), _iron(), Vector3(0, 0.27, 0))     # lid
	_part(root, _cyl(0.13, 0.17, 0.04), _iron(), Vector3(0, 0.33, 0))
	_part(root, _cyl(0.24, 0.2, 0.05), _iron(), Vector3(0, -0.29, 0))    # foot
	for k in 4:   # straps with runes glowing on them
		var a := TAU * k / 4.0 + PI / 4.0
		var dir := Vector3(cos(a), 0, sin(a))
		var strap := _part(root, _box(Vector3(0.05, 0.44, 0.025)), _iron(), dir * 0.222 + Vector3(0, -0.02, 0))
		strap.rotation.y = -a + PI / 2.0
		for r in 3:
			var rune := _part(root, _box(Vector3(0.022, 0.035, 0.012)), _liquid(Color(1.0, 0.55, 0.1), 3.0), dir * 0.236 + Vector3(0, -0.12 + r * 0.1, 0))
			rune.rotation.y = -a + PI / 2.0


static func _vampiric(root: Node3D) -> void:
	_part(root, _sph(0.15, 0.6), _liquid(BLOOD, 1.0), Vector3(0, -0.04, 0))
	_part(root, _sph(0.175, 0.66), _glass(), Vector3(0, -0.04, 0))
	for k in 6:   # silver ribs, leaning in at the top and bottom like a cage
		var a := TAU * k / 6.0
		var dir := Vector3(cos(a), 0, sin(a))
		for seg in 3:
			var y := -0.24 + seg * 0.2
			var r := 0.175 * (0.62 if seg != 1 else 1.0)
			var rib := _part(root, _cyl(0.014, 0.014, 0.22), _silver(), dir * r + Vector3(0, y + 0.04, 0))
			var tilt := (-0.38 if seg == 0 else (0.38 if seg == 2 else 0.0))   # + tips the top in
			rib.basis = Basis(dir.cross(Vector3.UP).normalized(), tilt) if tilt != 0.0 else Basis()
	_part(root, _cyl(0.05, 0.0, 0.16), _silver(), Vector3(0, -0.43, 0))    # spiked foot
	_part(root, _torus(0.045, 0.085), _silver(), Vector3(0, 0.27, 0))     # collar
	_part(root, _cyl(0.045, 0.045, 0.12), _liquid(BLOOD, 1.2), Vector3(0, 0.33, 0))   # the neck
	_part(root, _cyl(0.06, 0.07, 0.07), _silver(), Vector3(0, 0.41, 0))   # cap
	var horn := _part(root, _cyl(0.0, 0.035, 0.14), _liquid(Color(0.6, 0.03, 0.06), 0.8), Vector3(0.01, 0.51, 0))
	horn.rotation.z = -0.35
	for sd in [-1.0, 1.0]:   # shoulder spikes
		var sp := _part(root, _cyl(0.0, 0.03, 0.12), _silver(), Vector3(sd * 0.15, 0.17, 0))
		sp.rotation.z = -sd * 0.9


static func _nectar(root: Node3D) -> void:
	_part(root, _sph(0.2, 0.4), _liquid(NECTAR, 1.5), Vector3(0, -0.07, 0))
	_part(root, _sph(0.225, 0.45), _glass(), Vector3(0, -0.07, 0))
	var vein := _liquid(Color(0.25, 0.85, 1.0), 1.6)
	for k in 3:   # glowing veins wrapped round it
		var ring := _part(root, _torus(0.218, 0.232), vein, Vector3(0, -0.07, 0))
		ring.basis = Basis(Vector3.UP, TAU * k / 6.0) * Basis(Vector3.RIGHT, PI / 2.0)
	for y in [-0.15, 0.0]:
		var band := _part(root, _torus(0.205 - absf(y + 0.07) * 0.3, 0.218 - absf(y + 0.07) * 0.3), vein, Vector3(0, y, 0))
		band.rotation.x = 0.0
	_part(root, _cyl(0.17, 0.12, 0.04), _glass(), Vector3(0, -0.29, 0))   # flat foot
	_part(root, _cyl(0.05, 0.065, 0.13), _glass(), Vector3(0, 0.2, 0))    # neck
	_part(root, _cyl(0.04, 0.04, 0.1), _liquid(NECTAR, 2.0), Vector3(0, 0.19, 0))
	_part(root, _sph(0.075, 0.15), _liquid(Color(0.2, 0.7, 1.0), 1.8), Vector3(0, 0.33, 0))   # ball stopper
	_part(root, _torus(0.07, 0.085), vein, Vector3(0, 0.33, 0))
	var sparks := CPUParticles3D.new()
	sparks.amount = 14
	sparks.lifetime = 1.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.32
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 0.02
	sparks.initial_velocity_max = 0.12
	sparks.gravity = Vector3(0, 0.05, 0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	var sm := _liquid(Color(0.6, 1.0, 1.0), 4.0)
	sm = sm.duplicate()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = sm
	sparks.mesh = q
	root.add_child(sparks)


# ------------------------------------------------------------------ parts and materials

static func _part(root: Node3D, mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 16
	m.rings = 1
	return m


static func _sph(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 16
	m.rings = 8
	return m


static func _torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 20
	m.ring_segments = 6
	return m


static func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func _liquid(c: Color, glow: float) -> StandardMaterial3D:
	var key := "l" + c.to_html() + str(glow)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
		m.roughness = 0.2
		_mats[key] = m
	return _mats[key]


static func _glass() -> StandardMaterial3D:
	if not _mats.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.93, 1.0, 0.22)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic_specular = 1.0
		m.rim_enabled = true
		m.rim = 0.6
		_mats["glass"] = m
	return _mats["glass"]


static func _silver() -> StandardMaterial3D:
	if not _mats.has("silver"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.78, 0.78, 0.82)
		m.metallic = 0.95
		m.roughness = 0.28
		_mats["silver"] = m
	return _mats["silver"]


static func _iron() -> StandardMaterial3D:
	if not _mats.has("iron"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.19, 0.18)
		m.metallic = 0.85
		m.roughness = 0.45
		_mats["iron"] = m
	return _mats["iron"]
