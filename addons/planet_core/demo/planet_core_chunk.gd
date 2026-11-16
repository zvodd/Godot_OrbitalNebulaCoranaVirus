extends Node3D
## Builds one planet chunk with the C++ extension and prints the triangle count.
##
## This is the "extension actually runs in the game" check (acceptance gate #4): it needs no
## renderer, so it works headlessly.
##
##   godot --headless --path . res://addons/planet_core/demo/planet_core_chunk.tscn
## or, from a script: `godot --headless -s addons/planet_core/demo/planet_core_headless.gd`
##
## Attach it to any Node3D; it does not touch the planet's own nodes.

## Which chunk to mesh. 0 is the first patch.
@export var patch: int = 0
## Planet seed; the game's default planet def is used.
@export var planet_seed: int = 42
## Build a MeshInstance3D so the chunk can be seen when not running headless.
@export var show_mesh: bool = true

var _mesh_instance: MeshInstance3D


func _ready() -> void:
	print("planet_core chunk demo")
	if not PlanetCore.available:
		push_error("planet_core GDExtension is not loaded — build it with `scons` in addons/planet_core")
		return

	var def: PlanetDef = load("res://data/planets/default_planet.tres")
	if def == null:
		push_error("planet_core chunk demo: default_planet.tres failed to load")
		return

	var t := Time.get_ticks_usec()
	var ico := PlanetCore.build_icosphere(def.subdivision, def.patch_level)
	var grid := PlanetCore.build_grid(def, planet_seed, ico)
	var gen_ms := (Time.get_ticks_usec() - t) / 1000.0

	var mesher := PlanetCore.new_mesher()
	t = Time.get_ticks_usec()
	mesher.build_patch(grid, patch)
	var mesh_ms := (Time.get_ticks_usec() - t) / 1000.0

	var vertices := mesher.get_vertices()
	var normals := mesher.get_normals()
	var colors := mesher.get_colors()
	print("  planet %d: %d lattice vertices x %d rows, %d points, %d deposits" % [
			planet_seed, grid.get_V(), grid.get_rows(), grid.get_point_count(), grid.get_deposits().size()])
	print("  patch %d of %d (%d faces each)" % [patch, ico.get_patch_count(), ico.get_faces_per_patch()])
	print("  TRIANGLE COUNT: %d (%d vertices)" % [vertices.size() / 3, vertices.size()])
	print("  build+generate %.1f ms, mesh %.2f ms" % [gen_ms, mesh_ms])

	if show_mesh and vertices.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "PlanetCoreChunk%03d" % patch
		_mesh_instance.mesh = mesh
		add_child(_mesh_instance)


## The triangle count of the chunk that was built, for callers that want the number.
func triangle_count() -> int:
	if _mesh_instance == null or _mesh_instance.mesh == null:
		return 0
	var arrays := _mesh_instance.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts.size() / 3
