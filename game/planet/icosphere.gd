class_name Icosphere
extends RefCounted
## Geodesic grid on the unit sphere: vertices, faces, adjacency, chunk patches and a
## direction → nearest-vertex lookup. Pure data (ROADMAP §4.1).

const LUT_N := 32

var level: int
var patch_level: int
var vertex_count: int
var face_count: int
var patch_count: int
var faces_per_patch: int
## Mean chord length between neighbouring vertices (unit sphere).
var mean_edge: float

## Unit positions.
var verts: PackedVector3Array
## 3 vertex indices per face. Faces of patch p are the contiguous range
## [p * faces_per_patch, (p + 1) * faces_per_patch).
var faces: PackedInt32Array
## Patch (chunk) id per face.
var face_patch: PackedInt32Array
## CSR adjacency: neighbours of v are adj[adj_offsets[v] .. adj_offsets[v + 1]].
var adj_offsets: PackedInt32Array
var adj: PackedInt32Array
## CSR: patches that must be re-meshed when a lattice point on vertex v changes
## (patches touching v or any neighbour of v, because normals use neighbour fills).
var dirty_offsets: PackedInt32Array
var dirty_patches: PackedInt32Array

var _lut: PackedInt32Array


func _init(p_level: int = 5, p_patch_level: int = 2) -> void:
	level = p_level
	patch_level = mini(p_patch_level, p_level)
	_build_mesh()
	_build_adjacency()
	_build_dirty_patches()
	_build_lut()


func patch_face_begin(patch: int) -> int:
	return patch * faces_per_patch


func valence(v: int) -> int:
	return adj_offsets[v + 1] - adj_offsets[v]


## Nearest vertex to a direction (need not be normalised). `hint` is a vertex to start
## the walk from; pass -1 to use the cubemap LUT.
func nearest_vertex(dir: Vector3, hint: int = -1) -> int:
	var cur := hint if hint >= 0 else _lut[_lut_index(dir)]
	var best_d := dir.dot(verts[cur])
	while true:
		var improved := false
		var s := adj_offsets[cur]
		var e := adj_offsets[cur + 1]
		for j in range(s, e):
			var n := adj[j]
			var d := dir.dot(verts[n])
			if d > best_d:
				best_d = d
				cur = n
				improved = true
		if not improved:
			break
	return cur


func nearest_vertex_brute(dir: Vector3) -> int:
	var best := 0
	var best_d := -INF
	for i in vertex_count:
		var d := dir.dot(verts[i])
		if d > best_d:
			best_d = d
			best = i
	return best


# ---------------------------------------------------------------------------

func _build_mesh() -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var base: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	verts = PackedVector3Array()
	for v in base:
		verts.append(v.normalized())
	faces = PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	face_patch = PackedInt32Array()
	face_patch.resize(20)
	for i in 20:
		face_patch[i] = i

	var mid := {}
	for l in range(1, level + 1):
		var nf := PackedInt32Array()
		var np := PackedInt32Array()
		var fc := faces.size() / 3
		nf.resize(fc * 12)
		np.resize(fc * 4)
		for f in fc:
			var a := faces[f * 3]
			var b := faces[f * 3 + 1]
			var c := faces[f * 3 + 2]
			var ab := _midpoint(a, b, mid)
			var bc := _midpoint(b, c, mid)
			var ca := _midpoint(c, a, mid)
			var o := f * 12
			nf[o] = a; nf[o + 1] = ab; nf[o + 2] = ca
			nf[o + 3] = b; nf[o + 4] = bc; nf[o + 5] = ab
			nf[o + 6] = c; nf[o + 7] = ca; nf[o + 8] = bc
			nf[o + 9] = ab; nf[o + 10] = bc; nf[o + 11] = ca
			var p := face_patch[f]
			for j in 4:
				# Up to the patch level every face is its own patch; below it, inherit.
				np[f * 4 + j] = (f * 4 + j) if l <= patch_level else p
		faces = nf
		face_patch = np

	vertex_count = verts.size()
	face_count = faces.size() / 3
	patch_count = 20 * int(pow(4, patch_level))
	faces_per_patch = face_count / patch_count


