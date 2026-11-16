#include "planet_core_grid.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
// GDScript's `clampi` / `roundi` / `ceili` / `floori`, spelled out so the ports are literal.
inline int32_t clamp_i(int64_t v, int32_t lo, int32_t hi) {
	return (int32_t)(v < lo ? lo : (v > hi ? hi : v));
}
// roundi(): round half away from zero, like the engine.
inline int32_t round_i(double v) {
	return (int32_t)(v >= 0.0 ? std::floor(v + 0.5) : std::ceil(v - 0.5));
}
inline int32_t ceil_i(double v) { return (int32_t)std::ceil(v); }
inline int32_t floor_i(double v) { return (int32_t)std::floor(v); }
} // namespace

void PlanetCoreGrid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "config", "ico"), &PlanetCoreGrid::setup, DEFVAL(Ref<PlanetCoreIcosphere>()));
	ClassDB::bind_method(D_METHOD("get_config"), &PlanetCoreGrid::get_config);
	ClassDB::bind_method(D_METHOD("get_ico"), &PlanetCoreGrid::get_ico);
	ClassDB::bind_method(D_METHOD("get_V"), &PlanetCoreGrid::get_V);
	ClassDB::bind_method(D_METHOD("get_rows"), &PlanetCoreGrid::get_rows);
	ClassDB::bind_method(D_METHOD("get_dr"), &PlanetCoreGrid::get_dr);
	ClassDB::bind_method(D_METHOD("get_r0"), &PlanetCoreGrid::get_r0);
	ClassDB::bind_method(D_METHOD("get_point_count"), &PlanetCoreGrid::get_point_count);
	ClassDB::bind_method(D_METHOD("get_fill"), &PlanetCoreGrid::get_fill);
	ClassDB::bind_method(D_METHOD("set_fill", "fill"), &PlanetCoreGrid::set_fill);
	ClassDB::bind_method(D_METHOD("get_material"), &PlanetCoreGrid::get_material);
	ClassDB::bind_method(D_METHOD("set_material", "material"), &PlanetCoreGrid::set_material);
	ClassDB::bind_method(D_METHOD("get_deposit"), &PlanetCoreGrid::get_deposit);
	ClassDB::bind_method(D_METHOD("set_deposit", "deposit"), &PlanetCoreGrid::set_deposit);
	ClassDB::bind_method(D_METHOD("get_corruption"), &PlanetCoreGrid::get_corruption);
	ClassDB::bind_method(D_METHOD("set_corruption", "corruption"), &PlanetCoreGrid::set_corruption);
	ClassDB::bind_method(D_METHOD("get_mat_colors"), &PlanetCoreGrid::get_mat_colors);
	ClassDB::bind_method(D_METHOD("get_shell_of_row"), &PlanetCoreGrid::get_shell_of_row);
	ClassDB::bind_method(D_METHOD("get_shell_top_row"), &PlanetCoreGrid::get_shell_top_row);
	ClassDB::bind_method(D_METHOD("get_shell_bottom_row"), &PlanetCoreGrid::get_shell_bottom_row);
	ClassDB::bind_method(D_METHOD("get_shell_initial_solid"), &PlanetCoreGrid::get_shell_initial_solid);
	ClassDB::bind_method(D_METHOD("get_shell_removed"), &PlanetCoreGrid::get_shell_removed);
	ClassDB::bind_method(D_METHOD("get_deposits"), &PlanetCoreGrid::get_deposits);
	ClassDB::bind_method(D_METHOD("get_materials"), &PlanetCoreGrid::get_materials);
	ClassDB::bind_method(D_METHOD("get_dirty_patches"), &PlanetCoreGrid::get_dirty_patches);
	ClassDB::bind_method(D_METHOD("get_pending_ore"), &PlanetCoreGrid::get_pending_ore);
	ClassDB::bind_method(D_METHOD("get_newly_exposed"), &PlanetCoreGrid::get_newly_exposed);
	ClassDB::bind_method(D_METHOD("get_outermost_intact_shell"), &PlanetCoreGrid::get_outermost_intact_shell);
	ClassDB::bind_method(D_METHOD("set_outermost_intact_shell", "shell"), &PlanetCoreGrid::set_outermost_intact_shell);

	// Indexed accessors: single-cell reads/writes, no whole-array copy.
	ClassDB::bind_method(D_METHOD("fill_at", "idx"), &PlanetCoreGrid::fill_at);
	ClassDB::bind_method(D_METHOD("set_fill_at", "idx", "value"), &PlanetCoreGrid::set_fill_at);
	ClassDB::bind_method(D_METHOD("is_solid_at", "idx"), &PlanetCoreGrid::is_solid_at);
	ClassDB::bind_method(D_METHOD("material_at", "idx"), &PlanetCoreGrid::material_at);
	ClassDB::bind_method(D_METHOD("set_material_at", "idx", "value"), &PlanetCoreGrid::set_material_at);
	ClassDB::bind_method(D_METHOD("deposit_at", "idx"), &PlanetCoreGrid::deposit_at);
	ClassDB::bind_method(D_METHOD("set_deposit_at", "idx", "value"), &PlanetCoreGrid::set_deposit_at);
	ClassDB::bind_method(D_METHOD("corruption_at", "idx"), &PlanetCoreGrid::corruption_at);
	ClassDB::bind_method(D_METHOD("set_corruption_at", "idx", "value"), &PlanetCoreGrid::set_corruption_at);
	ClassDB::bind_method(D_METHOD("shell_removed_at", "shell"), &PlanetCoreGrid::shell_removed_at);
	ClassDB::bind_method(D_METHOD("shell_initial_solid_at", "shell"), &PlanetCoreGrid::shell_initial_solid_at);
	ClassDB::bind_method(D_METHOD("shell_count"), &PlanetCoreGrid::shell_count);
	ClassDB::bind_method(D_METHOD("shell_name", "shell"), &PlanetCoreGrid::shell_name);
	ClassDB::bind_method(D_METHOD("mat_color_at", "material"), &PlanetCoreGrid::mat_color_at);
	ClassDB::bind_method(D_METHOD("material_count"), &PlanetCoreGrid::material_count);
	ClassDB::bind_method(D_METHOD("material_at_index", "index"), &PlanetCoreGrid::material_at_index);
	ClassDB::bind_method(D_METHOD("deposit_count"), &PlanetCoreGrid::deposit_count);
	ClassDB::bind_method(D_METHOD("deposit_at_index", "index"), &PlanetCoreGrid::deposit_at_index);
	ClassDB::bind_method(D_METHOD("add_deposit", "material_index", "shell"), &PlanetCoreGrid::add_deposit);
	ClassDB::bind_method(D_METHOD("dirty_patch_at", "i"), &PlanetCoreGrid::dirty_patch_at);
	ClassDB::bind_method(D_METHOD("clear_dirty_patch", "patch"), &PlanetCoreGrid::clear_dirty_patch);
	ClassDB::bind_method(D_METHOD("pending_ore_count"), &PlanetCoreGrid::pending_ore_count);
	ClassDB::bind_method(D_METHOD("pending_ore_material", "i"), &PlanetCoreGrid::pending_ore_material);
	ClassDB::bind_method(D_METHOD("pending_ore_index", "i"), &PlanetCoreGrid::pending_ore_index);
	ClassDB::bind_method(D_METHOD("clear_pending_ore"), &PlanetCoreGrid::clear_pending_ore);
	ClassDB::bind_method(D_METHOD("newly_exposed_count"), &PlanetCoreGrid::newly_exposed_count);
	ClassDB::bind_method(D_METHOD("newly_exposed_at", "i"), &PlanetCoreGrid::newly_exposed_at);
	ClassDB::bind_method(D_METHOD("clear_newly_exposed"), &PlanetCoreGrid::clear_newly_exposed);
	ClassDB::bind_method(D_METHOD("first_open_neighbour", "idx"), &PlanetCoreGrid::first_open_neighbour);
	ClassDB::bind_method(D_METHOD("row_radius", "k"), &PlanetCoreGrid::row_radius);
	ClassDB::bind_method(D_METHOD("lattice_pos", "idx"), &PlanetCoreGrid::lattice_pos);
	ClassDB::bind_method(D_METHOD("world_to_lattice", "p"), &PlanetCoreGrid::world_to_lattice);
	ClassDB::bind_method(D_METHOD("shell_top_radius", "shell"), &PlanetCoreGrid::shell_top_radius);
	ClassDB::bind_method(D_METHOD("surface_radius"), &PlanetCoreGrid::surface_radius);
	ClassDB::bind_method(D_METHOD("core_surface_radius"), &PlanetCoreGrid::core_surface_radius);
	ClassDB::bind_method(D_METHOD("cleared_fraction", "shell"), &PlanetCoreGrid::cleared_fraction);
	ClassDB::bind_method(D_METHOD("is_diggable_row", "k"), &PlanetCoreGrid::is_diggable_row);
	ClassDB::bind_method(D_METHOD("points_in_sphere", "p", "radius"), &PlanetCoreGrid::points_in_sphere);
	ClassDB::bind_method(D_METHOD("is_solid", "idx"), &PlanetCoreGrid::is_solid);
	ClassDB::bind_method(D_METHOD("is_exposed", "idx"), &PlanetCoreGrid::is_exposed);
	ClassDB::bind_method(D_METHOD("is_cuttable", "idx"), &PlanetCoreGrid::is_cuttable);
	ClassDB::bind_method(D_METHOD("gradient", "idx"), &PlanetCoreGrid::gradient);
	ClassDB::bind_method(D_METHOD("erode", "idx", "amount"), &PlanetCoreGrid::erode);
	ClassDB::bind_method(D_METHOD("touch", "idx"), &PlanetCoreGrid::touch);
	ClassDB::bind_method(D_METHOD("carve_sphere", "p", "radius"), &PlanetCoreGrid::carve_sphere);
	ClassDB::bind_method(D_METHOD("mark_all_dirty"), &PlanetCoreGrid::mark_all_dirty);
	ClassDB::bind_method(D_METHOD("clear_dirty"), &PlanetCoreGrid::clear_dirty);
	ClassDB::bind_method(D_METHOD("refresh_exposure"), &PlanetCoreGrid::refresh_exposure);
	ClassDB::bind_method(D_METHOD("dirty_count"), &PlanetCoreGrid::dirty_count);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "outermost_intact_shell"), "set_outermost_intact_shell", "get_outermost_intact_shell");
}

