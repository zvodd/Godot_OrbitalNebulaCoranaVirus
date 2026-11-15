class_name PlanetGrid
extends RefCounted
## Layered-icosphere lattice: fill / material / deposit / corruption per point, shell
## bookkeeping and spatial queries. Pure data — no nodes (ROADMAP §4.2, §4.4).
##
## Storage rows: row 0 is the indestructible core, rows 1..K are diggable, the last row is
## permanent air. Keeping the two boundary rows as real storage means the mesher needs no
## special cases. Lattice index = row * V + vertex.

const ISO := 0.5
const ROOTED := 255

var def: PlanetDef
var ico: Icosphere
var V: int
## Total storage rows (diggable rows + 2).
var rows: int
var dr: float
## Radius of storage row 0 (the core row).
var r0: float
var point_count: int

var fill: PackedFloat32Array
var material: PackedByteArray
var deposit: PackedInt32Array
## 0 clean, 1..254 corrupted and growing, 255 rooted. Any value > 0 is uncuttable.
var corruption: PackedByteArray

var materials: Array[MaterialDef] = []
var mat_colors: PackedColorArray
var deposits: Array[Deposit] = []

## Shell 0 is the crust. -1 for the core and air rows.
var shell_of_row: PackedInt32Array
var shell_top_row: PackedInt32Array
var shell_bottom_row: PackedInt32Array
var shell_initial_solid: Array[float] = []
var shell_removed: Array[float] = []
## Moves inward (index grows) on collapse.
var outermost_intact_shell: int = 0

## Change tracking, drained by the Planet node each frame.
var dirty_patches: Dictionary = {}
## (material index, lattice index) for every ore chunk that should pop.
var pending_ore: Array[Vector2i] = []
var newly_exposed: PackedInt32Array = PackedInt32Array()

var _grad: PackedVector3Array
var _grad_ok: PackedByteArray
var _lat_scale: float


func _init(p_def: PlanetDef, p_ico: Icosphere = null) -> void:
	def = p_def
	ico = p_ico if p_ico != null else Icosphere.new(def.subdivision, def.patch_level)
	V = ico.vertex_count
	dr = def.row_spacing
	rows = def.diggable_rows() + 2
	r0 = def.core_radius - dr
	point_count = rows * V
	_lat_scale = 2.0 / (ico.mean_edge * ico.mean_edge)

	fill = PackedFloat32Array()
	fill.resize(point_count)
	material = PackedByteArray()
	material.resize(point_count)
	deposit = PackedInt32Array()
	deposit.resize(point_count)
	deposit.fill(-1)
	corruption = PackedByteArray()
	corruption.resize(point_count)
	_grad = PackedVector3Array()
	_grad.resize(point_count)
	_grad_ok = PackedByteArray()
	_grad_ok.resize(point_count)

	_build_material_table()
	_build_shells()


# --- layout -----------------------------------------------------------------

func row_radius(k: int) -> float:
	return r0 + k * dr


func lattice_pos(idx: int) -> Vector3:
	@warning_ignore("integer_division")
	return ico.verts[idx % V] * (r0 + (idx / V) * dr)


func world_to_lattice(p: Vector3) -> int:
	var v := ico.nearest_vertex(p)
	var k := clampi(roundi((p.length() - r0) / dr), 0, rows - 1)
	return k * V + v


## Radius of the iso-surface on top of a shell while it is intact.
func shell_top_radius(shell: int) -> float:
	return row_radius(shell_top_row[shell]) + 0.5 * dr


func surface_radius() -> float:
	return shell_top_radius(mini(outermost_intact_shell, shell_top_row.size() - 1))


func core_surface_radius() -> float:
	return r0 + 0.5 * dr


func cleared_fraction(shell: int) -> float:
	return shell_removed[shell] / maxf(shell_initial_solid[shell], 1.0)


func material_index(m: MaterialDef) -> int:
	return materials.find(m)


