class_name PlanetMesher
extends RefCounted
## Marching tetrahedra over the lattice's triangular prisms (ROADMAP §5.1).
## Pure data: PlanetGrid arrays in → triangle arrays out. No nodes, no rendering types,
## so it can be threaded or ported later.
##
## Each icosphere face × row gap is a prism, split into 3 tets using global vertex order
## (v0 < v1 < v2; b = bottom row, t = top row):
##   T1 = (v0b, v1b, v2b, v0t)   T2 = (v1b, v2b, v0t, v1t)   T3 = (v2b, v0t, v1t, v2t)
## The diagonal on every quad side depends only on the shared edge, so neighbouring
## prisms agree and the mesh is watertight.

const ISO := 0.5
## Colour multiplier for corrupted cells.
const CORRUPT_TINT := Color(0.28, 0.1, 0.34)

# For each 4-bit inside mask: a corner permutation (a, b, c, d).
#  kind 1: a is the lone inside corner.   kind 3: a is the lone outside corner.
#  kind 2: a, b inside; c, d outside.
static var _PERM := PackedInt32Array([
	0, 1, 2, 3,  # 0000 (unused)
	0, 1, 2, 3,  # 0001  in: 0
	1, 0, 2, 3,  # 0010  in: 1
	0, 1, 2, 3,  # 0011  in: 0 1
	2, 0, 1, 3,  # 0100  in: 2
	0, 2, 1, 3,  # 0101  in: 0 2
	1, 2, 0, 3,  # 0110  in: 1 2
	3, 0, 1, 2,  # 0111  out: 3
	3, 0, 1, 2,  # 1000  in: 3
	0, 3, 1, 2,  # 1001  in: 0 3
	1, 3, 0, 2,  # 1010  in: 1 3
	2, 0, 1, 3,  # 1011  out: 2
	2, 3, 0, 1,  # 1100  in: 2 3
	1, 0, 2, 3,  # 1101  out: 1
	0, 1, 2, 3,  # 1110  out: 0
	0, 1, 2, 3,  # 1111 (unused)
])
static var _KIND := PackedInt32Array([0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 0])

var vertices: PackedVector3Array
var normals: PackedVector3Array
var colors: PackedColorArray

var _grid: PlanetGrid
var _fill: PackedFloat32Array
var _verts: PackedVector3Array
var _V: int
var _r0: float
var _dr: float

var _ti := PackedInt32Array([0, 0, 0, 0])
var _tf := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
# Scratch slots for the (up to 4) iso crossings of the current tet.
var _sp := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var _sn := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var _sc := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])


## Mesh one patch (chunk). Results are left in `vertices`, `normals`, `colors`
## (non-indexed triangles, Godot clockwise-front winding).
func build_patch(grid: PlanetGrid, patch: int) -> void:
	var begin := grid.ico.patch_face_begin(patch)
	build_faces(grid, begin, begin + grid.ico.faces_per_patch)


## Mesh a contiguous range of icosphere faces.
func build_faces(grid: PlanetGrid, face_begin: int, face_end: int) -> void:
	vertices = PackedVector3Array()
	normals = PackedVector3Array()
	colors = PackedColorArray()
	_grid = grid
	_fill = grid.fill
	_verts = grid.ico.verts
	_V = grid.V
	_r0 = grid.r0
	_dr = grid.dr

	var fill := _fill
	var faces := grid.ico.faces
	var V := _V
	var gaps := grid.rows - 1
	for f in range(face_begin, face_end):
		var v0 := faces[f * 3]
		var v1 := faces[f * 3 + 1]
		var v2 := faces[f * 3 + 2]
		var tmp: int
		if v0 > v1:
			tmp = v0; v0 = v1; v1 = tmp
		if v1 > v2:
			tmp = v1; v1 = v2; v2 = tmp
		if v0 > v1:
			tmp = v0; v0 = v1; v1 = tmp

		var b0 := fill[v0]
		var b1 := fill[v1]
		var b2 := fill[v2]
		var nb := int(b0 >= ISO) + int(b1 >= ISO) + int(b2 >= ISO)
		var base := 0
		for k in gaps:
			var top := base + V
			var t0 := fill[top + v0]
			var t1 := fill[top + v1]
			var t2 := fill[top + v2]
			var nt := int(t0 >= ISO) + int(t1 >= ISO) + int(t2 >= ISO)
			var n := nb + nt
			if n != 0 and n != 6:
				_tet(base + v0, base + v1, base + v2, top + v0, b0, b1, b2, t0)
				_tet(base + v1, base + v2, top + v0, top + v1, b1, b2, t0, t1)
				_tet(base + v2, top + v0, top + v1, top + v2, b2, t0, t1, t2)
			b0 = t0; b1 = t1; b2 = t2
			nb = nt
			base = top
	_grid = null


