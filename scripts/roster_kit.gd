class_name RosterKit
extends Node3D
## Active abilities for the playable roster characters (Abilities hands casts and ticks here
## when the selected character isn't the Fire Wizard). Numbers match data/abilities.json;
## flat damage scales with the Damage stat, % of max HP damage doesn't.
##
## Ice Wizard
##   1  Flash Freeze    30 s  Freeze goblins within 15 m for 3 s (+50% damage taken); frozen
##                            goblins that die shatter for 40% of max HP within 2 yd (chains)
##   2  Glacial Path    45 s  +60% move speed for 6 s; your ice trail lasts 5 s, slows 60%, 15 dmg/s
##   3  Absolute Zero  120 s  25 m blizzard on you for 8 s: 80% slow, 4% max HP/s; then everything
##                            inside freezes for 2 s and shatters for 200 damage
## Thunder Wizard
##   1  Overcharge      30 s  +40% move speed for 8 s; every jump and landing shocks 6 m for 40
##   2  Thunderclap     45 s  12 bolts on the goblins with the most HP within 25 m: 120 + 1.5 s stun
##   3  Storm Lord     120 s  10 s storm: a bolt every 0.25 s within 18 m, 90 dmg, chains to 3 more
## Dark Wizard
##   1  Siphon          30 s  4 s: goblins within 12 m lose 6% max HP/s; heal 1 HP per goblin per
##                            second (max 5% of max HP per second)
##   2  Raise Dead      50 s  15 dead goblins rise and fight for 15 s (25 per hit), then explode
##                            for 60 within 3 m
##   3  Eclipse        120 s  8 s of darkness: goblins lose track of you and wander, you deal +100%
##                            damage, every kill sends a shadow wisp at a goblin for 60
## Everyone else: one KitPart each (scripts/kits/), which this node hands casts and ticks to:
## KitMerlin, KitOgre, KitGhast, KitHunter, KitVicki, KitRogue, KitGaiden, KitCroc.

signal healed(amount: float)
signal drop_xp(at: Vector3, amount: float)   # an extra XP gem (Pickpocket)

## Numbers the weapons need from the kits
const CLONE_DAMAGE := 0.6            # Reed Clones copy your attacks at 60%
const HUNT_TARGETS := 3              # Hunter's Night: bolts lock on to the 3 biggest enemies...
const HUNT_DAMAGE := 3.0             # ...for 3x damage
const STAKE_PIN := 2.0               # Stake Volley pins for 2 s
const PARTS := {
	"merlin": "res://scripts/kits/kit_merlin.gd", "ogre": "res://scripts/kits/kit_ogre.gd",
	"ghast": "res://scripts/kits/kit_ghast.gd", "vampire_hunter": "res://scripts/kits/kit_hunter.gd",
	"vicki": "res://scripts/kits/kit_vicki.gd", "rogue": "res://scripts/kits/kit_rogue.gd",
	"gaiden": "res://scripts/kits/kit_gaiden.gd", "dr_croc": "res://scripts/kits/kit_croc.gd",
	"thog": "res://scripts/kits/kit_thog.gd", "argyle_sock": "res://scripts/kits/kit_sock.gd",
	"loco_robotico": "res://scripts/kits/kit_loco.gd", "blob": "res://scripts/kits/kit_blob.gd",
}

const YARD := 0.9144
const SOUND_DIR := "res://audio/abilities/"

# --- Ice
const FREEZE_RADIUS := 15.0
const FREEZE_TIME := 3.0
const FREEZE_DELAY := 0.35          # the staff slam lands
const SHATTER_FRAC := 0.4
const PATH_TIME := 6.0
const PATH_SPEED := 1.6
const PATH_TRAIL_LIFE := 5.0
const PATH_STEP := 0.9               # metres between ice patches
const PATH_RADIUS := 1.4
const PATH_SLOW := 0.4               # 60% slow
const PATH_DPS := 15.0
const ZERO_TIME := 8.0
const ZERO_RADIUS := 25.0
const ZERO_SLOW := 0.2               # 80% slow
const ZERO_DPS := 0.04               # of max HP per second
const ZERO_FREEZE := 2.0
const ZERO_SHATTER := 200.0
# --- Thunder
const CHARGE_TIME := 8.0
const CHARGE_SPEED := 1.4
const CHARGE_RADIUS := 6.0
const CHARGE_DAMAGE := 40.0
const CLAP_BOLTS := 12
const CLAP_RADIUS := 25.0
const CLAP_DAMAGE := 120.0
const CLAP_STUN := 1.5
const CLAP_SPACING := 0.05           # seconds between strikes
const STORM_TIME := 10.0
const STORM_RADIUS := 18.0
const STORM_EVERY := 0.25
const STORM_DAMAGE := 90.0
const STORM_CHAINS := 3
const STORM_HEIGHT := 14.0
# --- Dark
const SIPHON_TIME := 4.0
const SIPHON_RADIUS := 12.0
const SIPHON_DPS := 0.06
const SIPHON_HEAL_PER := 1.0         # HP per goblin per second
const SIPHON_HEAL_CAP := 0.05        # of your max HP per second
const RAISE_COUNT := 15
const RAISE_TIME := 15.0
const RAISE_HIT := 25.0
const RAISE_RATE := 0.8              # seconds between ally hits
const RAISE_BLAST := 60.0
const RAISE_BLAST_RADIUS := 3.0
const RAISE_SPEED := 6.5
const ECLIPSE_TIME := 8.0
const ECLIPSE_DAMAGE := 2.0          # damage multiplier
const WISP_DAMAGE := 60.0
const WISP_SPEED := 15.0
const WISP_MAX := 80

