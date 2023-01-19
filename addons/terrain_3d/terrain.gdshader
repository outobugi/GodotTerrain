shader_type spatial;
render_mode depth_draw_opaque, diffuse_burley;

uniform float terrain_height = 64.0;
uniform float terrain_size = 1024.0;

uniform bool parallax_enabled = true;
uniform float parallax_depth = 1.0;

uniform sampler2D terrain_heightmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D terrain_normalmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D terrain_controlmap : filter_linear_mipmap_anisotropic, repeat_disable;

uniform sampler2DArray texture_array_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray texture_array_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform int texture_array_normal_max;

uniform vec3 texture_uv_scale_array[256];
uniform vec3 texture_3d_projection_array[256];
uniform vec4 texture_color_array[256];

uniform bool terrain_use_grid = true;
uniform float terrain_grid_scale = 1.0;

varying float camera_distance_fade;

vec3 unpack_normal(vec4 rgba) {
	vec3 n = rgba.xzy * 2.0 - vec3(1.0);
	n.z *= -1.0;
	return n;
}

vec4 pack_normal(vec3 n, float a) {
	n.z *= -1.0;
	return vec4((n.xzy + vec3(1.0)) * 0.5, a);
}

float get_height(vec2 uv){
	return texture(terrain_heightmap, uv).r * terrain_height;
}

vec3 get_normal(vec2 uv){
	vec3 n = unpack_normal(texture(terrain_normalmap, uv));
	return normalize(n);
}

void vertex(){
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	UV2 = (world_vertex.xz / vec2(terrain_size+1.0)) + vec2(0.5);
	UV = world_vertex.xz * 0.5;
	VERTEX.y = get_height(UV2) * (VERTEX.y + 1.0);
	NORMAL = get_normal(UV2);
	TANGENT = cross(NORMAL, vec3(0,0,1));
	BINORMAL = cross(NORMAL, TANGENT);
	camera_distance_fade = smoothstep(92, 128, distance(INV_VIEW_MATRIX[3].xyz, world_vertex));
}

vec4 depth_blend(vec4 a_value, float a_bump, vec4 b_value, float b_bump, float t) {
	float ma = max(a_bump + (1.0 - t), b_bump + t) - 0.1;
	float ba = max(a_bump + (1.0 - t) - ma, 0.0);
	float bb = max(b_bump + t - ma, 0.0);
	return (a_value * ba + b_value * bb) / (ba + bb);
}

//vec2 parallax_mapping(vec2 uv, vec3 view, float height){  
//	return uv - view.xy * (1.0 - height) * parallax_depth * 0.02;  
//}

float random(vec2 input){
	vec4 a = fract(input.xyxy * (2.0f * vec4(1.3442f, 1.0377f, 0.98848f, 0.75775f)) + input.yxyx);
	return fract(dot(a*a, vec4(251.0)));
}

float blend_weights(float weight, float detail){
	weight = sqrt(weight*0.3);
	float detailContrast = 3.0f;
	float result = max(0.1 * weight, detailContrast * (weight + detail) + 1.0f - (detail + detailContrast));
	return pow(result, 2.0);
}

vec2 rotate(vec2 v, float cosa, float sina) {
	return vec2(cosa * v.x - sina * v.y, sina * v.x + cosa * v.y);
}

/////// 3D PROJECTION UV ///////


//		vec3 wp = (inverse(VIEW_MATRIX) * vec4(VERTEX, 1)).xyz;
//		vec3 wn = (inverse(VIEW_MATRIX) * vec4(NORMAL, 0)).xyz;
		

//	vec2 proj = 0.5 * (world_nor.xz / world_nor.y);
//	proj = clamp(floor(proj * 7.0 + 7.25), 0, 15);
//	float projDX = (proj.x - 7.0) / 7.0;
//	float projDY = (proj.y - 7.0) / 7.0;
//	vec3 projF = normalize(vec3(projDX, 0.5, projDY));
//	vec3 projU = normalize(cross(projF, vec3(rot.x, 0.0, rot.y)));
//	vec3 projV = cross(projU, projF);
//	matUV = vec2(dot(projU, world_pos), dot(projV, world_pos));
//	float projWeight = clamp(dot(projF, world_nor), 0, 1);
//	weight *= (projWeight * projWeight + 0.0001);

