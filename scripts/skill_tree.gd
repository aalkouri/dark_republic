class_name SkillTree
extends RefCounted
## Per-character skill trees: three categories (Defense, Offense, Special), each two rows of
## three skills. Each skill costs one skill point (a character earns one per level, max 10).
## Row 2 needs at least one row-1 skill of the same category; Special unlocks at level 5.
## Learned skills are saved (Wallet) and applied to the run's stats at the start.
##
## The Fire Wizard has a hand-made tree; every other character gets its own fixed "random" draw
## from the shared pool (seeded by the character id, so it never changes between sessions).

const CATEGORIES := ["Defense", "Offense", "Special"]
const CATEGORY_COLORS := [Color(0.45, 0.72, 1.0), Color(1.0, 0.45, 0.25), Color(0.78, 0.5, 1.0)]
const POINT_COST := 1
const SPECIAL_LEVEL := 5      # the Special column unlocks at this level
const PER_ROW := 3

# Skill: id, name, desc, icon, effects [[stat, op, amount], ...]
# Pools per category: [tier 1 skills, tier 2 skills]
const POOL := {
	"Defense": [
		[
			{"id": "tough", "name": "Tough Hide", "desc": "+20 max HP", "icon": "heart", "fx": [["max_hp", "flat", 20.0]]},
			{"id": "plating", "name": "Plating", "desc": "+4 armor", "icon": "shield", "fx": [["armor", "flat", 4.0]]},
			{"id": "mend", "name": "Mending", "desc": "Regenerate 0.6 HP/s", "icon": "cross", "fx": [["regen", "flat", 0.6]]},
			{"id": "padding", "name": "Padding", "desc": "+3 armor, +10 max HP", "icon": "shield", "fx": [["armor", "flat", 3.0], ["max_hp", "flat", 10.0]]},
			{"id": "guard", "name": "Guarded Start", "desc": "Start each run with a shield worth 15% max HP", "icon": "bubble", "fx": [["start_shield", "flat", 0.15]]},
		],
		[
			{"id": "giant", "name": "Giant's Heart", "desc": "+25% max HP", "icon": "heart", "fx": [["max_hp", "add", 0.25]]},
			{"id": "bastion", "name": "Bastion", "desc": "+10 armor", "icon": "shield", "fx": [["armor", "flat", 10.0]]},
			{"id": "troll_blood", "name": "Troll Blood", "desc": "Regenerate 1.5 HP/s", "icon": "cross", "fx": [["regen", "flat", 1.5]]},
			{"id": "aegis", "name": "Aegis", "desc": "Start each run with a shield worth 35% max HP", "icon": "bubble", "fx": [["start_shield", "flat", 0.35]]},
			{"id": "iron_will", "name": "Iron Will", "desc": "+15% max HP, +5 armor", "icon": "shield", "fx": [["max_hp", "add", 0.15], ["armor", "flat", 5.0]]},
		],
	],
	"Offense": [
		[
			{"id": "sharpen", "name": "Sharpen", "desc": "+10% damage", "icon": "blade", "fx": [["damage", "add", 0.1]]},
			{"id": "quick", "name": "Quick Hands", "desc": "+10% attack speed", "icon": "clock", "fx": [["attack_speed", "add", 0.1]]},
			{"id": "heavy", "name": "Heavy Hitter", "desc": "+4 projectile damage", "icon": "orb", "fx": [["orb_damage", "flat", 4.0]]},
			{"id": "reach", "name": "Wide Swings", "desc": "+15% area", "icon": "burst", "fx": [["area", "add", 0.15]]},
			{"id": "velocity", "name": "Velocity", "desc": "+20% projectile speed", "icon": "arrow", "fx": [["projectile_speed", "add", 0.2]]},
		],
		[
			{"id": "volley", "name": "Volley", "desc": "+1 projectile", "icon": "burst", "fx": [["projectile_count", "flat", 1.0]]},
			{"id": "pierce", "name": "Piercing", "desc": "Projectiles pierce 1 more goblin", "icon": "arrow", "fx": [["orb_pierce", "flat", 1.0]]},
			{"id": "brutal", "name": "Brutality", "desc": "+25% damage", "icon": "blade", "fx": [["damage", "add", 0.25]]},
			{"id": "frenzy", "name": "Frenzy", "desc": "+25% attack speed", "icon": "clock", "fx": [["attack_speed", "add", 0.25]]},
			{"id": "colossal", "name": "Colossal", "desc": "+35% area", "icon": "burst", "fx": [["area", "add", 0.35]]},
		],
	],
	"Special": [
		[
			{"id": "fleet", "name": "Fleet Feet", "desc": "+10% move speed", "icon": "boot", "fx": [["move_speed", "add", 0.1]]},
			{"id": "spring", "name": "Spring Step", "desc": "+1 air jump", "icon": "feather", "fx": [["extra_jumps", "flat", 1.0]]},
			{"id": "greed", "name": "Greed", "desc": "+15% coins from runs", "icon": "coin", "fx": [["coin_gain", "add", 0.15]]},
			{"id": "magnet", "name": "Magnetism", "desc": "+50% pickup range", "icon": "magnet", "fx": [["pickup_range", "add", 0.5]]},
			{"id": "scholar", "name": "Scholar", "desc": "+15% XP", "icon": "book", "fx": [["xp_gain", "add", 0.15]]},
		],
		[
			{"id": "haste", "name": "Time Warp", "desc": "Abilities recharge 20% faster", "icon": "clock", "fx": [["ability_cdr", "mult", 0.8]]},
			{"id": "fortune", "name": "Fortune", "desc": "+2 luck (more epic goblins and drops)", "icon": "clover", "fx": [["luck", "flat", 2.0]]},
			{"id": "midas", "name": "Midas Touch", "desc": "+40% coins from runs", "icon": "coin", "fx": [["coin_gain", "add", 0.4]]},
			{"id": "sprinter", "name": "Sprinter", "desc": "+20% move speed", "icon": "boot", "fx": [["move_speed", "add", 0.2]]},
			{"id": "sage", "name": "Sage", "desc": "+35% XP", "icon": "book", "fx": [["xp_gain", "add", 0.35]]},
		],
	],
}