const TICK := 0.25                   # damage-over-time step

var kit := ""
var hub: Abilities
var stats: Stats
var enemies: EnemyManager
var player: Player
var fx: FxManager
var corpses: CorpseManager
var lightning: LightningFx
var allies: AllyCrowd
var part: KitPart                    # the abilities of everyone but the wizards
var weapons: WeaponSystem            # set by main (Stake Volley and Shuriken Storm fire projectiles)

var _eclipse_mult := ECLIPSE_DAMAGE   # the damage bonus this Eclipse applied (its level at cast)
var _main: Color
var _deep: Color
var _light: Color
var _sounds := {}
var _waits: Array = []               # [seconds left, Callable]

# Ice state
var _path_t := 0.0
var _path_last := Vector3.INF
var _patches: Array = []             # {pos, age, disc}
var _path_tick := 0.0
var _zero_t := 0.0
var _zero_tick := 0.0
var _zero_nodes: Array = []
var _zero_frozen := PackedInt32Array()   # uids frozen by Absolute Zero, shattered after the freeze
# Thunder state
var _charge_t := 0.0
var _was_floor := true
var _charge_cd := 0.0
var _charge_sparks: CPUParticles3D
var _clap_left := 0
var _clap_t := 0.0
var _clap_hit := {}
var _storm_t := 0.0
var _storm_tick := 0.0
var _storm_cloud: Node3D
var _storm_light: OmniLight3D
# Dark state
var _siphon_t := 0.0
var _siphon_tick := 0.0
var _siphon_disc: GroundDisc
var _heal_acc := 0.0
var _heal_show := 0.0
var _eclipse_t := 0.0
var _eclipse_light: OmniLight3D
var _dimmed: Array = []              # [node, property, original value]
var _wisps: Array = []               # {pos, life}
var _mote_mm: MultiMesh
var _motes: Array = []               # {pos, vel, life, max, color, home (bool), size}


## Strength multiplier of ability slot `i` from its level (1x at level 1, 4x at level 10).
func pw(i: int) -> float:
	return hub.power(i) if hub != null else 1.0


func setup(p_hub: Abilities, p_kit: String) -> void:
	hub = p_hub
	kit = p_kit
	stats = hub.stats
	enemies = hub.enemies
	player = hub.player
	fx = hub.fx
	corpses = enemies.corpses
	_main = RosterHero.color(kit, "main")
	_deep = RosterHero.color(kit, "deep")
	_light = RosterHero.color(kit, "light")
	if PARTS.has(kit):
		part = load(PARTS[kit]).new()
		part.k = self


func _ready() -> void:
	lightning = LightningFx.new()
	add_child(lightning)
	enemies.shatter_frac = SHATTER_FRAC
	enemies.shatter_radius = 2.0 * YARD
	enemies.shattered.connect(_on_shattered)
	player.air_jumped.connect(_on_air_jump)
	for k in ["freeze", "glacial", "blizzard", "shatter", "overcharge", "zap", "thunderclap", "storm",
			"siphon", "raise_dead", "eclipse"]:
		_sounds[k] = _sfx(SOUND_DIR + k + ".wav")
	# Glowing motes (siphoned life, shadow wisps, ice chips): one MultiMesh of soft spheres
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 8
	s.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_fog = true
	m.vertex_color_use_as_albedo = true
	s.material = m
	_mote_mm = MultiMesh.new()
	_mote_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mote_mm.use_colors = true
	_mote_mm.mesh = s
	_mote_mm.instance_count = 600
	_mote_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mote_mm
	mmi.top_level = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-500, -100, -500), Vector3(1000, 300, 1000))
	add_child(mmi)
	if kit == "dark_wizard":
		allies = AllyCrowd.new()
		allies.enemies = enemies
		add_child(allies)
	Events.enemy_killed.connect(_on_kill)
	if part:
		add_child(part)


func _exit_tree() -> void:
	_restore_light()
	if Events.enemy_killed.is_connected(_on_kill):
		Events.enemy_killed.disconnect(_on_kill)


