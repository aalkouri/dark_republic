class_name WeaponSystem
extends Node3D
## Runs all owned weapons each tick. Weapon stats live in the shared Stats object
## (orb_*, aura_*, slam_*) and are scaled by global stats (damage, attack_speed, area...).
## Projectiles are packed arrays + one MultiMesh, same pattern as enemies.
##
## The starting weapon (upgrade "weapon_orb", stats orb_*) depends on the character (`style`):
##   fire     Fireballs        auto-aimed fireballs that pierce
##   ice      Frost Shards     icicles that slow goblins (SHARD_SLOW for SHARD_SLOW_TIME)
##   thunder  Chain Lightning  instant arcs that jump CHAIN_JUMPS (+ pierce) times, losing 20% each
##   dark     Shadow Bolts     slow, extra-piercing bolts; CURSE_CHANCE to curse for CURSE_TIME
##
## Signature weapons: once a character is unlocked, their weapon can turn up for everyone
## else as a rare Legendary level-up reward ("sig_<style>", stats sig_<style>_*). It runs
## alongside the starting weapon; each projectile remembers its own style.

const P_MAX := 400
const P_STRIDE := 16      # 12 transform + 4 colour (per-projectile style colour)
const STYLES := ["fire", "ice", "thunder", "dark"]
const STYLE_CHAR := {"fire": "fire_wizard", "ice": "ice_wizard", "thunder": "thunder_wizard", "dark": "dark_wizard"}
const SIG_WEIGHT := 0.45        # vs 3-10 for normal rewards: a rare find
const SIG_RARITY := 3           # always Legendary
const SIG_MAX_LEVEL := 5
const SIG_BASE := {"damage": 16.0, "cooldown": 1.0, "count": 1.0, "pierce": 0.0}
const CORE_COLORS := {"fire": Color(1.0, 0.78, 0.3), "ice": Color(0.85, 0.97, 1.0), "thunder": Color(1.0, 0.95, 0.5), "dark": Color(0.35, 0.08, 0.5)}
const TAIL_COLORS := {"fire": Color(1.0, 0.32, 0.05, 0.75), "ice": Color(0.3, 0.7, 1.0, 0.6), "thunder": Color(1.0, 0.9, 0.3, 0.6), "dark": Color(0.6, 0.15, 1.0, 0.7)}

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
var p_style := PackedByteArray()   # index into STYLES

const SHARD_SLOW := 0.7          # Frost Shards: goblins move at 70% speed...
const SHARD_SLOW_TIME := 2.0     # ...for 2 s
const CHAIN_JUMPS := 4           # Chain Lightning: extra goblins each arc jumps to
const CHAIN_RANGE := 6.0
const CHAIN_FALLOFF := 0.8       # damage kept per jump
const CHAIN_REACH := 22.0        # first target range
const DARK_SPEED := 0.6          # Shadow Bolts fly at 60% speed...
const DARK_PIERCE := 2           # ...pierce 2 more goblins...
const CURSE_CHANCE := 0.2        # ...and curse (+25% damage taken)...
const CURSE_TIME := 4.0          # ...for 4 s
## Level-up card for the starting weapon, per style.
const CARDS := {
	"fire": {"name": "Fireballs", "desc": "Hurls fireballs from your staff at the nearest enemies.",
		"icon": {"glyph": "fireball", "cover": "#7a2a10", "tint": "#ff9a30"}},
	"ice": {"name": "Frost Shards", "desc": "Hurls icicles from your staff that slow the enemies they hit.",
		"icon": {"glyph": "shard", "cover": "#1d4a6e", "tint": "#bfe9ff"}},
	"thunder": {"name": "Chain Lightning", "desc": "Lightning arcs from your staff and jumps between enemies.",
		"icon": {"glyph": "chainbolt", "cover": "#3a2a6e", "tint": "#fff27a"}},
	"dark": {"name": "Shadow Bolts", "desc": "Slow bolts of shadow that pierce and curse the enemies they hit.",
		"icon": {"glyph": "shadowbolt", "cover": "#2a1236", "tint": "#c45bff"}},
}

var style := "fire"              # set by main from the selected character, before _ready
var lightning: LightningFx
var orb_t := 0.3
var sig_t := {}                  # signature weapon id -> seconds to next shot
var aura_t := 0.0
var slam_t := 1.5

