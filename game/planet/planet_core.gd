class_name PlanetCore
extends RefCounted
## GDScript ↔ C++ bridge for the `planet_core` GDExtension (ROADMAP §5.1, M2 note).
##
## The extension is pure data: it knows nothing about `Resource`s. This class flattens a
## `PlanetDef` (and its `MaterialDef` / `ShellDef` / `OreDef` tree) into a `PlanetCoreConfig`
## and offers the two calls a game script actually wants:
##
##     var core := PlanetCore.new()
##     var ico := core.build_icosphere(5, 2)
##     var grid := core.build_grid(planet_def, seed)      # generate + build in one step
##     var mesher := core.new_mesher()
##     mesher.build_patch(grid, 0)
##     var tris := mesher.get_vertices()
##
## The GDScript originals (`Icosphere`, `PlanetGrid`, `PlanetMesher`) stay in place as the
## reference implementation; `tests/test_planet_core_equivalence.gd` builds one planet both ways
## and compares the triangle arrays.

## True when the extension loaded and every class it needs is available.
static var available: bool:
	get:
		return ClassDB.class_exists(&"PlanetCoreGrid") \
				and ClassDB.class_exists(&"PlanetCoreMesher") \
				and ClassDB.class_exists(&"PlanetCoreIcosphere") \
				and ClassDB.class_exists(&"PlanetCoreConfig") \
				and ClassDB.class_exists(&"PlanetCoreMaterial") \
				and ClassDB.class_exists(&"PlanetCoreShell") \
				and ClassDB.class_exists(&"PlanetCoreOre") \
				and ClassDB.class_exists(&"PlanetCoreGenerator")


## Flatten a `PlanetDef` into the extension's plain-data config.
## Material and shell tables are de-duplicated exactly like `PlanetGrid._build_material_table`
## (core material, then per shell: base, secondary, each ore), so material indices match.
static func config_from_planet_def(def: PlanetDef) -> PlanetCoreConfig:
	assert(def != null, "PlanetCore.config_from_planet_def: def is null")

	var cfg := PlanetCoreConfig.new()
	cfg.subdivision = def.subdivision
	cfg.patch_level = def.patch_level
	cfg.core_radius = def.core_radius
	cfg.row_spacing = def.row_spacing

	# Mirrors PlanetGrid._build_material_table().
	var materials: Array[MaterialDef] = []
	var index_of := {}
	var add := func(m: MaterialDef) -> void:
		if m != null and not index_of.has(m):
			index_of[m] = materials.size()
			materials.append(m)
	add.call(def.core_material)
	for s in def.shells:
		add.call(s.base_material)
		add.call(s.secondary_material)
		for o in s.ores:
			if o != null:
				add.call(o.material)

	var core_materials := []
	for m: MaterialDef in materials:
		var cm := PlanetCoreMaterial.new()
		cm.name = m.name
		cm.color = m.color
		cm.min_power = m.min_power
		cm.hardness = m.hardness
		cm.instant_threshold = m.instant_threshold
		cm.ore = m.is_ore()
		cm.chunk_volume = m.chunk_volume
		cm.chunk_mass = m.chunk_mass
		core_materials.append(cm)
	cfg.materials = core_materials
	cfg.core_material = int(index_of.get(def.core_material, 0))

	var core_shells := []
	for s in def.shells:
		var cs := PlanetCoreShell.new()
		cs.name = s.name
		cs.rows = s.rows
		cs.base_material = int(index_of.get(s.base_material, -1))
		cs.secondary_material = int(index_of.get(s.secondary_material, -1))
		cs.secondary_amount = s.secondary_amount
		cs.noise_frequency = s.noise_frequency
		var ores := []
		for o in s.ores:
			if o == null:
				continue
			var co := PlanetCoreOre.new()
			co.material = int(index_of.get(o.material, -1))
			co.count_min = o.count_min
			co.count_max = o.count_max
			co.size_min = o.size_min
			co.size_max = o.size_max
			ores.append(co)
		cs.ores = ores
		core_shells.append(cs)
	cfg.shells = core_shells
	return cfg


## Build (or rebuild) an extension icosphere.
static func build_icosphere(level: int = 5, patch_level: int = 2) -> PlanetCoreIcosphere:
	var ico := PlanetCoreIcosphere.new()
	ico.build(level, patch_level)
	return ico


## Allocate a grid from a `PlanetDef`. Pass `ico` to share a cached lattice, as `Planet` does.
static func build_grid(def: PlanetDef, planet_seed: int, ico: PlanetCoreIcosphere = null) -> PlanetCoreGrid:
	var cfg := config_from_planet_def(def)
	var grid := PlanetCoreGrid.new()
	grid.setup(cfg, ico)
	PlanetCoreGenerator.generate(grid, planet_seed)
	return grid


static func new_mesher() -> PlanetCoreMesher:
	return PlanetCoreMesher.new()