func _sfx(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = Settings.SFX_BUS
	p.max_polyphony = 3
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p


func _play(key: String, volume_db := 0.0) -> void:
	var p: AudioStreamPlayer = _sounds.get(key)
	if p and p.stream:
		p.volume_db = volume_db
		p.play()


func _dmg() -> float:
	return stats.value("damage")


func _after(secs: float, f: Callable) -> void:
	_waits.append([secs, f])


func cast(i: int) -> void:
	if part:
		part.cast(i)
		return
	match kit:
		"ice_wizard":
			[_cast_freeze, _cast_glacial, _cast_zero][i].call()
		"thunder_wizard":
			[_cast_charge, _cast_clap, _cast_storm][i].call()
		"dark_wizard":
			[_cast_siphon, _cast_raise, _cast_eclipse][i].call()


# ------------------------------------------------------------------ weapon hooks

## Damage multiplier for the next weapon attack (Smoke Bomb's ambush).
func weapon_mult() -> float:
	return part.weapon_mult() if part else 1.0


func weapon_fired() -> void:
	if part:
		part.weapon_fired()


## [model, feet position] of every shadow clone that copies your attacks.
func clone_list() -> Array:
	return part.clone_list() if part else []


## Damage of a clone's copy of your attack (Reed Clones 60%; the Lost Pair sock 100%).
func clone_damage() -> float:
	return part.clone_damage() if part else CLONE_DAMAGE


func rage_active() -> bool:
	return part != null and part.active("rage")


func hunt_active() -> bool:
	return part != null and part.active("hunt")


## Cooldown to start after casting slot i (Shadow Step's charges, Rewind's resets).
func adjust_cooldown(i: int, cd: float) -> float:
	return part.adjust_cooldown(i, cd) if part else cd


func heal_pct(frac: float) -> void:
	var h := minf(player.max_hp * frac, player.max_hp - player.hp)
	if h > 0.0:
		player.heal(h)
		healed.emit(h)


## True while an ability's effect is still running (tests, HUD).
func active(name: String) -> bool:
	if part:
		return part.active(name)
	match name:
		"glacial": return _path_t > 0.0
		"zero": return _zero_t > 0.0
		"overcharge": return _charge_t > 0.0
		"storm": return _storm_t > 0.0
		"siphon": return _siphon_t > 0.0
		"eclipse": return _eclipse_t > 0.0
		"raise": return allies != null and allies.count() > 0
	return false


func tick(dt: float) -> void:
	for k in range(_waits.size() - 1, -1, -1):
		_waits[k][0] -= dt
		if _waits[k][0] <= 0.0:
			var f: Callable = _waits[k][1]
			_waits.remove_at(k)
			f.call()
	if part:
		part.tick(dt)
	_tick_glacial(dt)
	_tick_zero(dt)
	_tick_charge(dt)
	_tick_clap(dt)
	_tick_storm(dt)
	_tick_siphon(dt)
	_tick_eclipse(dt)
	if allies:
		allies.tick(dt, _dmg() * pw(1))
	_tick_motes(dt)


# ================================================================== ICE

func _cast_freeze() -> void:
	_play("freeze")
	_after(FREEZE_DELAY, _freeze_burst)


func _freeze_burst() -> void:
	var at := player.global_position
	var n := 0
	var fr := FREEZE_RADIUS * pw(0)
	for i in enemies.query_radius(at + Vector3(0, 0.8, 0), fr, false):
		enemies.freeze(i, FREEZE_TIME)
		n += 1
	_ring(at, fr, _light, 0.45)
	_ice_spikes(at, fr, clampi(int(22 * pw(0)), 22, 70))
	fx.burst(at + Vector3(0, 1.0, 0), 5.0, _light, 0.4)
	player.add_shake(0.4)
	print_verbose("Flash Freeze froze %d enemies" % n)


func _on_shattered(at: Vector3, radius: float) -> void:
	fx.burst(at, radius * 1.3, Color(0.75, 0.92, 1.0), 0.3)
	for k in 5:
		var v := Vector3(randf_range(-1, 1), randf_range(0.8, 1.6), randf_range(-1, 1)).normalized() * randf_range(4, 8)
		_mote(at, v, 0.5, Color(0.8, 0.95, 1.0), 0.18, false, 14.0)
	if randf() < 0.35:
		_play("shatter", -8.0)


func _cast_glacial() -> void:
	_play("glacial")
	if _path_t <= 0.0:
		stats.apply("move_speed", "mult", PATH_SPEED)
	_path_t = PATH_TIME
	_path_last = Vector3.INF


func _tick_glacial(dt: float) -> void:
	if _path_t > 0.0:
		_path_t -= dt
		var p := player.global_position
		if player.is_on_floor() and (_path_last == Vector3.INF or p.distance_to(_path_last) >= PATH_STEP):
			_path_last = p
			var disc := GroundDisc.create(PATH_RADIUS, Color(0.75, 0.92, 1.0, 0.55))
			add_child(disc)
			disc.global_position = p
			disc.rotation.y = randf() * TAU
			_patches.append({"pos": p, "age": 0.0, "disc": disc})
			if randf() < 0.5:
				_mote(p + Vector3(0, 0.2, 0), Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)), 0.6, _light, 0.12, false, 3.0)
		if _path_t <= 0.0:
			stats.apply("move_speed", "mult", 1.0 / PATH_SPEED)
	for k in range(_patches.size() - 1, -1, -1):
		var pt: Dictionary = _patches[k]
		pt["age"] += dt
		var disc: GroundDisc = pt["disc"]
		var left := PATH_TRAIL_LIFE - float(pt["age"])
		disc.alpha = 0.55 * clampf(left / 1.0, 0.0, 1.0)
		if left <= 0.0:
			disc.queue_free()
			_patches.remove_at(k)
	_path_tick -= dt
	if _path_tick <= 0.0 and not _patches.is_empty():
		_path_tick = 0.2
		var d := PATH_DPS * 0.2 * _dmg() * pw(1)
		var seen := {}
		for pt in _patches:
			for i in enemies.query_radius((pt["pos"] as Vector3) + Vector3(0, 0.8, 0), PATH_RADIUS, false):
				if seen.has(i):
					continue
				seen[i] = true
				enemies.slow(i, PATH_SLOW, 0.5)
				enemies.dot_damage(i, d)


