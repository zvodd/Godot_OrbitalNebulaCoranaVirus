#ifndef PLANET_CORE_MESHER_H
#define PLANET_CORE_MESHER_H

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

#include "planet_core_grid.h"

namespace godot {

/**
 * C++ port of `game/planet/planet_mesher.gd`.
 *
 * Marching tetrahedra over the lattice's triangular prisms. Pure data: PlanetCoreGrid arrays
 * in -> triangle arrays out. No nodes, no rendering types.
 *
 * Each icosphere face x row gap is a prism, split into 3 tets using global vertex order
 * (v0 < v1 < v2; b = bottom row, t = top row):
 *   T1 = (v0b, v1b, v2b, v0t)   T2 = (v1b, v2b, v0t, v1t)   T3 = (v2b, v0t, v1t, v2t)
 * The diagonal on every quad side depends only on the shared edge, so neighbouring prisms
 * agree and the mesh is watertight.
 */
class PlanetCoreMesher : public RefCounted {
	GDCLASS(PlanetCoreMesher, RefCounted)

public:
	static constexpr double ISO = 0.5;
	/** Colour multiplier for corrupted cells. */
	static const Color CORRUPT_TINT;

private:
	std::vector<Vector3> vertices;
	std::vector<Vector3> normals;
	std::vector<Color> colors;

	Ref<PlanetCoreGrid> grid;
	const std::vector<float> *fill_ptr = nullptr;
	const std::vector<Vector3> *verts_ptr = nullptr;
	int32_t V = 0;
	double r0 = 0.0;
	double dr = 1.0;

	// Scratch: corner permutation for the current tet.
	int32_t ti[4] = { 0, 0, 0, 0 };
	float tf[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	// Scratch: the (up to 4) iso crossings of the current tet.
	Vector3 sp[4];
	Vector3 sn[4];
	Color sc[4];

	void _tet(int32_t i0, int32_t i1, int32_t i2, int32_t i3,
			float f0, float f1, float f2, float f3);
	void _edge(int32_t slot, int32_t i, int32_t j, double fi, double fj,
			const Vector3 &pi, const Vector3 &pj, int32_t solid);
	void _tri(int32_t s0, int32_t s1, int32_t s2, const Vector3 &outward);

protected:
	static void _bind_methods();

public:
	/** Mesh one patch (chunk). Results are left in vertices/normals/colors. */
	void build_patch(const Ref<PlanetCoreGrid> &p_grid, int32_t patch);
	/** Mesh a contiguous range of icosphere faces. */
	void build_faces(const Ref<PlanetCoreGrid> &p_grid, int32_t face_begin, int32_t face_end);

	PackedVector3Array get_vertices() const;
	PackedVector3Array get_normals() const;
	PackedColorArray get_colors() const;
	int32_t get_triangle_count() const { return (int32_t)(vertices.size() / 3); }

	const std::vector<Vector3> &vertices_ref() const { return vertices; }
	const std::vector<Vector3> &normals_ref() const { return normals; }
	const std::vector<Color> &colors_ref() const { return colors; }
};

} // namespace godot

#endif // PLANET_CORE_MESHER_H
