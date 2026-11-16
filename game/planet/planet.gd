class_name Planet
extends Node3D
## Owns the lattice, the chunk nodes and the dirty-rebuild queue.
## The planet never moves; everything else orbits it.
##
## Meshing runs in the `planet_core` GDExtension (`addons/planet_core/`). The GDScript
## `Icosphere` / `PlanetGrid` / `PlanetMesher` remain in the tree as the reference
## implementation for `tests/test_planet_core_equivalence.gd`; the game does not use them.
## `use_gdscript_core = true` swaps the fallback in (the equivalence tooling never goes
## through this node, it builds both cores directly).

## An ore chunk should pop at `world_pos`.
signal ore_released(material: MaterialDef, world_pos: Vector3)
## A deposit's first solid cell just touched air.
signal deposit_exposed(deposit: RefCounted)
## Chunk meshes/colliders were rebuilt this frame.
signal chunks_rebuilt(count: int)
## The whole planet was (re)generated.
signal regenerated

const SURFACE_SHADER := preload("res://game/planet/planet_surface.gdshader")

@export var planet_def: PlanetDef
@export var planet_seed: int = 1
## Build in _ready. Turn off to drive build() yourself.
@export var auto_build: bool = true
## Max time per frame spent re-meshing dirty chunks.
@export var rebuild_budget_ms: float = 4.0
## Use the GDScript reference implementation instead of the extension. Only for A/B work:
## the extension is the supported path.
@export var use_gdscript_core: bool = false

## The lattice: a `PlanetCoreGridData` (C++) or a `PlanetGrid` (fallback). Typed loosely so
## either can be assigned.
var grid: RefCounted
var chunks: Array[PlanetChunk] = []
## True when the C++ mesher built the current chunks (false = GDScript fallback).
var using_core_mesher: bool = false
## Chunks meshed by C++ since the last build(). Telemetry / test proof that C++ is meshing.
var core_chunk_builds: int = 0

# Debug stats.
var last_rebuild_ms: float = 0.0
var last_rebuild_count: int = 0
var worst_chunk_ms: float = 0.0
var initial_build_ms: float = 0.0

## C++ path: the extension mesher. Null while running the GDScript fallback.
var _mesher: PlanetCoreMesher
## GDScript fallback only.
var _gd_mesher: PlanetMesher
var _material: ShaderMaterial
## C++ lattice, when the extension is in use.
var _ico: PlanetCoreIcosphere
## GDScript lattice, fallback only.
var _gd_ico: Icosphere
## `MaterialDef` table in lattice order (the extension stores plain data only).
var _def_materials: Array[MaterialDef] = []


func _ready() -> void:
	if auto_build and planet_def != null:
		build(planet_seed)


## Generate (or regenerate) the planet from a seed and mesh every chunk.
func build(new_seed: int) -> void:
	var t := Time.get_ticks_msec()
	planet_seed = new_seed
	var use_core := not use_gdscript_core and PlanetCore.available
	if not use_core and not use_gdscript_core:
		push_warning("planet_core GDExtension is not loaded; falling back to the GDScript core " \
				+ "(build it with `scons` in addons/planet_core)")

	if use_core:
		_build_core()
	else:
		_build_gdscript()
	using_core_mesher = use_core
	core_chunk_builds = 0

	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SURFACE_SHADER
		_material.set_shader_parameter("inner_radius", grid.core_surface_radius())
		_material.set_shader_parameter("outer_radius", grid.shell_top_radius(0))

	var patch_count: int = _ico.get_patch_count() if use_core else _gd_ico.patch_count
	while chunks.size() < patch_count:
		var c := PlanetChunk.new()
		c.patch = chunks.size()
		c.name = "Chunk%03d" % c.patch
		c.material_override = _material
		add_child(c)
		chunks.append(c)
	while chunks.size() > patch_count:
		chunks.pop_back().queue_free()

	flush()
	worst_chunk_ms = 0.0
	initial_build_ms = Time.get_ticks_msec() - t
	if use_core:
		print("Planet seed %d: %d chunks, %d triangles via planet_core (C++), %d ms initial, %.2f ms worst chunk" % [
				planet_seed, chunks.size(), triangle_count(), initial_build_ms, worst_chunk_ms])
	else:
		print("Planet seed %d: %d chunks, %d triangles via the GDScript reference core, %d ms initial" % [
				planet_seed, chunks.size(), triangle_count(), initial_build_ms])
	regenerated.emit()


