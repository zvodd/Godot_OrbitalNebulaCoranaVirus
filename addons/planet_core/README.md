# planet_core — C++ GDExtension

Port of the planet meshing core from GDScript to C++, keeping the **pure-data contract**:
arrays in → arrays out, no nodes, no rendering types.

The GDScript originals stay in place as the reference implementation:

| GDScript (reference) | C++ | What it does |
|---|---|---|
| `game/planet/icosphere.gd` | `PlanetCoreIcosphere` | geodesic grid: verts, faces, CSR adjacency, `face_patch`, dirty patches, cubemap LUT + greedy `nearest_vertex` |
| `game/planet/planet_grid.gd` | `PlanetCoreGrid` | layered lattice (fill/material/deposit/corruption), shells, queries, `gradient`, `erode`/`touch`/`carve_sphere`, dirty tracking |
| `game/planet/planet_mesher.gd` | `PlanetCoreMesher` | marching tetrahedra over prisms → non-indexed triangle arrays |
| `game/planet/planet_generator.gd` | `PlanetCoreGenerator` | seed → material mix + ore deposits (deterministic) |
| `game/planet/deposit.gd` | `PlanetCoreDeposit` | one ore blob's runtime state |
| `PlanetDef` / `ShellDef` / `MaterialDef` / `OreDef` | `PlanetCoreConfig` / `PlanetCoreShell` / `PlanetCoreMaterial` / `PlanetCoreOre` | plain-data mirrors (the extension never touches `Resource`s) |

## Build

godot-cpp (Godot 4.7 API) must be built once. It is found at, in order:
`godot_cpp=<path>`, `$GODOT_CPP_PATH`, `../../../godot-cpp` (next to the game repo), or
`addons/planet_core/godot-cpp`.

```sh
cd addons/planet_core
scons platform=linux target=template_debug -j4
```

Output: `bin/libplanet_core.linux.template_debug.x86_64.so`, which `planet_core.gdextension`
points at. An existing `godot-cpp/bin/libgodot-cpp*.a` is reused (incremental builds take
~30 s); pass `build_godot_cpp=yes` to rebuild godot-cpp from source too.

After building, run `godot --headless --import` once so the editor registers the new `.so`.

## Use from GDScript

`game/planet/planet_core.gd` (`class_name PlanetCore`) is the only entry point you need:

```gdscript
var def: PlanetDef = load("res://data/planets/default_planet.tres")
var ico := PlanetCore.build_icosphere(def.subdivision, def.patch_level)
var grid := PlanetCore.build_grid(def, 42, ico)   # allocate + generate
var mesher := PlanetCore.new_mesher()
mesher.build_patch(grid, 0)
var vertices := mesher.get_vertices()             # PackedVector3Array, non-indexed
var normals := mesher.get_normals()
var colors := mesher.get_colors()
```

## Public API

All classes extend `RefCounted`; names mirror the GDScript members. `get_*()` array getters
return copies, so the extension owns its buffers.

**`PlanetCoreIcosphere`** — `build(level, patch_level)`, `is_built()`, `get_level()`,
`get_patch_level()`, `get_vertex_count()`, `get_face_count()`, `get_patch_count()`,
`get_faces_per_patch()`, `get_mean_edge()`, `get_verts()`, `get_faces()`, `get_face_patch()`,
`get_adj_offsets()`, `get_adj()`, `get_dirty_offsets()`, `get_dirty_patches()`, `get_lut()`,
`patch_face_begin(patch)`, `valence(v)`, `nearest_vertex(dir, hint = -1)`,
`nearest_vertex_brute(dir)`.

**`PlanetCoreGrid`** — `setup(config, ico = null)`, `get_config()`, `get_ico()`, `get_V()`,
`get_rows()`, `get_dr()`, `get_r0()`, `get_point_count()`, `get_fill()`/`set_fill()`,
`get_material()`/`set_material()`, `get_deposit()`/`set_deposit()`,
`get_corruption()`/`set_corruption()`, `get_mat_colors()`, `get_materials()`, `get_deposits()`,
`get_shell_of_row()`, `get_shell_top_row()`, `get_shell_bottom_row()`, `get_shell_initial_solid()`,
`get_shell_removed()`, `get_outermost_intact_shell()`/`set_outermost_intact_shell()`,
`get_dirty_patches()`, `get_pending_ore()`, `get_newly_exposed()`, `dirty_count()`,
`clear_dirty()`, `mark_all_dirty()`, `row_radius(k)`, `lattice_pos(idx)`,
`world_to_lattice(p)`, `shell_top_radius(shell)`, `surface_radius()`, `core_surface_radius()`,
`cleared_fraction(shell)`, `is_diggable_row(k)`, `points_in_sphere(p, radius)`, `is_solid(idx)`,
`is_exposed(idx)`, `is_cuttable(idx)`, `gradient(idx)`, `erode(idx, amount)`, `touch(idx)`,
`carve_sphere(p, radius)`, `refresh_exposure()`.

**`PlanetCoreMesher`** — `build_patch(grid, patch)`, `build_faces(grid, face_begin, face_end)`,
`get_vertices()`, `get_normals()`, `get_colors()`, `get_triangle_count()`. Results are
non-indexed triangles in Godot's clockwise-front winding; the mesher is reusable across chunks.

**`PlanetCoreGenerator`** — static `generate(grid, planet_seed)`.

**`PlanetCoreConfig`** — `subdivision`, `patch_level`, `core_radius`, `row_spacing`,
`core_material` (index), `materials` (`PlanetCoreMaterial[]`), `shells` (`PlanetCoreShell[]`),
`diggable_rows()`. **`PlanetCoreShell`** — `name`, `rows`, `base_material`, `secondary_material`,
`secondary_amount`, `noise_frequency`, `ores`. **`PlanetCoreMaterial`** — `name`, `color`,
`min_power`, `hardness`, `instant_threshold`, `ore`, `chunk_volume`, `chunk_mass`, `is_ore()`,
`cuttable()`. **`PlanetCoreOre`** — `material`, `count_min`, `count_max`, `size_min`, `size_max`.
**`PlanetCoreDeposit`** — `id`, `material_index`, `shell`, `cells`, `exposed`, `accum`, `mined`,
`get_cell_count()`.

## Equivalence

Output is **bit-identical** to the GDScript reference — not merely within tolerance:

```
godot --headless -s tests/test_planet_core_equivalence.gd
  whole planet: 254520 vertices / 84840 triangles
  max delta pos 0.0 (254520/254520 bit-identical), nrm 0.0, col 0.0
  GDScript 820 ms, C++ 27 ms (31x)
```

That is by construction: GDScript scalars are float64 while `PackedFloat32Array` and `Vector3`
components are float32, and `Vector3 op scalar` narrows the scalar to float32 *before* the
operation. godot-cpp's `real_t` is float32, so the port narrows at exactly the same points.

The generator uses the engine's own `RandomNumberGenerator` and `FastNoiseLite` (called through
godot-cpp) rather than reimplementing them, so the draw sequence and noise field are identical.

See `docs/ROADMAP.md` §5.1b and §10 for the gates, and
`addons/planet_core/demo/` for a scene and a `-s` script that build one chunk headlessly.
