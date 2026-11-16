#ifndef PLANET_CORE_DEPOSIT_H
#define PLANET_CORE_DEPOSIT_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <vector>

namespace godot {

/**
 * C++ port of `game/planet/deposit.gd`: a connected blob of ore cells plus its runtime state.
 * `occupied_by` (a crawler node) stays on the GDScript side — this class is pure data.
 */
class PlanetCoreDeposit : public RefCounted {
	GDCLASS(PlanetCoreDeposit, RefCounted)

public:
	int32_t id = -1;
	int32_t material_index = 0;
	int32_t shell = 0;
	std::vector<int32_t> cells;
	bool exposed = false;
	/** Cut volume not yet turned into an ore chunk. */
	double accum = 0.0;
	/** Total volume cut out of this deposit. */
	double mined = 0.0;

protected:
	static void _bind_methods();

public:
	void set_id(int32_t p_id) { id = p_id; }
	int32_t get_id() const { return id; }
	void set_material_index(int32_t p_index) { material_index = p_index; }
	int32_t get_material_index() const { return material_index; }
	void set_shell(int32_t p_shell) { shell = p_shell; }
	int32_t get_shell() const { return shell; }
	void set_cells(const PackedInt32Array &p_cells);
	PackedInt32Array get_cells() const;
	int32_t get_cell_count() const { return (int32_t)cells.size(); }
	void set_exposed(bool p_exposed) { exposed = p_exposed; }
	bool get_exposed() const { return exposed; }
	void set_accum(double p_accum) { accum = p_accum; }
	double get_accum() const { return accum; }
	void set_mined(double p_mined) { mined = p_mined; }
	double get_mined() const { return mined; }
};

} // namespace godot

#endif // PLANET_CORE_DEPOSIT_H
