class_name SurfaceNavigator
extends Node3D

## Configuration
@export var step_size := 2.0
@export var h_weight := 250.0
@export var search_limit := 5000
@export var hash_size := 1.5

## State
var _open_list: Array[SurfaceNode] = []
var _closed_set: Dictionary = {} # Vector3i -> bool
var _space_state: PhysicsDirectSpaceState3D

class SurfaceNode:
	var pos: Vector3
	var normal: Vector3
	var g_cost: float
	var h_cost: float
	var f_cost: float: get = get_f_cost
	var parent: SurfaceNode
	
	func get_f_cost() -> float: return g_cost + h_cost

func find_path(start_pos: Vector3, start_normal: Vector3, target: Vector3) -> Array[Vector3]:
	_space_state = get_world_3d().direct_space_state
	_open_list.clear()
	_closed_set.clear()
	
	var start_node := SurfaceNode.new()
	start_node.pos = start_pos
	start_node.normal = start_normal
	_open_list.append(start_node)
	
	var count := 0
	while _open_list.size() > 0 and count < search_limit:
		count += 1
		_open_list.sort_custom(func(a, b): return a.f_cost < b.f_cost)
		var current : SurfaceNode = _open_list.pop_front()
		
		# Goal check
		if current.pos.distance_to(target) < step_size * 1.5:
			return _reconstruct_path(current)
			
		_closed_set[_get_hash(current.pos)] = true
		
		# Expand neighbors
		for neighbor in _get_neighbors(current, target):
			if _get_hash(neighbor.pos) in _closed_set: continue
			_open_list.append(neighbor)
			
	return []

func _get_neighbors(node: SurfaceNode, target: Vector3) -> Array[SurfaceNode]:
	var neighbors: Array[SurfaceNode] = []
	# Ensure axis is unit length for .rotated()
	var norm := node.normal.normalized()
	
	var basis_tangent := norm.cross(Vector3.UP if abs(norm.y) < 0.9 else Vector3.RIGHT).normalized()
	
	for i in range(6):
		# Use normalized 'norm' as axis
		var dir := basis_tangent.rotated(norm, i * PI/3.0)
		var hit := _run_3_ray_probe(node.pos, norm, dir)
		
		if hit.is_empty(): continue
		
		var n := SurfaceNode.new()
		n.pos = hit.position
		n.normal = hit.normal # Raycast hits are usually unit, but .normalized() here is safer
		n.parent = node
		n.g_cost = node.g_cost + node.pos.distance_to(n.pos)
		n.h_cost = n.pos.distance_to(target) * h_weight
		neighbors.append(n)
	return neighbors

func _run_3_ray_probe(p: Vector3, n: Vector3, d: Vector3) -> Dictionary:
	# 1. FLAT/SLOPE
	var res := _ray(p + (d * step_size) + (n * step_size), -n * step_size * 2.0)
	if not res.is_empty(): return res
	
	# 2. INNER CORNER
	res = _ray(p, d * step_size * 1.1)
	if not res.is_empty(): return res
	
	# 3. OUTER LEDGE
	res = _ray(p + (d * step_size) - (n * step_size * 0.5), -d * step_size)
	return res

func _ray(origin: Vector3, cast: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + cast)
	return _space_state.intersect_ray(query)

func _get_hash(pos: Vector3) -> Vector3i:
	return Vector3i(pos / hash_size)

func _reconstruct_path(end_node: SurfaceNode) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var curr = end_node
	while curr:
		path.push_front(curr.pos)
		curr = curr.parent
	return path
