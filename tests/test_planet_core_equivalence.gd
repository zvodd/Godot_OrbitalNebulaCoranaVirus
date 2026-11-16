extends SceneTree
## EQUIVALENCE GATE (hard acceptance gate #2).
##
## Builds the same planet twice from the same seed/config — once with the GDScript
## `Icosphere` / `PlanetGrid` / `PlanetMesher` reference, once with the `planet_core`
## C++ extension — and asserts the triangle arrays match:
##   * positions within 1e-6 (and reports how many are bit-identical)
##   * normals within 1e-4
##   * colors within 1e-4
##
## Run: godot --headless -s tests/test_planet_core_equivalence.gd
## Exits non-zero on any failure, so it can gate a commit.

const SEED := 42
## World-space tolerance for positions (gate: 1e-6).
const POS_EPS := 1e-6
## Tolerance for normals and colours (gate: 1e-4).
const VEC_EPS := 1e-4

var _fails := 0
var _checks := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	print("planet_core equivalence gate")
	if not PlanetCore.available:
		print("  FAIL planet_core GDExtension is not loaded (run `scons` in addons/planet_core)")
		quit(1)
		return

	var def: PlanetDef = load("res://data/planets/default_planet.tres")
	_check(def != null, "default planet def loads")

	_compare_icosphere(def)
	var g := _build_gdscript(def)
	var c := PlanetCore.build_grid(def, SEED, PlanetCore.build_icosphere(def.subdivision, def.patch_level))
	_compare_arrays(g, c)

	var m_gd := PlanetMesher.new()
	var m_cpp := PlanetCore.new_mesher()
	_compare_whole_planet(g, c, m_gd, m_cpp)
	_compare_carved(g, c, m_gd, m_cpp)

	print("\n%d checks, %d failed, %d ms" % [_checks, _fails, Time.get_ticks_msec() - t0])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what)


# --- reference build (GDScript) ---------------------------------------------

func _build_gdscript(def: PlanetDef) -> PlanetGrid:
	var grid := PlanetGrid.new(def)
	PlanetGenerator.generate(grid, SEED)
	return grid


# --- comparison helpers -----------------------------------------------------

func _compare_icosphere(def: PlanetDef) -> void:
	print("icosphere")
	var gd := Icosphere.new(def.subdivision, def.patch_level)
	var cpp := PlanetCore.build_icosphere(def.subdivision, def.patch_level)
	_check(gd.vertex_count == cpp.get_vertex_count(), "vertex_count %d == %d" % [gd.vertex_count, cpp.get_vertex_count()])
	_check(gd.face_count == cpp.get_face_count(), "face_count %d == %d" % [gd.face_count, cpp.get_face_count()])
	_check(gd.patch_count == cpp.get_patch_count() and gd.faces_per_patch == cpp.get_faces_per_patch(),
			"patch layout %dx%d" % [cpp.get_patch_count(), cpp.get_faces_per_patch()])
	_check(gd.verts == cpp.get_verts(), "verts bit-identical")
	_check(gd.faces == cpp.get_faces(), "faces identical")
	_check(gd.face_patch == cpp.get_face_patch(), "face_patch identical")
	_check(gd.adj_offsets == cpp.get_adj_offsets() and gd.adj == cpp.get_adj(), "adjacency CSR identical")
	_check(gd.dirty_offsets == cpp.get_dirty_offsets() and gd.dirty_patches == cpp.get_dirty_patches(),
			"dirty-patch CSR identical")
	_check(is_equal_approx(gd.mean_edge, cpp.get_mean_edge()), "mean_edge %.17f" % cpp.get_mean_edge())


