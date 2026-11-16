extends SceneTree
## Headless boot of the real entry scene on the C++ planet core (acceptance gate #3).
##
## Prints proof that the extension is loaded and doing the meshing — not the GDScript fallback —
## plus triangle count and the build/rebuild timings.
##
## Run: godot --headless --fixed-fps 60 -s tests/test_planet_core_boot.gd

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	print("planet core boot (game/main.tscn)")
	_check(PlanetCore.available, "PlanetCore.available = %s" % PlanetCore.available)
	# ClassDB does not index GDScript `class_name`s, so check the script resource instead.
	_check(load("res://game/planet/planet_core_grid_data.gd") != null, "PlanetCoreGridData script loads")

	var main: Node3D = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)

	var planet: Planet = main.planet
	_check(planet != null, "main scene exposes a Planet")
	_check(planet.using_core_mesher, "planet.using_core_mesher = true (C++ path)")
	_check(planet.grid is PlanetCoreGridData, "grid is a C++ PlanetCoreGridData")
	_check(planet.core_chunk_builds > 0,
			"C++ mesher built %d chunks (proof it is not the GDScript fallback)" % planet.core_chunk_builds)
	_check(planet.chunks.size() == 320, "%d chunks" % planet.chunks.size())
	_check(planet.dirty_count() == 0, "dirty queue empty after the initial build")
	_check(planet.triangle_count() > 50000, "%d triangles" % planet.triangle_count())

	# Drive one carve so the incremental rebuild path is measured too, not just the initial one.
	var rig: GyroRig = main.rig
	rig.manual_control = false
	rig.aim_at(Vector3(0.3, 1.0, -0.2))
	await _frames(3)
	var before_builds := planet.core_chunk_builds
	rig.laser.active = true
	await _frames(120)
	rig.laser.active = false
	await _frames(10)
	_check(planet.core_chunk_builds > before_builds,
			"live carving rebuilt %d chunks through C++" % (planet.core_chunk_builds - before_builds))

	# Steady-state per-chunk cost: mesh + upload for every chunk, median and p90. The single
	# worst chunk in a burst is dominated by OS scheduling noise, so report the distribution.
	var stats := _chunk_stats(planet)
	print("  chunk rebuild        : median %.3f ms, p90 %.3f ms, worst %.3f ms (%d chunks)" % [
			stats.median, stats.p90, stats.worst, stats.n])

	print("\n-- measurements --")
	print("  PlanetCore.available : %s" % PlanetCore.available)
	print("  using_core_mesher    : %s" % planet.using_core_mesher)
	print("  C++ chunk builds     : %d" % planet.core_chunk_builds)
	print("  triangles            : %d" % planet.triangle_count())
	print("  initial_build_ms     : %d" % roundi(planet.initial_build_ms))
	print("  worst_chunk_ms       : %.3f" % planet.worst_chunk_ms)
	print("  last_rebuild_ms      : %.3f (%d chunks)" % [planet.last_rebuild_ms, planet.last_rebuild_count])
	print("  dirty queue          : %d" % planet.dirty_count())

	print("\n%d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


## Time every chunk's mesh + upload once, and return the distribution.
func _chunk_stats(planet: Planet) -> Dictionary:
	var data := planet.grid as PlanetCoreGridData
	data.mark_all_dirty()
	var times: Array[float] = []
	while data.dirty_count() > 0:
		var p := data.dirty_patch_at(data.dirty_count() - 1)
		var t := Time.get_ticks_usec()
		planet._mesher.build_patch(data, p)
		planet.chunks[p].apply(planet._mesher.get_vertices(), planet._mesher.get_normals(),
				planet._mesher.get_colors())
		times.append((Time.get_ticks_usec() - t) / 1000.0)
		data.clear_dirty_patch(p)
	times.sort()
	return {
		"n": times.size(),
		"median": times[times.size() / 2] if times.size() > 0 else 0.0,
		"p90": times[int(times.size() * 0.9)] if times.size() > 0 else 0.0,
		"worst": times[times.size() - 1] if times.size() > 0 else 0.0,
	}
