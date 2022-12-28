shader_type canvas_item;
render_mode blend_mix;

uniform float height = 1.0;

vec4 pack_normal(vec3 n) {
	return vec4((0.5 * (n + 1.0)).xzy, 1.0);
}

void fragment() {
	vec2 uv = UV;
	vec2 ps = TEXTURE_PIXEL_SIZE;
	float left = texture(TEXTURE, uv + vec2(-ps.x, 0)).r * height;
	float right = texture(TEXTURE, uv + vec2(ps.x, 0)).r * height;
	float back = texture(TEXTURE, uv + vec2(0, -ps.y)).r * height;
	float fore = texture(TEXTURE, uv + vec2(0, ps.y)).r * height;
	vec3 horizontal = vec3(2.0, right - left, 0.0);
	vec3 vertical = vec3(0.0, back - fore, 2.0);
	vec3 normal = normalize(cross(vertical, horizontal));
	
	COLOR = pack_normal(normal);

}