vec4 get_material(vec2 uv, vec4 index, ivec2 uv_center, float weight, inout float scale, inout vec4 out_normal){
	
	float rand = random(vec2(uv_center));
	float rand_angle = rand * PI;
	uv += (rand - 0.5) * 2.0;

	float material = index.r * 255.0;
	float materialOverlay = index.g * 255.0;
	float materialBlend = index.b;
	vec2 rot = normalize(vec2(sin(rand_angle), cos(rand_angle)));
	vec2 matUV = rotate(uv, rot.x, rot.y) * texture_uv_scale_array[int(material)].xy;
	vec2 ddx = dFdx(matUV);
	vec2 ddy = dFdy(matUV);
	
	vec4 col1 = textureGrad(texture_array_albedo, vec3(matUV, material), ddx, ddy);
	vec4 col2 = textureGrad(texture_array_albedo, vec3(matUV, materialOverlay), ddx, ddy);
	
	vec4 albedo = depth_blend(col1, col1.a, col2, col2.a, materialBlend);
	
	vec4 nor1 = textureGrad(texture_array_normal, vec3(matUV, material), ddx, ddy);
	vec4 nor2 = textureGrad(texture_array_normal, vec3(matUV, materialOverlay), ddx, ddy);
	
	float nw = 1.0 - float(texture_array_normal_max >= int(material));
	vec4 normal = depth_blend(nor1, col1.a, nor2, col2.a, materialBlend);
	
	vec3 n = unpack_normal(normal);
	n.xz = rotate(n.xz, rot.x, -rot.y);
	normal = pack_normal(n, normal.a);
	
	weight = blend_weights(weight, albedo.a);

	out_normal += mix(normal, vec4(0.5, 0.5, 1.0, 1.0), nw) * weight;
	scale += weight;
	
	return albedo * weight;
}

void fragment() {
	
	vec3 normal = vec3(0.5, 0.5, 1.0);
	vec3 color = vec3(0.0);
	float rough = 1.0;
	
	NORMAL = mat3(VIEW_MATRIX) * get_normal(UV2);
	
	if (terrain_use_grid){
		vec2 p = UV*2.0*terrain_grid_scale;
		vec2 ddx = dFdx(p);
		vec2 ddy = dFdy(p);
		vec2 w = max(abs(ddx), abs(ddy)) + 0.01;  
		vec2 i = 2.0*(abs(fract((p-0.5*w)/2.0)-0.5)-abs(fract((p+0.5*w)/2.0)-0.5))/w;
		color = vec3((0.5 - 0.5*i.x*i.y)*0.2 + 0.2); 

	} else {
		
		vec2 texSize = vec2(textureSize(terrain_controlmap, 0));
		vec2 pos_texel = UV2 * texSize + 0.5;
		vec2 pos_texel00 = floor(pos_texel);
		
		vec4 mirror = vec4(0.0, 0.0, 1.0, 1.0);
		mirror.xy = fract(pos_texel00 * 0.5) * 2.0;
		mirror.zw = vec2(1.0) - mirror.xy;
	
		vec2 weights1 = clamp(pos_texel - pos_texel00, 0, 1);
		weights1 = mix(weights1, vec2(1.0) - weights1, mirror.xy);
		
		vec2 weights0 = vec2(1.0) - weights1;
		
		ivec2 index00UV = ivec2(pos_texel00 + mirror.xy);
		ivec2 index01UV = ivec2(pos_texel00 + mirror.xw);
		ivec2 index10UV = ivec2(pos_texel00 + mirror.zy);
		ivec2 index11UV = ivec2(pos_texel00 + mirror.zw);
		
		vec4 index00 = texelFetch(terrain_controlmap, index00UV, 0);
		vec4 index01 = texelFetch(terrain_controlmap, index01UV, 0);
		vec4 index10 = texelFetch(terrain_controlmap, index10UV, 0);
		vec4 index11 = texelFetch(terrain_controlmap, index11UV, 0);
		
		float scale = 0.0;
		vec4 in_normal = vec4(0.0);
		
		color = get_material(UV, index00, index00UV, weights0.x * weights0.y, scale, in_normal).rgb;
		color += get_material(UV, index01, index01UV, weights0.x * weights1.y, scale, in_normal).rgb;
		color += get_material(UV, index10, index10UV, weights1.x * weights0.y, scale, in_normal).rgb;
		color += get_material(UV, index11, index11UV, weights1.x * weights1.y, scale, in_normal).rgb;
		
		scale = 1.0/scale;
		rough = in_normal.a * scale;
		normal = in_normal.rgb * scale;
		color *= scale;

	}
	
	ALBEDO = color;
	ROUGHNESS = rough;
	NORMAL_MAP = normal;
	NORMAL_MAP_DEPTH = 1.0;
}