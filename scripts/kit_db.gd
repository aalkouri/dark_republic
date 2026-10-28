class_name KitDB
extends RefCounted
## Character kits from data/abilities.json: each character's starting weapon and three
## abilities (key 1 from the start, key 2 at run level 5, key 3 = ultimate at level 10).
## Only the Fire Wizard's kit is implemented in gameplay so far (abilities.gd); the others are
## designs shown on the character select screen until each character is built.

const PATH := "res://data/abilities.json"
const KEYS := ["1", "2", "3"]
const UNLOCK_LEVELS := [1, 5, 10]
const HOT := "[color=#ffb347]%s[/color]"

static var _kits: Dictionary = {}


static func kits() -> Dictionary:
	if _kits.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_kits = d.get("kits", {})
	return _kits


static func has_kit(id: String) -> bool:
	return kits().has(id)


static func kit(id: String) -> Dictionary:
	return kits().get(id, {})


static func ability(id: String, i: int) -> Dictionary:
	var a: Array = kit(id).get("abilities", [])
	return a[i] if i >= 0 and i < a.size() else {}


static func is_ult(i: int) -> bool:
	return i == 2


## "Weapon: Frost Shards - piercing icicles..." for the preview panel.
static func weapon_line(id: String) -> String:
	var w: Dictionary = kit(id).get("weapon", {})
	if w.is_empty():
		return ""
	var s := "Weapon: %s" % w["name"]
	if w.has("desc"):
		s += "  -  %s" % w["desc"]
	return s


## {braces} in the JSON mark numbers; they're highlighted like the Fire Wizard's tooltips.
static func highlight(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		var open := s.find("{", i)
		if open < 0:
			out += s.substr(i)
			break
		var close := s.find("}", open)
		if close < 0:
			out += s.substr(i)
			break
		out += s.substr(i, open - i) + HOT % s.substr(open + 1, close - open - 1)
		i = close + 1
	return out


## Tooltip lines in the same layout as Abilities.describe_lines: title, key and cooldown, a
## one-line summary and the bulleted numbers.
static func describe_lines(id: String, i: int) -> Array[String]:
	var a := ability(id, i)
	var lines: Array[String] = []
	if a.is_empty():
		return lines
	var title := "[font_size=22][b]%s[/b][/font_size]" % a["name"]
	if is_ult(i):
		title += "  [color=#ffd23f][ULTIMATE][/color]"
	lines.append(title)
	lines.append("[color=#aaaaaa]Key %s  ·  Cooldown %s[/color]" % [KEYS[i], fmt_cd(float(a.get("cooldown", 0)))])
	lines.append("")
	if a.has("text"):
		lines.append(str(a["text"]))
	for l in a.get("lines", []):
		lines.append("• " + highlight(str(l)))
	return lines


static func fmt_cd(secs: float) -> String:
	if secs >= 60.0:
		var m := int(secs) / 60
		var sec := int(ceil(secs)) % 60
		return "%d min" % m if sec == 0 else "%d:%02d" % [m, sec]
	return "%d s" % ceili(secs)
