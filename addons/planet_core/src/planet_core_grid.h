#ifndef PLANET_CORE_GRID_H
#define PLANET_CORE_GRID_H

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

#include "planet_core_config.h"
#include "planet_core_deposit.h"
#include "planet_core_icosphere.h"

namespace godot {

/**
 * C++ port of `game/planet/planet_grid.gd`.
 *
 * Layered-icosphere lattice: fill / material / deposit / corruption per point, shell
 * bookkeeping and spatial queries. Pure data — no nodes.
 *
 * Storage rows: row 0 is the indestructible core, rows 1..K are diggable, the last row is
 * permanent air. Lattice index = row * V + vertex.
 *
 * Numeric note: the GDScript original mixes double scalars with float32 `Vector3` components
 * (`PackedFloat32Array`, `PackedVector3Array`). This port keeps the same split — doubles for
 * accumulators and derived scalars, float32 for anything that lands in a packed array — so the
 * results are bit-identical.
 */
class PlanetCoreGrid : public RefCounted {
	GDCLASS(PlanetCoreGrid, RefCounted)

public:
	static constexpr double ISO = 0.5;
	static constexpr int32_t ROOTED = 255;

private:
	Ref<PlanetCoreConfig> config;
	Ref<PlanetCoreIcosphere> ico;

	int32_t V = 0;
	/** Total storage rows (diggable rows + 2). */
	int32_t rows = 0;
	double dr = 1.0;
	/** Radius of storage row 0 (the core row). */
	double r0 = 0.0;
	int32_t point_count = 0;

	std::vector<float> fill;
	std::vector<uint8_t> material;
	std::vector<int32_t> deposit;
	std::vector<uint8_t> corruption;

	std::vector<Ref<PlanetCoreMaterial>> materials;
	std::vector<Color> mat_colors;
	std::vector<Ref<PlanetCoreDeposit>> deposits;

	// Shell 0 is the crust; -1 for the core and air rows.
	std::vector<int32_t> shell_of_row;
	std::vector<int32_t> shell_top_row;
	std::vector<int32_t> shell_bottom_row;
	std::vector<double> shell_initial_solid;
	std::vector<double> shell_removed;
	int32_t outermost_intact_shell = 0;

	// Dirty tracking: insertion-ordered list + O(1) membership flags.
	std::vector<int32_t> dirty_order;
	std::vector<uint8_t> dirty_flag;

	std::vector<Vector2i> pending_ore;
	std::vector<int32_t> newly_exposed;

	// Gradient cache is logically part of the read path, so it stays mutable behind const.
	mutable std::vector<Vector3> grad;
	mutable std::vector<uint8_t> grad_ok;
	double lat_scale = 0.0;

	void _build_material_table();
	void _build_shells();
	void _on_opened(int32_t idx, int32_t v, int32_t k);
	void _expose(int32_t idx);

protected:
	static void _bind_methods();

public:
	PlanetCoreGrid();
	virtual ~PlanetCoreGrid() = default;

	/**
	 * Allocate from a plain-data config. Pass an existing icosphere to share the lattice
	 * (the GDScript Planet node caches one); null builds a fresh one.
	 */
	void setup(const Ref<PlanetCoreConfig> &p_config, const Ref<PlanetCoreIcosphere> &p_ico = Ref<PlanetCoreIcosphere>());

	Ref<PlanetCoreConfig> get_config() const { return config; }
	Ref<PlanetCoreIcosphere> get_ico() const { return ico; }
	// C++-side references for hot paths (not bound to GDScript).
	const Ref<PlanetCoreConfig> &config_ref() const { return config; }
	const Ref<PlanetCoreIcosphere> &ico_ref() const { return ico; }

	int32_t get_V() const { return V; }
	int32_t get_rows() const { return rows; }
	double get_dr() const { return dr; }
	double get_r0() const { return r0; }
	int32_t get_point_count() const { return point_count; }

	// --- packed-array accessors (GDScript-facing, same names where practical) ---

	PackedFloat32Array get_fill() const;
	void set_fill(const PackedFloat32Array &p_fill);
	PackedByteArray get_material() const;
	void set_material(const PackedByteArray &p_material);
	PackedInt32Array get_deposit() const;
	void set_deposit(const PackedInt32Array &p_deposit);
	PackedByteArray get_corruption() const;
	void set_corruption(const PackedByteArray &p_corruption);
	PackedColorArray get_mat_colors() const;
	PackedInt32Array get_shell_of_row() const;
	PackedInt32Array get_shell_top_row() const;
	PackedInt32Array get_shell_bottom_row() const;
	PackedFloat64Array get_shell_initial_solid() const;
	PackedFloat64Array get_shell_removed() const;
	Array get_deposits() const;
	Array get_materials() const;
	PackedInt32Array get_dirty_patches() const;
	TypedArray<Vector2i> get_pending_ore() const;
	PackedInt32Array get_newly_exposed() const;

	int32_t get_outermost_intact_shell() const { return outermost_intact_shell; }
	void set_outermost_intact_shell(int32_t p_shell) { outermost_intact_shell = p_shell; }

	// --- indexed cell accessors --------------------------------------------
	//
	// The `get_*()` array getters above copy the whole lattice (~1 MB at L=5). Anything that
	// touches cells inside a loop must use these instead, or every access becomes O(V*rows).
	// Each one is a single bounds-checked load/store.