func _compare_arrays(gd: PlanetGrid, cpp: PlanetCoreGrid) -> void:
	print("lattice + generator")
	_check(gd.V == cpp.get_V() and gd.rows == cpp.get_rows(), "lattice %dV x %d rows" % [cpp.get_V(), cpp.get_rows()])
	_check(gd.point_count == cpp.get_point_count(), "point_count %d" % cpp.get_point_count())

	var fill_gd := gd.fill
	var fill_cpp := cpp.get_fill()
	var fill_diff := _max_float_delta(fill_gd, fill_cpp)
	_check(fill_gd.size() == fill_cpp.size() and fill_diff == 0.0,
			"fill identical (%d values, max delta %s)" % [fill_cpp.size(), fill_diff])
	_check(gd.material == cpp.get_material(), "material identical")
	_check(gd.deposit == cpp.get_deposit(), "deposit identical")
	_check(gd.corruption == cpp.get_corruption(), "corruption identical")
	_check(gd.mat_colors == cpp.get_mat_colors(), "material colours identical")
	_check(gd.shell_of_row == cpp.get_shell_of_row(), "shell_of_row identical")

	var deps_gd := gd.deposits
	var deps_cpp := cpp.get_deposits()
	_check(deps_gd.size() == deps_cpp.size(), "deposit count %d == %d" % [deps_gd.size(), deps_cpp.size()])
	var bad := 0
	var exposed := 0
	if deps_gd.size() == deps_cpp.size():
		for i in deps_gd.size():
			var a: Deposit = deps_gd[i]
			var b: PlanetCoreDeposit = deps_cpp[i]
			if a.id != b.id or a.material_index != b.material_index or a.shell != b.shell \
					or a.exposed != b.exposed or a.cells != b.get_cells():
				bad += 1
			if b.exposed:
				exposed += 1
	_check(bad == 0, "deposits match cell for cell (%d bad, %d exposed)" % [bad, exposed])

	# Gradient is the normals' source, so check it directly on a sample.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4321
	var gmax := 0.0
	for i in 400:
		var idx := rng.randi_range(0, gd.point_count - 1)
		var a := gd.gradient(idx)
		var b := cpp.gradient(idx)
		gmax = maxf(gmax, maxf(absf(a.x - b.x), maxf(absf(a.y - b.y), absf(a.z - b.z))))
	_check(gmax <= POS_EPS, "gradient matches (%d samples, max delta %s)" % [400, gmax])

	# Queries.
	var qbad := 0
	for i in 12:
		var p := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * rng.randf_range(10.0, 32.0)
		var radius := rng.randf_range(0.8, 4.0)
		if gd.points_in_sphere(p, radius) != cpp.points_in_sphere(p, radius):
			qbad += 1
	_check(qbad == 0, "points_in_sphere identical on 12 spheres (%d differ)" % qbad)

	# Erosion path: same result on both, and identical bookkeeping.
	var mism := 0
	for i in 200:
		var idx := rng.randi_range(0, gd.point_count - 1)
		var amount := rng.randf_range(0.0, 1.5)
		var a := gd.erode(idx, amount)
		var b := cpp.erode(idx, amount)
		if a != b:
			mism += 1
	_check(mism == 0, "erode() returns identical amounts (%d differ)" % mism)
	_check(gd.fill == cpp.get_fill(), "fill identical after 200 erosions")
	_check(gd.deposit == cpp.get_deposit(), "deposit identical after 200 erosions")
	var ore_gd := gd.pending_ore
	var ore_cpp := cpp.get_pending_ore()
	_check(ore_gd == ore_cpp, "pending_ore identical after 200 erosions (%d chunks)" % ore_cpp.size())
	_check(_same_floats(gd.shell_removed, cpp.get_shell_removed()), "shell_removed identical")


