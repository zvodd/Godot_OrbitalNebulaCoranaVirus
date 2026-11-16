#include "planet_core_generator.h"

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

#include <vector>

using namespace godot;

void PlanetCoreGenerator::_bind_methods() {
	ClassDB::bind_static_method("PlanetCoreGenerator", D_METHOD("generate", "grid", "planet_seed"), &PlanetCoreGenerator::generate);
}

void PlanetCoreGenerator::generate(const Ref<PlanetCoreGrid> &grid, int64_t planet_seed) {
	ERR_FAIL_COND_MSG(grid.is_null(), "PlanetCoreGenerator.generate: grid is null.");

	// Owned via Ref: godot-cpp objects must be heap-allocated through the engine.
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)planet_seed);

	Ref<FastNoiseLite> noise;
	noise.instantiate();
	noise->set_noise_type(FastNoiseLite::TYPE_SIMPLEX_SMOOTH);
	noise->set_seed((int32_t)planet_seed);
	noise->set_frequency(1.0f);

	const Ref<PlanetCoreIcosphere> &ico = grid->ico_ref();
	const Ref<PlanetCoreConfig> &config = grid->config_ref();
	const int32_t V = grid->get_V();
	const int32_t rows = grid->get_rows();
	const std::vector<Vector3> &verts = ico->verts_ref();
	std::vector<float> &fill = grid->fill_ref();
	std::vector<uint8_t> &material = grid->material_ref();

	// Core row: solid, indestructible. Air row: empty.
	const int32_t core_mi = config->get_core_material();
	for (int32_t v = 0; v < V; v++) {
		fill[(size_t)v] = 1.0f;
		material[(size_t)v] = (uint8_t)core_mi;
		fill[(size_t)((rows - 1) * V + v)] = 0.0f;
	}

	Array shells = config->get_shells();
	const std::vector<int32_t> &shell_of_row = grid->shell_of_row_ref();
	for (int32_t k = 1; k < rows - 1; k++) {
		const int32_t shell_idx = shell_of_row[(size_t)k];
		Ref<PlanetCoreShell> shell = shells[shell_idx];
		if (shell.is_null()) {
			continue;
		}
		const int32_t base_mi = shell->get_base_material();
		const int32_t sec_mi = shell->get_secondary_material();
		const double amount = sec_mi >= 0 ? shell->get_secondary_amount() : 0.0;
		// row_radius() is a GDScript float (double); noise_frequency is a double too.
		const double scale = grid->row_radius(k) * shell->get_noise_frequency();
		const int32_t row = k * V;
		for (int32_t v = 0; v < V; v++) {
			fill[(size_t)(row + v)] = 1.0f;
			int32_t mi = base_mi;
			if (amount > 0.0) {
				// verts[v] * scale narrows the double scalar to float32, like the engine.
				const Vector3 p = verts[(size_t)v] * (real_t)scale + Vector3(0.0f, (real_t)((double)k * 0.15), 0.0f);
				const double n = (double)noise->get_noise_3dv(p);
				if (n * 0.75 + 0.5 < amount) {
					mi = sec_mi;
				}
			}
			material[(size_t)(row + v)] = (uint8_t)mi;
		}
	}

	_place_deposits(grid, rng.ptr());

	std::vector<double> &shell_removed = grid->shell_removed_ref();
	for (size_t s = 0; s < shell_removed.size(); s++) {
		shell_removed[s] = 0.0;
	}
	grid->refresh_exposure();
	grid->mark_all_dirty();
}

void PlanetCoreGenerator::_place_deposits(const Ref<PlanetCoreGrid> &grid, RandomNumberGenerator *rng) {
	const Ref<PlanetCoreConfig> &config = grid->config_ref();
	const Ref<PlanetCoreIcosphere> &ico = grid->ico_ref();

	std::vector<Ref<PlanetCoreDeposit>> &deposits = grid->deposits_ref();
	deposits.clear();
	std::vector<int32_t> &deposit = grid->deposit_ref();
	std::fill(deposit.begin(), deposit.end(), -1);

	const int32_t V = grid->get_V();
	const std::vector<int32_t> &offs = ico->adj_offsets_ref();
	const std::vector<int32_t> &adj = ico->adj_ref();
	std::vector<uint8_t> &material = grid->material_ref();
	const std::vector<int32_t> &shell_top = grid->shell_top_row_ref();
	const std::vector<int32_t> &shell_bottom = grid->shell_bottom_row_ref();

	const Array shells = config->get_shells();
	for (int64_t s = 0; s < shells.size(); s++) {
		Ref<PlanetCoreShell> shell = shells[s];
		if (shell.is_null()) {
			continue;
		}
		const int32_t k_lo = shell_bottom[(size_t)s];
		const int32_t k_hi = shell_top[(size_t)s];
		const Array ores = shell->get_ores();
		for (int64_t oi = 0; oi < ores.size(); oi++) {
			Ref<PlanetCoreOre> ore = ores[oi];
			if (ore.is_null()) {
				continue;
			}
			const int32_t mi = ore->get_material();
			if (mi < 0) {
				continue;
			}
			const int32_t count = rng->randi_range(ore->get_count_min(), ore->get_count_max());
			for (int32_t c = 0; c < count; c++) {
				int32_t start = -1;
				for (int32_t attempt = 0; attempt < 8; attempt++) {
					const int32_t idx = rng->randi_range(k_lo, k_hi) * V + rng->randi_range(0, V - 1);
					if (deposit[(size_t)idx] < 0) {
						start = idx;
						break;
					}
				}
				if (start < 0) {
					continue;
				}

				Ref<PlanetCoreDeposit> d;
				d.instantiate();
				d->set_id((int32_t)deposits.size());
				d->set_material_index(mi);
				d->set_shell((int32_t)s);
				deposits.push_back(d);

				const int32_t target = rng->randi_range(ore->get_size_min(), ore->get_size_max());
				std::vector<int32_t> frontier;
				frontier.push_back(start);
				deposit[(size_t)start] = d->get_id();
				// Grow from a random frontier cell each step -> blobby, not spherical.
				while (!frontier.empty() && (int32_t)d->cells.size() < target) {
					const int32_t pick = rng->randi_range(0, (int32_t)frontier.size() - 1);
					const int32_t idx = frontier[(size_t)pick];
					frontier[(size_t)pick] = frontier[frontier.size() - 1];
					frontier.pop_back();
					d->cells.push_back(idx);
					material[(size_t)idx] = (uint8_t)mi;
					const int32_t k = idx / V;
					const int32_t v = idx - k * V;
					if (k > k_lo && deposit[(size_t)(idx - V)] < 0) {
						deposit[(size_t)(idx - V)] = d->get_id();
						frontier.push_back(idx - V);
					}
					if (k < k_hi && deposit[(size_t)(idx + V)] < 0) {
						deposit[(size_t)(idx + V)] = d->get_id();
						frontier.push_back(idx + V);
					}
					for (int32_t j = offs[(size_t)v]; j < offs[(size_t)v + 1]; j++) {
						const int32_t nb = k * V + adj[(size_t)j];
						if (deposit[(size_t)nb] < 0) {
							deposit[(size_t)nb] = d->get_id();
							frontier.push_back(nb);
						}
					}
				}
				// Frontier cells that never made it into the deposit go back to plain terrain.
				for (size_t fi = 0; fi < frontier.size(); fi++) {
					deposit[(size_t)frontier[fi]] = -1;
				}
			}
		}
	}
}
