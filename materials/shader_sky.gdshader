shader_type sky;

uniform sampler2D sky_tex : source_color;

void sky(){
	COLOR = texture(sky_tex, SKY_COORDS * vec2(4.0,3.5)).rgb;
}
