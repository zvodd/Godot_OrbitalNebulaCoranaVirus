#ifndef PLANET_CORE_GENERATOR_H
#define PLANET_CORE_GENERATOR_H

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>

#include "planet_core_grid.h"
#include "planet_core_icosphere.h"

namespace godot {

class RandomNumberGenerator;

/**
 * C++ port of `game/planet/planet_generator.gd`: seed -> materials and ore deposits.
 *
 * Deterministic, so a save only needs the seed plus mutable state (ROADMAP §4.3).
 *
 * The engine's own `RandomNumberGenerator` and `FastNoiseLite` are used (not a reimplementation)
 * so the draw sequence and noise field are identical to the GDScript generator: the same seed
 * yields the same planet, deposit for deposit.
 */
class PlanetCoreGenerator : public RefCounted {
	GDCLASS(PlanetCoreGenerator, RefCounted)

	static void _place_deposits(const Ref<PlanetCoreGrid> &grid, RandomNumberGenerator *rng);

protected:
	static void _bind_methods();

public:
	/** Fill and populate `grid` from `planet_seed`. Same seed -> same planet. */
	static void generate(const Ref<PlanetCoreGrid> &grid, int64_t planet_seed);
};

} // namespace godot

#endif // PLANET_CORE_GENERATOR_H