func _cast_zero() -> void:
	_play("blizzard")
	_zero_t = ZERO_TIME
	_zero_tick = 0.0
	# The storm: a frosted disc, a bright rim, falling snow and a cold light, all riding on you
	var root := Node3D.new()
	add_child(root)
	var disc := GroundDisc.create(ZERO_RADIUS, Color(0.7, 0.88, 1.0, 0.16))
	root.add_child(disc)
	var rim := GroundDisc.create(ZERO_RADIUS, Color(0.85, 0.96, 1.0, 0.5))
	rim.set_ring(0.94)
	root.add_child(rim)
	var snow := _snow(ZERO_RADIUS)
	root.add_child(snow)
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.85, 1.0)
	light.light_energy = 2.5
	light.omni_range = ZERO_RADIUS
	light.position.y = 8.0
	root.add_child(light)
	_zero_nodes = [root, disc, rim, snow, light]
	fx.burst(player.global_position + Vector3(0, 1, 0), 8.0, _light, 0.5)


func _snow(radius: float) -> CPUParticles3D:
	var p := Abilities._flame_particles(0.16, 1.4, 1100)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.95))
	grad.set_color(1, Color(0.8, 0.9, 1.0, 0.0))
	p.color_ramp = grad
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(radius * 0.8, 3.0, radius * 0.8)
	p.position.y = 9.0
	p.direction = Vector3(0.8, -1, 0.3)
	p.spread = 12.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 14.0
	p.gravity = Vector3(0, -4, 0)
	(p.mesh as QuadMesh).size = Vector2(0.25, 0.25)
	((p.mesh as QuadMesh).material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	return p


func _tick_zero(dt: float) -> void:
	if _zero_t <= 0.0:
		return
	_zero_t -= dt
	var at := player.global_position
	(_zero_nodes[0] as Node3D).global_position = at
	var rim: GroundDisc = _zero_nodes[2]
	rim.alpha = 0.35 + 0.15 * sin(_zero_t * 6.0)
	_zero_tick -= dt
	if _zero_tick <= 0.0:
		_zero_tick = TICK
		for i in enemies.query_radius(at + Vector3(0, 0.8, 0), ZERO_RADIUS, false):
			enemies.slow(i, ZERO_SLOW, TICK + 0.3)
			enemies.dot_damage(i, enemies.hp_max[i] * ZERO_DPS * pw(2) * TICK * enemies.pct_scale(i))
	if _zero_t <= 0.0:
		_zero_end(at)


func _zero_end(at: Vector3) -> void:
	_zero_frozen = PackedInt32Array()
	for i in enemies.query_radius(at + Vector3(0, 0.8, 0), ZERO_RADIUS, false):
		enemies.freeze(i, ZERO_FREEZE)
		_zero_frozen.append(enemies.uid[i])
	_ice_spikes(at, ZERO_RADIUS, 40)
	_ring(at, ZERO_RADIUS, _light, 0.6)
	_play("freeze", 2.0)
	var root: Node3D = _zero_nodes[0]
	var snow: CPUParticles3D = _zero_nodes[3]
	snow.emitting = false
	var tw := root.create_tween()
	tw.tween_method(func(a: float):
		(_zero_nodes[1] as GroundDisc).alpha = 0.16 * a
		(_zero_nodes[2] as GroundDisc).alpha = 0.5 * a
		(_zero_nodes[4] as OmniLight3D).light_energy = 2.5 * a, 1.0, 0.0, ZERO_FREEZE)
	tw.tween_callback(root.queue_free)
	_after(ZERO_FREEZE, _zero_shatter)


func _zero_shatter() -> void:
	var want := {}
	for u in _zero_frozen:
		want[u] = true
	var d := ZERO_SHATTER * _dmg() * pw(2)
	for i in enemies.count:
		if not enemies.dead[i] and want.has(enemies.uid[i]):
			fx.burst(enemies.center_of(i), 1.4, Color(0.8, 0.95, 1.0), 0.3)
			enemies.damage(i, d)
	_play("shatter", 2.0)
	player.add_shake(0.6)
	_zero_frozen = PackedInt32Array()


## Ice crystals bursting up around a circle, then melting away.
func _ice_spikes(at: Vector3, radius: float, n: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.92, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.7, 1.0)
	mat.emission_energy_multiplier = 0.8
	mat.roughness = 0.1
	var prism := PrismMesh.new()
	prism.size = Vector3(0.5, 1.6, 0.5)
	prism.material = mat
	for k in n:
		var a := TAU * k / n + randf_range(-0.1, 0.1)
		var r := radius * randf_range(0.35, 1.0)
		var x := at.x + cos(a) * r
		var z := at.z + sin(a) * r
		var mi := MeshInstance3D.new()
		mi.mesh = prism
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = Vector3(x, SwampWater.height_at(x, z) - 0.6, z)
		mi.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))
		var s := randf_range(0.6, 1.4)
		mi.scale = Vector3(s, 0.05, s)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(s, s, s), 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_interval(randf_range(0.6, 1.2))
		tw.tween_property(mi, "scale", Vector3(s * 0.6, 0.02, s * 0.6), 0.5)
		tw.tween_callback(mi.queue_free)


