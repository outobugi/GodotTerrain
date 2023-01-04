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
}

vec2 hash(vec2 s){
	return fract(sin(mod(vec2(dot(s, vec2(127.1,311.7)), dot(s, vec2(269.5,183.3))), 3.14159))*43758.5453);
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

vec3 get_stochastic_blend_weights(vec3 weights, float a, float b, float c, float contrast){
	// https://forum.unity.com/threads/procedural-stochastic-texturing-prototype.628522/
	// compute weight with height map
	float epsilon = 1.0 / 1024.0;
	vec3 out_weights = vec3(weights.x * (a + epsilon),weights.y * (b + epsilon),weights.z * (c + epsilon));
	// Contrast weights
	float maxWeight = max(out_weights.x, max(out_weights.y, out_weights.z));
	float transition = contrast * maxWeight;
	float threshold = maxWeight - transition;
	float scale = 1.0 / transition;
	out_weights = clamp((out_weights - threshold) * scale, vec3(0), vec3(1));
	// Normalize weights.
	float weightScale = 1.0 / (out_weights.x + out_weights.y + out_weights.z);
	out_weights *= weightScale;
	return out_weights;
}

vec2 parallax_mapping(vec2 uv, vec3 view, float height){  
	return uv - view.xy * (1.0 - height) * parallax_depth * 0.02;  
}

vec4 stochastic_sample(vec2 uv, float index, vec3 view, out vec4 out_normal, out vec4 out_orm){
	vec2 skewV = mat2(vec2(1.0,1.0),vec2(-0.57735027 , 1.15470054))*uv * 3.464;
	vec2 vxID = floor(skewV);
	vec2 fracV = fract(skewV);
	vec3 barry = vec3(fracV.x,fracV.y,1.0-fracV.x-fracV.y);
	mat4 bw_vx = barry.z>0.0?
		mat4(vec4(vxID,0.0,0.0),vec4((vxID+vec2(0.0,1.0)),0.0,0.0),vec4(vxID+vec2(1.0,0.0),0,0),vec4(barry.zyx,0)):
		mat4(vec4(vxID+vec2(1.0,1.0),0.0,0.0),vec4((vxID+vec2(1.0,0.0)),0.0,0.0),vec4(vxID+vec2(0.0,1.0),0,0),vec4(-barry.z,1.0-barry.y,1.0-barry.x,0));
		
	vec2 ddx = dFdx(uv);
	vec2 ddy = dFdy(uv);
	vec3 uv1 = vec3(uv+hash(bw_vx[0].xy), index);
	vec3 uv2 = vec3(uv+hash(bw_vx[1].xy), index);
	vec3 uv3 = vec3(uv+hash(bw_vx[2].xy), index);
	
//	float h1 = textureGrad(albedo,uv1,ddx,ddy).a;
//	float h2 = textureGrad(albedo,uv2,ddx,ddy).a;
//	float h3 = textureGrad(albedo,uv3,ddx,ddy).a;
//
//	if (parallax_enabled){
//		uv1.xy = parallax_mapping(uv1.xy, view, h1);
//		uv2.xy = parallax_mapping(uv2.xy, view, h2);
//		uv3.xy = parallax_mapping(uv3.xy, view, h3);
//	}
	
	vec4 col1 = textureGrad(texture_array_albedo,uv1,ddx,ddy);
	vec4 col2 = textureGrad(texture_array_albedo,uv2,ddx,ddy);
	vec4 col3 = textureGrad(texture_array_albedo,uv3,ddx,ddy);
	
	vec3 weights = get_stochastic_blend_weights(bw_vx[3].xyz, col1.a, col2.a, col3.a, 0.1);
	
	vec4 col = (col1*weights.x) + (col2*weights.y) + (col3*weights.z);
	
	out_normal = vec4(0.5);
	
	if (texture_array_normal_max >= int(index)){
		out_normal = (textureGrad(texture_array_normal,uv1 ,ddx,ddy)*weights.x) +
		(textureGrad(texture_array_normal,uv2,ddx,ddy)*weights.y) +
		(textureGrad(texture_array_normal,uv3,ddx,ddy)*weights.z);
	} 
	if (texture_array_orm_max >= int(index)){
		out_orm = (textureGrad(texture_array_orm,uv1 ,ddx,ddy)*weights.x) +
		(textureGrad(texture_array_orm,uv2,ddx,ddy)*weights.y) +
		(textureGrad(texture_array_orm,uv3,ddx,ddy)*weights.z);
	}
	return col;
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
		
		vec3 view_dir = normalize(normalize(-VERTEX)*mat3(TANGENT,-BINORMAL,NORMAL));
		int int_indices[4] = {int(indices.x), int(indices.y), int(indices.z), int(indices.w)};
		
		ab0 = stochastic_sample(UV*texture_uv_scale_array[int_indices[0]].xy, indices.x, view_dir, nr0, orm0);
		ab0.rgb *= texture_color_array[0].rgb;
		ab1 = stochastic_sample(UV*texture_uv_scale_array[int_indices[1]].xy, indices.y, view_dir, nr1, orm1);
		ab1.rgb *= texture_color_array[1].rgb;
		ab2 = stochastic_sample(UV*texture_uv_scale_array[int_indices[2]].xy, indices.z, view_dir, nr2, orm2);
		ab2.rgb *= texture_color_array[2].rgb;
		ab3 = stochastic_sample(UV*texture_uv_scale_array[int_indices[3]].xy, indices.w, view_dir, nr3, orm3);
		ab3.rgb *= texture_color_array[3].rgb;
		
		vec4 w = get_depth_blended_weights(weights, vec4(ab0.a, ab1.a, ab2.a, ab3.a));
		float w_sum = (w.r + w.g + w.b + w.a);
	
		color = (w.r * ab0.rgb + w.g * ab1.rgb + w.b * ab2.rgb + w.a * ab3.rgb) / w_sum;
		normal = (w.r * nr0.raa + w.g * nr1.raa + w.b * nr2.raa + w.a * nr3.raa) / w_sum; // RAAAAAAAAAAAAAA
		
	}
	
	ALBEDO = color;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	NORMAL = mat3(VIEW_MATRIX) * get_normal(UV2);
	NORMAL_MAP = normal;
}