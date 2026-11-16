extends SceneTree
## Checks that the `planet_core` GDExtension loads cleanly and exposes the expected API.
##
## Run: godot --headless -s tests/test_planet_core_extension.gd
##
## This is the "gate #1 + #4" companion to the equivalence gate: it proves the .so loaded, that
## every class and public method is registered, and that one chunk meshes headlessly.

var _fails := 0
var _checks := 0

## Class -> methods that must exist. Kept in sync with the C++ bindings on purpose: if a method
## is dropped from the extension this test fails instead of the game.
const EXPECTED_API := {
	"PlanetCoreIcosphere": [
		"build", "is_built", "get_level", "get_patch_level", "get_vertex_count",
		"get_face_count", "get_patch_count", "get_faces_per_patch", "get_mean_edge",
		"get_verts", "get_faces", "get_face_patch", "get_adj_offsets", "get_adj",
		"get_dirty_offsets", "get_dirty_patches", "get_lut", "patch_face_begin",
		"valence", "nearest_vertex", "nearest_vertex_brute",
	],
	"PlanetCoreGrid": [
		"setup", "get_config", "get_ico", "get_V", "get_rows", "get_dr", "get_r0",
		"get_point_count", "get_fill", "set_fill", "get_material", "set_material",
		"get_deposit", "set_deposit", "get_corruption", "set_corruption", "get_mat_colors",
		"get_shell_of_row", "get_shell_top_row", "get_shell_bottom_row",
		"get_shell_initial_solid", "get_shell_removed", "get_deposits", "get_materials",
		"get_dirty_patches", "get_pending_ore", "get_newly_exposed",
		"get_outermost_intact_shell", "set_outermost_intact_shell", "row_radius",
		"lattice_pos", "world_to_lattice", "shell_top_radius", "surface_radius",
		"core_surface_radius", "cleared_fraction", "is_diggable_row", "points_in_sphere",
		"is_solid", "is_exposed", "is_cuttable", "gradient", "erode", "touch",
		"carve_sphere", "mark_all_dirty", "clear_dirty", "refresh_exposure", "dirty_count",
	],
	"PlanetCoreMesher": [
		"build_patch", "build_faces", "get_vertices", "get_normals", "get_colors",
		"get_triangle_count",
	],
	"PlanetCoreConfig": [
		"diggable_rows", "get_subdivision", "set_subdivision", "get_materials",
		"set_materials", "get_shells", "set_shells",
	],
	"PlanetCoreMaterial": ["cuttable", "is_ore", "get_color", "get_hardness", "get_chunk_volume"],
	"PlanetCoreShell": ["get_rows", "get_base_material", "get_secondary_amount", "get_ores"],
	"PlanetCoreOre": ["get_material", "get_count_min", "get_size_max"],
	"PlanetCoreDeposit": ["get_cells", "get_cell_count", "get_exposed", "get_material_index"],
	"PlanetCoreGenerator": ["generate"],
}


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	print("planet_core extension")

	# 1) The library is loaded and every class is registered.
	_check(PlanetCore.available, "extension classes registered")
	if not PlanetCore.available:
		print("\n%d checks, %d failed" % [_checks, _fails])
		quit(1)
		return

	# 2) Public API surface.
	var missing := 0
	for cls: String in EXPECTED_API:
		if not ClassDB.class_exists(cls):
			missing += 1
			continue
		for m: String in EXPECTED_API[cls]:
			# Static functions are legitimate here (PlanetCoreGenerator.generate).
			if not ClassDB.class_has_method(cls, m, true):
				missing += 1
				print("    missing %s.%s" % [cls, m])
	_check(missing == 0, "public API complete (%d missing)" % missing)
	_check(ClassDB.can_instantiate("PlanetCoreMesher"), "PlanetCoreMesher is instantiable")
	_check(ClassDB.is_parent_class("PlanetCoreGrid", "RefCounted"), "PlanetCoreGrid is RefCounted")

	# 3) Build one chunk headlessly and print the triangle count (acceptance gate #4).
	var def: PlanetDef = load("res://data/planets/default_planet.tres")
	var ico := PlanetCore.build_icosphere(def.subdivision, def.patch_level)
	var grid := PlanetCore.build_grid(def, 42, ico)
	var mesher := PlanetCore.new_mesher()
	mesher.build_patch(grid, 3)
	var tris := mesher.get_triangle_count()
	print("  chunk 3: %d triangles" % tris)
	_check(tris > 0, "one chunk meshed headlessly (%d triangles)" % tris)
	_check(mesher.get_vertices().size() == tris * 3, "non-indexed triangle array (%d vertices)" % mesher.get_vertices().size())
	_check(mesher.get_normals().size() == tris * 3 and mesher.get_colors().size() == tris * 3,
			"normals and colours are parallel arrays")

	# 4) The mesher is reusable: a second chunk replaces the arrays rather than appending.
	var first := mesher.get_vertices().size()
	mesher.build_patch(grid, 4)
	_check(mesher.get_vertices().size() != 0 and mesher.get_triangle_count() > 0,
			"mesher reusable across chunks (was %d vertices)" % first)

	# 5) Lattice helpers behave like the reference.
	var idx := grid.world_to_lattice(grid.lattice_pos(1234))
	_check(idx == 1234, "world_to_lattice(lattice_pos(i)) == i (got %d)" % idx)
	_check(is_equal_approx(grid.surface_radius(), 31.5), "surface_radius %.2f" % grid.surface_radius())
	_check(grid.get_deposits().size() > 100, "deposits generated (%d)" % grid.get_deposits().size())
	_check(grid.dirty_count() == ico.get_patch_count(), "all patches dirty after generate (%d)" % grid.dirty_count())
	grid.clear_dirty()
	_check(grid.dirty_count() == 0, "clear_dirty empties the queue")
	grid.carve_sphere(Vector3(0, 31, 0), 3.0)
	_check(grid.dirty_count() > 0, "carving dirties patches (%d)" % grid.dirty_count())

	print("\n%d checks, %d failed, %d ms" % [_checks, _fails, Time.get_ticks_msec() - t0])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what)
