# Roadmap & Technical Design — Nebula MVP

> Companion to [GDD.md](GDD.md). This doc is written so another agent/dev can pick up cold.
> **Keep the Status table current** whenever a milestone or task lands.
> Numbers here are starting points — tune freely, but update this doc when you do.

## Status

| Milestone | State | Notes |
|---|---|---|
| M0 Docs & brief | ✅ done | GDD + this roadmap + CLAUDE.md |
| M1 Icosphere lattice & planet data | ✅ done | `game/planet/` icosphere, grid, generator; `tests/test_planet_core.gd`. Debug lattice-point cutaway scene skipped. |
| M2 Mesh extraction, chunks, collision | ✅ done | Marching tets, 320 chunks, trimesh collision, 4 ms dirty budget. ~1.6 ms avg / ~7 ms worst chunk. Normals are gradient-based (seamless across chunks), mesh is non-indexed. |
| M2b Planet core in C++ (GDExtension) | ✅ done | `addons/planet_core/` ports Icosphere + PlanetGrid + PlanetMesher + generator behind the same pure-data contract. Output is **bit-identical** to the GDScript reference (equivalence gate: max delta 0.0) and ~31x faster (820 ms → 27 ms for the whole planet). GDScript originals stay in place as the reference. |
| M2c Game runs on the C++ core | ✅ done | `Planet` owns a `PlanetCoreGridData` + `PlanetCoreMesher`; every chunk rebuild goes through C++. Indexed accessors (`fill_at`/`material_at`/`erode`/`dirty_patch_at`…) keep the carve path linear (1422x cheaper than `get_fill()[idx]`). Measured: initial build **1964 → 231 ms** (8.5x), per-chunk rebuild **2.68 → 0.40 ms** median (6.7x). GDScript fallback still selectable via `Planet.use_gdscript_core`. |
| M3 Gyro aim + laser (types, lenses, materials) | 🟡 playable | Trackball rig, 3 laser types, 3 lenses, reach limit. All types/lenses unlocked (no upgrades yet). Needs feel/tuning pass by the designer. |
| M4 Ore chunks, tractor beam, collector, HUD | 🟡 playable | Chunks, radial gravity, tractor cone with line of sight, collector, placeholder HUD + F3 overlay. No fuel bar (M5). |
| M5 Round loop: fuel, end screen, upgrades, persistence | ⏳ next | |
| M6 Crawlers | ⬜ | |
| M7 Shell collapse + depth limit polish | ⬜ | |
| M8 Balance & feel pass | ⬜ | |

**As built (2026-11-16), the game on the C++ core (M2c):**
- `Planet` owns a `PlanetCoreGridData` (a `PlanetCoreGrid` subclass adding the array-shaped
  properties GDScript code expects) and a `PlanetCoreMesher`. `Planet.grid` stays public but is
  now typed `RefCounted`, so code that touches cells must pick a branch or use the shared surface.
- **Indexed accessors are mandatory on the hot path.** `get_fill()` copies the whole lattice
  (~1 MB, 344 us/call at L=5), so `get_fill()[idx]` in a carve loop is O(n^2). The extension now
  exposes `fill_at` / `set_fill_at` / `is_solid_at` / `material_at` / `deposit_at` /
  `corruption_at` / `shell_removed_at` / `dirty_patch_at` / `clear_dirty_patch` /
  `pending_ore_*` / `first_open_neighbour`, and `LaserCarve`, `Laser`, `Hud` and `Planet` use them.
  Measured 0.24 us vs 342 us per access — **1422x**; a whole carve tick is 0.23 ms.
- `PlanetCoreGridData.fill` &c. are **read-only snapshots** for scattered reads and tests, not
  loops. Writes go through the indexed setters plus `touch_cell(idx)` (named that way because
  `touch()` is a native `PlanetCoreGrid` method and GDScript cannot override it).
- `Planet.dirty_count()` / `carve_sphere()` / `triangle_count()` / the four signals keep their
  shape. `carve_sphere` invalidates the snapshot cache; `_process` drains pending ore and exposure
  events through the indexed accessors instead of building arrays.
