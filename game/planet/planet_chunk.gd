class_name PlanetChunk
extends MeshInstance3D
## One icosphere patch through every row: render mesh + trimesh collision (ROADMAP §5.2).

const LAYER_TERRAIN := 1

var patch: int = -1
var triangle_count: int = 0

var _body: StaticBody3D
var _shape_node: CollisionShape3D
## Created on the first apply() and then mutated in place, never re-assigned (see apply()).
var _shape: ConcavePolygonShape3D
var _mesh: ArrayMesh


func _init() -> void:
	_mesh = ArrayMesh.new()
	_body = StaticBody3D.new()
	_body.collision_layer = LAYER_TERRAIN
	_body.collision_mask = 0
	_shape_node = CollisionShape3D.new()
	_shape_node.disabled = true
	_body.add_child(_shape_node)
	add_child(_body)


## Replace the chunk's geometry with non-indexed triangle arrays (from PlanetCoreMesher on the
## shipped path, PlanetMesher on the GDScript fallback).
##
## The collision shape is kept and its faces are updated **in place**, and the shape is never
## re-assigned to the `CollisionShape3D` after the first time. Both matter, and they were
## measured on 320 live chunks at 256 triangles each:
##
##   mutate the attached shape in place      0.012 ms / chunk   <- this
##   re-assign the same shape to the node    0.42  ms / chunk
##   attach a brand-new shape                0.66  ms / chunk
##   set_faces() on a detached shape         0.006 ms / chunk
##
## Re-assigning or swapping the shape makes the physics server tear down and rebuild the
## shape's BVH and broadphase entry, which dominated the whole rebuild (~150 ms of 170 ms).
func apply(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	_mesh.clear_surfaces()
	@warning_ignore("integer_division")
	triangle_count = vertices.size() / 3
	if vertices.is_empty():
		mesh = null
		_shape_node.shape = null
		_shape_node.disabled = true
		_shape = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = _mesh
	if _shape == null:
		_shape = ConcavePolygonShape3D.new()
		# Ore chunks and rays inside pits can approach from either side.
		_shape.backface_collision = true
		_shape_node.shape = _shape
	# In place: the shape stays attached to the same body, so the physics server only
	# refreshes its internal faces instead of rebuilding the shape.
	_shape.set_faces(vertices)
	_shape_node.disabled = false
