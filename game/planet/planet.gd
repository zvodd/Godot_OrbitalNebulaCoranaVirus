class_name Planet
extends Node3D
## Owns the lattice (PlanetGrid), the chunk nodes and the dirty-rebuild queue.
## The planet never moves; everything else orbits it.

## An ore chunk should pop at `world_pos`.
signal ore_released(material: MaterialDef, world_pos: Vector3)
## A deposit's first solid cell just touched air.
signal deposit_exposed(deposit: Deposit)
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

var grid: PlanetGrid
var chunks: Array[PlanetChunk] = []

# Debug stats.
var last_rebuild_ms: float = 0.0
var last_rebuild_count: int = 0
var worst_chunk_ms: float = 0.0
var initial_build_ms: float = 0.0

var _mesher := PlanetMesher.new()
var _material: ShaderMaterial
var _ico: Icosphere


func _ready() -> void:
	if auto_build and planet_def != null:
		build(planet_seed)


## Generate (or regenerate) the planet from a seed and mesh every chunk.
func build(new_seed: int) -> void:
	var t := Time.get_ticks_msec()
	planet_seed = new_seed
	if _ico == null or _ico.level != planet_def.subdivision or _ico.patch_level != planet_def.patch_level:
		_ico = Icosphere.new(planet_def.subdivision, planet_def.patch_level)
	grid = PlanetGrid.new(planet_def, _ico)
	PlanetGenerator.generate(grid, planet_seed)

	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SURFACE_SHADER
	_material.set_shader_parameter("inner_radius", grid.core_surface_radius())
	_material.set_shader_parameter("outer_radius", grid.shell_top_radius(0))

	while chunks.size() < _ico.patch_count:
		var c := PlanetChunk.new()
		c.patch = chunks.size()
		c.name = "Chunk%03d" % c.patch
		c.material_override = _material
		add_child(c)
		chunks.append(c)
	while chunks.size() > _ico.patch_count:
		chunks.pop_back().queue_free()

	flush()
	worst_chunk_ms = 0.0
	initial_build_ms = Time.get_ticks_msec() - t
	regenerated.emit()


## Re-mesh every dirty chunk right now, ignoring the frame budget.
func flush() -> void:
	_rebuild(INF)


func dirty_count() -> int:
	return grid.dirty_patches.size()


func triangle_count() -> int:
	var n := 0
	for c in chunks:
		n += c.triangle_count
	return n


## Debug: remove everything in a sphere (ore is vaporized).
func carve_sphere(world_pos: Vector3, radius: float) -> void:
	grid.carve_sphere(to_local(world_pos), radius)


func _process(_delta: float) -> void:
	if grid == null:
		return
	if not grid.pending_ore.is_empty():
		for drop in grid.pending_ore:
			ore_released.emit(grid.materials[drop.x], to_global(_ore_spawn_pos(drop.y)))
		grid.pending_ore.clear()
	if not grid.newly_exposed.is_empty():
		for id in grid.newly_exposed:
			deposit_exposed.emit(grid.deposits[id])
		grid.newly_exposed.clear()
	if not grid.dirty_patches.is_empty():
		_rebuild(rebuild_budget_ms)


func _rebuild(budget_ms: float) -> void:
	var start := Time.get_ticks_usec()
	var done := 0
	for patch: int in grid.dirty_patches.keys():
		var t := Time.get_ticks_usec()
		_mesher.build_patch(grid, patch)
		chunks[patch].apply(_mesher.vertices, _mesher.normals, _mesher.colors)
		grid.dirty_patches.erase(patch)
		done += 1
		var now := Time.get_ticks_usec()
		worst_chunk_ms = maxf(worst_chunk_ms, (now - t) / 1000.0)
		if (now - start) / 1000.0 >= budget_ms:
			break
	last_rebuild_ms = (Time.get_ticks_usec() - start) / 1000.0
	last_rebuild_count = done
	if done > 0:
		chunks_rebuilt.emit(done)


## Where an ore chunk cut from lattice point `idx` should appear: on its open-air side,
## so it never spawns inside solid ground (the planet's interior has no collision).
func _ore_spawn_pos(idx: int) -> Vector3:
	var pos := grid.lattice_pos(idx)
	if grid.fill[idx] < PlanetGrid.ISO:
		return pos
	var V := grid.V
	@warning_ignore("integer_division")
	var k := idx / V
	if grid.fill[idx + V] < PlanetGrid.ISO:
		return pos.lerp(grid.lattice_pos(idx + V), 0.8)
	var v := idx - k * V
	for j in range(_ico.adj_offsets[v], _ico.adj_offsets[v + 1]):
		var nb := k * V + _ico.adj[j]
		if grid.fill[nb] < PlanetGrid.ISO:
			return pos.lerp(grid.lattice_pos(nb), 0.8)
	return pos + pos.normalized() * grid.dr
