class_name Abilities
extends Node3D
## The fire wizard's three active abilities (keys 1 / 2 / 3).
##   1  Meteor        30 s  Lands where you aim, 3 s after casting. Big AoE damage.
##   2  Fire Shockwave 45 s  Expanding ring from the floor under you; knocks enemies back 5 yd.
##   3  Inferno (ult) 120 s  Ignites every enemy: 5% max HP/s for 10 s. Burning enemies that
##                           die explode for 50% of their max HP within 2 yd (chains).
## Cooldowns tick in the physics step, so they pause with the game.

signal cast(index: int)

const YARD := 0.9144

const METEOR_COOLDOWN := 30.0
const METEOR_FALL_TIME := 3.0
const METEOR_RADIUS := 8.0
const METEOR_DAMAGE := 250.0
const METEOR_RANGE := 45.0
const METEOR_KNOCKBACK := 3.0

const SHOCK_COOLDOWN := 45.0
const SHOCK_RADIUS := 9.0
const SHOCK_EXPAND_TIME := 0.45
const SHOCK_DAMAGE := 80.0
const SHOCK_KNOCKBACK := 5.0 * YARD

const ULT_COOLDOWN := 120.0
const ULT_BURN_TIME := 10.0
const ULT_BURN_DPS := 0.05          # of max HP per second
const ULT_EXPLODE_FRAC := 0.5       # of the dying enemy's max HP
const ULT_EXPLODE_RADIUS := 2.0 * YARD

const DEFS := [
	{"name": "Meteor", "key": "1", "cooldown": METEOR_COOLDOWN, "ult": false},
	{"name": "Fire Shockwave", "key": "2", "cooldown": SHOCK_COOLDOWN, "ult": false},
	{"name": "Inferno", "key": "3", "cooldown": ULT_COOLDOWN, "ult": true},
]

var stats: Stats
var enemies: EnemyManager
var player: Player
var fx: FxManager

var cooldown := PackedFloat32Array([0.0, 0.0, 0.0])

var _meteors: Array = []   # {target, t, rock, marker, fill, start}
var _shocks: Array = []    # {center, t, hit: Dictionary, ring, disc}
var _fire_mat: StandardMaterial3D
var _rock_mesh: SphereMesh


func setup(p_stats: Stats, p_enemies: EnemyManager, p_player: Player, p_fx: FxManager) -> void:
	stats = p_stats
	enemies = p_enemies
	player = p_player
	fx = p_fx
	enemies.burn_dps_frac = ULT_BURN_DPS
	enemies.burn_explode_frac = ULT_EXPLODE_FRAC
	enemies.burn_explode_radius = ULT_EXPLODE_RADIUS


func _ready() -> void:
	_fire_mat = StandardMaterial3D.new()
	_fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fire_mat.albedo_color = Color(1.0, 0.45, 0.1, 0.9)

	_rock_mesh = SphereMesh.new()
	_rock_mesh.radius = 2.2
	_rock_mesh.height = 4.4
	_rock_mesh.radial_segments = 10
	_rock_mesh.rings = 6
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.25, 0.08, 0.04)
	rock_mat.emission_enabled = true
	rock_mat.emission = Color(1.0, 0.35, 0.05)
	rock_mat.emission_energy_multiplier = 2.5
	_rock_mesh.material = rock_mat


func is_ready(i: int) -> bool:
	return cooldown[i] <= 0.0


func fraction_remaining(i: int) -> float:
	return clampf(cooldown[i] / float(DEFS[i]["cooldown"]), 0.0, 1.0)


func reset_cooldowns() -> void:
	cooldown = PackedFloat32Array([0.0, 0.0, 0.0])


func try_cast(i: int) -> bool:
	if i < 0 or i >= DEFS.size() or not is_ready(i):
		return false
	match i:
		0:
			_cast_meteor()
		1:
			_cast_shockwave()
		2:
			_cast_inferno()
	cooldown[i] = DEFS[i]["cooldown"]
	cast.emit(i)
	return true


