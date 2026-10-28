class_name EnemyManager
extends Node3D
## Data-oriented crowd: enemies are rows in packed arrays, not nodes.
## - Rendering: one MultiMesh, whole instance buffer uploaded once per tick.
## - Spatial queries: a player-centred uniform grid rebuilt every tick with a counting sort
##   (no per-cell allocations), used for separation, weapon hits and contact damage.
## - Removal: kills are flagged and swap-removed at the start of the next tick, so indices
##   stay stable for the rest of the frame.
## - Status effects live in the same rows: burn (DoT; dying while burning explodes) and
##   knockback (a fixed displacement over a short time that overrides steering).

signal exploded(pos: Vector3, radius: float)
signal epic_killed(pos: Vector3)
signal shattered(pos: Vector3, radius: float)   # a frozen goblin died and burst into ice

const MAX := 1500
const CELL := 2.0
const GRID_N := 64                      # 64 * 2m = 128m window around the player
const HALF := CELL * GRID_N * 0.5
const RELOCATE_DIST := 58.0             # stragglers further than this teleport back near the player
const STRIDE := 20                      # 12 floats transform + 4 color + 4 custom (tint, fx)
const ACCEL := 25.0
const SEPARATION_NEIGHBOURS := 8
const BURN_COLOR := Color(1.0, 0.42, 0.08)
const MAX_EXPLOSIONS_PER_TICK := 60
const BOSS_KNOCKBACK_SCALE := 0.25
const EPIC_SIZE := 1.5
const EPIC_HP := 4.0
const EPIC_TINT := Color(0.72, 0.25, 1.0)
const GOBLIN_VAT := "res://models/goblin"   # baked vertex animation (tools/bake_vat.gd)
const GOBLIN_HEIGHT := 0.95                 # model height at scale 1
const STRIDE_LEN := 0.9                     # metres covered per run cycle at scale 1
const ATTACK_REACH := 0.55                  # start swinging this close to the player (+ radius)

# Burn tuning (set by the ultimate; % of max HP)
var burn_dps_frac := 0.05
var burn_explode_frac := 0.5
var burn_explode_radius := 1.83     # 2 yards

