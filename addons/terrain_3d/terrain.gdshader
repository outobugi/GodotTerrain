shader_type spatial;
render_mode depth_draw_opaque, diffuse_burley;

uniform float terrain_height = 128.0;
uniform float terrain_size = 1024.0;

uniform bool parallax_enabled = true;
uniform float parallax_depth = 1.0;

uniform sampler2D terrain_heightmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D terrain_normalmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D terrain_controlmap : filter_nearest_mipmap_anisotropic, repeat_disable;

uniform sampler2DArray texture_array_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray texture_array_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform int texture_array_normal_max;

uniform vec3 texture_uv_scale_array[16];
uniform vec4 texture_color_array[16];

uniform bool terrain_use_grid = true;
uniform float terrain_grid_scale = 2.0;
uniform sampler2D terrain_grid : source_color, filter_linear_mipmap_anisotropic;

varying float camera_distance_fade;

float get_height(vec2 uv){
	return texture(terrain_heightmap, uv).r * terrain_height;
}

vec3 get_normal(vec2 uv){
	vec4 nmap = texture(terrain_normalmap, uv);
	vec3 n = normalize(nmap.xzy * 2.0 - 1.0);
	n.z *= -1.0;
	return normalize(n);
}

void vertex(){
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	UV2 = (world_vertex.xz / vec2(terrain_size+1.0)) + vec2(0.5);
	UV = world_vertex.xz * 0.5;
	VERTEX.y = get_height(UV2) * (VERTEX.y + 1.0); // keep the skirt vertices intact
	NORMAL = get_normal(UV2);
	TANGENT = cross(NORMAL, vec3(0,0,1));
	BINORMAL = cross(NORMAL, TANGENT);
//	camera_distance_fade = smoothstep(92, 128, distance(INV_VIEW_MATRIX[3].xyz, world_vertex));
}

vec4 depth_blend(vec4 a_value, float a_bump, vec4 b_value, float b_bump, float t) { // unsused
	// https://www.gamasutra.com
	// /blogs/AndreyMishkinis/20130716/196339/Advanced_Terrain_Texture_Splatting.php
	float ma = max(a_bump + (1.0 - t), b_bump + t) - 0.15;
	float ba = max(a_bump + (1.0 - t) - ma, 0.0);
	float bb = max(b_bump + t - ma, 0.0);
	return (a_value * ba + b_value * bb) / (ba + bb);
}

//vec2 parallax_mapping(vec2 uv, vec3 view, float height){  
//	return uv - view.xy * (1.0 - height) * parallax_depth * 0.02;  
//}

float bbs(float input){
	return fract(dot(input*input, 251.0));
}

float random(vec2 input){
	vec4 a= fract(input.xyxy * (2.0f * vec4(1.3442f, 1.0377f, 0.98848f, 0.75775f)) + input.yxyx);
	float v = fract(dot(a*a, vec4(251.0)));
	return bbs(v);
}

float blend_weights(float weight, float detail){
	float detailContrast = 2.0;
	float result = max(0.1 * weight, detailContrast * (weight + detail) + 1.0 - (detail + detailContrast));
	return pow(result, 4.0);
}

vec2 rotate(vec2 v, float cosa, float sina) {
	return vec2(cosa * v.x - sina * v.y, sina * v.x + cosa * v.y);
}

vec4 get_material(vec2 uv, vec4 index, vec2 uv_center, float weight, inout float scale){
	
	float weightMod = index.g;
	weightMod = weightMod * weightMod + 0.1;
	float rand = random(uv_center);
	uv = rotate(uv, cos(rand), sin(rand));
	
	float material = floor(index.r * 255.0 + 0.5);
	vec4 col = texture(texture_array_albedo, vec3(uv, material));
	weight = blend_weights(sqrt(weight * weightMod), col.a);
	scale += weight;
	return col * weight;
}

void fragment() {
	
	vec3 normal = vec3(0.5, 0.5, 1.0);
	vec3 color = vec3(0.0);
	
	if (terrain_use_grid){
		color = texture(terrain_grid, UV*terrain_grid_scale).rgb;
	} else {
	
		vec2 texSize = vec2(textureSize(terrain_controlmap, 0));
		vec2 pos_texel = UV2 * texSize;
		vec2 pos_texel00 = floor(pos_texel);
		
		vec4 mirror = vec4(0.0, 0.0, 1.0, 1.0);
		mirror.xy = fract(pos_texel00 * 0.5) * 2.0;
		mirror.zw = vec2(1.0) - mirror.xy;
		
		vec2 weights1 = clamp(pos_texel - pos_texel00, 0, 1);
		weights1 = clamp(mix(weights1, vec2(1.0) - weights1, mirror.xy), 0, 1);
		vec2 weights0 = vec2(1.0) - weights1;
		
		vec2 index00UV = (pos_texel00 + mirror.xy) / texSize;
		vec2 index01UV = (pos_texel00 + mirror.xw) / texSize;
		vec2 index10UV = (pos_texel00 + mirror.zy) / texSize;
		vec2 index11UV = (pos_texel00 + mirror.zw) / texSize;
		
		vec4 index00 = texture(terrain_controlmap, index00UV);
		vec4 index01 = texture(terrain_controlmap, index01UV);
		vec4 index10 = texture(terrain_controlmap, index10UV);
		vec4 index11 = texture(terrain_controlmap, index11UV);
		
		float scale = 0.0;
		
		vec4 ab0, ab1, ab2, ab3;
		color = get_material(UV, index00, index00UV, weights0.x * weights0.y, scale).rgb;
		color += get_material(UV, index01, index01UV, weights0.x * weights1.y, scale).rgb;
		color += get_material(UV, index10, index10UV, weights1.x * weights0.y, scale).rgb;
		color += get_material(UV, index11, index11UV, weights1.x * weights1.y, scale).rgb;
		
		color *= 1.0/scale;

	}
	
	ALBEDO = color;
	NORMAL = mat3(VIEW_MATRIX) * get_normal(UV2);
	NORMAL_MAP = normal;
	NORMAL_MAP_DEPTH = 1.0;
}