var mm: MultiMesh
var tail_mm: MultiMesh
var tail_buf := PackedFloat32Array()
var buf := PackedFloat32Array()
var aura_mesh: GroundDisc
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
	p_style.resize(P_MAX)
	buf.resize(P_MAX * P_STRIDE)

	# Fireballs: a hot core, plus a flame tail (second MultiMesh) stretched along the flight path
	var orb := SphereMesh.new()
	orb.radius = 0.24
	orb.height = 0.48
	orb.radial_segments = 10
	orb.rings = 5
	var orb_mat := StandardMaterial3D.new()
	orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb_mat.vertex_color_use_as_albedo = true   # colour per projectile (style)
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
	tail_mat.disable_fog = true   # additive + fog = pale grey halos
	tail_mat.vertex_color_use_as_albedo = true
	tail.material = tail_mat
	tail_mm = MultiMesh.new()
	tail_mm.transform_format = MultiMesh.TRANSFORM_3D
	tail_mm.use_colors = true
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
	mm.use_colors = true
	mm.mesh = orb
	mm.instance_count = P_MAX
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 100, 1000))
	add_child(mmi)

	aura_mesh = GroundDisc.create(1.0, Color(0.55, 1.0, 0.35, 0.18))   # drapes over the hills
	aura_mesh.visible = false
	add_child(aura_mesh)

	_ring_mat = _fx_material(Color(1.0, 0.9, 0.5, 0.6))
	lightning = LightningFx.new()
	add_child(lightning)


## Rename and re-icon the starting weapon's level-up card for this style.
static func retheme_card(db: UpgradeDB, p_style: String) -> void:
	if not CARDS.has(p_style) or not db.defs.has("weapon_orb"):
		return
	var d: Dictionary = db.defs["weapon_orb"]
	var c: Dictionary = CARDS[p_style]
	d["name"] = c["name"]
	d["desc"] = c["desc"]
	d["icon"] = c["icon"]
	# Its stats show on the cards too ("+20% Frost Shards Damage", not "Fireball Damage")
	if p_style != "fire":
		db.stat_names["orb_damage"] = ["%s Damage", c["name"]]
		db.stat_names["orb_cooldown"] = ["%s Cooldown", c["name"]]
		db.stat_names["orb_count"] = c["name"]
		db.stat_names["orb_pierce"] = ["%s Pierce", c["name"]]


## Character id -> weapon style.
static func style_of(char_id: String) -> String:
	return {"ice_wizard": "ice", "thunder_wizard": "thunder", "dark_wizard": "dark"}.get(char_id, "fire")


## Adds the signature weapons of every unlocked character (except your own, which you already
## carry) to the level-up pool as rare Legendary rewards, and defines their stats.
static func add_signature_weapons(db: UpgradeDB, stats: Stats, own_style: String) -> void:
	for sty in STYLES:
		if sty == own_style or not char_unlocked(STYLE_CHAR[sty]):
			continue
		var c: Dictionary = CARDS[sty]
		var sid: String = "sig_" + str(sty)
		var who := str(STYLE_CHAR[sty]).replace("_", " ").capitalize()
		for k in SIG_BASE:
			stats.define("%s_%s" % [sid, k], SIG_BASE[k])
		db.stat_names["%s_damage" % sid] = ["%s Damage", c["name"]]
		db.stat_names["%s_count" % sid] = c["name"]
		db.stat_names["%s_pierce" % sid] = ["%s Pierce", c["name"]]
		db.defs[sid] = {
			"id": sid, "kind": "weapon", "name": c["name"], "icon": c["icon"],
			"desc": ["LEGENDARY: the %s's weapon. %s", who, c["desc"]],
			"weight": SIG_WEIGHT, "max_level": SIG_MAX_LEVEL, "fixed": true, "rarity_fixed": SIG_RARITY,
			"signature": sty,
			"per_level": [
				{"stat": sid + "_damage", "op": "add", "value": 0.25},
				{"stat": sid + "_count", "op": "flat", "value": 0.5},
				{"stat": sid + "_pierce", "op": "flat", "value": 0.34},
			],
		}
		db.order.append(sid)


## Unlocked = free from the start (characters.json) or bought with coins.
static func char_unlocked(char_id: String) -> bool:
	if Wallet.is_char_unlocked(char_id):
		return true
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
	if d is Dictionary:
		for c in d.get("characters", []):
			if c["id"] == char_id:
				return bool(c.get("unlocked", false))
	return false


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

	# --- Fireballs: auto-targeted projectiles
	if db.level_of("weapon_orb") > 0:
		orb_t -= dt
		if orb_t <= 0.0:
			var fired := _fire_chain(chest, dmg_mult, "orb") if style == "thunder" else _fire_orbs(chest, dmg_mult, style, "orb")
			orb_t = stats.value("orb_cooldown") / haste if fired else 0.1
	# --- Signature weapons (other characters' weapons, Legendary rewards)
	for sid in db.levels:
		if not str(sid).begins_with("sig_") or db.levels[sid] <= 0:
			continue
		var sty: String = db.defs[sid]["signature"]
		sig_t[sid] = float(sig_t.get(sid, 0.4)) - dt
		if sig_t[sid] <= 0.0:
			var ok := _fire_chain(chest, dmg_mult, sid) if sty == "thunder" else _fire_orbs(chest, dmg_mult, sty, sid)
			sig_t[sid] = stats.value(sid + "_cooldown") / haste if ok else 0.1
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
		aura_mesh.alpha = 0.14 + 0.16 * _aura_pulse

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


