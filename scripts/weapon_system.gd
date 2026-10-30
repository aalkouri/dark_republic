class_name WeaponSystem
extends Node3D
## Runs all owned weapons each tick. Weapon stats live in the shared Stats object
## (orb_*, aura_*, slam_*) and are scaled by global stats (damage, attack_speed, area...).
## Projectiles are packed arrays + one MultiMesh, same pattern as enemies.
##
## The starting weapon (upgrade "weapon_orb", stats orb_*) depends on the character (`style`).
## Its damage and cooldown are the orb stats scaled by the weapon's own numbers
## (data/abilities.json: "damage", "every"; the Fire Wizard's 12 dmg / 0.9 s = 1x):
##   fire     Fireballs        auto-aimed fireballs that pierce
##   ice      Frost Shards     icicles that slow goblins (SHARD_SLOW for SHARD_SLOW_TIME)
##   thunder  Chain Lightning  instant arcs that jump CHAIN_JUMPS (+ pierce) times, losing 20% each
##   dark     Shadow Bolts     slow, extra-piercing bolts; CURSE_CHANCE to curse for CURSE_TIME
##   arcane   Arcane Bolts     (Merlin) homing bolts that bounce to ARCANE_BOUNCES more enemies
##   trunk    Tree Trunk       (Ogre) 120 deg cleave, 3 m, heavy knockback (360 deg in Swamp Rage)
##   wail     Wail             (Ghast) 8 m cone of sound: hits everything in it, slows 25%
##   silver   Silver Bolts     (Vampire Hunter) heavy bolts, pierce 3, double damage to epics
##   spear    Valkyrie Spear   (Vicki) 6 m piercing thrust; every 4th is a 25 m javelin
##   daggers  Twin Daggers     (Rogue) short throws in pairs; hits bleed 3% max HP/s for 3 s
##   katana   Katana           (Gaiden) 3-hit combo in a 3 m arc; the 3rd sends a 10 m wind slash
##   flask    Volatile Flasks  (Dr. Croc) lobbed: burst 3 m, then an acid puddle (4% max HP/s)
## On melee weapons "count" widens the reach (+20% each) instead of adding projectiles.
##
## Signature weapons: once a character is unlocked, their weapon can turn up for everyone
## else as a rare Legendary level-up reward ("sig_<style>", stats sig_<style>_*). It runs
## alongside the starting weapon; each projectile remembers its own kind.

const P_MAX := 500
const P_STRIDE := 16      # 12 transform + 4 colour (per-projectile colour)
## Projectile kinds (p_kind indexes this).
const P_KINDS := ["fire", "ice", "thunder", "dark", "arcane", "silver", "javelin", "dagger", "wind", "stake", "shuriken"]
## Weapon style -> character. Order = signature weapon order.
const STYLE_CHAR := {
	"fire": "fire_wizard", "ice": "ice_wizard", "thunder": "thunder_wizard", "dark": "dark_wizard",
	"arcane": "merlin", "trunk": "ogre", "wail": "ghast", "silver": "vampire_hunter",
	"spear": "vicki", "daggers": "rogue", "katana": "gaiden", "flask": "dr_croc",
}
const STYLES := ["fire", "ice", "thunder", "dark", "arcane", "trunk", "wail", "silver", "spear", "daggers", "katana", "flask"]
const MELEE := ["trunk", "wail", "spear", "katana"]
const SIG_WEIGHT := 0.45        # vs 3-10 for normal rewards: a rare find...
const SIG_WEIGHT_TOTAL := 1.35  # ...and all of them together stay rare
const SIG_RARITY := 3           # always Legendary
const SIG_MAX_LEVEL := 5
const SIG_BASE := {"damage": 16.0, "cooldown": 1.0, "count": 1.0, "pierce": 0.0}
const BASE_DAMAGE := 12.0       # orb_damage / orb_cooldown at the start of a run (the Fire Wizard's)
const BASE_EVERY := 0.9
const CORE_COLORS := {"fire": Color(1.0, 0.78, 0.3), "ice": Color(0.85, 0.97, 1.0), "thunder": Color(1.0, 0.95, 0.5),
	"dark": Color(0.35, 0.08, 0.5), "arcane": Color(0.85, 0.92, 1.0), "silver": Color(0.95, 0.96, 1.0),
	"javelin": Color(1.0, 0.95, 0.75), "dagger": Color(0.85, 0.88, 0.92), "wind": Color(0.9, 1.0, 1.0),
	"stake": Color(0.62, 0.42, 0.24), "shuriken": Color(0.8, 0.82, 0.88)}
const TAIL_COLORS := {"fire": Color(1.0, 0.32, 0.05, 0.75), "ice": Color(0.3, 0.7, 1.0, 0.6), "thunder": Color(1.0, 0.9, 0.3, 0.6),
	"dark": Color(0.6, 0.15, 1.0, 0.7), "arcane": Color(0.3, 0.45, 1.0, 0.75), "silver": Color(0.7, 0.75, 0.9, 0.35),
	"javelin": Color(1.0, 0.8, 0.35, 0.55), "dagger": Color(0.5, 0.8, 0.4, 0.3), "wind": Color(0.6, 0.9, 1.0, 0.45),
	"stake": Color(1.0, 0.9, 0.7, 0.25), "shuriken": Color(0.9, 0.2, 0.25, 0.35)}
