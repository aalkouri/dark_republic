extends Node
## The map bosses who joined the roster - the Pharaoh, the Necromancer and Singe - are playable:
## each plays as its own code-built boss model at player size (PlayableBoss), puts its weapon
## away when not attacking, its signature weapon hits the way its card says, all three abilities
## do what they say (damage, effects, cooldowns), the ultimate sets the woods ablaze, the Forge
## has its recipe and level 1 special, character select previews it in 3D, it has its own
## entrance, a run starts on a map that isn't its home, and the unlock rules hold (beat the boss,
## then 10,000 coins; never on its home map).
##   godot --headless --fixed-fps 60 --path . res://tools/test_playable_bosses.tscn [-- --only=<id>]

const CHARS := ["pharaoh", "necromancer", "singe"]
const HOME := {"pharaoh": "desert", "necromancer": "graveyard", "singe": "caldera"}
const STYLE := {"pharaoh": "scarab", "necromancer": "soul", "singe": "ember"}
const RECIPE := {"pharaoh": {"fire": 2, "lightning": 1, "light": 2}, "necromancer": {"ice": 1, "dark": 3, "light": 1}, "singe": {"fire": 3, "dark": 2}}
const AM := EnemyManager.ABILITY_DAMAGE_MULT   # abilities hit twice as hard as listed
const COOLDOWNS := {"pharaoh": [30, 45, 120], "necromancer": [30, 45, 120], "singe": [25, 45, 120]}

var fails := 0
var main: Node
var em: EnemyManager
var player: Player
var ab: Abilities
var ws: WeaponSystem


func _ready() -> void:
	Wallet.persist = false
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.split("=")[1]
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	for id in CHARS:
		if only != "" and id != only:
			continue
		print("--- ", id)
		_static_checks(id)
		await _holster(id)
		await _preview(id)
		await _select_screen(id)
		await _load(id)
		_check("%s: a run starts on a map that isn't home (the Swamp), as its own boss model" % id, player.model is RosterHero and (player.model as RosterHero).boss != null
			and (player.model as RosterHero).char_id == id, str(player.model))
		_check("%s: its weapon is the starting weapon" % id, ws.style == STYLE[id], ws.style)
		_check("%s: abilities come from its kit" % id, ab.roster != null and ab.roster.part != null, "")
		await call("_" + id)
		await _cooldowns(id)
		await _ult_burns(id)
	_finish()


# ------------------------------------------------------------------ data, unlock, forge

func _static_checks(id: String) -> void:
	_check("%s is playable (model + kit)" % id, RosterHero.is_playable(id) and RosterModel.has_model(id) and KitDB.has_kit(id), "")
	var c: Dictionary = {}
	for ch in load("res://scripts/character_select.gd").load_characters():
		if ch["id"] == id:
			c = ch
	_check("%s: unlock rules unchanged: beat the boss, then 10,000 coins" % id, int(c.get("price", 0)) == 10000 and str(c.get("requires_boss", "")) == id, str(c.get("price", 0)))
	_check("%s: banned from its home map (%s)" % [id, HOME[id]], MapPicker.banned_maps(id).has(HOME[id]) and MapPicker.lock_reason(HOME[id], id) != ""
		and MapPicker.lock_reason("swamp", id) == "", MapPicker.lock_reason(HOME[id], id))
	var kit := KitDB.kit(id)
	var abil: Array = kit.get("abilities", [])
	var cds_ok := abil.size() == 3
	for i in abil.size():
		cds_ok = cds_ok and int(abil[i]["cooldown"]) == int(COOLDOWNS[id][i]) and AbilityGlyphs.NAMES.has(str(abil[i]["icon"]["glyph"]))
	_check("%s: 3 abilities with cooldowns %s and drawn icons" % [id, str(COOLDOWNS[id])], cds_ok, "")
	var sty: String = STYLE[id]
	_check("%s: a signature weapon style (%s), a Legendary card for the others" % [id, sty], WeaponSystem.STYLE_CHAR.get(sty, "") == id and WeaponSystem.STYLES.has(sty)
		and WeaponSystem.card(sty)["name"] == kit["weapon"]["name"], str(WeaponSystem.card(sty)))
	_check("%s: forge recipe of 5 shards %s" % [id, str(RECIPE[id])], Forge.has_recipe(sty) and Forge.cost(sty, 1) == RECIPE[id], str(Forge.cost(sty, 1)))
	_check("every weapon style still has a recipe and a special (%d styles)" % WeaponSystem.STYLES.size(), Forge.RECIPES.size() == WeaponSystem.STYLES.size() and Forge.SPECIALS.size() == WeaponSystem.STYLES.size(), "")
	_check("%s: a level 1 forge special" % id, Forge.SPECIALS.has(sty) and Forge.describe(sty, 1).has(Forge.SPECIALS[sty]), "")
	_check("%s: an entrance of its own" % id, HeroEntrances.has_entrance(id), HeroEntrances.kind_of(id))
	var tree := SkillTree.tree_for(id)
	_check("%s: a skill tree (the generic draw)" % id, not tree.is_empty(), str(tree.keys()))


