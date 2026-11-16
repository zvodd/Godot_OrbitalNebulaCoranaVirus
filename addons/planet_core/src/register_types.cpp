#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "planet_core_config.h"
#include "planet_core_deposit.h"
#include "planet_core_generator.h"
#include "planet_core_grid.h"
#include "planet_core_icosphere.h"
#include "planet_core_mesher.h"

using namespace godot;

void initialize_planet_core_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(PlanetCoreMaterial);
	GDREGISTER_CLASS(PlanetCoreOre);
	GDREGISTER_CLASS(PlanetCoreShell);
	GDREGISTER_CLASS(PlanetCoreConfig);
	GDREGISTER_CLASS(PlanetCoreDeposit);
	GDREGISTER_CLASS(PlanetCoreIcosphere);
	GDREGISTER_CLASS(PlanetCoreGrid);
	GDREGISTER_CLASS(PlanetCoreMesher);
	GDREGISTER_CLASS(PlanetCoreGenerator);
}

void uninitialize_planet_core_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT planet_core_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_planet_core_module);
	init_obj.register_terminator(uninitialize_planet_core_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
