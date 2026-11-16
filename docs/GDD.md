# Game Design Document — Nebula (working title)

> Status: pre-production / MVP planning. Last updated 2026-11-16.
> Companion doc: [ROADMAP.md](ROADMAP.md) (technical design, milestones, task breakdown).
> Anything marked **OPEN** is undecided — ask the designer, or use the stated default.

## 1. Pitch

An **incremental planet-mining game**. You control a big gyroscopic satellite orbiting a small
planet. Its laser slowly cuts into the planet's layered shells, ore drops loose, and a tractor
beam hauls it up. Fuel runs out, the round ends, you spend ore on upgrades, and go again — on the
same planet (whose damage persists) or a new one. Crawlers roam the surface and sit on exposed ore
deposits, corrupting the ore around them unless you shoot them first. Clear enough of a shell and
it collapses: the satellite drops to a lower orbit and the planet looms larger.

**The planet and ore system is the star of the show.** Everything else stays rudimentary
(placeholder meshes, lines, plain UI) until the core feels good.

## 2. Core loop

```
 ┌──────────────── ROUND ────────────────┐
 │ aim gyro → laser cuts cells           │
 │   rock/sand → vaporize (particles)    │
 │   ore       → drops ORE CHUNKS        │
 │ tractor beam pulls chunks → collected │
 │ crawlers walk to exposed deposits,    │
 │   sit → ore around them CORRUPTS      │
 │ laser kills crawlers (plasma burst    │
 │   cleanses non-rooted corruption)     │
 │ shell ≥80% cleared → COLLAPSE button  │
 │   → satellite drops to lower orbit    │
 │ fuel drains (use + slow passive)      │
 └──────────── fuel = 0 ─────────────────┘
                    │
        round ends: un-extracted chunks lost,
        crawlers despawn, non-rooted corruption cleared
                    │
            UPGRADE SCREEN (spend ore)
                    │
        same planet (damage persists) or new planet
```

Pacing target: early rounds are slow and grindy (sand is slow, rock is impossible). Upgrades
steadily turn obstacles into nothing — the classic incremental "number goes up" feel, expressed
as the planet getting easier to tear apart.

## 3. The Planet

### 3.1 Structure
- The planet is a **layered icosphere**: a geodesic grid of cells on the sphere, repeated at
  many radial depths (**rows**). Each lattice point stores *fill* (how solid, 0–1),
  *material*, and *deposit id*.
- Rows are grouped into **shells** (concentric bands, e.g. 8–10 shells of ~3 rows each).
  Shells are the design-level "layers": each shell has its own base material mix and ore table.
- A **core** at the centre is indestructible (MVP). OPEN: what the core means (win, jackpot,
  nothing). Default: nothing; it's just the floor.
- Rendering is a smooth mesh extracted from the lattice (treated as a distance field), so
  carving produces organic craters/tunnels, not blocks.

### 3.2 Materials
Materials are **data, not simulation**. No slumping sand, no structural collapse physics.
Each material defines:

| Field | Meaning |
|---|---|
| `min_power` | Per-cell laser power below which the material cannot be cut at all (beam just scorches). |
| `hardness` | Erosion rate divisor once cuttable: `rate = power / hardness`. |
| `instant_threshold` | When `rate` exceeds it, the cell is removed instantly ("evaporates like sand"). |
| `particle_effect` | Authored scene played while cutting. MVP: one generic burst tinted per material. |
| `ore_type` | `none` → vaporizes. Otherwise the cell drops ore chunks of that type. |
| `color` | Placeholder vertex colour on the planet mesh. |

MVP material set:
- **Sand** — cuttable from the start, slow; becomes instant after a few laser upgrades.
- **Rock** — *cannot* be cut initially; a very early upgrade allows it (slow); further upgrades
  eventually make it as easy as sand (instant).
- **Ores** — 3–4 types, each with its own `min_power`/`hardness`, found at increasing depth.
  Placeholder names: Copper, Cobalt, Iridium, Aetherite. OPEN: final names/theme.

### 3.3 Ore deposits
- Ore exists as **deposits**: connected blobs of ore cells generated per shell from the shell's
  ore table. A deposit has an id, ore type, its cells, and runtime state
  (`exposed`, `occupied_by` crawler). Corruption is tracked **per cell**, not per deposit (see 5).