## The weapon is put away at rest, drawn to attack / cast, and put back after (Singe has none).
func _holster(id: String) -> void:
	var stage := Node3D.new()
	add_child(stage)
	var h := RosterHero.create(id)
	stage.add_child(h)
	await _frames(3)
	var b: Node3D = h.boss
	var box := _aabb(b)
	_check("%s: player-sized (%.2f m tall)" % [id, box.size.y], box.size.y > 1.35 and box.size.y < 2.4, "%.2f x %.2f" % [box.size.x, box.size.y])
	if id == "singe":
		_check("singe: no held weapon to put away (his claws and embers)", not h.is_drawn() and h.weapons.is_empty() and h.stowed.is_empty(), "")
		var tip := h.attack(h.global_position + Vector3(0, 1, -5))
		_check("singe: embers leave from his claw", tip.distance_to(h.global_position) < 2.0 and (b as SingeBody).attacks == 1, "%.2f" % tip.distance_to(h.global_position))
	else:
		var st: Array = b.get("stowed")
		_check("%s: weapon put away at rest (on the belt / back)" % id, not h.is_drawn() and _stowed_visible(st) and not _hand_visible(b), "")
		for s in st:
			var local := h.global_transform.affine_inverse() * (s as Node3D).global_position
			_check("%s: ...on the body (%.2f, %.2f, %.2f)" % [id, local.x, local.y, local.z], Vector2(local.x, local.z).length() < 0.75 and local.y > 0.4 and local.y < 1.9, "")
		var tip := h.attack(h.global_position + Vector3(0, 1, -5))
		_check("%s: an attack draws it" % id, h.is_drawn() and _hand_visible(b) and not _stowed_visible(st), "")
		_check("%s: ...shots leave from its head" % id, tip.distance_to(b.call("tip")) < 0.01 and tip.y > h.global_position.y + 0.6, "%.2f" % tip.y)
		await _secs(0.7)
		h.attack(h.global_position + Vector3(0, 1, -5))
		await _secs(0.6)
		_check("%s: stays out while attacking again" % id, h.is_drawn(), "")
		await _secs(2.2)
		_check("%s: put away again after a pause" % id, not h.is_drawn() and _stowed_visible(st), "")
		h.play_hit()
		await _secs(0.1)
		_check("%s: getting hit doesn't draw it" % id, not h.is_drawn(), "")
		h.play_ability(1)
		await _secs(0.1)
		_check("%s: a cast draws it" % id, h.is_drawn(), "")
		await _secs(3.0)
		_check("%s: ...and puts it back after" % id, not h.is_drawn(), "")
	# Poses: run, attack, cast, hit, death
	var cast_n: int = b.get("casts")
	h.play_ability(2)
	await _secs(0.3)
	_check("%s: the ultimate's cast pose" % id, int(b.get("casts")) == cast_n + 1 and _cast_pose(id, b), "")
	await _secs(2.0)
	h.set_motion(6.5, false)
	await _secs(0.5)
	_check("%s: runs (legs / glide / scamper)" % id, _running(id, b), "")
	h.set_motion(0.0, false)
	h.play_death()
	await _secs(3.5)
	_check("%s: plays a death when the run ends (even paused)" % id, bool(b.get("dead")) and h.process_mode == Node.PROCESS_MODE_ALWAYS and _died(id, b), "")
	stage.queue_free()
	await _frames(2)


func _hand_visible(b: Node3D) -> bool:
	if b is PharaohBody:
		return (b as PharaohBody).model.hand_l.visible and (b as PharaohBody).model.hand_r.visible
	if b is NecromancerBody:
		return (b as NecromancerBody).staff.visible
	return false


func _stowed_visible(st: Array) -> bool:
	if st.is_empty():
		return false
	for s in st:
		if not (s as Node3D).visible:
			return false
	return true


