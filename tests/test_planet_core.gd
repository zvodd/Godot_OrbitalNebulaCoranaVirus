extends SceneTree
## Headless checks for the planet core: icosphere invariants, lattice queries, generator,
## mesher watertightness / orientation, and carve-rate maths.
## Run: godot --headless -s tests/test_planet_core.gd

var _fails := 0
var _checks := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	_test_icosphere()
	var grid := _test_grid()
	_test_mesher(grid)
	_test_carve(grid)
	print("\n%d checks, %d failed, %d ms" % [_checks, _fails, Time.get_ticks_msec() - t0])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what)


func _test_icosphere() -> void:
	print("icosphere")
	var t := Time.get_ticks_msec()
	var ico := Icosphere.new(5, 2)
	print("  build %d ms" % (Time.get_ticks_msec() - t))
	_check(ico.vertex_count == 10242, "V = 10242 (got %d)" % ico.vertex_count)
	_check(ico.face_count == 20480, "F = 20480 (got %d)" % ico.face_count)
	_check(ico.patch_count == 320 and ico.faces_per_patch == 64, "320 patches x 64 faces")

	var v5 := 0
	var bad := 0
	for v in ico.vertex_count:
		var n := ico.valence(v)
		if n == 5:
			v5 += 1
		elif n != 6:
			bad += 1
	_check(v5 == 12 and bad == 0, "12 valence-5 vertices, rest valence 6")

	var asym := 0
	for v in ico.vertex_count:
		for j in range(ico.adj_offsets[v], ico.adj_offsets[v + 1]):
			var n := ico.adj[j]
			var back := false
			for jj in range(ico.adj_offsets[n], ico.adj_offsets[n + 1]):
				if ico.adj[jj] == v:
					back = true
					break
			if not back:
				asym += 1
	_check(asym == 0, "adjacency symmetric")

	var contiguous := true
	for f in ico.face_count:
		@warning_ignore("integer_division")
		if ico.face_patch[f] != f / ico.faces_per_patch:
			contiguous = false
			break
	_check(contiguous, "patch faces are contiguous ranges")

	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var mismatch := 0
	for i in 10000:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		if d.length_squared() < 1e-6:
			continue
		var a := ico.nearest_vertex(d)
		var b := ico.nearest_vertex_brute(d)
		if a != b and not is_equal_approx(d.normalized().dot(ico.verts[a]), d.normalized().dot(ico.verts[b])):
			mismatch += 1
	_check(mismatch == 0, "dir -> vertex lookup matches brute force on 10k dirs (%d mismatches)" % mismatch)
	print("  mean edge %.4f rad (%.2f units at r=31)" % [ico.mean_edge, ico.mean_edge * 31.0])


func _test_grid() -> PlanetGrid:
	print("grid + generator")
	var def: PlanetDef = load("res://data/planets/default_planet.tres")
	_check(def != null and def.shells.size() == 8, "default planet def loads with 8 shells")
	var t := Time.get_ticks_msec()
	var grid := PlanetGrid.new(def)
	PlanetGenerator.generate(grid, 42)
	print("  build + generate %d ms" % (Time.get_ticks_msec() - t))
	_check(grid.rows == 26, "24 diggable rows + core + air (got %d)" % grid.rows)
	_check(is_equal_approx(grid.row_radius(1), 8.0) and is_equal_approx(grid.row_radius(24), 31.0),
			"row radii 8..31")
	_check(is_equal_approx(grid.surface_radius(), 31.5), "surface radius 31.5")
	_check(grid.materials.size() == 7, "7 materials (got %d)" % grid.materials.size())
	_check(grid.deposits.size() > 100, "deposits placed (%d)" % grid.deposits.size())

	# Deposit bookkeeping is consistent.
	var bad := 0
	var exposed := 0
	for d in grid.deposits:
		if d.exposed:
			exposed += 1
		for idx in d.cells:
			if grid.deposit[idx] != d.id or grid.material[idx] != d.material_index:
				bad += 1
	_check(bad == 0, "deposit cells agree with lattice arrays")
	print("  %d deposits exposed at the surface" % exposed)

	# Determinism.
	var grid2 := PlanetGrid.new(def, grid.ico)
	PlanetGenerator.generate(grid2, 42)
	_check(grid2.material == grid.material and grid2.deposit == grid.deposit, "same seed -> same planet")

	# world <-> lattice round trip.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wrong := 0
	for i in 2000:
		var idx := rng.randi_range(0, grid.point_count - 1)
		if grid.world_to_lattice(grid.lattice_pos(idx)) != idx:
			wrong += 1
	_check(wrong == 0, "world_to_lattice(lattice_pos(i)) == i")

	# points_in_sphere vs brute force.
	var miss := 0
	for i in 20:
		var p := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * rng.randf_range(10.0, 32.0)
		var radius := rng.randf_range(0.8, 4.0)
		var got := {}
		for idx in grid.points_in_sphere(p, radius):
			got[idx] = true
		var want := 0
		for idx in grid.point_count:
			if grid.lattice_pos(idx).distance_to(p) <= radius:
				want += 1
				if not got.has(idx):
					miss += 1
		if want != got.size():
			miss += 1
	_check(miss == 0, "points_in_sphere matches brute force")
	return grid


