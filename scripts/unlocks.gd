class_name Unlocks
extends RefCounted
## Permanent upgrades bought with coins in the title's Unlocks menu (UnlocksMenu), each with a
## few levels (Wallet.unlock_levels), and the discovery marks for its catalogue tabs.
##   map        1 level   the minimap (top right) and the big map (M)
##   free_ban   3 levels  that many of the run's 3 bans cost nothing
##   reroll     5 levels  that many Refreshes a run on the level-up cards (100 coins each)
## Catalogue: weapons, tomes and items show once found in a run, maps once unlocked. Anything
## found through play gets a "new" dot (Wallet.new_marks) on its square and its tab until hovered;
## hovering a new weapon, tome or item also pays DISCOVERY_REWARD coins (with the coin payout).

const LIST := [
	{"id": "map", "name": "Map", "glyph": "eye", "color": "#7fd8ff", "costs": [750],
		"desc": "Unlocks the minimap and the big map (M).",
		"levels": ["The minimap and the big map"]},
	{"id": "free_ban", "name": "Free Ban", "glyph": "cross", "color": "#ff6a5a", "costs": [500, 1000, 2000],
		"desc": "Makes your bans on the level-up cards free.",
		"levels": ["1 free ban a run", "2 free bans a run", "3 free bans a run"]},
	{"id": "reroll", "name": "Reroll", "glyph": "clock", "color": "#ffd24a", "costs": [500, 1000, 2000, 5000, 10000],
		"desc": "Refresh the level-up cards for a new set (100 coins each).",
		"levels": ["1 refresh a run", "2 refreshes a run", "3 refreshes a run", "4 refreshes a run", "5 refreshes a run"]},
]
const REFRESH_COST := 100
## Hovering a newly found weapon, tome or item (its red dot) pays this many coins, once; a newly
## opened map pays MAP_REWARDS (the Swamp's is waiting from the start).
const DISCOVERY_REWARD := 150
const MAP_REWARDS := {"swamp": 1000, "forest": 1500, "castle": 3000, "desert": 3000, "graveyard": 5000, "caldera": 5000}
const REWARD_KINDS := ["weapon", "tome", "item", "map"]


## Coins for hovering the new square of `kind`:`id` (0 if it pays nothing).
static func reward_for(kind: String, id: String) -> int:
	if kind == "map":
		return int(MAP_REWARDS.get(id, 0))
	return DISCOVERY_REWARD if kind in REWARD_KINDS else 0

static func find(id: String) -> Dictionary:
	for u in LIST:
		if u["id"] == id:
			return u
	return {}


static func max_level(id: String) -> int:
	return (find(id).get("costs", []) as Array).size()


## Coins for the next level of `id` (0 once it's maxed).
static func next_cost(id: String) -> int:
	var costs: Array = find(id).get("costs", [])
	var lv := Wallet.unlock_level(id)
	return int(costs[lv]) if lv < costs.size() else 0


## Buy the next level of `id`. False if it's maxed or you can't afford it.
static func buy(id: String) -> bool:
	var lv := Wallet.unlock_level(id)
	if lv >= max_level(id) or not Wallet.spend(next_cost(id)):
		return false
	Wallet.set_unlock_level(id, lv + 1)
	return true


static func has_map() -> bool:
	return Wallet.unlock_level("map") >= 1
