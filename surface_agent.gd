class_name SurfaceAgent
extends Node3D

@export var navigator: SurfaceNavigator
@export var sampler: SurfaceSampler
@export var speed := 5.0
@export var stop_distance := 0.5

var _path: Array[Vector3] = []
var _current_normal := Vector3.UP

func _ready() -> void:
	_pick_new_target()

func _process(delta: float) -> void:
	if _path.is_empty():
		_pick_new_target()
		return
	
	_move_to_next_node(delta)

func _move_to_next_node(delta: float) -> void:
	var target := _path[0]
	var dir := global_position.direction_to(target)
	
	global_position = global_position.move_toward(target, speed * delta)
	
	# Basic orientation to surface
	if dir.length() > 0.1:
		var look_target := global_position + dir
		look_at(look_target, _current_normal)

	if global_position.distance_to(target) < stop_distance:
		_path.remove_at(0)

func _pick_new_target() -> void:
	var hit := sampler.get_random_point(global_position)
	if hit.is_empty(): return
	
	var new_path := navigator.find_path(global_position, _current_normal, hit.position)
	if not new_path.is_empty():
		_path = new_path
		# Update normal from navigator logic or hit
		_current_normal = hit.normal