- A deposit is **exposed** when any of its solid cells touches air (i.e. mining revealed it).
  Only exposed deposits are reachable by crawlers. **Exposing ore is both the reward and the
  risk** — this is the central tension.

### 3.4 Depth limit = laser focal reach (PROPOSED, confirm in playtest)
- The beam can only focus so far from the satellite. Each laser type has a **reach** (distance);
  cells closer to the core than `orbit_radius − reach` cannot be cut.
- Reach grows with upgrades or by switching laser type. Shell collapse lowers the satellite's
  orbit (3.5), which moves the whole reachable window deeper. This unifies "depth limit",
  "laser type depth" and "collapse lets you go deeper" into one number.
- Tune so that, at the start, reach covers roughly the outer shell plus a little of the next.
  This replaces the earlier "3 layers past the outermost shell" rule (which was ambiguous between
  shells and rows).

### 3.5 Shell collapse
- Unlocked by an upgrade. Once the **outermost intact shell is ≥ 80% cleared** (by initial solid
  volume), a **Collapse** button appears. Pressing it disintegrates every remaining cell of that
  shell (big dissolve effect) and **reveals the next shell as the new surface**.
- **The satellite then descends to a lower orbit**, so the planet looks *bigger* on screen after
  each collapse, and the laser's reach now extends deeper. In-fiction: "now we can get close
  enough to focus nearer the core". (Note for tuning: the orbit must drop by more than the shell's
  thickness, proportionally, or the planet would look *smaller*. See ROADMAP §6.1.)
- **Needs playtesting.** Threshold starts at 80%. Later upgrade stages (lower threshold, ore
  salvage from the collapsing shell, etc.) are deliberately undecided until it's playable.

### 3.6 Persistence
- Planet damage persists across rounds, and so do **rooted** (permanent) corrupted cells.
  Non-rooted corruption is cleared at round end (default; see 5).
- Player can return to a planet or roll a new one (new seed). MVP: a "New planet" button on the
  upgrade screen; old planet save kept.

## 4. Player tools

The player's gyro is **a big satellite** in orbit around the planet. It carries **emitters**.
Emitters are generic components (origin + direction) so that later satellites/bots can carry the
same tools; a "laser satellite" upgrade is literally another one of these.

### 4.1 Aiming
- The satellite **orbits freely over the whole sphere, poles included**; the planet stays still
  (simplest for physics, chunks and crawlers).
- The laser fires down the centre of the view (crosshair). You aim by moving the satellite around
  its orbit (trackball-style controls with inertia, from the existing camera script). Scroll only
  moves the camera relative to the satellite; it doesn't change the orbit or the beam's reach.
- Orbit radius is set by the outermost intact shell (drops on collapse, 3.5).
- The 3D gyro armature model and the targeting lens/hologram are the designer's own assets,
  coming later; placeholder until then.

### 4.2 Laser = **Laser type** + **Lens** (two swappable slots)
- **Laser type** — *what it can get through*. Defines base power per material (or per material
  class), **reach** (focal distance from the satellite, see 3.4), and fuel cost/second.
  Upgrades raise power and reach. MVP types (placeholder names), shortest to longest reach:
  - *Thermal* — cuts sand only, short reach.
  - *Plasma* — cuts rock and shallow ores, medium reach.
  - *Ion* — cuts everything, long reach, expensive fuel.
- **Lens** — *the pattern, spread and focus of the beam*.
  - pattern: circle, line, ring, scatter (set of sample points around the hit point)
  - spread: radius of the pattern
  - focus: concentration factor
  - **Per-cell power = laser power × focus ÷ beam area × pattern weight.** A wide lens spreads
    power thin: clears sand fast but may drop below rock's `min_power`. A pin lens bores rock but
    clears area slowly. The interplay falls out of the material model with no extra rules.
  - MVP lenses: *Standard* (circle, medium), *Pin* (small, high focus), *Wide* (large, low focus).

### 4.3 Ore chunks and the tractor beam
- Cutting ore cells accumulates ore; each time a threshold is reached an **ore chunk** (small
  physics body) pops out at the cut and falls toward the planet centre (radial gravity).
