class_name PlayableBoss
extends RefCounted
## The map bosses who joined the roster, as playable characters: each one's own code-built boss
## model at player size, posed procedurally (PharaohBody, NecromancerBody, SingeBody).
## RosterHero.CFG marks them "procedural": "pharaoh" / "necromancer" / "singe"; RosterHero and
## RosterModel drive every one of them through the same little interface:
##   animate(dt, speed, airborne)   every frame: ground speed (m/s), in the air or not
##   attack(target) -> Vector3      the weapon move toward `target`; returns where shots leave from
##   tip() -> Vector3               where shots leave from
##   cast(i)                        the cast pose for ability slot i (2 = the ultimate)
##   hit() / die()                  flinch / the death (the run is over)
##   drawn                          weapon in hand (attacking / casting) or put away
##   set_dim(f) / set_hurt(f)

const KINDS := ["pharaoh", "necromancer", "singe"]


static func create(kind: String) -> Node3D:
	match kind:
		"pharaoh":
			return PharaohBody.create()
		"necromancer":
			return NecromancerBody.create()
		"singe":
			return SingeBody.create()
	return null


static func is_kind(kind: String) -> bool:
	return kind in KINDS


## An overlay laid over every mesh of a body: dims it (immune) and flashes it white (hurt).
static func overlay() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 0)
	return m


static func apply_overlay(root: Node, mat: Material) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = mat


## The overlay's colour for a dim level and a hurt flash.
static func tint(mat: StandardMaterial3D, dim: float, hurt: float) -> void:
	if hurt > 0.01:
		mat.albedo_color = Color(1.0, 0.9, 0.82, clampf(hurt, 0.0, 1.0) * 0.5)
	else:
		mat.albedo_color = Color(0, 0, 0, clampf(1.0 - dim, 0.0, 1.0) * 0.6)