## C++ path: build the lattice in the extension and generate into it.
func _build_core() -> void:
	if _ico == null or _ico.get_level() != planet_def.subdivision \
			or _ico.get_patch_level() != planet_def.patch_level:
		_ico = PlanetCore.build_icosphere(planet_def.subdivision, planet_def.patch_level)
	var data := PlanetCoreGridData.new()
	data.setup(PlanetCore.config_from_planet_def(planet_def), _ico)
	PlanetCoreGenerator.generate(data, planet_seed)
	# Generation wrote the arrays from C++, so any cached view is stale.
	data.invalidate()
	grid = data
	if _mesher == null:
		_mesher = PlanetCore.new_mesher()


## Fallback: the GDScript reference implementation.
func _build_gdscript() -> void:
	if _gd_ico == null or _gd_ico.level != planet_def.subdivision \
			or _gd_ico.patch_level != planet_def.patch_level:
		_gd_ico = Icosphere.new(planet_def.subdivision, planet_def.patch_level)
	var g := PlanetGrid.new(planet_def, _gd_ico)
	PlanetGenerator.generate(g, planet_seed)
	grid = g
	if _gd_mesher == null:
		_gd_mesher = PlanetMesher.new()


## Re-mesh every dirty chunk right now, ignoring the frame budget.
func flush() -> void:
	_rebuild(INF)


func dirty_count() -> int:
	if using_core_mesher:
		return (grid as PlanetCoreGridData).dirty_count()
	return (grid as PlanetGrid).dirty_patches.size()


func triangle_count() -> int:
	var n := 0
	for c in chunks:
		n += c.triangle_count
	return n


## Debug: remove everything in a sphere (ore is vaporized).
func carve_sphere(world_pos: Vector3, radius: float) -> void:
	if using_core_mesher:
		var data := grid as PlanetCoreGridData
		data.carve_sphere(to_local(world_pos), radius)
		# carve_sphere() ran in C++, so the cached arrays are stale.
		data.invalidate()
	else:
		(grid as PlanetGrid).carve_sphere(to_local(world_pos), radius)


func _process(_delta: float) -> void:
	if grid == null:
		return
	if not using_core_mesher:
		_process_gdscript()
		return
	var data := grid as PlanetCoreGridData
	var pending := data.pending_ore_count()
	if pending > 0:
		for i in pending:
			var mi := data.pending_ore_material(i)
			ore_released.emit(_material_def(mi), to_global(_ore_spawn_pos(data.pending_ore_index(i))))
		data.clear_pending_ore()
	var exposed := data.newly_exposed_count()
	if exposed > 0:
		for i in exposed:
			deposit_exposed.emit(data.deposit_at_index(data.newly_exposed_at(i)))
		data.clear_newly_exposed()
	if data.dirty_count() > 0:
		_rebuild(rebuild_budget_ms)


func _process_gdscript() -> void:
	var g := grid as PlanetGrid
	if not g.pending_ore.is_empty():
		for drop in g.pending_ore:
			ore_released.emit(g.materials[drop.x], to_global(_ore_spawn_pos(drop.y)))
		g.pending_ore.clear()
	if not g.newly_exposed.is_empty():
		for id in g.newly_exposed:
			deposit_exposed.emit(g.deposits[id])
		g.newly_exposed.clear()
	if not g.dirty_patches.is_empty():
		_rebuild(rebuild_budget_ms)


func _rebuild(budget_ms: float) -> void:
	if using_core_mesher:
		_rebuild_core(budget_ms)
	else:
		_rebuild_gdscript(budget_ms)
	if last_rebuild_count > 0:
		chunks_rebuilt.emit(last_rebuild_count)


