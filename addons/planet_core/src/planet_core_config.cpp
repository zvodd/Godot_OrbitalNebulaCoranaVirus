#include "planet_core_config.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;

void PlanetCoreMaterial::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_name", "name"), &PlanetCoreMaterial::set_name);
	ClassDB::bind_method(D_METHOD("get_name"), &PlanetCoreMaterial::get_name);
	ClassDB::bind_method(D_METHOD("set_color", "color"), &PlanetCoreMaterial::set_color);
	ClassDB::bind_method(D_METHOD("get_color"), &PlanetCoreMaterial::get_color);
	ClassDB::bind_method(D_METHOD("set_min_power", "min_power"), &PlanetCoreMaterial::set_min_power);
	ClassDB::bind_method(D_METHOD("get_min_power"), &PlanetCoreMaterial::get_min_power);
	ClassDB::bind_method(D_METHOD("set_hardness", "hardness"), &PlanetCoreMaterial::set_hardness);
	ClassDB::bind_method(D_METHOD("get_hardness"), &PlanetCoreMaterial::get_hardness);
	ClassDB::bind_method(D_METHOD("set_instant_threshold", "instant_threshold"), &PlanetCoreMaterial::set_instant_threshold);
	ClassDB::bind_method(D_METHOD("get_instant_threshold"), &PlanetCoreMaterial::get_instant_threshold);
	ClassDB::bind_method(D_METHOD("set_ore", "ore"), &PlanetCoreMaterial::set_ore);
	ClassDB::bind_method(D_METHOD("is_ore"), &PlanetCoreMaterial::is_ore);
	ClassDB::bind_method(D_METHOD("set_chunk_volume", "chunk_volume"), &PlanetCoreMaterial::set_chunk_volume);
	ClassDB::bind_method(D_METHOD("get_chunk_volume"), &PlanetCoreMaterial::get_chunk_volume);
	ClassDB::bind_method(D_METHOD("set_chunk_mass", "chunk_mass"), &PlanetCoreMaterial::set_chunk_mass);
	ClassDB::bind_method(D_METHOD("get_chunk_mass"), &PlanetCoreMaterial::get_chunk_mass);
	ClassDB::bind_method(D_METHOD("cuttable"), &PlanetCoreMaterial::cuttable);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name"), "set_name", "get_name");
	ADD_PROPERTY(PropertyInfo(Variant::COLOR, "color"), "set_color", "get_color");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_power"), "set_min_power", "get_min_power");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "hardness"), "set_hardness", "get_hardness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "instant_threshold"), "set_instant_threshold", "get_instant_threshold");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "ore"), "set_ore", "is_ore");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "chunk_volume"), "set_chunk_volume", "get_chunk_volume");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "chunk_mass"), "set_chunk_mass", "get_chunk_mass");
}

bool PlanetCoreMaterial::cuttable() const {
	return std::isfinite(min_power);
}

void PlanetCoreOre::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_material", "material"), &PlanetCoreOre::set_material);
	ClassDB::bind_method(D_METHOD("get_material"), &PlanetCoreOre::get_material);
	ClassDB::bind_method(D_METHOD("set_count_min", "count_min"), &PlanetCoreOre::set_count_min);
	ClassDB::bind_method(D_METHOD("get_count_min"), &PlanetCoreOre::get_count_min);
	ClassDB::bind_method(D_METHOD("set_count_max", "count_max"), &PlanetCoreOre::set_count_max);
	ClassDB::bind_method(D_METHOD("get_count_max"), &PlanetCoreOre::get_count_max);
	ClassDB::bind_method(D_METHOD("set_size_min", "size_min"), &PlanetCoreOre::set_size_min);
	ClassDB::bind_method(D_METHOD("get_size_min"), &PlanetCoreOre::get_size_min);
	ClassDB::bind_method(D_METHOD("set_size_max", "size_max"), &PlanetCoreOre::set_size_max);
	ClassDB::bind_method(D_METHOD("get_size_max"), &PlanetCoreOre::get_size_max);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "material"), "set_material", "get_material");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "count_min"), "set_count_min", "get_count_min");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "count_max"), "set_count_max", "get_count_max");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "size_min"), "set_size_min", "get_size_min");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "size_max"), "set_size_max", "get_size_max");
}

