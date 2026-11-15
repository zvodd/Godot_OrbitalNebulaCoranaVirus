class_name Emitter
extends Node3D
## Base for anything that fires along a direction (laser, tractor). Aim = the node's own
## -Z, so the same tool works on the gyro satellite now and on bots / laser satellites later.

const LAYER_TERRAIN := 1
const LAYER_ORE := 2
const LAYER_CRAWLER := 4
const LAYER_COLLECTOR := 8

## Held on / off by whoever owns the emitter.
var active: bool = false


func aim_origin() -> Vector3:
	return global_position


func aim_direction() -> Vector3:
	return -global_basis.z.normalized()
