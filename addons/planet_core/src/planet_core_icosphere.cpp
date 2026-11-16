#include "planet_core_icosphere.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <cmath>
#include <limits>

using namespace godot;

void PlanetCoreIcosphere::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "level", "patch_level"), &PlanetCoreIcosphere::build, DEFVAL(5), DEFVAL(2));
	ClassDB::bind_method(D_METHOD("is_built"), &PlanetCoreIcosphere::is_built);
	ClassDB::bind_method(D_METHOD("get_level"), &PlanetCoreIcosphere::get_level);
	ClassDB::bind_method(D_METHOD("get_patch_level"), &PlanetCoreIcosphere::get_patch_level);
	ClassDB::bind_method(D_METHOD("get_vertex_count"), &PlanetCoreIcosphere::get_vertex_count);
	ClassDB::bind_method(D_METHOD("get_face_count"), &PlanetCoreIcosphere::get_face_count);
	ClassDB::bind_method(D_METHOD("get_patch_count"), &PlanetCoreIcosphere::get_patch_count);
	ClassDB::bind_method(D_METHOD("get_faces_per_patch"), &PlanetCoreIcosphere::get_faces_per_patch);
	ClassDB::bind_method(D_METHOD("get_mean_edge"), &PlanetCoreIcosphere::get_mean_edge);
	ClassDB::bind_method(D_METHOD("get_verts"), &PlanetCoreIcosphere::get_verts);
	ClassDB::bind_method(D_METHOD("get_faces"), &PlanetCoreIcosphere::get_faces);
	ClassDB::bind_method(D_METHOD("get_face_patch"), &PlanetCoreIcosphere::get_face_patch);
	ClassDB::bind_method(D_METHOD("get_adj_offsets"), &PlanetCoreIcosphere::get_adj_offsets);
	ClassDB::bind_method(D_METHOD("get_adj"), &PlanetCoreIcosphere::get_adj);
	ClassDB::bind_method(D_METHOD("get_dirty_offsets"), &PlanetCoreIcosphere::get_dirty_offsets);
	ClassDB::bind_method(D_METHOD("get_dirty_patches"), &PlanetCoreIcosphere::get_dirty_patches);
	ClassDB::bind_method(D_METHOD("get_lut"), &PlanetCoreIcosphere::get_lut);
	ClassDB::bind_method(D_METHOD("patch_face_begin", "patch"), &PlanetCoreIcosphere::patch_face_begin);
	ClassDB::bind_method(D_METHOD("valence", "v"), &PlanetCoreIcosphere::valence);
	ClassDB::bind_method(D_METHOD("nearest_vertex", "dir", "hint"), &PlanetCoreIcosphere::nearest_vertex, DEFVAL(-1));
	ClassDB::bind_method(D_METHOD("nearest_vertex_brute", "dir"), &PlanetCoreIcosphere::nearest_vertex_brute);
}

void PlanetCoreIcosphere::build(int32_t p_level, int32_t p_patch_level) {
	level = p_level;
	patch_level = p_patch_level < p_level ? p_patch_level : p_level;
	verts.clear();
	faces.clear();
	face_patch.clear();
	adj_offsets.clear();
	adj.clear();
	dirty_offsets.clear();
	dirty_patches.clear();
	lut.clear();
	_build_mesh();
	_build_adjacency();
	_build_dirty_patches();
	_build_lut();
	built = true;
}

Ref<PlanetCoreIcosphere> PlanetCoreIcosphere::create(int32_t p_level, int32_t p_patch_level) {
	Ref<PlanetCoreIcosphere> ico;
	ico.instantiate();
	ico->build(p_level, p_patch_level);
	return ico;
}

int32_t PlanetCoreIcosphere::patch_face_begin(int32_t patch) const {
	return patch * faces_per_patch;
}

int32_t PlanetCoreIcosphere::valence(int32_t v) const {
	return adj_offsets[v + 1] - adj_offsets[v];
}