## A ring sweeping out from `at` to `radius` and fading.
func _ring(at: Vector3, radius: float, color: Color, time: float) -> void:
	var g := GroundDisc.create(1.0, color, true)
	g.set_ring(0.85)
	add_child(g)
	g.global_position = at
	g.scale = Vector3(0.5, 1, 0.5)
	var tw := g.create_tween()
	tw.set_parallel(true)
	tw.tween_property(g, "scale", Vector3(radius, 1, radius), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(g, "alpha", 0.0, time * 1.3).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(g.queue_free)


# ================================================================== THUNDER

func _cast_charge() -> void:
	_play("overcharge")
	if _charge_t <= 0.0:
		stats.apply("move_speed", "mult", CHARGE_SPEED)
		_charge_sparks = Abilities._flame_particles(0.18, 0.35, 40)
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 0.9, 1))
		grad.set_color(1, Color(_main, 0))
		_charge_sparks.color_ramp = grad
		_charge_sparks.emission_sphere_radius = 0.6
		_charge_sparks.spread = 180.0
		_charge_sparks.initial_velocity_min = 2.0
		_charge_sparks.initial_velocity_max = 5.0
		_charge_sparks.position.y = 1.0
		player.add_child(_charge_sparks)
	_charge_t = CHARGE_TIME
	_was_floor = player.is_on_floor()
	_shock(player.global_position)


func _tick_charge(dt: float) -> void:
	if _charge_t <= 0.0:
		return
	_charge_t -= dt
	_charge_cd -= dt
	var on := player.is_on_floor()
	if on != _was_floor and _charge_cd <= 0.0:
		_shock(player.global_position)   # took off or landed
	_was_floor = on
	if randf() < dt * 10.0:   # crackle around him
		var c := player.global_position + Vector3(0, 1.0, 0)
		lightning.bolt(c, c + Vector3(randf_range(-1, 1), randf_range(-0.8, 1.0), randf_range(-1, 1)).normalized() * 1.1, _main, 0.025, 0.08, 0.4, false)
	if _charge_t <= 0.0:
		stats.apply("move_speed", "mult", 1.0 / CHARGE_SPEED)
		if is_instance_valid(_charge_sparks):
			_charge_sparks.queue_free()


## Overcharge: extra mid-air jumps (Feather, skill-tree air jumps) shock too, not just take-off
## and landing (which the floor check in _tick_charge catches).
func _on_air_jump() -> void:
	if _charge_t > 0.0:
		_shock(player.global_position)


func _shock(at: Vector3) -> void:
	_charge_cd = 0.15
	var d := CHARGE_DAMAGE * _dmg() * pw(0)
	var c := at + Vector3(0, 0.9, 0)
	var k := 0
	for i in enemies.query_radius(c, CHARGE_RADIUS, false):
		if k < 10:
			lightning.bolt(c, enemies.center_of(i), _main, 0.04, 0.14)
		k += 1
		enemies.damage(i, d)
	_ring(at, CHARGE_RADIUS, _main, 0.25)
	_play("zap", -4.0)


func _cast_clap() -> void:
	_play("thunderclap")
	_clap_left = CLAP_BOLTS
	_clap_t = 0.25
	_clap_hit = {}


