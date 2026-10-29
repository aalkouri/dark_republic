class_name CastleDoors
extends Node3D
## The castle's great front doors: two 6 m x 14 m oak leaves banded with iron, hinged on the
## doorway's sides. They start open (swung inward); when the run begins they slam shut and stay
## shut, so you can't leave. Placed at the doorway's centre on the south wall.

signal shut

const LEAF_W := 6.0
const LEAF_H := 14.0   # fills the doorway up to the arch
const LEAF_T := 0.5
const OPEN_ANGLE := deg_to_rad(95.0)
const SLAM_SOUND := "res://audio/castle/door_slam.wav"

var _hinges: Array[Node3D] = []
var is_open := true
var _sfx: AudioStreamPlayer3D


func _ready() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.24, 0.14, 0.07)
	wood.roughness = 0.85
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.13, 0.13, 0.14)
	iron.metallic = 0.6
	iron.roughness = 0.5
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(side * LEAF_W, 0, 0)
		add_child(hinge)
		var leaf := AnimatableBody3D.new()
		leaf.sync_to_physics = false   # driven through the hinge: follow its transform directly
		leaf.position = Vector3(-side * LEAF_W * 0.5, LEAF_H * 0.5, 0)
		hinge.add_child(leaf)
		var shape := BoxShape3D.new()
		shape.size = Vector3(LEAF_W, LEAF_H, LEAF_T)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		leaf.add_child(cs)
		_part(leaf, Vector3(LEAF_W, LEAF_H, LEAF_T), Vector3.ZERO, wood)
		for k in 4:   # planks' grooves and iron bands
			_part(leaf, Vector3(0.06, LEAF_H, LEAF_T + 0.04), Vector3(-LEAF_W * 0.5 + (k + 1) * LEAF_W / 5.0, 0, 0), iron)
		for y in [-5.0, 0.0, 5.0]:
			_part(leaf, Vector3(LEAF_W, 0.35, LEAF_T + 0.08), Vector3(0, y, 0), iron)
		var ring := TorusMesh.new()   # a big iron ring handle on both faces
		ring.inner_radius = 0.28
		ring.outer_radius = 0.38
		ring.material = iron
		for face in [-1.0, 1.0]:
			var r := MeshInstance3D.new()
			r.mesh = ring
			r.rotation = Vector3(PI / 2, 0, 0)
			r.position = Vector3(-side * (LEAF_W * 0.5 - 0.8), -LEAF_H * 0.5 + 5.0, face * (LEAF_T * 0.5 + 0.08))   # near the free edge
			leaf.add_child(r)
		hinge.rotation.y = side * -OPEN_ANGLE   # open: swung inward (toward -Z)
		_hinges.append(hinge)
	_sfx = AudioStreamPlayer3D.new()
	_sfx.bus = Settings.SFX_BUS
	_sfx.unit_size = 25.0
	_sfx.position = Vector3(0, 4, -2)
	if ResourceLoader.exists(SLAM_SOUND):
		_sfx.stream = load(SLAM_SOUND)
	add_child(_sfx)


func _part(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = at
	parent.add_child(mi)


## Swing both leaves shut over `time` seconds (accelerating), then boom.
func close(time := 1.1) -> void:
	if not is_open:
		return
	is_open = false
	var tw := create_tween()
	tw.set_parallel(true)
	for h in _hinges:
		tw.tween_property(h, "rotation:y", 0.0, time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(func():
		if _sfx.stream:
			_sfx.play()
		shut.emit())


## Shut at once (screenshots and tests that skip the entrance).
func close_now() -> void:
	is_open = false
	for h in _hinges:
		h.rotation.y = 0.0
