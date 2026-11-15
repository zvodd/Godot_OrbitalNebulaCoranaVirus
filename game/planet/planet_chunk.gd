class_name PlanetChunk
extends MeshInstance3D
## One icosphere patch through every row: render mesh + trimesh collision (ROADMAP §5.2).

const LAYER_TERRAIN := 1

var patch: int = -1
var triangle_count: int = 0

var _body: StaticBody3D
var _shape_node: CollisionShape3D
var _shape: ConcavePolygonShape3D
var _mesh: ArrayMesh


func _init() -> void:
	_mesh = ArrayMesh.new()
	_shape = ConcavePolygonShape3D.new()
	# Ore chunks and rays inside pits can approach from either side.
	_shape.backface_collision = true
	_body = StaticBody3D.new()
	_body.collision_layer = LAYER_TERRAIN
	_body.collision_mask = 0
	_shape_node = CollisionShape3D.new()
	_shape_node.disabled = true
	_body.add_child(_shape_node)
	add_child(_body)


## Replace the chunk's geometry with non-indexed triangle arrays from PlanetMesher.
func apply(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	_mesh.clear_surfaces()
	@warning_ignore("integer_division")
	triangle_count = vertices.size() / 3
	if vertices.is_empty():
		mesh = null
		_shape_node.shape = null
		_shape_node.disabled = true
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = _mesh
	_shape.set_faces(vertices)
	_shape_node.shape = _shape
	_shape_node.disabled = false
