class_name Forge
extends RefCounted
## The Forge: every character's signature weapon can be forged up to level 10 with elemental
## shards (Wallet.shards). Each weapon has its own recipe of 5 shard "parts" (the Ice Wizard's is
## 5 ice; the Sock's 2 dark + 3 lightning); level 1 costs exactly those 5 shards and every later
## level scales the recipe up to TOTALS. Forge levels are saved (Wallet.forge) and apply to that
## weapon wherever it's used: as the character's own starting weapon, or as the Legendary card
## another character pulls in a run.
##
## Every level: +25% damage and +8% attack rate (BIG buffs, they stack); levels 4 and 8 add +1
## projectile (or hit / reach on melee weapons). Some weapons also gain a special at level 1:
## the Fire Wizard's Fireballs make every 5th hit explode like a level 1 Blast Bomb.

const MAX_LEVEL := 10
const DAMAGE_PER_LEVEL := 0.25
const RATE_PER_LEVEL := 0.08
const COUNT_AT := [4, 8]                 # +1 count at these levels
const TOTALS := [5, 10, 15, 20, 30, 40, 50, 60, 75, 100]   # shards for level 1 .. 10
const FIRE_BLAST_EVERY := 5              # Fireballs: every 5th hit explodes...
const FIRE_BLAST_DAMAGE := 25.0 * 1.15   # ...for what a level 1 Blast Bomb does (base 25, +15%)
const FIRE_BLAST_RADIUS := 3.0

## Shard parts per weapon style (always 5 in all).
const RECIPES := {
	"fire": {"fire": 5},
	"ice": {"ice": 5},
	"thunder": {"lightning": 5},
	"dark": {"dark": 5},
	"arcane": {"fire": 1, "ice": 2, "lightning": 2},      # Merlin
	"trunk": {"fire": 3, "dark": 2},                      # Ogre
	"wail": {"ice": 1, "dark": 4},                        # Ghast
	"silver": {"ice": 2, "lightning": 3},                 # Vampire Hunter
	"spear": {"ice": 2, "lightning": 3},                  # Vicki
	"daggers": {"lightning": 2, "dark": 3},               # The Rogue
	"katana": {"fire": 1, "lightning": 2, "dark": 2},     # Gaiden
	"flask": {"fire": 2, "ice": 1, "dark": 2},            # Dr. Croc
	"club": {"fire": 2, "ice": 2, "dark": 1},             # Thog
	"static": {"lightning": 3, "dark": 2},                # An Argyle Sock
	"maracas": {"fire": 2, "lightning": 3},               # Loco Robotico
	"acid": {"fire": 2, "dark": 3},                       # The Blob
}
## Weapon specials, unlocked at forge level 1.
const SPECIALS := {
	"fire": "Every 5th hit explodes like a Blast Bomb",
}


static func has_recipe(style: String) -> bool:
	return RECIPES.has(style)


static func level_of(style: String) -> int:
	return int(Wallet.forge.get(style, 0))


## Shards needed to forge `style` up to `to_level` (1..10): {kind: count}, in Wallet.SHARDS order.
static func cost(style: String, to_level: int) -> Dictionary:
	var out := {}
	if not RECIPES.has(style) or to_level < 1 or to_level > MAX_LEVEL:
		return out
	var k: int = int(TOTALS[to_level - 1]) / 5
	var r: Dictionary = RECIPES[style]
	for kind in Wallet.SHARDS:
		if r.has(kind):
			out[kind] = int(r[kind]) * k
	return out


## Shards needed for the next level, or {} at max level.
static func next_cost(style: String) -> Dictionary:
	return cost(style, level_of(style) + 1)


static func can_afford(style: String) -> bool:
	var c := next_cost(style)
	if c.is_empty():
		return false
	for kind in c:
		if int(Wallet.shards.get(kind, 0)) < int(c[kind]):
			return false
	return true


## Spend the shards and raise the weapon a level. Returns true if it was forged.
static func forge(style: String) -> bool:
	if not can_afford(style):
		return false
	var c := next_cost(style)
	for kind in c:
		Wallet.shards[kind] = int(Wallet.shards[kind]) - int(c[kind])
	Wallet.forge[style] = level_of(style) + 1
	Wallet.save_progress()
	Wallet._refresh_shards()
	return true


static func damage_mult(lvl: int) -> float:
	return 1.0 + DAMAGE_PER_LEVEL * lvl


static func rate_mult(lvl: int) -> float:
	return 1.0 + RATE_PER_LEVEL * lvl


static func count_bonus(lvl: int) -> int:
	var n := 0
	for at in COUNT_AT:
		if lvl >= at:
			n += 1
	return n


## Apply a weapon's forge level to its stats for this run (`pre` = "orb" for your own weapon,
## "sig_<style>" for a Legendary card).
static func apply(stats: Stats, pre: String, style: String) -> void:
	var lvl := level_of(style)
	if lvl <= 0:
		return
	stats.apply(pre + "_damage", "mult", damage_mult(lvl))
	stats.apply(pre + "_cooldown", "mult", 1.0 / rate_mult(lvl))
	var n := count_bonus(lvl)
	if n > 0:
		stats.apply(pre + "_count", "flat", float(n))


## What a weapon at forge level `lvl` gets, as lines (for the forge menu and tooltips).
static func describe(style: String, lvl: int) -> Array[String]:
	var out: Array[String] = []
	if lvl <= 0:
		out.append(I18n.t("Not forged yet"))
		return out
	out.append(I18n.f("Damage +%d%%", roundi(DAMAGE_PER_LEVEL * lvl * 100.0)))
	out.append(I18n.f("Attack rate +%d%%", roundi(RATE_PER_LEVEL * lvl * 100.0)))
	var n := count_bonus(lvl)
	if n > 0:
		out.append(I18n.f("+%d projectile / hit", n))
	if SPECIALS.has(style):
		out.append(I18n.t(SPECIALS[style]))
	return out