func _cast_pose(id: String, b: Node3D) -> bool:
	match id:
		"pharaoh": return (b as PharaohBody).model.pose == "raise"
		"necromancer": return (b as NecromancerBody).model._pose == "rise"
		"singe": return (b as SingeBody).model.pose == "raise"
	return false


func _running(id: String, b: Node3D) -> bool:
	match id:
		"pharaoh":
			var m := (b as PharaohBody).model
			return m.pose == "walk" and m.walk_speed > 3.0 and absf(m.hip_r.rotation.x) + absf(m.hip_l.rotation.x) > 0.05 and m.rotation.x < -0.1
		"necromancer":
			return (b as NecromancerBody).model._pose == "walk" and b.rotation.x < -0.1
		"singe":
			return (b as SingeBody).model.pose == "scamper"
	return false


func _died(id: String, b: Node3D) -> bool:
	match id:
		"pharaoh": return (b as PharaohBody).model.pose == "die" and (b as PharaohBody).model.scale.y < PharaohBody.SCALE * 0.8
		"necromancer": return (b as NecromancerBody).model.crumble > 0.9
		"singe": return (b as SingeBody).model.pose == "die" and (b as SingeBody).model._pile.visible
	return false


func _preview(id: String) -> void:
	var m := RosterModel.create(id)
	add_child(m)
	await _frames(3)
	_check("%s: character select preview in 3D, relaxed, weapon put away" % id, m._boss != null and not m.is_drawn(), "")
	m.free()


## The real character select: locked until the boss is beaten and 10,000 coins paid; then it's
## playable with a 3D preview.
func _select_screen(id: String) -> void:
	Wallet.coins = 0
	Wallet.unlocked_chars = []
	Wallet.bosses_defeated = []
	var cs: Node = load("res://scenes/character_select.tscn").instantiate()
	add_child(cs)
	await _frames(3)
	var k := -1
	for j in cs.characters.size():
		if cs.characters[j]["id"] == id:
			k = j
	_check("%s: on the roster, locked" % id, k >= 0 and not cs.is_unlocked(k) and cs.is_ready(k), "")
	Wallet.coins = 20000
	_check("%s: coins alone don't unlock it" % id, not cs.can_unlock(k), "")
	Wallet.bosses_defeated = [id]
	Wallet.coins = 9999
	_check("%s: beating the boss alone doesn't either" % id, not cs.can_unlock(k), "")
	Wallet.coins = 10000
	_check("%s: beaten and 10,000 coins: it can be unlocked" % id, cs.can_unlock(k), "")
	Wallet.unlock_char(id)
	cs._shown = -1
	cs._show(k)
	await _frames(3)
	var rm: RosterModel = cs._previews.get(id)
	_check("%s: unlocked: playable, previewed in 3D as its boss model" % id, cs.is_unlocked(k) and rm != null and rm._boss != null and rm.visible, "")
	cs.queue_free()
	await _frames(2)


# ------------------------------------------------------------------ the Pharaoh