PlanetCoreGrid::PlanetCoreGrid() = default;

void PlanetCoreGrid::setup(const Ref<PlanetCoreConfig> &p_config, const Ref<PlanetCoreIcosphere> &p_ico) {
	config = p_config;
	ERR_FAIL_COND_MSG(config.is_null(), "PlanetCoreGrid.setup: config is null.");

	if (p_ico.is_valid()) {
		ico = p_ico;
	} else {
		ico = PlanetCoreIcosphere::create(config->get_subdivision(), config->get_patch_level());
	}

	V = ico->get_vertex_count();
	dr = config->get_row_spacing();
	rows = config->diggable_rows() + 2;
	r0 = config->get_core_radius() - dr;
	point_count = rows * V;
	const double mean_edge = ico->get_mean_edge();
	lat_scale = 2.0 / (mean_edge * mean_edge);

	fill.assign((size_t)point_count, 0.0f);
	material.assign((size_t)point_count, 0);
	deposit.assign((size_t)point_count, -1);
	corruption.assign((size_t)point_count, 0);
	grad.assign((size_t)point_count, Vector3());
	grad_ok.assign((size_t)point_count, 0);

	dirty_order.clear();
	dirty_flag.assign((size_t)ico->get_patch_count(), 0);
	pending_ore.clear();
	newly_exposed.clear();
	deposits.clear();

	_build_material_table();
	_build_shells();
}