void PlanetCoreIcosphere::_build_mesh() {
	const double t = (1.0 + std::sqrt(5.0)) / 2.0;
	// Kept in source order: the vertex numbering must match the GDScript original exactly.
	const double base[12][3] = {
		{ -1, t, 0 }, { 1, t, 0 }, { -1, -t, 0 }, { 1, -t, 0 },
		{ 0, -1, t }, { 0, 1, t }, { 0, -1, -t }, { 0, 1, -t },
		{ t, 0, -1 }, { t, 0, 1 }, { -t, 0, -1 }, { -t, 0, 1 }
	};
	verts.clear();
	verts.reserve(10242);
	for (int i = 0; i < 12; i++) {
		Vector3 v((real_t)base[i][0], (real_t)base[i][1], (real_t)base[i][2]);
		verts.push_back(v.normalized());
	}

	static const int32_t base_faces[60] = {
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1
	};
	faces.assign(base_faces, base_faces + 60);
	face_patch.assign(20, 0);
	for (int32_t i = 0; i < 20; i++) {
		face_patch[i] = i;
	}

	std::unordered_map<uint64_t, int32_t> mid;
	for (int32_t l = 1; l <= level; l++) {
		std::vector<int32_t> nf;
		std::vector<int32_t> np;
		const int32_t fc = (int32_t)(faces.size() / 3);
		nf.resize((size_t)fc * 12);
		np.resize((size_t)fc * 4);
		for (int32_t f = 0; f < fc; f++) {
			const int32_t a = faces[f * 3];
			const int32_t b = faces[f * 3 + 1];
			const int32_t c = faces[f * 3 + 2];
			const int32_t ab = _midpoint(a, b, mid);
			const int32_t bc = _midpoint(b, c, mid);
			const int32_t ca = _midpoint(c, a, mid);
			const int32_t o = f * 12;
			nf[o] = a;
			nf[o + 1] = ab;
			nf[o + 2] = ca;
			nf[o + 3] = b;
			nf[o + 4] = bc;
			nf[o + 5] = ab;
			nf[o + 6] = c;
			nf[o + 7] = ca;
			nf[o + 8] = bc;
			nf[o + 9] = ab;
			nf[o + 10] = bc;
			nf[o + 11] = ca;
			const int32_t p = face_patch[f];
			for (int32_t j = 0; j < 4; j++) {
				// Up to the patch level every face is its own patch; below it, inherit.
				np[f * 4 + j] = (l <= patch_level) ? (f * 4 + j) : p;
			}
		}
		faces.swap(nf);
		face_patch.swap(np);
	}

	vertex_count = (int32_t)verts.size();
	face_count = (int32_t)(faces.size() / 3);
	patch_count = 20 * (int32_t)std::pow(4.0, (double)patch_level);
	faces_per_patch = face_count / patch_count;
}

int32_t PlanetCoreIcosphere::_midpoint(int32_t a, int32_t b, std::unordered_map<uint64_t, int32_t> &cache) {
	const uint64_t lo = (uint64_t)(a < b ? a : b);
	const uint64_t hi = (uint64_t)(a < b ? b : a);
	const uint64_t key = (lo << 32) | hi;
	auto it = cache.find(key);
	if (it != cache.end()) {
		return it->second;
	}
	const int32_t idx = (int32_t)verts.size();
	verts.push_back((verts[a] + verts[b]).normalized());
	cache[key] = idx;
	return idx;
}