## Per projectile kind: hit radius, speed multiplier
const P_RADIUS := {"wind": 1.4, "javelin": 0.6, "silver": 0.45, "shuriken": 0.5, "stake": 0.45}

var stats: Stats
var db: UpgradeDB
var enemies: EnemyManager
var player: Player
var kit: RosterKit              # the character's abilities, when they change how the weapon works

var pc := 0
var p_pos := PackedVector3Array()
var p_vel := PackedVector3Array()
var p_life := PackedFloat32Array()
var p_dmg := PackedFloat32Array()
var p_pierce := PackedInt32Array()
var p_hits: Array = []     # PackedInt32Array of enemy uids already hit, per projectile
var p_style := PackedByteArray()   # index into P_KINDS
var p_target := PackedInt32Array() # homing: uid of the target (0 = none)
var p_tidx := PackedInt32Array()   # ...and its row last time we looked

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
const ARCANE_BOUNCES := 2        # Arcane Bolts: bounce on to 2 more enemies...
const ARCANE_SPEED := 0.75       # ...flying a little slower, homing
const ARCANE_TURN := 9.0
const ARCANE_BOUNCE_RANGE := 10.0
const TRUNK_REACH := 3.0         # Tree Trunk: 120 deg cleave
const TRUNK_ARC := 120.0
const TRUNK_KNOCK := 6.0
const WAIL_REACH := 8.0          # Wail: cone
const WAIL_ARC := 55.0
const WAIL_SLOW := 0.75
const WAIL_SLOW_TIME := 1.5
const SILVER_PIERCE := 3         # Silver Bolts
const SILVER_SPEED := 1.7
const SILVER_EPIC := 2.0
const SPEAR_REACH := 6.0         # Valkyrie Spear: thrust line
const SPEAR_WIDTH := 0.9
const JAVELIN_EVERY := 4
const JAVELIN_RANGE := 25.0
const DAGGER_RANGE := 11.0       # Twin Daggers
const DAGGER_SPEED := 1.4
const BLEED_FRAC := 0.03
const BLEED_TIME := 3.0
const KATANA_REACH := 3.0        # Katana
const KATANA_ARC := 150.0
const WIND_RANGE := 10.0
const FLASK_RADIUS := 3.0        # Volatile Flasks
const FLASK_FLIGHT := 0.6
const FLASK_RANGE := 16.0
const ACID_FRAC := 0.04
const ACID_TIME := 3.0
const MELEE_SEEK := 1.6          # melee weapons swing once an enemy is within reach x this

## Level-up card for the starting weapon, per style (the rest come from data/abilities.json).
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
var combo := {}                  # style -> attack counter (katana combo, javelin every 4th)
var aura_t := 0.0
var slam_t := 1.5
var swings := 0                  # melee swings made (tests)

var mm: MultiMesh
var tail_mm: MultiMesh
var tail_buf := PackedFloat32Array()
var buf := PackedFloat32Array()
var aura_mesh: GroundDisc
var aura_mat: StandardMaterial3D
var _aura_pulse := 0.0
var _rings: Array = []     # [MeshInstance3D, age, radius]
var _ring_mat: StandardMaterial3D
var _flasks: Array = []    # {from, to, t, dmg, node}
var _puddles: Array = []   # {pos, t, disc, tick}
var _sectors := {}         # arc degrees -> unit fan mesh
var _flask_mesh: Mesh
var _whoosh: AudioStreamPlayer


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
	p_target.resize(P_MAX)
	p_tidx.resize(P_MAX)
	buf.resize(P_MAX * P_STRIDE)

	# Projectiles: a hot core, plus a glowing tail (second MultiMesh) stretched along the flight path
	var orb := SphereMesh.new()
	orb.radius = 0.24
	orb.height = 0.48
	orb.radial_segments = 10
	orb.rings = 5
	var orb_mat := StandardMaterial3D.new()
	orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb_mat.vertex_color_use_as_albedo = true   # colour per projectile
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
	var flask := SphereMesh.new()
	flask.radius = 0.2
	flask.height = 0.4
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.5, 1.0, 0.3, 0.85)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.emission_enabled = true
	fm.emission = Color(0.4, 1.0, 0.2)
	fm.emission_energy_multiplier = 1.5
	flask.material = fm
	_flask_mesh = flask
	_whoosh = AudioStreamPlayer.new()
	_whoosh.bus = Settings.SFX_BUS
	_whoosh.max_polyphony = 4
	_whoosh.volume_db = -10.0
	if ResourceLoader.exists("res://audio/abilities/whoosh.wav"):
		_whoosh.stream = load("res://audio/abilities/whoosh.wav")
	add_child(_whoosh)