- **`PlanetChunk.apply()` keeps one `ConcavePolygonShape3D` and mutates it in place, and never
  re-assigns it to the `CollisionShape3D`.** Re-assigning or swapping the shape costs 0.42-0.66
  ms/chunk (physics rebuilds the shape's BVH and broadphase entry); in-place `set_faces()` on the
  already-attached shape costs 0.012 ms. Before that fix, collision churn was ~150 ms of a 170 ms
  full-planet rebuild. There is no way to skip this work entirely: an enabled trimesh shape costs
  ~0.3 ms to update versus ~0.02 ms while disabled, and batching the enable just moves the cost.
- Measured on this machine, same `Planet` node, both paths:

  | | GDScript | C++ |
  |---|---|---|
  | initial build (320 chunks) | 1964 ms | **231 ms** (8.5x) |
  | per-chunk rebuild, median | 2.68 ms | **0.40 ms** (6.7x) |
  | per-chunk rebuild, p90 | 2.90 ms | **0.44 ms** |
  | one `LaserCarve.apply` tick | — | 0.23 ms |

  Whole-planet meshing alone is 14.5 ms of that build; generation is ~70 ms and the rest is
  ArrayMesh upload + unavoidable trimesh collision.
- `Planet.use_gdscript_core = true` runs the old path (still exercised by `test_gameplay`'s
  `_paint` and by the equivalence gate, which builds both cores directly).

**As built (2026-11-16), the C++ planet core:**
- `addons/planet_core/` is a GDExtension built with `scons` against `godot-cpp` (Godot 4.7 API).
  Build: `cd addons/planet_core && scons platform=linux target=template_debug -j4`. It reuses an
  existing `godot-cpp/bin/libgodot-cpp*.a` (`build_godot_cpp=yes` forces a from-source rebuild) and
  finds godot-cpp at `../../../godot-cpp`, `$GODOT_CPP_PATH`, or `godot_cpp=<path>`.
- Classes (all `RefCounted`): `PlanetCoreIcosphere`, `PlanetCoreGrid`, `PlanetCoreMesher`,
  `PlanetCoreGenerator` (static `generate`), plus plain-data `PlanetCoreConfig` /
  `PlanetCoreMaterial` / `PlanetCoreShell` / `PlanetCoreOre` / `PlanetCoreDeposit`.
- `game/planet/planet_core.gd` (`class_name PlanetCore`) is the only GDScript-side entry point: it
  flattens a `PlanetDef` into a `PlanetCoreConfig` and wraps the build calls. The extension never
  touches `Resource`s.
- Acceptance: `tests/test_planet_core_equivalence.gd` (the gate — builds one planet both ways and
  compares the triangle arrays), `tests/test_planet_core_extension.gd` (load + API surface + one
  headless chunk), `tests/test_planet_core_equivalence_levels.gd` (same at L=3/C=1 and L=4/C=2).
  `addons/planet_core/demo/planet_core_chunk.tscn` (+ a `-s` headless variant) prints a chunk's
  triangle count.

**As built (2026-11-15), where it differs from the sections below:**
- Main scene is `game/main.tscn` (`run/main_scene` now points at it). Tests:
  `godot --headless -s tests/test_planet_core.gd` and
  `godot --headless --fixed-fps 60 -s tests/test_gameplay.gd`. Run `--headless --import` once
  after adding a `class_name`.
- The two boundary rows are **real storage rows** (row 0 = core, last row = air), so
  `rows = K + 2` and `radius(k) = core_radius + (k − 1)·dr`. `PlanetDef.shells` is ordered
  **outside → in** (shell 0 = crust).
- `MaterialDef` has `ore_id` / `chunk_volume` / `chunk_mass` instead of an `OreDef` reference;
  `OreDef` is a shell ore-table entry (material, count range, size range).
- `LaserTypeDef` has a single `power` (no per-material table). Per-cell power =
  `power × focus ÷ max(lens area ÷ 1.4, 1)`. Carve maths lives in the node-free
  `game/tools/laser_carve.gd`. The beam only cuts **exposed** cells (layer by layer), using a
  short capsule along the beam so pits keep the lens width.
- Debug keys so far: F3 overlay, F7 crater at aim, F9 new planet. Not done: F5/F6/F8, live-chunk
  merge is implemented but untested at the 150 cap.

---

## 1. Engine & constraints

- **Godot 4.7**, GDScript, **GL Compatibility** renderer (no compute shaders → all meshing on CPU),
  **Jolt** physics. The `[dotnet]` section in `project.godot` is a leftover; there is no C#.
- MVP is **GDScript only**. If meshing perf blocks progress, the mesher is the one piece that may be
  ported to C#/GDExtension — keep it isolated behind a pure-data interface to allow that.
- Placeholder art for everything except the planet.

## 2. Existing code inventory (pre-MVP prototypes)

| Path | What it is | Plan |
|---|---|---|
| `surface_crawler/surface_navigator.gd` | **A\* over raycast probes.** 6 hex directions around the surface normal, 3-ray probe each (flat/slope, inner corner, outer ledge), spatial-hash closed set. Works on any collision geometry incl. walls/ceilings — no navmesh. | **Reuse for crawlers** (M6) after fixes in §8. |
| `surface_crawler/surface_movementer.gd` | Follows a path, aligns actor to surface normal (quat slerp). Random wander when idle. | Reuse; replace wander with target selection; fix ray length. |
| `surface_crawler/surf_crawl_scenario.tscn` | CSG test scene for the crawler. | Keep as a test scene. |
| `script/orbit_cam.gd` / `demo-experiment-sufrnorm/orbit.gd` | Same yaw/pitch inertia orbit camera, duplicated (Camera3D vs Node3D base). Pitch clamped ±0.49π. | Merge into one `game/player/gyro_rig.gd` (M3). |
| `script/MultiMeshManager.gd`, `script/scene_multi_demo.gd`, `script/gn_post_import.gd` | Blender geometry-nodes instance import → MultiMesh; click-to-erase instances in radius. Current main scene. | Not part of MVP. Leave alone (maybe later for surface props/debris). |
| `materials/shader_cool_surface2.gdshader` | Triplanar procedural pattern + fresnel. | Basis for planet shader (triplanar, no UVs needed). |
| `materials/shader_sky.gdshader`, `assets/rainbow_nebula.webp` | Nebula sky. | Reuse. |
| `materials/canvas_crosshair.gdshader` | Crosshair. | Reuse in HUD. |

**Do not delete or restructure the demo folders.** New game code lives under `game/`.

## 3. Target project layout

```
game/
  main.tscn                 # new main scene (set run/main_scene when M3 is playable)
  planet/
    icosphere.gd            # geodesic grid: verts, faces, adjacency, patch ids, dir→vertex lookup
    planet_grid.gd          # lattice data: fill/material/deposit arrays, shells, queries
    planet_generator.gd     # seed → materials, deposits
    planet_mesher.gd        # marching tetrahedra over prisms → triangle arrays (pure data)
    planet.gd / planet.tscn # node: owns grid, chunk nodes, dirty queue, carve API, save/load
    planet_chunk.gd         # MeshInstance3D + StaticBody3D/ConcavePolygonShape3D per patch
    deposit.gd              # deposit runtime state
  defs/                     # Resource classes (data-driven)
    material_def.gd shell_def.gd ore_def.gd laser_type_def.gd lens_def.gd upgrade_def.gd
  tools/
    emitter.gd              # base: origin + aim direction, owner
    laser.gd                # carve + damage crawlers, beam visual, particles
    tractor_beam.gd         # cone pull, collection
  ore/
    ore_chunk.gd/.tscn      # RigidBody3D
    collector.gd            # anything that receives ore (gyro now; ships later)
  mobs/
    crawler.gd/.tscn        # uses SurfaceNavigator + SurfaceMovementComponent
    crawler_spawner.gd
  player/
    gyro_rig.gd             # merged orbit/trackball camera + emitter mount
  run/
    run_state.gd            # fuel, round timer, round-end corruption clear, end-of-round
    meta.gd                 # AUTOLOAD: ore bank, upgrade levels, derived stats, save/load
  ui/
    hud.tscn/.gd  upgrade_screen.tscn/.gd  debug_overlay.gd
data/                       # .tres instances: materials/ shells/ ores/ lasers/ lenses/ upgrades/
tests/                      # headless test scripts (see §10)
```

Physics layers: **1 terrain**, **2 ore chunks**, **3 crawlers**, **4 player/collector**.
Navigator and terrain carving rays use mask = terrain only.

## 4. Planet data model (M1)

### 4.1 Icosphere
- Subdivision level **L = 5** → `V = 10·4^L + 2 = 10 242` vertices, `F = 20·4^L = 20 480` faces.
  12 vertices have 5 neighbours, the rest 6. Average edge ≈ 0.0376 rad → **≈1.2 units at r=32**.
- Build once (cache to a `.res` or regenerate at startup — it's fast enough to measure first):
  - `verts: PackedVector3Array` (unit), `faces: PackedInt32Array` (3 per face)
  - adjacency: CSR arrays `adj_offsets: PackedInt32Array`, `adj: PackedInt32Array`
  - `face_patch: PackedInt32Array` — the level-**C = 2** ancestor face index (0..319). This is the
    **chunk id**. Track it during subdivision: child faces inherit the parent's patch at levels > C.
  - **Direction → nearest vertex**: cubemap LUT (6 × 64 × 64 ints of a nearby vertex), then greedy
    walk to the neighbour with the highest `dot(dir, vert)` until no improvement.

### 4.2 Lattice
- Rows `k = 0..K-1`, `k = 0` innermost, `k = K-1` surface. Radius `r_k = r_core + k·dr`.
  MVP: `r_core = 8`, `K = 24`, `dr = 1.0` → surface at r = 31.
- Index: `idx = k·V + i`. ~246k points.
- Arrays (all on `PlanetGrid`):
  - `fill: PackedFloat32Array` — 1 solid, 0 air. **Iso = 0.5.** (Float, not byte: slow cut rates are
    < 1/255 per frame.)
  - `material: PackedByteArray` — index into material table.
  - `deposit: PackedInt32Array` — −1 or deposit id.
  - `corruption: PackedByteArray` — 0 clean, 1..254 corrupted and growing, **255 rooted**
    (permanent). Any value > 0 makes the cell uncuttable. See §8.
- Virtual boundary: row `K` is always air (so the surface triangulates); row `−1` is always solid
  (core).
- **Shells**: `ShellDef` resources, each covering a contiguous row range (MVP 8 shells × 3 rows).
  `shell_of_row[k]`. Per-shell bookkeeping: `initial_solid`, `removed_solid` → `cleared_fraction`.
- `outermost_intact_shell` (int; starts at the top shell, moves inward on collapse).
  `surface_radius` = top radius of that shell. The satellite's `orbit_radius` derives from it (§6.1).

### 4.3 Generation (`planet_generator.gd`)
- Everything derives from `seed` via `RandomNumberGenerator` + `FastNoiseLite` seeded
  deterministically, so a save only needs `seed` + mutable state.
- Per point: shell's base material mix chosen by 3D noise (e.g. sand vs rock bands).
- Deposits: per shell, `N` seeds from the shell's ore table (`OreDef`: ore material, count range,
  size range); flood-fill over lattice neighbours (lateral adjacency + row ±1) to the target size.
  Store `Deposit {id, ore_material, cells: PackedInt32Array, exposed, occupied_by}`.

### 4.4 Queries
- `world_to_lattice(p)` → (vertex via LUT+walk, row via `round((|p|−r_core)/dr)`).
- `lattice_pos(idx)` → `verts[i] * r_k`.
- `points_in_sphere(p, R)` → BFS laterally from nearest vertex while `angle·|p| < R + cell`,
  rows within `[|p|−R, |p|+R]`, exact 3D distance check.
- Exposure: a solid point is exposed if any lateral neighbour or row `k+1` is air. Deposits update
  `exposed` incrementally when one of their cells' neighbours changes.

**M1 acceptance:** headless test verifies V/F counts, 12 valence-5 vertices, adjacency symmetric,
dir→vertex lookup matches brute force on 10k random dirs; debug scene draws lattice points coloured
by material/shell with a cutaway.

## 5. Mesh extraction (M2)

### 5.1 Marching tetrahedra on prisms
- Each icosphere face × row gap (`k`→`k+1`, including the virtual air row) is a **triangular prism**.
- Split each prism into 3 tets using global vertex order. Sort the face's vertices so
  `v0 < v1 < v2` (global index); with `b` = bottom row, `t` = top row:
  - T1 = (v0b, v1b, v2b, v0t)
  - T2 = (v1b, v2b, v0t, v1t)
  - T3 = (v2b, v0t, v1t, v2t)
  
  Every quad side face is then split along the diagonal **(smaller-index top ↔ larger-index bottom)**,
  which depends only on the shared edge → adjacent prisms agree → watertight mesh.
- Standard marching-tetrahedra (16 cases), interpolate on `fill − 0.5`.
- **Early-out**: skip a prism if all 6 corners are on the same side of iso. Most prisms skip.
- Per-vertex data: position, normal, `COLOR` = material colour of the solid endpoint
  (`CUSTOM0` can carry material id / heat / corruption for shader effects; corruption tint is
  needed by M6).
- Normals: MVP = accumulate face normals per deduplicated edge-vertex (key = sorted lattice index pair),
  then normalize. Gradient-based normals optional later.
- `planet_mesher.gd` is **pure data in → arrays out** (no nodes) so it can be ported/threaded.

### 5.1b C++ port (M2b) — done
- `addons/planet_core/` implements the three core classes in C++ as a GDExtension, keeping the
  pure-data contract: arrays in → arrays out, no nodes, no rendering types in the mesher.
- **Equivalence is the spec.** The port reproduces GDScript's numeric behaviour exactly rather than
  approximately: GDScript scalars are float64, `PackedFloat32Array` / `Vector3` components are
  float32, and `Vector3 op scalar` narrows the scalar to float32 *before* the operation. The C++
  code narrows at the same points (`real_t` = float in godot-cpp), which is why positions come out
  bit-identical instead of merely within tolerance.
- The generator calls the engine's own `RandomNumberGenerator` and `FastNoiseLite` (via godot-cpp)
  instead of reimplementing them, so the draw sequence and noise field match the GDScript
  generator exactly — same seed, same planet, same 204 deposits.
- Measured on this machine: whole planet 84 840 triangles in **27 ms** (C++) vs **820 ms**
  (GDScript), ~31x. A single 64-face chunk meshes in ~0.06 ms.
- The GDScript classes remain the reference implementation and are still what the game's `Planet`
  node uses; switching the node over is a separate step (it would also need the chunk/collision
  path to read `PlanetCoreMesher` output).

### 5.2 Chunks
- Chunk = one patch (64 faces at L=5/C=2) × all rows → 320 chunks. ~1.6k prisms each.
- `PlanetChunk`: `MeshInstance3D` (ArrayMesh) + `StaticBody3D` with `ConcavePolygonShape3D`
  (`set_faces` from the same triangles), layer 1.
- A lattice point affects every chunk containing a face that uses its vertex (patch borders → up to
  ~3 chunks). Precompute `vertex_patches`.
- Dirty queue on `Planet`; rebuild at most **N chunks or T ms per frame** (start: 4 ms budget).
- **Perf target:** single chunk rebuild ≤ 8 ms in GDScript. If missed: split chunks by row band,
  cache per-prism corner sides, or port mesher (C#/GDExtension). Measure before optimizing.

### 5.3 Planet shader
- Triplanar (from `shader_cool_surface2`) modulated by vertex colour; simple lambert. Rim/fresnel
  optional. Cut-face "heat" glow later via CUSTOM0.

**M2 acceptance:** planet renders, shells visible when carved (debug "carve sphere at point" key),
collision matches the mesh (raycasts hit it), dirty-chunk rebuild timing shown in debug overlay.

## 6. Player, laser, lenses (M3)

### 6.1 Gyro satellite rig
- The gyro is **a big satellite**. The planet never moves; the satellite orbits it.
- Merge the two orbit scripts into `gyro_rig.gd`. It must reach the **poles**, so replace clamped
  yaw/pitch with quaternion trackball accumulation (keep the inertia/gain feel from the current
  script). The satellite sits at `orbit_radius` looking at the planet centre.
- Scroll moves the **camera** relative to the satellite (third-person framing) only. The beam
  always starts at the satellite, so zooming never changes reach.
- **Orbit radius**: `orbit_radius = surface_radius × orbit_factor[collapses]`, with
  `orbit_factor` decreasing per collapse (start e.g. 1.8, 1.65, 1.5, …). The planet's apparent
  angular size is `asin(surface_radius / orbit_radius)`, so it **grows only if the ratio grows**.
  Dropping the orbit by exactly the shell thickness would make the planet look *smaller*.
- On collapse, animate the descent (a few seconds, ease in-out) while chunks rebuild.
- The rig owns the emitters; laser fires along the camera's forward through the crosshair.
- Placeholder for the designer's armature + targeting hologram.

### 6.2 Defs
```
MaterialDef  : name, color, min_power, hardness, instant_threshold, particle_scene, ore_type (OreDef or null)
LaserTypeDef : name, power_by_material: Dictionary[MaterialDef→float] (or per class), reach (units from satellite), fuel_per_sec, beam_color
LensDef      : name, pattern (CIRCLE|LINE|RING|SCATTER), spread, focus, sample_points
```
Upgrades multiply/add to these at runtime via `Meta` derived stats — **never mutate .tres at runtime**.

### 6.3 Carve algorithm (per physics frame while firing)
1. Raycast from emitter along aim (mask terrain|crawlers). Crawler hit → damage it, stop.
2. Lens generates sample points on the tangent plane at the hit (pattern × spread), each with weight.
3. For each sample: `points_in_sphere(sample, cell_radius)`. For each lattice point `idx` with `fill > 0`:
   - skip if beyond **reach**: `|pos| < orbit_radius − reach` (scorch effect)
   - skip if `corruption[idx] > 0` (scorch effect)
   - `p = laser_power(mat) · focus / area · weight · falloff(dist)`
   - if `p < mat.min_power` → scorch only
   - `rate = p / mat.hardness`; if `rate ≥ mat.instant_threshold` → `Δ = fill` else `Δ = min(fill, rate·dt)`
   - `fill −= Δ`; shell `removed_solid += Δ`; if ore → `deposit.accum += Δ`
4. Mark affected chunks dirty; update exposure; throttle particle spawns per material.
5. Deposit `accum ≥ chunk_volume` → spawn ore chunk at the cell, slightly outward.

Beam visual: stretched cylinder/line, colour per laser type.

**M3 acceptance:** you can aim anywhere incl. poles; sand cuts slowly with Thermal; rock is
uncuttable until Plasma; lenses visibly change crater shape; reach stops cuts below
`orbit_radius − reach`.

## 7. Ore chunks, tractor, collector, HUD (M4)

- Radial gravity: an `Area3D` with `gravity_point = true` centred on the planet,
  `gravity_space_override = REPLACE`. Chunks are small `RigidBody3D` (layer 2), mass by ore type.
- Cap live chunks (start 150); beyond that, merge value into the nearest chunk of the same ore.
- Tractor: hold RMB. Cone from emitter (range, half-angle). Each physics frame, for chunks in cone
  with line of sight (terrain mask) → apply force toward emitter `∝ strength / mass`, damp lateral
  velocity. Within collect radius → `collector.receive(ore, amount)`, free.
- `Collector` interface → the gyro now; pickup ships later.
- HUD: fuel bar, ore counts, active laser type + lens (number keys / Q-E to cycle), shell/depth
  readout, cleared % of outermost shell.

**M4 acceptance:** cutting ore drops chunks that fall into the pit; tractor pulls them out; chunks
stuck behind overhangs can't be pulled without line of sight; ore counts increase only on collection.

## 8. Crawlers (M6) — navigator fixes first

Fix `SurfaceNavigator` before relying on it:
1. Open list is re-sorted every iteration and never deduped → use a binary heap + `best_g[hash]`.
2. `h_weight = 250` makes it pure greedy → use ~1.2–2.0.
3. Up to 5000 iters × 18 raycasts synchronously → **time-slice** (search object advanced by
   N iterations per frame, or a request queue with a per-frame raycast budget).
4. Set ray `collision_mask` = terrain only (currently hits everything incl. chunks/crawlers).
5. `step_size` ≈ lattice cell width (~1.2). `hash_size` ≈ 0.75·step.
6. `Vector3i(pos / hash_size)` truncates toward zero (double-size cells at the origin plane) → use
   `floor`.
7. Mover: ground-normal ray is ±1 unit → make it ~2× step; repath cooldown on failure instead of
   retrying every frame (current `_pick_random_target` runs every frame while pathless).

Crawler behaviour:
- Spawner: points on the outer surface (raycast down from random directions), rate from round
  time/depth. Cap live crawlers (start 12).
- Target: nearest exposed deposit that is not occupied and still has clean ore; goal = air-side
  position of one of its exposed cells. Re-target if it becomes occupied or mined out.
- Arrive → sit (squash tween ~2 s, interruptible by death) → `deposit.occupied_by = self`,
  crawler stays parked and starts **corrupting**.

Corruption (per-cell, `PlanetGrid.corruption`):
- Every `spread_interval` (start 1.0 s) a seated crawler:
  - raises every corrupted cell it owns by `growth_step`; at ≥ `root_threshold` the cell becomes
    **255 = rooted** (permanent);
  - corrupts the frontier: clean neighbouring cells with `fill > 0` that belong to **the same
    deposit** (lateral + row ±1 adjacency). Spread starts at the cell under the crawler.
- Corrupted cells can't be cut (§6.3) and are tinted on the mesh (mark chunks dirty, or push a
  shader param, whichever is cheaper).
- HP; laser damage per second. **On death: plasma burst** of radius `burst_radius` (upgrade track,
  start small, about 1–2 cells) → every non-rooted corrupted cell inside → 0. Rooted cells stay.
- Round end: despawn all crawlers, clear all **non-rooted** corruption (default; GDD §10 OPEN).
  Rooted cells are saved with the planet.

**M6 acceptance:** ≥8 crawlers path concurrently without frame drops >2 ms; they enter dug pits;
they never path to unexposed deposits; corruption visibly spreads through the occupied deposit
only; killing early saves most of it; a bigger burst upgrade frees more.

## 9. Round loop, upgrades, persistence (M5) and shell collapse (M7)

### Run state
- `fuel` drains: `passive + laser_on·laser_type.fuel_per_sec + tractor_on·tractor_cost`.
- `fuel ≤ 0` → round end: freeze input, tally collected ore → `Meta.bank`, despawn chunks
  (lost) and crawlers, clear non-rooted corruption, save planet, show upgrade screen.
- Upgrade screen: list of `UpgradeDef` (id, track, levels, cost per level by ore, effect key/value).
  Buttons: Buy, **Next round (same planet)**, **New planet**.

### Persistence
- `user://meta.json` — ore bank, upgrade levels, current planet id.
- `user://planets/<id>.planet` — header (version, seed, L, K, r_core, dr), `fill` buffer
  (`FileAccess` + ZSTD compression), `corruption` buffer (rooted cells only survive a save),
  deposit runtime state that persists (mined amounts), `outermost_intact_shell` / collapse count,
  per-shell removed counters. Material/deposit layout regenerates from seed.

### Shell collapse (M7)
- Visible if upgrade owned and `cleared_fraction(outermost_intact_shell) ≥ threshold` (0.8 base).
- On press: zero all fill in that shell, play dissolve, mark all chunks dirty (rebuild spread over
  frames), `outermost_intact_shell −= 1` (inward), **animate the satellite down to the new
  `orbit_radius`** (§6.1), save.
- Later upgrade stages (threshold, salvage, …) are **undecided until playtested**; keep the
  threshold and any salvage % as plain tunables so they can become upgrades later.

## 10. Testing & tooling

- `tests/` holds headless scripts (`extends SceneTree`), run with
  `godot --headless -s tests/<name>.gd` (Godot executable path is machine-specific — set it
  locally). Priorities: icosphere invariants, lattice lookup, mesher watertightness (every edge
  shared by exactly 2 triangles on a closed carve), save/load round-trip, carve rate math.
- The C++ core adds three gates (run them after touching `addons/planet_core/`):
  - `godot --headless -s tests/test_planet_core_equivalence.gd` — **the equivalence gate.** Builds
    the same planet twice (GDScript reference vs extension) and asserts the triangle arrays match:
    positions within 1e-6, normals and colours within 1e-4. Reports vertex/triangle counts and the
    max delta, per patch and for the whole planet, on an intact/carved/corrupted planet. Also
    compares fill/material/deposit/corruption, gradients, `points_in_sphere`, `erode` and
    `shell_removed`, and fails on any mismatch.
  - `godot --headless -s tests/test_planet_core_extension.gd` — the `.so` loaded, every class and
    public method is registered, and one chunk meshes headlessly (prints the triangle count).
  - `godot --headless -s tests/test_planet_core_equivalence_levels.gd` — the same equivalence at
    L=3/C=1 and L=4/C=2, so the port is not tuned to the shipping lattice.
  - `godot --headless --fixed-fps 60 -s tests/test_planet_core_boot.gd` — boots the real entry
    scene `game/main.tscn` on the C++ path and prints `PlanetCore.available`, proof the C++ mesher
    built the chunks (`using_core_mesher`, `core_chunk_builds`), triangle count,
    `initial_build_ms`, `worst_chunk_ms` and the per-chunk median/p90.
  - `godot --headless -s tests/test_planet_core_perf.gd` — guards the O(n²) trap: asserts the
    indexed accessors stay orders of magnitude cheaper than `get_fill()[idx]` and that one
    `LaserCarve.apply()` tick stays well under a frame.
- Building the extension: `cd addons/planet_core && scons platform=linux target=template_debug -j4`.
  Run `godot --headless --import` once afterwards so the editor picks up the new `.so`.
- `debug_overlay.gd`: FPS, chunk rebuild ms, dirty queue length, live chunks/crawlers, nav
  raycasts/frame. Toggle F3.
- Debug keys: F5 refill fuel, F6 grant ore, F7 carve big sphere at aim, F8 toggle cutaway.

## 11. Risks

| Risk | Mitigation |
|---|---|
| GDScript meshing too slow | Early-out prisms, time-sliced dirty queue, row-band chunks, port mesher only if needed. |
| Trimesh collision rebuild hitches | Same queue/budget as mesh; consider only rebuilding collision for chunks near crawlers/chunks. |
| Navigator raycast cost | Fixes in §8; per-frame raycast budget; fallback: A\* over lattice "air-next-to-solid" points (no raycasts). |
| Chunk physics count | Cap + merge; sleep settled bodies. |
| Small cells near core | Fine for MVP; later use a coarser icosphere for deep shells. |

## 12. Post-MVP backlog

Ore pickup ships · autonomous mining bots · laser satellites · designer's gyro armature + hologram ·
authored particles per material · heat/crack shader effects · core meaning · planet variety ·
more crawler types · LOD for bigger planets.
