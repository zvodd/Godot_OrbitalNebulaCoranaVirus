class_name SurfaceSampler
extends Node3D

@export var radius := 20.0
@export var collision_mask := 1

func get_random_point(origin: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var random_dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var start := origin + (random_dir * radius)
	
	# Cast toward origin to find surface inside volume
	var query := PhysicsRayQueryParameters3D.create(start, origin)
	query.collision_mask = collision_mask
	
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {} # No surface found
	return {"position": hit.position, "normal": hit.normal}