## The level-up card of a style's weapon: name, desc, icon.
static func card(p_style: String) -> Dictionary:
	if CARDS.has(p_style):
		return CARDS[p_style]
	var w: Dictionary = KitDB.kit(STYLE_CHAR.get(p_style, "")).get("weapon", {})
	return {"name": w.get("name", p_style.capitalize()), "desc": w.get("desc", ""), "icon": w.get("icon", {})}


## Rename and re-icon the starting weapon's level-up card for this style.
static func retheme_card(db: UpgradeDB, p_style: String) -> void:
	if not STYLE_CHAR.has(p_style) or not db.defs.has("weapon_orb"):
		return
	var d: Dictionary = db.defs["weapon_orb"]
	var c := card(p_style)
	d["name"] = c["name"]
	d["desc"] = c["desc"]
	d["icon"] = c["icon"]
	# Its stats show on the cards too ("+20% Frost Shards Damage", not "Fireball Damage")
	if p_style != "fire":
		db.stat_names["orb_damage"] = ["%s Damage", c["name"]]
		db.stat_names["orb_cooldown"] = ["%s Cooldown", c["name"]]
		db.stat_names["orb_count"] = ["%s Reach", c["name"]] if MELEE.has(p_style) else c["name"]
		db.stat_names["orb_pierce"] = ["%s Pierce", c["name"]]


## Character id -> weapon style.
static func style_of(char_id: String) -> String:
	for s in STYLE_CHAR:
		if STYLE_CHAR[s] == char_id:
			return s
	return "fire"


## Damage and cooldown of a style's weapon relative to the Fireballs (from its kit numbers).
static func scale_of(p_style: String) -> Vector2:
	if CARDS.has(p_style):
		return Vector2.ONE
	var w: Dictionary = KitDB.kit(STYLE_CHAR.get(p_style, "")).get("weapon", {})
	var dmg := float(str(w.get("damage", BASE_DAMAGE)).split(" ")[0])
	return Vector2(dmg / BASE_DAMAGE, float(w.get("every", BASE_EVERY)) / BASE_EVERY)


## Adds the signature weapons of every unlocked character (except your own, which you already
## carry) to the level-up pool as rare Legendary rewards, and defines their stats.
static func add_signature_weapons(db: UpgradeDB, stats: Stats, own_style: String) -> void:
	var sigs := []
	for sty in STYLES:
		if sty != own_style and char_unlocked(STYLE_CHAR[sty]):
			sigs.append(sty)
	var weight := minf(SIG_WEIGHT, SIG_WEIGHT_TOTAL / maxf(1.0, sigs.size()))
	for sty in sigs:
		var c := card(sty)
		var sid: String = "sig_" + str(sty)
		var who := I18n.t(_char_name(STYLE_CHAR[sty]))
		for k in SIG_BASE:
			stats.define("%s_%s" % [sid, k], SIG_BASE[k])
		db.stat_names["%s_damage" % sid] = ["%s Damage", c["name"]]
		db.stat_names["%s_count" % sid] = c["name"]
		db.stat_names["%s_pierce" % sid] = ["%s Pierce", c["name"]]
		db.defs[sid] = {
			"id": sid, "kind": "weapon", "name": c["name"], "icon": c["icon"],
			"desc": ["LEGENDARY: the %s's weapon. %s", who, c["desc"]],
			"weight": weight, "max_level": SIG_MAX_LEVEL, "fixed": true, "rarity_fixed": SIG_RARITY,
			"signature": sty,
			"per_level": [
				{"stat": sid + "_damage", "op": "add", "value": 0.25},
				{"stat": sid + "_count", "op": "flat", "value": 0.5},
				{"stat": sid + "_pierce", "op": "flat", "value": 0.34},
			],
		}
		db.order.append(sid)


static var _chars: Array = []

static func _char_data() -> Array:
	if _chars.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
		if d is Dictionary:
			_chars = d.get("characters", [])
	return _chars


static func _char_name(char_id: String) -> String:
	for c in _char_data():
		if c["id"] == char_id:
			return str(c["name"]).trim_prefix("The ")   # no-i18n
	return char_id.replace("_", " ").capitalize()


## Unlocked = free from the start (characters.json) or bought with coins.
static func char_unlocked(char_id: String) -> bool:
	if Wallet.is_char_unlocked(char_id):
		return true
	for c in _char_data():
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

	# --- The starting weapon
	if db == null or db.level_of("weapon_orb") > 0:
		orb_t -= dt
		if orb_t <= 0.0:
			var fired := fire(style, "orb", dmg_mult)
			orb_t = stats.value("orb_cooldown") * scale_of(style).y / haste if fired else 0.1
	# --- Signature weapons (other characters' weapons, Legendary rewards)
	if db != null:
		for sid in db.levels:
			if not str(sid).begins_with("sig_") or db.levels[sid] <= 0:
				continue
			var sty: String = db.defs[sid]["signature"]
			sig_t[sid] = float(sig_t.get(sid, 0.4)) - dt
			if sig_t[sid] <= 0.0:
				var ok := fire(sty, sid, dmg_mult)
				sig_t[sid] = stats.value(sid + "_cooldown") * scale_of(sty).y / haste if ok else 0.1
	_update_projectiles(dt)
	_update_flasks(dt)

	# --- Stink Aura: damage ticks in a radius
	if db != null and db.level_of("weapon_aura") > 0:
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
	if db != null and db.level_of("weapon_slam") > 0:
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


