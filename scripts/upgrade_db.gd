class_name UpgradeDB
extends RefCounted
## Loads the upgrade table (data/upgrades.json), drafts level-up choices and applies them.
## Adding an upgrade = adding a JSON entry. Upgrades with custom behaviour (on-kill effects etc.)
## read their stats in ItemEffects; everything else is pure stat modifiers.

var uncapped := false   # Unrelenting mode: no max level on any upgrade
var rarities: Array = []
var defs := {}          # id -> definition Dictionary
var order: Array = []   # ids in file order
var levels := {}        # id -> owned level
var banned := {}        # id -> true: banned from level-up drafts for the rest of the run
var stat_names := {}
var percent_stats: Array = []
var rng: RandomNumberGenerator


func _init(path: String, p_rng: RandomNumberGenerator) -> void:
	rng = p_rng
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	assert(data is Dictionary, "UpgradeDB: could not parse %s" % path)
	rarities = data["rarities"]
	stat_names = data.get("stat_names", {})
	percent_stats = data.get("percent_stats", [])
	for d in data["upgrades"]:
		defs[d["id"]] = d
		order.append(d["id"])


func level_of(id: String) -> int:
	return levels.get(id, 0)


func owned_of_kind(kind: String) -> int:
	var c := 0
	for id in levels:
		if defs[id]["kind"] == kind:
			c += 1
	return c


func _eligible(max_weapons: int) -> Array:
	var out := []
	for id in order:
		var d: Dictionary = defs[id]
		var lv := level_of(id)
		if (lv >= int(d["max_level"]) and not uncapped) or banned.has(id):
			continue
		if d["kind"] == "weapon" and lv == 0 and owned_of_kind("weapon") >= max_weapons:
			continue
		if d.has("signature") and lv == 0 and has_signature():
			continue   # one other character's weapon per run: once you have one, the rest stop showing
		out.append(id)
	return out


## True once you've taken another character's (Legendary) weapon this run.
func has_signature() -> bool:
	for id in levels:
		if levels[id] > 0 and defs.has(id) and defs[id].has("signature"):
			return true
	return false


## How likely a card is to come up. A signature weapon you already have levels up as often as
## any other weapon (it's only rare to find).
func weight_of(id: String) -> float:
	var d: Dictionary = defs[id]
	if d.has("signature") and level_of(id) > 0:
		return weapon_weight()
	return float(d["weight"])


## The average weight of the ordinary weapon cards.
func weapon_weight() -> float:
	var total := 0.0
	var n := 0
	for k in defs:
		if defs[k]["kind"] == "weapon" and not defs[k].has("signature"):
			total += float(defs[k]["weight"])
			n += 1
	return total / n if n > 0 else 8.0


## Returns up to n picks: [{ "id": String, "rarity": int }, ...] with distinct ids.
func draft(n: int, luck: float, max_weapons: int) -> Array:
	var pool := _eligible(max_weapons)
	var picks := []
	while picks.size() < n and not pool.is_empty():
		var total := 0.0
		for id in pool:
			total += weight_of(id)
		var r := rng.randf() * total
		var chosen: String = pool[pool.size() - 1]
		for id in pool:
			r -= weight_of(id)
			if r <= 0.0:
				chosen = id
				break
		pool.erase(chosen)
		var d: Dictionary = defs[chosen]
		var is_unlock: bool = d["kind"] == "weapon" and level_of(chosen) == 0
		var rarity := 0 if (is_unlock or d.get("fixed", false)) else roll_rarity(luck)
		if d.has("rarity_fixed"):   # signature weapons are always Legendary
			rarity = int(d["rarity_fixed"])
		picks.append({"id": chosen, "rarity": rarity})
	return picks


func roll_rarity(luck: float) -> int:
	var weights := []
	var total := 0.0
	for i in rarities.size():
		var w := float(rarities[i]["weight"])
		if i > 0:
			w *= 1.0 + luck
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return 0


func apply(pick: Dictionary, stats: Stats) -> void:
	var id: String = pick["id"]
	var d: Dictionary = defs[id]
	var lv := level_of(id)
	levels[id] = lv + 1
	if d["kind"] == "weapon" and lv == 0:
		return  # unlocking a weapon uses its base stats
	for m in _scaled_mods(d, int(pick["rarity"])):
		stats.apply(m["stat"], m["op"], m["value"])
	Events.upgrade_chosen.emit(id, int(pick["rarity"]))


func _scaled_mods(d: Dictionary, rarity: int) -> Array:
	var mult := 1.0 if d.get("fixed", false) else float(rarities[rarity]["mult"])
	var out := []
	for m in d.get("per_level", []):
		var v := float(m["value"])
		if m["op"] == "mult":
			v = 1.0 - (1.0 - v) * mult
		else:
			v *= mult
		out.append({"stat": m["stat"], "op": m["op"], "value": v})
	return out


## Text for a draft card: { title, rarity_name, color, body }
func describe(pick: Dictionary) -> Dictionary:
	var d: Dictionary = defs[pick["id"]]
	var rarity: Dictionary = rarities[int(pick["rarity"])]
	var lv := level_of(pick["id"])
	var is_unlock: bool = d["kind"] == "weapon" and lv == 0
	var lines := []
	if is_unlock:
		lines.append(tr("NEW WEAPON"))
		lines.append(text(d["desc"]))
	else:
		if lv == 0:
			lines.append(text(d["desc"]))
		for m in _scaled_mods(d, int(pick["rarity"])):
			lines.append(_fmt_mod(m))
	var tag := tr("NEW") if lv == 0 else tr("Lv %d → %d") % [lv, lv + 1]
	return {
		"title": tr(d["name"]),
		"subtitle": "%s · %s · %s" % [tr(rarity["name"]), tr(d["kind"].capitalize()), tag],
		"color": Color.html(rarity["color"]),
		"body": "\n".join(lines),
		"icon": d.get("icon", {}),   # {"glyph", "cover", "tint"?} for UpgradeIcon
		"kind": d["kind"],
		"next_level": lv + 1,   # the level it will be once picked
	}


func _fmt_mod(m: Dictionary) -> String:
	var name: String = text(stat_names.get(m["stat"], m["stat"]))
	var v: float = m["value"]
	match m["op"]:
		"add":
			return "+%d%% %s" % [roundi(v * 100.0), name]
		"mult":
			if v < 1.0:
				return "-%d%% %s" % [roundi((1.0 - v) * 100.0), name]
			return "x%.2f %s" % [v, name]
		_:
			if m["stat"] in percent_stats:
				return "+%d%% %s" % [roundi(v * 100.0), name]
			if absf(v - roundf(v)) < 0.01:
				return "+%d %s" % [roundi(v), name]
			return "+%.1f %s" % [v, name]


## Translated text: a plain string, or [format, part, part...] where every piece is
## translated (used for text built from names, e.g. "%s Damage").
static func text(v) -> String:
	if v is Array:
		var parts := []
		for k in range(1, v.size()):
			parts.append(TranslationServer.translate(str(v[k])))
		return TranslationServer.translate(str(v[0])) % parts
	return TranslationServer.translate(str(v))