func _tick_clap(dt: float) -> void:
	if _clap_left <= 0:
		return
	_clap_t -= dt
	while _clap_t <= 0.0 and _clap_left > 0:
		_clap_t += CLAP_SPACING
		_clap_left -= 1
		var best := -1
		var best_hp := -1.0
		for i in enemies.query_radius(player.global_position + Vector3(0, 0.8, 0), CLAP_RADIUS, false):
			if _clap_hit.has(enemies.uid[i]):
				continue
			if enemies.hp[i] > best_hp:
				best_hp = enemies.hp[i]
				best = i
		if best < 0:
			_clap_left = 0
			return
		_clap_hit[enemies.uid[best]] = true
		var at := enemies.center_of(best)
		_sky_bolt(at, 0.08, 0.35)
		enemies.stun(best, CLAP_STUN)
		enemies.damage(best, CLAP_DAMAGE * _dmg() * pw(1))
		player.add_shake(0.25)


## A bolt out of the sky onto `at`, with a flash where it lands.
func _sky_bolt(at: Vector3, width: float, life: float, from := Vector3.INF) -> void:
	if from == Vector3.INF:
		from = at + Vector3(randf_range(-4, 4), 30.0, randf_range(-4, 4))
		from.y = minf(from.y, Abilities.ceiling - 0.5)
	lightning.bolt(from, at, _main, width, life, 0.12)
	lightning.bolt(from, at, _light, width * 0.6, life * 0.7, 0.1, false)
	fx.burst(at, 1.6, Color(1.0, 0.95, 0.6), 0.25)
	var ground := Vector3(at.x, SwampWater.height_at(at.x, at.z), at.z)
	_ring(ground, 2.5, _main, 0.3)


func _cast_storm() -> void:
	_play("storm")
	_storm_t = STORM_TIME
	_storm_tick = 0.6
	if is_instance_valid(_storm_cloud):
		return
	# A dark thunderhead over his head
	_storm_cloud = Node3D.new()
	add_child(_storm_cloud)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.11, 0.16)
	mat.roughness = 1.0
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.2, 0.45)
	mat.emission_energy_multiplier = 0.15
	for k in 14:
		var s := SphereMesh.new()
		var r := randf_range(2.0, 4.0)
		s.radius = r
		s.height = r * 1.3
		s.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := randf() * TAU
		var d := randf_range(0.0, 7.0)
		mi.position = Vector3(cos(a) * d, randf_range(-0.8, 0.8), sin(a) * d)
		_storm_cloud.add_child(mi)
	_storm_light = OmniLight3D.new()
	_storm_light.light_color = Color(0.85, 0.85, 1.0)
	_storm_light.light_energy = 0.0
	_storm_light.omni_range = 40.0
	_storm_light.position.y = -2.0
	_storm_cloud.add_child(_storm_light)
	_storm_cloud.scale = Vector3.ONE * 0.1
	_storm_cloud.create_tween().tween_property(_storm_cloud, "scale", Vector3.ONE, 0.6).set_ease(Tween.EASE_OUT)


func _tick_storm(dt: float) -> void:
	if not is_instance_valid(_storm_cloud):
		return
	var above := player.global_position + Vector3(0, STORM_HEIGHT, 0)
	_storm_cloud.global_position = _storm_cloud.global_position.lerp(above, 1.0 - exp(-4.0 * dt)) if _storm_t < STORM_TIME - 0.05 else above
	_storm_cloud.rotation.y += dt * 0.2
	_storm_light.light_energy = maxf(0.0, _storm_light.light_energy - dt * 30.0)
	if _storm_t <= 0.0:
		return
	_storm_t -= dt
	_storm_tick -= dt
	if _storm_tick <= 0.0:
		_storm_tick += STORM_EVERY
		var near := enemies.query_radius(player.global_position + Vector3(0, 0.8, 0), STORM_RADIUS, false)
		if not near.is_empty():
			var t := near[randi() % near.size()]
			var from := _storm_cloud.global_position + Vector3(randf_range(-5, 5), -1.5, randf_range(-5, 5))
			_chain_strike(t, from, STORM_DAMAGE * _dmg() * pw(2), STORM_CHAINS)
			_storm_light.light_energy = 6.0
	if _storm_t <= 0.0:
		var cloud := _storm_cloud
		_storm_cloud = null
		var tw := cloud.create_tween()
		tw.tween_property(cloud, "scale", Vector3.ONE * 0.05, 0.8).set_ease(Tween.EASE_IN)
		tw.tween_callback(cloud.queue_free)


## Strike goblin `t` from `from`, then jump to `chains` more goblins nearby (80% each time).
func _chain_strike(t: int, from: Vector3, dmg: float, chains: int) -> void:
	var hit := {}
	var cur := t
	_sky_bolt(enemies.center_of(cur), 0.07, 0.25, from)
	for j in chains + 1:
		hit[cur] = true
		var at := enemies.center_of(cur)
		if j > 0:
			lightning.bolt(from, at, _main, 0.05, 0.18)
		enemies.damage(cur, dmg)
		from = at
		dmg *= 0.8
		var next := -1
		var best := 36.0
		for e in enemies.query_radius(at, 6.0, false):
			if hit.has(e):
				continue
			var dd := at.distance_squared_to(enemies.center_of(e))
			if dd < best:
				best = dd
				next = e
		if next < 0:
			break
		cur = next
	if randf() < 0.5:
		_play("zap", -6.0)


