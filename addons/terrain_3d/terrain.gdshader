shader_type spatial;
render_mode depth_draw_opaque, diffuse_burley;

uniform float terrain_height = 128.0;
uniform float terrain_size = 1024.0;

uniform bool parallax_enabled = true;
uniform float parallax_depth = 1.0;

uniform sampler2D terrain_heightmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D terrain_normalmap : filter_linear_mipmap, repeat_disable;
//uniform sampler2D terrain_globalmap : filter_linear_mipmap, repeat_disable; // unsused for now

uniform sampler2D terrain_splatmap_01 : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D terrain_splatmap_02 : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D terrain_splatmap_03 : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D terrain_splatmap_04 : filter_linear_mipmap_anisotropic, repeat_disable;

uniform sampler2DArray texture_array_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2DArray texture_array_normal : filter_linear_mipmap_anisotropic, hint_normal;
uniform sampler2DArray texture_array_orm : filter_linear_mipmap_anisotropic;

uniform int texture_array_normal_max;
uniform int texture_array_orm_max;

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
	
	camera_distance_fade = smoothstep(100, 150, distance(INV_VIEW_MATRIX[3].xyz, world_vertex));
}

vec4 depth_blend(vec4 a_value, float a_bump, vec4 b_value, float b_bump, float t) {
	// https://www.gamasutra.com
	// /blogs/AndreyMishkinis/20130716/196339/Advanced_Terrain_Texture_Splatting.php
	float ma = max(a_bump + (1.0 - t), b_bump + t) - 0.1;
	float ba = max(a_bump + (1.0 - t) - ma, 0.0);
	float bb = max(b_bump + t - ma, 0.0);
	return (a_value * ba + b_value * bb) / (ba + bb);
}

vec4 get_depth_blended_weights(vec4 splat, vec4 bumps) {
	float dh = 0.2;
	vec4 h = bumps + splat;
	h *= smoothstep(0, 0.1, splat);
	vec4 d = h + dh;
	d.r -= max(h.g, max(h.b, h.a));
	d.g -= max(h.r, max(h.b, h.a));
	d.b -= max(h.g, max(h.r, h.a));
	d.a -= max(h.g, max(h.b, h.r));
	return clamp(d, 0, 1);
}

vec2 parallax_mapping(vec2 uv, vec3 view, float height){  
	return uv - view.xy * (1.0 - height) * parallax_depth * 0.02;  
}

vec2 rotate(vec2 v, float cosa, float sina) {
	return vec2(cosa * v.x - sina * v.y, sina * v.x + cosa * v.y);
}

vec4 tex(vec2 uv, float index, out vec4 out_normal, out vec4 out_orm){
	float frequency = 2.0;
	float sharpness = 0.7;
	
	vec2 uv2 = rotate(uv, cos(PI*0.2), sin(PI*0.6));
	
	float t = 1.1 + 0.5
		* sin(uv2.x * frequency + sin(uv.x) * 2.0) 
		* cos(uv2.y * frequency + sin(uv.y) * 2.0);
	t = smoothstep(sharpness, 2.0 - sharpness, t);
	
	vec4 col0 = texture(texture_array_albedo, vec3(uv, index));
	vec4 col1 = texture(texture_array_albedo, vec3(uv2, index));
	
	out_normal = vec4(0.5);
	out_orm = vec4(1,1,0,1);
	if (camera_distance_fade < 0.9){
		if (texture_array_normal_max >= int(index)){
			vec4 a = texture(texture_array_normal, vec3(uv, index));
			vec4 b = texture(texture_array_normal, vec3(uv2, index));
			out_normal = mix(depth_blend(a, col0.a, b, col1.a, t), out_normal, camera_distance_fade);
		}
		
		if (texture_array_orm_max >= int(index)){
			vec4 a = texture(texture_array_orm, vec3(uv, index));
			vec4 b = texture(texture_array_orm, vec3(uv2, index));
			out_orm = mix(depth_blend(a, col0.a, b, col1.a, t), out_orm, camera_distance_fade);
		}
	}

	return depth_blend(col0, col0.a, col1, col1.a, t);
}