- The **tractor beam** (hold right mouse) is a cone from the gyro. Chunks in range and line of
  sight are pulled up; on reaching the gyro they're **collected**. **Only extracted ore counts.**
  Chunks still on the planet when fuel runs out are lost.
- Tractor upgrades: pull strength (heavier ores need more), range, cone width.
- Deep narrow shafts make extraction harder — this is intended.

### 4.4 Fuel
- Fuel drains from **laser use + tractor use + a slow passive drain**. Fuel 0 → round ends.
- Upgrades: tank capacity, passive-drain reduction, per-tool efficiency.

## 5. Crawlers (enemies)

- Spawn on the planet surface over the round (rate rises with round time / depth).
- Each picks the nearest **exposed, unoccupied** deposit and walks there **over existing terrain**
  (planet surface, walls and floors of pits you dug). They cannot burrow.
- On arrival they play a **sit-down animation** (placeholder: squash tween + a couple of seconds)
  and start **corrupting** the deposit: tendrils of reinforcement spread outward through the ore
  they landed on, making it **unminable**. The corrupted area grows slowly over time.
  - Corruption spreads only through cells of **that deposit's ore**, starting at the crawler.
  - PROPOSED mechanic: each corrupted cell's corruption keeps growing; once it passes a threshold
    the cell is **rooted** (permanent). So older tendrils near the crawler root first.
- The laser damages and kills crawlers (the beam also cuts terrain behind/under them).
- **Killing a crawler releases a plasma burst** that cleanses corruption within a radius, but
  **rooted cells stay corrupted** ("some of it is permanent"). Kill them early and you lose little.
- **Upgrade path:** a bigger plasma burst radius, so more of the corrupted ore is freed.
- OPEN: does "permanent" mean for the rest of the round or forever on this planet? Default:
  rooted cells stay unminable **for good on this planet**; non-rooted tendrils left by crawlers
  still alive at round end are cleared.
- Placeholder visuals: capsule/blob mesh; corrupted cells tinted dark on the planet mesh.

## 6. Meta-progression

- Currency = the ore types themselves (upgrades cost specific ores → pushes deeper).
- Upgrade tracks (MVP, all data-driven):
  - Laser types: unlock Plasma, Ion; power levels per type.
  - Lenses: unlock Pin, Wide.
  - Laser reach (focal distance).
  - Fuel: capacity, passive drain, tool efficiency.
  - Tractor: strength, range, cone.
  - Shell collapse: unlock (further stages TBD after playtesting).
  - Crawler control: plasma burst radius on kill.
- Upgrade screen: plain list/grid of buttons with costs. Placeholder UI.

## 7. Presentation (MVP = placeholder)

- Planet: vertex-coloured mesh using the existing triplanar shader approach, per-material colour.
- Laser: line/cylinder from gyro to hit point, colour per laser type.
- Tractor: translucent cone.
- Particles: one CPU/GPU particle burst tinted per material (designer authors real ones later).
- Sky: existing nebula sky shader. Crosshair: existing canvas shader.
- HUD: fuel bar, ore counts, current laser/lens, depth/shell info, collapse button.

## 8. Later goals (post-MVP, do not build yet — but don't design them out)

- **Ore pickup ships** — fly down and fetch chunks (another `Collector`).
- **Autonomous mining bots** — on-surface miners (another emitter carrier; reuse crawler nav).
- **Laser satellites** — orbiting emitters with their own laser type/lens.
- Designer's gyro armature model + targeting hologram.
- Authored particle effects per material.
- More crawler behaviours; core meaning; planet variety (biomes, sizes).

## 9. Decisions log