func is_diggable_row(k: int) -> bool:
	return k > 0 and k < rows - 1


# --- queries ----------------------------------------------------------------

## Lattice points within radius R of world point p (any fill).
func points_in_sphere(p: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var plen := p.length()
	if plen < 0.0001:
		return out
	var k_lo := maxi(ceili((plen - radius - r0) / dr), 0)
	var k_hi := mini(floori((plen + radius - r0) / dr), rows - 1)
	if k_lo > k_hi:
		return out
	# A column (direction u) can only hold points within R if its ray passes within R of p.
	var s := minf(radius / plen, 1.0)
	var cos_min := sqrt(1.0 - s * s) * plen
	var r2 := radius * radius
	var verts := ico.verts
	var offs := ico.adj_offsets
	var adj := ico.adj

	var start := ico.nearest_vertex(p)
	var queue := PackedInt32Array([start])
	var seen := {start: true}
	var head := 0
	while head < queue.size():
		var n := queue[head]
		head += 1
		var u := verts[n]
		for k in range(k_lo, k_hi + 1):
			if (u * (r0 + k * dr)).distance_squared_to(p) <= r2:
				out.append(k * V + n)
		for j in range(offs[n], offs[n + 1]):
			var nb := adj[j]
			if not seen.has(nb) and p.dot(verts[nb]) >= cos_min:
				seen[nb] = true
				queue.append(nb)
	return out


func is_solid(idx: int) -> bool:
	return fill[idx] >= ISO


## A solid point is exposed if a lateral neighbour or the row above is air.
func is_exposed(idx: int) -> bool:
	if fill[idx] < ISO:
		return false
	@warning_ignore("integer_division")
	var k := idx / V
	if k >= rows - 1 or fill[idx + V] < ISO:
		return true
	var v := idx - k * V
	var base := k * V
	for j in range(ico.adj_offsets[v], ico.adj_offsets[v + 1]):
		if fill[base + ico.adj[j]] < ISO:
			return true
	return false


## Can this point be cut at all (ignoring power)?
func is_cuttable(idx: int) -> bool:
	@warning_ignore("integer_division")
	var k := idx / V
	return k > 0 and k < rows - 1 and corruption[idx] == 0 and materials[material[idx]].cuttable()


## Gradient of fill (points from air toward solid). Cached; the mesher negates it for normals.
func gradient(idx: int) -> Vector3:
	if _grad_ok[idx] != 0:
		return _grad[idx]
	@warning_ignore("integer_division")
	var k := idx / V
	var v := idx - k * V
	var base := idx - v
	var f := fill[idx]
	var up := fill[idx + V] if k < rows - 1 else 0.0
	var down := fill[idx - V] if k > 0 else 1.0
	var verts := ico.verts
	var pv := verts[v]
	var g := pv * ((up - down) / (2.0 * dr))
	var lat := Vector3.ZERO
	var s := ico.adj_offsets[v]
	var e := ico.adj_offsets[v + 1]
	var adj := ico.adj
	for j in range(s, e):
		var n := adj[j]
		lat += (verts[n] - pv) * (fill[base + n] - f)
	g += lat * (_lat_scale / ((e - s) * maxf(r0 + k * dr, 0.001)))
	_grad[idx] = g
	_grad_ok[idx] = 1
	return g


# --- mutation ---------------------------------------------------------------

## Remove up to `amount` of fill at a lattice point. Returns what was actually removed.
## Does NOT check power, corruption or reach — callers do that (see LaserCarve).
func erode(idx: int, amount: float) -> float:
	@warning_ignore("integer_division")
	var k := idx / V
	if k <= 0 or k >= rows - 1:
		return 0.0
	var f := fill[idx]
	if f <= 0.0 or amount <= 0.0:
		return 0.0
	var d := minf(f, amount)
	var nf := f - d
	if nf < 0.002:
		d = f
		nf = 0.0
	fill[idx] = nf

	var shell := shell_of_row[k]
	shell_removed[shell] += d
	var dep := deposit[idx]
	if dep >= 0:
		var mi := material[idx]
		var m := materials[mi]
		if m.is_ore():
			var dd := deposits[dep]
			dd.accum += d
			dd.mined += d
			while dd.accum >= m.chunk_volume:
				dd.accum -= m.chunk_volume
				pending_ore.append(Vector2i(mi, idx))

	var v := idx - k * V
	touch(idx)
	if f >= ISO and nf < ISO:
		_on_opened(idx, v, k)
	return d


## Mark a point as changed: invalidates cached gradients around it and flags its chunks.
func touch(idx: int) -> void:
	@warning_ignore("integer_division")
	var k := idx / V
	var v := idx - k * V
	var base := idx - v
	_grad_ok[idx] = 0
	if k > 0:
		_grad_ok[idx - V] = 0
	if k < rows - 1:
		_grad_ok[idx + V] = 0
	var adj := ico.adj
	for j in range(ico.adj_offsets[v], ico.adj_offsets[v + 1]):
		_grad_ok[base + adj[j]] = 0
	var dp := ico.dirty_patches
	for j in range(ico.dirty_offsets[v], ico.dirty_offsets[v + 1]):
		dirty_patches[dp[j]] = true


## Remove everything within a sphere regardless of material (debug / collapse helper).
## Ore removed this way is vaporized, not dropped.
func carve_sphere(p: Vector3, radius: float) -> float:
	var total := 0.0
	var drops := pending_ore.size()
	for idx in points_in_sphere(p, radius):
		total += erode(idx, 1.0)
	pending_ore.resize(drops)
	return total


func mark_all_dirty() -> void:
	for p in ico.patch_count:
		dirty_patches[p] = true
	_grad_ok.fill(0)


## Recompute which deposits are exposed from scratch (after generation / load).
func refresh_exposure() -> void:
	for d in deposits:
		d.exposed = false
		for idx in d.cells:
			if is_exposed(idx):
				d.exposed = true
				break


func _on_opened(idx: int, v: int, k: int) -> void:
	# A cell just became air: any solid deposit cell next to it is now exposed.
	_expose(idx - V)
	if k < rows - 1:
		_expose(idx + V)
	var base := idx - v
	var adj := ico.adj
	for j in range(ico.adj_offsets[v], ico.adj_offsets[v + 1]):
		_expose(base + adj[j])


func _expose(idx: int) -> void:
	var dep := deposit[idx]
	if dep >= 0 and fill[idx] >= ISO:
		var dd := deposits[dep]
		if not dd.exposed:
			dd.exposed = true
			newly_exposed.append(dep)


# --- setup ------------------------------------------------------------------

func _build_material_table() -> void:
	materials.clear()
	_add_material(def.core_material)
	for s in def.shells:
		_add_material(s.base_material)
		_add_material(s.secondary_material)
		for o in s.ores:
			_add_material(o.material)
	mat_colors = PackedColorArray()
	for m in materials:
		mat_colors.append(m.color)


func _add_material(m: MaterialDef) -> void:
	if m != null and not materials.has(m):
		materials.append(m)


func _build_shells() -> void:
	var n := def.shells.size()
	shell_of_row = PackedInt32Array()
	shell_of_row.resize(rows)
	shell_of_row.fill(-1)
	shell_top_row = PackedInt32Array()
	shell_top_row.resize(n)
	shell_bottom_row = PackedInt32Array()
	shell_bottom_row.resize(n)
	shell_initial_solid.resize(n)
	shell_removed.resize(n)
	var top := rows - 2
	for s in n:
		var sr := def.shells[s].rows
		shell_top_row[s] = top
		shell_bottom_row[s] = top - sr + 1
		for k in range(top - sr + 1, top + 1):
			shell_of_row[k] = s
		shell_initial_solid[s] = float(sr * V)
		shell_removed[s] = 0.0
		top -= sr
