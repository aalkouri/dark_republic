class_name CalderaEdge
extends RefCounted
## The rim of the Ashen Caldera: towering crater cliffs all round beyond the invisible walls
## (banded basalt and red scoria, ash on every ledge, lava seeping down the faces in places),
## and far off on the horizon a great active volcano: a hazy cone with a glowing crater, lava
## streaking its flanks and a column of ash and smoke boiling up from it (it keeps its distance
## like the sky). The smaller cinder cone inside the arena (CalderaBuilder bakes it into the
## ground) smokes, glows and erupts (Volcano).

const BAND := 120.0
const STEP_ALONG := 4.0
const STEP_OUT := 2.5


static func build(parent: Node3D, half: float, night: bool, rng: RandomNumberGenerator) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = rng.randi()
	DesertEdge._collision(parent, half)
	for s in 4:
		_cliffs(parent, half, s, r, night)
	var h := Horizon.new()
	h.name = "GreatVolcano"   # no-i18n
	h.bearing = r.randf() * TAU
	parent.add_child(h)
	h.build(WorldBuilder.edge_haze, night)
	var v := Volcano.new()
	v.name = "CinderCone"   # no-i18n
	parent.add_child(v)
	v.build(night)


## A band of crater cliffs along side `s`: from below the ground at the wall up a steep jagged
## face 28-60 m high, then rolling back down beyond.
static func _cliffs(parent: Node3D, half: float, s: int, r: RandomNumberGenerator, night: bool) -> void:
	var f := DesertEdge._frame(half, s)
	var o: Vector3 = f[0]
	var along: Vector3 = f[1]
	var out: Vector3 = f[2]
	var n := FastNoiseLite.new()
	n.seed = r.randi()
	n.frequency = 0.02
	var rn := FastNoiseLite.new()
	rn.seed = r.randi()
	rn.frequency = 0.06
	rn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var len := half * 2.0 + BAND * 2.0
	var na := int(len / STEP_ALONG) + 1
	var no := int((BAND + 6.0) / STEP_OUT) + 1
	var pts := []
	var tags := []
	for i in na:
		var a := -len * 0.5 + i * STEP_ALONG
		var row := []
		var trow := []
		var edge_p := o + along * clampf(a, -half + 1.0, half - 1.0) - out * 1.0
		var g0 := SwampWater.height_at(edge_p.x, edge_p.z)
		var crest := 28.0 + 32.0 * (n.get_noise_1d(a * 0.5) * 0.5 + 0.5)
		var face := 14.0 + 8.0 * (n.get_noise_1d(a * 0.3 + 40.0) * 0.5 + 0.5)
		var seep := n.get_noise_1d(a * 0.9 + 90.0) > 0.55
		for j in no:
			var d := -6.0 + j * STEP_OUT
			var up := smoothstep(-1.0, face, d)
			var back := 1.0 - smoothstep(face + 25.0, BAND, d) * 0.5
			var jag := rn.get_noise_2d(a * 1.2, d * 1.4) * 5.0 * up + n.get_noise_2d(a * 3.0, d * 3.0) * 1.5
			var h := g0 - 1.5 + (crest * pow(up, 0.85) + jag) * back
			var p := o + along * a + out * d
			p.y = h
			row.append(p)
			trow.append(0.2 if seep and d > 1.0 and d < face * 0.9 else 0.0)
		pts.append(row)
		tags.append(trow)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in na - 1:
		for j in no - 1:
			for q in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				var p: Vector3 = pts[q[0]][q[1]]
				var band := sin(p.y * 0.55 + n.get_noise_2d(p.x * 0.05, p.z * 0.05) * 3.0)
				var c := CalderaProps.BASALT.lerp(CalderaProps.SCORIA, smoothstep(0.3, 0.9, band))
				if night:
					c = c.darkened(0.2)
				var tg: float = tags[q[0]][q[1]]
				st.set_color(Color(c.r, c.g, c.b, tg))
				st.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	var arr := mesh.surface_get_arrays(0)
	var nm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for k in nm.size():
		if nm[k].y < 0.0:
			nm[k] = -nm[k]
	arr[Mesh.ARRAY_NORMAL] = nm
	var m2 := ArrayMesh.new()
	m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = m2
	mi.material_override = CalderaProps.rock_material()
	mi.name = "CraterCliffs"   # no-i18n
	mi.add_to_group("edge_cliffs")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## The great volcano on the skyline: a hazy cone, its crater glowing, lava streaks down its