## Projectile weapons. `sty` picks the look/behaviour, `pre` the stat prefix ("orb" for the
## starting weapon, "sig_<style>" for a signature weapon).
func _fire_orbs(origin: Vector3, dmg_mult: float, sty := "fire", pre := "orb") -> bool:
	var n := maxi(1, int(stats.value(pre + "_count")) + int(stats.value("projectile_count")))
	var targets := enemies.nearest_k(origin, 28.0, n)
	if targets.is_empty():
		return false
	var speed := stats.value("orb_speed") * stats.value("projectile_speed")
	var dmg := stats.value(pre + "_damage") * dmg_mult
	var pierce := int(stats.value(pre + "_pierce"))
	var life := 1.6
	if sty == "dark":
		speed *= DARK_SPEED
		pierce += DARK_PIERCE
		life /= DARK_SPEED
	# The wizard swings his staff at the first target; every orb leaves from the staff tip.
	if player.model != null and player.model.has_method("attack"):
		origin = player.model.attack(enemies.center_of(targets[0]))
	for k in n:
		var ti := targets[k % targets.size()]
		var dir := (enemies.center_of(ti) - origin).normalized()
		if k >= targets.size():  # more orbs than targets: fan out
			var spread := 0.22 * float(k - targets.size() + 1) * (1.0 if k % 2 == 0 else -1.0)
			dir = dir.rotated(Vector3.UP, spread)
		_spawn_projectile(origin, dir * speed, life, dmg, pierce, STYLES.find(sty))
	return true


## Chain Lightning: an instant arc from the staff to each target, jumping on to nearby goblins.
func _fire_chain(origin: Vector3, dmg_mult: float, pre := "orb") -> bool:
	var n := maxi(1, int(stats.value(pre + "_count")) + int(stats.value("projectile_count")))
	var targets := enemies.nearest_k(origin, CHAIN_REACH, n)
	if targets.is_empty():
		return false
	if player.model != null:
		origin = player.model.attack(enemies.center_of(targets[0]))
	var dmg := stats.value(pre + "_damage") * dmg_mult
	var jumps := CHAIN_JUMPS + int(stats.value(pre + "_pierce"))
	var col := RosterHero.color("thunder_wizard", "main")
	var hit := {}
	for t in targets:
		if hit.has(t):
			continue
		var from := origin
		var cur := t
		var d := dmg
		for j in jumps + 1:
			hit[cur] = true
			var at := enemies.center_of(cur)
			lightning.bolt(from, at, col, 0.05 if j > 0 else 0.07, 0.14)
			enemies.damage(cur, d)
			from = at
			d *= CHAIN_FALLOFF
			var next := -1
			var best := CHAIN_RANGE * CHAIN_RANGE
			for e in enemies.query_radius(at, CHAIN_RANGE, false):
				if hit.has(e):
					continue
				var dd := at.distance_squared_to(enemies.center_of(e))
				if dd < best:
					best = dd
					next = e
			if next < 0:
				break
			cur = next
	return true


func _spawn_projectile(p: Vector3, v: Vector3, life: float, dmg: float, pierce: int, sty_i := 0) -> void:
	if pc >= P_MAX:
		return
	p_style[pc] = maxi(sty_i, 0)
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
				var ps: int = p_style[i]
				if ps == 1:
					enemies.slow(e, SHARD_SLOW, SHARD_SLOW_TIME)
				elif ps == 3 and randf() < CURSE_CHANCE:
					enemies.curse(e, CURSE_TIME)
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
			p_style[i] = p_style[last]
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
		# Core: a round fireball / shadow orb, or a long thin icicle along the flight path
		var sty: String = STYLES[p_style[i]]
		var cb := Basis.IDENTITY
		if sty == "ice":
			cb = Basis(side * 0.45, up * 0.45, fwd * 2.2)
		elif sty == "dark":
			cb = Basis.IDENTITY.scaled(Vector3.ONE * (1.15 + 0.15 * sin(p_life[i] * 25.0)))
		buf[b] = cb.x.x; buf[b + 1] = cb.y.x; buf[b + 2] = cb.z.x; buf[b + 3] = p.x
		buf[b + 4] = cb.x.y; buf[b + 5] = cb.y.y; buf[b + 6] = cb.z.y; buf[b + 7] = p.y
		buf[b + 8] = cb.x.z; buf[b + 9] = cb.y.z; buf[b + 10] = cb.z.z; buf[b + 11] = p.z
		var cc: Color = CORE_COLORS[sty]
		var tcl: Color = TAIL_COLORS[sty]
		buf[b + 12] = cc.r; buf[b + 13] = cc.g; buf[b + 14] = cc.b; buf[b + 15] = 1.0
		tail_buf[b + 12] = tcl.r; tail_buf[b + 13] = tcl.g; tail_buf[b + 14] = tcl.b; tail_buf[b + 15] = tcl.a
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