void PlanetCoreGrid::_build_material_table() {
	materials.clear();
	mat_colors.clear();

	Array mats = config->get_materials();
	for (int64_t i = 0; i < mats.size(); i++) {
		Ref<PlanetCoreMaterial> m = mats[i];
		if (m.is_valid()) {
			materials.push_back(m);
			mat_colors.push_back(m->get_color());
		}
	}
	ERR_FAIL_COND_MSG(materials.empty(), "PlanetCoreGrid: config has no materials.");
}

void PlanetCoreGrid::_build_shells() {
	Array shells = config->get_shells();
	const int32_t n = (int32_t)shells.size();
	shell_of_row.assign((size_t)rows, -1);
	shell_top_row.assign((size_t)n, 0);
	shell_bottom_row.assign((size_t)n, 0);
	shell_initial_solid.assign((size_t)n, 0.0);
	shell_removed.assign((size_t)n, 0.0);

	int32_t top = rows - 2;
	for (int32_t s = 0; s < n; s++) {
		Ref<PlanetCoreShell> shell = shells[s];
		const int32_t sr = shell.is_valid() ? shell->get_rows() : 0;
		shell_top_row[(size_t)s] = top;
		shell_bottom_row[(size_t)s] = top - sr + 1;
		for (int32_t k = top - sr + 1; k <= top; k++) {
			if (k >= 0 && k < rows) {
				shell_of_row[(size_t)k] = s;
			}
		}
		shell_initial_solid[(size_t)s] = (double)(sr * V);
		shell_removed[(size_t)s] = 0.0;
		top -= sr;
	}
	outermost_intact_shell = 0;
}

// --- layout -----------------------------------------------------------------

Vector3 PlanetCoreGrid::lattice_pos(int32_t idx) const {
	const int32_t k = idx / V;
	// ico->verts are float32 and the radius is a GDScript float (double), narrowed on multiply.
	const real_t r = (real_t)(r0 + (double)k * dr);
	return ico->verts_ref()[(size_t)(idx - k * V)] * r;
}

int64_t PlanetCoreGrid::world_to_lattice(const Vector3 &p) const {
	const int64_t v = ico->nearest_vertex(p);
	// p.length() is float32; the double arithmetic after it stays double, like GDScript.
	const int32_t k = clamp_i(round_i(((double)p.length() - r0) / dr), 0, rows - 1);
	return (int64_t)k * V + v;
}

