class_name PlanetDef
extends Resource
## Planet layout: lattice resolution and the shell stack (ROADMAP §4).

## Icosphere subdivision level. 5 → 10 242 lattice columns.
@export_range(1, 6) var subdivision: int = 5
## Chunk patch level. 2 → 320 chunks.
@export_range(0, 4) var patch_level: int = 2
## Radius of the innermost diggable row.
@export var core_radius: float = 8.0
## Radial spacing between rows.
@export var row_spacing: float = 1.0
## Material of the indestructible core.
@export var core_material: MaterialDef
## Shells from the OUTSIDE in: shells[0] is the crust.
@export var shells: Array[ShellDef] = []


func diggable_rows() -> int:
	var n := 0
	for s in shells:
		n += s.rows
	return n
