#include "planet_core_mesher.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;

const Color PlanetCoreMesher::CORRUPT_TINT = Color(0.28f, 0.1f, 0.34f);

namespace {
// For each 4-bit inside mask: a corner permutation (a, b, c, d).
//  kind 1: a is the lone inside corner.   kind 3: a is the lone outside corner.
//  kind 2: a, b inside; c, d outside.
const int32_t PERM[64] = {
	0, 1, 2, 3, // 0000 (unused)
	0, 1, 2, 3, // 0001  in: 0
	1, 0, 2, 3, // 0010  in: 1
	0, 1, 2, 3, // 0011  in: 0 1
	2, 0, 1, 3, // 0100  in: 2
	0, 2, 1, 3, // 0101  in: 0 2
	1, 2, 0, 3, // 0110  in: 1 2
	3, 0, 1, 2, // 0111  out: 3
	3, 0, 1, 2, // 1000  in: 3
	0, 3, 1, 2, // 1001  in: 0 3
	1, 3, 0, 2, // 1010  in: 1 3
	2, 0, 1, 3, // 1011  out: 2
	2, 3, 0, 1, // 1100  in: 2 3
	1, 0, 2, 3, // 1101  out: 1
	0, 1, 2, 3, // 1110  out: 0
	0, 1, 2, 3, // 1111 (unused)
};
const int32_t KIND[16] = { 0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 0 };
} // namespace

void PlanetCoreMesher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build_patch", "grid", "patch"), &PlanetCoreMesher::build_patch);
	ClassDB::bind_method(D_METHOD("build_faces", "grid", "face_begin", "face_end"), &PlanetCoreMesher::build_faces);
	ClassDB::bind_method(D_METHOD("get_vertices"), &PlanetCoreMesher::get_vertices);
	ClassDB::bind_method(D_METHOD("get_normals"), &PlanetCoreMesher::get_normals);
	ClassDB::bind_method(D_METHOD("get_colors"), &PlanetCoreMesher::get_colors);
	ClassDB::bind_method(D_METHOD("get_triangle_count"), &PlanetCoreMesher::get_triangle_count);
}

void PlanetCoreMesher::build_patch(const Ref<PlanetCoreGrid> &p_grid, int32_t patch) {
	ERR_FAIL_COND_MSG(p_grid.is_null(), "PlanetCoreMesher.build_patch: grid is null.");
	const int32_t begin = p_grid->get_ico()->patch_face_begin(patch);
	build_faces(p_grid, begin, begin + p_grid->get_ico()->get_faces_per_patch());
}