## flanks and an ash column boiling up. Follows the camera (like the sky).
class Horizon extends Node3D:
	const DISTANCE := 385.0
	var bearing := 0.0
	var _glow: StandardMaterial3D

	func build(haze: Color, night: bool) -> void:
		var sh := Shader.new()
		sh.code = DistantCastle.SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("haze", haze)
		mat.set_shader_parameter("body", haze.darkened(0.6 if night else 0.45).lerp(Color(0.12, 0.08, 0.07), 0.4))
		mat.set_shader_parameter("rim", 0.0)
		mat.set_shader_parameter("mist_top", 40.0)
		var c := CylinderMesh.new()
		c.top_radius = 16.0
		c.bottom_radius = 150.0
		c.height = 125.0
		c.radial_segments = 40
		c.rings = 6
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = mat
		mi.position = Vector3(0, 62.5 - 20.0, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# shoulders: a lumpy second cone
		var c2 := CylinderMesh.new()
		c2.top_radius = 26.0
		c2.bottom_radius = 100.0
		c2.height = 60.0
		c2.radial_segments = 24
		var m2 := MeshInstance3D.new()
		m2.mesh = c2
		m2.material_override = mat
		m2.position = Vector3(-85, 10.0, 25)
		m2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m2)
		# the crater's glow and lava streaks down the face toward us
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.disable_fog = true
		_glow.albedo_color = Color(1.0, 0.45, 0.12)
		var rim := TorusMesh.new()
		rim.inner_radius = 12.0
		rim.outer_radius = 17.0
		var rm := MeshInstance3D.new()
		rm.mesh = rim
		rm.material_override = _glow
		rm.position = Vector3(0, 105.5, 0)
		rm.scale = Vector3(1, 0.25, 1)
		add_child(rm)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var slope := (150.0 - 16.0) / 125.0   # metres out per metre down the cone
		for k in 3:
			var a := PI * 0.5 + (k - 1) * 0.45 + rng.randf_range(-0.1, 0.1)
			var prev_l := Vector3.ZERO
			var prev_r := Vector3.ZERO
			var len := rng.randf_range(0.45, 0.75)
			for s in 16:
				var t := s / 15.0 * len
				var down := t * 125.0
				var rr := 16.0 + down * slope + 0.6
				var y := 105.0 - down
				var aa := a + sin(t * 9.0 + k) * 0.05
				var w := lerpf(0.035, 0.012, t / len)   # radians: the stream narrows as it runs out
				var pl := Vector3(cos(aa - w) * rr, y, sin(aa - w) * rr)
				var pr := Vector3(cos(aa + w) * rr, y, sin(aa + w) * rr)
				if s > 0:
					for v in [prev_l, prev_r, pr, prev_l, pr, pl]:
						st.add_vertex(v)
				prev_l = pl
				prev_r = pr
		var sm := MeshInstance3D.new()
		sm.mesh = st.commit()
		var streak := _glow.duplicate() as StandardMaterial3D
		streak.cull_mode = BaseMaterial3D.CULL_DISABLED
		streak.albedo_color = Color(0.95, 0.3, 0.06)
		sm.material_override = streak
		add_child(sm)
		# the ash column: great dark billows rising and spreading, lit orange from below
		var p := CPUParticles3D.new()
		p.amount = 70
		p.lifetime = 26.0
		p.preprocess = 26.0
		p.local_coords = true
		p.position = Vector3(0, 112.0, 0)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 14.0
		p.direction = Vector3(0.15, 1, 0)
		p.spread = 14.0
		p.initial_velocity_min = 6.0
		p.initial_velocity_max = 10.0
		p.gravity = Vector3(1.2, -0.05, 0)
		p.damping_min = 0.1
		p.damping_max = 0.2
		p.scale_amount_min = 1.0
		p.scale_amount_max = 1.6
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.6))
		curve.add_point(Vector2(1, 2.4))
		p.scale_amount_curve = curve
		var q := QuadMesh.new()
		q.size = Vector2(46, 46)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = Abilities._soft_dot()
		m.disable_fog = true
		q.material = m
		p.mesh = q
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.9, 0.4, 0.15, 0.0))
		ramp.add_point(0.08, Color(0.55, 0.25, 0.12, 0.75))
		ramp.add_point(0.4, Color(0.2, 0.14, 0.12, 0.7))
		ramp.set_color(ramp.get_point_count() - 1, Color(0.16, 0.12, 0.11, 0.0))
		p.color_ramp = ramp
		add_child(p)

	func _process(_dt: float) -> void:
		var cam := get_viewport().get_camera_3d()
		var from := cam.global_position if cam != null else Vector3.ZERO
		var dir := Vector3(cos(bearing), 0.0, sin(bearing))
		global_position = Vector3(from.x, -10.0, from.z) + dir * DISTANCE
		rotation.y = atan2(-dir.x, -dir.z)
		if _glow != null:
			var t := Time.get_ticks_msec() * 0.001
			_glow.albedo_color = Color(1.0, 0.42 + 0.08 * sin(t * 1.3), 0.12)