var arena_half := 220.0
var rng: RandomNumberGenerator
var water: SwampWater          # optional: the ground (goblins follow its hills and pools)
const WATER_SPEED_MULT := 0.5
var numbers: DamageNumbers      # optional: floating damage numbers
var corpses: CorpseManager      # optional: dead goblins fall over and linger for 3 s
var damage_mult := 1.0          # all damage dealt to goblins (5x Damage power-up)
var vat: VatCrowd               # the goblin mesh + baked animations
var aph := PackedFloat32Array()  # animation phase (0..1) per goblin
var _clip_run := 0.0
var _clip_attack := 0.25
var _attack_rate := 1.0
var fear := false               # Fear Idol: goblins run away from the player
var lost := false               # Eclipse: goblins lose track of the player and wander
var bonus_mult := 1.0           # ability damage buffs (Eclipse), on top of damage_mult
# Status effects from roster abilities (per goblin, seconds left):
#   slow   moves at slow_f of its speed            (Frost Shards, Glacial Path, Absolute Zero)
#   freeze frozen solid: can't move or hit you, takes +freeze_bonus damage, shatters on death
#   stun   can't move or hit you                   (Thunderclap, Rewind...)
#   curse  takes +curse_bonus damage               (Shadow Bolts)
var slow_t := PackedFloat32Array()
var slow_f := PackedFloat32Array()
var freeze_t := PackedFloat32Array()
var stun_t := PackedFloat32Array()
var curse_t := PackedFloat32Array()
var freeze_bonus := 0.5
var curse_bonus := 0.25
var shatter_frac := 0.4         # frozen goblins that die burst for this much of their max HP
var shatter_radius := 1.83      # 2 yards
var _shatters := PackedVector3Array()   # queued: x, z, damage
const FX_FROZEN := 8.0          # added to the shader's per-instance code (see VatCrowd)
const FX_CHILL := 16.0
const FX_SHADOW := 32.0
const BURN_NUMBER_INTERVAL := 0.5   # burn damage is totalled and shown twice a second
const BAR_STRIDE := 16              # health bars: 12 transform + 4 custom (hp fraction, epic)
const BAR_HIDE_DIST := 45.0
const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float hide_dist = 45.0;
varying float hp;
varying float epic;
void vertex() {
	hp = INSTANCE_CUSTOM.x;
	epic = INSTANCE_CUSTOM.y;
	float s = length(MODEL_MATRIX[0].xyz);
	// Billboard: face the camera, keep the instance's scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	float dist = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	if (dist > hide_dist) { VERTEX *= 0.0; }
}
void fragment() {
	vec2 uv = UV;
	float bx = 0.035;
	float by = 0.22;
	vec3 border = mix(vec3(0.02), vec3(0.65, 0.25, 1.0), epic);
	vec3 col = border;
	if (uv.x > bx && uv.x < 1.0 - bx && uv.y > by && uv.y < 1.0 - by) {
		float x = (uv.x - bx) / (1.0 - 2.0 * bx);
		vec3 fill = hp > 0.5 ? mix(vec3(1.0, 0.85, 0.1), vec3(0.2, 0.85, 0.2), (hp - 0.5) * 2.0)
		                     : mix(vec3(0.9, 0.12, 0.08), vec3(1.0, 0.85, 0.1), hp * 2.0);
		col = x < hp ? fill : vec3(0.18, 0.05, 0.05);
	}
	ALBEDO = col;
}
"""

# Type table (index = type id)
var type_names := PackedStringArray()
var t_hp := PackedFloat32Array()
var t_speed := PackedFloat32Array()
var t_radius := PackedFloat32Array()
var t_scale := PackedFloat32Array()
var t_height := PackedFloat32Array()
var t_damage := PackedFloat32Array()
var t_xp := PackedFloat32Array()
var t_color: Array[Color] = []

# Per-enemy rows
var count := 0
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var hp := PackedFloat32Array()
var hp_max := PackedFloat32Array()
var typ := PackedInt32Array()
var flash := PackedFloat32Array()
var uid := PackedInt32Array()
var dead := PackedByteArray()
var epic := PackedByteArray()
var sz := PackedFloat32Array()          # per-enemy size multiplier (epic = 1.5)
var sep_x := PackedFloat32Array()
var sep_z := PackedFloat32Array()
var burn_t := PackedFloat32Array()      # seconds of burn left
var burn_acc := PackedFloat32Array()    # burn damage not yet shown as a number
var burn_num_t := PackedFloat32Array()
var dot_next := PackedFloat32Array()     # time the next DoT number may show
var kb_vel := PackedVector3Array()      # knockback velocity while kb_t > 0
var kb_t := PackedFloat32Array()
var _explosions := PackedVector3Array() # queued burn explosions: x, z, damage packed in a Vector3
var _next_uid := 1
var _dead_count := 0
var _time := 0.0
var _frame := 0

# Grid
var cell_of := PackedInt32Array()
var cell_count := PackedInt32Array()
var cell_start := PackedInt32Array()
var cell_fill := PackedInt32Array()
var sorted := PackedInt32Array()
var gx0 := 0.0
var gz0 := 0.0

var mm: MultiMesh
var buf := PackedFloat32Array()
var bar_mm: MultiMesh
var bar_buf := PackedFloat32Array()

enum { GRUNT, RUNNER, TANK, BOSS }


func _ready() -> void:
	pos.resize(MAX)
	vel.resize(MAX)
	hp.resize(MAX)
	hp_max.resize(MAX)
	burn_t.resize(MAX)
	burn_acc.resize(MAX)
	burn_num_t.resize(MAX)
	dot_next.resize(MAX)
	kb_vel.resize(MAX)
	kb_t.resize(MAX)
	typ.resize(MAX)
	flash.resize(MAX)
	uid.resize(MAX)
	dead.resize(MAX)
	epic.resize(MAX)
	sz.resize(MAX)
	sep_x.resize(MAX)
	sep_z.resize(MAX)
	for a in [slow_t, slow_f, freeze_t, stun_t, curse_t]:
		a.resize(MAX)
	cell_of.resize(MAX)
	sorted.resize(MAX)
	cell_count.resize(GRID_N * GRID_N)
	cell_start.resize(GRID_N * GRID_N)
	cell_fill.resize(GRID_N * GRID_N)
	aph.resize(MAX)
	buf.resize(MAX * STRIDE)
	for i in MAX:   # instance color stays white; per-instance look lives in custom data
		for k in 4:
			buf[i * STRIDE + 12 + k] = 1.0

	# Goblins. The color is the clothing; scale 1 is about half the wizard's height.
	#            name            hp      speed radius scale  dmg   xp     clothing
	_add_type("Goblin", 10.0, 4.2, 0.45, 1.0, 16.0, 1.0, Color(0.5, 0.32, 0.17))
	_add_type("Goblin Scamp", 6.0, 6.8, 0.36, 0.8, 12.0, 1.0, Color(0.9, 0.68, 0.18))
	_add_type("Goblin Brute", 55.0, 3.0, 0.85, 1.8, 32.0, 5.0, Color(0.38, 0.4, 0.46))
	_add_type("Goblin Warlord", 2500.0, 3.6, 2.0, 4.5, 70.0, 120.0, Color(0.55, 0.08, 0.1))

	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	vat = VatCrowd.load_bake(GOBLIN_VAT)
	_clip_run = float(vat.clip_index["run"]) / 4.0
	_clip_attack = float(vat.clip_index["attack"]) / 4.0
	_attack_rate = 1.0 / float(vat.clip_length["attack"])
	mm.mesh = vat.mesh
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(mmi)
	_make_bars()


func _make_bars() -> void:
	bar_buf.resize(MAX * BAR_STRIDE)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.12)
	var sh := Shader.new()
	sh.code = BAR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("hide_dist", BAR_HIDE_DIST)
	quad.material = mat
	bar_mm = MultiMesh.new()
	bar_mm.transform_format = MultiMesh.TRANSFORM_3D
	bar_mm.use_custom_data = true
	bar_mm.mesh = quad
	bar_mm.instance_count = MAX
	bar_mm.visible_instance_count = 0
	var bi := MultiMeshInstance3D.new()
	bi.multimesh = bar_mm
	bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(bi)


func _add_type(n: String, p_hp: float, speed: float, radius: float, scale: float, damage: float, xp: float, color: Color) -> void:
	type_names.append(n)
	t_hp.append(p_hp)
	t_speed.append(speed)
	t_radius.append(radius)
	t_scale.append(scale)
	t_height.append(GOBLIN_HEIGHT * scale)
	t_damage.append(damage)
	t_xp.append(xp)
	t_color.append(color)


# ---------------------------------------------------------------- spawning / damage

func spawn(t: int, p: Vector3, hp_mult := 1.0, is_epic := false) -> int:
	if count >= MAX:
		return -1
	var i := count
	count += 1
	pos[i] = Vector3(clampf(p.x, -arena_half, arena_half), 0.0, clampf(p.z, -arena_half, arena_half))
	pos[i].y = SwampWater.height_at(pos[i].x, pos[i].z)
	vel[i] = Vector3.ZERO
	hp[i] = t_hp[t] * hp_mult * (EPIC_HP if is_epic else 1.0)
	epic[i] = 1 if is_epic else 0
	sz[i] = EPIC_SIZE if is_epic else 1.0
	hp_max[i] = hp[i]
	burn_t[i] = 0.0
	burn_acc[i] = 0.0
	burn_num_t[i] = 0.0
	dot_next[i] = _time + BURN_NUMBER_INTERVAL
	kb_t[i] = 0.0
	typ[i] = t
	flash[i] = 0.0
	uid[i] = _next_uid
	_next_uid += 1
	aph[i] = rng.randf() if rng != null else 0.0
	dead[i] = 0
	sep_x[i] = 0.0
	sep_z[i] = 0.0
	slow_t[i] = 0.0
	slow_f[i] = 1.0
	freeze_t[i] = 0.0
	stun_t[i] = 0.0
	curse_t[i] = 0.0
	return i


## Returns true if this hit killed the enemy. Kill events fire immediately;
## the row is removed at the start of the next tick.
func damage(i: int, amount: float, knockback := Vector3.ZERO) -> bool:
	if dead[i]:
		return false
	amount *= damage_mult * taken_mult(i)
	hp[i] -= amount
	flash[i] = 0.08
	if numbers != null:
		numbers.add(_number_pos(i), amount)
	if knockback != Vector3.ZERO:
		vel[i] += knockback / (t_scale[typ[i]] * sz[i])
	if hp[i] <= 0.0:
		_kill(i)
		return true
	return false


## How much extra damage this goblin takes right now (frozen, cursed, ability buffs).
func taken_mult(i: int) -> float:
	var m := bonus_mult
	if freeze_t[i] > 0.0:
		m *= 1.0 + freeze_bonus
	if curse_t[i] > 0.0:
		m *= 1.0 + curse_bonus
	return m


## Slow to `factor` of normal speed for `secs` (the stronger / longer effect wins).
func slow(i: int, factor: float, secs: float) -> void:
	if dead[i]:
		return
	if slow_t[i] <= 0.0 or factor <= slow_f[i]:
		slow_f[i] = factor
	slow_t[i] = maxf(slow_t[i], secs)


## Frozen solid for `secs` (the boss for a third as long).
func freeze(i: int, secs: float) -> void:
	if dead[i]:
		return
	freeze_t[i] = maxf(freeze_t[i], secs * (0.34 if typ[i] == BOSS else 1.0))
	vel[i] = Vector3.ZERO


func stun(i: int, secs: float) -> void:
	if dead[i]:
		return
	stun_t[i] = maxf(stun_t[i], secs * (0.5 if typ[i] == BOSS else 1.0))
	vel[i] = Vector3.ZERO


func curse(i: int, secs: float) -> void:
	if not dead[i]:
		curse_t[i] = maxf(curse_t[i], secs)


## Frozen or stunned: stands still and can't hurt the player.
func is_held(i: int) -> bool:
	return freeze_t[i] > 0.0 or stun_t[i] > 0.0


func frozen_count() -> int:
	var n := 0
	for i in count:
		if freeze_t[i] > 0.0 and not dead[i]:
			n += 1
	return n


func _kill(i: int) -> void:
	dead[i] = 1
	_dead_count += 1
	if corpses != null:
		var t := typ[i]
		var col: Color = t_color[t]
		if epic[i]:
			col = col.lerp(EPIC_TINT, 0.3)   # clothing only leans purple
		var facing := Vector3(vel[i].x, 0.0, vel[i].z)
		corpses.add(pos[i], facing, t_scale[t] * sz[i], col, epic[i] == 1, burn_t[i] > 0.0)
	if epic[i]:
		epic_killed.emit(pos[i])
	if burn_t[i] > 0.0:
		_explosions.append(Vector3(pos[i].x, pos[i].z, hp_max[i] * burn_explode_frac))
	if freeze_t[i] > 0.0 and shatter_frac > 0.0:
		_shatters.append(Vector3(pos[i].x, pos[i].z, hp_max[i] * shatter_frac))
	Events.enemy_killed.emit(pos[i], typ[i])


## Damage over time (burning ground etc.): no hit flash, numbers totalled twice a second.
func dot_damage(i: int, amount: float) -> void:
	if dead[i]:
		return
	amount *= damage_mult * taken_mult(i)
	hp[i] -= amount
	burn_acc[i] += amount
	if hp[i] <= 0.0 or _time >= dot_next[i]:
		if numbers != null and burn_acc[i] >= 0.5:
			numbers.add(_number_pos(i), burn_acc[i], DamageNumbers.BURN)
			burn_acc[i] = 0.0
		dot_next[i] = _time + BURN_NUMBER_INTERVAL
	if hp[i] <= 0.0:
		_kill(i)


func _number_pos(i: int) -> Vector3:
	return pos[i] + Vector3(0.0, (t_height[typ[i]] + 0.35) * sz[i], 0.0)


## Push an enemy a fixed distance away over `duration` seconds (overrides steering).
func knock(i: int, dir: Vector3, distance: float, duration := 0.25) -> void:
	if dead[i]:
		return
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5)
	if typ[i] == BOSS:
		distance *= BOSS_KNOCKBACK_SCALE
	kb_vel[i] = dir.normalized() * (distance / duration)
	kb_t[i] = duration
	vel[i] = Vector3.ZERO


## Unit (x, z) facing from this goblin toward `target`.
func heading_to(i: int, target: Vector3) -> Vector2:
	var d := Vector2(target.x - pos[i].x, target.z - pos[i].z)
	return d / d.length() if d.length_squared() > 0.0001 else Vector2(0, 1)


## Direction the enemy is currently heading (velocity, or knockback while being knocked).
func heading(i: int) -> Vector3:
	var v := kb_vel[i] if kb_t[i] > 0.0 else vel[i]
	v.y = 0.0
	return v


## Set every live enemy on fire.
func ignite_all(duration: float) -> int:
	var n := 0
	for i in count:
		if not dead[i]:
			burn_t[i] = duration
			burn_acc[i] = 0.0
			burn_num_t[i] = BURN_NUMBER_INTERVAL
			n += 1
	return n


func center_of(i: int) -> Vector3:
	return pos[i] + Vector3(0.0, 0.5 * t_scale[typ[i]] * sz[i], 0.0)


func alive_count() -> int:
	return count - _dead_count


# ---------------------------------------------------------------- queries

## Indices of live enemies overlapping a sphere-ish volume (horizontal radius + vertical band).
func query_radius(c: Vector3, r: float, vertical := true) -> PackedInt32Array:
	var res := PackedInt32Array()
	var minx := maxi(floori((c.x - r - 2.5 - gx0) / CELL), 0)
	var maxx := mini(floori((c.x + r + 2.5 - gx0) / CELL), GRID_N - 1)
	var minz := maxi(floori((c.z - r - 2.5 - gz0) / CELL), 0)
	var maxz := mini(floori((c.z + r + 2.5 - gz0) / CELL), GRID_N - 1)
	if minx > maxx or minz > maxz:
		return res
	for cz in range(minz, maxz + 1):
		var row := cz * GRID_N
		for cx in range(minx, maxx + 1):
			var cell := row + cx
			var s := cell_start[cell]
			for k in range(s, s + cell_count[cell]):
				var i := sorted[k]
				if dead[i]:
					continue
				var p := pos[i]
				var t := typ[i]
				var rr := r + t_radius[t] * sz[i]
				var dx := p.x - c.x
				var dz := p.z - c.z
				if dx * dx + dz * dz > rr * rr:
					continue
				if vertical and (c.y < p.y - 0.5 or c.y > p.y + t_height[t] * sz[i] + 0.5):
					continue
				res.append(i)
	return res


## Up to k nearest live enemies within r (horizontal distance), nearest first.
func nearest_k(c: Vector3, r: float, k: int) -> PackedInt32Array:
	var best := PackedInt32Array()
	var best_d := PackedFloat32Array()
	if k <= 0:
		return best
	for i in query_radius(c, r, false):
		var p := pos[i]
		var d := (p.x - c.x) * (p.x - c.x) + (p.z - c.z) * (p.z - c.z)
		if best.size() == k and d >= best_d[k - 1]:
			continue
		var at := best.size()
		while at > 0 and best_d[at - 1] > d:
			at -= 1
		best.insert(at, i)
		best_d.insert(at, d)
		if best.size() > k:
			best.resize(k)
			best_d.resize(k)
	return best


# ---------------------------------------------------------------- simulation

func tick(dt: float, player_pos: Vector3) -> void:
	_time += dt
	_frame += 1
	_compact()
	_build_grid(player_pos)
	_resolve_explosions()
	_resolve_shatters()

	var n := count
	var parity := _frame & 1
	var corr := minf(1.0, 10.0 * dt)
	var max_dv := ACCEL * dt
	var lim := arena_half
	var reloc2 := RELOCATE_DIST * RELOCATE_DIST
	# Ground height grid (1 m cells), sampled inline below so goblins follow the hills
	var hg_on := water != null and water.hsize > 0
	var hg: PackedFloat32Array = water.hgrid if hg_on else PackedFloat32Array()
	var hs := water.hsize if hg_on else 0
	var ho := water.horigin if hg_on else 0.0
	var hmax := float(hs) - 1.001
	for i in n:
		var p := pos[i]
		var t := typ[i]
		var tx := player_pos.x - p.x
		var tz := player_pos.z - p.z
		var d2 := tx * tx + tz * tz

		if d2 > reloc2 and t != BOSS and not fear:
			var a := rng.randf() * TAU
			var r := rng.randf_range(28.0, 36.0)
			pos[i] = Vector3(player_pos.x + cos(a) * r, 0.0, player_pos.z + sin(a) * r)
			vel[i] = Vector3.ZERO
			continue

		var sc := t_scale[t] * sz[i]
		var b := i * STRIDE

		# Burn DoT (% of max HP per second)
		var burning := burn_t[i] > 0.0
		if burning and not dead[i]:
			burn_t[i] -= dt
			var bd := hp_max[i] * burn_dps_frac * dt * damage_mult
			hp[i] -= bd
			burn_acc[i] += bd
			burn_num_t[i] -= dt
			if numbers != null and (burn_num_t[i] <= 0.0 or hp[i] <= 0.0 or burn_t[i] <= 0.0):
				numbers.add(_number_pos(i), burn_acc[i], DamageNumbers.BURN)
				burn_acc[i] = 0.0
				burn_num_t[i] = BURN_NUMBER_INTERVAL
			if hp[i] <= 0.0:
				_kill(i)

		# Knockback: fixed displacement, no steering or separation
		if kb_t[i] > 0.0:
			kb_t[i] -= dt
			var kv := kb_vel[i]
			p.x = clampf(p.x + kv.x * dt, -lim, lim)
			p.z = clampf(p.z + kv.z * dt, -lim, lim)
			p.y = 0.0
			if hg_on:
				var hgx := clampf(p.x - ho, 0.0, hmax)
				var hgz := clampf(p.z - ho, 0.0, hmax)
				var hix := int(hgx)
				var hiz := int(hgz)
				var hfx := hgx - hix
				var hfz := hgz - hiz
				var hk := hiz * hs + hix
				var h0 := hg[hk] + (hg[hk + 1] - hg[hk]) * hfx
				var h1 := hg[hk + hs] + (hg[hk + hs + 1] - hg[hk + hs]) * hfx
				p.y = h0 + (h1 - h0) * hfz
			pos[i] = p
			_write_xform(b, p, -kv.x, -kv.z, sc, sc)
			buf[b + 12] = _clip_run
			buf[b + 13] = aph[i]
			if flash[i] > 0.0:
				flash[i] -= dt
			_write_color(i, b, t, burning)
			continue

		# Status timers. Frozen / stunned goblins stand still (animation paused) and can't attack.
		if slow_t[i] > 0.0:
			slow_t[i] -= dt
		if curse_t[i] > 0.0:
			curse_t[i] -= dt
		if freeze_t[i] > 0.0 or stun_t[i] > 0.0:
			freeze_t[i] -= dt
			stun_t[i] -= dt
			vel[i] = Vector3.ZERO
			var face := heading_to(i, player_pos)
			_write_xform(b, p, face.x, face.y, sc, sc)
			buf[b + 12] = _clip_run
			buf[b + 13] = aph[i]
			if flash[i] > 0.0:
				flash[i] -= dt
			_write_color(i, b, t, burning)
			continue

		# Separation is expensive, so each enemy recomputes it every other frame (cached between).
		if (i & 1) == parity:
			var ax := 0.0
			var az := 0.0
			var c := cell_of[i]
			if c >= 0:
				var cx := c % GRID_N
				var cz := c / GRID_N
				var ri := t_radius[t] * sz[i]
				var checked := 0
				for oz in range(maxi(cz - 1, 0), mini(cz + 2, GRID_N)):
					if checked >= SEPARATION_NEIGHBOURS:
						break
					for ox in range(maxi(cx - 1, 0), mini(cx + 2, GRID_N)):
						if checked >= SEPARATION_NEIGHBOURS:
							break
						var cell := oz * GRID_N + ox
						var s := cell_start[cell]
						for k in range(s, s + cell_count[cell]):
							var j := sorted[k]
							if j == i:
								continue
							var q := pos[j]
							var dx := p.x - q.x
							var dz := p.z - q.z
							var dd := dx * dx + dz * dz
							var minr := ri + t_radius[typ[j]] * sz[j]
							if dd < minr * minr and dd > 0.000001:
								var dist := sqrt(dd)
								var push := (minr - dist) / dist
								ax += dx * push
								az += dz * push
							checked += 1
							if checked >= SEPARATION_NEIGHBOURS:
								break
			sep_x[i] = ax
			sep_z[i] = az

		# Steering: accelerate toward the player at the type's speed
		var v := vel[i]
		var dvx := -v.x
		var dvz := -v.z
		var fx := 0.0
		var fz := 1.0
		if d2 > 0.0001:
			var inv := 1.0 / sqrt(d2)
			fx = tx * inv
			fz = tz * inv
			var sp := t_speed[t] * (WATER_SPEED_MULT if p.y < -0.15 else 1.0)
			if slow_t[i] > 0.0:
				sp *= slow_f[i]
			if fear:
				sp = -sp   # run away from the player
			elif lost and t != BOSS:
				# Lost in the dark: amble along a slowly turning heading of their own
				var wa := float(uid[i]) * 2.399 + _time * 0.35
				fx = cos(wa)
				fz = sin(wa)
				sp *= 0.55
			dvx += fx * sp
			dvz += fz * sp
		var dl := sqrt(dvx * dvx + dvz * dvz)
		if dl > max_dv:
			dvx *= max_dv / dl
			dvz *= max_dv / dl
		v.x += dvx
		v.z += dvz
		v.y = 0.0
		p.x = clampf(p.x + v.x * dt + sep_x[i] * corr, -lim, lim)
		p.z = clampf(p.z + v.z * dt + sep_z[i] * corr, -lim, lim)
		p.y = 0.0
		if hg_on:
			var hgx := clampf(p.x - ho, 0.0, hmax)
			var hgz := clampf(p.z - ho, 0.0, hmax)
			var hix := int(hgx)
			var hiz := int(hgz)
			var hfx := hgx - hix
			var hfz := hgz - hiz
			var hk := hiz * hs + hix
			var h0 := hg[hk] + (hg[hk + 1] - hg[hk]) * hfx
			var h1 := hg[hk + hs] + (hg[hk + hs + 1] - hg[hk + hs]) * hfx
			p.y = h0 + (h1 - h0) * hfz
		pos[i] = p
		vel[i] = v

		# Face movement direction (or the player when nearly stopped)
		var vl := v.x * v.x + v.z * v.z
		var spd := 0.0
		if vl > 0.04:
			spd = sqrt(vl)
			fx = v.x / spd
			fz = v.z / spd

		# Animation (baked vertex animation, played by the shader): swing at the player when
		# in reach, otherwise run with the cycle rate matched to ground speed (no foot sliding).
		# Written inline (no helper calls): this is the hottest loop in the game.
		var reach := t_radius[t] * sz[i] + ATTACK_REACH
		var ph := aph[i]
		var clip := _clip_run
		if d2 < reach * reach and not fear and not (lost and t != BOSS):
			clip = _clip_attack
			ph += dt * _attack_rate
		else:
			ph += dt * maxf(spd, 0.8) / (STRIDE_LEN * sc)
		ph -= floorf(ph)
		aph[i] = ph
		buf[b] = fz * sc
		buf[b + 1] = 0.0
		buf[b + 2] = fx * sc
		buf[b + 3] = p.x
		buf[b + 4] = 0.0
		buf[b + 5] = sc
		buf[b + 6] = 0.0
		buf[b + 7] = p.y
		buf[b + 8] = -fx * sc
		buf[b + 9] = 0.0
		buf[b + 10] = fz * sc
		buf[b + 11] = p.z
		buf[b + 12] = clip
		buf[b + 13] = ph

		# Per-instance look (custom data): clothing tint + burn/flash/epic code
		var fxc := 0.0
		var col: Color = t_color[t]
		if burning:
			fxc = 0.55 + 0.45 * sin(_time * 22.0 + float(uid[i]) * 1.7)
		if flash[i] > 0.0:
			flash[i] -= dt
			fxc += 2.0
		if epic[i]:
			fxc += 4.0
			col = col.lerp(EPIC_TINT, 0.3)   # clothing only leans purple
		if slow_t[i] > 0.0:
			fxc += FX_CHILL
		if curse_t[i] > 0.0:
			fxc += FX_SHADOW
		buf[b + 16] = col.r
		buf[b + 17] = col.g
		buf[b + 18] = col.b
		buf[b + 19] = fxc

	mm.buffer = buf
	mm.visible_instance_count = n
	_write_bars(n)


## Health bars: one billboard per enemy above its head (basis = uniform scale; shader billboards).
func _write_bars(n: int) -> void:
	for i in n:
		var b := i * BAR_STRIDE
		var s := clampf(t_scale[typ[i]] * sz[i], 1.0, 3.0)
		var p := pos[i]
		bar_buf[b] = s
		bar_buf[b + 3] = p.x
		bar_buf[b + 5] = s
		bar_buf[b + 7] = p.y + (t_height[typ[i]] + 0.15) * t_scale[typ[i]] * sz[i] * 1.0 + 0.1
		bar_buf[b + 10] = s
		bar_buf[b + 11] = p.z
		bar_buf[b + 12] = clampf(hp[i] / hp_max[i], 0.0, 1.0) if not dead[i] else 0.0
		bar_buf[b + 13] = float(epic[i])
	bar_mm.buffer = bar_buf
	bar_mm.visible_instance_count = n


func _write_xform(b: int, p: Vector3, fx: float, fz: float, s: float, sy: float, roll := 0.0, bob := 0.0) -> void:
	var l := fx * fx + fz * fz
	if l > 0.000001 and absf(l - 1.0) > 0.001:
		l = 1.0 / sqrt(l)
		fx *= l
		fz *= l
	elif l <= 0.000001:
		fx = 0.0
		fz = 1.0
	# Columns: X = right rolled, Y = up rolled, Z = forward. Rows are written out.
	var c := cos(roll)
	var sn := sin(roll)
	buf[b] = fz * c * s
	buf[b + 1] = -fz * sn * sy
	buf[b + 2] = fx * s
	buf[b + 3] = p.x
	buf[b + 4] = sn * s
	buf[b + 5] = c * sy
	buf[b + 6] = 0.0
	buf[b + 7] = p.y + bob
	buf[b + 8] = -fx * c * s
	buf[b + 9] = fx * sn * sy
	buf[b + 10] = fz * s
	buf[b + 11] = p.z


## Per-instance look goes into custom data: rgb = clothing tint, a = burn + 2*flash + 4*epic.
func _write_color(i: int, b: int, t: int, burning: bool) -> void:
	var col: Color = t_color[t]
	var fx := 0.0
	if burning:
		fx += 0.55 + 0.45 * sin(_time * 22.0 + float(uid[i]) * 1.7)
	if flash[i] > 0.0:
		fx += 2.0
	if epic[i]:
		fx += 4.0
		col = col.lerp(EPIC_TINT, 0.3)   # clothing only leans purple
	if freeze_t[i] > 0.0:
		fx += FX_FROZEN
	elif slow_t[i] > 0.0:
		fx += FX_CHILL
	if curse_t[i] > 0.0:
		fx += FX_SHADOW
	buf[b + 16] = col.r
	buf[b + 17] = col.g
	buf[b + 18] = col.b
	buf[b + 19] = fx


## Burn explosions are queued on death and resolved here (capped per tick), so chain
## reactions spread over frames instead of recursing.
func _resolve_explosions() -> void:
	if _explosions.is_empty():
		return
	var n := mini(_explosions.size(), MAX_EXPLOSIONS_PER_TICK)
	var now := _explosions.slice(0, n)
	_explosions = _explosions.slice(n)
	for e in now:
		var c := Vector3(e.x, 0.8, e.y)
		for j in query_radius(c, burn_explode_radius, false):
			damage(j, e.z)
		exploded.emit(Vector3(e.x, 0.6, e.y), burn_explode_radius)


## Shatters work like burn explosions: queued on death, resolved (capped) next tick, chaining.
func _resolve_shatters() -> void:
	if _shatters.is_empty():
		return
	var n := mini(_shatters.size(), MAX_EXPLOSIONS_PER_TICK)
	var now := _shatters.slice(0, n)
	_shatters = _shatters.slice(n)
	for e in now:
		var c := Vector3(e.x, 0.8, e.y)
		for j in query_radius(c, shatter_radius, false):
			damage(j, e.z)
		shattered.emit(Vector3(e.x, SwampWater.height_at(e.x, e.y) + 0.6, e.y), shatter_radius)


func burning_count() -> int:
	var n := 0
	for i in count:
		if burn_t[i] > 0.0 and not dead[i]:
			n += 1
	return n


func _build_grid(center: Vector3) -> void:
	gx0 = floorf(center.x / CELL) * CELL - HALF
	gz0 = floorf(center.z / CELL) * CELL - HALF
	cell_count.fill(0)
	for i in count:
		var p := pos[i]
		var cx := floori((p.x - gx0) / CELL)
		var cz := floori((p.z - gz0) / CELL)
		if cx < 0 or cz < 0 or cx >= GRID_N or cz >= GRID_N:
			cell_of[i] = -1
		else:
			var c := cz * GRID_N + cx
			cell_of[i] = c
			cell_count[c] += 1
	var acc := 0
	for c in GRID_N * GRID_N:
		cell_start[c] = acc
		cell_fill[c] = acc
		acc += cell_count[c]
	for i in count:
		var c := cell_of[i]
		if c >= 0:
			sorted[cell_fill[c]] = i
			cell_fill[c] += 1


func _compact() -> void:
	if _dead_count == 0:
		return
	var i := 0
	while i < count:
		if dead[i]:
			var last := count - 1
			pos[i] = pos[last]
			vel[i] = vel[last]
			hp[i] = hp[last]
			hp_max[i] = hp_max[last]
			burn_t[i] = burn_t[last]
			burn_acc[i] = burn_acc[last]
			burn_num_t[i] = burn_num_t[last]
			dot_next[i] = dot_next[last]
			kb_vel[i] = kb_vel[last]
			kb_t[i] = kb_t[last]
			typ[i] = typ[last]
			flash[i] = flash[last]
			uid[i] = uid[last]
			aph[i] = aph[last]
			dead[i] = dead[last]
			epic[i] = epic[last]
			sz[i] = sz[last]
			sep_x[i] = sep_x[last]
			sep_z[i] = sep_z[last]
			slow_t[i] = slow_t[last]
			slow_f[i] = slow_f[last]
			freeze_t[i] = freeze_t[last]
			stun_t[i] = stun_t[last]
			curse_t[i] = curse_t[last]
			count -= 1
		else:
			i += 1
	_dead_count = 0
