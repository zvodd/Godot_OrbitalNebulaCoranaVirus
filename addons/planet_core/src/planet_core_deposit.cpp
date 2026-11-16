#include "planet_core_deposit.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void PlanetCoreDeposit::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_id", "id"), &PlanetCoreDeposit::set_id);
	ClassDB::bind_method(D_METHOD("get_id"), &PlanetCoreDeposit::get_id);
	ClassDB::bind_method(D_METHOD("set_material_index", "index"), &PlanetCoreDeposit::set_material_index);
	ClassDB::bind_method(D_METHOD("get_material_index"), &PlanetCoreDeposit::get_material_index);
	ClassDB::bind_method(D_METHOD("set_shell", "shell"), &PlanetCoreDeposit::set_shell);
	ClassDB::bind_method(D_METHOD("get_shell"), &PlanetCoreDeposit::get_shell);
	ClassDB::bind_method(D_METHOD("set_cells", "cells"), &PlanetCoreDeposit::set_cells);
	ClassDB::bind_method(D_METHOD("get_cells"), &PlanetCoreDeposit::get_cells);
	ClassDB::bind_method(D_METHOD("get_cell_count"), &PlanetCoreDeposit::get_cell_count);
	ClassDB::bind_method(D_METHOD("set_exposed", "exposed"), &PlanetCoreDeposit::set_exposed);
	ClassDB::bind_method(D_METHOD("get_exposed"), &PlanetCoreDeposit::get_exposed);
	ClassDB::bind_method(D_METHOD("set_accum", "accum"), &PlanetCoreDeposit::set_accum);
	ClassDB::bind_method(D_METHOD("get_accum"), &PlanetCoreDeposit::get_accum);
	ClassDB::bind_method(D_METHOD("set_mined", "mined"), &PlanetCoreDeposit::set_mined);
	ClassDB::bind_method(D_METHOD("get_mined"), &PlanetCoreDeposit::get_mined);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "id"), "set_id", "get_id");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "material_index"), "set_material_index", "get_material_index");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "shell"), "set_shell", "get_shell");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "cells"), "set_cells", "get_cells");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "exposed"), "set_exposed", "get_exposed");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "accum"), "set_accum", "get_accum");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "mined"), "set_mined", "get_mined");
}

void PlanetCoreDeposit::set_cells(const PackedInt32Array &p_cells) {
	cells.resize((size_t)p_cells.size());
	for (int64_t i = 0; i < p_cells.size(); i++) {
		cells[(size_t)i] = p_cells[i];
	}
}

PackedInt32Array PlanetCoreDeposit::get_cells() const {
	PackedInt32Array out;
	out.resize((int64_t)cells.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < cells.size(); i++) {
		w[i] = cells[i];
	}
	return out;
}