void PlanetCoreIcosphere::_build_adjacency() {
	// Consistently wound closed mesh: each undirected edge appears once per direction,
	// so adding the "next" vertex of every face corner lists each neighbour exactly once.
	std::vector<int32_t> deg((size_t)vertex_count, 0);
	for (size_t i = 0; i < faces.size(); i++) {
		deg[faces[i]] += 1;
	}
	adj_offsets.assign((size_t)vertex_count + 1, 0);
	int32_t total = 0;
	for (int32_t v = 0; v < vertex_count; v++) {
		adj_offsets[v] = total;
		total += deg[v];
	}
	adj_offsets[vertex_count] = total;
	adj.assign((size_t)total, 0);
	std::vector<int32_t> cursor(adj_offsets.begin(), adj_offsets.end() - 1);
	double edge_sum = 0.0;
	for (int32_t f = 0; f < face_count; f++) {
		for (int32_t j = 0; j < 3; j++) {
			const int32_t a = faces[f * 3 + j];
			const int32_t b = faces[f * 3 + (j + 1) % 3];
			adj[cursor[a]] = b;
			cursor[a] += 1;
			// distance_to() is real_t (float32) in both implementations; the sum stays double.
			edge_sum += (double)verts[a].distance_to(verts[b]);
		}
	}
	mean_edge = edge_sum / (double)total;
}

void PlanetCoreIcosphere::_build_dirty_patches() {
	// Patches touching each vertex.
	std::vector<std::vector<int32_t>> own((size_t)vertex_count);
	for (int32_t f = 0; f < face_count; f++) {
		const int32_t p = face_patch[f];
		for (int32_t j = 0; j < 3; j++) {
			std::vector<int32_t> &list = own[faces[f * 3 + j]];
			bool has = false;
			for (size_t q = 0; q < list.size(); q++) {
				if (list[q] == p) {
					has = true;
					break;
				}
			}
			if (!has) {
				list.push_back(p);
			}
		}
	}
	dirty_offsets.assign((size_t)vertex_count + 1, 0);
	dirty_patches.clear();
	for (int32_t v = 0; v < vertex_count; v++) {
		dirty_offsets[v] = (int32_t)dirty_patches.size();
		std::vector<int32_t> merged = own[v];
		for (int32_t j = adj_offsets[v]; j < adj_offsets[v + 1]; j++) {
			const int32_t nb = adj[j];
			for (size_t q = 0; q < own[nb].size(); q++) {
				const int32_t p = own[nb][q];
				bool has = false;
				for (size_t m = 0; m < merged.size(); m++) {
					if (merged[m] == p) {
						has = true;
						break;
					}
				}
				if (!has) {
					merged.push_back(p);
				}
			}
		}
		for (size_t m = 0; m < merged.size(); m++) {
			dirty_patches.push_back(merged[m]);
		}
	}
	dirty_offsets[vertex_count] = (int32_t)dirty_patches.size();
}

void PlanetCoreIcosphere::_build_lut() {
	lut.assign((size_t)(6 * LUT_N * LUT_N), 0);
	int32_t cur = 0;
	for (int32_t face = 0; face < 6; face++) {
		for (int32_t y = 0; y < LUT_N; y++) {
			for (int32_t x = 0; x < LUT_N; x++) {
				// u/v are doubled GDScript floats: keep the double maths, narrow at the Vector3.
				const double u = (x + 0.5) / LUT_N * 2.0 - 1.0;
				const double v = (y + 0.5) / LUT_N * 2.0 - 1.0;
				Vector3 d;
				switch (face) {
					case 0:
						d = Vector3(1, (real_t)u, (real_t)v);
						break;
					case 1:
						d = Vector3(-1, (real_t)u, (real_t)v);
						break;
					case 2:
						d = Vector3((real_t)u, 1, (real_t)v);
						break;
					case 3:
						d = Vector3((real_t)u, -1, (real_t)v);
						break;
					case 4:
						d = Vector3((real_t)u, (real_t)v, 1);
						break;
					default:
						d = Vector3((real_t)u, (real_t)v, -1);
						break;
				}
				cur = (int32_t)nearest_vertex(d, cur);
				lut[(size_t)((face * LUT_N + y) * LUT_N + x)] = cur;
			}
		}
	}
}