double PlanetCoreGrid::shell_top_radius(int32_t shell) const {
	const int32_t s = shell >= 0 && shell < (int32_t)shell_top_row.size() ? shell : 0;
	return row_radius(shell_top_row[(size_t)s]) + 0.5 * dr;
}

double PlanetCoreGrid::surface_radius() const {
	const int32_t last = (int32_t)shell_top_row.size() - 1;
	const int32_t s = outermost_intact_shell < last ? outermost_intact_shell : last;
	return shell_top_radius(s);
}

double PlanetCoreGrid::cleared_fraction(int32_t shell) const {
	const double initial = shell_initial_solid[(size_t)shell];
	return shell_removed[(size_t)shell] / (initial > 1.0 ? initial : 1.0);
}

// --- queries ----------------------------------------------------------------

void PlanetCoreGrid::points_in_sphere_into(const Vector3 &p, double radius, std::vector<int32_t> &out) const {
	out.clear();
	// GDScript's Vector3.length() is float32; the double arithmetic on it stays double.
	const double plen = (double)p.length();
	if (plen < 0.0001) {
		return;
	}
	const int32_t k_lo = std::max(ceil_i((plen - radius - r0) / dr), 0);
	const int32_t k_hi = std::min(floor_i((plen + radius - r0) / dr), rows - 1);
	if (k_lo > k_hi) {
		return;
	}
	// A column (direction u) can only hold points within R if its ray passes within R of p.
	double s = radius / plen;
	if (s > 1.0) {
		s = 1.0;
	}
	const double cos_min = std::sqrt(1.0 - s * s) * plen;
	const double r2 = radius * radius;

	const std::vector<Vector3> &verts = ico->verts_ref();
	const std::vector<int32_t> &offs = ico->adj_offsets_ref();
	const std::vector<int32_t> &adj = ico->adj_ref();

	const int32_t start = (int32_t)ico->nearest_vertex(p);
	std::vector<int32_t> queue;
	queue.push_back(start);
	std::vector<uint8_t> seen((size_t)V, 0);
	seen[(size_t)start] = 1;
	size_t head = 0;
	while (head < queue.size()) {
		const int32_t n = queue[head];
		head += 1;
		const Vector3 &u = verts[(size_t)n];
		for (int32_t k = k_lo; k <= k_hi; k++) {
			// u * radius is float32 (scalar narrowed), so is distance_squared_to; the
			// comparison against r2 stays double, like GDScript's float-vs-float compare.
			const Vector3 pos = u * (real_t)(r0 + (double)k * dr);
			if ((double)pos.distance_squared_to(p) <= r2) {
				out.push_back(k * V + n);
			}
		}
		for (int32_t j = offs[(size_t)n]; j < offs[(size_t)n + 1]; j++) {
			const int32_t nb = adj[(size_t)j];
			if (!seen[(size_t)nb] && (double)p.dot(verts[(size_t)nb]) >= cos_min) {				seen[(size_t)nb] = 1;
				queue.push_back(nb);
			}
		}
	}
}

PackedInt32Array PlanetCoreGrid::points_in_sphere(const Vector3 &p, double radius) const {
	std::vector<int32_t> out;
	points_in_sphere_into(p, radius, out);
	PackedInt32Array arr;
	arr.resize((int64_t)out.size());
	int32_t *w = arr.ptrw();
	for (size_t i = 0; i < out.size(); i++) {
		w[i] = out[i];
	}
	return arr;
}

bool PlanetCoreGrid::is_exposed(int32_t idx) const {
	if (fill[(size_t)idx] < (float)ISO) {
		return false;
	}
	const int32_t k = idx / V;
	if (k >= rows - 1 || fill[(size_t)(idx + V)] < (float)ISO) {
		return true;
	}
	const int32_t v = idx - k * V;
	const int32_t base = k * V;
	const std::vector<int32_t> &offs = ico->adj_offsets_ref();
	const std::vector<int32_t> &adj = ico->adj_ref();
	for (int32_t j = offs[(size_t)v]; j < offs[(size_t)v + 1]; j++) {
		if (fill[(size_t)(base + adj[(size_t)j])] < (float)ISO) {
			return true;
		}
	}
	return false;
}

bool PlanetCoreGrid::is_cuttable(int32_t idx) const {
	const int32_t k = idx / V;
	if (k <= 0 || k >= rows - 1 || corruption[(size_t)idx] != 0) {
		return false;
	}
	const Ref<PlanetCoreMaterial> &m = materials[(size_t)material[(size_t)idx]];
	return m.is_valid() && m->cuttable();
}