# The Fire Wizard's own tree (fire-themed names on the same kinds of effects)
const AUTHORED := {
	"fire_wizard": {
		"Defense": [
			[
				{"id": "ember_hide", "name": "Ember Hide", "desc": "+20 max HP", "icon": "heart", "fx": [["max_hp", "flat", 20.0]]},
				{"id": "ashen_ward", "name": "Ashen Ward", "desc": "+4 armor", "icon": "shield", "fx": [["armor", "flat", 4.0]]},
				{"id": "smoulder", "name": "Smoulder Mend", "desc": "Regenerate 0.6 HP/s", "icon": "cross", "fx": [["regen", "flat", 0.6]]},
			],
			[
				{"id": "phoenix_heart", "name": "Phoenix Heart", "desc": "+25% max HP", "icon": "heart", "fx": [["max_hp", "add", 0.25]]},
				{"id": "cinder_shell", "name": "Cinder Shell", "desc": "Start each run with a shield worth 35% max HP", "icon": "bubble", "fx": [["start_shield", "flat", 0.35]]},
				{"id": "hearthfire", "name": "Hearthfire", "desc": "Regenerate 1.5 HP/s", "icon": "cross", "fx": [["regen", "flat", 1.5]]},
			],
		],
		"Offense": [
			[
				{"id": "kindling", "name": "Kindling", "desc": "+10% damage", "icon": "flame", "fx": [["damage", "add", 0.1]]},
				{"id": "quickfire", "name": "Quickfire", "desc": "+10% attack speed", "icon": "clock", "fx": [["attack_speed", "add", 0.1]]},
				{"id": "hot_orbs", "name": "White-Hot Orbs", "desc": "+4 fireball damage", "icon": "orb", "fx": [["orb_damage", "flat", 4.0]]},
			],
			[
				{"id": "wildfire", "name": "Wildfire", "desc": "+1 fireball", "icon": "burst", "fx": [["projectile_count", "flat", 1.0]]},
				{"id": "searing", "name": "Searing Pierce", "desc": "Fireballs pierce 1 more goblin", "icon": "arrow", "fx": [["orb_pierce", "flat", 1.0]]},
				{"id": "inferno_mastery", "name": "Pyromastery", "desc": "+25% damage", "icon": "flame", "fx": [["damage", "add", 0.25]]},
			],
		],
		"Special": [
			[
				{"id": "fleet", "name": "Fleet Feet", "desc": "+10% move speed", "icon": "boot", "fx": [["move_speed", "add", 0.1]]},
				{"id": "updraft", "name": "Updraft", "desc": "+1 air jump", "icon": "feather", "fx": [["extra_jumps", "flat", 1.0]]},
				{"id": "gold_sense", "name": "Gold Sense", "desc": "+15% coins from runs", "icon": "coin", "fx": [["coin_gain", "add", 0.15]]},
			],
			[
				{"id": "time_warp", "name": "Time Warp", "desc": "Abilities recharge 20% faster", "icon": "clock", "fx": [["ability_cdr", "mult", 0.8]]},
				{"id": "ember_magnet", "name": "Ember Pull", "desc": "+50% pickup range", "icon": "magnet", "fx": [["pickup_range", "add", 0.5]]},
				{"id": "fortunes_flame", "name": "Fortune's Flame", "desc": "+2 luck (more epic goblins and drops)", "icon": "clover", "fx": [["luck", "flat", 2.0]]},
			],
		],
	},
}