# ================================================================== DARK

func _cast_siphon() -> void:
	_play("siphon")
	_siphon_t = SIPHON_TIME
	_siphon_tick = 0.0
	if not is_instance_valid(_siphon_disc):
		_siphon_disc = GroundDisc.create(SIPHON_RADIUS, Color(_main, 0.2), true)
		_siphon_disc.set_ring(0.9)
		add_child(_siphon_disc)


func _tick_siphon(dt: float) -> void:
	if _siphon_t <= 0.0:
		return
	_siphon_t -= dt
	var at := player.global_position
	_siphon_disc.global_position = at
	_siphon_disc.alpha = (0.25 + 0.15 * sin(_siphon_t * 9.0)) * clampf(_siphon_t * 2.0, 0.0, 1.0)
	_siphon_tick -= dt
	if _siphon_tick <= 0.0:
		_siphon_tick += TICK
		var near := enemies.query_radius(at + Vector3(0, 0.8, 0), SIPHON_RADIUS, false)
		for i in near:
			enemies.dot_damage(i, enemies.hp_max[i] * SIPHON_DPS * pw(0) * TICK * enemies.pct_scale(i))
		var shown := 0
		for i in near:   # streams of life flowing back to the caster
			if shown >= 14:
				break
			shown += 1
			_mote(enemies.center_of(i), Vector3(0, 1.5, 0), 1.2, _light if shown % 3 == 0 else _main, 0.2, true, 12.0)
		var heal := minf(near.size() * SIPHON_HEAL_PER * TICK, player.max_hp * SIPHON_HEAL_CAP * TICK) * pw(0)
		if heal > 0.0 and player.hp < player.max_hp:
			heal = minf(heal, player.max_hp - player.hp)
			player.heal(heal)
			_heal_acc += heal
	_heal_show -= dt
	if _heal_acc >= 1.0 and (_heal_show <= 0.0 or _siphon_t <= 0.0):   # a "+N" about once a second
		healed.emit(_heal_acc)
		_heal_acc = 0.0
		_heal_show = 1.0
	if _siphon_t <= 0.0:
		_siphon_disc.queue_free()
		_siphon_disc = null


func _cast_raise() -> void:
	_play("raise_dead")
	var at := player.global_position
	var spots: Array = corpses.take_recent(at, 25.0, RAISE_COUNT) if corpses else []
	while spots.size() < RAISE_COUNT:   # not enough fresh bodies: older dead claw up out of the bog
		var a := randf() * TAU
		var r := randf_range(3.0, 9.0)
		var x := at.x + cos(a) * r
		var z := at.z + sin(a) * r
		spots.append(Vector3(x, SwampWater.height_at(x, z), z))
	for k in spots.size():
		var p: Vector3 = spots[k]
		allies.add(p, RAISE_TIME, k * 0.04)
		fx.burst(p + Vector3(0, 0.4, 0), 1.2, _main, 0.4)
	_ring(at, 10.0, _main, 0.5)


## Allies that time out explode (AllyCrowd calls this).
func ally_expired(at: Vector3) -> void:
	for i in enemies.query_radius(at + Vector3(0, 0.6, 0), RAISE_BLAST_RADIUS, false):
		enemies.damage(i, RAISE_BLAST * _dmg() * pw(1))
	fx.burst(at + Vector3(0, 0.6, 0), RAISE_BLAST_RADIUS * 1.2, _main, 0.35)


func _cast_eclipse() -> void:
	_play("eclipse")
	if _eclipse_t <= 0.0:
		enemies.lost = true
		_eclipse_mult = 1.0 + (ECLIPSE_DAMAGE - 1.0) * pw(2)
		enemies.bonus_mult *= _eclipse_mult
		_dim_world(true)
		_eclipse_light = OmniLight3D.new()
		_eclipse_light.light_color = Color(0.6, 0.3, 1.0)
		_eclipse_light.light_energy = 1.8
		_eclipse_light.omni_range = 9.0
		_eclipse_light.position.y = 2.0
		player.add_child(_eclipse_light)
	_eclipse_t = ECLIPSE_TIME
	fx.burst(player.global_position + Vector3(0, 1, 0), 10.0, _deep, 0.6)


func _tick_eclipse(dt: float) -> void:
	_tick_wisps(dt)
	if _eclipse_t <= 0.0:
		return
	_eclipse_t -= dt
	if _eclipse_t <= 0.0:
		enemies.lost = false
		enemies.bonus_mult /= _eclipse_mult
		_dim_world(false)
		if is_instance_valid(_eclipse_light):
			_eclipse_light.queue_free()