Vector3 PlanetCoreGrid::gradient(int32_t idx) const {
	if (grad_ok[(size_t)idx] != 0) {
		return grad[(size_t)idx];
	}
	const int32_t k = idx / V;
	const int32_t v = idx - k * V;
	const int32_t base = idx - v;
	// GDScript `var f := fill[idx]` is a float; the fill values are float32 in the array.
	const double f = (double)fill[(size_t)idx];
	const double up = k < rows - 1 ? (double)fill[(size_t)(idx + V)] : 0.0;
	const double down = k > 0 ? (double)fill[(size_t)(idx - V)] : 1.0;

	const std::vector<Vector3> &verts = ico->verts_ref();
	const Vector3 &pv = verts[(size_t)v];
	// pv * ((up - down) / (2.0 * dr)): the scalar is double, narrowed to float by operator*.
	const real_t vert = (real_t)((up - down) / (2.0 * dr));
	Vector3 g = pv * vert;

	Vector3 lat;
	const int32_t s = ico->adj_offsets_ref()[(size_t)v];
	const int32_t e = ico->adj_offsets_ref()[(size_t)v + 1];
	const std::vector<int32_t> &adj = ico->adj_ref();
	for (int32_t j = s; j < e; j++) {
		const int32_t n = adj[(size_t)j];
		const Vector3 diff = verts[(size_t)n] - pv;              // float32 subtraction
		const real_t dfill = (real_t)((double)fill[(size_t)(base + n)] - f); // double, narrowed
		lat += diff * dfill;
	}
	const double radius = r0 + (double)k * dr;
	const double denom = (double)(e - s) * (radius > 0.001 ? radius : 0.001);
	// g += lat * (_lat_scale / denom); scalar narrowed to float32 on multiply.
	g += lat * (real_t)(lat_scale / denom);

	grad[(size_t)idx] = g;
	grad_ok[(size_t)idx] = 1;
	return g;
}

// --- mutation ---------------------------------------------------------------

double PlanetCoreGrid::erode(int32_t idx, double amount) {
	const int32_t k = idx / V;
	if (k <= 0 || k >= rows - 1) {
		return 0.0;
	}
	const double f = (double)fill[(size_t)idx];
	if (f <= 0.0 || amount <= 0.0) {
		return 0.0;
	}
	double d = f < amount ? f : amount;
	double nf = f - d;
	if (nf < 0.002) {
		d = f;
		nf = 0.0;
	}
	fill[(size_t)idx] = (float)nf;

	const int32_t shell = shell_of_row[(size_t)k];
	if (shell >= 0) {
		shell_removed[(size_t)shell] += d;
	}

	const int32_t dep = deposit[(size_t)idx];
	if (dep >= 0 && dep < (int32_t)deposits.size()) {
		const int32_t mi = material[(size_t)idx];
		const Ref<PlanetCoreMaterial> &m = materials[(size_t)mi];
		if (m.is_valid() && m->is_ore()) {
			Ref<PlanetCoreDeposit> dd = deposits[(size_t)dep];
			if (dd.is_valid()) {
				const double chunk_volume = m->get_chunk_volume();
				dd->set_accum(dd->get_accum() + d);
				dd->set_mined(dd->get_mined() + d);
				while (dd->get_accum() >= chunk_volume) {
					dd->set_accum(dd->get_accum() - chunk_volume);
					pending_ore.push_back(Vector2i(mi, idx));
				}
			}
		}
	}

	const int32_t v = idx - k * V;
	touch(idx);
	if (f >= ISO && nf < ISO) {
		_on_opened(idx, v, k);
	}
	return d;
}

void PlanetCoreGrid::touch(int32_t idx) {
	const int32_t k = idx / V;
	const int32_t v = idx - k * V;
	const int32_t base = idx - v;
	grad_ok[(size_t)idx] = 0;
	if (k > 0) {
		grad_ok[(size_t)(idx - V)] = 0;
	}
	if (k < rows - 1) {
		grad_ok[(size_t)(idx + V)] = 0;
	}
	const std::vector<int32_t> &adj = ico->adj_ref();
	const std::vector<int32_t> &offs = ico->adj_offsets_ref();
	for (int32_t j = offs[(size_t)v]; j < offs[(size_t)v + 1]; j++) {
		grad_ok[(size_t)(base + adj[(size_t)j])] = 0;
	}
	const std::vector<int32_t> &dp = ico->dirty_patches_ref();
	const std::vector<int32_t> &doffs = ico->dirty_offsets_ref();
	for (int32_t j = doffs[(size_t)v]; j < doffs[(size_t)v + 1]; j++) {
		const int32_t p = dp[(size_t)j];
		if (p >= 0 && p < (int32_t)dirty_flag.size() && dirty_flag[(size_t)p] == 0) {
			dirty_flag[(size_t)p] = 1;
			dirty_order.push_back(p);
		}
	}
}

double PlanetCoreGrid::carve_sphere(const Vector3 &p, double radius) {
	double total = 0.0;
	const size_t drops = pending_ore.size();
	std::vector<int32_t> hits;
	points_in_sphere_into(p, radius, hits);
	for (size_t i = 0; i < hits.size(); i++) {
		total += erode(hits[i], 1.0);
	}
	pending_ore.resize(drops);
	return total;
}

