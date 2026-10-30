class_name CrocBulk
extends SkeletonModifier3D
## Dr. Croc's Mutagen bulk: on top of the whole model growing, his chest, shoulders and arms
## swell out of proportion (the head and hands held back) so he looks pumped up, hulking, and
## his lab coat strains tight across him. Applied after the animation, scaled by `amount` 0..1.

## Bone -> scale at full bulk. Scales compound down the chain (Spine on top of Spine01...),
## so the neck and hands take some back.
const SCALE := {
	"Spine02": 1.06, "Spine01": 1.12, "Spine": 1.22, "neck": 0.76,
	"LeftShoulder": 1.06, "RightShoulder": 1.06, "LeftArm": 1.18, "RightArm": 1.18,
	"LeftHand": 0.85, "RightHand": 0.85,
	"LeftUpLeg": 1.12, "RightUpLeg": 1.12, "LeftFoot": 0.9, "RightFoot": 0.9,
}

var amount := 0.0
var _ids := {}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or amount <= 0.001:
		return
	if _ids.is_empty():
		for b in SCALE:
			_ids[b] = sk.find_bone(b)
	for b in SCALE:
		var id: int = _ids[b]
		if id < 0:
			continue
		var f := lerpf(1.0, float(SCALE[b]), amount)
		sk.set_bone_pose_scale(id, sk.get_bone_pose_scale(id) * f)
