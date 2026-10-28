class_name HeroBase
extends Node3D
## What the player, weapons and abilities need from a playable character's model. The Fire
## Wizard (HeroModel) and the roster characters (RosterHero) both implement it.


## Swing / thrust the weapon toward `target` (world space). Returns where projectiles leave from.
func attack(_target: Vector3) -> Vector3:
	return staff_tip()


func staff_tip() -> Vector3:
	return global_position + Vector3(0, 1.4, 0)


## Ground speed (m/s) and whether he's in the air; called every frame by the player.
func set_motion(_speed: float, _airborne: bool) -> void:
	pass


func play_hit() -> void:
	pass


## Cast animation for ability slot i (0, 1, 2 = ultimate).
func play_ability(_i: int) -> void:
	pass


func vanish() -> void:
	visible = false


func reappear() -> void:
	visible = true


## Gone at once (the entrance comet): no animation.
func hide_now() -> void:
	visible = false


func is_playing(_layer: String) -> bool:
	return false


## Scale the whole character's brightness (1 = normal, 0.5 = immune).
func set_dim(_f: float) -> void:
	pass


func set_hurt(_amount: float) -> void:
	pass
