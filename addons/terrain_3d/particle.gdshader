shader_type particles;

uniform int seed;

uniform int instance_count = 16;
uniform int instance_density = 1;

uniform float terrain_height = 0.0;
uniform float terrain_size = 0.0;

uniform sampler2D terrain_heightmap : repeat_disable;
uniform sampler2D terrain_normalmap : repeat_disable;
uniform sampler2D terrain_controlmap : repeat_disable;
uniform float material_index = 0.0;

uniform sampler2D mask_texture : filter_linear_mipmap, repeat_disable;

const float PHI = 1.61803398874989484820459;

float random(vec2 xy){
	return fract(tan(distance(xy*PHI, xy)*float(seed+1))*xy.x);
}

vec3 unpack_normal(vec4 rgba) {
	vec3 n = normalize(rgba.xzy * 2.0 - 1.0);
	n.z *= -1.0;
	return n;
}

void process() {
	
	float count_sqrt = sqrt(float(instance_count));
	float spacing = float(instance_density) / 2.0;
	
	vec3 pos = vec3(0.0, 0.0, 0.0);
	pos.z = float(INDEX / uint(count_sqrt));
	pos.x = float(INDEX % uint(count_sqrt));

	pos.x -= count_sqrt * 0.5;
	pos.z -= count_sqrt * 0.5;
	pos *= spacing;
	
	pos.x += EMISSION_TRANSFORM[3][0] - mod(EMISSION_TRANSFORM[3][0], spacing);
	pos.z += EMISSION_TRANSFORM[3][2] - mod(EMISSION_TRANSFORM[3][2], spacing);
	
	float rand_offset = random(pos.xz);
	
	TRANSFORM[3].x = pos.x + rand_offset;
	TRANSFORM[3].z = pos.z + rand_offset;

	vec2 uv = (vec2(TRANSFORM[3].x, TRANSFORM[3].z) / vec2(terrain_size+1.0)) + vec2(0.5);
	vec3 normal = normalize(unpack_normal(texture(terrain_normalmap, uv)));
	float angle = rand_offset * PI;
	
	vec3 temp_xbasis=vec3(cos(angle), 0.0, sin(angle));
	
	TRANSFORM[1][0]=normal.x;
	TRANSFORM[1][1]=normal.y;
	TRANSFORM[1][2]=normal.z;
	vec3 zbasis=normalize(cross(temp_xbasis,normal));
	TRANSFORM[2][0]=zbasis.x;
	TRANSFORM[2][1]=zbasis.y;
	TRANSFORM[2][2]=zbasis.z;
	vec3 xbasis=normalize(-cross(zbasis,normal));
	TRANSFORM[0][0]=xbasis.x;
	TRANSFORM[0][1]=xbasis.y;
	TRANSFORM[0][2]=xbasis.z;

	TRANSFORM[3].y = texture(terrain_heightmap, uv).r * terrain_height;
	
	float current_index = texture(terrain_controlmap, uv).r * 255.0;

	if (current_index == material_index){
		float scale = 1.0;
		TRANSFORM[0] *= scale;
		TRANSFORM[1] *= scale;
		TRANSFORM[2] *= scale;
	} else {
		// hacky. I dont like it :(
		TRANSFORM[3].y = -10000.0;
	}
	
}
