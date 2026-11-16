class_name PlanetCoreGridData
extends PlanetCoreGrid
## The C++ lattice, presented with the array-shaped properties the GDScript code expects.
##
## `PlanetCoreGrid` is pure C++ and exposes indexed accessors (`fill_at`, `material_at`, …) plus
## whole-array getters (`get_fill`). Game code is written against named arrays, though
## (`grid.materials[i].name`, `grid.shell_removed[0]`), so this subclass adds those as
## properties.
##
## ## Arrays are snapshots — do not index them in a loop
##
## `get_fill()` copies ~1 MB at L=5. Exposing that as a live array would make `grid.fill[idx]`
## inside a loop O(n²), which is the exact trap this port has to avoid. So:
##
##   * `fill` / `material` / `deposit` / `corruption` are **read-only snapshots**, cached and
##     refreshed by `invalidate()`. They are for scattered reads and for tests, not hot loops.
##   * **Writes** go through the indexed setters (`set_fill_at`, `set_material_at`,
##     `set_deposit_at`, `set_corruption_at`) followed by `touch_cell()`.
##   * The carve hot path never touches these: `LaserCarve` calls `fill_at()` / `erode()`.
##
## `flush()` refreshes the C++-owned tables (shell bookkeeping, the deposit list); `Planet`
## calls it before collecting ore / exposure events and before meshing.

const _FILL := 0
const _MATERIAL := 1
const _DEPOSIT := 2
const _CORRUPTION := 3

var _cache: Array = [PackedFloat32Array(), PackedByteArray(), PackedInt32Array(), PackedByteArray()]
var _cache_valid := [false, false, false, false]
## Cached scalars/tables, filled lazily.
var _materials: Array = []
var _mat_colors := PackedColorArray()
var _shell_removed: Array[float] = []
var _shell_initial_solid: Array[float] = []
var _deposit_objects: Array = []


## Drop every cached view: the lattice changed behind our back (generation, carve_sphere, a
## C++-side erode, a re-setup with new dimensions).
func invalidate() -> void:
	for i in 4:
		_cache_valid[i] = false
	_materials = []
	_mat_colors = PackedColorArray()
	_shell_removed = []
	_shell_initial_solid = []
	_deposit_objects = []


# --- per-cell arrays (read-only snapshots) ---------------------------------

## Snapshot of the C++ fill array. Refresh with `invalidate()`; O(points) to build.
var fill: PackedFloat32Array:
	get:
		if not _cache_valid[_FILL]:
			_cache[_FILL] = get_fill()
			_cache_valid[_FILL] = true
		return _cache[_FILL]

## Snapshot of the C++ material array (indexes into `materials`).
var material: PackedByteArray:
	get:
		if not _cache_valid[_MATERIAL]:
			_cache[_MATERIAL] = get_material()
			_cache_valid[_MATERIAL] = true
		return _cache[_MATERIAL]

## Snapshot of the C++ deposit array (-1 = plain terrain).
var deposit: PackedInt32Array:
	get:
		if not _cache_valid[_DEPOSIT]:
			_cache[_DEPOSIT] = get_deposit()
			_cache_valid[_DEPOSIT] = true
		return _cache[_DEPOSIT]

## Snapshot of the C++ corruption array (0 = clean).
var corruption: PackedByteArray:
	get:
		if not _cache_valid[_CORRUPTION]:
			_cache[_CORRUPTION] = get_corruption()
			_cache_valid[_CORRUPTION] = true
		return _cache[_CORRUPTION]


# --- tables -----------------------------------------------------------------

## `PlanetCoreMaterial` objects, index-compatible with the GDScript `MaterialDef` table.
var materials: Array:
	get:
		if _materials.is_empty():
			_sync_tables()
		return _materials

var mat_colors: PackedColorArray:
	get:
		if _materials.is_empty():
			_sync_tables()
		return _mat_colors

## `PlanetCoreDeposit` objects (id-ordered).
var deposits: Array:
	get:
		if _deposit_objects.size() != deposit_count():
			_sync_deposits()
		return _deposit_objects

## Per-shell removed volume, as a plain Array[float] like `PlanetGrid.shell_removed`.
var shell_removed: Array[float]:
	get:
		if _shell_removed.size() != shell_count():
			_sync_shells()
		else:
			for i in _shell_removed.size():
				_shell_removed[i] = shell_removed_at(i)
		return _shell_removed

var shell_initial_solid: Array[float]:
	get:
		if _shell_initial_solid.size() != shell_count():
			_sync_shells()
		return _shell_initial_solid


func _sync_tables() -> void:
	_materials = get_materials()
	_mat_colors = get_mat_colors()


func _sync_deposits() -> void:
	_deposit_objects = get_deposits()


func _sync_shells() -> void:
	var n := shell_count()
	_shell_removed = []
	_shell_initial_solid = []
	_shell_removed.resize(n)
	_shell_initial_solid.resize(n)
	for i in n:
		_shell_removed[i] = shell_removed_at(i)
		_shell_initial_solid[i] = shell_initial_solid_at(i)


## Refresh the C++-owned table caches. `Planet` calls this before collecting pending ore /
## exposure events and before meshing (materials and deposits can change under it).
func flush() -> void:
	if _shell_removed.size() != shell_count():
		_sync_shells()
	else:
		for i in _shell_removed.size():
			_shell_removed[i] = shell_removed_at(i)
	if _deposit_objects.size() != deposit_count():
		_sync_deposits()


## Mirror of the GDScript `PlanetGrid.touch()`: flag the patches that need re-meshing.
## Writes to the lattice go through the indexed setters, so nothing has to be pushed back —
## only the cached snapshots become stale.
##
## Deliberately NOT named `touch()`: that is a native `PlanetCoreGrid` method, and overriding a
## native method from GDScript is an error.
func touch_cell(idx: int) -> void:
	for i in 4:
		_cache_valid[i] = false
	super.touch(idx)


## Convenience for ore painting: append a deposit and return it.
func new_deposit(material_index: int, shell: int = 0) -> PlanetCoreDeposit:
	var id := add_deposit(material_index, shell)
	_deposit_objects = get_deposits()
	return _deposit_objects[id] if id < _deposit_objects.size() else null