## Fire one attack of weapon `sty` with stat prefix `pre` ("orb" or "sig_<style>"), from the
## player and from any shadow clones (Reed Clones). False if there was nothing to hit.
func fire(sty: String, pre: String, dmg_mult: float) -> bool:
	var mult := dmg_mult
	if pre == "orb" and kit != null:
		mult *= kit.weapon_mult()
	var ok := _fire_from(sty, pre, player.global_position, mult, player.model)
	if ok and pre == "orb" and kit != null:
		kit.weapon_fired()
		for c in kit.clone_list():   # [model, position]
			_fire_from(sty, pre, c[1], mult * RosterKit.CLONE_DAMAGE, c[0])
	return ok


func _fire_from(sty: String, pre: String, feet: Vector3, mult: float, model: HeroBase) -> bool:
	var chest := feet + Vector3(0.0, 0.9, 0.0)
	match sty:
		"thunder":
			return _fire_chain(chest, mult, pre, model)
		"arcane", "silver", "daggers":
			return _fire_orbs(chest, mult, sty, pre, model)
		"trunk":
			return _swing(feet, mult, pre, model, TRUNK_REACH, 360.0 if (kit != null and kit.rage_active() and pre == "orb") else TRUNK_ARC, sty)
		"wail":
			return _swing(feet, mult, pre, model, WAIL_REACH, WAIL_ARC, sty)
		"katana":
			return _swing(feet, mult, pre, model, KATANA_REACH, KATANA_ARC, sty)
		"spear":
			return _thrust(feet, mult, pre, model)
		"flask":
			return _throw_flasks(feet, mult, pre, model)
	return _fire_orbs(chest, mult, sty, pre, model)


func _dmg(pre: String, sty: String, mult: float) -> float:
	return stats.value(pre + "_damage") * (scale_of(sty).x if pre == "orb" else 1.0) * mult


func _count(pre: String) -> int:
	return maxi(1, int(stats.value(pre + "_count")) + int(stats.value("projectile_count")))


## Projectile weapons. `sty` picks the look/behaviour, `pre` the stat prefix ("orb" for the
## starting weapon, "sig_<style>" for a signature weapon).
func _fire_orbs(origin: Vector3, dmg_mult: float, sty := "fire", pre := "orb", model: HeroBase = null) -> bool:
	if model == null:
		model = player.model
	var n := _count(pre)
	var reach := 28.0
	if sty == "daggers":
		reach = DAGGER_RANGE + 2.0
	var hunting := sty == "silver" and pre == "orb" and kit != null and kit.hunt_active()
	var targets := _top_hp(origin, 30.0, RosterKit.HUNT_TARGETS) if hunting else enemies.nearest_k(origin, reach, n)
	if targets.is_empty():
		return false
	var speed := stats.value("orb_speed") * stats.value("projectile_speed")
	var dmg := _dmg(pre, sty, dmg_mult)
	var pierce := int(stats.value(pre + "_pierce"))
	var life := 1.6
	var kind := sty
	match sty:
		"dark":
			speed *= DARK_SPEED
			pierce += DARK_PIERCE
			life /= DARK_SPEED
		"arcane":
			speed *= ARCANE_SPEED
			pierce += ARCANE_BOUNCES
			life = 3.0
		"silver":
			speed *= SILVER_SPEED
			pierce += SILVER_PIERCE
			life = 1.2
			if hunting:
				dmg *= RosterKit.HUNT_DAMAGE
		"daggers":
			kind = "dagger"
			speed *= DAGGER_SPEED
			life = DAGGER_RANGE / speed
	# The wizard swings his staff at the first target; every orb leaves from the staff tip.
	if model != null and model.has_method("attack"):
		origin = model.attack(enemies.center_of(targets[0]))
	var shots := n * (2 if sty == "daggers" else 1)
	if hunting:
		shots = maxi(shots, targets.size())
	for k in shots:
		var ti := targets[k % targets.size()]
		var dir := (enemies.center_of(ti) - origin).normalized()
		if sty == "daggers":   # a pair, a little apart
			dir = dir.rotated(Vector3.UP, 0.09 * (1.0 if k % 2 == 0 else -1.0))
		elif k >= targets.size():  # more orbs than targets: fan out
			var spread := 0.22 * float(k - targets.size() + 1) * (1.0 if k % 2 == 0 else -1.0)
			dir = dir.rotated(Vector3.UP, spread)
		var homing := enemies.uid[ti] if (sty == "arcane" or hunting) else 0
		spawn_projectile(origin, dir * speed, life, dmg, pierce, P_KINDS.find(kind), homing)
	return true


