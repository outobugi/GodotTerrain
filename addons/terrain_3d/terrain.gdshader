shader_type spatial;
render_mode depth_draw_opaque, diffuse_burley;

uniform float terrain_height = 128.0;
uniform float terrain_size = 1024.0;

uniform sampler2D terrain_heightmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D terrain_normalmap : filter_linear_mipmap, repeat_disable;
uniform sampler2D terrain_globalmap : filter_linear_mipmap, repeat_disable; // unsused

uniform sampler2D terrain_splatmap_01 : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D terrain_splatmap_02 : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D terrain_splatmap_03 : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D terrain_splatmap_04 : filter_linear_mipmap_anisotropic, repeat_disable;

uniform sampler2DArray texture_albedos : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2DArray texture_normals : filter_linear_mipmap_anisotropic, hint_normal;

uniform bool use_grid = true;
uniform sampler2D terrain_grid : source_color, filter_linear_mipmap_anisotropic;

vec3 unpack_normal(vec4 rgba) {
	
	vec3 n = normalize(rgba.xzy * 2.0 - 1.0);
	n.z *= -1.0;
	return n;
}

vec4 pack_normal(vec3 n, float a) {
	n.z *= -1.0;
	return vec4((n.xzy + vec3(1.0)) * 0.5, a);
}

void vertex(){
	
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	UV2 = (world_vertex.xz / vec2(terrain_size+1.0)) + vec2(0.5);
	
	UV = world_vertex.xz * 0.5;
	
	float height = (texture(terrain_heightmap, UV2).r);
	VERTEX.y = (height * terrain_height) * (VERTEX.y + 1.0);

	NORMAL = unpack_normal(texture(terrain_normalmap, UV2));
	TANGENT = cross(NORMAL, vec3(0,0,1));
	BINORMAL = cross(NORMAL, TANGENT);
	
}

vec2 hash(vec2 s){
	return fract(sin(mod(vec2(dot(s, vec2(127.1,311.7)), dot(s, vec2(269.5,183.3))), 3.14159))*43758.5453);
}

vec3 blend_normals(vec3 base, vec3 detail){
	// https://blog.selfshadow.com/publications/blending-in-detail/
	vec3 n1 = base*2.0 - vec3(1.0);
	vec3 n2 = detail*2.0 - vec3(1.0);
	float a = 1.0/(1.0 + n1.z);
	float b = -n1.x*n1.y*a;
	vec3 b1 = vec3(1.0 - n1.x*n1.x*a, b, -n1.x);
	vec3 b2 = vec3(b, 1.0 - n1.y*n1.y*a, -n1.y);
	vec3 b3 = n1;
	if (n1.z < -0.9999999){
		b1 = vec3( 0, -1, 0);
		b2 = vec3(-1,  0, 0);
	}
	vec3 r = n2.x*b1 + n2.y*b2 + n2.z*b3;
	return r*0.5 + 0.5;
}

vec4 depth_blend(vec4 color_a, vec4 color_b, float t, float blend) {
	// https://www.gamasutra.com/blogs/AndreyMishkinis/20130716/196339/Advanced_Terrain_Texture_Splatting.php
	float ma = max(color_a.a + (1.0 - t), color_b.a + t) - blend;
	float ba = max(color_a.a + (1.0 - t) - ma, 0.0);
	float bb = max(color_b.a + t - ma, 0.0);
	return (color_a * ba + color_b * bb) / (ba + bb);
}

vec4 get_depth_blended_weights(vec4 splat, vec4 bumps) {
	float dh = 0.2;

	vec4 h = bumps + splat;

	// TODO Keep improving multilayer blending, there are still some edge cases...
	// Mitigation: nullify layers with near-zero splat
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

vec4 stochastic_sample(sampler2DArray albedo, sampler2DArray normal, vec2 uv, float index, out vec4 out_normal){
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
	float blend = 0.2;
	
	vec4 col1 = textureGrad(albedo,uv1,ddx,ddy);
	vec4 col2 = textureGrad(albedo,uv2,ddx,ddy);
	vec4 col3 = textureGrad(albedo,uv3,ddx,ddy);
	
	vec3 weights = get_stochastic_blend_weights(bw_vx[3].xyz, col1.a, col2.a, col3.a, 0.2);
	
	vec4 col = (col1*weights.x) + (col2*weights.y) + (col3*weights.z);
	
	out_normal = (textureGrad(normal,uv1 ,ddx,ddy)*weights.x) +
	(textureGrad(normal,uv2,ddx,ddy)*weights.y) +
	(textureGrad(normal,uv3,ddx,ddy)*weights.z);
	
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
		ew3.r, ew3.g, ew3.b, ew3.a
	};

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
	
//	out_high_weights /= 
//		out_high_weights.r + out_high_weights.g + out_high_weights.b + out_high_weights.a;
}


void fragment() {

	vec4 indices;
	vec4 weights;
	get_splat_weights(UV2, indices, weights);
	
	vec4 ab0, ab1, ab2, ab3;
	vec4 nr0, nr1, nr2, nr3;
	
	ab0 = stochastic_sample(texture_albedos, texture_normals, UV, indices.x, nr0);
	ab1 = stochastic_sample(texture_albedos, texture_normals, UV, indices.y, nr1);
	ab2 = stochastic_sample(texture_albedos, texture_normals, UV, indices.z, nr2);
	ab3 = stochastic_sample(texture_albedos, texture_normals, UV, indices.w, nr3);
	
//	ab0 = texture(texture_albedos, vec3(UV, indices.x));
//	ab1 = texture(texture_albedos, vec3(UV, indices.y));
//	ab2 = texture(texture_albedos, vec3(UV, indices.z));
//	ab3 = texture(texture_albedos, vec3(UV, indices.w));
//
//	nr0 = texture(texture_normals, vec3(UV, indices.x));
//	nr1 = texture(texture_normals, vec3(UV, indices.y));
//	nr2 = texture(texture_normals, vec3(UV, indices.z));
//	nr3 = texture(texture_normals, vec3(UV, indices.w));
	
	vec4 w = get_depth_blended_weights(weights, vec4(ab0.a, ab1.a, ab2.a, ab3.a));
	float w_sum = (w.r + w.g + w.b + w.a);
	
	vec3 normal = vec3(0.5,0.5,1.0);
	vec3 color = vec3(1.0);
	
	if (use_grid){
		color = texture(terrain_grid, UV*2.0).rgb;
	} else {
		color = (
			w.r * ab0.rgb +
			w.g * ab1.rgb +
			w.b * ab2.rgb +
			w.a * ab3.rgb) / w_sum;
		normal = (
			w.r * nr0.rgb +
			w.g * nr1.rgb +
			w.b * nr2.rgb +
			w.a * nr3.rgb) / w_sum;
	}

	ALBEDO = color;
	vec3 blended_normals = blend_normals(texture(terrain_normalmap, UV2).rgb, normal);
	NORMAL = mat3(VIEW_MATRIX) * normalize(unpack_normal(vec4(blended_normals, 1.0)));;
}