void PlanetCoreGrid::mark_all_dirty() {
	for (int32_t p = 0; p < ico->get_patch_count(); p++) {
		if (p < (int32_t)dirty_flag.size() && dirty_flag[(size_t)p] == 0) {
			dirty_flag[(size_t)p] = 1;
			dirty_order.push_back(p);
		}
	}
	std::fill(grad_ok.begin(), grad_ok.end(), (uint8_t)0);
}

void PlanetCoreGrid::clear_dirty() {
	dirty_order.clear();
	std::fill(dirty_flag.begin(), dirty_flag.end(), (uint8_t)0);
}

void PlanetCoreGrid::refresh_exposure() {
	for (size_t i = 0; i < deposits.size(); i++) {
		Ref<PlanetCoreDeposit> d = deposits[i];
		if (d.is_null()) {
			continue;
		}
		d->set_exposed(false);
		const std::vector<int32_t> &cells = d->cells;
		for (size_t c = 0; c < cells.size(); c++) {
			if (is_exposed(cells[c])) {
				d->set_exposed(true);
				break;
			}
		}
	}
}

void PlanetCoreGrid::_on_opened(int32_t idx, int32_t v, int32_t k) {
	// A cell just became air: any solid deposit cell next to it is now exposed.
	_expose(idx - V);
	if (k < rows - 1) {
		_expose(idx + V);
	}
	const int32_t base = idx - v;
	const std::vector<int32_t> &adj = ico->adj_ref();
	const std::vector<int32_t> &offs = ico->adj_offsets_ref();
	for (int32_t j = offs[(size_t)v]; j < offs[(size_t)v + 1]; j++) {
		_expose(base + adj[(size_t)j]);
	}
}

void PlanetCoreGrid::_expose(int32_t idx) {
	if (idx < 0 || idx >= point_count) {
		return;
	}
	const int32_t dep = deposit[(size_t)idx];
	if (dep >= 0 && dep < (int32_t)deposits.size() && fill[(size_t)idx] >= (float)ISO) {
		Ref<PlanetCoreDeposit> dd = deposits[(size_t)dep];
		if (dd.is_valid() && !dd->get_exposed()) {
			dd->set_exposed(true);
			newly_exposed.push_back(dep);
		}
	}
}

// --- indexed cell accessors -------------------------------------------------
//
// These exist because `get_fill()[idx]` copies ~1 MB per call: the carve path touches a cell
// several times per tick inside loops, so the copy made it O(n^2) and ate the whole speed-up.
// Each accessor is one array load plus a bounds check.

double PlanetCoreGrid::fill_at(int32_t idx) const {
	if (idx < 0 || idx >= point_count) {
		return 0.0;
	}
	return (double)fill[(size_t)idx];
}

void PlanetCoreGrid::set_fill_at(int32_t idx, double value) {
	if (idx < 0 || idx >= point_count) {
		return;
	}
	// Narrowed to float32 like every other write into the packed fill array.
	fill[(size_t)idx] = (float)value;
}

bool PlanetCoreGrid::is_solid_at(int32_t idx) const {
	if (idx < 0 || idx >= point_count) {
		return false;
	}
	return fill[(size_t)idx] >= (float)ISO;
}

int32_t PlanetCoreGrid::material_at(int32_t idx) const {
	if (idx < 0 || idx >= point_count) {
		return 0;
	}
	return (int32_t)material[(size_t)idx];
}

void PlanetCoreGrid::set_material_at(int32_t idx, int32_t value) {
	if (idx < 0 || idx >= point_count) {
		return;
	}
	material[(size_t)idx] = (uint8_t)(value & 0xFF);
}

int32_t PlanetCoreGrid::deposit_at(int32_t idx) const {
	if (idx < 0 || idx >= point_count) {
		return -1;
	}
	return deposit[(size_t)idx];
}

void PlanetCoreGrid::set_deposit_at(int32_t idx, int32_t value) {
	if (idx < 0 || idx >= point_count) {
		return;
	}
	deposit[(size_t)idx] = value;
}

int32_t PlanetCoreGrid::corruption_at(int32_t idx) const {
	if (idx < 0 || idx >= point_count) {
		return 0;
	}
	return (int32_t)corruption[(size_t)idx];
}

void PlanetCoreGrid::set_corruption_at(int32_t idx, int32_t value) {
	if (idx < 0 || idx >= point_count) {
		return;
	}
	corruption[(size_t)idx] = (uint8_t)(value & 0xFF);
}

double PlanetCoreGrid::shell_removed_at(int32_t shell) const {
	if (shell < 0 || shell >= (int32_t)shell_removed.size()) {
		return 0.0;
	}
	return shell_removed[(size_t)shell];
}

