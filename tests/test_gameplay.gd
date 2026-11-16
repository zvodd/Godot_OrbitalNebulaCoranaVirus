extends SceneTree
## Headless end-to-end check of the main scene: the planet builds, the laser digs, ore
## chunks drop and rest on the terrain, and the tractor beam hauls them to the collector.
## Run: godot --headless --fixed-fps 60 -s tests/test_gameplay.gd

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
	var main: Node3D = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	var planet: Planet = main.planet
	var rig: GyroRig = main.rig
	var grid := planet.grid
	rig.manual_control = false

	print("core")
	_check(planet.using_core_mesher, "planet runs on the C++ planet_core mesher")
	_check(grid is PlanetCoreGridData, "grid is a PlanetCoreGridData (%s)" % grid.get_class())

	print("scene")
	_check(planet.chunks.size() == 320, "320 chunks")
	_check(planet.triangle_count() > 50000, "planet meshed (%d tris, built in %d ms)" % [
		planet.triangle_count(), roundi(planet.initial_build_ms)])
	_check(planet.dirty_count() == 0, "nothing dirty after the initial build")
	_check(absf(rig.orbit_radius - grid.surface_radius() * 1.8) < 0.01, "orbit radius = surface x 1.8 (%.1f)" % rig.orbit_radius)

	print("aim")
	rig.aim_at(Vector3(0.3, 1.0, -0.2))
	await _frames(3)
	var laser := rig.laser
	_check(laser.has_hit, "laser ray hits the terrain collider")
	var hit_r := laser.hit_point.length()
	_check(absf(hit_r - grid.surface_radius()) < 0.3, "hit is on the surface (r=%.2f)" % hit_r)
	# Poles included.
	rig.aim_at(Vector3.UP)
	await _frames(3)
	_check(laser.has_hit and absf(laser.hit_point.normalized().dot(Vector3.UP)) > 0.999, "can aim straight at the pole")

	print("laser: sand vs rock")
	var sand := _mat(grid, "Sand")
	var rock := _mat(grid, "Rock")
	var sand_dir := Vector3(1, 0.2, 0.1).normalized()
	_paint(grid, sand_dir, sand)
	planet.flush()
	rig.aim_at(sand_dir)
	rig.select_laser(0)
	await _frames(3)
	var r0 := laser.hit_point.length()
	var removed0: float = grid.shell_removed[0]
	laser.active = true
	await _frames(240)
	var r1 := laser.hit_point.length()
	var removed1: float = grid.shell_removed[0]
	_check(removed1 > removed0 + 1.0, "4 s of Thermal removes sand (%.1f cells)" % (removed1 - removed0))
	_check(r1 < r0 - 0.5, "the pit got deeper under the beam (r %.2f -> %.2f)" % [r0, r1])
	_check(r1 > LaserCarve.min_cut_radius(rig.current_laser(), rig.orbit_radius) - 1.0, "...but not past the laser's reach")
	# The pit should be as wide as the lens, not a pinhole: check a cell off-axis at the rim.
	var side := sand_dir.cross(Vector3.UP).normalized()
	var rim: int = grid.world_to_lattice(sand_dir * 31.0 + side * 1.2)
	_check(not grid.is_solid_at(rim), "pit is beam-width at the rim (fill %.2f at 1.2 off-axis)" % grid.fill_at(rim))
	_check(planet.dirty_count() < 8, "dirty chunks keep up with the frame budget (%d queued)" % planet.dirty_count())
	laser.active = false

	var rock_dir := Vector3(-1, 0.1, 0.3).normalized()
	_paint(grid, rock_dir, rock)
	planet.flush()
	rig.aim_at(rock_dir)
	await _frames(3)
	var before: float = grid.shell_removed[0]
	laser.active = true
	await _frames(60)
	_check(grid.shell_removed[0] == before, "Thermal cannot cut rock")
	_check(laser.last_result != null and laser.last_result.blocked == LaserCarve.Block.TOO_HARD, "...and reports TOO_HARD")
	rig.select_laser(1)
	await _frames(120)
	_check(grid.shell_removed[0] > before, "Plasma cuts it")
	laser.active = false

	print("ore chunks + tractor")
	var copper := _mat(grid, "Copper")
	var ore_dir := Vector3(0.1, -1, 0.4).normalized()
	_paint(grid, ore_dir, copper, 3.0)
	planet.flush()
	rig.aim_at(ore_dir)
	rig.select_laser(1)
	await _frames(3)
	laser.active = true
	await _frames(300)
	laser.active = false
	var field: OreField = main.ore_field
	var spawned := field.live_count()
	_check(spawned > 0, "cutting ore drops chunks (%d)" % spawned)
	_check(main.collector.totals.is_empty(), "nothing is collected without the tractor")
	await _frames(240)
	var resting := 0
	for c in field.get_children():
		var cp: Vector3 = c.global_position
		# Resting = above the core, below the rim, and sitting in an air cell near the pit.
		if cp.length() > grid.core_surface_radius() and cp.length() < grid.surface_radius() + 2.0 \
				and not grid.is_solid_at(grid.world_to_lattice(cp)) \
				and cp.normalized().dot(ore_dir) > 0.97:
			resting += 1
	_check(resting == field.live_count() and resting > 0, "chunks rest in the pit, not through the planet (%d of %d)" % [resting, field.live_count()])

	rig.tractor.active = true
	await _frames(600)
	rig.tractor.active = false
	var got := float(main.collector.totals.get(&"copper", 0.0))
	_check(got > 0.0, "tractor beam delivers ore to the collector (%d copper, %d still loose)" % [int(got), field.live_count()])

	print("regenerate")
	planet.build(999)
	await _frames(3)
	_check(planet.grid != grid and field.live_count() == 0 and planet.triangle_count() > 50000, "new planet rebuilds cleanly")

	print("\n%d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _mat(grid: RefCounted, mat_name: String) -> int:
	var core := grid as PlanetCoreGridData
	if core != null:
		for i in core.material_count():
			if core.material_at_index(i).get_name() == mat_name:
				return i
		return -1
	var g := grid as PlanetGrid
	for i in g.materials.size():
		if g.materials[i].name == mat_name:
			return i
	return -1


## Make a solid patch of one material under `dir` so the test doesn't depend on the seed.
## Uses the indexed setters on the C++ grid: writing through `grid.fill[idx]` would need a
## per-cell cache flush and is exactly the pattern the port exists to avoid.
func _paint(grid: RefCounted, dir: Vector3, mi: int, radius: float = 5.0) -> void:
	var core := grid as PlanetCoreGridData
	var dep: RefCounted = null
	var is_ore: bool = (core.material_at_index(mi) if core != null else (grid as PlanetGrid).materials[mi]).is_ore()
	if is_ore:
		dep = core.new_deposit(mi, 0) if core != null else _gd_deposit(grid)
	for idx in grid.points_in_sphere(dir * 30.0, radius):
		@warning_ignore("integer_division")
		var k: int = idx / grid.get_V()
		if grid.is_diggable_row(k):
			if core != null:
				core.set_fill_at(idx, 1.0)
				core.set_material_at(idx, mi)
				core.set_deposit_at(idx, dep.get_id() if dep != null else -1)
				if dep != null:
					dep.append_cell(idx)
			else:
				var g := grid as PlanetGrid
				g.fill[idx] = 1.0
				g.material[idx] = mi
				g.deposit[idx] = dep.id if dep != null else -1
				if dep != null:
					dep.cells.append(idx)
			if core != null:
				core.touch_cell(idx)
			else:
				grid.touch(idx)
	if core != null:
		core.flush()


func _gd_deposit(grid: RefCounted) -> Deposit:
	var g := grid as PlanetGrid
	var dep := Deposit.new()
	dep.id = g.deposits.size()
	g.deposits.append(dep)
	return dep
