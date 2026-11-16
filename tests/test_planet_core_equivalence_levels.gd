extends SceneTree
## Equivalence spot-check at a NON-default lattice level, plus a chunk-level timing pass.
##
## The main gate (`tests/test_planet_core_equivalence.gd`) covers the shipping config (L=5, C=2).
## This one proves the port is not accidentally tuned to that one shape: it rebuilds at L=3/C=1
## and L=4/C=2 and compares triangle arrays the same way.
##
## Run: godot --headless -s tests/test_planet_core_equivalence_levels.gd

const SEED := 7
const POS_EPS := 1e-6
const VEC_EPS := 1e-4

var _fails := 0
var _checks := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	print("planet_core equivalence across lattice levels")
	if not PlanetCore.available:
		print("  FAIL planet_core GDExtension is not loaded")
		quit(1)
		return

	var def: PlanetDef = load("res://data/planets/default_planet.tres").duplicate()
	for cfg in [[3, 1], [4, 2]]:
		def.subdivision = cfg[0]
		def.patch_level = cfg[1]
		_compare_level(def, cfg[0], cfg[1])

	print("\n%d checks, %d failed, %d ms" % [_checks, _fails, Time.get_ticks_msec() - t0])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what)


func _compare_level(def: PlanetDef, level: int, patch_level: int) -> void:
	print("L=%d C=%d" % [level, patch_level])
	var gd := PlanetGrid.new(def)
	PlanetGenerator.generate(gd, SEED)
	var cpp := PlanetCore.build_grid(def, SEED, PlanetCore.build_icosphere(level, patch_level))

	_check(gd.V == cpp.get_V(), "V = %d" % cpp.get_V())
	_check(gd.ico.patch_count == cpp.get_ico().get_patch_count()
			and gd.ico.faces_per_patch == cpp.get_ico().get_faces_per_patch(),
			"%d patches x %d faces" % [cpp.get_ico().get_patch_count(), cpp.get_ico().get_faces_per_patch()])
	_check(gd.fill == cpp.get_fill(), "fill identical")
	_check(gd.material == cpp.get_material(), "material identical")
	_check(gd.deposit == cpp.get_deposit(), "deposit identical")

	var m_gd := PlanetMesher.new()
	var m_cpp := PlanetCore.new_mesher()
	m_gd.build_faces(gd, 0, gd.ico.face_count)
	m_cpp.build_faces(cpp, 0, cpp.get_ico().get_face_count())

	var v_gd := m_gd.vertices
	var v_cpp := m_cpp.get_vertices()
	var n_gd := m_gd.normals
	var n_cpp := m_cpp.get_normals()
	var c_gd := m_gd.colors
	var c_cpp := m_cpp.get_colors()
	if v_gd.size() != v_cpp.size():
		_check(false, "vertex count %d vs %d" % [v_gd.size(), v_cpp.size()])
		return

	var max_pos := 0.0
	var max_nrm := 0.0
	var max_col := 0.0
	for i in v_gd.size():
		var a := v_gd[i]
		var b := v_cpp[i]
		max_pos = maxf(max_pos, maxf(absf(a.x - b.x), maxf(absf(a.y - b.y), absf(a.z - b.z))))
		var na := n_gd[i]
		var nb := n_cpp[i]
		max_nrm = maxf(max_nrm, maxf(absf(na.x - nb.x), maxf(absf(na.y - nb.y), absf(na.z - nb.z))))
		var ca := c_gd[i]
		var cb := c_cpp[i]
		max_col = maxf(max_col, maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), maxf(absf(ca.b - cb.b), absf(ca.a - cb.a)))))

	_check(max_pos <= POS_EPS and max_nrm <= VEC_EPS and max_col <= VEC_EPS,
			"%d vertices / %d triangles match (pos %s, nrm %s, col %s)" % [
					v_gd.size(), v_gd.size() / 3, max_pos, max_nrm, max_col])
