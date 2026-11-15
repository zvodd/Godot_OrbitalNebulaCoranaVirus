class_name LaserCarve
extends RefCounted
## The carve maths, kept free of nodes so it can be unit-tested (ROADMAP §6.3).
##
## Per-cell power = laser power × focus ÷ (beam area in cells).
##   power < material.min_power → scorch only
##   rate = power / hardness (fill per second); rate ≥ instant_threshold → removed at once
## Only exposed cells (or already-opened remnants) are cut, so the beam digs layer by layer
## and reveals ore before eating it.

## World-unit area of one lattice cell near the surface (≈1.2 × 1.2).
const CELL_AREA := 1.4
## Smallest brush that reliably contains a lattice point.
const MIN_BRUSH := 0.9
## How far the brush centre is pushed into the surface along the beam.
const BITE := 0.5
## Spheres stacked back along the beam per sample (capsule length ≈ steps × radius).
const CAPSULE_STEPS := 3
## Cut-rate drop from the beam axis to its edge (0 = flat-bottomed pit, 1 = sharp cone).
const EDGE_FALLOFF := 0.25

enum Block { NONE, TOO_HARD, OUT_OF_REACH, CORRUPTED, CORE }


class Result:
	## Total fill removed this tick.
	var removed: float = 0.0
	## Material index that lost the most fill, or -1.
	var cut_material: int = -1
	## Why the centre of the beam is not cutting (Block), if it isn't.
	var blocked: int = Block.NONE
	## Material index responsible for `blocked`, or -1.
	var blocked_material: int = -1
	## Per-cell power delivered by this laser + lens.
	var cell_power: float = 0.0


static func cell_power(laser: LaserTypeDef, lens: LensDef, power_mult: float = 1.0) -> float:
	return laser.power * power_mult * lens.focus / maxf(lens.area() / CELL_AREA, 1.0)


## Minimum radius (distance from planet centre) this laser can cut at.
static func min_cut_radius(laser: LaserTypeDef, orbit_radius: float, reach_bonus: float = 0.0) -> float:
	return orbit_radius - (laser.reach + reach_bonus)


## Apply one tick of beam. `hit` is the surface hit point, `beam_dir` the beam's travel
## direction (unit). `power_mult` / `reach_bonus` are where upgrades plug in later.
static func apply(grid: PlanetGrid, hit: Vector3, beam_dir: Vector3, laser: LaserTypeDef,
		lens: LensDef, orbit_radius: float, dt: float,
		power_mult: float = 1.0, reach_bonus: float = 0.0) -> Result:
	var res := Result.new()
	var p_cell := cell_power(laser, lens, power_mult)
	res.cell_power = p_cell
	var min_r := min_cut_radius(laser, orbit_radius, reach_bonus)
	var min_r2 := min_r * min_r

	# Tangent frame for the lens pattern.
	var up := Vector3.UP if absf(beam_dir.y) < 0.95 else Vector3.RIGHT
	var tx := beam_dir.cross(up).normalized()
	var ty := tx.cross(beam_dir)

	# idx → strongest falloff over all samples that touch it.
	# Each sample is a short capsule along the beam (a few spheres stacked back toward the
	# emitter), so the pit keeps the beam's full width as its floor sinks instead of
	# narrowing into a pinhole under the hit point.
	var cells := {}
	for s in lens.samples():
		var radius := maxf(s.z, MIN_BRUSH)
		var axis := hit + tx * s.x + ty * s.y
		var r2 := radius * radius
		for step in CAPSULE_STEPS:
			var centre := axis + beam_dir * (minf(BITE, radius) - step * radius)
			for idx in grid.points_in_sphere(centre, radius):
				if grid.fill[idx] <= 0.0:
					continue
				var rel := grid.lattice_pos(idx) - axis
				var along := rel.dot(beam_dir)
				var lateral2 := rel.length_squared() - along * along
				if lateral2 > r2:
					continue
				var falloff := 1.0 - EDGE_FALLOFF * lateral2 / r2
				if falloff > cells.get(idx, 0.0):
					cells[idx] = falloff

	var per_material := {}
	var V := grid.V
	var last_row := grid.rows - 1
	for idx: int in cells:
		var mi := grid.material[idx]
		var m := grid.materials[mi]
		@warning_ignore("integer_division")
		var k := idx / V
		var solid := grid.fill[idx] >= PlanetGrid.ISO
		# Buried cells wait until the layer above them is gone.
		if solid and not grid.is_exposed(idx):
			continue
		var block := Block.NONE
		if k <= 0 or k >= last_row or not m.cuttable():
			block = Block.CORE
		elif grid.lattice_pos(idx).length_squared() < min_r2:
			block = Block.OUT_OF_REACH
		elif grid.corruption[idx] > 0:
			block = Block.CORRUPTED
		elif p_cell < m.min_power:
			block = Block.TOO_HARD
		if block != Block.NONE:
			# Report the block only for solid cells; remnants don't matter.
			if solid and (res.blocked == Block.NONE or block == Block.TOO_HARD):
				res.blocked = block
				res.blocked_material = mi
			continue
		var rate := p_cell / m.hardness
		var amount := 1.0 if rate >= m.instant_threshold else rate * float(cells[idx]) * dt
		var d := grid.erode(idx, amount)
		if d > 0.0:
			res.removed += d
			per_material[mi] = per_material.get(mi, 0.0) + d

	var best := 0.0
	for mi: int in per_material:
		if per_material[mi] > best:
			best = per_material[mi]
			res.cut_material = mi
	if res.removed > 0.0:
		res.blocked = Block.NONE
		res.blocked_material = -1
	return res