void PlanetCoreMesher::build_faces(const Ref<PlanetCoreGrid> &p_grid, int32_t face_begin, int32_t face_end) {
	ERR_FAIL_COND_MSG(p_grid.is_null(), "PlanetCoreMesher.build_faces: grid is null.");
	vertices.clear();
	normals.clear();
	colors.clear();

	grid = p_grid;
	fill_ptr = &p_grid->fill_ref();
	verts_ptr = &p_grid->get_ico()->verts_ref();
	V = p_grid->get_V();
	r0 = p_grid->get_r0();
	dr = p_grid->get_dr();

	const std::vector<float> &fill = *fill_ptr;
	const std::vector<int32_t> &faces = grid->get_ico()->faces_ref();
	const std::vector<Vector3> &verts = *verts_ptr;
	const int32_t rows = grid->get_rows();
	const int32_t gaps = rows - 1;

	for (int32_t f = face_begin; f < face_end; f++) {
		int32_t v0 = faces[(size_t)(f * 3)];
		int32_t v1 = faces[(size_t)(f * 3 + 1)];
		int32_t v2 = faces[(size_t)(f * 3 + 2)];
		int32_t tmp;
		if (v0 > v1) {
			tmp = v0;
			v0 = v1;
			v1 = tmp;
		}
		if (v1 > v2) {
			tmp = v1;
			v1 = v2;
			v2 = tmp;
		}
		if (v0 > v1) {
			tmp = v0;
			v0 = v1;
			v1 = tmp;
		}

		double b0 = (double)fill[(size_t)v0];
		double b1 = (double)fill[(size_t)v1];
		double b2 = (double)fill[(size_t)v2];
		int32_t nb = (b0 >= ISO ? 1 : 0) + (b1 >= ISO ? 1 : 0) + (b2 >= ISO ? 1 : 0);
		int32_t base = 0;
		for (int32_t k = 0; k < gaps; k++) {
			const int32_t top = base + V;
			const double t0 = (double)fill[(size_t)(top + v0)];
			const double t1 = (double)fill[(size_t)(top + v1)];
			const double t2 = (double)fill[(size_t)(top + v2)];
			const int32_t nt = (t0 >= ISO ? 1 : 0) + (t1 >= ISO ? 1 : 0) + (t2 >= ISO ? 1 : 0);
			const int32_t n = nb + nt;
			if (n != 0 && n != 6) {
				_tet(base + v0, base + v1, base + v2, top + v0, (float)b0, (float)b1, (float)b2, (float)t0);
				_tet(base + v1, base + v2, top + v0, top + v1, (float)b1, (float)b2, (float)t0, (float)t1);
				_tet(base + v2, top + v0, top + v1, top + v2, (float)b2, (float)t0, (float)t1, (float)t2);
			}
			b0 = t0;
			b1 = t1;
			b2 = t2;
			nb = nt;
			base = top;
		}
	}
	grid.unref();
	fill_ptr = nullptr;
	verts_ptr = nullptr;
}

void PlanetCoreMesher::_tet(int32_t i0, int32_t i1, int32_t i2, int32_t i3,
		float f0, float f1, float f2, float f3) {
	const int32_t m = (f0 >= (float)ISO ? 1 : 0) | ((f1 >= (float)ISO ? 1 : 0) << 1) |
			((f2 >= (float)ISO ? 1 : 0) << 2) | ((f3 >= (float)ISO ? 1 : 0) << 3);
	const int32_t kind = KIND[m];
	if (kind == 0) {
		return;
	}
	ti[0] = i0;
	ti[1] = i1;
	ti[2] = i2;
	ti[3] = i3;
	tf[0] = f0;
	tf[1] = f1;
	tf[2] = f2;
	tf[3] = f3;

	const int32_t p = m * 4;
	const int32_t a = PERM[p];
	const int32_t b = PERM[p + 1];
	const int32_t c = PERM[p + 2];
	const int32_t d = PERM[p + 3];
	const int32_t ia = ti[a];
	const int32_t ib = ti[b];
	const int32_t ic = ti[c];
	const int32_t id = ti[d];
	const double fa = (double)tf[a];
	const double fb = (double)tf[b];
	const double fc = (double)tf[c];
	const double fd = (double)tf[d];

	const std::vector<Vector3> &verts = *verts_ptr;
	// _verts[ix % V] * (_r0 + (ix / V) * _dr): scalar is a GDScript float (double), narrowed
	// to float32 on the Vector3 multiply.
	const Vector3 pa = verts[(size_t)(ia % V)] * (real_t)(r0 + (double)(ia / V) * dr);
	const Vector3 pb = verts[(size_t)(ib % V)] * (real_t)(r0 + (double)(ib / V) * dr);
	const Vector3 pc = verts[(size_t)(ic % V)] * (real_t)(r0 + (double)(ic / V) * dr);
	const Vector3 pd = verts[(size_t)(id % V)] * (real_t)(r0 + (double)(id / V) * dr);

	if (kind == 2) {
		// a, b solid; c, d air. Quad ac -> ad -> bd -> bc.
		_edge(0, ia, ic, fa, fc, pa, pc, ia);
		_edge(1, ia, id, fa, fd, pa, pd, ia);
		_edge(2, ib, id, fb, fd, pb, pd, ib);
		_edge(3, ib, ic, fb, fc, pb, pc, ib);
		const Vector3 outward = pc - pa;
		_tri(0, 1, 2, outward);
		_tri(0, 2, 3, outward);
	} else if (kind == 1) {
		// a is the only solid corner.
		_edge(0, ia, ib, fa, fb, pa, pb, ia);
		_edge(1, ia, ic, fa, fc, pa, pc, ia);
		_edge(2, ia, id, fa, fd, pa, pd, ia);
		_tri(0, 1, 2, pb - pa);
	} else {
		// a is the only air corner.
		_edge(0, ia, ib, fa, fb, pa, pb, ib);
		_edge(1, ia, ic, fa, fc, pa, pc, ic);
		_edge(2, ia, id, fa, fd, pa, pd, id);
		_tri(0, 1, 2, pa - pb);
	}
}

