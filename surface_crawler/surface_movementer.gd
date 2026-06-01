class_name SurfaceMovementComponent
extends Node3D

## Config
@export var navigator: SurfaceNavigator
@export var speed := 5.0
@export var rotation_speed := 8.0
@export var acceleration := 10.0
@export var sample_radius := 15.0

## State
var _path: Array[Vector3] = []
var _current_normal := Vector3.UP
var _velocity := Vector3.ZERO
@onready var _actor: Node3D = get_parent()

func _ready() -> void:
	if not navigator:
		push_error("Navigator not assigned")

func _process(delta: float) -> void:
	if _path.is_empty():
		_pick_random_target()
		return
		
	_move(delta)

## Public API
func move_to(target_pos: Vector3) -> void:
	var path := navigator.find_path(_actor.global_position, _current_normal, target_pos)
	if not path.is_empty():
		_path = path

## Private logic
func _move(delta: float) -> void:
	var target_node_pos := _path[0]
	var to_target := target_node_pos - _actor.global_position
	var dist := to_target.length()
	
	if dist < 0.2:
		_path.remove_at(0)
		return

	# Smooth Position
	var desired_dir := to_target.normalized()
	var target_vel := desired_dir * speed
	_velocity = _velocity.lerp(target_vel, acceleration * delta)
	_actor.global_position += _velocity * delta

	# Smooth Rotation (Align to Surface + Movement)
	_update_orientation(desired_dir, delta)

func _update_orientation(move_dir: Vector3, delta: float) -> void:
	var space := _actor.get_world_3d().direct_space_state
	# Ray length should account for scale; using 2.0 as safe buffer
	var query := PhysicsRayQueryParameters3D.create(_actor.global_position + _current_normal, _actor.global_position - _current_normal)
	var hit := space.intersect_ray(query)
	
	if not hit.is_empty():
		_current_normal = _current_normal.lerp(hit.normal, acceleration * delta)

	# 1. Build orthonormal vectors
	var side := _current_normal.cross(move_dir).normalized()
	var forward := side.cross(_current_normal).normalized()
	
	# 2. Create target Basis (pure rotation)
	var target_basis := Basis(side, _current_normal, -forward).orthonormalized()
	
	# 3. Handle Scaling: Extract current scale to preserve it
	var current_scale := _actor.global_basis.get_scale()
	
	# 4. Slerp using Quaternions (ignores scale, avoids errors)
	var current_quat := _actor.global_basis.get_rotation_quaternion()
	var target_quat := target_basis.get_rotation_quaternion()
	var result_quat := current_quat.slerp(target_quat, rotation_speed * delta)
	
	# 5. Reconstruct Basis with scale
	_actor.global_basis = Basis(result_quat).scaled(current_scale)

func _pick_random_target() -> void:
	var space := _actor.get_world_3d().direct_space_state
	var random_dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var start := _actor.global_position + (random_dir * sample_radius)
	
	var query := PhysicsRayQueryParameters3D.create(start, _actor.global_position)
	var hit := space.intersect_ray(query)
	
	if not hit.is_empty():
		move_to(hit.position)
