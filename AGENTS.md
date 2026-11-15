# Nebula — agent handover

Incremental planet-mining game in **Godot 4.7 / GDScript / GL Compatibility / Jolt**.
A gyro satellite orbiting a small layered planet lasers out ore, a tractor beam extracts it,
crawlers corrupt exposed deposits, fuel ends the round, ore buys upgrades, and collapsing a
cleared shell drops the satellite to a lower orbit.

## Read first
1. [docs/GDD.md](docs/GDD.md) — what the game is, decisions log, open questions.
2. [docs/ROADMAP.md](docs/ROADMAP.md) — technical design, milestones, **Status table** (start here
   to find the next task), acceptance criteria.

## Rules of the road
- The **planet + ore system is the star**. Everything else stays placeholder (capsules, lines,
  plain UI) unless the designer says otherwise.
- New game code goes in `game/`, data `.tres` in `data/`, tests in `tests/`. Don't restructure
  the existing prototype folders (`surface_crawler/`, `script/`, `demo-experiment-sufrnorm/`,
  `materials/`) — reuse from them as ROADMAP §2 describes.
- Data-driven: materials, shells, ores, laser types, lenses, upgrades are Resources. Upgrades
  modify runtime-derived stats, never the `.tres` files.
- Keep the mesher pure-data (arrays in → arrays out) so it can be ported later.
- When you finish or change scope on a milestone, **update the ROADMAP Status table and the GDD
  decisions log** in the same commit. Open design questions go to GDD §10 — ask the designer
  rather than guessing on anything marked OPEN (or use the documented default and say so).
- Godot executable path is machine-specific; tests run as
  `godot --headless -s tests/<name>.gd`.
