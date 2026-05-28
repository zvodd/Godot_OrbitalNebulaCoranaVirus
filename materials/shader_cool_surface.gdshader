shader_type spatial;

varying vec3 POS;
void vertex() {
	POS = VERTEX;
}

void fragment() {
	vec3 n_pos = normalize(POS - NORMAL); // Model space centered at 0,0,0
	float u = atan(n_pos.z, n_pos.x) / TAU + 0.5;
	float v = acos(n_pos.y) / PI;
	vec2 sphere_uv = vec2(u, v);
	
	vec2 coords = sphere_uv * 3.0;
    float l = length(coords * 2.0 - 1.0) * 50.0;
    // TIME replaces T. COLOR (vec3) replaces O.
    vec3 c = (sin(l - sin(l + TIME) + coords.x / 0.1 + vec3(0.0, 1.0, 2.0)) + 0.4) * cos(l);
    ALBEDO = smoothstep(-0.7, 1.0, c);
}
