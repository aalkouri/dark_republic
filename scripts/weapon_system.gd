class_name WeaponSystem
extends Node3D
## Runs all owned weapons each tick. Weapon stats live in the shared Stats object
## (orb_*, aura_*, slam_*) and are scaled by global stats (damage, attack_speed, area...).
## Projectiles are packed arrays + one MultiMesh, same pattern as enemies.

const P_MAX := 400
const P_STRIDE := 12

var stats: Stats
var db: UpgradeDB
var enemies: EnemyManager
var player: Player

var pc := 0
var p_pos := PackedVector3Array()
var p_vel := PackedVector3Array()
var p_life := PackedFloat32Array()
var p_dmg := PackedFloat32Array()
var p_pierce := PackedInt32Array()
var p_hits: Array = []     # PackedInt32Array of enemy uids already hit, per projectile

var orb_t := 0.3
var aura_t := 0.0
var slam_t := 1.5

var mm: MultiMesh
var tail_mm: MultiMesh
var tail_buf := PackedFloat32Array()
var buf := PackedFloat32Array()
var aura_mesh: MeshInstance3D
var aura_mat: StandardMaterial3D
var _aura_pulse := 0.0
var _rings: Array = []     # [MeshInstance3D, age, radius]
var _ring_mat: StandardMaterial3D


func setup(p_stats: Stats, p_db: UpgradeDB, p_enemies: EnemyManager, p_player: Player) -> void:
	stats = p_stats
	db = p_db
	enemies = p_enemies
	player = p_player


func _ready() -> void:
	p_pos.resize(P_MAX)
	p_vel.resize(P_MAX)
	p_life.resize(P_MAX)
	p_dmg.resize(P_MAX)
	p_pierce.resize(P_MAX)
	p_hits.resize(P_MAX)
	buf.resize(P_MAX * P_STRIDE)

	# Fireballs: a hot core, plus a flame tail (second MultiMesh) stretched along the flight path
	var orb := SphereMesh.new()
	orb.radius = 0.24
	orb.height = 0.48
	orb.radial_segments = 10
	orb.rings = 5
	var orb_mat := StandardMaterial3D.new()
	orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb_mat.albedo_color = Color(1.0, 0.78, 0.3)
	orb.material = orb_mat
	var tail := SphereMesh.new()
	tail.radius = 0.5
	tail.height = 1.0
	tail.radial_segments = 10
	tail.rings = 5
	var tail_mat := StandardMaterial3D.new()
	tail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tail_mat.albedo_color = Color(1.0, 0.32, 0.05, 0.75)
	tail.material = tail_mat
	tail_mm = MultiMesh.new()
	tail_mm.transform_format = MultiMesh.TRANSFORM_3D
	tail_mm.mesh = tail
	tail_mm.instance_count = P_MAX
	tail_mm.visible_instance_count = 0
	tail_buf.resize(P_MAX * P_STRIDE)
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = tail_mm
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(tmi)
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = orb
	mm.instance_count = P_MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(mmi)

	aura_mat = _fx_material(Color(0.55, 1.0, 0.35, 0.18))
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.05
	disc.radial_segments = 32
	disc.material = aura_mat
	aura_mesh = MeshInstance3D.new()
	aura_mesh.mesh = disc
	aura_mesh.top_level = true
	aura_mesh.visible = false
	aura_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(aura_mesh)

	_ring_mat = _fx_material(Color(1.0, 0.9, 0.5, 0.6))


static func _fx_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


func tick(dt: float) -> void:
	var dmg_mult := stats.value("damage")
	var haste := maxf(0.1, stats.value("attack_speed"))
	var area := stats.value("area")
	var feet := player.global_position
	var chest := feet + Vector3(0.0, 0.9, 0.0)

	# --- Bonk Orbs: auto-targeted projectiles
	if db.level_of("weapon_orb") > 0:
		orb_t -= dt
		if orb_t <= 0.0:
			orb_t = stats.value("orb_cooldown") / haste if _fire_orbs(chest, dmg_mult) else 0.1
	_update_projectiles(dt)

	# --- Stink Aura: damage ticks in a radius
	if db.level_of("weapon_aura") > 0:
		var r := stats.value("aura_radius") * area
		aura_mesh.visible = true
		aura_mesh.global_position = feet + Vector3(0.0, 0.06, 0.0)
		aura_mesh.scale = Vector3(r, 1.0, r)
		aura_t -= dt
		if aura_t <= 0.0:
			aura_t = stats.value("aura_tick") / haste
			_aura_pulse = 1.0
			var d := stats.value("aura_damage") * dmg_mult
			for e in enemies.query_radius(chest, r):
				enemies.damage(e, d)
		_aura_pulse = maxf(0.0, _aura_pulse - dt * 5.0)
		aura_mat.albedo_color.a = 0.14 + 0.16 * _aura_pulse

	# --- Ground Slam: periodic knockback nova
	if db.level_of("weapon_slam") > 0:
		slam_t -= dt
		if slam_t <= 0.0:
			slam_t = stats.value("slam_cooldown") / haste
			var r := stats.value("slam_radius") * area
			var d := stats.value("slam_damage") * dmg_mult
			for e in enemies.query_radius(chest, r):
				var away := enemies.pos[e] - feet
				away.y = 0.0
				enemies.damage(e, d, away.normalized() * 14.0)
			_spawn_ring(feet, r)
	_update_rings(dt)