func _mesh_report(m: PlanetMesher) -> Dictionary:
	# Every edge of a closed surface is shared by exactly two triangles, in opposite directions.
	var ids := {}
	var edges := {}
	var tri_count := m.vertices.size() / 3
	var degenerate := 0
	var inward := 0
	var volume := 0.0
	for t in tri_count:
		var tri := [0, 0, 0]
		for j in 3:
			var p := m.vertices[t * 3 + j]
			var id: int = ids.get(p, -1)
			if id < 0:
				id = ids.size()
				ids[p] = id
			tri[j] = id
		var a := m.vertices[t * 3]
		var b := m.vertices[t * 3 + 1]
		var c := m.vertices[t * 3 + 2]
		# Godot winding is clockwise-front, so flip the sign for outward-positive volume.
		volume -= a.dot(b.cross(c)) / 6.0
		if tri[0] == tri[1] or tri[1] == tri[2] or tri[0] == tri[2]:
			degenerate += 1
			continue
		var face_n := (c - a).cross(b - a)
		var vert_n := m.normals[t * 3] + m.normals[t * 3 + 1] + m.normals[t * 3 + 2]
		if face_n.dot(vert_n) < 0.0:
			inward += 1
		for j in 3:
			var u: int = tri[j]
			var v: int = tri[(j + 1) % 3]
			var key := (u << 32) | v
			edges[key] = int(edges.get(key, 0)) + 1
	var open := 0
	for key: int in edges:
		var rev := ((key & 0xFFFFFFFF) << 32) | (key >> 32)
		if edges[key] != 1 or int(edges.get(rev, 0)) != 1:
			open += 1
	return {"tris": tri_count, "open": open, "degenerate": degenerate, "inward": inward, "volume": volume}


