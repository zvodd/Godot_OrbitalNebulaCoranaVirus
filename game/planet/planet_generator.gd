class_name PlanetGenerator
extends RefCounted
## seed → materials and ore deposits. Deterministic, so a save only needs the seed plus
## mutable state (ROADMAP §4.3).


static func generate(grid: PlanetGrid, planet_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = planet_seed
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = planet_seed
	noise.frequency = 1.0

	var V := grid.V
	var rows := grid.rows
	var verts := grid.ico.verts
	var fill := grid.fill
	var material := grid.material

	# Core row: solid, indestructible. Air row: empty.
	var core_mi := grid.material_index(grid.def.core_material)
	for v in V:
		fill[v] = 1.0
		material[v] = core_mi
		fill[(rows - 1) * V + v] = 0.0

	for k in range(1, rows - 1):
		var shell := grid.def.shells[grid.shell_of_row[k]]
		var base_mi := grid.material_index(shell.base_material)
		var sec_mi := grid.material_index(shell.secondary_material)
		var amount := shell.secondary_amount if sec_mi >= 0 else 0.0
		var scale := grid.row_radius(k) * shell.noise_frequency
		var row := k * V
		for v in V:
			fill[row + v] = 1.0
			var mi := base_mi
			if amount > 0.0:
				var n := noise.get_noise_3dv(verts[v] * scale + Vector3(0, k * 0.15, 0))
				if n * 0.75 + 0.5 < amount:
					mi = sec_mi
			material[row + v] = mi

	grid.fill = fill
	grid.material = material
	_place_deposits(grid, rng)
	for s in grid.shell_removed.size():
		grid.shell_removed[s] = 0.0
	grid.refresh_exposure()
	grid.mark_all_dirty()


static func _place_deposits(grid: PlanetGrid, rng: RandomNumberGenerator) -> void:
	grid.deposits.clear()
	grid.deposit.fill(-1)
	var V := grid.V
	var offs := grid.ico.adj_offsets
	var adj := grid.ico.adj
	for s in grid.def.shells.size():
		var shell := grid.def.shells[s]
		var k_lo := grid.shell_bottom_row[s]
		var k_hi := grid.shell_top_row[s]
		for ore in shell.ores:
			var mi := grid.material_index(ore.material)
			if mi < 0:
				continue
			var count := rng.randi_range(ore.count_min, ore.count_max)
			for c in count:
				var start := -1
				for attempt in 8:
					var idx := rng.randi_range(k_lo, k_hi) * V + rng.randi_range(0, V - 1)
					if grid.deposit[idx] < 0:
						start = idx
						break
				if start < 0:
					continue
				var d := Deposit.new()
				d.id = grid.deposits.size()
				d.material_index = mi
				d.shell = s
				grid.deposits.append(d)

				var target := rng.randi_range(ore.size_min, ore.size_max)
				var frontier := PackedInt32Array([start])
				grid.deposit[start] = d.id
				# Grow from a random frontier cell each step → blobby, not spherical.
				while not frontier.is_empty() and d.cells.size() < target:
					var pick := rng.randi_range(0, frontier.size() - 1)
					var idx := frontier[pick]
					frontier[pick] = frontier[frontier.size() - 1]
					frontier.resize(frontier.size() - 1)
					d.cells.append(idx)
					grid.material[idx] = mi
					@warning_ignore("integer_division")
					var k := idx / V
					var v := idx - k * V
					if k > k_lo and grid.deposit[idx - V] < 0:
						grid.deposit[idx - V] = d.id
						frontier.append(idx - V)
					if k < k_hi and grid.deposit[idx + V] < 0:
						grid.deposit[idx + V] = d.id
						frontier.append(idx + V)
					for j in range(offs[v], offs[v + 1]):
						var nb := k * V + adj[j]
						if grid.deposit[nb] < 0:
							grid.deposit[nb] = d.id
							frontier.append(nb)
				# Frontier cells that never made it into the deposit go back to plain terrain.
				for idx in frontier:
					grid.deposit[idx] = -1