func _on_kill(at: Vector3, type_id: int) -> void:
	if part:
		part.on_kill(at, type_id)
	if _eclipse_t > 0.0 and _wisps.size() < WISP_MAX:
		_wisps.append({"pos": at + Vector3(0, 0.8, 0), "life": 4.0, "tpos": Vector3.INF, "retarget": 0.0})


func _tick_wisps(dt: float) -> void:
	for k in range(_wisps.size() - 1, -1, -1):
		var w: Dictionary = _wisps[k]
		w["life"] -= dt
		var p: Vector3 = w["pos"]
		w["retarget"] -= dt
		if w["retarget"] <= 0.0:   # re-aim a few times a second, not every frame
			w["retarget"] = 0.2
			var t := enemies.nearest_k(p, 25.0, 1)
			w["tpos"] = enemies.center_of(t[0]) if not t.is_empty() else Vector3.INF
		var target: Vector3 = w["tpos"]
		if w["life"] <= 0.0 or target == Vector3.INF:
			_wisps.remove_at(k)
			continue
		var to := target - p
		if to.length() < 0.8:
			var hit := enemies.query_radius(p, 1.0, false)
			if not hit.is_empty():
				enemies.damage(hit[0], WISP_DAMAGE * _dmg() * pw(2))
				fx.burst(p, 0.9, _main, 0.25)
				_wisps.remove_at(k)
				continue
			w["retarget"] = 0.0
		p += to.normalized() * minf(WISP_SPEED * dt, to.length())
		p.y += sin(float(w["life"]) * 12.0) * 0.03
		w["pos"] = p
		_mote(p, Vector3.ZERO, 0.25, _main.lerp(_deep, randf() * 0.5), 0.22, false, 0.0)


## Darken the sun and the ambient light to `level` of normal (and restore them).
func _dim_world(on: bool, level := 0.12) -> void:
	if on:
		_dimmed.clear()
		for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			_dimmed.append([n, "light_energy", n.light_energy])
		for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			var env: Environment = (n as WorldEnvironment).environment
			if env:
				_dimmed.append([env, "ambient_light_energy", env.ambient_light_energy])
				_dimmed.append([env, "background_energy_multiplier", env.background_energy_multiplier])
		for d in _dimmed:
			var tw := create_tween()
			tw.tween_property(d[0], d[1], float(d[2]) * level, 0.6)
	else:
		_restore_light(0.8)


func _restore_light(time := 0.0) -> void:
	for d in _dimmed:
		if not is_instance_valid(d[0]):
			continue
		if time > 0.0 and is_inside_tree():
			create_tween().tween_property(d[0], d[1], d[2], time)
		else:
			d[0].set(d[1], d[2])
	_dimmed.clear()


# ================================================================== motes

## A glowing mote. `home` = flies to the player (siphoned life), else drifts with `vel`
## (drag slows it).
func _mote(at: Vector3, vel: Vector3, life: float, color: Color, size: float, home: bool, drag: float) -> void:
	if _motes.size() >= _mote_mm.instance_count:
		return
	_motes.append({"pos": at, "vel": vel, "life": life, "max": life, "color": color, "size": size, "home": home, "drag": drag})


func _tick_motes(dt: float) -> void:
	var buf := PackedFloat32Array()
	buf.resize(_mote_mm.instance_count * 16)
	var n := 0
	var chest := player.global_position + Vector3(0, 1.1, 0)
	for k in range(_motes.size() - 1, -1, -1):
		var m: Dictionary = _motes[k]
		m["life"] -= dt
		var p: Vector3 = m["pos"]
		if m["home"]:
			var to := chest - p
			if to.length() < 0.5:
				m["life"] = 0.0
			var v: Vector3 = m["vel"]
			v = v.lerp(to.normalized() * 16.0, 1.0 - exp(-5.0 * dt))
			m["vel"] = v
		else:
			m["vel"] = (m["vel"] as Vector3) * exp(-float(m["drag"]) * dt * 0.2) + Vector3(0, -2.0, 0) * dt * (1.0 if m["drag"] > 5.0 else 0.0)
		p += (m["vel"] as Vector3) * dt
		m["pos"] = p
		if m["life"] <= 0.0:
			_motes.remove_at(k)
			continue
		var f := float(m["life"]) / float(m["max"])
		var s := float(m["size"]) * (0.5 + 0.5 * f)
		var c: Color = m["color"]
		var b := n * 16
		buf[b] = s; buf[b + 3] = p.x
		buf[b + 5] = s; buf[b + 7] = p.y
		buf[b + 10] = s; buf[b + 11] = p.z
		buf[b + 12] = c.r; buf[b + 13] = c.g; buf[b + 14] = c.b; buf[b + 15] = minf(1.0, f * 1.5)
		n += 1
	_mote_mm.buffer = buf
	_mote_mm.visible_instance_count = n