## The `k` enemies with the most HP within `r` (Hunter's Night lock-on).
func _top_hp(c: Vector3, r: float, k: int) -> PackedInt32Array:
	var all := enemies.query_radius(c, r, false)
	var arr := Array(all)
	arr.sort_custom(func(a: int, b: int): return enemies.hp[a] > enemies.hp[b])
	return PackedInt32Array(arr.slice(0, k))


## Chain Lightning: an instant arc from the staff to each target, jumping on to nearby goblins.
func _fire_chain(origin: Vector3, dmg_mult: float, pre := "orb", model: HeroBase = null) -> bool:
	if model == null:
		model = player.model
	var n := _count(pre)
	var targets := enemies.nearest_k(origin, CHAIN_REACH, n)
	if targets.is_empty():
		return false
	if model != null:
		origin = model.attack(enemies.center_of(targets[0]))
	var dmg := _dmg(pre, "thunder", dmg_mult)
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


# ------------------------------------------------------------------ melee

## Tree Trunk / Wail / Katana: hit everything in an arc of `arc` degrees and `reach` metres
## toward the nearest enemy. Count (+ projectiles) widens the reach.
func _swing(feet: Vector3, dmg_mult: float, pre: String, model: HeroBase, reach: float, arc: float, sty: String) -> bool:
	var extra := maxi(0, _count(pre) - 1)
	reach *= stats.value("area") * (1.0 + 0.2 * extra)
	var chest := feet + Vector3(0, 0.9, 0)
	var near := enemies.nearest_k(chest, reach * MELEE_SEEK, 1)
	if near.is_empty():
		return false
	var to := enemies.pos[near[0]] - feet
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.05 else Vector3.FORWARD
	if model != null:
		model.attack(enemies.center_of(near[0]))
	var dmg := _dmg(pre, sty, dmg_mult)
	var step: int = combo.get(sty + pre, 0)
	combo[sty + pre] = step + 1
	var cos_half := cos(deg_to_rad(arc * 0.5))
	var col := Color(0.85, 0.7, 0.45, 0.55)
	match sty:
		"wail":
			col = Color(0.75, 0.95, 1.0, 0.4)
		"katana":
			col = Color(1.0, 0.95, 0.95, 0.7)
			if step % 3 == 2:
				dmg *= 1.25
	for e in enemies.query_radius(chest, reach, false):
		var d := enemies.pos[e] - feet
		d.y = 0.0
		var l := d.length()
		if arc < 360.0 and l > enemies.t_radius[enemies.typ[e]] * enemies.sz[e] + 0.6 and d.dot(dir) / maxf(l, 0.001) < cos_half:
			continue
		match sty:
			"trunk":
				enemies.damage(e, dmg)
				enemies.knock(e, d if l > 0.05 else dir, TRUNK_KNOCK, 0.3)
			"wail":
				enemies.damage(e, dmg)
				enemies.slow(e, WAIL_SLOW, WAIL_SLOW_TIME)
			_:
				enemies.damage(e, dmg, d.normalized() * 3.0)
	swings += 1
	var side := 1.0 if step % 2 == 0 else -1.0
	match sty:
		"wail":
			for k in 3:   # rings of sound rolling out along the cone
				_sector(feet + Vector3(0, 1.2, 0), dir, reach * (0.45 + 0.28 * k), arc, col, 0.25 + 0.08 * k, 0.0, 0.08 * k)
		"katana":
			_sector(feet + Vector3(0, 1.0, 0), dir, reach, arc, col, 0.18, 0.35 * side)
			if step % 3 == 2:   # the 3rd cut sends a wind slash
				var speed := 32.0 * stats.value("projectile_speed")
				spawn_projectile(feet + Vector3(0, 1.0, 0) + dir * 0.8, dir * speed, WIND_RANGE / speed, dmg, 99, P_KINDS.find("wind"))
		_:
			_sector(feet + Vector3(0, 0.6, 0), dir, reach, arc, col, 0.3, 0.25 * side)
			if model == player.model:
				player.add_shake(0.12)
	_play_whoosh(0.8 if sty == "trunk" else (1.4 if sty == "katana" else 1.0))
	return true


## Valkyrie Spear: a thrust that pierces a line; every JAVELIN_EVERY-th throw is a javelin.
func _thrust(feet: Vector3, dmg_mult: float, pre: String, model: HeroBase) -> bool:
	var extra := maxi(0, _count(pre) - 1)
	var reach := SPEAR_REACH * stats.value("area") * (1.0 + 0.2 * extra)
	var chest := feet + Vector3(0, 0.9, 0)
	var step: int = combo.get("spear" + pre, 0)
	var javelin := step % JAVELIN_EVERY == JAVELIN_EVERY - 1
	var near := enemies.nearest_k(chest, JAVELIN_RANGE if javelin else reach * MELEE_SEEK, 1)
	if near.is_empty():
		return false
	combo["spear" + pre] = step + 1
	var to := enemies.pos[near[0]] - feet
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.05 else Vector3.FORWARD
	if model != null:
		model.attack(enemies.center_of(near[0]))
	var dmg := _dmg(pre, "spear", dmg_mult)
	if javelin:
		var speed := 40.0 * stats.value("projectile_speed")
		spawn_projectile(chest + Vector3(0, 0.5, 0) + dir * 0.5, dir * speed, JAVELIN_RANGE / speed, dmg * 1.5, 99, P_KINDS.find("javelin"))
		_play_whoosh(0.7)
		return true
	for e in enemies.query_radius(chest + dir * reach * 0.5, reach * 0.6, false):
		var d := enemies.pos[e] - feet
		d.y = 0.0
		var along := d.dot(dir)
		var across := (d - dir * along).length()
		if along < -0.5 or along > reach or across > SPEAR_WIDTH + enemies.t_radius[enemies.typ[e]] * enemies.sz[e]:
			continue
		enemies.damage(e, dmg, dir * 3.0)
	swings += 1
	_streak(chest + Vector3(0, 0.3, 0), dir, reach, Color(1.0, 0.92, 0.6, 0.75), 0.16)
	_play_whoosh(1.2)
	return true