func tick(dt: float) -> void:
	for i in cooldown.size():
		cooldown[i] = maxf(0.0, cooldown[i] - dt)
	_update_meteors(dt)
	_update_shocks(dt)


# ------------------------------------------------------------------ 1: Meteor

func _cast_meteor() -> void:
	var target := _aim_point()
	var marker := _ground_disc(METEOR_RADIUS, Color(1.0, 0.15, 0.05, 0.22))
	marker.global_position = target + Vector3(0, 0.05, 0)
	var fill := _ground_disc(METEOR_RADIUS, Color(1.0, 0.4, 0.05, 0.35))
	fill.global_position = target + Vector3(0, 0.07, 0)
	fill.scale = Vector3(0.01, 1, 0.01)

	var rock := MeshInstance3D.new()
	rock.mesh = _rock_mesh
	rock.top_level = true
	add_child(rock)
	var trail := _flame_particles(3.0, 1.6, 220)
	rock.add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 4.0
	light.omni_range = 18.0
	rock.add_child(light)

	# Comes in at an angle, from behind the caster.
	var back := (target - player.global_position)
	back.y = 0.0
	back = back.normalized() if back.length() > 0.5 else Vector3(0, 0, 1)
	var start := target - back * 35.0 + Vector3(0, 75.0, 0)
	rock.global_position = start
	_meteors.append({"target": target, "t": 0.0, "rock": rock, "marker": marker, "fill": fill, "start": start})


func _aim_point() -> Vector3:
	var cam := player.cam
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var p: Vector3
	if hit.is_empty():
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		p = player.global_position + flat * 20.0
		p.y = 0.0
	else:
		p = hit["position"]
	var off := p - player.global_position
	off.y = 0.0
	if off.length() > METEOR_RANGE:
		p = player.global_position + off.normalized() * METEOR_RANGE
		p.y = 0.0
	return _floor_below(p + Vector3(0, 0.5, 0))


func _update_meteors(dt: float) -> void:
	for k in range(_meteors.size() - 1, -1, -1):
		var m: Dictionary = _meteors[k]
		m["t"] += dt
		var tt: float = m["t"] / METEOR_FALL_TIME
		var target: Vector3 = m["target"]
		var marker: MeshInstance3D = m["marker"]
		var fill: MeshInstance3D = m["fill"]
		var rock: MeshInstance3D = m["rock"]
		if tt < 1.0:
			var e := tt * tt   # accelerates as it falls
			rock.global_position = (m["start"] as Vector3).lerp(target, e)
			rock.rotate_x(dt * 3.0)
			fill.scale = Vector3(tt, 1, tt)
			(marker.mesh.material as StandardMaterial3D).albedo_color.a = 0.18 + 0.12 * sin(m["t"] * 12.0)
			continue
		_meteor_impact(target)
		marker.queue_free()
		fill.queue_free()
		rock.queue_free()
		_meteors.remove_at(k)


func _meteor_impact(at: Vector3) -> void:
	var dmg := METEOR_DAMAGE * stats.value("damage")
	for i in enemies.query_radius(Vector3(at.x, 0.8, at.z), METEOR_RADIUS, false):
		var away := enemies.pos[i] - at
		if not enemies.damage(i, dmg):
			enemies.knock(i, away, METEOR_KNOCKBACK, 0.2)
	fx.burst(at + Vector3(0, 1.0, 0), METEOR_RADIUS * 1.1, Color(1.0, 0.4, 0.08), 0.6)
	fx.burst(at + Vector3(0, 2.5, 0), METEOR_RADIUS * 0.6, Color(1.0, 0.8, 0.3), 0.4)
	for n in 10:
		var a := randf() * TAU
		var r := randf_range(1.0, METEOR_RADIUS * 0.9)
		fx.burst(at + Vector3(cos(a) * r, randf_range(0.3, 2.0), sin(a) * r), randf_range(1.0, 2.2), Color(1.0, 0.35, 0.05), randf_range(0.4, 0.8))
	var d := player.global_position.distance_to(at)
	player.add_shake(clampf(1.2 - d / 40.0, 0.15, 1.0))


