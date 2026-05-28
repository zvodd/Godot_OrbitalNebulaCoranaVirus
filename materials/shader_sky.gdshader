shader_type sky;

uniform sampler2D sky_tex : filter_linear, source_color, hint_default_black;
uniform float blend_center : hint_range(0.0, 1.0) = 0.98;
uniform float blend_width : hint_range(0.0, 0.2) = 0.02;
uniform vec2 side_uv_scale = vec2(4.0, 3.14159);
uniform vec2 top_uv_scale = vec2(3.14159, 3.14159);

void sky() {
	float abs_y = abs(EYEDIR.y);
	float half_w = blend_width * 0.5;
	float low = blend_center - half_w;
	float high = blend_center + half_w;

	if (abs_y < low) {
		// Only side
		COLOR = texture(sky_tex, SKY_COORDS * side_uv_scale).rgb;
	} 
	else if (abs_y > high) {
		// Only top/bottom
		COLOR = texture(sky_tex, EYEDIR.zx * top_uv_scale).rgb;
	} 
	else {
		// Transition zone: sample both
		vec3 side = texture(sky_tex, SKY_COORDS * side_uv_scale).rgb;
		vec3 top = texture(sky_tex, EYEDIR.zx * top_uv_scale).rgb;
		float weight = smoothstep(low, high, abs_y);
		COLOR = mix(side, top, weight);
	}
}