func _midpoint(a: int, b: int, cache: Dictionary) -> int:
	var key := (a << 32) | b if a < b else (b << 32) | a
	var found: int = cache.get(key, -1)
	if found >= 0:
		return found
	var idx := verts.size()
	verts.append((verts[a] + verts[b]).normalized())
	cache[key] = idx
	return idx


func _build_adjacency() -> void:
	# Consistently wound closed mesh: each undirected edge appears once per direction,
	# so adding the "next" vertex of every face corner lists each neighbour exactly once.
	var deg := PackedInt32Array()
	deg.resize(vertex_count)
	for i in faces.size():
		deg[faces[i]] += 1
	adj_offsets = PackedInt32Array()
	adj_offsets.resize(vertex_count + 1)
	var total := 0
	for v in vertex_count:
		adj_offsets[v] = total
		total += deg[v]
	adj_offsets[vertex_count] = total
	adj = PackedInt32Array()
	adj.resize(total)
	var cursor := adj_offsets.duplicate()
	var edge_sum := 0.0
	for f in face_count:
		for j in 3:
			var a := faces[f * 3 + j]
			var b := faces[f * 3 + (j + 1) % 3]
			adj[cursor[a]] = b
			cursor[a] += 1
			edge_sum += verts[a].distance_to(verts[b])
	mean_edge = edge_sum / total


func _build_dirty_patches() -> void:
	# Patches touching each vertex.
	var own: Array[Array] = []
	own.resize(vertex_count)
	for v in vertex_count:
		own[v] = []
	for f in face_count:
		var p := face_patch[f]
		for j in 3:
			var list: Array = own[faces[f * 3 + j]]
			if not list.has(p):
				list.append(p)
	dirty_offsets = PackedInt32Array()
	dirty_offsets.resize(vertex_count + 1)
	dirty_patches = PackedInt32Array()
	for v in vertex_count:
		dirty_offsets[v] = dirty_patches.size()
		var merged: Array = own[v].duplicate()
		for j in range(adj_offsets[v], adj_offsets[v + 1]):
			for p: int in own[adj[j]]:
				if not merged.has(p):
					merged.append(p)
		for p: int in merged:
			dirty_patches.append(p)
	dirty_offsets[vertex_count] = dirty_patches.size()


func _build_lut() -> void:
	_lut = PackedInt32Array()
	_lut.resize(6 * LUT_N * LUT_N)
	var cur := 0
	for face in 6:
		for y in LUT_N:
			for x in LUT_N:
				var u := (x + 0.5) / LUT_N * 2.0 - 1.0
				var v := (y + 0.5) / LUT_N * 2.0 - 1.0
				var d: Vector3
				match face:
					0: d = Vector3(1, u, v)
					1: d = Vector3(-1, u, v)
					2: d = Vector3(u, 1, v)
					3: d = Vector3(u, -1, v)
					4: d = Vector3(u, v, 1)
					_: d = Vector3(u, v, -1)
				cur = nearest_vertex(d, cur)
				_lut[(face * LUT_N + y) * LUT_N + x] = cur


func _lut_index(d: Vector3) -> int:
	var ax := absf(d.x)
	var ay := absf(d.y)
	var az := absf(d.z)
	var face: int
	var u: float
	var v: float
	if ax >= ay and ax >= az:
		face = 0 if d.x > 0.0 else 1
		u = d.y / ax
		v = d.z / ax
	elif ay >= az:
		face = 2 if d.y > 0.0 else 3
		u = d.x / ay
		v = d.z / ay
	else:
		face = 4 if d.z > 0.0 else 5
		u = d.x / az
		v = d.y / az
	var x := clampi(int((u * 0.5 + 0.5) * LUT_N), 0, LUT_N - 1)
	var y := clampi(int((v * 0.5 + 0.5) * LUT_N), 0, LUT_N - 1)
	return (face * LUT_N + y) * LUT_N + x