## The cinder cone inside the arena (its slopes are part of the ground): a glowing lava lake in
## its crater, lava streams down one flank, a smoke column, and eruptions (erupt()): a flare of
## light, a burst of lava blobs and a thick puff of ash.
class Volcano extends Node3D:
	var crater := Vector3.ZERO
	var _light: OmniLight3D
	var _burst: CPUParticles3D
	var _puff: CPUParticles3D
	var _flare := 0.0

	func build(night: bool) -> void:
		var c: Dictionary = CalderaBuilder.cone
		if c.is_empty():
			return
		crater = c["top"]
		var mb := MeshBuilder.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var rr: float = c["crater"]
		# the crater rim: a ring of jagged rocks, the lava lake inside
		for k in 20:
			var a := TAU * k / 20.0
			var col := CalderaProps._shade(CalderaProps.SCORIA if k % 2 else CalderaProps.BASALT, rng, 0.2)
			col.a = CalderaProps.HOT if k % 3 == 0 else CalderaProps.ROCK
			mb.add(ForestProps._lumpy(rng.randf_range(1.8, 3.0), rng), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, 0.7, 1.0)), crater + Vector3(cos(a) * rr, -0.6, sin(a) * rr)), col)
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit(CalderaProps.rock_material())
		add_child(mi)
		var lake := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = rr * 0.92
		disc.bottom_radius = rr * 0.92
		disc.height = 0.2
		disc.radial_segments = 32
		lake.mesh = disc
		lake.material_override = CalderaBuilder.lava_material("pool")
		lake.position = crater + Vector3(0, -1.6, 0)
		add_child(lake)
		# lava streams down the flank toward the arena
		var fall_mat := CalderaBuilder.lava_material("river")
		var base: Vector3 = c["at"]
		var to_mid := Vector2(-base.x, -base.z).normalized()
		for s in 2:
			var a := atan2(to_mid.y, to_mid.x) + (s - 0.5) * 0.7 + rng.randf_range(-0.15, 0.15)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var prev_a := Vector3.ZERO
			var prev_b := Vector3.ZERO
			var dist := 0.0
			var prev_c := Vector3.ZERO
			var n := 26
			var radius: float = c["r"]
			for k in n + 1:
				var t := float(k) / n
				var aa := a + sin(t * 7.0 + s) * 0.06
				var d := lerpf(rr, radius * 0.92, t)
				var px := base.x + cos(aa) * d
				var pz := base.z + sin(aa) * d
				var p := Vector3(px, SwampWater.height_at(px, pz) + 0.25, pz)
				var side := Vector3(-sin(aa), 0, cos(aa)) * lerpf(0.5, 1.3, t) * (0.8 + 0.4 * sin(t * 11.0 + s))
				if k > 0:
					var d0 := dist
					dist += p.distance_to(prev_c)
					for tri in [[prev_a, Vector2(0, d0)], [prev_b, Vector2(2, d0)], [p + side, Vector2(2, dist)], [prev_a, Vector2(0, d0)], [p + side, Vector2(2, dist)], [p - side, Vector2(0, dist)]]:
						st.set_normal(Vector3.UP)
						st.set_uv(tri[1])
						st.add_vertex(tri[0])
				prev_a = p - side
				prev_b = p + side
				prev_c = p
			var sm := MeshInstance3D.new()
			sm.mesh = st.commit()
			sm.material_override = fall_mat
			sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(sm)
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.45, 0.15)
		_light.light_energy = 3.0
		_light.omni_range = 40.0
		_light.shadow_enabled = false
		_light.position = crater + Vector3(0, 6.0, 0)
		add_child(_light)
		add_child(CalderaProps.steam(crater + Vector3(0, 1.0, 0), rr * 0.6, 40, night, Color(0.22, 0.18, 0.16, 0.55)))
		add_child(CalderaProps.embers(crater + Vector3(0, 0.5, 0), rr * 0.6, 50))
		# the eruption: lava blobs flung high, a thick puff of ash
		_burst = CPUParticles3D.new()
		_burst.emitting = false
		_burst.one_shot = true
		_burst.explosiveness = 0.85
		_burst.amount = 90
		_burst.lifetime = 3.2
		_burst.local_coords = false
		_burst.position = crater
		_burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_burst.emission_sphere_radius = rr * 0.5
		_burst.direction = Vector3.UP
		_burst.spread = 32.0
		_burst.initial_velocity_min = 16.0
		_burst.initial_velocity_max = 30.0
		_burst.gravity = Vector3(0, -18.0, 0)
		_burst.scale_amount_min = 0.8
		_burst.scale_amount_max = 2.0
		var bq := SphereMesh.new()
		bq.radius = 0.6
		bq.height = 1.2
		bq.radial_segments = 8
		bq.rings = 4
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color(1.0, 0.5, 0.12)
		bm.disable_fog = true
		bq.material = bm
		_burst.mesh = bq
		add_child(_burst)
		_puff = CalderaProps.steam(crater + Vector3(0, 3.0, 0), rr, 40, night, Color(0.16, 0.13, 0.12, 0.8))
		(_puff.mesh as QuadMesh).size = Vector2(7.0, 7.0)
		_puff.emitting = false
		_puff.one_shot = true
		_puff.explosiveness = 0.6
		_puff.preprocess = 0.0
		_puff.initial_velocity_min = 8.0
		_puff.initial_velocity_max = 16.0
		_puff.lifetime = 6.0
		add_child(_puff)

	func erupt(strength := 1.0) -> void:
		_flare = maxf(_flare, strength)
		if _burst != null:
			_burst.restart()
			_burst.emitting = true
			_puff.restart()
			_puff.emitting = true

	func _process(dt: float) -> void:
		if _light == null:
			return
		_flare = maxf(0.0, _flare - dt * 0.35)
		var t := Time.get_ticks_msec() * 0.001
		_light.light_energy = 3.0 + 0.6 * sin(t * 2.3) + _flare * 14.0
		_light.omni_range = 40.0 + _flare * 60.0