func _test_mesher(grid: PlanetGrid) -> void:
	print("mesher")
	var m := PlanetMesher.new()
	var t := Time.get_ticks_usec()
	m.build_faces(grid, 0, grid.ico.face_count)
	var full_ms := (Time.get_ticks_usec() - t) / 1000.0
	var rep := _mesh_report(m)
	print("  whole planet: %d tris in %.0f ms" % [rep.tris, full_ms])
	_check(rep.tris > 0 and rep.open == 0, "intact planet is watertight (%d open edges)" % rep.open)
	_check(rep.inward == 0, "normals agree with winding (%d disagree)" % rep.inward)
	var sphere_vol := 4.0 / 3.0 * PI * pow(grid.surface_radius(), 3)
	_check(absf(rep.volume / sphere_vol - 1.0) < 0.02,
			"mesh volume %.0f ~ sphere %.0f (outward-facing)" % [rep.volume, sphere_vol])

	# Carve some craters, a deep shaft and a partial erosion, then re-check.
	var removed := grid.carve_sphere(Vector3(0, 31, 0), 4.0)
	removed += grid.carve_sphere(Vector3(20, 20, 8).normalized() * 30.0, 2.5)
	for depth in 12:
		removed += grid.carve_sphere(Vector3(-1, 0.2, 0.4).normalized() * (31.0 - depth * 1.5), 1.6)
	for idx in grid.points_in_sphere(Vector3(0, 0, 31), 3.0):
		removed += grid.erode(idx, 0.37)
	_check(removed > 100.0, "carving removes volume (%.0f cells)" % removed)
	_check(grid.shell_removed[0] > 0.0 and grid.cleared_fraction(0) > 0.0, "shell bookkeeping tracks removal")
	_check(not grid.dirty_patches.is_empty(), "carving marks patches dirty")

	m.build_faces(grid, 0, grid.ico.face_count)
	var rep2 := _mesh_report(m)
	_check(rep2.open == 0, "carved planet is still watertight (%d open edges, %d tris)" % [rep2.open, rep2.tris])
	# Gradient normals are smooth, so a few sliver triangles on sharp crater rims disagree.
	_check(rep2.inward < rep2.tris / 200, "carved normals agree with winding (%d of %d disagree)" % [rep2.inward, rep2.tris])
	_check(rep2.volume < rep.volume, "carved mesh volume shrank (%.0f -> %.0f)" % [rep.volume, rep2.volume])

	# Per-chunk timing over the dirty set (the in-game rebuild path).
	var worst := 0.0
	var total := 0.0
	var n := 0
	for patch: int in grid.dirty_patches:
		t = Time.get_ticks_usec()
		m.build_patch(grid, patch)
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		worst = maxf(worst, ms)
		total += ms
		n += 1
	print("  chunk rebuild: %d chunks, avg %.2f ms, worst %.2f ms (target <= 8 ms)" % [n, total / maxi(n, 1), worst])
	grid.dirty_patches.clear()