## Volatile Flasks: lob a flask at each of the nearest enemies.
func _throw_flasks(feet: Vector3, dmg_mult: float, pre: String, model: HeroBase) -> bool:
	var chest := feet + Vector3(0, 0.9, 0)
	var targets := enemies.nearest_k(chest, FLASK_RANGE, _count(pre))
	if targets.is_empty():
		return false
	var from := chest + Vector3(0, 0.6, 0)
	if model != null:
		from = model.attack(enemies.center_of(targets[0]))
	var dmg := _dmg(pre, "flask", dmg_mult)
	for t in targets:
		var to := enemies.pos[t] + enemies.heading(t) * FLASK_FLIGHT * 0.6   # lead the target a little
		to.y = SwampWater.height_at(to.x, to.z)
		var mi := MeshInstance3D.new()
		mi.mesh = _flask_mesh
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = from
		_flasks.append({"from": from, "to": to, "t": 0.0, "dmg": dmg, "node": mi})
	return true


func _update_flasks(dt: float) -> void:
	for k in range(_flasks.size() - 1, -1, -1):
		var f: Dictionary = _flasks[k]
		f["t"] += dt / FLASK_FLIGHT
		var t: float = minf(f["t"], 1.0)
		var p: Vector3 = (f["from"] as Vector3).lerp(f["to"], t) + Vector3(0, 4.0 * t * (1.0 - t) * 3.0, 0)
		var mi: MeshInstance3D = f["node"]
		mi.global_position = p
		mi.rotation.x += dt * 12.0
		if t >= 1.0:
			mi.queue_free()
			_flasks.remove_at(k)
			_flask_burst(f["to"], f["dmg"])
	for k in range(_puddles.size() - 1, -1, -1):
		var pd: Dictionary = _puddles[k]
		pd["t"] -= dt
		var disc: GroundDisc = pd["disc"]
		disc.alpha = 0.4 * clampf(pd["t"] / 0.6, 0.0, 1.0)
		if pd["t"] <= 0.0:
			disc.queue_free()
			_puddles.remove_at(k)
			continue
		pd["tick"] -= dt
		if pd["tick"] <= 0.0:
			pd["tick"] = 0.25
			for e in enemies.query_radius((pd["pos"] as Vector3) + Vector3(0, 0.6, 0), FLASK_RADIUS * stats.value("area"), false):
				enemies.afflict(e, ACID_FRAC, 1.0)


func _flask_burst(at: Vector3, dmg: float) -> void:
	var r := FLASK_RADIUS * stats.value("area")
	for e in enemies.query_radius(at + Vector3(0, 0.6, 0), r, false):
		enemies.damage(e, dmg)
		enemies.afflict(e, ACID_FRAC, ACID_TIME)
	var disc := GroundDisc.create(r, Color(0.45, 1.0, 0.2, 0.4), true)
	add_child(disc)
	disc.global_position = at
	_puddles.append({"pos": at, "t": ACID_TIME, "disc": disc, "tick": 0.25})
	_spawn_ring(at, r)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 1.0, 0.3)
	light.light_energy = 3.0
	light.omni_range = 6.0
	light.top_level = true
	add_child(light)
	light.global_position = at + Vector3(0, 1.0, 0)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.3)
	tw.tween_callback(light.queue_free)


# ------------------------------------------------------------------ melee FX

## A flat fan of light sweeping round `arc` degrees about `dir`, fading over `life` s.
func _sector(at: Vector3, dir: Vector3, radius: float, arc: float, col: Color, life: float, tilt := 0.0, delay := 0.0) -> void:
	var key := int(arc)
	if not _sectors.has(key):
		_sectors[key] = _fan_mesh(arc)
	var mi := MeshInstance3D.new()
	mi.mesh = _sectors[key]
	var mat := _fx_material(col)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_fog = true
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var b := Basis.looking_at(dir, Vector3.UP).rotated(dir, tilt)
	mi.global_transform = Transform3D(b.scaled(Vector3(radius * 0.4, 1, radius * 0.4)), at)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	if delay > 0.0:
		mi.visible = false
		tw.tween_callback(func(): mi.visible = true).set_delay(delay)
	tw.tween_method(func(s: float): mi.global_transform = Transform3D(b.scaled(Vector3(radius * s, 1, radius * s)), at), 0.4, 1.0, life * 0.6).set_ease(Tween.EASE_OUT).set_delay(delay)
	tw.tween_property(mat, "albedo_color:a", 0.0, life).set_ease(Tween.EASE_IN).set_delay(delay)
	tw.chain().tween_callback(mi.queue_free)


