class_name MultiMeshManager extends Node3D

@export var pool: MeshTransformPool:
	set(val):
		pool = val
		if is_inside_tree():
			rebuild()

func _ready() -> void:
	rebuild()

## Clear children and spawn new MultiMeshes
func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	
	if not pool: return

	for group: MeshTransformGroup in pool.groups:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = MultiMesh.new()
		mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		mmi.multimesh.mesh = group.mesh
		mmi.multimesh.instance_count = group.transforms.size()
		
		for i: int in group.transforms.size():
			mmi.multimesh.set_instance_transform(i, group.transforms[i])
		
		add_child(mmi)

## Remove instances within sphere. 
func remove_instances_in_radius(global_pos: Vector3, radius: float) -> void:
	var r_sq := radius * radius
	
	for child in get_children():
		var mmi := child as MultiMeshInstance3D
		if not mmi: continue
		
		var mm := mmi.multimesh
		var kept_transforms: Array[Transform3D] = []
		var changed := false
		
		# Check every instance
		for i: int in mm.instance_count:
			var tf := mm.get_instance_transform(i)
			var global_tf := mmi.global_transform * tf
			
			if global_tf.origin.distance_squared_to(global_pos) > r_sq:
				kept_transforms.append(tf)
			else:
				changed = true
		
		# Update MultiMesh if deletions happened
		if changed:
			_update_mmi_data(mmi, kept_transforms)

func _update_mmi_data(mmi: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	var mm := mmi.multimesh
	var new_count := transforms.size()
	
	if new_count == 0:
		mmi.queue_free()
		return

	mm.instance_count = new_count
	for i: int in new_count:
		mm.set_instance_transform(i, transforms[i])