## Every dirty chunk rebuild on this path runs through the C++ mesher.
func _rebuild_core(budget_ms: float) -> void:
	var data := grid as PlanetCoreGridData
	# Push any array edits made through the cached properties back into C++ first.
	data.flush()
	var start := Time.get_ticks_usec()
	var done := 0
	# Walk the dirty list backwards: clearing an entry cannot then skip the next one.
	for i in range(data.dirty_count() - 1, -1, -1):
		var patch := data.dirty_patch_at(i)
		if patch < 0 or patch >= chunks.size():
			data.clear_dirty_patch(patch)
			continue
		var t := Time.get_ticks_usec()
		_mesher.build_patch(data, patch)
		chunks[patch].apply(_mesher.get_vertices(), _mesher.get_normals(), _mesher.get_colors())
		data.clear_dirty_patch(patch)
		core_chunk_builds += 1
		done += 1
		var now := Time.get_ticks_usec()
		worst_chunk_ms = maxf(worst_chunk_ms, (now - t) / 1000.0)
		if (now - start) / 1000.0 >= budget_ms:
			break
	last_rebuild_ms = (Time.get_ticks_usec() - start) / 1000.0
	last_rebuild_count = done


## Fallback path: unchanged from the pre-port implementation.
func _rebuild_gdscript(budget_ms: float) -> void:
	var g := grid as PlanetGrid
	var start := Time.get_ticks_usec()
	var done := 0
	for patch: int in g.dirty_patches.keys():
		var t := Time.get_ticks_usec()
		_gd_mesher.build_patch(g, patch)
		chunks[patch].apply(_gd_mesher.vertices, _gd_mesher.normals, _gd_mesher.colors)
		g.dirty_patches.erase(patch)
		done += 1
		var now := Time.get_ticks_usec()
		worst_chunk_ms = maxf(worst_chunk_ms, (now - t) / 1000.0)
		if (now - start) / 1000.0 >= budget_ms:
			break
	last_rebuild_ms = (Time.get_ticks_usec() - start) / 1000.0
	last_rebuild_count = done


## Where an ore chunk cut from lattice point `idx` should appear: on its open-air side,
## so it never spawns inside solid ground (the planet's interior has no collision).
func _ore_spawn_pos(idx: int) -> Vector3:
	if using_core_mesher:
		var data := grid as PlanetCoreGridData
		var pos := data.lattice_pos(idx)
		if not data.is_solid_at(idx):
			return pos
		var nb := data.first_open_neighbour(idx)
		if nb >= 0:
			return pos.lerp(data.lattice_pos(nb), 0.8)
		return pos + pos.normalized() * data.get_dr()
	var g := grid as PlanetGrid
	var pos := g.lattice_pos(idx)
	if g.fill[idx] < PlanetGrid.ISO:
		return pos
	var V := g.V
	@warning_ignore("integer_division")
	var k := idx / V
	if g.fill[idx + V] < PlanetGrid.ISO:
		return pos.lerp(g.lattice_pos(idx + V), 0.8)
	var v := idx - k * V
	for j in range(g.ico.adj_offsets[v], g.ico.adj_offsets[v + 1]):
		var nb := k * V + g.ico.adj[j]
		if g.fill[nb] < PlanetGrid.ISO:
			return pos.lerp(g.lattice_pos(nb), 0.8)
	return pos + pos.normalized() * g.dr


## `MaterialDef` for a lattice material index (the extension only stores plain data).
func _material_def(mi: int) -> MaterialDef:
	var table := planet_def_materials()
	return table[mi] if mi >= 0 and mi < table.size() else null


## `MaterialDef` table in the order the lattice uses, matching
## `PlanetCore.config_from_planet_def` (core material first, then per shell: base, secondary,
## each ore). Needed because the extension's material table holds plain-data mirrors.
func planet_def_materials() -> Array[MaterialDef]:
	if not _def_materials.is_empty():
		return _def_materials
	var seen := {}
	var add := func(m: MaterialDef) -> void:
		if m != null and not seen.has(m):
			seen[m] = true
			_def_materials.append(m)
	add.call(planet_def.core_material)
	for s in planet_def.shells:
		add.call(s.base_material)
		add.call(s.secondary_material)
		for o in s.ores:
			if o != null:
				add.call(o.material)
	return _def_materials