# ------------------------------------------------------------------ 2: Fire Shockwave

func _cast_shockwave() -> void:
	var center := _floor_below(player.global_position + Vector3(0, 0.5, 0))
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 8
	torus.material = _fire_mat.duplicate()
	ring.mesh = torus
	ring.top_level = true
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = center + Vector3(0, 0.3, 0)
	var disc := _ground_disc(1.0, Color(1.0, 0.35, 0.05, 0.35))
	disc.global_position = center + Vector3(0, 0.06, 0)
	_shocks.append({"center": center, "t": 0.0, "hit": {}, "ring": ring, "disc": disc})
	player.add_shake(0.35)


func _update_shocks(dt: float) -> void:
	var dmg := SHOCK_DAMAGE * stats.value("damage")
	for k in range(_shocks.size() - 1, -1, -1):
		var s: Dictionary = _shocks[k]
		s["t"] += dt
		var tt: float = s["t"] / SHOCK_EXPAND_TIME
		var center: Vector3 = s["center"]
		var ring: MeshInstance3D = s["ring"]
		var disc: MeshInstance3D = s["disc"]
		var r := SHOCK_RADIUS * minf(tt, 1.0)
		if tt <= 1.0:
			var hit: Dictionary = s["hit"]
			for i in enemies.query_radius(Vector3(center.x, 0.8, center.z), r, false):
				var u := enemies.uid[i]
				if hit.has(u):
					continue
				hit[u] = true
				var away := enemies.pos[i] - center
				if not enemies.damage(i, dmg):
					enemies.knock(i, away, SHOCK_KNOCKBACK, 0.3)
		# Visual: ring rides the front, then fades out
		var fade := clampf(1.0 - (tt - 1.0) / 0.5, 0.0, 1.0)
		var vr := maxf(r, 0.3)
		ring.scale = Vector3(vr, 1.0 + 1.5 * fade, vr)
		disc.scale = Vector3(vr, 1, vr)
		((ring.mesh as TorusMesh).material as StandardMaterial3D).albedo_color.a = 0.9 * fade
		(disc.mesh.material as StandardMaterial3D).albedo_color.a = 0.3 * fade
		if tt > 1.0 and fade <= 0.0:
			ring.queue_free()
			disc.queue_free()
			_shocks.remove_at(k)
		elif tt <= 1.0 and Engine.get_physics_frames() % 3 == 0:
			var a := randf() * TAU
			fx.burst(center + Vector3(cos(a) * r, 0.6, sin(a) * r), 1.1, Color(1.0, 0.4, 0.08), 0.3)


# ------------------------------------------------------------------ 3: Inferno (ultimate)

func _cast_inferno() -> void:
	var n := enemies.ignite_all(ULT_BURN_TIME)
	var at := player.global_position + Vector3(0, 1.0, 0)
	fx.burst(at, 6.0, Color(1.0, 0.75, 0.25), 0.5)
	fx.burst(at, 14.0, Color(1.0, 0.3, 0.05), 0.8)
	player.add_shake(0.6)
	print_verbose("Inferno ignited %d enemies" % n)


# ------------------------------------------------------------------ helpers

func _floor_below(from: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -200, 0))
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector3(from.x, 0.0, from.z)
	return hit["position"]


func _ground_disc(radius: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.04
	mesh.radial_segments = 40
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Shared fire particle emitter (meteor trail, wizard flames).
static func _flame_particles(size: float, lifetime: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.6
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 2.0, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.35, 1.0))
	grad.set_color(1, Color(0.6, 0.05, 0.0, 0.0))
	grad.add_point(0.35, Color(1.0, 0.35, 0.05, 0.8))
	p.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	p.mesh = quad
	return p


static var _dot_tex: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 32
		t.height = 32
		_dot_tex = t
	return _dot_tex