## Unit fan in the XZ plane facing -Z: bright at the rim, clear at the centre.
func _fan_mesh(arc: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(6, int(arc / 8.0))
	var a0 := deg_to_rad(-arc * 0.5)
	var a1 := deg_to_rad(arc * 0.5)
	for k in n:
		var t0 := a0 + (a1 - a0) * k / n
		var t1 := a0 + (a1 - a0) * (k + 1) / n
		var e0 := 1.0 - absf(float(k) / n - 0.5) * 1.2
		var e1 := 1.0 - absf(float(k + 1) / n - 0.5) * 1.2
		var o0 := Vector3(sin(t0), 0, -cos(t0))
		var o1 := Vector3(sin(t1), 0, -cos(t1))
		var verts := [o0 * 0.55, o0, o1, o0 * 0.55, o1, o1 * 0.55]
		var cols := [Color(1, 1, 1, 0.0), Color(1, 1, 1, e0), Color(1, 1, 1, e1), Color(1, 1, 1, 0.0), Color(1, 1, 1, e1), Color(1, 1, 1, 0.0)]
		for v in 6:
			st.set_color(cols[v])
			st.add_vertex(verts[v])
	return st.commit()


## A bright streak along `dir` (spear thrusts).
func _streak(at: Vector3, dir: Vector3, length: float, col: Color, life: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.18, 1.0)
	mi.mesh = bm
	var mat := _fx_material(col)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_fog = true
	mi.material_override = mat
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var b := Basis.looking_at(dir, Vector3.UP)
	mi.global_transform = Transform3D(b.scaled(Vector3(1, 1, length)), at + dir * length * 0.5)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_property(mi, "scale", Vector3(0.2, 0.2, length), life)
	tw.chain().tween_callback(mi.queue_free)


func _play_whoosh(pitch: float) -> void:
	if _whoosh.stream:
		_whoosh.pitch_scale = pitch * randf_range(0.92, 1.08)
		_whoosh.play()


# ------------------------------------------------------------------ projectiles

## Add a projectile. `kind` indexes P_KINDS; `homing` = uid of the enemy to steer toward.
func spawn_projectile(p: Vector3, v: Vector3, life: float, dmg: float, pierce: int, kind := 0, homing := 0) -> void:
	if pc >= P_MAX:
		return
	p_style[pc] = maxi(kind, 0)
	p_pos[pc] = p
	p_vel[pc] = v
	p_life[pc] = life
	p_dmg[pc] = dmg
	p_pierce[pc] = pierce
	p_hits[pc] = PackedInt32Array()
	p_target[pc] = homing
	p_tidx[pc] = -1
	pc += 1


func _spawn_projectile(p: Vector3, v: Vector3, life: float, dmg: float, pierce: int, sty_i := 0) -> void:
	spawn_projectile(p, v, life, dmg, pierce, sty_i)


func _update_projectiles(dt: float) -> void:
	var i := 0
	while i < pc:
		p_life[i] -= dt
		var kind: String = P_KINDS[p_style[i]]
		# Homing: steer toward the target (find another if it died)
		if p_target[i] != 0:
			var ti := p_tidx[i]
			if ti < 0 or ti >= enemies.count or enemies.uid[ti] != p_target[i] or enemies.dead[ti]:
				ti = enemies.index_of(p_target[i])
				p_tidx[i] = ti
			if ti == -1:
				var hl0: PackedInt32Array = p_hits[i]
				var nx := _next_target(p_pos[i], hl0, 14.0)
				p_target[i] = enemies.uid[nx] if nx >= 0 else 0
				p_tidx[i] = nx
			else:
				var sp := p_vel[i].length()
				var want := (enemies.center_of(ti) - p_pos[i]).normalized() * sp
				p_vel[i] = p_vel[i].lerp(want, minf(1.0, ARCANE_TURN * dt * 3.0)).normalized() * sp
		var p := p_pos[i] + p_vel[i] * dt
		p_pos[i] = p
		var alive := p_life[i] > 0.0
		if alive:
			var hl: PackedInt32Array = p_hits[i]
			for e in enemies.query_radius(p, P_RADIUS.get(kind, 0.3)):
				var u := enemies.uid[e]
				if hl.has(u):
					continue
				hl.append(u)
				var dmg := p_dmg[i]
				if kind == "silver" and (enemies.epic[e] or enemies.is_boss(e)):
					dmg *= SILVER_EPIC
				enemies.damage(e, dmg, p_vel[i].normalized() * 2.5)
				match kind:
					"ice":
						enemies.slow(e, SHARD_SLOW, SHARD_SLOW_TIME)
					"dark":
						if randf() < CURSE_CHANCE:
							enemies.curse(e, CURSE_TIME)
					"dagger":
						enemies.afflict(e, BLEED_FRAC, BLEED_TIME)
					"stake":
						enemies.stun(e, RosterKit.STAKE_PIN)
				p_pierce[i] -= 1
				if p_pierce[i] < 0:
					alive = false
					break
				if kind == "arcane":   # bounce on to the next enemy
					var nx := _next_target(p, hl, ARCANE_BOUNCE_RANGE)
					if nx < 0:
						alive = false
						break
					p_target[i] = enemies.uid[nx]
					p_tidx[i] = nx
					p_vel[i] = (enemies.center_of(nx) - p).normalized() * p_vel[i].length()
					p_life[i] = maxf(p_life[i], 1.0)
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
			p_target[i] = p_target[last]
			p_tidx[i] = p_tidx[last]
			pc -= 1
			continue
		var b := i * P_STRIDE
		# Tail: a stretched glow trailing behind the core along -velocity
		var v := p_vel[i]
		var sp2 := v.length()
		var fwd := v / sp2 if sp2 > 0.01 else Vector3.FORWARD
		var side := fwd.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(fwd)
		var flick := 0.85 + 0.3 * sin(p_life[i] * 40.0 + float(i))
		var tb := Basis(side * 0.55 * flick, up * 0.55 * flick, fwd * 1.6)
		match kind:
			"silver", "javelin", "stake":
				tb = Basis(side * 0.12, up * 0.12, fwd * 2.4)
			"dagger":
				tb = Basis(side * 0.1, up * 0.1, fwd * 1.0)
			"wind":
				tb = Basis(side * 2.4, up * 0.2, fwd * 1.4)
			"shuriken":
				tb = Basis(side * 0.35, up * 0.08, fwd * 1.2)
		var tc := p - fwd * 0.55
		tail_buf[b] = tb.x.x; tail_buf[b + 1] = tb.y.x; tail_buf[b + 2] = tb.z.x; tail_buf[b + 3] = tc.x
		tail_buf[b + 4] = tb.x.y; tail_buf[b + 5] = tb.y.y; tail_buf[b + 6] = tb.z.y; tail_buf[b + 7] = tc.y
		tail_buf[b + 8] = tb.x.z; tail_buf[b + 9] = tb.y.z; tail_buf[b + 10] = tb.z.z; tail_buf[b + 11] = tc.z
		# Core: a round fireball / shadow orb, a long thin icicle or bolt, a spinning star...
		var cb := Basis.IDENTITY
		match kind:
			"ice":
				cb = Basis(side * 0.45, up * 0.45, fwd * 2.2)
			"dark":
				cb = Basis.IDENTITY.scaled(Vector3.ONE * (1.15 + 0.15 * sin(p_life[i] * 25.0)))
			"arcane":
				cb = Basis.IDENTITY.scaled(Vector3.ONE * (0.75 + 0.2 * sin(p_life[i] * 30.0)))
			"silver", "stake":
				cb = Basis(side * 0.16, up * 0.16, fwd * 3.0)
			"javelin":
				cb = Basis(side * 0.14, up * 0.14, fwd * 7.0)
			"dagger":
				cb = Basis(side * 0.12, up * 0.05, fwd * 1.5).rotated(fwd, p_life[i] * 30.0)
			"wind":
				cb = Basis(side * 4.5, up * 0.12, fwd * 0.6)
			"shuriken":
				var spin := Basis(Vector3.UP, p_life[i] * 25.0)
				cb = spin * Basis.IDENTITY.scaled(Vector3(1.4, 0.15, 1.4))
		buf[b] = cb.x.x; buf[b + 1] = cb.y.x; buf[b + 2] = cb.z.x; buf[b + 3] = p.x
		buf[b + 4] = cb.x.y; buf[b + 5] = cb.y.y; buf[b + 6] = cb.z.y; buf[b + 7] = p.y
		buf[b + 8] = cb.x.z; buf[b + 9] = cb.y.z; buf[b + 10] = cb.z.z; buf[b + 11] = p.z
		var cc: Color = CORE_COLORS[kind]
		var tcl: Color = TAIL_COLORS[kind]
		buf[b + 12] = cc.r; buf[b + 13] = cc.g; buf[b + 14] = cc.b; buf[b + 15] = 1.0
		tail_buf[b + 12] = tcl.r; tail_buf[b + 13] = tcl.g; tail_buf[b + 14] = tcl.b; tail_buf[b + 15] = tcl.a
		i += 1
	mm.buffer = buf
	mm.visible_instance_count = pc
	tail_mm.buffer = tail_buf
	tail_mm.visible_instance_count = pc


## Nearest live enemy within `r` that this projectile hasn't hit yet, or -1.
func _next_target(at: Vector3, hit: PackedInt32Array, r: float) -> int:
	var best := -1
	var best_d := r * r
	for e in enemies.query_radius(at, r, false):
		if hit.has(enemies.uid[e]):
			continue
		var d := at.distance_squared_to(enemies.center_of(e))
		if d < best_d:
			best_d = d
			best = e
	return best


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