func _pharaoh() -> void:
	var kit: KitPharaoh = ab.roster.part
	# Scarab Bolts: seek their target, hit, burrow in
	_clear()
	var a := _spawn(EnemyManager.TANK, 9.0, 0.5, 50.0)
	await _secs(0.05)
	var h0 := em.hp[a]
	ws.fire("scarab", "orb", 1.0)
	var kinds := 0
	for i in ws.pc:
		kinds += 1 if WeaponSystem.P_KINDS[ws.p_style[i]] == "scarab" else 0
	_check("Scarab Bolts: golden scarabs that seek their target", kinds >= 1 and ws.p_target[0] != 0, "%d" % kinds)
	await _secs(1.0)
	var hit: float = h0 - em.hp[a]
	var want := 14.0   # (the test fires it with a 1.0 damage multiplier)
	_check("...hit for about 14 and burrow in (2%% max HP/s for 2 s)", ws.scarab_hits >= 1 and hit >= want * 0.95 and em.pct_t[a] > 0.0 and is_equal_approx(em.pct_f[a], WeaponSystem.SCARAB_FRAC), "-%.1f" % hit)
	# Forged: they seek on to one more enemy
	_clear()
	_spawn(EnemyManager.TANK, 8.0, 0.0, 50.0)
	_spawn(EnemyManager.TANK, 10.0, 0.3, 50.0)
	await _secs(0.05)
	ws.special["scarab"] = true
	ws.fire("scarab", "orb", 1.0)
	await _secs(1.6)
	_check("forged Scarab Bolts: a scarab seeks on to a 2nd enemy", _hurt_count() == 2, "%d hurt" % _hurt_count())
	ws.special.erase("scarab")
	# Curse of the Sands
	_clear()
	var lane := []
	for n in 4:
		lane.append(em.uid[_spawn(EnemyManager.TANK, 4.0 + n * 4.0, 0.0, 50.0)])
	var off_u := em.uid[_spawn(EnemyManager.TANK, 8.0, PI * 0.5, 50.0)]
	for i in em.count:
		em.slow(i, 0.001, 30.0)
	await _secs(0.05)
	var dmg: float = main.stats.value("damage")
	_cast(0)
	await _secs(0.45)
	var lane_ok := true
	for u in lane:
		var i := em.index_of(u)
		lane_ok = lane_ok and i >= 0 and em.hp_max[i] - em.hp[i] >= KitPharaoh.CURSE_DAMAGE * dmg * AM * kit.pw(0) * 0.99 and em.curse_t[i] > 5.0 and em.pct_t[i] > 3.0
	_check("Curse of the Sands: a 22 m beam where you aim: 60, cursed 6 s, withering", lane_ok and kit.curse_hits == 4, "%d hits" % kit.curse_hits)
	var oi := em.index_of(off_u)
	_check("...only down the lane", oi >= 0 and em.hp[oi] == em.hp_max[oi], "")
	var li := em.index_of(lane[0])
	_check("...and slowed 50%", em.slow_t[li] > 3.0 and em.slow_f[li] <= 0.5, "%.2f" % em.slow_f[li])
	# Sandstorm
	_clear()
	for n in 6:
		_spawn(EnemyManager.TANK, 5.0, TAU * n / 6.0, 50.0)
	var far := em.uid[_spawn(EnemyManager.TANK, 14.0, 0.0, 50.0)]
	await _secs(0.05)
	_cast(1)
	await _secs(1.05)
	var storm_ok := 0
	for i in em.count:
		if em.uid[i] != far and em.hp[i] < em.hp_max[i] and em.slow_t[i] > 0.0 and em.slow_f[i] <= 0.5:
			storm_ok += 1
	_check("Sandstorm: a storm whirls round him: enemies in it slowed 50% and scoured", kit.active("storm") and storm_ok == 6, "%d" % storm_ok)
	_check("...and blinded (wandering, harmless) when it catches them", kit.blinded == 6, "%d" % kit.blinded)
	var fi := em.index_of(far)
	_check("...out to 8 m", fi >= 0 and em.hp[fi] == em.hp_max[fi], "")
	var per := 0.0
	for i in em.count:
		if em.uid[i] != far:
			per = em.hp_max[i] - em.hp[i]
			break
	_check("...20 a second", absf(per - KitPharaoh.STORM_DPS * dmg * AM * kit.pw(1) * 1.0) < KitPharaoh.STORM_DPS * dmg * AM * kit.pw(1) * 0.55, "%.0f in ~1 s" % per)
	await _secs(KitPharaoh.STORM_TIME)
	_check("...for 8 s", not kit.active("storm"), "")
	# Wrath of the Sands
	_clear()
	for n in 8:
		_spawn(EnemyManager.TANK, randf_range(4.0, 20.0), randf() * TAU, 100.0)
	for n in 3:
		_spawn(EnemyManager.GRUNT, 6.0, n, 0.05)
	var out_u := em.uid[_spawn(EnemyManager.TANK, 29.0, 0.0, 100.0)]
	em.slow(em.index_of(out_u), 0.001, 30.0)   # it stays out of reach
	await _secs(0.05)
	_cast(2)
	await _secs(0.5)
	_check("Wrath of the Sands: the Sphinx's head rises behind him", kit.active("wrath") and is_instance_valid(kit._wrath_head), "")
	await _secs(1.2)
	var wrath_ok := 0
	for i in em.count:
		if not em.dead[i] and em.uid[i] != out_u and em.hp_max[i] - em.hp[i] >= KitPharaoh.WRATH_DAMAGE * dmg * AM * kit.pw(2) * 0.99:
			wrath_ok += 1
	_check("...its storm tears through every enemy within 25 m: 300", wrath_ok == 8, "%d" % wrath_ok)
	var o2 := em.index_of(out_u)
	_check("...not beyond", o2 >= 0 and em.hp[o2] == em.hp_max[o2], "")
	await _secs(0.5)
	_check("...and the fallen rise as mummies that fight for him", kit.mummies.count() == KitPharaoh.WRATH_MUMMIES and kit._wrath_dead.size() >= 3, "%d mummies, %d fallen" % [kit.mummies.count(), kit._wrath_dead.size()])
	var t := _spawn(EnemyManager.TANK, 3.0, 1.0, 100.0)
	em.slow(t, 0.001, 30.0)
	var tu := em.uid[t]
	await _secs(2.5)
	t = em.index_of(tu)
	_check("...hitting enemies", t >= 0 and em.hp[t] < em.hp_max[t], "")
	await _secs(KitPharaoh.WRATH_MUMMY_TIME)
	_check("...for 12 s", kit.mummies.count() == 0 and not kit.active("wrath"), "%d" % kit.mummies.count())


