class_name OreDef
extends Resource
## One entry of a shell's ore table: how many deposits of which ore material, and how big.

@export var material: MaterialDef
@export var count_min: int = 4
@export var count_max: int = 8
## Deposit size in lattice cells.
@export var size_min: int = 30
@export var size_max: int = 90
