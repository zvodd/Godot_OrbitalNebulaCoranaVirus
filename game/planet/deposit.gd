class_name Deposit
extends RefCounted
## A connected blob of ore cells plus its runtime state (GDD §3.3).

var id: int = -1
## Index into PlanetGrid.materials.
var material_index: int = 0
var shell: int = 0
## Lattice indices.
var cells: PackedInt32Array = PackedInt32Array()
## True once any solid cell of the deposit touches air. Crawlers only target exposed deposits.
var exposed: bool = false
## Crawler sitting on it (M6), or null.
var occupied_by: Object = null
## Cut volume not yet turned into an ore chunk.
var accum: float = 0.0
## Total volume cut out of this deposit.
var mined: float = 0.0