# ------------------------------------------------------------------ the Necromancer

func _necromancer() -> void:
	var kit: KitNecromancer = ab.roster.part
	var dmg: float = main.stats.value("damage")
	# Soul Bolts: pierce 2 more enemies
	_clear()
	var line := []
	for n in 4:
		line.append(em.uid[_spawn(EnemyManager.TANK, 5.0 + n * 1.2, 0.0, 50.0)])
	for i in em.count:
		em.slow(i, 0.001, 30.0)
	await _secs(0.05)
	ws.fire("soul", "orb", 1.0)
	var kinds := 0
	for i in ws.pc:
		kinds += 1 if WeaponSystem.P_KINDS[ws.p_style[i]] == "soul" else 0
	_check("Soul Bolts: green skull bolts", kinds >= 1, "%d" % kinds)
	await _secs(1.2)
	var hurt := 0
	var hit := 0.0
	for u in line:
		var i := em.index_of(u)
		if i >= 0 and em.hp[i] < em.hp_max[i]:
			hurt += 1
			hit = em.hp_max[i] - em.hp[i]
	_check("...that hit for 20 and pierce 2 more enemies (3 in a row)", hurt == 3 and ws.soul_hits == 3 and absf(hit - 20.0) < 2.0, "%d hurt, -%.1f, %d hits" % [hurt, hit, ws.soul_hits])
	# Forged: each hit heals
	_clear()
	for n in 3:
		_spawn(EnemyManager.TANK, 5.0 + n * 1.2, 0.0, 50.0)
	await _secs(0.05)
	player.hp = player.max_hp * 0.5
	var hp0 := player.hp
	ws.special["soul"] = true
	ws.set("_soul_heal_t", -10.0)
	ws.fire("soul", "orb", 1.0)
	await _secs(1.2)
	_check("forged Soul Bolts: each hit heals 1 HP", player.hp >= hp0 + 2.5, "%.1f -> %.1f" % [hp0, player.hp])
	ws.special.erase("soul")
	player.hp = player.max_hp
	# Raise the Dead
	_clear()
	for n in 5:
		_spawn(EnemyManager.GRUNT, 6.0, n, 0.05)
	await _secs(0.05)
	for i in em.count:
		em.damage(i, 1.0e6)
	await _secs(0.3)
	var t := _spawn(EnemyManager.TANK, 4.0, 0.0, 100.0)
	em.slow(t, 0.001, 30.0)
	var tu := em.uid[t]
	_cast(0)
	await _secs(0.1)
	_check("Raise the Dead: 8 of the dead rise and fight for him", kit.dead.count() == KitNecromancer.RAISE_COUNT and kit.active("dead"), "%d" % kit.dead.count())
	await _secs(3.0)
	t = em.index_of(tu)
	var lost := em.hp_max[t] - em.hp[t] if t >= 0 else 0.0
	_check("...each hitting for 18", t >= 0 and lost >= KitNecromancer.RAISE_HIT * dmg * AM * kit.pw(0) * 0.99, "-%.1f" % lost)
	await _secs(KitNecromancer.RAISE_TIME - 2.9 + 0.6)
	_check("...for 12 s", kit.dead.count() == 0, "%d" % kit.dead.count())
	# Soul Drain
	_clear()
	var beam := []
	for n in 3:
		beam.append(em.uid[_spawn(EnemyManager.TANK, 4.0 + n * 4.0, 0.0, 50.0)])
	var side_u := em.uid[_spawn(EnemyManager.TANK, 6.0, PI * 0.5, 50.0)]
	for i in em.count:
		em.slow(i, 0.001, 30.0)
	await _secs(0.05)
	player.hp = player.max_hp * 0.5
	var hp1 := player.hp
	_cast(1)
	await _secs(1.02)
	var body := (player.model as RosterHero).boss as NecromancerBody
	_check("Soul Drain: a beam from his staff (levelled)", kit.active("drain") and is_instance_valid(kit._drain_beam) and body.model._pose == "channel" and body.drawn, body.model._pose)
	var drained := 0
	var dps := 0.0
	for u in beam:
		var i := em.index_of(u)
		if i >= 0 and em.hp[i] < em.hp_max[i]:
			drained += 1
			dps = em.hp_max[i] - em.hp[i]
	_check("...drains everything in a 16 m line: 40 a second", drained == 3 and absf(dps - KitNecromancer.DRAIN_DPS * dmg * AM * kit.pw(1)) < KitNecromancer.DRAIN_DPS * dmg * AM * kit.pw(1) * 0.3, "%d, -%.0f" % [drained, dps])
	var si := em.index_of(side_u)
	_check("...only along the beam", si >= 0 and em.hp[si] == em.hp_max[si], "")
	_check("...and heals him", player.hp > hp1 and kit.drain_healed > 0.0 and player.hp - hp1 <= player.max_hp * KitNecromancer.DRAIN_HEAL_CAP * 1.1, "%.1f -> %.1f" % [hp1, player.hp])
	await _secs(KitNecromancer.DRAIN_TIME - 0.9)
	_check("...for 4 s", not kit.active("drain"), "")
	player.hp = player.max_hp
	# The Graves Open
	_clear()
	for n in 10:
		_spawn(EnemyManager.TANK, randf_range(4.0, 22.0), randf() * TAU, 100.0)
	var out_u := em.uid[_spawn(EnemyManager.TANK, 30.0, 0.0, 100.0)]
	await _secs(0.05)
	_cast(2)
	await _secs(KitNecromancer.GRAVES_DELAY + 0.1)
	var graves_ok := 0
	var rooted := 0
	for i in em.count:
		if not em.dead[i] and em.uid[i] != out_u:
			if em.hp_max[i] - em.hp[i] >= KitNecromancer.GRAVES_DAMAGE * dmg * AM * kit.pw(2) * 0.99:
				graves_ok += 1
			if em.stun_t[i] > 1.0:
				rooted += 1
	_check("The Graves Open: bone spikes burst under every enemy within 25 m: 300", graves_ok == 10 and kit._spikes.size() >= 10, "%d, %d spikes" % [graves_ok, kit._spikes.size()])
	_check("...rooting them", rooted == 10, "%d" % rooted)
	var o := em.index_of(out_u)
	_check("...not beyond", o >= 0 and em.hp[o] == em.hp_max[o], "")
	await _secs(KitNecromancer.GRAVES_RISE - KitNecromancer.GRAVES_DELAY + 0.1)
	_check("...then 16 of the dead rise and fight for him", kit.dead.count() == KitNecromancer.GRAVES_DEAD, "%d" % kit.dead.count())
	await _secs(KitNecromancer.GRAVES_DEAD_TIME + 0.9)
	_check("...for 10 s", kit.dead.count() == 0, "%d" % kit.dead.count())