int64_t PlanetCoreIcosphere::_lut_index(const Vector3 &dir) const {
	const double ax = std::fabs((double)dir.x);
	const double ay = std::fabs((double)dir.y);
	const double az = std::fabs((double)dir.z);
	int32_t face;
	double u;
	double v;
	if (ax >= ay && ax >= az) {
		face = dir.x > 0.0f ? 0 : 1;
		u = (double)dir.y / ax;
		v = (double)dir.z / ax;
	} else if (ay >= az) {
		face = dir.y > 0.0f ? 2 : 3;
		u = (double)dir.x / ay;
		v = (double)dir.z / ay;
	} else {
		face = dir.z > 0.0f ? 4 : 5;
		u = (double)dir.x / az;
		v = (double)dir.y / az;
	}
	int32_t x = (int32_t)((u * 0.5 + 0.5) * LUT_N);
	int32_t y = (int32_t)((v * 0.5 + 0.5) * LUT_N);
	x = x < 0 ? 0 : (x > LUT_N - 1 ? LUT_N - 1 : x);
	y = y < 0 ? 0 : (y > LUT_N - 1 ? LUT_N - 1 : y);
	return (int64_t)((face * LUT_N + y) * LUT_N + x);
}

int64_t PlanetCoreIcosphere::nearest_vertex(const Vector3 &dir, int32_t hint) const {
	int32_t cur = hint >= 0 ? hint : (int32_t)lut[_lut_index(dir)];
	real_t best_d = dir.dot(verts[cur]);
	while (true) {
		bool improved = false;
		const int32_t s = adj_offsets[cur];
		const int32_t e = adj_offsets[cur + 1];
		for (int32_t j = s; j < e; j++) {
			const int32_t n = adj[j];
			const real_t d = dir.dot(verts[n]);
			if (d > best_d) {
				best_d = d;
				cur = n;
				improved = true;
			}
		}
		if (!improved) {
			break;
		}
	}
	return cur;
}

int64_t PlanetCoreIcosphere::nearest_vertex_brute(const Vector3 &dir) const {
	int32_t best = 0;
	real_t best_d = -std::numeric_limits<real_t>::infinity();
	for (int32_t i = 0; i < vertex_count; i++) {
		const real_t d = dir.dot(verts[i]);
		if (d > best_d) {
			best_d = d;
			best = i;
		}
	}
	return best;
}

PackedVector3Array PlanetCoreIcosphere::get_verts() const {
	PackedVector3Array out;
	out.resize((int64_t)verts.size());
	Vector3 *w = out.ptrw();
	for (size_t i = 0; i < verts.size(); i++) {
		w[i] = verts[i];
	}
	return out;
}

PackedInt32Array PlanetCoreIcosphere::get_faces() const {
	PackedInt32Array out;
	out.resize((int64_t)faces.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < faces.size(); i++) {
		w[i] = faces[i];
	}
	return out;
}

PackedInt32Array PlanetCoreIcosphere::get_face_patch() const {
	PackedInt32Array out;
	out.resize((int64_t)face_patch.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < face_patch.size(); i++) {
		w[i] = face_patch[i];
	}
	return out;
}

PackedInt32Array PlanetCoreIcosphere::get_adj_offsets() const {
	PackedInt32Array out;
	out.resize((int64_t)adj_offsets.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < adj_offsets.size(); i++) {
		w[i] = adj_offsets[i];
	}
	return out;
}

PackedInt32Array PlanetCoreIcosphere::get_adj() const {
	PackedInt32Array out;
	out.resize((int64_t)adj.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < adj.size(); i++) {
		w[i] = adj[i];
	}
	return out;
}

PackedInt32Array PlanetCoreIcosphere::get_dirty_offsets() const {
	PackedInt32Array out;
	out.resize((int64_t)dirty_offsets.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < dirty_offsets.size(); i++) {
		w[i] = dirty_offsets[i];
	}
	return out;
}

PackedInt32Array PlanetCoreIcosphere::get_dirty_patches() const {
	PackedInt32Array out;
	out.resize((int64_t)dirty_patches.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < dirty_patches.size(); i++) {
		w[i] = dirty_patches[i];
	}
	return out;
}

PackedInt32Array PlanetCoreIcosphere::get_lut() const {
	PackedInt32Array out;
	out.resize((int64_t)lut.size());
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < lut.size(); i++) {
		w[i] = lut[i];
	}
	return out;
}
