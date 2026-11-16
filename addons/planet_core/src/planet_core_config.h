#ifndef PLANET_CORE_CONFIG_H
#define PLANET_CORE_CONFIG_H

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

/**
 * Plain-data mirror of MaterialDef, so the mesher and generator never touch Resources.
 * The GDScript side builds these from `data/materials/*.tres`.
 */
class PlanetCoreMaterial : public RefCounted {
	GDCLASS(PlanetCoreMaterial, RefCounted)

	String name = String("Material");
	Color color = Color(0.5, 0.5, 0.5);
	double min_power = 1.0;
	double hardness = 1.0;
	double instant_threshold = 8.0;
	bool ore = false;
	double chunk_volume = 2.0;
	double chunk_mass = 1.0;

protected:
	static void _bind_methods();

public:
	void set_name(const String &p_name) { name = p_name; }
	String get_name() const { return name; }
	void set_color(const Color &p_color) { color = p_color; }
	Color get_color() const { return color; }
	void set_min_power(double p_power) { min_power = p_power; }
	double get_min_power() const { return min_power; }
	void set_hardness(double p_hardness) { hardness = p_hardness; }
	double get_hardness() const { return hardness; }
	void set_instant_threshold(double p_value) { instant_threshold = p_value; }
	double get_instant_threshold() const { return instant_threshold; }
	void set_ore(bool p_ore) { ore = p_ore; }
	bool is_ore() const { return ore; }
	void set_chunk_volume(double p_volume) { chunk_volume = p_volume; }
	double get_chunk_volume() const { return chunk_volume; }
	void set_chunk_mass(double p_mass) { chunk_mass = p_mass; }
	double get_chunk_mass() const { return chunk_mass; }

	bool cuttable() const;
};

/** Plain-data mirror of OreDef (one entry of a shell's ore table). */
class PlanetCoreOre : public RefCounted {
	GDCLASS(PlanetCoreOre, RefCounted)

	int32_t material = -1;
	int32_t count_min = 4;
	int32_t count_max = 8;
	int32_t size_min = 30;
	int32_t size_max = 90;

protected:
	static void _bind_methods();

public:
	void set_material(int32_t p_material) { material = p_material; }
	int32_t get_material() const { return material; }
	void set_count_min(int32_t p_value) { count_min = p_value; }
	int32_t get_count_min() const { return count_min; }
	void set_count_max(int32_t p_value) { count_max = p_value; }
	int32_t get_count_max() const { return count_max; }
	void set_size_min(int32_t p_value) { size_min = p_value; }
	int32_t get_size_min() const { return size_min; }
	void set_size_max(int32_t p_value) { size_max = p_value; }
	int32_t get_size_max() const { return size_max; }
};

/** Plain-data mirror of ShellDef. Material fields are indices into PlanetCoreConfig.materials. */
class PlanetCoreShell : public RefCounted {
	GDCLASS(PlanetCoreShell, RefCounted)

	String name = String("Shell");
	int32_t rows = 3;
	int32_t base_material = -1;
	int32_t secondary_material = -1;
	double secondary_amount = 0.3;
	double noise_frequency = 0.08;
	Array ores;

protected:
	static void _bind_methods();

public:
	void set_name(const String &p_name) { name = p_name; }
	String get_name() const { return name; }
	void set_rows(int32_t p_rows) { rows = p_rows; }
	int32_t get_rows() const { return rows; }
	void set_base_material(int32_t p_material) { base_material = p_material; }
	int32_t get_base_material() const { return base_material; }
	void set_secondary_material(int32_t p_material) { secondary_material = p_material; }
	int32_t get_secondary_material() const { return secondary_material; }
	void set_secondary_amount(double p_amount) { secondary_amount = p_amount; }
	double get_secondary_amount() const { return secondary_amount; }
	void set_noise_frequency(double p_frequency) { noise_frequency = p_frequency; }
	double get_noise_frequency() const { return noise_frequency; }
	void set_ores(const Array &p_ores) { ores = p_ores; }
	Array get_ores() const { return ores; }
};

/**
 * Plain-data mirror of PlanetDef: lattice resolution plus the material/shell tables.
 * Build one with `PlanetCoreConfig.from_planet_def()` or by hand.
 */
class PlanetCoreConfig : public RefCounted {
	GDCLASS(PlanetCoreConfig, RefCounted)

	int32_t subdivision = 5;
	int32_t patch_level = 2;
	double core_radius = 8.0;
	double row_spacing = 1.0;
	int32_t core_material = 0;
	Array materials;
	Array shells;

protected:
	static void _bind_methods();

public:
	void set_subdivision(int32_t p_level) { subdivision = p_level; }
	int32_t get_subdivision() const { return subdivision; }
	void set_patch_level(int32_t p_level) { patch_level = p_level; }
	int32_t get_patch_level() const { return patch_level; }
	void set_core_radius(double p_radius) { core_radius = p_radius; }
	double get_core_radius() const { return core_radius; }
	void set_row_spacing(double p_spacing) { row_spacing = p_spacing; }
	double get_row_spacing() const { return row_spacing; }
	void set_core_material(int32_t p_material) { core_material = p_material; }
	int32_t get_core_material() const { return core_material; }
	void set_materials(const Array &p_materials) { materials = p_materials; }
	Array get_materials() const { return materials; }
	void set_shells(const Array &p_shells) { shells = p_shells; }
	Array get_shells() const { return shells; }

	int32_t diggable_rows() const;
};

} // namespace godot

#endif // PLANET_CORE_CONFIG_H