# ------------------------------------------------------------------ Singe

func _singe() -> void:
	var kit: KitSinge = ab.roster.part
	var dmg: float = main.stats.value("damage")
	# Fireflick: embers in pairs that set what they hit burning
	_clear()
	var tg := _spawn(EnemyManager.TANK, 7.0, 0.0, 50.0)
	em.slow(tg, 0.001, 30.0)
	await _secs(0.05)
	var h0 := em.hp[tg]
	ws.fire("ember", "orb", 1.0)
	var kinds := 0
	for i in ws.pc:
		kinds += 1 if WeaponSystem.P_KINDS[ws.p_style[i]] == "ember" else 0
	_check("Fireflick: embers flicked in pairs", kinds == 2, "%d" % kinds)
	await _secs(0.6)
	var hit := h0 - em.hp[tg]
	_check("...8 each, and they set what they hit burning (3% max HP/s for 2 s)", ws.ember_hits >= 1 and hit >= 8.0 * 0.95 and is_equal_approx(em.pct_f[tg], WeaponSystem.EMBER_FRAC) and em.pct_t[tg] > 1.0, "-%.1f, %d hits" % [hit, ws.ember_hits])
	_clear()
	tg = _spawn(EnemyManager.TANK, 7.0, 0.0, 50.0)
	em.slow(tg, 0.001, 30.0)
	await _secs(0.05)
	ws.special["ember"] = true
	ws.fire("ember", "orb", 1.0)
	await _secs(0.6)
	_check("forged Fireflick: burns deal double", is_equal_approx(em.pct_f[tg], WeaponSystem.EMBER_FRAC * Forge.EMBER_BURN), "%.3f" % em.pct_f[tg])
	ws.special.erase("ember")
	# Scorch Trail
	_clear()
	var spd0: float = main.stats.value("move_speed")
	_cast(0)
	_check("Scorch Trail: +30% move speed", is_equal_approx(main.stats.value("move_speed"), spd0 * KitSinge.TRAIL_SPEED) and kit.active("trail"), "%.2f" % main.stats.value("move_speed"))
	var start := player.global_position
	for f in 60:   # run along, leaving scorch marks
		player.global_position = start + Vector3(f * 0.1, 0, 0)
		player.global_position.y = main.water.ground_height(player.global_position.x, player.global_position.z) + 0.05
		await get_tree().physics_frame
	_check("...leaving scorch marks behind him", kit.trail_marks >= 5, "%d marks" % kit.trail_marks)
	var on := _spawn_at(EnemyManager.TANK, kit._marks[2]["pos"], 50.0)
	em.slow(on, 0.001, 30.0)
	var onu := em.uid[on]
	await _secs(0.4)
	on = em.index_of(onu)
	_check("...enemies on them take 15 and burn (5% max HP/s)", on >= 0 and kit.trail_hits >= 1 and em.hp_max[on] - em.hp[on] >= KitSinge.TRAIL_DAMAGE * dmg * AM * kit.pw(0) * 0.99 and is_equal_approx(em.pct_f[on], KitSinge.TRAIL_BURN), "%d hits" % kit.trail_hits)
	await _secs(KitSinge.TRAIL_TIME)
	_check("...for 6 s", not kit.active("trail") and is_equal_approx(main.stats.value("move_speed"), spd0), "%.2f" % main.stats.value("move_speed"))
	await _secs(KitSinge.TRAIL_LIFE)
	_check("...the marks burn out after 4 s", kit._marks.is_empty(), "%d" % kit._marks.size())
	# Lava Cannonball
	_clear()
	var body := (player.model as RosterHero).boss as SingeBody
	var from := player.global_position
	_cast(1)
	var to: Vector3 = kit._ball_to
	for n in 6:
		_spawn_at(EnemyManager.TANK, to + Vector3(cos(n), 0, sin(n)) * 3.0, 50.0)
	await _secs(0.3)
	player.god_mode = false
	var hpa := player.hp
	var got := player.hurt(50.0)
	player.god_mode = true
	_check("Lava Cannonball: curled into a ball of coals, untouchable in the air", kit.active("ball") and body.curled and not got and player.hp == hpa, "")
	await _secs(0.65)
	_check("...dives where you aim (up to 18 m)", player.global_position.distance_to(to) < 1.0 and from.distance_to(to) <= KitSinge.BALL_RANGE + 0.5 and not body.curled, "%.1f m" % from.distance_to(to))
	var crashed := 0
	for i in em.count:
		if not em.dead[i] and em.hp_max[i] - em.hp[i] >= KitSinge.BALL_DAMAGE * dmg * AM * kit.pw(1) * 0.99:
			crashed += 1
	_check("...crashing down for 150 within 6 m", crashed == 6 and kit.ball_hits == 6, "%d" % crashed)
	await _secs(0.6)
	_check("...leaving a lava pool that burns (4% max HP/s)", kit.active("pool") and kit.pool_hits > 0, "%d" % kit.pool_hits)
	await _secs(KitSinge.POOL_TIME)
	_check("...for 3 s", not kit.active("pool"), "")
	# Caldera Eruption
	_clear()
	for n in 12:
		var e := _spawn(EnemyManager.TANK, randf_range(4.0, 18.0), randf() * TAU, 200.0)
		em.slow(e, 0.001, 30.0)
	await _secs(0.05)
	_cast(2)
	await _secs(1.0)
	_check("Caldera Eruption: the ground cracks open and lava bombs fly", kit.active("eruption") and (kit._bombs.size() > 0 or kit.bombs_landed > 0), "")
	await _secs(KitSinge.ERUPT_TIME + 0.5)
	_check("...36 bombs in 6 s", kit.bombs_landed == KitSinge.ERUPT_BOMBS and not kit.active("eruption"), "%d" % kit.bombs_landed)
	var bombed := 0
	for i in em.count:
		if not em.dead[i] and em.hp_max[i] - em.hp[i] >= KitSinge.BOMB_DAMAGE * dmg * AM * kit.pw(2) * 0.99:
			bombed += 1
	_check("...each 110 within 3.5 m plus a burn: most of the horde gets hit", bombed >= 8 and kit.bomb_hits >= 15, "%d bombed, %d hits" % [bombed, kit.bomb_hits])