## Compare one whole-planet mesh (full face range) plus every per-patch mesh.
func _compare_whole_planet(gd: PlanetGrid, cpp: PlanetCoreGrid, m_gd: PlanetMesher, m_cpp: PlanetCoreMesher) -> void:
	print("mesher (whole planet)")
	var t := Time.get_ticks_usec()
	m_gd.build_faces(gd, 0, gd.ico.face_count)
	var gd_ms := (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	m_cpp.build_faces(cpp, 0, cpp.get_ico().get_face_count())
	var cpp_ms = (Time.get_ticks_usec() - t) / 1000.0
	var r := _compare_mesh(m_gd, m_cpp, "whole planet")
	_check(r.tris > 0, "whole planet produced triangles (%d)" % r.tris)
	print("  GDScript %.1f ms, C++ %.1f ms (%.1fx)" % [gd_ms, cpp_ms, gd_ms / maxf(cpp_ms, 0.001)])

	print("mesher (per patch)")
	var bad := 0
	var worst := 0.0
	var tris := 0
	for patch in gd.ico.patch_count:
		m_gd.build_patch(gd, patch)
		m_cpp.build_patch(cpp, patch)
		var pr := _compare_mesh(m_gd, m_cpp, "patch %d" % patch, false)
		tris += pr.tris
		worst = maxf(worst, pr.max_pos)
		if not pr.ok:
			bad += 1
		if bad > 0:
			break
	_check(bad == 0, "all %d patches match (worst position delta %s, %d triangles total)" % [gd.ico.patch_count, worst, tris])


## Carve the same craters on both grids, then re-mesh and compare. This is the path the game
## actually uses (dirty patches after laser cuts).
func _compare_carved(gd: PlanetGrid, cpp: PlanetCoreGrid, m_gd: PlanetMesher, m_cpp: PlanetCoreMesher) -> void:
	print("mesher (carved)")
	gd.dirty_patches.clear()
	cpp.clear_dirty()
	var removed_gd := 0.0
	var removed_cpp := 0.0
	removed_gd += gd.carve_sphere(Vector3(0, 31, 0), 4.0)
	removed_cpp += cpp.carve_sphere(Vector3(0, 31, 0), 4.0)
	removed_gd += gd.carve_sphere(Vector3(20, 20, 8).normalized() * 30.0, 2.5)
	removed_cpp += cpp.carve_sphere(Vector3(20, 20, 8).normalized() * 30.0, 2.5)
	for depth in 12:
		var p := Vector3(-1, 0.2, 0.4).normalized() * (31.0 - depth * 1.5)
		removed_gd += gd.carve_sphere(p, 1.6)
		removed_cpp += cpp.carve_sphere(p, 1.6)
	_check(removed_gd == removed_cpp, "carve_sphere removed the same volume (%.3f)" % removed_cpp)
	_check(gd.fill == cpp.get_fill(), "fill identical after carving")
	_check(_same_keys(gd.dirty_patches, cpp.get_dirty_patches()),
			"same dirty set after carving (%d patches)" % cpp.dirty_count())

	m_gd.build_faces(gd, 0, gd.ico.face_count)
	m_cpp.build_faces(cpp, 0, cpp.get_ico().get_face_count())
	_compare_mesh(m_gd, m_cpp, "carved planet")

	# Corrupted cells must tint the same way.
	for idx in gd.points_in_sphere(Vector3(0, 0, 31), 3.0):
		if gd.corruption[idx] == 0 and gd.is_solid(idx):
			gd.corruption[idx] = 40
			cpp.set_corruption(_paint_corruption(cpp, idx, 40))
			break
	m_gd.build_faces(gd, 0, gd.ico.face_count)
	m_cpp.build_faces(cpp, 0, cpp.get_ico().get_face_count())
	_compare_mesh(m_gd, m_cpp, "corrupted planet")


## Set one corruption byte on the C++ grid, returning the whole array (the binding takes the
## full buffer so the extension stays a plain array owner).
func _paint_corruption(cpp: PlanetCoreGrid, idx: int, value: int) -> PackedByteArray:
	var c := cpp.get_corruption()
	c[idx] = value
	return c


func _compare_mesh(m_gd: PlanetMesher, m_cpp: PlanetCoreMesher, label: String, report: bool = true) -> Dictionary:
	var v_gd := m_gd.vertices
	var v_cpp := m_cpp.get_vertices()
	var n_gd := m_gd.normals
	var n_cpp := m_cpp.get_normals()
	var c_gd := m_gd.colors
	var c_cpp := m_cpp.get_colors()

	var ok := true
	var tris := 0
	var max_pos := 0.0
	var max_nrm := 0.0
	var max_col := 0.0
	var bit_pos := 0
	var bit_nrm := 0
	var bit_col := 0

	if v_gd.size() != v_cpp.size() or n_gd.size() != n_cpp.size() or c_gd.size() != c_cpp.size():
		if report:
			_check(false, "%s: vertex count %d vs %d (normals %d/%d, colours %d/%d)" % [
					label, v_gd.size(), v_cpp.size(), n_gd.size(), n_cpp.size(), c_gd.size(), c_cpp.size()])
		return {"ok": false, "tris": 0, "max_pos": 0.0, "max_nrm": 0.0, "max_col": 0.0}

	tris = v_gd.size() / 3
	for i in v_gd.size():
		var a := v_gd[i]
		var b := v_cpp[i]
		if a == b:
			bit_pos += 1
		var dp := maxf(absf(a.x - b.x), maxf(absf(a.y - b.y), absf(a.z - b.z)))
		if dp > max_pos:
			max_pos = dp

		var na := n_gd[i]
		var nb := n_cpp[i]
		if na == nb:
			bit_nrm += 1
		var dn := maxf(absf(na.x - nb.x), maxf(absf(na.y - nb.y), absf(na.z - nb.z)))
		if dn > max_nrm:
			max_nrm = dn

		var ca := c_gd[i]
		var cb := c_cpp[i]
		if ca == cb:
			bit_col += 1
		var dc := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), maxf(absf(ca.b - cb.b), absf(ca.a - cb.a))))
		if dc > max_col:
			max_col = dc

	if max_pos > POS_EPS or max_nrm > VEC_EPS or max_col > VEC_EPS:
		ok = false
	if not ok:
		_check(false, "%s: %d tris, max delta pos %s nrm %s col %s" % [label, tris, max_pos, max_nrm, max_col])
	elif report:
		_check(true, "%s: %d vertices / %d triangles, max delta pos %s (bit-identical %d/%d), nrm %s (%d), col %s (%d)" % [
				label, v_gd.size(), tris, max_pos, bit_pos, v_gd.size(), max_nrm, bit_nrm, max_col, bit_col])

	return {"ok": ok, "tris": tris, "max_pos": max_pos, "max_nrm": max_nrm, "max_col": max_col}


func _max_float_delta(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size():
		return INF
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst


## Element-wise float comparison for `Array[float]` vs `PackedFloat64Array` (bit-exact).
func _same_floats(a: Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


## The GDScript grid keeps dirty patches in a Dictionary; the extension keeps an ordered list.
## Compare them as sets.
func _same_keys(gd_dirty: Dictionary, cpp_dirty: PackedInt32Array) -> bool:
	if gd_dirty.size() != cpp_dirty.size():
		return false
	for k: int in gd_dirty.keys():
		if not cpp_dirty.has(k):
			return false
	return true
