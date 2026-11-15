class_name OreField
extends Node3D
## Spawns and owns loose ore chunks, and provides the planet's radial gravity (ROADMAP §7).

## Beyond this, new ore is merged into the nearest chunk of the same type.
@export var max_chunks: int = 150
@export var gravity: float = 7.0

var planet: Planet
var _area: Area3D


func setup(p_planet: Planet) -> void:
	planet = p_planet
	planet.ore_released.connect(spawn)
	planet.chunks_rebuilt.connect(_on_terrain_changed)
	planet.regenerated.connect(clear)

	# Point gravity toward the planet centre for everything on the ore layer.
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = OreChunk.LAYER_ORE
	_area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	_area.gravity_point = true
	_area.gravity_point_center = Vector3.ZERO
	_area.gravity_point_unit_distance = 0.0
	_area.gravity = gravity
	var shape := SphereShape3D.new()
	shape.radius = 400.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_area.add_child(cs)
	planet.add_child(_area)


func live_count() -> int:
	return get_child_count()


func spawn(mat: MaterialDef, world_pos: Vector3) -> void:
	if get_child_count() >= max_chunks:
		var nearest := _nearest_of(mat.ore_id, world_pos)
		if nearest != null:
			nearest.amount += 1.0
			return
	var chunk := OreChunk.new()
	chunk.setup(mat)
	add_child(chunk)
	chunk.global_position = world_pos
	# A little pop away from the planet so it tumbles into the pit.
	var out := world_pos.normalized()
	chunk.linear_velocity = out * randf_range(1.0, 2.5) + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0
	chunk.angular_velocity = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 8.0


## Remove every loose chunk (round end / new planet). Un-extracted ore is lost.
func clear() -> void:
	for c in get_children():
		c.queue_free()


func _physics_process(_delta: float) -> void:
	if planet == null or planet.grid == null:
		return
	# Safety net: anything that got under the core or flung away is lost.
	var floor_r := planet.grid.core_surface_radius() - 2.0
	for c in get_children():
		var r := (c as Node3D).global_position.length()
		if r < floor_r or r > 300.0:
			c.queue_free()


func _on_terrain_changed(_count: int) -> void:
	# Static colliders changed under sleeping bodies; wake them so they fall into new pits.
	for c in get_children():
		(c as RigidBody3D).sleeping = false


func _nearest_of(ore_id: StringName, world_pos: Vector3) -> OreChunk:
	var best: OreChunk = null
	var best_d := INF
	for c in get_children():
		var chunk := c as OreChunk
		if chunk.ore_id != ore_id:
			continue
		var d := chunk.global_position.distance_squared_to(world_pos)
		if d < best_d:
			best_d = d
			best = chunk
	return best
