class_name TractorBeam
extends Emitter
## Cone that pulls ore chunks up to the emitter; chunks that arrive are handed to a
## Collector. Needs line of sight, so deep narrow shafts are harder (GDD §4.3).

## Upgrade-able stats (plain vars for now; Meta-derived later).
@export var beam_range: float = 48.0
@export var half_angle_deg: float = 11.0
## Max pull force. Heavier ores accelerate slower.
@export var strength: float = 40.0
@export var pull_speed: float = 16.0
@export var collect_radius: float = 3.0

var collector: Collector
## Chunks currently being pulled (debug / HUD).
var pulling: int = 0

var _cone: MeshInstance3D


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.4, 0.9, 1.0, 0.07)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 1
	mesh.cap_bottom = false
	mesh.material = mat
	_cone = MeshInstance3D.new()
	_cone.mesh = mesh
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cone.visible = false
	add_child(_cone)
	_update_cone()


func _update_cone() -> void:
	# Cylinder axis is +Y with the apex at +Y/2; aim is -Z. Put the apex at the emitter.
	var r := beam_range * tan(deg_to_rad(half_angle_deg))
	var b := Basis(Vector3.RIGHT * r, Vector3.BACK * beam_range, Vector3.DOWN * r)
	_cone.transform = Transform3D(b, Vector3.FORWARD * beam_range * 0.5)


func _physics_process(_delta: float) -> void:
	_cone.visible = active
	pulling = 0
	if not active:
		return
	var origin := aim_origin()
	var dir := aim_direction()
	var cos_limit := cos(deg_to_rad(half_angle_deg))
	var space := get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group(OreChunk.GROUP):
		var chunk := node as OreChunk
		if chunk == null or chunk.is_queued_for_deletion():
			continue
		var to_chunk := chunk.global_position - origin
		var dist := to_chunk.length()
		if dist <= collect_radius:
			if collector != null:
				collector.receive(chunk.ore_id, chunk.amount)
			chunk.queue_free()
			continue
		if dist > beam_range or to_chunk.dot(dir) / dist < cos_limit:
			continue
		# Line of sight against terrain only.
		var query := PhysicsRayQueryParameters3D.create(chunk.global_position, origin, LAYER_TERRAIN)
		if not space.intersect_ray(query).is_empty():
			continue
		var want := -to_chunk / dist * pull_speed
		var force := (want - chunk.linear_velocity) * chunk.mass * 6.0
		chunk.sleeping = false
		chunk.apply_central_force(force.limit_length(strength))
		pulling += 1
