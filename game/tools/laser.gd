class_name Laser
extends Emitter
## Cuts the planet along its aim. Laser type decides what it can get through and how deep;
## the lens decides the footprint. Visuals are placeholders (cylinder + sparks + light).

var planet: Planet
var laser_type: LaserTypeDef
var lens: LensDef
## Upgrade hooks (Meta-derived stats later). Never written into the .tres.
var power_mult: float = 1.0
var reach_bonus: float = 0.0

## Aim state, refreshed every physics frame whether firing or not.
var has_hit: bool = false
var hit_point: Vector3 = Vector3.ZERO
var hit_normal: Vector3 = Vector3.UP
## Result of the last firing tick (null when idle).
var last_result: LaserCarve.Result = null
## Material index under the beam centre, or -1.
var aimed_material: int = -1

var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _sparks: CPUParticles3D
var _glow: OmniLight3D


func _ready() -> void:
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.1
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	cyl.material = _beam_mat
	_beam = MeshInstance3D.new()
	_beam.mesh = cyl
	_beam.top_level = true
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)

	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3.ONE * 0.16
	spark_mesh.material = spark_mat
	_sparks = CPUParticles3D.new()
	_sparks.mesh = spark_mesh
	_sparks.top_level = true
	_sparks.emitting = false
	_sparks.amount = 48
	_sparks.lifetime = 0.7
	_sparks.local_coords = false
	_sparks.spread = 50.0
	_sparks.initial_velocity_min = 3.0
	_sparks.initial_velocity_max = 9.0
	_sparks.gravity = Vector3.ZERO
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.4
	add_child(_sparks)

	_glow = OmniLight3D.new()
	_glow.top_level = true
	_glow.omni_range = 9.0
	_glow.light_energy = 2.5
	_glow.visible = false
	add_child(_glow)


func _physics_process(delta: float) -> void:
	last_result = null
	if planet == null or planet.grid == null or laser_type == null or lens == null:
		_show(false, false)
		return
	var origin := aim_origin()
	var dir := aim_direction()
	# A ray that passes exactly through a mesh vertex (aiming dead down a lattice column)
	# can slip between triangles, so retry with a hair of sideways offset before giving up.
	var space := get_world_3d().direct_space_state
	var side := global_basis.x.normalized() * 0.02
	var hit := {}
	for nudge: Vector3 in [Vector3.ZERO, side, -side + global_basis.y.normalized() * 0.02]:
		var from := origin + nudge
		hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(
				from, from + dir * origin.length() * 1.5, LAYER_TERRAIN | LAYER_CRAWLER))
		if not hit.is_empty():
			break
	has_hit = not hit.is_empty()
	if not has_hit:
		aimed_material = -1
		_show(active, false)
		if active:
			_place_beam(origin, origin + dir * 200.0)
		return
	hit_point = hit.position
	hit_normal = hit.normal
	var grid := planet.grid
	var local_hit := planet.to_local(hit_point)
	var local_dir := planet.global_basis.inverse() * dir
	aimed_material = _material_at(local_hit, local_dir)

	if not active:
		_show(false, false)
		return
	# TODO(M6): a crawler hit takes damage here and stops the beam.
	last_result = LaserCarve.apply(grid, local_hit, local_dir, laser_type, lens,
			planet.to_local(origin).length(), delta, power_mult, reach_bonus)
	_place_beam(origin, hit_point)
	_show(true, true)
	var cutting := last_result.removed > 0.0
	var mi := last_result.cut_material if cutting else aimed_material
	var col: Color = _spark_color(grid, mi)
	_sparks.global_position = hit_point - dir * 0.2
	_sparks.direction = -dir
	_sparks.color = col.lightened(0.25) if cutting else Color(0.6, 0.6, 0.6)
	_sparks.initial_velocity_max = 9.0 if cutting else 3.0
	# Sparks fall back toward the planet.
	_sparks.gravity = -hit_point.normalized() * 6.0
	_glow.global_position = hit_point - dir * 0.8
	_glow.light_color = laser_type.beam_color
	_glow.light_energy = 2.5 if cutting else 0.8


## Material colour for the spark tint. Indexed on the C++ grid so it does not copy the table.
func _spark_color(grid: RefCounted, mi: int) -> Color:
	if mi < 0:
		return Color.WHITE
	var core := grid as PlanetCoreGridData
	if core != null:
		return core.mat_color_at(mi)
	return (grid as PlanetGrid).mat_colors[mi]


## Material of the solid cell nearest to just below the hit.
func _material_at(local_hit: Vector3, local_dir: Vector3) -> int:
	return _nearest_material(planet.grid, local_hit + local_dir * 0.4)


func _nearest_material(grid: RefCounted, probe: Vector3) -> int:
	var best := -1
	var best_d := INF
	var core := grid as PlanetCoreGridData
	if core != null:
		# fill_at / material_at are single-cell reads; grid.fill[idx] would copy the lattice.
		for idx in core.points_in_sphere(probe, 1.3):
			if core.is_solid_at(idx):
				var d := core.lattice_pos(idx).distance_squared_to(probe)
				if d < best_d:
					best_d = d
					best = idx
		return core.material_at(best) if best >= 0 else -1
	var g := grid as PlanetGrid
	for idx in g.points_in_sphere(probe, 1.3):
		if g.fill[idx] >= PlanetGrid.ISO:
			var d := g.lattice_pos(idx).distance_squared_to(probe)
			if d < best_d:
				best_d = d
				best = idx
	return g.material[best] if best >= 0 else -1


func _place_beam(from: Vector3, to: Vector3) -> void:
	var axis := to - from
	var length := axis.length()
	if length < 0.001:
		return
	var y := axis / length
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var width := clampf(lens.spread * 0.6, 0.6, 3.0)
	_beam.global_transform = Transform3D(Basis(x * width, y * length, z * width), (from + to) * 0.5)
	var c := laser_type.beam_color
	_beam_mat.albedo_color = Color(c.r, c.g, c.b, 0.85)


func _show(beam: bool, impact: bool) -> void:
	_beam.visible = beam
	_sparks.emitting = impact
	_glow.visible = impact
