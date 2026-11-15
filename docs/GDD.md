# Game Design Document — Nebula (working title)

> Status: pre-production / MVP planning. Last updated 2026-11-15.
> Companion doc: [ROADMAP.md](ROADMAP.md) (technical design, milestones, task breakdown).
> Anything marked **OPEN** is undecided — ask the designer, or use the stated default.

## 1. Pitch

An **incremental planet-mining game**. You control a two-axis gyroscopic armature hovering over a
small planet. A laser in the armature slowly cuts into the planet's layered shells, ore drops
loose, and a tractor beam hauls it up. Fuel runs out, the round ends, you spend ore on upgrades,
and go again — on the same planet (whose damage persists) or a new one. Crawlers roam the surface
and sit on exposed ore deposits, locking them for the round unless you shoot them first.

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
 │   sit → deposit LOCKED for the round  │
 │ laser kills crawlers en route         │
 │ fuel drains (use + slow passive)      │
 └──────────── fuel = 0 ─────────────────┘
                    │
        round ends: un-extracted chunks lost,
        locks cleared, crawlers despawn
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
  (`exposed`, `locked`, `locked_by`).
- A deposit is **exposed** when any of its solid cells touches air (i.e. mining revealed it).
  Only exposed deposits are reachable by crawlers. **Exposing ore is both the reward and the
  risk** — this is the central tension.

### 3.4 Depth limit
- You cannot cut deeper than **N shells below the outermost intact shell** (MVP N = 3).
  Raising the limit comes from an upgrade path **or** from switching to a laser type with more
  depth reach.
- **OPEN**: designer said "3 layers past the outermost shell". Interpretation (a) = 3 *shells*
  (default, implemented), (b) = 3 *rows* below the outermost shell's floor. If (b) is chosen,
  the limit must be measured from the bottom of the outermost shell, otherwise a thick shell
  could never reach the 80% collapse threshold.

### 3.5 Shell collapse
- Unlocked by an upgrade. Once the **outermost intact shell is ≥ 80% cleared** (by initial solid
  volume), a **Collapse** button appears. Pressing it disintegrates every remaining cell of that
  shell (big dissolve effect); the next shell becomes the surface and the depth window moves in.
- Further stages of the upgrade improve it. OPEN: lower threshold (80 → 60 → 40%) and/or salvage a
  percentage of the ore in the collapsing shell. Default plan: both, as separate upgrade tracks.

### 3.6 Persistence
- Planet damage persists across rounds. Deposit **locks reset** each round.
- Player can return to a planet or roll a new one (new seed). MVP: a "New planet" button on the
  upgrade screen; old planet save kept.

## 4. Player tools

The player's gyro carries **emitters**. Emitters are generic components (origin + direction) so
that later satellites/bots can carry the same tools.

### 4.1 Aiming
The laser fires down the centre of the view (crosshair). You aim by rotating the gyro/camera
(existing trackball-style orbit camera). The 3D gyro armature model and the targeting
lens/hologram are the designer's own assets, coming later — placeholder until then.

### 4.2 Laser = **Laser type** + **Lens** (two swappable slots)
- **Laser type** — *what it can get through*. Defines base power per material (or per material
  class), **depth reach** (shells below outermost), and fuel cost/second. Upgrades raise power.
  MVP types (placeholder names):
  - *Thermal* — cuts sand only, depth reach 1.
  - *Plasma* — cuts rock and shallow ores, depth reach 2.
  - *Ion* — cuts everything, depth reach 3, expensive fuel.
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
- Each picks the nearest **exposed, unlocked** deposit and walks there **over existing terrain**
  (planet surface, walls and floors of pits you dug). They cannot burrow.
- On arrival they play a **sit-down animation** (placeholder: squash tween + a couple of seconds)
  and the deposit becomes **locked**: unminable for the rest of the round.
- The laser damages and kills crawlers (the beam also cuts terrain behind/under them).
- Killing a crawler **that has already sat** does **not** unlock the deposit initially. An upgrade
  path later allows it (stage 1: unlocks after a delay; stage 2: unlocks immediately — OPEN, tune).
- Placeholder visuals: capsule/blob mesh.

## 6. Meta-progression

- Currency = the ore types themselves (upgrades cost specific ores → pushes deeper).
- Upgrade tracks (MVP, all data-driven):
  - Laser types: unlock Plasma, Ion; power levels per type.
  - Lenses: unlock Pin, Wide.
  - Depth reach (+1 shell per stage).
  - Fuel: capacity, passive drain, tool efficiency.
  - Tractor: strength, range, cone.
  - Shell collapse: unlock; threshold; salvage.
  - Crawler control: unseat-on-kill.
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
| 2026-11-15 | Sitting crawler's lock survives its death until an upgrade allows unlocking. |
| 2026-11-15 | Shell collapse: upgrade-unlocked, button appears at 80% cleared. |
| 2026-11-15 | Laser split into Laser type (what it cuts, depth reach) and Lens (pattern/spread/focus). |
| 2026-11-15 | Only extracted (tractored) ore counts. |
| 2026-11-15 | Tools are generic emitters; collection via a generic collector (future ships/bots/satellites). |
| 2026-11-15 | GDScript only for MVP; small planet (radius ~32 units). |

## 10. Open questions

1. Depth limit: 3 shells (default) vs 3 rows. See 3.4.
2. Shell collapse later stages: threshold vs salvage (default: both tracks).
3. What the core is.
4. Ore names / setting.
5. Crawler unseat upgrade stages.
6. New-planet variety (MVP: same generator, new seed).