double PlanetCoreGrid::shell_initial_solid_at(int32_t shell) const {
	if (shell < 0 || shell >= (int32_t)shell_initial_solid.size()) {
		return 0.0;
	}
	return shell_initial_solid[(size_t)shell];
}

String PlanetCoreGrid::shell_name(int32_t shell) const {
	if (config.is_null() || shell < 0 || shell >= config->get_shells().size()) {
		return String();
	}
	Ref<PlanetCoreShell> s = config->get_shells()[shell];
	return s.is_valid() ? s->get_name() : String();
}

Color PlanetCoreGrid::mat_color_at(int32_t material_idx) const {
	if (material_idx < 0 || material_idx >= (int32_t)mat_colors.size()) {
		return Color(1, 1, 1);
	}
	return mat_colors[(size_t)material_idx];
}

Ref<PlanetCoreMaterial> PlanetCoreGrid::material_at_index(int32_t index) const {
	if (index < 0 || index >= (int32_t)materials.size()) {
		return Ref<PlanetCoreMaterial>();
	}
	return materials[(size_t)index];
}

Ref<PlanetCoreDeposit> PlanetCoreGrid::deposit_at_index(int32_t index) const {
	if (index < 0 || index >= (int32_t)deposits.size()) {
		return Ref<PlanetCoreDeposit>();
	}
	return deposits[(size_t)index];
}

int32_t PlanetCoreGrid::add_deposit(int32_t material_index, int32_t shell) {
	Ref<PlanetCoreDeposit> d;
	d.instantiate();
	d->set_id((int32_t)deposits.size());
	d->set_material_index(material_index);
	d->set_shell(shell);
	deposits.push_back(d);
	return d->get_id();
}

int32_t PlanetCoreGrid::dirty_patch_at(int32_t i) const {
	if (i < 0 || i >= (int32_t)dirty_order.size()) {
		return -1;
	}
	return dirty_order[(size_t)i];
}

bool PlanetCoreGrid::clear_dirty_patch(int32_t patch) {
	if (patch < 0 || patch >= (int32_t)dirty_flag.size() || dirty_flag[(size_t)patch] == 0) {
		return false;
	}
	dirty_flag[(size_t)patch] = 0;
	for (size_t i = 0; i < dirty_order.size(); i++) {
		if (dirty_order[i] == patch) {
			// Order-preserving removal: the Planet node walks this list while dropping entries.
			dirty_order.erase(dirty_order.begin() + (ptrdiff_t)i);
			break;
		}
	}
	return true;
}

int32_t PlanetCoreGrid::pending_ore_material(int32_t i) const {
	if (i < 0 || i >= (int32_t)pending_ore.size()) {
		return -1;
	}
	return pending_ore[(size_t)i].x;
}

int32_t PlanetCoreGrid::pending_ore_index(int32_t i) const {
	if (i < 0 || i >= (int32_t)pending_ore.size()) {
		return -1;
	}
	return pending_ore[(size_t)i].y;
}

int32_t PlanetCoreGrid::newly_exposed_at(int32_t i) const {
	if (i < 0 || i >= (int32_t)newly_exposed.size()) {
		return -1;
	}
	return newly_exposed[(size_t)i];
}

int32_t PlanetCoreGrid::first_open_neighbour(int32_t idx) const {
	if (idx < 0 || idx >= point_count) {
		return -1;
	}
	const int32_t k = idx / V;
	if (k < rows - 1 && idx + V < point_count && fill[(size_t)(idx + V)] < (float)ISO) {
		return idx + V;
	}
	const int32_t v = idx - k * V;
	const int32_t base = k * V;
	const std::vector<int32_t> &offs = ico->adj_offsets_ref();
	const std::vector<int32_t> &adj = ico->adj_ref();
	for (int32_t j = offs[(size_t)v]; j < offs[(size_t)v + 1]; j++) {
		const int32_t nb = base + adj[(size_t)j];
		if (fill[(size_t)nb] < (float)ISO) {
			return nb;
		}
	}
	return -1;
}

// --- packed accessors -------------------------------------------------------

PackedFloat32Array PlanetCoreGrid::get_fill() const {
	PackedFloat32Array out;
	out.resize((int64_t)fill.size());
	float *w = out.ptrw();
	for (size_t i = 0; i < fill.size(); i++) {
		w[i] = fill[i];
	}
	return out;
}

void PlanetCoreGrid::set_fill(const PackedFloat32Array &p_fill) {
	ERR_FAIL_COND_MSG(p_fill.size() != (int64_t)fill.size(), "PlanetCoreGrid.fill: size mismatch.");
	const float *r = p_fill.ptr();
	for (size_t i = 0; i < fill.size(); i++) {
		fill[i] = r[i];
	}
}

PackedByteArray PlanetCoreGrid::get_material() const {
	PackedByteArray out;
	out.resize((int64_t)material.size());
	uint8_t *w = out.ptrw();
	for (size_t i = 0; i < material.size(); i++) {
		w[i] = material[i];
	}
	return out;
}