## The character's tree: {category: [[row 1 skills], [row 2 skills]]}, 3 skills per row.
static func tree_for(char_id: String) -> Dictionary:
	if AUTHORED.has(char_id):
		return AUTHORED[char_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(char_id)
	var out := {}
	for cat in CATEGORIES:
		var rows := []
		for tier in 2:
			var pool: Array = (POOL[cat][tier] as Array).duplicate()
			var picks := []
			for k in PER_ROW:
				picks.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
			rows.append(picks)
		out[cat] = rows
	return out


static func find(char_id: String, skill_id: String) -> Dictionary:
	var tree := tree_for(char_id)
	for cat in CATEGORIES:
		for tier in 2:
			for s in tree[cat][tier]:
				if s["id"] == skill_id:
					return {"skill": s, "category": cat, "tier": tier}
	return {}


static func cost(_tier: int) -> int:
	return POINT_COST


static func category_locked(char_id: String, category: String) -> bool:
	return category == "Special" and Wallet.char_level(char_id) < SPECIAL_LEVEL


## Can `skill_id` be learned now? Returns "" if so, else the reason.
static func blocked_reason(char_id: String, skill_id: String) -> String:
	var info := find(char_id, skill_id)
	if info.is_empty():
		return "Unknown skill"
	if Wallet.has_skill(char_id, skill_id):
		return "Learned"
	if category_locked(char_id, info["category"]):
		return "Unlocks at level %d" % SPECIAL_LEVEL
	if info["tier"] == 1:
		var any := false
		for s in tree_for(char_id)[info["category"]][0]:
			if Wallet.has_skill(char_id, s["id"]):
				any = true
		if not any:
			return "Learn a %s skill from the first row first" % String(info["category"]).to_lower()
	if Wallet.skill_points_free(char_id) < POINT_COST:
		return "No skill points (earn one each level)"
	return ""


## Spend a skill point and learn the skill. Returns true on success.
static func learn(char_id: String, skill_id: String) -> bool:
	if blocked_reason(char_id, skill_id) != "":
		return false
	Wallet.learn_skill(char_id, skill_id)
	return true


## Apply a character's learned skills to a run's stats.
static func apply(char_id: String, stats: Stats) -> Array:
	var applied := []
	for skill_id in Wallet.skills_of(char_id):
		var info := find(char_id, skill_id)
		if info.is_empty():
			continue
		for e in info["skill"]["fx"]:
			if stats.has_stat(e[0]):
				stats.apply(e[0], e[1], e[2])
		applied.append(skill_id)
	return applied
