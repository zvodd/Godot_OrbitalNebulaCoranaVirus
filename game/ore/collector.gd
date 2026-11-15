class_name Collector
extends Node
## Anything that receives ore: the gyro satellite now, pickup ships later.
## Only ore that reaches a collector counts (GDD §4.3).

signal ore_received(ore_id: StringName, amount: float)

## ore_id → amount collected this round.
var totals: Dictionary = {}


func receive(ore_id: StringName, amount: float) -> void:
	totals[ore_id] = float(totals.get(ore_id, 0.0)) + amount
	ore_received.emit(ore_id, amount)


func clear() -> void:
	totals.clear()
