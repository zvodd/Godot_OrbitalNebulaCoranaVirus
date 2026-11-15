class_name ShellDef
extends Resource
## A concentric band of lattice rows with its own material mix and ore table (GDD §3.1).

@export var name: String = "Shell"
## Number of lattice rows this shell covers.
@export var rows: int = 3
@export var base_material: MaterialDef
## Mixed in by 3D noise. Null = base only.
@export var secondary_material: MaterialDef
## 0 = none, 1 = all secondary.
@export_range(0.0, 1.0) var secondary_amount: float = 0.3
## Noise frequency (per world unit) for the base/secondary bands.
@export var noise_frequency: float = 0.08
@export var ores: Array[OreDef] = []
