class_name OreChunk
extends RigidBody3D
## A loose piece of ore. Falls toward the planet centre (OreField's gravity area) until a
## tractor beam hauls it to a Collector. Placeholder visuals: a tinted box.

const GROUP := &"ore_chunks"
const LAYER_TERRAIN := 1
const LAYER_ORE := 2
const RADIUS := 0.32

var ore_id: StringName = &""
## Ore units this chunk is worth (grows when chunks merge at the cap).
var amount: float = 1.0
var material_def: MaterialDef


func setup(mat: MaterialDef) -> void:
	material_def = mat
	ore_id = mat.ore_id
	mass = mat.chunk_mass
	collision_layer = LAYER_ORE
	collision_mask = LAYER_TERRAIN | LAYER_ORE
	linear_damp = 0.15
	angular_damp = 1.0
	add_to_group(GROUP)

	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)

	var m := StandardMaterial3D.new()
	m.albedo_color = mat.color
	m.emission_enabled = true
	m.emission = mat.color
	m.emission_energy_multiplier = 0.6
	m.roughness = 0.4
	var box := BoxMesh.new()
	box.size = Vector3.ONE * RADIUS * 1.5
	box.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	add_child(mi)
