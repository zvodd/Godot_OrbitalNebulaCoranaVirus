class_name RaycastEraser extends Node

@export var cam: Camera3D
@export var manager: MultiMeshManager
@export var radius : float = 0.25
@export_flags_3d_physics var ray_mask: int = 1

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_erase()

func _try_erase() -> void:
	if not cam or not manager: 
		push_warning("Missing refs")
		return
	
	var mouse_pos := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mouse_pos)
	var end := origin + cam.project_ray_normal(mouse_pos) * 500.0
	
	var space := manager.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, end, ray_mask)
	query.collide_with_areas = true
	var result := space.intersect_ray(query)
	
	if not result.is_empty():
		var hit_pos: Vector3 = result.position
		print("Hit %v" %[hit_pos])
		manager.remove_instances_in_radius(hit_pos, radius)
	else:
		print("no collide")
