extends SceneTree
## Headless smoke test for the extension: builds one chunk and prints the triangle count,
## then quits. Run with
##
##   godot --headless -s addons/planet_core/demo/planet_core_headless.gd
##
## Unlike the scene version this needs no renderer and no main scene, so it is also used by
## tests/test_planet_core.gd as a "the extension runs" check.

func _init() -> void:
	print("planet_core headless demo")
	if not PlanetCore.available:
		push_error("planet_core GDExtension is not loaded — build it with `scons` in addons/planet_core")
		quit(1)
		return
	var def: PlanetDef = load("res://data/planets/default_planet.tres")
	var t := Time.get_ticks_usec()
	var ico := PlanetCore.build_icosphere(def.subdivision, def.patch_level)
	var grid := PlanetCore.build_grid(def, 42, ico)
	var gen_ms := (Time.get_ticks_usec() - t) / 1000.0

	var mesher := PlanetCore.new_mesher()
	t = Time.get_ticks_usec()
	mesher.build_patch(grid, 7)
	var mesh_ms := (Time.get_ticks_usec() - t) / 1000.0

	var tris := mesher.get_vertices().size() / 3
	print("  planet: %d verts x %d rows = %d points, %d deposits" % [
			grid.get_V(), grid.get_rows(), grid.get_point_count(), grid.get_deposits().size()])
	print("  chunk 7: %d triangles" % tris)
	print("  build+generate %.1f ms, mesh %.2f ms" % [gen_ms, mesh_ms])
	print("  TRIANGLE COUNT: %d" % tris)
	quit(0 if tris > 0 else 1)