void get_splat_weights(vec2 uv, out vec4 out_high_indices, out vec4 out_high_weights) {
	vec4 ew0 = (texture(terrain_splatmap_01, uv));
	vec4 ew1 = (texture(terrain_splatmap_02, uv));
	vec4 ew2 = (texture(terrain_splatmap_03, uv));
	vec4 ew3 = (texture(terrain_splatmap_04, uv));
	float weights[16] = {
		ew0.r, ew0.g, ew0.b, ew0.a,
		ew1.r, ew1.g, ew1.b, ew1.a,
		ew2.r, ew2.g, ew2.b, ew2.a,
		ew3.r, ew3.g, ew3.b, ew3.a };
		
	int high_indices_array[4] = {0, 0, 0, 0};
	float high_weights_array[4] = {0.0, 0.0, 0.0, 0.0};
	int count = 0;
	float pivot =1.0/8.0;
	
	for (int i = 0; i < 16; ++i) {
		if (weights[i] > pivot) {
			high_weights_array[count] = weights[i];
			high_indices_array[count] = i;
			weights[i] = 0.0;
			++count;
		}
	}
	
	while (count < 4 && pivot > 0.0) {
		float max_weight = 0.0;
		int max_index = 0;
		
		for (int i = 0; i < 16; ++i) {
			if (weights[i] > max_weight) {
				max_weight = weights[i];
				max_index = i;
				weights[i] = 0.0;
			}
		}
		high_indices_array[count] = max_index;
		high_weights_array[count] = max_weight;
		++count;
		pivot = max_weight;
	}
	out_high_weights = vec4(
		high_weights_array[0], high_weights_array[1], 
		high_weights_array[2], high_weights_array[3]);
	out_high_indices = vec4(
		float(high_indices_array[0]), float(high_indices_array[1]),
		float(high_indices_array[2]), float(high_indices_array[3]));
}

void fragment() {

	vec3 normal = vec3(0.5);
	vec3 color = vec3(1.0);
	vec3 orm = vec3(1,1,0);
	
	if (terrain_use_grid){
		color = texture(terrain_grid, UV*terrain_grid_scale).rgb;
	} else {
		vec4 indices;
		vec4 weights;
		get_splat_weights(UV2, indices, weights);
		
		vec4 ab0, ab1, ab2, ab3;
		vec4 nr0, nr1, nr2, nr3;
		vec4 orm0, orm1, orm2, orm3;
		
//		vec3 view_dir = normalize(normalize(-VERTEX)*mat3(TANGENT,-BINORMAL,NORMAL));
		int int_indices[4] = {int(indices.x), int(indices.y), int(indices.z), int(indices.w)};
		
		ab0 = tex(UV*texture_uv_scale_array[int_indices[0]].xy, indices.x, nr0, orm0) * texture_color_array[int_indices[0]];
		ab1 = tex(UV*texture_uv_scale_array[int_indices[1]].xy, indices.y, nr1, orm1) * texture_color_array[int_indices[1]];
		ab2 = tex(UV*texture_uv_scale_array[int_indices[2]].xy, indices.z, nr2, orm2) * texture_color_array[int_indices[2]];
		ab3 = tex(UV*texture_uv_scale_array[int_indices[3]].xy, indices.w, nr3, orm3) * texture_color_array[int_indices[3]];
	
		vec4 w = get_depth_blended_weights(weights, vec4(ab0.a, ab1.a, ab2.a, ab3.a));
		float w_sum = (w.r + w.g + w.b + w.a);
	
		color = (w.r * ab0.rgb + w.g * ab1.rgb + w.b * ab2.rgb + w.a * ab3.rgb) / w_sum;
		normal = (w.r * nr0.raa + w.g * nr1.raa + w.b * nr2.raa + w.a * nr3.raa) / w_sum; // RAAAAAAAAAAAAAA
		orm = (w.r * orm0.rgb + w.g * orm1.rgb + w.b * orm2.rgb + w.a * orm3.rgb) / w_sum;
	}
	
	ALBEDO = color;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	NORMAL = mat3(VIEW_MATRIX) * get_normal(UV2);
	NORMAL_MAP = normal;
	NORMAL_MAP_DEPTH = 1.0;
}