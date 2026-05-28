shader_type canvas_item;

uniform vec4 crosshair_color : source_color = vec4(1.0,1.0,1.0,1.0);
uniform float thickness : hint_range(1.0,20.0) = 2.0;         // pixels
uniform float gap : hint_range(0.0,50.0) = 4.0;               // pixels between center and arm start
uniform float length : hint_range(1.0,200.0) = 12.0;         // pixels arm length
uniform vec4 border_color : source_color = vec4(0.0,0.0,0.0,0.0);
uniform float border_thickness : hint_range(0.0,10.0) = 0.0;  // pixels (outer)
uniform float aa_mul : hint_range(0.5,3.0) = 1.0;             // antialias multiplier

// convert pixel sizes -> uv (TEXTURE_PIXEL_SIZE = 1.0 / rect_size_in_pixels)
vec2 px_to_uv(float p) { return p * vec2(0.01, 0.01); }

float band_mask_axis(float coord, float center_coord, float half_width, float edge_aa) {
    float d = abs(coord - center_coord);
    return 1.0 - smoothstep(half_width - edge_aa, half_width + edge_aa, d);
}

float range_mask_1d(float x, float a_min, float a_max, float edge_aa) {
    // 1 inside [a_min, a_max], smoothed by edge_aa
    float left = smoothstep(a_min - edge_aa, a_min + edge_aa, x);
    float right = smoothstep(a_max - edge_aa, a_max + edge_aa, x);
    return left * (1.0 - right);
}


void fragment() {
    vec2 uv = UV;
    vec2 c = vec2(0.5, 0.5);

    // convert params to uv-space (separate x/y to handle non-square rects)
    vec2 t_uv = px_to_uv(thickness);
    vec2 g_uv = px_to_uv(gap);
    vec2 l_uv = px_to_uv(length);
    vec2 bt_uv = px_to_uv(border_thickness);

    // antialias widths
    float ax = max(fwidth(uv.x), 1e-6) * aa_mul;
    float ay = max(fwidth(uv.y), 1e-6) * aa_mul;

    // helper: build crosshair mask for given thickness (uv)
    // horizontal arms
    float half_th_y = t_uv.y * 0.5;
    float yband = band_mask_axis(uv.y, c.y, half_th_y, ay * 0.5);

    float left_min = c.x - g_uv.x - l_uv.x;
    float left_max = c.x - g_uv.x;
    float left_mask = range_mask_1d(uv.x, left_min, left_max, ax * 0.5);

    float right_min = c.x + g_uv.x;
    float right_max = c.x + g_uv.x + l_uv.x;
    float right_mask = range_mask_1d(uv.x, right_min, right_max, ax * 0.5);

    float horiz = yband * (left_mask + right_mask);

    // vertical arms
    float half_th_x = t_uv.x * 0.5;
    float xband = band_mask_axis(uv.x, c.x, half_th_x, ax * 0.5);

    float top_min = c.y - g_uv.y - l_uv.y;
    float top_max = c.y - g_uv.y;
    float top_mask = range_mask_1d(uv.y, top_min, top_max, ay * 0.5);

    float bot_min = c.y + g_uv.y;
    float bot_max = c.y + g_uv.y + l_uv.y;
    float bot_mask = range_mask_1d(uv.y, bot_min, bot_max, ay * 0.5);

    float vert = xband * (top_mask + bot_mask);

    float inner_mask = clamp(horiz + vert, 0.0, 1.0);

    // border: same shape but with expanded thickness
    float t2_x = t_uv.x + bt_uv.x * 2.0;
    float t2_y = t_uv.y + bt_uv.y * 2.0;

    // horizontal border
    float half_t2_y = t2_y * 0.5;
    float yband_o = band_mask_axis(uv.y, c.y, half_t2_y, ay * 0.5);

    float left_mask_o = range_mask_1d(uv.x, left_min, left_max, ax * 0.5); // same x extents
    float right_mask_o = range_mask_1d(uv.x, right_min, right_max, ax * 0.5);

    float horiz_o = yband_o * (left_mask_o + right_mask_o);

    // vertical border
    float half_t2_x = t2_x * 0.5;
    float xband_o = band_mask_axis(uv.x, c.x, half_t2_x, ax * 0.5);

    float top_mask_o = range_mask_1d(uv.y, top_min, top_max, ay * 0.5);
    float bot_mask_o = range_mask_1d(uv.y, bot_min, bot_max, ay * 0.5);

    float vert_o = xband_o * (top_mask_o + bot_mask_o);

    float outer_mask = clamp(horiz_o + vert_o, 0.0, 1.0);
    float border_mask = max(outer_mask - inner_mask, 0.0);

    vec4 base = texture(TEXTURE, UV) * COLOR;
    vec4 col = base;

    // apply border then inner color (respect alpha)
    if (border_color.a > 0.0) {
        col = mix(col, border_color, border_mask * border_color.a);
    }
	if (inner_mask * crosshair_color.a < 0.5){
		discard;
	}
    col = mix(col, crosshair_color, inner_mask * crosshair_color.a);

    COLOR = col;
}