void PlanetCoreShell::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_name", "name"), &PlanetCoreShell::set_name);
	ClassDB::bind_method(D_METHOD("get_name"), &PlanetCoreShell::get_name);
	ClassDB::bind_method(D_METHOD("set_rows", "rows"), &PlanetCoreShell::set_rows);
	ClassDB::bind_method(D_METHOD("get_rows"), &PlanetCoreShell::get_rows);
	ClassDB::bind_method(D_METHOD("set_base_material", "material"), &PlanetCoreShell::set_base_material);
	ClassDB::bind_method(D_METHOD("get_base_material"), &PlanetCoreShell::get_base_material);
	ClassDB::bind_method(D_METHOD("set_secondary_material", "material"), &PlanetCoreShell::set_secondary_material);
	ClassDB::bind_method(D_METHOD("get_secondary_material"), &PlanetCoreShell::get_secondary_material);
	ClassDB::bind_method(D_METHOD("set_secondary_amount", "amount"), &PlanetCoreShell::set_secondary_amount);
	ClassDB::bind_method(D_METHOD("get_secondary_amount"), &PlanetCoreShell::get_secondary_amount);
	ClassDB::bind_method(D_METHOD("set_noise_frequency", "frequency"), &PlanetCoreShell::set_noise_frequency);
	ClassDB::bind_method(D_METHOD("get_noise_frequency"), &PlanetCoreShell::get_noise_frequency);
	ClassDB::bind_method(D_METHOD("set_ores", "ores"), &PlanetCoreShell::set_ores);
	ClassDB::bind_method(D_METHOD("get_ores"), &PlanetCoreShell::get_ores);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name"), "set_name", "get_name");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "rows"), "set_rows", "get_rows");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "base_material"), "set_base_material", "get_base_material");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "secondary_material"), "set_secondary_material", "get_secondary_material");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "secondary_amount"), "set_secondary_amount", "get_secondary_amount");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "noise_frequency"), "set_noise_frequency", "get_noise_frequency");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "ores"), "set_ores", "get_ores");
}

void PlanetCoreConfig::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_subdivision", "level"), &PlanetCoreConfig::set_subdivision);
	ClassDB::bind_method(D_METHOD("get_subdivision"), &PlanetCoreConfig::get_subdivision);
	ClassDB::bind_method(D_METHOD("set_patch_level", "level"), &PlanetCoreConfig::set_patch_level);
	ClassDB::bind_method(D_METHOD("get_patch_level"), &PlanetCoreConfig::get_patch_level);
	ClassDB::bind_method(D_METHOD("set_core_radius", "radius"), &PlanetCoreConfig::set_core_radius);
	ClassDB::bind_method(D_METHOD("get_core_radius"), &PlanetCoreConfig::get_core_radius);
	ClassDB::bind_method(D_METHOD("set_row_spacing", "spacing"), &PlanetCoreConfig::set_row_spacing);
	ClassDB::bind_method(D_METHOD("get_row_spacing"), &PlanetCoreConfig::get_row_spacing);
	ClassDB::bind_method(D_METHOD("set_core_material", "material"), &PlanetCoreConfig::set_core_material);
	ClassDB::bind_method(D_METHOD("get_core_material"), &PlanetCoreConfig::get_core_material);
	ClassDB::bind_method(D_METHOD("set_materials", "materials"), &PlanetCoreConfig::set_materials);
	ClassDB::bind_method(D_METHOD("get_materials"), &PlanetCoreConfig::get_materials);
	ClassDB::bind_method(D_METHOD("set_shells", "shells"), &PlanetCoreConfig::set_shells);
	ClassDB::bind_method(D_METHOD("get_shells"), &PlanetCoreConfig::get_shells);
	ClassDB::bind_method(D_METHOD("diggable_rows"), &PlanetCoreConfig::diggable_rows);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "subdivision"), "set_subdivision", "get_subdivision");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "patch_level"), "set_patch_level", "get_patch_level");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "core_radius"), "set_core_radius", "get_core_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "row_spacing"), "set_row_spacing", "get_row_spacing");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "core_material"), "set_core_material", "get_core_material");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "materials"), "set_materials", "get_materials");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "shells"), "set_shells", "get_shells");
}

int32_t PlanetCoreConfig::diggable_rows() const {
	int32_t n = 0;
	for (int64_t i = 0; i < shells.size(); i++) {
		Ref<PlanetCoreShell> shell = shells[i];
		if (shell.is_valid()) {
			n += shell->get_rows();
		}
	}
	return n;
}