# ------------------------------------------------------------------ cooldowns, ultimates

## Casting starts the ability's cooldown, and it can't be cast again until it's over.
func _cooldowns(id: String) -> void:
	_clear()
	for i in 3:
		ab.cooldown[i] = 0.0
	ab.level = 10
	var ok := true
	var info := ""
	for i in 2:
		var cast_ok := ab.try_cast(i)
		var cd: float = ab.cooldown[i]
		var again := ab.try_cast(i)
		ok = ok and cast_ok and not again and cd > float(COOLDOWNS[id][i]) * 0.5 and cd <= float(COOLDOWNS[id][i]) + 0.01
		info += "%.1f " % cd
		await _secs(0.3)
	_check("%s: casting starts each cooldown (%s s at level 10), no recast meanwhile" % [id, str(COOLDOWNS[id])], ok, info)
	await _secs(4.0)


func _ult_burns(id: String) -> void:
	_clear()
	var tree: Node3D = null
	for t in get_tree().get_nodes_in_group(TreeFire.GROUP):
		var tb := t as Node3D
		if not tb.has_meta("burn_state") and float(tb.get_meta("reach")) < 2.0 and (tree == null or tb.global_position.length() < tree.global_position.length()):
			tree = tb
	var away := Vector3(tree.global_position.x, 0, tree.global_position.z).normalized()
	var at := tree.global_position - away * 4.0
	player.global_position = Vector3(at.x, main.water.ground_height(at.x, at.z) + 0.3, at.z)
	player.velocity = Vector3.ZERO
	await _secs(0.1)
	_cast(2)
	await _secs(0.1)
	_check("%s: the ultimate sets the trees around it ablaze" % id, TreeFire.state_of(tree) == "burning", TreeFire.state_of(tree))
	await _secs(3.0)


