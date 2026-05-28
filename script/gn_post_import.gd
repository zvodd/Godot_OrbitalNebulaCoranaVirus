@tool
class_name GNPostImport extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	var pool := MeshTransformPool.new()
	var mesh_map: Dictionary = {} # Dictionary[Mesh, Array[Transform3D]]
	
	_extract_instances(scene, mesh_map)
	
	# Convert map to exportable resources
	for m: Mesh in mesh_map:
		var group := MeshTransformGroup.new()
		group.mesh = m
		group.transforms = mesh_map[m]
		pool.groups.append(group)
	
	# Save resource next to original GLTF
	var source_path := get_source_file()
	var save_path := source_path.get_base_dir() + "/" + source_path.get_file().get_basename() + "_gn_pool.tres"
	
	var err := ResourceSaver.save(pool, save_path)
	if err != OK:
		push_error("Failed save GN pool: ", err)
		
	return scene

func _extract_instances(node: Node, map: Dictionary) -> void:
	# Check if GN Instance. Adjust string match if needed.
	if node is MeshInstance3D and node.name.begins_with("GN Instance"):
		var m: Mesh = node.mesh
		if m != null:
			if not map.has(m):
				map[m] = [] as Array[Transform3D]
			
			# Store global transform relative to scene root if needed. 
			# Using local transform here. Change to node.global_transform if hierarchy deep.
			map[m].append(node.transform) 
			
		# Nuke original node. Replaced by custom system later.
		node.queue_free()
	else:
		# Only iterate children if not freeing parent, or iterate safely
		for child: Node in node.get_children():
			_extract_instances(child, map)