func _test_carve(grid: PlanetGrid) -> void:
	print("carve maths")
	var thermal: LaserTypeDef = load("res://data/lasers/thermal.tres")
	var plasma: LaserTypeDef = load("res://data/lasers/plasma.tres")
	var ion: LaserTypeDef = load("res://data/lasers/ion.tres")
	var standard: LensDef = load("res://data/lenses/standard.tres")
	var pin: LensDef = load("res://data/lenses/pin.tres")
	var wide: LensDef = load("res://data/lenses/wide.tres")
	_check(thermal != null and plasma != null and ion != null and standard != null and pin != null and wide != null,
			"laser + lens defs load")

	var sand := grid.materials[_mat(grid, "Sand")]
	var rock := grid.materials[_mat(grid, "Rock")]
	_check(LaserCarve.cell_power(thermal, standard) >= sand.min_power, "Thermal + Standard cuts sand")
	_check(LaserCarve.cell_power(thermal, pin) < rock.min_power, "Thermal cannot cut rock, even with Pin")
	_check(LaserCarve.cell_power(plasma, standard) >= rock.min_power, "Plasma + Standard cuts rock")
	_check(LaserCarve.cell_power(plasma, wide) < rock.min_power, "Plasma + Wide is too thin for rock")
	_check(LaserCarve.cell_power(thermal, pin) > LaserCarve.cell_power(thermal, standard)
			and LaserCarve.cell_power(thermal, standard) > LaserCarve.cell_power(thermal, wide),
			"per-cell power: Pin > Standard > Wide")

	var orbit := grid.surface_radius() * 1.8
	var dt := 1.0 / 60.0

	# A fresh patch of pure sand / pure rock so the result doesn't depend on the seed.
	var sand_hit := _paint(grid, Vector3(1, -1, 0.3).normalized(), _mat(grid, "Sand"))
	var rock_hit := _paint(grid, Vector3(-0.3, -1, -1).normalized(), _mat(grid, "Rock"))

	var r := LaserCarve.apply(grid, sand_hit, -sand_hit.normalized(), thermal, standard, orbit, dt)
	var expected_rate := LaserCarve.cell_power(thermal, standard) / sand.hardness
	_check(r.removed > 0.0 and r.cut_material == _mat(grid, "Sand"), "one tick of Thermal erodes sand")
	_check(r.removed <= expected_rate * dt * 30.0, "sand erodes slowly, not instantly (%.4f / tick)" % r.removed)

	r = LaserCarve.apply(grid, rock_hit, -rock_hit.normalized(), thermal, standard, orbit, dt)
	_check(r.removed == 0.0 and r.blocked == LaserCarve.Block.TOO_HARD, "Thermal only scorches rock")
	r = LaserCarve.apply(grid, rock_hit, -rock_hit.normalized(), plasma, standard, orbit, dt)
	_check(r.removed > 0.0, "Plasma cuts the same rock")

	# Instant removal when rate >= instant_threshold.
	var before := grid.fill[grid.world_to_lattice(sand_hit.normalized() * 31.0)]
	r = LaserCarve.apply(grid, sand_hit, -sand_hit.normalized(), ion, pin, orbit, dt)
	var after := grid.fill[grid.world_to_lattice(sand_hit.normalized() * 31.0)]
	_check(before > 0.0 and after == 0.0, "Ion + Pin removes sand instantly")

	# Layer by layer: buried cells are untouched until the layer above is gone.
	var buried := grid.world_to_lattice(rock_hit.normalized() * 29.0)
	_check(grid.fill[buried] == 1.0, "buried cells are not cut through the layer above")

	# Reach: bore straight down with Ion until nothing more can be cut.
	var dir := Vector3(0.5, 0.5, -0.7).normalized()
	var min_r := LaserCarve.min_cut_radius(thermal, orbit)
	var hit_r := grid.surface_radius()
	var blocked := LaserCarve.Block.NONE
	for i in 4000:
		hit_r = _surface_along(grid, dir)
		# Thermal reach with Ion power, so only reach can stop it.
		var deep := LaserTypeDef.new()
		deep.power = ion.power
		deep.reach = thermal.reach
		r = LaserCarve.apply(grid, dir * hit_r, -dir, deep, standard, orbit, 0.1)
		if r.removed == 0.0:
			blocked = r.blocked
			break
	_check(blocked == LaserCarve.Block.OUT_OF_REACH, "boring stops with OUT_OF_REACH")
	_check(hit_r > min_r - 1.6 and hit_r < min_r + 1.6,
			"shaft floor %.1f is at the reach limit %.1f" % [hit_r, min_r])

	# Ore accounting: cutting a deposit queues chunks, vaporized ore does not.
	grid.pending_ore.clear()
	var dep: Deposit = null
	for d in grid.deposits:
		if d.shell == 0 and d.mined == 0.0 and d.cells.size() >= 30:
			dep = d
			break
	var m := grid.materials[dep.material_index]
	var cut := 0.0
	for idx in dep.cells:
		cut += grid.erode(idx, 1.0)
	var want := int(cut / m.chunk_volume)
	_check(grid.pending_ore.size() == want and want > 0,
			"cutting %.0f ore queues %d chunks (got %d)" % [cut, want, grid.pending_ore.size()])
	_check(dep.exposed or cut > 0.0, "deposit bookkeeping survives mining")


func _mat(grid: PlanetGrid, mat_name: String) -> int:
	for i in grid.materials.size():
		if grid.materials[i].name == mat_name:
			return i
	return -1


## Force a clean, solid column region of one material; returns the surface hit point.
func _paint(grid: PlanetGrid, dir: Vector3, mi: int) -> Vector3:
	for idx in grid.points_in_sphere(dir * 30.0, 5.0):
		@warning_ignore("integer_division")
		var k := idx / grid.V
		if grid.is_diggable_row(k):
			grid.fill[idx] = 1.0
			grid.material[idx] = mi
			grid.deposit[idx] = -1
			grid.touch(idx)
	return dir * grid.surface_radius()


## Radius where the solid surface is along a direction (walk down from the top).
func _surface_along(grid: PlanetGrid, dir: Vector3) -> float:
	var v := grid.ico.nearest_vertex(dir)
	for k in range(grid.rows - 1, -1, -1):
		if grid.fill[k * grid.V + v] >= PlanetGrid.ISO:
			return grid.row_radius(k) + 0.5 * grid.dr
	return grid.r0