func _tet(i0: int, i1: int, i2: int, i3: int, f0: float, f1: float, f2: float, f3: float) -> void:
	var m := int(f0 >= ISO) | (int(f1 >= ISO) << 1) | (int(f2 >= ISO) << 2) | (int(f3 >= ISO) << 3)
	var kind := _KIND[m]
	if kind == 0:
		return
	_ti[0] = i0; _ti[1] = i1; _ti[2] = i2; _ti[3] = i3
	_tf[0] = f0; _tf[1] = f1; _tf[2] = f2; _tf[3] = f3
	var p := m * 4
	var a := _PERM[p]
	var b := _PERM[p + 1]
	var c := _PERM[p + 2]
	var d := _PERM[p + 3]
	var ia := _ti[a]; var ib := _ti[b]; var ic := _ti[c]; var id := _ti[d]
	var fa := _tf[a]; var fb := _tf[b]; var fc := _tf[c]; var fd := _tf[d]
	var V := _V
	@warning_ignore("integer_division")
	var pa := _verts[ia % V] * (_r0 + (ia / V) * _dr)
	@warning_ignore("integer_division")
	var pb := _verts[ib % V] * (_r0 + (ib / V) * _dr)
	@warning_ignore("integer_division")
	var pc := _verts[ic % V] * (_r0 + (ic / V) * _dr)
	@warning_ignore("integer_division")
	var pd := _verts[id % V] * (_r0 + (id / V) * _dr)

	if kind == 2:
		# a, b solid; c, d air. Quad ac → ad → bd → bc.
		_edge(0, ia, ic, fa, fc, pa, pc, ia)
		_edge(1, ia, id, fa, fd, pa, pd, ia)
		_edge(2, ib, id, fb, fd, pb, pd, ib)
		_edge(3, ib, ic, fb, fc, pb, pc, ib)
		var outward := pc - pa
		_tri(0, 1, 2, outward)
		_tri(0, 2, 3, outward)
	elif kind == 1:
		# a is the only solid corner.
		_edge(0, ia, ib, fa, fb, pa, pb, ia)
		_edge(1, ia, ic, fa, fc, pa, pc, ia)
		_edge(2, ia, id, fa, fd, pa, pd, ia)
		_tri(0, 1, 2, pb - pa)
	else:
		# a is the only air corner.
		_edge(0, ia, ib, fa, fb, pa, pb, ib)
		_edge(1, ia, ic, fa, fc, pa, pc, ic)
		_edge(2, ia, id, fa, fd, pa, pd, id)
		_tri(0, 1, 2, pa - pb)


## Iso crossing on lattice edge (i, j) → scratch slot. Always interpolated from the lower
## index to the higher one, so every tet sharing the edge gets bit-identical results.
## `solid` is the endpoint whose material colours the vertex.
func _edge(slot: int, i: int, j: int, fi: float, fj: float, pi: Vector3, pj: Vector3, solid: int) -> void:
	var pos: Vector3
	var g: Vector3
	if i < j:
		var t := (ISO - fi) / (fj - fi)
		pos = pi.lerp(pj, t)
		g = _grid.gradient(i).lerp(_grid.gradient(j), t)
	else:
		var t := (ISO - fj) / (fi - fj)
		pos = pj.lerp(pi, t)
		g = _grid.gradient(j).lerp(_grid.gradient(i), t)
	_sp[slot] = pos
	var len2 := g.length_squared()
	_sn[slot] = -g / sqrt(len2) if len2 > 1e-10 else pos.normalized()
	var col := _grid.mat_colors[_grid.material[solid]]
	if _grid.corruption[solid] > 0:
		col = col * CORRUPT_TINT
	_sc[slot] = col


## Append a triangle from scratch slots, wound so the surface faces `outward` (solid → air).
func _tri(s0: int, s1: int, s2: int, outward: Vector3) -> void:
	var q0 := _sp[s0]
	# Godot front faces are clockwise: the right-hand normal must point INTO the solid.
	if (_sp[s1] - q0).cross(_sp[s2] - q0).dot(outward) > 0.0:
		var tmp := s1
		s1 = s2
		s2 = tmp
	vertices.append(q0)
	vertices.append(_sp[s1])
	vertices.append(_sp[s2])
	normals.append(_sn[s0])
	normals.append(_sn[s1])
	normals.append(_sn[s2])
	colors.append(_sc[s0])
	colors.append(_sc[s1])
	colors.append(_sc[s2])