	double fill_at(int32_t idx) const;
	void set_fill_at(int32_t idx, double value);
	/** fill_at(idx) >= ISO, so callers do not re-implement the threshold. */
	bool is_solid_at(int32_t idx) const;
	int32_t material_at(int32_t idx) const;
	void set_material_at(int32_t idx, int32_t value);
	int32_t deposit_at(int32_t idx) const;
	void set_deposit_at(int32_t idx, int32_t value);
	int32_t corruption_at(int32_t idx) const;
	void set_corruption_at(int32_t idx, int32_t value);

	// Scalar/row-table accessors: same reasoning, these must not copy the whole table either.
	double shell_removed_at(int32_t shell) const;
	double shell_initial_solid_at(int32_t shell) const;
	int32_t shell_count() const { return (int32_t)shell_top_row.size(); }
	String shell_name(int32_t shell) const;
	Color mat_color_at(int32_t material) const;
	int32_t material_count() const { return (int32_t)materials.size(); }
	Ref<PlanetCoreMaterial> material_at_index(int32_t index) const;

	int32_t deposit_count() const { return (int32_t)deposits.size(); }
	Ref<PlanetCoreDeposit> deposit_at_index(int32_t index) const;
	/** Append an empty deposit (used when a script paints ore into the lattice). */
	int32_t add_deposit(int32_t material_index, int32_t shell);

	// Dirty queue without allocating an Array/Dictionary per call.
	int32_t dirty_patch_at(int32_t i) const;
	bool clear_dirty_patch(int32_t patch);

	// Deferred ore drops / exposure notifications, read by the Planet node each frame.
	int32_t pending_ore_count() const { return (int32_t)pending_ore.size(); }
	int32_t pending_ore_material(int32_t i) const;
	int32_t pending_ore_index(int32_t i) const;
	void clear_pending_ore() { pending_ore.clear(); }
	int32_t newly_exposed_count() const { return (int32_t)newly_exposed.size(); }
	int32_t newly_exposed_at(int32_t i) const;
	void clear_newly_exposed() { newly_exposed.clear(); }

	/**
	 * Index of an air neighbour of `idx` (row above first, then lateral), or -1.
	 * Port of `Planet._ore_spawn_pos`'s neighbour search, so callers need no adjacency arrays.
	 */
	int32_t first_open_neighbour(int32_t idx) const;

	// --- C++-side views for the hot loops ---
	const std::vector<float> &fill_ref() const { return fill; }
	std::vector<float> &fill_ref() { return fill; }
	const std::vector<uint8_t> &material_ref() const { return material; }
	std::vector<uint8_t> &material_ref() { return material; }
	const std::vector<int32_t> &deposit_ref() const { return deposit; }
	std::vector<int32_t> &deposit_ref() { return deposit; }
	const std::vector<uint8_t> &corruption_ref() const { return corruption; }
	const std::vector<Color> &mat_colors_ref() const { return mat_colors; }
	const std::vector<Ref<PlanetCoreMaterial>> &materials_ref() const { return materials; }
	std::vector<Ref<PlanetCoreDeposit>> &deposits_ref() { return deposits; }
	const std::vector<Ref<PlanetCoreDeposit>> &deposits_ref() const { return deposits; }
	std::vector<double> &shell_removed_ref() { return shell_removed; }
	std::vector<int32_t> &shell_of_row_ref() { return shell_of_row; }
	const std::vector<int32_t> &shell_of_row_ref() const { return shell_of_row; }
	const std::vector<int32_t> &shell_top_row_ref() const { return shell_top_row; }
	const std::vector<int32_t> &shell_bottom_row_ref() const { return shell_bottom_row; }
	std::vector<Vector2i> &pending_ore_ref() { return pending_ore; }
	std::vector<int32_t> &newly_exposed_ref() { return newly_exposed; }
	std::vector<int32_t> &dirty_order_ref() { return dirty_order; }

	// --- layout ---

	double row_radius(int32_t k) const { return r0 + k * dr; }
	Vector3 lattice_pos(int32_t idx) const;
	int64_t world_to_lattice(const Vector3 &p) const;
	double shell_top_radius(int32_t shell) const;
	double surface_radius() const;
	double core_surface_radius() const { return r0 + 0.5 * dr; }
	double cleared_fraction(int32_t shell) const;
	bool is_diggable_row(int32_t k) const { return k > 0 && k < rows - 1; }

	// --- queries ---

	PackedInt32Array points_in_sphere(const Vector3 &p, double radius) const;
	void points_in_sphere_into(const Vector3 &p, double radius, std::vector<int32_t> &out) const;
	bool is_solid(int32_t idx) const { return fill[(size_t)idx] >= (float)ISO; }
	bool is_exposed(int32_t idx) const;
	bool is_cuttable(int32_t idx) const;
	/** Gradient of fill (points from air toward solid), cached. The mesher negates it. */
	Vector3 gradient(int32_t idx) const;

	// --- mutation ---

	double erode(int32_t idx, double amount);
	void touch(int32_t idx);
	double carve_sphere(const Vector3 &p, double radius);
	void mark_all_dirty();
	void clear_dirty();
	void refresh_exposure();
	int32_t dirty_count() const { return (int32_t)dirty_order.size(); }
};

} // namespace godot

#endif // PLANET_CORE_GRID_H
