class_name SpineTwist
extends SkeletonModifier3D
## Turns the upper body around the vertical axis (applied after the animation), split across
## the three spine bones so the twist looks natural. Used to aim fireball casts.

const BONES := ["Spine02", "Spine01", "Spine"]
const SHARE := [0.4, 0.35, 0.25]
const TURN_RATE := 14.0

var target_angle := 0.0
var angle := 0.0
var _ids: Array[int] = []


func _process(dt: float) -> void:
	angle = lerpf(angle, target_angle, 1.0 - exp(-TURN_RATE * dt))


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or absf(angle) < 0.0005:
		return
	if _ids.is_empty():
		for b in BONES:
			_ids.append(sk.find_bone(b))
	for k in _ids.size():
		var id := _ids[k]
		if id < 0:
			continue
		var parent := sk.get_bone_parent(id)
		var pb := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
		var turn := Basis(Vector3.UP, angle * SHARE[k])
		var local := Basis(sk.get_bone_pose_rotation(id))
		var rotated := pb.inverse() * turn * pb * local
		sk.set_bone_pose_rotation(id, rotated.get_rotation_quaternion())