void PlanetCoreGrid::set_material(const PackedByteArray &p_material) {
	ERR_FAIL_COND_MSG(p_material.size() != (int64_t)material.size(), "PlanetCoreGrid.material: size mismatch.");
	const uint8_t *r = p_material.ptr();
	for (size_t i = 0; i < material.size(); i++) {
		material[i] = r[i];
	}
}

PackedInt32Array PlanetCoreGrid::get_deposit() const {
	PackedInt32Array out;
	out.resize((int64_t)deposit.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < deposit.size(); i++) {
		w[i] = deposit[i];
	}
	return out;
}

void PlanetCoreGrid::set_deposit(const PackedInt32Array &p_deposit) {
	ERR_FAIL_COND_MSG(p_deposit.size() != (int64_t)deposit.size(), "PlanetCoreGrid.deposit: size mismatch.");
	const int32_t *r = p_deposit.ptr();
	for (size_t i = 0; i < deposit.size(); i++) {
		deposit[i] = r[i];
	}
}

PackedByteArray PlanetCoreGrid::get_corruption() const {
	PackedByteArray out;
	out.resize((int64_t)corruption.size());
	uint8_t *w = out.ptrw();
	for (size_t i = 0; i < corruption.size(); i++) {
		w[i] = corruption[i];
	}
	return out;
}

void PlanetCoreGrid::set_corruption(const PackedByteArray &p_corruption) {
	ERR_FAIL_COND_MSG(p_corruption.size() != (int64_t)corruption.size(), "PlanetCoreGrid.corruption: size mismatch.");
	const uint8_t *r = p_corruption.ptr();
	for (size_t i = 0; i < corruption.size(); i++) {
		corruption[i] = r[i];
	}
}

PackedColorArray PlanetCoreGrid::get_mat_colors() const {
	PackedColorArray out;
	out.resize((int64_t)mat_colors.size());
	Color *w = out.ptrw();
	for (size_t i = 0; i < mat_colors.size(); i++) {
		w[i] = mat_colors[i];
	}
	return out;
}

PackedInt32Array PlanetCoreGrid::get_shell_of_row() const {
	PackedInt32Array out;
	out.resize((int64_t)shell_of_row.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < shell_of_row.size(); i++) {
		w[i] = shell_of_row[i];
	}
	return out;
}

PackedInt32Array PlanetCoreGrid::get_shell_top_row() const {
	PackedInt32Array out;
	out.resize((int64_t)shell_top_row.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < shell_top_row.size(); i++) {
		w[i] = shell_top_row[i];
	}
	return out;
}

PackedInt32Array PlanetCoreGrid::get_shell_bottom_row() const {
	PackedInt32Array out;
	out.resize((int64_t)shell_bottom_row.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < shell_bottom_row.size(); i++) {
		w[i] = shell_bottom_row[i];
	}
	return out;
}

PackedFloat64Array PlanetCoreGrid::get_shell_initial_solid() const {
	PackedFloat64Array out;
	out.resize((int64_t)shell_initial_solid.size());
	double *w = out.ptrw();
	for (size_t i = 0; i < shell_initial_solid.size(); i++) {
		w[i] = shell_initial_solid[i];
	}
	return out;
}

PackedFloat64Array PlanetCoreGrid::get_shell_removed() const {
	PackedFloat64Array out;
	out.resize((int64_t)shell_removed.size());
	double *w = out.ptrw();
	for (size_t i = 0; i < shell_removed.size(); i++) {
		w[i] = shell_removed[i];
	}
	return out;
}

Array PlanetCoreGrid::get_deposits() const {
	Array out;
	for (size_t i = 0; i < deposits.size(); i++) {
		out.push_back(deposits[i]);
	}
	return out;
}

Array PlanetCoreGrid::get_materials() const {
	Array out;
	for (size_t i = 0; i < materials.size(); i++) {
		out.push_back(materials[i]);
	}
	return out;
}

PackedInt32Array PlanetCoreGrid::get_dirty_patches() const {
	PackedInt32Array out;
	out.resize((int64_t)dirty_order.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < dirty_order.size(); i++) {
		w[i] = dirty_order[i];
	}
	return out;
}

TypedArray<Vector2i> PlanetCoreGrid::get_pending_ore() const {
	TypedArray<Vector2i> out;
	out.resize((int64_t)pending_ore.size());
	for (size_t i = 0; i < pending_ore.size(); i++) {
		out[(int64_t)i] = pending_ore[i];
	}
	return out;
}

PackedInt32Array PlanetCoreGrid::get_newly_exposed() const {
	PackedInt32Array out;
	out.resize((int64_t)newly_exposed.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < newly_exposed.size(); i++) {
		w[i] = newly_exposed[i];
	}
	return out;
}
