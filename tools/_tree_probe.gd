extends Node
func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for k in 30:
		await get_tree().process_frame
	var best: Array = []
	for b in get_tree().get_nodes_in_group(TreeFire.GROUP):
		var p: Vector3 = (b as Node3D).global_position
		if p.length() > 15.0 and p.length() < 40.0:
			best.append(p)
	for p in best.slice(0, 6):
		print("TREE ", p)
	get_tree().quit()
