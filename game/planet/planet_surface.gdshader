shader_type spatial;
// Planet surface: per-material vertex colour, broken up by 3D value noise (no UVs needed),
// darkened with depth so pits read clearly, plus a faint rim. Placeholder-grade on purpose.

uniform float noise_scale = 0.9;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.3;
uniform float inner_radius = 7.5;
uniform float outer_radius = 31.5;
uniform float depth_darkening : hint_range(0.0, 1.0) = 0.5;
uniform vec3 rim_color : source_color = vec3(1.0, 0.6, 0.4);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.12;

varying vec3 v_pos;

void vertex() {
	v_pos = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void fragment() {
	float n = vnoise(v_pos * noise_scale) * 0.6 + vnoise(v_pos * noise_scale * 3.3) * 0.4;
	// Vertex colours are authored in sRGB.
	vec3 col = pow(COLOR.rgb, vec3(2.2));
	col *= 1.0 - noise_strength + 2.0 * noise_strength * n;
	float depth = smoothstep(inner_radius, outer_radius, length(v_pos));
	col *= mix(1.0 - depth_darkening, 1.0, depth);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	EMISSION = rim_color * fres * rim_strength;
}
