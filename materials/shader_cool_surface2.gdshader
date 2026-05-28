shader_type spatial;
render_mode unshaded;

varying vec3 v_pos;
varying vec3 v_nor;
uniform float uv_scale = 1.0;


void vertex() {
    v_pos = VERTEX;
    v_nor = NORMAL;
}

vec4 pattern(vec2 p, float t) {
    float l = length(p) - 1.0;
    vec4 c = vec4(0.0, 1.0, 2.0, 0.0);
    float inner = 0.1 / max(l * 10.0, -l) - sin(l + p.y * max(1.0, -l * 10.0) + t + c.x);
    return 0.5 + tanh(0.1 / max(l * 10.0, -l) - sin(l + p.y * max(1.0, -l * 10.0) + t + vec4(0, 1, 2, 1))) / 2.0;
}

void fragment() {
    vec3 n = normalize(v_pos);
    vec3 w = abs(n);
    w /= (w.x + w.y + w.z);
    // Scaling happens here
    vec3 p = v_pos * uv_scale;
    vec4 xz = pattern(p.xz, TIME);
    vec4 xy = pattern(p.xy, TIME);
    vec4 yz = pattern(p.yz, TIME);
    vec4 res = xz * w.y + xy * w.z + yz * w.x;
	
    //ALBEDO = res.rgb;
	
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 5.0);
	ALBEDO = mix(res.rgb, vec3(0.9,0.1,0.5), fresnel);
	
    //ALPHA = res.a;
}