# ------------------------------------------------------------------ helpers

func _load(id: String) -> void:
	get_tree().paused = false
	Settings.selected_map = "swamp"
	Settings.selected_character = id
	Settings.game_mode = "classic"
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	await get_tree().scene_changed
	main = get_tree().current_scene
	for f in 60 * 15:
		await get_tree().physics_frame
		if not main.intro:
			break
	em = main.enemies
	player = main.player
	ab = main.abilities
	ws = main.weapons
	player.god_mode = true
	main.run_time = 1.0
	main.set("_spawn_budget", -1.0e9)
	ab.level = 10
	await _secs(0.2)


func _cast(i: int) -> void:
	ab.cooldown[i] = 0.0
	ab.level = 10
	if not ab.try_cast(i):
		_check("cast %d" % i, false, "try_cast failed")


func _clear() -> void:
	for i in em.count:
		em.dead[i] = 1
		em.ally_t[i] = 0.0
		em.frog_t[i] = 0.0
	em.count = 0
	em.set("_dead_count", 0)
	em.lost = false
	ws.pc = 0
	ws.combo.clear()
	ws.orb_t = 999.0
	main.xp_next = 1.0e12
	main.set("_spawn_budget", -1.0e9)


func _spawn(t: int, dist: float, ang: float, hpm: float) -> int:
	var fwd := Vector3(-sin(player.cam_yaw), 0, -cos(player.cam_yaw))
	var right := Vector3(cos(player.cam_yaw), 0, -sin(player.cam_yaw))
	var p := player.global_position + (fwd * cos(ang) + right * sin(ang)) * dist
	return _spawn_at(t, p, hpm)


func _spawn_at(t: int, p: Vector3, hpm: float) -> int:
	var i := em.spawn(t, p, hpm)
	em.vel[i] = Vector3.ZERO
	em.slow(i, 0.001, 0.2)
	em.slow_t[i] = 0.0
	em.tick(0.0, player.global_position)
	return i


func _hurt_count() -> int:
	var n := 0
	for i in em.count:
		if not em.dead[i] and em.hp[i] < em.hp_max[i]:
			n += 1
	return n


func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		if m.material_override is ShaderMaterial and m.get_parent().name.contains("hair"):
			continue
		var a: AABB = m.global_transform * m.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


func _frames(n: int) -> void:
	for f in n:
		await get_tree().process_frame


func _secs(s: float) -> void:
	for f in int(s * 60):
		await get_tree().physics_frame


func _finish() -> void:
	get_tree().paused = false
	print("TEST %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s  %s  [%s]" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		fails += 1
