extends Node
## Global event bus (autoload "Events").
## Items and systems hook gameplay moments here instead of referencing each other.

signal enemy_killed(pos: Vector3, type_id: int)
signal player_damaged(amount: float)
signal level_up(level: int)
signal upgrade_chosen(id: String, rarity: int)
signal prop_burnt(at: Vector3)   # a tree / fallen log / burnable prop finished burning (TreeFire)
