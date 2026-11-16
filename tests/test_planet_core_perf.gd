extends SceneTree
## Perf gate: proves the carve hot path uses indexed accessors rather than copying arrays.
##
## Run: godot --headless -s tests/test_planet_core_perf.gd
##
## The trap this guards: `PlanetCoreGrid.get_fill()` copies the whole lattice (~1 MB at L=5).
## Indexing `grid.fill[idx]` inside a carve loop therefore costs O(points) *per cell touched*,
## which is O(n²) per tick and would erase the port's win. This test measures both shapes of the
## access on the same grid and asserts the indexed one is orders of magnitude cheaper.

## Cells to touch per measurement. Enough to dwarf call overhead, small enough to stay quick.
const PROBES := 20000
## The indexed path must be at least this many times cheaper than a whole-array read per access.
const MIN_SPEEDUP := 100.0

var _fails := 0
var _checks := 0


func _init() -> void:
	print("planet_core perf (indexed accessors)")
	if not PlanetCore.available:
		print("  FAIL planet_core GDExtension is not loaded")
		quit(1)
		return

	var def: PlanetDef = load("res://data/planets/default_planet.tres")
	var grid := PlanetCoreGridData.new()
	grid.setup(PlanetCore.config_from_planet_def(def), PlanetCore.build_icosphere(
			def.subdivision, def.patch_level))
	PlanetCoreGenerator.generate(grid, 42)
	grid.invalidate()

	var points := grid.get_point_count()
	var stride := maxi(points / PROBES, 1)

	# (a) Indexed accessors: one load per cell.
	var acc_ind := 0.0
	var t := Time.get_ticks_usec()
	var i := 0
	while i < points:
		acc_ind += grid.fill_at(i) + float(grid.material_at(i)) + float(grid.corruption_at(i))
		i += stride
	var ms_ind := (Time.get_ticks_usec() - t) / 1000.0

	# (b) The trap: read the whole array, then index it once, per cell.
	var acc_raw := 0.0
	t = Time.get_ticks_usec()
	i = 0
	while i < points and i < stride * 32:  # cap: this is O(n) per access
		var all := grid.get_fill()
		acc_raw += all[i]
		i += stride
	var ms_raw := (Time.get_ticks_usec() - t) / 1000.0

	print("  %d indexed accesses in %.2f ms (%.3f us/access)" % [
			PROBES, ms_ind, ms_ind * 1000.0 / PROBES])
	print("  32 whole-array copies in %.2f ms (%.1f us/access)" % [
			ms_raw, ms_raw * 1000.0 / 32.0])
	_check(acc_ind > 0.0 and acc_raw > 0.0, "both access shapes return data")
	_check(ms_ind < 50.0, "indexed path stays linear (%.2f ms for %d accesses)" % [ms_ind, PROBES])

	# Per-access ratio. Both sides do the same number of *accesses*; the difference is that one
	# copies the lattice first. 32 whole-array reads vs 32 indexed reads keeps it quick and
	# still shows the ~1000x gap that makes the trap fatal.
	var copies := 32
	var idx_reads := 32
	var t2 := Time.get_ticks_usec()
	var sink := 0.0
	for k in copies:
		var all2 := grid.get_fill()
		sink += all2[k]
	var ms_copies := (Time.get_ticks_usec() - t2) / 1000.0
	t2 = Time.get_ticks_usec()
	for k in idx_reads:
		sink += grid.fill_at(k)
	var ms_idx := (Time.get_ticks_usec() - t2) / 1000.0
	var per_raw := ms_copies * 1000.0 / float(copies)
	var per_idx := ms_idx * 1000.0 / float(idx_reads)
	var speedup := per_raw / maxf(per_idx, 1e-6)
	print("  %.3f us/access indexed vs %.1f us/access via get_fill()[idx] (%.0fx cheaper, %d pts)" % [
			per_idx, per_raw, speedup, points])
	_check(sink > 0.0 and speedup >= MIN_SPEEDUP,
			"indexed accessors beat get_fill()[idx] by >= %dx (%.0fx)" % [int(MIN_SPEEDUP), speedup])

	# A full carve tick through the real code path, for the headline number.
	var laser: LaserTypeDef = load("res://data/lasers/plasma.tres")
	var lens: LensDef = load("res://data/lenses/wide.tres")
	var dir := Vector3(0.3, 1.0, -0.2).normalized()
	t = Time.get_ticks_usec()
	var result := LaserCarve.apply(grid, dir * grid.surface_radius(), -dir, laser, lens, 56.7, 1.0 / 60.0)
	var tick_ms := (Time.get_ticks_usec() - t) / 1000.0
	print("  one LaserCarve.apply() tick: %.3f ms (removed %.3f)" % [tick_ms, result.removed])
	_check(tick_ms < 20.0, "a carve tick stays well under a frame (%.3f ms)" % tick_ms)

	print("\n%d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what)
