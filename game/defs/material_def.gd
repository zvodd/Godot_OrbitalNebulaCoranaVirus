class_name MaterialDef
extends Resource
## One planet material. Data only — no simulation (GDD §3.2).

@export var name: String = "Material"
## Placeholder vertex colour on the planet mesh.
@export var color: Color = Color.GRAY
## Per-cell laser power below which the beam only scorches. INF = indestructible.
@export var min_power: float = 1.0
## Erosion divisor once cuttable: rate (fill/sec) = power / hardness.
@export var hardness: float = 1.0
## If rate >= this the cell is removed instantly.
@export var instant_threshold: float = 8.0
## Authored particle scene (later). MVP uses one generic burst tinted by `color`.
@export var particle_scene: PackedScene

@export_group("Ore")
## Empty = vaporizes when cut. Otherwise the currency key this material drops.
@export var ore_id: StringName = &""
## Fill volume (cells) that must be cut to pop one ore chunk.
@export var chunk_volume: float = 2.0
## Ore chunk mass (heavier ores need a stronger tractor).
@export var chunk_mass: float = 1.0


func is_ore() -> bool:
	return ore_id != &""


func cuttable() -> bool:
	return is_finite(min_power)