func _fire_orbs(origin: Vector3, dmg_mult: float) -> bool:
	var n := maxi(1, int(stats.value("orb_count")) + int(stats.value("projectile_count")))
	var targets := enemies.nearest_k(origin, 28.0, n)
	if targets.is_empty():
		return false
	var speed := stats.value("orb_speed") * stats.value("projectile_speed")
	var dmg := stats.value("orb_damage") * dmg_mult
	var pierce := int(stats.value("orb_pierce"))
	# The wizard swings his staff at the first target; every orb leaves from the staff tip.
	if player.model != null and player.model.has_method("attack"):
		origin = player.model.attack(enemies.center_of(targets[0]))
	for k in n:
		var ti := targets[k % targets.size()]
		var dir := (enemies.center_of(ti) - origin).normalized()
		if k >= targets.size():  # more orbs than targets: fan out
			var spread := 0.22 * float(k - targets.size() + 1) * (1.0 if k % 2 == 0 else -1.0)
			dir = dir.rotated(Vector3.UP, spread)
		_spawn_projectile(origin, dir * speed, 1.6, dmg, pierce)
	return true


func _spawn_projectile(p: Vector3, v: Vector3, life: float, dmg: float, pierce: int) -> void:
	if pc >= P_MAX:
		return
	p_pos[pc] = p
	p_vel[pc] = v
	p_life[pc] = life
	p_dmg[pc] = dmg
	p_pierce[pc] = pierce
	p_hits[pc] = PackedInt32Array()
	pc += 1


func _update_projectiles(dt: float) -> void:
	var i := 0
	while i < pc:
		p_life[i] -= dt
		var p := p_pos[i] + p_vel[i] * dt
		p_pos[i] = p
		var alive := p_life[i] > 0.0
		if alive:
			var hl: PackedInt32Array = p_hits[i]
			for e in enemies.query_radius(p, 0.3):
				var u := enemies.uid[e]
				if hl.has(u):
					continue
				hl.append(u)
				enemies.damage(e, p_dmg[i], p_vel[i].normalized() * 2.5)
				p_pierce[i] -= 1
				if p_pierce[i] < 0:
					alive = false
					break
			p_hits[i] = hl
		if not alive:
			var last := pc - 1
			p_pos[i] = p_pos[last]
			p_vel[i] = p_vel[last]
			p_life[i] = p_life[last]
			p_dmg[i] = p_dmg[last]
			p_pierce[i] = p_pierce[last]
			p_hits[i] = p_hits[last]
			pc -= 1
			continue
		var b := i * P_STRIDE
		# Tail: a stretched glow trailing behind the core along -velocity
		var v := p_vel[i]
		var sp := v.length()
		var fwd := v / sp if sp > 0.01 else Vector3.FORWARD
		var side := fwd.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(fwd)
		var flick := 0.85 + 0.3 * sin(p_life[i] * 40.0 + float(i))
		var tb := Basis(side * 0.55 * flick, up * 0.55 * flick, fwd * 1.6)
		var tc := p - fwd * 0.55
		tail_buf[b] = tb.x.x; tail_buf[b + 1] = tb.y.x; tail_buf[b + 2] = tb.z.x; tail_buf[b + 3] = tc.x
		tail_buf[b + 4] = tb.x.y; tail_buf[b + 5] = tb.y.y; tail_buf[b + 6] = tb.z.y; tail_buf[b + 7] = tc.y
		tail_buf[b + 8] = tb.x.z; tail_buf[b + 9] = tb.y.z; tail_buf[b + 10] = tb.z.z; tail_buf[b + 11] = tc.z
		buf[b] = 1.0; buf[b + 1] = 0.0; buf[b + 2] = 0.0; buf[b + 3] = p.x
		buf[b + 4] = 0.0; buf[b + 5] = 1.0; buf[b + 6] = 0.0; buf[b + 7] = p.y
		buf[b + 8] = 0.0; buf[b + 9] = 0.0; buf[b + 10] = 1.0; buf[b + 11] = p.z
		i += 1
	mm.buffer = buf
	mm.visible_instance_count = pc
	tail_mm.buffer = tail_buf
	tail_mm.visible_instance_count = pc


func _spawn_ring(at: Vector3, radius: float) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	torus.material = _ring_mat.duplicate()
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0.0, 0.3, 0.0)
	_rings.append([mi, 0.0, radius])


func _update_rings(dt: float) -> void:
	for k in range(_rings.size() - 1, -1, -1):
		var ring: Array = _rings[k]
		var mi: MeshInstance3D = ring[0]
		ring[1] += dt
		var tt: float = ring[1] / 0.3
		if tt >= 1.0:
			mi.queue_free()
			_rings.remove_at(k)
			continue
		var r: float = ring[2] * (0.3 + 0.7 * tt)
		mi.scale = Vector3(r, 1.0 + (1.0 - tt) * 2.0, r)
		var mat: StandardMaterial3D = (mi.mesh as TorusMesh).material
		mat.albedo_color.a = 0.6 * (1.0 - tt)