| Date | Decision |
|---|---|
| 2026-11-15 | Data model = layered icosphere lattice; render via mesh extraction (marching tetrahedra), **not** shader raymarching (keeps physics collision, existing raycast navigator, chunk physics). |
| 2026-11-15 | Materials are data only (no slumping/structural sim); difficulty comes from upgrades vs `min_power`/`hardness`; visuals via authored particles. |
| 2026-11-15 | Fuel drains on tool use + slow passive drain. |
| 2026-11-15 | ~~Sitting crawler's lock survives its death until an upgrade allows unlocking.~~ Superseded by the corruption model below. |
| 2026-11-15 | Shell collapse: upgrade-unlocked, button appears at 80% cleared. |
| 2026-11-15 | Laser split into Laser type (what it cuts, reach) and Lens (pattern/spread/focus). |
| 2026-11-15 | Only extracted (tractored) ore counts. |
| 2026-11-15 | Tools are generic emitters; collection via a generic collector (future ships/bots/satellites). |
| 2026-11-15 | GDScript only for MVP; small planet (radius ~32 units). |
| 2026-11-15 | The gyro is a big satellite orbiting freely (poles included); the planet stays still. |
| 2026-11-15 | Shell collapse reveals the next surface and lowers the satellite's orbit (planet looks bigger, beam reaches deeper). Stages after unlock: decide after playtesting. |
| 2026-11-15 | Crawlers corrupt ore around them over time instead of locking a whole deposit; death releases a plasma burst that cleanses non-permanent corruption; upgrades enlarge the burst. |
| 2026-11-15 | First playable (M1–M4 core): all laser types and lenses are unlocked until the upgrade system exists; no fuel yet. Starting numbers live in `data/` and are untuned (sand currently digs fast with Thermal). |
| 2026-11-15 | The beam cuts only exposed cells, so ore is always revealed before it is eaten. Crosshair is drawn where the beam lands, not at screen centre. |
| 2026-11-16 | Meshing moves to a C++ GDExtension (`addons/planet_core/`) behind the existing pure-data contract, so it can be threaded later. Equivalence with the GDScript reference is a hard gate, not a tolerance to tune: the port reproduces GDScript's float32/float64 narrowing exactly, so positions come out **bit-identical** (max delta 0.0). Whole-planet meshing measured 820 ms → 27 ms (~31x). The GDScript classes stay as the reference implementation, so the port can always be diffed. |
| 2026-11-16 | The extension's generator calls the engine's own `RandomNumberGenerator` + `FastNoiseLite` rather than reimplementing them, so the same seed produces the same planet (204 deposits, identical cells) in both implementations. This keeps saves portable across the port and makes the equivalence gate meaningful. |
| 2026-11-16 | The extension is **pure data and resource-free**: a plain-data `PlanetCoreConfig` mirrors `PlanetDef`, built by `game/planet/planet_core.gd`. Godot `Resource`s stay a GDScript concern, which keeps the C++ side independent of the data-driven layer and safe to thread. |
| 2026-11-16 | The game now runs on the C++ core (`Planet` owns a `PlanetCoreGridData` + `PlanetCoreMesher`). Cells are read and written through **indexed accessors** (`fill_at`, `set_fill_at`, `erode`, `dirty_patch_at`, …), never through the whole-array getters: `get_fill()` copies ~1 MB, so indexing it in the carve loop is O(n²) and wipes out the win. Measured 1422x cheaper per access. |
| 2026-11-16 | `PlanetChunk` keeps one `ConcavePolygonShape3D` and updates it in place, never re-assigning it to the `CollisionShape3D`. Re-assigning costs 0.42-0.66 ms/chunk because the physics server rebuilds the shape's BVH; in-place update costs 0.012 ms. With that fixed, a 320-chunk rebuild is 231 ms initial / 0.40 ms median per chunk (was 1964 ms / 2.68 ms in GDScript). Collision cost itself is irreducible — an enabled trimesh shape is ~15x more expensive to update than a disabled one, and batching just moves the charge. |
| 2026-11-16 | The GDScript core stays selectable (`Planet.use_gdscript_core`) but is no longer the shipping path; it remains the equivalence reference, so the port can always be diffed. |

## 10. Open questions

1. Depth limit as laser focal reach from the satellite (proposed, 3.4); confirm once playable.
2. Shell collapse stages after unlock; needs playtesting.
3. Corruption permanence: rest of round vs forever on the planet (default: rooted = forever). See 5.
4. Can the laser and tractor fire at the same time? Default: yes.
5. What the core is.
6. Ore names / setting.
7. New-planet variety (MVP: same generator, new seed).