void PlanetCoreMesher::_edge(int32_t slot, int32_t i, int32_t j, double fi, double fj,
		const Vector3 &pi, const Vector3 &pj, int32_t solid) {
	Vector3 pos;
	Vector3 g;
	// t is a GDScript float (double); lerp narrows it to float32 like the engine does.
	if (i < j) {
		const real_t t = (real_t)((ISO - fi) / (fj - fi));
		pos = pi.lerp(pj, t);
		g = grid->gradient(i).lerp(grid->gradient(j), t);
	} else {
		const real_t t = (real_t)((ISO - fj) / (fi - fj));
		pos = pj.lerp(pi, t);
		g = grid->gradient(j).lerp(grid->gradient(i), t);
	}
	sp[slot] = pos;
	const double len2 = (double)g.length_squared();
	if (len2 > 1e-10) {
		sn[slot] = -g / (real_t)std::sqrt(len2);
	} else {
		sn[slot] = pos.normalized();
	}
	Color col = grid->mat_colors_ref()[(size_t)grid->material_ref()[(size_t)solid]];
	if (grid->corruption_ref()[(size_t)solid] > 0) {
		col = col * CORRUPT_TINT;
	}
	sc[slot] = col;
}

void PlanetCoreMesher::_tri(int32_t s0, int32_t s1, int32_t s2, const Vector3 &outward) {
	const Vector3 q0 = sp[s0];
	// Godot front faces are clockwise: the right-hand normal must point INTO the solid.
	if ((sp[s1] - q0).cross(sp[s2] - q0).dot(outward) > 0.0f) {
		const int32_t tmp = s1;
		s1 = s2;
		s2 = tmp;
	}
	vertices.push_back(q0);
	vertices.push_back(sp[s1]);
	vertices.push_back(sp[s2]);
	normals.push_back(sn[s0]);
	normals.push_back(sn[s1]);
	normals.push_back(sn[s2]);
	colors.push_back(sc[s0]);
	colors.push_back(sc[s1]);
	colors.push_back(sc[s2]);
}

PackedVector3Array PlanetCoreMesher::get_vertices() const {
	PackedVector3Array out;
	out.resize((int64_t)vertices.size());
	Vector3 *w = out.ptrw();
	for (size_t i = 0; i < vertices.size(); i++) {
		w[i] = vertices[i];
	}
	return out;
}

PackedVector3Array PlanetCoreMesher::get_normals() const {
	PackedVector3Array out;
	out.resize((int64_t)normals.size());
	Vector3 *w = out.ptrw();
	for (size_t i = 0; i < normals.size(); i++) {
		w[i] = normals[i];
	}
	return out;
}

PackedColorArray PlanetCoreMesher::get_colors() const {
	PackedColorArray out;
	out.resize((int64_t)colors.size());
	Color *w = out.ptrw();
	for (size_t i = 0; i < colors.size(); i++) {
		w[i] = colors[i];
	}
	return out;
}
