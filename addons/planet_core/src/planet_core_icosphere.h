#ifndef PLANET_CORE_ICOSPHERE_H
#define PLANET_CORE_ICOSPHERE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

/**
 * C++ port of `game/planet/icosphere.gd`.
 *
 * Geodesic grid on the unit sphere: vertices, faces, CSR adjacency, chunk patches and a
 * cubemap direction -> vertex lookup with a greedy descent. Pure data.
 *
 * The build order, the midpoint cache and the LUT walk are reproduced exactly, so the arrays
 * are bit-identical to the GDScript `Icosphere`.
 */
class PlanetCoreIcosphere : public RefCounted {
	GDCLASS(PlanetCoreIcosphere, RefCounted)

public:
	static const int32_t LUT_N = 32;

private:
	int32_t level = 5;
	int32_t patch_level = 2;
	int32_t vertex_count = 0;
	int32_t face_count = 0;
	int32_t patch_count = 0;
	int32_t faces_per_patch = 0;
	// GDScript floats are doubles, so the mean edge is accumulated and kept in double.
	double mean_edge = 0.0;

	std::vector<Vector3> verts;
	std::vector<int32_t> faces;
	std::vector<int32_t> face_patch;
	std::vector<int32_t> adj_offsets;
	std::vector<int32_t> adj;
	std::vector<int32_t> dirty_offsets;
	std::vector<int32_t> dirty_patches;
	std::vector<int32_t> lut;

	bool built = false;

	void _build_mesh();
	int32_t _midpoint(int32_t a, int32_t b, std::unordered_map<uint64_t, int32_t> &cache);
	void _build_adjacency();
	void _build_dirty_patches();
	void _build_lut();
	int64_t _lut_index(const Vector3 &dir) const;

protected:
	static void _bind_methods();

public:
	/** Build with the given subdivision level and chunk patch level (idempotent per call). */
	void build(int32_t p_level = 5, int32_t p_patch_level = 2);
	/** Convenience: allocates and builds in one call. */
	static Ref<PlanetCoreIcosphere> create(int32_t p_level = 5, int32_t p_patch_level = 2);
	bool is_built() const { return built; }

	int32_t get_level() const { return level; }
	int32_t get_patch_level() const { return patch_level; }
	int32_t get_vertex_count() const { return vertex_count; }
	int32_t get_face_count() const { return face_count; }
	int32_t get_patch_count() const { return patch_count; }
	int32_t get_faces_per_patch() const { return faces_per_patch; }
	double get_mean_edge() const { return mean_edge; }

	PackedVector3Array get_verts() const;
	PackedInt32Array get_faces() const;
	PackedInt32Array get_face_patch() const;
	PackedInt32Array get_adj_offsets() const;
	PackedInt32Array get_adj() const;
	PackedInt32Array get_dirty_offsets() const;
	PackedInt32Array get_dirty_patches() const;
	PackedInt32Array get_lut() const;

	int32_t patch_face_begin(int32_t patch) const;
	int32_t valence(int32_t v) const;

	/** Nearest vertex to a direction (need not be normalised). `hint` < 0 uses the cubemap LUT. */
	int64_t nearest_vertex(const Vector3 &dir, int32_t hint = -1) const;
	/** Exact linear scan, used by tests to validate the walk. */
	int64_t nearest_vertex_brute(const Vector3 &dir) const;

	// C++-side views (not bound to GDScript) for the hot mesher and grid loops.
	const std::vector<Vector3> &verts_ref() const { return verts; }
	const std::vector<int32_t> &faces_ref() const { return faces; }
	const std::vector<int32_t> &adj_offsets_ref() const { return adj_offsets; }
	const std::vector<int32_t> &adj_ref() const { return adj; }
	const std::vector<int32_t> &dirty_offsets_ref() const { return dirty_offsets; }
	const std::vector<int32_t> &dirty_patches_ref() const { return dirty_patches; }
	const std::vector<int32_t> &lut_ref() const { return lut; }

	PlanetCoreIcosphere() = default;
	~PlanetCoreIcosphere() = default;
};

} // namespace godot

#endif // PLANET_CORE_ICOSPHERE_H
