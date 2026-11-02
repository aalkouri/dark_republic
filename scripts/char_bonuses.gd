extends RefCounted
## Each character's three starting stat bonuses ("bonuses" in data/characters.json), applied at
## run start after the skill tree, and shown on the character select screen with a bar whose
## colour is the bonus's size: red small, yellow medium, green big.
##
## A bonus is {"stat", "value", "mode"}:
##   "mult" -> the stat is multiplied by value          (move speed x1.2)
##   "set"  -> the stat starts at value instead of base (crit chance 6% instead of 3%)
##   "flat" -> +value on the base                       (armor +5, for stats that start at 0)
##
## Not a class_name on purpose (no global class cache rebuild needed): preload it.

const CHARACTERS_PATH := "res://data/characters.json"
const UPGRADES_PATH := "res://data/upgrades.json"

## Same base values as main.gd's BASE_STATS (the select screen has no run to ask).
const BASE := {
	"max_hp": 100.0, "regen": 0.0, "armor": 0.0, "move_speed": 8.0, "damage": 1.0,
	"attack_speed": 1.0, "area": 1.0, "projectile_speed": 1.0, "projectile_count": 0.0,
	"pickup_range": 4.0, "xp_gain": 1.0, "luck": 0.0, "extra_jumps": 0.0, "jump_height": 1.0,
	"crit_chance": 0.03, "crit_damage": 1.5, "coin_gain": 1.0, "ability_cdr": 1.0,
}
## Stats that start at 0 have no ratio, so a flat bonus is sized against this much of the
## stat: "1 + value / ref" (armor +5 counts like x1.5).
const FLAT_REF := {"armor": 10.0, "regen": 1.0, "luck": 0.25, "extra_jumps": 1.5, "projectile_count": 2.0}
## Lower is better: a multiplier under 1 is the boost (ability cooldown x0.8 = 20% faster).
const LOWER_IS_BETTER := ["ability_cdr"]
## Names for stats upgrades.json's stat_names doesn't have.
const EXTRA_NAMES := {"jump_height": "Jump Height", "ability_cdr": "Ability Cooldown", "coin_gain": "Coin Gain"}
const PERCENT := ["luck", "crit_chance", "crit_damage"]

## Size tiers by boost ratio: under 1.3x small, 1.3x-1.5x medium, 1.5x and up big.
const MEDIUM_AT := 1.3
const BIG_AT := 1.5
const BAR_FULL_AT := 2.0   # the bar is full at a 2x boost (length is proportional to ratio - 1)
const TIER_COLORS := {
	"small": Color(0.86, 0.22, 0.18), "medium": Color(0.95, 0.8, 0.2), "big": Color(0.35, 0.85, 0.3),
}

static var _by_char := {}
static var _stat_names := {}


static func _load() -> void:
	if not _by_char.is_empty():
		return
	var f := FileAccess.open(CHARACTERS_PATH, FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for c in d.get("characters", []):
				_by_char[str(c.get("id", ""))] = c.get("bonuses", [])
	var u := FileAccess.open(UPGRADES_PATH, FileAccess.READ)
	if u:
		var d2 = JSON.parse_string(u.get_as_text())
		if d2 is Dictionary:
			_stat_names = d2.get("stat_names", {})


## The character's bonuses (an empty array for mystery slots or characters without any).
static func of(char_id: String) -> Array:
	_load()
	return _by_char.get(char_id, [])


## Apply the character's bonuses to a run's stats. Returns how many were applied.
static func apply(char_id: String, stats) -> int:
	var n := 0
	for b in of(char_id):
		var st := str(b.get("stat", ""))
		if not stats.has_stat(st):
			continue
		var v := float(b.get("value", 0.0))
		match str(b.get("mode", "mult")):
			"mult":
				stats.apply(st, "mult", v)
			"set":
				stats.apply(st, "flat", v - stats.base_of(st))
			"flat":
				stats.apply(st, "flat", v)
			_:
				continue
		n += 1
	return n


## How big the boost is, as a multiplier on the base (1.2 = 20% better).
static func ratio(b: Dictionary) -> float:
	var st := str(b.get("stat", ""))
	var v := float(b.get("value", 0.0))
	var base := float(BASE.get(st, 1.0))
	match str(b.get("mode", "mult")):
		"set":
			if base <= 0.0:
				return 1.0 + v / float(FLAT_REF.get(st, 1.0))
			return (base / v) if st in LOWER_IS_BETTER else (v / base)
		"flat":
			if base <= 0.0:
				return 1.0 + v / float(FLAT_REF.get(st, 1.0))
			return (base / (base + v)) if st in LOWER_IS_BETTER else ((base + v) / base)
	return (1.0 / v) if (st in LOWER_IS_BETTER and v > 0.0) else v


static func tier(b: Dictionary) -> String:
	var r := ratio(b)
	if r >= BIG_AT - 0.0001:
		return "big"
	if r >= MEDIUM_AT - 0.0001:
		return "medium"
	return "small"


static func tier_color(t: String) -> Color:
	return TIER_COLORS.get(t, TIER_COLORS["small"])


## Bar fill, 0-1: proportional to the boost, full at 2x.
static func bar_fill(b: Dictionary) -> float:
	return clampf((ratio(b) - 1.0) / (BAR_FULL_AT - 1.0), 0.06, 1.0)


## The stat's display name, translated.
static func stat_name(st: String) -> String:
	_load()
	var nm = _stat_names.get(st, EXTRA_NAMES.get(st, st.capitalize()))
	return I18n.t(str(nm))


## The bonus value as shown: "6%", "x1.2", "+5", "-20%".
static func value_text(b: Dictionary) -> String:
	var st := str(b.get("stat", ""))
	var v := float(b.get("value", 0.0))
	var mode := str(b.get("mode", "mult"))
	if st in LOWER_IS_BETTER:
		var m := v if mode == "mult" else v / float(BASE.get(st, 1.0))
		return "-%d%%" % roundi((1.0 - m) * 100.0)
	if mode == "mult":
		return "x" + _num(v)
	var pct := st in PERCENT
	var shown := ("%s%%" % _num(v * 100.0)) if pct else _num(v)
	return shown if mode == "set" else "+" + shown


static func _num(v: float) -> String:
	return ("%.2f" % v).rstrip("0").rstrip(".")
